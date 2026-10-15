-- The original custom-starmap's conditions/resources tooltip, adapted to
-- Factorio 2.1 runtime prototypes and the data-stage dsm-catalog snapshot.
local M={}
local function number(v)
  if v==math.floor(v) and math.abs(v)<1e15 then
    return string.format("%.0f",v)
  end
  return tostring(v) -- preserve modded precision, e.g. evolution 0.0503
end

function M.value_text(key,v,proto)
  if type(v)~="number" then return tostring(v) end
  if (proto and proto.is_time) or key=="day-night-cycle" then
    return {"dsm.minutes",number(math.floor(v/360+0.5)/10)}
  end
  local text=number(v)
  local unit=proto and proto.localised_unit_key
  if not M.meaningful(unit) then unit="surface-property-unit."..key end
  return {"?",{unit,text},text}
end

function M.meaningful(value)
  if type(value)=="string" then return value:match("%S")~=nil end
  if type(value)=="table" then
    if #value==0 then return false end
    if value[1]=="" then
      for i=2,#value do if M.meaningful(value[i]) then return true end end
      return false
    end
    return true
  end
  return value~=nil
end

function M.property_title(key,proto)
  local name=proto and proto.localised_name
  if M.meaningful(name) then return name end
  return {"?",{"surface-property-name."..key},key}
end

function M.content_sprite(name)
  for _,kind in ipairs({"item","fluid","entity"}) do
    local path=kind.."/"..name
    if helpers.is_valid_sprite_path(path) then return path end
  end
end

local function sprite_tag(name)
  local path=M.content_sprite(name)
  return path and ("["..path:gsub("/","=",1).."]") or nil
end

function M.property_lines(node)
  local keys,lines={},{}
  for key in pairs(node.properties or {}) do keys[#keys+1]=key end
  table.sort(keys,function(a,b)
    local pa,pb=prototypes.surface_property[a],prototypes.surface_property[b]
    local oa,ob=pa and pa.order or a,pb and pb.order or b
    return oa==ob and a<b or oa<ob
  end)
  for i=1,#keys do
    local key=keys[i]
    local p=prototypes.surface_property[key]
    lines[#lines+1]={"",M.property_title(key,p),": ",M.value_text(key,node.properties[key],p)}
  end
  return lines
end

-- Nested groups keep each LocalisedString under Factorio's 20-parameter limit.
local function assemble(lines)
  local groups={}
  for i=1,#lines,8 do
    local group={""}
    for j=i,math.min(i+7,#lines) do
      group[#group+1]=lines[j]
      group[#group+1]="\n"
    end
    groups[#groups+1]=group
  end
  while #groups>16 do
    local next_level={}
    for i=1,#groups,16 do
      local group={""}
      for j=i,math.min(i+15,#groups) do group[#group+1]=groups[j] end
      next_level[#next_level+1]=group
    end
    groups=next_level
  end
  local result={""}
  for _,group in ipairs(groups) do result[#result+1]=group end
  return result
end

function M.text(node,compact)
  if node.kind=="map-star" then return node.localised_name or node.name end
  local lines={}
  local proto=prototypes.space_location[node.name]
  if not compact then
    local description=proto and proto.localised_description or node.description
    if description then lines[#lines+1]=description;lines[#lines+1]="" end
  end
  for _,line in ipairs(M.property_lines(node)) do lines[#lines+1]=line end
  local icons={}
  for _,resource in ipairs(node.contents or {}) do
    local tag=sprite_tag(resource)
    if tag then icons[#icons+1]=tag end
  end
  if #icons>0 then
    lines[#lines+1]={"dsm.contents"}
    -- Keep each rich-text parameter below 200 bytes, like the old GUI.
    local row=""
    for _,icon in ipairs(icons) do
      if #row+#icon+1>170 then lines[#lines+1]=row;row="" end
      row=row..icon.." "
    end
    if row~="" then lines[#lines+1]=row end
  end
  if not compact then
    local solar=node.solar_power_in_space
    lines[#lines+1]={"dsm.solar",solar or 100}
  end
  return assemble(lines)
end

return M
