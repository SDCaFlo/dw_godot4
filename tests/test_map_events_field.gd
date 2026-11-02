extends SceneTree
## The map events' wiring on a field (specs/map_events.md §4.1.2, §7), on the porter output:
##   DW_STEP_4F=<n> godot --headless --path . -s res://tests/test_map_events_field.gd
## DW_STEP_4F gives the last built step (0: none); a later step's checks are reported PENDING.
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false
var _step := 0
var _pending: Array[String] = []
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
	_step = int(OS.get_environment("DW_STEP_4F")) if OS.get_environment("DW_STEP_4F").is_valid_int() else 0
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("maps/MAYO01/map.json"):
		print("SKIP: porter output missing")
		quit(0)
		return false
	PsxMath.setup(data)
	_setup()
	if _gate(2, "step 2: MapProps view and wiring"):
		_step2()
	if _gate(4, "step 4: screen-effect views and wiring"):
		_step4()
	_teardown()
	var state := "FAILED %d" % _failed if _failed else "OK"
	if _pending:
		state += "; PENDING (DW_STEP_4F=%d): %s" % [_step, ", ".join(_pending)]
	print("%s: map event field checks (%d run)" % [state, _checks])
	quit(1 if _failed else 0)
	return false


func _gate(step: int, what: String) -> bool:
	if _step >= step:
		return true
	_pending.append(what)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _eq(got, want, what: String) -> void:
	_check(got == want, "%s: got %s, want %s" % [what, got, want])


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


func _run(code: Array) -> void:
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code))
	interp.files._cache[500] = bytes
	interp.call_section(500, 1)


func _frame() -> void:
	interp.tick_script()
	boxes.step()


## Content.psx_transform, called through the script so this file loads before step 2 exists.
func _pt(m: PackedInt32Array) -> Transform3D:
	return load("res://scripts/content/content.gd").call("psx_transform", m)


func _frames(n: int) -> void:
	for i in n:
		_frame()


# --- Step 2 ---------------------------------------------------------------------------------------

func _step2() -> void:
	if not ResourceLoader.exists("res://scripts/field/map_props_view.gd"):
		_check(false, "step 2: scripts/field/map_props_view.gd exists")
		return
	_session()
	_psx_transform()
	_unported_without_props()
	_routines()
	_view()
	_daytime_signal()


func _session() -> void:
	_check(gs.get("session") is Dictionary, "GameState.session is a Dictionary")
	if not gs.get("session") is Dictionary:
		return
	gs.session["dirt_pile_size"] = 9
	gs.new_game()
	_eq(gs.session.get("dirt_pile_size"), 9, "P6: a new game keeps the session (static data)")
	_check(not gs.state.has("session"), "the session is not in the saved state")


func _psx_transform() -> void:
	var t: Transform3D = _pt(PsxMath.trans_matrix(PsxMath.identity(), Vector3i(10, 20, 30)))
	_eq(t, Transform3D(Basis.IDENTITY, Vector3(10, -20, -30)), "psx_transform: identity at (10, 20, 30)")
	for r in [Vector3i(0, 0x400, 0), Vector3i(0x123, 0x456, 0x789), Vector3i(-0x400, 0, 0)]:
		var m := PsxMath.rot_matrix(r)
		var got: Transform3D = _pt(m)
		_check(got.basis.is_equal_approx(load("res://scripts/ui/arena/arena_scene_view.gd")._godot_basis(m)), "psx_transform: basis as ArenaSceneView's for %s" % r)
	var yaw: Transform3D = _pt(PsxMath.rot_matrix(Vector3i(0, 0x400, 0)))
	_check(yaw.basis.get_euler().is_equal_approx(Vector3(0, Content.psx_yaw(0x400), 0)),
			"psx_transform: a PSX yaw is Content.psx_yaw")


func _unported_without_props() -> void:
	interp.set("map_props", null)
	unported.clear()
	_run([0x64, 0x1A, 0x76, 0, 0xFE, 0])
	_frames(2)
	_check("CALL_ROUTINE 0x1A" in unported, "without MapProps 0x1A stays unported")
	_check("SPAWN_BOULDER" in unported, "without MapProps 0x76 stays unported")
	_eq(ctx.is_paused, true, "and the script runs on")


