class_name FishingWindows
extends RefCounted
## The contents of fishing's two windows (specs/fishing.md §2.9; step F5): the text box (box 2,
## FISH_showTextBox's text-area rows and FISH_renderTextBox) and the bait menu (box 3,
## FISH_drawBaitMenuRow and FISH_renderBaitMenu). The logic (FishingTextBox, FishingBaitMenu) holds
## the state; these draw it on the UI boxes' canvas.

## BI_IN.TIM palette 4 (page (896, 256), CLUT (256, 484), image from v 0x80): the "×" at (0x80, 0x9C),
## 8 × 8 (fish.c:1290-1294), and renderItemAmount's digits (Inventory.DIGITS).
const BI_IN := "etctim/00_bi_in.p4.png"
const BI_IN_V := 0x80
const TIMES_UV := Rect2(0x80, 0x9C - 0x80, 8, 8)
const DIGIT_U := 0x89
const DIGIT_ROW := 0x9C - 0x80
const CENTRE := Vector2(160, 120)
## FISH_renderBaitMenu's columns (fish.c:1283-1300): icon, name, "×", count; the cursor 144 apart.
const ICON_X: Array[int] = [8, 0x98]
const NAME_X: Array[int] = [0x1B, 0xAB]
const TIMES_X: Array[int] = [0x7D, 0x10D]
const AMOUNT_X: Array[int] = [0x86, 0x116]
const ROW_HEIGHT := 0x12
const NAME_WIDTH := 0x60
const LINE_HEIGHT := 0xC

var boxes: UIBoxes
var text_area: TextArea
var data: Node
var game_state: Node
var text_box: FishingTextBox
var bait_menu: FishingBaitMenu
## Kept: a texture made inside _draw and dropped is freed before the canvas renders it.
var _bi_in: Texture2D


# --- The text box --------------------------------------------------------------------------------

## FISH_showTextBox's text (fish.c:1518-1527): the whole text area cleared, the lines at rows 0, 12,
## 24, 36.
func draw_text_lines() -> void:
	if text_area == null:
		return
	text_area.clear(Rect2i(0, 0, 256, 256))
	for i in FishingTextBox.LINES:
		if text_box.lines[i] != "":
			text_area.draw_string(text_box.lines[i], 0, i * LINE_HEIGHT)


## FISH_renderTextBox (fish.c:1476): the lines, shadowed.
func render_text_box(canvas: CanvasItem, id: int) -> void:
	if not text_box.shown or text_area == null:
		return
	var b: UIBoxes.Box = boxes.boxes[id]
	for i in FishingTextBox.LINES:
		if text_box.lines[i] != "":
			text_area.render_string(canvas, 0, b.final.position.x + 5, b.final.position.y + i * 13 + 3, 0xFF, LINE_HEIGHT,
					0, i * LINE_HEIGHT, true)


## renderUIBox (script_textbox.c:996): the "next" arrow from TEXTBOX_OPEN_TIMER.
func on_render_text_box(id: int) -> void:
	if text_box.shown:
		boxes.show_next_arrow(id, text_box.open_timer)


# --- The bait menu -------------------------------------------------------------------------------

## FISH_openBaitMenu's text (fish.c:1357-1361) and the scroll bar's rows (:1369-1374), before the box
## opens.
func prepare_bait_menu() -> void:
	if text_area != null:
		text_area.clear(Rect2i(0, 0, 256, 256))
		for row in bait_menu.visible_rows:
			draw_bait_row(row)
	var b: UIBoxes.Box = boxes.boxes[FishingBaitMenu.BOX_ID]
	if bait_menu.total_rows > bait_menu.visible_rows:
		b.row_offset = bait_menu.row_offset
		b.visible_rows = bait_menu.visible_rows
		b.total_rows = bait_menu.total_rows


