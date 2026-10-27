class_name ParticleBursts
extends RefCounted
## The hit sparks' logic (createParticleFX, tickParticleFX, initializeParticleFX; efe.c:350-462,
## tickParticleFX from its assembly, asm/us/main/matchings/efe/tickParticleFX.s): up to 4 bursts,
## each a flash of 2-3 SPOT256 quarters on its third frame and 20-48 DEFEFF particles flying out.
## The random rolls happen here, drawn or not, so the rolls after them stay the C's. The field's
## ParticleFX (the training stations, in the HUD) and the battle's BattleFxView (in 3D) draw them.
##
## With an entity (the battle's hits) a burst also starts entity particles on it on its frames 10
## and 13, and mode 1 scatters dust clouds around its feet over its last frames.

const SLOTS := 4
## The 50 particle directions (FX_PARTICLE_DATA).
const PARTICLES := 50
## PARTICLE_FX_FLASH_COUNT / PARTICLE_FX_PARTICLE_COUNT by mode, and the timer of each mode.
const FLASH_COUNT := [2, 3, 2]
const PARTICLE_COUNT := [0x19, 0x30, 0x14]
const TIMERS := [0x13, 0x16, 0xE]
## The colour of each kind.
const COLORS := [[0xFF, 0x6E, 0x46], [0xFF, 0x6E, 0x46], [0xC8, 0xC8, 0x64], [0xCC, 0, 0x88], [0x32, 0x32, 0xFF],
		[0x96, 0x96, 0x96], [0xFF, 0x6E, 0x6E]]
const FLASH_STATE := 2
## RotMatrixZYX's angles: 4096 per turn.
const ONE_TURN := 4096.0

## FX_PARTICLE_DATA: rolled once (initializeParticleFX), shared by every view.
static var directions: Array[Vector3i] = []

## PARTICLE_FX_DATA: {state (-1 free), timer, end_frame, mode, color [r, g, b], position (PSX),
## entity (-1 none), spread [[dx, dy, dz, size] per flash]}.
var effects: Array = []
## The entity parts, set by the battle (none in the field): addEntityParticleFX(entity, timer);
## createCloudFX(Vector3i); func(entity) -> Vector3i (x, z of its position, radius).
var add_entity_particles := Callable()
var create_cloud := Callable()
var entity_ground := Callable()


func _init() -> void:
	for i in SLOTS:
		effects.append({"state": -1})


## initializeParticleFX: each direction is (0, 0, (rand % 150 + 250) × 16) turned by three random
## angles of ±1 turn (RotMatrixZYX).
static func initialize_directions() -> void:
	directions.clear()
	for i in PARTICLES:
		var ang := Vector3(((Rng.rand() & 0x7F) - 0x40) * 4096 / 64, ((Rng.rand() & 0x7F) - 0x40) * 4096 / 64,
				((Rng.rand() & 0x7F) - 0x40) * 4096 / 64) * TAU / ONE_TURN
		var length := ((Rng.rand() % 150) + 0xFA) * 0x10
		var v := Basis.from_euler(ang, EULER_ORDER_ZYX) * Vector3(0, 0, length)
		directions.append(Vector3i(roundi(v.x), roundi(v.y), roundi(v.z)))


## createParticleFX(kind, mode, pos, entity, lifetime): the first free slot. The C rolls the first
## two flashes' spreads (dx, dy, dz, size each) before it checks the mode and the kind, so an
## unknown one still uses those 8 rolls; mode 1 rolls a third flash.
func create(kind: int, mode: int, position_psx: Vector3i, lifetime := 0, entity := -1) -> void:
	var slot := -1
	for i in SLOTS:
		if effects[i]["state"] == -1:
			slot = i
			break
	if slot < 0:
		return
	var spread := []
	for i in 2:
		spread.append([(Rng.rand() % 200) - 100, (Rng.rand() % 200) - 100, (Rng.rand() % 200) - 100,
				(Rng.rand() % 170) + 250])
	if mode == 1:
		spread.append([(Rng.rand() % 200) - 100, (Rng.rand() % 200) - 100, (Rng.rand() % 200) - 100,
				(Rng.rand() % 200) + 300])
	if mode < 0 or mode >= TIMERS.size() or kind < 0 or kind >= COLORS.size():
		return
	effects[slot] = {"state": 0, "timer": TIMERS[mode], "end_frame": lifetime + 4, "mode": mode,
			"color": COLORS[kind], "position": position_psx, "entity": entity, "spread": spread}


