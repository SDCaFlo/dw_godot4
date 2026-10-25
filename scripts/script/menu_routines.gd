class_name MenuRoutines
extends Node
## The base of the routine nodes that run a dialogue with the script item menu (ShopRoutines,
## CardShopRoutines, MeritShopRoutines, MojyamonRoutines; specs/shops.md §3, specs/card_shops.md
## §3): the script state, the shared ItemMenu, and the steps' common moves (SCRIPT_STATE_2,
## SCRIPT_NEXT_STATE_2, SCRIPT_TEXTBOX_MODE).

## setInputRepeatMask(0x5000): ↑ ↓ repeat in the lists.
const LIST_REPEAT := Pad.UP | Pad.DOWN

var host: ScriptRoutines
var ctx: ScriptContext
var textboxes: TextBoxes
var game_state: Node
var data: Node
var menu: ItemMenu


func configure(routine_host: ScriptRoutines) -> void:
	host = routine_host
	ctx = host.ctx
	textboxes = host.textboxes
	game_state = host.game_state
	data = host.data
	menu = host.menu


## readPStat(PSTAT_254): the NPC running the routine.
func _owner() -> int:
	return ctx.read_pstat(0xFE)


## showMapHeadTextbox in the dialogue box.
func _line(index: int, owner: int, section := TextBoxes.SECTION_SHOPKEEPER) -> void:
	textboxes.show_maphead_textbox(index, owner, 0, section)


## Waits for ✕ on the line shown, then step `next` (SCRIPT_TEXTBOX_MODE 1).
func _then(next: int) -> void:
	ctx.state_2 = 1
	ctx.next_state_2 = next
	ctx.textbox_mode = 1


## showMapheadSelection as the tamer's: `count` choices, then step `next` + the choice (mode 2).
func _choice(index: int, count: int, next: int, section := TextBoxes.SECTION_SHOPKEEPER, keep := false) -> void:
	textboxes.show_maphead_selection(index, ScriptContext.OWNER_TAMER, count, keep, section)
	ctx.state_2 = 1
	ctx.next_state_2 = next
	ctx.textbox_mode = 2


## Step `step` on the next frame, nothing to wait for (mode 0).
func _now(step: int) -> void:
	ctx.state_2 = step
	ctx.textbox_mode = 0


## The line is shown and the list takes the input (mode 3, step 1).
func _wait_list() -> void:
	ctx.state_2 = 1
	ctx.textbox_mode = 3


func _repeat(on: bool) -> void:
	textboxes.pad.set_repeat_mask(LIST_REPEAT if on else 0)


func _close_list() -> void:
	textboxes.trigger_box_close_flag(ItemMenu.LIST_BOX)


## destroyItemMenuBox on both lists; ACTIVE_INSTRUCTION = 0 (the script goes on).
func _end() -> void:
	menu.left = null
	menu.right = null
	ctx.active_instruction = 0
