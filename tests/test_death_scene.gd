extends SceneTree
## Step 6-2, the death scene's look (specs/death_scene.md): the acceptance checks, written from the C
## by the reviewer (the expected values are §3's, not the port's). Don't change them to make the
## code pass; when one looks wrong, report it with the C line (spec §0).
##   godot --headless --path . -s res://tests/test_death_scene.gd
## Until step 6-2 is done the classes it checks don't exist: it reports them as failures. With
## DW_STEP_6_2=1 a failure exits 1; without it the suite prints PENDING and exits 0, so the other
## work's runs stay green (spec §7; step 9 removes the gate).

class FakeMusic extends RefCounted:
	func stop_bgm() -> void:
		pass


class FakeSound extends Node:
	var played: Array = []
	var music := FakeMusic.new()

	func play_sound(slot: int, value: int) -> int:
		played.append([slot, value])
		return 0

	func stop_sound() -> void:
		pass

	func load_map_sounds(_set_id: int) -> void:
		pass

	func load_partner_sounds(_sounds: Dictionary) -> void:
		pass


const FACE_GROUPS := "res://scripts/content/tmd_face_groups.gd"
const WIREFRAME := "res://scripts/field/partner_wireframe.gd"
const SHARDS := "res://scripts/field/death/dooa_shards.gd"
const CAMERA := "res://scripts/field/death/cutscene_camera.gd"
const PIECES := "res://scripts/field/death/egg_piece_shards.gd"
const STREAKS := "res://scripts/field/death/spark_streaks.gd"
const FADE := "res://scripts/field/death/palette_fade.gd"
const IRIS := "res://scripts/field/death/death_iris_math.gd"

## WIREFRAME_RNG_TABLE (model.c:2501).
const TABLE := [6, 3, 11, 8, 10, 13, 1, 4, 14, 7, 12, 15, 5, 2, 9, 0]
## DOOA_SHARD_WAVE_SCHEDULE (dooa.c:263).
const SCHEDULE := [15, 15, 15, 15, 15, 14, 14, 14, 14, 13, 13, 13, 12, 12, 12, 11, 11, 11, 10, 10, 10, 9, 9, 8,
		8, 7, 7, 6, 6, 5, 5, 4, 3, 2, 1, 0]
const MODE_TRI := 0x34
const MODE_QUAD := 0x3C

var _failed := 0
var _checks := 0
var _started := false
var _missing: Array[String] = []

var data: Node
var gs: Node
var sound: FakeSound
var tamer: Tamer
var partner: Partner
var dooa: DooaScene
var evo: Evolution
var care: Care
var map_changes: Array = []
## The views DooaScene asked FieldMap to show, by frame.
var views := {}
var restored := 0
var old_view := {"eye": Vector3i(0, -1000, -2000), "ref": Vector3i(0, 0, 0), "offset": Vector2i(0x90, 0x70), "projection": 300}
var room_view := {"eye": Vector3i(100, -1500, -1800), "ref": Vector3i(0, -100, 0), "offset": Vector2i(0x96, 0x70), "projection": 350}


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: data porter output missing")
		quit(0)
		return false
	PsxMath.setup(data)

	_test_face_groups()
	_test_shards()
	_test_camera_maths()
	_test_flash_offset()
	_test_pieces()
	_test_streaks()
	_test_fades_maths()
	_test_iris_maths()
	_setup_scene()
	_test_dissolve_timeline()
	_test_rebirth_timeline()

	var enforced := OS.get_environment("DW_STEP_6_2") == "1"
	var state := "OK" if _failed == 0 else ("FAILED %d" % _failed if enforced else "PENDING (step 6-2): %d failing" % _failed)
	if not _missing.is_empty():
		state += "; missing: " + ", ".join(_missing)
	print("%s: death scene checks (%d run)" % [state, _checks])
	quit(1 if _failed and enforced else 0)
	return false


# --- helpers --------------------------------------------------------------------------------------

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


## A DooaScene member added by 6-2, or null (counted as one failure, once).
func _member(obj: Object, member: String) -> Variant:
	var v: Variant = obj.get(member)
	if v == null and not ("DooaScene." + member) in _missing:
		_missing.append("DooaScene." + member)
		_check(false, "DooaScene.%s exists (spec §5)" % member)
	return v


## An untyped copy, so typed and untyped arrays compare by their elements.
static func _plain(a: Variant) -> Array:
	return (a as Array).map(func(x): return x) if a is Array else []


