@tool
extends Node
## Field scene: one map, the tamer walking on it, warps between maps, the game clock
## (specs/clock.md) with its HUD and the day / evening / night fades.
##
## Debug keys: [ / ] previous / next map, T one hour later, L text language, H toggle the help line.
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
## Editor only: show the map in the editor viewports.
@export var editor_preview := true:
	set(value):
		editor_preview = value
		_refresh_preview()

var _maps: PackedStringArray
## Triggers are ignored until the tamer leaves the cell it arrived on.
var _arrival_trigger := 0
var _clock: Clock
var _partner: Partner
var _care: Care
var _fade: Fade
var _poop: PoopPiles
var _message := ""
var _message_frames := 0

@onready var _field: FieldMap = $World/SubViewport/FieldMap
@onready var _tamer: Tamer = $World/SubViewport/Tamer
@onready var _label: Label = $Hud/Label
@onready var _camera: Camera3D = $World/SubViewport/FieldMap/Camera3D
@onready var _background: Sprite2D = $Background/Sprite2D


func _ready() -> void:
	_maps = DirAccess.get_directories_at(Content.path("maps"))
	_tamer.field = _field
	if Engine.is_editor_hint():
		_refresh_preview()
		return
	if _maps.is_empty():
		_label.text = "No maps in %s.\nRun: python -m dwporter convert maps mmd_files" % Content.path("maps")
		return
	# The partner ticks before the clock, as in the original's object list (specs/care.md §2.1).
	_start_partner()
	_start_clock()
	_start_care()
	_enter(start_map if start_map in _maps else _maps[0], start_spawn)


## initializePartner's model part: the partner of the game state follows the tamer
## (specs/partner.md).
func _start_partner() -> void:
	_partner = Partner.new()
	_partner.name = "Partner"
	$World/SubViewport.add_child(_partner)
	_partner.field = _field
	_partner.tamer = _tamer
	_partner.game_state = GameState
	if debug_partner != "":
		GameState.state["partner"]["digimon"] = debug_partner
	if not _partner.load_digimon(GameData, GameState.state["partner"]["digimon"]):
		_partner.queue_free()
		_partner = null
		return
	GameLoop.frame.connect(_partner.tick)


## The care rules and the fade they use (specs/care.md §3). A new game's partner gets
## initializePartner's care values; a loaded game keeps its own.
func _start_care() -> void:
	_fade = Fade.new()
	_fade.name = "Fade"
	_fade.clock = _clock
	GameLoop.frame.connect(_tick_message)
	if _partner != null:
		_care = Care.new()
		_care.name = "Care"
		add_child(_care)
		_care.game_state = GameState
		_care.data = GameData
		_care.clock = _clock
		_care.field = _field
		_care.partner = _partner
		_care.tamer = _tamer
		_care.fade = _fade
		_care.message.connect(_show_message)
		_care.script_requested.connect(_on_script_requested)
		_partner.care = _care
		_partner.clock = _clock
		_partner.fade = _fade
		if GameState.state["boot_mode"] == GameState.BOOT_NEW_GAME or debug_partner != "":
			_care.initialize_partner()
		_start_care_visuals()
	# Last in the HUD and in the frame: the fade covers everything (a render object in the original).
	$Hud.add_child(_fade)
	GameLoop.frame.connect(_fade.tick)


## The care on screen (specs/care.md §3.2): happiness / discipline bars next to the clock, the
## condition bubbles over the partner, the poop piles on the map.
func _start_care_visuals() -> void:
	var bars := StatusBars.new()
	bars.name = "StatusBars"
	bars.clock = _clock
	bars.care = _care
	bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	$Hud.add_child(bars)
	var bubbles := ConditionBubbles.new()
	bubbles.name = "ConditionBubbles"
	bubbles.partner = _partner
	bubbles.camera = _camera
	bubbles.field = _field
	bubbles.data = GameData
	bubbles.set_anchors_preset(Control.PRESET_FULL_RECT)
	$Hud.add_child(bubbles)
	_care.bubble_shown.connect(bubbles.show_bubble)
	_care.butterfly_changed.connect(_on_butterfly_changed.bind(bubbles))
	_poop = PoopPiles.new()
	_poop.name = "PoopPiles"
	_poop.game_state = GameState
	_poop.partner = _partner
	$World/SubViewport.add_child(_poop)
	_care.poop_changed.connect(_poop.refresh)


## setButterfly removes the bubble first (handleConditionBubble, partner_impl.c:1590). The
## butterfly itself (butterfly.c) isn't drawn yet.
func _on_butterfly_changed(shown: bool, bubbles: ConditionBubbles) -> void:
	if shown:
		bubbles.remove_current()


## Stand-in for script section 0x4DE (the partner collapses or dies; scripts milestone): the values
## partnerTickDying leaves (partner.c:674-676), then the script is over.
func _on_script_requested(section: int) -> void:
	var care: Dictionary = GameState.state["partner"]["care"]
	care["remaining_lifetime"] = 360
	care["sickness_timer"] = 0
	care["injury_timer"] = 0
	_care.script_running = false
	_show_message("script 0x%X (partner collapses): not ported yet" % section)


## Stand-in for the text box: a message in the help line for a few seconds.
func _show_message(text: String) -> void:
	_message = text
	_message_frames = 100
	_update_label()


