class_name DigimonTechniquesTab
extends Node
## The Digimon screen's Techniques tab (renderDigimonMovesView US, game_menu.c:2752;
## specs/status_screens.md §3.3-3.5): the equipped techniques and the finisher; the grid of every
## technique (move_data `menu_cell`) where they are equipped; the help page.

## MOVES_VIEW_TEXT_AREA / MAIN_D_801342F0.
const TEXT_AREA := Rect2i(0, 24, 256, 200)
## The grid cursor's limits and steps (tickDigimonMenu).
const CURSOR_MIN := Vector2i(0x73, 0x6F)
const CURSOR_MAX := Vector2i(0xF1, 0xC9)
const CURSOR_STEP := Vector2i(0x12, 0xF)
## The text-area row the selected technique's name is drawn at (renderDigimonMovesSelected).
const SELECTED_NAME_ROW := 0x84
## MOVES_VIEW_TECHSET_TEXT (US, :614): x, y, w, h, u, texY.
const TECHSET := [[0x16, -0x4C, 0x17, 7, 0x5C, 0x22], [0x62, -0x4C, 0x13, 7, 0x4C, 0x29], [0x7A, -0x4C, 0x10, 7, 0x00, 0x30],
		[0x44, -0x4C, 0x0B, 7, 0x74, 0x22], [0x35, -0x3F, 4, 4, 0x78, 0x0C], [0x35, -0x30, 4, 4, 0x78, 0x0C],
		[0x35, -0x20, 4, 4, 0x78, 0x0C], [0x5E, -0x3F, 4, 4, 0x78, 0x0C], [0x5E, -0x30, 4, 4, 0x78, 0x0C],
		[0x5E, -0x20, 4, 4, 0x78, 0x0C], [0x75, -0x3F, 4, 4, 0x78, 0x0C], [0x75, -0x30, 4, 4, 0x78, 0x0C],
		[0x75, -0x20, 4, 4, 0x78, 0x0C]]
## MOVES_TECHSET_LINES (:511).
const TECHSET_LINES := [[-146, -21, 146, -21, 0], [-147, -20, 147, -20, 1], [-146, -19, 146, -19, 0],
		[-146, 16, 146, 16, 0], [-147, 17, 147, 17, 1], [-146, 18, 147, 18, 0]]
## MOVES_VIEW_HELP_LINES (:520) and MOVES_VIEW_HELP_CORNERS (:535).
const HELP_LINES := [[-138, 26, -83, 26, 0], [-138, 27, -83, 27, 1], [-138, 28, -83, 28, 0],
		[-142, 30, -142, 89, 0], [-141, 30, -141, 89, 1], [-140, 30, -140, 89, 0],
		[-82, 30, -82, 89, 0], [-81, 30, -81, 89, 1], [-80, 30, -80, 89, 0],
		[-138, 91, -83, 91, 0], [-138, 92, -83, 92, 1], [-138, 93, -83, 93, 0]]
const HELP_CORNERS := [[-142, 26, 4, 4, 0x78, 0x10], [-83, 26, 4, 4, 0x7C, 0x10], [-142, 89, 4, 4, 0x78, 0x14],
		[-83, 89, 4, 4, 0x7C, 0x14]]
