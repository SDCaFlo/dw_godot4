class_name CurlingMatch
extends RefCounted
## Curling's match (specs/curling.md §2.5-2.8, step C3): KAR_start, the world object's tick, the
## tamer state 12 tick (KAR_tick: KAR_tickMatchState then the HUD calls, in the C's order), the
## yes / no prompt, the hint box, the tally, the ring markers and KAR_finishMatch. In the C's integers.
## Logic only: the stones are CurlingStones (C2), the opponent's plan CurlingAi, and everything else
## goes through `world` (CurlingWorld). The HUD is described, not drawn: `sprites` (the KarSprites in
## draw order) and `arrow` (the aim arrow's 15 points) are rebuilt by each tamer_tick() for the view
## (C5). The windows' renderString / renderSelectionCursor / renderUIBox calls are the view's too.
## Fields are the C's globals (spec §3) in snake_case; their C types are kept where they wrap.
## Port-only: uploadMapTileImages, called after each camera step (kar.c:2246, :2961, :3066, :3092,
## :3127), streams the background tiles into VRAM; the port draws the whole background, so nothing.

# --- Match states (MAIN_D_80135244, KAR_tickMatchState kar.c:2765) ----------------------------------
const ST_START := 0
const ST_PROMPT := 1
const ST_DEMO_WAIT := 2
const ST_READY := 3
const ST_DEMO_PLAN := 4
const ST_CHOOSE := 5
const ST_AIM := 6
const ST_CAMERA_TO_STONE := 7
const ST_POWER := 8
const ST_THROW := 9
const ST_RELEASE := 0xA
const ST_SLIDING := 0xB
const ST_STOPPED := 0xC
const ST_TALLY := 0xD
const ST_DEMO_CAMERA := 0xE
const ST_TURN := 0xF
const ST_CAMERA_TO_THROWER := 0x10
const ST_OPPONENT := 0x11
const ST_UNUSED := 0x12
const ST_HINT := 0x13
const ST_END := 0x14

