class_name EffectHost
extends RefCounted
## The battle's effect engine (specs/battle_effects.md §3.2): it creates one BattleEffect scene per
## loaded technique (BTL_loadMoveEFE), runs them in slot order every frame (BTL_tickEFEEngine /
## BTL_renderEFEEngine), and keeps the engine's shared state: the 16 slots and texture places, the
## VM globals, the attack-object queue the battle pops (addAttackObject / popAttackObject), the 10
## looping-sound channels and the 4 particle emitters. A technique's scene is the move record's
## `effect_scene`, or the original's EfeEffect.

const SLOTS := 16
const TEXTURE_PLACES := 16
## ATTACK_OBJECTS[16] (graphics.c:91).
const ATTACK_OBJECTS := 16
## EFE_SOUND_DATA[10]; the effect sounds that loop (BTL_playEFESound).
const SOUND_CHANNELS := 10
const LOOP_SOUNDS := [0x12, 0x20, 0x21, 0x22]
## The battle effects' sound bank (playSound(8, id)).
const SOUND_BANK := 8
## EFE_PARTICLE_EMITTERS[4], 21 particles each (the 21st is the scan's end).
const EMITTERS := 4
const EMITTER_PARTICLES := 20
const DEFAULT_SCENE := "res://scenes/battle/effects/efe_effect.tscn"

## The context the effects read the battle through.
var ctx: BattleEffectContext
var data: Node
## Where the effect nodes go (the battle's 3D world); null headless.
var world: Node
## A test hook: when set, every technique uses this scene (a mod's effect in the tests).
var scene_override := ""

## The slots' effects (EFE_DATA_PTR); null = free.
var slots: Array = []
## EFE_LOADED_MOVE_DATA: the effect id per slot, -1 free.
var loaded: Array[int] = []
## UNUSED_EFE_ARRAY: -1 when started, 1 after a tick, 0 when the script marked it finished.
var unused: Array[int] = []
var _texture_taken: Array[bool] = []

# The VM's globals, shared by every effect as in the C.
var target_entity_index := 1
var hit_entity_index := 1
## EFE_SUB_EFFECT_INDEX and COMBAT_EFFECT_ITR: the tick loop's positions (stale outside it).
var sub_effect_index := 0
var combat_effect_itr := 0
var bone_offset := 0

## ATTACK_OBJECTS: {victim, active, position, effect, sub_effect, caster}, oldest first.
var attack_objects: Array[Dictionary] = []
## EFE_SOUND_DATA: {mask, effect, context}.
var _sounds: Array[Dictionary] = []
## EFE_PARTICLE_EMITTERS: {effect, instance, frames, start_offset, start_velocity, acceleration,
## color, type, distance[], velocity[]} or {} when free.
var emitters: Array[Dictionary] = []

static var _folders := {}


func _init(context: BattleEffectContext = null) -> void:
	ctx = context
	data = context.data if context != null else null
	if ctx != null and ctx.fx == null:
		ctx.fx = BattleFx.new(ctx)
	if ctx != null and ctx.visuals == null:
		ctx.visuals = BattleVisuals.new(ctx)
	if ctx != null:
		ctx.visuals.host = self
	reset()


## BTL_initializeEFEEngine: empty slots, sounds, emitters, queue.
func reset() -> void:
	slots.resize(SLOTS)
	slots.fill(null)
	loaded.resize(SLOTS)
	loaded.fill(-1)
	unused.resize(SLOTS)
	unused.fill(0)
	_texture_taken.resize(TEXTURE_PLACES)
	_texture_taken.fill(false)
	attack_objects.clear()
	_sounds.clear()
	for i in SOUND_CHANNELS:
		_sounds.append({"mask": -1, "effect": null, "context": -1})
	emitters.clear()
	for i in EMITTERS:
		emitters.append({})
	if ctx != null and ctx.fx != null:
		ctx.fx.reset()
	if ctx != null and ctx.visuals != null:
		ctx.visuals.remove_all()


## The asset porter folder of a technique's EFEDAT slot (efe/index.json), "" if none.
static func efe_folder(technique: int) -> String:
	if _folders.is_empty():
		var path := Content.path("efe/index.json")
		if FileAccess.file_exists(path):
			var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if index is Dictionary:
				for e in index.get("effects", []):
					_folders[int(e["slot"])] = String(e["folder"])
	return _folders.get(technique, "")


