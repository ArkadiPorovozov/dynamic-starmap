local M = {}

function M.catalog()
  return prototypes.mod_data["dsm-catalog"].data
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