## How many rand() draws the code made since set_seed(seed): the next value matches the replay's.
func _rand_draws(seed: int, after: int, max_draws := 400) -> int:
	for n in max_draws:
		Rng.set_seed(seed)
		for i in n:
			Rng.rand()
		if Rng.rand() == after:
			return n
	return -1


## A sidecar-style object: `faces` = [[mode, [vertex indices]], ...] over `vertices`.
static func _object(vertices: Array, faces: Array, normals := []) -> Dictionary:
	var prims := []
	for i in faces.size():
		var f: Array = faces[i]
		var n: Array = f[2] if f.size() > 2 else []
		prims.append({"kind": "quad" if (f[0] & 0xFC) == MODE_QUAD else "triangle", "mode": f[0], "vertices": f[1],
				"normals": n if not n.is_empty() else f[1].map(func(_v): return 0), "uvs": f[1].map(func(_v): return [0, 0]),
				"tsb": 25, "cba": 31240, "offset": 0x100 + i * 0x24})
	return {"vertices": vertices, "normals": normals if not normals.is_empty() else [[0, -4096, 0]], "primitives": prims,
			"n_primitive": prims.size()}


# --- A: face groups (TmdFaceGroups) --------------------------------------------------------------

func _test_face_groups() -> void:
	var groups: Variant = _script(FACE_GROUPS)
	if groups == null:
		return
	# A2: group g is textured when TABLE[g] < share.
	_eq(Array(groups.shown(0)), [], "share 0: no group textured")
	_eq(Array(groups.shown(1)), [15], "share 1: only group 15 (TABLE[15] = 0)")
	_eq(Array(groups.shown(8)), [0, 1, 6, 7, 9, 12, 13, 15], "share 8: the groups with TABLE[g] < 8")
	var all_but_11 := range(16)
	all_but_11.erase(11)
	_eq(Array(groups.shown(15)), all_but_11, "share 15: all but group 11 (TABLE[11] = 15)")
	_eq(Array(groups.shown(16)), range(16), "share 16: every group")
	# A fake object: 18 triangles then 2 quads (faces 18, 19), 20 faces: groups 0-3 hold 2 faces.
	var verts := []
	for i in 24:
		verts.append([i * 10, -i * 5, i])
	var faces := []
	for i in 18:
		faces.append([MODE_TRI, [i, i + 1, i + 2]])
	faces.append([MODE_QUAD, [18, 19, 20, 21]])
	faces.append([MODE_QUAD | 2, [20, 21, 22, 23]])
	var mat_a := StandardMaterial3D.new()
	var mat_b := StandardMaterial3D.new()
	var mats: Array[Material] = []
	for i in faces.size():
		mats.append(mat_a if i % 2 == 0 else mat_b)
	var built: Dictionary = groups.build(_object(verts, faces), mats, true)
	_eq(built.get("end"), 20, "A7: every face read when all are 0x34 / 0x3C kinds")
	# Vertex counts per group: a triangle 3, a quad 6 (two triangles); outlines as line pairs:
	# a triangle 6 (A8), a quad 8 (A9).
	var want_faces := {}
	var want_lines := {}
	for i in faces.size():
		var quad: bool = (int(faces[i][0]) & 0xFC) == MODE_QUAD
		want_faces[i & 15] = int(want_faces.get(i & 15, 0)) + (6 if quad else 3)
		want_lines[i & 15] = int(want_lines.get(i & 15, 0)) + (8 if quad else 6)
	_eq(_vertex_counts(built.get("faces"), built.get("groups")), want_faces, "textured faces split by i & 15")
	_eq(_vertex_counts(built.get("lines"), built.get("line_groups")), want_lines, "outlines split by i & 15, line pairs")
	# Each surface keeps its faces' material: group 1 holds faces 1 and 17, both odd (mat_b).
	var faces_mesh: ArrayMesh = built.get("faces")
	var group_list: PackedInt32Array = built.get("groups", PackedInt32Array())
	for s in group_list.size():
		if group_list[s] == 1 and faces_mesh != null:
			_check(faces_mesh.surface_get_material(s) == mat_b, "group 1's faces keep their material (spec §5)")
	# A9: the quad (face 18, vertices 18 19 20 21) is outlined v0 v1, v1 v3, v3 v2, v2 v0.
	var lines: ArrayMesh = built.get("lines")
	var lg: PackedInt32Array = built.get("line_groups", PackedInt32Array())
	var want_quad := [18, 19, 19, 21, 21, 20, 20, 18].map(func(v): return Content.psx_to_godot(verts[v]))
	var found := false
	for s in lg.size():
		if lg[s] == 2 and lines != null:
			var pts: PackedVector3Array = lines.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for k in range(0, pts.size() - 7, 2):
				if Array(pts.slice(k, k + 8)) == want_quad:
					found = true
	_check(found, "A9: the quad's outline is v0 v1 v3 v2, closed back to v0")
	# A7: a primitive of another kind (0x2C, a flat quad) ends the object: nothing after it.
	faces[5] = [0x2C, [5, 6, 7, 8]]
	var cut: Dictionary = groups.build(_object(verts, faces), mats, true)
	_eq(cut.get("end"), 5, "A7: the loop stops at the first other kind (face 5)")
	var counts := _vertex_counts(cut.get("faces"), cut.get("groups"))
	_eq(counts.values().reduce(func(a, b): return a + b, 0), 15, "A7: only faces 0-4 drawn (5 triangles)")
	_test_agumon_materials()


