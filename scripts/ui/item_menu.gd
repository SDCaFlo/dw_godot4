class_name ItemMenu
extends RefCounted
## The event scripts' item menu (script_common.c:695-1153, :1457-1617, :1729-2420, :2536-2920,
## :3123; specs/shops.md §2.5-2.9): the item lists of the shops and the item picker (box 1), the
## bits box (box 2), and the boxes opened from a row (box 3): the amount, "Is it OK? Yes No" and the
## item's description. Used by the routine nodes (ShopRoutines); it works on the scripts' text boxes
## (TextBoxes: line buffers, entries, pages), the UI boxes and the game state. The card lists (types
## 3, 4, 6), the merit list (7) and the card branches of the boxes: specs/card_shops.md §2.7-2.8.

## ITEM_MENU_TYPE.
const TYPE_BUY := 0
const TYPE_SELL := 1
const TYPE_RECYCLE := 2
const TYPE_CARD_BUY := 3
const TYPE_CARD_SELL := 4
const TYPE_PICK := 5
const TYPE_CARD_SHOW := 6
const TYPE_MERIT := 7
## updateItemMenuStrings' styles: the row writer (calculateItemMenuStrings, calculateCardMenuStrings,
## calculateItemListStrings); `row_writers` maps them, a menu of its own adds its style (TradeMenu).
const STYLE_ITEM := 0
const STYLE_CARD := 1
const STYLE_TRADE := 4
const LIST_BOX := 1
const BITS_BOX := 2
const SUB_BOX := 3
## ITEM_MENU_POS, ITEM_MENU_DESCRIPTION_RECTS, SELECTION_CURSOR_WIDTHS (script_common.c:624-638).
const POS := [[-0x37, -0x62, 0xBE, 0x81], [-0x47, -0x62, 0xDE, 0x81], [-0x47, -0x62, 0xDE, 0x81],
		[-0x37, -0x62, 0xBE, 0x81], [-0x47, -0x62, 0xDE, 0x81], [-0x24, -0x62, 0xA6, 0x81],
		[-0x24, -0x62, 0xA6, 0x81], [-0x37, -0x62, 0xBE, 0x81]]
const DESCRIPTION_RECTS := [[5, 17, 170, 18], [5, 17, 202, 18], [5, 17, 202, 18], [5, 17, 170, 18],
		[5, 17, 202, 18], [5, 17, 146, 18], [5, 17, 146, 18], [5, 17, 170, 18]]
const CURSOR_WIDTHS := [0xAA, 0xCA, 0xCA, 0xAA, 0xCA, 0x92, 0x92, 0xAA]
## ITEM_MENU_HEADER_UVS (:330): u, v (VRAM-style; & 0xFF on the page), w, h. SYSTEM_W, palette
## GetClut(96, 492).
const HEADER_UVS := [[0x200, 0x1A2, 0x14, 7], [0x214, 0x1A2, 0x14, 7], [0x250, 0x1B0, 0x14, 7],
		[0x264, 0x1B0, 0x16, 7], [0x228, 0x1A2, 0xC, 7], [0x234, 0x1A2, 0x14, 7], [0x238, 0x1B0, 0x14, 7]]
const HEADER_CLUT := (492 << 6) | 6
## AMOUNT_BOX_LAYOUT (US, :292): x, y, chars (taken 12 px a char, one after the other).
const AMOUNT_LAYOUT := [[0x1A, 7, 8], [0x4A, 0x1B, 5], [0x59, 0x2B, 2], [0x40, 0x41, 6]]
## CONFIRM_BOX_LAYOUT (US, :316): src x, src y, x, y, width.
const CONFIRM_LAYOUT := [[0, 0, 4, 2, 0x60], [0, 0xC, 0xE, 0x12, 0x24], [0x24, 0xC, 0x44, 0x12, 0x24]]
const GLYPH_WIDTH := 12
## UI_LINES' dark and light words (renderHorizontalLine, renderItemMenuScrollBar).
const DARK := 0x020202
const LIGHT := 0xA08769
## playShopSoundOnlyInSavannah (MAIN_D_801345C0 / C2): on map 0x83, playSound(0, 0x17).
const SAVANNAH_MAP := 0x83
const SAVANNAH_SOUND := 0x17
const MONEY_MAX := 999999
## The stock triggers (0x180 + item id).
const STOCK_TRIGGER := 0x180
## The item picker's "cancel allowed / nothing picked" trigger (TRIGGER_3).
const TRIGGER_PICK := 3
## A card is no longer offered or added by the shops and packs at 9 held (hasAnyCardToBuy,
## showCardTextbox).
const CARD_SHOP_LIMIT := 9
const MERIT_MAX := 9999
## The MAPHEAD sections of the card shops, the merit shop and "Is it OK? Yes No".
const CARD_SECTION := 0x4D3
const MERIT_SECTION := 0x4D4
const CONFIRM_SECTION := 0x4D8
## renderCardSprite: the rarity's icon on SYSTEM_W, u = rarity x 12, v 0x1C0, CLUT (96, 493).
const CARD_ICON_V := 0x1C0
const CARD_ICON_CLUT := (493 << 6) | 6
const CARD_ICON_SIZE := 12


## ItemMenuBox: the rows (item, second byte) and the window over them.
class ListBox:
	var buf := PackedByteArray()
	var item_count := 0
	var visible_rows := 6
	## The scroll bar's rect in the box.
	var rect := Rect2i()
	var is_open := false
	var box_id := 0
	var top_row := 0
	var cursor := 0
	var prev_top_row := 0
	var prev_cursor := 0
	## The text row of each visible row slot (rotated when the list scrolls).
	var item_row: Array[int] = []

	func item(row: int) -> int:
		return buf[row * 2] if row * 2 < buf.size() else 0xFF

	func second(row: int) -> int:
		return buf[row * 2 + 1] if row * 2 + 1 < buf.size() else 0


