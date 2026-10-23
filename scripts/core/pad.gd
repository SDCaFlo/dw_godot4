class_name Pad
extends RefCounted
## The pad as the original reads it once per game frame (specs/text.md §2.8): pollInputGame
## (main.c:4035) and processInput / isKeyDown (script_common.c:1261). GameLoop owns one and polls
## it at the start of every game frame, from the Godot input actions.

## PadRead bits (US buttons: ✕ confirms, △ cancels; dw/input.h).
const CONFIRM := 0x40
const CANCEL := 0x10
const ALT := 0x20
const UP := 0x1000
const RIGHT := 0x2000
const DOWN := 0x4000
const LEFT := 0x8000
## pollInputGame repeats these (the d-pad of both pads).
const GAME_REPEAT := 0xF000F000
## Godot input action -> bit.
const ACTIONS := {"ui_accept": CONFIRM, "ui_cancel": CANCEL, "ui_up": UP, "ui_right": RIGHT, "ui_down": DOWN,
		"ui_left": LEFT}

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
