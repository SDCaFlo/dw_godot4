class_name ParticleFX
extends Control
## The hit sparks (createParticleFX, tickParticleFX, renderParticleFX, initializeParticleFX;
## efe.c:350-575; renderParticleFlash efe.c:1055; renderFXParticle, addFXPrim, lerp
## effect_common.c; specs/training.md §6.9): up to 4 bursts, each a flash of 2-3 mirrored SPOT256
## quarters on its third frame and 50 DEFEFF particles that fly out and fade. Drawn in the
## 320 x 240 HUD like CloudFX, additive. Only the effect without an entity is ported (the
## training stations'); the entity parts (addEntityParticleFX, mode 1's clouds) are battle effects.

const SLOTS := 4
const PARTICLES := 50
## PARTICLE_FX_FLASH_COUNT / PARTICLE_FX_PARTICLE_COUNT by mode, and the timer of each mode.
const FLASH_COUNT := [2, 3, 2]
const PARTICLE_COUNT := [0x19, 0x30, 0x14]
const TIMERS := [0x13, 0x16, 0xE]
## The colour of each kind.
const COLORS := [[0xFF, 0x6E, 0x46], [0xFF, 0x6E, 0x46], [0xC8, 0xC8, 0x64], [0xCC, 0, 0x88], [0x32, 0x32, 0xFF],
		[0x96, 0x96, 0x96], [0xFF, 0x6E, 0x6E]]
const FLASH_STATE := 2
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
## The burst's growth: _sin(lerp(0, 0x6E, 0, timer, state)) >> 7; _sin (math.c:13) takes 512 units
## per turn and returns 4096 = 1.
const BURST_ANGLE := 0x6E
const SIN_TURN := 512.0
const SIN_ONE := 4096.0
## RotMatrixZYX's angles: 4096 per turn.
const ONE_TURN := 4096.0

var camera: Camera3D
var field: FieldMap
## PARTICLE_FX_DATA: {state (-1 free), timer, end_frame, mode, color [r, g, b], position (PSX),
## spread [[dx, dy, dz, size] per flash]}.
var effects: Array = []
## FX_PARTICLE_DATA: the 50 particle directions (PSX units).
var directions: Array[Vector3i] = []
var _flash: PsxTexture
var _particle: PsxTexture
var _additive: Control


func _init() -> void:
	for i in SLOTS:
		effects.append({"state": -1})
	_initialize_directions()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	material = PsxUiFilter.material()
	_flash = PsxTexture.load_palette(FLASH_TEXTURE, 0)
	if _flash != null:
		_flash.base = _mirrored(_flash.base)
		_flash.stp = _mirrored(_flash.stp)
	_particle = PsxTexture.load_palette(PARTICLE_TEXTURE, PARTICLE_PALETTE)
	_additive = Control.new()
	_additive.mouse_filter = MOUSE_FILTER_IGNORE
	_additive.set_anchors_preset(Control.PRESET_FULL_RECT)
	_additive.material = PsxUiFilter.material("add")
	_additive.draw.connect(_draw_effects.bind(true))
	add_child(_additive)


## initializeParticleFX: each direction is (0, 0, (rand % 150 + 250) × 16) turned by three random
## angles of ±1 turn (RotMatrixZYX).
func _initialize_directions() -> void:
	directions.clear()
	for i in PARTICLES:
		var ang := Vector3(((Rng.rand() & 0x7F) - 0x40) * 4096 / 64, ((Rng.rand() & 0x7F) - 0x40) * 4096 / 64,
				((Rng.rand() & 0x7F) - 0x40) * 4096 / 64) * TAU / ONE_TURN
		var length := ((Rng.rand() % 150) + 0xFA) * 0x10
		var v := Basis.from_euler(ang, EULER_ORDER_ZYX) * Vector3(0, 0, length)
		directions.append(Vector3i(roundi(v.x), roundi(v.y), roundi(v.z)))


## createParticleFX(kind, mode, pos, NULL, lifetime): the first free slot; nothing for an unknown
## kind or mode, or when the 4 slots are used. `position` is PSX (x, y, z).
func create(kind: int, mode: int, position_psx: Vector3i, lifetime := 0) -> void:
	var slot := -1
	for i in SLOTS:
		if effects[i]["state"] == -1:
			slot = i
			break
	if slot < 0 or mode < 0 or mode >= TIMERS.size() or kind < 0 or kind >= COLORS.size():
		return
	var spread := []
	for i in FLASH_COUNT[mode]:
		spread.append([(Rng.rand() % 200) - 100, (Rng.rand() % 200) - 100, (Rng.rand() % 200) - 100, 0])
	spread[0][3] = (Rng.rand() % 170) + 250
	spread[1][3] = (Rng.rand() % 170) + 250
	if mode == 1:
		spread[2][3] = (Rng.rand() % 200) + 300
	effects[slot] = {"state": 0, "timer": TIMERS[mode], "end_frame": lifetime + 4, "mode": mode,
			"color": COLORS[kind], "position": position_psx, "spread": spread}


func active_count() -> int:
	var n := 0
	for fx in effects:
		if fx["state"] >= 0:
			n += 1
	return n


## tickParticleFX for every burst, one game frame.
func tick() -> void:
	for i in SLOTS:
		var fx: Dictionary = effects[i]
		if fx["state"] < 0:
			continue
		fx["state"] += 1
		fx["end_frame"] -= 1
		if fx["state"] >= fx["timer"] and fx["end_frame"] < 0:
			effects[i] = {"state": -1}
	queue_redraw()
	if _additive != null:
		_additive.queue_redraw()


## lerp (effect_common.c:278), with its remainder correction.
static func lerp_c(start: int, end: int, t0: int, t1: int, t: int) -> int:
	if t1 == t0:
		return 0
	var span := end - start
	var result := (span * (t - t0)) / (t1 - t0)
	if span >= 0:
		result = result % (span + 1)
		if result < 0:
			result += span
	else:
		result = result % (span - 1)
		if result > 0:
			result += span
	return result + start


## The burst's distance factor at a state: _sin(lerp(0, 0x6E, 0, timer, state)) >> 7.
static func burst_factor(timer: int, state: int) -> int:
	var angle := lerp_c(0, BURST_ANGLE, 0, timer, state)
	return int(sin(angle * TAU / SIN_TURN) * SIN_ONE) >> 7


## A particle's PSX position at a state.
func particle_position(fx: Dictionary, i: int) -> Vector3i:
	var d := burst_factor(fx["timer"], fx["state"])
	return Vector3i(fx["position"]) + Vector3i((d * directions[i].x) >> 9, (d * directions[i].y) >> 9,
			(d * directions[i].z) >> 9)


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


## The flash's quarter of `texture` mirrored into the four quarters of a 128 x 128 texture.
static func _mirrored(texture: Texture2D) -> Texture2D:
	var src := texture.get_image()
	if src.is_compressed():
		src.decompress()
	var q := src.get_region(Rect2i(FLASH_REGION))
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
