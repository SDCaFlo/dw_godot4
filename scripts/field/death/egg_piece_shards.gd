class_name EggPieceShards
extends RefCounted
## DOO2_SHARD_SETS: an egg piece falling apart into translucent fragments (specs/death_scene.md §3 H,
## §4.7): DOO2_buildShardSet (doo2.c:597), DOO2_tickShardSet (doo2.c:208), the motion of
## DOO2_renderTriShard / QuadShard (doo2.c:228 / 272). Logic only; RebirthEgg's Pieces draw it.
## PSX units, +Y down; the egg's vertices are world positions (identity coordinates, G5).

const SLOTS := 6
## The sets' lifetime: removed when the timer reaches 41 (H7).
const LIFE := 41
## The motion's divisor: speed 80 × 3 (doo2.c:252).
const DRIFT := 240

## Each {"timer" (-1 free), "object" (sidecar object), "faces": [{"centre", "offset": Vector3i, "frame"}]}.
var sets: Array[Dictionary] = []


func _init() -> void:
	reset()


## DOO2_resetShardSets.
func reset() -> void:
	sets.clear()
	for i in SLOTS:
		sets.append({"timer": -1, "object": {}, "faces": []})


## DOO2_buildShardSet(offset 0, model, piece): the first free set, or -1 (H1). A face's "centre" is
## the mean of its first three vertex normals (H3: the C reads the TMD's normal_top by n0..n2).
func build(object: Dictionary) -> int:
	var slot := -1
	for i in SLOTS:
		if int(sets[i]["timer"]) < 0:
			slot = i
			break
	if slot < 0:
		return -1
	var normals: Array = object.get("normals", [])
	var faces := []
	for p: Dictionary in object.get("primitives", []):
		var mode := int(p.get("mode", 0))
		if mode != TmdFaceGroups.TRIANGLE and mode != TmdFaceGroups.QUAD:
			continue
		var ni: Array = p.get("normals", [])
		var sum := Vector3i.ZERO
		for k in 3:
			var n: Array = normals[int(ni[k])] if k < ni.size() and int(ni[k]) < normals.size() else [0, 0, 0]
			sum += Vector3i(int(n[0]), int(n[1]), int(n[2]))
		faces.append({"centre": Vector3i(PsxMath.div(sum.x, 3), PsxMath.div(sum.y, 3), PsxMath.div(sum.z, 3)),
				"offset": Vector3i.ZERO, "frame": 0, "face": p})
	sets[slot] = {"timer": 0, "object": object, "faces": faces}
	return slot


## DOO2_tickShardSet (the timer, the removal at 41), then the render's motion step (H4).
func tick() -> void:
	for s in sets:
		if int(s["timer"]) < 0:
			continue
		s["timer"] = int(s["timer"]) + 1
		if int(s["timer"]) >= LIFE:
			s["timer"] = -1
			continue
		var verts: Array = s["object"].get("vertices", [])
		for f: Dictionary in s["faces"]:
			_step(f, verts)


## One frame of a fragment: it falls (frame + centre / 240) and drifts out until the mean of its
## vertices' y reaches the floor; the C's mean takes the third vertex's z (H4, doo2.c:253, 303).
static func _step(f: Dictionary, verts: Array) -> void:
	var p: Dictionary = f["face"]
	var vi: Array = p["vertices"]
	var quad := int(p.get("mode", 0)) == TmdFaceGroups.QUAD
	var y := func(k: int) -> int: return int(verts[vi[k]][1])
	var z := func(k: int) -> int: return int(verts[vi[k]][2])
	var mean: int = PsxMath.div(y.call(0) + y.call(1) + z.call(2) + y.call(3), 4) if quad \
			else PsxMath.div(y.call(0) + y.call(1) + z.call(2), 3)
	var c: Vector3i = f["centre"]
	var o: Vector3i = f["offset"]
	f["frame"] = int(f["frame"]) + 1
	o.y += int(f["frame"]) + PsxMath.div(c.y, DRIFT)
	if o.y + mean > 0:
		o.y = -mean
	else:
		o.x += PsxMath.div(c.x, DRIFT)
		o.z += PsxMath.div(c.z, DRIFT)
	f["offset"] = o


## The sets' grey this frame (H5): (41 - timer) * 74 / 40 + 54.
func grey(s: Dictionary) -> int:
	return (LIFE - int(s["timer"])) * 74 / 40 + 54


## A fragment's vertices (PSX world units).
func vertices(s: Dictionary, f: Dictionary) -> Array[Vector3i]:
	var verts: Array = s["object"].get("vertices", [])
	var out: Array[Vector3i] = []
	for i in f["face"]["vertices"]:
		var v: Array = verts[int(i)]
		out.append(Vector3i(int(v[0]), int(v[1]), int(v[2])) + Vector3i(f["offset"]))
	return out
