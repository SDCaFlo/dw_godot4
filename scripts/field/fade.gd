class_name Fade
extends ColorRect
## Fade to / from black (fade.c): the counters the ported scenes wait on, and a full-screen black
## rect. A render object in the original, so it steps once per game frame after the tick objects
## (connect tick() to GameLoop.frame after the partner and the clock).
##
## The original subtracts `progress` (0..160) from every colour (semi-transparency mode 2); the
## port darkens with black at alpha progress / 160, close but not the same curve.

const FULL := 160

var clock: Clock
## FADE_OUT_CURRENT: frames into a fade to black (1 = started), 0 when none.
var out_current := 0
## FADE_IN_CURRENT: frames into a fade from black, 0 when none or done.
var in_current := 0
## FADE_PROGRESS: darkness 0..160.
var progress := 0
## FADE_PROTECTION: set by fade_to_black until a fade from black ends (stops the care tick, warps).
var protection := false

var _out_frames := 0
var _in_target := 0


func _ready() -> void:
	color = Color.BLACK
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_progress()


## fadeToBlack (fade.c:73): stops game time as well.
func fade_to_black(frames: int) -> void:
	_out_frames = frames + 1
	out_current = 1
	in_current = 0
	if clock != null:
		clock.running = false
	protection = true


## fadeFromBlack (fade.c:87).
func fade_from_black(frames: int) -> void:
	out_current = 0
	_in_target = frames + 1
	in_current = 1


## renderFadeOut / renderFadeIn (fade.c:101-142), once per game frame.
func tick() -> void:
	if out_current > 0:
		progress = mini(progress + FULL / _out_frames, FULL)
		out_current += 1
	elif in_current > 0:
		if in_current < _in_target:
			var step := in_current * (FULL / _in_target)
			if step < 1:
				step = in_current
			progress = maxi(FULL - step, 0)
			in_current += 1
		else:
			in_current = 0
			progress = 0
			protection = false
	_draw_progress()


func _draw_progress() -> void:
	visible = progress > 0
	color.a = float(progress) / FULL
