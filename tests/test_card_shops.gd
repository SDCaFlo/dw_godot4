extends SceneTree
## The card shops (0x0E), the merit shop (0x01) and Mojyamon's trades (0x02) (scripts/script/
## card_shop_routines.gd, merit_shop_routines.gd, mojyamon_routines.gd, scripts/ui/item_menu.gd,
## trade_menu.gd; specs/card_shops.md) run by the interpreter on small scripts:
##   godot --headless --path . -s res://tests/test_card_shops.gd
## Exits 1 if a check fails.

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
var menu: ItemMenu
var cards: CardShopRoutines
var mojyamon: MojyamonRoutines
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
	_pack()
	_pack_limit()
	_roll()
	_single()
	_single_empty()
	_sell()
	_merit_card()
	_merit_item()
	_mojyamon_trade()
	_mojyamon_refused()
	_mojyamon_full()
	_shared_bits_box()
	_teardown()
	print("%s: card shop checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
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
	for scene in ["shop", "card_shop", "merit_shop", "mojyamon"]:
		routines.add_child(load("res://scenes/script/%s_routines.tscn" % scene).instantiate())
	root.add_child(routines)
	routines.configure(ctx, tb, gs, data)
	interp.routines = routines
	menu = routines.menu
	cards = routines.node_for(0x0E)
	mojyamon = routines.node_for(0x02)
	Rng.set_seed(7)


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


## A script: `code`, then value 50 = 1, END.
func _run_code(code: Array) -> void:
	gs.set_script_value(50, 0)
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code + [0x1E, 0, 50, 1, 0xFE, 0]))
	files._cache[500] = bytes
	interp.call_section(500, 1)
	_frame()


## value 0xFE = `owner`, SET_DIALOG_OWNER `owner` (a script starts as the tamer's: the tamer's
## lines would not open box 0), CALL_ROUTINE `routine`.
func _run(routine: int, owner := 0xFF) -> void:
	_run_code([0x1E, 0, 0xFE, owner, 0x1B, owner, 0x64, routine])


func _ended() -> bool:
	return gs.script_value(50) == 1


func _waiting_text() -> bool:
	return ctx.state_2 == 1 and ctx.textbox_mode in [1, 2] and boxes.boxes[0].state == UIBoxes.STATE_OPEN \
			and tb.entries[0].write_count == tb.entries[0].render_count and tb.entries[0].idle == 0


func _choice_shown() -> bool:
	return _waiting_text() and ctx.textbox_mode == 2


## The list box takes input: open, its page drawn (no flip pending: is_busy() would flip it).
func _list_ready() -> bool:
	var e: TextBoxes.Entry = tb.entries[1]
	return ctx.state_2 == 1 and ctx.textbox_mode == 0 and boxes.boxes[1].state == UIBoxes.STATE_OPEN \
			and e.write_count == e.render_count and e.page_ready == 0 and boxes.boxes[0].state == UIBoxes.STATE_OPEN


func _sub_open() -> bool:
	return boxes.boxes[3].state == UIBoxes.STATE_OPEN


func _set_inventory(items: Dictionary) -> void:
	var slots: Array = gs.state["inventory"]["slots"]
	for i in slots.size():
		slots[i] = null
	for key in items:
		gs.give_item(key, items[key])


func _clear_cards() -> void:
	for record in data.records("items/card_data"):
		gs.set_card_count(int(record["id"]), 0)


func _card(key: String) -> int:
	return data.id_of("items/card_data", key)


func _item(key: String) -> int:
	return data.id_of("items/item_data", key)


func _priced_cards() -> Array:
	return data.records("items/card_data").filter(func(r): return r.get("price") != null)


## A line buffer row as text (ASCII bytes, full-width letters and digits, "－" as "-").
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


## The dialogue box's shown page.
func _page_text() -> String:
	var e: TextBoxes.Entry = tb.entries[0]
	var out := ""
	for r in 4:
		out += _line_text(e.back_page * 4 + r) + "|"
	return out


