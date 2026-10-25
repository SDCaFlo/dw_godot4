@tool
extends Node
## Field scene: one map, the tamer walking on it, warps between maps, the game clock
## (specs/clock.md) with its HUD and the day / evening / night fades.
##
## The root keeps the start order, the hand-over of references between its hosts (Systems/*:
## Entities, MapSession, ScriptHost, CareHost, ClockHost; Debug) and the frame order: its one
## connection to GameLoop.frame, _frame, ticks every system in the original's order
## (specs/scenes.md §3, §4.2). The debug keys are in DebugHost.
##
## In the editor the scene previews start_map / start_spawn / time_of_day from the porter output
## (pick them in the Inspector). The preview is only in memory: before each save it is cleared
## from the saved nodes, so no game content is written into field.tscn.

@export var start_map := "MAYO04A":
	set(value):
		start_map = value
		_refresh_preview()
@export var start_spawn := 0:
	set(value):
		start_spawn = value
		_refresh_preview()
## Editor preview only: 0 day, 1 evening, 2 night (maps with one palette always show the day).
## In the game the clock decides.
@export_enum("day", "evening", "night") var time_of_day := 0:
	set(value):
		time_of_day = value
		_refresh_preview()
## Debug: a Digimon key (e.g. "dw1:greymon") to use as the partner instead of the game state's.
@export var debug_partner := ""
## The 3D view's resolution as a multiple of 320 x 240 (ISSUES.md I-3): 1 is the PSX's, more is
## an emulator-like upscaling (the background and the 2D stay at the PSX resolution). The
## debugger changes it while playing.
@export_range(1, 4) var render_scale := 4
## The text and windows' upscaling filter (PsxUiFilter, ISSUES.md D-3): Scale4x like an emulator's
## 2D filter; off, the PSX's square pixels. The debugger changes it while playing.
@export var ui_filter := true
## Debug: open the debugger window (F1 toggles it).
@export var debug_window := true
## Editor only: show the map in the editor viewports.
@export var editor_preview := true:
	set(value):
		editor_preview = value
		_refresh_preview()

var _maps: PackedStringArray

@onready var _field: FieldMap = $World/SubViewport/FieldMap
@onready var _tamer: Tamer = $World/SubViewport/Tamer
@onready var _label: Label = $Hud/Label
@onready var _camera: Camera3D = $World/SubViewport/FieldMap/Camera3D
@onready var _background: Sprite2D = $World/SubViewport/Background/Sprite2D
@onready var _world: SubViewport = $World/SubViewport
@onready var _hud: CanvasLayer = $Hud
## The hosts (specs/scenes.md §4.2).
@onready var entities: EntityHost = $Systems/Entities
@onready var map_session: MapSession = $Systems/MapSession
@onready var scripts: ScriptHost = $Systems/ScriptHost
@onready var care_host: CareHost = $Systems/CareHost
@onready var clock_host: ClockHost = $Systems/ClockHost
@onready var menu_host: MenuHost = $Systems/MenuHost
@onready var debug: DebugHost = $Debug


func _ready() -> void:
	_maps = DirAccess.get_directories_at(Content.path("maps"))
	_tamer.field = _field
	map_session.world = _world
	map_session.field_map = _field
	map_session.tamer = _tamer
	debug.label = _label
	debug.field_map = _field
	map_session.map_loaded.connect(debug.on_map_loaded)
	if Engine.is_editor_hint():
		_refresh_preview()
		return
	_tamer.animation_sound.connect(entities.play_sound)
	if _maps.is_empty():
		_label.text = "No maps in %s.\nRun: python -m dwporter convert maps mmd_files" % Content.path("maps")
		return
	# Debug: DW_START_HOUR=22 starts at that hour (render checks of the night, --write-movie).
	var env_hour := OS.get_environment("DW_START_HOUR")
	if env_hour.is_valid_int():
		GameState.state["clock"]["hour"] = clampi(int(env_hour), 0, 23)
	_start()
	GameLoop.frame.connect(_frame)
	set_render_scale(render_scale)
	PsxUiFilter.set_enabled(ui_filter)
	_start_debug()
	# Debug: DW_START_MAP=MAYO10 starts on another map (render checks, --write-movie).
	var env_map := OS.get_environment("DW_START_MAP")
	if env_map != "":
		start_map = env_map
	map_session.begin(start_map if start_map in _maps else _maps[0], start_spawn)


