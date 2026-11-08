class_name FieldFishingWorld
extends FishingWorld
## FishingWorld on the field (specs/fishing.md §5.2): the real tamer, the GameState inventory and
## triggers, the Sound autoload, GameData's texts, and the FieldMap's scroll. Godot positions
## become PSX world units as FieldMap.background_pixel takes them: (x, -y, -z).

## TRIGGER_HAVE_OLD_FISHROD / TRIGGER_HAVE_AMAZING_ROD (include/dw/trigger.h:829-830).
const TRIGGER_OLD_ROD := 45
const TRIGGER_AMAZING_ROD := 46
## ITEM_PARA.sortingValue == 2: food (hasFoodItem, main/fish.c:36).
const FOOD_SORT := 2
## INVENTORY.types.array[30]: hasFoodItem and FISH_openBaitMenu read all 30 slots.
const SLOTS := 30
const EMPTY := 0xFF

var tamer: Tamer
var field_map: FieldMap
var game_state: Node
var data: Node
var sound: Node


## The bone's world matrix in PSX axes: S · B · S with S = diag(1, -1, -1), at 4096 = 1.0.
func bone_matrix(bone: int) -> PackedInt32Array:
	var m := PsxMath.identity()
	if tamer == null:
		return m
	var basis := tamer.bone_basis(bone).orthonormalized()
	var sign := [1, -1, -1]
	for i in 3:
		for j in 3:
			m[i * 3 + j] = roundi(basis[j][i] * sign[i] * sign[j] * 4096.0)
	var p := _psx(tamer.bone_position(bone))
	m[9] = p.x
	m[10] = p.y
	m[11] = p.z
	return m


static func _psx(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x), roundi(-v.y), roundi(-v.z))


func tamer_position() -> Vector3i:
	return _psx(tamer.position) if tamer != null else Vector3i.ZERO


func tamer_yaw() -> int:
	return tamer.direction if tamer != null else 0


func set_tamer_yaw(yaw: int) -> void:
	if tamer != null:
		tamer.set_direction(yaw)


func start_animation(id: int) -> void:
	if tamer != null:
		tamer.start_animation(id)


func animation_playing() -> bool:
	return tamer != null and not tamer.scene_animation_done()


func set_animation_loop_count(_n: int) -> void:
	if tamer != null:
		tamer.finish_scene_loop()


func inventory_types() -> Array:
	var out := []
	var slots: Array = game_state.state["inventory"]["slots"]
	for i in SLOTS:
		var slot = slots[i] if i < slots.size() else null
		out.append(EMPTY if slot == null else data.id_of("items/item_data", slot["item"]))
	return out


func is_food(item: int) -> bool:
	return int(data.item(item).get("sort_category", -1)) == FOOD_SORT


func give_item(item: int, count: int) -> bool:
	return game_state.give_item(item, count)


func remove_item(item: int, count: int) -> void:
	game_state.remove_item(item, count)


func best_rod() -> int:
	if game_state.is_trigger_set(TRIGGER_AMAZING_ROD):
		return 2
	if game_state.is_trigger_set(TRIGGER_OLD_ROD):
		return 1
	return 0


func add_fish_caught() -> void:
	var care: Dictionary = game_state.state["partner"]["care"]
	care["fish_caught"] = int(care.get("fish_caught", 0)) + 1


func play_sound(bank: int, id: int) -> void:
	if sound != null:
		sound.play_sound(bank, id)


func text(id: String) -> String:
	return data.text(id)


func item_name(item: int) -> String:
	return data.localize(data.item(item).get("name", {}))


func bite_chance(bait: int, kind: int) -> int:
	return data.fishing_bite_chance(bait, kind)


func scroll_camera(dx: int, dy: int) -> void:
	if field_map != null:
		field_map.scroll_pixels(Vector2(dx, dy))


func set_camera_follow(on: bool) -> void:
	if tamer != null:
		tamer.camera_follow = on