var textboxes: TextBoxes
var boxes: UIBoxes
var text_area: TextArea
var pad: Pad
var ctx: ScriptContext
var game_state: Node
var data: Node

## ITEM_MENU_LEFT, ITEM_MENU_RIGHT.
var left: ListBox
var right: ListBox
var type := TYPE_BUY
## SHOP_ITEM_TYPE, SHOP_ITEM_PRICE, MAX_SHOP_AMOUNT, SHOP_AMOUNT.
var item_type := 0
var item_price := 0
var max_amount := 0
var amount := 0
## UPDATE_SHOP_BIT_BOX, BIT_BOX_SHOW_BITS.
var update_bits_box := false
var show_bits := true
## ITEM_MENU_SUB_TEXTBOX_LINE.
var sub_line := 0
## The list box's page is being drawn or flipped this frame (flipTextboxPage, from the render).
var _busy := false
## style -> func(box, row, last).
var row_writers := {}


func _init(text_boxes: TextBoxes, state: Node, game_data: Node) -> void:
	textboxes = text_boxes
	boxes = text_boxes.boxes
	text_area = text_boxes.text_area
	pad = text_boxes.pad
	ctx = text_boxes.ctx
	game_state = state
	data = game_data
	row_writers[STYLE_ITEM] = _row_string
	row_writers[STYLE_CARD] = _card_row_string


func _sound(id: int) -> void:
	textboxes.sound.emit(id)


# --- the lists (script_common.c:695-797, script_menu.c:1385) ---------------------------------------

## allocateItemMenuBox.
static func allocate(rows: int, x: int, y: int, w: int, h: int) -> ListBox:
	var box := ListBox.new()
	box.visible_rows = rows
	box.rect = Rect2i(x, y, w, h)
	return box


func money() -> int:
	return int(game_state.state["money"])


func _price(item: int) -> int:
	var p = data.item(item).get("price")
	return int(p) if p != null else 0


func _slots() -> Array:
	var slots: Array = game_state.state["inventory"]["slots"]
	return slots.slice(0, mini(int(game_state.state["inventory"]["size"]), slots.size()))


func _slot_item(slot) -> int:
	return data.id_of("items/item_data", slot["item"]) if slot != null else 0xFF


## shopFillBuyItemList: a row per stock trigger, (item, buyable). True if anything is buyable.
func fill_buy() -> bool:
	var box := left
	box.buf = PackedByteArray()
	box.item_count = 0
	var slots := _slots()
	var has_space := slots.has(null)
	var any := false
	for item in 128:
		if not game_state.is_trigger_set(STOCK_TRIGGER + item):
			continue
		box.item_count += 1
		box.buf.append(item)
		if _price(item) > money():
			box.buf.append(0)
			continue
		var buyable := 0
		if has_space:
			buyable = 1
			for s in slots:
				if _slot_item(s) == item and int(s["amount"]) == 99:
					buyable = 0
					break
		else:
			for s in slots:
				if _slot_item(s) == item and int(s["amount"]) != 99:
					buyable = 1
					break
		box.buf.append(buyable)
		if buyable == 1:
			any = true
	return any


## shopFillSellItemList: a row per inventory slot, (item or 0xFF, amount | 0x80 when droppable).
## True if any item is droppable.
func fill_sell() -> bool:
	var box := right
	box.buf = PackedByteArray()
	box.item_count = 0
	var any := false
	for s in _slots():
		var item := _slot_item(s)
		var count := int(s["amount"]) if s != null else 0
		if item != 0xFF and bool(data.item(item).get("droppable", false)):
			count |= 0x80
			any = true
		box.item_count += 1
		box.buf.append(item)
		box.buf.append(count & 0xFF)
	return any


## fillRecycleShopItemList: a row per recycle stock slot with a count, (item, count | 0x80 when
## affordable). True if any.
func fill_recycle() -> bool:
	var box := left
	box.buf = PackedByteArray()
	box.item_count = 0
	var stock: Array = game_state.state["script"]["recycle_stock"]
	var items: Array = data.recyclable_items()
	for i in mini(stock.size(), items.size()):
		var count := int(stock[i])
		if count == 0:
			continue
		var item := int(items[i]["item"]["id"])
		box.item_count += 1
		box.buf.append(item)
		if _price(item) <= money():
			count |= 0x80
		box.buf.append(count & 0xFF)
	return box.item_count != 0


## shopFillMeritItemList (script_menu.c:1479): a row per item with a merit price, in id order:
## (item, available): the merit is enough and there is a free slot or a stack below 99.
func fill_merit() -> bool:
	var box := right
	box.buf = PackedByteArray()
	box.item_count = 0
	var slots := _slots()
	var has_space := slots.has(null)
	var merit := int(game_state.state["merit"])
	var any := false
	for record in data.records("items/item_data"):
		var value := int(record.get("merit", 0))
		if value == 0:
			continue
		var item := int(record["id"])
		box.item_count += 1
		box.buf.append(item)
		var available := 0
		if value <= merit:
			if has_space:
				available = 1
			else:
				for s in slots:
					if _slot_item(s) == item and int(s["amount"]) != 99:
						available = 1
						break
		box.buf.append(available)
		if available:
			any = true
	return any


## The cards the shops list: every card that has a price, in id order (the C's ids 1-0x40).
func _priced_cards() -> Array:
	var out := []
	for record in data.records("items/card_data"):
		if record.get("price") != null:
			out.append(int(record["id"]))
	return out


func card_price(card: int) -> int:
	var p = data.card(card).get("price")
	return int(p) if p != null else 0


func card_rarity(card: int) -> int:
	return int(data.card(card).get("rarity", 0))