func _vertex_counts(mesh: Variant, group_list: Variant) -> Dictionary:
	var out := {}
	if mesh == null or group_list == null:
		return out
	for s in (group_list as PackedInt32Array).size():
		var n: int = (mesh as ArrayMesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
		out[group_list[s]] = int(out.get(group_list[s], 0)) + n
	return out


## Spec §5: each sidecar face finds its material by its packet offset (glTF primitive extras).
func _test_agumon_materials() -> void:
	var wire: Variant = _script(WIREFRAME)
	if wire == null or not Content.exists("mmd_files/MMD0/AGUM.json"):
		return
	var sidecar: Dictionary = Content.load_json("mmd_files/MMD0/AGUM.json")
	var gltf: Dictionary = Content.load_json("mmd_files/MMD0/AGUM.gltf")
	var model := Content.load_model("mmd_files/MMD0/AGUM.gltf")
	var per_object: Array = wire.face_materials(model, sidecar, gltf)
	var objects: Array = sidecar["tmd"]["objects"]
	var missing := 0
	var total := 0
	for skel in sidecar["skeleton"]:
		var o := int(skel.get("objIndex", -1))
		if o < 0:
			continue
		var mats: Array = per_object[o] if o < per_object.size() else []
		for i in objects[o]["primitives"].size():
			total += 1
			if i >= mats.size() or mats[i] == null:
				missing += 1
	_check(total > 0 and missing == 0, "Agumon: every face of every bone object finds its surface's material (%d of %d missing)" % [missing, total])
	model.free()


# --- F: the body's shards (DooaShards) -----------------------------------------------------------

func _test_shards() -> void:
	var script: Variant = _script(SHARDS)
	if script == null:
		return
	# Bone 2: 18 triangles; bone 3: a triangle, then a 0x2C face at 1, then triangles (F4).
	var verts := []
	for i in 20:
		verts.append(Vector3i(i * 7 - 50, -100 - i * 3, i * 5 - 40))
	var tris := []
	for i in 18:
		tris.append([MODE_TRI, [i, i + 1, i + 2]])
	var bone3 := [[MODE_TRI, [0, 1, 2]], [0x2C, [1, 2, 3, 4]]]
	for i in 16:
		bone3.append([MODE_TRI, [i, i + 1, i + 2]])
	var bones := [{"bone": 2, "object": _object([], tris), "vertices": verts},
			{"bone": 3, "object": _object([], bone3), "vertices": verts}]
	var shards: Variant = script.new()
	shards.location = Vector3i(5, 0, 5)
	shards.stored_y = -20
	var wave := 6  # TABLE[0] = 6: faces 0 and 16 of each bone.
	Rng.set_seed(11)
	shards.spawn_wave(wave, bones)
	var after := Rng.rand()
	_eq(_rand_draws(11, after), 36, "F3: one rand() per face of every bone (18 + 18), the wave or not")
	# The replay: (rand() & 3) != 0 first, then the group; bone 3 stops at its 0x2C face (F4).
	Rng.set_seed(11)
	var want := []
	for b in bones:
		var prims: Array = b["object"]["primitives"]
		var stuck := false
		for j in prims.size():
			var r := Rng.rand()
			if int(prims[j]["mode"]) == 0x2C:
				stuck = true
			if stuck:
				continue
			if (r & 3) != 0 and TABLE[j & 15] == wave:
				want.append([b["bone"], j])
	_eq(_plain(shards.shards.map(func(s): return [s["bone"], s["face"]])), want, "F3 / F4: the faces that break off")
	if shards.shards.is_empty():
		return
	# F5-F7, F19: a shard drawn on its spawn frame sits exactly where its face was.
	var s0: Dictionary = shards.shards[0]
	_eq([s0["fall_speed"], s0["radius"], s0["rot"], s0["delay"]], [0, 0x1000, Vector3i.ZERO, 0], "F7: initial values")
	var face: Array = bones[0]["object"]["primitives"][s0["face"]]["vertices"] if s0["bone"] == 2 else bone3[s0["face"]][1]
	var posed: Array = face.map(func(v): return verts[v])
	_eq(_plain(shards.vertices(s0)), _plain(posed), "F5 / F6 / F19: on its first frame the shard is its face, in place")
	var c := Vector3i(0, 0, 0)
	for v: Vector3i in posed:
		c += v
	c = Vector3i(PsxMath.div(c.x, 3), PsxMath.div(c.y, 3), PsxMath.div(c.z, 3))
	_eq(s0["center"], c - Vector3i(5, -20, 5), "F5: centre = mean of the face minus (x, storedY, z)")
	_eq(s0["axis_distance"], maxi(PsxMath.get_distance(s0["center"].x, 0, s0["center"].z), 1), "F7: axisDistance")
	# F10: the fall, 12 frames: centreY += 1 + 2 + ... (min 0).
	var start_y: int = s0["center"].y
	shards.state = 0
	for i in 12:
		shards.tick()
	_eq(shards.shards[0]["center"].y, mini(start_y + 78, 0), "F10: after 12 frames the shard fell 78")
	shards.shards[0]["fall_speed"] = 0x3FF
	shards.tick()
	shards.tick()
	_eq(shards.shards[0]["fall_speed"], 0x400, "F10: fall speed capped at 0x400")
	_eq(shards.shards[0]["center"].y, 0, "F10: the floor stops it (centreY 0)")
	# F11: state 1's entry rolls spinMax, targetRadius, dropDepth per shard, in that order.
	var n: int = shards.shards.size()
	Rng.set_seed(23)
	shards.state = 1
	shards.tick()
	_eq(_rand_draws(23, Rng.rand()), 3 * n, "F11: three rand() per shard on state 1's entry")
	Rng.set_seed(23)
	var r1 := Rng.rand()
	var r2 := Rng.rand()
	var r3 := Rng.rand()
	var s: Dictionary = shards.shards[0]
	var ad: int = s["axis_distance"]
	var lo := 0x64000 / ad
	var hi := 0x190000 / ad
	_eq([s["spin_max"], s["target_radius"], s["drop_depth"]], [r1 % 0x155 + 0xE3, lo + r2 % (hi - lo), r3 % 0x226],
			"F11: the first shard's rolls")
	_eq(s["spin"], s["spin_max"] / 100, "F12: spin += spinMax / 100 on the first frame")
	if s["target_radius"] / 80 != 0:
		_eq(s["radius"], 0x1000 + s["target_radius"] / 100 if 0x1000 < s["target_radius"] else 0x1000, "F12: radius += target / 100")
	# F12's quirk: target 90 (/80 = 1, so no +1) adds 90 / 100 = 0: it never grows.
	s["radius"] = 10
	s["target_radius"] = 90
	shards.tick()
	_eq(s["radius"], 10, "F12: a target of 80-99 never grows (the /80 test, the /100 step)")
	# F14 / F15: state 3; every shard gone within 19 + 11 frames, then at storedY - 100.
	shards.state = 3
	for i in 31:
		shards.tick()
	_check(shards.shards.all(func(x): return x["delay"] == -1), "F15: every shard gone 31 frames after state 3")
	_check(shards.shards.all(func(x): return x["center"].y == -20 - 100), "F15: a gone shard ends at storedY - 100")
	_check(shards.shards.all(func(x): return x["rot"].y >= 0 and x["rot"].y < 4096), "F15: rotY mod 4096 in state 3")
	# F16: the flicker colour, each channel rand() % 100 + 60.
	shards.flash = true
	shards.tick()
	var col: Vector3i = shards.color
	_check(col.x >= 60 and col.x < 160 and col.y >= 60 and col.y < 160 and col.z >= 60 and col.z < 160, "F16: flicker colour in [60, 160): %s" % col)


# --- D: the cutscene camera (CutsceneCamera) -----------------------------------------------------

func _test_camera_maths() -> void:
	var cam: Variant = _script(CAMERA)
	if cam == null:
		return
	var height := 250
	var start := {"eye": Vector3i(0, -1000, -2000), "ref": Vector3i(0, 0, 0), "offset": Vector2i(0xA0, 0x78), "projection": 300}
	var pos := Vector3i.ZERO
	# D1-D4: ref = (0, -h/2, 0); eye = RotMatrixZYX(0, 0x638, 0) · (0, 0, h*5 + 1200) + ref, y -= 400 + 2h.
	var m := PsxMath.rot_matrix_zyx(Vector3i(0, 0x638, 0))
	var arm := PsxMath.apply_matrix_lv(m, Vector3i(0, 0, height * 5 + 1200))
	var ref := Vector3i(0, -125, 0)
	var eye := ref + arm + Vector3i(0, -400 - 2 * height, 0)
	_eq(_plain(cam.orbit(pos, 0, height)), [ref, eye], "D1-D4: the orbit's reference point and eye")
	_eq(cam.view(start, pos, 0, height, 0x23, 0x55, 0x22), {}, "D7: before the start, no change")
	_eq(cam.view(start, pos, 0, height, 0x23, 0x55, 0x56), {}, "D7: after the end, no change")
	# D5 at 0x30 (mid = 0x3C): ref y = lerp(0, -125, 0x23, 0x3C, 0x30) = -65; eye and projection the start's.
	var v: Dictionary = cam.view(start, pos, 0, height, 0x23, 0x55, 0x30)
	_eq([v.get("ref"), v.get("eye"), v.get("offset"), v.get("projection")], [Vector3i(0, -65, 0), start["eye"], Vector2i(160, 120), 300],
			"D5: first half at 0x30")
	# D6 at the end: eye = the orbit's; offset y = 120 + lerp(0, 20, 0, 200, 250) = 124 (the lerp's wrap); projection 1000.
	v = cam.view(start, pos, 0, height, 0x23, 0x55, 0x55)
	_eq([v.get("ref"), v.get("eye"), v.get("offset"), v.get("projection")], [ref, eye, Vector2i(160, 124), 1000], "D6: second half at the end")
	# D12: 0x2C4 - 0x17B = 0x149, the start: the view is the start view again.
	v = cam.view(start, pos, 0, height, 0x149, 0x17B, 0x2C4 - 0x17B)
	_eq([v.get("ref"), v.get("eye"), v.get("offset"), v.get("projection")], [start["ref"], start["eye"], start["offset"], 300],
			"D12: the camera out ends on the room's own view")


# --- E: the flashes' offset (BattleFx) -----------------------------------------------------------

func _test_flash_offset() -> void:
	var fx := BattleFx.new()
	var id := fx.create_flash(0, Vector3i(0, -100, 0), -1, 8, 0, 0x14, Vector3i(80, 80, 80), Vector3i(20, 20, 20))
	if not fx.has_method("set_flash_offset"):
		_missing.append("BattleFx.set_flash_offset")
		_check(false, "BattleFx.set_flash_offset exists (E2)")
		return
	fx.call("set_flash_offset", id, 7, -3)
	_eq([fx.flashes[id].get("offset_x"), fx.flashes[id].get("offset_y")], [7, -3], "E2: setEFEFlashOffset stores the offset")


# --- H: the egg's pieces (EggPieceShards) --------------------------------------------------------

func _test_pieces() -> void:
	var script: Variant = _script(PIECES)
	if script == null:
		return
	# One triangle: vertices (0,-50,0) (10,-50,0) (0,-60,30); normals (0,4096,0) (0,4096,0) (0,0,4096).
	var obj := _object([[0, -50, 0], [10, -50, 0], [0, -60, 30]], [[MODE_TRI, [0, 1, 2], [0, 1, 2]]],
			[[0, 4096, 0], [0, 4096, 0], [0, 0, 4096]])
	var pieces: Variant = script.new()
	var slot: int = pieces.build(obj)
	_eq(slot, 0, "H1: the first free set")
	var face: Dictionary = pieces.sets[slot]["faces"][0]
	_eq(face["centre"], Vector3i(0, 2730, 1365), "H3: the 'centre' is the mean of the first three normals")
	# H4: offsetY += frame + 2730 / 240 (11); the floor test reads (vy + vy + vz) / 3 = -23 (the C's typo).
	pieces.tick()
	_eq(pieces.sets[slot]["faces"][0]["offset"], Vector3i(0, 12, 5), "H4: frame 1: (0, 12, 5)")
	pieces.tick()
	_eq(pieces.sets[slot]["faces"][0]["offset"], Vector3i(0, 23, 5), "H4: frame 2: on the floor (the .vz mean -23), no drift")
	pieces.tick()
	_eq(pieces.sets[slot]["faces"][0]["offset"], Vector3i(0, 23, 5), "H4: frame 3: it stays")
	_eq(pieces.grey(pieces.sets[slot]), (41 - 3) * 74 / 40 + 54, "H5: the grey (41 - timer) * 74 / 40 + 54")
	for i in 38:
		pieces.tick()
	_eq(pieces.sets[slot]["timer"], -1, "H7: removed at timer 41")
	for i in 6:
		pieces.build(obj)
	_eq(pieces.build(obj), -1, "H1: no seventh set")


# --- I: the spark streaks (SparkStreaks) ---------------------------------------------------------

func _test_streaks() -> void:
	var script: Variant = _script(STREAKS)
	if script == null:
		return
	Rng.set_seed(5)
	var streaks: Array = script.roll(3, Vector3i(0, -100, 0))
	_eq(streaks.size(), 3, "I1: as many streaks as fadeLevel")
	_eq(_rand_draws(5, Rng.rand()), 9, "I3: three rand() per streak (rot x, rot y, the grey)")
	var c1 := Rng._custom1
	Rng.set_seed(5)
	for i in 15:
		Rng.custom_random(0, 10)
	_eq(Rng._custom1, c1, "I3: five customRandom per streak (range, length, b's x / y / z)")
	_check(streaks.all(func(s): return s["grey"] >= 10 and s["grey"] < 138 and s["origin"] == Vector3i(0, -100, 0)),
			"I3 / I5: grey rand() % 128 + 10, from the origin")


# --- J: the palette fades (PaletteFade) ----------------------------------------------------------

func _test_fades_maths() -> void:
	var script: Variant = _script(FADE)
	if script == null:
		return
	_eq([script.factor(255), script.factor(0)], [0.0, 1.0], "J: level 255 black, 0 full colour")
	_check(absf(script.factor(128) - 127.0 / 255.0) < 0.0001, "J: level 128 = 127 / 255")


# --- K: the iris (DeathIrisMath) -----------------------------------------------------------------

func _test_iris_maths() -> void:
	var script: Variant = _script(IRIS)
	if script == null:
		return
	_eq([script.radius(0, 0x23, 1, false), script.radius(0, 0x23, 10, false), script.radius(0, 0x23, 34, false),
			script.radius(0, 0x23, 35, false)], [6240, 4576, 192, 0], "K1 / K2: MURD's iris radius")
	_eq(script.radius(0, 0x21, 40, true), 0, "K1: DOOA clamps t to the end")
	# K3: size 300, H 300, depth 2000: projected 45, (45 << 12) / 256 = 720.
	_eq([script.in_front(192, 300, 300, 2000), script.in_front(720, 300, 300, 2000), script.in_front(721, 300, 300, 2000),
			script.in_front(6240, 300, 300, 0)], [true, true, false, true], "K3: the partner in front once the radius is under its size")


# --- B, C, E, G, J: the timelines (DooaScene) ----------------------------------------------------

func _setup_scene() -> void:
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game("dw1:agumon")
	sound = FakeSound.new()
	care = Care.new()
	care.game_state = gs
	care.data = data
	evo = Evolution.new()
	evo.game_state = gs
	evo.data = data
	evo.care = care
	care.evolution = evo
	tamer = Tamer.new()
	partner = Partner.new()
	partner.tamer = tamer
	partner.game_state = gs
	partner.data = data
	partner.sound = sound
	partner.care = care
	dooa = DooaScene.new()
	dooa.partner = partner
	dooa.tamer = tamer
	dooa.game_state = gs
	dooa.sound = sound
	dooa.evolution = evo
	dooa.data = data
	dooa.change_map = func(map: int, exit: int) -> void: map_changes.append([map, exit])
	dooa.map_layer = func(_on: bool) -> void: pass
	# FieldMap's camera hook (spec §5): the old map's view until the map change, then the room's.
	dooa.set("get_view", func() -> Dictionary: return (room_view if not map_changes.is_empty() else old_view).duplicate())
	dooa.set("set_view", func(v: Dictionary) -> void: views[dooa.frame] = v)
	dooa.set("restore_view", func() -> void: restored += 1)


func _dissolve_until(frame: int, record: Callable = Callable()) -> void:
	var guard := 0
	while dooa.frame < frame and dooa.sequence == DooaScene.DISSOLVE and guard < 2000:
		dooa.tick()
		if record.is_valid():
			record.call()
		guard += 1


func _test_dissolve_timeline() -> void:
	gs.state["partner"]["lives"] = 2
	tamer.position = Vector3(300, 0, 0)
	partner.position = Vector3(-200, 0, 100)
	Rng.set_seed(3)
	dooa.start_dissolve()
	var height := int(data.digimon("dw1:agumon").get("height", 0))
	var totals := {}
	var waves := []
	if dooa.has_signal("wave_spawned"):
		dooa.connect("wave_spawned", func(w: int) -> void: waves.append([dooa.frame, w]))
	else:
		_missing.append("DooaScene.wave_spawned")
		_check(false, "DooaScene.wave_spawned exists (spec §5)")
	var scales := {}
	var flash_y := {}
	_dissolve_until(0xD1, func() -> void:
		totals[dooa.frame] = dooa.get("wireframe_total")
		scales[dooa.frame] = dooa.get("scale")
		var fx: Variant = dooa.get("fx")
		var last: Variant = dooa.get("last_flash")
		if fx != null and last != null and int(last) >= 0:
			flash_y[dooa.frame] = (fx as BattleFx).flashes[int(last)].get("position", Vector3i.ZERO).y)
	# B2 / B3: the wireframe share.
	var want_totals := {}
	for f in range(1, 0xD1 + 1):
		want_totals[f] = 16 if f < 0x69 else (SCHEDULE[f - 0x69] if f <= 0x8C else 0)
	want_totals[0xD1] = 16
	var bad := []
	for f in want_totals:
		if totals.get(f) != want_totals[f]:
			bad.append("0x%X: %s want %s" % [f, totals.get(f), want_totals[f]])
	_check(bad.is_empty(), "B2 / B3: PARTNER_WIREFRAME_TOTAL frame by frame: %s" % ", ".join(bad.slice(0, 6)))
	var want_waves := []
	for k in SCHEDULE.size():
		if k == 0 or SCHEDULE[k - 1] != SCHEDULE[k]:
			want_waves.append([0x69 + k, SCHEDULE[k]])
	_eq(waves, want_waves, "B2: 16 waves, on 0x69 and each change")
	_eq([_member(dooa, "wire_color_min"), _member(dooa, "wire_color_max")], [0x37, 0xFF], "A6: the grey range reset at 0xD1")
	# C5: the squash (sy, sx = sz) per frame.
	var want_scales := {0xC0: [3604, 4492], 0xC4: [5734, 2481], 0xC8: [14909, 813], 0xCC: [20070, 506], 0xCD: [16384, 385], 0xD0: [409, 204]}
	for f in want_scales:
		var sc: Variant = scales.get(f)
		var got: Variant = [sc.y, sc.x, sc.z] if sc is Vector3i else sc
		_eq(got, [want_scales[f][0], want_scales[f][1], want_scales[f][1]], "C5: the scale at 0x%X" % f)
	# B6: the flash's target y.
	var stored: Variant = _member(dooa, "stored_y")
	var target: Variant = _member(dooa, "flash_target_y")
	if stored != null:
		_eq(target, int(stored) - (height + 100), "B6: the flash target = storedY - (height + 100)")
	# D9 / D11: the camera calls (their maths is _test_camera_maths'): views from 0x23 to 0x55, the jump at 0x56.
	_check(views.has(0x30) and views.has(0x55) and views.has(0x56) and not views.has(0x57), "D9 / D11: camera views 0x23-0x56, none after")
	var cam: Variant = load(CAMERA) if ResourceLoader.exists(CAMERA) else null
	if cam != null and views.has(0x56):
		# D10: the room's start offset is fixed per death map (ROOM10 0xBC, ROOM08 0xA0; y 0x78).
		var offset := Vector2i(0xBC if dooa.death_map == DooaScene.DEATH_MAP_LATE else 0xA0, 0x78)
		var want: Dictionary = cam.view({"eye": room_view["eye"], "ref": room_view["ref"], "offset": offset,
				"projection": room_view["projection"]}, Vector3i.ZERO, partner.direction, height, 0, 0x64, 0x63)
		_eq(views[0x56], want, "D10 / D11: at 0x56 the room's view (its fixed offset) and frame 0x63 of 0-0x64")
	# E1: the rising flash, one each frame, y = lerp(target, 0, 0xD1, 0x135, f).
	_dissolve_until(0x135, func() -> void:
		var fx: Variant = dooa.get("fx")
		var last: Variant = dooa.get("last_flash")
		if fx != null and last != null and int(last) >= 0:
			flash_y[dooa.frame] = (fx as BattleFx).flashes[int(last)].get("position", Vector3i.ZERO).y)
	if target != null:
		for f in [0xD2, 0x100, 0x134]:
			_eq(flash_y.get(f), PsxMath.lerp_int(int(target), 0, 0xD1, 0x135, f), "E1: the rising flash's y at 0x%X" % f)
	var shards: Variant = dooa.get("shards")
	_dissolve_until(0x136)
	_check(shards != null and shards.get("flash") == true, "F17: the shards flicker from 0x135")
	# D12 / D13 and J2.
	var jij := {}
	_dissolve_until(0x1B8, func() -> void: jij[dooa.frame] = dooa.get("jijimon_fade"))
	_check(views.has(0x149) and views.has(0x17B), "D12: camera out over 0x149-0x17B")
	_eq([jij.get(0x185), jij.get(0x19E), jij.get(0x1B7)], [255, 128, 0], "J2 / J3: Jijimon's palette level")
	_dissolve_until(0x200)
	_check(restored >= 1, "D13: phase 4 restores the map's own view")


func _test_rebirth_timeline() -> void:
	dooa.egg_slot = 1
	Rng.set_seed(9)
	dooa.start_rebirth()
	var thresholds := {}
	var fade_levels := {}
	var tamer_fade := {}
	var npc_fade := {}
	var flashes := {}
	var pieces := {}
	var guard := 0
	while dooa.sequence == DooaScene.REBIRTH and dooa.frame < 262 and guard < 400:
		dooa.tick()
		guard += 1
		var f := dooa.frame
		thresholds[f] = dooa.get("egg_threshold")
		fade_levels[f] = dooa.get("fade_level")
		tamer_fade[f] = dooa.get("tamer_fade")
		npc_fade[f] = dooa.get("others_fade")
		var flags: Variant = dooa.get("piece_flags")
		pieces[f] = Array(flags) if flags != null else null
		var fx: Variant = dooa.get("fx")
		var last: Variant = dooa.get("last_flash")
		if fx != null and last != null and int(last) >= 0:
			flashes[f] = (fx as BattleFx).flashes[int(last)].duplicate()
		if f == 10 or f == 100:
			var sh: Variant = dooa.get("shards")
			_eq(sh.get("state") if sh != null else null, 1 if f == 10 else 3, "F18: shard state %d at rebirth %d" % [1 if f == 10 else 3, f])
	# G2 / G11 (phase 0xCD is entered on 100 and computes from 101).
	_eq([thresholds.get(99), thresholds.get(100), thresholds.get(101), thresholds.get(103), thresholds.get(115),
			thresholds.get(116), thresholds.get(129), thresholds.get(130)], [0, 0, 1, 2, 8, 8, 14, 16], "G2 / G11: the egg's threshold")
	# I1 / I2: streaks per frame.
	_eq([fade_levels.get(133), fade_levels.get(136), fade_levels.get(140), fade_levels.get(143), fade_levels.get(146), fade_levels.get(147)],
			[5, 4, 3, 2, 2, 0], "I1 / I2: fadeLevel")
	# E4 / E5: the rebirth flash's scale and colours.
	for row in [[133, 2048, 115], [142, 1536, 65], [152, 1024, 10]]:
		var fl: Dictionary = flashes.get(row[0], {})
		var lo: int = row[2]
		var cmin: Vector3i = fl.get("color_min", Vector3i(-1, -1, -1))
		_check(fl.get("scale_max") == row[1] and fl.get("t_max") == 4 and fl.get("color_max") == Vector3i(lo / 6, lo / 6, lo / 6)
				and cmin.x >= lo and cmin.x < lo + maxi(lo * 50 / 120, 1), "E4 / E5: the rebirth flash at %d: %s" % [row[0], fl])
	# J4-J6: the tamer's palette on even frames, entities 3 / 4's on odd ones, from black at 152.
	_eq([tamer_fade.get(152), npc_fade.get(152)], [255, 255], "J4: both black at 152")
	_eq([tamer_fade.get(153), npc_fade.get(153)], [255, 250], "J5: 153 (odd): entities 3 / 4 at 250")
	_eq([tamer_fade.get(154), npc_fade.get(154)], [245, 250], "J5: 154 (even): the tamer at 245")
	_eq([tamer_fade.get(177), npc_fade.get(177)], [133, 128], "J5 / J6: 177")
	_eq([tamer_fade.get(202), npc_fade.get(202), dooa.darkness], [0, 0, 0], "J7: full colour at 202")
	# G8 / G10: the pieces break at sparkle entries 4, 14, 24, 34, 44, 45 (frames 207 ... 248).
	_eq(pieces.get(206), [0, 0, 0, 0, 0, 0], "G8: no piece broken before 207")
	_eq(pieces.get(207), [-1, 0, 0, 0, 0, 0], "G8 / G10: piece 0 breaks at 207 (entry 4)")
	_eq(pieces.get(247), [-1, -1, -1, -1, -1, 0], "G10: piece 4 at 247 (entry 44)")
	_eq(pieces.get(248), [-1, -1, -1, -1, -1, -1], "G10: piece 5 at 248 (entry 45)")