## DIGIMON_MOVE_INFO_LINES_LEFT / _RIGHT (US, :542, :578).
const INFO_LINES := [
	[[-102, 1, -17, 1, 0], [-102, 2, -17, 2, 1], [-102, 3, -17, 3, 0], [-145, 5, -145, 92, 0], [-144, 5, -144, 92, 1],
	[-143, 5, -143, 92, 0], [-15, 5, -15, 21, 0], [-14, 5, -14, 21, 1], [-13, 5, -13, 21, 0], [-142, 22, -16, 22, 0],
	[-143, 23, -16, 23, 1], [-142, 24, -16, 24, 0], [-61, 25, -61, 92, 0], [-60, 24, -60, 92, 1], [-59, 25, -59, 92, 0],
	[-141, 93, -62, 93, 0], [-141, 94, -62, 94, 1], [-141, 95, -62, 95, 0]],
	[[55, 1, 141, 1, 0], [55, 2, 141, 2, 1], [55, 3, 141, 3, 0], [12, 5, 12, 21, 0], [13, 5, 13, 21, 1],
	[14, 5, 14, 21, 0], [142, 5, 142, 92, 0], [143, 5, 143, 92, 1], [144, 5, 144, 92, 0], [16, 22, 142, 22, 0],
	[15, 23, 142, 23, 1], [16, 24, 142, 24, 0], [58, 25, 58, 92, 0], [59, 24, 59, 92, 1], [60, 25, 60, 92, 0],
	[62, 93, 141, 93, 0], [62, 94, 141, 94, 1], [62, 95, 141, 95, 0]],
]
## MOVES_VIEW_STRING_SPRITES (US, :689): x, y, width, u, v; MOVES_VIEW_SPRITES (US, :704).
const HELP_STRINGS := [[-114, -65, 0x73, 0x00, 0x18], [15, -65, 0x6E, 0x71, 0x18], [-114, -51, 0x00, 0xDF, 0x18],
		[-114, -34, 0x0C, 0x00, 0x24], [-102, -34, 0xBE, 0x0C, 0x24], [-90, -20, 0x00, 0x54, 0x30],
		[-102, 2, 0x64, 0x00, 0x3C], [-102, 18, 0x64, 0x00, 0x48], [-102, 34, 0x64, 0x00, 0x54],
		[-102, 50, 0x64, 0x00, 0x60], [-102, 66, 0x64, 0x00, 0x60], [-102, 82, 0x64, 0x00, 0x6C]]
const HELP_SPRITES := [[5, -65, 0xC, 0xC, 0x24, 0x00], [82, -34, 0xC, 0xC, 0x54, 0x00], [-66, -20, 0xC, 0xC, 0x24, 0x00],
		[-120, 2, 0xC, 0xC, 0x54, 0x00], [-120, 18, 0xC, 0xC, 0x24, 0x00], [-120, 50, 0xC, 0xC, 0x6C, 0x00],
		[-120, 82, 0xC, 0xC, 0xB4, 0x00]]
## The status names' text-area cells (US renderDigimonMovesSelected): u, width per status 1-4.
const STATUS_TEXT := {1: [0x84, 0x1A], 2: [0xA0, 0x1C], 3: [0xBC, 0x20], 4: [0xDB, 0x1E]}

var screen: DigimonScreen
## The grid cursor (MOVE_SELECT_BOX_X / Y).
var cursor := CURSOR_MIN
## The technique whose name is drawn at SELECTED_NAME_ROW (-1 none).
var _named := -1
## (row, column) -> technique id, and the techniques in id order as renderDigimonMoveBox walks them.
var _cells := {}
var _walk: Array = []


## move_data's menu_cell: the cell's technique (for a shared cell, the pair's first id).
func _build_cells() -> void:
	if not _cells.is_empty():
		return
	for record in screen.data.records("moves/move_data"):
		var cell = record.get("menu_cell")
		if cell == null:
			continue
		var id := int(record["id"])
		var key := Vector2i(int(cell["column"]), int(cell["row"]))
		var pair = record.get("learned_with")
		if pair != null and int(pair) < id:
			continue
		_cells[key] = id
		_walk.append(id)
	_walk.sort()


## The technique of a grid cell (column, row), -1 for none.
func technique_at(cell: Vector2i) -> int:
	_build_cells()
	return int(_cells.get(cell, -1))


func cursor_cell() -> Vector2i:
	return Vector2i((cursor.x - CURSOR_MIN.x) / 18, (cursor.y - CURSOR_MIN.y) / 15)


func _cell_of(id: int) -> Vector2i:
	var cell = screen.data.move(id).get("menu_cell")
	return Vector2i(int(cell["column"]), int(cell["row"])) if cell != null else Vector2i(-1, -1)


# --- strings and state (the C's render function's counting part) -------------------------------

