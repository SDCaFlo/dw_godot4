class_name MenuDraw
extends RefCounted
## The game menu's drawing helpers (game_menu.c:2960, :3801-3857, :4262-4324; utils.c:214), for the
## screens drawn on the UI boxes (specs/status_screens.md). Screen coordinates are relative to the
## centre (160, 120) unless a helper says it takes the PSX's absolute ones.
##
## renderRectPolyFT4's texture pages, as the asset porter's images: page 5 (VRAM (320, 0)) with
## v = texY + 0x80 is ETCDAT/SYSTEM_W.TIM (etctim/08_system_w, rows from VRAM 128: image row =
## texY); page 0x18 (VRAM (512, 256)) is ETCDAT/SBOY.TIM (etctim/05_sboy, image row = v). A palette
## word (GetClut) is row (word >> 6), x (word & 0x3F) * 16: SYSTEM_W's palettes are rows 488 + n at
## x 96, SBOY's rows 488 + n at x 112.

const CENTRE := Vector2(160, 120)
## A palette's image: palette 0 has no suffix (the asset porter's `<name>.png`).
const SYSTEM_W := "etctim/08_system_w%s.png"
const SBOY := "etctim/05_sboy%s.png"
## UI_LINES_BORDER_COLOR (game_menu.c:495).
const LINE_COLORS := [0x020202, 0xFAD990, 0xC59F4A, 0x6996B4]
## renderRectPolyFT4's dimmed colour (flag 1): 0x32 instead of 0x80.
const DIMMED := Color(0x32 / 128.0, 0x32 / 128.0, 0x32 / 128.0)
## ITEM.TIM icons (renderItemSprite / setItemTexture): 16 x 16 cells, palette `icon_clut`.
const ITEM_ICONS := "tim_files/ETCDAT/ITEM%s.png"
## renderNumber's digits: drawn into the text area at row 0xF0, DIGIT_WIDTH 8 apart (US).
const DIGIT_ROW := 0xF0
const DIGIT_WIDTH := 8

static var _textures := {}


## A texture page's palette as an image ("system_w" / "sboy").
static func texture(page: String, palette: int) -> Texture2D:
	var key := "%s %d" % [page, palette]
	if not _textures.has(key):
		var suffix := "" if palette == 0 else ".p%d" % palette
		_textures[key] = Content.load_texture((SYSTEM_W if page == "system_w" else SBOY) % suffix)
	return _textures[key]


## renderItemSprite (utils2.c:269): an item's 16 x 16 icon (15 texels on the last row / column).
static func item_icon(canvas: CanvasItem, record: Dictionary, x: int, y: int) -> void:
	var clut := int(record.get("icon_clut", 0))
	var key := "item %d" % clut
	if not _textures.has(key):
		_textures[key] = Content.load_texture(ITEM_ICONS % ("" if clut == 0 else ".p%d" % clut))
	var tex: Texture2D = _textures[key]
	if tex == null:
		return
	var id := int(record.get("id", 0))
	var u := (id % 16) * 16
	var v := (id / 16) * 16
	var w := 15 if u == 0xF0 else 16
	var h := 15 if v == 0xF0 else 16
	canvas.draw_texture_rect_region(tex, Rect2(CENTRE + Vector2(x, y), Vector2(w, h)), Rect2(u, v, w, h))


## The palette index of a CLUT word on SYSTEM_W (rows 488 + n at x 96).
static func system_w_palette(clut: int) -> int:
	return (clut >> 6) - 488


## renderRectPolyFT4 on SYSTEM_W (page 5): `tex_v` is the C's texY (the image row). Flag 1 dims it;
## a sprite reaching u or v 0x100 loses its last texel, as the C does.
static func sprite(canvas: CanvasItem, x: int, y: int, w: int, h: int, u: int, tex_v: int, clut: int, flags := 0) -> void:
	_sprite(canvas, texture("system_w", system_w_palette(clut)), x, y, w, h, u, tex_v + 0x80, tex_v, flags)


## renderRectPolyFT4 on SBOY (page 0x18), palette row `row` (GetClut(0x70, row)).
static func sboy_sprite(canvas: CanvasItem, x: int, y: int, w: int, h: int, u: int, v: int, row: int, flags := 0) -> void:
	_sprite(canvas, texture("sboy", row - 488), x, y, w, h, u, v, v, flags)


static func _sprite(canvas: CanvasItem, tex: Texture2D, x: int, y: int, w: int, h: int, u: int, v_page: int,
		v_image: int, flags: int) -> void:
	if tex == null or w <= 0 or h <= 0:
		return
	if v_page + h >= 0x100:
		h -= 1
	if u + w >= 0x100:
		w -= 1
	var tint := DIMMED if flags & 1 else Color.WHITE
	canvas.draw_texture_rect_region(tex, Rect2(CENTRE + Vector2(x, y), Vector2(w, h)), Rect2(u, v_image, w, h), tint)
	if flags & 0x80:
		PsxDraw.line3(canvas, 0x020202, x - 1, y - 1, x + 0xD, y - 1, x + 0xD, y + 0xC)
		PsxDraw.line3(canvas, 0x020202, x - 1, y - 1, x - 1, y + 0xC, x + 0xD, y + 0xC)