func _routines() -> void:
	var props := MapProps.new({})
	interp.set("map_props", props)
	unported.clear()
	interp._reported.clear()
	# 0x1A load the cart; script value 0xFE = 1; 0x13: model 1, then the frame ends.
	gs.set_script_value(0xFE, 1)
	_run([0x64, 0x1A, 0x64, 0x13, 0xFE, 0])
	_frame()
	_eq(props.loaded.get(&"cart"), true, "0x1A: loadDirtCartModel")
	_eq(props.cart_model, 1, "0x13: setDirtCartModel(value 0xFE)")
	_eq(ctx.is_paused, false, "0x13 ends the frame (longjmp 2)")
	_frame()
	_eq(ctx.is_paused, true, "then the section ends")
	# 0x1B, 0x14 (ends the frame), 0x14.
	_run([0x64, 0x1B, 0x64, 0x14, 0x64, 0x14, 0xFE, 0])
	_frame()
	_eq(props.loaded.get(&"pile"), true, "0x1B: loadDirtPileModel")
	_eq(props.dirt_pile_size(), 14, "0x14: one decrease, then the frame ends")
	_frame()
	_eq(props.dirt_pile_size(), 13, "0x14: the second on the next frame")
	_frame()
	_eq(ctx.is_paused, true, "pile section ended")
	# Boxes: 0x2B spawn, 0x2C open (value 0xFE = 2); 0x2A (value 0) with trigger 350 reports the TFS.
	gs.set_script_value(0xFE, 2)
	_run([0x64, 0x2B, 0x64, 0x2C, 0xFE, 0])
	_frames(2)
	_eq(props.loaded.get(&"boxes"), true, "0x2B: spawnToyTownBoxes")
	_eq(props.selected_box, 2, "0x2C: openToyTownBox(value 0xFE)")
	gs.set_script_value(0xFE, 0)
	_run([0x64, 0x2A, 0xFE, 0])
	_frames(2)
	_eq(props.selected_box, 0, "0x2A: somethingToyTown(value 0xFE)")
	_check(not "readMapTFS (step 7)" in unported, "0x2A without trigger 350: no TFS reload")
	gs.set_trigger(350)
	_run([0x64, 0x2A, 0xFE, 0])
	_frames(2)
	_check("readMapTFS (step 7)" in unported, "0x2A with trigger 350: the TFS reload reported")
	# 0x29 gearbox.
	props.open_box(1)
	_run([0x64, 0x29, 0xFE, 0])
	_frames(2)
	_eq(props.loaded.get(&"gearbox"), true, "0x29: spawnGearbox")
	_eq(props.selected_box, 0, "0x29: clears the selected box")
	# 0x31 pedestal, 0x32 waits for moveAngemonPedestal (case 50).
	_run([0x64, 0x31, 0x64, 0x32, 0xFE, 0])
	_frame()
	_eq(props.loaded.get(&"pedestal"), true, "0x31: spawnAngemonPedestal")
	_eq(props.pedestal_z, 1500, "0x32 set up: no move on its own frame")
	_eq(ctx.active_instruction, ScriptContext.OP_CALL_ROUTINE, "0x32: the routine waits")
	_frames(49)
	_eq(props.pedestal_z, 1990, "0x32: one move a frame")
	_eq(ctx.is_paused, false, "0x32: still waiting at 1990")
	_frame()
	_eq(props.pedestal_z, 2000, "0x32: the 50th move ends it")
	_eq(ctx.is_paused, true, "0x32: the script goes on and ends")
	# Boulder opcodes: 0x76 _, 0x77 _ x=30 z=40 (ends the frame), 0x78 _.
	_run([0x76, 0, 0x77, 0, 30, 0, 40, 0, 0x78, 0, 0xFE, 0])
	_frame()
	_eq(props.loaded.get(&"boulder"), true, "0x76: spawnBoulder")
	_eq(props.boulder_translation, Vector3i(-300, -470, 2040), "0x77: moveBoulder(x, z), x to y")
	_eq(ctx.is_paused, false, "0x77 ends the frame")
	_frame()
	_eq(props.loaded.get(&"boulder"), false, "0x78: removeObject(0xFB6)")
	_eq(ctx.is_paused, true, "boulder section ended")
	_run([0x77, 0, 0xFF, 0xFF, 0x00, 0x80, 0xFE, 0])
	_frames(2)
	_eq(props.boulder_translation, Vector3i(-300, -471, 2040 - 0x8000), "0x77: the shorts are signed")
	for name in ["CALL_ROUTINE 0x13", "CALL_ROUTINE 0x14", "CALL_ROUTINE 0x1A", "CALL_ROUTINE 0x1B",
			"CALL_ROUTINE 0x29", "CALL_ROUTINE 0x2A", "CALL_ROUTINE 0x2B", "CALL_ROUTINE 0x2C",
			"CALL_ROUTINE 0x31", "CALL_ROUTINE 0x32", "SPAWN_BOULDER", "MOVE_BOULDER", "DESPAWN_BOULDER"]:
		_check(not name in unported, "%s is no longer unported" % name)


