class_name ConditionBubbles
extends Control
## The condition bubbles over the partner (bubble.c: addConditionBubble, tickConditionBubble,
## renderConditionBubble; specs/care.md §2.11), drawn in the 320 x 240 HUD from ETCDAT/FEEL_EF.TIM
## (asset porter etctim/03_feel_ef: VRAM 960,384, palette p<n> = CLUT row 480 + n, pixel (u, v - 128)).
##
## Care.handle_condition_bubble decides which bubble shows; this node animates and draws it. The
## bubble's x / z follow the partner's position: the original offsets it from a bone
## (CONDITION_FX_OFFSETS, effect_common.c:307), which isn't converted yet.

const TEXTURE := "etctim/03_feel_ef"
const V_BASE := 128
const SLOTS := 3
## CONDITION_SPRITES (bubble.c:55): u, v, w, h, palette (CLUT y - 480), mx, my (the anchor), additive
## (attribute 0x50000000: semi-transparency mode 1; 0x40000000: mode 0, half / half).
const SPRITES := [
	[0x90, 0x80, 16, 16, 3, 8, 0x1A, true],    # 0 hungry
	[0xD0, 0x90, 16, 16, 3, 8, 0x1A, true],    # 1 poopy
	[0xE0, 0xB0, 16, 16, 2, 8, 0x1A, true],    # 2 dying (unused)
	[0x80, 0xB0, 8, 8, 2, 0, 0x0D, true],      # 3 sleepy, low Z
	[0x98, 0x90, 8, 8, 2, 8, 0x13, true],      # 4 sleepy, middle Z
	[0x90, 0x90, 8, 8, 2, 3, 0x1C, true],      # 5 sleepy, high Z
	[0xC0, 0x80, 16, 16, 1, 8, 0x17, true],    # 6 tired
	[0xC0, 0x90, 16, 16, 1, 8, 0x1A, true],    # 7 sick
	[0xD0, 0xA0, 16, 16, 3, 8, 0x1A, true],    # 8 injured
	[0x80, 0xB0, 16, 16, 2, 8, 0x1A, true],    # 9 evolving
	[0xD0, 0xB0, 16, 16, 4, 8, 8, false],      # 10 bubble bursting
	[0xA0, 0x90, 32, 32, 4, 0x10, 0x1F, false],  # 11 bubble
]
## CONDITION_SPRITES_ICON (bubble.c:353): sprites per icon; 9 (tired) and 12 (evolving) are drawn
## by their own code.
const ICON_SPRITES := {0: [], 1: [0], 2: [1], 3: [2], 4: [3], 5: [3, 4], 6: [3, 4, 5], 7: [4, 5], 8: [5],
		10: [7], 11: [8]}
## CONDITION_BUBBLE_TYPES (bubble.c:410): bubble type -> ConditionIcon list {duration, next, icon}.
const SLEEPY := [[10, 1, 0], [4, 1, 4], [4, 1, 5], [8, 1, 6], [1, 1, 7], [1, 1, 8], [1, -5, 0]]
const TYPES := {0: [[100, 0, 1]], 1: [[100, 0, 2]], 2: [[100, 0, 10]], 3: SLEEPY, 4: [[1000, 0, 9]],
		5: [[100, 0, 3]], 6: [[100, 0, 11]], 7: [[100, 0, 12]]}
const HUNGRY_FRAMES := [0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3]
const POOPY_FRAMES := [0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 2, 2, 1]
const INJURED_FRAMES := [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 0]
const EVOLVING_FRAMES := [0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3]
const TIRED_U := [0, 0, 16, 16, 32, 32, 48, 48, 48, 48, 48, 48, 48, 48]
const TIRED_MY := [9, 9, 9, 9, 9, 9, 9, 9, 9, 8, 6, 3, 0, -6]
const SCALE_ONE := 4096.0

var partner: Partner
var camera: Camera3D
var field: FieldMap
var data: Node
## CONDITION_BUBBLES[3]: {frame, frame2, base_height, height, scale, icons, icon}; null = free.
var bubbles := [null, null, null]
## CONDITION_BUBBLE_ID: the slot of the last bubble added.
var current := -1

## palette -> PsxTexture
var _textures := {}
var _additive: Control


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	for palette in [1, 2, 3, 4]:
		var texture := PsxTexture.load_palette(TEXTURE, palette)
		if texture != null:
			_textures[palette] = texture
	# Mode-1 texels add to the screen: a child layer with an additive material, drawn on top.
	_additive = Control.new()
	_additive.mouse_filter = MOUSE_FILTER_IGNORE
	_additive.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_additive.material = material
	_additive.draw.connect(_draw_bubbles.bind(true))
	add_child(_additive)
	var loop := get_node_or_null("/root/GameLoop")
	if loop != null:
		loop.frame.connect(tick)


## handleConditionBubble's removeConditionBubble(CONDITION_BUBBLE_ID) + addConditionBubble(type).
func show_bubble(type: int) -> void:
	remove_current()
	for i in SLOTS:
		if bubbles[i] == null:
			var height := int(data.digimon(partner.digimon).get("height", 0)) if partner != null and data != null else 0
			var base := -height + 20
			bubbles[i] = {"frame": 0, "frame2": 0, "base_height": base, "height": base, "scale": 0,
					"icons": TYPES.get(type, [[100, 0, 0]]), "icon": 0}
			current = i
			return
	current = -1


## removeConditionBubble(CONDITION_BUBBLE_ID).
func remove_current() -> void:
	if current >= 0 and current < SLOTS:
		bubbles[current] = null
	current = -1


