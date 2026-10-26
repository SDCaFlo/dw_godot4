extends SceneTree
## The item keeper (0x0B), the jukebox (0x09) and Birdramon's transport (0x0A) (scripts/script/
## item_keeper_routines.gd, jukebox_routines.gd, birdramon_routines.gd, scripts/ui/keeper_menu.gd,
## item_menu.gd; specs/town_services.md) run by the interpreter on small scripts:
##   godot --headless --path . -s res://tests/test_town_services.gd
## Exits 1 if a check fails.

## The music player's calls, in order.
class FakeMusic extends Node:
	var active_bgm_font := 1
	var active_bgm_track := 1
	var calls: Array = []

	func stop_bgm() -> void:
		calls.append(["stop_bgm"])

	func play_music(font: int, track: int) -> int:
		calls.append(["play_music", font, track])
		return 1

	func play_bgm(id: int) -> void:
		calls.append(["play_bgm", id])


class FakeSound extends Node:
	var music: FakeMusic


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
var keeper: KeeperMenu
var music: FakeMusic
var fake_sound: FakeSound
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
	_keeper()
	_keeper_last_item()
	_keeper_no()
	_jukebox()
	_jukebox_unlocked()
	_birdramon_cancel()
	_birdramon_flight()
	_teardown()
	print("%s: town service checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
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
	music = FakeMusic.new()
	fake_sound = FakeSound.new()
	fake_sound.music = music
	routines = ScriptRoutines.new()
	for scene in ["shop", "item_keeper", "jukebox", "birdramon"]:
		routines.add_child(load("res://scenes/script/%s_routines.tscn" % scene).instantiate())
	root.add_child(routines)
	routines.configure(ctx, tb, gs, data, fake_sound)
	interp.routines = routines
	menu = routines.menu
	keeper = (routines.node_for(0x0B) as ItemKeeperRoutines).keeper


func _teardown() -> void:
	routines.free()
	boxes.free()
	music.free()
	fake_sound.free()
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


## value 0xFE = `owner`, SET_DIALOG_OWNER `owner`, CALL_ROUTINE `routine`, value 50 = 1, END.
func _run(routine: int, owner := 0xFF) -> void:
	gs.set_script_value(50, 0)
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray([0x1E, 0, 0xFE, owner, 0x1B, owner, 0x64, routine, 0x1E, 0, 50, 1, 0xFE, 0]))
	files._cache[500] = bytes
	interp.call_section(500, 1)
	_frame()


func _ended() -> bool:
	return gs.script_value(50) == 1


func _waiting_text() -> bool:
	return ctx.state_2 == 1 and ctx.textbox_mode in [1, 2] and boxes.boxes[0].state == UIBoxes.STATE_OPEN \
			and tb.entries[0].write_count == tb.entries[0].render_count and tb.entries[0].idle == 0


func _choice_shown() -> bool:
	return _waiting_text() and ctx.textbox_mode == 2


## A box's page drawn and flipped (its tick flips it) and ✕ seen released.
func _page_settled(id: int) -> bool:
	var e: TextBoxes.Entry = tb.entries[id]
	return boxes.boxes[id].state == UIBoxes.STATE_OPEN and e.write_count == e.render_count and e.page_ready == 0


func _list_ready() -> bool:
	return ctx.state_2 == 1 and ctx.textbox_mode == 0 and boxes.boxes[0].state == UIBoxes.STATE_OPEN \
			and _page_settled(1) and tb.fresh_dialogue == 0


func _keeper_ready() -> bool:
	return ctx.state_2 == 1 and ctx.textbox_mode == 0 and _page_settled(1) and _page_settled(2) \
			and tb.fresh_dialogue == 0


func _set_inventory(items: Dictionary) -> void:
	var slots: Array = gs.state["inventory"]["slots"]
	for i in slots.size():
		slots[i] = null
	for key in items:
		gs.give_item(key, items[key])


func _item(key: String) -> int:
	return data.id_of("items/item_data", key)


## A line buffer row as text (ASCII bytes, full-width letters and digits).
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
	return " "


func _page_text() -> String:
	var e: TextBoxes.Entry = tb.entries[0]
	var out := ""
	for r in 4:
		out += _line_text(e.back_page * 4 + r) + "|"
	return out


# --- the item keeper ----------------------------------------------------------------------------

func _open_keeper() -> void:
	_run(0x0B)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_choice_shown)
	_press(Pad.CONFIRM)


