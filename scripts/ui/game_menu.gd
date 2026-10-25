class_name GameMenu
extends Node
## The △ menu (game_menu.c; specs/game_menu.md): the menu object (tickTriangleMenu), box 0's tick
## (tickGameMenu) and render function (renderGameMenu), the options (handleGameMenuSelection).
## The root of scenes/ui/game_menu.tscn, opened and ticked by the field's MenuHost.
##
## Sprites come from ETCDAT/FI_INFO.TIM (asset porter etctim/04_fi_info, p<n> = palette row 496 + n):
## page (896, 256), so a sprite's (u, v) is image pixel (u, v - 192). Screen coordinates are
## relative to the centre (160, 120).

## Player was chosen: its screen comes with step 5e-3b.
signal unported(what: String)
## Digimon: box 0 is closed, the Digimon screen opens (tickTriangleMenu state 3).
signal open_digimon_screen
## Items was chosen (drawInventoryText), then box 0 is closed: the inventory opens (addInventoryUI).
signal items_chosen
signal open_inventory
## The menu closed (△ or an option that gives the field back).
signal closed

const TEXTURE := "etctim/04_fi_info.p%d.png"
const CENTRE := Vector2(160, 120)
const V_BASE := 192
## MENU_OPTIONS[1..7] (game_menu.c:463): x, y, palette (clutY), width, height, u, v.
const OPTIONS := [
	[], [0x14, 0x47, 12, 20, 20, 0x00, 0x00], [0x38, 0x47, 13, 20, 20, 0x28, 0x00],
	[0x5B, 0x47, 12, 20, 20, 0x00, 0x14], [0x14, 0x6F, 13, 20, 20, 0x28, 0x14],
	[0x38, 0x6F, 13, 20, 20, 0x00, 0x28], [0x5B, 0x6F, 13, 20, 20, 0x28, 0x28],
	[0x14, 0x1F, 13, 20, 19, 0x50, 0x00],
]
## GAME_MENU_TEXT_SPRITES[1..7] (US): x, y, width, height, u, v (drawn from v - 1).
const LABELS := [
	[], [0x13, 0x60, 0x18, 7, 0x50, 0x14], [0x35, 0x60, 0x1C, 7, 0x50, 0x1B], [0x5A, 0x60, 0x1C, 7, 0x50, 0x22],
	[0x15, 0x88, 0x14, 7, 0x6C, 0x14], [0x39, 0x88, 0x14, 7, 0x6C, 0x1B], [0x60, 0x88, 0x14, 7, 0x6C, 0x22],
	[0x17, 0x38, 0x10, 7, 0x50, 0x29],
]
## The selection frame (renderTriangleCursor, game_menu.c:1582; specs/game_menu.md §2.7): x, y,
## width, height of each piece from the cursor's base, the art's (u, v) (4 x 4 texels, the edges'
## band 4 x 3) and whether it is mirrored in u / v. The art in rows v 0xFC-0xFF: the rounded corner
## at u 0-3, the edge band at 4-7, the side bar at 8-11. SELECTION_CURSOR_* (game_menu.c:389) place
## the same 8 pieces in a 29 x 26 frame, but taken literally (the PSX's polygon sampling, the
## sides from the top) they leave gaps and show the sides under the corners; these are the pieces
## as the art fits together, in the same bounds. Drawn in this order: edges and sides, then the
## corners over them (the reverse of the C's AddPrims, which the ordering table draws last first).
const CURSOR_PIECES := [
	[4, 0, 21, 3, 4, 0xFC, false, false],
	[4, 23, 21, 3, 4, 0xFC, false, true],
	[0, 4, 4, 18, 8, 0xFC, false, false],
	[25, 4, 4, 18, 8, 0xFC, true, false],
	[0, 0, 4, 4, 0, 0xFC, false, false],
	[25, 0, 4, 4, 0, 0xFC, true, false],
	[0, 22, 4, 4, 0, 0xFC, false, true],
	[25, 22, 4, 4, 0, 0xFC, true, true],
]
## GAME_MENU_LINES (the first 2) and their UI_LINES_BORDER_COLOR.
const LINES := [[-62, -59, 62, -59, Color8(2, 2, 2)], [-63, -58, 63, -58, Color8(0x90, 0xD9, 0xFA)]]
## The options (handleGameMenuSelection).
const ITEMS := 1
const DIGIMON := 2
const PLAYER := 3
const PRAISE := 4
const SCOLD := 5
const SLEEP := 6
const FISHING := 7
## MENU_TEXT_AREA (US) and where STR_YEAR_DAY is drawn.
const YEAR_DAY_AREA := Rect2i(0, 232, 24, 12)
const YEAR_DAY_V := 0xE8
## renderRectPolyFT4's disabled colour (0x32 instead of 0x80).
const DISABLED := Color(0x32 / 128.0, 0x32 / 128.0, 0x32 / 128.0)
## TRIANGLE_MENU_STATE: -1 open (the box's tick runs the menu).
const STATE_OPEN := -1
const STATE_OPENING := 0
const STATE_REMOVE := 1
## Items: box 0 closes, then the inventory (specs/inventory.md §2.1).
const STATE_ITEMS := 2
## Digimon: box 0 closes, then the Digimon screen; back: box 1 closes, the menu opens again
## (specs/status_screens.md §2).
const STATE_DIGIMON := 3
const STATE_DIGIMON_BACK := 4

