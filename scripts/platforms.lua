-- Space platforms from the old map: parked icons beside their destination,
-- moving icons on actual 2.1 space connections. Never change platform state.
local M = {}
local TAU = 2*math.pi
-- Factorio's Lua 5.2 uses atan2; Lua 5.3+ (including the model test)
-- accepts two arguments to atan instead.
local atan2 = math.atan2 or function(y,x) return math.atan(y,x) end
local FLIGHT_SPRITE = "dsm-platform-moving-sprite"
local PARKED_SPRITE = "dsm-platform-parked-sprite"
local ICON_SCALE = 0.27
-- A rotated 54px icon at 0.27 scale fits inside a ~0.33-tile radius.
-- Both radial and same-ring separation exceed the full icon diameter.
local PARKED_CLEARANCE = 1.25
local PARKED_SPACING = 1.05
local PARKED_RING_STEP = 1.15

-- Offset the game artwork +90 degrees clockwise relative to the direction
-- vector. In flight that vector follows the connection; parked it aims inward.
local function flight_orientation(dx,dy,sign)
  return (atan2(dy*sign,dx*sign)/TAU + 0.25) % 1
end

local function render(id) return id and rendering.get_object_by_id(id) end

function M.clear(st)
  for _,mark in pairs(st.platform_marks or {}) do
    if mark.entity and mark.entity.valid then mark.entity.destroy() end
    for _,id in pairs({mark.sprite,mark.label}) do
      local r=render(id); if r then r.destroy() end
    end
  end
  st.platform_marks={}
end

function M.find(st,entity)
  if not (entity and entity.valid and
    (entity.name=="dsm-platform-parked-marker" or
     entity.name=="dsm-platform-moving-marker")) then return nil end
  for _,mark in pairs(st.platform_marks or {}) do
    if mark.entity == entity then
      local force=game.forces[mark.force]
      local platform=force and force.platforms[mark.index]
      if platform and platform.valid then return platform,mark end
    end
  end
end

local function point_for(platform,cat,st,parked_slot)
  local loc=platform.space_location
  if loc and st.entities[loc.name] and st.entities[loc.name].valid then
    local node=cat.nodes[loc.name]
    -- Fixed occupancy per planet: fill a complete circle before starting
    -- the next. Slots are assigned globally across forces in stable order.
    local slot=parked_slot or {ring=0,used=0}
    local ring=slot.ring
    if not slot.capacity then
      slot.radius=node.size/2 + PARKED_CLEARANCE + ring*PARKED_RING_STEP
      local step=2*math.asin(math.min(1,PARKED_SPACING/(2*slot.radius)))
      slot.capacity=math.max(1,math.floor(TAU/step))
    end
    local radius,capacity=slot.radius,slot.capacity
    local base=(node.parked_orientation or 0)*TAU-math.pi/2
    local angle=base+(slot.used+(ring%2)*0.5)*TAU/capacity
    slot.used=slot.used+1
    if slot.used>=capacity then
      slot.ring,slot.used,slot.radius,slot.capacity=ring+1,0,nil,nil
    end
    local center=(st.positions and st.positions[loc.name]) or st.entities[loc.name].position
    local x,y=center.x+radius*math.cos(angle),center.y+radius*math.sin(angle)
    -- The same artwork orientation offset as the moving platform, now with
    -- the direction vector pointing from this slot TOWARDS the planet.
    local inward=flight_orientation(center.x-x,center.y-y,1)
    return {x=x,y=y},false,nil,nil,nil,nil,nil,inward
  end
  local conn=platform.space_connection
  if not conn then return nil end
  local from,to=conn.from and conn.from.name,conn.to and conn.to.name
  if not (from and to and st.entities[from] and st.entities[to]) then return nil end
  -- 2.1 LuaSpacePlatform.distance is a fraction [0,1] of the real
  -- space-connection. Marker motion needs no rendered path or fake links.
  local frac=math.max(0,math.min(1,platform.distance or 0))
  local a,b=(st.positions and st.positions[from]) or st.entities[from].position,
            (st.positions and st.positions[to]) or st.entities[to].position
  local dx,dy=b.x-a.x,b.y-a.y
  local length=math.sqrt(dx*dx+dy*dy)
  if length<1e-9 then return {x=a.x,y=a.y},true,frac,dx,dy,from,to end
  -- The platform's fraction describes progress along the *connection*,
  -- not a flight all the way through each planet. Start/end at the body's
  -- sprite radius plus the moving icon's clickable half-extent. Keep the
  -- entire moving icon outside the disk, including on return journeys.
  local hitbox=cat.platform_marker_clearance or 0.4 -- old catalogs on migration
  local start=(cat.nodes[from].size or 0)/2+hitbox
  local finish=(cat.nodes[to].size or 0)/2+hitbox
  -- A very short/overlapping connection cannot fit both full clearances;
  -- collapse onto the centre of the available gap instead of reversing it.
  if start+finish>length then
    local ratio=length/(start+finish)
    start,finish=start*ratio,finish*ratio
  end
  local along=start+(length-start-finish)*frac
  local p={x=a.x+dx*along/length,y=a.y+dy*along/length}
  return p,true,frac,dx,dy,from,to
end