## renderBox (game_menu.c:3810): a flat box. Flags: 1 semi-transparent (50 / 50), 1 | 2 subtracted
## (approximated as darkening by the colour's share: Godot's canvas has no subtract blend here),
## 0x80 a dark outline.
static func box(canvas: CanvasItem, x: int, y: int, w: int, h: int, r: int, g: int, b: int, flags := 0) -> void:
	if w > 0 and h > 0:
		var rect := Rect2(CENTRE + Vector2(x, y), Vector2(w, h))
		if flags & 1 and flags & 2:
			canvas.draw_rect(rect, Color(0, 0, 0, (r + g + b) / (3.0 * 255.0)))
		elif flags & 1:
			canvas.draw_rect(rect, Color8(r, g, b, 128))
		else:
			canvas.draw_rect(rect, Color8(r, g, b))
	if flags & 0x80:
		PsxDraw.line3(canvas, 0x020202, x - 1, y - 1, x + 0xD, y - 1, x + 0xD, y + 0xC)
		PsxDraw.line3(canvas, 0x020202, x - 1, y - 1, x - 1, y + 0xC, x + 0xD, y + 0xC)


## renderInsetBox (game_menu.c:3801): absolute PSX coordinates (0-320, 0-240).
static func inset_box(canvas: CanvasItem, x: int, y: int, w: int, h: int) -> void:
	x -= 0xA0
	y -= 0x78
	PsxDraw.line3(canvas, 0x020202, x, y + h, x, y, x + w, y)
	PsxDraw.line3(canvas, 0xA08769, x, y + h, x + w, y + h, x + w, y)
	box(canvas, x, y, w, h, 0x35, 0x4B, 0x5C)


## renderBorderBox (game_menu.c:3849): absolute PSX coordinates; c1 the top-left lines, c2 the others.
static func border_box(canvas: CanvasItem, x: int, y: int, w: int, h: int, c1: int, c2: int, r: int, g: int, b: int) -> void:
	x -= 0xA0
	y -= 0x78
	PsxDraw.line3(canvas, _word(c1), x, y + h, x, y, x + w, y)
	PsxDraw.line3(canvas, _word(c2), x, y + h, x + w, y + h, x + w, y)
	box(canvas, x, y, w, h, r, g, b)


## renderSeparatorLines: [x1, y1, x2, y2, colour index] each.
static func lines(canvas: CanvasItem, entries: Array) -> void:
	for l in entries:
		PsxDraw.line2(canvas, LINE_COLORS[l[4]], l[0], l[1], l[2], l[3])


## renderMenuTab (game_menu.c:2960): a tab over the box's top edge; `front` the current one.
static func menu_tab(canvas: CanvasItem, x: int, w: int, front: bool) -> void:
	var h := 0x10 if front else 0xF
	sprite(canvas, x, -0x68, 7, h, 0xD4, 0x8C - 0x80, 0x7B06)
	for i in (w - 0xE) / 4:
		sprite(canvas, x + 7 + i * 4, -0x68, 4, h, 0xE2, 0x8C - 0x80, 0x7B06)
	sprite(canvas, x + w - 9, -0x68, 7, h, 0xDB, 0x8C - 0x80, 0x7B06)


## renderNumber (utils.c:214): `value` in `n` digits without leading zeros, right-aligned, cut
## from the digits drawn at text-area row 0xF0. Quirk kept: the colour's blue is its green.
static func number(canvas: CanvasItem, text_area: TextArea, color: int, x: int, y: int, n: int, value: int) -> void:
	var digits := GameMenu.date_digits(maxi(value, 0), n)
	var tint := text_area.tint(color)
	tint.b = tint.g
	var tex := text_area.texture()
	var first := n - digits.size()
	for k in digits.size():
		var d: int = digits[k]
		canvas.draw_texture_rect_region(tex, Rect2(CENTRE + Vector2(x + (first + k) * DIGIT_WIDTH, y), Vector2(DIGIT_WIDTH, 12)),
				Rect2(d * DIGIT_WIDTH, DIGIT_ROW, DIGIT_WIDTH, 12), tint)


## The digits renderNumber reads (MAIN_D_80124C54, full-width "0123456789"), one per 8 pixels.
static func draw_digits(text_area: TextArea) -> void:
	text_area.clear(Rect2i(0, DIGIT_ROW, 0x50, 12))
	for d in 10:
		text_area.draw_string(str(d), d * DIGIT_WIDTH, DIGIT_ROW)


static func _word(rgb: int) -> int:
	# The C passes colours as 0xBBGGRR words already.
	return rgb
