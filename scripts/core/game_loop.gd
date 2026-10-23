extends Node
## The original's game frame: gameLoop runs once per VSync(3), 20 frames per second on NTSC
## (main.c:3958). Autoload "GameLoop": emits `frame` once per game frame, so ported tick
## functions (clock, partner, care) run at the original rate whatever Godot's frame rate is.

signal frame

const FRAME_RATE := 20.0
## Game frames run at most per Godot frame: after a stall the game slows down instead of
## running many frames at once.
const MAX_FRAMES_PER_STEP := 3

var paused := false
## Game frames run since start.
var frame_count := 0

var _accumulated := 0.0


func _process(delta: float) -> void:
	if paused or Engine.is_editor_hint():
		return
	_accumulated = minf(_accumulated + delta, MAX_FRAMES_PER_STEP / FRAME_RATE)
	while _accumulated >= 1.0 / FRAME_RATE:
		_accumulated -= 1.0 / FRAME_RATE
		frame_count += 1
		frame.emit()
