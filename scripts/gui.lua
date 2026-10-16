local State = require("scripts.state")
local Surface = require("scripts.surface")
local Map = require("scripts.map")
local Platforms = require("scripts.platforms")
local Cards = require("scripts.cards")
local Conditions = require("scripts.conditions")
local Clicks = require("scripts.clicks")
-- Remove screen overlays from saves made by 0.15–0.16.3. They intercept
-- mouse selection and must not sit over the restored native world entities.
local PB_PREFIX = "dsm-pbtn-"
local function clear_old_hits(player)
  local stale={}
  for _,child in pairs(player.gui.screen.children) do
    if child.valid and child.name and
       (child.name:sub(1,8)=="dsm-hit-" or
        child.name:sub(1,17)=="dsm-platform-hit-" or
        child.name:sub(1,#PB_PREFIX)==PB_PREFIX) then
      stale[#stale+1]=child
    end
  end
  for _,child in ipairs(stale) do if child.valid then child.destroy() end end
end
local M = {}

local TOP_BUTTON = "dsm-top-starmap"
function M.ensure_top_button(player)
  if not (player and player.valid) then return end
  local btn = player.gui.top[TOP_BUTTON]
  if btn and btn.valid then return btn end
  btn = player.gui.top.add{
    type = "button",
    name = TOP_BUTTON,
    caption = {"dsm.open-starmap"},
    tooltip = {"dsm.open-starmap"},
    style = "tool_button"
  }
  return btn
end

function M.remove_top_button(player)
  if not (player and player.valid) then return end
  local btn = player.gui.top[TOP_BUTTON]
  if btn and btn.valid then btn.destroy() end
end
local GUI, DETAILS, PLATFORM, HOVER = "dsm-panel", "dsm-details", "dsm-platform", "dsm-hover-conditions"

local function destroy_gui(player)
  clear_old_hits(player)
  local panel = player.gui.screen[GUI]
  if panel then panel.destroy() end
  local detail = player.gui.screen[DETAILS]
  if detail then detail.destroy() end
  local preview = player.gui.screen[PLATFORM]
  if preview then preview.destroy() end
  local hover = player.gui.screen[HOVER]
  if hover then hover.destroy() end
end

local function show_details(player, name)
  local node = State.catalog().nodes[name]
  if not node then return end
  local old = player.gui.screen[DETAILS]
  if old then old.destroy() end
  local proto = prototypes.space_location[name]
  local frame = player.gui.screen.add{
    type="frame", name=DETAILS, direction="vertical",
    caption=proto and proto.localised_name or node.localised_name or name
  }
  frame.auto_center = false
  frame.location = {x=260,y=120}
  local body = frame.add{type="scroll-pane"}
  body.style.maximal_height = 580
  body.style.maximal_width = 390
  local column = body.add{type="flow", direction="vertical"}
  local function line(caption, gold)
    local label = column.add{type="label", caption=caption}
    label.style.single_line = false
    label.style.maximal_width = 370
    if gold then label.style.font_color = {r=1,g=0.79,b=0.46} end
  end
  local desc = proto and proto.localised_description or node.description
  if desc then
    line(desc)
    local spacer=column.add{type="empty-widget"}
    spacer.style.height=6
  end
  local fields = State.copy((proto and proto.custom_tooltip_fields) or node.tooltip_fields or {})
  table.sort(fields, function(a,b) return (a.order or 100) < (b.order or 100) end)
  for _, field in ipairs(fields) do
    if field.show_in_tooltip ~= false and
       Conditions.meaningful(field.name) and Conditions.meaningful(field.value) then
      line({"", field.name, ": ", field.value}, true)
    end
  end
  local surface_props = node.properties or {}
  local keys = {}
  for key in pairs(surface_props) do keys[#keys+1] = key end
  table.sort(keys, function(a,b)
    local pa, pb = prototypes.surface_property[a], prototypes.surface_property[b]
    local ka, kb = pa and pa.order or a, pb and pb.order or b
    return ka == kb and a < b or ka < kb
  end)
  for _, key in ipairs(keys) do
    local prop = prototypes.surface_property[key]
    local value = surface_props[key]
    line({"", Conditions.property_title(key,prop), ": ",
      Conditions.value_text(key,value,prop)}, true)
  end
  local planet = game.planets[name]
  if not surface_props["day-night-cycle"] and planet and planet.surface then
    line({"dsm.day-cycle", math.floor(planet.surface.ticks_per_day/360+0.5)/10}, true)
  end

  -- Extra orbital info requested for planets.
  local st = State.get()
  local pos = st.positions and st.positions[name]
  if pos then
    line({"dsm.coordinates", pos.x, pos.y}, true)
    local dist = math.sqrt(pos.x * pos.x + pos.y * pos.y)
    line({"dsm.distance", dist}, true)
  end
  local orient = st.visual_orientations and st.visual_orientations[name]
  if orient ~= nil then
    line({"dsm.rotation", orient * 360}, true)
  end
  local connectors = 0
  for _, conn in pairs(prototypes.space_connection or {}) do
    if conn.from == name or conn.to == name then connectors = connectors + 1 end
  end
  line({"dsm.connectors", connectors}, true)
  local contents, seen = {}, {}
  for _, resource in ipairs(node.contents or {}) do
    contents[#contents+1], seen[resource] = resource, true
  end
  local map = proto and proto.map_gen_settings
  local settings = map and map.autoplace_settings and map.autoplace_settings.entity
  if not node.contents_custom then
    for resource in pairs((settings and settings.settings) or {}) do
      local entity = prototypes.entity[resource]
      if entity and entity.type == "resource" and not seen[resource] then
        contents[#contents+1], seen[resource] = resource, true
      end
    end
  end
  table.sort(contents)
  if #contents > 0 then
    line({"dsm.contents"}, true)
    local icons
    for i, resource in ipairs(contents) do
      if i % 8 == 1 then icons = column.add{type="flow", direction="horizontal"} end
      local entity = prototypes.entity[resource]
      local sprite = "entity/"..resource
      if not helpers.is_valid_sprite_path(sprite) then
        if prototypes.item[resource] then sprite="item/"..resource
        elseif prototypes.fluid and prototypes.fluid[resource] then sprite="fluid/"..resource end
      end
      if helpers.is_valid_sprite_path(sprite) then
        local icon = icons.add{type="sprite", sprite=sprite,
          tooltip=entity and entity.localised_name or resource, resize_to_sprite=false}
        icon.style.width, icon.style.height = 32, 32
      else
        icons.add{type="label", caption=resource}
      end
    end
  end
  local solar = proto and proto.solar_power_in_space or node.solar_power_in_space
  if solar then line({"dsm.solar", math.floor(solar*10+0.5)/10}, true) end
end

-- The old map used a tooltip_frame near the selected body, with a title,
-- localised description, surface conditions, generated contents and solar power.
local function place_hover(player,frame,position)
  local res=player.display_resolution or {width=1280,height=720}
  local scale=player.display_scale or 1
  if scale<=0 then scale=1 end
  local zoom=1
  local ok,value=pcall(function() return player.zoom end)
  if ok and type(value)=="number" and value>0 then zoom=value end
  local point=player.position
  -- Screen GUI locations use display pixels, while frame style sizes use
  -- GUI pixels. Keep the hover card beside the actual world sprite at any
  -- interface scale, and clamp its physical footprint to the screen.
  local x=res.width/2+(position.x-point.x)*32*zoom+20*scale
  local y=res.height/2+(position.y-point.y)*32*zoom+22*scale
  local max_x=math.max(4,res.width-430*scale)
  local max_y=math.max(4,res.height-560*scale)
  x,y=math.max(4,math.min(x,max_x)),math.max(4,math.min(y,max_y))
  local loc=frame.location
  if not loc or (loc.x-x)^2+(loc.y-y)^2>1 then frame.location={x=x,y=y} end
end

-- Custom tooltip frame based on the old project's planet-info menu. All
-- body-specific values come from the final data-stage catalog; live
-- prototypes supply localised names for property and resource icons.
local function show_hover(player,name)
  local node=State.catalog().nodes[name]
  if not node then return end
  local frame=player.gui.screen[HOVER]
  if frame and frame.tags.node~=name then frame.destroy();frame=nil end
  if not frame then
    local ok,err=pcall(function()
    frame=player.gui.screen.add{
      type="frame",name=HOVER,direction="vertical",style="tooltip_frame",tags={node=name}
    }
    frame.style.padding=8
    frame.ignored_by_interaction=true
    local proto=prototypes.space_location[name]
    local heading=frame.add{type="flow",direction="horizontal"}
    if node.sprite and helpers.is_valid_sprite_path(node.sprite) then
      local icon=heading.add{type="sprite",sprite=node.sprite}
      icon.style.width,icon.style.height=34,34
    end
    heading.add{type="label",caption=proto and proto.localised_name or
      node.localised_name or name,style="tooltip_title_label"}
    local scroll=frame.add{type="scroll-pane"}
    scroll.style.maximal_height=480
    scroll.style.maximal_width=400
    local column=scroll.add{type="flow",direction="vertical"}
    local function line(caption,color)
      local label=column.add{type="label",caption=caption,style="tooltip_label"}
      label.style.single_line=false
      label.style.maximal_width=380
      if color then label.style.font_color=color end
      return label
    end
    local description=node.description
    if description then
      line(description)
      local spacer=column.add{type="empty-widget"}
      spacer.style.height=6
    end
    local fields=State.copy(node.tooltip_fields or {})
    table.sort(fields,function(a,b) return tostring(a.order or "")<tostring(b.order or "") end)
    for _,field in ipairs(fields) do
      if field.show_in_tooltip~=false and
         Conditions.meaningful(field.name) and Conditions.meaningful(field.value) then
        line({"",field.name,": ",field.value},{r=1,g=0.8,b=0.51})
      end
    end
    local props=Conditions.property_lines(node)
    if #props>0 then
      line({"dsm.conditions"},{r=1,g=0.8,b=0.51})
      for _,row in ipairs(props) do line(row) end
    end
    if node.parent then
      line({"dsm.map-orbit",math.floor(node.radius*10+0.5)/10})
    end
    if node.solar_power_in_space then
      line({"dsm.solar",node.solar_power_in_space})
    end
    if node.contents and #node.contents>0 then
      line({"dsm.contents"},{r=1,g=0.8,b=0.51})
      local row
      for i,resource in ipairs(node.contents) do
        if i%2==1 then row=column.add{type="flow",direction="horizontal"} end
        local slot=row.add{type="flow",direction="horizontal"}
        slot.style.minimal_width=185
        local sprite=Conditions.content_sprite(resource)
        local entity=prototypes.entity[resource]
        local item=prototypes.item[resource]
        local fluid=prototypes.fluid and prototypes.fluid[resource]
        local title=(entity and entity.localised_name) or
          (item and item.localised_name) or
          (fluid and fluid.localised_name) or resource
        if sprite then
          local icon=slot.add{type="sprite",sprite=sprite,tooltip=title}
          icon.style.width,icon.style.height=28,28
        end
        local label=slot.add{type="label",caption=title,tooltip=title}
        label.style.maximal_width=145
      end
    end
    end)
    if not ok then
      log("[dynamic-starmap] hover menu: "..tostring(err))
      -- A third-party GUI style/icon must not suppress the whole card.
      if frame and frame.valid then
        frame.clear()
        frame.add{type="label",caption=node.localised_name or name}
        local fallback=frame.add{type="label",caption=Conditions.text(node,false)}
        fallback.style.single_line=false
      end
    end
  end
  local p=State.get().positions and State.get().positions[name]
  local ent=State.get().entities[name]
  if p or (ent and ent.valid) then place_hover(player,frame,p or ent.position) end
end

-- Кликабельные кнопки поверх планет: событие on_gui_click движок доставляет
-- гарантированно, в отличие от cursor_position/selected у mouse custom-input
-- в Remote View. Кнопка несёт имя тела в tags; позиция/размер каждый тик
-- следуют за спрайтом (world->screen как в place_hover).
local function update_planet_buttons(player,st,view)
  if not (player.surface and player.surface.name==Surface.NAME) then
    if view.pbuttons then
      for _,btn in pairs(view.pbuttons) do if btn.valid then btn.destroy() end end
      view.pbuttons=nil
    end
    return
  end
  view.pbuttons=view.pbuttons or {}
  local res=player.display_resolution or {width=1280,height=720}
  local scale=player.display_scale or 1
  if scale<=0 then scale=1 end
  local zoom=1
  local ok,z=pcall(function() return player.zoom end)
  if ok and type(z)=="number" and z>0 then zoom=z end
  local cam=player.position
  local seen={}
  for name,node in pairs(State.catalog().nodes) do
    local ent=st.entities[name]
    if name~="star" and ent and ent.valid and node.sprite and
       helpers.is_valid_sprite_path(node.sprite) then
      seen[name]=true
      local btn=view.pbuttons[name]
      if not (btn and btn.valid) then
        local okb,created=pcall(function()
          return player.gui.screen.add{type="sprite-button",
            name=PB_PREFIX..name,sprite=node.sprite,tags={node=name}}
        end)
        if not okb then created=nil end
        btn=created
        view.pbuttons[name]=btn
        if btn and btn.valid then
          pcall(function() btn.tags={node=name} end)
          pcall(function() btn.ignored_by_interaction=false end)
          pcall(function() btn.enabled=true end)
          pcall(function() btn.mouse_button_filter={"left"} end)
          pcall(function() btn.visible=true end)
          pcall(function() btn.style.padding=0 end)
        end
      end
      if btn and btn.valid then
        local p=(st.positions and st.positions[name]) or ent.position
        local dia=node.size*32*zoom
        local x=res.width/2+(p.x-cam.x)*32*zoom-dia/2
        local y=res.height/2+(p.y-cam.y)*32*zoom-dia/2
        if x<-dia or y<-dia or x>res.width or y>res.height then
          btn.visible=false
        else
          btn.visible=true
          btn.location={x=x,y=y}
          local w=math.max(10,dia/scale)
          if math.abs((btn.style.width or 0)-w)>1 then
            btn.style.width,btn.style.height=w,w
          end
        end
      end
    end
  end
  for name,btn in pairs(view.pbuttons) do
    if not seen[name] then
      if btn and btn.valid then btn.destroy() end
      view.pbuttons[name]=nil
    end
  end
end

-- The original map lets you inspect a parked or flying platform without
-- moving the player. The camera looks at its real platform surface.
local function platform_camera_fit(surface)
  local ok,fit=pcall(function()
    local minx,miny,maxx,maxy=math.huge,math.huge,-math.huge,-math.huge
    for chunk in surface.get_chunks() do
      local a=chunk.area
      minx,miny=math.min(minx,a.left_top.x),math.min(miny,a.left_top.y)
      maxx,maxy=math.max(maxx,a.right_bottom.x),math.max(maxy,a.right_bottom.y)
    end
    if minx==math.huge then return nil end
    local w,h=maxx-minx+40,maxy-miny+40
    return {position={x=(minx+maxx)/2,y=(miny+maxy)/2},
      zoom=math.max(0.09,math.min(0.6,300/(32*w),210/(32*h))),
      area={{minx-16,miny-16},{maxx+16,maxy+16}}}
  end)
  if ok then return fit end
end

local function show_platform(player,platform,mark)
  local frame=player.gui.screen[PLATFORM]
  local key=mark.force..":"..mark.index
  if frame and frame.tags and frame.tags.key~=key then frame.destroy();frame=nil end
  if not frame then
    frame=player.gui.screen.add{type="frame",name=PLATFORM,direction="vertical",
      caption=platform.name,tags={key=key}}
    frame.auto_center=false
    frame.location={x=670,y=120}
    frame.add{type="label",name="dsm-platform-route",caption=""}
    frame.add{type="button",name="dsm-platform-view",caption={"dsm.view-platform"}}
    local surf=platform.surface
    if surf and surf.valid then
      local cam=frame.add{type="camera",name="dsm-platform-camera"}
      local fit=platform_camera_fit(surf)
      cam.surface_index=surf.index
      cam.position=fit and fit.position or {0,0}
      cam.zoom=fit and fit.zoom or 0.12
      player.force.chart(surf,fit and fit.area or {{-64,-64},{64,64}})
      cam.style.width,cam.style.height=300,210
    end
  end
  frame.caption=platform.name
  local conn=platform.space_connection
  local location=platform.space_location
  if conn then
    frame["dsm-platform-route"].caption={"dsm.flight",conn.from.name,conn.to.name,
      math.floor((platform.distance or 0)*100+0.5)}
  else
    frame["dsm-platform-route"].caption={"dsm.parked",location and location.name or "?"}
  end
end

-- UI is gated per viewer/force; shared map entities are never hidden globally
-- (that would leak one force's research state into another force's camera).
local function unlocked(player,name)
  if name=="star" then return true end
  local ok,result=pcall(function() return player.force.is_space_location_unlocked(name) end)
  return not ok or result~=false
end

function M.close(player, keep_gui)
  local st = State.get()
  local old = st.viewers[player.index]
  if not old then return false end
  old.hover_name,old.probe_name=nil,nil
  Cards.hide(player)
  if not keep_gui then destroy_gui(player) end
  st.viewers[player.index] = nil
  if st.camera_views then
    st.camera_views[player.index]=nil
  end
  if old.type == defines.controllers.character and old.character and old.character.valid then
    if player.controller_type ~= defines.controllers.character or player.character ~= old.character then
      -- Factorio requires the player and the character to belong to the
      -- SAME surface before set_controller{type=character}. The remote map
      -- camera is on dsm-space, but the body is usually still on Nauvis.
      local home=old.character.surface
      if player.surface~=home then
        player.set_controller{type=defines.controllers.remote,
          surface=home,position=old.character.position}
      end
      player.set_controller{type=defines.controllers.character,character=old.character}
    end
  elseif old.type == defines.controllers.remote and game.surfaces[old.surface] then
    player.set_controller{type=defines.controllers.remote, surface=old.surface, position=old.position}
  elseif old.type == defines.controllers.god then
    local home=game.surfaces[old.surface]
    if home and player.surface~=home then
      player.set_controller{type=defines.controllers.remote,surface=home,position=old.position}
    end
    player.set_controller{type=defines.controllers.god}
  else
    -- The original character may have died while the map was open.
    player.set_controller{type=defines.controllers.god}
  end
  return true
end

function M.open(player)
  if not (player and player.valid) then return false end
  local st = State.get()
  if st.viewers[player.index] then return true end
  if st.pending_rebuild_surface then return false end
  if player.controller_type ~= defines.controllers.character and
     player.controller_type ~= defines.controllers.remote and
     player.controller_type ~= defines.controllers.god then return false end
  local s = game.surfaces[Surface.NAME]
  if not s or not next(st.entities) then s = Map.rebuild() end
  st.viewers[player.index] = {
    type=player.controller_type, character=player.character,
    surface=player.surface.name, position=State.copy(player.position)
  }
  local sun=(st.entities.star and st.entities.star.valid and
    st.entities.star.position) or (st.positions and st.positions.star) or {x=0,y=0}
  local centre={x=sun.x,y=sun.y}
  player.set_controller{type=defines.controllers.remote,surface=s,position=centre}
  -- Remote View can restore its previous camera position AFTER set_controller
  -- in the same tick. Reassert the sun as centre once on the next tick.
  st.viewers[player.index].initial_center=centre
  st.camera_views=st.camera_views or {}
  st.camera_views[player.index]={}
  Surface.load_camera(player,s,st.camera_views[player.index],true)
  for _, ent in pairs(st.entities) do
    if ent.valid then Surface.chart_near(player, s, ent.position, 32) end
  end
  destroy_gui(player) -- remove legacy sidebar on saves made before this version
  return true
end

function M.focus_position(player,point)
  if not M.open(player) then return false end
  local st=State.get()
  st.viewers[player.index].initial_center={x=point.x,y=point.y}
  local s=game.surfaces[Surface.NAME]
  player.set_controller{type=defines.controllers.remote,surface=s,position=point}
  st.camera_views=st.camera_views or {}
  st.camera_views[player.index]=st.camera_views[player.index] or {}
  Surface.load_camera(player,s,st.camera_views[player.index],true)
  return true
end

function M.focus(player, name)
  local st = State.get()
  -- Focusing only moves the camera ON the map; it never unlocks travel.
  if not State.catalog().nodes[name] then return false end
  if not M.open(player) then return false end
  local ent = st.entities[name]
  if not (ent and ent.valid) then return false end
  local preview=player.gui.screen[PLATFORM];if preview then preview.destroy() end
  st.viewers[player.index].initial_center={x=ent.position.x,y=ent.position.y}
  player.set_controller{type=defines.controllers.remote, surface=ent.surface, position=ent.position}
  st.camera_views=st.camera_views or {}
  st.camera_views[player.index]=st.camera_views[player.index] or {}
  Surface.load_camera(player,ent.surface,st.camera_views[player.index],true)
  show_details(player, name)
  return true
end

function M.focus_platform(player,key)
  local st=State.get()
  if not (player and st.viewers[player.index]) then return false end
  local mark=st.platform_marks and st.platform_marks[key]
  if not (mark and mark.entity and mark.entity.valid and
          mark.force==player.force.name) then return false end
  local platform=Platforms.find(st,mark.entity)
  if not (platform and platform.valid and platform.force==player.force) then return false end
  local point=mark.moving and mark.sprite_position or mark.entity.position
  point=point or mark.entity.position
  local hover=player.gui.screen[HOVER];if hover then hover.destroy() end
  local details=player.gui.screen[DETAILS];if details then details.destroy() end
  st.viewers[player.index].hover_name=nil
  st.viewers[player.index].probe_name=nil
  st.viewers[player.index].initial_center={x=point.x,y=point.y}
  player.set_controller{type=defines.controllers.remote,
    surface=mark.entity.surface,position=point}
  st.camera_views=st.camera_views or {}
  st.camera_views[player.index]=st.camera_views[player.index] or {}
  Surface.load_camera(player,mark.entity.surface,st.camera_views[player.index],true)
  show_platform(player,platform,mark)
  return true
end

function M.toggle(player)
  if not player then return end
  if State.get().viewers[player.index] then M.close(player) else M.open(player) end
end


-- Наведение на кнопку планеты: показываем карточку и обновляем пробник,
-- как это делало наведение на мировую сущность.
function M.on_button_hover(event)
  local element=event.element
  if not (element and element.valid) then return end
  if not (element.name and element.name:sub(1,#PB_PREFIX)==PB_PREFIX) then return end
  local player=game.get_player(event.player_index)
  if not (player and State.get().viewers[player.index]) then return end
  local name=element.tags and element.tags.node
  if not name then return end
  local view=State.get().viewers[player.index]
  view.probe_name,view.probe_tick=name,game.tick
  view.hover_name,view.hover_tick=name,game.tick
  show_hover(player,name)
end

function M.on_selected(event)
  local player = game.get_player(event.player_index)
  local st=State.get()
  if not (player and st.viewers[player.index]) then return end
  local ent = player.selected
  local platform,mark=Platforms.find(st,ent)
  if platform and platform.force==player.force then
    local hover=player.gui.screen[HOVER];if hover then hover.destroy() end
    st.viewers[player.index].hover_name=nil
    local details=player.gui.screen[DETAILS];if details then details.destroy() end
    show_platform(player,platform,mark)
    local view=st.viewers[player.index]
    if ent and ent.valid and (not view.last_selected_teleport or
        view.last_selected_teleport~=ent.unit_number or
        (event.tick or game.tick)-(view.last_selected_tick or 0)>10) then
      view.last_selected_teleport=ent.unit_number
      view.last_selected_tick=event.tick or game.tick
      Clicks.open_remote_target(player,ent,{allow_locked=true})
    end
    return
  end
  local name = ent and ent.valid and ent.name:match("^dsm%-node%-(.+)$")
  if name and st.entities[name] and Clicks.owned_target(st,player,ent) then
    local view=st.viewers[player.index]
    if not view.last_selected_teleport or view.last_selected_teleport~=ent.unit_number or
       (event.tick or game.tick)-(view.last_selected_tick or 0)>10 then
      view.last_selected_teleport=ent.unit_number
      view.last_selected_tick=event.tick or game.tick
      Clicks.open_remote_target(player,ent,{allow_locked=true})
      return
    end
  end
  local preview=player.gui.screen[PLATFORM];if preview then preview.destroy() end
  local name = ent and ent.valid and ent.name:match("^dsm%-node%-(.+)$")
  local node = name and State.catalog().nodes[name]
  -- Inspection is available for every visible map entity; research gates
  -- travel/focus, not the data-stage hover card.
  if node then
    local view=State.get().viewers[player.index]
    view.probe_name,view.probe_tick=name,game.tick
    view.last_entity_hover,view.last_entity_tick=name,game.tick
    local view=State.get().viewers[player.index]
    view.hover_name,view.hover_tick=name,game.tick
    show_hover(player,name)
  else
    local view=State.get().viewers[player.index]
    if view then view.hover_tick=view.hover_tick or game.tick end
    local detail = player.gui.screen[DETAILS]
    if detail then detail.destroy() end
  end
end

-- Reconcile the camera BEFORE camera chunk requests in Map.tick. Remote View
-- may apply a previous offset after the same-tick set_controller call.
function M.snap_pending()
  local st=State.get()
  for index,view in pairs(st.viewers) do
    local player=game.get_player(index)
    if player and player.valid and view.initial_center then
      local centre=view.initial_center
      view.initial_center=nil
      local surface=game.surfaces[Surface.NAME]
      if surface and player.controller_type==defines.controllers.remote and
         player.surface==surface then
        player.set_controller{type=defines.controllers.remote,
          surface=surface,position=centre}
        st.camera_views=st.camera_views or {}
        st.camera_views[index]=st.camera_views[index] or {}
        Surface.load_camera(player,surface,st.camera_views[index],true)
      end
    end
  end
end

function M.tick(event)
  local st=State.get()
  for index,view in pairs(st.viewers) do
    local player=game.get_player(index)
    if player and player.valid then
      local selected=player.selected
      local name=selected and selected.valid and
        selected.name:match("^dsm%-node%-(.+)$")
      if not name and view.probe_name and event.tick-(view.probe_tick or 0)<=3 then
        name=view.probe_name
        selected=st.entities[name]
      end
      if name and selected and selected.valid and
         Clicks.same_entity(st.entities[name],selected) then
        if view.hover_name~=name or not player.gui.screen[HOVER] then show_hover(player,name) end
        view.hover_name,view.hover_tick=name,event.tick
        if Clicks.same_entity(player.selected,selected) then view.probe_name,view.probe_tick=name,event.tick end
        local frame=player.gui.screen[HOVER]
        local p=st.positions and st.positions[name]
        if frame and frame.valid and p then place_hover(player,frame,p) end
      elseif view.hover_name and event.tick-(view.hover_tick or 0)>12 then
        local frame=player.gui.screen[HOVER]
        if frame then frame.destroy() end
        view.hover_name=nil
      end
      update_planet_buttons(player,st,view)
    end
  end
end

function M.close_all()
  local st = State.get()
  local indices = {}
  for index in pairs(st.viewers) do indices[#indices+1] = index end
  for _, index in ipairs(indices) do
    local player = game.get_player(index)
    if player and player.valid then M.close(player) else
        if st.camera_views then st.camera_views[index]=nil end
      st.viewers[index] = nil
    end
  end
  -- Upgrades may leave a sidebar on a player without an active viewer entry.
  for _,player in pairs(game.players) do
    if player.valid then destroy_gui(player) end
  end
end

State.Gui = M
return M
