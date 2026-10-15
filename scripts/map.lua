local State = require("scripts.state")
local Surface = require("scripts.surface")
local Planets = require("scripts.planets")
local Platforms = require("scripts.platforms")
local Cards = require("scripts.cards")
local Custom = require("scripts.custom")
local M = {}

-- Rebuild only our entities and renders; keeps the same surface and chunks.
function M.rebuild()
  local cat, st = State.catalog(), State.get()
  assert(not st.pending_rebuild_surface, "starmap surface is being cleared")
  local surface = Surface.get()
  Platforms.clear(st)
  rendering.clear("dynamic-starmap")
  for _, ent in pairs(st.entities) do if ent.valid then ent.destroy() end end
  st.entities, st.sprites, st.rings, st.labels, st.orbits, st.cards = {}, {}, {}, {}, {}, {}
  st.camera_views={}
  -- Old saves can contain cached route geometry; nothing renders it anymore.
  st.clock = st.clock or game.tick
  local order, parents = Planets.order(cat.nodes)
  st.order, st.parents = order, parents
  local pos = Planets.positions(cat, st.clock, order, parents, st.orbit_overrides)
  -- Match the original project's full generation BEFORE placing the sun,
  -- bodies or platforms. Otherwise create_entity can silently return nil in
  -- still-ungenerated chunks, leaving the star and ships missing.
  Surface.chart_surface_as_radar(surface,true)
  for _,point in pairs(pos) do surface.request_to_generate_chunks(point,1) end
  surface.force_generate_chunk_requests()
  Surface.background(surface, cat)
  Planets.create(surface, cat, st, order, parents, pos)
  Platforms.update(surface,cat,st)
  Cards.restore()
  Custom.redraw(surface)
  for _, force in pairs(game.forces) do
    if force.valid ~= false then M.chart_force(force) end
  end
  local count,ships=0,0
  for _,ent in pairs(st.entities) do if ent.valid then count=count+1 end end
  for _,mark in pairs(st.platform_marks or {}) do
    if mark.entity and mark.entity.valid then ships=ships+1 end
  end
  if not (st.entities.star and st.entities.star.valid) then
    st.last_rebuild_error="sun entity could not be created"
  else
    st.last_rebuild_error=nil
  end
  log("[dynamic-starmap] rebuilt: bodies="..count.."/"..#order..
    ", sun="..tostring(st.entities.star and st.entities.star.valid or false)..
    ", platforms="..ships..", speed="..tostring(st.time_scale or cat.time_scale))
  return surface
end

-- Restore a map that was deleted outside this mod. Unlike regenerate(),
-- this never calls surface.clear() and never deletes another surface.
-- It also repairs an existing map whose own markers/renders are missing.
function M.restore()
  if State.get().pending_rebuild_surface then return false,"pending" end
  local missing = game.surfaces[Surface.NAME] == nil
  if missing then
    local st=State.get()
    st.entities,st.sprites,st.platform_marks={},{},{}
    st.map_version=nil
  end
  local ok,surface=pcall(M.rebuild)
  if not ok then
    log("[dynamic-starmap] restore failed: "..tostring(surface))
    return false,tostring(surface)
  end
  return true,surface
end

-- Do not clear a surface occupied by players, including external remote viewers.
function M.can_regenerate(ignore_our_viewers)
  if State.get().pending_rebuild_surface then return false,"pending" end
  local surface = game.surfaces[Surface.NAME]
  if not surface then return true end
  local viewers = State.get().viewers
  for _, player in pairs(game.players) do
    if player.valid then
      if player.physical_surface and player.physical_surface.index == surface.index then
        return false, "occupied"
      end
      if player.surface and player.surface.index == surface.index and
         not (ignore_our_viewers and viewers[player.index]) then
        return false, "occupied"
      end
    end
  end
  return true
end

