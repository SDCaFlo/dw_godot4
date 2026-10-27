class_name NamingBox
extends RefCounted
## The naming screen (shop/script_menu.c:2702-3311; specs/new_game.md §2.4): UI box 1, the
## character grid with its "Name" / Back / OK labels and the frame cursor, and UI box 2, the name
## with its letter underscore. NamingRoutines owns one and opens it at step 0x14; ✕ on OK moves the
## routine to step 0x15. The characters come from the data (systems/naming); the layout is the US
## tables (NAMING_CTRL_BOXES, the NAMING_* cursor tables).
##
## The name is held as text of full-width characters (the C's 2-byte Shift-JIS codes): up to 6.

const SELECTOR_BOX := 1
const NAME_BOX := 2
## setupNameSelectorBox / setupNameDisplayBox: the rects, the flags (0xE1 when renaming).
const SELECTOR_RECT := Rect2i(-145, -91, 290, 138)
const NAME_RECT := Rect2i(-145, 60, 149, 42)
const FLAGS := 0xC1
const RENAME_FLAGS := 0xE1
## NAMING_SELECTOR: a cell (row * 5 + column; rows 9-17 are the right half) or BUTTON | the button.
const BUTTON := 0x8000
## US buttons (NAMING_DELETE 0, NAMING_OK 1; NAMING_FIRST_BUTTON 0).
const BACK := 0
const OK := 1
const LETTERS := 6
const ROWS := 9
const COLUMNS := 5
## NAMING_ROLLOVER_CHARS (US: every row's edge goes to Back), NAMING_ROLLOVER_CTRL (US: both 0x19).
const ROLLOVER_CHARS := BUTTON | BACK
const ROLLOVER_CTRL := 0x19
const ROLLOVER_LEFT := 0x31
## The full-width space (0x8140): it can't start a name, and terminateNamingBuffer cuts it at the end.
const SPACE := "　"
## renderNamingBox (US): the labels of text row 1 (x, y, width): "Name", "Back", "OK".
const LABELS := [[0x0E, 6, 0x30], [0x0E, 0x5A, 0x30], [0x0E, 0x76, 0x18]]
const GRID_X := 0x4E
const HALF_X := 0x70
const CELL_X := 18
const CELL_Y := 14
const GLYPH := 12
## renderSelectionBox: the cursor's 8 pieces (corners and edges of the UI page at (896, 448), CLUT
## (256, 508): etctim/04_fi_info palette 12, v from 192) and their places on a cell and a button.
const CURSOR_PAGE := "etctim/04_fi_info"
const CURSOR_PALETTE := 12
const CURSOR_V := 192
const U0 := [0x00, 0x04, 0x00, 0x04, 0x04, 0x04, 0x08, 0x08]
const U1 := [0x04, 0x00, 0x04, 0x00, 0x08, 0x08, 0x0C, 0x0C]
const V0 := [0xFB, 0xFB, 0xFF, 0xFF, 0xFB, 0xFB, 0xFB, 0xFB]
const V1 := [0xFF, 0xFF, 0xFB, 0xFB, 0xFF, 0xFF, 0xFF, 0xFF]
const PIECE_Y := [0x00, 0x00, 0x0E, 0x0E, 0x00, 0x0E, 0x00, 0x00]
const PIECE_H := [0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E, 0x0E]
const CELL_PIECE_X := [0x00, 0x10, 0x00, 0x10, 0x04, 0x04, 0x00, 0x11]
const CELL_PIECE_W := [0x04, 0x04, 0x04, 0x04, 0x10, 0x10, 0x04, 0x04]
const BUTTON_PIECE_X := [0x00, 0x2D, 0x00, 0x2D, 0x04, 0x04, 0x00, 0x2E]
const BUTTON_PIECE_W := [0x04, 0x04, 0x04, 0x04, 0x2E, 0x2E, 0x04, 0x04]
## renderNameDisplayBox: the name's width in text row 0 (tamer, partner), the underscore's colours.
const NAME_WIDTH := [0x48, 0x54]
const UNDERSCORE := [0x020202, 0x10C0C0, 0x020202]
## The US labels and the prompts (MAIN_D_801345F4: empty in US).
const TITLE_TEXT := "MAIN_D_801345F8"
const BUTTONS_TEXT := "MAIN_D_80134600"

var textboxes: TextBoxes
var ctx: ScriptContext
var data: Node

