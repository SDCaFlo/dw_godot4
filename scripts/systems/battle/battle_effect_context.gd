class_name BattleEffectContext
extends RefCounted
## What a battle effect may read and do in the battle (specs/battle_effects.md §3.1). The battle
## owns one and hands it to every BattleEffect; an effect never reaches the battle another way.
## Entities are the original's ENTITY_TABLE indices: 0 the tamer, 1 the partner, 2-9 the map
## Digimon; -1 is "none" (NULL). Positions, rotations and matrices are in PSX units (y down, 4096
## = a turn / 1.0; matrices as PsxMath's PackedInt32Array(12)).
## This base class is a world without entities: the battle (5d-3) and the tests extend it.

## The C's entity table size (ENTITY_TABLE[10]).
const ENTITIES := 10

var data: Node


# --- entities -------------------------------------------------------------------------------------

## ENTITY_TABLE[id] != NULL.
func entity_present(_id: int) -> bool:
	return false


func is_on_map(_id: int) -> bool:
	return false


func is_on_screen(_id: int) -> bool:
	return false


## The Digimon id (entity->type); -1 if none.
func digimon_type(_id: int) -> int:
	return -1


## stats.current.currentHP.
func current_hp(_id: int) -> int:
	return 0


## stats.current.isHit: set when an effect hits it, cleared by the battle (specs/battle.md §2.11).
func is_hit(_id: int) -> bool:
	return false


func set_hit(_id: int, _value: bool) -> void:
	pass


## posData->location.
func location(_id: int) -> Vector3i:
	return Vector3i.ZERO


## posData->rotation.vy.
func rotation_y(_id: int) -> int:
	return 0


## The world matrix of bone `bone` (posData[bone].posMatrix.workm, calculateBoneMatrix: a bone at
## or past the Digimon's bone count is bone 0).
func bone_matrix(_id: int, _bone: int) -> PackedInt32Array:
	return PsxMath.identity()


## entityLookAtLocation(entity, target location) with its matrix refreshed (BTL_faceTargetEntity).
func look_at(_id: int, _target: int) -> void:
	pass


# --- Digimon data ---------------------------------------------------------------------------------

func _digimon(id: int) -> Dictionary:
	var type := digimon_type(id)
	return data.digimon(type) if data != null and type >= 0 else {}


## DIGIMON_DATA[type].radius.
func radius(id: int) -> int:
	return int(_digimon(id).get("radius", 0))


## DIGIMON_DATA[type].height.
func height(id: int) -> int:
	return int(_digimon(id).get("height", 0))


## getOriginalType(type) (effect_common.c:320).
func original_type(id: int) -> int:
	return int(_digimon(id).get("original_type", -1))


# --- camera and screen ----------------------------------------------------------------------------

## GsWSMATRIX: world to screen.
func world_screen_matrix() -> PackedInt32Array:
	return PsxMath.identity()


## VIEWPORT_DISTANCE (the projection distance H).
func viewport_distance() -> int:
	return 0x200


## RotTransPers of a world position with GsWSMATRIX (worldPosToScreenPos, effect_common.c:504):
## {"screen": Vector2i (GTE SXY), "sz": int (depth)}.
func world_to_screen(pos: Vector3i) -> Dictionary:
	var m := world_screen_matrix()
	var v := PsxMath.apply_matrix_lv(m, PsxMath.s16_vec(pos)) + PsxMath.translation(m)
	var h := viewport_distance()
	var z := maxi(v.z, 1)
	return {"screen": Vector2i(PsxMath.div(v.x * h, z), PsxMath.div(v.y * h, z)), "sz": v.z}


## setMapLayerEnabled (BTL_disableMapLayer: off for this frame; the engine's tick turns it back on).
func set_map_layer(_enabled: bool) -> void:
	pass


## BTL_setupFixedCamera / BTL_restoreCameraView.
func set_fixed_camera(_fixed: bool) -> void:
	pass


# --- services -------------------------------------------------------------------------------------

## playSound(bank, id).
func play_sound(_bank: int, _id: int) -> void:
	pass


## playSound2(bank, id): a looping sound; returns its mask, or -1.
func play_loop(_bank: int, _id: int) -> int:
	return -1


## thunkStopSoundMask(mask).
func stop_loop(_mask: int) -> void:
	pass


## createParticleFX, createCloudFX, addEntityParticleFX, EFECreateFlash: the shared effects. `args`
## are the C's arguments; the draw-side code decides what to show.
func effect(_kind: String, _args: Array) -> void:
	pass
