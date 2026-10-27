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

## gameClearSave: MAIN_STATE = 2, saves to File City.
func _start_game_clear() -> bool:
	game_state.state["boot_mode"] = 2  # BOOT_GAME_CLEARED
	# Set the save location to File City top map.
	var file_city_map: String = str(data.key_of("systems/maps", 0xCC))
	game_state.state["world"]["screen"] = file_city_map
	_open_slot_box(SaveSlotBox.MODE_SAVE)
	return true  # Waits.


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