## hasAnyCardToBuy (script_menu.c:1296): the 6 slots of the card shop, (card, available) or
## (0xFF, 0). True if any slot holds a card.
func fill_card_shop() -> bool:
	var box := left
	box.buf = PackedByteArray()
	box.item_count = 0
	var any := false
	for slot in game_state.state["script"]["card_shop"]:
		box.item_count += 1
		if slot == null:
			box.buf.append_array([0xFF, 0])
			continue
		var card: int = data.id_of("items/card_data", slot)
		box.buf.append(card)
		box.buf.append(1 if card_price(card) <= money() and game_state.card_count(card) < CARD_SHOP_LIMIT else 0)
		any = true
	return any


## shopFillSellCardList (script_menu.c:1359): a row per priced card, (card, count) when held, else
## an empty row (0xFF, 0). True if any is held.
func fill_cards() -> bool:
	var box := left
	box.buf = PackedByteArray()
	box.item_count = 0
	var any := false
	for card in _priced_cards():
		box.item_count += 1
		var count: int = game_state.card_count(card)
		if count != 0:
			box.buf.append_array([card, count])
			any = true
		else:
			box.buf.append_array([0xFF, 0])
	return any


## playShopSoundOnlyInSavannah.
func savannah_sound() -> void:
	if ctx.current_screen_id == SAVANNAH_MAP:
		_sound(SAVANNAH_SOUND)


## getRecycleId: the recycle stock slot of an item (the first, item 0x54 is listed twice), 0xFF.
func recycle_id(item: int) -> int:
	var items: Array = data.recyclable_items()
	for i in items.size():
		if int(items[i]["item"]["id"]) == item:
			return i
	return 0xFF


## isPartnerBaby: the partner's Digimon is one of BABY_IDS (systems/babies).
func is_partner_baby() -> bool:
	var partner: int = data.id_of("digimon/digimon_data", game_state.state["partner"]["digimon"])
	for b in data.system("babies"):
		for entry in b.get("baby_ids", []):
			if int(entry["id"]) == partner:
				return true
	return false


## getItemMenuFromType.
func current_box() -> ListBox:
	if type == TYPE_SELL or type == TYPE_PICK or type == TYPE_MERIT:
		return right
	return left


# --- the list box (box 1: createItemMenu, tickItemMenu, renderItemMenu) ----------------------------

## createItemMenu.
func create() -> void:
	var owner := ctx.read_pstat(0xFE)
	if type == TYPE_SELL or type == TYPE_PICK:
		owner = ScriptContext.OWNER_TAMER
	var p: Array = POS[type]
	textboxes.create_textbox(LIST_BOX, 0xF1, Rect2i(p[0], p[1], p[2], p[3]), _origin(owner), tick_list, render_list,
			on_render_list)
	textboxes.register_textbox(LIST_BOX, 9, 6, 1, 0)
	var box := current_box()
	_init_box(box, LIST_BOX, 9)
	update_strings(box, 9)
	ctx.shop_variable = 0


## createCardMenu (script_menu.c:1452): box 1 for types 3, 4, 6 (from the tamer for type 4).
func create_card_menu() -> void:
	var owner := ScriptContext.OWNER_TAMER if type == TYPE_CARD_SELL else ctx.read_pstat(0xFE)
	var p: Array = POS[type]
	textboxes.create_textbox(LIST_BOX, 0xF1, Rect2i(p[0], p[1], p[2], p[3]), _origin(owner), tick_card_menu,
			render_card_menu, on_render_list)
	textboxes.register_textbox(LIST_BOX, 9, 6, 1, 0)
	var box := current_box()
	_init_box(box, LIST_BOX, 9)
	update_strings(box, 9, STYLE_CARD)
	ctx.shop_variable = 0


func _origin(owner: int) -> Rect2i:
	var o = textboxes.setup_box_origin(owner)
	return o if o is Rect2i else Rect2i(-5, -5, 10, 10)


## initItemMenuBox.
func _init_box(box: ListBox, box_id: int, start_row: int) -> void:
	if box.is_open:
		return
	box.is_open = true
	box.box_id = box_id
	box.top_row = 0
	box.cursor = 0
	box.prev_top_row = 0
	box.prev_cursor = 0
	box.item_row.clear()
	for i in box.visible_rows:
		box.item_row.append(start_row + i)


## getTextboxLine: the line buffer offset of a row slot, on the entry's back page.
func _line(box: ListBox, index: int) -> int:
	var e: TextBoxes.Entry = textboxes.entries[box.box_id]
	var at := box.item_row[index] * textboxes.line_size
	if e.vram_mode == 2:
		at += textboxes.line_size / 2
	if e.double_buffered == 1:
		at += ((e.back_page ^ 1) * e.vram_rows) * textboxes.line_size
	return at


func _put(at: int, bytes) -> int:
	for b in bytes:
		if at >= 0 and at < textboxes.lines.size():
			textboxes.lines[at] = b & 0xFF
		at += 1
	return at


## terminateString.
func _terminate(at: int, last: bool) -> int:
	at = _put(at, [1, 1])
	return _put(at, [0, 0] if last else [0xD, 0])


func _name_bytes(item: int) -> PackedByteArray:
	return text_area.font.to_bytes(data.localize(data.item(item).get("name")))


## The name of the Digimon a card shows.
func _card_name_bytes(card: int) -> PackedByteArray:
	var digimon = data.card(card).get("digimon", {})
	return text_area.font.to_bytes(data.localize(data.digimon(int(digimon.get("id", 0))).get("name")))


