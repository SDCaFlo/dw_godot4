class_name GalleryWorld
extends FieldBattleWorld
## The effects gallery's world (EffectGallery, specs/battle_effects.md §7.4), not part of the
## original: a battle-less context with the gallery's two Digimon as the caster (entity 1) and the
## target (entity 2); the camera, the bones and the sounds are the field's, as in a battle. The
## other entities are absent, so a technique only ever sees these two.

## The gallery's Digimon by entity id (1, 2), their Digimon ids, their isHit flags.
var digimon := {}
var types := {}
var _hit := {}


func _node(id: int) -> Node3D:
	return digimon.get(id) as Node3D


func digimon_type(id: int) -> int:
	return int(types.get(id, -1))


func is_on_map(id: int) -> bool:
	return _node(id) != null


func is_on_screen(id: int) -> bool:
	return _node(id) != null


## Alive, so the hit tests take them.
func current_hp(id: int) -> int:
	return 1 if _node(id) != null else 0


func is_hit(id: int) -> bool:
	return bool(_hit.get(id, false))


func set_hit(id: int, value: bool) -> void:
	_hit[id] = value