## Set by the host.
var boxes: UIBoxes
var text_area: TextArea
var tamer: Tamer
var partner: Partner
var care: Care
var clock: Clock
var pad: Pad
var sound: Node
var game_state: Node
var data: Node
## getFishingAvailability (fish.c:59): 0 none, 1 a rod but no food or no rod upgrade, 2 ready.
## Fishing isn't ported: always 0 (the fishing row isn't shown).
var fishing_availability := Callable()

## IS_IN_MENU.
var is_open := false
## The menu object exists (addObject 0xFA4 until removeObject).
var active := false
## TRIANGLE_MENU_STATE, MENU_OPTIONS[0].unknown (the selection), MENU_OPTION_COUNT.
var menu_state := STATE_OPENING
var selection := ITEMS
var count := 7
## MENU_OPTIONS[n].disabled for Fishing (Sleep's is Care.sleep_enabled, setSleepDisabled).
var fishing_disabled := false

var _textures := {}


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")
	if sound == null:
		sound = get_node_or_null("/root/Sound")


## addGameMenu (game_menu.c:1306) and the rest of tamerTickWalkingState's △ (tamer.c:529-537):
## IS_IN_MENU, stopGameTime, setPartnerIdling.
func open() -> void:
	add_game_menu()
	is_open = true
	if clock != null:
		clock.running = false
	if partner != null:
		partner.start_animation(Partner.ANIM_IDLE)


## addGameMenu (game_menu.c:1306): the options and the menu object, from Items (or Fishing).
func add_game_menu() -> void:
	selection = ITEMS
	count = 7
	fishing_disabled = false
	var fishing: int = fishing_availability.call() if fishing_availability.is_valid() else 0
	if fishing != 0:
		count += 1
		fishing_disabled = fishing == 1
		selection = FISHING
	if care != null:
		care.sleep_enabled = _sleepy()
	menu_state = STATE_OPENING
	active = true


## Back from the inventory (tickInventoryUI action 2): closeTriangleMenu, addGameMenu; IS_IN_MENU
## and the stopped time stay.
func reopen() -> void:
	close()
	add_game_menu()


## The Digimon screen's △ (TRIANGLE_MENU_STATE = 4).
func digimon_screen_back() -> void:
	menu_state = STATE_DIGIMON_BACK


## startFeedingItem's menu part (game_menu.c:2228): the menu object goes, IS_IN_MENU = 0, game time
## runs (the inventory has closed its boxes).
func hand_over() -> void:
	active = false
	_resume()


## The menu can open: box 0 free (state != 1, frame 0); the script and fade tests are the host's.
func box_free() -> bool:
	var b: UIBoxes.Box = boxes.boxes[0]
	return b.state != UIBoxes.STATE_OPEN and b.frame == 0


## tickTriangleMenu (game_menu.c:1328), with the objects. Only the states this step reaches.
func tick() -> void:
	if not active:
		return
	match menu_state:
		STATE_OPENING:
			_create_menu_box(0, -0x42, -0x50, 0x84, 0x95 if count == 8 else 0x6E)
			if boxes.boxes[0].frame == 4:
				menu_state = STATE_OPEN
			if text_area != null:
				text_area.clear(YEAR_DAY_AREA)
				text_area.draw_string(_year_day(), 0, YEAR_DAY_V)
		STATE_ITEMS:
			_close_box_if_open(0)
			if boxes.boxes[0].frame == 0:
				open_inventory.emit()
				menu_state = STATE_OPEN
		STATE_DIGIMON:
			_close_box_if_open(0)
			if boxes.boxes[0].frame == 0:
				open_digimon_screen.emit()
				menu_state = STATE_OPEN
		STATE_DIGIMON_BACK:
			if tamer != null:
				tamer.visible = true
			if partner != null:
				partner.visible = true
			_close_box_if_open(1)
			if boxes.boxes[1].frame == 0:
				menu_state = STATE_OPENING
		STATE_REMOVE:
			_close_box_if_open(0)
			active = false