## calculateItemMenuStrings (US): a row's line (§2.6.1).
func _row_string(box: ListBox, row: int, last: bool) -> void:
	var at := _line(box, row)
	var item := box.item(box.top_row + row)
	var second := box.second(box.top_row + row)
	if item != 0xFF:
		var available := second != 0 if type == TYPE_BUY or type == TYPE_MERIT else second & 0x80 != 0
		at = _put(at, [1, 1 if available else 3])
		at = _put(at, _name_bytes(item))
		at = _put(at, [0xF, 0])
		var amount_part := false
		if type != TYPE_PICK:
			at = _put(at, [0x16, 0])
			var value := 0
			if type != TYPE_MERIT:
				value = _price(item)
				if type == TYPE_SELL:
					if second & 0x80:
						value >>= 1
					else:
						for i in 4:
							at = _put(at, [0x81, 0x7C])
						at = _put(at, [0xF, 0])
						amount_part = true
			else:
				value = int(data.item(item).get("merit", 0))
			if not amount_part:
				at = _put(at, TextBoxes.int_to_string_sjis(value, 4, 0))
				at = _put(at, [0xF, 0])
		if type == TYPE_SELL:
			at = _put(at, TextBoxes.int_to_string_sjis(second & 0x7F, 2, 0))
		if type != TYPE_BUY and type != TYPE_MERIT and type != TYPE_SELL:
			at = _put(at, [0x1C, 0])
			at = _put(at, TextBoxes.int_to_string_sjis(second & 0x7F, 2, 0))
	_terminate(at, last)


## calculateCardMenuStrings (US): a card row (specs/card_shops.md §2.7).
func _card_row_string(box: ListBox, row: int, last: bool) -> void:
	var at := _line(box, row)
	var card := box.item(box.top_row + row)
	var second := box.second(box.top_row + row)
	if card != 0xFF:
		var colour := 1
		if type == TYPE_CARD_BUY:
			if second == 0:
				colour = 3
			elif game_state.card_count(card) == 0:
				colour = 7
		at = _put(at, [1, colour])
		at = _put(at, _card_name_bytes(card))
		at = _put(at, [0x17, 0, 0xF, 0])
		var price := card_price(card)
		if type == TYPE_CARD_BUY:
			at = _put(at, TextBoxes.int_to_string_sjis(price, 4, 0))
		else:
			if type != TYPE_CARD_SHOW:
				at = _put(at, TextBoxes.int_to_string_sjis(price >> 1, 4, 0))
				at = _put(at, [0xF, 0])
			at = _put(at, TextBoxes.int_to_string_sjis(second, 2, 0))
	_terminate(at, last)


func _write_row(box: ListBox, row: int, last: bool, style: int) -> void:
	row_writers[style].call(box, row, last)


## updateItemMenuStrings: every visible row into the back page; the page is then drawn.
func update_strings(box: ListBox, start_row: int, style := STYLE_ITEM) -> void:
	var e: TextBoxes.Entry = textboxes.entries[box.box_id]
	var rows := mini(box.item_count - box.top_row, box.visible_rows)
	if rows != 0:
		for i in rows:
			_write_row(box, i, box.item_row[i] == start_row + rows - 1, style)
	else:
		var at := start_row * textboxes.line_size
		if e.vram_mode == 2:
			at += textboxes.line_size / 2
		if e.double_buffered == 1:
			at += ((e.back_page ^ 1) * e.vram_rows) * textboxes.line_size
		_put(at, [0, 0])
	e.page_ready = 1
	e.write_count += 1


## updateItemMenuLine: the row under the cursor written into the shown page and drawn at once.
func _update_line(box: ListBox, style: int) -> void:
	var e: TextBoxes.Entry = textboxes.entries[box.box_id]
	e.back_page ^= 1
	_write_row(box, box.cursor, true, style)
	e.back_page ^= 1
	var row := box.item_row[box.cursor]
	if e.double_buffered == 1:
		row += e.back_page * e.vram_rows
	var coords := TextBoxes.vram_mode_coords(e.vram_mode)
	var at := row * textboxes.line_size + (textboxes.line_size / 2 if coords[0] != 0 else 0)
	textboxes.draw_string2(at, coords[0], row * TextBoxes.ROW_HEIGHT)


## flipTextboxPage (script_common.c:2536): true while the rows are drawn; a finished page flips.
## Where the C falls off its end after the flip (no return value), the port counts that frame busy.
func flip_page(box_id: int) -> bool:
	var e: TextBoxes.Entry = textboxes.entries[box_id]
	if e.double_buffered == 0:
		return false
	if e.registered == 0:
		return true
	if e.write_count != e.render_count:
		return true
	if e.page_ready == 0:
		return false
	e.back_page ^= 1
	e.flip_count += 1
	e.page_ready = 0
	return true


## isItemMenuBoxBusy.
func is_busy(box: ListBox) -> bool:
	if box == null:
		return true
	return flip_page(box.box_id)


# The cursor (itemMenuCursorUp / Down / Top / Bottom).

func cursor_up(box: ListBox, style := STYLE_ITEM) -> void:
	if box.top_row + box.cursor == 0:
		_sound(0xB)
		return
	if box.cursor == 0:
		box.top_row -= 1
		var last: int = box.item_row[box.visible_rows - 1]
		for k in range(box.visible_rows - 1, 0, -1):
			box.item_row[k] = box.item_row[k - 1]
		box.item_row[0] = last
		_update_line(box, style)
	else:
		box.cursor -= 1
	_sound(2)


func cursor_down(box: ListBox, style := STYLE_ITEM) -> void:
	box.cursor += 1
	if box.top_row + box.cursor < box.item_count:
		if box.cursor == box.visible_rows:
			box.top_row += 1
			box.cursor -= 1
			var first: int = box.item_row[0]
			for k in range(1, box.visible_rows):
				box.item_row[k - 1] = box.item_row[k]
			box.item_row[box.visible_rows - 1] = first
			_update_line(box, style)
		_sound(2)
	else:
		box.cursor -= 1
		_sound(0xB)


func cursor_top(box: ListBox, start_row: int, style := STYLE_ITEM) -> void:
	box.prev_top_row = box.top_row
	box.prev_cursor = box.cursor
	box.top_row = 0
	box.cursor = 0
	_sound(2)
	update_strings(box, start_row, style)


func cursor_bottom(box: ListBox, start_row: int, style := STYLE_ITEM) -> void:
	box.prev_top_row = box.top_row
	box.prev_cursor = box.cursor
	var diff := box.item_count - box.visible_rows
	if diff <= 0:
		box.top_row = 0
		box.cursor = box.item_count - 1
	else:
		box.top_row = diff
		box.cursor = box.visible_rows - 1
	_sound(2)
	update_strings(box, start_row, style)