## drawDigimonMovesText (game_menu.c:4048), one part per frame; true when done.
func draw_strings() -> bool:
	var area := screen.text_area
	var labels := DigimonScreen.STATUS_LABELS
	match screen.sub_state:
		0:
			area.clear(TEXT_AREA)
			MenuDraw.draw_digits(area)
			_draw_equipped(0)
			screen.sub_state = 1
		1:
			area.draw_string(screen.data.text(labels[3]), 0, 0x48)
			_draw_equipped(1)
			screen.sub_state = 2
		2:
			area.draw_string(screen.data.text(labels[6]), 0x84, 0x6C)
			_draw_equipped(2)
			screen.sub_state = 3
		3:
			_draw_equipped(3)
			area.draw_string(screen.data.text(labels[4]), 0, 0x6C)
			screen.sub_state = 4
		4:
			area.draw_string(screen.data.text(labels[5]), 0, 0x54)
			screen.sub_state = 5
		5:
			area.draw_string(screen.data.text(labels[7]), 0, 0x60)
			area.draw_string(screen.data.text(DigimonScreen.TECH_LABELS[0]), 0, 0x78)
			cursor = CURSOR_MIN
			_named = -1
			return true
	return false


## EQUIPPED_MOVES[slot] and its name at row 0x18 + 12 * slot.
func _draw_equipped(slot: int) -> void:
	var id := screen.equipped(slot)
	if id >= 0:
		screen.text_area.draw_string(screen.move_name(id), 0, slot * 0xC + 0x18)


## drawMoveViewHelpStrings (:3318): the help page's 8 lines (STATUS_VIEW_LABELS[9..16], which
## reads on into TECH_VIEW_LABELS[1..8]); true when done.
func draw_help_strings() -> bool:
	if screen.sub_state == 0:
		screen.text_area.clear(TEXT_AREA)
	screen.text_area.draw_string(screen.data.text(DigimonScreen.TECH_LABELS[screen.sub_state + 1]), 0, screen.sub_state * 0xC + 0x18)
	screen.sub_state += 1
	return screen.sub_state == 8


func update() -> void:
	var box: UIBoxes.Box = screen.boxes.boxes[1]
	match screen.menu_state:
		0:
			if draw_strings():
				screen.menu_state = 1
		2, 4:
			box.final.size.y -= 0x27
			if box.final.size.y < 0x4A:
				screen.menu_state += 1
		3, 5:
			box.final.size.y += 0x27
			if box.final.size.y > 0xBD:
				screen.menu_state = 6 if screen.menu_state == 3 else 1
		6:
			# renderDigimonMovesSelected draws the technique under the cursor into the text area.
			var id := technique_at(cursor_cell())
			if id != _named:
				_named = id
				screen.text_area.clear(Rect2i(0, SELECTED_NAME_ROW, 0x78, 0xC))
				if id >= 0 and screen.has_move(id):
					screen.text_area.draw_string(screen.move_name(id), 0, SELECTED_NAME_ROW)
		7:
			if draw_help_strings():
				screen.menu_state = 8
		9:
			if draw_strings():
				screen.menu_state = 6


func leave() -> void:
	pass


# --- input in the grid (tickDigimonMenu MENU_STATE 6) --------------------------------------------

func tick_grid() -> void:
	var pad := screen.pad
	if pad.is_key_down(Pad.CANCEL):
		# A partner keeps one attack equipped (power != 0) to leave the grid.
		var attack := false
		for slot in 3:
			var id := screen.equipped(slot)
			if id >= 0 and int(screen.data.move(id).get("power", 0)) != 0:
				attack = true
				break
		if attack:
			screen.menu_state = 4
		screen.play_sound(4)
	elif pad.is_key_down(Pad.SQUARE):
		screen.menu_state = 7
		screen.sub_state = 0
		screen.play_sound(3)
	elif pad.is_key_down(Pad.CONFIRM):
		var slot := equipped_slot()
		if slot >= 0:
			screen.set_equipped(slot, -1)
			screen.play_sound(3)
		else:
			equip()
	var before := cursor
	if pad.is_changed(Pad.UP):
		cursor.y -= CURSOR_STEP.y
	if pad.is_changed(Pad.DOWN):
		cursor.y += CURSOR_STEP.y
	if pad.is_changed(Pad.LEFT):
		cursor.x -= CURSOR_STEP.x
	if pad.is_changed(Pad.RIGHT):
		cursor.x += CURSOR_STEP.x
	cursor = Vector2i(clampi(cursor.x, CURSOR_MIN.x, CURSOR_MAX.x), clampi(cursor.y, CURSOR_MIN.y, CURSOR_MAX.y))
	if cursor != before:
		screen.play_sound(2)


