class_name TradeMenu
extends RefCounted
## Mojyamon's trade box (box 1; mojyaTradeFillItemList, createMojyaTradeMenu, tickMojyaTradeMenu,
## renderMojyaTradeMenu, updateMojyaTradeStrings, shop/script_menu.c:1758-1799, :2547-2656;
## calculateItemListStrings, script_common.c; specs/card_shops.md §2.6) on the item menu's two
## lists: left the items Mojyamon wants (| 0x80 when held), right what he gives for them.

const MOJYA_SECTION := 0x4D6
## The trade rows' first text row (initItemMenuBox(LEFT, 1, 0xA)); row 9 is the label's.
const START_ROW := 0xA
const LABEL_ROW := 9
## MOJYA_LABEL_END (US): where updateMojyaTradeStrings ends rows 9 and 13 with 0x0D.
const LABEL_END := 20
## The traded triggers: set × 3 + row + 5; all of 5-13 set → 14.
const TRADED_TRIGGER := 5
const ALL_TRADED_TRIGGER := 0xE
## padWithSpaces(out, 8, len) (US): 8 - len / 2 full-width spaces after the give item (len in bytes).
const NAME_WIDTH := 8
## TRADE_LABEL (US "You have Will trade"), drawn over row 9 each frame.
const LABEL := "MAIN_D_801307CC"
const PSTAT_PICKED := 249
const NOTHING_PICKED := 0xFF

var menu: ItemMenu
var textboxes: TextBoxes
var ctx: ScriptContext
var game_state: Node
var data: Node
## ITEM_MENU_TYPE as mojyaTradeFillItemList sets it (the set × 3), kept apart from the list type.
var trade_base := 0


func _init(item_menu: ItemMenu) -> void:
	menu = item_menu
	textboxes = menu.textboxes
	ctx = menu.ctx
	game_state = menu.game_state
	data = menu.data
	menu.row_writers[ItemMenu.STYLE_TRADE] = _row


## mojyaTradeFillItemList: the set's trades (systems/mojyamon_trades; the C always lists 3 rows, a
## set's unused slots are left out of the table).
func fill(trade_set: int) -> void:
	trade_base = trade_set * 3
	var trades: Array = []
	for record in data.system("mojyamon_trades"):
		if int(record.get("set", -1)) == trade_set:
			trades = record.get("trades", [])
	menu.left.buf = PackedByteArray()
	menu.right.buf = PackedByteArray()
	for trade in trades:
		var give := int(trade["give"]["id"])
		menu.left.buf.append_array([give | 0x80 if game_state.item_count(give) != 0 else give, 0])
		menu.right.buf.append_array([int(trade["get"]["id"]), 0])
	menu.left.item_count = trades.size()
	menu.right.item_count = trades.size()


## The trade of a row (the left list's top row + row): its traded trigger.
func traded_trigger(row: int) -> int:
	return trade_base + menu.left.top_row + row + TRADED_TRIGGER


## setMojyaItemTradedTrigger.
func set_traded() -> void:
	game_state.set_trigger(traded_trigger(menu.left.cursor))
	for t in range(TRADED_TRIGGER, ALL_TRADED_TRIGGER):
		if not game_state.is_trigger_set(t):
			return
	game_state.set_trigger(ALL_TRADED_TRIGGER)


## createMojyaTradeMenu.
func create() -> void:
	textboxes.create_textbox(ItemMenu.LIST_BOX, 0xE1, Rect2i(-88, -80, 223, 83), menu._origin(ctx.read_pstat(0xFE)),
			tick, render)
	textboxes.register_textbox(ItemMenu.LIST_BOX, LABEL_ROW, 4, 1, 0)
	menu._init_box(menu.left, ItemMenu.LIST_BOX, START_ROW)
	update_strings()


## updateMojyaTradeStrings: the JP label line in box 1 (its write taken back; nothing draws it in
## US, the label is drawn over it), then the rows.
func update_strings() -> void:
	textboxes.show_maphead_textbox(0xF, ScriptContext.OWNER_NONE, ItemMenu.LIST_BOX, MOJYA_SECTION)
	textboxes.entries[ItemMenu.LIST_BOX].write_count -= 1
	for row in [LABEL_ROW, LABEL_ROW + 4]:
		var at: int = row * textboxes.line_size + LABEL_END
		if at < textboxes.lines.size():
			textboxes.lines[at] = 0xD
	menu.update_strings(menu.left, START_ROW, ItemMenu.STYLE_TRADE)


