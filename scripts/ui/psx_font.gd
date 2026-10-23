class_name PsxFont
extends RefCounted
## The game's own font for one language (font.c; data porter group `font`, data_porter/specs/font.md):
## the glyphs by Shift-JIS code, looked up like drawGlyph, and the codes a string turns into.
## specs/text.md §2.1, §3.

## The release whose font a language uses (data porter: each language's main release).
const RELEASES := {"en_us": "us", "ja": "jp_rev1", "en_eu": "eu"}
## GLYPH_WIDTH (include/dw/font.h:9-13): JP's drawString advance, and what the sickness message
## multiplies the name length by.
const GLYPH_WIDTHS := {"en_us": 12, "ja": 12, "en_eu": 8}
const SPACE := 0x8140
const CELL_WIDTH := 12
const GLYPH_HEIGHT := 11

var language := "en_us"
## GLYPH_DATA in table order: {code, rows, width, ...}.
var glyphs: Array = []
## GLYPH_WIDTH of the language.
var glyph_width := 12

## code -> glyph index (first entry with that code, like the C search).
var _index := {}
## Unicode character -> code, from the glyphs' `char`.
var _codes := {}
## ASCII 0x20-0x7E -> [convertAsciiToJis code, US drawString code].
var _ascii := {}


func _init(data: Node, lang := "en_us") -> void:
	language = lang
	glyph_width = GLYPH_WIDTHS.get(lang, 12)
	glyphs = data.font(lang)
	for i in glyphs.size():
		var g: Dictionary = glyphs[i]
		var code := int(g["code"])
		if not _index.has(code):
			_index[code] = i
		var ch = g.get("char")
		if ch is String and ch != "" and not _codes.has(ch):
			_codes[ch] = code
	for a in data.font_ascii():
		_ascii[int(a["ascii"])] = [int(a["code"]), int(a["draw_string_code"])]


## drawGlyph's search (font.c:1603-1609): the last entry is overwritten with the code first, so a
## code missing from the table finds the last glyph (× in US, a crossed box in JP / EU).
func glyph_index(code: int) -> int:
	return _index.get(code, glyphs.size() - 1)


func glyph(code: int) -> Dictionary:
	return glyphs[glyph_index(code)] if not glyphs.is_empty() else {}


## What drawGlyph returns: US the glyph's width; EU 8 for the space, else the glyph's width (the
## code-range rule, already in the data); JP nothing (0: drawString adds GLYPH_WIDTH).
func advance(code: int) -> int:
	if language == "ja":
		return 0
	if language == "en_eu" and code == SPACE:
		return 8
	return int(glyph(code).get("width", CELL_WIDTH))


## The codes drawString hands drawGlyph for a string. ASCII goes through convertAsciiToJis; US
## drawString also turns . into 0x8142 and ' into 0x8175 (`draw_string` true), drawString2 and the
## battle-end box don't (false). Other characters are the font's Shift-JIS codes; a character the
## font lacks gets 0, which draws the fallback glyph.
func encode(text: String, draw_string := true) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 0x80:
			var pair: Array = _ascii.get(c, [0, 0])
			out.append(pair[1] if draw_string and language == "en_us" else pair[0])
		else:
			out.append(_codes.get(text[i], 0))
	return out


## A code no table has: what a character without a Shift-JIS code is written as (it draws the
## fallback glyph, like any unknown code).
const NO_CODE := 0xFFFE


## The bytes a C string holds for `text` (strcpy into the text-box lines): ASCII stays one byte,
## unless `full_width` (names typed on the naming screen, every JP / EU string), where it becomes
## convertAsciiToJis's code; other characters are their 2-byte Shift-JIS code, high byte first.
func to_bytes(text: String, full_width := false) -> PackedByteArray:
	var out := PackedByteArray()
	var wide := full_width or language != "en_us"
	for i in text.length():
		var c := text.unicode_at(i)
		var code := 0
		if c < 0x80:
			if not wide:
				out.append(c)
				continue
			code = _ascii.get(c, [0, 0])[0]
		else:
			code = _codes.get(text[i], 0)
		if code == 0:
			code = NO_CODE
		out.append(code >> 8)
		out.append(code & 0xFF)
	return out


## Bit 15 - x of a row is pixel x; a 0 bit is ink (font.c:1630).
static func is_ink(rows: Array, x: int, y: int) -> bool:
	return (int(rows[y]) >> (15 - x)) & 1 == 0
