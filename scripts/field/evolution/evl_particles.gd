class_name EvlParticles
extends RefCounted
## The evolution's rings (EVL_spawnParticle evl.c:778, EVL_tickParticle :1163, EVL_renderParticle
## :1176, EVL_releaseAllParticles :854; specs/evolution_scene.md §3 H, §4.4): green squares on the
## floor plane at the partner's start location, growing and fading over 0x57 frames. Logic only:
## EvlParticlesView draws them.

## EVL_D_80068944[100] (evl.c:784).
const SLOTS := 100
## evl.c:1168, :1187, :1207: the life and the lerps' end, 0x56.
const LIFE := 0x56
## evl.c:1187: the half side lerps from 8 to 0x9C4.
const SIZE_START := 8
const SIZE_END := 0x9C4

## {"timer" (-1 free), "pos": Vector3i, "color": Vector3i}.
var particles: Array[Dictionary] = []


func _init() -> void:
	for i in SLOTS:
		particles.append({"timer": -1, "pos": Vector3i.ZERO, "color": Vector3i.ZERO})


## EVL_spawnParticle: the first free slot, or -1 (H3).
func spawn(pos: Vector3i, color: Vector3i) -> int:
	for i in SLOTS:
		if int(particles[i]["timer"]) < 0:
			particles[i] = {"timer": 0, "pos": pos, "color": color}
			return i
	return -1


## EVL_tickParticle (H4): removed by the tick that finds the timer at 0x56, else + 1.
func tick() -> void:
	for p in particles:
		var t := int(p["timer"])
		if t < 0:
			continue
		p["timer"] = -1 if t >= LIFE else t + 1


## EVL_releaseAllParticles (H8).
func release_all() -> void:
	for p in particles:
		p["timer"] = -1


## The live particles (drawn this frame).
func drawn() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in particles:
		if int(p["timer"]) >= 0:
			out.append(p)
	return out


## H5: the square's corners (+, +), (+, -), (-, -), (-, +) on the particle's y.
static func corners(p: Dictionary) -> Array:
	var s := PsxMath.lerp_int(SIZE_START, SIZE_END, 0, LIFE, int(p["timer"]))
	var c: Vector3i = p["pos"]
	return [Vector3i(c.x + s, c.y, c.z + s), Vector3i(c.x + s, c.y, c.z - s), Vector3i(c.x - s, c.y, c.z - s),
			Vector3i(c.x - s, c.y, c.z + s)]


## H6: the colour fading to black, lerp(c, 0, 0, 0x56, timer) per channel.
static func color(p: Dictionary) -> Vector3i:
	var c: Vector3i = p["color"]
	var t := int(p["timer"])
	return Vector3i(PsxMath.lerp_int(c.x, 0, 0, LIFE, t), PsxMath.lerp_int(c.y, 0, 0, LIFE, t), PsxMath.lerp_int(c.z, 0, 0, LIFE, t))
