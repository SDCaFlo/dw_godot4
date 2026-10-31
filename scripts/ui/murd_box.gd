class_name MurdBox
extends RefCounted
## The MURD life loss display box (src/murd/murd.c:416-470, 690-753; specs/death_reincarnation.md §3).
## Uses UI box ID 3 to display the remaining lives banner and animate the lost heart.
##
## Texture: ETCHI/LIFE.png (112 x 24)
## - Backdrop: (-85, -40), 64 x 24 at u 48, v 0
## - Full heart: (-11 + i * 34, -40), 24 x 24 at u 0, v 0
## - Empty heart: (-11 + i * 34, -40), 24 x 24 at u 24, v 0
##
## Animation timeline:
## - Frames 0..9 (state 0): Full heart shown on the losing slot.
## - Frames 10..29 (state 1): Lost heart blinks every 2 frames between full and empty.
## - Frame 30+ (state 2): Empty heart stays.

const BOX_ID := 3
const FINAL_POS := Rect2i(-95, -50, 190, 44)
const START_POS := Rect2i(-8, -6, 16, 12)

const TEXTURE_PATH := "tim_files/ETCHI/LIFE.png"

const BACKDROP_UV := Rect2(48, 0, 64, 24)
const FULL_HEART_UV := Rect2(0, 0, 24, 24)
const EMPTY_HEART_UV := Rect2(24, 0, 24, 24)

const BACKDROP_POS := Vector2i(-85, -40)
const HEART_BASE_X := -11
const HEART_STEP_X := 34  # 0x22
const HEART_Y := -40

var boxes: UIBoxes
var frame := 0
var state := 0
var lives := 3
var is_open := false
var _texture: Texture2D


func _init(p_boxes: UIBoxes = null) -> void:
	boxes = p_boxes


func open(current_lives: int, start_rect: Rect2i = START_POS) -> void:
	lives = current_lives
	frame = 0
	state = 0
	is_open = true
	_ensure_texture()
	if boxes != null:
		boxes.create_animated(BOX_ID, 0, 2, FINAL_POS, start_rect, tick, render)


func close(target_rect: Rect2i = START_POS) -> void:
	is_open = false
	if boxes != null and boxes.boxes[BOX_ID].state != UIBoxes.STATE_CLOSED:
		boxes.remove_animated(BOX_ID, target_rect)


## MURD_removeLivesBox (murd.c:470): removeStaticUIBox(3), gone at once.
func remove_static() -> void:
	is_open = false
	if boxes != null:
		boxes.remove_static(BOX_ID)


func tick(_id := 0) -> void:
	frame += 1
	match state:
		0:
			if frame >= 10:
				state = 1
		1:
			if frame >= 30:
				state = 2
		2:
			pass


func render(canvas: CanvasItem, _id: int) -> void:
	_ensure_texture()
	if _texture == null:
		return

	# 1. Backdrop banner
	var backdrop_dst := Rect2(PsxDraw.CENTRE + Vector2(BACKDROP_POS.x, BACKDROP_POS.y), BACKDROP_UV.size)
	canvas.draw_texture_rect_region(_texture, backdrop_dst, BACKDROP_UV)

	# 2. Hearts before the losing slot: full
	# Original C: for (i = 0; i < (partner->lives + 1) - 1; i++)
	for i in lives:
		var x := HEART_BASE_X + i * HEART_STEP_X
		var dst := Rect2(PsxDraw.CENTRE + Vector2(x, HEART_Y), FULL_HEART_UV.size)
		canvas.draw_texture_rect_region(_texture, dst, FULL_HEART_UV)

	# 3. The losing heart slot (at index = lives)
	if lives < 3:
		var x := HEART_BASE_X + lives * HEART_STEP_X
		var dst := Rect2(PsxDraw.CENTRE + Vector2(x, HEART_Y), FULL_HEART_UV.size)
		match state:
			0:
				canvas.draw_texture_rect_region(_texture, dst, FULL_HEART_UV)
			1:
				var show_full := ((frame / 2) & 1) == 0
				var uv := FULL_HEART_UV if show_full else EMPTY_HEART_UV
				canvas.draw_texture_rect_region(_texture, dst, uv)
			2:
				canvas.draw_texture_rect_region(_texture, dst, EMPTY_HEART_UV)

	# 4. Hearts after the losing slot: empty
	# Original C: for (i = partner->lives + 1; i < 3; i++)
	for i in range(lives + 1, 3):
		var x := HEART_BASE_X + i * HEART_STEP_X
		var dst := Rect2(PsxDraw.CENTRE + Vector2(x, HEART_Y), EMPTY_HEART_UV.size)
		canvas.draw_texture_rect_region(_texture, dst, EMPTY_HEART_UV)


func _ensure_texture() -> void:
	if _texture == null:
		_texture = Content.load_texture(TEXTURE_PATH)
