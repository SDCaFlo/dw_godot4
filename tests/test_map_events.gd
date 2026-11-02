extends SceneTree
## The map events (specs/map_events.md §7), one block per step of §6:
##   DW_STEP_4F=<n> godot --headless --path . -s res://tests/test_map_events.gd
## DW_STEP_4F gives the last built step (0: none); a later step's checks are reported PENDING.
## Exits 1 if a check fails.

const PROPS_PATH := "res://scripts/field/map_props.gd"

var _failed := 0
var _checks := 0
var _started := false
var _step := 0
var _pending: Array[String] = []


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_step = int(OS.get_environment("DW_STEP_4F")) if OS.get_environment("DW_STEP_4F").is_valid_int() else 0
	if _gate(1, "step 1: MapProps logic"):
		_props()
	var state := "FAILED %d" % _failed if _failed else "OK"
	if _pending:
		state += "; PENDING (DW_STEP_4F=%d): %s" % [_step, ", ".join(_pending)]
	print("%s: map event checks (%d run)" % [state, _checks])
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


func _ident_at(t: Vector3i) -> PackedInt32Array:
	return PsxMath.trans_matrix(PsxMath.identity(), t)


# --- Step 1: MapProps logic (§3.1, §4.1.1) -----------------------------------------------------

func _props() -> void:
	if not ResourceLoader.exists(PROPS_PATH):
		_check(false, "step 1: %s exists" % PROPS_PATH)
		return
	var data: Node = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		_check(false, "step 1: GameData (the rsin table) is available")
		data.free()
		return
	PsxMath.setup(data)
	data.free()
	var cls: GDScript = load(PROPS_PATH)
	_models(cls)
	_cart(cls)
	_pile(cls)
	_boulder(cls)
	_boxes(cls)
	_gearbox(cls)
	_pedestal(cls)
	_unload(cls)


func _models(cls: GDScript) -> void:
	var m: Dictionary = cls.MODELS
	var want := {&"cart": "DOSYA", &"cart_box": "HAKO", &"pile": "T_YAMA", &"boulder": "IWA",
			&"big_box": "BIGBOX", &"small_box": "SMABOX", &"gearbox": "GAND", &"pedestal": "ABOX"}
	for k in want:
		_eq(m.get(k), "tmd_files/ETCNA/%s.gltf" % want[k], "P1/P5/P8/P11/P15/P17: model %s" % k)
	_eq(cls.BOULDER_TEXTURE, "ETCNA/IWA1.TIM", "P8: boulder texture")


func _cart(cls: GDScript) -> void:
	var p = cls.new({})
	_eq(p.drawn(&"cart"), false, "cart not drawn before load")
	p.load_dirt_cart()
	_eq(p.loaded.get(&"cart"), true, "P2: cart loaded")
	_eq(p.cart_model, 2, "P2: model 2 after load")
	_eq(p.drawn(&"cart"), false, "P2: model 2 draws nothing")
	p.set_dirt_cart_model(0)
	_eq(p.drawn(&"cart"), true, "cart model 0 drawn")
	p.set_dirt_cart_model(1)
	_eq(p.cart_model, 1, "cart model 1")
	# P3: location + RotMatrix(rot) · (0, 0, radius + 100), x and z only; the partner's y is ignored.
	var loc := Vector3i(1000, -250, -400)
	var rot := Vector3i(0, 0x400, 0)  # a quarter turn
	var m: PackedInt32Array = p.cart_transform(loc, rot, 150)
	var rm := PsxMath.rot_matrix(rot)
	for i in 9:
		_eq(m[i], rm[i], "P3: cart rotation entry %d" % i)
	var w := PsxMath.apply_matrix_lv(rm, Vector3i(0, 0, 250))
	_eq(Vector3i(m[9], m[10], m[11]), Vector3i(w.x + 1000, w.y, w.z - 400), "P3: cart translation")
	_eq(m[10], 0, "P3: cart y ignores the partner's y (yaw only)")
	var m0: PackedInt32Array = p.cart_transform(Vector3i(10, 20, 30), Vector3i.ZERO, 0)
	_eq(Vector3i(m0[9], m0[10], m0[11]), Vector3i(10, 0, 130), "P3: no rotation, radius 0")
	var tilt := Vector3i(0x200, 0, 0)
	var mt: PackedInt32Array = p.cart_transform(Vector3i.ZERO, tilt, 0)
	var wt := PsxMath.apply_matrix_lv(PsxMath.rot_matrix(tilt), Vector3i(0, 0, 100))
	_eq(mt[10], wt.y, "P3: the cart's y is the rotated offset's")
	_check(wt.y != 0, "P3: a pitched partner moves the cart's y")