# --- Code constants -----------------------------------------------------------------------------------
## The spots (kar.c:2776-2780, :2973-2976, :3075-3078): the tamer (-0x190, 0x578), the opponent (0x190).
const TAMER_SPOT_X := -0x190
const OPPONENT_SPOT_X := 0x190
const SPOT_Z := 0x578
## Animations: the wait 0 (kar.c:2782), beginAiming tamer 0x23 / Penguinmon 0x1C (:1953, :1955),
## beginThrow 0x24 / 0x1D / 0x1F (:2024-2028), the throw 0x25 / 0x1E / 0x20 (:3006-3010), the end 2 (:955).
const ANIM_WAIT := 0
const ANIM_END := 2
const ANIM_AIM_TAMER := 0x23
const ANIM_AIM_PENGUINMON := 0x1C
const ANIM_BEGIN_TAMER := 0x24
const ANIM_BEGIN_PENGUINMON := 0x1D
const ANIM_BEGIN_OTHER := 0x1F
const ANIM_THROW_TAMER := 0x25
const ANIM_THROW_PENGUINMON := 0x1E
const ANIM_THROW_OTHER := 0x20
## The opponent slot the C tests (`MAIN_D_80135248 == 2`: Penguinmon; kar.c:889, :1954, :2109, :2207).
const PENGUINMON := 2
## The partner's slot (KAR_finishMatch, kar.c:953).
const PARTNER := 1
## The demo and the ready wait: timer += 6 until >= 0x169 (kar.c:2802, :2809); the ready prompt must
## have counted 0x30 frames (:2801).
const WAIT_STEP := 6
const WAIT_END := 0x169
const READY_FRAMES := 0x30
## The demo's plan (kar.c:2817-2819): rand() % 5, power 0x7D0, angle ratan2(-0xC1C, 0x190).
const DEMO_POWER := 0x7D0
const DEMO_DY := -0xC1C
const DEMO_DX := 0x190
## State 5's step: every 16 frames, timer++ >= 0x10 then -= 0xF (kar.c:2826-2827).
const CHOOSE_FRAMES := 0x10
const CHOOSE_BACK := 0xF
## beginAiming (kar.c:1944): the start aim -0x400 (:1964); a pegged stone shows model 2 (row 0) or 1
## (row 1) (:1960).
const AIM_START := -0x400
const HELD_PEGGED_MODEL_TAMER := 2
const HELD_PEGGED_MODEL_OPPONENT := 1
## The aim range: right while aim < -0x18F, left while aim >= -0x5B6 (kar.c:2937, :2945); the
## demo / opponent turns 0xA towards its plan, within ±0xA throws (:2924-2930).
const AIM_RIGHT_LIMIT := -0x18F
const AIM_LEFT_LIMIT := -0x5B6
const AIM_AUTO_STEP := 0xA
## Camera speeds (tickCameraMoveTo): to the stone 0x14 (kar.c:2959), the tally 5 (:2245), the demo's ring
## 0xA (:3065), to the thrower 0x14 (:3090, :3125). The ring centre (0, -0x6A4) (:3065).
const CAMERA_TO_STONE := 0x14
const CAMERA_TALLY := 5
const CAMERA_RING := 0xA
const CAMERA_TO_THROWER := 0x14
const RING_CENTRE_X := 0
const RING_CENTRE_Z := -0x6A4
## Power: +0x64 a frame, 0xBB8 runs out (kar.c:2971), speed = power + 0x258 (:3013).
const POWER_STEP := 0x64
const POWER_MAX := 0xBB8
const SPEED_BASE := 0x258
## State 0xA: the stone leaves the hand when timer++ >= 3 (kar.c:3020).
const RELEASE_FRAMES := 3
## Both rows have thrown 5 (kar.c:3105, :3130).
const STONES_PER_SIDE := 5
## The hint pages (KAR_tickHintBox's n): 0 choosing, 1 aiming, 2 power, 3 the rules (kar.c:2823, :2897,
## :2981, :3074); mid-match 4 behind / 5 ahead / 6 tie (:3156-3160); the end 7 opponent wins, 8 the tamer
## wins (:3137, :3140); pages >= 7 end the match (:3171).
const PAGE_CHOOSE := 0
const PAGE_AIM := 1
const PAGE_POWER := 2
const PAGE_RULES := 3
const PAGE_BEHIND := 4
const PAGE_AHEAD := 5
const PAGE_TIE := 6
const PAGE_OPPONENT_WINS := 7
const PAGE_TAMER_WINS := 8
## Sounds: playSound2(8, n) (spec §2.10): the slide 0 (kar.c:3016), the tally 5 / 6 for the BAD ring
## (:2270-2272), the end 7 / 8 (:3136, :3139); playSound(0, 2) the prompt (:2062), (0, 3) a hint page
## (:2124).
const BANK_MAP := 8
const BANK_SYSTEM := 0
const SOUND_SLIDE := 0
const SOUND_TALLY := 5
const SOUND_TALLY_BAD := 6
const SOUND_TAMER_WINS := 7
const SOUND_OPPONENT_WINS := 8
const SOUND_CURSOR := 2
const SOUND_PAGE := 3
## The BAD ring (kar.c:2269).
const RING_BAD := 3
## Row 1's ring flag (kar.c:2196, :2265).
const RING_ROW1 := 0x10
const RING_MASK := 0xF
## The tally's blink: blink++ >= 0xB toggles the state ±100 and blink -= 10 (kar.c:2280-2286), 8 toggles
## (blinks++ >= 7, :2287).
const BLINK_FRAMES := 0xB
const BLINK_BACK := 10
const BLINK_COUNT := 7
const BLINK_OFFSET := 100
const TALLY_DONE := 4
## A tallied stone hidden by the blink (state >= 0x65) doesn't light its ring (kar.c:1300).
const TALLY_HIDDEN := 0x65
## The result (KAR_finishMatch, kar.c:962-969): 2 with >= 0xA points, 1 a win, 0 a loss or a tie. The
## end faces 0x800 (towards the camera, :952-954). Text colour 1 (:959).
const RESULT_BIG_WIN := 2
const RESULT_WIN := 1
const RESULT_LOSS := 0
const BIG_WIN_SCORE := 0xA
const FACE_CAMERA := 0x800
const TEXT_COLOR_DEFAULT := 1
## The hint box's text: line 0 of each 4-line box (the name) in colour 7, the others 1 (kar.c:2470-2474);
## line n at y n * 13 + 1 (:2476). The prompt's strings at y hint * 13 + 0xDD (:2042).
const LINES_PER_BOX := 4
const TEXT_COLOR_NAME := 7
const LINE_HEIGHT := 13
const HINT_TEXT_Y := 1
const PROMPT_TEXT_Y := 0xDD
## The windows: MAIN_D_80134A10 / _18 (the prompt, kar.c:269-270), MAIN_D_80134A28 / _30 (the hint box,
## :276-277); pages < 4 open from (0x4B, -5) (:2096-2099).
const PROMPT_FINAL := Rect2i(-130, 42, 262, 59)
const PROMPT_START := Rect2i(75, -5, 10, 10)
const HINT_FINAL := Rect2i(-130, 42, 262, 59)
const HINT_START := Rect2i(0, 0, 10, 10)
const HINT_START_EARLY := Vector2i(0x4B, -5)
const HINT_EARLY_PAGES := 4
## The held stone (KAR_renderScene, kar.c:888-903): the tamer's bone 9 + 0x78 y, MetalMamemon's bone 4
## + 0x78 y, Penguinmon's location - 0x50 x.
const BONE_TAMER_HAND := 9
const BONE_OPPONENT_HAND := 4
const HELD_LIFT := 0x78
const PENGUINMON_HELD_X := 0x50
## KAR_renderScene's skips (kar.c:868-884): the stack builds one stone a second, i * 0x3C + 0x3C.
const STACK_STEP := 0x3C
## The HUD (spec §2.8). The stone cursor: x 0x64 / -0x78, y stone * 30 - 0x2D (kar.c:1111-1112).
const CURSOR_X_OPPONENT := 0x64
const CURSOR_X_TAMER := -0x78
const CURSOR_STEP := 30
const CURSOR_Y := -0x2D
## The scores: ones at x -0x69 / 0x68, tens 0x10 left, y -0x3E; glyph 10 is the minus (kar.c:1131-1147).
const SCORE_X_TAMER := -0x69
const SCORE_X_OPPONENT := 0x68
const SCORE_TENS_DX := 0x10
const SCORE_Y := -0x3E
const GLYPH_MINUS := 10
## The power gauge, states 8-9: frame x -0x32 / 0x32, CLUT x 0x70 / 0x80; bar i at 250 * i <= power, x
## frame + 3i - 3, CLUT x 0x30 for i = 10, else 0x70 (kar.c:1159-1172).
const GAUGE_X := 0x32
const GAUGE_CLUT_TAMER := 0x70
const GAUGE_CLUT_OPPONENT := 0x80
const GAUGE_BARS := 10
const GAUGE_STEP := 250
const GAUGE_BAR_DX := 3
const GAUGE_BAR_CLUT_FULL := 0x30
const GAUGE_BAR_CLUT := 0x70
## The ready prompt: readyTimer++ >= 0x31 -> 0x30, drawn while bit 8 is set (kar.c:1185-1189).
const READY_CAP_TEST := 0x31
const READY_CAP := 0x30
const READY_BLINK_BIT := 8
## The opponent slot whose plate 2 is KAR_D_8005B558 (kar.c:1206).
const METALMAMEMON := 3
## The aim scroll, state 6 on the tamer's turn: left / right ∓8 when |aimTurn| >= 10 or a hint is on,
## up / down ∓10 (kar.c:1228-1243).
const SCROLL_X := 8
const SCROLL_Y := 10
const SCROLL_TURN_MIN := 10
## The aim arrow, states 6-7 (kar.c:987): timer-- != 0 -> += 0xBF (:1017-1018); arrowGap++ >= 0x28 -> 0
## (:1020); 15 points (0, 0, -200 (i + 1)) (:1030); shade (timer + i * 0xBF / 15), -0xBF at >= 0xBF
## (:1035-1036); folded into x -0x2EE ... 0x2EE (:1038-1046); the head at i = 14 rotated by
## -((ratan2(prev - cur) - 0xC00) % 0x1000) (:1061-1064); dot arrowGap / 3 skipped (:1094).
const ARROW_POINTS := 15
const ARROW_STEP := -200
const ARROW_PERIOD := 0xBF
const ARROW_GAP_MAX := 0x28
const ARROW_GAP_DIV := 3
const ARROW_WALL := 0x2EE
const ARROW_HEAD_TURN := 0xC00