## Box 1's rows, both pages (a row's text wherever it was written).
func _list_text() -> String:
	var out := ""
	for r in range(9, 21):
		out += _line_text(r) + "|"
	return out


# --- the pack -----------------------------------------------------------------------------------

func _pack() -> void:
	_clear_cards()
	gs.clear_trigger(3)
	gs.clear_trigger(4)
	_run(0x0E, 5)
	_check(ctx.active_instruction == ScriptContext.OP_CALL_ROUTINE and not _ended(), "0x0E waits")
	var first := ""
	for i in 3:
		_check(_until(_waiting_text), "card %d shown" % (i + 1))
		if i == 0:
			first = _page_text()
		var digimon := ctx.read_pstat(CardShopRoutines.PSTAT_CARD)
		_check(not data.cards_of(digimon).is_empty(), "value 249 = a card's Digimon (%d)" % digimon)
		_press(Pad.CONFIRM)
	_check(_until(_ended), "the pack ends after 3 cards")
	var total := 0
	for record in data.records("items/card_data"):
		total += gs.card_count(int(record["id"]))
	_check(total == 3, "3 cards added (%d)" % total)
	_check("|This is a" in first or "|A " in first or "|Another" in first,
			"the tamer's card line: %s" % first)


func _pack_limit() -> void:
	for record in data.records("items/card_data"):
		gs.set_card_count(int(record["id"]), 9)
	_run(0x0E, 5)
	_until(_waiting_text)
	_check("|Another" in _page_text(), "held 6 or more: \"Another … card.\": %s" % _page_text())
	for i in 3:
		_until(_waiting_text)
		_press(Pad.CONFIRM)
	_until(_ended)
	var over := false
	for record in data.records("items/card_data"):
		if gs.card_count(int(record["id"])) != 9:
			over = true
	_check(not over, "a card held 9 times is not added")
	_clear_cards()


func _roll() -> void:
	var seen := {}
	var ok := true
	for i in 400:
		var card := cards.roll_card()
		var rarity := menu.card_rarity(card)
		seen[rarity] = int(seen.get(rarity, 0)) + 1
		if rarity < 0 or rarity > 4 or data.card(card).get("price") == null:
			ok = false
	_check(ok, "rolls give priced cards of classes 0-4")
	_check(int(seen.get(4, 0)) > int(seen.get(3, 0)) and int(seen.get(3, 0)) > int(seen.get(1, 0)),
			"class 4 (50 %%) more than 3 (30 %%) more than 1 (4 %%): %s" % seen)


# --- a single card ------------------------------------------------------------------------------

func _single() -> void:
	_clear_cards()
	gs.clear_trigger(3)
	gs.set_trigger(4)
	var shop: Array = gs.state["script"]["card_shop"]
	var phoenix := _card("dw1:phoenixmon")
	var nanimon := _card("dw1:nanimon")
	for i in shop.size():
		shop[i] = null
	shop[0] = data.key_of("items/card_data", phoenix)
	shop[2] = data.key_of("items/card_data", nanimon)
	gs.set_card_count(nanimon, 9)
	gs.state["money"] = 6000
	_run(0x0E, 5)
	_check(_until(_list_ready), "single card: the list opens")
	_check(menu.type == ItemMenu.TYPE_CARD_BUY and menu.left.item_count == 6, "type 3, the 6 slots")
	_check(Array(menu.left.buf.slice(0, 6)) == [phoenix, 1, 0xFF, 0, nanimon, 0],
			"Phoenixmon buyable, slot 1 empty, Nanimon held 9: %s" % [Array(menu.left.buf.slice(0, 6))])
	_check("Phoenixmon5000" in _list_text().replace(" ", ""), "a row: name, price: %s" % _list_text())
	var colours := []
	for r in range(9, 21):
		if _line_text(r).begins_with("Phoenixmon") or _line_text(r).begins_with("Nanimon"):
			colours.append(tb.lines[r * tb.line_size + 1])
	_check(colours.has(7) and colours.has(3), "not held yet: colour 7; not buyable: red (%s)" % [colours])
	sounds.clear()
	_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	_check(sounds.has(0xB) and not _sub_open(), "✕ on an empty slot: refused")
	_press(Pad.UP)
	_press(Pad.CONFIRM)
	_check(_until(_sub_open), "✕: Is it OK? Yes No")
	_press(Pad.CONFIRM)
	_check(int(gs.state["money"]) == 1000 and gs.card_count(phoenix) == 1 and shop[0] == null,
			"Yes: 5000 bits, the card, its slot emptied")
	_check(_until(_ended), "one card a call: the script goes on")
	gs.clear_trigger(4)


