class_name EfeTexture
## An effect slot's TIM read from the slot's own bytes (BTL_setupLoadedEFEFile puts it in VRAM; the
## TIM's own position is ignored), for the slots whose scripts rewrite their CLUT
## (loadClutColors, addClutLoadPrim; specs/battle_effects.md §7.5): the pixels as palette indices,
## the CLUT rows as raw 16-bit colours, and textures built from them with whatever rows the
## scripts wrote. The other slots use the porter's PNGs.

## parse() result: {bpp, width (pixels), height, indices (PackedByteArray), rows (Array of
## PackedInt32Array(16 or 256))}, or {} when there is no 4 / 8-bit TIM there.
static func parse(mem: PackedByteArray, at: int) -> Dictionary:
	if at < 0 or at + 8 > mem.size() or mem.decode_u32(at) != 0x10:
		return {}
	var flags := mem.decode_u32(at + 4)
	var bpp: int = [4, 8, 16, 24][flags & 3]
	if bpp > 8:
		return {}
	var p := at + 8
	var rows := []
	if flags & 8:
		var w := mem.decode_u16(p + 8)
		var h := mem.decode_u16(p + 10)
		for r in h:
			var row := PackedInt32Array()
			for c in w:
				row.append(mem.decode_u16(p + 12 + (r * w + c) * 2))
			rows.append(row)
		p += mem.decode_u32(p)
	var hw := mem.decode_u16(p + 8)
	var height := mem.decode_u16(p + 10)
	var width := hw * (4 if bpp == 4 else 2)
	var indices := PackedByteArray()
	indices.resize(width * height)
	var data := p + 12
	for y in height:
		for x in width:
			var i := y * width + x
			if bpp == 4:
				var b := mem[data + y * hw * 2 + (x >> 1)]
				indices[i] = (b >> 4) if x & 1 else (b & 0xF)
			else:
				indices[i] = mem[data + y * hw * 2 + x]
	return {"bpp": bpp, "width": width, "height": height, "indices": indices, "rows": rows}


## A 15-bit PSX colour as the porter converts it ((v << 3) | (v >> 2) per channel).
static func rgb(c: int) -> Color:
	var e := func(v: int) -> int: return (v << 3) | (v >> 2)
	return Color8(e.call(c & 0x1F), e.call((c >> 5) & 0x1F), e.call((c >> 10) & 0x1F))


## The TIM in one palette as a PsxTexture (the texels without the STP bit in `base`, the others in
## `stp`; colour 0 transparent), the TIM's size.
static func sprite_texture(tim: Dictionary, palette: PackedInt32Array) -> PsxTexture:
	var base := Image.create(tim["width"], tim["height"], false, Image.FORMAT_RGBA8)
	var stp := Image.create(tim["width"], tim["height"], false, Image.FORMAT_RGBA8)
	_fill(tim, palette, base, stp, false)
	var t := PsxTexture.new()
	t.base = ImageTexture.create_from_image(base)
	t.stp = ImageTexture.create_from_image(stp)
	return t


## The TIM in one palette on a 256 x 256 texture page (at (0, 0), effect texture place 0, as the
## porter's model pages): [albedo (every texel but colour 0), STP mask (white where the bit is
## set)] for a PsxLit material.
static func page_textures(tim: Dictionary, palette: PackedInt32Array) -> Array:
	var albedo := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var mask := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	_fill(tim, palette, albedo, mask, true)
	return [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(mask)]


static func _fill(tim: Dictionary, palette: PackedInt32Array, first: Image, second: Image, page: bool) -> void:
	var w: int = mini(tim["width"], first.get_width())
	var h: int = mini(tim["height"], first.get_height())
	var indices: PackedByteArray = tim["indices"]
	for y in h:
		for x in w:
			var i: int = indices[y * tim["width"] + x]
			var c := palette[i] if i < palette.size() else 0
			if c == 0:
				continue
			if page:
				first.set_pixel(x, y, rgb(c))
				if c & 0x8000:
					second.set_pixel(x, y, Color.WHITE)
			elif c & 0x8000:
				second.set_pixel(x, y, rgb(c))
			else:
				first.set_pixel(x, y, rgb(c))