## NAMING_BUFFER (full-width text), NAMING_CURRENT_LETTER, NAMING_SELECTOR, SHOP_AMOUNT (the page).
var buffer := ""
var letter := 0
var selector := 0
var page := 0
## NAMING_BOX_FLAG bit 0 (the partner's name) and bit 1 (renaming).
var partner := false
var renaming := false

var _pages: Array = []
var _cursor: PsxTexture


func _init(text_boxes: TextBoxes, script_ctx: ScriptContext, game_data: Node) -> void:
	textboxes = text_boxes
	ctx = script_ctx
	data = game_data


## The language's pages (systems/naming) and the page the screen opens on.
func _load_pages() -> void:
	_pages = []
	page = 0
	var lang: String = data.language if data != null else "en_us"
	if data == null:
		return
	for entry in data.system("naming"):
		if entry.get("language") == lang or (_pages.is_empty() and entry.get("language") == "en_us"):
			_pages = entry.get("pages", [])
			page = int(entry.get("start_page", 0))


## setupNameSelectorBox and setupNameDisplayBox, growing from `origin`.
func open(origin: Rect2i) -> void:
	_load_pages()
	textboxes.fixed_width = true
	var flags := RENAME_FLAGS if renaming else FLAGS
	textboxes.create_textbox(SELECTOR_BOX, flags, SELECTOR_RECT, origin, tick, render_selector)
	textboxes.register_textbox(SELECTOR_BOX, 1, 7, 1, 0)
	selector = 0
	fill_menu_strings()
	textboxes.create_textbox(NAME_BOX, flags, NAME_RECT, origin, Callable(), render_name)
	textboxes.register_textbox(NAME_BOX, 0, 1, 0, 0)
	letter = mini(buffer.length(), LETTERS - 1)
	update_preview()


## triggerBoxCloseFlag on both boxes.
func close() -> void:
	textboxes.trigger_box_close_flag(SELECTOR_BOX)
	textboxes.trigger_box_close_flag(NAME_BOX)


## The character at a cell of the current page ("" outside it).
func character(cell: int) -> String:
	if page >= _pages.size():
		return ""
	var row := cell / COLUMNS
	var half: Dictionary = _pages[page]["left" if row < ROWS else "right"]
	var rows: Array = half.get("rows", [])
	row = row % ROWS
	if row >= rows.size():
		return ""
	var text := str(rows[row])
	var column := cell % COLUMNS
	return text[column] if column < text.length() else ""


# --- tickNamingBox --------------------------------------------------------------------------------

func tick(_id := 0) -> void:
	if textboxes.flip_textbox_page(SELECTOR_BOX):
		return
	if textboxes.boxes.boxes[SELECTOR_BOX].state != UIBoxes.STATE_OPEN:
		return
	if textboxes.boxes.boxes[NAME_BOX].state != UIBoxes.STATE_OPEN:
		return
	if not textboxes.is_x_pressed_after_dialogue():
		return
	var pad := textboxes.pad
	var row := selector / COLUMNS
	var column := selector % COLUMNS
	var special := selector & 0x7FFF
	if pad.is_key_down(Pad.SQUARE):
		buffer = ""
		letter = 0
		update_preview()
		_sound(3)
		return
	if pad.is_key_down(Pad.CONFIRM):
		if selector & BUTTON == 0:
			var c := character(selector)
			if c == SPACE and letter == 0:
				_sound(0xB)
				return
			buffer = buffer.substr(0, letter) + c
			if letter != LETTERS - 1:
				letter += 1
			update_preview()
			if buffer.length() == LETTERS and letter == LETTERS - 1:
				selector = BUTTON | OK
			_sound(3)
			return
		match special:
			BACK:
				delete_last()
			OK:
				if buffer.is_empty():
					_sound(0xB)
					return
				terminate()
				_sound(3)
				ctx.state_2 = 0x15
	elif pad.is_key_down(Pad.ALT):
		selector = BUTTON | BACK
		_sound(2)
	elif pad.is_key_down(Pad.CANCEL):
		delete_last()
	elif pad.is_key_down(Pad.START):
		selector = BUTTON | OK
		_sound(2)
	elif pad.is_key_down(Pad.LEFT):
		move_left(column, row, special)
	elif pad.is_key_down(Pad.RIGHT):
		move_right(column, row, special)
	elif pad.is_key_down(Pad.UP):
		move_up(column, row)
	elif pad.is_key_down(Pad.DOWN):
		move_down(column, row)


## namingDeleteLast. Quirk kept (US): the cursor moves back first, then the name ends there, so
## a full name loses its 6th and 5th letters (the cursor stays on the 6th once it is written).
func delete_last() -> void:
	if buffer.is_empty():
		return
	if letter == 0:
		buffer = ""
	else:
		letter -= 1
		buffer = buffer.substr(0, letter)
	update_preview()
	_sound(3)


