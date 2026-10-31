class_name ScriptContext
extends RefCounted
## The event-script interpreter's state (script_interp.c globals; specs/script.md, specs/text.md
## §2.7): what ScriptInterpreter runs on and what the text boxes read and change.

## SCRIPT_OP_* (include/dw/script.h).
const OP_SET_SELECTION := 0x10
const OP_SHOW_TEXTBOX := 0x1A
const OP_SET_DIALOG_OWNER := 0x1B
const OP_SET_TEXTBOX_SIZE := 0x26
const OP_CALL_ROUTINE := 0x64
const OP_DELAY := 0x67
const OP_SET_TEXTBOX_MODE := 0x68
## ACTIVE_INSTRUCTION when the script has ended (tickTextboxHandling's other branch).
const INSTRUCTION_ENDED := 0xFF
## Speaker / owner ids (getSpeakerName, scriptIdToEntityId).
const OWNER_NONE := 0xFF
const OWNER_TAMER := 0xFD
const OWNER_PARTNER := 0xFC
const OWNER_SPECIAL := 0xC8
## setTrigger(0x31): cancel can't leave a choice.
const TRIGGER_NO_CANCEL := 0x31

## ACTIVE_SCRIPT: the script's bytes (`code`, script `code_id`); SCRIPT_POINTER: an offset into them.
var code := PackedByteArray()
var code_id := 0
var pointer := 0
## ACTIVE_INSTRUCTION: the opcode waiting for something (0 = the script runs on).
var active_instruction := 0
## SCRIPT_TEXTBOX_MODE: what a builtin routine (CALL_ROUTINE) waits for: 1 confirm, 2 choice, 3 page shown.
var textbox_mode := 0
## SCRIPT_STATE_2 / SCRIPT_NEXT_STATE_2: the builtin routine's step.
var state_2 := 0
var next_state_2 := 0
## CURRENT_DIALOGUE_OWNER (callScriptSection starts it at the tamer).
var dialogue_owner := OWNER_TAMER
## MAIN_D_80135000: 2 = SHOW_TEXTBOX without the speaker line.
var text_owner_mode := 0
## TEXTBOX_CLOSE_MODE (SET_TEXTBOX_MODE): 0 confirm, 1 at once, 2 after AUTOCLOSE_FRAMES.
var textbox_close_mode := 0
## IS_SCRIPT_PAUSED.
var is_paused := false
## SHOP_VARIABLE (text code 0x10).
var shop_variable := 0

# The interpreter's own globals (script_interp.c; specs/script.md §2).
## ACTIVE_MAP_SCRIPT: the script `code` holds; CURRENT_SCRIPT_ID: the current map's DG script;
## CURRENT_SCREEN_ID: the map SET_SCRIPT set (0xFFFF until then).
var active_script_id := 0xFFFF
var current_script_id := 0xFFFF
var current_screen_id := 0
## SCRIPT_SECTION / SCRIPT_SECTION_IS_EVENT (an NPC talk or a map entry).
var section := 0
var section_is_event := 0
## MAIN_D_80134FE7: script value 0 saved by callScriptSection, restored when the script ends.
var saved_pstat0 := 0
## MAIN_D_80134FE9: 0x4B while a script's map change runs.
var map_change := 0
## MAIN_D_80134FF0: the script has taken over the field (scriptPauseGame).
var took_over := 0
## MAIN_D_80134FEC: SET_SCRIPT's map setup is pending.
var map_setup_pending := 0
## SOME_SCRIPT_SYNC_BIT.
var sync_bit := 1
## SCRIPT_PARAM_1 (the builtin routine, the map to change to), WAIT_FOR_ENTITY_ID.
var script_param_1 := 0
var wait_for_entity_id := 0
## MAIN_D_80134F9C: TALKED_TO_ENTITY when the section started (the battle's opponent).
var talked_to_entity := 0
## SCRIPT_STATE.stack[8] / SCRIPT_STACK_OFFSET: {pointer, script, type, arg}.
var stack: Array = []
## TEXTBOX_ORIGIN_X/Y/Z (SET_TEXTBOX_ORIGIN): the next box's origin as a world point, or null.
var textbox_origin = null

var game_state: Node
var data: Node
## getSpeakerName / scriptIdToEntityId: the Digimon type of the entity with a script id (-1 = none).
var entity_type := Callable()
## setupBoxOrigin: the screen position (Vector2i, relative to the centre) of the entity with a
## script id, or null when there is none.
var entity_screen_position := Callable()
## scriptPauseGame(owner).
var pause_game := Callable()
## worldPosToScreenPos2: a PSX world point [x, y, z] on screen (Vector2i relative to the centre) or null.
var world_screen_position := Callable()


## pollNextScriptUByte.
func next_byte() -> int:
	var b := byte_at(pointer)
	pointer += 1
	return b


func byte_at(offset: int) -> int:
	return code[offset] if offset >= 0 and offset < code.size() else 0


func u16_at(offset: int) -> int:
	return byte_at(offset) | (byte_at(offset + 1) << 8)


## readPStat.
func read_pstat(index: int) -> int:
	return game_state.script_value(index) if game_state != null else 0


## writePStat.
func write_pstat(index: int, value: int) -> void:
	if game_state != null:
		game_state.set_script_value(index, value)


func is_trigger_set(trigger: int) -> bool:
	return game_state != null and game_state.is_trigger_set(trigger)


func type_of(script_id: int) -> int:
	if script_id == OWNER_TAMER:
		return 0
	return int(entity_type.call(script_id)) if entity_type.is_valid() else -1