## The systems in the order the field starts them; each host gets the references it needs.
func _start() -> void:
	map_session.start_map_items()
	entities.world = _world
	entities.field_map = _field
	entities.tamer = _tamer
	entities.debug_partner = debug_partner
	entities.start_partner()
	entities.start_npcs()
	var partner := entities.partner
	clock_host.field_map = _field
	clock_host.start()
	var clock := clock_host.clock
	_hud.add_child(clock_host.hud)
	clock.minute_passed.connect(debug.update_label)
	scripts.field_map = _field
	scripts.camera = _camera
	scripts.tamer = _tamer
	scripts.partner = partner
	scripts.entities = entities.entities
	scripts.clock = clock
	scripts.map_items = map_session.map_items
	scripts.map_chests = map_session.map_chests
	scripts.start()
	scripts.message.connect(debug.show_message)
	entities.npc_autotalk.connect(scripts.npc_autotalk)
	care_host.world = _world
	care_host.field_map = _field
	care_host.camera = _camera
	care_host.tamer = _tamer
	care_host.partner = partner
	care_host.clock = clock
	care_host.text_area = scripts.text_area
	care_host.interpreter = scripts.interpreter
	care_host.debug_partner = debug_partner
	care_host.start()
	care_host.message.connect(debug.show_message)
	menu_host.tamer = _tamer
	menu_host.partner = partner
	menu_host.care = care_host.care
	menu_host.clock = clock
	menu_host.fade = care_host.fade
	menu_host.boxes = scripts.boxes
	menu_host.text_area = scripts.text_area
	menu_host.script_ctx = scripts.script_ctx
	menu_host.pad = GameLoop.pad
	menu_host.start()
	menu_host.message.connect(debug.show_message)
	map_session.partner = partner
	map_session.entities = entities.entities
	map_session.scripts = scripts
	map_session.clock = clock
	map_session.care_host = care_host
	# Map entry goes through MAPHEAD (specs/script.md §3): SET_SCRIPT loads the map, the end of
	# the setup section sets it up, script warps run the map change.
	if scripts.interpreter != null:
		scripts.interpreter.load_map = map_session.script_load_map
		scripts.interpreter.setup_map = map_session.script_setup_map
		scripts.interpreter.tick_map_change = map_session.tick_script_map_change
		_tamer.change_map = map_session.change_map
		_tamer.map_interaction = map_session.check_map_interaction


## The debug tools, then the HUD in its drawing order: the clock (added with it), the care bars and
## bubbles, the care panel, the windows in front of the HUD (their ordering-table layers 1-6 are in
## front of the HUD's 13-15), the fade over everything, the map name on the black screen.
func _start_debug() -> void:
	debug.maps = _maps
	debug.map_session = map_session
	debug.scripts = scripts
	debug.care_host = care_host
	debug.menu_host = menu_host
	debug.clock = clock_host.clock
	debug.render_scale = render_scale
	debug.ui_filter = ui_filter
	debug.show_window = debug_window
	debug.start()
	debug.window.render_scale_changed.connect(set_render_scale)
	debug.window.ui_filter_changed.connect(func(on: bool) -> void:
		ui_filter = on
		PsxUiFilter.set_enabled(on))
	for node: Node in [care_host.bars, care_host.bubbles, debug.panel, scripts.boxes, care_host.fade, scripts.map_name]:
		if node != null:
			_hud.add_child(node)


## One game frame, in the original's object order (specs/scenes.md §3): the tamer and the partner
## before the clock (specs/care.md §2.1), the NPCs after them (both skipped while the △ menu is open:
## IS_IN_MENU, specs/game_menu.md §2.6), the menu object; updateMapLightState and tickScript
## (specs/map_objects.md §2.4), the camera's pans after the script and the partner that start them
## (specs/camera.md §6), the overlay sprites where the map renders; the HUD; the UI boxes after
## everything that opens and closes them; the fade last.
func _frame() -> void:
	_tamer.tick()
	var in_menu := menu_host.is_open()
	entities.freeze_npcs(in_menu)
	if not in_menu:
		entities.tick_partner()
		entities.tick_npcs()
	menu_host.tick()
	clock_host.tick()
	if scripts.interpreter != null:
		map_session.update_map_light_state()
		scripts.tick_script()
		_field.tick_pan()
		_field.overlays.tick()
	debug.tick_message()
	care_host.tick_visuals(in_menu)
	debug.tick_panel()
	scripts.step_boxes()
	care_host.tick_fade()


## The 3D viewport at 320 x 240 x `value`, shown at the PSX size (ISSUES.md I-3). The background
## canvas layer, inside the viewport (field.tscn), is scaled with it; screen positions go through
## FieldMap.unproject.
func set_render_scale(value: int) -> void:
	render_scale = clampi(value, 1, 4)
	FieldMap.render_scale = render_scale
	var container: SubViewportContainer = $World
	container.stretch = false
	_world.size = Vector2i(FieldMap.SCREEN) * render_scale
	container.size = Vector2(_world.size)
	container.scale = Vector2.ONE / render_scale
	# Downscaling a bigger picture to the window: filtered, so the extra detail isn't lost to aliasing.
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if render_scale == 1 else CanvasItem.TEXTURE_FILTER_LINEAR
	($World/SubViewport/Background as CanvasLayer).scale = Vector2.ONE * render_scale


# --- Editor preview --------------------------------------------------------------------------

## Properties of saved nodes that the preview changes; reset to their class defaults before a save.
const _PREVIEW_PROPERTIES := {
	"background": ["texture", "position"],
	"camera": ["transform", "projection", "keep_aspect", "size", "frustum_offset", "near", "far"],
	"tamer": ["transform"],
	"label": ["text"],
}


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		clear_preview()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_refresh_preview()


func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	clear_preview()
	if not editor_preview or not start_map in _maps:
		return
	_field.time_of_day = time_of_day
	map_session.enter(start_map, start_spawn)


## Puts the saved nodes back to what field.tscn stores (the preview's map, doors and tamer model
## are unowned children and are never saved).
func clear_preview() -> void:
	var nodes := {"background": _background, "camera": _camera, "tamer": _tamer, "label": _label}
	for key in _PREVIEW_PROPERTIES:
		var node: Node = nodes[key]
		for property in _PREVIEW_PROPERTIES[key]:
			node.set(property, ClassDB.class_get_property_default_value(node.get_class(), property))
	_field.unload()


## start_map as a drop-down of the converted maps.
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "start_map":
		if _maps.is_empty():
			_maps = DirAccess.get_directories_at(Content.path("maps"))
		property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
		property["hint_string"] = ",".join(_maps)
