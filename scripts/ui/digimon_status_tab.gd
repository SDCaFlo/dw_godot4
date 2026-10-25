class_name DigimonStatusTab
extends Node
## The Digimon screen's Status tab (renderDigimonStatsView, game_menu.c:2402; specs/status_screens.md
## §3.2): the partner's values, its specialties, lives, conditions, the happiness / discipline /
## virus bars and its model. `update` runs where the C's render function counts (the strings, one
## part per frame), `draw` draws.

## DIGIMON_STATS_TEXT_AREA.
const TEXT_AREA := Rect2i(0, 24, 256, 200)
## STATS_VIEW_LINES (game_menu.c:502): x1, y1, x2, y2, colour.
const LINES := [[-27, -15, -27, 99, 0], [-26, -16, -26, 100, 1], [-27, -15, -25, 99, 0],
		[-146, -18, 146, -18, 0], [-147, -17, 147, -17, 1], [-146, -16, 146, -16, 0]]
## STATS_VIEW_TEXT (US, :736): x, y, width, u, v (drawn in colour 3 at y + 1).
const LABELS := [[-138, 34, 0x30, 0x48, 0x30], [-126, 64, 0x24, 0x18, 0x30], [-126, 79, 0x24, 0x78, 0x30],
		[-4, 4, 0x18, 0x9C, 0x30], [-4, 19, 0x18, 0xB4, 0x30], [-4, 34, 0x24, 0x00, 0x24],
		[-4, 49, 0x24, 0x24, 0x24], [-81, -35, 0, 0x00, 0x30], [-10, -35, 0, 0x00, 0x30]]
## STATS_VIEW_ELEMENTS (:761, US): x, y, width, height, u, texY; palettes STATS_VIEW_ELEMENT_CLUT.
const ICONS := [[-140, -81, 0x35, 0x0B, 0x00, 0x4B], [-140, -12, 0x35, 0x0B, 0x00, 0x56],
		[-18, -12, 0x35, 0x0B, 0x00, 0x61], [-138, -66, 0x1A, 0x0A, 0x80, 0x30], [-138, -50, 0x1A, 0x0A, 0x9A, 0x30],
		[-67, -34, 0x1C, 0x0A, 0xB4, 0x30], [-133, -34, 0x13, 0x0A, 0x80, 0x3A], [52, -62, 0x19, 0x08, 0x00, 0x38],
		[9, -62, 0x19, 0x08, 0x19, 0x38], [85, -62, 0x19, 0x08, 0x32, 0x38], [-137, 79, 0x09, 0x0B, 0xF0, 0x25],
		[-17, 4, 0x0B, 0x0B, 0x93, 0x3A], [-17, 19, 0x0B, 0x0B, 0x9E, 0x3A], [-17, 34, 0x0B, 0x0B, 0xA9, 0x3A],
		[-17, 49, 0x0B, 0x0B, 0xB4, 0x3A], [-17, 64, 0x0B, 0x0B, 0xBF, 0x3A], [-17, 79, 0x0A, 0x0B, 0xCA, 0x3A],
		[-126, 49, 0x24, 0x0C, 0xD4, 0x3A], [-4, 64, 0x24, 0x0C, 0xD4, 0x46], [-4, 79, 0x24, 0x0C, 0xD4, 0x52],
		[-138, 79, 0x09, 0x0B, 0x2C, 0x74]]
const ICON_PALETTES := [8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 10, 11, 11, 11, 11, 11, 11, 4, 4, 4, 10]
## STATS_VIEW_INSETS (:715, US): absolute x, y, w, h.
const INSETS := [[50, 52, 98, 14], [50, 68, 244, 14], [50, 84, 26, 14], [122, 84, 26, 14], [75, 171, 50, 8],
		[75, 186, 50, 8], [75, 201, 50, 8], [194, 130, 104, 5], [194, 145, 104, 5], [194, 160, 54, 5],
		[194, 175, 54, 5], [194, 190, 54, 5], [194, 205, 54, 5]]
## MAIN_D_80123DD0: the condition bits shown, in order (sick, injured, hungry, sleepy, unhappy, tired).
const CONDITIONS := [0x40, 0x20, 0x04, 0x01, 0x10, 0x02]
const POOPY := 0x08
## The bars' palettes on SBOY (GetClut(0x70, 0x1F6 / 0x1F5)) and the faces' (GetClut(0x60, 0x1F2)).
const BAR_FILL := 0x1F6
const BAR_BASE := 0x1F5
const FACE_CLUT := (0x1F2 << 6) | (0x60 >> 4)

var screen: DigimonScreen


