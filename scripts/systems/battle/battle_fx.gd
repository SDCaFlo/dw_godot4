class_name BattleFx
extends RefCounted
## The main binary's shared effects as a battle uses them (specs/battle_effects.md §7.3): the hit
## sparks (ParticleBursts: createParticleFX with its entity parts), the entity particles
## (addEntityParticleFX, efe.c:611-695), the dust clouds (createCloudFX, efe.c:714-744) and the
## flashes (EFECreateFlash, tickEFEFlash; efe.c:808-897). Logic only, headless too: the sparks and
## the entity particles roll rand(), and the battle's later rolls follow theirs. BattleFxView draws
## them. Each is its own object in the C's list; they tick here in the order sparks, entity
## particles, clouds, flashes (their place among the battle's other objects is the port's).

## ENTITY_PARTICLE_FX_DATA[20].
const ENTITY_SLOTS := 20
## CLOUD_FX_DATA[0x3C] and its 14 states.
const CLOUD_SLOTS := 0x3C
const CLOUD_STATES := 0xE
## EFE_FLASH_DATA[12]; the flash modes EFECreateFlash knows (|mode|).
const FLASH_SLOTS := 12
const FLASH_MODES := [0, 1, 0x20]
## ENTITY_PARTICLE_FX_MODES: the 9 sprites.
const ENTITY_SPRITES := 9

var ctx: BattleEffectContext
var bursts := ParticleBursts.new()
## ENTITY_PARTICLE_FX_DATA: {timer (-1 free), bone, sprite, owner}.
var entity_particles: Array[Dictionary] = []
## CLOUD_FX_DATA: {state (-1 free), x, z}.
var clouds: Array[Dictionary] = []
## EFE_FLASH_DATA: {progress (-1 free), t_max, mode, fixed_depth, scale_min, scale_max,
## color_min, color_max (Vector3i), position (PSX)}.
var flashes: Array[Dictionary] = []


func _init(context: BattleEffectContext = null) -> void:
	ctx = context
	bursts.add_entity_particles = func(entity: int, timer: int) -> void: add_entity_particles(entity, timer)
	bursts.create_cloud = create_cloud
	bursts.entity_ground = _entity_ground
	reset()


func reset() -> void:
	for fx in bursts.effects.size():
		bursts.effects[fx] = {"state": -1}
	entity_particles.clear()
	for i in ENTITY_SLOTS:
		entity_particles.append({"timer": -1})
	clouds.clear()
	for i in CLOUD_SLOTS:
		clouds.append({"state": -1, "x": 0, "z": 0})
	flashes.clear()
	for i in FLASH_SLOTS:
		flashes.append({"progress": -1})


# --- creating -----------------------------------------------------------------------------------

## createParticleFX(kind, mode, pos, entity, lifetime).
func create_particles(kind: int, mode: int, position: Vector3i, entity: int, lifetime: int) -> void:
	bursts.create(kind, mode, position, lifetime, entity)


## addEntityParticleFX(owner, timer): sparkles on a random bone (1 to boneCount - 1); -1 when the
## 20 slots are used.
func add_entity_particles(owner: int, timer: int) -> int:
	var i := 0
	while i < ENTITY_SLOTS and entity_particles[i]["timer"] >= 0:
		i += 1
	if i == ENTITY_SLOTS:
		return -1
	entity_particles[i] = {"timer": timer, "bone": _random_bone(owner), "sprite": 0, "owner": owner}
	return i


## createCloudFX(pos): the first free slot, at (x, z); nothing when all 60 are used.
func create_cloud(position: Vector3i) -> void:
	for c in clouds:
		if c["state"] < 0:
			c["state"] = 0
			c["x"] = position.x
			c["z"] = position.z
			return


## EFECreateFlash: `mode` 0 / 1 / 0x20 (negative: the C adds the screen's drawing offset, 0 for
## the battle's centred view). FLASH_INSTANCE is the slot, or -1.
func create_flash(mode: int, position: Vector3i, fixed_depth: int, t_max: int, scale_min: int, scale_max: int,
		color_min: Vector3i, color_max: Vector3i) -> int:
	var i := 0
	while i < FLASH_SLOTS and flashes[i]["progress"] >= 0:
		i += 1
	if i == FLASH_SLOTS or not absi(mode) in FLASH_MODES:
		return -1
	flashes[i] = {"progress": 0, "t_max": t_max, "mode": mode, "fixed_depth": fixed_depth, "scale_min": scale_min,
			"scale_max": scale_max, "color_min": color_min, "color_max": color_max, "position": position}
	return i


# --- the frame ----------------------------------------------------------------------------------

func tick() -> void:
	bursts.tick()
	_tick_entity_particles()
	for c in clouds:
		if c["state"] >= 0:
			c["state"] += 1
			if c["state"] >= CLOUD_STATES:
				c["state"] = -1
	for f in flashes:
		if f["progress"] >= 0:
			f["progress"] += 1
			if f["progress"] >= f["t_max"]:
				f["progress"] = -1


## tickEntityParticleFX: gone at 0; every 4th frame a new bone and sprite.
func _tick_entity_particles() -> void:
	for p in entity_particles:
		if p["timer"] < 0:
			continue
		if p["timer"] <= 0:
			p["timer"] = -1
			continue
		if p["timer"] % 4 == 0:
			p["bone"] = _random_bone(p["owner"])
			p["sprite"] = Rng.rand() % ENTITY_SPRITES
		p["timer"] -= 1


func active_count() -> int:
	var n := bursts.active_count()
	for p in entity_particles:
		n += 1 if p["timer"] >= 0 else 0
	for c in clouds:
		n += 1 if c["state"] >= 0 else 0
	for f in flashes:
		n += 1 if f["progress"] >= 0 else 0
	return n


## rand() % (DIGIMON_DATA[type].boneCount - 1) + 1.
func _random_bone(owner: int) -> int:
	var bones := 1
	if ctx != null and ctx.data != null:
		bones = int(ctx.data.digimon(ctx.digimon_type(owner)).get("bone_count", 1))
	var roll := Rng.rand()
	# MIPS div by 0 (a one-bone Digimon) leaves the dividend in hi.
	return (roll % (bones - 1) if bones > 1 else roll) + 1


## tickParticleFX's clouds: posData[0]'s position (x, z) and the Digimon's radius.
func _entity_ground(entity: int) -> Vector3i:
	if ctx == null:
		return Vector3i.ZERO
	var t := PsxMath.translation(ctx.bone_matrix(entity, 0))
	return Vector3i(t.x, t.z, ctx.radius(entity))
