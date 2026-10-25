class_name PlayerChartTab
extends Node
## The Player screen's evolution chart (renderEvoChartView / renderEvoChartDetail, game_menu.c:3365,
## :3450, the cursor in tickPlayerMenu :1912; specs/status_screens.md §4.2): the icons of the
## Digimon raised in five level columns; ✕ moves a cursor over them, ✕ on a raised one opens box 2
## with what it comes from and evolves into.

## EVO_CHART_TEXT_AREA, EVO_CHART_NAME_AREA (the detail's name, row 0x30).
const TEXT_AREA := Rect2i(0, 12, 256, 200)
const NAME_AREA := Rect2i(0, 48, 120, 12)
## EVO_CHART_BOXES (game_menu.c:853), Digimon id - 1: absolute x, y, u, v (SBOY) and palette index.
## Quirk: the C's loops run over 0x3E entries; the 62nd reads past the table (an offscreen frame).
const BOXES := [
		[30, 43, 0x40, 0x90, 0], [67, 43, 0x60, 0x90, 0], [104, 43, 0x40, 0x80, 0], [104, 176, 0x60, 0x80, 1],
		[141, 43, 0x40, 0x30, 1], [213, 62, 0x60, 0x30, 3], [141, 100, 0x80, 0x30, 1], [189, 62, 0xA0, 0x30, 0],
		[165, 43, 0xC0, 0x30, 0], [213, 119, 0xE0, 0x30, 1], [189, 157, 0xA0, 0x70, 1], [250, 43, 0xC0, 0x00, 0],
		[274, 119, 0xE0, 0x00, 0], [274, 138, 0x00, 0x10, 0], [30, 119, 0x80, 0x90, 0], [67, 119, 0xA0, 0x90, 0],
		[104, 62, 0x80, 0x80, 2], [104, 100, 0xA0, 0x80, 0], [213, 100, 0x00, 0x40, 0], [189, 81, 0x20, 0x40, 0],
		[189, 43, 0x40, 0x40, 0], [213, 138, 0x60, 0x40, 2], [141, 157, 0x80, 0x40, 0], [141, 138, 0xA0, 0x40, 0],
		[165, 119, 0xC0, 0x70, 1], [250, 62, 0x20, 0x10, 0], [250, 119, 0x40, 0x10, 0], [250, 157, 0x60, 0x10, 0],
		[30, 81, 0xC0, 0x90, 2], [67, 81, 0xE0, 0x90, 0], [104, 81, 0xC0, 0x80, 0], [104, 138, 0xE0, 0x80, 0],
		[189, 100, 0xC0, 0x40, 0], [141, 81, 0xE0, 0x40, 1], [165, 138, 0x00, 0x50, 2], [213, 43, 0x20, 0x50, 0],
		[213, 81, 0x40, 0x50, 0], [165, 62, 0x60, 0x50, 0], [213, 157, 0xE0, 0x70, 0], [274, 43, 0x80, 0x10, 3],
		[250, 81, 0xA0, 0x10, 0], [250, 176, 0xC0, 0x10, 0], [30, 157, 0x00, 0xA0, 0], [67, 157, 0x20, 0xA0, 1],
		[104, 119, 0x00, 0x90, 2], [104, 157, 0x20, 0x90, 2], [141, 62, 0x80, 0x50, 3], [165, 81, 0xA0, 0x50, 3],
		[189, 138, 0xC0, 0x50, 3], [165, 100, 0xE0, 0x50, 0], [141, 119, 0x00, 0x60, 0], [165, 157, 0x20, 0x60, 0],
		[141, 176, 0x00, 0x80, 0], [274, 62, 0xE0, 0x10, 0], [274, 100, 0x00, 0x20, 0], [274, 157, 0x20, 0x20, 1],
		[104, 195, 0x60, 0x60, 0], [189, 119, 0x40, 0x60, 0], [274, 81, 0x20, 0x00, 0], [250, 100, 0x40, 0x00, 4],
		[250, 138, 0x60, 0x00, 3]]