## FISH_drawBaitMenuRow (fish.c:1225): a row's two names into the text area.
func draw_bait_row(row: int) -> void:
	if text_area == null:
		return
	for i in FishingBaitMenu.COLUMNS:
		var slot := _slot(row * 2 + i)
		if slot < 0:
			continue
		var item := _item_at(slot)
		if item < 0:
			continue
		var rect := Rect2i(i * NAME_WIDTH, (row % bait_menu.visible_rows) * LINE_HEIGHT, NAME_WIDTH, LINE_HEIGHT)
		text_area.clear(rect)
		text_area.draw_string(data.localize(data.item(item).get("name", {})), rect.position.x, rect.position.y)


## FISH_renderBaitMenu's drawing (fish.c:1248-1307).
func render_bait_menu(canvas: CanvasItem, id: int) -> void:
	if not bait_menu.shown:
		return
	var b: UIBoxes.Box = boxes.boxes[id]
	var x := b.final.position.x
	var y := b.final.position.y
	for row in bait_menu.visible_rows:
		for col in FishingBaitMenu.COLUMNS:
			var r := row + bait_menu.row_offset
			var slot := _slot(col + r * 2)
			if slot < 0:
				continue
			var item := _item_at(slot)
			if item < 0:
				continue
			MenuDraw.item_icon(canvas, data.item(item), x + ICON_X[col], y + 0xE + row * ROW_HEIGHT)
			if text_area != null:
				text_area.render_string(canvas, 0, x + NAME_X[col], y + 0x10 + row * ROW_HEIGHT, NAME_WIDTH, LINE_HEIGHT,
						col * NAME_WIDTH, (r % bait_menu.visible_rows) * LINE_HEIGHT, true)
			var tex := _bi_in_texture()
			if tex != null:
				canvas.draw_texture_rect_region(tex, Rect2(CENTRE + Vector2(x + TIMES_X[col], y + 0x14 + row * ROW_HEIGHT), TIMES_UV.size),
						TIMES_UV)
			_amount(canvas, _amount_at(slot), x + AMOUNT_X[col], y + 0x12 + row * ROW_HEIGHT)
	PsxDraw.selection_cursor(canvas, x + 6 + bait_menu.column * 144, y + 0xD + (bait_menu.cursor_row - bait_menu.row_offset) * 18,
			0x8E, 0x12)


## The rest of FISH_renderBaitMenu (fish.c:1309-1315), once per game frame: the scroll bar's row
## and the row a scroll uncovered, drawn into the text area.
func on_render_bait_menu(id: int) -> void:
	if not bait_menu.shown:
		return
	if bait_menu.total_rows > bait_menu.visible_rows:
		boxes.boxes[id].row_offset = bait_menu.row_offset
		if bait_menu.last_row != -1:
			draw_bait_row(bait_menu.last_row)
			bait_menu.last_row = -1


func _slot(index: int) -> int:
	return bait_menu.items[index] if index >= 0 and index < bait_menu.items.size() else -1


func _item_at(slot: int) -> int:
	var slots: Array = game_state.state["inventory"]["slots"]
	if slot < 0 or slot >= slots.size() or slots[slot] == null:
		return -1
	return data.id_of("items/item_data", slots[slot]["item"])


func _amount_at(slot: int) -> int:
	var slots: Array = game_state.state["inventory"]["slots"]
	return int(slots[slot]["amount"]) if slot >= 0 and slot < slots.size() and slots[slot] != null else 0


func _bi_in_texture() -> Texture2D:
	if _bi_in == null:
		_bi_in = Content.load_texture(BI_IN)
	return _bi_in


## renderItemAmount(0, 2, ...): two digits, right-aligned, no leading zeros (as Inventory._amount).
func _amount(canvas: CanvasItem, value: int, x: int, y: int) -> void:
	var tex := _bi_in_texture()
	if tex == null:
		return
	var digits := GameMenu.date_digits(value, 2)
	var first := 2 - digits.size()
	for k in digits.size():
		var d: int = digits[k]
		canvas.draw_texture_rect_region(tex, Rect2(CENTRE + Vector2(x + (first + k) * 6, y), Vector2(6, 10)),
				Rect2(DIGIT_U + d * 6, DIGIT_ROW, 6, 10))
