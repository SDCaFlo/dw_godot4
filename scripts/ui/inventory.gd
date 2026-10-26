class_name Inventory
extends Node
## The inventory (inventory.c; specs/inventory.md §2.1-2.6): the inventory object (tickInventoryUI)
## and its four boxes: the list (box 0), the description (1), Use / Move / Sort / Drop (2), sorting
## or the drop question (3). The root of scenes/ui/inventory.tscn, opened from the △ menu and ticked
## by the MenuHost. What an item can do is ItemUse's: the list only asks it (the grey options) and
## hands the item over (`use_item`).

## △ on the list: back to the △ menu (closeTriangleMenu + addGameMenu).
signal back
## Use: the hand-over to the partner (startFeedingItem).
signal use_item(item: String)

const CENTRE := Vector2(160, 120)
## renderItemAmount's digits (setEntityTextDigit: page 0x1E, palette (256, 484)): BI_IN.TIM, p4,
## UV (d * 6 + 0x89, 0x9C) = image (d * 6 + 0x89, 28), 6 x 10.
const DIGITS := "etctim/00_bi_in.p4.png"
const DIGIT_U := 0x89
const DIGIT_ROW := 0x9C - 0x80
## INVENTORY_ACTION values (tickInventoryUI).
const ACTION_NONE := 0
const ACTION_VIEW := 1
const ACTION_BACK := 2
const ACTION_OPTIONS := 3
const ACTION_CLOSE_OPTIONS := 4
const ACTION_USE := 5
const ACTION_MOVE := 6
const ACTION_DROP := 7
const ACTION_SORT := 8
const ACTION_CLOSE_SORT := 9
const ACTION_SORTED := 11
const ACTION_DROP_ASK := 14
const ACTION_CLOSE_DROP := 15
## The options of box 2 (ITEM_MENU_LABELS).
const OPTION_USE := 0
const OPTION_MOVE := 1
const OPTION_SORT := 2
const OPTION_DROP := 3
## isInventoryButtonPressed: a button held this many frames repeats every frame.
const REPEAT_FRAMES := 0xB
## The move source's frame colour (drawLine3P 0x5D4AF1).
const MOVE_FRAME := 0x5D4AF1
## Text-area rows (drawInventoryText, updateItemDescription, the boxes' strings).
const LABELS_U := 0xC0
const DESCRIPTION := Rect2i(0, 0xB4, 0xFC, 0xC)
const TEXT_LABELS := ["STR_ITEM_MENU_LABEL_USE", "STR_ITEM_MENU_LABEL_MOVE", "STR_ITEM_MENU_LABEL_SORT",
		"STR_ITEM_MENU_LABEL_DROP"]

## Set by the host.
var boxes: UIBoxes
var text_area: TextArea
var tamer: Tamer
var game_state: Node
var data: Node
var item_use: ItemUse
var pad: Pad
var sound: Node

## IS_INVENTORY_INITIALIZED: the object exists.
var active := false
var action := ACTION_NONE
## INVENTORY_POINTER, INVENTORY_TYPE_OFFSET (rows scrolled), ITEM_MOVE_SOURCE.
var pointer := 0
var row_offset := 0
var move_source := 0
## ITEM_MENU_SELECTED, SORT_SELECTED, DROP_ITEM_SELECTED_OPTION.
var option := 0
var sort_selected := 0
var drop_option := 1
## INVENTORY.names[slot]: the text-area cell holding the slot's name (drawInventoryText).
var names: Array = []
## ITEM_MOVE_TARGET as renderInventoryBottom uses it: the slot whose description is drawn.
var _description_slot := -1
var _repeat := 0
var _digits: Texture2D


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")
	if sound == null:
		sound = get_node_or_null("/root/Sound")


# --- the slots -------------------------------------------------------------------------------------

func size() -> int:
	return int(game_state.state["inventory"]["size"])


func _slots() -> Array:
	return game_state.state["inventory"]["slots"]


## The item key in a slot, "" when empty.
func item_at(slot: int) -> String:
	var s = _slots()[slot] if slot >= 0 and slot < _slots().size() else null
	return str(s["item"]) if s != null else ""


