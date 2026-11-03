extends SceneTree
## The map events (specs/map_events.md §7), one block per step of §6:
##   DW_STEP_4F=<n> godot --headless --path . -s res://tests/test_map_events.gd
## Steps 1-6 are built, so every check runs (DW_STEP_4F=<n> still limits them to the steps up to n).
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
	# Steps 1-6 are built (spec §6): every check runs; DW_STEP_4F=<n> can still limit them.
	_step = int(OS.get_environment("DW_STEP_4F")) if OS.get_environment("DW_STEP_4F").is_valid_int() else 6
	if _gate(1, "step 1: MapProps logic"):
		_props()
	if _gate(3, "step 3: screen-effect logic"):
		_screen_effects()
	if _gate(5, "step 5a: Machinedramon's logic (EabScene)"):
		_eab()
	if _gate(6, "step 6: the ending's logic (EndingScene)"):
		_ending()
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


# --- Step 5a: Machinedramon's logic (§3.3, §4.3.1) ----------------------------------------------

const EAB_PATH := "res://scripts/field/eab/eab_scene.gd"


func _l(a: int, b: int, t0: int, t1: int, t: int) -> int:
	return PsxMath.lerp_int(a, b, t0, t1, t)


func _live(list: Array) -> int:
	return list.filter(func(r): return r["timer"] >= 0).size()


func _eab() -> void:
	if not ResourceLoader.exists(EAB_PATH):
		_check(false, "step 5a: %s exists" % EAB_PATH)
		return
	var cls: GDScript = load(EAB_PATH)
	_eq(cls.FLASHES.size(), 9, "E4: nine flash positions")
	_eq(cls.FLASHES[0], [0, -300, -900, 0x1400], "E4: EAB_D_8006170C[0]")
	_eq(cls.FLASHES[8], [-1200, -300, -2500, 0x1400], "E4: EAB_D_8006170C[8]")
	_eq(cls.PULSE, [1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0], "E8: EAB_D_8006179C")
	_eab_buildup(cls)
	_eab_spawn(cls)
	_eab_particles(cls)
	_eab_spawn_rings(cls)


func _ring_y(amp: int, base: int, t: int) -> int:
	return PsxMath.div(PsxMath.sin512(_l(0, 0x80, 1, 0x12, t)) * amp, 4096) + base


func _eab_buildup(cls: GDScript) -> void:
	var e = cls.new()
	e.start_buildup()
	_eq(e.events, ["buildup_entity_hidden", ["sound2", 8, 0]], "E2: start events")
	_eq(e.buildup_active, true, "E2: running")
	# Frames 1-5: no ring; frame 6: the first, ticked in its own frame (timer 1).
	for f in 5:
		e.tick()
	_eq(_live(e.rings), 0, "E2: no ring before frame 6")
	e.tick()
	_eq(e.rings[0]["timer"], 1, "E2: a ring at frame 6, ticked in its frame")
	_eq(e.rings[0]["kind"], cls.RING_BUILDUP, "E2: a build-up ring")
	_eq(e.ring_scale(0), Vector3i(0x10B8, _ring_y(0xC3C, 0x15C, 1), 0x10B8), "E3: scale at t 1")
	# Frames 6, 12, 18 add one each.
	for f in 12:
		e.tick()
	_eq(_live(e.rings), 3, "E2: three rings by frame 18")
	_eq([e.rings[0]["timer"], e.rings[1]["timer"], e.rings[2]["timer"]], [13, 7, 1], "E2: their timers")
	var xz := _l(0x10B8, 0x614, 1, 0x12, 13)
	_eq(e.ring_scale(0), Vector3i(xz, _ring_y(0xC3C, 0x15C, 13), xz), "E3: scale at t 13")
	# The first ends at t 0x12 (frame 23), so frame 24 finds slot 0 free.
	for f in 5:
		e.tick()
	_eq(e.rings[0]["timer"], -1, "E3: gone at 0x12 (frame 23)")
	e.tick()
	_eq(e.rings[0]["timer"], 1, "E2: frame 24 reuses slot 0")
	_eq(e.buildup_frame, 6, "E2: (frame + 1) % 18 (24 -> 6)")


