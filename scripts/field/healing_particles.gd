class_name HealingParticles
extends Node3D
## The healing particles over the partner when an item heals it (main/particle.c:
## addHealingParticleEffect :209, tickHealingParticles :88, renderHealingParticles :164; ISSUES.md
## I-21), in the field and in battle (the item handlers call it in both, item.c:2236-2373). One
## instance (NUM_HEALING_INSTANCES), 44 frames:
## - a ring of 20 sparks rising from the partner's feet to above its head (one more a frame for 20
##   frames, each burning 17 frames in yellow-green, its size rolled every frame);
## - with the variant (hasParticle2: the bigger recoveries), 4 sparks a frame for 39 frames falling
##   from above the head in a widening spiral (5 frames each, fading to white).
## Its logic rolls rand() in its tick as the C does; ItemUse.healing_effect starts it. The field's
## CareHost owns it (scenes/field/healing_particles.tscn) and ticks it in the field and battle frames.

const PARTICLES := 20
const FRAMES := 44
const RING_FRAMES := 20
const RING_LIFE := 17
const SPIRAL_FRAMES := 39
const SPIRAL_LIFE := 5
const SPIRAL_SIZE := 24
## PARTICLE_COLOR1 / 2 (the ring, by its counter) and 3 (the spiral).
const COLOR1 := [[0x02, 0x04, 0x01], [0x04, 0x06, 0x02], [0x07, 0x09, 0x03], [0x0a, 0x0b, 0x03],
		[0x0c, 0x0d, 0x04], [0x0f, 0x10, 0x04], [0x12, 0x12, 0x05], [0x15, 0x15, 0x06], [0x17, 0x17, 0x06],
		[0x1a, 0x19, 0x07], [0x1d, 0x1c, 0x07], [0x1f, 0x1e, 0x08], [0x22, 0x21, 0x09], [0x25, 0x23, 0x09],
		[0x27, 0x25, 0x0a], [0x2a, 0x28, 0x0a], [0x2d, 0x2a, 0x0b], [0x30, 0x2d, 0x0c]]
const COLOR2 := [[0x04, 0x09, 0x03], [0x0a, 0x0e, 0x05], [0x10, 0x13, 0x06], [0x16, 0x18, 0x07],
		[0x1b, 0x1d, 0x09], [0x21, 0x23, 0x0a], [0x27, 0x28, 0x0b], [0x2d, 0x2d, 0x0d], [0x33, 0x32, 0x0e],
		[0x39, 0x37, 0x0f], [0x3f, 0x3d, 0x10], [0x44, 0x42, 0x12], [0x4a, 0x47, 0x13], [0x50, 0x4c, 0x14],
		[0x56, 0x51, 0x16], [0x5c, 0x57, 0x17], [0x62, 0x5c, 0x18], [0x68, 0x61, 0x1a]]
const COLOR3 := [[0x47, 0x51, 0x00], [0x60, 0x6b, 0x19], [0x7d, 0x86, 0x3d], [0xb3, 0xbb, 0x7a],
		[0xd7, 0xdc, 0xb7], [0xff, 0xff, 0xff]]

## Set by the owner: the partner (its bone 0 and its Digimon's size), the map (its projection).
var partner: Node3D
var field_map: FieldMap
var data: Node
var game_state: Node

## HEALING_PARTICLES[0]: frameId (-1 free), off (x, y, z), its pad (the ring's starting size: never
## read), radius, hasParticle2; entries1 (the ring) and entries2 (the spiral): {counter, pos, size}.
var frame_id := -1
var off := Vector3i.ZERO
var radius := 0
var has_particle2 := false
var entries1: Array[Dictionary] = []
var entries2: Array[Dictionary] = []

## renderFXParticle's sprites (FxParticles).
var _sprites: FxParticles


func _init() -> void:
	for i in PARTICLES:
		entries1.append({"counter": -1, "pos": Vector3i.ZERO, "size": 0})
		entries2.append({"counter": -1, "pos": Vector3i.ZERO, "size": 0})


