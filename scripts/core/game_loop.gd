extends Node
## The original's game frame: gameLoop runs once per VSync(3), 20 frames per second on NTSC
## (main.c:3958). Autoload "GameLoop": emits `frame` once per game frame, so ported tick
## functions (clock, partner, care) run at the original rate whatever Godot's frame rate is.

signal frame

const FRAME_RATE := 20.0
## Game frames run at most per Godot frame: after a stall the game slows down instead of
## running many frames at once.
const MAX_FRAMES_PER_STEP := 3
## The pad buttons the ported code polls: confirm (✕), cancel (△), the d-pad.
const PAD_ACTIONS: PackedStringArray = ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right"]

var paused := false
## Debug: game frames run per original frame (1 = the original's pace). Every system ticks on
## `frame`, so timers keep their exact frame counts, only sooner. Not part of the original.
var speed := 1
## Game frames run since start.
var frame_count := 0

var _accumulated := 0.0
## Buttons pressed since the last game frame, and the ones the current frame sees.
var _pending := {}
var _polled := {}


func _process(delta: float) -> void:
	if paused or Engine.is_editor_hint():
		return
	_accumulated = minf(_accumulated + delta, MAX_FRAMES_PER_STEP / FRAME_RATE)
	while _accumulated >= 1.0 / FRAME_RATE:
		_accumulated -= 1.0 / FRAME_RATE
		for i in speed:
			_poll()
			frame_count += 1
			frame.emit()


func _input(event: InputEvent) -> void:
	for action in PAD_ACTIONS:
		if event.is_action_pressed(action, false):
			_pending[action] = true


## POLLED_INPUT: true in the one game frame after the button went down (a press between two game
## frames is seen by the next one).
func pad_pressed(action: String) -> bool:
	return _polled.has(action)


## Tests and debug tools: a button press the next game frame sees.
func press(action: String) -> void:
	_pending[action] = true


## The start of a game frame: the presses since the last one become this frame's POLLED_INPUT.
func _poll() -> void:
	_polled = _pending
	_pending = {}
