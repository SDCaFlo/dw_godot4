class_name BattleEffect
extends Node3D
## The API of a technique's battle effect (specs/battle_effects.md §3.0-3.1). The battle creates one
## per loaded technique (one per fighter technique slot) for the whole battle, calls it once per
## original frame in its frame order, and gets the effect's hits back as signals. The effect never
## computes damage: it only says whom it touched, where, and when.
##
## The original techniques are EfeEffect (their bytecode). A move record's `effect_scene` can name
## another scene whose root script extends this one; it must:
## - run only from tick() / draw() (never _process), and read the battle only through `ctx`;
## - mark a victim with ctx.set_hit(victim, true) before emitting `hit` (one hit per victim until
##   the battle clears the mark);
## - emit `finished` when a use's last instance has ended.

## One attack object (addAttackObject): `victim` and `caster` are entity ids, `position` PSX units,
## `sub_effect` the use's instance index (the battle tells blocks apart by it).
signal hit(victim: int, position: Vector3i, sub_effect: int, caster: int)
## A use started by start() has ended.
signal finished(sub_effect: int)

## Load errors (BTL_setupLoadedEFEFile's isLoaded): the battle treats the slot as -1.
const OK_LOADED := 0
const ERR_NO_SLOT := -1
const ERR_NO_TEXTURE := -2
const ERR_WRONG_ID := -3
const ERR_ID_RANGE := -4
const ERR_NO_MODEL := -5

## The technique id (MOVE_DATA index).
var technique := -1
## The fighter slot (0 the partner, 1-3 the enemies) whose technique this is.
var caster_slot := -1
var ctx: BattleEffectContext
## The engine slot index the host gave it (COMBAT_EFFECT_ITR for its hits).
var slot_index := -1


## Loads what the effect needs. Returns OK_LOADED or a negative load error.
func setup(technique_id: int, caster: int, context: BattleEffectContext) -> int:
	technique = technique_id
	caster_slot = caster
	ctx = context
	return OK_LOADED


## Begins a use (BTL_startEFE) by `attacker` at `target` (entity ids, -1 = none). Returns the use's
## sub-effect index, which the battle keeps to stop it, or -1.
func start(_attacker: int, _target: int) -> int:
	return -1


## Ends a use early (BTL_stopEFESubEffect).
func stop(_sub_effect: int) -> void:
	pass


## The logic pass of one frame (BTL_tickEFEEngine): motion, hits, sounds.
func tick() -> void:
	pass


## The drawing pass of one frame (BTL_renderEFEEngine). Runs headless too: some originals compute
## values there.
func draw() -> void:
	pass


func is_running() -> bool:
	return false


## Frees what setup() loaded (BTL_unloadEFESlot).
func unload() -> void:
	pass
