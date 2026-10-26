class_name ItemKeeperRoutines
extends MenuRoutines
## Builtin 0x0B, the item keeper (tickItemKeeper, shop/script_menu.c:892; specs/town_services.md
## §2.1): items moved between the inventory and the storage, on the keeper's two boxes
## (KeeperMenu). A child of ScriptRoutines (scenes/script/item_keeper_routines.tscn).

const ITEM_KEEPER := 0x0B
var routines: Array = [ITEM_KEEPER]

const SECTION := KeeperMenu.SECTION
## setInputRepeatMask(0x5000 | CONFIRM | ALT): holding ✕ or ○ keeps moving items.
const KEEPER_REPEAT := LIST_REPEAT | Pad.CONFIRM | Pad.ALT

var keeper: KeeperMenu


func configure(routine_host: ScriptRoutines) -> void:
	super.configure(routine_host)
	keeper = KeeperMenu.new(menu)


func start(_routine: int) -> bool:
	return true


func tick(_routine: int) -> void:
	match ctx.state_2:
		0:
			menu.left = ItemMenu.allocate(5, 0x88, 0x28, 6, 0x4A)
			menu.right = ItemMenu.allocate(5, 0x88, 0x28, 6, 0x4A)
			_line(0, _owner(), SECTION)
			_then(3)
		2:
			_end()
		3:
			keeper.side = 0
			_choice(1, 2, 4, SECTION)
		4:
			textboxes.pad.set_repeat_mask(KEEPER_REPEAT)
			menu.type = ItemMenu.TYPE_PICK
			keeper.fill()
			keeper.create()
			_line(3, _owner(), SECTION)
			_wait_list()
		6:
			_repeat(false)
			_close_list()
			textboxes.trigger_box_close_flag(KeeperMenu.HAND_BOX)
			ctx.state_2 = 5
		5:
			_line(2, _owner(), SECTION)
			_then(2)