## getEquippedSlot (:2260): the slot holding the cursor's technique (or its pair), -1.
func equipped_slot() -> int:
	var id := technique_at(cursor_cell())
	if id < 0:
		return -1
	var pair = screen.data.move(id).get("learned_with")
	for slot in 3:
		var e := screen.equipped(slot)
		if e == id or (pair != null and e == int(pair)):
			return slot
	return -1


## equipMove (:2298): learned, usable by the partner's Digimon (its own variant of a pair), into
## the first free of the 3 slots; else the refusal sound.
func equip() -> void:
	var id := technique_at(cursor_cell())
	if id < 0 or not screen.has_move(id):
		screen.play_sound(4)
		return
	var usable := screen.digimon_moves()
	var pair = screen.data.move(id).get("learned_with")
	if not usable.has(id):
		if pair != null and usable.has(int(pair)):
			id = int(pair)
		else:
			screen.play_sound(4)
			return
	for slot in 3:
		if screen.equipped(slot) < 0:
			screen.set_equipped(slot, id)
			screen.text_area.clear(Rect2i(0, slot * 12 + 0x18, 0x84, 0xC))
			screen.text_area.draw_string(screen.move_name(id), 0, slot * 12 + 0x18)
			screen.play_sound(3)
			return
	screen.play_sound(4)


# --- drawing ---------------------------------------------------------------------------------------

func draw(canvas: CanvasItem) -> void:
	var state := screen.menu_state
	if state > 0 and state < 7:
		_draw_techset(canvas)
	match state:
		1:
			_draw_summary(canvas)
		6:
			_draw_grid(canvas)
		8:
			_draw_help(canvas)


func _draw_techset(canvas: CanvasItem) -> void:
	var area := screen.text_area
	for t in TECHSET:
		MenuDraw.sprite(canvas, t[0], t[1], t[2], t[3], t[4], t[5], 0x7B06)
	area.render_string(canvas, 3, -0x8E, -0x57, 0x3C, 0xC, 0, 0x48, true)
	for j in 3:
		var id := screen.equipped(j)
		if id < 0:
			continue
		var move: Dictionary = screen.data.move(id)
		area.render_string(canvas, 0, -0x7C, j * 0xF - 0x42, 0x78, 0xC, 0, j * 0xC + 0x18, true)
		MenuDraw.number(canvas, area, 0, 0x10, j * 0xF - 0x43, 3, int(move.get("power", 0)))
		MenuDraw.number(canvas, area, 0, 0x39, j * 0xF - 0x43, 3, int(move.get("mp", 0)))
		var range_id := int(move.get("range", {}).get("id", 0))
		if range_id != 0:
			area.render_string(canvas, 0, 0x65, j * 0xF - 0x42, 0xC, 0xC, (range_id - 1) * 0x24, 0x78, true)
		var status := int(move.get("status", {}).get("id", 0))
		if status != 0:
			MenuDraw.sprite(canvas, 0x7D, j * 0xF - 0x43, 0xC, 0xC, (status - 1) * 0xC, 0xC, 0x7A06)
	MenuDraw.lines(canvas, TECHSET_LINES.slice(0, 3))


