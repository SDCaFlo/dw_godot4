class_name DeathIris
extends Control
## The death scenes' iris (MURD_renderIris, murd.c:578–688; DOOA_renderIrisWindow, dooa.c:863;
## specs/death_scene.md K4, K5), drawn over the 3D world: SPOT256's round window (its u 0 quarter
## mirrored four ways: white outside, black inside) subtracted at the partner's middle, and four
## white rectangles subtracted around it (black), overlapping the window's edge by
## lerp(4, 1, 0x1860, 0, radius) pixels. Colour 0x80 (1.0). A view: DeathHost calls show_iris every
## frame from MURD's or DOOA's state. Scene: scenes/field/death/death_iris.tscn; PSX screen pixels
## (320 x 240; its canvas layer follows the render scale).

const SPOT := "etctim/07_spot256"
## renderParticleFlash's quarter: 64 x 64 at image (0, 0) (u 0, v 0x80 less the page's 0x80 rows).
const QUARTER := Rect2(0, 0, 64, 64)
const FLASH_SIZE := 0x40

var _window: Texture2D
var _centre := Vector2.ZERO
var _radius := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(FieldMap.SCREEN)
	var sub := CanvasItemMaterial.new()
	sub.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	material = sub
	# SPOT256's colours have the STP bit (0xFFFF: white): its texels are the semi-transparent ones,
	# subtracted (abr 2); they live in PsxTexture's stp texture.
	var spot := PsxTexture.load_palette(SPOT, 0)
	if spot != null:
		_window = ParticleFX.mirrored(spot.stp, QUARTER)
	visible = false


## The window at `centre` (PSX screen pixels) with the C's radius (K1: 4096 = the scale unit).
func show_iris(centre: Vector2, radius: int) -> void:
	_centre = centre
	_radius = radius
	visible = true
	queue_redraw()


func hide_iris() -> void:
	visible = false


func _draw() -> void:
	# renderParticleFlash's half size: (scale · 63 >> 10) + 1; the rectangles' half: scale · 256 / 4096.
	var half := ((_radius * (FLASH_SIZE - 1)) >> 10) + 1
	var box := (_radius << 8) / 4096
	var t := PsxMath.lerp_int(4, 1, 0x1860, 0, _radius)
	var c := _centre.round()
	if _window != null:
		draw_texture_rect(_window, Rect2(c - Vector2(half, half), Vector2(half, half) * 2), false)
	var w := FieldMap.SCREEN
	var left := c.x - box
	var right := c.x + box
	var top := c.y - box
	var bottom := c.y + box
	_black(Rect2(0, 0, left + t, w.y))
	_black(Rect2(right - t, 0, w.x - (right - t), w.y))
	_black(Rect2(left, 0, right - left, top + t))
	_black(Rect2(left, bottom - t, right - left, w.y - (bottom - t)))


## A white rectangle subtracted: black.
func _black(r: Rect2) -> void:
	if r.size.x > 0 and r.size.y > 0:
		draw_rect(r, Color.WHITE)