func _amount_at(slot: int) -> int:
	var s = _slots()[slot]
	return int(s["amount"]) if s != null else 0


## Swaps two slots with their name cells (moveItem, sortItems' swapByte).
func _swap(a: int, b: int) -> void:
	var slots := _slots()
	var t = slots[a]
	slots[a] = slots[b]
	slots[b] = t
	var n = names[a]
	names[a] = names[b]
	names[b] = n
	game_state.changed.emit("inventory")


# --- drawInventoryText (inventory.c:255) -------------------------------------------------------

func draw_text() -> void:
	names.resize(size())
	text_area.clear_all()
	for slot in size():
		names[slot] = slot
		if item_at(slot) != "":
			text_area.draw_string(_item_name(item_at(slot)), (slot & 1) * 0x60, (slot / 2) * 0xC)
	for i in 4:
		text_area.draw_string(data.text(TEXT_LABELS[i]), LABELS_U, i * 12)


func _item_name(item: String) -> String:
	return data.localize(data.item(item).get("name")).strip_edges()


# --- addInventoryUI / tickInventoryUI (inventory.c:324, :336) ------------------------------------

## addInventoryUI: box 0 free and the tamer holding nothing.
func open() -> void:
	if not active and boxes.boxes[0].state == UIBoxes.STATE_CLOSED and (tamer == null or tamer.held_item == ""):
		active = true
		action = ACTION_VIEW


func tick() -> void:
	if not active:
		return
	var pressed := pad.polled & ~pad.polled_previous
	var b := boxes.boxes
	if pressed & Pad.CONFIRM:
		if b[3].state == UIBoxes.STATE_OPEN:
			if option == OPTION_SORT:
				_select_sorting()
			else:
				action = ACTION_DROP if drop_option == 0 else ACTION_CLOSE_DROP
		elif b[2].state == UIBoxes.STATE_OPEN:
			_select_option()
		else:
			_select_list()
	if pressed & Pad.CANCEL:
		if b[3].state == UIBoxes.STATE_OPEN:
			action = ACTION_CLOSE_SORT if option == OPTION_SORT else ACTION_CLOSE_DROP
		elif b[2].state == UIBoxes.STATE_CLOSED:
			if b[0].state == UIBoxes.STATE_MENU:
				_play_sound(3)
				b[0].state = UIBoxes.STATE_OPEN
				action = ACTION_NONE
			elif b[1].state == UIBoxes.STATE_OPEN:
				action = ACTION_BACK
		elif b[2].state == UIBoxes.STATE_OPEN:
			action = ACTION_CLOSE_OPTIONS
	match action:
		ACTION_VIEW:
			_create_view()
			if tamer != null and tamer.animation_id() != 4:
				tamer.play_scene_animation(4)
		ACTION_BACK:
			_close_view()
			if b[0].frame == 0:
				if tamer != null:
					tamer.start_animation(0)
				back.emit()
		ACTION_OPTIONS:
			_create_options()
		ACTION_CLOSE_OPTIONS, ACTION_MOVE:
			_close_box2()
		ACTION_USE:
			if _close_box2():
				_close_view()
			if b[0].state == UIBoxes.STATE_CLOSED:
				action = ACTION_NONE
				use_item.emit(item_at(pointer))
		ACTION_DROP:
			if b[3].state != UIBoxes.STATE_CLOSED:
				_close_box3()
			elif b[2].state != UIBoxes.STATE_CLOSED:
				_close_box2()
			else:
				action = ACTION_NONE
				game_state.remove_item(item_at(pointer), _amount_at(pointer))
		ACTION_SORT:
			_create_sort()
		ACTION_CLOSE_SORT, ACTION_CLOSE_DROP:
			_close_box3()
		ACTION_SORTED, ACTION_SORTED + 1, ACTION_SORTED + 2:
			if b[3].state != UIBoxes.STATE_CLOSED:
				_close_box3()
			elif b[2].state != UIBoxes.STATE_CLOSED:
				_close_box2()
			else:
				action = ACTION_NONE
		ACTION_DROP_ASK:
			_create_drop_question()