var stones: CurlingStones
var ai: CurlingAi
var world: CurlingWorld
var pad: Pad

## MAIN_D_80135244 (int32).
var state := 0
## MAIN_D_8013523C (int8): the side throwing, 0 the tamer, 1 the opponent.
var row := 0
## MAIN_D_8013523A (int16): the selected stone of that row.
var selected := 0
## MAIN_D_8013523E (int16).
var power := 0
## MAIN_D_8013524C (int32).
var aim := 0
## MAIN_D_80135250 (int8): 0 none, >= 1 the hint box's box, -1 just closed; the prompt's 0-4.
var hint := 0
## MAIN_D_80135252 (uint16).
var timer := 0
## MAIN_D_80135254 (int16).
var aim_turn := 0
## MAIN_D_80135248 (uint8): the opponent's entity slot (pstat 0x7A + 2).
var opponent := 0
## MAIN_D_80135256 (int8).
var tally_index := 0
## MAIN_D_80134A4F (int8, initialised to -1, kar.c:444).
var tally_last := -1
## MAIN_D_80135257 (uint8).
var lit := 0
## MAIN_D_8013522C (uint8).
var line_index := 0
## MAIN_D_8013522D (int8).
var skip := 0
## MAIN_D_8013522E (int8).
var tally_sub := 0
## MAIN_D_80135230 / _34 (int32).
var blinks := 0
var blink := 0
## MAIN_D_80135238 (uint16).
var arrow_gap := 0
## MAIN_D_80135220 (uint8).
var ready_timer := 0
## MAIN_D_80135224 (int32).
var camera_arrived := 0
## MAIN_D_80135228 (uint32).
var slide_sound := 0
## KAR_D_800638F4 / KAR_D_80063904.
var cam_prev := Vector3i.ZERO
var cam_from := Vector3i.ZERO
## KAR_D_80063914: a copy of the tamer's last stone. The C's bss: every field 0 (state 0).
var last_stone: CurlingStones.Stone
## KAR_D_800639C0[10]: the stones in throw order.
var throw_order: Array = []
## The world object 0x1388 is in the object list (addObject in KAR_start, removeObject in finish).
var active := false
## The HUD's KarSprites this frame, in draw order: {x, y, clut_x, clut_y, u, v, w, h, r, g, b}.
var sprites: Array = []
## The aim arrow this frame (states 6-7): 15 × {pos: Vector3i (world, y 0), shade (RGB = shade + 0x40),
## head: bool (point 14), rot (the head's screen rotation), skip: bool (the gap's dot, not drawn)}.
var arrow: Array = []

var _data: Dictionary


## `data` is GameData.curling().
func _init(data: Dictionary, p_world: CurlingWorld, p_pad: Pad) -> void:
	_data = data
	world = p_world
	pad = p_pad
	stones = CurlingStones.new(data)
	stones.sound.connect(_on_stone_sound)
	ai = CurlingAi.new(stones, world, data)
	last_stone = CurlingStones.Stone.new()
	last_stone.state = 0
	for i in 10:
		throw_order.append(null)


func _on_stone_sound(id: int) -> void:
	world.play_sound(BANK_MAP, id)


# --- KAR_start (kar.c:778) ---------------------------------------------------------------------------

## KAR_start without the file read (KARRING.TMD) and the tamer's isOnMap, which the host does.
func start() -> void:
	world.set_sync_bit(0)
	state = ST_START
	_setup_match(0)
	active = true  # addObject(0x1388, ...)
	# MAIN_D_80135248 = readPStat(0x7a) + 2 (kar.c:793-794), from the data.
	opponent = (world.read_pstat(int(_data["pstat_opponent"])) + int(_data["opponent_slot_base"])) & 0xFF


## KAR_setupMatch (kar.c:686): the stones (CurlingStones.setup) and the match's selected stone, row and
## power (:702-704).
func _setup_match(mode: int) -> void:
	stones.setup(mode)
	selected = 0
	row = 0
	power = 0


## The world object's tick (KAR_tickStones, kar.c:797), while it is in the object list.
func tick_stones() -> void:
	if active:
		stones.tick(state, row, selected)


## KAR_renderScene's placement of the held stone (kar.c:887-903), called by the host in the render
## phase. The C places it inside the draw loop, after the skips (see skipped()); a held stone (state 0)
## only exists in states 6-0xA, where no skip applies to the throwing row, so it is placed here for
## every held stone.
func update_held_stone() -> void:
	for p in CurlingStones.ROWS:
		for i in CurlingStones.PER_ROW:
			var s: CurlingStones.Stone = stones.rows[p].stones[i]
			if s.state != CurlingStones.STATE_HELD:
				continue
			var idx := opponent if row != 0 else 0
			if idx == PENGUINMON:
				s.pos = world.location(idx)
				s.pos.x = s.pos.x - PENGUINMON_HELD_X
			elif idx == 0:
				var t := world.bone_translation(idx, BONE_TAMER_HAND)
				s.pos = Vector3i(t.x, t.y + HELD_LIFT, t.z)
				s.rotation = Vector3i.ZERO
			else:
				var t := world.bone_translation(idx, BONE_OPPONENT_HAND)
				s.pos = Vector3i(t.x, t.y + HELD_LIFT, t.z)
				s.rotation = Vector3i.ZERO


## KAR_renderScene's skips (kar.c:868-884), for the view: row 1 is hidden below state 0x10 (but 3) while
## a hint shows or before state 5; below state 4, stone i waits until timer >= i * 0x3C + 0x3C. The
## stones' own state rules (state < -0x64 or >= 0x65 not drawn) are the view's.
func skipped(p: int, i: int) -> bool:
	if p == 1 and state != ST_READY and state < ST_CAMERA_TO_THROWER:
		if hint != 0:
			return true
		if state < ST_CHOOSE:
			return true
	if state < ST_DEMO_PLAN:
		if timer < i * STACK_STEP + STACK_STEP:
			return true
	return false


# --- KAR_finishMatch (kar.c:945) ---------------------------------------------------------------------

