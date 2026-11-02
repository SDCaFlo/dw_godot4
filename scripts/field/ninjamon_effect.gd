class_name NinjamonEffect
extends RefCounted
## Ninjamon's overlay streak effect logic (specs/map_events.md §3.2 S8, §4.2.1):
## drives 0x29 map overlay sprites over 0x3C frames (createNinjamonEffect, renderNinjamonEffect; overworld.c:777-830).

## overworld.c:782, 783 (0x29 overlay objects)
const COUNT := 0x29
## overworld.c:816 (data->orderValue = 10)
const ORDER := 10
## overworld.c:820 (NINJAMON_FX_COUNTER >= 0x3c)
const TOTAL_FRAMES := 0x3C
## overworld.c:810 (data->x > 0xa0)
const WRAP_X := 0xA0
## overworld.c:784, 785 (randomLimit(10))
const RANDOM_LIMIT := 10
## overworld.c:784 (+ 12)
const OFFSET_X_BASE := 12
## overworld.c:785 (+ 3)
const OFFSET_Y_BASE := 3

## overworld.c:796-797 (LocalMapObjectInstance x, y)
var positions: Array = []
## overworld.c:781 (NINJAMON_FX_COUNTER)
var frame: int = 0
## port-only: tracks completion when frame reaches TOTAL_FRAMES (overworld.c:820)
var done: bool = false

var _saved: Array = []
var _dx: Array[int] = []
var _dy: Array[int] = []


## createNinjamonEffect (overworld.c:777).
func start(saved: Array) -> void:
	_saved = saved.duplicate()
	positions = saved.duplicate()
	frame = 0
	done = false
	_dx.resize(COUNT)
	_dy.resize(COUNT)
	for i in COUNT:
		_dx[i] = Rng.random_limit(RANDOM_LIMIT) + OFFSET_X_BASE
		_dy[i] = Rng.random_limit(RANDOM_LIMIT) + OFFSET_Y_BASE


## renderNinjamonEffect (overworld.c:801).
func tick() -> bool:
	if done:
		return true
	for i in COUNT:
		var p: Vector2i = positions[i]
		var nx := PsxMath.s16(p.x + _dx[i])
		var ny := PsxMath.s16(p.y + _dy[i])
		if nx > WRAP_X:
			var orig: Vector2i = _saved[i]
			positions[i] = orig
			_dx[i] = Rng.random_limit(RANDOM_LIMIT) + OFFSET_X_BASE
			_dy[i] = Rng.random_limit(RANDOM_LIMIT) + OFFSET_Y_BASE
		else:
			positions[i] = Vector2i(nx, ny)
	frame += 1
	if frame >= TOTAL_FRAMES:
		done = true
	return done