## closeInventoryBoxes (inventory.c:463): every box goes at once, the object too.
func close_all() -> void:
	if not active:
		return
	active = false
	action = ACTION_NONE
	for i in 4:
		if boxes.boxes[i].state != UIBoxes.STATE_CLOSED:
			boxes.remove_static(i)


## closeInventoryBoxes2 (inventory.c:651): the description shrinks into the cell, then the list into
## the tamer; once the list is gone, closeInventoryBoxes.
func _close_view() -> void:
	var b := boxes.boxes
	if b[0].frame == 0:
		close_all()
		return
	if b[1].state == UIBoxes.STATE_OPEN:
		boxes.remove_animated(1, Rect2i(_cell_x() + 3, b[0].final.position.y + 8 + _row() * 0x12, 0x10, 0x10))
	if b[1].frame <= 0 and b[0].state == UIBoxes.STATE_OPEN:
		boxes.remove_animated(0, _tamer_rect())


## removeUIBox2: true once box 2 is free.
func _close_box2() -> bool:
	var b: UIBoxes.Box = boxes.boxes[2]
	if b.frame == 0:
		return true
	if b.state == UIBoxes.STATE_OPEN:
		boxes.remove_animated(2)
	return false


func _close_box3() -> void:
	if boxes.boxes[3].state == UIBoxes.STATE_OPEN:
		boxes.remove_animated(3)


func _tamer_rect() -> Rect2i:
	return tamer.screen_rect() if tamer != null else Rect2i(-5, -5, 10, 10)


# --- the list (createInventoryView, tickInventoryTop, renderInventoryTop/Bottom) -----------------

func _create_view() -> void:
	var b := boxes.boxes
	if b[1].state == UIBoxes.STATE_OPEN:
		return
	if b[0].frame == 0:
		row_offset = 0
		pointer = 0
		var features := UIBoxes.FEATURE_HALF_FILL
		var total := 5
		if size() > 10:
			features |= UIBoxes.FEATURE_SCROLL_BAR
			total = 10 if size() == 20 else 15
		boxes.create_animated(0, 0, features, Rect2i(-0x98, -0x68, 0x130, 0x6E if size() == 10 else 0xB6),
				_tamer_rect(), tick_list, render_list)
		b[0].row_offset = 0
		b[0].visible_rows = 9
		b[0].total_rows = total
	if b[0].state != UIBoxes.STATE_OPEN:
		return
	if b[1].frame == 0:
		_description_slot = -1
		var from := Rect2i(b[0].final.position.x + 8, b[0].final.position.y + 0xE, 0x10, 0x10)
		boxes.create_animated(1, 0, UIBoxes.FEATURE_HALF_FILL, Rect2i(-0x98, 0x4D, 0x130, 0x1C), from,
				Callable(), render_description, update_description)


## tickInventoryTop: the cursor while the options are closed.
func tick_list(_id: int) -> void:
	if boxes.boxes[2].state != UIBoxes.STATE_CLOSED or boxes.boxes[1].state != UIBoxes.STATE_OPEN:
		return
	_update_repeat()
	var pressed := pad.polled & ~pad.polled_previous
	if _repeating(Pad.UP) and pointer >= 2:
		_play_sound(2)
		pointer -= 2
	if _repeating(Pad.DOWN) and pointer < size() - 2:
		_play_sound(2)
		pointer += 2
	if pressed & Pad.LEFT and pointer & 1:
		_play_sound(2)
		pointer -= 1
	if pressed & Pad.RIGHT and not pointer & 1:
		_play_sound(2)
		pointer += 1
	if pointer < row_offset * 2:
		row_offset -= 1
	if pointer > (row_offset + boxes.boxes[0].visible_rows - 1) * 2 + 1:
		row_offset += 1


