class_name TextArea
extends RefCounted
## The text area (font.c:1503-1763; specs/text.md §2.2-2.3): 256 x 256 4-bit pixels at VRAM
## (704, 256) that strings are drawn into, shown on screen in rectangles by renderString.
##
## One area is shared by everything that shows text, as in the original: field.gd makes it and
## hands it to its users, who own rows of it as the original does (the message box rows 120-155,
## the dialogue box rows 0-95).

const SIZE := 256
## TEXT_DRAW_LIMIT: drawGlyph draws nothing at x or y >= 256 - 12.
const DRAW_LIMIT := SIZE - PsxFont.CELL_WIDTH
const CENTRE := Vector2(160, 120)

var font: PsxFont
## The colour index of each pixel (0 = transparent), row by row.
var pixels := PackedByteArray()
## COLORCODE_LOWBITS: the index setTextColor gives ink pixels.
var text_color := 1

## FONT_CLUT as RGBA (index 0 and the unused 0x0000 entries transparent).
var _palette: Array[Color] = []
## TEXT_COLORS of the language's release as tints (rgb / 0x80).
var _tints: Array[Color] = []
var _image: Image
var _texture: ImageTexture
## Rows changed since the texture was last built.
var _dirty_from := 0
var _dirty_to := SIZE


func _init(data: Node, lang := "en_us") -> void:
	pixels.resize(SIZE * SIZE)
	for c in data.font_clut():
		var rgb: Array = c["rgb8"]
		_palette.append(Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]), 0 if c["transparent"] else 255))
	_image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	set_language(data, lang)


## The font and TEXT_COLORS of a language's release. What is already drawn stays.
func set_language(data: Node, lang: String) -> void:
	font = PsxFont.new(data, lang)
	_tints.clear()
	var release: String = PsxFont.RELEASES.get(lang, "us")
	for t in data.text_colors():
		if release in t["releases"]:
			var tint: Array = t["tint"]
			_tints.append(Color(float(tint[0]), float(tint[1]), float(tint[2])))


## clearTextArea (font.c:1518).
func clear_all() -> void:
	clear(Rect2i(0, 0, SIZE, SIZE))


## clearTextSubArea (font.c:1526): VRAM holds 4 pixels per 16-bit word, so x and the width are cut
## to multiples of 4 (x / 4, w >> 2).
func clear(rect: Rect2i) -> void:
	var x0 := (rect.position.x / 4) * 4
	var w := (rect.size.x >> 2) * 4
	var y0 := maxi(rect.position.y, 0)
	var y1 := mini(rect.position.y + rect.size.y, SIZE)
	for y in range(y0, y1):
		for x in range(maxi(x0, 0), mini(x0 + w, SIZE)):
			pixels[y * SIZE + x] = 0
	_mark(y0, y1)


## setTextColor (font.c:1537).
func set_text_color(color: int) -> void:
	text_color = color & 0xF


## drawGlyph (font.c:1544) with the code as it reads (high byte first, e.g. 0x8260 = Ａ; the C
## byte-swaps the string's bytes into this). Writes the whole 12 x 11 cell: ink pixels get the text
## colour, the others 0. Returns what the C returns (PsxFont.advance; 0 when clipped).
## Quirk kept: LoadImage places the cell at x / 4 in 16-bit VRAM words, so a glyph lands on the
## multiple of 4 at or left of x.
func draw_glyph(code: int, x: int, y: int) -> int:
	if x < 0 or x >= DRAW_LIMIT or y < 0 or y >= DRAW_LIMIT:
		return 0
	# The JP / EU drawGlyph returns before the search for the full-width space.
	if font.language != "en_us" and code == PsxFont.SPACE:
		return font.advance(code)
	var rows: Array = font.glyph(code).get("rows", [])
	var cell_x := (x / 4) * 4
	for row in PsxFont.GLYPH_HEIGHT:
		for col in PsxFont.CELL_WIDTH:
			pixels[(y + row) * SIZE + cell_x + col] = text_color if PsxFont.is_ink(rows, col, row) else 0
	_mark(y, y + PsxFont.GLYPH_HEIGHT)
	return font.advance(code)


## drawString (font.c:1709 / 1728): the string's codes one after the other, x advanced by each
## glyph's width (JP: GLYPH_WIDTH). Returns the x after the last glyph.
func draw_string(text: String, x: int, y: int) -> int:
	return draw_codes(font.encode(text), x, y)


func draw_codes(codes: PackedInt32Array, x: int, y: int) -> int:
	for code in codes:
		var w := draw_glyph(code, x & 0xFFFF, y)
		x += font.glyph_width if font.language == "ja" else w
	return x


## The colour index of one pixel (tests, debug).
func pixel(x: int, y: int) -> int:
	return pixels[y * SIZE + x]


## The area as a texture (font palette applied; index 0 transparent), rebuilt when it changed.
func texture() -> ImageTexture:
	if _dirty_from < _dirty_to:
		for y in range(_dirty_from, _dirty_to):
			for x in SIZE:
				var index := pixels[y * SIZE + x]
				_image.set_pixel(x, y, _palette[index] if index < _palette.size() else Color(0, 0, 0, 0))
		if _texture == null:
			_texture = ImageTexture.create_from_image(_image)
		else:
			_texture.update(_image)
		_dirty_from = SIZE
		_dirty_to = 0
	return _texture


func _mark(y0: int, y1: int) -> void:
	_dirty_from = mini(_dirty_from, y0)
	_dirty_to = maxi(_dirty_to, y1)


## TEXT_COLORS[color] as a modulate colour (0x80 = 1.0; brighter tints go above 1 like the PSX's
## texel * colour / 128).
func tint(color: int) -> Color:
	return _tints[color] if color >= 0 and color < _tints.size() else Color.WHITE


## renderString (utils2.c:247): the text-area rectangle (u, v, w, h) at screen (x, y), relative to
## the screen centre, tinted by TEXT_COLORS[color]; with `shadow` a black copy 1 px down-right is
## drawn behind it (it goes into the ordering table after the text).
func render_string(canvas: CanvasItem, color: int, x: int, y: int, w: int, h: int, u: int, v: int, shadow := false) -> void:
	var tex := texture()
	var src := Rect2(u & 0xFF, v & 0xFF, w, h)
	if shadow:
		canvas.draw_texture_rect_region(tex, Rect2(CENTRE + Vector2(x + 1, y + 1), Vector2(w, h)), src, Color.BLACK)
	canvas.draw_texture_rect_region(tex, Rect2(CENTRE + Vector2(x, y), Vector2(w, h)), src, tint(color))