func finish() -> void:
	if state == ST_END:
		return
	state = ST_END
	world.set_yaw(opponent, FACE_CAMERA)
	world.set_yaw(PARTNER, FACE_CAMERA)
	world.set_yaw(0, FACE_CAMERA)
	world.start_animation(0, ANIM_END)
	world.start_animation(PARTNER, ANIM_END)
	world.start_animation(opponent, ANIM_END)
	world.set_sync_bit(1)
	active = false  # removeObject(0x1388, 0xf)
	world.set_text_color(TEXT_COLOR_DEFAULT)
	var result_pstat := int(_data["pstat_result"])  # 0x79
	if _row(0).score > _row(1).score:
		if _row(0).score >= BIG_WIN_SCORE:
			world.write_pstat(result_pstat, RESULT_BIG_WIN)
		else:
			world.write_pstat(result_pstat, RESULT_WIN)
	else:
		world.write_pstat(result_pstat, RESULT_LOSS)


# --- KAR_tick (kar.c:973): tamer state 12 --------------------------------------------------------------

## The ten calls in the C's order. The render calls change state the logic reads (the arrow decrements
## the shared timer, the ready prompt counts readyTimer).
func tamer_tick() -> void:
	sprites = []
	arrow = []
	_tick_match_state()
	_render_aim_arrow()
	_render_stone_cursor()
	_render_scores()
	_render_power_meter()
	_render_ready_prompt()
	_render_name_plates()
	_handle_aim_scroll()
	_update_ring_markers()
	_check_stones_stopped()


# --- helpers -------------------------------------------------------------------------------------------

func _row(p: int) -> CurlingStones.Row:
	return stones.rows[p]


func _stone() -> CurlingStones.Stone:
	return stones.rows[row].stones[selected]


## The thrower's slot: 0 on the tamer's turn, else the opponent's (`row != 0 ? MAIN_D_80135248 : 0`).
func _thrower() -> int:
	return opponent if row != 0 else 0


## A new press: POLLED_INPUT & bit and not POLLED_INPUT_PREVIOUS & bit.
func _pressed(bit: int) -> bool:
	return pad.polled & bit != 0 and pad.polled_previous & bit == 0


func _held(bit: int) -> bool:
	return pad.polled & bit != 0


## A KarSprite struct copy (the C copies the table entry, then sets its fields).
func _sprite(src: Dictionary) -> Dictionary:
	return {"x": int(src["x"]), "y": int(src["y"]), "clut_x": int(src["clut_x"]), "clut_y": int(src["clut_y"]),
			"u": int(src["u"]), "v": int(src["v"]), "w": int(src["w"]), "h": int(src["h"]),
			"r": int(src["r"]), "g": int(src["g"]), "b": int(src["b"])}


## KAR_renderSprite (kar.c:2749): a POLY_FT4 at OT 10; here, the next entry of `sprites`.
func _render_sprite(sp: Dictionary) -> void:
	sprites.append(sp.duplicate())


## A KarStone struct copy (`*dst = *src`, kar.c:2829, :3083).
static func _copy_stone(src: CurlingStones.Stone, dst: CurlingStones.Stone) -> void:
	dst.state = src.state
	dst.type = src.type
	dst.weight = src.weight
	dst.speed = src.speed
	dst.angle = src.angle
	dst.ring = src.ring
	dst.prev_ring = src.prev_ring
	dst.model = src.model
	dst.target = src.target
	dst.rotation = src.rotation
	dst.pos = src.pos


func _hint_table() -> Dictionary:
	# KAR_tickHintBox picks the page function by the slot (`MAIN_D_80135248 == 2`, kar.c:2109):
	# slot 2 is Penguinmon's table, anything else MetalMamemon's.
	return _data["hints"]["penguinmon" if opponent == PENGUINMON else "metalmamemon"]


# --- KAR_tickMatchState (kar.c:2765) -------------------------------------------------------------------

func _tick_match_state() -> void:
	var player := _thrower()
	match state:
		ST_START:
			timer = 0
			world.set_location_xz(0, TAMER_SPOT_X, SPOT_Z)
			world.set_yaw(0, 0)
			world.set_location_xz(opponent, OPPONENT_SPOT_X, SPOT_Z)
			world.set_yaw(opponent, 0)
			world.start_animation(0, ANIM_WAIT)
			world.start_animation(opponent, ANIM_WAIT)
			state = ST_PROMPT
			world.clear_text_area()
			hint = 0
		ST_PROMPT:
			var prompt := _tick_yes_no_prompt()
			if prompt == 1:
				state = ST_READY
				hint = 0
			elif prompt == 2:
				world.clear_text_area()
				state = ST_DEMO_WAIT
				hint = 0
				_setup_match(1)
		ST_READY:
			if ready_timer >= READY_FRAMES:
				timer = (timer + WAIT_STEP) & 0xFFFF
				if timer >= WAIT_END:
					timer = 0
					state = ST_CHOOSE
		ST_DEMO_WAIT:
			timer = (timer + WAIT_STEP) & 0xFFFF
			if timer >= WAIT_END:
				timer = 0
				state = ST_DEMO_PLAN
		ST_DEMO_PLAN:
			hint = 1
			state = ST_CHOOSE
			_row(0).plan_stone = (Rng.rand() % 5) & 0xFFFF  # unk4 is uint16
			_row(0).plan_power = DEMO_POWER
			_row(0).stones[_row(0).plan_stone].angle = PsxMath.ratan2(DEMO_DY, DEMO_DX)
		ST_CHOOSE:
			_state_choose()
		ST_AIM:
			_state_aim()
		ST_CAMERA_TO_STONE:
			camera_arrived = world.camera_move_to(_stone().pos.x, _stone().pos.z, CAMERA_TO_STONE)
			if camera_arrived == 1:
				state = ST_POWER
			aim_turn = 0
		ST_POWER:
			_state_power()
		ST_THROW:
			if row == 0:
				world.start_animation(0, ANIM_THROW_TAMER)
			elif opponent == PENGUINMON:
				world.start_animation(opponent, ANIM_THROW_PENGUINMON)
			else:
				world.start_animation(opponent, ANIM_THROW_OTHER)
			_stone().speed = PsxMath.s16(power + SPEED_BASE)
			state = ST_RELEASE
			timer = 0
			slide_sound = world.play_sound(BANK_MAP, SOUND_SLIDE) & 0xFFFFFFFF
			cam_prev = _stone().pos
		ST_RELEASE:
			var t := timer
			timer = (timer + 1) & 0xFFFF
			if t >= RELEASE_FRAMES:
				timer = 0
				_stone().state = CurlingStones.STATE_ICE
				cam_prev = _stone().pos
				state = ST_SLIDING
		ST_SLIDING:
			cam_from = cam_prev
			cam_prev = _stone().pos
			world.camera_move_by_diff(cam_from, cam_prev)
		ST_STOPPED:
			world.stop_sound_mask(slide_sound)
			_classify_stone_rings()
			_row(row).thrown += 1
			state = ST_TALLY
			for i in 2:
				_row(i).thrown = 0
				for j in CurlingStones.PER_ROW:
					if _row(i).stones[j].state != CurlingStones.STATE_WAITING:
						_row(i).thrown += 1
		ST_TALLY:
			var prompt := _tick_score_tally()
			if prompt != 0:
				if hint != 0:
					state = ST_DEMO_CAMERA
				else:
					state = ST_TURN
		ST_DEMO_CAMERA:
			camera_arrived = world.camera_move_to(RING_CENTRE_X, RING_CENTRE_Z, CAMERA_RING)
			if camera_arrived == 1:
				state = ST_TURN
		ST_TURN:
			_state_turn(player)
		ST_CAMERA_TO_THROWER:
			var loc := world.location(player)
			camera_arrived = world.camera_move_to(loc.x, loc.z, CAMERA_TO_THROWER)
			if camera_arrived == 1:
				if _row(0).thrown >= STONES_PER_SIDE and _row(1).thrown >= STONES_PER_SIDE:
					hint = 1
					world.clear_text_area()
					state = ST_HINT
					if _row(0).score > _row(1).score:
						world.play_sound(BANK_MAP, SOUND_TAMER_WINS)
						timer = PAGE_TAMER_WINS
					else:
						world.play_sound(BANK_MAP, SOUND_OPPONENT_WINS)
						timer = PAGE_OPPONENT_WINS
				elif row != 0:
					state = ST_OPPONENT
				else:
					state = ST_CHOOSE
		ST_OPPONENT:
			ai.choose(opponent, last_stone)
			state = ST_HINT
			hint = 1
			timer = 0
			power = 0
			if _row(0).score > _row(1).score:
				timer = PAGE_AHEAD
			elif _row(0).score == _row(1).score:
				timer = PAGE_TIE
			else:
				timer = PAGE_BEHIND
		ST_UNUSED:
			# No state sets 0x12 (kar.c:3163).
			if world.box_state() == 1:
				state = ST_HINT
		ST_HINT:
			if _tick_hint_box(PsxMath.s8(timer)) == 0:
				hint = 0
				if timer >= PAGE_OPPONENT_WINS:
					finish()
				else:
					state = ST_CHOOSE
					timer = 0
					power = 0
		ST_END:
			timer = 0
			power = 0
			finish()