func _tick_message() -> void:
	if _message_frames > 0:
		_message_frames -= 1
		if _message_frames == 0:
			_message = ""
			_update_label()


## addClock (clock.c:90): the clock and its HUD run while the field is played.
func _start_clock() -> void:
	_clock = Clock.new()
	_clock.name = "Clock"
	add_child(_clock)
	_clock.time_of_day_changed.connect(_field.set_time_of_day)
	_clock.daytime_transition.connect(_field.start_daytime_transition)
	_clock.minute_passed.connect(_update_label)
	var hud := ClockHud.new()
	hud.name = "ClockHud"
	hud.clock = _clock
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	$Hud.add_child(hud)
	# The clock takes the top-left corner: the help line moves to the bottom.
	_label.offset_top = 200
	_label.offset_bottom = 238
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	GameLoop.frame.connect(_field.tick_daytime_transition)


func _enter(map_name: String, spawn: int) -> void:
	if not _field.load_map(map_name):
		return
	var spawn_point := _field.spawn(clampi(spawn, 0, _field.data["spawns"].size() - 1))
	_tamer.place(spawn_point)
	if _partner != null:
		_partner.place_for_spawn(spawn_point)
	_field.follow(_tamer.global_position)
	_arrival_trigger = _field.tile_trigger(_tamer.position)
	if _clock != null:
		_record_map(map_name, spawn)
	_update_label()


## CURRENT_SCREEN / CURRENT_EXIT (and the previous ones) in the game state, then updateTimeOfDay
## for the new map (setupMap, map.c:4244).
func _record_map(map_name: String, spawn: int) -> void:
	var world: Dictionary = GameState.state["world"]
	var id := GameData.map_id(map_name)
	if id >= 0:
		world["previous_screen"] = world["screen"]
		world["screen"] = GameData.key_of("systems/maps", id)
	world["previous_exit"] = world["exit"]
	world["exit"] = spawn
	_clock.map_has_time_of_day = id < 0 or not GameData.map(id).get("no_time_of_day", false)
	_clock.active = true
	_clock.update_time_of_day()
	if _care != null:
		var setup: Dictionary = _field.data["setup"]
		_care.set_area_response(setup.get("liked_regions", []), setup.get("disliked_regions", []))
	if _poop != null:
		_poop.refresh()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _field.data.is_empty():
		return
	var trigger := _field.tile_trigger(_tamer.position)
	if trigger == _arrival_trigger:
		return
	_arrival_trigger = 0
	var warp := _field.warp_for_trigger(trigger)
	if not warp.is_empty():
		_enter(warp["map_name"], int(warp["spawn"]))


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not event.is_pressed() or event.is_echo() or _maps.is_empty():
		return
	match event.keycode:
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			var step := 1 if event.keycode == KEY_BRACKETRIGHT else -1
			var index := (_maps.find(_field.map_name) + step + _maps.size()) % _maps.size()
			_enter(_maps[index], 0)
		KEY_T:
			var clock: Dictionary = GameState.state["clock"]
			# % 24: advanceToTime starts a new day only for an earlier hour (specs/clock.md §2.4).
			_clock.advance_to_time((clock["hour"] + 1) % 24, clock["minute"])
		KEY_L:
			var languages := GameData.LANGUAGES
			GameData.set_language(languages[(languages.find(GameData.language) + 1) % languages.size()])
			_update_label()
		KEY_H:
			_label.visible = not _label.visible
		KEY_Z:
			_menu_sleep()


## The menu's "Sleep" (handleGameMenuSelection case 6, game_menu.c:2178): only while it is enabled
## (the partner is sleepy) and both are free. Debug key until the menus exist.
func _menu_sleep() -> void:
	if _care == null or not _care.sleep_enabled or _partner.state != Partner.STATE_NORMAL \
			or _tamer.state != Tamer.STATE_FREE:
		_show_message("Sleep: only while the partner is sleepy")
		return
	_partner.set_state(Partner.STATE_SLEEP)
	_clock.running = true


func _update_label() -> void:
	var time: String = ["day", "evening", "night"][_field.time_of_day] if _field.palette_count() > 1 else "no time cycle"
	if _clock != null:
		var clock: Dictionary = GameState.state["clock"]
		if _clock.map_has_time_of_day:
			time = {Clock.TIME_DAY: "day", Clock.TIME_EVENING: "evening", Clock.TIME_NIGHT: "night"}[_clock.current_time_of_day]
		time = "year %d day %d %02d:%02d (%s)" % [clock["year"], clock["day"], clock["hour"], clock["minute"], time]
	var help := _message if _message != "" else "arrows move, shift run, [ ] map, T +1 hour, Z sleep, L language, H hide"
	_label.text = "%s\n%s\n%s" % [_map_label(), time, help]


## Map name from the data porter (MAP_ENTRIES + map.yaml) in the GameData language; the asset
## porter's English name if the data output is missing (and in the editor).
func _map_label() -> String:
	if Engine.is_editor_hint():
		return _field.display_name()
	var id := GameData.map_id(_field.map_name) if GameData.available() else -1
	if id < 0:
		return _field.display_name()
	var area := GameData.localize(GameData.map(id).get("name")).strip_edges()
	if area == "":
		return _field.display_name()
	return "%s (%s, %s)" % [area, _field.map_name, GameData.language]


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
	_enter(start_map, start_spawn)


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
