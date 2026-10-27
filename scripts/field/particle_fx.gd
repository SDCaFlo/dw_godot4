class_name ParticleFX
extends Control
## The hit sparks (renderParticleFX, efe.c:536; renderParticleFlash efe.c:1055; renderFXParticle,
## addFXPrim effect_common.c; specs/training.md §6.9) of the training stations: the bursts of
## ParticleBursts (the logic, with its random rolls) drawn in the 320 x 240 HUD like CloudFX,
## additive. The battle draws the same bursts in 3D (BattleFxView).

const SLOTS := ParticleBursts.SLOTS
const PARTICLES := ParticleBursts.PARTICLES
const PARTICLE_COUNT := ParticleBursts.PARTICLE_COUNT
const FLASH_STATE := ParticleBursts.FLASH_STATE
## The flash: SPOT256 (etctim/07_spot256, tpage 832,256 8bpp, u 0x40 v 0xC0 = image (64, 64)),
## one 64 x 64 quarter mirrored four ways; its size is (scale × 63 >> 10) + 1 per quarter.
const FLASH_TEXTURE := "etctim/07_spot256"
const FLASH_REGION := Rect2(64, 64, 64, 64)
const FLASH_SIZE := 0x40
## renderFXParticle: DEFEFF palette 1 (CLUT 192,489), u 0 v 160 on tpage 768,256 = image (0, 32),
## 15 x 15, drawn 0x28 world units wide.
const PARTICLE_TEXTURE := "etctim/02_defeff"
const PARTICLE_PALETTE := 1
const PARTICLE_REGION := Rect2(0, 32, 15, 15)
const PARTICLE_SIZE := 0x28

var camera: Camera3D
var field: FieldMap
var bursts := ParticleBursts.new()
## PARTICLE_FX_DATA (ParticleBursts.effects).
var effects: Array:
	get:
		return bursts.effects
## FX_PARTICLE_DATA.
var directions: Array[Vector3i]:
	get:
		return ParticleBursts.directions
var _flash: PsxTexture
var _particle: PsxTexture
var _additive: Control


func _init() -> void:
	ParticleBursts.initialize_directions()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	material = PsxUiFilter.material()
	_flash = PsxTexture.load_palette(FLASH_TEXTURE, 0)
	if _flash != null:
		_flash.base = mirrored(_flash.base, FLASH_REGION)
		_flash.stp = mirrored(_flash.stp, FLASH_REGION)
	_particle = PsxTexture.load_palette(PARTICLE_TEXTURE, PARTICLE_PALETTE)
	_additive = Control.new()
	_additive.mouse_filter = MOUSE_FILTER_IGNORE
	_additive.set_anchors_preset(Control.PRESET_FULL_RECT)
	_additive.material = PsxUiFilter.material("add")
	_additive.draw.connect(_draw_effects.bind(true))
	add_child(_additive)


## createParticleFX(kind, mode, pos, NULL, lifetime). `position` is PSX (x, y, z).
func create(kind: int, mode: int, position_psx: Vector3i, lifetime := 0) -> void:
	bursts.create(kind, mode, position_psx, lifetime)


func active_count() -> int:
	return bursts.active_count()


## tickParticleFX for every burst, one game frame.
func tick() -> void:
	bursts.tick()
	queue_redraw()
	if _additive != null:
		_additive.queue_redraw()


static func lerp_c(start: int, end: int, t0: int, t1: int, t: int) -> int:
	return ParticleBursts.lerp_c(start, end, t0, t1, t)


static func burst_factor(timer: int, state: int) -> int:
	return ParticleBursts.burst_factor(timer, state)


func particle_position(fx: Dictionary, i: int) -> Vector3i:
	return ParticleBursts.particle_position(fx, i)


func _draw() -> void:
	_draw_effects(false)


## renderParticleFX: the flashes on state 2, then the particles while state < timer. The texels
## without the STP bit draw here, the others on the additive layer.
func _draw_effects(additive: bool) -> void:
	if camera == null:
		return
	var projection := 1.0
	if field != null and not field.data.is_empty():
		projection = float(field.data.get("camera", {}).get("projection", 1.0))
	var canvas: CanvasItem = _additive if additive else self
	for fx in effects:
		var state: int = fx["state"]
		if state < 0:
			continue
		var c: Array = fx["color"]
		if state == FLASH_STATE and _flash != null:
			for s in fx["spread"]:
				var at: Vector3i = Vector3i(fx["position"]) + Vector3i(s[0], s[1], s[2])
				var depth := _depth(at)
				if depth >> 4 <= 0x20 or depth >> 4 >= 0x1000:
					continue
				var scale := int(s[3] * projection * 8) / depth
				var half := ((scale * (FLASH_SIZE - 1)) >> 10) + 1
				_draw_flash(canvas, _flash.stp if additive else _flash.base, _screen(at), half,
						Color(c[0] / 128.0, c[1] / 128.0, c[2] / 128.0))
		if state >= fx["timer"] or _particle == null:
			continue
		var shade := Color(lerp_c(c[0], 0, 0, fx["timer"], state) / 128.0, lerp_c(c[1], 0, 0, fx["timer"], state) / 128.0,
				lerp_c(c[2], 0, 0, fx["timer"], state) / 128.0)
		for i in PARTICLE_COUNT[fx["mode"]]:
			var at := particle_position(fx, i)
			var depth := _depth(at)
			if (depth >> 4) - 0x37 <= 0x20 or (depth >> 4) - 0x37 >= 0x1000:
				continue
			var size := int(PARTICLE_SIZE * projection) / depth
			var screen := _screen(at)
			canvas.draw_texture_rect_region(_particle.stp if additive else _particle.base,
					Rect2(screen - Vector2(size >> 1, size >> 1), Vector2(size, size)), PARTICLE_REGION, shade)


## The four quarters around `centre`, each `half` pixels: the whole flash, built once from the
## quarter (its (63, 63) corner at the centre, mirrored right and below).
func _draw_flash(canvas: CanvasItem, texture: Texture2D, centre: Vector2, half: int, shade: Color) -> void:
	var h := float(half)
	canvas.draw_texture_rect(texture, Rect2(centre - Vector2(h, h), Vector2(2 * h, 2 * h)), false, shade)


## A flash's quarter (`region` of `texture`) mirrored into the four quarters of a texture twice its
## size (renderParticleFlash draws the quarter, then mirrors it right and below).
static func mirrored(texture: Texture2D, region: Rect2) -> Texture2D:
	var src := texture.get_image()
	if src.is_compressed():
		src.decompress()
	var q := src.get_region(Rect2i(region))
	var size := q.get_width()
	var image := Image.create(size * 2, size * 2, false, q.get_format())
	image.blit_rect(q, Rect2i(0, 0, size, size), Vector2i.ZERO)
	var right := q.duplicate()
	right.flip_x()
	image.blit_rect(right, Rect2i(0, 0, size, size), Vector2i(size, 0))
	var below := q.duplicate()
	below.flip_y()
	image.blit_rect(below, Rect2i(0, 0, size, size), Vector2i(0, size))
	var both := right.duplicate()
	both.flip_y()
	image.blit_rect(both, Rect2i(0, 0, size, size), Vector2i(size, size))
	return ImageTexture.create_from_image(image)


func _depth(psx: Vector3i) -> int:
	var world := Content.psx_to_godot([psx.x, psx.y, psx.z])
	if camera.is_position_behind(world):
		return 0
	return int(-(camera.global_transform.affine_inverse() * world).z)


func _screen(psx: Vector3i) -> Vector2:
	return FieldMap.unproject(camera, Content.psx_to_godot([psx.x, psx.y, psx.z]))
