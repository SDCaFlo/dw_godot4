class_name KeeperMenu
extends RefCounted
## The item keeper's two boxes (itemKeeperFillItemList, createItemKeepWindow, tickItemKeeperWindow,
## updateKeeperTextbox, keeperMove…, keeperScroll…ToItem, renderKeeperBox; shop/script_menu.c:1536,
## :1605, :1941-2394; specs/town_services.md §2.1) on the item menu's two lists: box 1 the storage
## (left), box 2 the inventory (right), side by side in the text rows' two halves.

const SECTION := 0x4D5
## The rows: 9 the label's, 10-14 the five row slots.
const START_ROW := 0xA
const LABEL_ROW := 9
## KEEPER_LABEL_END (US): where updateKeeperTextbox ends rows 9 and 15 with 0x0D.
const LABEL_END := 6
## The US labels (C string literals): MAIN_D_801307B4, MAIN_D_801307C0.
const IN_HAND := "In hand"
const KEEPING := "Keeping"
const STORAGE_BOX := 1
const HAND_BOX := 2
const STACK_MAX := 99
const TEN := 10
## Ten move only below 90 on the side they go to.
const TEN_LIMIT := 0x5A
## The active side's lit title bar (GsBOXF, half-transparent).
const HIGHLIGHT := Color8(0x80, 0x80, 0xFF)

var menu: ItemMenu
var textboxes: TextBoxes
var ctx: ScriptContext
var game_state: Node
var data: Node
## MAIN_D_80134F90: 0 the storage, 1 the inventory.
var side := 0


func _init(item_menu: ItemMenu) -> void:
	menu = item_menu
	textboxes = menu.textboxes
	ctx = menu.ctx
	game_state = menu.game_state
	data = menu.data


## smth[0x54 + item]: the stored count.
func stored(item: int) -> int:
	return int(game_state.state["script"]["item_keeper"].get(data.key_of("items/item_data", item), 0))


func set_stored(item: int, count: int) -> void:
	var keep: Dictionary = game_state.state["script"]["item_keeper"]
	var key: String = data.key_of("items/item_data", item)
	if count == 0:
		keep.erase(key)
	else:
		keep[key] = count
	game_state.changed.emit("item_keeper")


## itemKeeperFillItemList: left, every stored item in id order (| 0x80 when it can come out);
## right, every inventory slot (| 0x80 when its storage isn't full).
func fill() -> void:
	var slots := menu._slots()
	var has_space := slots.has(null)
	var box := menu.left
	box.buf = PackedByteArray()
	box.item_count = 0
	for record in data.records("items/item_data"):
		var item := int(record["id"])
		var count := stored(item)
		if count == 0:
			continue
		box.item_count += 1
		var out := has_space
		if not out:
			for s in slots:
				if menu._slot_item(s) == item and int(s["amount"]) != STACK_MAX:
					out = true
					break
		box.buf.append_array([item, count | 0x80 if out else count])
	box = menu.right
	box.buf = PackedByteArray()
	box.item_count = 0
	for s in slots:
		box.item_count += 1
		if s == null:
			box.buf.append_array([0xFF, 0])
			continue
		var item := menu._slot_item(s)
		var amount := int(s["amount"])
		box.buf.append_array([item, amount | 0x80 if stored(item) != STACK_MAX else amount])


## createItemKeepWindow.
func create() -> void:
	textboxes.create_textbox(STORAGE_BOX, 0xE1, Rect2i(-152, -98, 148, 127), menu._origin(ctx.read_pstat(0xFE)),
			tick, render_storage)
	textboxes.register_textbox(STORAGE_BOX, LABEL_ROW, 6, 1, 1)
	menu._init_box(menu.left, STORAGE_BOX, START_ROW)
	update_box(0)
	textboxes.create_textbox(HAND_BOX, 0xE1, Rect2i(0, -98, 148, 127), menu._origin(ScriptContext.OWNER_TAMER),
			Callable(), render_hand)
	textboxes.register_textbox(HAND_BOX, LABEL_ROW, 6, 1, 2)
	menu._init_box(menu.right, HAND_BOX, START_ROW)
	update_box(1)


func _list(of_side: int) -> ItemMenu.ListBox:
	return menu.left if of_side == 0 else menu.right