## EVO_CHART_VIEW_COLORS / EVO_CHART_DETAIL_COLORS: palette rows (GetClut(0x70, 488 + n)).
const PALETTE_ROWS := [488, 489, 490, 491, 492]
## The cursor (SBOY u 0, v 0xE8, GetClut(0x70, 503)).
const CURSOR_ROW := 503
## The level columns' frames (renderEvoChartView): absolute x, y, w, h, c1, c2, r, g, b.
const COLUMNS := [[0x15, 0x27, 0x22, 0x9F, 0xAAA0C8, 0x5A3C8C, 0xA5, 0x5A, 0x73],
		[0x3A, 0x27, 0x22, 0x9F, 0xA078A5, 0x46144B, 0x6E, 0x2D, 0x5A],
		[0x5F, 0x27, 0x22, 0xB0, 0xC88250, 0x5F370A, 0x0F, 0x50, 0x82],
		[0x84, 0x27, 0x6A, 0x9F, 0x6EAF5A, 0x285A00, 0x00, 0x87, 0x41],
		[0xF1, 0x27, 0x38, 0x9F, 0x6996D2, 0x1E4178, 0xAF, 0x64, 0x2D]]
## The footer (US): colour, x, width, u (row 0x0C, y 0x54).
const FOOTER := [[PlayerScreen.FOOTER_GLYPH1, -0x1A, 0x0C, 0x00], [0, -0x0E, 0x3C, 0x0C],
		[PlayerScreen.FOOTER_GLYPH2, 0x3A, 0x0C, 0x48], [0, 0x46, 0x3C, 0x54]]
## The detail (box 2): CHART_FROM_LINES_* / CHART_TO_LINES_* (Line4Points: x1-x4, y1-y4) and the
## icons' places CHART_*_SPRITES_* (x, y), the even layout when the count of slots used is even.
const FROM_LINES_EVEN := [[-84, -68, -37, -10, -48, -48, -17, -17], [-102, -74, -64, -10, -24, -24, -14, -14],
		[-102, -74, -64, -10, -1, -1, -11, -11], [-84, -68, -37, -10, 23, 23, -8, -8]]
const FROM_LINES_ODD := [[-66, -52, -10, -10, -60, -60, -18, -18], [-84, -58, -37, -10, -36, -36, -15, -15],
		[-102, -10, -10, -10, -12, -12, -12, -12], [-84, -58, -37, -10, 12, 12, -9, -9],
		[-66, -52, -10, -10, 36, 36, -6, -6]]
const TO_LINES_EVEN := [[9, 61, 64, 64, -20, -72, -72, -72], [9, 36, 67, 82, -17, -17, -48, -48],
		[9, 63, 73, 100, -14, -14, -24, -24], [9, 63, 73, 100, -11, -11, -1, -1], [9, 36, 67, 82, -8, -8, 23, 23],
		[9, 61, 64, 64, -5, 47, 47, 47]]
const TO_LINES_ODD := [[9, 51, 64, 64, -18, -60, -60, -60], [9, 36, 57, 82, -15, -15, -36, -36],
		[9, 100, 100, 100, -12, -12, -12, -12], [9, 36, 57, 82, -9, -9, 12, 12], [9, 51, 64, 64, -6, 36, 36, 36]]