func render_list(canvas: CanvasItem, id: int) -> void:
	var b: UIBoxes.Box = boxes.boxes[id]
	var x := b.final.position.x
	var y := b.final.position.y
	var slot := row_offset * 2
	for i in (10 if size() == 10 else 18):
		if slot >= size():
			break
		var item := item_at(slot)
		if item != "":
			var record: Dictionary = data.item(item)
			var col := 0x9A if i & 1 else 0xA
			_icon(canvas, record, x + col, y + 8 + (i / 2) * 0x12)
			var usable: Dictionary = record.get("usable", {})
			var color := 8 if usable.get("name", "none") == "none" else int(usable.get("id", 0)) + 5
			var cell: int = names[slot] if slot < names.size() else slot
			text_area.render_string(canvas, color, x + (0xAD if i & 1 else 0x1D), y + 0xA + (i / 2) * 0x12, 0x60, 0xC,
					(cell & 1) * 0x60, (cell / 2) * 0xC, true)
			_amount(canvas, _amount_at(slot), x + (0x113 if i & 1 else 0x83), y + 0xC + (i / 2) * 0x12)
		slot += 1
	if b.state == UIBoxes.STATE_MENU:
		var row := move_source / 2 - row_offset
		if row >= 0 and row < b.visible_rows:
			var mx := x + (0x97 if move_source & 1 else 7)
			var my := y + 7 + row * 0x12
			PsxDraw.line3(canvas, MOVE_FRAME, mx, my + 0x12, mx, my, mx + 0x8A, my)
			PsxDraw.line3(canvas, MOVE_FRAME, mx + 0x8A, my, mx + 0x8A, my + 0x12, mx, my + 0x12)
	PsxDraw.selection_cursor(canvas, _cell_x(), y + 7 + _row() * 0x12, 0x8A, 0x12)
	b.row_offset = row_offset


## renderInventoryBottom's counting part: a new slot under the cursor redraws its description.
func update_description(_id: int) -> void:
	if item_at(pointer) == "":
		return
	if pointer != _description_slot:
		text_area.clear(DESCRIPTION)
		text_area.draw_string(data.localize(data.item(item_at(pointer)).get("description")).strip_edges(), 0, DESCRIPTION.position.y)
	_description_slot = pointer


func render_description(canvas: CanvasItem, id: int) -> void:
	if item_at(pointer) == "":
		return
	var b: UIBoxes.Box = boxes.boxes[id]
	text_area.render_string(canvas, 9, b.final.position.x + 0x1A, b.final.position.y + 8, 0xFC, 0xC, 0, DESCRIPTION.position.y, true)


func _cell_x() -> int:
	return boxes.boxes[0].final.position.x + (0x97 if pointer & 1 else 7)


func _row() -> int:
	return pointer / 2 - row_offset


# --- the options (createItemOption, selectOptionMenu, selectRegularInventory) ------------------

func _create_options() -> void:
	var b := boxes.boxes
	if not (b[1].state == UIBoxes.STATE_OPEN and b[2].frame == 0):
		return
	option = OPTION_USE
	var x := b[0].final.position.x + (0x9A if pointer & 1 else 0xA)
	var row := _row()
	var y := b[0].final.position.y + (0x18 + row * 0x12 if row < 5 else 0x20 + (row - 6) * 0x12)
	var from := Rect2i(x - 3, b[0].final.position.y + 7 + row * 0x12, 0x8A, 0x12)
	boxes.create_animated(2, 1, 0, Rect2i(x, y, 0x3A, 0x54), from, tick_options, render_options)


func tick_options(_id: int) -> void:
	if boxes.boxes[3].state == UIBoxes.STATE_CLOSED:
		option = _option_selector(option, 4, Pad.UP, Pad.DOWN)


## getItemOptionColor (inventory.c:209), field.
func option_color(i: int) -> int:
	if i == OPTION_MOVE or i == OPTION_SORT:
		return 9
	var item := item_at(pointer)
	if item == "":
		return 0xA
	if i == OPTION_USE:
		return 9 if item_use.can_use(item) else 0xA
	return 9 if item_use.can_drop(item) else 0xA


