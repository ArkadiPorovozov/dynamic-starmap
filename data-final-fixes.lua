-- Runs after PlanetsLib (optional dependency). Read the FINAL prototypes only;
-- never call PlanetsLib:extend/update and never write to its orbit metadata.
local cfg = data.raw["mod-data"]["dsm-config"].data
local nodes, routes = {}, {}

-- The Space Age empty-space tile already has autoplace probability 1.
-- Select it in this surface's map-gen settings; do not modify vanilla or PlanetsLib.
local all = {}
for _, kind in ipairs({"space-location", "planet"}) do
  for name, proto in pairs(data.raw[kind] or {}) do
    all[name] = proto
  end
end

-- Map-only bodies declared through api.lua:define. They are catalogued and
-- drawn here, but never inserted into Space Age or PlanetsLib prototypes.
for name,spec in pairs(cfg.custom_nodes or {}) do
  assert(not all[name],"map-only node conflicts with planet/space-location: "..name)
  local p={type="dsm-custom",name=name,distance=spec.radius,
    orientation=spec.phase or 0,starmap_icon=spec.icon,
    starmap_icon_size=spec.icon_size or 128,
    localised_name=spec.localised_name or name,
    localised_description=spec.description,
    magnitude=spec.magnitude,solar_power_in_space=spec.solar_power_in_space,
    surface_properties=spec.properties}
  all[name]=p
  -- Later Map:update/extend calls override the initial custom definition.
  -- Radius stays exact, and the base Space Age prototypes are never changed.
  local overrides=cfg.nodes[name] or {}
  local definition=table.deepcopy(spec)
  for key,value in pairs(overrides) do definition[key]=table.deepcopy(value) end
  cfg.nodes[name]=definition
end

-- Space Age draws its central sun from utility-sprites; it does NOT have to
-- declare a "star" space-location. Add a map-only centre without touching
-- data.raw["space-location"] or the vanilla flight graph.
if not all.star then
  all.star={type="map-star",name="star",distance=0,orientation=0,
    localised_name={"dsm.sun"}}
end

local function xy(proto)
  local a = (proto.orientation or 0) * 2 * math.pi
  local origin = proto.origin or {x = 0, y = 0}
  return (origin.x or origin[1] or 0) + (proto.distance or 0) * math.sin(a),
         (origin.y or origin[2] or 0) - (proto.distance or 0) * math.cos(a)
end

local function parent_of(proto)
  -- The central star must not acquire a parent from another body at (0, 0).
  if proto.name == "star" then return nil end
  -- PlanetsLib's orbit tree wins. 2.1.20's native origin is a coordinate, not a parent ID.
  local orbit = proto.orbit
  local p = orbit and orbit.parent
  if p and p.name ~= proto.name and all[p.name] then return p.name end
  local origin = proto.origin
  if origin then
    local x, y = origin.x or origin[1] or 0, origin.y or origin[2] or 0
    local best
    for name, candidate in pairs(all) do
      if name ~= proto.name then
        local cx, cy = xy(candidate)
        if math.abs(cx-x) < 0.001 and math.abs(cy-y) < 0.001 then
          if not best or name == "star" then best = name end
        end
      end
    end
    if best then return best end
  end
  if proto.name ~= "star" and all.star then return "star" end
end

