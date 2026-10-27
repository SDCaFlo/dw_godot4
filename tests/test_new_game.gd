extends SceneTree
## The new game's questions and the naming screen (scripts/script/naming_routines.gd,
## scripts/ui/naming_box.gd; specs/new_game.md §2.3-2.5), driven frame by frame with a fake pad:
##   godot --headless --path . -s res://tests/test_new_game.gd
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
var naming: NamingRoutines
var sounds: Array = []
## The intro's frames run the machine directly (NewGameScene), the script's through the interpreter.
var _intro := false
var _intro_done := false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("scripts/MAPHEAD/script.json") or data.system("naming").is_empty():
		print("SKIP: porter output missing")
		quit(0)
		return false
	PsxMath.setup(data)
	_setup()
	_full_width()
	_cursor_moves()
	_typing()
	for path in [[0, 0, 0], [0, 1, 1], [1, 0, 0], [1, 1, 1]]:
		_questions(path[0], path[1], path[2])
	_name_again()
	_rename()
	_boot_partner()
	_teardown()
	print("%s: new game checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
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
	routines.add_child(load("res://scenes/script/naming_routines.tscn").instantiate())
	root.add_child(routines)
	routines.configure(ctx, tb, gs, data)
	interp.routines = routines
	naming = routines.node_for(0x20) as NamingRoutines


func _teardown() -> void:
	routines.free()
	boxes.free()
	gs.free()
	data.free()


func _frame(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	if _intro:
		tb.tick_textbox_handling()
		if not _intro_done and naming.new_game_tick():
			_intro_done = true
	else:
		interp.tick_script()
	boxes.step()


func _press(button: int) -> void:
	_frame()
	_frame(button)
	_frame()


func _until(done: Callable, limit := 200) -> bool:
	for i in limit:
		if done.call():
			return true
		_frame()
	return done.call()


func _waiting_text() -> bool:
	return ctx.state_2 == 1 and ctx.textbox_mode in [1, 2] and boxes.boxes[0].state == UIBoxes.STATE_OPEN \
			and tb.entries[0].write_count == tb.entries[0].render_count and tb.entries[0].idle == 0


## Box 0's line confirmed; false if nothing was waiting.
func _next_line() -> bool:
	if not _until(func(): return _waiting_text() and ctx.textbox_mode == 1):
		return false
	_press(Pad.CONFIRM)
	return true


func _choose(choice: int) -> bool:
	if not _until(func(): return _waiting_text() and ctx.textbox_mode == 2):
		return false
	for i in choice:
		_press(Pad.DOWN)
	_press(Pad.CONFIRM)
	return true


func _naming_ready() -> bool:
	var e: TextBoxes.Entry = tb.entries[1]
	return ctx.state_2 == 1 and boxes.boxes[1].state == UIBoxes.STATE_OPEN and boxes.boxes[2].state == UIBoxes.STATE_OPEN \
			and e.write_count == e.render_count and e.page_ready == 0 and tb.fresh_dialogue == 0


## Types `text` (letters of the US page) on the open naming screen, then OK.
func _type(text: String) -> void:
	for c in text:
		var cell := _cell_of(NamingRoutines.to_full_width(c))
		naming.naming.selector = cell
		_press(Pad.CONFIRM)
	_press(Pad.START)
	_press(Pad.CONFIRM)


func _cell_of(c: String) -> int:
	for cell in NamingBox.ROWS * 2 * NamingBox.COLUMNS:
		if naming.naming.character(cell) == c:
			return cell
	return -1


func _start_intro() -> void:
	_intro = true
	_intro_done = false
	gs.new_game()
	naming.new_game_start()


# --- checks ------------------------------------------------------------------------------------------

func _full_width() -> void:
	_check(NamingRoutines.from_full_width("ＡｂＣ０　ア") == "AbC0 ア", "full-width letters become ASCII")
	_check(NamingRoutines.to_full_width("Agumon!") == "Ａｇｕｍｏｎ", "ASCII becomes full width, 6 letters")
	_check(NamingRoutines.to_full_width("A B") == "Ａ　Ｂ", "a space becomes the full-width space")


func _cursor_moves() -> void:
	var n := naming.naming
	n._load_pages()
	_check(n.character(0) == "Ａ" and n.character(9 * 5) == "ａ" and n.character(16 * 5 + 4) == "９",
			"the US page: A, a, 9 where the C has them")
	n.selector = 0
	n.move_left(0, 0, 0)
	_check(n.selector == NamingBox.BUTTON | NamingBox.BACK, "← from the left edge goes to Back")
	n.move_left(0, 0, 0)
	_check(n.selector == 74, "← from a button: cell 0x19 + 0x31")
	n.move_right(4, 14, 0)
	_check(n.selector == NamingBox.BUTTON | NamingBox.BACK, "→ from the right half's edge goes to Back")
	n.move_right(0, 0, 0)
	_check(n.selector == 25, "→ from a button: cell 0x19")
	n.selector = 4
	n.move_right(4, 0, 0)
	_check(n.selector == 45, "→ from the left half's edge: the right half's first column")
	n.selector = 45
	n.move_left(0, 9, 0)
	_check(n.selector == 4, "← from the right half's first column: the left half's last")
	n.selector = 2
	n.move_up(2, 0)
	_check(n.selector == 42, "↑ wraps within the left half (row 8)")
	n.selector = 47
	n.move_up(2, 9)
	_check(n.selector == 87, "↑ wraps within the right half (row 17)")
	n.move_down(2, 17)
	_check(n.selector == 47, "↓ wraps back to row 9")
	n.selector = NamingBox.BUTTON | NamingBox.BACK
	n.move_up(0, 0)
	_check(n.selector == NamingBox.BUTTON | NamingBox.OK, "↑ on Back: OK")
	n.move_down(0, 0)
	_check(n.selector == NamingBox.BUTTON | NamingBox.BACK, "↓ on OK: Back")
	n.buffer = "Ａ　　"
	n.terminate()
	_check(n.buffer == "Ａ", "trailing full-width spaces cut")


## The naming screen opened by a rename (value 3), checked letter by letter.
func _typing() -> void:
	_intro = false
	gs.state["partner"]["name"] = ""
	gs.state["tamer"]["name"] = "Tamer"
	gs.set_script_value(0xFE, 3)
	interp.call_section(_script([0x64, 0x20]), 1)
	_frame()
	_check(_until(_naming_ready), "renaming opens the naming screen at once")
	var n := naming.naming
	n.selector = _cell_of("　")
	sounds.clear()
	_press(Pad.CONFIRM)
	_check(n.buffer == "" and sounds == [0xB], "a full-width space can't start a name")
	_press(Pad.START)
	_press(Pad.CONFIRM)
	_check(ctx.state_2 == 1 and sounds.has(0xB), "OK on an empty name is refused")
	for c in "ABCDEF":
		n.selector = _cell_of(NamingRoutines.to_full_width(c))
		_press(Pad.CONFIRM)
	_check(n.buffer == "ＡＢＣＤＥＦ" and n.letter == 5, "six letters, the cursor on the 6th")
	_check(n.selector == NamingBox.BUTTON | NamingBox.OK, "the 6th letter moves the cursor to OK")
	n.selector = _cell_of("Ｇ")
	_press(Pad.CONFIRM)
	_check(n.buffer == "ＡＢＣＤＥＧ", "a 7th letter replaces the 6th")
	_press(Pad.CANCEL)
	_check(n.buffer == "ＡＢＣＤ" and n.letter == 4, "△ on a full name: the 6th and 5th go (US quirk)")
	n.selector = NamingBox.BUTTON | NamingBox.BACK
	_press(Pad.CONFIRM)
	_check(n.buffer == "ＡＢＣ" and n.letter == 3, "Back deletes the last letter")
	_press(Pad.ALT)
	_check(n.selector == NamingBox.BUTTON | NamingBox.BACK, "○ jumps to Back")
	_press(Pad.SQUARE)
	_check(n.buffer == "" and n.letter == 0, "□ clears the name")
	_type("Gabu")
	_check(_until(func(): return ctx.active_instruction == 0), "the rename ends once box 1 has closed")
	_check(gs.state["partner"]["name"] == "Gabu" and gs.state["tamer"]["name"] == "Tamer",
			"only the partner's name changed")
	_check(not tb.fixed_width and pad.repeat_mask == 0, "fixed width and the input repeat are off again")


## The whole intro: the answers, the names, the end.
func _questions(digivice: int, second: int, expected: int) -> void:
	_start_intro()
	var what := "answers %d / %d" % [digivice, second]
	var ok := _next_line() and _next_line() and _choose(digivice) and _next_line() and _next_line() and \
			_choose(second) and _next_line() and _next_line()
	_check(ok and gs.is_trigger_set(ScriptContext.TRIGGER_NO_CANCEL), what + ": the questions, trigger 49 set")
	_check(gs.script_value(0xFE) == expected, what + ": value 0xFE = %d" % expected)
	_check(_until(_naming_ready), what + ": the tamer's naming screen")
	_check(naming.naming.buffer == "" and gs.state["tamer"]["name"] == "", what + ": the tamer's name starts empty")
	_type("Taichi")
	ok = _next_line() and _choose(0) and _next_line()
	_check(ok and gs.state["tamer"]["name"] == "Taichi", what + ": the tamer's name")
	_check(_until(_naming_ready) and naming.naming.partner and naming.naming.buffer == "",
			what + ": the partner's naming starts empty")
	_type("Agu")
	ok = _next_line() and _choose(0) and _next_line() and _next_line()
	_check(ok and _until(func(): return _intro_done), what + ": the intro ends")
	_check(gs.state["partner"]["name"] == "Agu", what + ": the partner's name")
	_check(not gs.is_trigger_set(ScriptContext.TRIGGER_NO_CANCEL), what + ": trigger 49 unset at the end")


## "No" to "<name>, right?": the naming again, with the name kept.
func _name_again() -> void:
	_start_intro()
	for step in [_next_line, _next_line, func(): return _choose(0), _next_line, _next_line, func(): return _choose(0),
			_next_line, _next_line]:
		step.call()
	_until(_naming_ready)
	_type("Abc")
	_next_line()
	_choose(1)
	_check(_until(_naming_ready) and naming.naming.buffer == "Ａｂｃ" and not naming.naming.partner,
			"No: the tamer's naming again, the name kept")
	_check(naming.naming.letter == 3, "the cursor after the kept name")


## The script's rename: value 3, the partner's current name to start from.
func _rename() -> void:
	_intro = false
	gs.state["partner"]["name"] = "Digimon"
	gs.set_script_value(0xFE, 3)
	interp.call_section(_script([0x64, 0x20]), 1)
	_frame()
	_check(_until(_naming_ready) and naming.naming.buffer == "Ｄｉｇｉｍｏ" and naming.naming.letter == 5,
			"renaming starts from the current name (6 letters)")
	_press(Pad.START)
	_press(Pad.CONFIRM)
	_check(_until(func(): return ctx.active_instruction == 0) and gs.state["partner"]["name"] == "Digimo",
			"OK keeps it")


## GameState.start_new_game_partner: the answer's partner (systems/new_game), marked raised.
func _boot_partner() -> void:
	for answer in 2:
		gs.new_game()
		gs.start_new_game_partner(answer)
		var key: String = gs.state["partner"]["digimon"]
		var expected := "dw1:agumon" if answer == 0 else "dw1:gabumon"
		_check(key == expected and gs.is_trigger_set(0x200 + data.id_of("digimon/digimon_data", key)),
				"answer %d: %s, raised" % [answer, expected])


## A one-section script running `ops`, then END.
func _script(ops: Array) -> int:
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(ops + [0xFE, 0]))
	files._cache[500] = bytes
	return 500
