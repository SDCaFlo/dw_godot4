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
## The shared effects (sparks, entity particles, clouds, flashes); the EffectHost makes it.
var fx: BattleFx
## The visuals outside the scripts (statuses, finisher aura, aura projectiles, items, buffs); the
## EffectHost makes it.
var visuals: BattleVisuals


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


## translateConditionFXToEntity (effect_common.c:307): the point CONDITION_FX_OFFSETS gives the
## Digimon's original type, through its bone's world matrix (the status effects start there).
func condition_fx_position(id: int) -> Vector3i:
	var entry: Dictionary = data.condition_fx_offset(digimon_type(id)) if data != null and digimon_type(id) >= 0 else {}
	var o: Dictionary = entry.get("offset", {})
	var m := bone_matrix(id, int(entry.get("bone", 0)))
	var v := PsxMath.s16_vec(PsxMath.apply_matrix_sv(m, Vector3i(int(o.get("x", 0)), int(o.get("y", 0)), int(o.get("z", 0)))))
	return PsxMath.s16_vec(v + PsxMath.s16_vec(PsxMath.translation(m)))


## findAABBHitEntity (aabb.c:48): the first entity from `start` (not `ignore`) whose box (centred at
## half its height, half its radius wide) overlaps the box at `center`, `extent` half sizes; -1.
func find_aabb_entity(center: Vector3i, extent: Vector3i, ignore: int, start: int) -> int:
	for i in range(start, ENTITIES):
		if not entity_present(i) or i == ignore:
			continue
		var loc := location(i)
		var c := Vector3i(loc.x, loc.y - (height(i) >> 1), loc.z)
		var e := Vector3i(radius(i) >> 1, height(i) >> 1, radius(i) >> 1)
		if c.x + e.x < center.x - extent.x or c.x - e.x > center.x + extent.x:
			continue
		if c.y + e.y < center.y - extent.y or c.y - e.y > center.y + extent.y:
			continue
		if c.z + e.z < center.z - extent.z or c.z - e.z > center.z + extent.z:
			continue
		return i
	return -1


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


## The drawing offset: the projection centre's screen pixel (getDrawingOffsetCopy).
func drawing_offset() -> Vector2i:
	return Vector2i(160, 120)


## The OT slot of the battle's DR_OFFSET (BTL_battleTickFrame, battle_main.c:2604; the field's
## applyDrawOffset too): the frame's primitives in this slot and below are drawn after it, with the
## screen centre (160, 120: DR_OFFSETS, main.c:3579) as their origin instead of DRAWING_OFFSET.
const SCREEN_ORIGIN_SLOT := 0x20


## A primitive's screen point (as the C wrote it) at OT slot `slot`, relative to the projection
## centre: a slot at or below SCREEN_ORIGIN_SLOT is drawn from the screen centre, the others from
## the drawing offset (which is the projection centre).
func slot_point(point: Vector2, slot: int) -> Vector2:
	if slot > SCREEN_ORIGIN_SLOT:
		return point
	var ofs := drawing_offset()
	return point + Vector2(0xA0 - ofs.x, 0x78 - ofs.y)


## The Godot point drawn at `relative` (screen pixels from the projection centre) at view depth
## `depth`: where the views put the effects' screen primitives.
func screen_to_world(relative: Vector2, depth: float) -> Vector3:
	return Vector3(relative.x, -relative.y, -depth)


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


## The shared effects (BattleFx), by kind:
## - "particles" [kind, mode, position, entity, lifetime]: createParticleFX;
## - "cloud" [position]: createCloudFX;
## - "entity_particles" [entity, timer]: addEntityParticleFX;
## - "flash" [mode, position, fixed depth, frames, scale min, scale max, colour min, colour max]:
##   EFECreateFlash (positions and colours as Vector3i).
func effect(kind: String, args: Array) -> void:
	if fx == null:
		return
	match kind:
		"particles":
			fx.create_particles(args[0], args[1], args[2], args[3], args[4])
		"cloud":
			fx.create_cloud(args[0])
		"entity_particles":
			fx.add_entity_particles(args[0], args[1])
		"flash":
			fx.create_flash(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7])
