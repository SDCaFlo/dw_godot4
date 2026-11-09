class_name FishingHud
extends Control
## The tension gauge (FISH_drawTensionGauge, fish.c:2101; specs/fishing.md §2.7; step F5): the frame
## (FISH_SPRITES[31]) at (−95, −64) from the screen centre and remap(level, ±limit, 0, 9) bars
## (FISH_SPRITES[32]) 3 pixels apart in the tension colour. The C draws it while the rod shows and
## the gauge is on. The host sets the state each game frame (show_gauge) and the field adds it to
## the HUD under the UI boxes.

const CENTRE := Vector2(160, 120)
## MAIN_D_80134974: the gauge's position.
const POSITION := Vector2i(-95, -64)
const FRAME_SPRITE := 31
const BAR_SPRITE := 32
const BAR_STEP := 3

var view: FishingView
var _shown := false
var _bars := 0
var _color := Color.WHITE


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	material = PsxUiFilter.material()


## This frame's gauge (or none).
func show_gauge(shown: bool, bars := 0, color := Color.WHITE) -> void:
	_shown = shown
	_bars = bars
	_color = color
	queue_redraw()


func _draw() -> void:
	if not _shown or view == null:
		return
	_sprite(FRAME_SPRITE, POSITION, Color.WHITE)
	# A PSX tint of 255 is twice the texel (128 = 1.0), clamped.
	var tint := Color(_color.r8 / 128.0, _color.g8 / 128.0, _color.b8 / 128.0)
	for i in _bars:
		_sprite(BAR_SPRITE, POSITION + Vector2i(i * BAR_STEP, 0), tint)


## FISH_drawSprite2D at scale 1, no rotation, opaque (flags 0): both texel sets drawn as they are.
func _sprite(index: int, at: Vector2i, tint: Color) -> void:
	if index >= view.sprite_table.size():
		return
	var desc: Dictionary = view.sprite_table[index]
	var tex := view.sprite_texture(desc)
	if tex == null:
		return
	var uv: Array = desc["uv"]
	var origin: Array = desc["origin"]
	var w := absi(int(uv[2]) - int(uv[0]))
	var h := absi(int(uv[3]) - int(uv[1]))
	var dst := Rect2(CENTRE + Vector2(at.x - int(origin[0]), at.y - int(origin[1])), Vector2(w, h))
	var src := Rect2(int(uv[0]), int(uv[1]) - view.uv_origin_v, int(uv[2]) - int(uv[0]), int(uv[3]) - int(uv[1]))
	draw_texture_rect_region(tex.base, dst, src, tint)
	draw_texture_rect_region(tex.stp, dst, src, tint)
