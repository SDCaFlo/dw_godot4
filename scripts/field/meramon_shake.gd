class_name MeramonShake
extends RefCounted
## Meramon's screen shake logic (specs/map_events.md §3.2 S5-S7, §4.2.1):
## ticks horizontal shake offset steps over 210 frames (createMeramonShake, tickMeramonShake; map.c:5472-5541).

## map.c:5537 (0xd2 frames = 210 frames)
const TOTAL_FRAMES := 0xD2

## map.c:5488, 5490, 5492, 5494 (amplitude thresholds)
const THRESHOLD_1 := 0x1F
const THRESHOLD_2 := 0x3D
const THRESHOLD_3 := 0x79
const THRESHOLD_4 := 0xB5

## map.c:5474 (MERAMON_SHAKE_FRAME_COUNT)
var frame: int = 0
## map.c:5475, 5476 (MERAMON_SHAKE_DATA, MERAMON_SHAKE_BACKUP_OFFSET_Y)
var saved_offset: Vector2i = Vector2i.ZERO
## port-only: tracks completion when frame reaches TOTAL_FRAMES (map.c:5537)
var done: bool = false


## createMeramonShake (map.c:5472).
func start(offset: Vector2i) -> void:
	frame = 0
	saved_offset = offset
	done = false


## tickMeramonShake (map.c:5482).
func tick() -> int:
	if done:
		return 0
	var amp := 1
	if frame < THRESHOLD_1:
		amp = 1
	elif frame < THRESHOLD_2:
		amp = 2
	elif frame < THRESHOLD_3:
		amp = 3
	elif frame < THRESHOLD_4:
		amp = 2
	else:
		amp = 1
	var step := -amp if (frame % 2 == 0) else amp
	frame += 1
	if frame >= TOTAL_FRAMES:
		done = true
	return step
