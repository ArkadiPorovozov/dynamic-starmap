# Dynamic Starmap · публичный API 0.17.3

Карта — отдельная поверхность `dsm-space`. API меняет **только Dynamic Starmap**, не переопределяя нативные `planet`, `space-location`, `space-connection`, PlanetsLib или реальные космические платформы. Добавлять графические прототипы/тела можно только на стадии данных; runtime API управляет существующей картой.

## 1. Data stage — объекты, оформление и орбиты

Добавьте в `info.json` своей модификации зависимость `dynamic-starmap >= 0.17.3`. В `data-updates.lua` (или `data-final-fixes.lua` до завершения `dynamic-starmap`) используйте:

```lua
local Map = require("__dynamic-starmap__/api")

-- У существующей планеты: знак +1 = по часовой стрелке,
-- -1 = против часовой стрелки, если смотреть на карту сверху.
Map:update{
  name="nauvis", orbit_direction=-1,
  tidal_lock=false, spin_direction=1, spin=3600
}

-- Полностью пользовательское тело. Это ОБЪЕКТ КАРТЫ,
-- не настоящая планета Space Age и не поверхность для посадки.
Map:define{
  name="my-mod-beacon", parent="nauvis", radius=12,
  phase=0.25, period=48000, orbit_direction=-1,
  size=2, icon="__my-mod__/graphics/beacon.png", icon_size=128,
  localised_name={"my-mod.beacon"},
  description={"my-mod.beacon-description"},
  tidal_lock=false, spin_direction=-1, spin=2400,
  draw_orbit=true, color={r=0.35,g=0.35,b=0.4,a=1},
  contents={"iron-ore"}, properties={gravity=5}
}

Map:configure{stars=120, moon_scale=0.65, update_ticks_active=1}
```

| Метод | Назначение |
|---|---|
| `Map:define(node или {node,…})` | Добавить уникальное тело **только** на карту. Обязательны `name` и положительный `radius`; `parent` — имя тела карты, по умолчанию Солнце. Не добавляет ванильную локацию, маршрут или реальную поверхность. |
| `Map:remove_custom(name)` | Удалить ранее определённое пользовательское тело и его настройки до компиляции каталога. |
| `Map:extend(value)` | Добавить переопределение существующей локации; повторное переопределение через `extend` — ошибка. |
| `Map:update(value)` | Обновить отдельные поля переопределения существующей планеты или пользовательского тела. |
| `Map:hide(name)`, `Map:show(name)` | Скрыть/вернуть тело карты (не изменяет прототип Space Age). Солнце скрыть нельзя. |
| `Map:configure(settings)` | Общие параметры карты: `stars`, `orbit_gap`, `moon_scale`, `body_size_multiplier`, `orbit_color`, `planet_angular_speed`, `moon_angular_speed`, `time_scale`, `show_platforms`, `static_planet_entities` и др. |

Параметры узла: `parent`, `radius` (тайлы; заданный явно радиус не получает автоматическую прибавку +5), `phase` (начальная доля оборота, 0 = вверх), `period` (тики одного оборота, 0 = неподвижно), `orbit_direction` (`1` по часовой, `-1` против), `tidal_lock` (по умолчанию `true`, одна сторона повернута к Солнцу), `spin` (тики собственного оборота) и `spin_direction` (`1` или `-1`; действует при `tidal_lock=false`), `size`, `icon`, `icon_size`, `localised_name`, `description`, `contents`, `properties`, `draw_orbit`, `color`, `static_picture`, `hidden`. При приливной синхронизации `spin_direction` не меняет ориентацию картинки: она всегда смотрит на Солнце. Прототип для Солнца остаётся **картинкой entity**.

Смена орбитального направления не перемещает планету в начальный момент (`clock=0`), а меняет знак последующего движения. Для лун знак применяется относительно родителя.

## 2. Runtime — чтение и управление

В `control.lua` другого мода вызывайте `remote.call("dynamic_starmap", METHOD, ...)`. Доступные методы:

