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
function Map:configure(value)
  local cfg = config()
  for k, v in pairs(value) do
    assert(k ~= "nodes" and k ~= "connections", "use extend/update for nodes; connections are unsupported")
    cfg[k] = table.deepcopy(v)
  end
end
return Map