# --- loading ---------------------------------------------------------------------------------------

## BTL_loadMoveEFE: one effect per entry {technique, caster} (a fighter's technique slot). Returns
## the slot per entry (effectSlot), or -1 when it failed to load.
func load_moves(entries: Array) -> Array[int]:
	var out: Array[int] = []
	for e in entries:
		out.append(_load(int(e["technique"]), int(e.get("caster", -1))))
	return out


func _scene_for(technique: int) -> String:
	if scene_override != "":
		return scene_override
	var move: Dictionary = data.move(technique) if data != null else {}
	var path := String(move.get("effect_scene", ""))
	return path if path != "" else DEFAULT_SCENE


func _load(technique: int, caster: int) -> int:
	var k := loaded.find(-1)
	if k < 0:
		return -1
	var effect := load(_scene_for(technique)).instantiate() as BattleEffect
	if effect == null:
		return -1
	if effect is EfeEffect:
		effect.host = self
	effect.slot_index = k
	effect.hit.connect(_on_hit)
	var result := effect.setup(technique, caster, ctx)
	if result != BattleEffect.OK_LOADED:
		effect.unload()
		effect.free()
		return -1
	if world != null:
		world.add_child(effect)
	slots[k] = effect
	loaded[k] = technique + 0x100
	return k


## BTL_unloadAllEFESlots + BTL_removeEFEEngine.
func unload_all() -> void:
	for k in SLOTS:
		var effect: BattleEffect = slots[k]
		if effect != null:
			effect.unload()
			effect.free()
	stop_sounds()
	reset()


func take_texture_place() -> int:
	var i := _texture_taken.find(false)
	if i >= 0:
		_texture_taken[i] = true
	return i


func free_texture_place(i: int) -> void:
	if i >= 0 and i < TEXTURE_PLACES:
		_texture_taken[i] = false


# --- the battle's calls ----------------------------------------------------------------------------

## BTL_startEFE(k): the use's sub-effect index, or -1.
func start(k: int, attacker: int, target: int) -> int:
	if k < 0 or k >= SLOTS or slots[k] == null or loaded[k] < 0:
		return -1
	unused[k] = -1
	return slots[k].start(attacker, target)


## BTL_stopEFESubEffect(k, sub).
func stop(k: int, sub_effect: int) -> void:
	if sub_effect < 0 or k < 0 or k >= SLOTS or slots[k] == null:
		return
	slots[k].stop(sub_effect)


## BTL_tickEFEEngine, then the shared effects' objects (BattleFx) and the battle visuals
## (BattleVisuals).
func tick() -> void:
	if ctx != null:
		ctx.set_map_layer(true)
	for k in SLOTS:
		if unused[k] == 0:
			unused[k] = 1
	for k in SLOTS:
		combat_effect_itr = k
		if slots[k] != null:
			slots[k].tick()
	combat_effect_itr = SLOTS
	_tick_emitters()
	for s in _sounds:
		if s["mask"] >= 0 and s["effect"] != null and _context_frame(s["effect"], s["context"]) < 0:
			ctx.stop_loop(s["mask"])
			s["mask"] = -1
	if ctx != null and ctx.fx != null:
		ctx.fx.tick()
	if ctx != null and ctx.visuals != null:
		ctx.visuals.tick()


## BTL_renderEFEEngine.
func draw() -> void:
	for k in SLOTS:
		if slots[k] != null:
			slots[k].draw()


## popAttackObject(victim): the victim's oldest hit, or {}.
func pop_attack_object(victim: int) -> Dictionary:
	for i in attack_objects.size():
		if attack_objects[i]["victim"] == victim:
			return attack_objects.pop_at(i)
	return {}


# --- the effects' calls ----------------------------------------------------------------------------

## A hit from an effect: addAttackObject(victim, 1, pos, COMBAT_EFFECT_ITR, sub, caster).
func report_hit(effect: BattleEffect, victim: int, position: Vector3i, sub_effect: int, caster: int) -> void:
	effect.hit.emit(victim, position, sub_effect, caster)


func _on_hit(victim: int, position: Vector3i, sub_effect: int, caster: int) -> void:
	add_attack_object(victim, position, combat_effect_itr, sub_effect, caster)