func _pile(cls: GDScript) -> void:
	var session := {}
	var p = cls.new(session)
	_eq(p.dirt_pile_size(), 15, "P6: counter starts at 15")
	p.load_dirt_pile()
	_eq(p.drawn(&"pile"), true, "P7: pile drawn at 15")
	_eq(p.transform(&"pile"), _pile_matrix(15), "P5/P6: pile matrix at 15")
	_eq(p.transform(&"pile")[0], 0x1000, "P6: full size at 15")
	for c in range(14, 5, -1):
		p.decrease_dirt_pile()
		_eq(p.dirt_pile_size(), c, "P6: counter after a decrease")
		_eq(p.drawn(&"pile"), true, "P7: drawn at %d" % c)
	_eq(p.transform(&"pile"), _pile_matrix(6), "P6: matrix at 6")
	_eq(p.transform(&"pile")[0], 6 * 0x1000 / 15, "P6: scale 6/15 (1638)")
	p.decrease_dirt_pile()
	_eq(p.dirt_pile_size(), 5, "P6: counter 5")
	_eq(p.drawn(&"pile"), false, "P7: not drawn under 6")
	_eq(session.get("dirt_pile_size"), 5, "P6: the counter lives in the session")
	# Never reset: a new MapProps on the same session (a map change) keeps it.
	var q = cls.new(session)
	q.load_dirt_pile()
	_eq(q.dirt_pile_size(), 5, "P6: not reset by a reload")
	_eq(q.drawn(&"pile"), false, "P7: still not drawn")
	p.unload()
	_eq(p.dirt_pile_size(), 5, "P6: not reset by unload")
	# int8_t: past -128 it wraps to 127.
	var s2 := {"dirt_pile_size": -128}
	var r = cls.new(s2)
	r.decrease_dirt_pile()
	_eq(r.dirt_pile_size(), 127, "P6: int8_t wrap")
	var s3 := {"dirt_pile_size": 1}
	var n = cls.new(s3)
	n.load_dirt_pile()
	n.decrease_dirt_pile()
	n.decrease_dirt_pile()
	_eq(n.dirt_pile_size(), -1, "P6: counter goes negative")
	_eq(n.transform(&"pile")[0], -273, "P6: C division truncates (-0x1000 / 15)")


func _pile_matrix(c: int) -> PackedInt32Array:
	var s := PsxMath.s16(PsxMath.div(c * 0x1000, 15))
	return PsxMath.trans_matrix(PsxMath.scale_matrix(PsxMath.rot_matrix(Vector3i.ZERO), Vector3i(s, s, s)),
			Vector3i(2037, 0, 849))


func _boulder(cls: GDScript) -> void:
	var p = cls.new({})
	p.spawn_boulder()
	_eq(p.loaded.get(&"boulder"), true, "P9: boulder loaded")
	_eq(p.boulder_translation, Vector3i(-300, -500, 2000), "P9: spawn translation")
	_eq(p.boulder_rotation, Vector3i.ZERO, "P9: spawn rotation")
	_eq(p.transform(&"boulder"), _ident_at(Vector3i(-300, -500, 2000)), "P9: spawn matrix")
	p.move_boulder(30, 40)
	_eq(p.boulder_translation, Vector3i(-300, -470, 2040), "P10: dx goes to y (C quirk), dz to z")
	_eq(p.boulder_rotation, Vector3i(-10, 0, 0), "P10: pitch -10")
	var want := PsxMath.trans_matrix(PsxMath.scale_matrix(PsxMath.rot_matrix(Vector3i(-10, 0, 0)),
			Vector3i(0x1000, 0x1000, 0x1000)), Vector3i(-300, -470, 2040))
	_eq(p.transform(&"boulder"), want, "P10: matrix after a move")
	p.move_boulder(-5, 0)
	_eq(p.boulder_translation, Vector3i(-300, -475, 2040), "P10: negative dx")
	_eq(p.boulder_rotation.x, -20, "P10: pitch -20")
	p.move_boulder(0x18000, 0)  # int16_t argument: 0x18000 -> 0x8000 -> -0x8000
	_eq(p.boulder_translation.y, -475 - 0x8000, "P10: dx is int16_t")
	var q = cls.new({})
	q.spawn_boulder()
	for i in 3277:
		q.move_boulder(0, 0)
	_eq(q.boulder_rotation.x, PsxMath.s16(-32770), "P10: the pitch is an int16_t (wraps)")
	p.despawn_boulder()
	_eq(p.loaded.get(&"boulder"), false, "0x78: boulder removed")
	_eq(p.drawn(&"boulder"), false, "0x78: boulder not drawn")


