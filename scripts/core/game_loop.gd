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
## The pad as the original reads it (Pad: POLLED_INPUT, CHANGED_INPUT, isKeyDown), polled at the
## start of every game frame.
var pad := Pad.new()
## Debug: game frames run per original frame (1 = the original's pace). Every system ticks on
## `frame`, so timers keep their exact frame counts, only sooner. Not part of the original.
var speed := 1
## Game frames run since start.
var frame_count := 0

var _accumulated := 0.0
## Buttons pressed since the last game frame (a tap shorter than a frame still counts once).
var _tapped := 0


func _ready() -> void:
	Pad.add_actions()


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
			# The pause froze the game (handlePause's wait loop, specs/pause.md): no more frames.
			if is_inside_tree() and get_tree().paused:
				_accumulated = 0.0
				return


func _input(event: InputEvent) -> void:
	for action in Pad.ACTIONS:
		if event.is_action_pressed(action, false):
			_tapped |= Pad.ACTIONS[action]


## Debug tools: the button is held for the next game frame.
func press(action: String) -> void:
	_tapped |= Pad.ACTIONS.get(action, 0)


## gameLoop's pollInputGame + processInput (main.c:3935-3940): the buttons held now, plus taps
## since the last game frame.
func _poll() -> void:
	var down := _tapped
	_tapped = 0
	for action in Pad.ACTIONS:
		if Input.is_action_pressed(action):
			down |= Pad.ACTIONS[action]
	pad.poll(down)
	pad.process()
