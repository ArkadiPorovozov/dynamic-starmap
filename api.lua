-- Data-stage API, intentionally shaped like PlanetsLib:extend/update.
-- Only edits THIS mod's config; it never edits a planet or PlanetsLib itself.
local Map = {}
local function config() return data.raw["mod-data"]["dsm-config"].data end
local function entries(value)
  assert(type(value) == "table", "expected a node or a list of nodes")
  return value.name and {value} or value
end
function Map:extend(value)
  local nodes = config().nodes
  for _, node in ipairs(entries(value)) do
    assert(type(node.name) == "string", "node.name is required")
    assert(not nodes[node.name], "node override already exists: " .. node.name)
    nodes[node.name] = table.deepcopy(node)
    nodes[node.name].name = nil
  end
end
function Map:update(value)
  local nodes = config().nodes
  for _, node in ipairs(entries(value)) do
    assert(type(node.name) == "string", "node.name is required")
    local old = nodes[node.name] or {}
    for k, v in pairs(node) do if k ~= "name" then old[k] = table.deepcopy(v) end end
    nodes[node.name] = old
  end
end
-- A map-only body: no planet/space-location/route is added to vanilla.
-- Its name must be unique among both data-stage locations and map-only nodes.
function Map:define(value)
  local custom=config().custom_nodes
  for _,node in ipairs(entries(value)) do
    local name=node.name
    assert(type(name)=="string" and name:match("^[%w_%-]+$") and
      name~="star" and name~="space-location-unknown",
      "define requires a unique ASCII map-only name")
    assert(not custom[name] and not (data.raw.planet or {})[name] and
      not (data.raw["space-location"] or {})[name], "map node already exists: "..name)
    assert(type(node.radius)=="number" and node.radius>0 and node.radius<1000000,
      "map-only node requires positive radius")
    assert(node.parent==nil or type(node.parent)=="string", "parent must be a node name")
    local copy=table.deepcopy(node)
    copy.name=nil
    custom[name]=copy
  end
end

function Map:remove_custom(name)
  assert(type(name)=="string" and config().custom_nodes[name],"unknown custom node")
  config().custom_nodes[name]=nil
  config().nodes[name]=nil
end

function Map:hide(name)
  assert(type(name)=="string" and name~="star", "cannot hide the sun")
  self:update{name=name,hidden=true}
end

function Map:show(name)
  assert(type(name)=="string", "node name required")
  self:update{name=name,hidden=false}
end

function Map:configure(value)
  local cfg = config()
  for k, v in pairs(value) do
    assert(k ~= "nodes" and k ~= "custom_nodes" and k ~= "connections",
      "use extend/update/define for nodes; connections are unsupported")
    cfg[k] = table.deepcopy(v)
  end
end
return Map