func _single_empty() -> void:
	gs.set_trigger(4)
	gs.state["script"]["card_shop"].fill(null)
	_run(0x0E, 5)
	_check(_until(_waiting_text) and "more" in _page_text(), "no cards: \"We don't have any more.\"")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "then the script goes on")
	gs.clear_trigger(4)


# --- selling ------------------------------------------------------------------------------------

func _sell() -> void:
	_clear_cards()
	var nanimon := _card("dw1:nanimon")
	gs.set_card_count(nanimon, 3)
	gs.state["money"] = 100
	gs.set_trigger(3)
	_run(0x0E, 5)
	_check(_until(_list_ready), "selling: the list opens")
	_check(menu.type == ItemMenu.TYPE_CARD_SELL and menu.left.item_count == _priced_cards().size(),
			"a row per priced card (%d)" % menu.left.item_count)
	var held := 0
	for r in menu.left.item_count:
		if menu.left.item(r) != 0xFF:
			held += 1
	_check(held == 1 and menu.left.item(menu.left.item_count - 1) == nanimon, "only Nanimon's row is filled")
	_press(Pad.DOWN | Pad.R1)
	_check(menu.left.top_row + menu.left.cursor == menu.left.item_count - 1, "R1 + ↓: the bottom")
	_until(_list_ready)
	_press(Pad.CONFIRM)
	_check(_until(_sub_open), "✕: the amount box")
	_check(menu.item_price == 25 and menu.max_amount == 3, "half of 50, up to the 3 held")
	_press(Pad.UP)
	_press(Pad.CONFIRM)
	_check(int(gs.state["money"]) == 150 and gs.card_count(nanimon) == 1, "2 sold: +50 bits, 1 left")
	_check(_until(_ended), "one sale a call")
	gs.clear_trigger(3)


# --- the merit shop -----------------------------------------------------------------------------

func _merit_card() -> void:
	_clear_cards()
	var phoenix := _card("dw1:phoenixmon")
	gs.set_card_count(phoenix, 1)
	gs.state["merit"] = 50
	_run(0x01)
	_check(_until(_waiting_text) and "Merit" in _page_text(), "the merit greeting")
	_press(Pad.CONFIRM)
	_check(_until(_choice_shown), "Show a card / Use Merit points / See ya")
	_check(_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_OPEN, 30) and _line_text(8).ends_with("50"),
			"the points box: %s" % _line_text(8))
	_press(Pad.CONFIRM)
	_check(_until(_list_ready) and menu.type == ItemMenu.TYPE_CARD_SHOW, "Show a card: the card list (type 6)")
	_check(menu.left.item(0) == phoenix and menu.left.second(0) == 1, "Phoenixmon, 1 held")
	_press(Pad.CONFIRM)
	_check(_until(_waiting_text) and "rare" in _page_text() and "100" in _page_text(),
			"class 0: \"very rare … 100points\": %s" % _page_text())
	_press(Pad.CONFIRM)
	_check(_until(_choice_shown), "Give it / Cancel")
	_press(Pad.CONFIRM)
	_check(int(gs.state["merit"]) == 150 and gs.card_count(phoenix) == 0, "Give it: +100 points, the card gone")
	_check(_until(_choice_shown), "back at the choice")
	_check(_until(func(): return _line_text(8).ends_with("150"), 30), "the points box updates: %s" % _line_text(8))
	gs.state["merit"] = 9950
	gs.set_card_count(phoenix, 1)
	_press(Pad.CONFIRM)
	_until(_list_ready)
	_press(Pad.CONFIRM)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_choice_shown)
	_press(Pad.CONFIRM)
	_check(int(gs.state["merit"]) == 9999, "merit capped at 9999")
	_until(_choice_shown)
	_press(Pad.CONFIRM)
	_until(_list_ready)
	_press(Pad.TRIANGLE)
	_check(_until(_choice_shown), "△ in the card list: the choice again")
	_press(Pad.TRIANGLE)
	_check(_until(_waiting_text) and ctx.textbox_mode == 1, "△ on the choice: See ya")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "the merit shop ends")


