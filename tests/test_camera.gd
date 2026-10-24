extends SceneTree
## The field camera (scripts/field/field_map.gd) against specs/camera.md §2, the script's camera
## slot and "with camera" moves (specs/script.md §2.7 "Step 4"), and the toilet scene
## (specs/care.md §2.16), on MAYO01 (768 x 640 background) from the porter output:
##   godot --headless --path . -s res://tests/test_camera.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false
var data: Node
var gs: Node
var map: FieldMap
var limit: Vector2
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
	_follow()
	_pans()
	_camera_slot()
	_moves_with_camera()
	_toilet()
	_teardown()
	print("%s: camera checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
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
	limit = map.background_size - FieldMap.SCREEN
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


## The scroll that centres a Godot point (unclamped).
func _centre(world: Vector3) -> Vector2:
	return (map.background_pixel(world) - FieldMap.SCREEN / 2).round()


## A synthetic script section, loaded as script 500 (as tests/test_script.gd).
func _run(code: Array) -> void:
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code))
	interp.files._cache[500] = bytes
	interp.call_section(500, 1)


## A game frame: the script, then the pan (specs/camera.md §3).
func _frame() -> void:
	pad.poll(0)
	pad.process()
	interp.tick_script()
	map.tick_pan()
	boxes.step()


# --- §2.1-2.2: map entry and the follow --------------------------------------------------------------

func _follow() -> void:
	_eq(limit, Vector2(448, 400), "MAYO01: the scroll's range (6 x 5 tiles of 128 - the screen)")
	var far := Vector3(6000, 0, 0)
	map.follow(far)
	_eq([map.virtual_scroll, map.scroll.x], [_centre(far), limit.x],
			"map entry: the virtual scroll centres the tamer, the scroll is it clamped")
	# Without a direction (moveCameraByDiff in a scene): the clamp only, the virtual scroll takes
	# the whole motion.
	map.scroll = Vector2(100, 100)
	map.virtual_scroll = Vector2(100, 100)
	map.scroll_by(Vector2(7, -3), 0)
	_eq([map.scroll, map.virtual_scroll], [Vector2(107, 97), Vector2(107, 97)], "no direction held: the scroll moves")
	# Centred and walking right: the scroll follows.
	map.scroll_by(Vector2(5, 0), Pad.RIGHT)
	_eq(map.scroll.x, 112.0, "centred, right held: the scroll follows")
	# At the right edge: the scroll stops, the virtual scroll goes on.
	map.scroll = Vector2(limit.x - 2, 100)
	map.virtual_scroll = map.scroll
	var seen := []
	for i in 2:
		map.scroll_by(Vector2(5, 0), Pad.RIGHT)
		seen.append([map.scroll.x - limit.x, map.virtual_scroll.x - limit.x])
	_eq(seen, [[0.0, 3.0], [0.0, 8.0]], "at the edge the scroll stops, the virtual scroll goes on")
	# Walking back: each step is undone while the virtual scroll is still beyond the scroll.
	seen.clear()
	for i in 3:
		map.scroll_by(Vector2(-5, 0), Pad.LEFT)
		seen.append([map.scroll.x - limit.x, map.virtual_scroll.x - limit.x])
	_eq(seen, [[0.0, 3.0], [0.0, -2.0], [-5.0, -7.0]],
			"walking back, the scroll waits until the virtual scroll is back inside (updateDrawingOffsets' undo)")
	_eq([Tamer._held_directions(Vector2(-1, 1)), Tamer._held_directions(Vector2.ZERO)], [Pad.LEFT | Pad.DOWN, 0],
			"the held d-pad bits")


# --- §2.3: pans --------------------------------------------------------------------------------------

