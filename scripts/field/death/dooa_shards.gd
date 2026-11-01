class_name DooaShards
extends RefCounted
## DOOA_SHARD_EFFECT: the partner's faces breaking off as textured shards (specs/death_scene.md §3 F,
## §4.2): DOOA_spawnBoneShards (dooa.c:1559) at each wireframe wave, DOOA_updateShards (dooa.c:1325)
## every frame by the effect's state, DOOA_renderShards (dooa.c:1424) for the positions (F19).
## Logic only; DeathShards draws it. Positions are PSX units (+Y down); a shard's centre y is
## relative to stored_y (0 = the partner's feet when the shards started).

## WIREFRAME_RNG_TABLE (model.c:2501).
const TABLE := TmdFaceGroups.TABLE
## GPU_COM_TG3 / TG4 and their semi-transparent forms (dooa.c:1612–1614, libgs.h:326).
const TRIANGLES := [0x34, 0x36]
const QUADS := [0x3C, 0x3E]

## 0 the fall, 1 the lift (rebirth 10), 2 the spin (unused by DOOA), 3 the gathering (rebirth 100).
var state := 0
var prev_state := 0
## DOOA_toggleShardFlicker (0x135): flat random colours.
var flash := false
## The effect's colour (R, G, B; DOOA_initShardEffect: 0x50 each, F9).
var color := Vector3i(0x50, 0x50, 0x50)
## The partner's location (PSX) and DOOA_getStoredDigimonY.
var location := Vector3i.ZERO
var stored_y := 0
var shards: Array[Dictionary] = []


## DOOA_spawnShardWave(wave): for each bone (2 .. boneCount - 1 with an object, in order), the faces
## of group `wave` break off, 3 in 4 (F1–F7). `bones`: {"bone", "object" (sidecar), "vertices"
## (Array[Vector3i]: the object's vertices posed this frame, PSX world units)}.
func spawn_wave(wave: int, bones: Array) -> void:
	for b: Dictionary in bones:
		_spawn_bone(b, wave)


func _spawn_bone(b: Dictionary, wave: int) -> void:
	var prims: Array = b["object"].get("primitives", [])
	var verts: Array = b["vertices"]
	# F4: the C only steps past the kinds it knows: after another mode every later face reads that
	# same primitive (no shard), the rand() still rolled per face.
	var stuck := false
	for j in prims.size():
		var roll := Rng.rand()
		var p: Dictionary = prims[j]
		var mode := int(p.get("mode", 0))
		if not stuck and not (mode in TRIANGLES or mode in QUADS):
			stuck = true
		if stuck or (roll & 3) == 0 or TABLE[j & 15] != wave:
			continue
		var quad: bool = mode in QUADS
		var vi: Array = p["vertices"]
		var n := 4 if quad else 3
		var sum := Vector3i.ZERO
		for k in n:
			sum += verts[vi[k]]
		var centre := Vector3i(PsxMath.div(sum.x, n), PsxMath.div(sum.y, n), PsxMath.div(sum.z, n))
		var shape: Array[Vector3i] = []
		for k in n:
			shape.append(Vector3i(verts[vi[k]]) - centre)
		centre -= Vector3i(location.x, stored_y, location.z)
		var axis := PsxMath.get_distance(centre.x, 0, centre.z)
		shards.append({"bone": b["bone"], "face": j, "kind": "quad" if quad else "tri", "center": centre,
				"vertex": shape, "fall_speed": 0, "radius": 0x1000, "rot": Vector3i.ZERO,
				"axis_distance": axis if axis != 0 else 1, "delay": 0, "spin": 0, "spin_max": 0,
				"target_radius": 0, "drop_depth": 0, "uvs": p.get("uvs", [])})


## DOOA_updateShards: the flicker colour, then every shard by the state (F10–F16).
func tick() -> void:
	if flash:
		color = Vector3i(Rng.rand() % 100 + 60, Rng.rand() % 100 + 60, Rng.rand() % 100 + 60)
	var entering := state != prev_state
	for s in shards:
		match state:
			0:
				s["fall_speed"] = mini(int(s["fall_speed"]) + 1, 0x400)
				_set_y(s, mini(int(s["center"].y) + int(s["fall_speed"]), 0))
			1:
				if entering:
					s["spin"] = 0
					s["spin_max"] = Rng.rand() % 0x155 + 0xE3
					s["radius"] = 0x1000
					var lo := 0x64000 / int(s["axis_distance"])
					var hi := 0x190000 / int(s["axis_distance"])
					s["target_radius"] = lo + Rng.rand() % maxi(hi - lo, 1)
					s["fall_speed"] = 0
					s["drop_depth"] = Rng.rand() % 0x226
				# F12: the C tests /80 and adds /100.
				if int(s["spin_max"]) / 80 == 0:
					s["spin"] = int(s["spin"]) + 1
				else:
					s["spin"] = int(s["spin"]) + int(s["spin_max"]) / 100
				s["spin"] = mini(int(s["spin"]), int(s["spin_max"]))
				_rotate(s, false)
				if int(s["radius"]) < int(s["target_radius"]):
					if int(s["target_radius"]) / 80 == 0:
						s["radius"] = int(s["radius"]) + 1
					else:
						s["radius"] = int(s["radius"]) + int(s["target_radius"]) / 100
				s["fall_speed"] = int(s["fall_speed"]) + 1
				_set_y(s, maxi(int(s["center"].y) - (int(s["fall_speed"]) >> 3), -int(s["drop_depth"])))
			2:
				_rotate(s, false)
			3:
				if entering:
					s["delay"] = Rng.rand() % 20
					s["target_radius"] = s["radius"]
				if int(s["delay"]) > 0:
					s["delay"] = int(s["delay"]) - 1
				else:
					s["radius"] = int(s["radius"]) - (int(s["target_radius"]) / 10 + 1)
					if int(s["radius"]) < 0:
						s["radius"] = 0
						s["delay"] = -1
					_set_y(s, PsxMath.lerp_int(-int(s["drop_depth"]), stored_y - 100, int(s["target_radius"]), 0, int(s["radius"])))
				_rotate(s, true)
	prev_state = state


static func _set_y(s: Dictionary, y: int) -> void:
	var c: Vector3i = s["center"]
	s["center"] = Vector3i(c.x, y, c.z)


## rotY += spin; state 3 takes it mod 4096 (F15). rotY is an int16 in the C: the wrap keeps the
## same angle (65536 is 16 turns).
static func _rotate(s: Dictionary, wrap: bool) -> void:
	var r: Vector3i = s["rot"]
	var y := r.y + int(s["spin"])
	y = (y % 4096 + 4096) % 4096 if wrap else ((y + 0x8000) & 0xFFFF) - 0x8000
	s["rot"] = Vector3i(r.x, y, r.z)


## DOOA_renderShards (F19): the shard's vertices this frame, PSX world units.
func vertices(s: Dictionary) -> Array[Vector3i]:
	var c: Vector3i = s["center"]
	var r := int(s["radius"])
	var offset := Vector3i(PsxMath.div(c.x * r, 4096), c.y, PsxMath.div(c.z * r, 4096))
	var m := PsxMath.rot_matrix_zyx(s["rot"])
	var out: Array[Vector3i] = []
	for v: Vector3i in s["vertex"]:
		out.append(PsxMath.apply_matrix_sv(m, offset + v) + Vector3i(location.x, stored_y, location.z))
	return out


## Shards drawn (F22).
func drawn() -> Array[Dictionary]:
	return shards.filter(func(s): return int(s["delay"]) >= 0)