## State 5, choosing a stone (kar.c:2821).
func _state_choose() -> void:
	if row != 0 or hint != 0:
		# The demo or the opponent: the plan's stone (unk4), one step every 16 frames.
		if _tick_hint_box(PAGE_CHOOSE) != 0:
			return  # break: aimTurn is not reset
		var t := timer
		timer = (timer + 1) & 0xFFFF
		if t >= CHOOSE_FRAMES:
			timer = (timer - CHOOSE_BACK) & 0xFFFF
			if selected == _row(row).plan_stone:
				var copy: CurlingStones.Stone = stones.rows[2].stones[4]
				_copy_stone(_stone(), copy)
				copy.state = CurlingStones.STATE_OUT
				_begin_aiming()
				timer = 0
				if hint != 0:
					hint = 1
			if _row(row).plan_stone > selected:
				_select_next_stone()
	else:
		# The tamer (US: an else chain, kar.c:2846-2856).
		if _pressed(Pad.CONFIRM):
			_begin_aiming()
		elif _pressed(Pad.UP):
			_select_previous_stone()
		elif _pressed(Pad.DOWN):
			_select_next_stone()
	aim_turn = 0


## State 6, aiming (kar.c:2861; the US branch for the demo / opponent, :2898).
func _state_aim() -> void:
	if row != 0 or hint != 0:
		var target_angle: int = _stone().angle
		if _tick_hint_box(PAGE_AIM) != 0:
			# The pad turns the aim, one direction a frame; after a turn the C goes on to the plan's
			# test below (no break, kar.c:2900-2919).
			if _held(Pad.RIGHT) and aim < AIM_RIGHT_LIMIT:
				aim_turn = PsxMath.s16(aim_turn + 1) if aim_turn > 0 else 1
				_turn_aim_left(aim_turn)
			elif _held(Pad.LEFT) and aim >= AIM_LEFT_LIMIT:
				aim_turn = PsxMath.s16(aim_turn - 1) if aim_turn < 0 else -1
				_turn_aim_right(aim_turn)
			elif not _held(Pad.LEFT) and not _held(Pad.RIGHT):
				aim_turn = 0
				return
			else:
				return
		if target_angle <= aim + AIM_AUTO_STEP and target_angle >= aim - AIM_AUTO_STEP:
			_begin_throw()
			if hint != 0:
				hint = 1
		elif target_angle > aim:
			_turn_aim_left(AIM_AUTO_STEP)
		else:
			_turn_aim_right(-AIM_AUTO_STEP)
	else:
		if _pressed(Pad.CONFIRM):
			_begin_throw()
		if _held(Pad.RIGHT) and aim < AIM_RIGHT_LIMIT:
			aim_turn = PsxMath.s16(aim_turn + 1) if aim_turn > 0 else 1
			_turn_aim_left(aim_turn)
		if _held(Pad.LEFT) and aim >= AIM_LEFT_LIMIT:
			aim_turn = PsxMath.s16(aim_turn - 1) if aim_turn < 0 else -1
			_turn_aim_right(aim_turn)
		if not _held(Pad.LEFT) and not _held(Pad.RIGHT):
			aim_turn = 0


## State 8, the power gauge (kar.c:2970).
func _state_power() -> void:
	power = PsxMath.s16(power + POWER_STEP)
	if power >= POWER_MAX:
		power = 0
		state = ST_AIM
		world.set_location_xz(0, TAMER_SPOT_X, SPOT_Z)
		world.set_location_xz(opponent, OPPONENT_SPOT_X, SPOT_Z)
		if row == 0:
			world.start_animation(0, ANIM_WAIT)
		else:
			world.start_animation(opponent, ANIM_WAIT)
	elif row != 0 or hint != 0:
		if _tick_hint_box(PAGE_POWER) != 0:
			# Capped at the row's own plan while the hint shows (kar.c:2982-2984).
			if _row(row).plan_power <= power:
				power = _row(row).plan_power
		elif _row(1).plan_power <= power:
			# Row 1's plan even in the demo, where the plan is row 0's (kar.c:2985; spec §2.6).
			state = ST_THROW
			_stone().rotation.y = world.yaw(opponent)
			if hint != 0:
				hint = 1
	elif _pressed(Pad.CONFIRM):
		state = ST_THROW
		_stone().angle = aim
		_stone().rotation.y = world.yaw(0)


