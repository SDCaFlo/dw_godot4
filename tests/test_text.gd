extends SceneTree
## The text renderer (scripts/ui/) against specs/text.md §2, values worked out from the C:
##   godot --headless --path . -s res://tests/test_text.gd
## Exits 1 if a check fails. Needs the data porter output (font group).

var _failed := 0
## Checks run: a script error aborts a test function silently, so the count shows it.
var _checks := 0
var _frames := 0
var data: Node
var boxes: UIBoxes


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		data = load("res://scripts/data/game_data.gd").new()
		if not data.available() or data.font("en_us").is_empty():
			print("SKIP: data porter output (font) missing")
			quit(0)
			return false
		_font()
		_text_area()
		_boxes()
		_message_box_and_tamer()
		_pad()
		_draw_string2()
		_show_textbox()
		_dialogue_pages()
		_dialogue_choice()
		# Drawn by the engine in the next frames: the frame, the text and the arrow must not error.
		boxes = UIBoxes.new()
		root.add_child(boxes)
		var area := TextArea.new(data, "en_us")
		area.draw_string("Drawing test", 0, 120)
		var box := MessageBox.new(boxes, area)
		box.open(Rect2i(-5, -5, 10, 10))
		for i in 7:
			boxes.step()
		_eq(boxes.boxes[1].drawn, UIBoxes.DRAWN_STATIC, "drawing test box open")
	elif _frames == 4:
		boxes.queue_free()
		data.free()
		print("%s: text checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
		quit(1 if _failed else 0)
	return false


func _font() -> void:
	var us := PsxFont.new(data, "en_us")
	_eq(us.glyphs.size(), 79, "US glyphs")
	_eq(Array(us.encode("A.'z0 ")), [0x8260, 0x8142, 0x8175, 0x829A, 0x824F, 0x8140], "drawString codes (. and ' overridden)")
	_eq(Array(us.encode("'", false)), [0x8166], "convertAsciiToJis without the override")
	_eq(us.glyph_index(0x8260), 0, "Ａ is glyph 0")
	# & is 0x8195: not in the US table, so the search ends on the last entry (×).
	_eq([us.encode("&")[0], us.glyph_index(us.encode("&")[0])], [0x8195, 78], "unknown code -> the last glyph")
	_eq(us.glyph_index(us.encode("€")[0]), 78, "a character with no code -> the last glyph")
	_eq(us.glyph_index(us.encode("Ａ")[0]), 0, "a full-width character keeps its code")
	_eq([us.advance(0x8260), us.advance(0x8281), us.advance(0x8140)], [12, 8, 4], "US widths: Ａ 12, ａ 8, space 4")
	var eu := PsxFont.new(data, "en_eu")
	_eq([eu.advance(0x8260), eu.advance(0x8140), eu.glyph_width], [8, 8, 8], "EU: Ａ narrow, the space 8, GLYPH_WIDTH 8")
	var ja := PsxFont.new(data, "ja")
	_eq([ja.glyphs.size(), ja.encode("ア")[0], ja.advance(0x8341)], [992, 0x8341, 0], "JP: ア, drawGlyph returns nothing")


func _text_area() -> void:
	var area := TextArea.new(data, "en_us")
	area.set_text_color(3)
	var w := area.draw_glyph(0x8260, 0, 0)
	var rows: Array = data.font("en_us")[0]["rows"]
	var same := true
	for y in 11:
		for x in 12:
			if area.pixel(x, y) != (3 if PsxFont.is_ink(rows, x, y) else 0):
				same = false
	_eq([w, same], [12, true], "Ａ drawn from its rows in colour 3")
	_eq(area.pixel(12, 0), 0, "outside the cell untouched")
	area.clear_all()
	area.draw_glyph(0x8260, 5, 20)
	# Ａ row 5 (0x80FF) has ink in columns 1-7: from the cell at x 4 that is pixels 5-11 (at x 5 it would be 6-12).
	_eq([area.pixel(5, 25), area.pixel(11, 25), area.pixel(12, 25)], [3, 3, 0], "x 5 lands on the cell at x 4 (VRAM words)")
	_eq(area.draw_glyph(0x8260, 244, 0), 0, "clipped at x 244")
	_eq(area.draw_glyph(0x8260, 0, 244), 0, "clipped at y 244")
	_eq(area.draw_glyph(0x8260, -1, 0), 0, "negative x is clipped (uint16)")
	area.clear_all()
	_eq(area.draw_string("Ab", 0, 40), 20, "drawString advances by the widths (12 + 8)")
	area.set_text_color(1)
	area.draw_string("A", 0, 60)
	area.clear(Rect2i(5, 60, 7, 11))
	# x 5 / 4 = 1 word, w 7 >> 2 = 1 word: pixels 4-7 cleared, 8-11 kept.
	var row := 60 + 5   # Ａ row 5 is 0x80FF: ink at 1-7
	_eq([area.pixel(1, row), area.pixel(4, row), area.pixel(7, row)], [1, 0, 0], "clearTextSubArea in 4-pixel words")
	_eq(area.tint(0), Color(1, 1, 1), "TEXT_COLORS[0] = 0x80: unchanged")
	_eq(area.tint(3).r > 1.9, true, "TEXT_COLORS[3] red 0xff: brighter than the texture")
	var ja := TextArea.new(data, "ja")
	_eq(ja.draw_string("アイ", 0, 0), 24, "JP drawString: GLYPH_WIDTH per glyph")
	var eu := TextArea.new(data, "en_eu")
	_eq(eu.draw_codes(PackedInt32Array([0x8260, 0x8140, 0x8260]), 0, 0), 24, "EU: Ａ 8, space 8, Ａ 8")


func _boxes() -> void:
	var b := UIBoxes.new()
	var sounds := []
	var closed := []
	b.sound.connect(func(id): sounds.append(id))
	b.closed.connect(func(id): closed.append(id))
	var ticks := [0]
	var renders := [0]
	var start := Rect2i(-5, -5, 10, 10)
	var final := Rect2i(-130, 42, 262, 59)
	b.create_animated(1, 0, UIBoxes.FEATURE_HALF_FILL, final, start, func(_id): ticks[0] += 1, Callable(), func(_id): renders[0] += 1)
	_eq([sounds, b.boxes[1].state, b.is_available(1)], [[0], UIBoxes.STATE_OPENING, true], "created: sound 0, opening, frame still 0")
	var drawn := []
	for i in 6:
		b.step()
		drawn.append(b.boxes[1].drawn)
		if i == 0:
			_eq(b.is_available(1), false, "not available while it animates")
	_eq(drawn, [0, 1, 2, 3, 4, UIBoxes.DRAWN_STATIC], "outline frames 0-4, then the open box")
	_eq([b.boxes[1].state, b.is_available(1), ticks[0], renders[0]], [UIBoxes.STATE_OPEN, true, 1, 1],
			"open: available; tick and render only once it is open")
	_eq(UIBoxes.anim_rect(start, final, 2), Rect2i(-67, 18, 135, 35), "frame 2: start + 2 * (final - start) / 4, truncated")
	_eq([UIBoxes.anim_rect(start, final, 0), UIBoxes.anim_rect(start, final, 4)], [start, final], "frames 0 and 4")
	b.remove_animated(1, Rect2i(0, 0, 10, 10))
	drawn = []
	for i in 6:
		b.step()
		drawn.append(b.boxes[1].drawn)
	_eq(drawn, [4, 3, 2, 1, 0, UIBoxes.DRAWN_NOTHING], "closing: frames 4-0, then nothing")
	_eq([sounds, closed, b.boxes[1].state, b.boxes[1].start, b.is_available(1)], [[0, 1], [1], UIBoxes.STATE_CLOSED,
			Rect2i(0, 0, 10, 10), true], "closed: sound 1 on its first frame, shrinks to the new target, free")
	b.create_static(2, 1, UIBoxes.FEATURE_TITLE, final)
	b.step()
	_eq([b.boxes[2].state, b.boxes[2].drawn], [UIBoxes.STATE_OPEN, UIBoxes.DRAWN_STATIC], "a static box is open at once")
	b.remove_static(2)
	_eq([b.boxes[2].state, b.boxes[2].registered, closed], [UIBoxes.STATE_CLOSED, false, [1, 2]], "static box removed")
	_eq([PsxDraw.word_color(UIBoxes.LIGHT).r8, PsxDraw.word_color(UIBoxes.LIGHT).b8], [0x90, 0xFA],
			"line colour words: low byte red (0xFAD990 is light blue)")
	b.free()


func _message_box_and_tamer() -> void:
	var b := UIBoxes.new()
	var area := TextArea.new(data, "en_us")
	var box := MessageBox.new(b, area)
	box.open(Rect2i(-5, -5, 10, 10))
	var arrows := []
	for i in 18:
		b.step()
		if b.boxes[1].arrow >= 0:
			arrows.append(b.boxes[1].arrow / 4 % 3 * 16 + 0x4C)
	# Opening takes 5 frames; then the arrow uses the timer before ++TEXTBOX_OPEN_TIMER.
	_eq(arrows.slice(0, 13), [0x4C, 0x4C, 0x4C, 0x4C, 0x5C, 0x5C, 0x5C, 0x5C, 0x6C, 0x6C, 0x6C, 0x6C, 0x4C],
			"next arrow: a new frame every 4 frames, 3 frames")
	_eq(b.textbox_open_timer, 13, "TEXTBOX_OPEN_TIMER counted while open")
	box.close()
	for i in 5:
		b.step()
	_eq(box.is_shown(), false, "closed")

	# tamerTickAwardSomething (tamer.c:1751).
	var gs: Node = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	var clock := Clock.new()
	clock.game_state = gs
	clock.running = true
	var partner := Partner.new()
	var tamer := Tamer.new()
	var pad := Pad.new()
	tamer.clock = clock
	tamer.partner = partner
	tamer.message_box = box
	tamer.pad = pad
	tamer.set_state(Tamer.STATE_AWARD)
	tamer.tick()
	_eq([tamer.sub_state, clock.running, partner.state, tamer.camera_follow], [4, false, Partner.STATE_IDLE, false],
			"sub-state 0: game time stops, the partner idles, the camera stops")
	tamer.tick()
	_eq([tamer.sub_state, b.boxes[1].state, b.boxes[1].start], [5, UIBoxes.STATE_OPENING, Rect2i(-5, -5, 10, 10)],
			"sub-state 4: box 1 grows from the tamer")
	pad.poll(0)
	tamer.tick()
	_eq(tamer.sub_state, 5, "waits for the confirm button")
	pad.poll(Pad.CONFIRM)
	tamer.tick()
	_eq([tamer.state, partner.state, tamer.camera_follow, clock.running, b.boxes[1].state],
			[Tamer.STATE_FREE, Partner.STATE_NORMAL, true, true, UIBoxes.STATE_CLOSING],
			"confirm held (POLLED_INPUT): the box closes, all free")
	tamer.free()
	partner.free()
	clock.free()
	gs.free()
	b.free()


func _pad() -> void:
	var pad := Pad.new()
	pad.poll(Pad.CONFIRM)
	pad.process()
	# isKeyDown takes the key from INPUT_FRESH_MASK but not from this frame's INPUT_PENDING_MASK.
	_eq([pad.is_held(Pad.CONFIRM), pad.is_changed(Pad.CONFIRM), pad.is_key_down(Pad.CONFIRM), pad.is_key_down(Pad.CONFIRM)],
			[true, true, true, true], "pressed: held, changed, isKeyDown (all of this frame)")
	pad.poll(Pad.CONFIRM)
	pad.process()
	_eq([pad.is_changed(Pad.CONFIRM), pad.is_key_down(Pad.CONFIRM)], [false, false], "still held: not new, not again")
	pad.poll(0)
	pad.process()
	pad.poll(Pad.CONFIRM)
	pad.process()
	_eq(pad.is_key_down(Pad.CONFIRM), true, "released and pressed again: counts again")
	# pollInputGame's d-pad repeat: new on frame 1, then on the 6th frame held and every 2 frames.
	pad = Pad.new()
	var changed := []
	for frame in 11:
		pad.poll(Pad.DOWN)
		if pad.is_changed(Pad.DOWN):
			changed.append(frame + 1)
	_eq(changed, [1, 6, 8, 10], "CHANGED_INPUT d-pad repeat")
	# processInput's repeat mask: once, then on the 8th frame held and every 2 frames.
	pad = Pad.new()
	pad.set_repeat_mask(0x5000)
	var downs := []
	for frame in 13:
		pad.poll(Pad.DOWN)
		pad.process()
		if pad.is_key_down(Pad.DOWN):
			downs.append(frame + 1)
	_eq(downs, [1, 8, 10, 12], "isKeyDown with INPUT_REPEAT_MASK")


## TextBoxes on a fresh UI box set, with a script context and a pad.
func _text_boxes(lang := "en_us") -> Array:
	var b := UIBoxes.new()
	var area := TextArea.new(data, lang)
	var ctx := ScriptContext.new()
	var gs: Node = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()
	ctx.game_state = gs
	ctx.data = data
	var pad := Pad.new()
	var tb := TextBoxes.new(b, area, ctx, pad, data, gs)
	return [tb, b, area, ctx, pad, gs]


func _free(parts: Array) -> void:
	parts[1].free()
	parts[5].free()


func _draw_string2() -> void:
	var parts := _text_boxes()
	var tb: TextBoxes = parts[0]
	var area: TextArea = parts[2]
	var put := func(bytes: Array) -> void:
		tb.lines.fill(0)
		for i in bytes.size():
			tb.lines[i] = bytes[i]
	var ink_at := func(x: int, y: int) -> int: return area.pixel(x, y + 5)   # Ａ row 5: ink in columns 1-7
	put.call([0x01, 3, 0x41, 0x82, 0x60, 0x0D, 0])
	area.clear_all()
	_eq(tb.draw_string2(0, 0, 0), 0, "0D ends the line: 0")
	_eq([ink_at.call(1, 0), ink_at.call(13, 0)], [3, 3], "01 3 sets the colour; ASCII A and Ａ are the same glyph, 12 apart")
	put.call([0x82, 0x81, 0x81, 0x40, 0x82, 0x60, 0])
	area.clear_all()
	area.set_text_color(1)
	_eq(tb.draw_string2(0, 0, 0), 1, "00 ends the text: 1")
	# ａ advances 8; the full-width space clears its cell and advances by the last width again (8),
	# so Ａ's ink is at 17-23 (with a 12 px space it would be at 21-27).
	_eq([ink_at.call(17, 0), ink_at.call(24, 0)], [1, 0], "quirk: the space after ａ advances 8, Ａ lands at 16")
	put.call([0x41, 0x0C, 0, 0x41, 0])
	area.clear_all()
	tb.draw_string2(0, 0, 0)
	_eq(ink_at.call(97, 0), 1, "0C: to the next multiple of 8 cells (96)")
	put.call([0x17, 0, 0x41, 0])
	area.clear_all()
	tb.draw_string2(0, 0, 0)
	_eq([ink_at.call(105, 0), ink_at.call(104, 0)], [1, 0], "17: x 105 (the cell lands on 104)")
	put.call([0x0F, 0, 0x41, 0])
	area.clear_all()
	tb.draw_string2(0, 0, 0)
	_eq(ink_at.call(5, 0), 1, "0F: 6 px blank (the cell lands on 4)")
	tb.fixed_width = true
	put.call([0x82, 0x81, 0x82, 0x60, 0])
	area.clear_all()
	tb.draw_string2(0, 0, 0)
	_eq(ink_at.call(13, 0), 1, "DRAW_STRING2_IS_FIXED_WIDTH: ａ advances 12")
	_eq(Array(TextBoxes.int_to_string_sjis(5, 3, 1)), [0x82, 0x54], "intToStringSJIS 5, 3 digits, zeros dropped")
	_eq(Array(TextBoxes.int_to_string_sjis(5, 3, 0)), [0x81, 0x40, 0x81, 0x40, 0x82, 0x54], "zeros as full-width spaces")
	_eq(Array(TextBoxes.int_to_string_sjis(0, 3, 1)), [0x82, 0x4F], "the last digit stays")
	_eq(Array(TextBoxes.int_to_string_sjis(105, 3, 1)), [0x82, 0x50, 0x82, 0x4F, 0x82, 0x54], "inner zeros stay")
	_free(parts)


func _show_textbox() -> void:
	var parts := _text_boxes()
	var tb: TextBoxes = parts[0]
	var ctx: ScriptContext = parts[3]
	var gs: Node = parts[5]
	gs.state["partner"]["name"] = "Agu"
	ctx.code = PackedByteArray([0x82, 0x60, 0x82, 0x61, 0x0D, 0, 0x82, 0x62, 0x0D, 0, 0, 0, 0x2A, 0])
	tb.setup_dialogue_box(ScriptContext.OWNER_NONE)
	var width := tb.show_textbox(0, ScriptContext.OWNER_PARTNER)
	var e: TextBoxes.Entry = tb.entries[0]
	var row := func(r: int, n: int) -> Array: return Array(tb.lines.slice(r * tb.line_size, r * tb.line_size + n))
	# Back page = page 1: rows 4-7. The name is full-width (typed names are).
	_eq(row.call(4, 12), [1, 10, 0x82, 0x60, 0x82, 0x87, 0x82, 0x95, 1, 1, 0x0D, 0], "speaker line: colour 10, the partner's name")
	_eq(row.call(5, 6), [0x82, 0x60, 0x82, 0x61, 0x0D, 0], "first line")
	_eq(row.call(6, 3), [0x82, 0x62, 0], "last line: its 0D became the terminator")
	_eq([width, e.page_ready, e.write_count, ctx.pointer, ctx.active_instruction], [2, 1, 1, 12, ScriptContext.OP_SHOW_TEXTBOX],
			"widest line 2, last page (next op isn't SHOW_TEXTBOX), pointer after the text")
	# Values: 04 p (script value, 3 digits), 05 the tamer's name.
	gs.set_script_value(3, 42)
	gs.state["tamer"]["name"] = "Ry"
	ctx.code = PackedByteArray([0x04, 3, 0x05, 0, 0x0D, 0, 0, 0, 0])
	ctx.pointer = 0
	tb.show_textbox(0, ScriptContext.OWNER_NONE)
	# The back page is still page 1 (no flip yet): row 4.
	_eq(row.call(4, 9), [0x82, 0x53, 0x82, 0x51, 0x82, 0x71, 0x82, 0x99, 0], "04: ４２; 05: the tamer's name")
	_free(parts)


## One frame as the game runs it: the pad, tickScript's tickTextboxHandling, the UI boxes.
func _frame(parts: Array, buttons := 0) -> void:
	parts[4].poll(buttons)
	parts[4].process()
	parts[0].tick_textbox_handling()
	parts[1].step()


func _dialogue_pages() -> void:
	var parts := _text_boxes()
	var tb: TextBoxes = parts[0]
	var b: UIBoxes = parts[1]
	var ctx: ScriptContext = parts[3]
	var sounds := []
	tb.sound.connect(func(id): sounds.append(id))
	# Page 1, SHOW_TEXTBOX, page 2, then another instruction (0x2A).
	ctx.code = PackedByteArray([0x82, 0x60, 0x0D, 0, 0, 0, ScriptContext.OP_SHOW_TEXTBOX, 0, 0x82, 0x61, 0x0D, 0, 0, 0, 0x2A, 0])
	tb.setup_dialogue_box(ScriptContext.OWNER_NONE)
	tb.show_textbox(0, ScriptContext.OWNER_NONE)
	var e: TextBoxes.Entry = tb.entries[0]
	_eq(e.page_ready, 0, "page 1 is not the last (SHOW_TEXTBOX follows)")
	_frame(parts)
	_eq([e.registered, b.boxes[0].state], [1, UIBoxes.STATE_OPEN], "one line drawn: the page is complete and the box opens (static)")
	_frame(parts)
	_eq([e.back_page, e.flip_count, ctx.active_instruction], [1, 1, 0], "the box shows page 1; not the last page: the script goes on")
	# The interpreter: SHOW_TEXTBOX writes page 2 into the back page while page 1 is shown.
	ctx.pointer += 2
	tb.show_textbox(0, ScriptContext.OWNER_NONE)
	_eq([e.page_ready, e.write_count], [1, 2], "page 2 is the last")
	_frame(parts)
	_frame(parts)
	_eq([tb.arrow_flag, b.boxes[0].arrow >= 0], [1, true], "waiting: tickConfirmDialogue sets the arrow flag each frame, the arrow shows")
	_frame(parts, Pad.CONFIRM)
	_eq([e.back_page, sounds, ctx.active_instruction], [0, [3], ScriptContext.OP_SHOW_TEXTBOX], "confirm: page 2 is shown")
	_frame(parts, Pad.CONFIRM)
	_eq(ctx.active_instruction, ScriptContext.OP_SHOW_TEXTBOX, "held confirm: not again")
	_frame(parts)
	_frame(parts, Pad.CONFIRM)
	_eq([ctx.active_instruction, e.idle, sounds], [0, 1, [3, 3]], "confirm on the last page: the text is done")
	tb.close_all_textboxes()
	_eq([b.boxes[0].state, e.vram_rows], [UIBoxes.STATE_CLOSED, 0], "closeAllTextboxes: closed at once, rows freed")
	_free(parts)


func _dialogue_choice() -> void:
	var parts := _text_boxes()
	var tb: TextBoxes = parts[0]
	var ctx: ScriptContext = parts[3]
	var sounds := []
	tb.sound.connect(func(id): sounds.append(id))
	# SET_SELECTION's bytes after the opcode: count 2, targets 0x1234 and 0x0042, a third short,
	# the text (two lines), 2 more bytes.
	var bytes := [2, 0x34, 0x12, 0x42, 0x00, 0, 0, 0x82, 0x60, 0x0D, 0, 0x82, 0x61, 0x82, 0x62, 0x0D, 0, 0, 0, 0x2A, 0]
	ctx.code = PackedByteArray(bytes)
	ctx.dialogue_owner = ScriptContext.OWNER_NONE
	tb.setup_dialogue_box(ScriptContext.OWNER_NONE)
	tb.script_show_selection()
	_eq([tb.selection["count"], tb.selection["pointer"], tb.selection["cursor_width"], tb.selection["cursor_offset_y"],
			ctx.active_instruction], [2, 1, 2 * 12 + 2, 0, ScriptContext.OP_SET_SELECTION],
			"the choice: 2 options, the widest is 2 columns, no speaker line")
	for i in 4:
		_frame(parts)
	for key in [Pad.DOWN, 0, Pad.DOWN, 0, Pad.UP, 0]:
		_frame(parts, key)
	_eq([tb.selection["current"], sounds], [1, [2, 2, 2]], "down, down (wraps), up (wraps)")
	_frame(parts, Pad.CONFIRM)
	_eq([ctx.pointer, sounds.back()], [0x42, 3], "confirm: the script jumps to the option's target")
	# Cancel: continue after the text.
	ctx.pointer = 0
	tb.setup_dialogue_box(0xFE)
	tb.script_show_selection()
	for i in 4:
		_frame(parts)
	_frame(parts, Pad.CANCEL)
	_eq([ctx.pointer, sounds.back()], [tb.selection["end_pointer"], 4], "cancel: after the text (sound 4)")
	_free(parts)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])
