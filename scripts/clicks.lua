-- Click handling and Remote View redirection for dynamic-starmap.
-- Kept separate from gui.lua so the map GUI and camera code stay focused
-- on rendering; this module owns "where did the player click and where
-- should the camera go".
local State = require("scripts.state")
local Surface = require("scripts.surface")
local Platforms = require("scripts.platforms")
local Cards = require("scripts.cards")

local PB_PREFIX = "dsm-pbtn-"

local M = {}

local function same_entity(a, b)
  if a == b then return true end
  if not (a and b) then return false end
  local ok1, eq1 = pcall(function()
    return a.valid and b.valid and a.unit_number ~= nil and b.unit_number ~= nil and
      a.unit_number == b.unit_number
  end)
  if ok1 and eq1 then return true end
  local ok2, eq2 = pcall(function()
    return a.valid and b.valid and a.name == b.name and a.surface == b.surface and
      a.position.x == b.position.x and a.position.y == b.position.y
  end)
  return ok2 and eq2 or false
end

function M.same_entity(a, b) return same_entity(a, b) end

local function owned_target(st, player, entity)
  if not (entity and entity.valid) then return false end
  if entity.surface and player.surface and
     entity.surface.index ~= player.surface.index then return false end
  local name = entity.name:match("^dsm%-node%-(.+)$")
  if name then
    local stored = st.entities[name]
    return stored ~= nil and same_entity(stored, entity)
  end
  local platform = Platforms.find(st, entity)
  return platform and platform.force == player.force or false
end

function M.owned_target(st, player, entity) return owned_target(st, player, entity) end

local function capture_radius(ent)
  local name = ent.name:match("^dsm%-node%-(.+)$")
  local node = name and State.catalog().nodes[name]
  if node and node.size then return math.max(node.size / 2 + 1.5, 2) end
  return 2
end

function M.capture_radius(ent) return capture_radius(ent) end

local function planet_surface(name)
  local planet = game.planets and game.planets[name]
  local surf = planet and planet.surface
  if surf and surf.valid then return surf end
  surf = game.surfaces and game.surfaces[name]
  if surf and surf.valid then return surf end
  return nil
end

function M.planet_surface(name) return planet_surface(name) end

function M.open_remote_target(player, entity, opts)
  local st = State.get()
  if not (player and player.valid) or not entity or not entity.valid then return false end
  local surf, platform, target_label
  if entity.name == "dsm-platform-parked-marker" or
     entity.name == "dsm-platform-moving-marker" then
    platform = Platforms.find(st, entity)
    if not (platform and platform.force == player.force) then return false end
    surf = platform.surface
    target_label = platform.name
  else
    local name = entity.name:match("^dsm%-node%-(.+)$")
    if not name or name == "star" then return false end
    surf = planet_surface(name)
    target_label = name
  end
  if not (surf and surf.valid) then
    return false
  end
  local hub = platform and platform.hub
  local center = hub and hub.valid and hub.position or {x = 0, y = 0}
  local Gui = State.Gui
  Gui.close(player)
  local ok, err = pcall(function()
    player.force.chart(surf, {{center.x - 64, center.y - 64}, {center.x + 64, center.y + 64}})
    player.set_controller{type = defines.controllers.remote, surface = surf, position = center}
  end)
  if not ok then
    log("[dynamic-starmap] LMB teleport failed: " .. tostring(err))
    return false
  end
  return true
end

