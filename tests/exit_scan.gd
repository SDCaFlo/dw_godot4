extends Node
## Plays the trigger-cell exits that show a short scene before their WARP_TO (PLANS.md "exits"
## backlog) in the real field scene (autoloads, NPCs, camera):
##   godot --headless --fixed-fps 60 --path . res://tests/exit_scan.tscn
## For each exit: the map is entered through the field's debug map change (its MAPHEAD setup
## runs), the tamer is put on a cell of the exit's trigger (✕ pressed for cells 80-109, and while
## a script runs, for its text boxes), then the frames until the map changes and the tamer is free
## again are counted. A section that ends without warping (a first visit's scene) gets the tamer
## put back on the cell, up to VISITS times. Prints each exit's result and the opcodes reported
## unported on the way; exits 1 if one fails.

## [map, trigger cell, setup]. Setup: "values" script values set once the map is ready, "triggers"
## set and "clear" cleared then, "spawn" the map's exit to enter by (0 by default), "between" a cell crossed before each revisit (one that resets the first visit's
## trigger), "warp" false when the exit must not warp with that setup (the scene still has to end).
const EXITS := [
	# 1st visit: "I felt the ground move" (sets 141, 143); cell 0x36 clears 143; 2nd visit: the fall.
	["GCAN08_1", 0x35, {"between": 0x36}],
	["YAKA23", 0x52, {}], ["YAKA24", 0x51, {}], ["OGRE11", 0x33, {"spawn": 1}], ["TOPN01", 0x36, {}],
	["GCAN10", 0x51, {}], ["FACT01", 0x51, {}],
	# Toy Town: the door opens once trigger 349 is set, else "It won't open."
	["OMOC04", 0x51, {"triggers": [349]}], ["OMOC04", 0x51, {"clear": [349], "warp": false}],
	# Toy Town's door rooms: script value 110 (STORE_RANDOM 0-2 on entry, 3 all open) picks the door
	# that opens (0x51 + value); the others play a trap scene.
	["OMOC05", 0x51, {"values": {110: 0}}], ["OMOC05", 0x52, {"values": {110: 1}}],
	["OMOC05", 0x53, {"values": {110: 2}}], ["OMOC05", 0x51, {"values": {110: 1}, "warp": false}],
	["OMOC06", 0x51, {"values": {110: 0}}], ["OMOC06", 0x52, {"values": {110: 1}}],
	["OMOC06", 0x53, {"values": {110: 2}}], ["OMOC06", 0x52, {"values": {110: 2}, "warp": false}],
	["OMOC07", 0x51, {"values": {110: 0}}], ["OMOC07", 0x52, {"values": {110: 1}}],
	["OMOC07", 0x53, {"values": {110: 2}}], ["OMOC07", 0x53, {"values": {110: 0}, "warp": false}],
]
## Game frames an exit may take before it counts as stuck.
const TIMEOUT := 1500
## Times the tamer enters the cell before the exit counts as not warping.
const VISITS := 3

var _field: Node
var _index := -1
## 0 entering the map, 1 on the exit's cell, 2 on the "between" cell.
var _phase := 0
var _start_frame := 0
var _between_frame := 0
var _warp_frame := -1
var _visits := 0
## The exit's section has run since the tamer was put on the cell.
var _ran := false
var _start_position := Vector3.ZERO
var _moved := 0.0
var _unported := []
var _unported_before := 0
var _results := []
var _failed := false


func _ready() -> void:
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	_field._interpreter.unported.connect(func(_op, what): _unported.append(what))
	_next()


func _next() -> void:
	_index += 1
	if _index >= EXITS.size():
		for line in _results:
			print(line)
		print("unported on the way: ", _unported if not _unported.is_empty() else "none")
		get_tree().quit(1 if _failed else 0)
		return
	_phase = 0
	_visits = 0
	_unported_before = _unported.size()
	_field._debug_change_map(EXITS[_index][0], EXITS[_index][2].get("spawn", 0))
	_start_frame = GameLoop.frame_count


