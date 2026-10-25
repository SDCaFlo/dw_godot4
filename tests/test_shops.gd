extends SceneTree
## The shop builtins and the script item menu (scripts/script/shop_routines.gd, scripts/ui/item_menu.gd;
## specs/shops.md) run by the interpreter on small scripts, with the MAPHEAD lines of the porter output:
##   godot --headless --path . -s res://tests/test_shops.gd
## Exits 1 if a check fails.

## playSound(0, n) calls, in order.
class SoundLog extends Node:
	var played: Array = []

	func play_sound(_slot: int, value: int) -> int:
		played.append(value)
		return 0


var _failed := 0
var _checks := 0
var _started := false
var data: Node
var gs: Node
var interp: ScriptInterpreter
var ctx: ScriptContext
var tb: TextBoxes
var boxes: UIBoxes
var area: TextArea
var pad: Pad
var files: ScriptFiles
var routines: ScriptRoutines
var shop: ShopRoutines
var sounds: Array = []


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("scripts/MAPHEAD/script.json"):
		print("SKIP: porter output missing")
		quit(0)
		return false
	_setup()
	_lines()
	_buy()
	_rows()
	_sell()
	_baby_discount()
	_recycle()
	_no_stock()
	_pick_item()
	_bits_box()
	_teardown()
	print("%s: shop checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _setup() -> void:
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()
	boxes = UIBoxes.new()
	root.add_child(boxes)
	area = TextArea.new(data, "en_us")
	ctx = ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	pad = Pad.new()
	tb = TextBoxes.new(boxes, area, ctx, pad, data, gs)
	tb.sound.connect(func(id): sounds.append(id))
	files = ScriptFiles.new()
	interp = ScriptInterpreter.new(ctx, files, tb)
	interp.game_state = gs
	interp.data = data
	routines = ScriptRoutines.new()
	shop = load("res://scenes/script/shop_routines.tscn").instantiate()
	routines.add_child(shop)
	root.add_child(routines)
	routines.configure(ctx, tb, gs, data)
	interp.routines = routines


func _teardown() -> void:
	routines.free()
	boxes.free()
	gs.free()
	data.free()


func _frame(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	interp.tick_script()
	boxes.step()


## A press after an idle frame (a new box takes input once ✕ is up: isXPressedAfterDialogue).
func _press(button: int) -> void:
	_frame()
	_frame(button)
	_frame()


func _until(done: Callable, limit := 120) -> bool:
	for i in limit:
		if done.call():
			return true
		_frame()
	return done.call()


## A script: value 0xFE = `owner`, CALL_ROUTINE `routine`, value 50 = 1, END.
func _run(routine: int, owner := 0xFF) -> void:
	gs.set_script_value(50, 0)
	var code := [0x1E, 0, 0xFE, owner, 0x64, routine, 0x1E, 0, 50, 1, 0xFE, 0]
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code))
	files._cache[500] = bytes
	interp.call_section(500, 1)
	_frame()


func _ended() -> bool:
	return gs.script_value(50) == 1


## The dialogue waits for ✕ (the routine's text mode 1 / 2) and its page is shown.
func _waiting_text() -> bool:
	return ctx.state_2 == 1 and ctx.textbox_mode in [1, 2] and boxes.boxes[0].state == UIBoxes.STATE_OPEN \
			and tb.entries[0].write_count == tb.entries[0].render_count and tb.entries[0].idle == 0


func _list_ready() -> bool:
	return ctx.state_2 == 1 and boxes.boxes[1].state == UIBoxes.STATE_OPEN and not shop.menu.is_busy(shop.menu.current_box()) \
			and ctx.textbox_mode == 0


func _set_inventory(items: Dictionary) -> void:
	var slots: Array = gs.state["inventory"]["slots"]
	for i in slots.size():
		slots[i] = null
	for key in items:
		gs.give_item(key, items[key])


func _id(key: String) -> int:
	return data.id_of("items/item_data", key)