func _boxes(cls: GDScript) -> void:
	var p = cls.new({})
	p.spawn_toy_town_boxes()
	_eq(p.loaded.get(&"boxes"), true, "P11: boxes loaded")
	_eq(p.selected_box, 0, "P11: no box selected")
	_eq(p.big_lid, 0, "P13: big lid closed")
	_eq(p.small_lid, 0, "P13: small lid closed")
	_eq(p.transform(&"big_box"), _ident_at(Vector3i(500, -600, 600)), "P12: big box location")
	_eq(p.transform(&"small_box"), _ident_at(Vector3i(-400, -400, 600)), "P12: small box location")
	_eq(p.transform(&"big_lid"), PsxMath.identity(), "P13: closed lid matrix")
	for k in [&"big_box", &"big_lid", &"small_box", &"small_lid"]:
		_eq(p.drawn(k), true, "P11: %s drawn" % k)
	p.tick_render(true)
	_eq(p.big_lid, 0, "P13: nothing moves with no box selected")
	p.open_box(1)
	_eq(p.selected_box, 1, "P14: box 1 selected")
	var frames := 0
	while p.big_lid > -0x400 and frames < 100:
		p.tick_render(true)
		frames += 1
	_eq(frames, 11, "P13: the lid takes 11 frames")
	_eq(p.big_lid, -0x400, "P13: floor -0x400")
	_eq(p.small_lid, 0, "P13: the other lid stays")
	p.tick_render(true)
	_eq(p.big_lid, -0x400, "P13: stays at -0x400")
	_eq(p.transform(&"big_lid"), PsxMath.rot_matrix(Vector3i(-0x400, 0, 0)), "P13: open lid matrix")
	var q = cls.new({})
	q.spawn_toy_town_boxes()
	q.open_box(2)
	q.tick_render(false)
	_eq(q.small_lid, 0, "P13: no tick with the map layer off")
	q.tick_render(true)
	_eq(q.small_lid, -100, "P13: small lid -100")
	_eq(q.big_lid, 0, "P13: big lid stays")
	_eq(q.transform(&"small_lid"), PsxMath.rot_matrix(Vector3i(-100, 0, 0)), "P13: small lid matrix")
	# V1: routine 0x2A.
	_eq(q.set_box(0, true), true, "V1: box 0 with trigger 350 reloads the TFS")
	_eq(q.selected_box, 0, "V1: box set")
	_eq(q.set_box(0, false), false, "V1: no trigger, no reload")
	_eq(q.set_box(2, true), false, "V1: box 2 doesn't reload")
	_eq(q.selected_box, 2, "V1: box 2 set")


func _gearbox(cls: GDScript) -> void:
	var p = cls.new({})
	p.open_box(1)
	p.spawn_gearbox()
	_eq(p.selected_box, 0, "spawnGearbox clears the selected box")
	_eq(p.loaded.get(&"gearbox"), true, "P15: gearbox loaded")
	_eq(p.drawn(&"gearbox"), true, "P15: gearbox drawn")
	_eq(p.transform(&"gearbox"), _ident_at(Vector3i(-100, 0, 1700)), "P15: gearbox location")


func _pedestal(cls: GDScript) -> void:
	var p = cls.new({})
	p.spawn_pedestal()
	_eq(p.loaded.get(&"pedestal"), true, "P17: pedestal loaded")
	_eq(Vector2i(p.pedestal_x, p.pedestal_z), Vector2i(0, 1500), "P17: start")
	_eq(p.transform(&"pedestal"), _ident_at(Vector3i(0, 0, 1500)), "P17: start matrix")
	_eq(p.move_pedestal(), false, "P18: first step not done")
	_eq(Vector2i(p.pedestal_x, p.pedestal_z), Vector2i(-5, 1510), "P18: z 1510, x -5")
	_eq(p.move_pedestal(), false, "P18: second step")
	_eq(Vector2i(p.pedestal_x, p.pedestal_z), Vector2i(5, 1520), "P18: z 1520, x 5")
	var steps := 2
	var done := false
	while not done and steps < 200:
		done = p.move_pedestal()
		steps += 1
	_eq(steps, 50, "P18: 50 frames")
	_eq(Vector2i(p.pedestal_x, p.pedestal_z), Vector2i(5, 2000), "P18: end at z 2000, x 5")
	_eq(p.transform(&"pedestal"), _ident_at(Vector3i(5, 0, 2000)), "P18: end matrix")
	# P21: the daytime transition's removal.
	_eq(p.on_daytime_removal(1), false, "P21: target 1 doesn't hit the pedestal")
	_eq(p.loaded.get(&"pedestal"), true, "P21: still loaded")
	_eq(p.on_daytime_removal(0), true, "P21: target 0 removes the pedestal")
	_eq(p.loaded.get(&"pedestal"), false, "P21: pedestal gone")
	_eq(p.drawn(&"pedestal"), false, "P21: not drawn")
	_eq(p.on_daytime_removal(0), false, "P21: nothing left to remove")


func _unload(cls: GDScript) -> void:
	var p = cls.new({})
	p.load_dirt_cart()
	p.set_dirt_cart_model(0)
	p.load_dirt_pile()
	p.spawn_boulder()
	p.spawn_toy_town_boxes()
	p.spawn_gearbox()
	p.spawn_pedestal()
	p.unload()
	for g in [&"cart", &"pile", &"boulder", &"boxes", &"gearbox", &"pedestal"]:
		_eq(p.loaded.get(g, false), false, "P20: %s unloaded" % g)
	for k in [&"cart", &"pile", &"boulder", &"big_box", &"big_lid", &"small_box", &"small_lid", &"gearbox",
			&"pedestal"]:
		_eq(p.drawn(k), false, "P20: %s not drawn" % k)
	_eq(p.cart_model, 0, "P20: the state stays (only the objects go)")