## tickGameMenu (game_menu.c:1627): box 0's tick.
func tick_box(_id: int) -> void:
	if care != null and _sleepy():
		care.sleep_enabled = true
	var sel := selection
	var pressed := pad.polled & ~pad.polled_previous
	if pressed & Pad.UP:
		sel -= 3
		if sel <= 0:
			sel += ((count + 1) / 3) * 3
		if sel >= count:
			sel -= 3
	elif pressed & Pad.DOWN:
		sel += 3
		if sel >= count:
			sel -= ((count + 1) / 3) * 3
		if sel <= 0:
			sel += 3
	elif pressed & Pad.LEFT:
		sel -= 1
		if sel <= 0:
			sel = count - 1
	elif pressed & Pad.RIGHT:
		sel += 1
		if sel >= count:
			sel = 1
	if sel != selection:
		selection = sel
		_play_sound(2)
	if menu_state != STATE_OPEN:
		return
	if pad.is_key_down(Pad.CONFIRM):
		_play_sound(4 if is_disabled(selection) else 3)
		choose(selection)
	var b: UIBoxes.Box = boxes.boxes[0]
	if pad.is_key_down(Pad.CANCEL) and (b.state == UIBoxes.STATE_OPEN or b.frame == 0):
		_play_sound(4)
		close()
		if tamer != null:
			tamer.set_state(Tamer.STATE_FREE)
			tamer.camera_follow = true
		_resume()


## MENU_OPTIONS[n].disabled & 1: only Sleep and Fishing are ever disabled.
func is_disabled(entry: int) -> bool:
	if entry == SLEEP:
		return care == null or not care.sleep_enabled
	if entry == FISHING:
		return fishing_disabled
	return false


## handleGameMenuSelection (game_menu.c:2168).
func choose(entry: int) -> void:
	if is_disabled(entry):
		return
	match entry:
		ITEMS:
			menu_state = STATE_ITEMS
			items_chosen.emit()
		DIGIMON:
			menu_state = STATE_DIGIMON
		PLAYER:
			unported.emit("Player")
		PRAISE, SCOLD, SLEEP:
			close()
			if partner != null:
				var states := {PRAISE: Partner.STATE_PRAISE, SCOLD: Partner.STATE_SCOLD, SLEEP: Partner.STATE_SLEEP}
				partner.set_state(states[entry])
			_resume()


## closeTriangleMenu (game_menu.c:1403): box 1 and box 0 close, the object goes. (The inventory's
## boxes come with it, 5e-2.)
func close() -> void:
	_close_box_if_open(1)
	_close_box_if_open(0)
	active = false


## IS_IN_MENU = 0, startGameTime.
func _resume() -> void:
	is_open = false
	if clock != null:
		clock.running = true
	closed.emit()


## createMenuBox (game_menu.c:1684): an animated box grown from the tamer's screen position, unless
## open or still closing.
func _create_menu_box(id: int, x: int, y: int, w: int, h: int) -> void:
	var b: UIBoxes.Box = boxes.boxes[id]
	if b.state == UIBoxes.STATE_OPEN or b.frame != 0:
		return
	var start := tamer.screen_rect() if tamer != null else Rect2i(-5, -5, 10, 10)
	boxes.create_animated(id, 1, UIBoxes.FEATURE_HALF_FILL, Rect2i(x, y, w, h), start, tick_box, render)


## closeUIBoxIfOpen (game_menu.c:1411): an open box shrinks back to where it grew from.
func _close_box_if_open(id: int) -> void:
	var b: UIBoxes.Box = boxes.boxes[id]
	if b.frame >= 5 and b.state == UIBoxes.STATE_OPEN:
		boxes.remove_animated(id)


func _sleepy() -> bool:
	return game_state != null and int(game_state.state["partner"]["care"]["condition"]) & 1 != 0


func _year_day() -> String:
	return data.text("STR_YEAR_DAY") if data != null else "YearDay"


func _play_sound(value: int) -> void:
	if sound != null:
		sound.play_sound(0, value)


# --- renderGameMenu (game_menu.c:1424) -----------------------------------------------------------

