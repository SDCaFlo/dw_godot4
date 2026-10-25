class_name PlayerInfoTab
extends Node
## The Player screen's Info tab (renderPlayerInfoView, game_menu.c:2976; specs/status_screens.md
## §4.1): the tamer's name, level and title, Digimon raised, bits, play time, key items, medal count
## and his model. `update` runs where the C's render function counts (the strings, one part per
## frame), `draw` draws.

## PLAYER_INFO_TEXT_AREA.
const TEXT_AREA := Rect2i(0, 12, 256, 200)
## TAMER_LEVEL_TITLES (game_menu.c:1127), the text ids, drawn at rows 0x40 + level * 12.
const TITLES := ["MAIN_D_801342A8", "MAIN_D_801342B0", "MAIN_D_80123DE8", "MAIN_D_80123DF4", "MAIN_D_80123E04",
		"MAIN_D_801342B8", "MAIN_D_80123E10", "MAIN_D_801342C0", "MAIN_D_801342C8", "MAIN_D_801342D0", "MAIN_D_801342D8"]
## TAMER_VIEW_PLAYER_LINES (:795): x1, y1, x2, y2, colour.
const LINES := [[-146, -65, 146, -65, 0], [-147, -64, 147, -64, 1], [-146, -63, 146, -63, 0], [-45, -63, 146, -63, 0],
		[-47, -63, -47, 98, 0], [-46, -64, -46, 99, 1], [-45, -63, -45, 43, 0], [-46, 44, 145, 44, 0],
		[-45, 45, 147, 45, 1], [-45, 46, 145, 46, 0], [-45, 47, -45, 100, 0]]
## TAMER_WINDOW_BOXES (:809): absolute x, y, w, h.
const INSETS := [[74, 38, 75, 14], [211, 64, 27, 14], [211, 101, 27, 14], [211, 195, 27, 14], [198, 82, 99, 14],
		[199, 120, 75, 14], [199, 140, 75, 14], [211, 174, 18, 18], [231, 174, 18, 18], [251, 174, 18, 18],
		[271, 174, 18, 18]]
## TAMER_WINDOW_NAME_STRING (US, :824): x, y, width, u, v; the first 7 in colour 3, the others 0.
const LABELS := [[-124, -81, 0x24, 0x00, 0x0C], [-37, -54, 0x54, 0x24, 0x0C], [-37, -17, 0x54, 0x78, 0x0C],
		[-37, 2, 0x48, 0x00, 0x18], [-37, 22, 0x48, 0x60, 0x18], [-37, 57, 0x54, 0x00, 0x24],
		[-37, 77, 0x48, 0x54, 0x24], [0x50, -17, 0x18, 0xCC, 0x0C], [0x74, 2, 0x18, 0x48, 0x18],
		[0x4D, 0x16, 0x0C, 0xA8, 0x18], [0x50, 0x4D, 0x0C, 0x9C, 0x24]]
## The key items (triggers 0x2D-0x30) and their icons on SYSTEM_W (texY 0x20, palette 7): x, u.
const KEY_ITEMS := [[0x2D, 0x34, 0xB0], [0x2E, 0x49, 0xC0], [0x2F, 0x5E, 0xE0], [0x30, 0x73, 0xD0]]
const KEY_ITEM_CLUT := 0x7BC6
## The medals counted: the C counts 0x12 triggers from 0x16C (there are 15 medals).
const MEDAL_TRIGGERS := 0x12
## FMT_PLAYTIME (US) and its row.
const PLAYTIME_ROW := 0xE4

var screen: PlayerScreen