func _eab_spawn(cls: GDScript) -> void:
	var e = cls.new()
	e.start_buildup()
	e.location = Vector3i(100, 0, 2000)
	e.yaw = 0x400
	e.bone0 = Vector3i(100, -800, 2000)
	e.start_spawn()
	_check(e.events.has(["sound", 8, 1]), "E4: playSound(8, 1)")
	_eq(e.fx.flashes.filter(func(f): return f["progress"] >= 0).size(), 9, "E4: nine flashes")
	var f0: Dictionary = e.fx.flashes[0]
	_eq([f0["mode"], f0["position"], f0["fixed_depth"], f0["t_max"], f0["scale_min"], f0["scale_max"], f0["color_min"], f0["color_max"]],
			[0x20, Vector3i(0, -300, -900), 0x22, 0x32, 0, 0x1400, Vector3i(0x14, 0x14, 0x14), Vector3i(0xFF, 0xFF, 0xFF)],
			"E4: EFECreateFlash's arguments")
	_eq(e.result(), 0, "EAB_tick(_, 1): frame 0")
	var events := {}
	var views := {}
	var wire := {}
	var flashes := {}
	var backdrop := {}
	var done_at := -1
	for n in 0x160:
		e.anim_id = 0x33 if n >= 0xD2 else 0x21
		e.anim_ended = n == 0xE0
		e.tick()
		var f := n + 1
		events[f] = e.events.duplicate()
		views[f] = e.view.duplicate()
		wire[f] = e.wireframe_total
		flashes[f] = e.flashes_drawn.duplicate()
		backdrop[f] = e.backdrop
		if e.result() < 0:
			done_at = f
			break
	_eq(done_at, 0x154, "E12: frame -1 at 0x154")
	_eq(e.spawn_active, false, "E12: done")
	_eq(_live(e.rings), 0, "E12: the rings removed")
	_eq(flashes[0x2C], [], "E5: no flash before 0x2D")
	_eq(flashes[0x2D], [0xFF], "E5: the flash from 0x2D")
	_eq(flashes[0x32], [0xFF, 0xFF], "E5/E6: frame 0x32 draws both (phase 0, then the fall-through)")
	_eq(flashes[0x40], [_l(0xFF, 0, 0x32, 0x52, 0x40)], "E6: the fade at 0x40")
	_eq(flashes[0x53], [], "E6: no flash from 0x53")
	_eq(events[0x32], ["entity_on_map", ["animation", 0x21], "hide_entities", "map_layer_off", "save_view", "stop_sound",
			["sound2", 8, 2], ["vab", 5]], "E5: the setup at 0x32")
	_eq(e.buildup_active, false, "E5: the build-up removed")
	_eq(events[0xD2], [["animation", 0x33]], "E6: animation 0x33 at 0xD2")
	_eq(events[0xE1], [["animation", 0x33]], "E6: 0x33 restarts when it ends (353-356)")
	_eq(backdrop[0x31], false, "E10: no backdrop in phase 0")
	_eq(backdrop[0x32] and backdrop[0x140], true, "E10: the backdrop 0x32-0x140")
	_eq(backdrop[0x141], false, "E10: none in phase 2")
	_eq(wire[0x31], 0x10, "E6: whole before 0x32")
	_eq(wire[0x32], 0x10 - PsxMath.div(PsxMath.sin512(0x80) * 16, 4096), "E6: wireframe total at 0x32")
	_eq(wire[0xA0], 0x10 - PsxMath.div(PsxMath.sin512(_l(0x80, 0, 0x32, 0x122, 0xA0)) * 16, 4096), "E6: at 0xA0")
	_eq(wire[0x122], 0x10, "E6: whole again at 0x122")
	_eq(wire[0x130], 0x10, "E6: kept after 0x122")
	var ref := Vector3i(100, -800 - 0x64, 2000)
	var ry := _l(0x71C, 0x171C, 0x32, 0x122, 0x80) + 0x400
	var dist := _l(0xDAC, 0xBB8, 0x32, 0x140, 0x80)
	var h := _l(0x258, 0x32, 0x32, 0x140, 0x80)
	var eye := PsxMath.apply_matrix_lv(PsxMath.rot_matrix_zyx(Vector3i(0, ry, 0)), Vector3i(0, 0, dist)) + ref - Vector3i(0, h, 0)
	_eq(views[0x80], {"eye": eye, "ref": ref}, "E11: the orbit at 0x80")
	ry = 0x171C + 0x400
	dist = _l(0xDAC, 0xBB8, 0x32, 0x140, 0x130)
	h = _l(0x258, 0x32, 0x32, 0x140, 0x130)
	eye = PsxMath.apply_matrix_lv(PsxMath.rot_matrix_zyx(Vector3i(0, ry, 0)), Vector3i(0, 0, dist)) + ref - Vector3i(0, h, 0)
	_eq(views[0x130], {"eye": eye, "ref": ref}, "E11: yaw 0x171C after 0x122")
	_eq([views[0x13F], events[0x13F]], [{}, ["restore_view"]], "E11: frame 0x13F restores the view")
	_eq(events[0x140], ["map_layer_on", "show_entities", "restore_view", "stop_sound", ["sound", 8, 3]], "E12: phase 2 at 0x140")
	_eq(views[0x140], {}, "E12: the view restored")
	_eq(views[0x31], {}, "E11: no orbit in phase 0")