func _pans() -> void:
	var point := Content.psx_to_godot(map.data["setup"]["reference"]) * 2.0
	var c := _centre(point)
	_eq(c.x > 30 and c.y > 30 and c.x < limit.x - 30 and c.y < limit.y - 30, true, "the test point's centring scroll is inside: %s" % c)
	# total (23, -7), speed 10: x 23 / 10 = 2, +1 on the first |3| + 1 frames; y 0, -1 on the
	# first 8 frames, set back to the target once past it.
	var start := c - Vector2(23, -7)
	map.scroll = start
	map.camera_follow = true
	map.start_pan(point, 10)
	var steps := []
	var follow_during := []
	for i in 12:
		if not map.is_panning():
			break
		map.tick_pan()
		steps.append(Vector2i(map.scroll - start))
		follow_during.append(map.camera_follow)
	_eq(steps.map(func(v): return v.x), [3, 6, 9, 12, 14, 16, 18, 20, 22, 23],
			"x: 3 for 4 frames, then 2; past the target on frame 10, set to it, the pan ends")
	_eq(steps.map(func(v): return v.y), [-1, -2, -3, -4, -5, -6, -7, -7, -7, -7],
			"y: -1 for 8 frames (the remainder), held on the target")
	_eq([follow_during.slice(0, 9).has(true), map.camera_follow, map.pan_reached, map.virtual_scroll],
			[false, true, -1, c], "the follow is off while it runs and on after; a scene's pan leaves REACHED at -1; v = the target")
	# A target beyond the right edge: the pan ends at the edge, v keeps the unclamped target.
	var beyond := point + Vector3(3000, 0, 0)
	map.scroll = Vector2(limit.x - 40, c.y)
	map.start_pan(beyond, 10)
	var frames := 0
	while map.is_panning() and frames < 30:
		map.tick_pan()
		frames += 1
	_eq([map.scroll.x, map.virtual_scroll.x, frames <= 11], [limit.x, _centre(beyond).x, true],
			"beyond the edge: ends on the edge in about speed frames, v unclamped")


# --- the camera slot (types 6, 7) and WAIT_FOR_ENTITY 0xC8 --------------------------------------------

func _camera_slot() -> void:
	map.scroll = Vector2(100, 100)
	# MOVE_CAMERA_TO speed 10, x 0, z 600; WAIT_FOR_ENTITY 0xC8 (the camera); END.
	_run([0x4F, 10, 0, 0, 0x58, 0x02, 0x4A, 0xC8, 0xFE, 0])
	var pan_end := -1
	var ended := -1
	for f in range(1, 40):
		var panning := map.is_panning()
		_frame()
		if panning and not map.is_panning() and pan_end < 0:
			pan_end = f
		if ctx.is_paused and ended < 0:
			ended = f
			break
	var target := Content.psx_to_godot([0, 0, 600])
	_eq([interp.movement[ScriptInterpreter.CAMERA_SLOT], map.scroll, map.pan_reached],
			[ScriptInterpreter.FREE, _centre(target).clamp(Vector2.ZERO, limit), -1],
			"MOVE_CAMERA_TO: the camera ends centred on the point (clamped), REACHED back at -1")
	_eq(ended - pan_end, 1, "checkCameraMovement: the slot sees the end on its next tick, then the wait ends (pan end %d, script end %d)" % [pan_end, ended])
	# MOVE_CAMERA_TO_ENTITY _, the partner, speed 5.
	var partner := Partner.new()
	interp.partner = partner
	partner.position = Content.psx_to_godot([-300, 0, 900])
	_run([0x50, 0, 0xFC, 5, 0x4A, 0xC8, 0xFE, 0])
	for f in 30:
		_frame()
		if ctx.is_paused:
			break
	_eq([ctx.is_paused, map.scroll], [true, _centre(partner.position).clamp(Vector2.ZERO, limit)],
			"MOVE_CAMERA_TO_ENTITY: centred on the partner")
	interp.partner = null
	partner.free()


# --- the "with camera" moves (types 4, 15; moveCameraByDiff, §2.4) -----------------------------------

func _moves_with_camera() -> void:
	var tamer := Tamer.new()
	interp.tamer = tamer
	interp._previous_camera_pos_initialized = false
	tamer.position = Vector3.ZERO
	map.scroll = Vector2(200, 200)
	map.virtual_scroll = map.scroll
	# ENTITY_WALK_TO_WITH_CAMERA tamer, (3000, 0), anim 0; DELAY 30; END.
	_run([0x52, 0xFD, 0xB8, 0x0B, 0, 0, 0, 0, 0x67, 0, 30, 0, 0xFE, 0])
	_frame()
	_frame()
	_eq([interp.movement[0], map.scroll], [ScriptInterpreter.MOVE_WALK_TO_WITH_CAMERA, Vector2(200, 200)],
			"ENTITY_WALK_TO_WITH_CAMERA: slot 0 type 4; its first frame stores his position, no motion")
	tamer.position = Vector3(200, 0, 0)
	var motion := map.screen_motion(Vector3.ZERO, tamer.position)
	_frame()
	_eq([map.scroll, map.virtual_scroll], [Vector2(200, 200) + motion, Vector2(200, 200) + motion],
			"the next frame the camera moves by his motion since the previous tick (%s)" % motion)
	_force_end()
	interp._previous_camera_pos_initialized = false
	# ENTITY_MOVE_TO_AXIS_WITH_CAMERA tamer, 300, axis 2 (z), speed 3; WAIT tamer; END.
	tamer.position = Vector3.ZERO
	map.scroll = Vector2(200, 200)
	map.virtual_scroll = map.scroll
	_run([0x73, 0xFD, 0x2C, 0x01, 2, 3, 0x4A, 0xFD, 0xFE, 0])
	for f in 6:
		_frame()
	var dragged := map.screen_motion(Vector3.ZERO, Content.psx_to_godot([0, 0, 200]))
	_eq([ctx.is_paused, -tamer.position.z, map.virtual_scroll], [true, 300.0, Vector2(200, 200) + dragged],
			"ENTITY_MOVE_TO_AXIS_WITH_CAMERA on z: done on 300; the camera dragged by the steps to 200, not the last (the C returns before moveCameraByDiff)")
	interp.tamer = null
	tamer.free()


