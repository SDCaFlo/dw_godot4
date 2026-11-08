class_name Pad
extends RefCounted
## The pad as the original reads it once per game frame (specs/text.md §2.8): pollInputGame
## (main.c:4035) and processInput / isKeyDown (script_common.c:1261). GameLoop owns one and polls
## it at the start of every game frame, from the Godot input actions.
##
## Each PSX button is its own input action (`pad_cross`, `pad_up`, …), with keyboard and joypad
## events added by `add_actions` unless the project's input map already defines it. The d-pad and
## the left stick are digital directions like the PSX pad: a direction is held or not, whatever the
## stick's tilt.

## PadRead bits (US buttons: ✕ confirms, △ cancels; dw/input.h).
const L2 := 0x1
const R2 := 0x2
const L1 := 0x4
const R1 := 0x8
const TRIANGLE := 0x10
const CIRCLE := 0x20
const CROSS := 0x40
const SQUARE := 0x80
const SELECT := 0x100
const START := 0x800
const CONFIRM := CROSS
const CANCEL := TRIANGLE
const ALT := CIRCLE
const UP := 0x1000
const RIGHT := 0x2000
const DOWN := 0x4000
const LEFT := 0x8000
const DIRECTIONS := 0xF000
## pollInputGame repeats these (the d-pad of both pads).
const GAME_REPEAT := 0xF000F000
## Godot input action -> bit.
const ACTIONS := {"pad_cross": CROSS, "pad_circle": CIRCLE, "pad_square": SQUARE, "pad_triangle": TRIANGLE,
		"pad_l1": L1, "pad_r1": R1, "pad_l2": L2, "pad_r2": R2, "pad_select": SELECT, "pad_start": START,
		"pad_up": UP, "pad_right": RIGHT, "pad_down": DOWN, "pad_left": LEFT}
## Default events per action: keys (KEY_*), joypad buttons (JOY_BUTTON_*), joypad axes
## ([JOY_AXIS_*, direction]). Not part of the original. Shift runs (R1) as before.
const DEFAULT_EVENTS := {
	"pad_cross": {"keys": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], "buttons": [JOY_BUTTON_A]},
	"pad_circle": {"keys": [KEY_BACKSPACE], "buttons": [JOY_BUTTON_B]},
	"pad_square": {"keys": [], "buttons": [JOY_BUTTON_X]},
	"pad_triangle": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_Y]},
	"pad_l1": {"keys": [], "buttons": [JOY_BUTTON_LEFT_SHOULDER]},
	"pad_r1": {"keys": [KEY_SHIFT], "buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
	"pad_l2": {"keys": [], "axes": [[JOY_AXIS_TRIGGER_LEFT, 1.0]]},
	"pad_r2": {"keys": [], "axes": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]},
	"pad_select": {"keys": [], "buttons": [JOY_BUTTON_BACK]},
	"pad_start": {"keys": [KEY_P], "buttons": [JOY_BUTTON_START]},
	"pad_up": {"keys": [KEY_UP], "buttons": [JOY_BUTTON_DPAD_UP], "axes": [[JOY_AXIS_LEFT_Y, -1.0]]},
	"pad_down": {"keys": [KEY_DOWN], "buttons": [JOY_BUTTON_DPAD_DOWN], "axes": [[JOY_AXIS_LEFT_Y, 1.0]]},
	"pad_left": {"keys": [KEY_LEFT], "buttons": [JOY_BUTTON_DPAD_LEFT], "axes": [[JOY_AXIS_LEFT_X, -1.0]]},
	"pad_right": {"keys": [KEY_RIGHT], "buttons": [JOY_BUTTON_DPAD_RIGHT], "axes": [[JOY_AXIS_LEFT_X, 1.0]]},
}

## POLLED_INPUT: held this frame; POLLED_INPUT_PREVIOUS: last frame.
var polled := 0
var polled_previous := 0
## CHANGED_INPUT: newly pressed this frame, plus the d-pad repeat.
var changed := 0
var game_repeat_timer := 0
## processInput's state (INPUT_PENDING_MASK, INPUT_FRESH_MASK, INPUT_REPEAT_MASK, INPUT_REPEAT_COUNTER).
var pending := 0
var fresh := -1
var repeat_mask := 0
var repeat_counter := 0


## Adds the pad actions missing from the input map, with their default events.
static func add_actions() -> void:
	for action in DEFAULT_EVENTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		var events: Dictionary = DEFAULT_EVENTS[action]
		for key in events.get("keys", []):
			var event := InputEventKey.new()
			event.keycode = key
			InputMap.action_add_event(action, event)
		for button in events.get("buttons", []):
			var event := InputEventJoypadButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
		for axis in events.get("axes", []):
			var event := InputEventJoypadMotion.new()
			event.axis = axis[0]
			event.axis_value = axis[1]
			InputMap.action_add_event(action, event)


## pollInputGame (main.c:4035) with `down` = the buttons held now.
func poll(down: int) -> void:
	polled_previous = polled
	polled = down
	changed = polled & ~polled_previous
	var held := polled & polled_previous & GAME_REPEAT
	if held != 0:
		game_repeat_timer += 1
		if game_repeat_timer >= 5:
			game_repeat_timer -= 2
		else:
			held = 0
	else:
		game_repeat_timer = 0
	changed |= held


## processInput (script_common.c:1261).
func process() -> void:
	fresh |= ~polled
	var held := polled & repeat_mask
	if held == 0:
		repeat_counter = 0
	if repeat_mask != 0:
		var previous := polled_previous & repeat_mask
		if held == previous:
			if repeat_counter == 8:
				repeat_counter = 6
			elif repeat_counter != 6:
				held = 0
			repeat_counter += 1
		else:
			repeat_counter = 0
			fresh |= repeat_mask
			held = 0
	pending = held | (polled & fresh)


## isKeyDown (script_common.c:1294): true once per press (and per repeat); takes the key.
func is_key_down(key: int) -> bool:
	if pending & key == 0:
		return false
	fresh &= ~key
	return true


## setInputRepeatMask (script_common.c:1322).
func set_repeat_mask(mask: int) -> void:
	repeat_mask = mask


func is_held(key: int) -> bool:
	return polled & key != 0


func is_changed(key: int) -> bool:
	return changed & key != 0