## terminateNamingBuffer: the trailing full-width spaces are cut (the first letter is kept).
func terminate() -> void:
	while buffer.length() > 1 and buffer.ends_with(SPACE):
		buffer = buffer.substr(0, buffer.length() - 1)


## namingSelectionLeft.
func move_left(column: int, row: int, special: int) -> void:
	if selector & BUTTON == 0:
		if row < ROWS:
			selector = ROLLOVER_CHARS if column == 0 else row * COLUMNS + column - 1
		elif column == 0:
			selector = (row - ROWS) * COLUMNS + COLUMNS - 1
		else:
			selector = row * COLUMNS + column - 1
	else:
		selector = _rollover_ctrl(special) + ROLLOVER_LEFT
	_sound(2)


## namingSelectionRight.
func move_right(column: int, row: int, special: int) -> void:
	if selector & BUTTON == 0:
		if row < ROWS:
			selector = (row + ROWS) * COLUMNS if column == COLUMNS - 1 else row * COLUMNS + column + 1
		elif column == COLUMNS - 1:
			selector = ROLLOVER_CHARS
		else:
			selector = row * COLUMNS + column + 1
	else:
		selector = _rollover_ctrl(special)
	_sound(2)


## namingSelectionUp: the rows wrap within their half; the buttons cycle.
func move_up(column: int, row: int) -> void:
	if selector & BUTTON == 0:
		if row < ROWS:
			row = ROWS - 1 if row == 0 else row - 1
		else:
			row = ROWS * 2 - 1 if row == ROWS else row - 1
		selector = column + row * COLUMNS
	elif selector == BUTTON | BACK:
		selector = BUTTON | OK
	else:
		selector -= 1
	_sound(2)


## namingSelectionDown.
func move_down(column: int, row: int) -> void:
	if selector & BUTTON == 0:
		if row < ROWS:
			row = 0 if row == ROWS - 1 else row + 1
		else:
			row = ROWS if row == ROWS * 2 - 1 else row + 1
		selector = column + row * COLUMNS
	elif selector == BUTTON | OK:
		selector = BUTTON | BACK
	else:
		selector += 1
	_sound(2)


## NAMING_ROLLOVER_CTRL[special] (US: 2 entries, both 0x19).
func _rollover_ctrl(_special: int) -> int:
	return ROLLOVER_CTRL


func _sound(id: int) -> void:
	textboxes.sound.emit(id)


# --- the text rows ----------------------------------------------------------------------------------

## fillNamingMenuStrings: row 1 the labels, rows 2-4 the left half and 5-7 the right half (3 rows
## of 5 a line), into box 1's back page.
func fill_menu_strings() -> void:
	var e: TextBoxes.Entry = textboxes.entries[SELECTOR_BOX]
	var font := textboxes.text_area.font
	var first := e.vram_row + (e.back_page ^ 1) * e.vram_rows
	var line := PackedByteArray([1, 7])
	line.append_array(font.to_bytes(_text(TITLE_TEXT)))
	line.append_array([1, 1])
	line.append_array(font.to_bytes(_text(BUTTONS_TEXT)))
	line.append_array([0xD, 0])
	_write_line(first, line)
	for half in 2:
		var rows: Array = []
		if page < _pages.size():
			rows = _pages[page]["left" if half == 0 else "right"].get("rows", [])
		for j in range(0, ROWS, 3):
			var text := ""
			for k in 3:
				text += str(rows[j + k]) if j + k < rows.size() else ""
			line = font.to_bytes(text, true)
			# The last line ends the text (the C steps back over its 0x0D, 0).
			if half == 1 and j == ROWS - 3:
				line.append(0)
			else:
				line.append_array([0xD, 0])
			_write_line(first + 1 + half * 3 + j / 3, line)
	e.page_ready = 1
	e.write_count += 1


## updateNamingPreview: the prompt (empty in US), the name and full-width spaces up to 6 letters
## into text row 0, drawn there at once (drawString2, fixed width).
func update_preview() -> void:
	var font := textboxes.text_area.font
	var line := PackedByteArray([1, 1])
	line.append_array(font.to_bytes(buffer, true))
	for i in maxi(LETTERS - buffer.length(), 0):
		line.append_array([0x81, 0x40])
	line.append_array([1, 1, 0, 0])
	_write_line(0, line)
	textboxes.draw_string2(0, 0, 0)


