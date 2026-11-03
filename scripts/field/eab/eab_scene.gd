class_name EabScene
extends RefCounted
## Machinedramon's build-up and spawn logic (specs/map_events.md §3.3 E1-E12, §4.3.1):
## timelines, frames, phases, rings, particles, colours, camera orbit and wireframe total
## (eab.c:1-710, EAB_startBuildup, EAB_tick, EAB_tickSpawn).

## eab.c:219, :276 (the slots EAB_addBuildupRing / EAB_addSpawnRing search)
const RINGS := 3
## port-only: buildup ring kind
const RING_BUILDUP := 0
## port-only: spawn ring kind
const RING_SPAWN := 1
## eab.c:249 (EAB_tickBuildupRing)
const BUILDUP_RING_LIFE := 0x12
## eab.c:306 (EAB_tickSpawnRing)
const SPAWN_RING_LIFE := 9
## eab.c:519 (EAB_addParticle)
const PARTICLES := 100
## eab.c:600 (EAB_tickParticle)
const PARTICLE_LIFE := 0x56
## eab.c:136 (EAB_D_8006170C, nine [x, y, z, scale_max])
const FLASHES := [
	[0, -300, -900, 0x1400],
	[500, -300, -2100, 0x1400],
	[1000, -300, -1500, 0x1400],
	[600, -300, -700, 0x1400],
	[-800, -300, 500, 0x1400],
	[900, -300, -100, 0x1400],
	[-200, -300, -2800, 0x1400],
	[-1200, -300, 100, 0x1400],
	[-1200, -300, -2500, 0x1400],
]
## eab.c:148 (EAB_D_8006179C, 18 values)
const PULSE := [
	1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]
## eab.c:124 (MAIN_D_80134C3C)
const PARTICLE_RB := 0x0A
## eab.c:130 (EAB_D_800616DC)
const MODEL_COLOR := Vector3i(0x3C, 0x3C, 0x3C)
## eab.c:122, :123 (MAIN_D_80134C2C, MAIN_D_80134C34)
const RING_ROTATION := Vector3i(0, 0x800, 0)
## eab.c:384
const ANIM_RISE := 0x21
## eab.c:370, :396
const ANIM_LOOP := 0x33
## eab.c:391
const VAB_ID := 5
## eab.c:390, :446, :666, :708
const SOUND_BANK := 8

## eab.c:128 (MAIN_D_801353F0, buildup state)
var buildup_active: bool = false
var buildup_frame: int = 0

## eab.c:364 (EAB_D_800617E8, spawn state)
var spawn_active: bool = false
var frame: int = 0
var phase: int = 0

## eab.c:215 (EAB_D_800617D0[0..2]: timer, kind)
var rings: Array[Dictionary] = []

## eab.c:467, 518 (EAB_D_80061A10[0..99]: timer, pos, color)
var particles: Array[Dictionary] = []

## eab.c:693 (initializeFlashData(EAB_D_80061800))
var fx: BattleFx = BattleFx.new()

## model.c:85 (ENTITY1_WIREFRAME_TOTAL, eab.c:414-415)
var wireframe_total: int = 16

## Inputs set by the host before tick()
var location: Vector3i = Vector3i.ZERO
var yaw: int = 0
var bone0: Vector3i = Vector3i.ZERO
var anim_id: int = 0
var anim_ended: bool = false

## Outputs cleared at the start of each tick()
var events: Array = []
var flashes_drawn: Array[int] = []
var backdrop: bool = false
var view: Dictionary = {}


func _init() -> void:
	for i in RINGS:
		rings.append({"timer": -1, "kind": RING_BUILDUP})
	for i in PARTICLES:
		particles.append({"timer": -1, "pos": Vector3i.ZERO, "color": Vector3i.ZERO})


## EAB_startBuildup (eab.c:649).
func start_buildup() -> void:
	buildup_frame = 0
	buildup_active = true
	for r in rings:
		r["timer"] = -1
	events.append("buildup_entity_hidden")
	events.append(["sound2", SOUND_BANK, 0])


## EAB_tick init (eab.c:680-706).
func start_spawn() -> void:
	frame = 0
	phase = 0
	spawn_active = true
	for p in particles:
		p["timer"] = -1
	fx.reset()
	for f in FLASHES:
		fx.create_flash(0x20, Vector3i(f[0], f[1], f[2]), 0x22, 0x32, 0, f[3], Vector3i(0x14, 0x14, 0x14), Vector3i(0xFF, 0xFF, 0xFF))
	events.append(["sound", SOUND_BANK, 1])


## EAB_tick(entity, 1) (eab.c:683-685).
func result() -> int:
	return frame