func _draw_summary(canvas: CanvasItem) -> void:
	var area := screen.text_area
	area.render_string(canvas, 3, -0x8E, -0xF, 0x24, 0xC, 0x3C, 0x48, true)
	for i in 3:
		var t: Array = TECHSET[i]
		MenuDraw.sprite(canvas, t[0], -9, t[2], t[3], t[4], t[5], 0x7B06)
	MenuDraw.sprite(canvas, 0x75, 4, 4, 4, 0x78, 0xC, 0x7B06)
	MenuDraw.lines(canvas, TECHSET_LINES.slice(3, 6))
	var finisher := screen.equipped(3)
	if finisher >= 0:
		var move: Dictionary = screen.data.move(finisher)
		area.render_string(canvas, 3, -0x8E, -0xF, 0x24, 0xC, 0x3C, 0x48, true)
		area.render_string(canvas, 0, -0x7C, 1, 0x84, 0xC, 0, 0x3C, true)
		MenuDraw.number(canvas, area, 0, 0x10, 0, 3, int(move.get("power", 0)))
		# The finisher's range uses the JP layout of the labels in every release (kept).
		area.render_string(canvas, 0, 0x65, 1, 0xC, 0xC, (int(move.get("range", {}).get("id", 0)) - 1) * 0xC + 0x48, 0x6C, true)
		var status := int(move.get("status", {}).get("id", 0))
		if status != 0:
			MenuDraw.sprite(canvas, 0x7D, 0, 0xC, 0xC, (status - 1) * 0xC, 0xC, 0x7A06)
	# US: the two help lines.
	area.render_string(canvas, 0xF, -0x82, 0x19, 0xC, 0xC, 0, 0x54, true)
	area.render_string(canvas, 0, -0x76, 0x19, 0xA8, 0xC, 0xC, 0x54, true)
	area.render_string(canvas, 0, -0x76, 0x27, 0x84, 0xC, 0xC, 0x60, true)
	area.render_string(canvas, 7, -0x82, 0x27, 0xC, 0xC, 0, 0x60, true)
	area.render_string(canvas, 0, 0xE, 0x27, 0x18, 0xC, 0x90, 0x60, true)


func _draw_grid(canvas: CanvasItem) -> void:
	var area := screen.text_area
	area.render_string(canvas, 3, -0x8E, -0xF, 0x3C, 0xC, 0x60, 0x48, true)
	MenuDraw.lines(canvas, HELP_LINES)
	for c in HELP_CORNERS:
		MenuDraw.sprite(canvas, c[0], c[1], c[2], c[3], c[4], c[5], 0x7B06)
	area.render_string(canvas, 0, -0x87, 0x20, 0x30, 0xC, 0x3C, 0, true)
	area.render_string(canvas, 0, -0x81, 0x2E, 0x24, 0xC, 0, 0x6C, true)
	area.render_string(canvas, 0xC, -0x74, 0x4C, 0x18, 0xC, 0x30, 0x6C, true)
	MenuDraw.sprite(canvas, -0x74, 0x3C, 10, 10, 0x80, 0xC, 0x7B06)
	for j in 7:
		MenuDraw.sprite(canvas, -0x43, j * 0xF - 8, 0x14, 10, j * 0x14, 0x18, 0x7B06)
		MenuDraw.sprite(canvas, 100, j * 0xF - 8, 0x14, 10, j * 0x14, 0x18, 0x7B06)
	for j in 8:
		MenuDraw.sprite(canvas, j * 0x12 - 0x26, -0xF, 4, 5, j * 4 + 0x94, 0xC, 0x7B06)
	for row in 7:
		for col in 8:
			MenuDraw.box(canvas, col * 0x12 - 0x2A, row * 0xF - 7, 0xC, 0xC, 0x4E, 0x60, 0x6E, 0x80)
	# The cursor is on layer 5 with the grid (over its boxes), the cells on layer 4 over it.
	MenuDraw.sprite(canvas, cursor.x - 0xA0, cursor.y - 0x78, 0x12, 0x10, 0xC0, 0xC, 0x7B06)
	_draw_cells(canvas)
	_draw_selected(canvas, 0 if cursor.x > 0xA8 else 1)