func active_count() -> int:
	var n := 0
	for fx in effects:
		if fx["state"] >= 0:
			n += 1
	return n


## tickParticleFX for every burst, one game frame.
func tick() -> void:
	for i in SLOTS:
		var fx: Dictionary = effects[i]
		if fx["state"] < 0:
			continue
		fx["state"] += 1
		fx["end_frame"] -= 1
		var entity: int = fx["entity"]
		var mode: int = fx["mode"]
		if fx["state"] == 10:
			# Mode 1 doesn't test the entity (a NULL one would crash the PSX).
			if mode == 1 and entity >= 0:
				for k in 3:
					_entity_particles(entity, 0x16)
			elif mode == 0 and entity >= 0:
				for k in 3:
					_entity_particles(entity, 0xE)
			continue
		if fx["state"] == 13:
			if mode == 1 and entity >= 0:
				_entity_particles(entity, 0x16)
				_entity_particles(entity, 0xE)
			elif mode == 0 and entity >= 0:
				_entity_particles(entity, 0xE)
				_entity_particles(entity, 0xE)
			continue
		if fx["end_frame"] >= 0 and fx["end_frame"] < 4 and mode == 1:
			_scatter_clouds(fx)
			continue
		if fx["state"] >= fx["timer"] and fx["end_frame"] < 0:
			effects[i] = {"state": -1}


func _entity_particles(entity: int, timer: int) -> void:
	if add_entity_particles.is_valid():
		add_entity_particles.call(entity, timer)


## Mode 1's last frames: end_frame + 2 clouds at a random angle, radius + rand % (radius / 2) from
## the entity's position (_sin / _cos of a raw rand(), 512 per turn).
func _scatter_clouds(fx: Dictionary) -> void:
	if fx["entity"] < 0 or not entity_ground.is_valid():
		return
	var ground: Vector3i = entity_ground.call(fx["entity"])
	var radius := ground.z
	var half := PsxMath.s16(radius >> 1)
	for n in fx["end_frame"] + 2:
		var angle := Rng.rand()
		var roll := Rng.rand()
		# MIPS div by 0 leaves the dividend in hi.
		var distance := radius + (roll % half if half != 0 else roll)
		var x := ground.x + ((distance * PsxMath.sin512(angle)) >> 12)
		var z := ground.y - ((distance * PsxMath.cos512(angle)) >> 12)
		if create_cloud.is_valid():
			create_cloud.call(Vector3i(x, 0, z))


## lerp (effect_common.c:278), with its remainder correction.
static func lerp_c(start: int, end: int, t0: int, t1: int, t: int) -> int:
	if t1 == t0:
		return 0
	var span := end - start
	var result := (span * (t - t0)) / (t1 - t0)
	if span >= 0:
		result = result % (span + 1)
		if result < 0:
			result += span
	else:
		result = result % (span - 1)
		if result > 0:
			result += span
	return result + start


## The burst's distance factor at a state: _sin(lerp(0, 0x6E, 0, timer, state)) >> 7.
static func burst_factor(timer: int, state: int) -> int:
	return PsxMath.sin512(lerp_c(0, 0x6E, 0, timer, state)) >> 7


## A particle's PSX position at a state.
static func particle_position(fx: Dictionary, i: int) -> Vector3i:
	var d := burst_factor(fx["timer"], fx["state"])
	return Vector3i(fx["position"]) + Vector3i((d * directions[i].x) >> 9, (d * directions[i].y) >> 9,
			(d * directions[i].z) >> 9)