func _merit_item() -> void:
	_set_inventory({})
	gs.state["merit"] = 9999
	var priced: Array = data.records("items/item_data").filter(func(r): return int(r.get("merit", 0)) > 0)
	_run(0x01)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_choice_shown)
	_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	_check(_until(_list_ready) and menu.type == ItemMenu.TYPE_MERIT, "Use Merit points: the item list (type 7)")
	_check(menu.right.item_count == priced.size() and menu.right.item(0) == int(priced[0]["id"]),
			"a row per item with a merit price (%d)" % menu.right.item_count)
	var item := menu.right.item(0)
	var price := int(data.item(item)["merit"])
	_press(Pad.CONFIRM)
	_check(ctx.shop_variable == price and _until(_choice_shown), "✕: OK / Cancel")
	_press(Pad.CONFIRM)
	_check(int(gs.state["merit"]) == 9999 - price and gs.item_count(item) == 1, "OK: the item for %d points" % price)
	_until(_choice_shown)
	gs.state["merit"] = 0
	_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	_until(_list_ready)
	_check(menu.right.second(0) == 0, "no points: not available")
	sounds.clear()
	_press(Pad.CONFIRM)
	_check(sounds.has(0xB) and ctx.state_2 == 1, "✕ on it: refused")
	_press(Pad.TRIANGLE)
	_check(_until(_choice_shown), "△ in the item list: the choice again")
	_press(Pad.TRIANGLE)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_check(_until(_ended), "the merit shop ends")
	_check(_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_CLOSED, 30), "See ya closes the points box")


# --- Mojyamon -----------------------------------------------------------------------------------

func _mojyamon_start(trade_set: int) -> void:
	gs.set_script_value(TradeMenu.PSTAT_PICKED, trade_set)
	_run(0x02)
	_until(_waiting_text)
	_press(Pad.CONFIRM)


## The trade box takes input: its page flipped (the tick flips it) and ✕ seen released (the tick's
## isXPressedAfterDialogue, a frame after the flip).
func _trade_ready() -> bool:
	var e: TextBoxes.Entry = tb.entries[1]
	return ctx.state_2 == 1 and ctx.textbox_mode == 0 and boxes.boxes[1].state == UIBoxes.STATE_OPEN \
			and e.write_count == e.render_count and e.page_ready == 0 and tb.fresh_dialogue == 0 \
			and boxes.boxes[0].state == UIBoxes.STATE_OPEN