## renderDigimonMoveBox (:3183): the equipped cells red, the cells the partner's Digimon can't use
## dark, the learned techniques' icons. All on ordering-table layer 4, where what is added first is
## drawn last: the C adds the red boxes first (they end up over the icons), then per technique its
## dark box before its icon. The primitives are collected in the C's order and drawn reversed.
func _draw_cells(canvas: CanvasItem) -> void:
	_build_cells()
	var prims := []
	for slot in 3:
		var id := screen.equipped(slot)
		if id >= 0:
			var cell := _cell_of(id)
			if cell.x >= 0:
				prims.append(["box", cell.x * 0x12 - 0x2A, cell.y * 0xF - 7, 200, 0, 0x28, 1])
	# The C walks the cells in technique id order against the Digimon's sorted techniques; a
	# technique of its list the walk never meets (a pair's second id) stops the matching there
	# (quirk kept: the cells after it all look unusable).
	var moves := screen.digimon_moves()
	moves.sort()
	var i := 0
	var blink := 0 if screen.playtime_frames() % 0x14 < 10 else 0xC
	for id in _walk:
		var cell := _cell_of(id)
		var pair = screen.data.move(id).get("learned_with")
		if pair != null:
			if not moves.has(id) and not moves.has(int(pair)):
				prims.append(["box", cell.x * 0x12 - 0x2A, cell.y * 0xF - 7, 0x68, 0x68, 0x68, 3])
		if i < moves.size() and id == moves[i]:
			i += 1
		elif pair == null:
			prims.append(["box", cell.x * 0x12 - 0x2A, cell.y * 0xF - 7, 0x68, 0x68, 0x68, 3])
		if screen.has_move(id):
			var special := int(screen.data.move(id).get("element", {}).get("id", 0))
			var clut := 0x7A06
			if special >= 2 and special <= 4:
				clut = 0x7A46
			elif special == 5:
				clut = 0x7A86
			prims.append(["sprite", cell.x * 0x12 - 0x2A, special * 0xF - 7, blink + special * 0x18 + 0x24, clut])
	prims.reverse()
	for p in prims:
		if p[0] == "box":
			MenuDraw.box(canvas, p[1], p[2], 0xC, 0xC, p[3], p[4], p[5], p[6])
		else:
			MenuDraw.sprite(canvas, p[1], p[2], 0xC, 0xC, p[3], 0, p[4])


## renderDigimonMovesSelected (US, :3060): the panel on the side away from the cursor.
func _draw_selected(canvas: CanvasItem, panel: int) -> void:
	MenuDraw.lines(canvas, INFO_LINES[panel])
	MenuDraw.sprite(canvas, panel * 0x9D - 0x91, 1, 4, 4, 0x78, 0x10, 0x7B06)
	MenuDraw.sprite(canvas, panel * 0x9D - 0x10, 1, 4, 4, 0x7C, 0x10, 0x7B06)
	MenuDraw.sprite(canvas, panel * 0xCB - 0x91, 0x5C, 4, 4, 0x78, 0x14, 0x7B06)
	MenuDraw.sprite(canvas, panel * 0xCB - 0x3E, 0x5C, 4, 4, 0x7C, 0x14, 0x7B06)
	if panel == 0:
		MenuDraw.sprite(canvas, -0x10, 0x15, 4, 4, 0x7C, 0x14, 0x7B06)
	else:
		MenuDraw.sprite(canvas, 0xC, 0x15, 4, 4, 0x78, 0x14, 0x7B06)
	MenuDraw.box(canvas, panel * 0x9D - 0x8F, 3, 0x80, 0x13, 0x32, 0x32, 0x80)
	MenuDraw.box(canvas, panel * 0xCB - 0x8F, 0x18, 0x57, 0x45, 0x32, 0x32, 0x80)
	MenuDraw.sprite(canvas, panel * 0x9D - 0x8C, -2, 0x25, 7, 0x11, 0x30, 0x7B06)
	MenuDraw.sprite(canvas, panel * 0xCB - 0x8C, 0x1D, 0x17, 7, 0x5C, 0x22, 0x7B06)
	MenuDraw.sprite(canvas, panel * 0xCB - 0x8C, 0x2E, 0xB, 7, 0x74, 0x22, 0x7B06)
	MenuDraw.sprite(canvas, panel * 0xCB - 0x8C, 0x3F, 0x13, 7, 0x4C, 0x29, 0x7B06)
	MenuDraw.sprite(canvas, panel * 0xCB - 0x8C, 0x50, 0x10, 7, 0, 0x30, 0x7B06)
	for i in 4:
		MenuDraw.sprite(canvas, panel * 0xCB - 0x71, i * 0x11 + 0x1B, 0xA, 0xA, 0x8A, 0xC, 0x7B06)
	var id := technique_at(cursor_cell())
	if id < 0 or not screen.has_move(id):
		return
	var area := screen.text_area
	var move: Dictionary = screen.data.move(id)
	area.render_string(canvas, 0, panel * 0x9D - 0x8A, 9, 0x78, 0xC, 0, SELECTED_NAME_ROW, true)
	MenuDraw.number(canvas, area, 0, panel * 0xCB - 0x64, 0x1B, 3, int(move.get("power", 0)))
	MenuDraw.number(canvas, area, 0, panel * 0xCB - 0x64, 0x2C, 3, int(move.get("mp", 0)))
	area.render_string(canvas, 0, panel * 0xCB - 0x64, 0x3E, 0x24, 0xC, (int(move.get("range", {}).get("id", 0)) - 1) * 0x24, 0x78, true)
	var status := int(move.get("status", {}).get("id", 0))
	if STATUS_TEXT.has(status):
		area.render_string(canvas, 0, panel * 0xCB - 0x64, 0x4F, STATUS_TEXT[status][1], 0xC, STATUS_TEXT[status][0], 0x6C, true)