## calculateItemListStrings (US): "－" when traded, the give item (red when not held) padded to 8,
## the get item.
func _row(box: ItemMenu.ListBox, row: int, last: bool) -> void:
	var at := menu._line(box, row)
	at = menu._put(at, [1, 7])
	at = menu._put(at, [0x81, 0x7C] if game_state.is_trigger_set(traded_trigger(row)) else [0x81, 0x40])
	var index := box.top_row + row
	var give := menu.left.item(index)
	at = menu._put(at, [1, 1 if give & 0x80 else 3])
	var name := menu._name_bytes(give & 0x7F)
	at = menu._put(at, name)
	# The US loop never ends past 16 bytes (`used` < 0): the port pads nothing then.
	for i in maxi(NAME_WIDTH - (name.size() >> 1), 0):
		at = menu._put(at, [0x81, 0x40])
	at = menu._put(at, [0xF, 0, 1, 1])
	at = menu._put(at, menu._name_bytes(menu.right.item(index)))
	menu._terminate(at, last)


## tickMojyaTradeMenu (its own page flip: the render draws no icons, so never flips).
func tick(_id: int) -> void:
	var box := menu.left
	if menu.is_busy(box):
		return
	var boxes := menu.boxes
	if boxes.boxes[0].state != UIBoxes.STATE_OPEN or boxes.boxes[ItemMenu.LIST_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	if ctx.read_pstat(PSTAT_PICKED) != NOTHING_PICKED:
		return
	var pad := menu.pad
	if pad.is_key_down(Pad.CONFIRM):
		var item := box.item(box.top_row + box.cursor)
		if item & 0x80:
			game_state.set_script_value(PSTAT_PICKED, item & 0x7F)
			textboxes.show_maphead_textbox(0xB, ctx.read_pstat(0xFE), 0, MOJYA_SECTION)
			ctx.state_2 = 1
			ctx.next_state_2 = 4
			ctx.textbox_mode = 1
			menu._sound(3)
		else:
			menu._sound(0xB)
	elif pad.is_key_down(Pad.CANCEL):
		ctx.state_2 = 6
		menu._sound(4)
	elif pad.is_key_down(Pad.UP):
		if pad.polled & Pad.R1:
			_move_to(0, 0)
		else:
			menu.cursor_up(box, ItemMenu.STYLE_TRADE)
	elif pad.is_key_down(Pad.DOWN):
		if pad.polled & Pad.R1:
			var diff := box.item_count - box.visible_rows
			if diff <= 0:
				_move_to(0, box.item_count - 1)
			else:
				_move_to(diff, box.visible_rows - 1)
		else:
			menu.cursor_down(box, ItemMenu.STYLE_TRADE)


## itemMenuCursorMoveToTop / …MoveToBottom, then updateMojyaTradeStrings.
func _move_to(top_row: int, cursor: int) -> void:
	var box := menu.left
	box.prev_top_row = box.top_row
	box.prev_cursor = box.cursor
	box.top_row = top_row
	box.cursor = cursor
	menu._sound(2)
	update_strings()


## renderMojyaTradeMenu (US), in reverse of the C's adds (the cursor over them, as the item menu's).
func render(canvas: CanvasItem, _id: int) -> void:
	var box := menu.left
	if box == null:
		return
	var b: UIBoxes.Box = menu.boxes.boxes[ItemMenu.LIST_BOX]
	var bx := b.final.position.x
	var by := b.final.position.y
	menu._render_rows(canvas, box, bx + 8, by + 0x1B, 0, 0, 2)
	var e: TextBoxes.Entry = textboxes.entries[box.box_id]
	var coords := TextBoxes.vram_mode_coords(e.vram_mode)
	var y: int = LABEL_ROW * TextBoxes.ROW_HEIGHT + e.back_page * e.vram_rows * TextBoxes.ROW_HEIGHT
	menu.text_area.draw_string(data.text(LABEL), coords[0], y)
	menu.text_area.render_string(canvas, 0, bx + 0x7A, by + 5, 0x4E, 0xC, coords[0] + 0x42, y, true)
	menu.text_area.render_string(canvas, 0, bx + 0x14, by + 5, 0x42, 0xC, coords[0], y, true)
	menu._horizontal_line(canvas, bx + 4, by + 0x15, 0xD7)
	PsxDraw.selection_cursor(canvas, bx + 5, by + box.cursor * 0x12 + 0x19, 0xD4, 0x12)
