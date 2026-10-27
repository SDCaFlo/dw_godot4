class_name PsxTexture
## A converted TIM palette page split by the STP bit (asset_porter/specs/tim.md): the GPU blends
## only texels whose colour has bit 15 set, so a semi-transparent sprite draws its `base` texels
## normally and its `stp` texels with the sprite's blend mode. The raw colours come from the
## sidecar's tim.clut.palettes; converted pixels are matched to them by colour.

var base: Texture2D
var stp: Texture2D


## `path` = "<family>/<name>" (e.g. "etctim/03_feel_ef"); `palette` = row in the CLUT (0 = <name>.png).
static func load_palette(path: String, palette: int) -> PsxTexture:
	var texture := Content.load_texture("%s%s.png" % [path, "" if palette == 0 else ".p%d" % palette])
	var sidecar = Content.load_json(path + ".json")
	if texture == null or not sidecar is Dictionary:
		return null
	if palette >= sidecar["tim"]["clut"]["palettes"].size():
		return null
	# A palette is a string of values (etctim) or a list (the effects' TIMs).
	var entry: Variant = sidecar["tim"]["clut"]["palettes"][palette]
	var raw: Array = entry if entry is Array else Array(str(entry).split(" ", false))
	var stp_colours := {}
	var opaque_colours := {}
	for value in raw:
		var c := int(value)
		if c == 0:
			continue
		var key := _rgb(c)
		if c & 0x8000:
			stp_colours[key] = true
		else:
			opaque_colours[key] = true
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var base_image := image.duplicate()
	var stp_image := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a == 0.0:
				continue
			var key := Vector3i(pixel.r8, pixel.g8, pixel.b8)
			# A colour that is in the palette both with and without STP stays opaque.
			if stp_colours.has(key) and not opaque_colours.has(key):
				stp_image.set_pixel(x, y, pixel)
				base_image.set_pixel(x, y, Color(0, 0, 0, 0))
	var result := PsxTexture.new()
	result.base = ImageTexture.create_from_image(base_image)
	result.stp = ImageTexture.create_from_image(stp_image)
	return result


## color_to_rgba of the asset porter (dwporter/formats/psx.py): 5-bit channels as (v << 3) | (v >> 2).
static func _rgb(c: int) -> Vector3i:
	return Vector3i(_expand5(c & 0x1F), _expand5((c >> 5) & 0x1F), _expand5((c >> 10) & 0x1F))


static func _expand5(v: int) -> int:
	return (v << 3) | (v >> 2)
