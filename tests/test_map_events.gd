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
	if _gate(3, "step 3: screen-effect logic"):
		_screen_effects()
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


# --- Step 3: the screen effects' logic (§3.2, §4.2.1) -------------------------------------------

func _screen_effects() -> void:
	for path in ["res://scripts/field/meramon_shake.gd", "res://scripts/field/ninjamon_effect.gd",
			"res://scripts/field/mood_bubble.gd"]:
		if not ResourceLoader.exists(path):
			_check(false, "step 3: %s exists" % path)
			return
	_white_fade()
	_meramon(load("res://scripts/field/meramon_shake.gd"))
	_ninjamon(load("res://scripts/field/ninjamon_effect.gd"))
	_mood(load("res://scripts/field/mood_bubble.gd"))


func _white_fade() -> void:
	var fade := Fade.new()
	var clock := Clock.new()
	fade.clock = clock
	_eq(fade.get("mode"), 2, "S1: FADE_MODE starts at 2 (initializeFadeData)")
	fade.fade_to_white(20)
	_eq(fade.mode, 1, "S1: white mode")
	_eq(fade.out_current, 1, "S1: FADE_OUT_CURRENT 1")
	_eq(clock.running, true, "S1: no stopGameTime")
	_eq(fade.protection, false, "S1: no FADE_PROTECTION")
	var levels := []
	for i in 24:
		fade.tick()
		levels.append(fade.progress)
	_eq(levels[0], 7, "S1: first step 160 / (20 + 1)")
	_eq(levels[21], 154, "S1: 7 a frame")
	_eq(levels[22], 160, "S1: capped at 160 on frame 23")
	_eq(levels[23], 160, "S1: stays full")
	fade.fade_from_white(40)
	_eq(fade.mode, 1, "S2: white mode")
	_eq(fade.out_current, 0, "S2: fade out stopped")
	_eq(fade.in_current, 1, "S2: FADE_IN_CURRENT 1")
	var n := 0
	while fade.in_current > 0 and n < 100:
		fade.tick()
		n += 1
	_eq(n, 41, "S2: 40 steps, then the end frame")
	_eq(fade.progress, 0, "S2: clear at the end")
	_eq(clock.running, true, "S2: the clock still runs")
	fade.fade_to_black(10)
	_eq(fade.mode, 2, "fadeToBlack sets mode 2")
	_eq(clock.running, false, "fadeToBlack stops the clock")
	_eq(fade.protection, true, "fadeToBlack sets the protection")
	fade.fade_from_white(5)
	_eq(fade.mode, 1, "S2: white after black")
	for i in 10:
		fade.tick()
	_eq(fade.protection, false, "S2: renderFadeIn's end clears the protection (fade.c:125)")
	fade.fade_from_black(5)
	_eq(fade.mode, 2, "fadeFromBlack sets mode 2")
	fade.free()
	clock.free()


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


func _meramon(cls: GDScript) -> void:
	var m = cls.new()
	m.start(Vector2i(160, 120))
	_eq(m.saved_offset, Vector2i(160, 120), "S6: offsets saved")
	_eq(m.done, false, "S5: running")
	var sum := 0
	var steps := 0
	var ok := true
	while not m.done and steps < 400:
		var want := _shake_amp(steps) * (-1 if steps % 2 == 0 else 1)
		var got: int = m.tick()
		if got != want:
			ok = false
			_check(false, "S5: frame %d step %d, want %d" % [steps, got, want])
			break
		sum += got
		steps += 1
	_check(ok, "S5: every step's amplitude and sign")
	_eq(steps, 0xD2, "S6: 210 frames")
	_eq(sum, 0, "S5: the steps sum to 0")
	_eq(m.done, true, "S6: done")
	_eq(m.tick(), 0, "S6: no step once done")
	m.start(Vector2i(1, 2))
	_eq(m.frame, 0, "S5: a new start restarts")
	_eq(m.tick(), -1, "S5: frame 0 is -1")
	_eq(m.tick(), 1, "S5: frame 1 is +1")