func _mojyamon_trade() -> void:
	var meat := _item("dw1:giant_meat")
	var pilot := _item("dw1:auto_pilot")
	_check(meat >= 0 and pilot >= 0, "the items exist")
	var long_name := false
	for record in data.system("mojyamon_trades"):
		for trade in record.get("trades", []):
			if area.font.to_bytes(data.localize(data.item(int(trade["give"]["id"])).get("name"))).size() > 16:
				long_name = true
	_check(not long_name, "no give item over 16 bytes (padWithSpaces)")
	_set_inventory({"dw1:giant_meat": 1})
	for t in range(5, 15):
		gs.clear_trigger(t)
	for t in range(5, 14):
		if t != 8:
			gs.set_trigger(t)
	_mojyamon_start(1)
	_check(_until(_trade_ready), "the trade box opens")
	_check(menu.left.item_count == 3 and menu.left.item(0) == meat | 0x80 and menu.left.item(1) & 0x80 == 0,
			"set 1: Giant Meat held, Black trout not")
	_check(menu.right.item(0) == pilot, "Giant Meat → Auto Pilot")
	var text := _list_text()
	_check("Giant Meat" in text and "Auto Pilot" in text, "the rows: %s" % text)
	_check("-Black trout" in text.replace(" ", "") or "- Black" in text or "-Black" in text,
			"a traded row (trigger 6 set) is marked: %s" % text)
	_press(Pad.CONFIRM)
	_check(_until(_waiting_text) and "Giant Meat" in _page_text(), "\"You'll really give me Giant Meat?\"")
	_press(Pad.CONFIRM)
	_check(_until(_choice_shown), "Yeah / Well..., no")
	_press(Pad.CONFIRM)
	_check(gs.item_count(meat) == 0 and gs.item_count(pilot) == 1, "traded: the meat for the Auto Pilot")
	_check(gs.is_trigger_set(8) and gs.is_trigger_set(14), "trigger 1 × 3 + 0 + 5 set, then all 5-13: 14")
	_check(_until(_waiting_text) and "Thanks" in _page_text(), "\"Thanks!\"")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "one trade a call")


func _mojyamon_refused() -> void:
	_set_inventory({})
	_mojyamon_start(1)
	_until(_trade_ready)
	sounds.clear()
	_press(Pad.CONFIRM)
	_check(sounds.has(0xB) and ctx.state_2 == 1 and ctx.textbox_mode == 0, "✕ on an item not held: refused")
	_press(Pad.TRIANGLE)
	_check(_until(_waiting_text) and "trade all the time" in _page_text(), "△: \"I'll trade all the time …\"")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "△ ends the talk")
	_set_inventory({"dw1:giant_meat": 1})
	_mojyamon_start(1)
	_until(_trade_ready)
	_press(Pad.CONFIRM)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_choice_shown)
	_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	_check(_until(_waiting_text) and "trade all the time" in _page_text(), "Well..., no: the same line")
	_press(Pad.CONFIRM)
	_check(_until(_ended) and gs.item_count("dw1:giant_meat") == 1, "and nothing traded")


func _mojyamon_full() -> void:
	# Every slot holds something else: the Auto Pilot doesn't fit.
	_set_inventory({})
	var slots: Array = gs.state["inventory"]["slots"]
	var size := int(gs.state["inventory"]["size"])
	var filler: Array = data.records("items/item_data").filter(func(r):
		return not str(r["key"]) in ["dw1:giant_meat", "dw1:auto_pilot"])
	gs.give_item("dw1:giant_meat", 1)
	for i in range(1, size):
		gs.give_item(filler[i]["key"], 1)
	_check(not slots.slice(0, size).has(null), "the inventory is full")
	_mojyamon_start(1)
	_until(_trade_ready)
	_press(Pad.CONFIRM)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_choice_shown)
	_press(Pad.CONFIRM)
	_check(_until(_waiting_text) and "Too many" in _page_text(), "\"Too many Items.\"")
	_check(gs.item_count("dw1:giant_meat") == 1, "nothing traded")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "the talk ends")


# --- one item menu for all ----------------------------------------------------------------------

func _shared_bits_box() -> void:
	# 0x0F (the bits box, ShopRoutines), then a single card (CardShopRoutines): the box updates.
	_clear_cards()
	gs.set_trigger(4)
	var shop: Array = gs.state["script"]["card_shop"]
	shop.fill(null)
	shop[0] = "dw1:nanimon"
	gs.state["money"] = 1234
	_run_code([0x64, 0x0F, 0x1E, 0, 0xFE, 5, 0x64, 0x0E])
	_until(_list_ready)
	_check(_line_text(8).ends_with("1234"), "the bits box: %s" % _line_text(8))
	_press(Pad.CONFIRM)
	_until(_sub_open)
	_press(Pad.CONFIRM)
	_check(_until(_ended), "bought")
	_check(_until(func(): return _line_text(8).ends_with("1184"), 30), "the bits box shows 1184: %s" % _line_text(8))
	gs.clear_trigger(4)
