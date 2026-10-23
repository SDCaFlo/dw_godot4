class_name ScriptContext
extends RefCounted
## The event-script interpreter's state that the text boxes read and change (script_interp.c
## globals; specs/text.md §2.7). The interpreter (next milestone step) runs on it; until then the
## dialogue debug player (scripts/debug/dialogue_debug.gd) does, for the text instructions only.

## SCRIPT_OP_* (include/dw/script.h).
const OP_SET_SELECTION := 0x10
const OP_SHOW_TEXTBOX := 0x1A
const OP_SET_DIALOG_OWNER := 0x1B
const OP_SET_TEXTBOX_SIZE := 0x26
const OP_CALL_ROUTINE := 0x64
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

## ACTIVE_SCRIPT: the script's bytes (`code`); SCRIPT_POINTER: an offset into them.
var code := PackedByteArray()
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

var game_state: Node
var data: Node
## getSpeakerName / scriptIdToEntityId: the Digimon type of the entity with a script id (-1 = none).
var entity_type := Callable()
## setupBoxOrigin: the screen position (Vector2i, relative to the centre) of the entity with a
## script id, or null when there is none.
var entity_screen_position := Callable()
## scriptPauseGame(owner).
var pause_game := Callable()


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


func is_trigger_set(trigger: int) -> bool:
	return game_state != null and game_state.is_trigger_set(trigger)


func type_of(script_id: int) -> int:
	if script_id == OWNER_TAMER:
		return 0
	return int(entity_type.call(script_id)) if entity_type.is_valid() else -1