## tickConditionBubble (bubble.c:611), each bubble once per game frame.
func tick() -> void:
	for i in SLOTS:
		var b = bubbles[i]
		if b == null:
			continue
		var frame: int = b["frame"]
		if frame >= 50:
			if frame > 50:
				bubbles[i] = null
				continue
			b["height"] = b["base_height"] - 230
			b["scale"] = 0xF000
		elif frame < 10:
			b["scale"] = lerp_psx(0, 0x6000, 0, 10, frame)
			b["height"] = b["base_height"] + lerp_psx(0, -65, 0, 10, frame - 10)
		else:
			b["scale"] = 0x6000
			var angle := lerp_psx(0, 512, 0, 20, frame)
			b["height"] = b["base_height"] - 65 + ((roundi(sin(angle * TAU / 4096.0) * 4096) * 12) >> 12)
		var icon: Array = b["icons"][b["icon"]]
		if b["frame2"] >= icon[0]:
			b["frame2"] = 0
			b["icon"] = int(b["icon"]) + int(icon[1])
		b["frame2"] += 1
		b["frame"] = frame + 1
	queue_redraw()
	if _additive != null:
		_additive.queue_redraw()


## lerp (effect_common.c:278), with its wrap-around modulo.
static func lerp_psx(start: int, end: int, t0: int, t1: int, t: int) -> int:
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


func _draw() -> void:
	_draw_bubbles(false)


## renderConditionBubble (bubble.c:468). Each sprite's opaque texels and its half / half texels are
## drawn here; additive texels on the additive layer.
func _draw_bubbles(additive: bool) -> void:
	if partner == null or camera == null or field == null or _textures.size() < 4:
		return
	var canvas: CanvasItem = _additive if additive else self
	var projection := float(field.data.get("camera", {}).get("projection", 1.0)) if not field.data.is_empty() else 1.0
	for b in bubbles:
		if b == null:
			continue
		var world := Vector3(partner.global_position.x, partner.global_position.y - b["height"], partner.global_position.z)
		if camera.is_position_behind(world):
			continue
		var screen := camera.unproject_position(world)
		var depth := -(camera.global_transform.affine_inverse() * world).z
		if depth <= 0.0:
			continue
		var bubble_scale := float(b["scale"])
		if partner.on_screen:
			var top := 8 if b["frame"] >= 51 else 32
			top = int(top * (bubble_scale * projection / depth)) >> 12
			screen.y = maxf(screen.y, top)
			var value := maxf(depth / 16.0 - 20.0, 36.0)
			bubble_scale = bubble_scale * value / (depth / 16.0)
			depth = value * 16.0
		if depth <= 0x200 or depth >= 0x10000:
			continue
		var factor := bubble_scale * projection / depth / SCALE_ONE
		if b["frame"] >= 51:
			_sprite(canvas, additive, SPRITES[10], screen, factor)
			continue
		# The bubble goes into the ordering table after its icon, so it is drawn behind it.
		_sprite(canvas, additive, SPRITES[11], screen, factor)
		var icon: int = b["icons"][b["icon"]][2]
		var frame: int = b["frame"]
		match icon:
			9:
				var i := frame % 13
				_sprite(canvas, additive, _with(SPRITES[6], {0: TIRED_U[i] + 0xC0, 6: TIRED_MY[i] + 0x17}), screen, factor)
			1:
				var i := frame % 19
				var f: int = HUNGRY_FRAMES[i]
				var my := 0x1A + (3 if (i + 1) % 5 == 0 else 0)
				_sprite(canvas, additive, _with(SPRITES[0], {0: (f << 4) + 0x90, 1: 0x80 if f != 3 else 0xB0, 6: my}), screen, factor)
			2:
				_sprite(canvas, additive, _with(SPRITES[1], {0: (POOPY_FRAMES[frame % 13] << 4) + 0xD0}), screen, factor)
			3:
				_sprite(canvas, additive, _with(SPRITES[2], {0: (((frame / 15) & 1) << 4) + 0xE0}), screen, factor)
			10:
				_sprite(canvas, additive, _with(SPRITES[7], {1: (((frame / 20) & 1) << 4) + 0x90}), screen, factor)
			11:
				_sprite(canvas, additive, _with(SPRITES[8], {0: (INJURED_FRAMES[frame % 20] << 4) + 0xD0}), screen, factor)
			12:
				var f: int = EVOLVING_FRAMES[frame % 19]
				var change := {0: (f << 4) + 0x80, 1: 0xB8, 6: 0x12, 3: 8} if f == 0 else {0: (f << 4) + 0x80, 1: 0xB0, 6: 0x1A, 3: 16}
				_sprite(canvas, additive, _with(SPRITES[9], change), screen, factor)
			_:
				for s in ICON_SPRITES.get(icon, []):
					_sprite(canvas, additive, SPRITES[s], screen, factor)


static func _with(sprite: Array, changes: Dictionary) -> Array:
	var copy := sprite.duplicate()
	for index in changes:
		copy[index] = changes[index]
	return copy


## GsSortSprite: the anchor (mx, my) lands on the screen point, scaled by `factor`.
func _sprite(canvas: CanvasItem, additive: bool, sprite: Array, screen: Vector2, factor: float) -> void:
	var texture: PsxTexture = _textures[sprite[4]]
	var region := Rect2(sprite[0], sprite[1] - V_BASE, sprite[2], sprite[3])
	var rect := Rect2(screen - Vector2(sprite[5], sprite[6]) * factor, Vector2(sprite[2], sprite[3]) * factor)
	if additive:
		if sprite[7]:
			canvas.draw_texture_rect_region(texture.stp, rect, region)
		return
	canvas.draw_texture_rect_region(texture.base, rect, region)
	if not sprite[7]:
		canvas.draw_texture_rect_region(texture.stp, rect, region, Color(1, 1, 1, 0.5))
