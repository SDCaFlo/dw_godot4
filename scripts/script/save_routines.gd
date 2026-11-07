class_name SaveRoutines
extends Node
## Builtins 0x30 (save machine) and 0x36 (game-clear save): specs/save.md §2.3 B & D.
## A routine node under ScriptRoutines (specs/shops.md §3): starts and ticks the save machine
## or the game-clear save through the shared SaveSlotBox.

const SaveSlotBox := preload("res://scripts/ui/save_slot_box.gd")

## The builtins this node handles.
var routines := [0x30, 0x36]

var host: ScriptRoutines
var ctx: ScriptContext
var game_state: Node
var data: Node

var _slot_box: SaveSlotBox
var _waiting := false


func configure(routine_host: ScriptRoutines) -> void:
	host = routine_host
	ctx = host.ctx
	game_state = host.game_state
	data = host.data


## openSaveMachine (main_menu.c:5273) / gameClearSave (main_menu.c:5318).
func start(routine: int) -> bool:
	match routine:
		0x30:
			return _start_save_machine()
		0x36:
			return _start_game_clear()
	return false


## tickSaveMachine (main_menu.c:5288): returns true while the menu is open.
func tick(_routine: int) -> void:
	if not _waiting:
		ctx.active_instruction = 0


# --- Save machine (builtin 0x30) ---------------------------------------------------------------

## openSaveMachine: MAIN_STATE = 1, TARGET_MENU depends on partner level and memory card.
## In the port: opens the slot box in Save mode.
func _start_save_machine() -> bool:
	game_state.state["boot_mode"] = 1  # BOOT_CONTINUE
	_open_slot_box(SaveSlotBox.MODE_SAVE)
	return true  # Waits.


# --- Game-clear save (builtin 0x36) -------------------------------------------------------------

## gameClearSave (main_menu.c:5318): MAIN_STATE = 2, CURRENT_SCREEN = getFileCityTopMap(), saves.
func _start_game_clear() -> bool:
	game_state.state["boot_mode"] = 2  # BOOT_GAME_CLEARED
	game_state.state["world"]["screen"] = str(data.key_of("systems/maps", file_city_top_map(game_state)))
	_open_slot_box(SaveSlotBox.MODE_SAVE)
	return true  # Waits.


## getFileCityTopMap (map.c:5592-5639): File City's top map as the town has grown, TWNA02-TWNA13
## (0xA8-0xB3), from five recruitment triggers. dw1's own rule (literal triggers and maps, like the
## C); TWNA01 (0xCC) is the empty town of a new game only (main.c:3455).
static func file_city_top_map(state: Node) -> int:
	var a: bool = state.is_trigger_set(0xDC) and state.is_trigger_set(0xD6)
	var b: bool = state.is_trigger_set(0xDD)
	var e1: bool = state.is_trigger_set(0xE1)
	var f6: bool = state.is_trigger_set(0xF6)
	var base := 0xA8
	if a and b:
		base = 0xB1
	elif a:
		base = 0xAE
	elif b:
		base = 0xAB
	# The last two tests of each branch: 0xE1 first, then 0xF6, else the branch's own map.
	if e1:
		return base + 2
	if f6:
		return base + 1
	return base


func _open_slot_box(mode: int) -> void:
	_waiting = true
	_slot_box = SaveSlotBox.new()
	_slot_box.boxes = host.textboxes.boxes
	_slot_box.text_area = host.textboxes.text_area
	_slot_box.game_state = game_state
	_slot_box.data = data
	_slot_box.pad = host.textboxes.pad
	_slot_box.mode = mode
	_slot_box.finished.connect(_on_slot_finished)
	_slot_box.open()


func _on_slot_finished() -> void:
	_waiting = false