## addAttackObject(victim, 1, pos, effect, sub, caster): `effect` the slot (COMBAT_EFFECT_ITR), or
## 0x179 for an aura projectile (BTL_getAttackTech: the generic technique).
func add_attack_object(victim: int, position: Vector3i, effect: int, sub_effect: int, caster: int) -> void:
	if attack_objects.size() >= ATTACK_OBJECTS:
		return
	attack_objects.append({"victim": victim, "active": 1, "position": position, "effect": effect,
			"sub_effect": sub_effect, "caster": caster})


## BTL_markEFEFinished.
func mark_finished() -> void:
	if combat_effect_itr < SLOTS:
		unused[combat_effect_itr] = 0


## BTL_playEFESound.
func play_effect_sound(effect: EfeEffect, context: int, id: int) -> void:
	if id < 0 or ctx == null:
		return
	if not id in LOOP_SOUNDS:
		ctx.play_sound(SOUND_BANK, id)
		return
	for s in _sounds:
		if s["mask"] < 0:
			s["mask"] = ctx.play_loop(SOUND_BANK, id)
			s["effect"] = effect
			s["context"] = context
			return


## BTL_stopEFESounds.
func stop_sounds() -> void:
	for s in _sounds:
		if s["mask"] >= 0 and ctx != null:
			ctx.stop_loop(s["mask"])
		s["mask"] = -1


func _context_frame(effect: EfeEffect, context: int) -> int:
	if context < 0 or context >= effect.contexts.size():
		return -1
	var instance: int = effect.contexts[context]["instance"]
	return effect.frame_of(instance) if instance != 0 else -1


## BTL_addParticleEmitter.
func add_emitter(effect: EfeEffect, instance: int, kind: int, n: int, color: Vector3i, frames: int) -> void:
	var i := 0
	while i < EMITTERS and not emitters[i].is_empty():
		i += 1
	if i == EMITTERS:
		return
	var distance := []
	distance.resize(EMITTER_PARTICLES + 1)
	distance.fill(0)
	emitters[i] = {"effect": effect, "instance": instance, "type": kind, "frames": frames, "color": color,
			"start_offset": PsxMath.s16(n * 16), "start_velocity": PsxMath.s16(PsxMath.div(n, 8) * 16),
			"acceleration": PsxMath.s16(PsxMath.div(n, 160) * 16), "distance": distance,
			"velocity": distance.duplicate(), "direction": [], "position": []}
	emitters[i]["direction"].resize(EMITTER_PARTICLES + 1)
	emitters[i]["position"].resize(EMITTER_PARTICLES + 1)


## BTL_tickParticleEmitters (battle_effect.c:1898): a new particle a frame (3 rand() calls, which
## the battle's other rolls follow), the others slow down; the emitter ends with its instance or
## its frames.
func _tick_emitters() -> void:
	for i in EMITTERS:
		var e: Dictionary = emitters[i]
		if e.is_empty():
			continue
		var effect: EfeEffect = e["effect"]
		if effect.frame_of(e["instance"]) == -1:
			emitters[i] = {}
			continue
		var k := 0
		while k < EMITTER_PARTICLES and e["distance"][k] > 0:
			k += 1
		if k != EMITTER_PARTICLES:
			e["distance"][k] = e["start_offset"]
			e["velocity"][k] = e["start_velocity"]
			var rot := Vector3i()
			rot.x = PsxMath.div(((Rng.rand() & 0x7F) - 0x40) << 12, 64)
			rot.y = PsxMath.div(((Rng.rand() & 0x7F) - 0x40) << 12, 64)
			rot.z = PsxMath.div(((Rng.rand() & 0x7F) - 0x40) << 12, 64)
			e["direction"][k] = PsxMath.apply_matrix_sv(PsxMath.rot_matrix_zyx(rot), Vector3i(0, 0, e["start_offset"]))
			e["position"][k] = effect.read_vec(e["instance"] + EfeEffect.I_POS)
		for p in EMITTER_PARTICLES:
			if e["distance"][p] > 0:
				e["distance"][p] = PsxMath.s16(e["distance"][p] - e["velocity"][p])
				e["velocity"][p] = PsxMath.s16(e["velocity"][p] - e["acceleration"])
		e["frames"] = PsxMath.s16(e["frames"] - 1)
		if e["frames"] <= 0:
			emitters[i] = {}
