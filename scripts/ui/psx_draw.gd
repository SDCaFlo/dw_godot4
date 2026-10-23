class_name PsxDraw
## PSX 2D primitives for HUD windows, in the original's screen coordinates (relative to the
## centre (160, 120), like the clock and the UI boxes). Any CanvasItem draws through these, so new
## windows (menus, shops) draw like the original's.

const CENTRE := Vector2(160, 120)


## A colour word as drawLine2P / drawLine3P write it (line.c:51): the low byte is red, so 0xFAD990
## is (0x90, 0xD9, 0xFA).
static func word_color(word: int, alpha := 1.0) -> Color:
	return Color8(word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF, roundi(alpha * 255))


## drawLine2P (line.c:44): a flat line, both end points included. The UI only draws horizontal
## and vertical lines; others fall back to Godot's line.
static func line2(canvas: CanvasItem, word: int, x0: int, y0: int, x1: int, y1: int) -> void:
	var color := word_color(word)
	if y0 == y1 or x0 == x1:
		var r := Rect2(mini(x0, x1), mini(y0, y1), absi(x1 - x0) + 1, absi(y1 - y0) + 1)
		canvas.draw_rect(Rect2(CENTRE + r.position, r.size), color)
	else:
		canvas.draw_line(CENTRE + Vector2(x0, y0) + Vector2(0.5, 0.5), CENTRE + Vector2(x1, y1) + Vector2(0.5, 0.5), color)


## drawLine3P (line.c:26): two connected segments.
static func line3(canvas: CanvasItem, word: int, x0: int, y0: int, x1: int, y1: int, x2: int, y2: int) -> void:
	line2(canvas, word, x0, y0, x1, y1)
	line2(canvas, word, x1, y1, x2, y2)


## GsSortBoxFill / POLY_F4: a flat rectangle; `half` = semi-transparency mode 0 (attribute
## 0x40000000: half the screen plus half the colour).
static func box(canvas: CanvasItem, rect: Rect2i, rgb: Color, half := false) -> void:
	var c := rgb
	c.a = 0.5 if half else 1.0
	canvas.draw_rect(Rect2(CENTRE + Vector2(rect.position), Vector2(rect.size)), c)


## renderSelectionCursor (utils2.c:232): the highlight of a menu row. The C adds a light top-left
## line, a dark bottom-right line and a half-transparent grey fill; the ordering table draws them
## in reverse: fill, dark, light.
static func selection_cursor(canvas: CanvasItem, x: int, y: int, w: int, h: int) -> void:
	box(canvas, Rect2i(x + 1, y + 1, w - 1, h - 1), Color8(0x80, 0x80, 0x80), true)
	line3(canvas, 0x121212, x + w, y, x + w, y + h, x, y + h)
	line3(canvas, 0xB0B0B0, x, y + h - 1, x, y, x + w - 1, y)


## A POLY_FT4 sprite of a palette page at screen (x, y): `uv` in the image (v already minus the
## page origin). A semi-transparent sprite is drawn twice: its opaque texels (`stp` false) on a
## normal canvas, its STP texels (`stp` true) on a canvas with the blend mode, e.g. UIBoxes'
## additive layer for mode 1.
static func sprite(canvas: CanvasItem, texture: PsxTexture, uv: Rect2, x: int, y: int, stp := false) -> void:
	var dst := Rect2(CENTRE + Vector2(x, y), uv.size)
	if stp:
		canvas.draw_texture_rect_region(texture.stp, dst, uv)
	else:
		canvas.draw_texture_rect_region(texture.base, dst, uv)
