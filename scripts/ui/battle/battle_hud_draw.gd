class_name BattleHudDraw
extends RefCounted
## The battle HUD's PSX primitives (specs/battle.md §4), in the original's screen coordinates
## (relative to the centre (160, 120)). The HUD draws from two texture pages:
## - (896, 256): BI_IN.TIM at VRAM (896, 384), so v 0x80-0xBF is image row v - 0x80; its
##   palettes are CLUT rows 480 + n at x 256 (asset porter etctim/00_bi_in, p<n>);
## - (960, 256): FEEL_EF.TIM at (960, 384) (v 0x80-0xBF) and BTLCOMND.TIM at (960, 448) (v 0xC0-0xFF,
##   image row v - 0xC0, palettes CLUT rows 496 + n at x 272; etctim/01_btlcomnd).
## A POLY_FT4's colour 0x80 is neutral; brighter values double up to 0xFF.

const CENTRE := Vector2(160, 120)
const BI_IN := "etctim/00_bi_in"
const BTLCOMND := "etctim/01_btlcomnd"
const FEEL_EF := "etctim/03_feel_ef"
## The CLUT rows the palettes of each image start at.
const BI_IN_CLUT := 480
const BTLCOMND_CLUT := 496
const FEEL_EF_CLUT := 480

static var _textures := {}
static var _tables := {}


## A table of the `battle_hud` record (systems/battle_hud: the HUD's C tables by name).
static func table(data: Node, name: String) -> Array:
	if not _tables.has(name) and data != null:
		for r in data.system("battle_hud"):
			_tables[r["name"]] = r["values"]
	return _tables.get(name, [])


## The PsxTexture of an image's palette (cached).
static func texture(image: String, palette: int) -> PsxTexture:
	var key := "%s %d" % [image, palette]
	if not _textures.has(key):
		_textures[key] = PsxTexture.load_palette(image, palette)
	return _textures[key]


## Page (896, 256) at CLUT row `clut_y`: BI_IN.
static func page_896(clut_y: int) -> PsxTexture:
	return texture(BI_IN, clut_y - BI_IN_CLUT)


## Page (960, 256) at CLUT row `clut_y`, for a v of BTLCOMND (>= 0xC0) or FEEL_EF.
static func page_960(clut_y: int, v: int) -> PsxTexture:
	if v >= 0xC0:
		return texture(BTLCOMND, clut_y - BTLCOMND_CLUT)
	return texture(FEEL_EF, clut_y - FEEL_EF_CLUT)


## A page v as an image row: BI_IN and FEEL_EF start at v 0x80, BTLCOMND at 0xC0.
static func row(v: int) -> int:
	return v - 0xC0 if v >= 0xC0 else v - 0x80


## A colour as setRGB0 gives it (0x80 = 1.0).
static func rgb(r: int, g: int, b: int, a := 1.0) -> Color:
	return Color(r / 128.0, g / 128.0, b / 128.0, a)


static func grey(level: int) -> Color:
	return rgb(level, level, level)


## A POLY_FT4: texture rect `uv` (image pixels; a negative width mirrors it) on the corners `pts`
## in the C's order (0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right). `semi`: the STP texels
## blend 50 / 50 (semi-transparency mode 0); else they draw opaque.
static func quad(canvas: CanvasItem, tex: PsxTexture, uv: Rect2, pts: Array, tint := Color.WHITE, semi := false) -> void:
	if tex == null or tex.base == null:
		return
	var size := tex.base.get_size()
	var u0 := uv.position.x / size.x
	var u1 := (uv.position.x + uv.size.x) / size.x
	var v0 := uv.position.y / size.y
	var v1 := (uv.position.y + uv.size.y) / size.y
	var points := PackedVector2Array([CENTRE + pts[0], CENTRE + pts[1], CENTRE + pts[3], CENTRE + pts[2]])
	var uvs := PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
	canvas.draw_primitive(points, PackedColorArray([tint, tint, tint, tint]), uvs, tex.base)
	if tex.stp != null:
		var t := tint
		if semi:
			t.a *= 0.5
		canvas.draw_primitive(points, PackedColorArray([t, t, t, t]), uvs, tex.stp)


## setUVWH + setXYWH: an axis-aligned POLY_FT4 (the drawn size may stretch the texels).
static func rect(canvas: CanvasItem, tex: PsxTexture, u: int, v_row: int, w: int, h: int, x: int, y: int,
		dw: int, dh: int, tint := Color.WHITE, semi := false) -> void:
	quad(canvas, tex, Rect2(u, v_row, w, h), [Vector2(x, y), Vector2(x + dw, y), Vector2(x, y + dh),
			Vector2(x + dw, y + dh)], tint, semi)


## GsSortSprite: `w` x `h` texels with their pivot (mx, my) at (x, y), scaled (4096 = 1) and
## rotated (`rotate` in 1/4096 degree, clockwise on screen).
static func sprite(canvas: CanvasItem, tex: PsxTexture, u: int, v_row: int, w: int, h: int, x: int, y: int,
		mx: int, my: int, scalex := 4096, scaley := 4096, rotate := 0, tint := Color.WHITE) -> void:
	var a := deg_to_rad(rotate / 4096.0)
	var sx := scalex / 4096.0
	var sy := scaley / 4096.0
	var pts := []
	for c in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
		var p := Vector2((c.x - mx) * sx, (c.y - my) * sy)
		pts.append(Vector2(x, y) + p.rotated(a))
	quad(canvas, tex, Rect2(u, v_row, w, h), pts, tint)


## convertValueToDigits: the digits of `value` in `n` places, most significant first, without the
## leading zeros (0 keeps one digit).
static func digits(value: int, n: int) -> Array[int]:
	var all: Array[int] = []
	var v := absi(value)
	for i in n:
		all.push_front(v % 10)
		v /= 10
	while all.size() > 1 and all[0] == 0:
		all.pop_front()
	return all


## drawEntityText (utils2.c:183): the numbers over the fighters, BI_IN palette 4, 8 x 8 digits at
## u = digit * 8, v 0xB7, 7 px apart, tinted TEXT_COLORS[color]. `n` = the digits drawn.
static func entity_text(canvas: CanvasItem, tint: Color, value: int, x: int, y: int) -> void:
	var d := digits(value, 4)
	var tex := page_896(484)
	for k in d.size():
		rect(canvas, tex, d[k] * 8, row(0xB7), 8, 8, x + k * 7, y, 8, 8, tint)


## drawEntityTextIcon (utils2.c:354): BI_IN palette 6, 8 x 8 at (u, 0xB8).
static func entity_text_icon(canvas: CanvasItem, u: int, x: int, y: int) -> void:
	rect(canvas, page_896(0x1E6), u, row(0xB8), 8, 8, x, y, 8, 8)


## BTL_renderNumber (battle_hud.c:858): `places` right-aligned 7 x 11 digits, BI_IN palette 12,
## u = digit * 7, v 172.
static func hud_number(canvas: CanvasItem, places: int, x: int, y: int, value: int) -> void:
	var d := digits(value, places)
	var tex := page_896(492)
	var first := places - d.size()
	for k in d.size():
		rect(canvas, tex, d[k] * 7, row(172), 7, 11, x + (first + k) * 7, y, 7, 11)
