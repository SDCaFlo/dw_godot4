class_name BirdramonRoutines
extends MenuRoutines
## Builtin 0x0A, Birdramon's transport (tickBirdraTransport, shop/script_menu.c:987;
## specs/town_services.md §2.3): a paid flight to an unlocked area. "I know" moves the script to
## MAPHEAD section 0x4E3 ("Hold on tight!", TELEPORT from values 247 / 248). A child of
## ScriptRoutines (scenes/script/birdramon_routines.tscn).

const BIRDRAMON := 0x0A
var routines: Array = [BIRDRAMON]

const SECTION := ItemMenu.SERVICE_SECTION
const TAKE_OFF_SECTION := 0x4E3
## The flight's map and entrance, for TELEPORT 247.
const PSTAT_MAP := 247
const PSTAT_ENTRANCE := 248


func start(_routine: int) -> bool:
	return true


func tick(_routine: int) -> void:
	match ctx.state_2:
		0:
			menu.left = ItemMenu.allocate(6, 0xD2, 0x18, 6, 0x5A)
			menu.fill_destinations()
			_line(4, _owner(), SECTION)
			_then(3)
		2:
			_end()
		3:
			menu.create_bits_box(true)
			menu.create_destination_menu()
			_repeat(true)
			ctx.state_2 = 1
		4:
			_repeat(false)
			_choice(7, 2, 5, SECTION)
		5:
			textboxes.trigger_box_close_flag(ItemMenu.BITS_BOX)
			_close_list()
			var box := menu.left
			var target := menu.destination(box.item(box.top_row + box.cursor) & 0x7F)
			game_state.set_script_value(PSTAT_MAP, int(target["map"]["id"]))
			game_state.set_script_value(PSTAT_ENTRANCE, int(target["entrance"]))
			# ACTIVE_SCRIPT = getScript(0), SCRIPT_POINTER = its section 0x4E3: the script goes on there.
			ctx.code = textboxes.files.script(ScriptFiles.MAPHEAD)
			ctx.code_id = ScriptFiles.MAPHEAD
			ctx.pointer = ScriptFiles.section(ctx.code, TAKE_OFF_SECTION)
			game_state.state["money"] = int(game_state.state["money"]) - ctx.shop_variable
			game_state.changed.emit("money")
			ctx.state_2 = 2
		6:
			_repeat(false)
			textboxes.trigger_box_close_flag(ItemMenu.BITS_BOX)
			_close_list()
			_line(5, _owner(), SECTION)
			_then(2)