## updateKeeperTextbox: the JP label line in the side's box (its write taken back; drawn over in
## US), then its rows (style 0).
func update_box(of_side: int) -> void:
	var box_id := of_side + 1
	textboxes.show_maphead_textbox(4 + of_side, ScriptContext.OWNER_NONE, box_id, SECTION)
	textboxes.entries[box_id].write_count -= 1
	var half := 0 if of_side == 0 else textboxes.line_size / 2
	for row in [LABEL_ROW, LABEL_ROW + 6]:
		var at: int = row * textboxes.line_size + half + LABEL_END
		if at < textboxes.lines.size():
			textboxes.lines[at] = 0xD
	menu.update_strings(_list(of_side), START_ROW, ItemMenu.STYLE_ITEM)


## tickItemKeeperWindow (box 1's tick; both lists flip here).
func tick(_id: int) -> void:
	var busy_left := menu.is_busy(menu.left)
	var busy_right := menu.is_busy(menu.right)
	if busy_left or busy_right:
		return
	var boxes := menu.boxes.boxes
	if boxes[ItemMenu.SUB_BOX].state != UIBoxes.STATE_CLOSED:
		return
	if boxes[STORAGE_BOX].state != UIBoxes.STATE_OPEN or boxes[HAND_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	if ctx.state_2 != 1:
		return
	var box := _list(side)
	var pad := menu.pad
	if pad.is_key_down(Pad.CANCEL):
		ctx.state_2 = 6
		menu._sound(4)
	elif pad.is_key_down(Pad.LEFT):
		side = 0
		menu._sound(2)
	elif pad.is_key_down(Pad.RIGHT):
		side = 1
		menu._sound(2)
	elif box.item_count != 0:
		if pad.is_key_down(Pad.CONFIRM):
			move_one()
			menu._sound(3)
		elif pad.is_key_down(Pad.ALT):
			move_ten()
			menu._sound(3)
		elif pad.is_key_down(Pad.SQUARE):
			move_all()
			menu._sound(3)
		elif pad.is_key_down(Pad.UP):
			if pad.polled & Pad.R1:
				menu.move_to_top(box)
				update_box(side)
			else:
				menu.cursor_up(box, ItemMenu.STYLE_ITEM)
		elif pad.is_key_down(Pad.DOWN):
			if pad.polled & Pad.R1:
				menu.move_to_bottom(box)
				update_box(side)
			else:
				menu.cursor_down(box, ItemMenu.STYLE_ITEM)
		elif pad.is_key_down(Pad.START):
			var b: UIBoxes.Box = boxes[side + 1]
			menu.create_description(box, Rect2i(5 + b.final.position.x, 0x20 + b.final.position.y + box.cursor * 18,
					0x80, 0x12))
			menu._sound(3)


## The selected row of the active side: [item, second byte], or [] when it can't move (an empty
## row, bit 0x80 off).
func _selected() -> Array:
	var box := _list(side)
	var row := box.top_row + box.cursor
	var item := box.item(row)
	var second := box.second(row)
	if item == 0xFF or second & 0x80 == 0:
		return []
	return [item, second & 0x7F]


## keeperMoveOne.
func move_one() -> bool:
	var r := _selected()
	if r.is_empty():
		return false
	var item: int = r[0]
	if side == 0:
		if game_state.item_count(item) >= STACK_MAX:
			return false
		set_stored(item, stored(item) - 1)
		game_state.give_item(item, 1)
	else:
		if game_state.item_count(item) == 0:
			return false
		game_state.remove_item(item, 1)
		set_stored(item, stored(item) + 1)
	_moved(item)
	return true


## keeperMoveTen.
func move_ten() -> bool:
	var r := _selected()
	if r.is_empty() or r[1] < TEN:
		return false
	var item: int = r[0]
	if side == 0:
		if game_state.item_count(item) >= TEN_LIMIT:
			return false
		set_stored(item, stored(item) - TEN)
		game_state.give_item(item, TEN)
	else:
		if stored(item) >= TEN_LIMIT:
			return false
		game_state.remove_item(item, TEN)
		set_stored(item, stored(item) + TEN)
	_moved(item)
	return true


## keeperMoveStack: as many as fit (an amount of 0 is still "moved", as the C).
func move_all() -> bool:
	var r := _selected()
	if r.is_empty():
		return false
	var item: int = r[0]
	var amount: int = r[1]
	if side == 0:
		amount = mini(amount, (STACK_MAX - game_state.item_count(item)) & 0xFF)
		set_stored(item, stored(item) - amount)
		game_state.give_item(item, amount)
	else:
		amount = mini(amount, (STACK_MAX - stored(item)) & 0xFF)
		game_state.remove_item(item, amount)
		set_stored(item, stored(item) + amount)
	_moved(item)
	return true


## Both lists refilled; the side moved from follows the item first.
func _moved(item: int) -> void:
	fill()
	if side == 0:
		scroll_storage_to(item)
		scroll_hand_to(item)
	else:
		scroll_hand_to(item)
		scroll_storage_to(item)


## keeperScrollLeftToItem.
func scroll_storage_to(item: int) -> void:
	var box := menu.left
	box.prev_top_row = box.top_row
	box.prev_cursor = box.cursor
	var visible := box.visible_rows
	var top := box.top_row
	var count := box.item_count
	var i := -1
	for k in count:
		if box.item(k) == item:
			i = k
			break
	if i < 0:
		if count == 0:
			box.top_row = 0
			box.cursor = 0
			update_box(0)
			return
		i = mini(top + box.cursor, count - 1)
		if top + visible >= count and top != 0:
			box.top_row -= 1
			update_box(0)
			return
	if i >= top and i < top + visible:
		box.cursor = i - top
	else:
		ItemMenu.place(box, i)
	update_box(0)


## keeperScrollRightToItem: only when the item is listed.
func scroll_hand_to(item: int) -> void:
	var box := menu.right
	box.prev_top_row = box.top_row
	box.prev_cursor = box.cursor
	for i in box.item_count:
		if box.item(i) == item:
			if i >= box.top_row and i < box.top_row + box.visible_rows:
				box.cursor = i - box.top_row
			else:
				ItemMenu.place(box, i)
			break
	update_box(1)


func render_storage(canvas: CanvasItem, _id: int) -> void:
	_render(canvas, menu.left, false)


func render_hand(canvas: CanvasItem, _id: int) -> void:
	_render(canvas, menu.right, true)


## renderKeeperBox (US), in reverse of the C's adds (the cursor over them, as the item menu's).
func _render(canvas: CanvasItem, box: ItemMenu.ListBox, in_hand: bool) -> void:
	if box == null:
		return
	var id := box.box_id
	var b: UIBoxes.Box = menu.boxes.boxes[id]
	var bx := b.final.position.x
	var by := b.final.position.y
	menu._render_rows(canvas, box, bx + 8, by + 0x24, 0, 0, 2)
	if side == id - 1:
		PsxDraw.box(canvas, Rect2i(bx + 4, by + 3, 0x8C, 0x12), HIGHLIGHT, true)
	var e: TextBoxes.Entry = textboxes.entries[id]
	var coords := TextBoxes.vram_mode_coords(e.vram_mode)
	var y: int = LABEL_ROW * TextBoxes.ROW_HEIGHT + e.back_page * e.vram_rows * TextBoxes.ROW_HEIGHT
	menu.text_area.draw_string(IN_HAND if in_hand else KEEPING, coords[0], y)
	menu.text_area.render_string(canvas, 0, bx + 0x2D, by + 7, 0x38 if in_hand else 0x3C, 0xC, coords[0], y, true)
	menu._render_scroll_bar(canvas, box)
	menu._header(canvas, 3, bx + 0x6E, by + 0x17)
	_table_box(canvas, bx + 0x6B, by + 0x15, 0x25, 0xB)
	menu._header(canvas, 0, bx + 8, by + 0x17)
	_table_box(canvas, bx + 4, by + 0x15, 0x67, 0xB)
	PsxDraw.selection_cursor(canvas, bx + 5, by + box.cursor * 0x12 + 0x21, 0x80, 0x12)


## renderKeeperTableBox: light top-left, dark bottom-right (drawn in reverse).
func _table_box(canvas: CanvasItem, x: int, y: int, w: int, h: int) -> void:
	PsxDraw.line3(canvas, ItemMenu.DARK, x, y + h - 1, x + w - 1, y + h - 1, x + w - 1, y)
	PsxDraw.line3(canvas, ItemMenu.LIGHT, x + w - 1, y, x, y, x, y + h - 1)