const FROM_SPRITES_EVEN := [[-102, -57], [-120, -33], [-120, -9], [-102, 15]]
const FROM_SPRITES_ODD := [[-84, -69], [-102, -45], [-120, -21], [-102, 3], [-84, 27]]
const TO_SPRITES_EVEN := [[66, -81], [84, -57], [102, -33], [102, -9], [84, 16], [66, 39]]
const TO_SPRITES_ODD := [[66, -69], [84, -45], [102, -21], [84, 3], [66, 27]]
## The "from" lines' colours, and the "to" lines' (MAIN_D_80124A84: centre, edge per slot).
const FROM_CENTRE := 0x794E3
const FROM_EDGE := 0x65DB
const TO_COLORS := [[0xFB, 0xE8, 0x02], [0xEC, 0x9A, 0x00], [0x00, 0xB6, 0x00], [0x00, 0x64, 0x00],
		[0x00, 0xAE, 0xB8], [0x00, 0x6F, 0x8E], [0x00, 0x3C, 0xC8], [0x00, 0x1E, 0x8C], [0xBE, 0x00, 0xA0],
		[0x6E, 0x00, 0x6E], [0xBE, 0x00, 0x1E], [0x82, 0x1E, 0x1E]]
## MAIN_D_80124B48 (US): the detail's insets, absolute x, y, w, h.
const DETAIL_INSETS := [[0x1C, 0x2B, 0x4E, 0x82], [0x81, 0x32, 0x3C, 4], [0x88, 0x55, 0x30, 0x2E],
		[0xD6, 0x2A, 0x4E, 0x82], [0x26, 0xBB, 0x6C, 4], [0x1A, 0xCE, 0x84, 4]]
## The detail's level label (US): level -> x, width, u, v.
const LEVEL_LABELS := {1: [-0x5B, 0x2E, 0x24, 0x18], 2: [-0x63, 0x3E, 0x52, 0x18], 3: [-0x5B, 0x2F, 0x00, 0x24],
		4: [-0x64, 0x41, 0x2F, 0x24], 5: [-0x64, 0x41, 0x00, 0x3C]}
const DETAIL_BOX := 2

var screen: PlayerScreen
## CHART_SELECTED_COLUMN / CHART_SELECTED_ROW (the C names them the other way round), and
## CHART_SELECTED_DIGIMON: the Digimon id under the cursor, 0x3F when no icon is there, -1 none.
var column := 0
var row := 0
var selected_digimon := -1
## The Digimon whose name is in NAME_AREA (the detail draws it each frame; drawn once here).
var _named := -1


## MENU_STATE 0: drawEvoChartStrings(0) (game_menu.c:4168). True when done.
func draw_strings() -> bool:
	var area := screen.text_area
	var data := screen.data
	if screen.sub_state == 0:
		area.clear(TEXT_AREA)
		MenuDraw.draw_digits(area)
		area.draw_string(data.text(PlayerScreen.CARD_CHART_LABELS[1]), 0, 0xC)
		column = 0
		row = 0
		_named = -1
		screen.sub_state = 1
	area.draw_string(data.text(PlayerScreen.CARD_CHART_LABELS[2]), 0, 0x18)
	area.draw_string(data.text(PlayerScreen.CARD_CHART_LABELS[3]), 0, 0x24)
	area.draw_string(data.text(PlayerScreen.CARD_CHART_LABELS[4]), 0, 0x3C)
	return true


func update() -> void:
	if screen.menu_state == 0 and draw_strings():
		screen.menu_state = 1


func leave() -> void:
	pass


## The column's x (tickPlayerMenu, renderEvoChartView): three wide columns, then 24 apart.
func column_x() -> int:
	if column < 3:
		return column * 0x25 + 0x1C
	if column < 7:
		return (column - 3) * 0x18 + 0x8B
	return (column - 7) * 0x18 + 0xF8


