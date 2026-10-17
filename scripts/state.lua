local M = {}

local function build()
  local base = prototypes.mod_data["dsm-catalog"].data
  local st = storage.dsm
  if not (st and st.node_overrides and next(st.node_overrides)) then return base end
  -- Apply runtime node overrides on top of the data-stage catalog, so any
  -- field can be changed at runtime; unspecified fields keep the vanilla value.
  local merged = {}
  for k, v in pairs(base) do merged[k] = v end
  local nodes = {}
  for name, node in pairs(base.nodes or {}) do
    local override = st.node_overrides[name]
    if override then
      local copy = M.copy(node)
      for key, value in pairs(override) do
        if value == nil then copy[key] = nil else copy[key] = M.copy(value) end
      end
      nodes[name] = copy
    else
      nodes[name] = node
    end
  end
  merged.nodes = nodes
  return merged
end

-- The merged catalog is read many times per tick (tick, GUI, hover, click).
-- Cache it and rebuild only when runtime overrides change. A module local is
-- used instead of storage so it never bloats saves and resets on every load
-- (data-stage prototypes may change between mod versions). Neither the catalog
-- nor its nodes are mutated by callers, so sharing the table is safe.
local cache

function M.invalidate() cache = nil end

function M.catalog()
  if not cache then cache = build() end
  return cache
end

function M.get()
  storage.dsm = storage.dsm or {entities={}, sprites={}, viewers={}, paused=false, clock=game.tick}
  return storage.dsm
end

function M.copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = M.copy(v) end
  return result
end

return M
