-- Public data-stage configuration. Other mods can edit this in data-updates.lua.
-- No planet names or orbit parents are hard-coded here.
data:extend({
  {
    type = "mod-data", name = "dsm-config", data = {
      scale = 1,                 -- original prototype distance to map tiles
      distance_multiplier = 1,  -- native tile scale; API may adjust globally
      orbit_gap = 5,            -- add five tiles to EACH native sibling interval
      update_ticks = 12,        -- when nobody watches
      update_ticks_active = 1,  -- every tick (60/s at 60 UPS) when watched
      chart_radius = 96,        -- tiles revealed around remote camera
      time_scale = 1,           -- 0 pauses orbital motion
      stars = 80,              -- deterministic background points
      default_size = 2.2,
      body_size_multiplier = 2/3, -- every planet/moon/location 1.5x smaller; sun excluded
      orbit_color = {r=0.3,g=0.3,b=0.3,a=1}, -- darker grey orbit rings
      moon_scale = 0.6, orbit_clearance = 2,
      planet_angular_speed = 0.00001, -- rad/tick at radius 100: slower than old map
      moon_angular_speed = 0.00022,
      show_platforms = true,
      static_planet_entities = false, -- opt-in: no LuaRendering, but no sun-facing spin
      nodes = {},               -- overrides of existing space locations
      custom_nodes = {}         -- map-only nodes; never add vanilla planets/routes
    }
  },
  {
    type = "simple-entity", name = "dsm-platform-parked-marker",
    flags = {"placeable-off-grid", "not-deconstructable", "not-blueprintable", "not-flammable"},
    icon = "__dynamic-starmap__/graphics/button.png", icon_size = 64,
    collision_mask = {layers = {}}, selectable_in_game = true,
    collision_box = {{-0.1,-0.1},{0.1,0.1}},
    -- Rotated 54px sprite at scale 0.27: half diagonal ~0.322 tiles.
    selection_box = {{-0.34,-0.34},{0.34,0.34}},
    -- The oriented artwork is rendered separately; keep the entity for
    -- hovering, clicking and the existing platform-to-surface shortcut.
    picture = {filename="__dynamic-starmap__/graphics/transparent.png",
      width=1,height=1},max_health = 1000000
  },
  {
    type = "simple-entity", name = "dsm-platform-moving-marker",
    flags = {"placeable-off-grid", "not-deconstructable", "not-blueprintable", "not-flammable"},
    icon = "__dynamic-starmap__/graphics/button.png", icon_size = 64,
    collision_mask = {layers = {}}, selectable_in_game = true,
    collision_box = {{-0.1,-0.1},{0.1,0.1}},
    -- The icon is 54x37 px at scale 0.27; 0.32 tile encloses it at
    -- any rotation. The data-stage catalog exports this same hitbox margin
    -- for flight path clipping, so the ship stops outside planet images.
    selection_box = {{-0.32,-0.32},{0.32,0.32}},
    -- Invisible selection marker: the separately rotated rendering sprite is
    -- the visible craft. Keep this entity for hover and remote-view targeting.
    picture = {filename="__dynamic-starmap__/graphics/transparent.png",
      width=1,height=1},max_health = 1000000
  },
  {
    type = "sprite", name = "dsm-platform-parked-sprite",
    filename = "__core__/graphics/icons/starmap-platform-stacked-states.png",
    position = {0,0}, size = {54,54}
  },
  {
    type = "sprite", name = "dsm-platform-moving-sprite",
    filename = "__core__/graphics/icons/starmap-platform-moving-states.png",
    position = {0,0}, size = {54,37}
  },
  {
    type = "custom-input", name = "dsm-focus-target", key_sequence = "mouse-button-1",
    consuming = "none", include_selected_prototype = true
  },
  {
    type = "custom-input", name = "dsm-remote-target", key_sequence = "mouse-button-2",
    consuming = "none", include_selected_prototype = true
  },
  {
    type = "custom-input", name = "dsm-toggle", key_sequence = "SHIFT + M",
    alternative_key_sequence = "CONTROL + SHIFT + M",
    consuming = "none"
  },
  {type="custom-input",name="dsm-toggle-cards",key_sequence="SHIFT + I",consuming="game-only"}
})