## tickPlayerMenu, PLAYER_MENU_STATE 1 (MENU_STATE 2 and 3).
func tick() -> void:
	var pad := screen.pad
	if screen.menu_state == 2:
		var previous := [column, row]
		if pad.is_changed(Pad.LEFT):
			column -= 1
		if pad.is_changed(Pad.RIGHT):
			column += 1
		column = clampi(column, 0, 8)
		var max_row := 6
		if column < 2:
			# The first two columns (Fresh, In-Training) hold every other row.
			if pad.is_changed(Pad.UP):
				row -= 2
			if pad.is_changed(Pad.DOWN):
				row += 2
			row = (row / 2) * 2
		else:
			if pad.is_changed(Pad.UP):
				row -= 1
			if pad.is_changed(Pad.DOWN):
				row += 1
			if column == 2:
				max_row = 8
			elif (column >= 4 and column < 7) or column == 8:
				max_row = 6
			else:
				max_row = 7
		row = clampi(row, 0, max_row)
		if previous != [column, row]:
			screen.play_sound(2)
		var i := 0
		while i < 0x3E:
			var b: Array = BOXES[i] if i < BOXES.size() else [-146, -67]
			if column_x() + 2 == b[0] and row * 0x13 + 0x2B == b[1]:
				break
			i += 1
		selected_digimon = i + 1
		if screen.pad.is_key_down(Pad.CONFIRM):
			# An empty cell gives 0x3F (no icon): refused like a Digimon not raised.
			if i < BOXES.size() and screen.has_raised(selected_digimon):
				if screen.boxes.is_available(DETAIL_BOX):
					var start := Rect2i(column_x() - 0x99, row * 0x13 - 0x45, 10, 10)
					screen.boxes.create_animated(DETAIL_BOX, 1, 0, PlayerScreen.RECT, start, Callable(), draw_detail,
							update_detail)
					screen.play_sound(3)
					screen.menu_state = 3
			else:
				screen.play_sound(4)
	elif screen.menu_state == 3 and pad.is_key_down(Pad.CANCEL):
		screen.boxes.remove_animated(DETAIL_BOX, Rect2i(column_x() - 0x99, row * 0x13 - 0x45, 10, 10))
		screen.play_sound(3)
		screen.menu_state = 2


func _icon(canvas: CanvasItem, x: int, y: int, id: int, shift := 0) -> void:
	var b: Array = BOXES[id - 1]
	MenuDraw.sboy_sprite(canvas, x, y, 0x10, 0x10, shift + b[2], b[3], PALETTE_ROWS[b[4]])


func _frame(canvas: CanvasItem, x: int, y: int, fill := 0x87) -> void:
	MenuDraw.border_box(canvas, x, y, 0x12, 0x12, 0xBEBEBE, 0x3C3C3C, fill, fill, fill)


