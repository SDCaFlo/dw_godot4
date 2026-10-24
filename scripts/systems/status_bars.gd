class_name StatusBars
extends Control
## The happiness and discipline bars (renderStatusBars, partner_impl.c:2153; specs/care.md §2.14),
## drawn with the clock from ETCDAT/SYSTEM_W.TIM (asset porter etctim/08_system_w): texture page 5
## at VRAM (320, 0), the image starts at v 128; palette p<n> = CLUT row 488 + n. Screen coordinates
## are relative to the centre (160, 120), like the clock.

const TEXTURE := "etctim/08_system_w%s.png"
const CENTRE := Vector2(160, 120)
const V_BASE := 128
## CLUT (96, 500), (96, 503), (96, 498) -> palette rows 12, 15, 10.
const PAL_FRAME := 12
const PAL_HAPPINESS := 15
const PAL_DISCIPLINE := 10
## STATUS_UI_OFFSET_X: 75 while game time runs, slides by 50 per frame to 240 (off screen) when stopped.
const OFFSET_SHOWN := 75
const OFFSET_HIDDEN := 240
const SLIDE := 50

var clock: Clock
var care: Care
var offset_x := OFFSET_SHOWN
var _textures := {}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	# The text and windows' upscaling filter (PsxUiFilter, ISSUES.md D-3).
	material = PsxUiFilter.material()
	for palette in [PAL_FRAME, PAL_HAPPINESS, PAL_DISCIPLINE]:
		var texture := Content.load_texture(TEXTURE % (".p%d" % palette))
		if texture != null:
			_textures[palette] = texture
	var loop := get_node_or_null("/root/GameLoop")
	if loop != null:
		loop.frame.connect(_on_frame)


## The slide of renderStatusBars(IS_GAMETIME_RUNNING), once per game frame.
func _on_frame() -> void:
	if clock == null:
		return
	offset_x = clampi(offset_x + (-SLIDE if clock.running else SLIDE), OFFSET_SHOWN, OFFSET_HIDDEN)
	queue_redraw()


func _draw() -> void:
	if clock == null or _textures.size() < 3:
		return
	var state: Dictionary = clock.game_state.state
	var happiness := int(state["partner"]["care"]["happiness"])
	var discipline := int(state["partner"]["care"]["discipline"])
	var off := offset_x
	# Ordering-table depth: 15 (frames) behind 14 (icons, background dots) behind 13 (values).
	_part(PAL_FRAME, Rect2(0, 236, 75, 8), Vector2(off, 85))
	_part(PAL_FRAME, Rect2(0, 236, 75, 8), Vector2(off, 97))
	var happiness_u := 64 if happiness >= 0 else 97
	# Blinks on a liked (-11) or disliked (+11) map: MAP_TILE_DATA.partnerAreaResponse.
	var area := care.area_response if care != null else 0
	if int(state["clock"]["playtime"]["frames"]) % 10 < 5:
		if area == 2:
			happiness_u += 11
		elif area == 1:
			happiness_u -= 11
	_part(PAL_HAPPINESS, Rect2(happiness_u, 244, 11, 11), Vector2(off + 3, 83))
	_part(PAL_DISCIPLINE, Rect2(22 if discipline >= 50 else 33, 244, 11, 11), Vector2(off + 3, 95))
	var happiness_v := 153
	var happiness_count := happiness / 4
	if happiness >= 0:
		for i in 25:
			_part(PAL_HAPPINESS, Rect2(232, 151, 2, 2), Vector2(off + 18 + i * 2, 88))
	else:
		happiness_v = 151
		happiness_count = (happiness + 100) / 4
	var discipline_v := 153
	var discipline_count := (discipline - 50) / 2
	if discipline >= 50:
		for i in 25:
			_part(PAL_HAPPINESS, Rect2(232, 151, 2, 2), Vector2(off + 18 + i * 2, 100))
	else:
		discipline_v = 151
		discipline_count = discipline / 2
	for i in happiness_count:
		_part(PAL_HAPPINESS, Rect2(232, happiness_v, 2, 2), Vector2(off + 18 + i * 2, 88))
	# Quirk kept: the discipline dots are 4 wide at a step of 2, so they overlap.
	for i in discipline_count:
		_part(PAL_HAPPINESS, Rect2(232, discipline_v, 4, 2), Vector2(off + 18 + i * 2, 100))


func _part(palette: int, uv: Rect2, screen: Vector2) -> void:
	draw_texture_rect_region(_textures[palette], Rect2(CENTRE + screen, uv.size),
			Rect2(uv.position - Vector2(0, V_BASE), uv.size))