local function picture(proto, override, size)
  local icons = proto.starmap_icons
  if override.icon then icons = {{icon = override.icon, icon_size = override.icon_size or 128}} end
  if not icons then
    local filename = proto.starmap_icon or proto.icon
    if filename then
      icons = {{icon = filename, icon_size = proto.starmap_icon and (proto.starmap_icon_size or 64) or (proto.icon_size or 64)}}
    else
      icons = {{icon = "__dynamic-starmap__/graphics/body.png", icon_size = 128}}
    end
  end
  local layers = {}
  for _, icon in ipairs(icons) do
    if icon.icon then
      local px = icon.icon_size or proto.starmap_icon_size or 64
      layers[#layers+1] = {
        filename = icon.icon, width = px, height = px,
        scale = size * 32 / px * (#icons>1 and (icon.scale or 1) or 1),
        tint = icon.tint
      }
    end
  end
  if #layers == 0 then return {filename = "__dynamic-starmap__/graphics/body.png", width = 128, height = 128, scale = size / 4} end
  return #layers == 1 and layers[1] or {layers = layers}
end

-- From the old map's resource/flora/threat inventory, compiled once at
-- data-final-fixes. Runtime has no access to entity autoplace definitions.
-- Keep an inventory of every naturally generated entity type, not just the
-- vanilla resources/trees. An explicit map-gen entity may have no autoplace
-- on its own (mods supply the probability via property_expression_names).
local natural_types={
  resource=true,tree=true,fish=true,plant=true,cliff=true,
  ["simple-entity"]=true,["simple-entity-with-owner"]=true,
  ["simple-entity-with-force"]=true,unit=true,["unit-spawner"]=true,
  turret=true,["ammo-turret"]=true,["electric-turret"]=true,
  ["fluid-turret"]=true,["artillery-turret"]=true,
  ["spider-unit"]=true,["segmented-unit"]=true,segment=true,
  asteroid=true
}
local candidates,by_name={},{}
for kind in pairs(natural_types) do
  for name, entity in pairs(data.raw[kind] or {}) do
    local hidden=false
    for _,flag in ipairs(entity.flags or {}) do
      if flag=="hidden" then hidden=true;break end
    end
    if not hidden then
      local e={name=name,autoplace=entity.autoplace~=nil,
        control=entity.autoplace and entity.autoplace.control}
      by_name[name]=e
      if e.autoplace then candidates[#candidates+1]=e end
    end
  end
end
table.sort(candidates,function(a,b) return a.name<b.name end)

local function contents_of(proto)
  local found,result,keys={},{},{}
  local map=proto.map_gen_settings or {}
  local settings=map.autoplace_settings or {}
  local function add(name)
    if name and not found[name] then
      found[name]=true;result[#result+1]=name
    end
  end
  local function key(name)
    if type(name)~="string" then return end
    local normalized=name:gsub("_","-")
    keys[normalized]=true
    local prefix=proto.name:gsub("_","-").."-"
    if normalized:sub(1,#prefix)==prefix then
      keys[normalized:sub(#prefix+1)]=true
    end
  end
  for name in pairs(map.autoplace_controls or {}) do key(name) end
  for name in pairs((settings.entity and settings.entity.settings) or {}) do
    key(name)
    if by_name[name] then add(name) end -- exact explicit entity, even without autoplace
  end
  -- Map-gen expressions can explicitly spawn an entity without either an
  -- autoplace control or a conventional per-entity autoplace definition.
  for expr,value in pairs(map.property_expression_names or {}) do
    local name=type(expr)=="string" and expr:match("^entity:(.-):probability$")
    if name and by_name[name] and value~="0" then add(name) end
  end
  for _,e in ipairs(candidates) do
    if keys[e.name:gsub("_","-")] or
       (e.control and keys[e.control:gsub("_","-")]) then add(e.name) end
  end
  for tile in pairs((settings.tile and settings.tile.settings) or {}) do
    local t=data.raw.tile and data.raw.tile[tile]
    local fluid=t and t.fluid
    if fluid and data.raw.fluid and data.raw.fluid[fluid] then add(fluid) end
  end
  -- Territory enemies (e.g. vanilla demolishers) have no entity autoplace.
  local units=map.territory_settings and map.territory_settings.units or {}
  for _,unit in pairs(units) do
    local name=type(unit)=="table" and unit.unit or unit
    if type(name)=="string" and by_name[name] then add(name) end
  end
  table.sort(result) -- stable across data.raw hash iteration and mod load order
  return result
end

-- Empty custom tooltip fields and empty property names are common in
-- third-party prototypes. A truthy Lua string may still be visually blank.
local function meaningful(value)
  if type(value)=="string" then return value:match("%S")~=nil end
  if type(value)=="table" then
    if #value==0 then return false end
    if value[1]=="" then
      for i=2,#value do if meaningful(value[i]) then return true end end
      return false
    end
    return true -- a non-empty locale key cannot be resolved in data stage
  end
  return value~=nil
end

local function properties_of(proto)
  if proto.type=="map-star" then return {} end
  -- The game shows a planet's explicit values plus defaults of visible
  -- properties. Hidden technical properties may ALSO be explicitly assigned
  -- to Nauvis (PlanetsLib's planet-str is one), so filter BOTH sources.
  local definitions=data.raw["surface-property"] or {}
  local props={}
  local function visible(key)
    local p=definitions[key]
    return not p or (not p.hidden and not p.hidden_in_factoriopedia and
      (p.localised_name==nil or meaningful(p.localised_name)))
  end
  for key,value in pairs(proto.surface_properties or {}) do
    if visible(key) then props[key]=value end
  end
  for key,p in pairs(definitions) do
    if props[key]==nil and p.default_value~=nil and visible(key) then
      props[key]=p.default_value
    end
  end
  return props
end

local function property_title(key,proto)
  if proto and meaningful(proto.localised_name) then return proto.localised_name end
  -- Locale keys are provided by the game and the installed mods. An empty
  -- localised_name in data.raw does not mean its default locale is empty.
  return {"?",{"surface-property-name."..key},key}
end

local function numeric_text(value)
  if type(value)=="number" and value==math.floor(value) and math.abs(value)<1e15 then
    return string.format("%.0f",value)
  end
  return tostring(value)
end

local function property_display(key,value,proto)
  if type(value)~="number" then return tostring(value) end
  if key=="day-night-cycle" or (proto and proto.is_time) then
    local minutes=math.floor(value/360+0.5)/10
    return {"dsm.minutes",numeric_text(minutes)}
  end
  local text=numeric_text(value)
  local unit=proto and proto.localised_unit_key
  if not meaningful(unit) then unit="surface-property-unit."..key end
  return {"?",{unit,text},text}
end

-- The old custom-starmap also put the full data-stage card into the marker
-- prototype's own description. Keep that native entity tooltip as a fallback
-- if a remote controller/mod prevents our custom GUI hover from firing.
local function marker_description(node)
  -- Prototype property-tree LocalisedString parameters are stricter than
  -- runtime GUI captions: every leaf in our generated description is text.
  local function text_only(value)
    if type(value)=="table" then
      local copy={}
      for k,v in pairs(value) do copy[k]=text_only(v) end
      return copy
    end
    if value==nil then return "" end
    return type(value)=="string" and value or tostring(value)
  end
  if node.name=="star" then return node.description and text_only(node.description) end
  local lines={}
  if node.description then
    lines[#lines+1]=node.description
    lines[#lines+1]="" -- a single blank line before the conditions block
  end
  for _,field in ipairs(node.tooltip_fields or {}) do
    if field.show_in_tooltip~=false and meaningful(field.name) and meaningful(field.value) then
      local value=type(field.value)=="number" and numeric_text(field.value) or field.value
      lines[#lines+1]={"",field.name,": ",value}
    end
  end
  local keys={}
  for key in pairs(node.properties or {}) do keys[#keys+1]=key end
  table.sort(keys,function(a,b)
    local props=data.raw["surface-property"] or {}
    local pa,pb=props[a],props[b]
    local oa,ob=pa and pa.order or a,pb and pb.order or b
    return oa==ob and a<b or oa<ob
  end)
  for i=1,#keys do
    local key=keys[i]
    local prop=data.raw["surface-property"] and data.raw["surface-property"][key]
    local title=property_title(key,prop)
    local value=node.properties[key]
    lines[#lines+1]={"",title,": ",property_display(key,value,prop)}
  end
  if node.parent then
    lines[#lines+1]={"dsm.map-orbit",math.floor(node.radius*10+0.5)/10}
  end
  if #node.contents>0 then
    lines[#lines+1]={"dsm.contents"}
    local row=""
    for _,resource in ipairs(node.contents) do
      local tag
      if (data.raw.item or {})[resource] then tag="[item="..resource.."]"
      elseif (data.raw.fluid or {})[resource] then tag="[fluid="..resource.."]"
      else tag="[entity="..resource.."]" end
      if #row+#tag>160 then lines[#lines+1]=row;row="" end
      row=row..tag.." "
    end
    if row~="" then lines[#lines+1]=row end
  end
  if node.solar_power_in_space then
    lines[#lines+1]={"dsm.solar",node.solar_power_in_space}
  end
  local groups={}
  for i=1,#lines,8 do
    local group={""}
    for j=i,math.min(i+7,#lines) do
      group[#group+1]=lines[j]
      group[#group+1]="\n"
    end
    groups[#groups+1]=group
  end
  -- LocalisedString has a per-level parameter limit. Pack large modded
  -- inventories in additional levels instead of dropping late entries.
  while #groups>16 do
    local next_level={}
    for i=1,#groups,16 do
      local group={""}
      for j=i,math.min(i+15,#groups) do group[#group+1]=groups[j] end
      next_level[#next_level+1]=group
    end
    groups=next_level
  end
  local text={""}
  for _,group in ipairs(groups) do text[#text+1]=group end
  return text_only(text)
end

for name, proto in pairs(all) do
  local change = cfg.nodes[name] or {}
  if not change.hidden and (name=="star" or not proto.hidden or cfg.nodes[name] ~= nil)
     and name ~= "space-location-unknown" then
    local parent = change.parent or parent_of(proto)
    if not all[parent] or parent == name then parent = nil end
    local is_star = name == "star"
    local native_radius=proto.distance or 0
    if proto.orbit and proto.orbit.distance then
      native_radius=proto.orbit.distance
    end
    local radius=is_star and 0 or (change.radius or native_radius)
    local is_moon = parent and parent ~= "star"
    -- magnitude is the native apparent size; the hitbox matches the image.
    local size = change.size or (is_star and 14 or
      (type(proto.magnitude)=="number" and proto.magnitude>0 and
       math.max(0.2,2*proto.magnitude) or
       (is_moon and 1 or cfg.default_size or 2.2)))
    -- Scale the visible sprite AND marker hitbox/labels from one size value.
    -- Do not shrink the central sun. Overrides from Map:update{size=...}
    -- receive the same global multiplier, so it truly affects every body.
    local multiplier=cfg.body_size_multiplier or 1
    assert(type(multiplier)=="number" and multiplier>0,
      "dsm-config.body_size_multiplier must be positive")
    if not is_star then size=size*multiplier end
    -- An opt-in static textured entity removes the LuaRendering sprite at
    -- the cost of continuous rotation/tidal locking (Sprite4Way is discrete).
    local static_picture=not is_star and
      (change.static_picture==true or
       (change.static_picture~=false and cfg.static_planet_entities==true))
    local ename = "dsm-node-" .. name
    local sprite = "dsm-sprite-" .. name
    nodes[name] = {
      name = name, kind = proto.type, entity = ename, sprite = sprite,
      localised_name = proto.localised_name or (is_star and {"dsm.sun"} or name),
      magnitude = proto.magnitude,
      parent = parent, radius = radius * (cfg.scale or 1), raw_radius = radius,
      source_radius = native_radius * (cfg.scale or 1),
      phase = change.phase or (proto.orbit and proto.orbit.orientation) or proto.orientation or 0,
      period = change.period, spin = change.spin or 2400,
      -- +1: clockwise from north; -1: counterclockwise. Self-spin is
      -- independent and applies only when tidal_lock=false.
      orbit_direction = change.orbit_direction or 1,
      spin_direction = change.spin_direction or 1,
      tidal_lock = not static_picture and change.tidal_lock ~= false,
      size = size, static_picture = static_picture,
      -- This surface shows every orbit, regardless of draw_orbit on the
      -- VANILLA flat starmap. An explicit map override can hide one.
      draw_orbit = change.draw_orbit ~= false,
      parked_orientation = proto.parked_platforms_orientation,
      description = proto.localised_description or (not is_star and
        {"?",{"space-location-description."..name},{"planet-description."..name},""} or nil),
      properties = properties_of(proto),
      tooltip_fields = {},
      contents = table.deepcopy(change.contents or contents_of(proto)),
      contents_custom = change.contents ~= nil,
      solar_power_in_space = proto.solar_power_in_space,
      -- Global orbit color wins over legacy per-node colors; setting
      -- orbit_color=false via Map:configure restores the old per-node colors.
      color = cfg.orbit_color or change.color or (is_moon and
        {r=0.46,g=0.56,b=0.68,a=0.9} or {r=0.32,g=0.38,b=0.48,a=0.88})
    }
    -- Generic override: any field present in cfg.nodes[name] wins over the
    -- computed/vanilla value, so mods can change absolutely anything without
    -- editing this file. Fields not provided keep their vanilla/computed value.
    for key, value in pairs(change) do
      if value ~= nil then
        nodes[name][key] = table.deepcopy(value)
      end
    end
    if change.contents ~= nil then nodes[name].contents_custom = true end
    assert(nodes[name].orbit_direction==1 or nodes[name].orbit_direction==-1,
      "orbit_direction must be 1 (clockwise) or -1 (counterclockwise): "..name)
    assert(nodes[name].spin_direction==1 or nodes[name].spin_direction==-1,
      "spin_direction must be 1 or -1: "..name)
    for _,field in ipairs(proto.custom_tooltip_fields or {}) do
      if field.show_in_tooltip~=false and meaningful(field.name) and meaningful(field.value) then
        nodes[name].tooltip_fields[#nodes[name].tooltip_fields+1]=table.deepcopy(field)
      end
    end
    local image
    if is_star and not change.icon then
      -- Reuse the game's currently configured starmap_star artwork, so an
      -- optional UI overhaul can replace it without altering our prototypes.
      local utility=data.raw["utility-sprites"] and
        data.raw["utility-sprites"]["default"]
      local native=utility and utility.starmap_star
      local native_size=native and native.size or 512
      local width=type(native_size)=="table" and
        (native_size[1] or native_size.width) or native_size
      local height=type(native_size)=="table" and
        (native_size[2] or native_size.height) or native_size
      width,height=width or 512,height or 512
      image={filename=native and native.filename or
        "__core__/graphics/icons/starmap-star.png",
        width=width,height=height,scale=size*32/width}
    else
      image = picture(proto, change, size)
    end
    -- The sun is an ordinary entity picture, not a LuaRendering sprite.
    -- Other moving bodies keep their existing, separately animated sprites.
    local entity = {
      type = "simple-entity-with-owner", name = ename,
      flags = {"placeable-off-grid", "not-deconstructable", "not-blueprintable", "not-flammable"},
      icon = "__dynamic-starmap__/graphics/button.png", icon_size = 64,
      localised_name = proto.localised_name or (is_star and {"dsm.sun"} or name),
      localised_description = nodes[name].description,
      collision_mask = {layers = {}},
      -- Native world selection supplies hover/tooltips and the visible outline.
      selectable_in_game = true,
      collision_box = {{-size/3,-size/3},{size/3,size/3}},
      selection_box = {{-size/2,-size/2},{size/2,size/2}},
      picture = (is_star or static_picture) and image or
        {filename = "__dynamic-starmap__/graphics/transparent.png", width = 1, height = 1},
      max_health = 1000000
    }
    if is_star or static_picture then
      nodes[name].sprite = nil
      data:extend({entity})
    else
      image.type, image.name = "sprite", sprite
      data:extend({entity,image})
    end
  end
end

-- Some mods place multiple locations at the same native origin (often 0,0).
-- Inference can then produce A -> B -> A. Drop one inferred/invalid link,
-- deterministically, rather than crashing on save migration or map opening.
local names, active, done = {}, {}, {}
for name in pairs(nodes) do names[#names+1] = name end
table.sort(names)
local function check_parent(name)
  if done[name] then return end
  active[name] = true
  local parent = nodes[name].parent
  if parent then
    if not nodes[parent] or active[parent] then
      log("[dynamic-starmap] Ignoring cyclic/missing map parent: " .. name .. " -> " .. parent)
      nodes[name].parent = nil
    else
      check_parent(parent)
    end
  end
  active[name], done[name] = nil, true
end
for _, name in ipairs(names) do check_parent(name) end

-- Each sibling-to-sibling gap comes straight from the FINAL data-stage
-- distances. Add five tiles to that gap (including the first gap from the
-- parent), rather than multiplying all radii or using a nonlinear curve.
-- Both PlanetsLib orbit.distance and native distance are read above. Explicit
-- API radii remain exact; they do not rewrite the source distances used for
-- other bodies. Only actual image overlaps can increase an automatic radius.
local extra_gap=cfg.orbit_gap or 5
assert(type(extra_gap)=="number" and extra_gap>=0,
  "dsm-config.orbit_gap must be nonnegative")
local siblings = {}
for name,node in pairs(nodes) do
  if node.parent and nodes[node.parent] then
    siblings[node.parent] = siblings[node.parent] or {}
    siblings[node.parent][#siblings[node.parent]+1] = name
  end
end
for parent,list in pairs(siblings) do
  table.sort(list,function(a,b)
    if nodes[a].source_radius==nodes[b].source_radius then return a<b end
    return nodes[a].source_radius<nodes[b].source_radius
  end)
  local previous_native,desired,farthest=0,0,nil
  for _,name in ipairs(list) do
    local node=nodes[name]
    local moon=parent~="star"
    local native=node.source_radius
    desired=desired+math.max(0,native-previous_native)+extra_gap
    previous_native=native
    if not (cfg.nodes[name] and cfg.nodes[name].radius~=nil) then
      local clearance=cfg.orbit_clearance or 2
      local minimum=(nodes[parent].size+node.size)/2+clearance
      if farthest then
        minimum=math.max(minimum,farthest.radius+
          math.max(clearance,(farthest.size+node.size)*0.42+clearance*0.5))
      end
      -- Shrink the completed lunar orbit (including its +5 interval), not
      -- the planet intervals. Explicit API radii remain exact.
      node.radius=math.max(moon and desired*(cfg.moon_scale or 0.6) or desired,minimum)
    end
    if not farthest or node.radius>farthest.radius then farthest=node end
  end
end

local distance_multiplier = cfg.distance_multiplier or 1
assert(type(distance_multiplier)=="number" and distance_multiplier>0,
  "dsm-config.distance_multiplier must be a positive number")
for _, node in pairs(nodes) do
  node.radius = node.radius * distance_multiplier
  if node.period == nil then
    if node.radius <= 0 then
      node.period = 0
    else
      local moon = node.parent and node.parent ~= "star"
      local speed = moon and (cfg.moon_angular_speed or 0.00022) or
        ((cfg.planet_angular_speed or 0.00001) *
          (100/math.max(20,node.radius))^0.75)
      assert(speed > 0, "starmap angular speeds must be positive")
      node.period = math.floor(2*math.pi/speed + 0.5)
    end
  end
end

-- Radius in the tooltip must be the FINAL on-map radius, after the
-- data-derived gaps, lunar scaling and optional global multiplier.
for _,node in pairs(nodes) do
  local marker=data.raw["simple-entity-with-owner"][node.entity]
  if marker then marker.localised_description=marker_description(node) end
end

for name, edge in pairs(data.raw["space-connection"] or {}) do
  if nodes[edge.from] and nodes[edge.to] then
    routes[#routes+1] = {name=name, from=edge.from, to=edge.to, travel=true}
  end
end
-- Use the moving marker's final selection box as the flight icon clearance.
-- This keeps the visible sprite and clickable hitbox outside planet disks.
local marker=data.raw["simple-entity"]["dsm-platform-moving-marker"]
local box=marker.selection_box
local clearance=math.max(math.abs(box[1][1]),math.abs(box[1][2]),
  math.abs(box[2][1]),math.abs(box[2][2]))

-- This catalog is readable in control.lua via prototypes.mod_data, not data.raw.
data:extend({{type="mod-data", name="dsm-catalog", data={
  nodes=nodes, routes=routes, update_ticks=cfg.update_ticks or 12,
  update_ticks_active=cfg.update_ticks_active or 1, chart_radius=cfg.chart_radius or 96,
  time_scale=cfg.time_scale or 0, stars=cfg.stars or 0,
  distance_multiplier=distance_multiplier, show_platforms=cfg.show_platforms ~= false,
  platform_marker_clearance=clearance
}}})