func _process(_delta: float) -> void:
	if _index >= EXITS.size():
		return
	var map: String = EXITS[_index][0]
	var section: int = EXITS[_index][1]
	var setup: Dictionary = EXITS[_index][2]
	var tamer: Tamer = _field._tamer
	var ctx: ScriptContext = _field._script_ctx
	var frames := GameLoop.frame_count - _start_frame
	if frames > TIMEOUT:
		_finish("%s 0x%X: stuck in phase %d on %s (fade in %d, warp at %d, script paused %s, tamer state %d, waiting 0x%02X at %d)" % [
				map, section, _phase, _screen_file(), _field._fade.in_current, _warp_frame, ctx.is_paused, tamer.state, ctx.active_instruction, ctx.pointer], true)
		return
	match _phase:
		0:
			# The map's entry scene, if any, with its text boxes.
			if frames % 4 == 0 and not ctx.is_paused:
				GameLoop.press("pad_cross")
			if _screen_file() != map or not ctx.is_paused or tamer.state != Tamer.STATE_FREE or _field._fade.in_current <= 0x13:
				return
			if _trigger_tile(section).x < 0:
				_finish("%s 0x%X: no cell with trigger %d" % [map, section, section], true)
				return
			for value in setup.get("values", {}):
				GameState.set_script_value(value, setup["values"][value])
			for trigger in setup.get("triggers", []):
				GameState.set_trigger(trigger)
			for trigger in setup.get("clear", []):
				GameState.clear_trigger(trigger)
			_place_on(_trigger_tile(section))
			_start_position = tamer.position
			_visits = 1
			_ran = false
			_moved = 0.0
			_warp_frame = -1
			_start_frame = GameLoop.frame_count
			_phase = 1
		1:
			_moved = maxf(_moved, tamer.position.distance_to(_start_position))
			if not ctx.is_paused:
				_ran = true
			if frames % 4 == 0 and (not ctx.is_paused or (section >= 80 and _warp_frame < 0)):
				GameLoop.press("pad_cross")
			var screen := _screen_file()
			if _warp_frame < 0 and screen != map:
				_warp_frame = frames
			var settled := ctx.is_paused and tamer.state == Tamer.STATE_FREE
			if _warp_frame >= 0 and settled:
				_finish("%s 0x%X: visit %d warps after %d frames to %s (tamer moved %d before), free at %d%s" % [map,
						section, _visits, _warp_frame, screen, _moved, frames, _new_unported()],
						not setup.get("warp", true))
			elif _warp_frame < 0 and _ran and settled:
				# The section ended on this map.
				if not setup.get("warp", true):
					_finish("%s 0x%X with %s: no warp as expected, the scene ends at %d (tamer moved %d)%s" % [map,
							section, setup, frames, _moved, _new_unported()], false)
				elif _visits >= VISITS:
					_finish("%s 0x%X: no warp after %d visits" % [map, section, _visits], true)
				else:
					# Enter the cell again (crossing the "between" cell first).
					_visits += 1
					_ran = false
					if setup.has("between"):
						_place_on(_trigger_tile(setup["between"]))
						_between_frame = GameLoop.frame_count
						_phase = 2
					else:
						_place_on(_trigger_tile(section))
		2:
			# On the "between" cell: its section runs, then back to the exit's cell.
			if frames % 4 == 0 and not ctx.is_paused:
				GameLoop.press("pad_cross")
			if GameLoop.frame_count - _between_frame > 10 and ctx.is_paused and tamer.state == Tamer.STATE_FREE:
				_place_on(_trigger_tile(section))
				_phase = 1


func _finish(line: String, failed: bool) -> void:
	_results.append(("FAIL " if failed else "ok   ") + line)
	_failed = _failed or failed
	if failed:
		# Like tests/test_script.gd's _force_end: the next exit starts from a free tamer.
		var ctx: ScriptContext = _field._script_ctx
		ctx.is_paused = true
		ctx.map_change = 0
		ctx.stack.clear()
		_field._textboxes.close_all_textboxes()
		_field._tamer.set_state(Tamer.STATE_FREE)
	_next()


func _new_unported() -> String:
	var new_unported := _unported.slice(_unported_before)
	return "" if new_unported.is_empty() else ", unported: " + ", ".join(new_unported)


func _place_on(tile: Vector2i) -> void:
	var tamer: Tamer = _field._tamer
	var at := FieldMap.tile_centre(tile)
	tamer.position = Vector3(at.x, tamer.position.y, -at.y)


func _trigger_tile(trigger: int) -> Vector2i:
	var map: FieldMap = _field._field
	for tz in FieldMap.GRID:
		for tx in FieldMap.GRID:
			if map._cell(tx, tz) == trigger:
				return Vector2i(tx, tz)
	return Vector2i(-1, -1)


## The current map's file name (GameState keeps its key).
func _screen_file() -> String:
	return str(GameData.map(GameState.state["world"]["screen"]).get("file", ""))
