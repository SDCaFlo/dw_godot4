class_name EvlSparks
extends RefCounted
## The evolution's spark streaks (EVL_spawnSpark evl.c:806, EVL_tickSpark :1264,
## EVL_renderSparkStreak :1222; specs/evolution_scene.md §3 F, §4.3): one per broken bone (16 slots),
## living until 0x11C; each frame a thin additive triangle from bone 1 towards the bone, re-rolled.
## Logic only: the host draws streak()'s with SparkStreaks (the same primitive as DOO2's, F8).

## EVL_D_80068F84[16] (evl.c:815).
const SLOTS := 16
## evl.c:1246: the tip's length roll, customRandom(0x190, 0x1F4), squared.
const LENGTH_MIN := 0x190
const LENGTH_MAX := 0x1F4
## evl.c:1251-1253: the jitter, customRandom(-0x50, 0x50) per component.
const JITTER := 0x50
## evl.c:1260: the grey, rand() % 128 + 10.
const GREY_RANGE := 128
const GREY_BASE := 10

## {"bone" (-1 free), "timer"}.
var sparks: Array[Dictionary] = []


func _init() -> void:
	for i in SLOTS:
		sparks.append({"bone": -1, "timer": 0})


## EVL_spawnSpark: the first free slot, or -1 (F1).
func spawn(bone: int, timer: int) -> int:
	for i in SLOTS:
		if int(sparks[i]["bone"]) == -1:
			sparks[i] = {"bone": bone, "timer": timer}
			return i
	return -1


## EVL_tickSpark (F2): removed once its timer is below 0, else timer - 1.
func tick() -> void:
	for s in sparks:
		if int(s["bone"]) == -1:
			continue
		if int(s["timer"]) < 0:
			s["bone"] = -1
		else:
			s["timer"] = int(s["timer"]) - 1


## The live sparks (drawn this frame), in slot order.
func drawn() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in sparks:
		if int(s["bone"]) != -1:
			out.append(s)
	return out


## EVL_renderSparkStreak's triangle from the bone's and bone 1's positions (F3-F7), as SparkStreaks
## draws it: {"origin": bone 1, "a": the tip, "b": the tip jittered, "grey"}.
static func streak(bone_pos: Vector3i, centre: Vector3i) -> Dictionary:
	# evl.c:1239-1241: the bone's offset from bone 1, as SVECTOR (int16).
	var d := PsxMath.s16_vec(bone_pos - centre)
	var len_sq := d.x * d.x + d.y * d.y + d.z * d.z
	var s := Rng.custom_random(LENGTH_MIN, LENGTH_MAX)
	s *= s
	var tip := centre + Vector3i(_div(d.x * s, len_sq), _div(d.y * s, len_sq), _div(d.z * s, len_sq))
	var jittered := tip + Vector3i(Rng.custom_random(-JITTER, JITTER), Rng.custom_random(-JITTER, JITTER),
			Rng.custom_random(-JITTER, JITTER))
	return {"origin": centre, "a": tip, "b": jittered, "grey": Rng.rand() % GREY_RANGE + GREY_BASE}


## The R3000A's division (F4): `div` with no zero check gives -1 for a dividend >= 0 over 0, 1 for a
## negative one (port-only: the hardware's result, asm/us/evl/evl.s at 0x80062EDC).
static func _div(a: int, b: int) -> int:
	if b == 0:
		return -1 if a >= 0 else 1
	return PsxMath.div(a, b)
