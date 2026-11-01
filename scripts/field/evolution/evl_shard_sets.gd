class_name EvlShardSets
extends RefCounted
## The evolution's shard sets (EVL_buildShardSet evl.c:1001, EVL_tickShardSet :869,
## EVL_renderShardSet :882, EVL_renderTriShard / QuadShard :912 / :1118; specs/evolution_scene.md
## §3 E, §4.2): one set per broken bone, its faces frozen where the bone was posed at the break, each
## flying off along the mean of its first three normals, `drift × timer / 60`. Logic only:
## EvlShardsView draws them.

## evl.c:311 (EVL_initShardSets): 30 slots.
const SLOTS := 30
## evl.c:874: a set is removed by the tick that finds its timer at 0x1F.
const LAST_TIMER := 0x1F
## evl.c:901, :905: EVL_renderTri/QuadShard's speed, the drift's divisor.
const SPEED := 60
## evl.c:895: the grey (31 - timer) × 74 / 30 + 54.
const GREY_TOP := 31
const GREY_SPAN := 74
const GREY_STEPS := 30
const GREY_BASE := 54
## evl.c:1073-1092: the primitive modes read as triangles and quads; another mode ends the object.
const TRIANGLES := [0x34, 0x36]
const QUADS := [0x3C, 0x3E]

## MAIN_D_80135208[30]: {"timer" (-1 free), "bone", "object" (sidecar), "vertices": Array[Vector3i]
## (posed, PSX world units), "drifts": Array[Vector3i] (one per face read)}.
var sets: Array[Dictionary] = []


func _init() -> void:
	for i in SLOTS:
		sets.append({"timer": -1})


## EVL_buildShardSet: the first free slot (-1 if none, E1), the bone's posed vertices kept, a drift
## per face: the mean of its first three posed normals, quads too (E3).
func build(bone: int, object: Dictionary, vertices: Array, normals: Array) -> int:
	var slot := 0
	while slot < SLOTS and int(sets[slot]["timer"]) >= 0:
		slot += 1
	if slot == SLOTS:
		return -1
	var drifts: Array[Vector3i] = []
	for prim: Dictionary in object.get("primitives", []):
		var mode := int(prim.get("mode", 0))
		if not mode in TRIANGLES and not mode in QUADS:
			# evl.c:1072: no case for it, and the pointer doesn't move: no later face is read.
			break
		var n: Array = prim.get("normals", [])
		var sum := Vector3i.ZERO
		for k in 3:
			var i: int = int(n[k]) if k < n.size() else -1
			sum += normals[i] if i >= 0 and i < normals.size() else Vector3i.ZERO
		drifts.append(Vector3i(PsxMath.div(sum.x, 3), PsxMath.div(sum.y, 3), PsxMath.div(sum.z, 3)))
	sets[slot] = {"timer": 0, "bone": bone, "object": object, "vertices": vertices, "drifts": drifts}
	return slot


## EVL_tickShardSet, every live set (E6).
func tick() -> void:
	for s in sets:
		var t := int(s["timer"])
		if t < 0:
			continue
		s["timer"] = -1 if t >= LAST_TIMER else t + 1


## The live sets (drawn this frame).
func drawn() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in sets:
		if int(s["timer"]) >= 0:
			out.append(s)
	return out


## EVL_renderShardSet's faces at the set's timer: each {"kind" ("tri" / "quad"), "face", "points"
## (Vector3i)}, the vertices moved by drift × timer / 60, truncated (E4, E9).
func faces(s: Dictionary) -> Array:
	var out := []
	var timer := int(s["timer"])
	var verts: Array = s["vertices"]
	var prims: Array = s["object"].get("primitives", [])
	var drifts: Array = s["drifts"]
	for i in drifts.size():
		var d: Vector3i = drifts[i]
		var offset := Vector3i(PsxMath.div(d.x * timer, SPEED), PsxMath.div(d.y * timer, SPEED), PsxMath.div(d.z * timer, SPEED))
		var points := []
		for v in prims[i].get("vertices", []):
			var p: Vector3i = verts[int(v)] if int(v) < verts.size() else Vector3i.ZERO
			points.append(p + offset)
		out.append({"kind": "quad" if points.size() == 4 else "tri", "face": i, "points": points})
	return out


## evl.c:895 (E5).
static func grey(timer: int) -> int:
	return (GREY_TOP - timer) * GREY_SPAN / GREY_STEPS + GREY_BASE