## One game frame (specs/map_events.md §4.3.1).
func tick() -> void:
	events.clear()
	flashes_drawn.clear()
	backdrop = false
	view.clear()

	# 1. buildup_active (eab.c:187, EAB_tickBuildup)
	if buildup_active:
		buildup_frame = (buildup_frame + 1) % 18
		if buildup_frame % 6 == 0:
			_add_ring(RING_BUILDUP)

	# 2. spawn_active (eab.c:349-458, EAB_tickSpawn)
	if spawn_active:
		frame += 1
		if anim_id == ANIM_LOOP and anim_ended:
			events.append(["animation", ANIM_LOOP])
		match phase:
			0:
				if frame >= 0x2D:
					flashes_drawn.append(0xFF)
				if frame >= 0x32:
					phase = 1
					events.append("entity_on_map")
					events.append(["animation", ANIM_RISE])
					events.append("hide_entities")
					events.append("map_layer_off")
					events.append("save_view")
					buildup_active = false
					events.append("stop_sound")
					events.append(["sound2", SOUND_BANK, 2])
					events.append(["vab", VAB_ID])
					_tick_phase_1()
			1:
				_tick_phase_1()
			2:
				if frame < 0x14A:
					_add_ring(RING_SPAWN)
				if frame >= 0x154:
					for r in rings:
						r["timer"] = -1
					frame = -1
					spawn_active = false

	# 3. Each ring with timer >= 0 (eab.c:241, :298)
	for r in rings:
		if r["timer"] >= 0:
			r["timer"] += 1
			var life := BUILDUP_RING_LIFE if r["kind"] == RING_BUILDUP else SPAWN_RING_LIFE
			if r["timer"] >= life:
				r["timer"] = -1

	# 4. Each particle with timer >= 0 (eab.c:595)
	for p in particles:
		if p["timer"] >= 0:
			if p["timer"] >= PARTICLE_LIFE:
				p["timer"] = -1
			else:
				p["timer"] += 1

	# 5. fx.tick()
	fx.tick()


func _tick_phase_1() -> void:
	_add_ring(RING_SPAWN)
	if frame == 0xD2:
		events.append(["animation", ANIM_LOOP])
	if frame >= 0x32 and frame < 0x53:
		flashes_drawn.append(PsxMath.lerp_int(0xFF, 0, 0x32, 0x52, frame))
	var v: int = PULSE[frame % 18]
	if v != 0:
		var g := PsxMath.lerp_int(0x32, 0xE6, 1, 5, v)
		var angle := PsxMath.lerp_int(0, 0x80, 0x32, 0x122, frame)
		g = PsxMath.div(g * PsxMath.sin512(angle), 4096) & 0xFF
		_add_particle(location, Vector3i(PARTICLE_RB, g, PARTICLE_RB))
	backdrop = true
	if frame >= 0x32 and frame < 0x123:
		wireframe_total = 0x10 - PsxMath.div(PsxMath.sin512(PsxMath.lerp_int(0x80, 0, 0x32, 0x122, frame)) * 16, 4096)
	var ry := 0x171C
	if frame >= 0x32 and frame < 0x123:
		ry = PsxMath.lerp_int(0x71C, 0x171C, 0x32, 0x122, frame)
	ry += yaw
	var distance := PsxMath.lerp_int(0xDAC, 0xBB8, 0x32, 0x140, frame)
	var height := PsxMath.lerp_int(0x258, 0x32, 0x32, 0x140, frame)
	var ref := bone0 - Vector3i(0, 0x64, 0)
	var eye := PsxMath.apply_matrix_lv(PsxMath.rot_matrix_zyx(Vector3i(0, ry, 0)), Vector3i(0, 0, distance)) + ref - Vector3i(0, height, 0)
	view = {"eye": eye, "ref": ref}
	if frame == 0x13F:
		view = {}
		events.append("restore_view")
	if frame >= 0x140:
		phase = 2
		for p in particles:
			p["timer"] = -1
		events.append("map_layer_on")
		events.append("show_entities")
		view = {}
		events.append("restore_view")
		events.append("stop_sound")
		events.append(["sound", SOUND_BANK, 3])


func _add_ring(kind: int) -> void:
	for r in rings:
		if r["timer"] < 0:
			r["timer"] = 0
			r["kind"] = kind
			break


func _add_particle(pos: Vector3i, color: Vector3i) -> void:
	for p in particles:
		if p["timer"] < 0:
			p["timer"] = 0
			p["pos"] = pos
			p["color"] = color
			break


## Ring scale for ring slot i (eab.c:269-271, 326-328).
func ring_scale(i: int) -> Vector3i:
	var t: int = rings[i]["timer"]
	var angle := PsxMath.lerp_int(0, 0x80, 1, 0x12, t)
	if rings[i]["kind"] == RING_BUILDUP:
		var xz := PsxMath.lerp_int(0x10B8, 0x614, 1, 0x12, t)
		var y := PsxMath.div(PsxMath.sin512(angle) * 0xC3C, 4096) + 0x15C
		return Vector3i(xz, y, xz)
	else:
		var xz := PsxMath.lerp_int(0x16CC, 0x10B8, 1, 0x12, t)
		var y := PsxMath.div(PsxMath.sin512(angle) * 0x2B8, 4096) + 0xAE
		return Vector3i(xz, y, xz)


## Particle half-size for particle slot i (eab.c:619).
func particle_size(i: int) -> int:
	return PsxMath.lerp_int(8, 0x9C4, 0, PARTICLE_LIFE, particles[i]["timer"])


## Particle colour for particle slot i (eab.c:639).
func particle_color(i: int) -> Vector3i:
	var t: int = particles[i]["timer"]
	var c: Vector3i = particles[i]["color"]
	return Vector3i(
		PsxMath.lerp_int(c.x, 0, 0, PARTICLE_LIFE, t),
		PsxMath.lerp_int(c.y, 0, 0, PARTICLE_LIFE, t),
		PsxMath.lerp_int(c.z, 0, 0, PARTICLE_LIFE, t)
	)