func _view() -> void:
	var props := MapProps.new({})
	var view = load("res://scripts/field/map_props_view.gd").new()
	view.props = props
	var partner := FieldDigimon.new()
	partner.position = Vector3(1000, -50, 400)  # PSX (1000, 50, -400)
	partner.direction = 0x400
	partner.radius = 150
	root.add_child(partner)
	view.partner = partner
	root.add_child(view)
	view.render()
	for k in [&"cart", &"cart_box", &"pile", &"boulder", &"big_box", &"small_box", &"gearbox", &"pedestal"]:
		_eq(view.node(k), null, "no model before load: %s" % k)
	# The cart.
	props.load_dirt_cart()
	view.render()
	_check(view.node(&"cart") != null and view.node(&"cart_box") != null, "the cart's two models load with the group")
	if view.node(&"cart") == null or view.node(&"cart_box") == null:
		return
	_eq([view.node(&"cart").visible, view.node(&"cart_box").visible], [false, false], "P2: model 2 shows nothing")
	props.set_dirt_cart_model(0)
	view.render()
	_eq([view.node(&"cart").visible, view.node(&"cart_box").visible], [true, false], "model 0: the cart")
	var want := _pt(props.cart_transform(Vector3i(1000, 50, -400), Vector3i(0, 0x400, 0), 150))
	_check(view.node(&"cart").transform.is_equal_approx(want), "P3: the cart in front of the partner")
	partner.position = Vector3(0, 0, 0)
	partner.direction = 0
	view.render()
	want = _pt(props.cart_transform(Vector3i.ZERO, Vector3i.ZERO, 150))
	_check(view.node(&"cart").transform.is_equal_approx(want), "P3: the cart follows the partner each frame")
	props.set_dirt_cart_model(1)
	view.render()
	_eq([view.node(&"cart").visible, view.node(&"cart_box").visible], [false, true], "model 1: the box")
	_check(view.node(&"cart_box").transform.is_equal_approx(want), "P3: the box placed as the cart")
	# The pile shrinks.
	props.load_dirt_pile()
	props.decrease_dirt_pile()
	view.render()
	_check(view.node(&"pile") != null and view.node(&"pile").transform.is_equal_approx(_pt(props.transform(&"pile"))),
			"P6: the pile at its scale")
	# The boxes and a lid.
	props.spawn_toy_town_boxes()
	props.open_box(1)
	view.render()
	var big: Node3D = view.node(&"big_box")
	_check(big != null and view.node(&"small_box") != null, "P11: both boxes load")
	if big == null:
		return
	_check(big.transform.is_equal_approx(_pt(props.transform(&"big_box"))), "P12: big box placed")
	var lid := big.find_child("object_1", true, false) as Node3D
	_check(lid != null, "P11: the big box has its lid (object_1)")
	_eq(props.big_lid, -100, "P13: render ticks the lid")
	if lid != null:
		_check(lid.transform.is_equal_approx(_pt(props.transform(&"big_lid"))), "P13: the lid's rotation")
	# Map layer off: no lid tick.
	view.visible = false
	view.render()
	_eq(props.big_lid, -100, "P13: no lid tick while the map layer is off")
	view.visible = true
	# The pedestal and the gearbox.
	props.spawn_gearbox()
	props.spawn_pedestal()
	props.move_pedestal()
	view.render()
	_check(view.node(&"gearbox") != null and view.node(&"gearbox").transform.is_equal_approx(_pt(props.transform(&"gearbox"))),
			"P15: the gearbox placed")
	_check(view.node(&"pedestal") != null and view.node(&"pedestal").transform.is_equal_approx(_pt(props.transform(&"pedestal"))),
			"P18: the pedestal placed")
	props.spawn_boulder()
	view.render()
	_check(view.node(&"boulder") != null, "P8: the boulder loads")
	# Unload frees the models.
	props.unload()
	view.render()
	for k in [&"cart", &"cart_box", &"pile", &"boulder", &"big_box", &"small_box", &"gearbox", &"pedestal"]:
		_eq(view.node(k), null, "P20: %s freed after unload" % k)
	view.free()
	partner.free()


