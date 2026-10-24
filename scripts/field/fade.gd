class_name Fade
extends ColorRect
## Fade to / from black (fade.c): the counters the ported scenes wait on, and a full-screen black
## rect. A render object in the original, so it steps once per game frame after the tick objects
## (connect tick() to GameLoop.frame after the partner and the clock).
##
## renderFade (fade.c:144) draws a textured quad tinted progress (0..160) in semi-transparency mode
## 2: screen minus quad. A tint of 128 is 1.0 on the PSX, so from progress 128 the whole texel
## (assumed white) is subtracted and the screen is black; the port subtracts grey min(progress /
## 128, 1) the same way.

const FULL := 160
## The tint of a full-strength texel (PSX texture modulation: 128 = 1.0).
const TINT_ONE := 128.0
## Not in the original: game frames the screen stays black after a map change, before the fade in.
## The PSX reads the new map from the CD while black (changeMap blocks the game loop); the port
## loads it in one frame. Also covers the frames that run in bursts after the load's hitch.
const LOAD_FRAMES := 20

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
var _hold := 0


func _ready() -> void:
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	material = blend
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchors and offsets: anchors alone keep the old (zero) size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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


## Keeps the screen fully black for `frames` game frames: a fade from black started meanwhile
## waits (in_current stays 1, so its callers wait too).
func hold(frames: int) -> void:
	_hold = frames
	progress = FULL
	_draw_progress()


## renderFadeOut / renderFadeIn (fade.c:101-142), once per game frame.
func tick() -> void:
	if _hold > 0:
		_hold -= 1
	elif out_current > 0:
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
	var grey := minf(progress / TINT_ONE, 1.0)
	color = Color(grey, grey, grey)
