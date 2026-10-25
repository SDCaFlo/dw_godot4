class_name MojyamonRoutines
extends MenuRoutines
## Builtin 0x02, Mojyamon's trades (openMojyamonShop, shop/script_menu.c:1051; specs/card_shops.md
## §2.6): one item-for-item trade of the set in value 249, on the trade box (TradeMenu). A child of
## ScriptRoutines (scenes/script/mojyamon_routines.tscn).

const MOJYAMON := 0x02
var routines: Array = [MOJYAMON]

const SECTION := TradeMenu.MOJYA_SECTION

var trade: TradeMenu


func configure(routine_host: ScriptRoutines) -> void:
	super.configure(routine_host)
	trade = TradeMenu.new(menu)


func start(_routine: int) -> bool:
	return true


func tick(_routine: int) -> void:
	match ctx.state_2:
		0:
			menu.left = ItemMenu.allocate(3, 0, 0, 0, 0)
			menu.right = ItemMenu.allocate(3, 0, 0, 0, 0)
			trade.fill(ctx.read_pstat(TradeMenu.PSTAT_PICKED))
			game_state.set_script_value(TradeMenu.PSTAT_PICKED, TradeMenu.NOTHING_PICKED)
			_line(8, _owner(), SECTION)
			_then(3)
		2:
			_end()
		3:
			_repeat(true)
			trade.create()
			_line(9, _owner(), SECTION)
			_wait_list()
		4:
			_repeat(false)
			_choice(0xC, 2, 5, SECTION)
		5:
			# Yeah: what he gives first; the item asked for goes only if that worked.
			_close_list()
			var box := menu.left
			if game_state.give_item(menu.right.item(box.top_row + box.cursor), 1):
				game_state.remove_item(ctx.read_pstat(TradeMenu.PSTAT_PICKED), 1)
				trade.set_traded()
				_line(0xD, _owner(), SECTION)
			else:
				_line(0xE, _owner(), SECTION)
			_then(2)
			menu.savannah_sound()
		6:
			_repeat(false)
			_close_list()
			_line(10, _owner(), SECTION)
			_then(2)