func _keeper() -> void:
	var meat := _item("dw1:meat")
	var small := _item("dw1:sm_recovery")
	_set_inventory({"dw1:meat": 95, "dw1:sm_recovery": 3})
	gs.state["script"]["item_keeper"] = {"dw1:meat": 15}
	_open_keeper()
	_check(_until(_keeper_ready), "Yes: the keeper's two boxes open")
	_check(Array(menu.left.buf) == [meat, 15 | 0x80], "storage: Meat 15, can come out: %s" % [Array(menu.left.buf)])
	_check(menu.right.item_count == int(gs.state["inventory"]["size"]) and Array(menu.right.buf.slice(0, 4))
			== [meat, 95 | 0x80, small, 3 | 0x80], "inventory: a row per slot")
	_press(Pad.CONFIRM)
	_check(gs.item_count(meat) == 96 and keeper.stored(meat) == 14, "✕: one out (96 / 14)")
	_until(_keeper_ready)
	_press(Pad.ALT)
	_check(gs.item_count(meat) == 96 and keeper.stored(meat) == 14, "○: refused, 96 held is not below 90")
	_until(_keeper_ready)
	_press(Pad.SQUARE)
	_check(gs.item_count(meat) == 99 and keeper.stored(meat) == 11, "□: 3 out (up to 99), 11 stay")
	_until(_keeper_ready)
	sounds.clear()
	_press(Pad.RIGHT)
	_check(keeper.side == 1 and sounds.has(2), "→: the inventory side")
	_until(_keeper_ready)
	_press(Pad.CONFIRM)
	_check(gs.item_count(meat) == 98 and keeper.stored(meat) == 12, "✕: one in (98 / 12)")
	_until(_keeper_ready)
	_press(Pad.ALT)
	_check(gs.item_count(meat) == 88 and keeper.stored(meat) == 22, "○: ten in (88 / 22)")
	_until(_keeper_ready)
	keeper.set_stored(meat, 99)
	keeper.fill()
	_check(menu.right.second(0) & 0x80 == 0, "stored 99: the inventory row can't go in")
	_press(Pad.CONFIRM)
	_check(keeper.stored(meat) == 99 and gs.item_count(meat) == 88, "and ✕ moves nothing")
	_until(_keeper_ready)
	_press(Pad.START)
	_check(_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN, 30), "START: the description")
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_CLOSED and boxes.boxes[3].frame == 0, 30)
	_until(_keeper_ready)
	_press(Pad.TRIANGLE)
	_check(_until(_waiting_text) and "when you need it" in _page_text(), "△: \"Come to this shop …\"")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "the keeper ends")


func _keeper_last_item() -> void:
	_set_inventory({"dw1:meat": 5})
	gs.state["script"]["item_keeper"] = {"dw1:sm_recovery": 1, "dw1:meat": 30}
	_open_keeper()
	_until(_keeper_ready)
	_check(menu.left.item_count == 2 and menu.left.item(0) == _item("dw1:sm_recovery"), "stored in id order")
	_press(Pad.CONFIRM)
	_check(menu.left.item_count == 1 and menu.left.top_row + menu.left.cursor < 1,
			"the last one out: its row goes, the cursor stays in range")
	_check(menu.right.item(menu.right.top_row + menu.right.cursor) == _item("dw1:sm_recovery"),
			"the inventory side follows the item")
	_until(_keeper_ready)
	_press(Pad.TRIANGLE)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_check(_until(_ended), "the keeper ends")


func _keeper_no() -> void:
	_run(0x0B)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_choice_shown)
	_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	_check(_until(_waiting_text) and "when you need it" in _page_text(), "No: \"Come to this shop …\"")
	_press(Pad.CONFIRM)
	_check(_until(_ended) and boxes.boxes[1].state == UIBoxes.STATE_CLOSED, "and the end, no boxes")


# --- the jukebox --------------------------------------------------------------------------------

