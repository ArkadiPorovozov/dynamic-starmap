-- Supported runtime API for third-party mods. Does not mutate vanilla
-- Space Age platforms, planets, or space-connection prototypes.
local State=require("scripts.state")
local Surface=require("scripts.surface")
local Map=require("scripts.map")
local Gui=require("scripts.gui")
local Custom=require("scripts.custom")
local M={}

local function player(index)
  assert(type(index)=="number" and index>=1,"player index required")
  return game.get_player(index)
end
local function finite(value)
  return type(value)=="number" and value==value and
    value>-1000000 and value<1000000
end

function M.get_catalog() return State.copy(State.catalog()) end
function M.get_node(name)
  local node=State.catalog().nodes[name]
  return node and State.copy(node) or nil
end
function M.get_routes() return State.copy(State.catalog().routes) end
function M.get_surface() return game.surfaces[Surface.NAME] end
function M.get_entity(name)
  local ent=State.get().entities[name]
  return ent and ent.valid and ent or nil
end
function M.get_position(name)
  local p=State.get().positions and State.get().positions[name]
  return p and {x=p.x,y=p.y} or nil
end
function M.get_render_ids(name)
  local st=State.get()
  return {sprite=st.sprites and st.sprites[name],
    label=st.labels and st.labels[name],orbit=st.orbits and st.orbits[name]}
end
function M.get_platform_marks()
  local result={}
  for key,mark in pairs(State.get().platform_marks or {}) do
    if mark.entity and mark.entity.valid then
      local p=mark.sprite_position or mark.entity.position
      result[key]={force=mark.force,index=mark.index,moving=mark.moving,
        position={x=p.x,y=p.y}}
    end
  end
  return result
end
function M.get_state()
  local st=State.get()
  local viewers=0
  for _ in pairs(st.viewers) do viewers=viewers+1 end
  return {paused=st.paused,time_scale=st.time_scale or State.catalog().time_scale,
    clock=st.clock,pending_clear=st.pending_rebuild_surface~=nil,
    rebuild_error=st.last_rebuild_error,viewers=viewers}
end
function M.get_orbit(name)
  local node=State.catalog().nodes[name]
  if not node then return nil end
  local override=State.get().orbit_overrides and State.get().orbit_overrides[name] or {}
  local tidal_lock=override.tidal_lock
  if tidal_lock==nil then tidal_lock=node.tidal_lock end
  return {parent=node.parent,radius=override.radius or node.radius,
    phase=override.phase or node.phase,period=override.period or node.period,
    orbit_direction=override.orbit_direction or node.orbit_direction or 1,
    spin_direction=override.spin_direction or node.spin_direction or 1,
    tidal_lock=tidal_lock}
end

function M.open(index) local p=player(index);return p and Gui.open(p) or false end
function M.close(index) local p=player(index);return p and Gui.close(p) or false end
function M.toggle(index) local p=player(index);if not p then return false end
  if State.get().viewers[index] then return Gui.close(p) end
  return Gui.open(p)
end
function M.focus(index,name) local p=player(index);return p and Gui.focus(p,name) or false end
function M.focus_platform(index,force_index,platform_index)
  local p=player(index)
  if not p or not tonumber(force_index) or not tonumber(platform_index) then return false end
  return Gui.focus_platform(p,tostring(force_index)..":"..tostring(platform_index))
end
function M.focus_position(index,position)
  local p=player(index)
  assert(type(position)=="table" and finite(position.x) and finite(position.y),
    "focus_position needs a finite {x,y} within one million tiles")
  return p and Gui.focus_position(p,position) or false
end

function M.rebuild()
  if State.get().pending_rebuild_surface then return false end
  return Map.rebuild()
end
function M.restore()
  if not game.surfaces[Surface.NAME] then Gui.close_all() end
  local ok=Map.restore();return ok
end
function M.regenerate()
  if State.get().pending_rebuild_surface then return false end
  local ok=Map.can_regenerate(true)
  if not ok then return false end
  Gui.close_all()
  local started=Map.regenerate()
  return started -- if a surface exists, rebuilding finishes on_surface_cleared
end
function M.rechart(force_name)
  local force=game.forces[force_name]
  if not (force and force.valid) then return false end
  Map.chart_force(force)
  return true
end
function M.set_paused(value) assert(type(value)=="boolean","paused must be boolean")
  State.get().paused=value;return true
end
function M.set_time_scale(value)
  assert(finite(value) and value>=0 and value<=100,
    "time_scale must be a number in [0,100]")
  State.get().time_scale=value;return true
end

-- Runtime orbit overrides persist in storage. Geometry is rebuilt in place;
-- base data-stage catalog and native Space Age routes remain unchanged.
function M.set_orbit(name,changes)
  assert(type(changes)=="table","orbit settings table required")
  local node=State.catalog().nodes[name]
  assert(node and name~="star","unknown orbiting node")
  assert(not State.get().pending_rebuild_surface,"map is being cleared")
  local st=State.get()
  st.orbit_overrides=st.orbit_overrides or {}
  local override=State.copy(st.orbit_overrides[name] or {})
  local any=false
  for key,value in pairs(changes) do
    assert(key=="radius" or key=="phase" or key=="period" or
      key=="orbit_direction" or key=="spin_direction" or key=="tidal_lock",
      "unsupported runtime orbit property")
    if key=="tidal_lock" then
      assert(type(value)=="boolean","tidal_lock must be boolean")
    elseif key=="orbit_direction" or key=="spin_direction" then
      assert(value==1 or value==-1,"rotation direction must be 1 or -1")
    else
      assert(finite(value),"orbit value must be finite")
    end
    if key=="radius" then assert(value>0 and value<=100000,"radius out of range") end
    if key=="period" then assert(value>=0,"period cannot be negative") end
    override[key]=value
    any=true
  end
  if not any then return false end
  st.orbit_overrides[name]=override
  if game.surfaces[Surface.NAME] then Map.rebuild() end
  return true
end
function M.reset_orbit(name)
  local st=State.get()
  if not (st.orbit_overrides and st.orbit_overrides[name]) then return false end
  assert(not st.pending_rebuild_surface,"map is being cleared")
  st.orbit_overrides[name]=nil
  if game.surfaces[Surface.NAME] then Map.rebuild() end
  return true
end

function M.set_node(name, changes)
  assert(type(name)=="string" and State.catalog().nodes[name], "unknown node")
  assert(type(changes)=="table", "changes table required")
  local st = State.get()
  st.node_overrides = st.node_overrides or {}
  local override = State.copy(st.node_overrides[name] or {})
  for key, value in pairs(changes) do
    if value == nil then override[key] = nil else override[key] = State.copy(value) end
  end
  st.node_overrides[name] = override
  if game.surfaces[Surface.NAME] then Map.rebuild() end
  return true
end
function M.reset_node(name)
  local st = State.get()
  if not (st.node_overrides and st.node_overrides[name]) then return false end
  st.node_overrides[name] = nil
  if game.surfaces[Surface.NAME] then Map.rebuild() end
  return true
end

M.set_annotation=Custom.set
M.remove_annotation=Custom.remove
M.get_annotations=Custom.list
return M
