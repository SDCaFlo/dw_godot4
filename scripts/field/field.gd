@tool
extends Node
## Field scene: one map, the tamer walking on it, warps between maps.
##
## Debug keys: [ / ] previous / next map, T time of day, L text language, H toggle the help line.
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
## 0 day, 1 evening, 2 night (maps with one palette always show the day).
@export_enum("day", "evening", "night") var time_of_day := 0:
	set(value):
		time_of_day = value
		_refresh_preview()
## Editor only: show the map in the editor viewports.
@export var editor_preview := true:
	set(value):
		editor_preview = value
		_refresh_preview()

var _maps: PackedStringArray
## Triggers are ignored until the tamer leaves the cell it arrived on.
var _arrival_trigger := 0

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
	_field.time_of_day = time_of_day
	_enter(start_map if start_map in _maps else _maps[0], start_spawn)


func _enter(map_name: String, spawn: int) -> void:
	if not _field.load_map(map_name):
		return
	_tamer.place(_field.spawn(clampi(spawn, 0, _field.data["spawns"].size() - 1)))
	_field.follow(_tamer.global_position)
	_arrival_trigger = _field.tile_trigger(_tamer.position)
	_update_label()


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
			_field.set_time_of_day((_field.time_of_day + 1) % 3)
			_update_label()
		KEY_L:
			var languages := GameData.LANGUAGES
			GameData.set_language(languages[(languages.find(GameData.language) + 1) % languages.size()])
			_update_label()
		KEY_H:
			_label.visible = not _label.visible


func _update_label() -> void:
	var times := ["day", "evening", "night"]
	var time: String = times[_field.time_of_day] if _field.palette_count() > 1 else "no time cycle"
	_label.text = "%s  %s\narrows move, shift run, [ ] map, T time, L language, H hide" % [_map_label(), time]


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
