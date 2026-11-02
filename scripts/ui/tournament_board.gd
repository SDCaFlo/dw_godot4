class_name TournamentBoard
extends RefCounted
## Builtin 0x12's three boxes (dget/dget.c; specs/tournament_entry.md §4.4-4.5): box 1 the title
## and the day header (buildScheduleLabels, renderTournamentTextbox), box 2 the 5 x 6 schedule grid
## (buildScheduleEntries, tickTournamentSchedule, renderTournamentSchedule), box 3 a cup's info
## (initTournamentInfo, tickTournamentInfo, renderTournamentInfo). The states around them are
## TournamentRoutines'.

## The MAPHEAD section of the board's lines (dget.c:169, :704).
const SECTION := 0x4D8
const TITLE_BOX := 1
const GRID_BOX := 2
const INFO_BOX := 3
## The text rows: the title (8), the day header (9), the grid (10-15) (dget.c:168, :176, :225).
const TITLE_ROW := 8
const HEADER_ROW := 9
const GRID_ROW := 10
## buildScheduleLabels: TEXTBOX_LINES_PTR[0x210] = 0x0D (US / JP), [0x2AC] (EU) (dget.c:171-175).
const TITLE_CUT := 0x210
const TITLE_CUT_EU := 0x2AC
## renderTournamentTextbox (US): the title drawn over row 8 each frame (dget.c:459).
const TITLE := "Tournament"
## color = 0xe1 (dget.c:156, :213, :298): open animated, features 2; 0xc1 from the board (:301).
const FLAGS := 0xE1
const INFO_FLAGS_BOARD := 0xC1
## setRECT (dget.c:163-165, :221, :314).
const TITLE_RECT := Rect2i(-54, -98, 108, 20)
const TITLE_RECT_EU := Rect2i(-94, -98, 188, 20)
const GRID_RECT := Rect2i(-0x82, -0x3E, 0x104, 0x7C)
const INFO_X := -0x7E
const INFO_SIZE := Vector2i(0xFC, 0x63)
## yOff: -0x4f after a pick, -0x31 from the board (dget.c:298, :311).
const INFO_Y_PICKED := -0x4F
const INFO_Y_BOARD := -0x31
## registerTextbox(3, slot, 7, 0, 0): slot 8 after a pick, 0 from the board (dget.c:299, :312).
const INFO_ROW_PICKED := 8
const INFO_ROWS := 7
## The grid: 5 days x 6 slots, cells 51 px apart, rows 16 (dget.c:308-309, :574-575).
const DAYS := 5
const SLOTS := 6
const COLUMN_STEP := 51
const ROW_STEP := 16
## The cursor and its cell (dget.c:310, :576).
const CELL_SIZE := Vector2i(0x2A, 0xD)
## Grid cell colours (dget.c:239-245): 3 not enterable, 7 over-levelled, 1 enterable.
const COLOUR_CLOSED := 3
const COLOUR_OVERLEVELED := 7
const COLOUR_OPEN := 1
## Sounds, bank 0 (dget.c:480-549, :639): move 2, pick / START 3, △ 4, refused 0xB.
const SOUND_MOVE := 2
const SOUND_PICK := 3
const SOUND_CANCEL := 4
const SOUND_REFUSED := 0xB
## renderVerticalLine / renderHorizontalLine's words (script_common.c:2386, :2942).
const DARK := 0x020202
const LIGHT := 0xA08769

var textboxes: TextBoxes
var ctx: ScriptContext
var game_state: Node
var data: Node
## DGET_BUFFER: 30 bytes, cell = [column * 6 + row] (TournamentCups.fill_board).
var table := PackedByteArray()
## TOURNAMENT_SELECTED_COLUMN / TOURNAMENT_SELECTED_ROW.
var column := 0
var row := 0
## MAIN_D_801353B0: 0 = box 3 opened from the board (its tick closes it).
var info_from_board := 0


func _init(text_boxes: TextBoxes, game_data: Node, state: Node) -> void:
	textboxes = text_boxes
	ctx = textboxes.ctx
	data = game_data
	game_state = state


func _lang() -> String:
	return textboxes.text_area.font.language


## setupBoxOrigin, with ItemMenu's fallback when the owner isn't on screen.
func _origin(owner: int) -> Rect2i:
	var o = textboxes.setup_box_origin(owner)
	return o if o is Rect2i else Rect2i(-5, -5, 10, 10)