## MENU_STATE 0: drawDigimonStatsStrings (game_menu.c:3859), one part per frame. True when done.
func draw_strings() -> bool:
	var area := screen.text_area
	var data := screen.data
	match screen.sub_state:
		0:
			area.clear(TEXT_AREA)
			MenuDraw.draw_digits(area)
			area.draw_string(data.text("STR_STAT_LABEL_OFFENSE"), 0, 0x24)
			area.draw_string(data.text("STR_STAT_LABEL_DEFENSE"), 0x24, 0x24)
			screen.sub_state = 1
		1:
			area.draw_string(screen.digimon_name(), 0, 0x48)
			area.draw_string(str(screen.partner_state()["name"]), 0, 0x3C)
			screen.sub_state = 2
		2:
			area.draw_string(data.text(DigimonScreen.STATUS_LABELS[1]), 0, 0x30)
			screen.sub_state = 3
		3:
			area.draw_string(data.text(DigimonScreen.STATUS_LABELS[2]), 0, 0x18)
			return true
	return false


## The counting part: the strings, then the model shows.
func update() -> void:
	if screen.menu_state == 0:
		if draw_strings():
			screen.menu_state = 1
			if screen.digivice != null:
				screen.digivice.show_digimon(screen.data, screen.partner_state()["digimon"])


func leave() -> void:
	if screen.digivice != null:
		screen.digivice.hide_model()


func draw(canvas: CanvasItem) -> void:
	if screen.menu_state != 1:
		return
	var area := screen.text_area
	var p: Dictionary = screen.partner_state()
	var care: Dictionary = p["care"]
	var base: Dictionary = p["stats"]["base"]
	var current: Dictionary = p["stats"]["current"]
	var record: Dictionary = screen.data.digimon(p["digimon"])
	# The model first: under everything else of the window (renderDigiviceEntity sorts it in last).
	if screen.digivice != null:
		screen.digivice.draw_on(canvas)
	for r in INSETS:
		MenuDraw.inset_box(canvas, r[0], r[1], r[2], r[3])
	MenuDraw.lines(canvas, LINES)
	for l in LABELS:
		area.render_string(canvas, 3, l[0], l[1] + 1, l[2], 0xC, l[3], l[4], true)
	for j in ICONS.size():
		var i: Array = ICONS[j]
		MenuDraw.sprite(canvas, i[0], i[1], i[2], i[3], i[4], i[5], (488 + ICON_PALETTES[j]) << 6 | 6)
	area.render_string(canvas, 0, -0x6D, -0x42, 0x48, 0xC, 0, 0x3C)
	# US: the Digimon's name 10 pixels per character, at most 0x78.
	area.render_string(canvas, 0, -0x6C, -0x32, mini(screen.digimon_name().length() * 10, 0x78), 0xC, 0, 0x48)
	MenuDraw.number(canvas, area, 0, -0x6D, -0x22, 2, int(care["age"]))
	MenuDraw.number(canvas, area, 0, -0x23, -0x22, 2, int(care["weight"]))
	MenuDraw.number(canvas, area, 0, 0x23, 1, 4, int(current["hp"]))
	MenuDraw.number(canvas, area, 0, 0x5F, 1, 4, int(base["max_hp"]))
	MenuDraw.number(canvas, area, 0, 0x23, 0x10, 4, int(current["mp"]))
	MenuDraw.number(canvas, area, 0, 0x5F, 0x10, 4, int(base["max_mp"]))
	MenuDraw.number(canvas, area, 0, 0x23, 0x1F, 4, int(base["offense"]))
	MenuDraw.number(canvas, area, 0, 0x23, 0x2E, 4, int(base["defense"]))
	MenuDraw.number(canvas, area, 0, 0x23, 0x3D, 4, int(base["speed"]))
	MenuDraw.number(canvas, area, 0, 0x23, 0x4C, 4, int(base["brains"]))
	_bar(canvas, int(base["max_hp"]), 9999, 0x64, 0x24, 0xC)
	_bar(canvas, int(base["max_mp"]), 9999, 0x64, 0x24, 0x1B)
	_bar(canvas, int(base["offense"]), 999, 0x32, 0x24, 0x2A)
	_bar(canvas, int(base["defense"]), 999, 0x32, 0x24, 0x39)
	_bar(canvas, int(base["speed"]), 999, 0x32, 0x24, 0x48)
	_bar(canvas, int(base["brains"]), 999, 0x32, 0x24, 0x57)
	# The specialties (DIGIMON_DATA.special), blinking every 5 frames.
	var blink := 0 if screen.playtime_frames() % 10 < 5 else 0xC
	var k := 0
	for element in record.get("elements", []):
		var special := int(element.get("id", 0xFF))
		if special == 0xFF:
			continue
		var clut := 0x7A06
		if special >= 2 and special <= 4:
			clut = 0x7A46
		elif special == 5:
			clut = 0x7A86
		MenuDraw.sprite(canvas, k + 9, -0x33, 0xC, 0xC, blink + special * 0x18 + 0x24, 0, clut)
		k += 0xC
	var type_id := int(record.get("type", {}).get("id", 0))
	if type_id != 0:
		MenuDraw.sprite(canvas, 0x3B, -0x33, 0xC, 0xC, (type_id - 1) * 0xC, 0, 0x7A06)
	var cycle := int(screen.data.raise_data(p["digimon"]).get("sleep_cycle", {}).get("id", 0))
	if cycle == 5:
		area.render_string(canvas, 0, 0x55, -0x33, 0x30, 0xC, 0xCC, 0x30)
	elif cycle < 5:
		area.render_string(canvas, 0, 0x55, -0x33, 0x30, 0xC, cycle * 0x30, 0x18)
	# Lives: the empty heart under, the full one over it.
	for i in 3:
		MenuDraw.sprite(canvas, i * 0xE - 0x54, 0x22, 0xC, 0xB, 0xF4, 0xC, 0x7B86)
		if i < int(p.get("lives", 0)):
			MenuDraw.sprite(canvas, i * 0xE - 0x54, 0x22, 0xC, 0xB, 0xE8, 0xC, 0x7B86)
	_conditions(canvas, int(care["condition"]))
	var happiness := int(care["happiness"])
	MenuDraw.sprite(canvas, -0x8A, 0x31, 0xB, 0xB, 0 if happiness >= 0 else 0xB, 0x74, FACE_CLUT)
	if happiness >= 0:
		MenuDraw.sboy_sprite(canvas, -0x54, 0x35, 0x32, 6, 0x4A, 0xF0, BAR_BASE)
		MenuDraw.sboy_sprite(canvas, -0x54, 0x35, (0x32 - (0x32 - happiness / 2)) & 0xFF, 6, 0x18, 0xF0, BAR_FILL)
	else:
		MenuDraw.sboy_sprite(canvas, -0x54, 0x35, (0x32 - (0x32 - (happiness + 0x64) / 2)) & 0xFF, 6, 0x4A, 0xF0, BAR_BASE)
	var discipline := int(care["discipline"])
	MenuDraw.sprite(canvas, -0x8A, 0x40, 0xB, 0xB, 0x16 if discipline >= 0x32 else 0x21, 0x74, FACE_CLUT)
	if discipline >= 0x32:
		MenuDraw.sboy_sprite(canvas, -0x54, 0x44, 0x32, 6, 0x4A, 0xF0, BAR_BASE)
		MenuDraw.sboy_sprite(canvas, -0x54, 0x44, (discipline - 0x32) & 0xFF, 6, 0x18, 0xF0, BAR_FILL)
	else:
		MenuDraw.sboy_sprite(canvas, -0x54, 0x44, discipline & 0xFF, 6, 0x4A, 0xF0, BAR_BASE)
	MenuDraw.box(canvas, -0x54, 0x52, int(care["virus_bar"]) * 3, 6, 0xC8, 0xC8, 0x3C)


