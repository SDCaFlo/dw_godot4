extends Node
## Field scene: one map, the tamer walking on it, warps between maps.
##
## Debug keys: [ / ] previous / next map, T time of day, H toggle the help line.

@export var start_map := "MAYO04A"
@export var start_spawn := 0

var _maps: PackedStringArray
## Triggers are ignored until the tamer leaves the cell it arrived on.
var _arrival_trigger := 0

@onready var _field: FieldMap = $World/SubViewport/FieldMap
@onready var _tamer: Tamer = $World/SubViewport/Tamer
@onready var _label: Label = $Hud/Label


func _ready() -> void:
	_maps = DirAccess.get_directories_at(PorterAssets.path("maps"))
	_tamer.field = _field
	if _maps.is_empty():
		_label.text = "No maps in %s.\nRun: python -m dwporter convert maps mmd_files" % PorterAssets.path("maps")
		return
	_enter(start_map if start_map in _maps else _maps[0], start_spawn)


func _enter(map_name: String, spawn: int) -> void:
	if not _field.load_map(map_name):
		return
	_tamer.place(_field.spawn(spawn))
	_field.follow(_tamer.global_position)
	_arrival_trigger = _field.tile_trigger(_tamer.position)
	_update_label()


func _process(_delta: float) -> void:
	if _field.data.is_empty():
		return
	var trigger := _field.tile_trigger(_tamer.position)
	if trigger == _arrival_trigger:
		return
	_arrival_trigger = 0
	var warp := _field.warp_for_trigger(trigger)
	if not warp.is_empty():
		_enter(warp["map_name"], int(warp["spawn"]))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _maps.is_empty():
		return
	match event.keycode:
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			var step := 1 if event.keycode == KEY_BRACKETRIGHT else -1
			var index := (_maps.find(_field.map_name) + step + _maps.size()) % _maps.size()
			_enter(_maps[index], 0)
		KEY_T:
			_field.set_time_of_day((_field.time_of_day + 1) % 3)
			_update_label()
		KEY_H:
			_label.visible = not _label.visible


func _update_label() -> void:
	var times := ["day", "evening", "night"]
	var time: String = times[_field.time_of_day] if _field.palette_count() > 1 else "no time cycle"
	_label.text = "%s  %s\narrows move, shift run, [ ] map, T time, H hide" % [_field.display_name(), time]
