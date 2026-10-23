extends SceneTree
## The text renderer (scripts/ui/) against specs/text.md §2, values worked out from the C:
##   godot --headless --path . -s res://tests/test_text.gd
## Exits 1 if a check fails. Needs the data porter output (font group).

var _failed := 0
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
		print("%s: text checks" % ("FAILED %d" % _failed if _failed else "OK"))
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
	var pad: Node = load("res://scripts/core/game_loop.gd").new()
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
	pad._poll()
	tamer.tick()
	_eq(tamer.sub_state, 5, "waits for the confirm button")
	pad.press("ui_accept")
	pad._poll()
	tamer.tick()
	_eq([tamer.state, partner.state, tamer.camera_follow, clock.running, b.boxes[1].state],
			[Tamer.STATE_FREE, Partner.STATE_NORMAL, true, true, UIBoxes.STATE_CLOSING], "confirm: the box closes, all free")
	pad._poll()
	_eq(pad.pad_pressed("ui_accept"), false, "a press is seen by one game frame only")
	tamer.free()
	partner.free()
	pad.free()
	clock.free()
	gs.free()
	b.free()


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])
