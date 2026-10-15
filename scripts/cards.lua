-- Shift+I: world-space conditions beside planets, following the old map.
-- Visibility is per player; values/contents come from the data-stage catalog.
local State=require("scripts.state")
local Conditions=require("scripts.conditions")
local M={}

function M.forget(index)
  local st=State.get()
  for _,id in pairs((st.cards or {})[index] or {}) do
    local object=rendering.get_object_by_id(id)
    if object then object.destroy() end
  end
  if st.cards then st.cards[index]=nil end
  if st.card_enabled then st.card_enabled[index]=nil end
end

function M.hide(player) M.forget(player.index) end

local function unlocked(player,name)
  local ok,value=pcall(function() return player.force.is_space_location_unlocked(name) end)
  return not ok or value~=false
end

function M.show(player)
  local st=State.get()
  if not st.viewers[player.index] then return false end
  M.forget(player.index)
  st.card_enabled=st.card_enabled or {}
  st.cards=st.cards or {}
  st.card_enabled[player.index]=true
  local ids={}
  for name,node in pairs(State.catalog().nodes) do
    local ent=st.entities[name]
    if ent and ent.valid and name~="star" and unlocked(player,name) then
      local p=(st.positions and st.positions[name]) or ent.position
      local right=p.x>=0
      ids[name]=rendering.draw_text{
        text=Conditions.text(node,true),use_rich_text=true,
        surface=ent.surface,target={x=p.x+(right and 5 or -5),y=p.y},
        players={player},color={r=0.92,g=0.92,b=0.92,a=0.9},
        scale=0.68,alignment=right and "left" or "right"
      }.id
    end
  end
  st.cards[player.index]=ids
  return true
end

function M.update(st)
  for _,ids in pairs(st.cards or {}) do
    for name,id in pairs(ids) do
      local p=st.positions and st.positions[name]
      local obj=p and rendering.get_object_by_id(id)
      if obj then
        local right=p.x>=0
        obj.target={x=p.x+(right and 5 or -5),y=p.y}
        obj.alignment=right and "left" or "right"
      end
    end
  end
end

function M.toggle(player)
  if not player then return end
  if State.get().card_enabled and State.get().card_enabled[player.index] then
    M.hide(player)
  else M.show(player) end
end

function M.refresh_force(force)
  local st=State.get()
  local indices={}
  for index in pairs(st.card_enabled or {}) do indices[#indices+1]=index end
  for _,index in ipairs(indices) do
    local player=game.get_player(index)
    if player and player.valid and player.force==force then M.show(player) end
  end
end

function M.restore()
  local st=State.get()
  local indices={}
  for index in pairs(st.card_enabled or {}) do indices[#indices+1]=index end
  st.cards={}
  for _,index in ipairs(indices) do
    local player=game.get_player(index)
    if player and player.valid and st.viewers[index] then M.show(player) end
  end
end

return M