local function map_target(player, event)
  local st = State.get()
  if not (player and player.valid and
          player.surface and player.surface.name == Surface.NAME) then return nil end
  if event and (event.element and event.element.valid) then return nil end
  local point = (event and event.cursor_position) or player.position
  if not point then return nil end
  local cx, cy = point.x or point[1], point.y or point[2]
  if not (cx and cy) then return nil end
  local function hit(ent)
    if not (ent and ent.valid) then return nil end
    local name = ent.name:match("^dsm%-node%-(.+)$")
    local d = math.huge
    local p2 = name and st.positions and st.positions[name]
    for _, p in ipairs({ent.position, p2}) do
      if p then
        local dx, dy = p.x - cx, p.y - cy
        local dd = math.sqrt(dx * dx + dy * dy)
        if dd < d then d = dd end
      end
    end
    local capture = capture_radius(ent)
    if d <= capture then return d - capture end
    return nil
  end
  local selected = player.selected
  if selected and selected.valid and owned_target(st, player, selected) and hit(selected) then
    return selected
  end
  local best, best_score
  for _, mark in pairs(st.platform_marks or {}) do
    if mark.force == player.force.name and mark.entity and mark.entity.valid then
      local score = hit(mark.entity)
      if score and (not best_score or score < best_score) then
        best, best_score = mark.entity, score
      end
    end
  end
  if best then return best end
  for _, ent in pairs(st.entities) do
    if ent.valid and ent.name:match("^dsm%-node%-") then
      local score = hit(ent)
      if score and (not best_score or score < best_score) then
        best, best_score = ent, score
      end
    end
  end
  if not best then
    local nearest, ndist
    for _, ent in pairs(st.entities) do
      if ent.valid and ent.name:match("^dsm%-node%-") then
        local p2 = st.positions and st.positions[ent.name:match("^dsm%-node%-(.+)$")]
        local pos = p2 or ent.position
        local dx, dy = pos.x - cx, pos.y - cy
        local d = math.sqrt(dx * dx + dy * dy)
        if not ndist or d < ndist then nearest, ndist = ent, d end
      end
    end
    if nearest and ndist and ndist <= 8 then best = nearest end
  end
  return best
end

function M.map_target(player, event) return map_target(player, event) end

function M.open_selected_target(player, event)
  return M.open_remote_target(player, map_target(player, event))
end

function M.focus_selected_target(player, event)
  local ent = map_target(player, event)
  local view = player and State.get().viewers[player.index]
  local st = State.get()
  local tick = event and event.tick or game.tick
  if not (ent and ent.valid) and view and view.probe_name and
     view.probe_tick and tick - view.probe_tick <= 30 then
    local probe = st.entities and st.entities[view.probe_name]
    if probe and probe.valid then ent = probe end
  end
  if not (ent and ent.valid) then
    local sel = player and player.selected
    if sel and sel.valid and owned_target(st, player, sel) then
      local p = event and event.cursor_position
      if not p then
        ent = sel
      else
        local node_name = sel.name:match("^dsm%-node%-(.+)$")
        local node = node_name and State.catalog().nodes[node_name]
        local reach = (node and node.size or 1) / 2 + 1.5
        local dx, dy = sel.position.x - (p.x or p[1]), sel.position.y - (p.y or p[2])
        if dx * dx + dy * dy <= reach * reach then ent = sel end
      end
    end
  end
  if view then
    local p = event and event.cursor_position
    view.last_lmb_target = ent and ent.name or "-"
    view.last_lmb_tick = tick
    view.last_lmb_position = p and {x = p.x or p[1], y = p.y or p[2]} or nil
  end
  if not (ent and ent.valid) then return false end
  if view and view.click_entity == ent and view.click_tick and
     tick >= view.click_tick and tick - view.click_tick <= 8 then return true end
  if view then view.click_entity, view.click_tick = ent, tick end
  return M.open_remote_target(player, ent, {allow_locked = true})
end

function M.on_click(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if not (player and State.get().viewers[player.index]) then return end
  if element.name and element.name:sub(1, #PB_PREFIX) == PB_PREFIX then
    local name = element.tags and element.tags.node
    if not name then name = element.name:sub(#PB_PREFIX + 1) end
    local ent = name and State.get().entities[name]
    if ent and ent.valid then
      M.open_remote_target(player, ent, {allow_locked = true})
    else
      log("[dynamic-starmap] planet button click without entity: " .. tostring(name))
    end
    return
  end
  if element.name == "dsm-platform-view" then
    local mark = player.selected
    if not (mark and mark.valid and (mark.name == "dsm-platform-parked-marker" or
      mark.name == "dsm-platform-moving-marker")) then
      for _, record in pairs(State.get().platform_marks or {}) do
        if element.parent.tags and element.parent.tags.key == record.force .. ":" .. record.index then
          mark = record.entity
          break
        end
      end
    end
    M.open_remote_target(player, mark)
  end
end

return M
