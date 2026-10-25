class_name MeritShopRoutines
extends MenuRoutines
## Builtin 0x01, the merit shop (openMeritShop, shop/script_menu.c:788; specs/card_shops.md §2.5):
## a card shown for merit points (list type 6), merit points for an item (type 7). A child of
## ScriptRoutines (scenes/script/merit_shop_routines.tscn).

const MERIT_SHOP := 0x01
var routines: Array = [MERIT_SHOP]

const SECTION := ItemMenu.MERIT_SECTION


func start(_routine: int) -> bool:
	return true


func tick(_routine: int) -> void:
	match ctx.state_2:
		0:
			menu.left = ItemMenu.allocate(6, 0x9A, 0x18, 6, 0x5A)
			menu.right = ItemMenu.allocate(6, 0xB2, 0x18, 6, 0x5A)
			_line(0, _owner(), SECTION)
			_then(3)
		2:
			_end()
		3:
			_repeat(false)
			menu.create_bits_box(false)
			_choice(1, 3, 4, SECTION)
		4:
			_repeat(true)
			menu.type = ItemMenu.TYPE_CARD_SHOW
			menu.fill_cards()
			menu.create_card_menu()
			_line(5, _owner(), SECTION)
			_wait_list()
		5:
			_repeat(true)
			menu.type = ItemMenu.TYPE_MERIT
			menu.fill_merit()
			menu.create()
			_line(6, _owner(), SECTION)
			_wait_list()
		6:
			textboxes.trigger_box_close_flag(ItemMenu.BITS_BOX)
			_then(2)
		7:
			_repeat(false)
			_choice(2, 2, 8, SECTION)
		8:
			# Give it: the card for its merit value (capped at 9999).
			_close_list()
			_add_merit(ctx.shop_variable)
			game_state.set_card_count(menu.item_type, game_state.card_count(menu.item_type) - 1)
			_now(3)
			menu.savannah_sound()
		9, 0xD:
			_close_list()
			_now(3)
		0xA:
			_repeat(false)
			_close_list()
			_now(3)
		0xB:
			_repeat(false)
			_choice(3, 2, 0xC, SECTION)
		0xC:
			# OK: the item for its merit price.
			_close_list()
			_add_merit(-ctx.shop_variable)
			game_state.give_item(menu.item_type, 1)
			_now(3)
			menu.savannah_sound()


func _add_merit(value: int) -> void:
	var merit := int(game_state.state["merit"]) + value
	game_state.state["merit"] = mini(merit, ItemMenu.MERIT_MAX) if value > 0 else merit
	game_state.changed.emit("merit")
	menu.update_bits_box = true