func _eab_particles(cls: GDScript) -> void:
	# Frame 0x80: PULSE[0x80 % 18] = PULSE[2] = 3, so a particle.
	var g := PsxMath.div(_l(0x32, 0xE6, 1, 5, 3) * PsxMath.sin512(_l(0, 0x80, 0x32, 0x122, 0x80)), 4096) & 0xFF
	var e = cls.new()
	e.location = Vector3i(7, 8, 9)
	e.start_spawn()
	var added := {}
	for n in 0x80:
		e.tick()
		added[n + 1] = e.particles.filter(func(p): return p["timer"] == 1).size()
	_eq(added[0x31], 0, "E8: none in phase 0")
	_eq(added[0x36], 1, "E8: a particle at 0x36 (PULSE[0] = 1)")
	_eq(added[0x3F], 0, "E8: none at 0x3F (PULSE[9] = 0)")
	var newest: Array = e.particles.filter(func(p): return p["timer"] == 1)
	_eq(newest.size(), 1, "E8: frame 0x80's particle")
	if newest.size() != 1:
		return
	var k: int = e.particles.find(newest[0])
	_eq(newest[0]["color"], Vector3i(0x0A, g, 0x0A), "E8: its colour")
	_eq(newest[0]["pos"], Vector3i(7, 8, 9), "E8: at the entity's location")
	_eq(e.particle_size(k), _l(8, 0x9C4, 0, 0x56, 1), "E8: size at t 1")
	_eq(e.particle_color(k), Vector3i(_l(0x0A, 0, 0, 0x56, 1), _l(g, 0, 0, 0x56, 1), _l(0x0A, 0, 0, 0x56, 1)), "E8: colour fades")
	# A particle shows t 1..0x56, then goes.
	for n in 0x55:
		e.tick()
	_eq(e.particles[k]["timer"], 0x56, "E8: t 0x56 on its 86th frame")
	e.tick()
	_eq(e.particles[k]["timer"], -1, "E8: gone the next")


func _eab_spawn_rings(cls: GDScript) -> void:
	var e = cls.new()
	e.start_spawn()
	for n in 0x32:
		e.tick()
	_eq(_live(e.rings), 1, "E7: a spawn ring at 0x32")
	_eq(e.rings[0]["kind"], cls.RING_SPAWN, "E7: spawn kind")
	_eq(e.ring_scale(0), Vector3i(0x16CC, _ring_y(0x2B8, 0xAE, 1), 0x16CC), "E7: scale at t 1")
	for n in 2:
		e.tick()
	_eq(_live(e.rings), 3, "E7: three by 0x34")
	e.tick()
	_eq(_live(e.rings), 3, "E7: no fourth")
	# Ring 0 (t 1 at 0x32) reaches t 9 and goes at 0x3A, after that frame's add found no slot.
	for n in 5:
		e.tick()
	_eq(e.rings[0]["timer"], -1, "E7: ring 0 gone at 0x3A")
	e.tick()
	_eq(e.rings[0]["timer"], 1, "E7: slot 0 again at 0x3B")


# --- Step 6: the ending's logic (§3.4, §4.4.1) ----------------------------------------------------

const ENDING_PATH := "res://scripts/field/ending/ending_scene.gd"


## A bone's world matrix for the tests: no rotation, at (bone * 10, -100 * bone, 7).
func _bone_m(bone: int) -> PackedInt32Array:
	return _ident_at(Vector3i(bone * 10, -100 * bone, 7))


## world(p) with _bone_m: s16(div(pos * scale, 4096)) + t.
func _world(pos: Vector3i, bone: int, scale: int) -> Vector3i:
	var v := Vector3i(PsxMath.div(pos.x * scale, 0x1000), PsxMath.div(pos.y * scale, 0x1000), PsxMath.div(pos.z * scale, 0x1000))
	return PsxMath.s16_vec(PsxMath.s16_vec(v) + PsxMath.translation(_bone_m(bone)))