-- Full reset: remove all chunks/entities and chart data, not just draw objects.
-- Called after our remote viewers have been returned to their previous controller.
function M.regenerate(caller_index)
  local ok, reason = M.can_regenerate(false)
  if not ok then return false, reason end
  local st = State.get()
  local surface = game.surfaces[Surface.NAME]
  Platforms.clear(st)
  st.camera_views={}
  rendering.clear("dynamic-starmap")
  st.entities,st.sprites,st.rings,st.labels,st.orbits,st.positions={}, {}, {}, {}, {}, {}
  st.platform_marks={}
  st.order,st.parents=nil,nil
  st.clock,st.paused,st.time_scale,st.map_version=0,false,nil,nil
  st.last_rebuild_error=nil
  if not surface then return true, M.rebuild() end
  -- LuaSurface.clear() finishes at the END of the tick. Rebuilding now puts
  -- new entities into chunks that the engine then deletes. Wait for the real
  -- on_surface_cleared event before generating chunks or creating anything.
  st.pending_rebuild_surface=surface.index
  st.regeneration_caller=caller_index
  surface.clear() -- only on the dedicated map, after returning all viewers
  for _,force in pairs(game.forces) do
    if force.valid~=false then force.clear_chart(surface) end
  end
  return true,"pending"
end

function M.surface_cleared(event)
  local st=State.get()
  if st.pending_rebuild_surface~=event.surface_index then return end
  st.pending_rebuild_surface=nil
  local caller=st.regeneration_caller
  st.regeneration_caller=nil
  local ok,result=pcall(M.rebuild)
  if not ok then
    st.last_rebuild_error=tostring(result)
    log("[dynamic-starmap] rebuild after clear failed: "..st.last_rebuild_error)
  elseif not (st.entities.star and st.entities.star.valid) then
    ok=false
    st.last_rebuild_error="sun entity could not be created"
    log("[dynamic-starmap] rebuild after clear failed: "..st.last_rebuild_error)
  end
  if caller then
    local player=game.get_player(caller)
    if player and player.valid then
      player.print(ok and {"dsm.regenerate-done"} or
        {"dsm.restore-failed",st.last_rebuild_error})
    end
  end
end

function M.chart_force(force)
  local surface=game.surfaces[Surface.NAME]
  if not (force and surface) then return end
  force.chart(surface,{{-Surface.OLD_MAP_LIMIT,-Surface.OLD_MAP_LIMIT},
    {Surface.OLD_MAP_LIMIT,Surface.OLD_MAP_LIMIT}})
  for _,ent in pairs(State.get().entities) do
    if ent.valid then
      local x,y=ent.position.x,ent.position.y
      force.chart(surface,{{x-32,y-32},{x+32,y+32}})
    end
  end
end

function M.chunk_generated(event)
  if event.surface.name ~= Surface.NAME then return end
  for _,force in pairs(game.forces) do
    if force.valid ~= false then force.chart(event.surface, event.area) end
  end
end

function M.tick(event)
  local st, cat = State.get(), State.catalog()
  if st.pending_rebuild_surface then return end
  st.clock = st.clock or event.tick
  if not st.paused then st.clock = st.clock + (st.time_scale or cat.time_scale) end
  if not next(st.entities) then return end
  local surface = game.surfaces[Surface.NAME]
  if not surface then return end
  local active = false
  st.camera_views=st.camera_views or {}
  for _,player in pairs(game.players) do
    if player.valid and player.surface and player.surface.name==Surface.NAME then
      active=true
      local camera=st.camera_views[player.index] or {}
      st.camera_views[player.index]=camera
      Surface.load_camera(player,surface,camera,false)
    elseif player.index then
      st.camera_views[player.index]=nil
    end
  end
  -- As in custom-starmap: refresh the full central chart every 180 ticks.
  -- Only generate missing chunks; do not flush the map on every tick.
  if event.tick%180==0 then Surface.chart_surface_as_radar(surface,true) end
  local interval = active and (cat.update_ticks_active or 1) or cat.update_ticks
  if event.tick % math.max(1,interval) ~= 0 then return end
  local pos = Planets.positions(cat, st.clock, st.order, st.parents, st.orbit_overrides)
  for _, point in pairs(pos) do
    local cx, cy = math.floor(point.x/32), math.floor(point.y/32)
    if not surface.is_chunk_generated{x=cx,y=cy} then
      -- Stream the next planet chunk instead of synchronously flushing
      -- every outstanding camera request at the same time.
      surface.request_to_generate_chunks(point, 1)
    end
  end
  if not st.paused then Planets.update(cat, st, pos, active) end
  Platforms.update(surface,cat,st,active)
  if event.tick%4==0 then Cards.update(st) end
end

return M
