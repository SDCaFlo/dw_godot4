extends SceneTree
## The map objects (scripts/field/map_overlays.gd, the doors and blocked cells of field_map.gd)
## against specs/map_objects.md §2, on the porter output:
##   godot --headless --path . -s res://tests/test_map_objects.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false
var data: Node
var gs: Node
var map: FieldMap
var interp: ScriptInterpreter
var ctx: ScriptContext
var boxes: UIBoxes
var pad: Pad
var unported := []


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("maps/MAYO01/map.json"):
		print("SKIP: porter output missing")
		quit(0)
		return false
	_setup()
	_animation()
	_quads()
	_synthetic()
	_move_to()
	_script_ops()
	_doors()
	_rect()
	_lights()
	_snow()
	_teardown()
	print("%s: map object checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _setup() -> void:
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()
	map = FieldMap.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	map.add_child(camera)
	var doors := Node3D.new()
	doors.name = "Doors"
	map.add_child(doors)
	map.background = Sprite2D.new()
	root.add_child(map.background)
	root.add_child(map)
	map.load_map("MAYO01")
	boxes = UIBoxes.new()
	var area := TextArea.new(data, "en_us")
	ctx = ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	pad = Pad.new()
	var tb := TextBoxes.new(boxes, area, ctx, pad, data, gs)
	interp = ScriptInterpreter.new(ctx, ScriptFiles.new(), tb)
	interp.game_state = gs
	interp.data = data
	interp.field = map
	interp.pad = pad
	interp.unported.connect(func(_op, what): unported.append(what))


func _teardown() -> void:
	boxes.free()
	gs.free()
	data.free()


## A synthetic script section, loaded as script 500 (as tests/test_script.gd).
func _run(code: Array) -> void:
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code))
	interp.files._cache[500] = bytes
	interp.call_section(500, 1)


## A game frame: the script, then the overlays (where the map renders).
func _frame() -> void:
	interp.tick_script()
	map.overlays.tick()
	boxes.step()


func _ticks(n: int) -> void:
	for i in n:
		map.overlays.tick()


# --- §2.3: the animation ----------------------------------------------------------------------------

func _animation() -> void:
	var o := map.overlays
	_eq(o.instance_count(), 16, "MAYO01 has 16 instances")
	# Instance 7: sprites [-2, 5, 6, 7], times [120, 2, 6, 10]: a blank frame for 120 frames.
	var inst := o.instance(7)
	_eq([inst["frame"], o.is_drawn(7)], [0, false], "frame 0 is blank: not drawn")
	_ticks(119)
	_eq(o.instance(7)["frame"], 0, "still on the blank frame after 119 frames")
	_ticks(1)
	_eq([o.instance(7)["frame"], o.is_drawn(7)], [1, true], "frame 1 (sprite 5) on the 120th: drawn")
	# times [120, 2, 6, 10, 10, 10, 10] for sprites [-2, 5, 6, 7, 8, 9, 10], then -1.
	_ticks(2 + 6 + 10 + 10 + 10 + 9)
	_eq(o.instance(7)["frame"], 6, "the last frame (sprite 10)")
	_ticks(1)
	_eq(o.instance(7)["frame"], 0, "after the last frame (-1 next): frame 0 again")
	o.set_flag(7, MapOverlays.HIDDEN)
	_ticks(120)
	_eq([o.instance(7)["frame"], o.is_drawn(7)], [1, false], "hidden (flag 1): still animates, not drawn")
	o.reset_animation(7, 1)
	_eq([o.instance(7)["frame"], o.instance(7)["timer"]], [0, 0], "resetMapObjectAnimation: frame 0, timer 0")
	o.set_flag(7, 0)


## The quads: on the background pixels of their instance, at their sprite's depth.
func _quads() -> void:
	var o := map.overlays
	var orders_ok := true
	for k in o.instance_count():
		var order: int = o.instance(k)["order"]
		if not (order >= MapOverlays.ORDER_MIN and order <= MapOverlays.ORDER_MAX or order == MapOverlays.ORDER_BACK):
			orders_ok = false
	_eq(orders_ok, true, "every order between 0x23 and 0xFF6 (or 0xFFE)")
	var p := Vector2(123, 45)
	_eq((map.background_pixel(map.world_at_pixel(p, 3000.0)) - p).length() < 0.01, true,
			"world_at_pixel inverts background_pixel")
	_eq(is_equal_approx(map.view_depth(map.world_at_pixel(p, 3000.0)), 3000.0), true, "at the view depth asked")
	_ticks(120)
	var node: MeshInstance3D = o.instance(7)["node"]
	var obj: Dictionary = map.data["objects"][5]
	var corner := Vector2(o.instance(7)["x"], o.instance(7)["y"])
	var centre := corner + Vector2(int(obj["width"]), int(obj["height"])) / 2
	_eq([node.visible, (map.background_pixel(node.global_position) - centre).length() < 0.01], [true, true],
			"instance 7's quad: shown, centred on its background rectangle")