function M.update(surface,cat,st,active)
  if cat.show_platforms==false then return end
  st.platform_marks=st.platform_marks or {}
  local seen,parked={},{}
  local forces={}
  for _,force in pairs(game.forces) do forces[#forces+1]=force end
  table.sort(forces,function(a,b) return a.index<b.index end)
  for _,force in ipairs(forces) do
    local ordered={}
    for _,platform in pairs(force.platforms or {}) do
      if platform.valid then ordered[#ordered+1]=platform end
    end
    table.sort(ordered,function(a,b) return a.index<b.index end)
    for _,platform in ipairs(ordered) do
      if platform.valid then
        local loc=platform.space_location and platform.space_location.name
        local slot
        if loc then
          parked[loc]=parked[loc] or {ring=0,used=0}
          slot=parked[loc]
        end
        local point,moving,frac,dx,dy,from,to,park_angle=
          point_for(platform,cat,st,slot)
        local key=force.index..":"..platform.index
        if point and not surface.is_chunk_generated{
          x=math.floor(point.x/32),y=math.floor(point.y/32)} then
          surface.request_to_generate_chunks(point,1)
          -- The old project generated the finite map before drawing ships.
          -- For an extra modded location outside it, finish just this one
          -- missing local chunk so its first platform is not silently lost.
          if not st.platform_marks[key] then surface.force_generate_chunk_requests() end
          if not surface.is_chunk_generated{
            x=math.floor(point.x/32),y=math.floor(point.y/32)} then
            if st.platform_marks[key] then seen[key]=true end
            point=nil
          end
        end
        if point then
          seen[key]=true
          local mark=st.platform_marks[key]
          local prototype=moving and "dsm-platform-moving-marker" or
            "dsm-platform-parked-marker"
          if mark and (not mark.entity or not mark.entity.valid or
              mark.entity.name~=prototype or mark.moving~=moving) then
            if mark.entity and mark.entity.valid then mark.entity.destroy() end
            for _,id in pairs({mark.sprite,mark.label}) do local o=render(id);if o then o.destroy() end end
            mark=nil
          end
          if not mark then
            local ent=surface.create_entity{name=prototype,position=point,force=force}
            if not ent then
              st.platform_failures=st.platform_failures or {}
              local last=st.platform_failures[key]
              if not last or game.tick-last>600 then
                log("[dynamic-starmap] cannot create platform "..key.." at "..
                  string.format("%.2f,%.2f",point.x,point.y))
                st.platform_failures[key]=game.tick
              end
            else
              if st.platform_failures then st.platform_failures[key]=nil end
            end
            if ent then
              ent.destructible=false
              mark={entity=ent,force=force.name,index=platform.index,moving=moving}
              st.platform_marks[key]=mark
              mark.label=rendering.draw_text{
                text=platform.name,target={x=point.x,y=point.y-0.43},
                surface=surface,color={r=0.7,g=0.85,b=1,a=0.95},
                scale=0.42,alignment="center",forces={force}
              }.id
              mark.label_position={x=point.x,y=point.y-0.43}
              mark.label_name=platform.name
            end
          else
            local old=mark.entity.position
            if (old.x-point.x)^2+(old.y-point.y)^2 >
               (active and 0.000009 or 0.0004) then
              mark.entity.teleport(point) -- world selection stays near sprite
            end
            local label=render(mark.label)
            if label then
              local next_pos={x=point.x,y=point.y-0.43}
              local prev=mark.label_position
              if not prev or (prev.x-next_pos.x)^2+(prev.y-next_pos.y)^2>
                 (active and 1e-12 or 0.0001) then
                label.target=next_pos
                mark.label_position=next_pos
              end
              if mark.label_name~=platform.name then
                label.text=platform.name
                mark.label_name=platform.name
              end
            end
          end
          if mark then
            local angle=park_angle
            if moving then
              -- LuaSpacePlatform.distance runs [0,1] in the connection's
              -- canonical from->to direction. On return it decreases.
              if mark.from~=from or mark.to~=to or mark.last_frac==nil then
                mark.direction=(frac<=0.5) and 1 or -1
              elseif frac>mark.last_frac+1e-8 then mark.direction=1
              elseif frac<mark.last_frac-1e-8 then mark.direction=-1 end
              mark.from,mark.to,mark.last_frac=from,to,frac
              angle=flight_orientation(dx,dy,mark.direction)
            end
            local sprite=render(mark.sprite)
            if not sprite then
              sprite=rendering.draw_sprite{
                sprite=moving and FLIGHT_SPRITE or PARKED_SPRITE,
                surface=surface,target=point,x_scale=ICON_SCALE,y_scale=ICON_SCALE,
                orientation=angle,forces={force}
              }
              mark.sprite=sprite.id
              mark.sprite_position={x=point.x,y=point.y}
              mark.sprite_orientation=angle
            else
              local old=mark.sprite_position
              if not old or (old.x-point.x)^2+(old.y-point.y)^2>
                 (active and 1e-12 or 0.0001) then
                sprite.target=point
                mark.sprite_position={x=point.x,y=point.y}
              end
              if not mark.sprite_orientation or
                 math.abs((mark.sprite_orientation-angle+0.5)%1-0.5)>
                   (active and 1e-9 or 1/4096) then
                sprite.orientation=angle
                mark.sprite_orientation=angle
              end
            end
          end
        end
      end
    end
  end
  for key,mark in pairs(st.platform_marks) do
    if not seen[key] then
      if mark.entity and mark.entity.valid then mark.entity.destroy() end
      for _,id in pairs({mark.sprite,mark.label}) do local o=render(id);if o then o.destroy() end end
      st.platform_marks[key]=nil
    end
  end
end

return M