func render_options(canvas: CanvasItem, id: int) -> void:
	var b: UIBoxes.Box = boxes.boxes[id]
	var x := b.final.position.x + 9
	for i in 4:
		text_area.render_string(canvas, option_color(i), x + 3, b.final.position.y + 8 + i * 0x12, 0x24, 0xC, LABELS_U, i * 0xC, true)
	PsxDraw.selection_cursor(canvas, x, b.final.position.y + 6 + option * 0x12, 0x28, 0x10)


## selectOptionMenu (inventory.c:879).
func _select_option() -> void:
	if action >= ACTION_SORTED and action <= ACTION_SORTED + 2 or boxes.boxes[3].state != UIBoxes.STATE_CLOSED:
		return
	var item := item_at(pointer)
	match option:
		OPTION_USE:
			if item != "" and item_use.can_use(item):
				action = ACTION_USE
		OPTION_MOVE:
			action = ACTION_MOVE
			move_source = pointer
			boxes.boxes[0].state = UIBoxes.STATE_MENU
		OPTION_SORT:
			action = ACTION_SORT
		OPTION_DROP:
			if item != "" and item_use.can_drop(item):
				action = ACTION_DROP_ASK


## selectRegularInventory (inventory.c:924).
func _select_list() -> void:
	if action >= ACTION_SORTED and action <= ACTION_SORTED + 2 or action == ACTION_USE \
			or boxes.boxes[2].state != UIBoxes.STATE_CLOSED:
		return
	var b := boxes.boxes
	if b[0].state == UIBoxes.STATE_CLOSED:
		action = ACTION_VIEW
		return
	if action == ACTION_MOVE:
		_play_sound(4)
		b[0].state = UIBoxes.STATE_OPEN
		action = ACTION_NONE
		_swap(pointer, move_source)
		_description_slot = -1
		return
	if action < ACTION_USE and (tamer == null or tamer.held_item == "") and b[1].state == UIBoxes.STATE_OPEN:
		action = ACTION_OPTIONS


# --- sort and drop (box 3) ---------------------------------------------------------------------

func _create_sort() -> void:
	var b := boxes.boxes
	if not (b[2].state == UIBoxes.STATE_OPEN and b[3].state == UIBoxes.STATE_CLOSED):
		return
	text_area.draw_string(data.text("STR_BATTLE"), LABELS_U, 0x30)
	text_area.draw_string(data.text("STR_RAISE"), LABELS_U, 0x3C)
	text_area.draw_string(data.text("STR_BASIC"), LABELS_U, 0x48)
	sort_selected = 0
	var r := b[2].final
	boxes.create_animated(3, 1, 0, Rect2i(r.position.x + r.size.x, r.position.y, 0x48, 0x42),
			Rect2i(r.position.x + 9, r.position.y + 6 + option * 0x12, 0x28, 0x10), tick_sort, render_sort)


func tick_sort(_id: int) -> void:
	sort_selected = _option_selector(sort_selected, 3, Pad.UP, Pad.DOWN)


func render_sort(canvas: CanvasItem, id: int) -> void:
	var r := boxes.boxes[id].final
	for i in 3:
		text_area.render_string(canvas, 9, r.position.x + 0xC, r.position.y + 8 + i * 0x12, 0x30, 0xC, LABELS_U, 0x30 + i * 0xC, true)
	PsxDraw.selection_cursor(canvas, r.position.x + 9, r.position.y + 6 + sort_selected * 0x12, 0x36, 0x10)


## selectSorting: each mode sorts once.
func _select_sorting() -> void:
	if action != ACTION_SORTED + sort_selected:
		sort_items(ACTION_SORTED + sort_selected)
		action = ACTION_SORTED + sort_selected


## sortItems (inventory.c:947): the 6 sort categories, each by item id, in the mode's order; the
## inventory brought to that order by swaps (empty slots end up last).
func sort_items(mode: int) -> void:
	_description_slot = -1
	var groups := []
	for c in 6:
		groups.append([])
	for slot in size():
		var item := item_at(slot)
		if item != "":
			var record: Dictionary = data.item(item)
			groups[int(record.get("sort_category", 0))].append([int(record.get("id", 0)), item])
	var desired := []
	for c in data.sort_order(mode).get("categories", [0, 1, 2, 3, 4, 5]):
		var group: Array = groups[int(c)]
		group.sort_custom(func(a, b): return a[0] < b[0])
		for entry in group:
			desired.append(entry[1])
	# The C searches from slot 0: with the same item in two slots it can swap with the earlier one
	# (the types stay right, the amounts swap). Kept.
	for i in desired.size():
		if item_at(i) != desired[i]:
			for j in size():
				if item_at(j) == desired[i]:
					_swap(i, j)
					break