| Метод | Результат / действие |
|---|---|
| `get_catalog()`, `get_node(name)`, `get_routes()` | Копии финального каталога / узла / реальных соединений. Менять возвращённые таблицы безопасно — карта не изменится. |
| `get_surface()`, `get_entity(name)` | `LuaSurface` / живая `LuaEntity` или `nil`. Проверяйте `.valid` после пересборки. |
| `get_position(name)` | Копия текущей мировой позиции `{x,y}` тела или `nil`. |
| `get_render_ids(name)` | ID визуального спрайта, подписи, орбиты; могут поменяться после `rebuild`. Для Солнца `sprite=nil`, оно entity. |
| `get_platform_marks()` | Копии `{force,index,moving,position}` по ключам `forceIndex:platformIndex`. Не изменяет настоящие платформы. |
| `get_state()` | `{paused,time_scale,clock,pending_clear,rebuild_error,viewers}`. |
| `get_orbit(name)` | Текущие `parent,radius,phase,period,orbit_direction,spin_direction,tidal_lock`. |
| `open(player_index)`, `close(player_index)`, `toggle(player_index)` | Управление камерой карты. `open` фокусируется на Солнце; `close` возвращает к персонажу на его поверхности. |
| `focus(player_index,name)` | Перевести камеру карты к телу. Не телепортирует персонажа. |
| `focus_position(player_index,{x=...,y=...})` | Перевести камеру в произвольную точку карты (координаты в пределах ±1 млн). |
| `focus_platform(player_index,force_index,platform_index)` | Перевести камеру к значку существующей платформы своей силы. |
| `set_paused(bool)`, `set_time_scale(number)` | Пауза и множитель скорости `0..100`. |
| `set_orbit(name,{radius=?,phase=?,period=?,orbit_direction=?,spin_direction=?,tidal_lock=?})` | Сохранить runtime-переопределение орбиты, пересобрать визуальные объекты на той же поверхности. Направления — строго `1` или `-1`; звезда недоступна. |
| `reset_orbit(name)` | Удалить runtime-переопределение, вернуть data-stage значения. |
| `rechart(force_name)` | Повторно открыть центральную область выбранной силе. |
| `rebuild()` | Пересобрать объекты без очистки чанков. Возвращает поверхность или `false`, если идёт очистка. |
| `restore()` | Восстановить карту при её удалении; возвращает `true/false`. |
| `regenerate()` | Запустить полную **асинхронную** очистку: возвращает `true`, когда она начата, а не когда закончена. Следите за `get_state().pending_clear`. |
| `set_annotation(id,spec)` | Создать/обновить сохраняющуюся текстовую или графическую аннотацию. |
| `remove_annotation(id)`, `get_annotations()` | Удалить по ID / получить копию определений. |

Примеры runtime:

```lua
local api="dynamic_starmap"
remote.call(api,"set_orbit","nauvis",{orbit_direction=-1,radius=80})
remote.call(api,"focus_position",game.player.index,{x=0,y=0})
remote.call(api,"set_annotation","my-mod:signal",{
  kind="sprite",position={x=15,y=-10},
  sprite="item/iron-plate",scale=0.6,orientation=0.25,
  forces={"player"}
})
remote.call(api,"set_annotation","my-mod:label",{
  kind="text",position={x=15,y=-8},text={"my-mod.signal"},
  scale=0.7,color={r=1,g=0.8,b=0.3,a=1}
})
```

У аннотации обязательно `kind="sprite"` со штатным `SpritePath` либо `kind="text"` с текстом/LocalisedString и `{x,y}`; опциональны `scale` (0..20), `orientation` для спрайта, `color`/`alignment` для текста, `forces` — массив имён сил. ID используйте с префиксом своего мода (`"my-mod:..."`), чтобы не пересечься с другим модом. Аннотации не являются кликабельными объектами; для кликабельного тела используйте `Map:define` на data stage. Состояние аннотаций и орбитальных override сохраняется в `storage` и переживает пересборку. Runtime API не регистрирует Lua-функции обратного вызова и не обещает сохранность сырых `LuaEntity`/render-ID после пересборки.

**Ограничения:** добавление/удаление прототипов, текстур и новых настоящих локаций во время игры невозможно — это data stage. API не меняет Space Age/PlanetsLib, реальные поверхности, маршруты или состояние космических платформ. Команда `/dsm-regenerate` закрывает просмотр и завершает сборку только после `on_surface_cleared`; до этого `open/rebuild` блокируются.