func _row_origin(box: ListBox) -> Rect2i:
	var d: Array = DESCRIPTION_RECTS[type]
	var b: UIBoxes.Box = boxes.boxes[LIST_BOX]
	return Rect2i(d[0] + b.final.position.x, d[1] + b.final.position.y + box.cursor * 18, d[2], d[3])


## tickItemMenu (script_common.c:798).
func tick_list(_id: int) -> void:
	var box := current_box()
	if _busy or box == null:
		return
	if boxes.boxes[SUB_BOX].state != UIBoxes.STATE_CLOSED:
		return
	if boxes.boxes[LIST_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	if ctx.shop_variable != 0 or ctx.state_2 != 1:
		return
	if pad.is_key_down(Pad.CONFIRM):
		if type == TYPE_PICK:
			create_confirm(_row_origin(box))
		elif type != TYPE_MERIT:
			create_amount(_row_origin(box))
		else:
			_read_selected_item_merit()
	elif pad.is_key_down(Pad.CANCEL):
		if type == TYPE_MERIT:
			ctx.state_2 = 0xA
		elif type == TYPE_PICK:
			if game_state.is_trigger_set(TRIGGER_PICK):
				game_state.set_script_value(0xFE, 0xFF)
				game_state.clear_trigger(TRIGGER_PICK)
				ctx.state_2 = 4
		else:
			ctx.state_2 = 8
		_sound(4)
	elif pad.is_key_down(Pad.UP):
		if pad.polled & Pad.R1:
			cursor_top(box, 9)
		else:
			cursor_up(box)
	elif pad.is_key_down(Pad.DOWN):
		if pad.polled & Pad.R1:
			cursor_bottom(box, 9)
		else:
			cursor_down(box)
	elif pad.is_key_down(Pad.START):
		create_description(box, _row_origin(box))
		_sound(3)


## readSelectedItemMerit (script_common.c:877): an available item's merit price into
## SHOP_VARIABLE, then step 0xB at once (sound 3); else sound 0xB.
func _read_selected_item_merit() -> bool:
	var box := current_box()
	var row := box.top_row + box.cursor
	item_type = box.item(row)
	if item_type != 0xFF and box.second(row) != 0:
		ctx.shop_variable = int(data.item(item_type).get("merit", 0))
		ctx.state_2 = 0xB
		ctx.textbox_mode = 0
		_sound(3)
		return true
	_sound(0xB)
	return false


## tickCardMenu (script_menu.c:1816): tickItemMenu without the step check and without START.
func tick_card_menu(_id: int) -> void:
	var box := current_box()
	if _busy or box == null:
		return
	if boxes.boxes[SUB_BOX].state != UIBoxes.STATE_CLOSED:
		return
	if boxes.boxes[LIST_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	if ctx.shop_variable != 0:
		return
	if pad.is_key_down(Pad.CONFIRM):
		if type == TYPE_CARD_BUY:
			create_confirm(_row_origin(box))
		elif type == TYPE_CARD_SHOW:
			_merit_card_trade()
		else:
			create_amount(_row_origin(box))
	elif pad.is_key_down(Pad.CANCEL):
		ctx.state_2 = 0xA if type == TYPE_CARD_SHOW else 4
		_sound(4)
	elif pad.is_key_down(Pad.UP):
		if pad.polled & Pad.R1:
			cursor_top(box, 9, STYLE_CARD)
		else:
			cursor_up(box, STYLE_CARD)
	elif pad.is_key_down(Pad.DOWN):
		if pad.polled & Pad.R1:
			cursor_bottom(box, 9, STYLE_CARD)
		else:
			cursor_down(box, STYLE_CARD)


## createMeritCardTradeDialogue (script_menu.c:1911): a held card's merit value into SHOP_VARIABLE,
## the merit shop's line rarity + 7 (section 0x4D4), then step 7 (sound 3); else sound 0xB.
func _merit_card_trade() -> bool:
	var box := current_box()
	var row := box.top_row + box.cursor
	item_type = box.item(row)
	if item_type != 0xFF and box.second(row) != 0:
		ctx.shop_variable = int(data.card(item_type).get("merit", 0))
		textboxes.show_maphead_textbox(card_rarity(item_type) + 7, ctx.read_pstat(0xFE), 0, MERIT_SECTION)
		ctx.state_2 = 1
		ctx.next_state_2 = 7
		ctx.textbox_mode = 1
		_sound(3)
		return true
	_sound(0xB)
	return false


## The render function's counting part: the page flip (renderItemMenuItemList's isItemMenuBoxBusy).
func on_render_list(_id: int) -> void:
	_busy = is_busy(current_box())


## renderItemMenu (script_common.c:984), drawn in reverse of the C's adds: the texts, the icons,
## the scroll bar, the headers; the selection cursor over them (as the inventory's).
func render_list(canvas: CanvasItem, _id: int) -> void:
	var box := current_box()
	if box == null:
		return
	var b: UIBoxes.Box = boxes.boxes[LIST_BOX]
	var bx := b.final.position.x
	var by := b.final.position.y
	_render_rows(canvas, box, bx + 0x1A, by + 0x13, bx + 8, by + 0x12, 0)
	_render_scroll_bar(canvas, box)
	match type:
		TYPE_PICK:
			_header(canvas, 3, bx + 0x80, by + 5)
		TYPE_MERIT:
			_header(canvas, 2, bx + 0x80, by + 5)
		_:
			if type != TYPE_BUY:
				_header(canvas, 3, bx + 0xB6, by + 5)
			_header(canvas, 1, bx + 0x80, by + 5)
	_header(canvas, 0, bx + 8, by + 5)
	PsxDraw.selection_cursor(canvas, bx + 5, by + box.cursor * 0x12 + 0x11, CURSOR_WIDTHS[type], 0x12)


## renderCardMenu (script_menu.c:1876), in reverse of the C's adds as render_list.
func render_card_menu(canvas: CanvasItem, _id: int) -> void:
	var box := current_box()
	if box == null:
		return
	var b: UIBoxes.Box = boxes.boxes[LIST_BOX]
	var bx := b.final.position.x
	var by := b.final.position.y
	_render_rows(canvas, box, bx + 0x1A, by + 0x13, bx + 8, by + 0x12, 1)
	_render_scroll_bar(canvas, box)
	if type != TYPE_CARD_SHOW:
		if type == TYPE_CARD_SELL:
			_header(canvas, 3, bx + 0xB6, by + 5)
		_header(canvas, 1, bx + 0x80, by + 5)
	else:
		_header(canvas, 3, bx + 0x80, by + 5)
	_header(canvas, 0, bx + 8, by + 5)
	PsxDraw.selection_cursor(canvas, bx + 5, by + box.cursor * 0x12 + 0x11, CURSOR_WIDTHS[type], 0x12)


## renderCardSprite: the icon of a card's rarity.
func _card_icon(canvas: CanvasItem, card: int, x: int, y: int) -> void:
	MenuDraw.sprite(canvas, x, y, CARD_ICON_SIZE, CARD_ICON_SIZE, (card_rarity(card) * CARD_ICON_SIZE) & 0xFF,
			(CARD_ICON_V & 0xFF) - 0x80, CARD_ICON_CLUT)


## renderItemMenuSprite: a header label of SYSTEM_W.
func _header(canvas: CanvasItem, index: int, x: int, y: int) -> void:
	var e: Array = HEADER_UVS[index]
	MenuDraw.sprite(canvas, x, y, e[2], e[3], e[0] & 0xFF, (e[1] & 0xFF) - 0x80, HEADER_CLUT)


## renderItemMenuScrollBar.
func _render_scroll_bar(canvas: CanvasItem, box: ListBox) -> void:
	var b: UIBoxes.Box = boxes.boxes[box.box_id]
	var x := box.rect.position.x + b.final.position.x
	var y := box.rect.position.y + b.final.position.y
	var w := box.rect.size.x
	var h := box.rect.size.y
	var rows := maxi(box.item_count, box.visible_rows)
	var track := (h * 100) / rows
	var thumb_y := y + 1 + (track * box.top_row) / 100
	track = (track * box.visible_rows) / 100
	PsxDraw.box(canvas, Rect2i(x + 1, y + 1, w, h), Color8(0x35, 0x4B, 0x5C))
	PsxDraw.box(canvas, Rect2i(x + 2, thumb_y + 1, w - 2, track - 2), Color8(0x5B, 0x70, 0x80))
	PsxDraw.line3(canvas, DARK, x + 1, thumb_y + track - 1, x + w, thumb_y + track - 1, x + w, thumb_y + 1)
	PsxDraw.line3(canvas, LIGHT, x + w, thumb_y, x + 1, thumb_y, x + 1, thumb_y + track - 2)
	PsxDraw.line3(canvas, LIGHT, x, y + h + 1, x + w + 1, y + h + 1, x + w + 1, y + 1)
	PsxDraw.line3(canvas, DARK, x + w + 1, y, x, y, x, y + h)


## renderItemMenuItemList: the names from the text area, the icons (the previous top row while the
## page is drawn): mode 0 item icons, 1 card icons (+2, +2), 2 none.
func _render_rows(canvas: CanvasItem, box: ListBox, x1: int, y1: int, x2: int, y2: int, mode: int) -> void:
	var e: TextBoxes.Entry = textboxes.entries[box.box_id]
	var coords := TextBoxes.vram_mode_coords(e.vram_mode)
	var tex_y := e.back_page * e.vram_rows * TextBoxes.ROW_HEIGHT
	var count := mini(box.item_count - box.top_row, box.visible_rows)
	for i in range(count - 1, -1, -1):
		if box.item(box.top_row + i) != 0xFF:
			text_area.render_string(canvas, 0, x1, y1 + i * 0x12, coords[1], 0xC, coords[0],
					tex_y + box.item_row[i] * TextBoxes.ROW_HEIGHT, true)
	if mode == 2:
		return
	var top := box.prev_top_row if _busy else box.top_row
	count = mini(box.item_count - top, box.visible_rows)
	for i in range(count - 1, -1, -1):
		var item := box.item(top + i)
		if item == 0xFF:
			continue
		if mode == 0:
			MenuDraw.item_icon(canvas, data.item(item), x2, y2 + i * 0x12)
		else:
			_card_icon(canvas, item, x2 + 2, y2 + i * 0x12 + 2)


# --- the amount box (box 3: createItemMenuAmountBox, tickItemMenuAmountBox) ---------------------

## updateItemMenuSubTextboxLine: box 0's back-page rows.
func _sub_line() -> void:
	var e: TextBoxes.Entry = textboxes.entries[0]
	sub_line = (e.back_page ^ 1) * e.vram_rows


## createItemMenuAmountBox: true when the box opened (sound 3), else sound 0xB.
func create_amount(origin: Rect2i) -> bool:
	var box := current_box()
	var row := box.top_row + box.cursor
	item_type = box.item(row)
	if item_type == 0xFF:
		_sound(0xB)
		return false
	var second := box.second(row)
	item_price = _price(item_type)
	if type >= TYPE_CARD_BUY:
		item_price = card_price(item_type) >> 1
		max_amount = second
	elif type == TYPE_SELL:
		if second & 0x80 == 0:
			_sound(0xB)
			return false
		item_price >>= 1
		max_amount = second & 0x7F
	else:
		if type == TYPE_BUY:
			if second == 0:
				_sound(0xB)
				return false
			max_amount = 0x63
		else:
			if second & 0x80 == 0:
				_sound(0xB)
				return false
			max_amount = second & 0x7F
		var room: int = (0x63 - game_state.item_count(item_type)) & 0xFF
		if room < max_amount:
			max_amount = room
		if item_price > 0 and max_amount * item_price > money():
			max_amount = money() / item_price
	amount = 1
	_sub_line()
	textboxes.create_textbox(SUB_BOX, 0xC1, Rect2i(-0x41, -0x2A, 0x82, 0x53), origin, tick_amount, render_amount)
	textboxes.register_textbox(SUB_BOX, sub_line, 1, 0, 0)
	_amount_string()
	_sound(3)
	return true


## updateItemMenuAmountBoxString (US): name, 18 price, 19 amount, 1A total.
func _amount_string() -> void:
	var at := sub_line * textboxes.line_size
	at = _put(at, _name_bytes(item_type) if type < TYPE_CARD_BUY else _card_name_bytes(item_type))
	at = _put(at, [0x18, 0])
	at = _put(at, TextBoxes.int_to_string_sjis(item_price, 5, 0))
	at = _put(at, [0x19, 0])
	at = _put(at, TextBoxes.int_to_string_sjis(amount, 2, 0))
	at = _put(at, [0x1A, 0])
	at = _put(at, TextBoxes.int_to_string_sjis(mini(item_price * amount, MONEY_MAX), 6, 0))
	_put(at, [0, 0])
	var e: TextBoxes.Entry = textboxes.entries[SUB_BOX]
	e.page_ready = 1
	e.write_count += 1


## tickItemMenuAmountBox (script_common.c:1457).
func tick_amount(_id: int) -> void:
	if boxes.boxes[SUB_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	if amount != max_amount and pad.is_key_down(Pad.UP):
		if pad.polled & Pad.ALT:
			amount += 10
			if amount > max_amount:
				amount -= 10
		else:
			amount += 1
		_sound(2)
		_amount_string()
		return
	if amount != 1 and pad.is_key_down(Pad.DOWN):
		if pad.polled & Pad.ALT:
			var q := amount - 10
			if q <= 0:
				q += 10
			amount = q
		else:
			amount -= 1
		_sound(2)
		_amount_string()
		return
	if pad.is_key_down(Pad.CANCEL):
		textboxes.trigger_box_close_flag(SUB_BOX)
		_sound(4)
	elif pad.is_key_down(Pad.SQUARE):
		amount = max_amount
		_sound(3)
	elif pad.is_key_down(Pad.CONFIRM):
		var owner := ScriptContext.OWNER_TAMER
		if type >= TYPE_CARD_BUY:
			game_state.state["money"] = mini(money() + amount * item_price, MONEY_MAX)
			game_state.set_card_count(item_type, game_state.card_count(item_type) - amount)
			owner = ctx.read_pstat(0xFE)
		elif type == TYPE_SELL:
			game_state.state["money"] = mini(money() + amount * item_price, MONEY_MAX)
			game_state.remove_item(item_type, amount)
			owner = ctx.read_pstat(0xFE)
		else:
			var unit := item_price
			if is_partner_baby():
				unit = unit * 90 / 100
				ctx.shop_variable = amount * (item_price - unit)
			game_state.state["money"] = money() - amount * unit
			game_state.give_item(item_type, amount)
			if type == TYPE_RECYCLE:
				var slot := recycle_id(item_type)
				var stock: Array = game_state.state["script"]["recycle_stock"]
				if slot < stock.size():
					stock[slot] = int(stock[slot]) - amount
		game_state.changed.emit("money")
		ctx.state_2 = 7 if type < TYPE_CARD_BUY else 4
		textboxes.trigger_box_close_flag(SUB_BOX)
		textboxes.close_textbox(SUB_BOX, _origin(owner))
		update_bits_box = true
		savannah_sound()
	_amount_string()


## renderItemMenuAmountBox (US).
func render_amount(canvas: CanvasItem, _id: int) -> void:
	var b: UIBoxes.Box = boxes.boxes[SUB_BOX]
	var x := b.final.position.x
	var y := b.final.position.y
	var row_px := textboxes.entries[SUB_BOX].vram_row * TextBoxes.ROW_HEIGHT
	var col := 0
	var parts := []
	for f in AMOUNT_LAYOUT:
		parts.append([f[0], f[1], f[2], col])
		col += f[2]
	for k in range(parts.size() - 1, -1, -1):
		var p: Array = parts[k]
		text_area.render_string(canvas, 0, p[0] + x, p[1] + y, p[2] * GLYPH_WIDTH, 0xC, p[3] * GLYPH_WIDTH, row_px, true)
	if type < TYPE_CARD_BUY:
		MenuDraw.item_icon(canvas, data.item(item_type), x + 8, y + 5)
	else:
		_card_icon(canvas, item_type, x + 8 + 2, y + 5 + 2)
	_inset_without_box(canvas, x + 0x55, y + 0x2A, 0x1A, 0xE)
	_horizontal_line(canvas, x + 0xC, y + 0x3C, 0x6A)
	_horizontal_line(canvas, x + 4, y + 0x17, 0x7A)


## renderHorizontalLine: dark, light, dark (box coordinates already added).
func _horizontal_line(canvas: CanvasItem, x: int, y: int, w: int) -> void:
	PsxDraw.line2(canvas, DARK, x, y + 2, x + w - 1, y + 2)
	PsxDraw.line2(canvas, LIGHT, x, y + 1, x + w - 1, y + 1)
	PsxDraw.line2(canvas, DARK, x, y, x + w - 1, y)


## renderInsetWithoutBox.
func _inset_without_box(canvas: CanvasItem, x: int, y: int, w: int, h: int) -> void:
	PsxDraw.line3(canvas, DARK, x + w - 1, y, x, y, x, y + h - 1)
	PsxDraw.line3(canvas, LIGHT, x + 1, y + h - 1, x + w - 1, y + h - 1, x + w - 1, y)


# --- "Is it OK? Yes No" (box 3: createSingleCardShopMenu, tickSingleCardShop) --------------------

func create_confirm(origin: Rect2i) -> bool:
	var box := current_box()
	var row := box.top_row + box.cursor
	item_type = box.item(row)
	var second := box.second(row)
	if item_type == 0xFF or (second & 0x80 == 0 if type == TYPE_PICK else second == 0):
		_sound(0xB)
		return false
	_sub_line()
	textboxes.create_textbox(SUB_BOX, 0xC1, Rect2i(-0x38, -0x15, 0x70, 0x2A), origin, tick_confirm, render_confirm)
	textboxes.register_textbox(SUB_BOX, sub_line, 2, 0, 0)
	textboxes.show_maphead_textbox(0, ScriptContext.OWNER_NONE, SUB_BOX, CONFIRM_SECTION)
	amount = 0
	_sound(3)
	return true


func tick_confirm(_id: int) -> void:
	if boxes.boxes[SUB_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	if pad.is_key_down(Pad.CANCEL):
		textboxes.trigger_box_close_flag(SUB_BOX)
		_sound(4)
	elif pad.is_key_down(Pad.LEFT):
		amount = 0
		_sound(2)
	elif pad.is_key_down(Pad.RIGHT):
		amount = 1
		_sound(2)
	elif pad.is_key_down(Pad.CONFIRM):
		textboxes.trigger_box_close_flag(SUB_BOX)
		if amount == 0:
			if type != TYPE_PICK:
				# A single card bought: its slot is emptied (smth[cursor]: the 6 rows are all shown).
				game_state.set_card_count(item_type, game_state.card_count(item_type) + 1)
				game_state.state["money"] = money() - card_price(item_type)
				game_state.state["script"]["card_shop"][current_box().cursor] = null
				game_state.changed.emit("money")
				update_bits_box = true
				ctx.state_2 = 4
				savannah_sound()
			else:
				game_state.set_script_value(0xFE, item_type)
				game_state.clear_trigger(TRIGGER_PICK)
				ctx.state_2 = 4
				_sound(3)
		else:
			_sound(4)


func render_confirm(canvas: CanvasItem, _id: int) -> void:
	var b: UIBoxes.Box = boxes.boxes[SUB_BOX]
	var x := b.final.position.x + 4
	var y := b.final.position.y + 3
	var row_px := textboxes.entries[SUB_BOX].vram_row * TextBoxes.ROW_HEIGHT
	PsxDraw.selection_cursor(canvas, x + 8 + amount * 47, y + 0x12, 0x28, 0xE)
	for k in range(CONFIRM_LAYOUT.size() - 1, -1, -1):
		var e: Array = CONFIRM_LAYOUT[k]
		text_area.render_string(canvas, 0, x + e[2], y + e[3], e[4], 0xC, e[0], row_px + e[1], true)


# --- the description (box 3: createItemMenuDescriptionBox) -------------------------------------------

func create_description(box: ListBox, origin: Rect2i) -> bool:
	var item := box.item(box.top_row + box.cursor)
	if item == 0xFF:
		return false
	_sub_line()
	textboxes.create_textbox(SUB_BOX, 0xC1, Rect2i(-0x84, -0xB, 0x108, 0x16), origin, tick_description,
			render_description)
	textboxes.register_textbox(SUB_BOX, sub_line, 1, 0, 0)
	var at := sub_line * textboxes.line_size
	at = _put(at, text_area.font.to_bytes(data.localize(data.item(item).get("description"))))
	_put(at, [0, 0])
	var e: TextBoxes.Entry = textboxes.entries[SUB_BOX]
	e.page_ready = 1
	e.write_count += 1
	return true


func tick_description(_id: int) -> void:
	if boxes.boxes[SUB_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	if not pad.is_key_down(Pad.CONFIRM | Pad.CANCEL | Pad.START):
		return
	textboxes.trigger_box_close_flag(SUB_BOX)
	_sound(3)


func render_description(canvas: CanvasItem, _id: int) -> void:
	var b: UIBoxes.Box = boxes.boxes[SUB_BOX]
	var row_px := textboxes.entries[SUB_BOX].vram_row * TextBoxes.ROW_HEIGHT
	text_area.render_string(canvas, 0, b.final.position.x + 6, b.final.position.y + 5, 0xFC, 0xC, 0, row_px, true)


# --- the bits box (box 2: createShopBitsBox, tickShopBitsBox, renderShopBitsBox) --------------------

func create_bits_box(bits: bool) -> void:
	show_bits = bits
	update_bits_box = true
	if boxes.boxes[BITS_BOX].state == UIBoxes.STATE_OPEN:
		return
	textboxes.create_textbox(BITS_BOX, 0xE1, Rect2i(-0x98, -0x62, 0x52, 0x21), _origin(ScriptContext.OWNER_TAMER),
			tick_bits_box, render_bits_box)
	textboxes.register_textbox(BITS_BOX, 8, 1, 0, 0)
	tick_bits_box()


func tick_bits_box(_id := 0) -> void:
	if not update_bits_box:
		return
	update_bits_box = false
	var saved := ctx.active_instruction
	textboxes.show_maphead_textbox(6 if show_bits else 7, ScriptContext.OWNER_NONE, BITS_BOX)
	ctx.active_instruction = saved


func render_bits_box(canvas: CanvasItem, _id: int) -> void:
	var b: UIBoxes.Box = boxes.boxes[BITS_BOX]
	var row_px := textboxes.entries[BITS_BOX].vram_row * TextBoxes.ROW_HEIGHT
	var x := b.final.position.x + 6
	var y := b.final.position.y + 4
	text_area.render_string(canvas, 0, x + 0x10, y + 0xD, 0x3C, 0xC, 0x30, row_px, true)
	text_area.render_string(canvas, 0, x + 0x10, y, 0x30, 0xC, 0, row_px, true)
