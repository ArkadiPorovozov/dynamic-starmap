-- Runtime-owned map annotations. These belong to this mod's rendering set;
-- definitions survive saves and are redrawn when the surface is rebuilt.
local State=require("scripts.state")
local Surface=require("scripts.surface")
local M={}

local function finite(x)
  return type(x)=="number" and x==x and x>-1000000 and x<1000000
end

local function point(p)
  assert(type(p)=="table" and finite(p.x) and finite(p.y),
    "annotation position must have finite x/y within one million tiles")
  return {x=p.x,y=p.y}
end

local function draw(surface,id,spec)
  local forces
  if spec.forces then
    forces={}
    for _,name in ipairs(spec.forces) do
      local force=game.forces[name]
      if force and force.valid then forces[#forces+1]=force end
    end
    if #forces==0 then return end -- force may not exist yet; retry on rebuild
  end
  local base={surface=surface,target=spec.position,forces=forces}
  local object
  if spec.kind=="text" then
    base.text=spec.text
    base.color=spec.color or {r=1,g=1,b=1,a=1}
    base.scale=spec.scale or 1
    base.alignment=spec.alignment or "center"
    object=rendering.draw_text(base)
  else
    base.sprite=spec.sprite
    base.x_scale=spec.scale or 1
    base.y_scale=spec.scale or 1
    base.orientation=spec.orientation or 0
    object=rendering.draw_sprite(base)
  end
  State.get().annotation_renders[id]=object.id
end

function M.set(id,value)
  assert(type(id)=="string" and #id>0 and #id<=128,
    "annotation id must be a nonempty string of up to 128 characters")
  assert(type(value)=="table" and (value.kind=="text" or value.kind=="sprite"),
    "annotation.kind must be text or sprite")
  local spec={kind=value.kind,position=point(value.position)}
  if spec.kind=="text" then
    assert(type(value.text)=="string" or type(value.text)=="table",
      "text annotation needs text or LocalisedString")
    spec.text=State.copy(value.text)
    if value.color then
      assert(type(value.color)=="table","color must be a table")
      spec.color=State.copy(value.color)
    end
    if value.alignment then
      assert(value.alignment=="left" or value.alignment=="center" or
        value.alignment=="right","invalid text alignment")
      spec.alignment=value.alignment
    end
  else
    assert(type(value.sprite)=="string" and
      helpers.is_valid_sprite_path(value.sprite),"invalid sprite path")
    spec.sprite=value.sprite
    if value.orientation~=nil then
      assert(finite(value.orientation),"invalid orientation")
      spec.orientation=value.orientation%1
    end
  end
  if value.scale~=nil then
    assert(finite(value.scale) and value.scale>0 and value.scale<=20,
      "annotation scale must be in (0,20]")
    spec.scale=value.scale
  end
  if value.forces~=nil then
    assert(type(value.forces)=="table","forces must be an array of force names")
    spec.forces={}
    for _,name in ipairs(value.forces) do
      assert(type(name)=="string","force name must be a string")
      spec.forces[#spec.forces+1]=name
    end
  end
  local st=State.get()
  st.annotations=st.annotations or {}
  st.annotation_renders=st.annotation_renders or {}
  M.remove(id)
  st.annotations[id]=spec
  local surface=game.surfaces[Surface.NAME]
  if surface and not st.pending_rebuild_surface then draw(surface,id,spec) end
  return true
end

function M.remove(id)
  local st=State.get()
  local rid=st.annotation_renders and st.annotation_renders[id]
  local object=rid and rendering.get_object_by_id(rid)
  if object then object.destroy() end
  if st.annotation_renders then st.annotation_renders[id]=nil end
  local existed=st.annotations and st.annotations[id]~=nil or false
  if st.annotations then st.annotations[id]=nil end
  return existed
end

function M.list() return State.copy(State.get().annotations or {}) end

function M.redraw(surface)
  local st=State.get()
  st.annotation_renders={}
  for id,spec in pairs(st.annotations or {}) do draw(surface,id,spec) end
end

return M