## The help page (MENU_STATE 8).
func _draw_help(canvas: CanvasItem) -> void:
	var area := screen.text_area
	PsxDraw.line2(canvas, 0x020202, -0x92, -4, 0x92, -4)
	PsxDraw.line2(canvas, 0xFAD990, -0x93, -3, 0x93, -3)
	PsxDraw.line2(canvas, 0x020202, -0x92, -2, 0x92, -2)
	area.render_string(canvas, 3, -0x8E, -0x52, 0xA0, 0xC, 0, 0x30, true)
	area.render_string(canvas, 0xE, -0x72, -0x32, 0xC, 0xC, 0xCC, 0x30, true)
	area.render_string(canvas, 0xE, 6, -0x21, 0xC, 0xC, 0xCC, 0x30, true)
	area.render_string(canvas, 0xE, -0x2A, -0x13, 0xC, 0xC, 0xCC, 0x30, true)
	for s in HELP_STRINGS:
		area.render_string(canvas, 0, s[0], s[1] + 1, s[2], 0xC, s[3], s[4], true)
	area.render_string(canvas, 0, 0x42, 0x33, 0x3C, 0xC, 0x78, 0x48, true)
	area.render_string(canvas, 0, 0x42, 0x43, 0x3C, 0xC, 0x84, 0x54, true)
	MenuDraw.sprite(canvas, -0x81, -0x41, 0xC, 0xC, 0xB4, 0xC, 0x7B06)
	MenuDraw.sprite(canvas, -0x81, -0x22, 0xC, 0xC, 0xB4, 0xC, 0x7B06)
	MenuDraw.sprite(canvas, -0x7B, 0x50, 0x12, 0x10, 0xC0, 0xC, 0x7B06)
	for i in HELP_SPRITES.size():
		if i == 2:
			continue  # US leaves this one out
		var s: Array = HELP_SPRITES[i]
		MenuDraw.sprite(canvas, s[0], s[1], s[2], s[3], s[4], s[5], 0x7A46 if i == 5 else 0x7A06, 0x80)
	MenuDraw.box(canvas, 0x52, -0x22, 0xC, 0xC, 200, 0, 0x28, 0x81)
	MenuDraw.box(canvas, -0x78, 2, 0xC, 0xC, 200, 0, 0x28, 0x81)
	MenuDraw.box(canvas, -0x78, 0x22, 0xC, 0xC, 0x4E, 0x60, 0x6E, 0x80)
	MenuDraw.box(canvas, -0x78, 0x32, 0xC, 0xC, 0x68, 0x68, 0x68, 0x83)
	MenuDraw.box(canvas, -0x78, 0x42, 0xC, 0xC, 0x68, 0x68, 0x68, 0x83)
