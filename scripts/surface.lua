local State = require("scripts.state")
local M = {NAME="dsm-space"}

function M.settings()
  return {
    default_enable_all_autoplace_controls=false,
    property_expression_names={cliffiness="0", ["tile:empty-space:probability"]="1"},
    autoplace_settings={
      tile={treat_missing_as_default=false, settings={
        ["empty-space"]={frequency=1,size=1,richness=1}
      }},
      entity={treat_missing_as_default=false, settings={}},
      decorative={treat_missing_as_default=false, settings={}}
    }
  }
end

function M.get()
  local surface = game.surfaces[M.NAME]
  if not surface then surface = game.create_surface(M.NAME, M.settings()) end
  if State.get().map_version ~= 4 then
    surface.map_gen_settings = M.settings()
    State.get().map_version = 4
  end
  surface.show_clouds = false -- also repairs existing dsm-space surfaces
  surface.always_day = true
  surface.freeze_daytime = true
  surface.daytime = 0
  return surface
end

function M.background(surface, cat)
  local radius = 100
  for _, node in pairs(cat.nodes) do radius = math.max(radius, node.radius * 2 + 50) end
  radius = math.min(radius, 900)
  for i=1,cat.stars do
    local x = (2 * ((i * 7919 % 65521) / 65521) - 1) * radius
    local y = (2 * ((i * 10427 % 65519) / 65519) - 1) * radius
    rendering.draw_circle{
      color={r=0.48,g=0.64,b=0.9,a=0.55}, radius=(i % 13 == 0 and 0.09 or 0.045),
      filled=true, target={x=x,y=y}, surface=surface, draw_on_ground=true
    }
  end
end

function M.chart_near(player, surface, point, radius)
  player.force.chart(surface, {
    {point.x-radius, point.y-radius}, {point.x+radius, point.y+radius}
  })
end

-- Adapted from custom-starmap/control/surface.lua: generate the complete
-- finite central region FIRST, then chart it for every force. No radars,
-- power consumption, radar audio, or ongoing radar entities.
M.OLD_MAP_LIMIT = 500
M.COVERAGE_RADIUS_CHUNKS = math.ceil(M.OLD_MAP_LIMIT / 32) + 1

function M.chart_surface_as_radar(surface, generate)
  if not (surface and surface.valid) then return end
  if generate then
    local radius=M.COVERAGE_RADIUS_CHUNKS
    local missing=false
    for cx=-radius,radius do
      for cy=-radius,radius do
        if not surface.is_chunk_generated{x=cx,y=cy} then
          surface.request_to_generate_chunks({x=cx*32,y=cy*32},0)
          missing=true
        end
      end
    end
    if missing then surface.force_generate_chunk_requests() end
  end
  for _,force in pairs(game.forces) do
    if force.valid~=false then
      force.chart(surface,{{-M.OLD_MAP_LIMIT,-M.OLD_MAP_LIMIT},
        {M.OLD_MAP_LIMIT,M.OLD_MAP_LIMIT}})
    end
  end
end

-- The old project charts the whole finite map every 180 ticks. Camera
-- charting is an additional bounded fallback for modded systems beyond it.
function M.load_camera(player,surface,state,force)
  local res=player.display_resolution or {width=1280,height=720}
  local zoom=1
  local ok,z=pcall(function() return player.zoom end)
  if ok and type(z)=="number" and z>0 then zoom=z end
  local half_width=(res.width or 1280)/(64*zoom)
  local half_height=(res.height or 720)/(64*zoom)
  local radius=math.max(3,math.min(16,math.ceil(math.max(half_width,half_height)/32)+2))
  local point=player.position
  local cx,cy=math.floor(point.x/32),math.floor(point.y/32)
  local changed=force or state.cx~=cx or state.cy~=cy or state.radius~=radius
  if changed then
    -- On opening/focusing, generate only the central chunks immediately.
    -- The rest of the viewport is generated asynchronously around the camera.
    if force then
      surface.request_to_generate_chunks(point,math.min(radius,3))
      surface.force_generate_chunk_requests()
    end
    surface.request_to_generate_chunks(point,radius)
    -- A radar-like nearby pulse gives immediate vision at the new centre.
    M.chart_near(player,surface,point,math.min(radius,3)*32)
    state.cx,state.cy,state.radius=cx,cy,radius
    state.scan_row=-radius
  end
  -- Use chunk-aligned bounds: every row is <= (2*radius+1) chunks.
  local row=state.scan_row or -radius
  player.force.chart(surface,{
    {(cx-radius)*32,(cy+row)*32},
    {(cx+radius+1)*32,(cy+row+1)*32}
  })
  state.scan_row=row>=radius and -radius or row+1
  return not not changed
end

return M