## renderDigimonStatsBar (:3899): width = scale * value / max, 2 high.
func _bar(canvas: CanvasItem, value: int, max_value: int, scale: int, x: int, y: int) -> void:
	MenuDraw.box(canvas, x, y, (scale * value / max_value) & 0xFF, 2, 0x32, 0xC8, 0xC8)


## renderDigimonStatusConditions (:3912): one bobbing icon per condition, and the poop.
func _conditions(canvas: CanvasItem, condition: int) -> void:
	var t := screen.playtime_frames() % 16
	var bob := 0x82
	if t < 3:
		bob = 0x82
	elif t < 5:
		bob = 0x80
	elif t < 7:
		bob = 0x7D
	elif t < 9:
		bob = 0x79
	elif t < 11:
		bob = 0x7D
	elif t < 13:
		bob = 0x80
	for i in CONDITIONS.size():
		if condition & CONDITIONS[i]:
			var clut := 0x7A06
			if i == 0 or i == 4:
				clut = 0x7A86
			if i == 5:
				clut = 0x7A46
			MenuDraw.sprite(canvas, i * 0xF - 0x8A, bob - 0x78, 0xC, 0xC, i * 0xC + 0x30, 0xC, clut)
	if condition & POOPY:
		MenuDraw.sprite(canvas, -0x30, bob - 0x78, 0xC, 0xC, 0x60, 0x48, 0x7A06)
