class_name EggSelectBox
extends RefCounted
## The DOO2 reincarnation egg selection box (src/doo2/doo2.c:335-352, 721-769; specs/death_reincarnation.md §5).
## Used by Script Builtin 29 to allow the player to choose their reborn Digimon egg.
##
## Box: ID 3, Rect (-84, -70, 168, 80)
## Texture: ETCDAT/TAMA.p4.png through TAMA.p7.png (for each egg's palette 4..7)
##
## Layout:
## - 4 egg slots horizontally: x = (i * 36) - 54, y = -30 (-0x1e)
## - Egg sprite size: 32 x 32
## - Egg sprite u offset: (icons[i] * 32) + 96, where icons = [0, 2, 3, 1]
##   * Egg 0: u = 96, palette 4 (green stripe Botamon egg)
##   * Egg 1: u = 160, palette 5 (pink stripe Poyomon egg)
##   * Egg 2: u = 192, palette 6 (blue stripe Punimon egg)
##   * Egg 3: u = 128, palette 7 (purple stripe Yuramon egg)
## - Cursor sprite: x = (selected_egg * 36) - 54, y = -30 (-0x1e)
##   * Size: 40 x 40 (0x28 x 0x28), u = 96, v = 32 (centered at origin with 4px margin)
##
## Audio:
## - Left/Right: sound (0, 2) DW_SE_CURSOR
## - Confirm (Cross): sound (0, 3) DW_SE_DECIDE

const BOX_ID := 3
const FINAL_POS := Rect2i(-84, -70, 168, 80)
const START_POS := Rect2i(-8, -8, 16, 16)

const EGG_TEXTURE_FMT := "tim_files/ETCDAT/TAMA.p%d.png"

const EGG_ICONS := [0, 2, 3, 1]
const EGG_PALETTES := [4, 5, 6, 7]
const EGG_BASE_X := -54
const EGG_STEP_X := 36
const EGG_Y := -30
const EGG_SIZE := Vector2(32, 32)

const CURSOR_UV := Rect2(96, 32, 40, 40)
const CURSOR_SIZE := Vector2(40, 40)
const CURSOR_OFFSET := Vector2(-4, -4)

const SE_CURSOR := 2
const SE_DECIDE := 3

var boxes: UIBoxes
var pad: Pad
var selected_egg := 0
var is_open := false
var confirmed := false
var ready_for_input := false

var _egg_textures: Array[Texture2D] = []
var _cursor_texture: Texture2D


func _init(p_boxes: UIBoxes = null, p_pad: Pad = null) -> void:
	boxes = p_boxes
	pad = p_pad


func open(initial_egg: int = 0) -> void:
	selected_egg = initial_egg % 4
	is_open = true
	confirmed = false
	ready_for_input = false
	_ensure_textures()
	if boxes != null:
		boxes.create_animated(BOX_ID, 0, 2, FINAL_POS, START_POS, tick, render)


func close() -> void:
	is_open = false
	if boxes != null and boxes.boxes[BOX_ID].state != UIBoxes.STATE_CLOSED:
		boxes.remove_animated(BOX_ID, START_POS)


func tick(_id := 0) -> void:
	if not is_open:
		return

	# In PSX doo2.c: input is processed once box opening animation finishes
	if boxes != null:
		if boxes.boxes[BOX_ID].state == UIBoxes.STATE_OPEN:
			ready_for_input = true
	else:
		ready_for_input = true

	if not ready_for_input or confirmed:
		return

	if pad == null:
		return

	# Right (0x2000)
	if pad.changed & Pad.RIGHT:
		selected_egg = (selected_egg + 1) % 4
		if boxes != null:
			boxes.sound.emit(SE_CURSOR)

	# Left (0x8000)
	if pad.changed & Pad.LEFT:
		selected_egg = (selected_egg + 3) % 4
		if boxes != null:
			boxes.sound.emit(SE_CURSOR)

	# Confirm (Cross)
	if pad.changed & Pad.CONFIRM:
		confirmed = true
		if boxes != null:
			boxes.sound.emit(SE_DECIDE)
			boxes.remove_animated(BOX_ID, START_POS)


func render(canvas: CanvasItem, _id: int) -> void:
	_ensure_textures()

	# Render 4 egg icons
	for i in 4:
		var tex: Texture2D = _egg_textures[i] if i < _egg_textures.size() else null
		if tex == null:
			continue
		var u: float = (EGG_ICONS[i] * 32) + 96
		var uv := Rect2(u, 0, EGG_SIZE.x, EGG_SIZE.y)
		var x := EGG_BASE_X + i * EGG_STEP_X
		var dst := Rect2(PsxDraw.CENTRE + Vector2(x, EGG_Y), EGG_SIZE)
		canvas.draw_texture_rect_region(tex, dst, uv)

	# Render cursor over selected egg
	if _cursor_texture != null:
		var cur_x := EGG_BASE_X + selected_egg * EGG_STEP_X + CURSOR_OFFSET.x
		var cur_y := EGG_Y + CURSOR_OFFSET.y
		var dst := Rect2(PsxDraw.CENTRE + Vector2(cur_x, cur_y), CURSOR_SIZE)
		canvas.draw_texture_rect_region(_cursor_texture, dst, CURSOR_UV)


func _ensure_textures() -> void:
	if _egg_textures.is_empty():
		for p in EGG_PALETTES:
			var path := EGG_TEXTURE_FMT % p
			var tex := Content.load_texture(path)
			_egg_textures.append(tex)
	if _cursor_texture == null and not _egg_textures.is_empty():
		_cursor_texture = _egg_textures[0]
