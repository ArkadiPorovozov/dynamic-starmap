local M = {}
local TAU = 2 * math.pi

-- Factorio sprite orientation is clockwise from up: 0=N, 0.25=E.
-- Tidal locking is calculated from the body's WORLD position so moons also
-- keep the same hemisphere toward the sun as they follow their parent.
function M.facing_sun(point, sun)
  sun = sun or {x=0,y=0}
  local dx,dy=sun.x-point.x,sun.y-point.y
  if dx*dx+dy*dy < 0.000001 then return 0 end
  local y,x=dx,-dy
  local a
  if math.atan2 then
    a=math.atan2(y,x)
  elseif x==0 then
    a=y>=0 and math.pi/2 or -math.pi/2
  else
    a=math.atan(y/x)
    if x<0 then a=a+(y>=0 and math.pi or -math.pi) end
  end
  return (a/TAU)%1
end

local function orientation(node,point,sun,clock,override)
  override=override or {}
  local tidal=override.tidal_lock
  if tidal==nil then tidal=node.tidal_lock end
  if tidal~=false then return M.facing_sun(point,sun) end
  local direction=override.spin_direction or node.spin_direction or 1
  return node.spin>0 and (direction*clock/node.spin)%1 or 0
end

function M.order(nodes)
  local result, parents, visiting, done, names = {}, {}, {}, {}, {}
  for name in pairs(nodes) do names[#names+1] = name end
  table.sort(names)
  local function visit(name)
    if done[name] then return end
    visiting[name] = true
    local parent = nodes[name].parent
    if not (parent and nodes[parent]) or visiting[parent] then
      parent = nil -- tolerate old catalogues with orbit cycles
    else
      visit(parent)
    end
    parents[name] = parent
    visiting[name], done[name] = nil, true
    result[#result+1] = name
  end
  for _, name in ipairs(names) do visit(name) end
  return result, parents
end

function M.positions(cat, clock, order, parents, overrides)
  if not order then order, parents = M.order(cat.nodes) end
  local result = {}
  for _, name in ipairs(order) do
    local node = cat.nodes[name]
    local override=overrides and overrides[name] or {}
    local parent = result[parents[name]] or {x=0,y=0}
    local phase=override.phase or node.phase
    local period=override.period or node.period
    local radius=override.radius or node.radius
    local direction=override.orbit_direction or node.orbit_direction or 1
    local a = (phase + (period > 0 and direction*clock/period or 0)) * TAU
    result[name] = {x=parent.x + radius * math.sin(a), y=parent.y - radius * math.cos(a)}
  end
  return result
end

function M.create(surface, cat, st, order, parents, pos)
  st.positions=pos
  st.visual_positions,st.visual_orientations,st.orbit_centers={},{},{}
  for _, name in ipairs(order) do
    local node = cat.nodes[name]
    local ent = surface.create_entity{name=node.entity, position=pos[name], force="neutral"}
    if not ent then
      -- The engine returns nil (rather than raising) for an entity outside
      -- generated chunks. Do not silently drop the star or a whole orbit.
      surface.request_to_generate_chunks(pos[name],1)
      surface.force_generate_chunk_requests()
      ent=surface.create_entity{name=node.entity,position=pos[name],force="neutral"}
    end
    if not ent then
      log("[dynamic-starmap] cannot create body: "..name.." ("..node.entity..")")
    end
    if ent then
      ent.destructible = false
      st.entities[name] = ent
      st.visual_positions[name]={x=pos[name].x,y=pos[name].y}
      if node.sprite then
        local angle=orientation(node,pos[name],pos.star,st.clock,
          st.orbit_overrides and st.orbit_overrides[name])
        st.sprites[name] = rendering.draw_sprite{
          sprite=node.sprite, target=pos[name], surface=surface,
          orientation=angle
        }.id
        st.visual_orientations[name]=angle
      end
      if name ~= "star" then
        local proto=prototypes.space_location[name]
        st.labels[name] = rendering.draw_text{
          text=proto and proto.localised_name or name, surface=surface,
          target={x=pos[name].x,y=pos[name].y+node.size/2+0.16},
          color={r=0.96,g=0.96,b=0.96,a=0.95}, alignment="center", scale=0.6
        }.id
      end
      if parents[name] and node.radius > 0 and node.draw_orbit ~= false then
        local parent = st.entities[parents[name]]
        if parent then
          st.orbits[name] = rendering.draw_circle{
            color=node.color,
            radius=(st.orbit_overrides and st.orbit_overrides[name] and
              st.orbit_overrides[name].radius) or node.radius,
            width=parents[name]=="star" and 4 or 2,
            filled=false, target=pos[parents[name]], surface=surface, draw_on_ground=true
          }.id
          st.orbit_centers[name]={x=pos[parents[name]].x,y=pos[parents[name]].y}
        end
      end
    end
  end

end

local function changed(a,b)
  return not a or (a.x-b.x)^2+(a.y-b.y)^2>0.0001
end

function M.update(cat, st, pos, active)
  st.positions=pos
  for name,point in pairs(pos) do
    local ent=st.entities[name]
    if ent and ent.valid then
      local old=ent.position
      -- Keep the real selection marker within <0.1px of its visual sprite
      -- while viewed, without teleporting it on every tiny orbit step.
      local marker_delta=(old.x-point.x)^2+(old.y-point.y)^2
      if marker_delta>(active and 0.000009 or 0.0004) and
         ent.surface.is_chunk_generated{x=math.floor(point.x/32),
                                        y=math.floor(point.y/32)} then
        ent.teleport(point) -- wait for the asynchronously generated chunk
      end
      local obj=st.sprites[name] and rendering.get_object_by_id(st.sprites[name])
      if obj then
        local angle=orientation(cat.nodes[name],point,pos.star,st.clock,
          st.orbit_overrides and st.orbit_overrides[name])
        local previous=st.visual_orientations[name]
        if not previous or math.abs((angle-previous+0.5)%1-0.5)>
           (active and 1e-9 or 1/4096) then
          obj.orientation=angle
          st.visual_orientations[name]=angle
        end
      end
      local previous=st.visual_positions[name]
      if (active and (not previous or
          (previous.x-point.x)^2+(previous.y-point.y)^2>1e-12)) or
          (not active and changed(previous,point)) then
        if obj then obj.target=point end
        local label=st.labels[name] and rendering.get_object_by_id(st.labels[name])
        if label then
          label.target={x=point.x,y=point.y+cat.nodes[name].size/2+0.16}
        end
        st.visual_positions[name]={x=point.x,y=point.y}
      end
      local parent=st.parents and st.parents[name]
      local centre=parent and pos[parent]
      local old_center=st.orbit_centers[name]
      if centre and ((active and (not old_center or
          (old_center.x-centre.x)^2+(old_center.y-centre.y)^2>1e-12)) or
          (not active and changed(old_center,centre))) then
        local orbit=st.orbits[name] and rendering.get_object_by_id(st.orbits[name])
        if orbit then
          orbit.target=centre
          st.orbit_centers[name]={x=centre.x,y=centre.y}
        end
      end
    end
  end
end

return M