## renderEvoChartView in reverse of its adds: footer, columns, frames, icons, cursor last.
func draw(canvas: CanvasItem) -> void:
	if screen.menu_state == 0:
		return
	var area := screen.text_area
	for k in range(FOOTER.size() - 1, -1, -1):
		var f: Array = FOOTER[k]
		area.render_string(canvas, f[0], f[1], 0x54, f[2], 0xC, f[3], 0xC, true)
	for k in range(COLUMNS.size() - 1, -1, -1):
		var c: Array = COLUMNS[k]
		MenuDraw.border_box(canvas, c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
	for i in range(BOXES.size() - 1, -1, -1):
		_frame(canvas, BOXES[i][0] - 1, BOXES[i][1] - 1)
	var blink := screen.menu_state > 1 and screen.playtime_frames() % 10 < 5
	for i in range(BOXES.size() - 1, -1, -1):
		if screen.has_raised(i + 1):
			var shift := 0x10 if blink and i + 1 == selected_digimon else 0
			_icon(canvas, BOXES[i][0] - 0xA0, BOXES[i][1] - 0x78, i + 1, shift)
	if screen.menu_state >= 2:
		MenuDraw.sboy_sprite(canvas, column_x() - 0xA2, row * 0x13 - 0x4E, 0x18, 0x14, 0, 0xE8, CURSOR_ROW)


# --- the detail (box 2) ------------------------------------------------------------------------

func _paths() -> Dictionary:
	return screen.data.evolution_paths(selected_digimon).get("c", {})


## drawEvoChartStrings(id), sub-state 2: the name, at row 0x30.
func update_detail(_id: int) -> void:
	if _named != selected_digimon:
		screen.text_area.clear(NAME_AREA)
		screen.text_area.draw_string(_raw_name(selected_digimon), 0, 0x30)
		_named = selected_digimon
	screen.sub_state = 2


func _raw_name(id: int) -> String:
	return screen.data.localize(screen.data.digimon(id).get("name"))


## renderEvoChartDetail (game_menu.c:3450) in reverse of its adds.
func draw_detail(canvas: CanvasItem, _id: int) -> void:
	if selected_digimon < 1 or selected_digimon > BOXES.size():
		return
	var area := screen.text_area
	var paths := _paths()
	var from: Array = paths.get("from", [])
	var to: Array = paths.get("to", [])
	var from_count := from.filter(func(v): return int(v) != -1).size()
	var to_count := to.filter(func(v): return int(v) != -1).size()
	var from_lines: Array = FROM_LINES_EVEN if from_count % 2 == 0 else FROM_LINES_ODD
	var from_sprites: Array = FROM_SPRITES_EVEN if from_count % 2 == 0 else FROM_SPRITES_ODD
	var to_lines: Array = TO_LINES_EVEN if to_count % 2 == 0 else TO_LINES_ODD
	var to_sprites: Array = TO_SPRITES_EVEN if to_count % 2 == 0 else TO_SPRITES_ODD
	for i in range(DETAIL_INSETS.size() - 1, -1, -1):
		var r: Array = DETAIL_INSETS[i]
		MenuDraw.inset_box(canvas, r[0], r[1], r[2], r[3])
	var name_len := _raw_name(selected_digimon).length() / 2
	area.render_string(canvas, 0, -0x5C - (name_len - 4) * 6, 0x4D, 0x78, 0xC, 0, 0x30)
	var level := int(screen.data.digimon(selected_digimon).get("level", {}).get("id", 0))
	if LEVEL_LABELS.has(level):
		var l: Array = LEVEL_LABELS[level]
		area.render_string(canvas, 0, l[0], 0x3A, l[1], 0xC, l[2], l[3])
	area.render_string(canvas, 3, -0x14, -0x4F, 0x24, 0xC, 0, 0x18)
	_slots(canvas, to, to_sprites)
	_slots(canvas, from, from_sprites)
	_frame(canvas, 0x97, 99)
	_icon(canvas, -8, -0x14, selected_digimon)
	for j in range(to_sprites.size() - 1, -1, -1):
		if j < to.size() and int(to[j]) > 0:
			var c: Array = TO_COLORS[j * 2]
			var e: Array = TO_COLORS[j * 2 + 1]
			_path_line(canvas, to_lines[j], c[0] | c[1] << 8 | c[2] << 16, e[0] | e[1] << 8 | e[2] << 16)
	for j in range(from_sprites.size() - 1, -1, -1):
		if j < from.size() and int(from[j]) > 0:
			_path_line(canvas, from_lines[j], FROM_CENTRE, FROM_EDGE)


## The from / to icons: a frame each slot used, the icon when that Digimon was raised.
func _slots(canvas: CanvasItem, ids: Array, sprites: Array) -> void:
	for j in range(sprites.size() - 1, -1, -1):
		var id := int(ids[j]) if j < ids.size() else -1
		if id <= 0:
			continue
		var p: Array = sprites[j]
		_frame(canvas, p[0] + 0x9F, p[1] + 0x77)
		if id <= BOXES.size() and screen.has_raised(id):
			_icon(canvas, p[0], p[1], id)


## A path: three lines, the edge colour above and below the centre one (added edge, centre, edge).
func _path_line(canvas: CanvasItem, l: Array, centre: int, edge: int) -> void:
	for d in [1, 0, -1]:
		var word: int = centre if d == 0 else edge
		PsxDraw.line3(canvas, word, l[0], l[4] + d, l[1], l[5] + d, l[2], l[6] + d)
		PsxDraw.line2(canvas, word, l[2], l[6] + d, l[3], l[7] + d)