## Box 0's render function.
func render(canvas: CanvasItem, _id: int) -> void:
	var y_offset := -0x28 if count == 7 else 0
	for line in LINES:
		canvas.draw_line(CENTRE + Vector2(line[0], line[1]) + Vector2(0.5, 0.5),
				CENTRE + Vector2(line[2], line[3]) + Vector2(1.5, 0.5), line[4])
	_render_date(canvas)
	_render_cursor(canvas, selection, y_offset)
	var blink := _playtime_frames() % 10 < 5
	for i in range(1, count):
		var o: Array = OPTIONS[i]
		var tint := DISABLED if is_disabled(i) else Color.WHITE
		var highlight := 0x14 if i == selection and blink else 0
		_sprite(canvas, o[2], o[0] - 0x42, o[1] - 0x50 + y_offset, o[3], o[4], o[5] + highlight, o[6], tint)
		var l: Array = LABELS[i]
		_sprite(canvas, 13, l[0] - 0x42, l[1] - 0x50 + y_offset, l[2], l[3], l[4], l[5] - 1, tint)
	if text_area != null:
		# US: "Year" and "Day" from the text area (game_menu.c:1474).
		text_area.render_string(canvas, 0, -0x3C, -0x49, 0x24, 0xC, 0, 0xE7)
		text_area.render_string(canvas, 0, 6, -0x49, 0x1C, 0xC, 0x24, 0xE7)


## renderDateDigits (US, game_menu.c:1540): DAY + 1 and YEAR + 1, no leading zeros.
func _render_date(canvas: CanvasItem) -> void:
	if game_state == null:
		return
	var clock_state: Dictionary = game_state.state["clock"]
	var day := date_digits(int(clock_state["day"]) + 1, 2)
	for j in day.size():
		_digit(canvas, day[j], 0x25 + j * 9)
	var year := date_digits(int(clock_state["year"]) + 1, 3)
	for j in year.size():
		_digit(canvas, year[j], -0x16 + j * 9)


## convertValueToDigits: `value` zero-padded to n digits, the leading zeros left out (at least one
## digit), most significant first.
static func date_digits(value: int, n: int) -> Array:
	var text := ("%0" + str(n) + "d") % value
	text = text.substr(text.length() - n)
	var first := 0
	while first < n - 1 and text[first] == "0":
		first += 1
	var out := []
	for k in range(first, n):
		out.append(int(text[k]))
	return out


## A digit's sprite (renderDateDigits): its (u, v) in the page.
static func digit_uv(d: int) -> Vector2i:
	if d == 0:
		return Vector2i(0x78, 0x34)
	if d < 5:
		return Vector2i((d - 1) * 8 + 0x60, 0x28)
	return Vector2i((d - 5) * 8 + 0x50, 0x34)


func _digit(canvas: CanvasItem, d: int, x: int) -> void:
	var uv := digit_uv(d)
	_sprite(canvas, 12, x, -0x4A, 7, 12, uv.x + 1, uv.y, Color.WHITE)


## renderTriangleCursor (game_menu.c:1582): the frame around the selected icon (CURSOR_PIECES).
func _render_cursor(canvas: CanvasItem, sel: int, y_offset: int) -> void:
	var tex := _texture(12)
	if tex == null:
		return
	var base := CENTRE + Vector2(OPTIONS[sel][0] - 0x46, OPTIONS[sel][1] - 0x53 + y_offset)
	for piece in CURSOR_PIECES:
		var rows := 3 if piece[3] == 3 else 4
		var pos: Vector2 = base + Vector2(piece[0], piece[1])
		var size := Vector2(piece[2], piece[3])
		var src := Rect2(piece[4], piece[5] - V_BASE, 4, rows)
		# A mirrored piece: the source rect's opposite corners (draw_polygon's UVs follow the points).
		var left: float = src.end.x if piece[6] else src.position.x
		var right: float = src.position.x if piece[6] else src.end.x
		var top: float = src.end.y if piece[7] else src.position.y
		var bottom: float = src.position.y if piece[7] else src.end.y
		var t := tex.get_size()
		var points := PackedVector2Array([pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y)])
		var uvs := PackedVector2Array([Vector2(left, top) / t, Vector2(right, top) / t, Vector2(right, bottom) / t,
				Vector2(left, bottom) / t])
		canvas.draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, tex)


## renderRectPolyFT4 of a page sprite at (x, y): (u, v) of the page, palette p<palette>.
func _sprite(canvas: CanvasItem, palette: int, x: int, y: int, w: int, h: int, u: int, v: int, tint: Color) -> void:
	var tex := _texture(palette)
	if tex != null:
		canvas.draw_texture_rect_region(tex, Rect2(CENTRE + Vector2(x, y), Vector2(w, h)), Rect2(u, v, w, h), tint)


func _texture(palette: int) -> Texture2D:
	if not _textures.has(palette):
		_textures[palette] = Content.load_texture(TEXTURE % palette)
	return _textures[palette]


## PLAYTIME_FRAMES (the selection blinks with it).
func _playtime_frames() -> int:
	return int(game_state.state["clock"]["playtime"]["frames"]) if game_state != null else 0