## The text of a line buffer row (ASCII bytes and full-width digits).
func _line_text(row: int) -> String:
	var out := ""
	var i := row * tb.line_size
	while i < (row + 1) * tb.line_size:
		var b := tb.lines[i]
		if b == 0 or b == 0xD:
			break
		if b == 1 or b == 0xF or (b >= 0x16 and b <= 0x1C):
			i += 2
			continue
		if b >= 0x80:
			out += _sjis((b << 8) | tb.lines[i + 1])
			i += 2
			continue
		out += char(b)
		i += 1
	return out


## A full-width SJIS glyph as ASCII (digits, letters, space, "－").
static func _sjis(code: int) -> String:
	if code >= 0x824F and code <= 0x8258:
		return str(code - 0x824F)
	if code >= 0x8260 and code <= 0x8279:
		return char(0x41 + code - 0x8260)
	if code >= 0x8281 and code <= 0x829A:
		return char(0x61 + code - 0x8281)
	if code == 0x817C:
		return "-"
	return " "


func _lines() -> void:
	tb.files = files
	_check(tb.maphead_entry(0x4C4, 0) > 0, "MAPHEAD section 0x4C4 has its lines")
	ctx.code = files.script(ScriptFiles.MAPHEAD)
	ctx.pointer = tb.maphead_entry(0x4C4, 2)
	var text := ""
	var i := 0
	while i < 60:
		var b := ctx.byte_at(ctx.pointer + i)
		if b == 0:
			break
		if b >= 0x80:
			text += _sjis((b << 8) | ctx.byte_at(ctx.pointer + i + 1))
		else:
			text += "|"
		i += 2
	_check(text.begins_with("Buy") and "Sell" in text, "line 2 is the Buy / Sell choice: %s" % text)
	gs.set_script_value(0xFE, 0xFF)
	_check(tb.shopkeeper_section() == 0x4CE, "no shopkeeper: section 0x4CE")


func _buy() -> void:
	for t in range(0x180, 0x200):
		gs.clear_trigger(t)
	gs.clear_trigger(3)
	gs.set_trigger(0x180 + _id("dw1:med_recovery"))
	gs.set_trigger(0x180 + _id("dw1:lrg_recovery"))
	_set_inventory({"dw1:med_recovery": 98})
	gs.state["money"] = 1100
	_run(0x08)
	_check(ctx.active_instruction == ScriptContext.OP_CALL_ROUTINE and not _ended(), "the shop waits (the script stops)")
	_check(_until(_waiting_text), "the greeting is shown")
	_press(Pad.CONFIRM)
	_check(_until(func(): return _waiting_text() and ctx.textbox_mode == 2), "Buy / Sell / See ya")
	_check(_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_OPEN, 30), "the bits box opens")
	_check(_line_text(8).ends_with("1100"), "the bits box shows the bits: %s" % _line_text(8))
	_press(Pad.CONFIRM)
	_check(_until(_list_ready), "Buy: the list opens")
	var menu := shop.menu
	_check(menu.type == ItemMenu.TYPE_BUY and menu.left.item_count == 2, "two items on sale")
	_check(menu.left.buf[1] == 1 and menu.left.buf[3] == 1, "both buyable (one slot below 99, bits enough)")
	sounds.clear()
	_press(Pad.CONFIRM)
	_check(boxes.boxes[3].state != UIBoxes.STATE_CLOSED and sounds.has(3), "✕: the amount box")
	_check(menu.max_amount == 1, "at most 99 - 98 owned = 1 (%d)" % menu.max_amount)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN)
	_press(Pad.TRIANGLE)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_CLOSED and boxes.boxes[3].frame == 0)
	_press(Pad.DOWN)
	_check(menu.left.cursor == 1, "↓: the second item")
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN)
	_check(menu.item_type == _id("dw1:lrg_recovery") and menu.max_amount == 1, "lrg.recovery: 1100 / 1000 = 1 affordable")
	_press(Pad.UP)
	_check(menu.amount == 1, "↑ at the maximum: nothing")
	_press(Pad.CONFIRM)
	_check(int(gs.state["money"]) == 100 and gs.item_count("dw1:lrg_recovery") == 1, "✕: 1000 bits for one")
	_check(ctx.state_2 == 1 and ctx.next_state_2 == 3, "thanks, then the choice again")
	_check(_until(_waiting_text), "\"Thanks.\"")
	_press(Pad.CONFIRM)
	_check(_until(func(): return _waiting_text() and ctx.textbox_mode == 2), "the choice again")
	_press(Pad.TRIANGLE)
	_check(_until(_waiting_text), "△ on the choice: See ya, the farewell")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "the shop ends, the script goes on")


