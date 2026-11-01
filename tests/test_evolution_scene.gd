extends SceneTree
## Step 5f-2, the evolution scene (specs/evolution_scene.md): the acceptance checks, written from the C
## by the reviewer (the expected values are §3's, not the port's). Don't change them to make the
## code pass; when one looks wrong, report it with the C line (spec §0).
##   DW_STEP_5F_2=<step> godot --headless --path . -s res://tests/test_evolution_scene.gd
## A check runs once its step (spec §6) is reached; the others print PENDING. Exits 1 if a check fails.

const SEQUENCE := "res://scripts/field/evolution/evl_sequence.gd"
const SHARD_SETS := "res://scripts/field/evolution/evl_shard_sets.gd"
const SPARKS := "res://scripts/field/evolution/evl_sparks.gd"
const PARTICLES := "res://scripts/field/evolution/evl_particles.gd"
const BRIGHTEN := "res://scripts/field/evolution/palette_brighten.gd"

## D3: the break frames before 0x9B (0x6A, then EVL_D_80063EFC's entries >= 0 from 0x70).
const BREAK_TABLE := [0x6A, 0x70, 0x80, 0x8A, 0x92, 0x96, 0x98, 0x9A]
## EVL_D_80063F28 (evl.c:262): the rings' pattern (H1).
const RING_TABLE := [1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
const LOCATION := Vector3i(200, 0, -300)
const ROTATION_Y := 0x200
## Agumon -> Greymon: (radius, height) from digimon_data (checked against the data below).
const OLD := Vector2i(120, 250)
const NEW := Vector2i(230, 400)
## A 22-bone body (Agumon's count); bones 5 and 9 have no object (D4): 19 breaks, 3 without a spark.
const BONES := 22
const NO_OBJECT := [0, 5, 9]
const SAVED := {"eye": Vector3i(500, -1500, -2500), "ref": Vector3i(100, -200, 0), "offset": Vector2i(0x90, 0x70), "projection": 350}
## The fake animations play this many frames.
const ANIM_LENGTH := 15
const MODE_TRI := 0x34
const MODE_QUAD := 0x3C

var _failed := 0
var _checks := 0
var _pending: Array[String] = []
var _missing: Array[String] = []
var _step := 0

## What the sequence asked for, by frame (the fakes record into these).
var _f := 0
var _anim_ticks := 0
var views := {}
var restores: Array = []
var applied: Array = []
var sounds: Array = []
var anims: Array = []
var breaks: Array = []
var events: Array = []


func _initialize() -> void:
	_step = int(OS.get_environment("DW_STEP_5F_2")) if OS.get_environment("DW_STEP_5F_2").is_valid_int() else 0
	var data: Node = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: data porter output missing")
		quit(0)
		return
	PsxMath.setup(data)
	for key_size in [["dw1:agumon", OLD], ["dw1:greymon", NEW]]:
		var rec: Dictionary = data.digimon(key_size[0])
		_eq(Vector2i(int(rec.get("radius", 0)), int(rec.get("height", 0))), key_size[1], "C3: %s's radius and height" % key_size[0])
	_eq(int(data.digimon("dw1:agumon").get("bone_count", 0)), BONES, "D2: Agumon's bone count")
	data.free()

	if _gate(1, "the sequence (timeline, camera, bones, bodies, flashes, fades)"):
		_test_sequence()
	if _gate(3, "the shard sets"):
		_test_shard_sets()
	if _gate(4, "the sparks and the particles"):
		_test_sparks()
		_test_particles()
	if _gate(5, "the brighten"):
		_test_brighten()

	var state := "OK" if _failed == 0 else "FAILED %d" % _failed
	if not _missing.is_empty():
		state += "; missing: " + ", ".join(_missing)
	if not _pending.is_empty():
		state += "; PENDING (DW_STEP_5F_2=%d): %s" % [_step, ", ".join(_pending)]
	print("%s: evolution scene checks (%d run)" % [state, _checks])
	quit(1 if _failed else 0)


# --- helpers --------------------------------------------------------------------------------------

func _gate(step: int, what: String) -> bool:
	if _step >= step:
		return true
	_pending.append("step %d: %s" % [step, what])
	return false


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL: %s" % msg)


func _eq(got: Variant, want: Variant, msg: String) -> void:
	_check(got == want, "%s (got %s, want %s)" % [msg, got, want])


## The script at `path`, or null (counted as one failure).
func _script(path: String) -> Variant:
	if not ResourceLoader.exists(path):
		_missing.append(path.get_file())
		_check(false, "%s exists (spec §5)" % path)
		return null
	return load(path)


## An untyped copy, so typed and untyped arrays compare by their elements.
static func _plain(a: Variant) -> Array:
	return Array(a).map(func(x): return x) if a is Array or a is PackedInt32Array else []


## How many rand() draws the code made since set_seed(seed): the next value matches the replay's.
func _rand_draws(seed: int, after: int, max_draws := 40) -> int:
	for n in max_draws:
		Rng.set_seed(seed)
		for i in n:
			Rng.rand()
		if Rng.rand() == after:
			return n
	return -1


## The first `n` rand() of seed `seed`.
static func _rolls(seed: int, n: int) -> Array:
	Rng.set_seed(seed)
	var out := []
	for i in n:
		out.append(Rng.rand())
	return out


static func _lerp(a: int, b: int, t0: int, t1: int, t: int) -> int:
	return PsxMath.lerp_int(a, b, t0, t1, t)


static func _lerp3(a: Vector3i, b: Vector3i, t0: int, t1: int, t: int) -> Vector3i:
	return Vector3i(_lerp(a.x, b.x, t0, t1, t), _lerp(a.y, b.y, t0, t1, t), _lerp(a.z, b.z, t0, t1, t))


## C1: the orbit's reference point and eye for a total rotation y, a height and a distance.
static func _orbit(rotation: int, height: int, distance: int) -> Array:
	var ref := Vector3i(LOCATION.x, LOCATION.y - height / 2, LOCATION.z)
	var m := PsxMath.rot_matrix_zyx(Vector3i(0, rotation, 0))
	var eye := PsxMath.apply_matrix_lv(m, Vector3i(0, 0, distance)) + ref
	eye.y += -0x190 - 2 * height
	return [ref, eye]


## C2.
static func _distance(size: Vector2i) -> int:
	return maxi(size.x, size.y) * 5 + 0x4B0


## A sidecar-style object: `faces` = [[mode, [vertex indices], [normal indices]], ...].
static func _object(faces: Array) -> Dictionary:
	var prims := []
	for f: Array in faces:
		prims.append({"mode": f[0], "vertices": f[1], "normals": f[2] if f.size() > 2 else f[1],
				"uvs": f[1].map(func(_v): return [0, 0]), "tsb": 0x16, "cba": 0})
	return {"primitives": prims, "n_primitive": prims.size()}


# --- the sequence (EvlSequence) ------------------------------------------------------------------

## The bone order (D1) replayed: EVL_D_80067994's 40 entries.
static func _bone_order(seed: int) -> Array:
	var order := []
	order.resize(BONES)
	Rng.set_seed(seed)
	for i in range(1, BONES):
		order[i] = Rng.rand() & 0xFFF
	var list := []
	for i in range(1, BONES):
		var best := 1
		var best_val: int = order[1]
		for j in range(2, BONES):
			if best_val > order[j]:
				best = j
				best_val = order[j]
		list.append(best)
		order[best] = 0x1000
	list.append(-2)
	while list.size() < 40:
		list.append(-1)
	return list


## D3 / D4: [frame, bone] for every break, from the replayed order.
static func _want_breaks(order: Array) -> Array:
	var bones := order.filter(func(b): return b > 0 and not b in NO_OBJECT)
	var frames := BREAK_TABLE.duplicate()
	while frames.size() < bones.size():
		frames.append(0x9B + frames.size() - BREAK_TABLE.size())
	var out := []
	for i in bones.size():
		out.append([frames[i], bones[i]])
	return out


func _new_sequence() -> Object:
	var script: Variant = _script(SEQUENCE)
	if script == null:
		return null
	var seq: Object = script.new()
	seq.set("get_view", func() -> Dictionary: return SAVED.duplicate())
	seq.set("set_view", func(v: Dictionary) -> void: views[_f] = v.duplicate())
	seq.set("restore_view", func() -> void: restores.append(_f))
	seq.set("bone_position", func(b: int) -> Vector3i: return LOCATION + Vector3i(b * 10, -b * 5, b * 3))
	seq.set("apply_evolution", func() -> void: applied.append(_f))
	seq.set("play_sound", func(slot: int, value: int) -> void: sounds.append([_f, slot, value]))
	seq.set("stop_sound", func() -> void: sounds.append([_f, "stop"]))
	seq.set("start_animation", func(id: int) -> void:
		anims.append([_f, id])
		_anim_ticks = 0)
	seq.set("animation_done", func() -> bool: return _anim_ticks >= ANIM_LENGTH)
	for sig in ["bone_broken", "hand_over", "applied", "ended"]:
		if not seq.has_signal(sig):
			_missing.append("EvlSequence." + sig)
			_check(false, "EvlSequence.%s exists (spec §5)" % sig)
	return seq


func _test_sequence() -> void:
	var seq := _new_sequence()
	if seq == null:
		return
	if seq.has_signal("bone_broken"):
		seq.connect("bone_broken", func(bone: int) -> void:
			breaks.append([_f, bone])
			if _step >= 3 and seq.get("shards") != null:
				# The host's answer (spec §5): a set from the posed bone, in the same call.
				seq.get("shards").build(bone, _object([[MODE_TRI, [0, 1, 2]]]),
						[Vector3i(bone, 0, 0), Vector3i(bone, -10, 0), Vector3i(bone, 0, 10)],
						[Vector3i(0, -4096, 0), Vector3i(0, -4096, 0), Vector3i(0, -4096, 0)]))
	for sig in ["hand_over", "applied", "ended"]:
		if seq.has_signal(sig):
			seq.connect(sig, func() -> void: events.append([_f, sig]))

	# D1: the bone order, the only rolls of init.
	var objects := PackedInt32Array()
	for b in BONES:
		objects.append(-1 if b in NO_OBJECT else b)
	Rng.set_seed(77)
	seq.init(BONES, objects, LOCATION, ROTATION_Y, OLD, NEW)
	_eq(_rand_draws(77, Rng.rand(), 60), BONES - 1, "D1: boneCount - 1 rand() in EVL_initEvoSequence")
	var order := _bone_order(77)
	_eq(_plain(seq.get("bone_order")), order, "D1: the bone order (lowest roll first, ties to the lowest index; -2 after the last)")
	_eq([seq.get("timer"), seq.get("state")], [0, 0], "EVL_initEvoSequence: timer 0, state 0")

	# Run it, one rand() seed per frame so each frame's rolls can be replayed.
	var rec := {}
	var guard := 0
	while int(seq.get("timer")) >= 0 and guard < 800:
		_f = int(seq.get("timer"))
		Rng.set_seed(1000 + _f)
		seq.tick()
		var r := {"draws": _rand_draws(1000 + _f, Rng.rand(), 16), "timer": seq.get("timer"), "state": seq.get("state"),
				"map_fade": seq.get("map_fade"), "bank0": seq.get("bank0_factor"), "bank1": seq.get("bank1_factor"),
				"brighten": seq.get("brighten"), "brighten_t": seq.get("brighten_t"), "scale": seq.get("scale"),
				"total": seq.get("wireframe_total"), "sub": _plain(seq.get("wireframe_sub")), "angle": seq.get("angle")}
		var fx: Variant = seq.get("fx")
		r["new_flashes"] = (fx as BattleFx).flashes.filter(func(x): return x["progress"] == 0).map(func(x): return x.duplicate()) \
				if fx is BattleFx else []
		var sh: Variant = seq.get("shards")
		if sh != null:
			r["sets"] = (sh.get("sets") as Array).map(func(x): return int(x["timer"]))
		var sp: Variant = seq.get("sparks")
		if sp != null:
			r["sparks"] = (sp.get("sparks") as Array).map(func(x): return [int(x["bone"]), int(x["timer"])])
		var pa: Variant = seq.get("particles")
		if pa != null:
			r["particles"] = (pa.get("particles") as Array).map(func(x): return x.duplicate())
		rec[_f] = r
		_anim_ticks += 1
		guard += 1
	var last := _f
	_check(int(seq.get("timer")) == -1, "K3: the sequence ends (timer -1) within 800 frames")
	var want_breaks := _want_breaks(order)
	var break_frames := {}
	for b in want_breaks:
		break_frames[b[0]] = b[1]

	_check_timeline(rec, last)
	_check_rolls(rec, break_frames)
	_check_camera(rec)
	_check_bones(rec, want_breaks)
	_check_bodies(rec, want_breaks)
	_check_flashes(rec, break_frames)
	_check_fades(rec)
	if _gate(3, "the sequence's shard sets"):
		_check_sequence_sets(rec, want_breaks)
	if _gate(4, "the sequence's sparks and particles"):
		_check_sequence_sparks(rec, want_breaks)
		_check_sequence_particles(rec)


## A4, A5, B9, J5, K1-K3: the states, the signals, the animations, the apply.
func _check_timeline(rec: Dictionary, last: int) -> void:
	var bad := []
	for f in rec:
		if f == last:
			continue
		var want_state := 0 if f < 0x20 else (1 if f < 0x6A else (2 if f < 0x162 else (3 if f == 0x162 else 4)))
		if rec[f]["state"] != want_state or rec[f]["timer"] != f + 1:
			bad.append("0x%X: state %s timer %s" % [f, rec[f]["state"], rec[f]["timer"]])
	_check(bad.is_empty(), "A4: state 1 from 0x21, 2 from 0x6B, 3 at 0x163, 4 after; timer + 1 a frame: %s" % ", ".join(bad.slice(0, 5)))
	_eq(last, 0x163 + ANIM_LENGTH, "K3: state 4 ends when 0xB has played (started at 0x163)")
	_eq(events, [[0x20, "hand_over"], [0x11C, "applied"], [0x163, "ended"]], "B9 / J5 / K2: the hand-over, the apply, the end")
	_eq(applied, [0x11C], "J5: EVL_applyEvolution once, at 0x11C")
	_eq(anims, [[0x6A, 0xC], [0x6A + ANIM_LENGTH, 1], [0x11C, 0], [0x163, 0xB]],
			"A5 / J5 / K2: 0xC at the first break, 1 when it ends, 0 at the apply, 0xB at the end")


## B7, D5, G2, I3: the rand() draws of each frame, in the C's order.
func _check_rolls(rec: Dictionary, break_frames: Dictionary) -> void:
	var bad := []
	for f in rec:
		var want := 0
		if f <= 0x20:
			want = 3
		elif f == 0x163:
			want = 6
		else:
			if f >= 0x70 and f <= 0xCC:
				want += 3
			if break_frames.has(f):
				want += 1
			if f >= 0xD8 and f <= 0x11A and f % 2 == 0:
				want += 3
		if rec[f]["draws"] != want:
			bad.append("0x%X: %s want %d" % [f, rec[f]["draws"], want])
	_check(bad.is_empty(), "B7 / D5 / G2 / I3: rand() per frame: %s" % ", ".join(bad.slice(0, 6)))
	# The break sound: rand() % 3 + 2, after the brighten's three rolls when both run (G1 before D5).
	var at_6a := _rolls(1000 + 0x6A, 1)
	var at_80 := _rolls(1000 + 0x80, 4)
	_eq(sounds.filter(func(s): return s[0] == 0x6A), [[0x6A, 8, 1], [0x6A, 8, 0], [0x6A, 8, at_6a[0] % 3 + 2]],
			"0x6A: sounds (8, 1), (8, 0), then the break's (8, rand() % 3 + 2)")
	_eq(sounds.filter(func(s): return s[0] == 0x80), [[0x80, 8, at_80[3] % 3 + 2]], "D5: at 0x80 the break's roll comes after the brighten's three")
	_eq(sounds.filter(func(s): return s[0] == 0xD6), [[0xD6, "stop"], [0xD6, 8, 5]], "I1: 0xD6 stops the sounds, plays (8, 5)")
	var break_sounds := sounds.filter(func(s): return s.size() == 3 and s[1] == 8 and s[2] >= 2 and s[2] <= 4)
	_eq(break_sounds.map(func(s): return s[0]), break_frames.keys(), "D5: one (8, 2-4) per break, nothing else")


## C5-C13: the views the sequence set, frame by frame.
func _check_camera(rec: Dictionary) -> void:
	var t := _lerp(0, 20, 0, 200, OLD.y)
	_eq(t, 4, "C7: lerp(0, 20, 0, 200, 250) = 4 (the wrap)")
	var d_old := _distance(OLD)
	_eq([d_old, _distance(NEW)], [2450, 3200], "C3: the orbit distances")
	var o := _orbit(0x638 + ROTATION_Y, OLD.y, d_old)
	var want := {}
	for f in range(0x21, 0x41):
		want[f] = {"eye": SAVED["eye"], "ref": _lerp3(SAVED["ref"], o[0], 0x20, 0x40, f),
				"offset": Vector2i(_lerp(SAVED["offset"].x, 160, 0x20, 0x40, f), _lerp(SAVED["offset"].y, 120, 0x20, 0x40, f)),
				"projection": SAVED["projection"]}
	for f in range(0x41, 0x61):
		want[f] = {"eye": _lerp3(SAVED["eye"], o[1], 0x40, 0x60, f), "ref": o[0],
				"offset": Vector2i(160, _lerp(120, 120 + t, 0x40, 0x60, f)), "projection": _lerp(SAVED["projection"], 1000, 0x40, 0x60, f)}
	var angle := 0x638
	var angles := {}
	for f in range(0x61, 0x6B):
		angle += 0x16
		angles[f] = angle
		var a := _orbit(angle + ROTATION_Y, OLD.y, d_old)
		want[f] = {"eye": a[1], "ref": a[0], "offset": Vector2i(160, 124), "projection": 1000}
	for f in range(0xA5, 0x163):
		angle += 0x16 if f >= 0xC3 else _lerp(0, 0x16, 0xA4, 0xC2, f)
		angles[f] = angle
		var size := OLD if f < 0xCC else (NEW if f >= 0x108 else
				Vector2i(_lerp(OLD.x, NEW.x, 0xCC, 0x108, f), _lerp(OLD.y, NEW.y, 0xCC, 0x108, f)))
		var a := _orbit(angle + ROTATION_Y, size.y, _distance(size))
		want[f] = {"eye": a[1], "ref": a[0], "offset": Vector2i(160, 124), "projection": 1000}
	_eq([angles[0x6A], angles[0xA5], angles[0xB3], angles[0xC2], angles[0xC3], angles[0x162]],
			[0x714, 0x714, 0x765, 0x85B, 0x871, 0x161B], "C12: the reviewer's angle replay (sanity)")
	_eq(_lerp(OLD.y, NEW.y, 0xCC, 0x108, 0xEA) * 5 + 0x4B0, 2825, "C3: the distance at 0xEA")
	var bad := []
	for f in want:
		if views.get(f) != want[f]:
			bad.append("0x%X: %s want %s" % [f, views.get(f), want[f]])
	_check(bad.is_empty(), "C6 / C8 / C11: the views 0x21-0x6A and 0xA5-0x162: %s" % "; ".join(bad.slice(0, 3)))
	var stray := []
	for f in views:
		if f <= 0x20 or f > 0x162 or (f > 0x6A and f < 0xA5 and views[f] != want[0x6A]):
			stray.append("0x%X" % f)
	_check(stray.is_empty(), "C5 / C9 / C13: no other view set (0x6B-0xA4 keep 0x6A's): %s" % ", ".join(stray))
	for f in [0x6A, 0xB3, 0xC2, 0xC3, 0x162]:
		_eq(rec[f]["angle"], angles[f], "C12: the angle after 0x%X" % f)
	# C13: the C also restores at 0x162; port-only (the user, 2026-11-01): only with the rest, at 0x163.
	_eq(restores, [0x163], "C13: the saved view back at 0x163, with the colours (port-only: not at 0x162)")


## D1-D5, F1: the breaks.
func _check_bones(rec: Dictionary, want_breaks: Array) -> void:
	_eq(want_breaks.size(), BONES - 1 - 2, "D4: the reviewer's breaks (sanity)")
	_eq(breaks, want_breaks, "D3 / D4: one bone per break frame, in the order, those without an object skipped")


## J1, J3-J7: the wireframe shares and the scale.
func _check_bodies(rec: Dictionary, want_breaks: Array) -> void:
	var bad := []
	var ratio := Vector2i((NEW.x << 12) / OLD.x, (NEW.y << 12) / OLD.y)
	_eq(ratio, Vector2i(7850, 6553), "J4: the ratios (sanity)")
	for f in rec:
		var total := 16
		if f >= 0x11C and f < 0x126:
			total = 0
		elif f >= 0x126 and f < 0x14E:
			total = _lerp(0, 0x10, 0x126, 0x14E, f)
		var sub := []
		for b in 40:
			var broken: bool = f < 0x11C and want_breaks.any(func(x): return x[1] == b and x[0] <= f)
			sub.append(0 if broken else 16)
		var g := clampi(f, 0xCC, 0x107)
		var sx := 4096 if f < 0xCC or f >= 0x11C else _lerp(0x1000, ratio.x, 0xCC, 0x108, g)
		var sy := 4096 if f < 0xCC or f >= 0x11C else _lerp(0x1000, ratio.y, 0xCC, 0x108, g)
		var scale := Vector3i(sx, sy, sx)
		if rec[f]["total"] != total or rec[f]["sub"] != sub or rec[f]["scale"] != scale:
			bad.append("0x%X: total %s want %d, scale %s want %s%s" % [f, rec[f]["total"], total, rec[f]["scale"], scale,
					"" if rec[f]["sub"] == sub else ", sub differs"])
	_check(bad.is_empty(), "J1 / J3 / J5 / J6 / J7: the shares and the scale frame by frame: %s" % "; ".join(bad.slice(0, 4)))
	_eq([rec[0x126]["total"], rec[0x13A]["total"], rec[0x14D]["total"], rec[0x14E]["total"]], [0, 8, 15, 16], "J7: expected totals")
	_eq([rec[0xEA]["scale"], rec[0x107]["scale"]], [Vector3i(5973, 5324, 5973), Vector3i(7787, 6512, 7787)], "J4: expected scales")


## D6, I2-I5: the flashes made each frame.
func _check_flashes(rec: Dictionary, break_frames: Dictionary) -> void:
	var bad := []
	var centre := 0
	var front := 0
	for f in rec:
		var want := []
		if break_frames.has(f):
			var b: int = break_frames[f]
			want.append({"mode": 1, "position": LOCATION + Vector3i(b * 10, -b * 5, b * 3), "fixed_depth": -1, "t_max": 10,
					"scale_min": 0, "scale_max": 0x333, "color_min": Vector3i(0x96, 0x96, 0x96), "color_max": Vector3i(0x14, 0x14, 0x14)})
		if f >= 0xD8 and f <= 0x11A and f % 2 == 0:
			var base := _lerp(0x32, 0x78, 0xD6, 0x11C, f)
			var r := _rolls(1000 + f, 3)
			var mask := _lerp(5, 1, 0xD6, 0x11C, f)
			want.append({"mode": 0, "position": LOCATION + Vector3i(10, -5, 3), "fixed_depth": 0x21 if (f & mask) == 0 else 0xFA0,
					"t_max": 10, "scale_min": 0, "scale_max": _lerp(0x333, 0x4800, 0xD6, 0x11C, f),
					"color_min": Vector3i(base + r[0] % 100, base + r[1] % 100, base + r[2] % 100), "color_max": Vector3i(0x14, 0x14, 0x14)})
			centre += 1
			front += 1 if (f & mask) == 0 else 0
		var got: Array = rec[f]["new_flashes"].map(func(x): return {"mode": x["mode"], "position": x["position"],
				"fixed_depth": x["fixed_depth"], "t_max": x["t_max"], "scale_min": x["scale_min"], "scale_max": x["scale_max"],
				"color_min": x["color_min"], "color_max": x["color_max"]})
		if got != want:
			bad.append("0x%X: %s want %s" % [f, got, want])
	_check(bad.is_empty(), "D6 / I3 / A3: the flashes made each frame (progress 0 in their frame): %s" % "; ".join(bad.slice(0, 2)))
	_eq([centre, front], [34, 17], "I2 / I4: 34 centre flashes, 17 drawn in front")
	_eq([_lerp(0x333, 0x4800, 0xD6, 0x11C, 0xD8), _lerp(0x333, 0x4800, 0xD6, 0x11C, 0x11A), _lerp(0x32, 0x78, 0xD6, 0x11C, 0xF8)],
			[0x52A, 0x4608, 84], "I4: expected scales and colour base")
	var fx := BattleFx.new()
	for i in 13:
		fx.create_flash(0, Vector3i.ZERO, -1, 10, 0, 1, Vector3i.ONE, Vector3i.ONE)
	_eq(fx.flashes.filter(func(x): return x["progress"] >= 0).size(), 12, "I5: 12 flash slots")


## B1, B4, B5, G1, G2, G5: the fade levels and the brighten values.
func _check_fades(rec: Dictionary) -> void:
	var bad := []
	for f in rec:
		var want := (_lerp(0, 0xFF, 0, 0x20, f) if f < 0x20 else 0xFF) if f < 0x163 else 0
		if rec[f]["map_fade"] != want:
			bad.append("0x%X: %s want %d" % [f, rec[f]["map_fade"], want])
	_check(bad.is_empty(), "B1 / K2: map_fade frame by frame: %s" % ", ".join(bad.slice(0, 5)))
	_eq([rec[0]["map_fade"], rec[1]["map_fade"], rec[16]["map_fade"], rec[31]["map_fade"], rec[32]["map_fade"]], [0, 7, 127, 247, 255],
			"B1: expected levels")
	_eq([rec[0]["bank0"], rec[8]["bank0"], rec[9]["bank0"], rec[9]["bank1"], rec[16]["bank0"], rec[31]["bank1"], rec[32]["bank0"]],
			[1.0, 0.75, 0.75, 23.0 / 32.0, 0.5, 1.0 / 32.0, 0.0], "B4 / B5: bank 0 on even frames, bank 1 on odd ones, (32 - f) / 32")
	_eq([rec[0x100]["bank0"], rec[0x100]["bank1"], rec[0x163]["bank0"], rec[0x163]["bank1"]], [0.0, 1.0 / 32.0, 1.0, 1.0],
			"B4 / K2: dark until 0x163, then full colour")
	bad = []
	for f in rec:
		var want_t := -1
		var want_b: Variant = null
		if f >= 0x70 and f <= 0xCC:
			var r := _rolls(1000 + f, 3)
			want_t = mini(f, 0x9A)
			want_b = Vector3i(r[0] % 100, r[1] % 100, r[2] % 100)
		elif f > 0xCC and f < 0x11C:
			want_t = 0x9A
			want_b = rec[0xCC]["brighten"]
		if rec[f]["brighten_t"] != want_t or (want_b != null and rec[f]["brighten"] != want_b):
			bad.append("0x%X: %s / %s want %s / %s" % [f, rec[f]["brighten"], rec[f]["brighten_t"], want_b, want_t])
	_check(bad.is_empty(), "G1 / G2 / G5: the brighten's factors (R G B rolls) and t frame by frame: %s" % "; ".join(bad.slice(0, 4)))


## E1, E6, E11: a set per break, timer 0 in its frame, 32 frames drawn, all gone before the apply.
func _check_sequence_sets(rec: Dictionary, want_breaks: Array) -> void:
	var bad := []
	for f in rec:
		if not rec[f].has("sets"):
			bad.append("0x%X: no shards" % f)
			break
		var alive: Array = rec[f]["sets"].filter(func(t): return t >= 0)
		var want: Array = want_breaks.filter(func(x): return x[0] <= f and x[0] >= f - 31).map(func(x): return f - x[0])
		alive.sort()
		want.sort()
		if alive != want:
			bad.append("0x%X: %s want %s" % [f, alive, want])
	_check(bad.is_empty(), "E1 / E6 / A3: the sets' timers frame by frame: %s" % "; ".join(bad.slice(0, 3)))
	_check(rec[0x11C].get("sets", [0]).all(func(t): return t < 0), "E11: every set gone before the apply")


## F1, F2: the first 16 breaks get a spark with timer 0x11C - f; they last until 0x11D.
func _check_sequence_sparks(rec: Dictionary, want_breaks: Array) -> void:
	var bad := []
	for i in want_breaks.size():
		var f: int = want_breaks[i][0]
		var b: int = want_breaks[i][1]
		var list: Array = rec[f].get("sparks", [])
		var has := list.has([b, 0x11C - f])
		if has != (i < 16):
			bad.append("break %d (0x%X, bone %d): %s" % [i, f, b, "a spark" if has else "none"])
	_check(bad.is_empty(), "F1 / F2: sparks for the first 16 breaks only, timer 0x11C - f: %s" % ", ".join(bad))
	var alive := func(f: int) -> int: return (rec[f].get("sparks", []) as Array).filter(func(s): return s[0] >= 0).size()
	_eq([alive.call(0xA5), alive.call(0x11D), alive.call(0x11E)], [16, 16, 0], "F1 / F2: 16 alive, the last drawn at 0x11D")


## H1, H2, H4, H8: one ring on the pattern's frames of state 2, from the start location.
func _check_sequence_particles(rec: Dictionary) -> void:
	var bad := []
	for f in rec:
		var fresh: Array = (rec[f].get("particles", []) as Array).filter(func(p): return p["timer"] == 0)
		var want := []
		if f >= 0x6B and f <= 0x162 and RING_TABLE[f % 18] != 0:
			want.append([LOCATION, Vector3i(0x0A, _lerp(0x32, 0xE6, 1, 5, RING_TABLE[f % 18]), 0x0A)])
		var got := fresh.map(func(p): return [p["pos"], p["color"]])
		if got != want:
			bad.append("0x%X: %s want %s" % [f, got, want])
	_check(bad.is_empty(), "H1 / H2: the rings made each frame: %s" % "; ".join(bad.slice(0, 3)))
	# H4: the ring of 0x6C (108 % 18 = 0) lives until 0x6C + 0x56.
	var slot := -1
	var at: Array = rec[0x6C].get("particles", [])
	for i in at.size():
		if at[i]["timer"] == 0:
			slot = i
	_check(slot >= 0 and rec[0x6C + 0x56]["particles"][slot]["timer"] == 0x56 and rec[0x6C + 0x57]["particles"][slot]["timer"] == -1,
			"H4: drawn at timers 0 to 0x56, removed by the next tick")
	_check(rec[0x163].get("particles", [{"timer": 0}]).all(func(p): return p["timer"] < 0), "H8: all released at 0x163")


# --- E: the shard sets (EvlShardSets) ------------------------------------------------------------

func _test_shard_sets() -> void:
	var script: Variant = _script(SHARD_SETS)
	if script == null:
		return
	_eq([script.grey(0), script.grey(15), script.grey(31)], [130, 93, 54], "E5: the grey")
	# A triangle, a quad (0x3E: semi-transparent quads count, E3), a 0x2C face, then a triangle never read.
	var obj := _object([[MODE_TRI, [0, 1, 2], [0, 1, 2]], [MODE_QUAD | 2, [3, 4, 5, 6], [3, 4, 5, 6]], [0x2C, [0, 1, 2]],
			[MODE_TRI, [0, 1, 2], [0, 1, 2]]])
	var verts: Array[Vector3i] = [Vector3i(0, -50, 0), Vector3i(10, -50, 0), Vector3i(0, -60, 30), Vector3i(100, 0, 0),
			Vector3i(110, 0, 0), Vector3i(100, -10, 0), Vector3i(110, -10, 0)]
	var normals: Array[Vector3i] = [Vector3i(0, 4096, 0), Vector3i(0, 4096, 0), Vector3i(0, 0, 4096), Vector3i(-700, 0, 0),
			Vector3i(-700, 0, 0), Vector3i(-701, 0, 0), Vector3i(4096, 4096, 4096)]
	var sets: Variant = script.new()
	var slot: int = sets.build(3, obj, verts, normals)
	_eq(slot, 0, "E1: the first free slot")
	var s: Dictionary = sets.sets[slot]
	_eq(_plain(s.get("drifts")), [Vector3i(0, 2730, 1365), Vector3i(-700, 0, 0)],
			"E3: the mean of the first three normals (quads too, truncated), none after the 0x2C face")
	_eq(int(s["timer"]), 0, "E6: a new set's timer is 0")
	_eq(sets.faces(s).map(func(x): return x["points"]), [[verts[0], verts[1], verts[2]], [verts[3], verts[4], verts[5], verts[6]]],
			"E4 / E9: at timer 0 the faces sit on the body; the 0x2C face ends the set")
	for i in 7:
		sets.tick()
	# E4: drift × 7 / 60, truncated: (0, 318, 159) and (-81, 0, 0) (floor would give -82).
	var off_a := Vector3i(0, 318, 159)
	var off_b := Vector3i(-81, 0, 0)
	_eq(sets.faces(s).map(func(x): return x["points"]), [[verts[0] + off_a, verts[1] + off_a, verts[2] + off_a],
			[verts[3] + off_b, verts[4] + off_b, verts[5] + off_b, verts[6] + off_b]], "E4: drift × timer / 60 at timer 7")
	for i in 24:
		sets.tick()
	_eq(int(sets.sets[slot]["timer"]), 31, "E6: timer 31 after 31 ticks")
	sets.tick()
	_eq(int(sets.sets[slot]["timer"]), -1, "E6: removed by the 32nd tick")
	for i in 30:
		sets.build(3, obj, verts, normals)
	_eq(sets.build(3, obj, verts, normals), -1, "E1: no 31st set")


# --- F: the sparks (EvlSparks) -------------------------------------------------------------------

func _test_sparks() -> void:
	var script: Variant = _script(SPARKS)
	if script == null:
		return
	# F3-F7 replayed: bone at (100, -50, 30), bone 1 at (0, -100, 0): d = (100, 50, 30), lenSq 13400.
	Rng.set_seed(11)
	var got: Dictionary = script.streak(Vector3i(100, -50, 30), Vector3i(0, -100, 0))
	Rng.set_seed(11)
	var s := Rng.custom_random(0x190, 0x1F4)
	s *= s
	var centre := Vector3i(0, -100, 0)
	var tip := centre + Vector3i(PsxMath.div(100 * s, 13400), PsxMath.div(50 * s, 13400), PsxMath.div(30 * s, 13400))
	var jit := tip + Vector3i(Rng.custom_random(-0x50, 0x50), Rng.custom_random(-0x50, 0x50), Rng.custom_random(-0x50, 0x50))
	var grey := Rng.rand() % 128 + 10
	_eq([got.get("origin"), got.get("a"), got.get("b"), got.get("grey")], [centre, tip, jit, grey],
			"F3 / F5 / F6: origin = bone 1, a = the tip, b = the tip jittered, then the grey (SparkStreaks' keys)")
	# F4: bone 1's own spark divides 0 by 0: the R3000A's -1.
	Rng.set_seed(12)
	got = script.streak(centre, centre)
	Rng.set_seed(12)
	Rng.custom_random(0x190, 0x1F4)
	jit = centre - Vector3i.ONE + Vector3i(Rng.custom_random(-0x50, 0x50), Rng.custom_random(-0x50, 0x50), Rng.custom_random(-0x50, 0x50))
	_eq([got.get("a"), got.get("b")], [centre - Vector3i.ONE, jit], "F4: lenSq 0 gives a = origin - (1, 1, 1)")
	# F1 / F2.
	var sparks: Variant = script.new()
	_eq(sparks.spawn(3, 2), 0, "F1: the first free slot")
	for i in 15:
		sparks.spawn(4, 50)
	_eq(sparks.spawn(5, 50), -1, "F1: no 17th spark")
	var bone_after := []
	for i in 4:
		sparks.tick()
		bone_after.append([int(sparks.sparks[0]["bone"]), int(sparks.sparks[0]["timer"])])
	_eq(bone_after, [[3, 1], [3, 0], [3, -1], [-1, -1]], "F2: timer - 1 a tick, drawn at -1, removed after")


# --- H: the particles (EvlParticles) -------------------------------------------------------------

func _test_particles() -> void:
	var script: Variant = _script(PARTICLES)
	if script == null:
		return
	var p := {"timer": 1, "pos": Vector3i(100, -20, 50), "color": Vector3i(10, 230, 10)}
	_eq(_plain(script.corners(p)), [Vector3i(136, -20, 86), Vector3i(136, -20, 14), Vector3i(64, -20, 14), Vector3i(64, -20, 86)],
			"H5: the square at timer 1 (s = 36), corners (+,+) (+,-) (-,-) (-,+)")
	p["timer"] = 0x56
	_eq(script.corners(p)[0], Vector3i(100 + 2500, -20, 50 + 2500), "H5: s = 2500 at 0x56")
	p["timer"] = 43
	_eq(script.color(p), Vector3i(5, 115, 5), "H6: the colour at timer 43")
	p["timer"] = 0x55
	_eq(script.color(p).y, 3, "H6: g 230 at 0x55")
	var parts: Variant = script.new()
	_eq(parts.spawn(Vector3i.ZERO, Vector3i.ONE), 0, "H3: the first free slot")
	for i in 99:
		parts.spawn(Vector3i.ZERO, Vector3i.ONE)
	_eq(parts.spawn(Vector3i.ZERO, Vector3i.ONE), -1, "H3: no 101st")
	for i in 0x56:
		parts.tick()
	_eq(int(parts.particles[0]["timer"]), 0x56, "H4: timer 0x56 after 0x56 ticks")
	parts.tick()
	_eq(int(parts.particles[0]["timer"]), -1, "H4: removed by the next")
	parts.spawn(Vector3i.ZERO, Vector3i.ONE)
	parts.release_all()
	_check((parts.particles as Array).all(func(x): return x["timer"] < 0), "H8: release_all")


# --- G: the brighten (PaletteBrighten) -----------------------------------------------------------

func _test_brighten() -> void:
	var script: Variant = _script(BRIGHTEN)
	if script == null:
		return
	_eq([script.channel(10, 50, 0x85), script.channel(31, 99, 0x9A), script.channel(1, 99, 0x9A), script.channel(20, 0, 0x9A),
			script.channel(20, 99, 0x70)], [15, 31, 30, 20, 20], "G3 / G4: one channel")
	_eq(script.colour(Vector3i.ZERO, Vector3i(99, 99, 99), 0x9A), Vector3i.ZERO, "G3: black stays black")
	_eq(script.colour(Vector3i(0, 0, 1), Vector3i(99, 50, 0), 0x9A), Vector3i(30, 15, 1),
			"G3: a colour with one channel set brightens all three")
