local State = require("scripts.state")
local Surface = require("scripts.surface")
local Map = require("scripts.map")
local Gui = require("scripts.gui")
local Clicks = require("scripts.clicks")
_G.DSM_GUI = Gui
local Cards = require("scripts.cards")

-- Full regeneration is destructive, but only for our own dedicated surface.
local function regenerate(caller_index)
  local ok, reason = Map.can_regenerate(true)
  if not ok then return false, reason end
  Gui.close_all()
  return Map.regenerate(caller_index)
end

-- Restore without clearing chunks; close our stale cameras only when the
-- underlying surface is gone. An existing map can be repaired in place.
local function restore()
  if not game.surfaces[Surface.NAME] then Gui.close_all() end
  return Map.restore()
end


script.on_init(function() State.get(); Map.restore() end)
script.on_configuration_changed(function()
  Gui.close_all()
  -- 0.17 removed the pause button. Old saves may still be paused or have a
  -- zero time-scale, leaving every orbit apparently frozen with no GUI reset.
  local st=State.get()
  st.paused=false
  st.time_scale=nil
  Map.rebuild()
end)
script.on_event(defines.events.on_chunk_generated, Map.chunk_generated)
script.on_event(defines.events.on_surface_cleared, Map.surface_cleared)
script.on_event(defines.events.on_force_created, function(event)
  Map.chart_force(event.force)
end)
script.on_event(defines.events.on_research_finished, function(event)
  Cards.refresh_force(event.research.force)
end)
script.on_event(defines.events.on_tick, function(event)
  if not game.surfaces[Surface.NAME] then Map.restore() end
  Gui.snap_pending()
  Map.tick(event)
  Gui.tick(event)
end)
script.on_event("dsm-toggle-cards",function(event)
  Cards.toggle(game.get_player(event.player_index))
end)
script.on_event("dsm-remote-target", function(event)
  Clicks.open_selected_target(game.get_player(event.player_index),event)
end)
script.on_event("dsm-focus-target", function(event)
  Clicks.focus_selected_target(game.get_player(event.player_index),event)
end)
script.on_event("dsm-toggle", function(event)
  Gui.toggle(game.get_player(event.player_index))
end)
script.on_event(defines.events.on_gui_click, Clicks.on_click)
pcall(function()
  script.on_event(defines.events.on_gui_hover, Gui.on_button_hover)
end)
script.on_event(defines.events.on_selected_entity_changed, Gui.on_selected)
script.on_event(defines.events.on_player_controller_changed, function(event)
  local player = game.get_player(event.player_index)
  if player and State.get().viewers[player.index] and player.controller_type ~= defines.controllers.remote then
    Gui.close(player)
  end
end)
script.on_event(defines.events.on_player_removed, function(event)
  Cards.forget(event.player_index)
  State.get().viewers[event.player_index] = nil
  if State.get().camera_views then
    State.get().camera_views[event.player_index]=nil
  end
end)

-- Opt-in admin/debug commands report to their caller; normal map actions
-- stay quiet. Errors are also recorded in factorio-current.log.
commands.add_command("dsm-regenerate", {"dsm.regenerate-help"}, function(command)
  local player=command.player_index and game.get_player(command.player_index)
  if player and not player.admin then player.print({"dsm.regenerate-admin"});return end
  local ok,reason=regenerate(command.player_index)
  if player then
    if ok then
      player.print(reason=="pending" and {"dsm.regenerate-started"} or
        {"dsm.regenerate-done"})
    else
      player.print(reason=="occupied" and {"dsm.regenerate-occupied"} or
        {"dsm.restore-failed",tostring(reason)})
    end
  end
  if not ok then log("[dynamic-starmap] regenerate blocked: "..tostring(reason)) end
end)

commands.add_command("dsm-restore", {"dsm.restore-help"}, function(command)
  local player=command.player_index and game.get_player(command.player_index)
  if player and not player.admin then player.print({"dsm.restore-admin"});return end
  local ok,reason=restore()
  if player then player.print(ok and {"dsm.restore-done"} or
    {"dsm.restore-failed",tostring(reason)}) end
  if not ok then log("[dynamic-starmap] restore failed: "..tostring(reason)) end
end)

-- Explicitly requested diagnostic goes to both chat and factorio-current.log.
commands.add_command("dsm-hover-debug", {"dsm.hover-debug-help"}, function(command)
  local player=command.player_index and game.get_player(command.player_index)
  if not player then return end
  local view=State.get().viewers[player.index]
  local selected=player.selected
  local name=selected and selected.valid and selected.name or "-"
  local card=player.gui.screen["dsm-hover-conditions"]
  local open=card and card.valid and card.tags.node or "-"
  local last=view and view.last_lmb_position
  local click=(view and view.last_lmb_target or "-")..
    (last and (" @ "..string.format("%.2f,%.2f",last.x,last.y)) or "")
  local text="[dynamic-starmap] hover debug: selected="..tostring(name)..
    ", entity="..tostring(view and view.last_entity_hover or "-")..
    ", menu="..tostring(open)..", camera="..tostring(player.surface.name)..
    ", last LMB="..click
  local st=State.get()
  local bodies,ships=0,0
  for _,e in pairs(st.entities or {}) do if e.valid then bodies=bodies+1 end end
  for _,mark in pairs(st.platform_marks or {}) do
    if mark.entity and mark.entity.valid then ships=ships+1 end
  end
  text=text..", bodies="..bodies..", sun="..
    tostring(st.entities.star and st.entities.star.valid or false)..
    ", platforms="..ships..", clock="..tostring(st.clock)..
    ", speed="..tostring(st.time_scale or State.catalog().time_scale)..
    ", paused="..tostring(st.paused)..
    ", pending-clear="..tostring(st.pending_rebuild_surface ~= nil)..
    ", rebuild-error="..tostring(st.last_rebuild_error or "-")

  player.print(text)
  log(text)
end)

script.on_load(function()
end)
remote.add_interface("dynamic_starmap",require("scripts.public"))