func _rows() -> void:
	# The rows' strings of a buy list with an unaffordable item.
	gs.state["money"] = 600
	_set_inventory({})
	var menu := shop.menu
	menu.left = ItemMenu.allocate(6, 0xB2, 0x18, 6, 0x5A)
	menu.type = ItemMenu.TYPE_BUY
	menu.fill_buy()
	_check(Array(menu.left.buf) == [1, 1, 2, 0], "med.recovery 500 buyable, lrg.recovery 1000 not")
	tb.register_textbox(1, 9, 6, 1, 0)
	menu.left.is_open = false
	menu.left.box_id = 1
	menu.left.item_row = [9, 10, 11, 12, 13, 14]
	menu.update_strings(menu.left, 9)
	var row := 9 + 6 * (tb.entries[1].back_page ^ 1)
	_check(_line_text(row) == "med.recovery 500", "a buy row: name, price: '%s'" % _line_text(row))
	_check(tb.lines[row * tb.line_size + 1] == 1 and tb.lines[(row + 1) * tb.line_size + 1] == 3,
			"available rows white, the others grey")
	tb.clear_textbox_line_count(1)


func _sell() -> void:
	_set_inventory({"dw1:med_recovery": 4})
	gs.state["money"] = 999900
	_run(0x08)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(func(): return _waiting_text() and ctx.textbox_mode == 2)
	_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	_check(_until(_list_ready), "Sell: the inventory list")
	var menu := shop.menu
	_check(menu.type == ItemMenu.TYPE_SELL and menu.right.item_count == int(gs.state["inventory"]["size"]), "a row per slot")
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN)
	_check(menu.item_price == 250 and menu.max_amount == 4, "half price, up to the 4 owned")
	_press(Pad.SQUARE)
	_check(menu.amount == 4, "□: the maximum")
	_press(Pad.CONFIRM)
	_check(int(gs.state["money"]) == 999999 and gs.item_count("dw1:med_recovery") == 0, "sold: bits capped at 999999")
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(func(): return _waiting_text() and ctx.textbox_mode == 2)
	_press(Pad.TRIANGLE)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_check(_until(_ended), "the shop ends")


func _baby_discount() -> void:
	var partner = gs.state["partner"]["digimon"]
	gs.state["partner"]["digimon"] = "dw1:koromon"
	_set_inventory({})
	gs.state["money"] = 1000
	_check(shop.menu.is_partner_baby(), "Koromon is a baby")
	_run(0x08)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(func(): return _waiting_text() and ctx.textbox_mode == 2)
	_press(Pad.CONFIRM)
	_until(_list_ready)
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN)
	_press(Pad.UP)
	_press(Pad.CONFIRM)
	_check(int(gs.state["money"]) == 100 and ctx.shop_variable == 100, "two med.recovery at 450: 900, 100 saved")
	_until(_waiting_text)
	_check("100" in _page_text(), "the discount line names it")
	_press(Pad.CONFIRM)
	_until(func(): return _waiting_text() and ctx.textbox_mode == 2)
	_press(Pad.TRIANGLE)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_ended)
	gs.state["partner"]["digimon"] = partner


## The dialogue box's shown page as text.
func _page_text() -> String:
	var e: TextBoxes.Entry = tb.entries[0]
	var out := ""
	for r in 4:
		out += _line_text(e.back_page * 4 + r) + "|"
	return out


