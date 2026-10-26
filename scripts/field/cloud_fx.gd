class_name CloudFX
extends Control
## The dust clouds (createCloudFX, tickCloudFX, renderCloudFX, removeAllCloudFX; efe.c:702-760,
## tables :91-120; specs/training.md §2.6): up to 60 puffs on the ground that rise, grow and fade
## over 14 frames, drawn in the 320 x 240 HUD as renderSprite world sprites (as the condition
## bubbles) from ETCDAT/DEFEFF.TIM (asset porter etctim/02_defeff, VRAM 768,384, palette 0 =
## CLUT 192,488). Additive (attribute 0x50000000).

const SLOTS := 0x3C
const LAST_STATE := 0xE
const TEXTURE := "etctim/02_defeff"
const SIZE := 32
const ANCHOR := Vector2(16, 16)
## CLOUD_FX_U, CLOUD_FX_Y, CLOUD_FX_SCALE, CLOUD_FX_COLOR, by state.
const U := [0x00, 0x00, 0x20, 0x20, 0x20, 0x40, 0x40, 0x40, 0x40, 0x40, 0x60, 0x60, 0x60, 0x60]
const Y := [-50, -54, -58, -62, -66, -70, -74, -78, -82, -86, -90, -93, -96, -99]
const SCALE := [0x2000, 0x2EE0, 0x3840, 0x4000, 0x4000, 0x5000, 0x5000, 0x5000, 0x5000, 0x5400, 0x5800,
		0x5C00, 0x6000, 0x6400]
const COLOR := [0x80, 0x80, 0x80, 0x80, 0x79, 0x73, 0x6C, 0x66, 0x60, 0x59, 0x53, 0x4C, 0x46, 0x40]
const SCALE_ONE := 4096.0

var camera: Camera3D
var field: FieldMap
## CLOUD_FX_DATA: {state (-1 free), x, z} per slot.
var clouds: Array = []
var _texture: PsxTexture
var _additive: Control


func _init() -> void:
	for i in SLOTS:
		clouds.append({"state": -1, "x": 0, "z": 0})


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	material = PsxUiFilter.material()
	_texture = PsxTexture.load_palette(TEXTURE, 0)
	_additive = Control.new()
	_additive.mouse_filter = MOUSE_FILTER_IGNORE
	_additive.set_anchors_preset(Control.PRESET_FULL_RECT)
	_additive.material = PsxUiFilter.material("add")
	_additive.draw.connect(_draw_clouds.bind(true))
	add_child(_additive)


## createCloudFX: the first free slot, or nothing when all 60 are used.
func create(x: int, z: int) -> void:
	for c in clouds:
		if c["state"] < 0:
			c["state"] = 0
			c["x"] = x
			c["z"] = z
			return


## removeAllCloudFX.
func remove_all() -> void:
	for c in clouds:
		c["state"] = -1


func active_count() -> int:
	var n := 0
	for c in clouds:
		if c["state"] >= 0:
			n += 1
	return n


## tickCloudFX for every cloud, one game frame.
func tick() -> void:
	for c in clouds:
		if c["state"] < 0:
			continue
		c["state"] += 1
		if c["state"] >= LAST_STATE:
			c["state"] = -1
	queue_redraw()
	if _additive != null:
		_additive.queue_redraw()


func _draw() -> void:
	_draw_clouds(false)


## renderCloudFX: each cloud at (x, Y[state], z), its frame, colour and scale; renderSprite's
## distance scaling and cull (as ConditionBubbles). The texels without the STP bit are drawn
## normally here, the others on the additive layer.
func _draw_clouds(additive: bool) -> void:
	if camera == null or _texture == null:
		return
	var projection := 1.0
	if field != null and not field.data.is_empty():
		projection = float(field.data.get("camera", {}).get("projection", 1.0))
	for c in clouds:
		var state: int = c["state"]
		if state < 0:
			continue
		var world := Content.psx_to_godot([c["x"], Y[state], c["z"]])
		if camera.is_position_behind(world):
			continue
		var depth := -(camera.global_transform.affine_inverse() * world).z
		if depth <= 0x200 or depth >= 0x10000:
			continue
		var factor := float(SCALE[state]) * projection / depth / SCALE_ONE
		var screen := FieldMap.unproject(camera, world)
		var rect := Rect2(screen - ANCHOR * factor, Vector2(SIZE, SIZE) * factor)
		var shade := float(COLOR[state]) / 128.0
		var canvas: CanvasItem = _additive if additive else self
		canvas.draw_texture_rect_region(_texture.stp if additive else _texture.base, rect, Rect2(U[state], 0, SIZE, SIZE),
				Color(shade, shade, shade))
