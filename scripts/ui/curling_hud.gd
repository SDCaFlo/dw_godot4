class_name CurlingHud
extends Control
## Curling's HUD (specs/curling.md §2.8, §5.3; step C5): the POLY_FT4s KAR_tick adds, on the 4bpp
## sheet of map FRZL17 (tpage (640, 0), CLUT (clut_x, 0x1E6) = the sheet's palette clut_x / 16).
## - The match's sprites (CurlingMatch.sprites, KAR_renderSprite kar.c:2749-2762): setXYWH(x, y, w, h)
##   relative to the screen centre, setUVWH(u, v, w, h), RGB (0x80 = the texel as it is). All go to
##   slot 10 of the field's ordering table with AddPrim (kar.c:2760), which puts each at the head of
##   its slot, so the last one added is drawn first: the quads are the sprites in reverse.
## - The aim arrow (CurlingMatch.arrow, KAR_renderAimArrow kar.c:987-1101): a 16 x 16 quad per point
##   not skipped, centred on the point's projection with the field's camera (kar.c:1050-1054), sorted
##   at its own depth (AddPrim(ot + otz), kar.c:1095), so behind the slot-10 sprites: drawn first.
## The host calls draw_frame once per game frame; the field puts this node on the HUD under the boxes.

## The sheet's palettes (asset porter, maps family: FRZL17's 4bpp image through CLUT (n * 16, 486)).
const SHEET := "maps/FRZL17/curling/sheet.p%02d.png"
## The screen centre: KAR_renderSprite's x / y are relative to it (the slots below 0x20 are drawn with
## the fixed drawing offset of DR_OFFSETS, main.c:3579).
const CENTRE := Vector2(160, 120)
## A palette per 16 CLUT x (setClut(clut_x, 0x1E6): GetClut's x / 16).
const CLUT_STEP := 16
## RGB 0x80 is the texel as it is (the GPU's texel * colour / 128).
const NEUTRAL := 128.0
## The arrow (kar.c:1051-1092): colour shade + 0x40; dots UV (0x18, 0x38) 16 x -16 at
## (x -8, y +8) ... (x +8, y -8); the head UV (0x28, 0x28), 16 x 16 when rot is 0x800, else 15 x 15, on
## the same corners turned by KAR_rotatePoint(rot) (kar.c:1066-1081); CLUT (0x80, 0x1E6).
const ARROW_SHADE := 0x40
const ARROW_HALF := 8
const DOT_UV := Rect2(0x18, 0x38, 16, -16)
const HEAD_UV := Vector2(0x28, 0x28)
const HEAD_FULL_ROT := 0x800
const HEAD_FULL := 16
const HEAD_SMALL := 15
const ARROW_PALETTE := 0x80 / CLUT_STEP

## This frame's quads in drawing order: {rect: Rect2 (screen pixels, 0-320 x 0-240; vertex 0 at
## `position`, vertex 3 at `end`, as setXY4 / setXYWH give them), region: Rect2 (the sheet's texels, the
## same vertex order: a negative size flips), palette: int, color: Color (RGB / 0x80), angle: int (the
## head's KAR_rotatePoint turn, 4096 = a full turn; 0 for the others)}.
var quads: Array = []

var _textures := {}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	# The HUD's upscaling filter, nearest texels, the tint as the vertex colour (PsxUiFilter).
	material = PsxUiFilter.material()


## KAR_tick's draw calls for this frame; `project(Vector3i) -> Vector2` is the field's projection of a
## PSX world point to the 320 x 240 screen. `m` null: nothing.
func draw_frame(m: CurlingMatch, project: Callable) -> void:
	quads = []
	if m != null:
		# Port-only: the projection gives no depth; the arrow's points run away from the camera (z
		# -200 (i + 1) turned by the thrower's yaw), so the last point is the deepest and drawn first,
		# as the ordering table's depth slots would draw them.
		for k in range(m.arrow.size() - 1, -1, -1):
			var p: Dictionary = m.arrow[k]
			if p["skip"]:
				continue
			quads.append(_arrow_quad(p, project.call(p["pos"])))
		for k in range(m.sprites.size() - 1, -1, -1):
			var sp: Dictionary = m.sprites[k]
			quads.append({"rect": Rect2(int(sp["x"]) + CENTRE.x, int(sp["y"]) + CENTRE.y, int(sp["w"]), int(sp["h"])),
					"region": Rect2(int(sp["u"]), int(sp["v"]), int(sp["w"]), int(sp["h"])),
					"palette": int(sp["clut_x"]) / CLUT_STEP,
					"color": Color(int(sp["r"]) / NEUTRAL, int(sp["g"]) / NEUTRAL, int(sp["b"]) / NEUTRAL),
					"angle": 0})
	queue_redraw()


## One arrow point (kar.c:1049-1092) at its projection `sxy` (the field's gives gte_stsxy's whole pixels).
func _arrow_quad(p: Dictionary, sxy: Vector2) -> Dictionary:
	var shade := (int(p["shade"]) + ARROW_SHADE) / NEUTRAL
	var region := DOT_UV
	var angle := 0
	if p["head"]:
		angle = int(p["rot"])
		var size := HEAD_FULL if angle == HEAD_FULL_ROT else HEAD_SMALL
		region = Rect2(HEAD_UV, Vector2(size, size))
	return {"rect": Rect2(sxy.x - ARROW_HALF, sxy.y + ARROW_HALF, ARROW_HALF * 2, -ARROW_HALF * 2), "region": region,
			"palette": ARROW_PALETTE, "color": Color(shade, shade, shade), "angle": angle}


func _draw() -> void:
	for q: Dictionary in quads:
		var tex := _texture(q["palette"])
		if tex == null:
			continue
		var r: Rect2 = q["rect"]
		var g: Rect2 = q["region"]
		# POLY_FT4's vertices 0-3: (x0, y0), (x1, y0), (x0, y1), (x1, y1), the UVs alike.
		var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]
		var angle: int = q["angle"]
		if angle != 0:
			var centre := r.get_center()
			for c in 4:
				corners[c] = centre + _rotate_point(corners[c] - centre, angle)
		var size := Vector2(tex.get_size())
		var uvs: Array[Vector2] = [g.position, Vector2(g.end.x, g.position.y), Vector2(g.position.x, g.end.y), g.end]
		# Godot's quad goes round the edge: vertices 0, 1, 3, 2.
		var color: Color = q["color"]
		draw_primitive(PackedVector2Array([corners[0], corners[1], corners[3], corners[2]]),
				PackedColorArray([color, color, color, color]),
				PackedVector2Array([uvs[0] / size, uvs[1] / size, uvs[3] / size, uvs[2] / size]), tex)


## KAR_rotatePoint (kar.c:2740): (x cos - y sin, x sin + y cos), each product / 4096 truncated, on the
## screen offsets (the C's vx / vz hold the screen x / y).
static func _rotate_point(v: Vector2, ang: int) -> Vector2:
	var x := roundi(v.x)
	var y := roundi(v.y)
	var c := PsxMath.rcos(ang)
	var s := PsxMath.rsin(ang)
	return Vector2(PsxMath.div(x * c, 4096) - PsxMath.div(y * s, 4096), PsxMath.div(x * s, 4096) + PsxMath.div(y * c, 4096))


func _texture(palette: int) -> Texture2D:
	if not _textures.has(palette):
		_textures[palette] = Content.load_texture(SHEET % palette)
	return _textures[palette]