## The end of state 0xF, the turn change (kar.c:3073).
func _state_turn(player: int) -> void:
	if _tick_hint_box(PAGE_RULES) != 0:
		return
	world.set_location_xz(0, TAMER_SPOT_X, SPOT_Z)
	world.set_location_xz(opponent, OPPONENT_SPOT_X, SPOT_Z)
	world.start_animation(0, ANIM_WAIT)
	world.start_animation(opponent, ANIM_WAIT)
	if row == 0:
		_copy_stone(_row(0).stones[selected], last_stone)
	if hint != 0:
		# After the demo (kar.c:3088-3099).
		var loc := world.location(player)
		camera_arrived = world.camera_move_to(loc.x, loc.z, CAMERA_TO_THROWER)
		if camera_arrived == 1:
			world.set_yaw(player, 0)
			hint = 0
			state = ST_READY
			_setup_match(0)
			timer = 0
	else:
		if _row(0).thrown == _row(1).thrown:
			if _row(0).thrown == STONES_PER_SIDE:
				row = 1
			elif _row(0).score < _row(1).score:
				row = 0
			else:
				row = 1
		elif _row(0).thrown < _row(1).thrown:
			row = 0
		else:
			row = 1
		for j in CurlingStones.PER_ROW:
			if _row(row).stones[j].state == CurlingStones.STATE_WAITING:
				selected = j
				break
		timer = 0
		power = 0
		state = ST_CAMERA_TO_THROWER


# --- Player input (kar.c:1944-2030) ---------------------------------------------------------------------

## KAR_beginAiming (kar.c:1944).
func _begin_aiming() -> void:
	var idx := _thrower()
	state = ST_AIM
	if idx == 0:
		world.start_animation(0, ANIM_AIM_TAMER)
	elif opponent == PENGUINMON:
		world.start_animation(opponent, ANIM_AIM_PENGUINMON)
	var s := _stone()
	s.state = CurlingStones.STATE_HELD
	if s.type == CurlingStones.TYPE_PEGGED:
		s.model = HELD_PEGGED_MODEL_OPPONENT if row != 0 else HELD_PEGGED_MODEL_TAMER
	aim = AIM_START
	world.set_yaw(idx, 0)


## KAR_selectPreviousStone (kar.c:1968).
func _select_previous_stone() -> void:
	if selected > 0:
		for i in range(selected - 1, -1, -1):
			if _row(row).stones[i].state == CurlingStones.STATE_WAITING:
				selected = i
				return


## KAR_selectNextStone (kar.c:1982).
func _select_next_stone() -> void:
	if selected < 4:
		for i in range(selected + 1, CurlingStones.PER_ROW):
			if _row(row).stones[i].state == CurlingStones.STATE_WAITING:
				selected = i
				return


## KAR_turnAimLeft (kar.c:1997); KAR_turnAimRight (:2009) is the same code.
func _turn_aim_left(delta: int) -> void:
	var idx := _thrower()
	delta = PsxMath.s16(delta)
	world.set_yaw(idx, PsxMath.s16(world.yaw(idx) - delta))
	aim += delta


func _turn_aim_right(delta: int) -> void:
	var idx := _thrower()
	delta = PsxMath.s16(delta)
	world.set_yaw(idx, PsxMath.s16(world.yaw(idx) - delta))
	aim += delta


## KAR_beginThrow (kar.c:2020).
func _begin_throw() -> void:
	state = ST_CAMERA_TO_STONE
	if row == 0:
		world.start_animation(0, ANIM_BEGIN_TAMER)
	elif opponent == PENGUINMON:
		world.start_animation(opponent, ANIM_BEGIN_PENGUINMON)
	else:
		world.start_animation(opponent, ANIM_BEGIN_OTHER)


# --- KAR_tickYesNoPrompt (kar.c:2032) -------------------------------------------------------------------

## 1 "Start Game", 2 "Explain Game" once the box has closed; 0 meanwhile.
func _tick_yes_no_prompt() -> int:
	# MAIN_D_80134A20 (US): {KAR_D_8005ABB8, NULL}. The NULL draws nothing (spec §8 Q1): localize(null)
	# is "".
	var strs: Array = [_data["menu"], null]
	if hint < 2:
		world.draw_string(world.localize(strs[hint]), 0, hint * LINE_HEIGHT + PROMPT_TEXT_Y)
		hint += 1
	if world.box_state() == 0:
		if hint == 2:
			world.create_box(PROMPT_FINAL, PROMPT_START)
			hint = 3
		elif hint == 3 or hint == 4:
			return PsxMath.s8(hint - 2)
	if world.box_state() == 1:
		if _pressed(Pad.CONFIRM):
			world.remove_box()
		else:
			if _pressed(Pad.UP):
				hint = 4 if hint == 3 else 3
				world.play_sound(BANK_SYSTEM, SOUND_CURSOR)
			elif _pressed(Pad.DOWN):  # US: else if (kar.c:2064-2066)
				hint = 4 if hint == 3 else 3
				world.play_sound(BANK_SYSTEM, SOUND_CURSOR)
			# renderString x2 and renderSelectionCursor (kar.c:2076-2078): the view, from `hint`.
	return 0


# --- KAR_tickHintBox (kar.c:2085), KAR_drawHintPage* (:2457, :2491) --------------------------------------

## 1 while the hint box is on, 0 when no hint shows. `n` is the page.
func _tick_hint_box(n: int) -> int:
	var start := HINT_START
	if hint == 0:
		return 0
	if n < HINT_EARLY_PAGES:
		start.position = HINT_START_EARLY
	if world.box_state() == 0:
		if hint == 1:
			world.create_box(HINT_FINAL, start)
			world.clear_text_area()
			line_index = 0
			return 1
		return 0
	n = PsxMath.s8(_draw_hint_page(n, PsxMath.s8(line_index)))
	if line_index < n * LINES_PER_BOX:
		line_index = (line_index + 1) & 0xFF
	if world.box_state() == 1:
		if _pressed(Pad.CONFIRM):
			hint = PsxMath.s8(hint + 1)
			world.play_sound(BANK_SYSTEM, SOUND_PAGE)
			if n < hint:
				world.remove_box()
				hint = -1
		# hint != -1: renderString of box `hint` and renderUIBox(0) (kar.c:2130-2133): the view.
	return 1