func _ready() -> void:
	_sprites = FxParticles.new()
	_sprites.name = "Sprites"
	add_child(_sprites)


## addHealingParticleEffect(partner, variant): -1 while one is showing.
func add(variant: int) -> int:
	if frame_id != -1 or partner == null:
		return -1
	frame_id = 0
	var digimon: Dictionary = data.digimon(game_state.state["partner"]["digimon"]) if data != null else {}
	var p: Vector3 = partner.call("bone_position", 0) if partner.has_method("bone_position") else partner.global_position
	off = Vector3i(PsxMath.s16(roundi(p.x)), PsxMath.s16(-int(digimon.get("height", 0)) - 70), PsxMath.s16(roundi(-p.z)))
	radius = PsxMath.s16(int(digimon.get("radius", 0)) * 12 / 10)
	has_particle2 = variant != 0
	for e in entries1:
		e["counter"] = -1
	for e in entries2:
		e["counter"] = -1
	return 0


func active() -> bool:
	return frame_id != -1


## tickHealingParticles.
func tick() -> void:
	if frame_id < 0:
		return
	frame_id += 1
	if frame_id >= FRAMES:
		frame_id = -1
		return
	if frame_id < RING_FRAMES:
		var e := entries1[frame_id]
		e["counter"] = RING_LIFE
		var m := PsxMath.rot_matrix_zyx(Vector3i(0, (frame_id * 640) & 0xFFF, 0))
		var p := PsxMath.s16_vec(PsxMath.apply_matrix_sv(m, Vector3i(radius, 0, 0)))
		e["pos"] = PsxMath.s16_vec(Vector3i(p.x + off.x, off.y - PsxMath.lerp_int(0, off.y, 0, RING_FRAMES, frame_id),
				p.z + off.z))
	for e in entries1:
		e["counter"] -= 1
		e["size"] = (Rng.rand() % 70) + 15
	if frame_id < SPIRAL_FRAMES:
		var base := frame_id % 5
		for i in 4:
			var angle := PsxMath.lerp_int(0, 512, 0, 13, frame_id) + _div(512, i * 13 / 4)
			var e := entries2[base + i * 5]
			e["counter"] = SPIRAL_LIFE
			var x := off.x + (Rng.rand() % 60 - 30) - (((radius + 150) * PsxMath.sin512(angle)) >> 12)
			var z := off.z + (Rng.rand() % 60 - 30) + (((radius + 150) * PsxMath.cos512(angle)) >> 12)
			var y := PsxMath.lerp_int((Rng.rand() % 60 - 30) + off.y, 0, 0, SPIRAL_FRAMES, frame_id)
			e["pos"] = PsxMath.s16_vec(Vector3i(x, y, z))
	for e in entries2:
		e["counter"] -= 1


## The R3000's division: by 0 it gives -1 for a positive dividend (the C's 512 / (i * 13 / 4) at
## i = 0, which the game runs: no trap in tickHealingParticles' code).
static func _div(a: int, b: int) -> int:
	if b == 0:
		return -1 if a >= 0 else 1
	return PsxMath.div(a, b)


## renderHealingParticles: the ring twice (its size and half in two colours), the spiral.
func draw_frame() -> void:
	if _sprites == null:
		return
	_sprites.begin()
	if frame_id >= 0 and field_map != null:
		for e in entries1:
			var c: int = e["counter"]
			if c >= 0:
				_fx_particle(e["pos"], e["size"], COLOR1[c])
				_fx_particle(e["pos"], e["size"] >> 1, COLOR2[c])
		if has_particle2:
			for e in entries2:
				var c: int = e["counter"]
				if c >= 0:
					_fx_particle(e["pos"], SPIRAL_SIZE, COLOR3[c])
	_sprites.end()


## renderFXParticle (FxParticles.particle).
func _fx_particle(at: Vector3i, size: int, rgb: Array) -> void:
	_sprites.particle(field_map, at, size, Vector3i(rgb[0], rgb[1], rgb[2]))