## A synthetic map: the u8 timer's wrap (times 0) and the C's frame list.
func _synthetic() -> void:
	var o := MapOverlays.new()
	o.field = map
	map.add_child(o)
	var objs := [{"pos3d": [0, 0, 0], "width": 8, "height": 8, "files": [], "transparency": 4}]
	var sprites := [0, 0, -1, -1, -1, -1, -1, -1]
	o.load({"objects": objs, "object_instances": [{"sprites": sprites, "times": [0, 1, 0, 0, 0, 0, 0, 0],
			"x": 0, "y": 0, "flag": 0}]})
	for i in 255:
		o.tick()
	_eq(o.instance(0)["frame"], 0, "times 0: still after 255 frames")
	o.tick()
	_eq(o.instance(0)["frame"], 1, "quirk: the u8 timer wraps to 0 on the 256th: the frame advances")
	o.queue_free()


# --- §2.4: MOVE_OBJECT_TO ---------------------------------------------------------------------------

func _move_to() -> void:
	var o := map.overlays
	var inst := o.instance(0)
	inst["x"] = 0
	inst["y"] = 50
	var xs := []
	var done := false
	while not done and xs.size() < 10:
		done = o.tick_move_to(0, 0, 3, 100, 50)
		xs.append(o.instance(0)["x"])
	_eq(xs, [33, 66, 99, 100], "100 px in 3 steps: 33 a frame (C division), past it snapped, done")
	_eq(o.instance(0)["y"], 50, "an axis with delta 0 is on its target at once")
	o.tick_move_to(0, 0, 2, 0, 50)
	_eq(o.instance(0)["x"], 50, "the slot's flag was cleared: a new move takes its own delta (-50)")
	o.tick_move_to(0, 0, 2, 0, 50)


func _script_ops() -> void:
	unported.clear()
	var o := map.overlays
	o.instance(1)["x"] = 0
	o.instance(1)["y"] = 0
	# MOVE_OBJECT_TO slot 2, instance 1, speed 9, steps 2, _, x 40, y 10; WAIT_FOR_ENTITY 0xCD
	# (slot 14 = 0xCB + 2); SET_OBJ_VISIBILITY _, 1, 1; END.
	_run([0x71, 2, 1, 9, 2, 0, 40, 0, 10, 0, 0x4A, 0xCD, 0x57, 0, 1, 1, 0xFE, 0])
	_frame()
	_eq([interp.movement[14], o.instance(1)["x"]], [ScriptInterpreter.MOVE_OBJECT_TO, 0],
			"MOVE_OBJECT_TO: slot 12 + 2 type 13, the wait")
	var xs := []
	for i in 4:
		_frame()
		xs.append(o.instance(1)["x"])
	_eq(xs, [20, 40, 40, 40], "it moves 20 a frame (40 / 2) and ends on its target")
	_eq(o.instance(1)["y"], 10, "y 5 a frame")
	_eq([interp.movement[14], o.instance(1)["flag"], ctx.is_paused], [ScriptInterpreter.FREE, 1, true],
			"the slot is freed, the wait ends, SET_OBJ_VISIBILITY 1 hides it")
	# CALL_ROUTINE 0x15 with script values 0xF7 / 0xF8 = 7 / 1.
	gs.set_script_value(0xF7, 7)
	gs.set_script_value(0xF8, 1)
	o.instance(7)["frame"] = 2
	_run([0x64, 0x15, 0xFE, 0])
	_frame()
	_eq(o.instance(7)["frame"], 0, "CALL_ROUTINE 0x15: resetMapObjectAnimation(value 0xF7, 0xF8)")
	_frame()
	_eq(unported, [], "nothing reported")
	o.set_flag(1, 0)


# --- §2.6: doors --------------------------------------------------------------------------------------

