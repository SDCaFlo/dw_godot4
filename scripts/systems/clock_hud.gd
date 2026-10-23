class_name ClockHud
extends Control
## The clock in the top-left corner (renderGameClock, clock.c:241; specs/clock.md §2.6), drawn
## from the game's texture ETCDAT/FI_INFO.TIM (asset porter etctim/04_fi_info, p<n> = palette
## row 496 + n). PSX screen coordinates are relative to the centre (160, 120); texture
## coordinates map to the image as (u, v - 192).

const TEXTURE := "etctim/04_fi_info%s.png"
const CENTRE := Vector2(160, 120)
const V_BASE := 192
## CLOCK_OFFSET_X: shown at -135, slides by 50 per frame to -220 while time is stopped.
const OFFSET_SHOWN := -135
const OFFSET_HIDDEN := -220
const SLIDE := 50
## CLOCK_TEXCOORD_U / V[night][frame] (clock.c:27-35): the top icon's 4 frames.
const ICON_U := [[128, 160, 128, 160], [160, 128, 160, 128]]
const ICON_V := [[192, 192, 208, 192], [208, 224, 208, 224]]
## HOUR_POINT_X / Y[hour] (clock.c:37-47).
const HOUR_X := [20, 23, 26, 31, 34, 36, 36, 36, 34, 31, 26, 23, 20, 17, 14, 9, 6, 4, 4, 4, 6, 9, 14, 17]
const HOUR_Y := [5, 6, 6, 8, 12, 15, 19, 23, 26, 30, 32, 32, 33, 32, 32, 30, 26, 23, 19, 15, 12, 8, 6, 6]
## Minute hand sprite (initializeClockData, clock.c:224-237): 8x16 at (120, 192), pivot (3, 13).
const HAND_RECT := Rect2(120, 192, 8, 16)
const HAND_PIVOT := Vector2(3, 13)

var clock: Clock
var offset_x := OFFSET_SHOWN
## Palette 496 + n -> texture.
var _textures := {}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	for palette in 4:
		var texture := Content.load_texture(TEXTURE % ("" if palette == 0 else ".p%d" % palette))
		if texture != null:
			_textures[palette] = texture
	var loop := get_node_or_null("/root/GameLoop")
	if loop != null:
		loop.frame.connect(_on_frame)


## The slide of renderGameClock, once per game frame.
func _on_frame() -> void:
	if clock == null:
		return
	offset_x = clampi(offset_x + (SLIDE if clock.running else -SLIDE), OFFSET_HIDDEN, OFFSET_SHOWN)
	queue_redraw()


func _draw() -> void:
	if clock == null or _textures.size() < 4:
		return
	var time: Dictionary = clock.game_state.state["clock"]
	var hour: int = time["hour"]
	var night := 0 if hour >= 6 and hour < 17 else 1
	var frame: int = (time["frame"] % 16) / 4
	# Ordering-table depth 10 (the face) is drawn before depth 9 (everything else).
	_part(0, Rect2(208, 215, 48, 40), Vector2(offset_x, -88))
	_part(1, Rect2(192, 224, 16, 16), Vector2(offset_x - 2, -90))
	_part(1, Rect2(192, 240, 16, 16), Vector2(offset_x + 34, -90))
	_part(2, Rect2(ICON_U[night][frame], ICON_V[night][frame], 32, 16), Vector2(offset_x + 8, -100))
	# Minute hand: rotate = MINUTE * 0x6000 (4096 per degree): 6 degrees per minute, clockwise.
	draw_set_transform(CENTRE + Vector2(offset_x + 23, -66), deg_to_rad(time["minute"] * 6.0))
	draw_texture_rect_region(_textures[3], Rect2(-HAND_PIVOT, HAND_RECT.size), _region(HAND_RECT))
	draw_set_transform(Vector2.ZERO)
	_part(1, Rect2(203, 216, 6, 6), Vector2(offset_x + HOUR_X[hour], HOUR_Y[hour] - 88))


func _part(palette: int, uv: Rect2, screen: Vector2) -> void:
	draw_texture_rect_region(_textures[palette], Rect2(CENTRE + screen, uv.size), _region(uv))


static func _region(uv: Rect2) -> Rect2:
	return Rect2(uv.position - Vector2(0, V_BASE), uv.size)