## Draws line `n` of page `idx` and returns the page's box count (pages[idx + 1] - pages[idx]) / 4.
## The lines come from the opponent's table (data `hints`, KAR_D_8005AF58 / KAR_D_8005B318).
func _draw_hint_page(idx: int, n: int) -> int:
	var table := _hint_table()
	var pages: Array = table["pages"]
	var lines: Array = table["lines"]
	if PsxMath.mod(n, LINES_PER_BOX) == 0:
		world.set_text_color(TEXT_COLOR_NAME)
	else:
		world.set_text_color(TEXT_COLOR_DEFAULT)
	world.draw_string(world.localize(lines[int(pages[idx]) + n]), 0, n * LINE_HEIGHT + HINT_TEXT_Y)
	return PsxMath.s8(PsxMath.div(int(pages[idx + 1]) - int(pages[idx]), LINES_PER_BOX))


# --- KAR_classifyStoneRings (kar.c:2140), KAR_registerThrownStone (:2732) --------------------------------

func _classify_stone_rings() -> void:
	stones.classify_rings()
	_register_thrown_stone()


func _register_thrown_stone() -> void:
	tally_index = PsxMath.s8(_row(0).thrown + _row(1).thrown)
	throw_order[tally_index] = _stone()
	tally_last = -1


# --- KAR_tickScoreTally (kar.c:2181) ---------------------------------------------------------------------

## 1 when the tally is over.
func _tick_score_tally() -> int:
	var zones: Array = _data["zones"]
	if _pressed(Pad.CONFIRM):
		skip = 1
	if skip == 1 and (tally_sub == 2 or tally_sub == 1):
		# Confirm: every thrown stone's points at once (kar.c:2193-2219).
		tally_index = PsxMath.s8(_row(0).thrown + _row(1).thrown)
		tally_index -= 1
		_row(0).score = 0
		_row(1).score = 0
		while tally_index >= 0:
			var st: CurlingStones.Stone = throw_order[tally_index]
			var player := 1 if st.ring & RING_ROW1 != 0 else 0
			var ring: int = st.ring & RING_MASK
			if st.state > 0 and ring != 0:
				_row(player).score = PsxMath.s8(_row(player).score + int(zones[ring - 1]["points"]))
			tally_index -= 1
		for i in CurlingStones.ROWS:
			for j in CurlingStones.PER_ROW:
				var s: CurlingStones.Stone = _row(i).stones[j]
				if s.state >= BLINK_OFFSET:
					s.state -= BLINK_OFFSET
		blinks = 0
		blink = 0
		skip = 0
		tally_sub = 0
		return 1
	if tally_last != tally_index:
		while tally_index >= 0:
			var ring: int = throw_order[tally_index].ring & RING_MASK
			if ring != 0:
				tally_last = tally_index
				tally_sub = 0
				break
			tally_index -= 1
		if tally_index < 0:
			skip = 0
			return 1
	var cur: CurlingStones.Stone = throw_order[tally_index]
	if tally_sub == 0:
		if cur.ring != cur.prev_ring:
			var done := world.camera_move_to(cur.pos.x, cur.pos.z, CAMERA_TALLY)
			if done == 1:
				tally_sub = 1
			else:
				return 0
		else:
			tally_sub = 1
	if tally_sub == 1:
		var player := 1 if cur.ring & RING_ROW1 != 0 else 0
		var ring: int = cur.ring & RING_MASK
		_row(player).score = PsxMath.s8(_row(player).score + int(zones[ring - 1]["points"]))
		tally_sub = 2
		if cur.ring != cur.prev_ring and cur.ring & RING_MASK != 0:
			if ring == RING_BAD:
				world.play_sound(BANK_MAP, SOUND_TALLY_BAD)
			else:
				world.play_sound(BANK_MAP, SOUND_TALLY)
	if tally_sub == 2 and tally_index >= 0:
		if cur.ring != cur.prev_ring and cur.ring & RING_MASK != 0:
			var b := blink
			blink += 1
			if b >= BLINK_FRAMES:
				if cur.state < BLINK_OFFSET:
					cur.state += BLINK_OFFSET
				else:
					cur.state -= BLINK_OFFSET
				blink -= BLINK_BACK
				var c := blinks
				blinks += 1
				if c >= BLINK_COUNT:
					blinks = 0
					tally_sub = TALLY_DONE
					tally_index -= 1
		else:
			tally_index -= 1
		if tally_index < 0:
			return 1
		return 0
	return 0


# --- The HUD (kar.c:987-1213) -----------------------------------------------------------------------------

## KAR_renderAimArrow (kar.c:987). The thrower's rotation: the world gives rotation.vy only; vx / vz are
## taken as 0 (the throwers stand upright).
func _render_aim_arrow() -> void:
	var player := _thrower()
	if state < ST_AIM:
		return
	if state >= ST_POWER:
		return
	# `MAIN_D_80135244 >= 2` is always true here (kar.c:1016).
	var t := timer
	timer = (timer - 1) & 0xFFFF
	if t != 0:
		timer = (timer + ARROW_PERIOD) & 0xFFFF
	var g := arrow_gap
	arrow_gap = (arrow_gap + 1) & 0xFFFF
	if g >= ARROW_GAP_MAX:
		arrow_gap = 0
	var m := PsxMath.rot_matrix(Vector3i(0, world.yaw(player), 0))
	var base := _stone().pos
	var prev := Vector3i.ZERO
	for i in ARROW_POINTS:
		var out := PsxMath.apply_matrix_sv(m, Vector3i(0, 0, (i + 1) * ARROW_STEP))
		out.x = PsxMath.s16(out.x + base.x)
		out.z = PsxMath.s16(out.z + base.z)
		var shade := (timer + PsxMath.div(i * ARROW_PERIOD, 15)) & 0xFF
		if shade >= ARROW_PERIOD:
			shade -= ARROW_PERIOD
		while out.x < -ARROW_WALL or out.x >= ARROW_WALL + 1:
			if out.x < -ARROW_WALL:
				var w := PsxMath.s16(out.x + ARROW_WALL)
				out.x = PsxMath.s16(out.x - w * 2)
			if out.x >= ARROW_WALL + 1:
				var w := PsxMath.s16(out.x - ARROW_WALL)
				out.x = PsxMath.s16(out.x - w * 2)
		var head := i == ARROW_POINTS - 1
		var rot := 0
		if head:
			rot = PsxMath.ratan2(prev.z - out.z, prev.x - out.x)
			rot = rot - ARROW_HEAD_TURN
			rot = PsxMath.mod(rot, 0x1000)
			rot = -rot
		arrow.append({"pos": Vector3i(out.x, 0, out.z), "shade": shade, "head": head, "rot": rot,
				"skip": i == PsxMath.div(arrow_gap, ARROW_GAP_DIV)})
		prev = out