## MENU_STATE 0: drawPlayerInfoStrings (game_menu.c:4126), one part per frame. True when done.
func draw_strings() -> bool:
	var area := screen.text_area
	var data := screen.data
	var sub := screen.sub_state
	match sub:
		0:
			area.clear(TEXT_AREA)
			MenuDraw.draw_digits(area)
			screen.sub_state = 1
		1, 2, 3:
			if sub == 1:
				var playtime: Dictionary = screen.game_state.state["clock"]["playtime"]
				area.draw_string("%d : %d" % [int(playtime["hours"]), int(playtime["minutes"])], 0, PLAYTIME_ROW)
			area.draw_string(data.text(PlayerScreen.PLAYER_LABELS[sub + 1]), 0, (sub - 1) * 0xC + 0xC)
			screen.sub_state = sub + 1
		4:
			# DIGIMON_NAME(0): DIGIMON_DATA[0].name, where naming the player writes his name.
			area.draw_string(tamer_name(), 0, 0x30)
			for i in 4:
				area.draw_string(data.text(TITLES[i]), 0, i * 0xC + 0x40)
			screen.sub_state = 5
		5:
			for i in range(4, TITLES.size()):
				area.draw_string(data.text(TITLES[i]), 0, i * 0xC + 0x40)
			return true
	return false


func update() -> void:
	if screen.menu_state == 0 and draw_strings():
		screen.menu_state = 1
		if screen.digivice != null:
			# renderDigiviceEntity(ENTITY_TABLE[0]): the tamer, at RAISE_DATA[his type].view.
			screen.digivice.show_digimon(screen.data, 0)


func leave() -> void:
	if screen.digivice != null:
		screen.digivice.hide_model()


func tamer_name() -> String:
	return str(screen.game_state.state["tamer"]["name"])


func level() -> int:
	return int(screen.game_state.state["tamer"]["level"])


func medal_count() -> int:
	var count := 0
	for j in MEDAL_TRIGGERS:
		if screen.has_medal(j):
			count += 1
	return count


## The C's adds, drawn in reverse (one ordering-table layer): the model and the insets under all.
func draw(canvas: CanvasItem) -> void:
	if screen.menu_state != 1:
		return
	var area := screen.text_area
	var gs: Node = screen.game_state
	if screen.digivice != null:
		screen.digivice.draw_on(canvas)
	for k in range(INSETS.size() - 1, -1, -1):
		var r: Array = INSETS[k]
		MenuDraw.inset_box(canvas, r[0], r[1], r[2], r[3])
	MenuDraw.number(canvas, area, 0, 0x35, 0x4D, 2, medal_count())
	for k in range(KEY_ITEMS.size() - 1, -1, -1):
		var item: Array = KEY_ITEMS[k]
		if gs.is_trigger_set(item[0]):
			MenuDraw.sprite(canvas, item[1], 0x37, 0x10, 0x10, item[2], 0xA0 - 0x80, KEY_ITEM_CLUT)
	# US: the play time as text ("%d : %d"), the other releases two numbers.
	area.render_string(canvas, 0, 0x32, 0x16, 0x4C, 0xC, 0, PLAYTIME_ROW, true)
	MenuDraw.number(canvas, area, 0, 0x29, 2, 6, int(gs.state["money"]))
	MenuDraw.number(canvas, area, 0, 0x35, -0x11, 2, int(gs.state["tamer"]["raised_count"]))
	var lvl := clampi(level(), 0, TITLES.size() - 1)
	# The title's suffix cell (a leftover of the Japanese layout: empty in the US text).
	var n: int = str(screen.data.text(TITLES[lvl])).length() / 2
	area.render_string(canvas, 0, n * 12 + 0x28, -0x25, 0x30, 0xC, 0xB4, 0x18, true)
	area.render_string(canvas, 0, 0x28, -0x24, 0x64, 0xC, 0, lvl * 12 + 0x40, true)
	MenuDraw.number(canvas, area, 0, 0x35, -0x36, 2, level())
	area.render_string(canvas, 0, -0x54, -0x50, 0x48, 0xC, 0, 0x30, true)
	for i in range(LABELS.size() - 1, -1, -1):
		var l: Array = LABELS[i]
		area.render_string(canvas, 3 - (i / 7) * 3, l[0], l[1] + 1, l[2], 0xC, l[3], l[4], true)
	var lines := LINES.duplicate()
	lines.reverse()
	MenuDraw.lines(canvas, lines)