func _ninjamon(cls: GDScript) -> void:
	_eq(cls.COUNT, 0x29, "S8: 0x29 sprites")
	_eq(cls.ORDER, 10, "S8: order value 10")
	var saved := []
	for i in 0x29:
		saved.append(Vector2i(i * 4 - 80, 100 - i))
	saved[5] = Vector2i(0x9F, 0)  # wraps on its first frame
	# The rolls the effect must make, in order: start (dx, dy per sprite), then each wrap.
	Rng.set_seed(1234)
	var dx := []
	var dy := []
	for i in 0x29:
		dx.append(Rng.random_limit(10) + 12)
		dy.append(Rng.random_limit(10) + 3)
	var exp_pos := saved.duplicate()
	var frames := []
	for f in 3:
		for i in 0x29:
			exp_pos[i] = Vector2i(exp_pos[i].x + dx[i], exp_pos[i].y + dy[i])
			if exp_pos[i].x > 0xA0:
				exp_pos[i] = saved[i]
				dx[i] = Rng.random_limit(10) + 12
				dy[i] = Rng.random_limit(10) + 3
		frames.append(exp_pos.duplicate())
	Rng.set_seed(1234)
	var e = cls.new()
	e.start(saved)
	_eq(_list(e.positions), _list(saved), "S8: start positions are the saved ones")
	_eq(e.done, false, "S8: running")
	_eq(saved[5], Vector2i(0x9F, 0), "S8: start doesn't change the saved array")
	for f in 3:
		_eq(e.tick(), false, "S8: frame %d not done" % f)
		_eq(_list(e.positions), _list(frames[f]), "S8: positions after frame %d" % (f + 1))
	_eq(frames[0][5], saved[5], "S8: a sprite past 0xA0 goes back to its saved place")
	var n := 3
	var done := false
	while not done and n < 100:
		done = e.tick()
		n += 1
	_eq(n, 0x3C, "S8: done after 0x3C frames")
	_eq(e.done, true, "S8: done flag")


func _mood(cls: GDScript) -> void:
	_eq(cls.SIZE, 32, "S10: 32x32")
	_eq(cls.PIVOT, Vector2i(16, 16), "S10: pivot")
	_eq(cls.TPAGE, Vector2i(640, 0), "S10: tpage")
	_eq(cls.CLUT, Vector2i(0, 486), "S10: CLUT")
	_eq(cls.COLOR, 0x80, "S10: colour")
	var b = cls.new()
	_eq(b.instances, 0, "S9: none at first")
	_eq(b.render(true).size(), 0, "S9: nothing to draw")
	b.create(false, 3)
	_eq(b.instances, 0, "S9: entity off the map: nothing")
	b.create(true, 3)
	_eq(b.instances, 1, "S9: one bubble")
	_eq(b.timer, 0x1E, "S9: timer 0x1E")
	_eq(b.u, 96, "S9: u = mood * 32")
	var r: Array = b.render(true)
	_eq(r, [{"offset": 1, "scale": 0x100}], "S11: first frame offset 1, scale 1/16")
	_eq(b.timer, 0x1D, "S11: timer -1")
	_eq(b.render(false).size(), 0, "S11: entity off the map: nothing drawn")
	_eq(b.timer, 0x1D, "S11: and the timer doesn't move")
	for i in 0x1D:
		b.render(true)
	_eq(b.timer, 0, "S11: timer down to 0")
	_eq(b.render(true), [{"offset": 16, "scale": 0x1000}], "S11: full size")
	_eq(b.timer, 0, "S11: stays at 0")
	b.create(true, 0)
	_eq(b.instances, 2, "S9: a second create runs a second render object")
	_eq(b.u, 0, "S9: u of the last mood")
	r = b.render(true)
	_eq(r.size(), 2, "S11: drawn twice")
	_eq(r[0], {"offset": 1, "scale": 0x100}, "S11: first instance at 0x1E")
	_eq(r[1], {"offset": 16 - (0x1D >> 1), "scale": PsxMath.s16((16 - (0x1D >> 1)) << 8)}, "S11: second after one decrement")
	_eq(b.timer, 0x1C, "S11: two decrements a frame")
	b.create(true, 5)
	_eq(b.instances, 1, "S9: mood 5 removes one")
	b.create(true, 0x105)
	_eq(b.instances, 0, "S9: mood & 0xFF (0x105 -> 5) removes")
	b.create(true, 7)
	_eq(b.instances, 0, "S9: not below 0")
	b.create(true, 0x101)
	_eq(b.instances, 1, "S9: 0x101 & 0xFF is mood 1")
	_eq(b.u, 32, "S9: u 32")
	b.clear()
	_eq(b.instances, 0, "clear")


## An array as text, so typed and untyped arrays compare by their contents.
func _list(a) -> String:
	return str(Array(a))
