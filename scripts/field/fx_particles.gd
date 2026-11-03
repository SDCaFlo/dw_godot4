class_name FxParticles
extends WorldSprites
## renderFXParticle (effect_common.c:761) for the field's effects (the healing particles, the ending's
## sparks; moved out of HealingParticles): a POLY_FT4 of DEFEFF's 15 x 15 dot (tpage (768, 256),
## CLUT (192, 489), u 0 v 160), semi-transparent additive, its colour 128 = 1.0, culled at the OT
## depth (SZ >> 4) - 0x37 (addFXPrim). The owner calls begin(), particle() per particle, end().

## etctim/02_defeff palette 1, u 0 v 160 - 0x80 (the page's lower half), 15 x 15.
const DEFEFF := "etctim/02_defeff"
const DOT := Rect2(0, 32, 15, 15)
## addFXPrim's depth window: (SZ >> 4) - 0x37 in (0x20, 0x1000).
const OT_OFFSET := 0x37
const OT_MIN := 0x20
const OT_MAX := 0x1000

var _dot: PsxTexture


## One particle at the PSX point `at`, `size` units, colour `rgb` (0-255 per channel, 128 = 1.0).
func particle(field_map: FieldMap, at: Vector3i, size: int, rgb: Vector3i) -> void:
	var ws := field_map.world_screen_matrix()
	var depth := (PsxMath.apply_matrix_lv(ws, at) + PsxMath.translation(ws)).z
	var ot := (depth >> 4) - OT_OFFSET
	if depth <= 0 or ot <= OT_MIN or ot >= OT_MAX:
		return
	if _dot == null:
		_dot = PsxTexture.load_palette(DEFEFF, 1)
	sprite(_dot, PsxLit.ADD, Content.psx_to_godot([at.x, at.y, at.z]), Vector2(size, size), DOT,
			Color(rgb.x / 128.0, rgb.y / 128.0, rgb.z / 128.0))