func _jukebox() -> void:
	gs.clear_trigger(50)
	music.active_bgm_font = 1
	music.active_bgm_track = 1
	music.calls.clear()
	_run(0x09)
	_check(_until(_waiting_text) and gs.script_value(ItemMenu.PSTAT_TRACK) == 1, "track 1 (font 1, 1) is playing")
	_press(Pad.CONFIRM)
	_check(_until(_list_ready), "the track list opens")
	_check(menu.left.item_count == 62, "62 tracks before trigger 50 (%d)" % menu.left.item_count)
	_check(menu.left.top_row == 0 and menu.left.cursor == 1, "the cursor on the playing track")
	_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	_check(gs.script_value(ItemMenu.PSTAT_TRACK) == 2, "✕: value 249 = track 2")
	_check(_until(func(): return music.calls.has(["play_music", 2, 0]), 30), "its music starts: %s" % [music.calls])
	_check("Tropical Theme" in _page_text(), "\"{track}, right?\": %s" % _page_text())
	_until(_list_ready)
	music.calls.clear()
	_press(Pad.TRIANGLE)
	_check(_until(_waiting_text) and "next request" in _page_text(), "△: \"Help me on my next request.\"")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "the jukebox ends")
	_check(music.calls.has(["play_bgm", 1]), "the map's music again: %s" % [music.calls])


func _jukebox_unlocked() -> void:
	gs.set_trigger(50)
	music.active_bgm_font = 0x30
	music.calls.clear()
	_run(0x09)
	_until(_waiting_text)
	_check(gs.script_value(ItemMenu.PSTAT_TRACK) == 0xFF and music.calls.has(["stop_bgm"]),
			"no track playing: value 249 = 0xFF, the music stops")
	_press(Pad.CONFIRM)
	_until(_list_ready)
	_check(menu.left.item_count == 63 and menu.left.cursor == 0, "63 tracks once trigger 50 is set, cursor on 0")
	_press(Pad.TRIANGLE)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_check(_until(_ended), "the jukebox ends")
	gs.clear_trigger(50)


# --- Birdramon ----------------------------------------------------------------------------------

func _birdramon_setup() -> void:
	for record in data.system("birdramon_transport"):
		gs.clear_trigger(int(record["trigger"]))
	gs.set_trigger(221)
	gs.set_trigger(351)
	gs.state["money"] = 1500


func _birdramon_cancel() -> void:
	_birdramon_setup()
	_run(0x0A, 5)
	_check(_until(_waiting_text) and "Where should" in _page_text(), "\"Where should I take you?\"")
	_press(Pad.CONFIRM)
	_check(_until(_list_ready), "the destinations")
	_check(Array(menu.left.buf) == [0x80, 0, 3, 0], "Great Canyon affordable, Freezeland (2000) red: %s" % [Array(menu.left.buf)])
	_check(boxes.boxes[2].state != UIBoxes.STATE_CLOSED, "the bits box")
	var text := ""
	for r in range(9, 21):
		text += _line_text(r) + "|"
	_check("Great Canyon Top Area" in text and "1000" in text, "a row: the map's name, the cost: %s" % text)
	sounds.clear()
	_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	_check(sounds.has(0xB) and ctx.state_2 == 1 and ctx.textbox_mode == 0, "✕ on a red row: refused")
	_press(Pad.UP)
	_press(Pad.CONFIRM)
	_check(_until(_waiting_text) and "back" in _page_text(), "\"Are you sure? … can't take you back.\"")
	_press(Pad.CONFIRM)
	_check(_until(_choice_shown), "I know / Cancel")
	_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	_check(_until(_waiting_text) and "going yourself" in _page_text(), "Cancel: \"… going yourself …\"")
	_press(Pad.CONFIRM)
	_check(_until(_ended) and int(gs.state["money"]) == 1500, "the end, the bits kept")
	_run(0x0A, 5)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_list_ready)
	_press(Pad.TRIANGLE)
	_check(_until(_waiting_text) and "going yourself" in _page_text(), "△: the same line")
	_press(Pad.CONFIRM)
	_check(_until(_ended), "and the end")


func _birdramon_flight() -> void:
	_birdramon_setup()
	_run(0x0A, 5)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_list_ready)
	_press(Pad.CONFIRM)
	_until(_waiting_text)
	_press(Pad.CONFIRM)
	_until(_choice_shown)
	_press(Pad.CONFIRM)
	_check(int(gs.state["money"]) == 500, "I know: 1000 bits paid")
	_check(gs.script_value(BirdramonRoutines.PSTAT_MAP) == 38 and gs.script_value(BirdramonRoutines.PSTAT_ENTRANCE) == 9,
			"values 247 / 248 = map 38, entrance 9")
	_check(ctx.code_id == ScriptFiles.MAPHEAD, "the script goes on in MAPHEAD")
	_check(_until(func(): return "Hold on tight" in _page_text()), "section 0x4E3: \"Hold on tight!\"")
	_check(not _ended(), "the original script doesn't go on")