## KAR_renderStoneCursor (kar.c:1103).
func _render_stone_cursor() -> void:
	var sprite := _sprite(_data["sprites"]["stone_cursor"])
	if state == ST_CHOOSE:
		sprite["x"] = CURSOR_X_OPPONENT if row != 0 else CURSOR_X_TAMER
		sprite["y"] = selected * CURSOR_STEP + CURSOR_Y
		_render_sprite(sprite)


## KAR_renderScores (kar.c:1117).
func _render_scores() -> void:
	var spr := _sprite(_data["sprites"]["score_digit"])
	var dig: Array = _data["digits"]
	for i in 2:
		var score: int = _row(i).score
		var lo := PsxMath.s16(PsxMath.mod(score, 10))
		var hi := PsxMath.s16(PsxMath.div(score, 10))
		var x := SCORE_X_OPPONENT if i != 0 else SCORE_X_TAMER
		if score < 0:
			hi = GLYPH_MINUS
		if lo < 0:
			lo *= -1
		spr["u"] = int(dig[lo]["u"])
		spr["v"] = int(dig[lo]["v"])
		spr["x"] = x
		spr["y"] = SCORE_Y
		_render_sprite(spr)
		spr["u"] = int(dig[hi]["u"])
		spr["v"] = int(dig[hi]["v"])
		spr["x"] = x - SCORE_TENS_DX
		spr["y"] = SCORE_Y
		_render_sprite(spr)


## KAR_renderPowerMeter (kar.c:1152): the bars, then the frame.
func _render_power_meter() -> void:
	var bar := _sprite(_data["sprites"]["gauge_bar"])
	var frame := _sprite(_data["sprites"]["gauge_frame"])
	if state >= ST_POWER and state < ST_RELEASE:
		frame["x"] = GAUGE_X if row != 0 else -GAUGE_X
		frame["clut_x"] = GAUGE_CLUT_OPPONENT if row != 0 else GAUGE_CLUT_TAMER
		for i in range(GAUGE_BARS, 0, -1):
			if GAUGE_STEP * i <= power:
				bar["x"] = int(frame["x"]) + i * GAUGE_BAR_DX - GAUGE_BAR_DX
				bar["clut_x"] = GAUGE_BAR_CLUT_FULL if i == GAUGE_BARS else GAUGE_BAR_CLUT
				_render_sprite(bar)
		_render_sprite(frame)


## KAR_renderReadyPrompt (kar.c:1179): counts readyTimer, which state 3 reads.
func _render_ready_prompt() -> void:
	var sprite := _sprite(_data["sprites"]["ready_prompt"])
	if state == ST_READY:
		var t := ready_timer
		ready_timer = (ready_timer + 1) & 0xFF
		if t >= READY_CAP_TEST:
			ready_timer = READY_CAP
		if ready_timer & READY_BLINK_BIT != 0:
			_render_sprite(sprite)
	else:
		ready_timer = 0


## KAR_renderNamePlates (kar.c:1196).
func _render_name_plates() -> void:
	var plates: Array = []
	for p in _data["sprites"]["plates"]:
		plates.append(_sprite(p))
	if opponent == METALMAMEMON:
		plates[2] = _sprite(_data["sprites"]["plate_metalmamemon"])
	for p in plates:
		_render_sprite(p)


## KAR_handleAimScroll (kar.c:1215).
func _handle_aim_scroll() -> void:
	if state != ST_AIM:
		return
	var dx := 0
	var dy := 0
	if row != 0:
		return
	if aim_turn >= SCROLL_TURN_MIN or aim_turn < -(SCROLL_TURN_MIN - 1) or hint != 0:
		if _held(Pad.LEFT):
			dx -= SCROLL_X
		if _held(Pad.RIGHT):
			dx += SCROLL_X
	if _held(Pad.UP):
		dy -= SCROLL_Y
	if _held(Pad.DOWN):
		dy += SCROLL_Y
	if dx != 0 or dy != 0:
		world.camera_move_by_offset(dx, dy)


## KAR_updateRingMarkers (kar.c:1248): the lit ring markers (setMapObjectsFlag(start, count, flag ^ 1)).
func _update_ring_markers() -> void:
	var zones: Array = _data["zones"]
	var flags: Array = [0, 0, 0, 0]  # MAIN_D_80134A48, all 0
	if state == ST_SLIDING:
		lit = stones.lit_rings() & 0xFF
		for p in 4:
			if (lit >> p) & 1:
				flags[p] = 1
			world.set_map_objects_flag(int(zones[p]["marker_start"]), int(zones[p]["marker_count"]), flags[p] ^ 1)
	if state == ST_TALLY:
		var st: CurlingStones.Stone = throw_order[tally_index]
		if st.ring != st.prev_ring and st.state < TALLY_HIDDEN:
			var ring: int = st.ring & RING_MASK
			if ring != 0:
				flags[ring - 1] = 1
		for i in 4:
			world.set_map_objects_flag(int(zones[i]["marker_start"]), int(zones[i]["marker_count"]), flags[i] ^ 1)
	if state != ST_TALLY and state != ST_SLIDING:
		for i in 4:
			world.set_map_objects_flag(int(zones[i]["marker_start"]), int(zones[i]["marker_count"]), flags[i] ^ 1)


## KAR_checkStonesStopped (kar.c:1319): only in state 0xB (:1328).
func _check_stones_stopped() -> void:
	if state != ST_SLIDING:
		return
	if stones.check_stopped():
		state = ST_STOPPED