## buildScheduleLabels + buildScheduleEntries (dget.c:147, :201).
func open(board_table: PackedByteArray, owner: int, day: int) -> void:
	table = board_table
	_build_labels(owner, day)
	_build_entries(owner)


## The selected cell's byte.
func selected() -> int:
	return table[column * SLOTS + row]


# --- box 1: the title and the day header ---------------------------------------------------------

## buildScheduleLabels (dget.c:147).
func _build_labels(owner: int, day: int) -> void:
	var lang := _lang()
	textboxes.create_textbox(TITLE_BOX, FLAGS, TITLE_RECT_EU if lang == "en_eu" else TITLE_RECT, _origin(owner),
			Callable(), render_title)
	textboxes.register_textbox(TITLE_BOX, TITLE_ROW, 2, 0, 0)
	textboxes.show_maphead_textbox(1, ScriptContext.OWNER_NONE, TITLE_BOX, SECTION)
	textboxes.lines[TITLE_CUT_EU if lang == "en_eu" else TITLE_CUT] = 0xD
	var at := HEADER_ROW * textboxes.line_size
	at = _put(at, [1, 1])
	for i in DAYS:
		var day_of_month := (day + i) % 30 + 1
		at = _put(at, TextBoxes.int_to_string_sjis(day_of_month, 2, 0))
		if lang == "en_us":
			# A full-width space after a one-digit first day (dget.c:189-194).
			if i == 0 and day_of_month < 10:
				at = _put(at, [0x81, 0x40])
		elif lang == "ja":
			at = _put(at, [0x93, 0xFA])
	_terminate(at, true)


# --- box 2: the grid ----------------------------------------------------------------------------

## buildScheduleEntries (dget.c:201): the cursor at (0, 0), the rows written and shown at once
## (pageReady, writeCount).
func _build_entries(owner: int) -> void:
	column = 0
	row = 0
	textboxes.create_textbox(GRID_BOX, FLAGS, GRID_RECT, _origin(owner), tick_grid, render_grid)
	textboxes.register_textbox(GRID_BOX, GRID_ROW, SLOTS, 0, 1)
	var lang := _lang()
	for i in SLOTS:
		var at := (GRID_ROW + i) * textboxes.line_size
		for col in DAYS:
			at = _put(at, [1])
			var entry := table[col * SLOTS + i]
			if entry != TournamentCups.EMPTY:
				if entry & (TournamentCups.ELIGIBLE | TournamentCups.OVERLEVELED) == 0:
					at = _put(at, [COLOUR_CLOSED])
				elif entry & TournamentCups.OVERLEVELED != 0:
					at = _put(at, [COLOUR_OVERLEVELED])
				else:
					at = _put(at, [COLOUR_OPEN])
				var grade := _grade_bytes(entry & TournamentCups.ID_MASK)
				if grade.size() == 2:
					if lang != "en_eu":
						at = _put(at, [0xF, 0])
					at = _put(at, grade)
					at = _put(at, [0xF, 0])
				else:
					at = _put(at, grade)
			else:
				at = _put(at, [1, 0x81, 0x40])
				if lang != "en_us":
					at = _put(at, [0x81, 0x40])
		_terminate(at, i == SLOTS - 1)
	var e: TextBoxes.Entry = textboxes.entries[GRID_BOX]
	e.page_ready = 1
	e.write_count += 1


## TOURNAMENT_GRADES[id] as the text's bytes.
func _grade_bytes(id: int) -> PackedByteArray:
	return textboxes.text_area.font.to_bytes(data.localize(data.tournament(id).get("grade")))