func _doors() -> void:
	# GCAN03: the canyon gates, models 22 (+30 x) and 23 (-30 x), slots 0 and 1; the script gives them
	# turns, one per frame, with one shared timer.
	map.load_map("GCAN03")
	var x0: int = map.door(0)["translation"].x
	var x1: int = map.door(1)["translation"].x
	var done := []
	for i in 10:
		done.append(map.tick_rotate_door(i % 2, 1))
	_eq([map.door(0)["translation"].x - x0, map.door(1)["translation"].x - x1], [150, -120],
			"quirk: one timer for both: gate 0 moves 5 frames (150), gate 1 only 4 (-120)")
	_eq(done, [false, false, false, false, false, false, false, false, false, true],
			"the 10th tick passes 9: done without moving")
	# Through the script: ROTATE_3D_OBJECT door 0, _, target 1 sets slot 11 type 12.
	_run([0x70, 0, 0, 1, 0x4A, 0xCA, 0xFE, 0])
	_frame()
	_eq([interp.movement[11], interp.movement_args[11]["target"]], [ScriptInterpreter.MOVE_ROTATE_DOOR, 1],
			"ROTATE_3D_OBJECT: slot 11 type 12")
	for i in 9:
		_frame()
	_eq(interp.movement[11], ScriptInterpreter.MOVE_ROTATE_DOOR, "9 ticks: still moving")
	_frame()
	_eq([interp.movement[11], ctx.is_paused], [ScriptInterpreter.FREE, true], "done on the 10th tick; the wait ends")
	# YAKA11A: slot 0 empty (table 1), slots 1-3 model 9, 4-5 model 10 (double doors).
	map.load_map("YAKA11A")
	_eq([map.door(0), map.door(1)["model"], map.door(4)["model"]], [{}, 9, 10],
			"the slots are kept: slot 0 empty, 1 model 9, 4 model 10")
	_eq(map.door(4)["nodes"].size(), 2, "model 10 is drawn twice (renderDoors' mirrored copy)")
	var vy: int = map.door(1)["rotation"].y
	var r := []
	for i in 33:
		map.tick_rotate_door(1, 1)
		r.append(map.door(1)["rotation"].y - vy)
	_eq([r[0], r[31]], [33, 33 * 32], "model 9 turns 33 a frame for 32 frames")
	_eq(r[32], 0, "and on the 33rd it is back on its direction (kept, §6)")
	_eq(map.tick_rotate_door(0, 1), false, "an empty slot never ends")
	# GCAN05: model 0x1A tilts on x, clamped to -0x400.
	map.load_map("GCAN05")
	var ends := 0
	for i in 20:
		if map.tick_rotate_door(0, 1):
			ends = i + 1
	_eq([map.door(0)["rotation"].x, ends], [-0x400, 20], "model 0x1A: -110 a frame down to -0x400, done on the 20th")


# --- §2.7: SET_RECT_IMPASSABLE ------------------------------------------------------------------------

func _cell_trigger(tx: int, tz: int) -> int:
	var centre := FieldMap.tile_centre(Vector2i(tx, tz))
	return map.tile_trigger(Content.psx_to_godot([centre.x, 0, centre.y]))


func _rect() -> void:
	map.load_map("MAYO08A")
	var before := _cell_trigger(23, 20)
	# SET_RECT_IMPASSABLE _, x 22, z 16, w 3, h 12 (script 10's broken bridge).
	_run([0x7C, 0, 22, 0, 16, 0, 3, 12, 0xFE, 0])
	_frame()
	_eq([before != -1, _cell_trigger(23, 20), _cell_trigger(22, 16), _cell_trigger(24, 27)], [true, -1, -1, -1],
			"the cells of [22, 25) x [16, 28) are blocked")
	map.load_map("MAYO08A")
	_eq(_cell_trigger(23, 20), before, "the next map load restores the cells")


# --- §2.4: File City's lights ------------------------------------------------------------------------

func _lights() -> void:
	map.load_map("TWNB04")
	var lights: Array = data.map(data.map_id("TWNB04")).get("light_objects", [])
	_eq(lights.size(), 1, "TWNB04's map record has its light_objects")
	var flags := []
	for hour in [6, 7, 18, 19]:
		map.overlays.update_light_state(lights, hour, func(_t): return false)
		flags.append([map.overlays.instance(49)["flag"], map.overlays.instance(50)["flag"]])
	_eq(flags, [[0, 0], [1, 1], [1, 1], [0, 0]], "instances 49-50: shown before 7:00 and from 19:00, hidden between")


# --- §2.5: snow ---------------------------------------------------------------------------------------

func _snow() -> void:
	map.load_map("FRZL01")
	var record: Dictionary = data.map(data.map_id("FRZL01"))
	var source: Array = map.data["object_instances"]
	map.overlays.load(map.data, record.get("snow", {}))
	var o := map.overlays
	var snow := 0
	var orders := true
	for k in mini(0x23, o.instance_count()):
		if o.instance(k)["flag"] & MapOverlays.SNOW:
			snow += 1
		if o.instance(k)["order"] != MapOverlays.ORDER_SNOW:
			orders = false
	_eq([record.has("snow"), snow, orders], [true, mini(0x23, o.instance_count()), true],
			"FRZL01: its first 0x23 instances are snow, at order 0x1E")
	_eq(o.instance(0)["x"], int(source[0]["x"]), "instances below 0x14 keep their x")
	_ticks(30)
	_eq(o.instance(0)["y"] >= 0 and o.instance(0)["y"] < 0xF1, true, "the flakes fall and wrap above y 0xF1")


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])