func _ending() -> void:
	if not ResourceLoader.exists(ENDING_PATH):
		_check(false, "step 6: %s exists" % ENDING_PATH)
		return
	var cls: GDScript = load(ENDING_PATH)
	_eq(cls.PARTICLES, 80, "N6: NUM_ENDI_PARTICLES")
	_eq(cls.fade_factor(0), 1.0, "N2: full colour before the fade")
	_eq(cls.fade_factor(30), 0.5, "N2: half at frame 30")
	_eq(cls.fade_factor(60), 0.0, "N2: black at 60")
	var e = cls.new()
	e.bone_count = 12
	e.bone_matrix = _bone_m
	_eq(e.render(), [], "nothing before the start")
	e.start()
	_eq(e.events, [["sound", 8, 0]], "N1: playSound(8, 0)")
	_check(e.active and e.shown and e.attached, "N1: running, the particles shown and attached")
	_eq(e.frame, 0, "N1: frame 0")
	_eq(e.scale, 0x1000, "N1: scale 1")
	_eq(e.fade_frame, 0, "N1: no fade yet")
	# Frame 1: the fade at 1, a particle at bone 1 % 11 + 1 = 2 with three rolls x, y, z.
	Rng.set_seed(7)
	var r := [Rng.rand(), Rng.rand(), Rng.rand()]
	Rng.set_seed(7)
	e.tick()
	_eq(e.events, [], "frame 1: no event")
	_eq(e.frame, 1, "N2: frame incremented first")
	_eq(e.fade_frame, 1, "N2: the fade runs at frame 1")
	_eq(e.particles[0]["active"], 0, "N6: slot 0 spawned")
	_eq(e.particles[0]["bone"], 2, "N2: bone frame % (count - 1) + 1")
	_eq(e.particles[0]["pos"], Vector3i(r[0] % 140 - 70, r[1] % 80 - 40, r[2] % 80 - 40), "N6: the offset rolls")
	# The render's rolls: r, g, b, size per particle.
	Rng.set_seed(9)
	var c := [Rng.rand(), Rng.rand(), Rng.rand(), Rng.rand()]
	Rng.set_seed(9)
	var drawn: Array = e.render()
	_eq(drawn.size(), 1, "N6: one particle drawn")
	if drawn.size() == 1:
		_eq(drawn[0]["color"], Vector3i(c[0] % 70 + 60, c[1] % 70 + 60, c[2] % 70 + 60), "N6: the colour rolls")
		_eq(drawn[0]["size"], c[3] % 15 + 15, "N6: the size roll")
		_eq(drawn[0]["pos"], _world(e.particles[0]["pos"], 2, 0x1000), "N6: attached to its bone")
	while e.frame < 60:
		e.tick()
	_eq(e.phase, 1, "N2: phase 1 at 60")
	_eq(e.fade_frame, 60, "N2: the last fade at 60")
	_eq(e.scale, 0x1000, "N2: no scale in phase 0")
	while e.frame < 70:
		e.tick()
	_eq(e.scale, _l(0x1000, 0x999, 60, 78, 70), "N3: shrinking at 70")
	_eq(e.fade_frame, 60, "N3: no fade after phase 0")
	while e.frame < 79:
		e.tick()
	_eq(e.scale, _l(0x999, 0x1800, 78, 80, 79), "N3: growing at 79")
	var before := []
	for p in e.particles:
		before.append([p["active"], p["pos"], p["bone"]])
	e.tick()
	_eq(e.frame, 80, "frame 80")
	_eq(e.scale, 0x1800, "N3: 0x1800 at 80")
	_eq(e.events, [["sound", 8, 1]], "N3: playSound(8, 1)")
	_eq(e.phase, 2, "N3: phase 2")
	_eq(e.velocity, -450, "N3: velocity -450")
	_eq(e.attached, false, "N3: released")
	_eq(e.particles.filter(func(p): return p["active"] >= 0).size(), 80, "N6: 80 spawns fill the 80 slots")
	var m0 := _bone_m(0)
	_eq(e.base, PsxMath.s16_vec(Vector3i(m0[10], m0[11], 0)), "N7: base from t[1], t[2] and 0")
	var kept := true
	for i in 79:
		var want := _world(before[i][1], before[i][2], 0x1800)
		kept = kept and PsxMath.s16_vec(e.particles[i]["pos"] + e.base) == want
	_check(kept, "N3: released where they were, at scale 0x1800")
	var base_y: int = e.base.y
	e.tick()
	_eq(e.base.y, base_y - 450, "N4: base y += velocity")
	_eq(e.velocity, -430, "N4: velocity += 20")
	drawn = e.render()
	_eq(drawn.size(), 80, "N4: 80 drawn")
	if drawn.size() == 80:
		_eq(drawn[5]["pos"], PsxMath.s16_vec(e.particles[5]["pos"] + e.base), "N4: detached: pos + base")
	var ticks := 1
	while e.phase == 2 and ticks < 100:
		e.tick()
		ticks += 1
	_eq(ticks, 23, "N4: 23 frames up to velocity >= 0")
	_eq(e.frame, 103, "N4: phase 3 from frame 103")
	e.tick()
	_eq(e.events, ["stop_sound"], "N5: stopSound")
	_eq(e.result(), -1, "N5: frame -1")
	_eq(e.active, false, "N5: over")
	_eq(e.render(), [], "N5: the particles removed")