## tickTournamentSchedule (dget.c:468): box 2's tick, one key a frame.
func tick_grid(_id: int) -> void:
	var boxes := textboxes.boxes.boxes
	if boxes[INFO_BOX].state != UIBoxes.STATE_CLOSED or boxes[GRID_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	var pad := textboxes.pad
	if pad.is_key_down(Pad.CANCEL):
		ctx.state_2 = 3
		_sound(SOUND_CANCEL)
	elif pad.is_key_down(Pad.CONFIRM):
		var entry := selected()
		if entry != TournamentCups.EMPTY and entry & (TournamentCups.ELIGIBLE | TournamentCups.OVERLEVELED) != 0:
			game_state.set_script_value(TournamentRoutines.SCRIPT_VALUE_CUP, entry & TournamentCups.ID_MASK)
			ctx.state_2 = 3
			_sound(SOUND_PICK)
		else:
			_sound(SOUND_REFUSED)
	elif pad.is_key_down(Pad.LEFT):
		column = DAYS - 1 if column == 0 else column - 1
		_sound(SOUND_MOVE)
	elif pad.is_key_down(Pad.RIGHT):
		column = 0 if column == DAYS - 1 else column + 1
		_sound(SOUND_MOVE)
	elif pad.is_key_down(Pad.UP):
		row = SLOTS - 1 if row == 0 else row - 1
		_sound(SOUND_MOVE)
	elif pad.is_key_down(Pad.DOWN):
		row = 0 if row == SLOTS - 1 else row + 1
		_sound(SOUND_MOVE)
	elif pad.is_key_down(Pad.START):
		if selected() != TournamentCups.EMPTY:
			open_info(0)
			_sound(SOUND_PICK)
		else:
			_sound(SOUND_REFUSED)


## renderTournamentSchedule (dget.c:555). The C adds everything at depth 4 (the lines at
## 6 - box 2); the ordering table draws the last added first, so the port draws in reverse:
## the rows, the header, the cursor, then the lines.
func render_grid(canvas: CanvasItem, _id: int) -> void:
	var b: Vector2i = textboxes.boxes.boxes[GRID_BOX].final.position
	var x := b.x + 4
	var y := b.y + 3
	var area := textboxes.text_area
	var lang := _lang()
	var header_v := HEADER_ROW * TextBoxes.ROW_HEIGHT
	var row_v := header_v + TextBoxes.ROW_HEIGHT
	var sy := y + (0x18 if lang == "en_us" else 0x16)
	for r in SLOTS:
		for i in DAYS:
			match lang:
				"en_us":
					area.render_string(canvas, 0, x + 0x14 + COLUMN_STEP * i, sy, 0xC, 0xC, 0xC * i, row_v, true)
				"en_eu":
					area.render_string(canvas, 0, x + 0x10 + COLUMN_STEP * i, sy, 0x10, 0xC, 0x10 * i, row_v, true)
				_:
					area.render_string(canvas, 0, x + 0xC + COLUMN_STEP * i, sy, 0x18, 0xC, 0x18 * i, row_v, true)
		sy += ROW_STEP
		row_v += TextBoxes.ROW_HEIGHT
	for i in DAYS:
		match lang:
			"en_us":
				area.render_string(canvas, 0, x + 0xC + COLUMN_STEP * i, y + 2, 0x10, 0xC, 0x10 * i, header_v, true)
			"en_eu":
				area.render_string(canvas, 0, x + 0x10 + COLUMN_STEP * i, y + 2, 0x10, 0xC, 0x10 * i, header_v, true)
			_:
				area.render_string(canvas, 0, x + 6 + COLUMN_STEP * i, y + 2, 0x24, 0xC, 0x24 * i, header_v, true)
	PsxDraw.selection_cursor(canvas, x + column * COLUMN_STEP + 3, y + row * ROW_STEP + 0x16, CELL_SIZE.x, CELL_SIZE.y)
	_horizontal_line(canvas, b, 3, 0x14, 0xFE)
	var lx := 0x34
	for i in DAYS:
		_vertical_line(canvas, b, lx, 2, 0x13)
		_vertical_line(canvas, b, lx, 0x16, 0x64)
		lx += 0x33


## renderTournamentTextbox (dget.c:448): US draws "Tournament" over row 8 each frame.
func render_title(canvas: CanvasItem, _id: int) -> void:
	var b: Vector2i = textboxes.boxes.boxes[TITLE_BOX].final.position
	var v: int = textboxes.entries[TITLE_BOX].vram_row * TextBoxes.ROW_HEIGHT
	match _lang():
		"en_us":
			textboxes.text_area.draw_string(TITLE, 0, v)
			textboxes.text_area.render_string(canvas, 0, b.x + 6, b.y + 3, 0x54, 0xC, 0, v, true)
		"en_eu":
			textboxes.text_area.render_string(canvas, 0, b.x + 6, b.y + 3, 0xB0, 0xC, 0, v, true)
		_:
			textboxes.text_area.render_string(canvas, 0, b.x + 6, b.y + 3, 0x60, 0xC, 0, v, true)


# --- box 3: a cup's info ------------------------------------------------------------------------

## initTournamentInfo (dget.c:285): from the board (0) the box grows from the cursor's cell and its
## tick closes it; after a pick (1) it grows from the owner and stays. The text is the selected
## cup's info, read like a script text (SCRIPT_POINTER on entry 0 + 2).
func open_info(arg: int) -> void:
	info_from_board = arg
	var origin: Rect2i
	var y_off := INFO_Y_BOARD
	var slot := 0
	var flags := INFO_FLAGS_BOARD
	if arg != 0:
		flags = FLAGS
		origin = _origin(ctx.read_pstat(0xFE))
		y_off = INFO_Y_PICKED
		slot = INFO_ROW_PICKED
	else:
		var b: Vector2i = textboxes.boxes.boxes[GRID_BOX].final.position
		origin = Rect2i(b.x + 4 + column * COLUMN_STEP + 3, b.y + 3 + row * ROW_STEP + 0x16, CELL_SIZE.x, CELL_SIZE.y)
	textboxes.create_textbox(INFO_BOX, flags, Rect2i(Vector2i(INFO_X, y_off), INFO_SIZE), origin, tick_info, render_info)
	textboxes.register_textbox(INFO_BOX, slot, INFO_ROWS, 0, 0)
	var cup: Dictionary = data.tournament_cup(selected() & TournamentCups.ID_MASK)
	var saved_code := ctx.code
	var saved_pointer := ctx.pointer
	ctx.code = str(cup.get("info", {}).get("raw", "")).hex_decode()
	ctx.pointer = 2
	if ctx.code.size() > 2:
		textboxes.show_textbox_ready(INFO_BOX, ScriptContext.OWNER_NONE)
	ctx.code = saved_code
	ctx.pointer = saved_pointer
	ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE


## tickTournamentInfo (dget.c:631): START, ✕ or △ closes the board's info box.
func tick_info(_id: int) -> void:
	if info_from_board != 0 or textboxes.boxes.boxes[INFO_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	if textboxes.pad.is_key_down(Pad.START | Pad.CONFIRM | Pad.CANCEL):
		textboxes.trigger_box_close_flag(INFO_BOX)
		_sound(SOUND_PICK)


## renderTournamentInfo (dget.c:644): the 7 rows, 13 px apart.
func render_info(canvas: CanvasItem, _id: int) -> void:
	var b: Vector2i = textboxes.boxes.boxes[INFO_BOX].final.position
	var v: int = textboxes.entries[INFO_BOX].vram_row * TextBoxes.ROW_HEIGHT
	for i in INFO_ROWS:
		textboxes.text_area.render_string(canvas, 0, b.x + 6, b.y + 3 + 13 * i, 0xF0, 0xC, 0, v + TextBoxes.ROW_HEIGHT * i, true)


# --- helpers ------------------------------------------------------------------------------------

func _put(at: int, bytes) -> int:
	for v in bytes:
		if at < textboxes.lines.size():
			textboxes.lines[at] = int(v)
		at += 1
	return at


## terminateString (script_common.c:2905): 01 01, then 00 00 for the last line, else 0D 00.
func _terminate(at: int, last: bool) -> int:
	at = _put(at, [1, 1])
	return _put(at, [0, 0] if last else [0xD, 0])


## renderHorizontalLine (script_common.c:2386): dark, light, dark rows, relative to the box.
func _horizontal_line(canvas: CanvasItem, b: Vector2i, x: int, y: int, w: int) -> void:
	x += b.x
	y += b.y
	PsxDraw.line2(canvas, DARK, x, y + 2, x + w - 1, y + 2)
	PsxDraw.line2(canvas, LIGHT, x, y + 1, x + w - 1, y + 1)
	PsxDraw.line2(canvas, DARK, x, y, x + w - 1, y)


## renderVerticalLine (script_common.c:2942): dark, light, dark columns, relative to the box.
func _vertical_line(canvas: CanvasItem, b: Vector2i, x: int, y: int, h: int) -> void:
	x += b.x
	y += b.y
	PsxDraw.line2(canvas, DARK, x + 2, y, x + 2, y + h - 1)
	PsxDraw.line2(canvas, LIGHT, x + 1, y, x + 1, y + h - 1)
	PsxDraw.line2(canvas, DARK, x, y, x, y + h - 1)


func _sound(id: int) -> void:
	textboxes.sound.emit(id)
