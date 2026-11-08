class_name Pause
extends RefCounted
## The pause (specs/pause.md): handlePause (utils2.c:402), createPauseBox / removePauseBox
## (utils2.c:443, :434). Logic only: the host reads the pad, draws the box, plays the sound and
## freezes the game while `is_paused()`.

## createPauseBox (US): static UI box 5, colour 1, no features, at (-0x1A, -0xE, 0x38, 0x18).
const BOX_ID := 5
const BOX_COLOR := 1
const BOX_RECT := Rect2i(-0x1A, -0xE, 0x38, 0x18)
## drawString(MAIN_D_80134430, 0x78, 0xF0); renderPauseBox's renderString (US): 0x2A x 0xC at the
## box's (6, 6), colour 0, layer 0, shadowed.
const TEXT_ID := "MAIN_D_80134430"
const TEXT_U := 0x78
const TEXT_V := 0xF0
const TEXT_W := 0x2A
const TEXT_H := 0xC
const TEXT_OFFSET := 6
## renderPauseBox: the screen (-0xA0, -0x78, 0x140, 0xF0) in black, half transparent (attribute
## 0x40000000: semi-transparency rate 0, half the screen plus half black), behind the box.
const DIM_RECT := Rect2i(-0xA0, -0x78, 0x140, 0xF0)
## playSound(0, 3) when the box opens and when it closes.
const SOUND_BANK := 0
const SOUND_ID := 3
## readPStat(0) == 3: a script has taken over the field (scriptPauseGame).
const PSTAT_SCRIPT := 0
const SCRIPT_TAKEN_OVER := 3

## The box was created / removed (createPauseBox / removePauseBox did their work, sound included).
signal box_created
signal box_removed

## PAUSE_STATE: 1 while paused.
var state := 0
## PAUSE_BOX_VISIBLE: counts the frames that opened the box; the next handle removes it.
var box_visible := 0
## PAUSE_INPUT_PREVIOUS: the last PadRead(1) the pause looked at.
var input_previous := 0
## MAIN_D_80134E7C: the box exists.
var box_shown := false


## handlePause's early returns (utils2.c:408-413): in the field (GAME_STATE 0) not while a script
## has taken over or game time is stopped; nowhere during a fade to black (FADE_PROTECTION).
static func is_blocked(in_field: bool, script_value: int, game_time_running: bool, fade_protection: bool) -> bool:
	if in_field and (script_value == SCRIPT_TAKEN_OVER or not game_time_running):
		return true
	return fade_protection


## handlePause up to its wait loop, with `input` the pad read now (PadRead(1)). Returns true when
## the game must stop: the wait loop runs until `poll` sees START again.
func handle(input: int, blocked: bool) -> bool:
	if box_visible != 0:
		remove_box()
		box_visible = 0
	if blocked:
		return false
	_read(input)
	if state != 0:
		create_box()
		box_visible += 1
	return state != 0


## One read of handlePause's wait loop (utils2.c:425-431). Returns true while still paused.
func poll(input: int) -> bool:
	_read(input)
	return state != 0


func is_paused() -> bool:
	return state != 0


## removePauseBox (utils2.c:434): also called after the battle and match loops.
func remove_box() -> void:
	if box_shown:
		box_shown = false
		box_removed.emit()


## createPauseBox (utils2.c:443).
func create_box() -> void:
	if not box_shown:
		box_shown = true
		box_created.emit()


## START newly down (0x800) toggles the state.
func _read(input: int) -> void:
	if input & Pad.START and not input_previous & Pad.START:
		state = (state + 1) & 1
	input_previous = input
