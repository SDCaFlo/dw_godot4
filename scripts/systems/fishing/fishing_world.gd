class_name FishingWorld
extends RefCounted
## What the rod's logic (FishingRod, specs/fishing.md §5.1) asks of the rest of the game: the
## tamer, the inventory, the sounds, the texts and the camera. The field implements it (step F4);
## the tests use a fake. All positions are PSX world units (Vector3i), angles 12-bit.


## The bone's world matrix (posData[bone].posMatrix after calculatePosition, FISH_getBoneTransform
## fish.c:4541), in PsxMath's layout: rotation at 4096 = 1.0, translation in world units.
func bone_matrix(_bone: int) -> PackedInt32Array:
	return PsxMath.identity()


## TAMER_ENTITY.posData->location.
func tamer_position() -> Vector3i:
	return Vector3i.ZERO


## TAMER_ENTITY.posData->rotation.vy.
func tamer_yaw() -> int:
	return 0


func set_tamer_yaw(_yaw: int) -> void:
	pass


## startAnimation(&TAMER_ENTITY.entity, id).
func start_animation(_id: int) -> void:
	pass


## TAMER_ENTITY.entity.anim.animFlag & 1: the animation is still running.
func animation_playing() -> bool:
	return false


## TAMER_ENTITY.entity.anim.loopCount = n (the splash, fish.c:3958).
func set_animation_loop_count(_n: int) -> void:
	pass


## INVENTORY.types.array[30]: the item type in each slot, 0xFF empty.
func inventory_types() -> Array:
	return []


## ITEM_PARA[item].sortingValue == 2.
func is_food(_item: int) -> bool:
	return false


## giveItem(item, 1): false when the bag is full.
func give_item(_item: int, _count: int) -> bool:
	return true


## removeItem(item, 1).
func remove_item(_item: int, _count: int) -> void:
	pass


## getBestFishingRod (main/fish.c:19): 2 amazing rod, 1 old rod, 0 none.
func best_rod() -> int:
	return 0


## PARTNER_PARA.fishCaught++.
func add_fish_caught() -> void:
	pass


## playSound(bank, id).
func play_sound(_bank: int, _id: int) -> void:
	pass


## A string by its C id (GameData.text).
func text(_id: String) -> String:
	return ""


## ITEM_NAME(item).
func item_name(_item: int) -> String:
	return ""


## FISH_findFishToBite's chance for a bait and a kind (GameData.fishing_bite_chance).
func bite_chance(_bait: int, _kind: int) -> int:
	return 0


## FISH_scrollCameraTo's MAP_TILE_DATA.cameraX / Y += (dx, dy) (the background scrolls; the drawing
## offset moves the other way, which FishingCamera.offset follows).
func scroll_camera(_dx: int, _dy: int) -> void:
	pass


## setCameraFollowPlayer / unsetCameraFollowPlayer.
func set_camera_follow(_on: bool) -> void:
	pass