func _recycle() -> void:
	gs.set_trigger(3)
	var stock: Array = gs.state["script"]["recycle_stock"]
	stock.fill(0)
	stock[0] = 2
	_set_inventory({})
	gs.state["money"] = 10000
	var restore: int = int(data.recyclable_items()[0]["item"]["id"])
	_run(0x08)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_check(_until(func(): return _waiting_text() and ctx.textbox_mode == 2), "Buy / See ya")
	_press(Pad.CONFIRM)
	_check(_until(_list_ready) and shop.menu.type == ItemMenu.TYPE_RECYCLE, "the recycle list")
	_check(shop.menu.left.item_count == 1 and shop.menu.left.buf[0] == restore, "one recycled item in stock")
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN)
	_check(shop.menu.max_amount == 2, "up to the stock (2)")
	_press(Pad.UP)
	_press(Pad.CONFIRM)
	_check(int(stock[0]) == 0 and gs.item_count(restore) == 2, "bought: the stock goes down")
	_check(ctx.next_state_2 == 9, "nothing left: then \"No.\"")
	for i in 3:
		_until(_waiting_text)
		_press(Pad.CONFIRM)
	_check(_until(_ended), "the recycle shop ends")
	gs.clear_trigger(3)


func _no_stock() -> void:
	for t in range(0x180, 0x200):
		gs.clear_trigger(t)
	_run(0x08)
	_check(_until(_waiting_text), "no stock: \"I don't have anything to sell.\"")
	_check(ctx.next_state_2 == 2, "then the end")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "and the script goes on")


func _pick_item() -> void:
	# Nothing droppable: trigger 3 set, value 0xFE = 0xFF, at once.
	_set_inventory({})
	gs.clear_trigger(3)
	_run(0x00)
	_check(_until(_ended, 5), "the picker ends at once without items")
	_check(gs.is_trigger_set(3) and gs.script_value(0xFE) == 0xFF, "trigger 3 set, value 0xFE = 0xFF")
	# An item: picked with Yes.
	_set_inventory({"dw1:sm_recovery": 3})
	gs.set_trigger(3)
	_run(0x00)
	_check(_until(_list_ready) and shop.menu.type == ItemMenu.TYPE_PICK, "the item list opens")
	sounds.clear()
	_press(Pad.CONFIRM)
	_check(sounds.has(3) and _until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN), "✕: Is it OK? Yes No")
	_press(Pad.RIGHT)
	_check(shop.menu.amount == 1, "→: No")
	_press(Pad.LEFT)
	_press(Pad.CONFIRM)
	_check(_until(_ended), "Yes: the picker ends")
	_check(gs.script_value(0xFE) == _id("dw1:sm_recovery") and not gs.is_trigger_set(3), "value 0xFE = the item, trigger 3 unset")
	# △ with trigger 3 set: nothing picked.
	gs.set_trigger(3)
	_run(0x00)
	_until(_list_ready)
	_press(Pad.TRIANGLE)
	_check(_until(_ended), "△: the picker ends")
	_check(gs.script_value(0xFE) == 0xFF and not gs.is_trigger_set(3), "nothing picked: 0xFF, trigger 3 unset")


func _bits_box() -> void:
	# 0x0F, DELAY 40, 0x10, DELAY 30, value 50 = 1, END.
	gs.state["money"] = 4321
	gs.set_script_value(50, 0)
	var code := [0x64, 0x0F, 0x67, 0, 40, 0, 0x64, 0x10, 0x67, 0, 30, 0, 0x1E, 0, 50, 1, 0xFE, 0]
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code))
	files._cache[500] = bytes
	interp.call_section(500, 1)
	_frame()
	_check(ctx.active_instruction == ScriptContext.OP_DELAY, "0x0F doesn't wait (the DELAY after it does)")
	_check(_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_OPEN, 40), "0x0F: the bits box opens")
	_check(_line_text(8).ends_with("4321"), "the bits box: '%s'" % _line_text(8))
	_check(_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_CLOSED and _ended(), 80), "0x10 closes it")