func _create_drop_question() -> void:
	var b := boxes.boxes
	if not (b[2].state == UIBoxes.STATE_OPEN and b[3].state == UIBoxes.STATE_CLOSED):
		return
	text_area.draw_string(data.text("STR_YES"), 0xC5, 0x54)
	text_area.draw_string(data.text("STR_NO"), 0xC0, 0x60)
	text_area.draw_string(data.text("STR_ARE_YOU_SURE"), 0, 0xC0)
	drop_option = 1
	var r := b[2].final
	boxes.create_animated(3, 1, 0, Rect2i(-0x40, -0x26, 0x80, 0x35),
			Rect2i(r.position.x + 9, r.position.y + 6 + option * 0x12, 0x28, 0x10), tick_drop, render_drop)


func tick_drop(_id: int) -> void:
	_update_repeat()
	if _repeating(Pad.LEFT) and drop_option != 0:
		_play_sound(2)
		drop_option -= 1
	if _repeating(Pad.RIGHT) and drop_option == 0:
		_play_sound(2)
		drop_option += 1


func render_drop(canvas: CanvasItem, id: int) -> void:
	var r := boxes.boxes[id].final
	var y := r.position.y + 0x1E
	text_area.render_string(canvas, 9, -0x34, -0x1E, 0x6C, 0xC, 0, 0xC0, true)
	for i in 2:
		text_area.render_string(canvas, 9, r.position.x + 0x12 + i * 0x34 + 5, y + 2, 0x24, 0xC, LABELS_U, 0x54 + i * 0xC, true)
	PsxDraw.selection_cursor(canvas, r.position.x + 0x12 + drop_option * 0x35, y, 0x2A, 0x10)


# --- input repeat (inventory.c:1005-1034) ------------------------------------------------------

func _update_repeat() -> void:
	if pad.polled == pad.polled_previous:
		_repeat += 1
	else:
		_repeat = 0


## isInventoryButtonPressed: pressed this frame, or held for REPEAT_FRAMES and more.
func _repeating(mask: int) -> bool:
	return mask & (pad.polled & ~pad.polled_previous) != 0 or (_repeat >= REPEAT_FRAMES and mask & pad.polled != 0)


## tickInventoryOptionSelector.
func _option_selector(cursor: int, count: int, up: int, down: int) -> int:
	_update_repeat()
	if _repeating(up) and cursor != 0:
		_play_sound(2)
		cursor -= 1
	if _repeating(down) and cursor < count - 1:
		_play_sound(2)
		cursor += 1
	return cursor


# --- drawing helpers -----------------------------------------------------------------------------

## renderItemSprite.
func _icon(canvas: CanvasItem, record: Dictionary, x: int, y: int) -> void:
	MenuDraw.item_icon(canvas, record, x, y)


## renderItemAmount(0, 2, ...): two digits, right-aligned, no leading zeros.
func _amount(canvas: CanvasItem, value: int, x: int, y: int) -> void:
	# Kept: a texture made inside _draw and dropped is freed before the canvas renders it (white).
	if _digits == null:
		_digits = Content.load_texture(DIGITS)
	var tex := _digits
	if tex == null:
		return
	var digits := GameMenu.date_digits(value, 2)
	var first := 2 - digits.size()
	for k in digits.size():
		var d: int = digits[k]
		canvas.draw_texture_rect_region(tex, Rect2(CENTRE + Vector2(x + (first + k) * 6, y), Vector2(6, 10)),
				Rect2(DIGIT_U + d * 6, DIGIT_ROW, 6, 10))


func _play_sound(value: int) -> void:
	if sound != null:
		sound.play_sound(0, value)
