class_name PlayerCardsTab
extends Node
## The Player screen's card list (renderCardsView, game_menu.c:3750, the cursor in tickPlayerMenu
## :2072, renderCardImage / renderCardCount :2387; specs/status_screens.md §4.4): the 66 cards in
## 6 rows of 11, an icon for each card owned; ✕ on one opens its picture (box 2) and count (box 3).

## CARD_VIEW_TEXT_AREA.
const TEXT_AREA := Rect2i(0, 12, 256, 200)
const COLUMNS := 11
const ROWS := 6
## CARD_SPRITE_CLUT (game_menu.c:445): each card icon's palette, row 488 + n on SBOY.
const ICON_PALETTES := [0, 0, 4, 1, 0, 3, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1, 1, 4, 4, 3, 3, 4, 3, 6, 1, 3, 1,
		0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 1, 2, 0, 0, 0, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 3, 1, 1, 1, 0,
		0, 0]
## The cursor on SBOY (u 0, v 0xE8, palette row 503).
const CURSOR_ROW := 503
## The footer (US): colour, x, width, u (row 0x0C, y 0x53).
const FOOTER := [[PlayerScreen.FOOTER_GLYPH1, -0x23, 0x0C, 0x48], [0, -0x17, 0x3C, 0x54],
		[PlayerScreen.FOOTER_GLYPH2, 0x2B, 0x0C, 0x90], [0, 0x37, 0x3C, 0x9C]]
## The picture (box 2, CARD/CARD.ALL entry `selected`, asset porter card_all/card_NN) and the
## count (box 3).
const PICTURE_BOX := 2
const COUNT_BOX := 3
const PICTURE_RECT := Rect2i(-0x4B, -0x53, 0x96, 0xB4)
const COUNT_RECT := Rect2i(0x4A, 0x45, 0x36, 0x18)
const PICTURE := "card_all/card_%02d.png"

var screen: PlayerScreen
## SELECTED_CARD.
var selected := 0
var _picture: Texture2D


## drawCardViewStrings (game_menu.c:4240). True when done.
func draw_strings() -> bool:
	var area := screen.text_area
	if screen.sub_state == 0:
		area.clear(TEXT_AREA)
		MenuDraw.draw_digits(area)
		screen.sub_state = 1
		return false
	area.draw_string(screen.data.text(PlayerScreen.CARD_CHART_LABELS[0]), 0, 0xC)
	selected = 0
	return true


func update() -> void:
	if screen.menu_state == 0 and draw_strings():
		screen.menu_state = 1


func leave() -> void:
	pass


## Where box 2 and 3 grow from and shrink to: the card's cell.
func _cell_rect() -> Rect2i:
	return Rect2i((selected % COLUMNS) * 0x18 - 0x79, (selected / COLUMNS) * 0x18 - 0x36, 1, 1)


## tickPlayerMenu, PLAYER_MENU_STATE 3 (MENU_STATE 2 and 3).
func tick() -> void:
	var pad := screen.pad
	var previous := selected
	if screen.menu_state == 2:
		if pad.is_key_down(Pad.CONFIRM) and screen.card_amount(selected) != 0:
			screen.play_sound(3)
			screen.menu_state = 3
			_picture = Content.load_texture(PICTURE % selected)
			screen.boxes.create_animated(PICTURE_BOX, 1, 0, PICTURE_RECT, _cell_rect(), Callable(), draw_picture)
			screen.boxes.create_animated(COUNT_BOX, 1, 0, COUNT_RECT, _cell_rect(), Callable(), draw_count)
		if screen.menu_state == 2:
			if pad.is_changed(Pad.LEFT) and selected % COLUMNS != 0:
				selected -= 1
			if pad.is_changed(Pad.RIGHT) and selected % COLUMNS != COLUMNS - 1:
				selected += 1
			if pad.is_changed(Pad.UP) and selected >= COLUMNS:
				selected -= COLUMNS
			if pad.is_changed(Pad.DOWN) and selected < COLUMNS * (ROWS - 1):
				selected += COLUMNS
			if previous != selected:
				screen.play_sound(2)
	if pad.is_key_down(Pad.CANCEL) and screen.menu_state == 3:
		screen.play_sound(4)
		screen.menu_state = 2
		screen.boxes.remove_animated(PICTURE_BOX, _cell_rect())
		screen.boxes.remove_animated(COUNT_BOX, _cell_rect())


## renderCardImage: the picture, 0x96 x 0xB4.
func draw_picture(canvas: CanvasItem, _id: int) -> void:
	if _picture != null:
		canvas.draw_texture_rect(_picture, Rect2(MenuDraw.CENTRE + Vector2(-0x4B, -0x54), Vector2(0x96, 0xB4)), false)


## renderCardCount (US): the count (one digit), then a cell of the footer's row.
func draw_count(canvas: CanvasItem, _id: int) -> void:
	var area := screen.text_area
	area.render_string(canvas, 0, 0x6B, 0x4C, 0xC, 0xC, 0xD8, 0xC)
	MenuDraw.number(canvas, area, 0, 0x59, 0x4B, 1, screen.card_amount(selected))


## renderCardsView in reverse of its adds: footer, title, frames and icons, the cursor last.
func draw(canvas: CanvasItem) -> void:
	if screen.menu_state == 0:
		return
	var area := screen.text_area
	for k in range(FOOTER.size() - 1, -1, -1):
		var f: Array = FOOTER[k]
		area.render_string(canvas, f[0], f[1], 0x53, f[2], 0xC, f[3], 0xC, true)
	area.render_string(canvas, 3, -0x24, -0x50, 0x48, 0xC, 0, 0xC, true)
	for i in range(ROWS - 1, -1, -1):
		for j in range(COLUMNS - 1, -1, -1):
			var card := j + i * COLUMNS
			MenuDraw.border_box(canvas, j * 24 + 0x1E, i * 24 + 0x39, 0x12, 0x12, 0xBEBEBE, 0x3C3C3C, 0x69, 0x69, 0x69)
			if screen.card_amount(card) > 0:
				MenuDraw.sboy_sprite(canvas, j * 24 - 0x81, i * 24 - 0x3E, 0x10, 0x10, (card % 8) * 32, (card / 8) * 16,
						488 + ICON_PALETTES[card])
	if screen.menu_state >= 2:
		MenuDraw.sboy_sprite(canvas, (selected % COLUMNS) * 24 - 0x84, (selected / COLUMNS) * 24 - 0x40, 0x18, 0x14,
				0, 0xE8, CURSOR_ROW)