func _force_end() -> void:
	ctx.is_paused = true
	ctx.stack.clear()
	interp.textboxes.close_all_textboxes()


# --- the toilet scene (partner state 6, specs/care.md §2.16) ------------------------------------------

func _toilet() -> void:
	var clock := Clock.new()
	clock.game_state = gs
	var care := Care.new()
	care.game_state = gs
	care.data = data
	care.clock = clock
	gs.new_game("dw1:agumon")
	care.initialize_partner()
	gs.state["world"]["screen"] = "dw1:mayo01"
	gs.set_condition(Care.POOPY, true)
	var c: Dictionary = gs.state["partner"]["care"]
	c["happiness"] = 50
	var tamer := Tamer.new()
	tamer.field = map
	var partner := Partner.new()
	root.add_child(partner)
	partner.field = map
	partner.tamer = tamer
	partner.game_state = gs
	partner.care = care
	partner.data = data
	partner.script_ctx = ctx
	if not partner.load_digimon(data, "dw1:agumon"):
		_eq(false, true, "Agumon's model loads")
		return
	interp.tamer = tamer
	interp.partner = partner
	interp._previous_camera_pos_initialized = false
	tamer.position = Content.psx_to_godot([300, 0, -1200])
	partner.position = Content.psx_to_godot([300, 0, -1500])
	map.follow(tamer.position)
	var toilet: Dictionary = data.entity("map", "dw1:mayo01")["toilet"]
	unported.clear()
	interp.call_section(ScriptFiles.MAPHEAD, 0x4E2, 0)
	var subs := []
	var at_toilet := Vector2i.ZERO
	var follow_in_sub_1 := true
	var frames := 0
	while frames < 3000:
		frames += 1
		partner.tick()
		pad.poll(0)
		pad.process()
		interp.tick_script()
		map.tick_pan()
		boxes.step()
		partner._process(1.0 / GameLoop.FRAME_RATE)
		if partner.state == Partner.STATE_TOILET and (subs.is_empty() or subs.back() != partner.sub_state):
			subs.append(partner.sub_state)
			if partner.sub_state == 3:
				at_toilet = FieldMap.model_tile(int(partner.position.x), int(-partner.position.z))
		if partner.state == Partner.STATE_TOILET and partner.sub_state == 1:
			follow_in_sub_1 = follow_in_sub_1 and map.camera_follow
		if ctx.is_paused:
			break
	_eq(subs, [0, 1, 2, 3, 4], "the scene's sub-states in order (it starts after the partner's tick)")
	_eq(at_toilet, FieldMap.model_tile(int(toilet["camera_to"][0]), int(toilet["camera_to"][1])),
			"it squats on the toilet's tile (camera_to)")
	_eq(follow_in_sub_1, false, "the follow is off during the pan to the toilet")
	_eq([ctx.is_paused, FieldMap.model_tile(int(partner.position.x), int(-partner.position.z))],
			[true, FieldMap.model_tile(int(toilet["walk_to"][0]), int(toilet["walk_to"][1]))],
			"back on the first point, the sync bit ends the wait and the script (%d frames)" % frames)
	_eq([gs.has_condition(Care.POOPY), int(c["happiness"])], [false, 52], "handleToilet: not poopy, happiness + 2")
	_eq([partner.state, tamer.state, map.camera_follow, map.scroll], [Partner.STATE_NORMAL, Tamer.STATE_FREE, true,
			_centre(tamer.position).clamp(Vector2.ZERO, limit)],
			"the field is given back, the camera panned back to the tamer")
	_eq(unported, ["PLAY_SOUND"], "only the sound is left unported")
	interp.tamer = null
	interp.partner = null
	partner.queue_free()
	tamer.free()
	care.free()
	clock.free()


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])
