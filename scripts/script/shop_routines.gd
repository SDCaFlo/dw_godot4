class_name ShopRoutines
extends MenuRoutines
## The shop builtins (specs/shops.md §2.2-2.5): 0x08 the shop (openShop, script_common.c:1618) or,
## with trigger 3 set, the recycle shop (openRecycleShop, shop/script_menu.c:584); 0x00 the item
## picker (openDiscardItem, script_common.c:1815); 0x0F the bits box (createShopBitsBox); 0x23
## loadShopLibrary (an overlay load: nothing to do). A child of ScriptRoutines
## (scenes/script/shop_routines.tscn); the lists and boxes are the shared ItemMenu's.

const PICK_ITEM := 0x00
const SHOP := 0x08
const BITS_BOX := 0x0F
const LOAD_LIBRARY := 0x23
var routines: Array = [PICK_ITEM, SHOP, BITS_BOX, LOAD_LIBRARY]

## TRIGGER_3: the recycle shop (0x08), "nothing picked" (0x00).
const TRIGGER_3 := 3

## SHOP_ACTION_SELECTED: the Buy / Sell choice was shown (its cursor stays); MAIN_D_80134F74:
## something was bought or sold.
var _choice_shown := false
var _traded := false


func start(routine: int) -> bool:
	match routine:
		PICK_ITEM, SHOP:
			return true
		BITS_BOX:
			menu.create_bits_box(true)
	return false


func tick(routine: int) -> void:
	if routine == PICK_ITEM:
		_pick_item()
	elif game_state.is_trigger_set(TRIGGER_3):
		_recycle_shop()
	else:
		_shop()


func _shop_choice(index: int, count: int) -> void:
	_choice(index, count, 4, TextBoxes.SECTION_SHOPKEEPER, _choice_shown)
	_choice_shown = true


func _open_list(type: int, line: int, owner: int) -> void:
	_repeat(true)
	menu.type = type
	menu.create()
	_line(line, owner)
	_wait_list()


func _close_shop_list() -> void:
	_repeat(false)
	_close_list()


func _has_stock() -> bool:
	for i in 0x80:
		if game_state.is_trigger_set(ItemMenu.STOCK_TRIGGER + i):
			return true
	return false


## openShop.
func _shop() -> void:
	var npc := _owner()
	match ctx.state_2:
		0:
			menu.left = ItemMenu.allocate(6, 0xB2, 0x18, 6, 0x5A)
			menu.right = ItemMenu.allocate(6, 0xD2, 0x18, 6, 0x5A)
			_choice_shown = false
			_traded = false
			if _has_stock():
				_line(0, npc)
				_then(3)
			else:
				_line(1, npc)
				_then(2)
		2:
			_end()
		3:
			menu.create_bits_box(true)
			_shop_choice(2, 3)
		4:
			menu.type = ItemMenu.TYPE_BUY
			menu.fill_buy()
			_open_list(ItemMenu.TYPE_BUY, 8, npc)
		5:
			menu.type = ItemMenu.TYPE_SELL
			menu.fill_sell()
			_open_list(ItemMenu.TYPE_SELL, 9, npc)
		6:
			textboxes.trigger_box_close_flag(ItemMenu.BITS_BOX)
			_line(4 if _traded else 5, npc)
			_then(2)
		7:
			_close_shop_list()
			_line(0xD if menu.type == ItemMenu.TYPE_BUY and menu.is_partner_baby() else 0xA, npc)
			_then(3)
			_traded = true
		8:
			_close_shop_list()
			_line(0xB, npc)
			ctx.state_2 = 9
		9:
			_then(3)


## openRecycleShop.
func _recycle_shop() -> void:
	var npc := _owner()
	match ctx.state_2:
		0:
			menu.left = ItemMenu.allocate(6, 0xD2, 0x18, 6, 0x5A)
			var any := menu.fill_recycle()
			_choice_shown = false
			_traded = false
			if any:
				_line(0, npc)
				_then(3)
			else:
				_line(1, npc)
				_then(2)
		2:
			_end()
		3:
			menu.create_bits_box(true)
			_shop_choice(3, 2)
		4:
			_open_list(ItemMenu.TYPE_RECYCLE, 8, npc)
		5, 6:
			textboxes.trigger_box_close_flag(ItemMenu.BITS_BOX)
			_line(4 if _traded else 5, npc)
			_then(2)
		7:
			_close_shop_list()
			_line(0xD if menu.is_partner_baby() else 0xA, npc)
			_traded = true
			_then(3 if menu.fill_recycle() else 9)
		8:
			_close_shop_list()
			_line(0xB, npc)
			_then(3)
		9:
			_close_shop_list()
			_line(0xC, npc)
			_then(6)


## openDiscardItem: pick an item (script value 0xFE) or nothing (trigger 3, value 0xFF).
func _pick_item() -> void:
	match ctx.state_2:
		0:
			menu.right = ItemMenu.allocate(6, 0x9A, 0x18, 6, 0x5A)
			if menu.fill_sell():
				ctx.state_2 = 3
			else:
				game_state.set_trigger(TRIGGER_3)
				game_state.set_script_value(0xFE, 0xFF)
				ctx.state_2 = 2
			ctx.textbox_mode = 0
		2:
			menu.right = null
			ctx.active_instruction = 0
		3:
			_repeat(true)
			menu.type = ItemMenu.TYPE_PICK
			menu.create()
			ctx.state_2 = 1
		4:
			_close_shop_list()
			ctx.state_2 = 2
