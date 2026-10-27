class_name BattleThrownItem
extends RefCounted
## The item the tamer throws to the partner in battle (TAMER_ITEM; addThrownItem, tickThrownItem,
## main.c:4222-4280; specs/battle.md §2.18): it rides the tamer's hand (bone 9) until frame 7 of
## his throw (animation 6), then flies to the partner over 24 frames along ITEM_THROW_HEIGHT. On
## the 24th its item function runs (the caller's part).

const HAND_BONE := 9
## The throw's animation and the frame the item leaves the hand.
const THROW_ANIM := 6
const RELEASE_FRAME := 7
## The flight's frames (TAMER_ITEM.time >= 0x18 lands; the divisor is 0x19 - time).
const FLIGHT := 0x18

## The item (a key or an id); null when the hands are free (worldItem.type 0xFF).
var item: Variant = null
## worldItem.spriteLocation (PSX world units, y down).
var location := Vector3i.ZERO
var time := 0
var _heights: Array[int] = []


func _init(data: Node) -> void:
	if data != null:
		for r in data.system("item_throw"):
			_heights.append(int(r["height"]))


func active() -> bool:
	return item != null


## addThrownItem: only while the hands are free.
func start(thrown: Variant, hand: Vector3i) -> void:
	if item != null:
		return
	item = thrown
	location = hand
	time = 0


## tickThrownItem: true on the frame it lands on `target` (the partner's location).
func tick(tamer_anim: int, tamer_frame: int, hand: Vector3i, target: Vector3i) -> bool:
	if item == null:
		return false
	if tamer_anim == THROW_ANIM and tamer_frame < RELEASE_FRAME:
		location = hand
		return false
	var height := _heights[time] if time < _heights.size() else 0
	var step := Vector3i(0, height, 0)
	if time != 0:
		step.x = PsxMath.div(target.x - location.x, 0x19 - time)
		step.z = PsxMath.div(target.z - location.z, 0x19 - time)
	location = Vector3i(location.x + step.x, step.y, location.z + step.z)
	time += 1
	return time >= FLIGHT


## removeTamerItem.
func clear() -> void:
	item = null
	time = 0