func _daytime_signal() -> void:
	if not map.has_signal("daytime_transition_removed"):
		_check(false, "P21: FieldMap has daytime_transition_removed")
		return
	var got := []
	map.connect("daytime_transition_removed", func(p): got.append(p))
	map.set_time_of_day(0)
	_eq(got, [], "P21: no signal without a running fade")
	map.start_daytime_transition(1)
	for i in 25:
		map.tick_daytime_transition()
	_eq(got, [1], "P21: the fade's end removes (0xFBE, target)")
	got.clear()
	map.start_daytime_transition(2)
	map.tick_daytime_transition()
	map.set_time_of_day(2)
	_eq(got, [2], "P21: updateTimeOfDay during a fade removes it too")
	_eq(Clock.PALETTE.find_key(1), Clock.TIME_EVENING, "P21: palette 1 is time of day 0 (evening)")


# --- Step 4 ---------------------------------------------------------------------------------------

func _step4() -> void:
	if not ResourceLoader.exists("res://scripts/field/hosts/map_effects.gd"):
		_check(false, "step 4: scripts/field/hosts/map_effects.gd exists")
		return
	_fade_blend()
	var effects: Node = load("res://scripts/field/hosts/map_effects.gd").new()
	effects.set("field_map", map)
	effects.set("interpreter", interp)
	effects.set("game_state", gs)
	root.add_child(effects)
	interp.set("map_effects", effects)
	unported.clear()
	interp._reported.clear()
	_shake(effects)
	_ninjamon(effects)
	_mood(effects)
	for name in ["CALL_ROUTINE 0x1C", "CALL_ROUTINE 0x22", "CALL_ROUTINE 0x26", "CALL_ROUTINE 0x2D",
			"CALL_ROUTINE 0x2E"]:
		_check(not name in unported, "%s is no longer unported" % name)
	effects.free()


func _fade_blend() -> void:
	var fade := Fade.new()
	root.add_child(fade)
	interp.set("fade", fade)
	unported.clear()
	interp._reported.clear()
	gs.set_script_value(0xFE, 20)
	_run([0x64, 0x2D, 0xFE, 0])
	_frame()
	_eq(fade.get("mode"), 1, "0x2D: fadeToWhite")
	_eq(fade.out_current, 1, "0x2D: FADE_OUT_CURRENT 1")
	_eq(ctx.is_paused, true, "0x2D doesn't end the frame")
	fade.tick()
	var mat := fade.material as CanvasItemMaterial
	_check(mat != null and mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "S3: the white fade adds")
	_check(fade.visible and fade.color.r > 0.0, "S3: drawn at its progress")
	gs.set_script_value(0xFE, 40)
	_run([0x64, 0x2E, 0xFE, 0])
	_frame()
	_eq([fade.mode, fade.in_current, fade.out_current], [1, 1, 0], "0x2E: fadeFromWhite")
	fade.fade_to_black(10)
	fade.tick()
	_check(mat.blend_mode == CanvasItemMaterial.BLEND_MODE_SUB, "the black fade subtracts")
	_check(not "CALL_ROUTINE 0x2D" in unported and not "CALL_ROUTINE 0x2E" in unported, "0x2D / 0x2E are ported")
	fade.free()


func _shake_amp(f: int) -> int:
	if f < 0x1F:
		return 1
	if f < 0x3D:
		return 2
	if f < 0x79:
		return 3
	if f < 0xB5:
		return 2
	return 1