func _write_line(row: int, bytes: PackedByteArray) -> void:
	var at := row * textboxes.line_size
	for i in mini(bytes.size(), textboxes.line_size):
		textboxes.lines[at + i] = bytes[i]


func _text(id: String) -> String:
	return str(data.text(id)) if data != null else ""


# --- render -----------------------------------------------------------------------------------------

## renderNamingBox: the cursor, the labels (quirk kept, US: the 4th label call reads past the
## 3-entry table and draws nothing), the two halves.
func render_selector(canvas: CanvasItem, _id := 0) -> void:
	var area := textboxes.text_area
	var e: TextBoxes.Entry = textboxes.entries[SELECTOR_BOX]
	var r := textboxes.boxes.boxes[SELECTOR_BOX].final
	var bx := r.position.x
	var by := r.position.y
	_render_cursor(canvas, bx, by)
	var tex_y := e.back_page * e.vram_rows * TextBoxes.ROW_HEIGHT + e.vram_row * TextBoxes.ROW_HEIGHT
	var tex_x := 0
	for label in LABELS:
		area.render_string(canvas, 0, bx + label[0], by + label[1], label[2], 12, tex_x, tex_y, true)
		tex_x += label[2]
	var ty := tex_y + TextBoxes.ROW_HEIGHT
	for half in 2:
		var y := by + 6
		for i in 3:
			tex_x = 0
			for j in 3:
				var x := bx + GRID_X + half * HALF_X
				for k in COLUMNS:
					area.render_string(canvas, 0, x, y, GLYPH, 12, tex_x, ty, true)
					x += CELL_X
					tex_x += GLYPH
				y += CELL_Y
			ty += TextBoxes.ROW_HEIGHT


## renderSelectionBox: the frame around the cell or the button.
func _render_cursor(canvas: CanvasItem, bx: int, by: int) -> void:
	if _cursor == null:
		_cursor = PsxTexture.load_palette(CURSOR_PAGE, CURSOR_PALETTE)
	if _cursor == null:
		return
	var x := 0
	var y := 0
	var piece_x: Array = CELL_PIECE_X
	var piece_w: Array = CELL_PIECE_W
	if selector & BUTTON == 0:
		var row := selector / COLUMNS
		var column := selector % COLUMNS
		if row < ROWS:
			x = bx + column * CELL_X + 0x4A
			y = by + row * CELL_Y + 2
		else:
			x = bx + column * CELL_X + 0xBA
			y = by + (row - ROWS) * CELL_Y + 2
	else:
		var label: Array = LABELS[(selector & 0x7FFF) + 1]
		x = bx + label[0] - 4
		y = by + label[1] - 4
		piece_x = BUTTON_PIECE_X
		piece_w = BUTTON_PIECE_W
	for i in 8:
		var src := Rect2(mini(U0[i], U1[i]), mini(V0[i], V1[i]) - CURSOR_V, absi(U1[i] - U0[i]),
				absi(V1[i] - V0[i]))
		var dst := Rect2(PsxDraw.CENTRE + Vector2(x + piece_x[i], y + PIECE_Y[i]), Vector2(piece_w[i], PIECE_H[i]))
		# A reversed u / v pair mirrors the piece.
		if U0[i] > U1[i]:
			dst.position.x += dst.size.x
			dst.size.x = -dst.size.x
		if V0[i] > V1[i]:
			dst.position.y += dst.size.y
			dst.size.y = -dst.size.y
		canvas.draw_texture_rect_region(_cursor.base, dst, src)


## renderNameDisplayBox: the name (row 0), six cells after it (US: the row's empty end; quirk
## kept), the underscore under the letter cursor.
func render_name(canvas: CanvasItem, _id := 0) -> void:
	var area := textboxes.text_area
	var r := textboxes.boxes.boxes[NAME_BOX].final
	var x := r.position.x
	var y := r.position.y
	var v: int = NAME_WIDTH[1 if partner else 0]
	area.render_string(canvas, 0, x + 7, y + 6, v, 12, 0, 0, true)
	var sx := x + 0x3A
	for i in LETTERS:
		area.render_string(canvas, 0, sx, y + 0x14, GLYPH, 12, v, 0, true)
		sx += 0xE
		v += GLYPH
	# renderNamingUnderscore(2, letter * 12 + 4, 0x10, 12): three lines.
	var ux := x + letter * GLYPH + 4
	var uy := y + 0x10
	for i in 3:
		PsxDraw.line2(canvas, UNDERSCORE[i], ux, uy + i, ux + GLYPH - 1, uy + i)
