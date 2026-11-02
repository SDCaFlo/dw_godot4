class_name MoodBubble
extends RefCounted
## Monochromon shop mood bubble logic (specs/map_events.md §3.2 S9-S11, §4.2.1):
## manages bubble instances, timer, texture coordinate, scale and vertical offset
## (createMonochromonMoodBubble, renderMonochromonMoodBubble; script_common.c:271-290, 1220-1250, 3038-3054).

## script_common.c:275, 276 (32x32)
const SIZE := 32
## script_common.c:285, 286 (mx, my = 16)
const PIVOT := Vector2i(16, 16)
## script_common.c:277 (getTPage(0, 0, 640, 0))
const TPAGE := Vector2i(640, 0)
## script_common.c:280, 281 (GetClut(0, 486))
const CLUT := Vector2i(0, 486)
## script_common.c:282-284 (r, g, b = 0x80)
const COLOR := 0x80

## script_common.c:3048 (MONOCHROMON_BUBBLE_TIMER = 0x1e)
const START_TIMER := 0x1E
## script_common.c:3046 ((uint32_t)b < 5)
const MOOD_MAX := 5
## script_common.c:3049 (u = b * 32)
const U_STEP := 32

## port-only: active bubble render objects count (script_common.c:3050 addObject / 3053 removeObject)
var instances: int = 0
## script_common.c:3048 (MONOCHROMON_BUBBLE_TIMER)
var timer: int = 0
## script_common.c:3049 (MONOCHROMON_BUBBLE_SPRITE.u)
var u: int = 0


## createMonochromonMoodBubble (script_common.c:3038).
func create(entity_on_map: bool, mood: int) -> void:
	var m := mood & 0xFF
	if m < MOOD_MAX:
		if entity_on_map:
			timer = START_TIMER
			u = m * U_STEP
			instances += 1
	else:
		instances = maxi(instances - 1, 0)


## renderMonochromonMoodBubble (script_common.c:1220).
func render(entity_on_map: bool) -> Array:
	if not entity_on_map or instances <= 0:
		return []
	var frames: Array = []
	for i in instances:
		var offset := 0x10 - (timer >> 1)
		var scale := PsxMath.s16(offset << 8)
		frames.append({"offset": offset, "scale": scale})
		if timer != 0:
			timer -= 1
	return frames


## Clears active bubble instances on map change (step 4).
func clear() -> void:
	instances = 0