func _shake(effects: Node) -> void:
	if not "offset_shake" in map:
		_check(false, "FieldMap.offset_shake exists")
		return
	var base := map.drawing_offset()
	_eq(map.offset_shake, Vector2.ZERO, "no shake at first")
	_run([0x64, 0x22, 0xFE, 0])
	_frame()
	_eq(effects.get("shake_running"), true, "0x22: createMeramonShake")
	var sum := 0
	var ok := true
	for f in 0xD2:
		effects.tick()
		sum += _shake_amp(f) * (-1 if f % 2 == 0 else 1)
		if f < 0xD1 and (map.offset_shake != Vector2(sum, 0) or map.drawing_offset() != base + Vector2(sum, 0)):
			ok = false
			_check(false, "S5: frame %d offset %s, want %d" % [f, map.offset_shake, sum])
			break
	_check(ok, "S5: DRAWING_OFFSET_X += each frame's step")
	_eq(effects.shake_running, false, "S6: done after 0xD2 frames")
	_eq(map.offset_shake, Vector2.ZERO, "S6: the offset restored")
	_eq(map.drawing_offset(), base, "S6: the drawing offset back")
	var bg := map.background.position
	_run([0x64, 0x22, 0xFE, 0])
	_frame()
	effects.tick()
	_eq(map.background.position, bg, "the background doesn't shake")
	_check(map.drawing_offset() != base, "the 3D projection centre does")
	for f in 0xD2:
		effects.tick()


func _ninjamon(effects: Node) -> void:
	map.load_map("MAYO08B")
	var o := map.overlays
	if o.instance_count() < 0x29:
		_check(false, "MAYO08B has 0x29 overlay instances")
		return
	var saved: Array = o.store_positions(0, 0x29)
	Rng.set_seed(77)
	_run([0x64, 0x26, 0xFE, 0])
	_frame()
	_eq(effects.get("ninjamon_running"), true, "0x26: createNinjamonEffect")
	var ninja = effects.get("ninjamon")
	effects.tick()
	var ok := true
	for i in 0x29:
		var inst := o.instance(i)
		if Vector2i(inst["x"], inst["y"]) != ninja.positions[i] or inst["order"] != 10:
			ok = false
	_check(ok, "S8: the overlays take the effect's positions, order value 10")
	var shown := 0
	for i in 0x29:
		if o.instance(i)["flag"] != 1:
			shown += 1
	_check(shown > 0, "S8: not hidden while it runs")
	for f in 0x3B:
		effects.tick()
	_eq(effects.ninjamon_running, false, "S8: done after 0x3C frames")
	var hidden := true
	for i in 0x29:
		hidden = hidden and o.instance(i)["flag"] == 1
	_check(hidden, "S8: then every one gets flag 1")
	_check(o.instance(0x29).get("order", 0) != 10, "S8: instance 0x29 is not touched")
	o.set_flag(0, 0, 0x29)
	o.load_positions(saved, 0)
	# Screen coordinates for order < 20 (buildMapOverlayPrim mode 1).
	var k := 0
	for i in o.instance_count():
		if o.is_drawn(i):
			k = i
			break
	o.set_positions([Vector2i(0, 0)], k, 10)
	var node: MeshInstance3D = o.instance(k)["node"]
	var size := Vector2(node.mesh.size) * map.projection() / (10 * MapOverlays.OT_UNIT)
	var want := map.world_at_pixel(map.scroll + FieldMap.SCREEN / 2 + size / 2, 10 * MapOverlays.OT_UNIT)
	_check(node.global_position.is_equal_approx(want), "order < 20: drawn at (x, y) from the screen centre")
	map.load_map("MAYO01")


func _mood(effects: Node) -> void:
	# Script value 0xF7 = an id with no entity on the map: nothing (scriptIdToEntityId 0xFF).
	gs.set_script_value(0xF7, 0x50)
	gs.set_script_value(0xF8, 2)
	_run([0x64, 0x1C, 0xFE, 0])
	_frame()
	var bubble = effects.get("bubble")
	_eq(bubble.instances, 0, "S9: no bubble without the entity")
	effects.tick()
	_eq(effects.get("bubble_draws"), [], "S11: nothing drawn")
	_eq(effects.get("bubble_entity"), null, "S11: no entity")
	_eq(interp.call("entity_for_script_id", 0x50), null, "entity_for_script_id: none")
