class_name FishingRod
extends RefCounted
## The rod (specs/fishing.md §2.4, §2.6-2.13; step F3), logic: FISH_tickRod's state machine
## (fish.c:3688), the bobber ("swimmer": FISH_bobberCommand / _tickBobberPhysics), the bait sprite,
## the hooked fish (FISH_hookFish / _tickHookedFish / _tryStrike), the tension, the rod's pose and
## the camera pans, plus FISH_loadFishing / _endFishing / _tamerTick. In the C's integers. It drives
## `fishing` (the world: F2) and asks `world` (FishingWorld) for the tamer, the inventory and so on.

# --- Rod states (FishingRod.fishingState, fish.c:3723-3758) -------------------------------------
const STATE_NONE := 0
const STATE_CHOOSE := 1
const STATE_PAN_TO_TAMER := 2
const STATE_BAIT_MENU := 3
const STATE_AIM := 6
const STATE_THROWING := 7
const STATE_FLYING := 8
const STATE_FLOATING := 9
const STATE_BITE := 0xA
const STATE_REELING := 0xB
const STATE_CATCH := 0xD
const STATE_END := 0xE
const STATE_PAN_TO_BOBBER := 0xE96
const STATE_SNAG := 0x44C
const STATE_LINE_CUT := 0x4B0
const STATE_HOOK_LOST := 0x4B1
const STATE_SEADRAMON := 0x11AF

# --- Tamer animations (startAnimation ids) ------------------------------------------------------
const ANIM_IDLE := 0
const ANIM_TAKE_ROD := 0x1B
const ANIM_HOLD := 0x1C
const ANIM_WIND_UP := 0x1D
const ANIM_CAST := 0x1E
const ANIM_FLOAT := 0x1F
const ANIM_REEL_IN := 0x20
const ANIM_HOLD_FISH := 0x21
const ANIM_REEL_FISH := 0x22

# --- Bones and offsets ---------------------------------------------------------------------------
## FISH_getRodTipPos / _moveBaitToRodTip: bone 6; FISH_updateRodPose: bone 9 (fish.c:2312, :3482).
const BONE_TIP := 6
const BONE_HAND := 9
## MAIN_D_8013498C (28, 0, 2) rotated + MAIN_D_80134994 (0, 17, 0): the rod tip (fish.c:2314-2318).
const TIP_OFFSET := Vector3i(28, 0, 2)
const TIP_LIFT := Vector3i(0, 17, 0)
## MAIN_D_8013497C (28, 0, 2) + MAIN_D_80134984 (0, 93, 0): the bait at the tip (fish.c:2158-2162).
const BAIT_OFFSET := Vector3i(28, 0, 2)
const BAIT_LIFT := Vector3i(0, 93, 0)
## FISH_updateRodPose: (0x400, 0x400, 0) times toEulerAngles(-6, 0x34, 0x127), the base moved by
## MAIN_D_801349C8 (1, 19, -48); the 5 segments' lengths FISH_D_8007A594 (z 0xFC, 0xB9, 0x65, 0x4B,
## 0); the bend limit 0x80 without the gauge (fish.c:3484-3532).
const ROD_BASE_ROT := Vector3i(0x400, 0x400, 0)
const ROD_BASE_DIR := Vector3i(-6, 0x34, 0x127)
const ROD_BASE_OFFSET := Vector3i(1, 19, -48)
const ROD_SEGMENTS: Array[int] = [0xFC, 0xB9, 0x65, 0x4B, 0]
const ROD_BEND := 0x80

# --- The bobber ----------------------------------------------------------------------------------
## swimmer.mode (fish.c:2481): 0 still, 1 at the rod tip, 2-4 flying.
const MODE_STILL := 0
const MODE_AT_TIP := 1
const MODE_SWING := 2
const MODE_FLYING := 3
## Bobber commands (FISH_bobberCommand's argument).
const CMD_TICK := 0
const CMD_NIBBLE := 2
const CMD_AT_TIP := 4
const CMD_LAND := 7
const CMD_TAKEN := 11
const CMD_BIG_NIBBLE := 12
const CMD_GONE := 14
## The animation sequences (fish.c:352, :462-487).
const SEQ_LAND: Array[int] = [1, 2, 3, 4, 5, 4, 3, -1]
const SEQ_BOB: Array[int] = [4, 3, -1]
const SEQ_NIBBLE: Array[int] = [4, 5, 4, 3, -1]
const SEQ_UNUSED: Array[int] = [4, 5, 6, 7, 0, 0, 0, 0, 0, 0, 0, 0, 7, 6, 5, 4, 3, -1]
const SEQ_TAKEN: Array[int] = [4, 5, 6, 7, -1]
const SEQ_GONE: Array[int] = [7, 6, 5, 4, 3, -1]
## Flying: velocity × 300 >> 12 lost per frame; gravity 0x1E swinging, 3 cast (fish.c:2493, :3871,
## :3897).
const DRAG := 300
const GRAVITY_SWING := 0x1E
const GRAVITY_CAST := 3
## The release: power = frames + 5 → speed remap(power, 0, 0x14, 0x64, 0xC8 / 0x190), pitched
## −0xC8 (fish.c:3893-3904). ○ sets 0x14 frames.
const POWER_FRAMES := 0x14
const POWER_EXTRA := 5
const SPEED_MIN := 0x64
const SPEED_OLD_ROD := 0xC8
const SPEED_AMAZING_ROD := 0x190
const CAST_PITCH := -0xC8
## The bait sprite hangs 0x64 below the bobber (fish.c:2207).
const BAIT_HANG := 0x64
## Turning: 0x40 per frame (fish.c:3804).
const TURN_STEP := 0x40
## The snag: from frame 0x1F, every 20 frames, customRandom(1, 0x2710) < 0x3E9 (fish.c:3992).
const SNAG_FROM := 0x1F
const SNAG_EVERY := 20
const SNAG_ROLL := 0x2710
const SNAG_BELOW := 0x3E9
## The catch flies to the tip at 0x28 per frame (fish.c:4210).
const CATCH_STEP := 0x28
## The message frame of the line-cut / hook-lost states (fish.c:4342).
const MESSAGE_FRAME := 0xA

# --- Hooked fish (fish.c:3105-3442) -------------------------------------------------------------
const HOOK_NIBBLE := 0xA
const HOOK_TAKEN := 0x14
const HOOK_STRUGGLE := 0x28
const HOOK_PULL := 0x32
const HOOK_ESCAPE := 0x5A
const HOOK_SEADRAMON := 0x64
## FISH_tickHookedFish's modes.
const HOOKED_TICK := 0
const HOOKED_ESCAPE := 0xF
const HOOKED_GRAB := 0x10
const HOOKED_GONE := 0x11
const HOOKED_REEL := 0x12
## The hooked fish's headings: away from the tamer ±0x384; a probe 0x12C ahead, 30 tries.
const STRUGGLE_SPREAD := 0x384
const PROBE_AHEAD := 0x12C
const PROBE_TRIES := 0x1E
## Big fish from size 0x96 (fish.c:3138).
const BIG_SIZE := 0x96
## FISH_REEL_TARGET: never written (fish.c:827), the world origin.
const REEL_TARGET := Vector3i.ZERO
const REEL_NEAR := 0x32

# --- Tension (fish.c:2017-2117) -----------------------------------------------------------------
const LIMIT_OLD_ROD := 0x1388
const LIMIT_AMAZING_ROD := 0x2710

# --- Messages (text/fish/fish.yaml) --------------------------------------------------------------
const TEXT_TOOK_BAIT := "FISH_STR_THEY_TOOK_MY_BAIT"
const TEXT_TOO_LATE := "FISH_STR_TOO_LATE"
const TEXT_GOT_BAIT := "FISH_STR_THEY_GOT_MY_BAIT"
const TEXT_TOO_FAST := "FISH_STR_TOO_FAST"
const TEXT_STILL_BAIT := "FISH_STR_BUT_I_STILL_GOT_MY_BAIT"
const TEXT_HOOKED := "MAIN_D_801349D8"
const TEXT_GREAT := "FISH_FMT_GREAT_TOTAL_LENGTH_M_CM"
const TEXT_M_CM := "FISH_FMT_TOTAL_LENGTH_M_CM"
const TEXT_CM := "FISH_FMT_TOTAL_LENGTH_CM"
const TEXT_GOT_ONE := "FISH_STR_I_GOT_ONE"
const TEXT_LET_GO := "FISH_STR_IT_LOOKS_SAD_LET_IT_GO"
const TEXT_LINE_CUT := "FISH_STR_MY_LINE_GOT_CUT"
const TEXT_GAUGE := "FISH_STR_PAY_ATTENTION_TO_TENSION_GAUGE"
const TEXT_CALM := "FISH_STR_AND_BE_MORE_CALM"
const TEXT_HOOK_LOST := "FISH_STR_MY_HOOK_GOT_LOST"
const TEXT_HUH := "FISH_STR_HUH_I_WONDER_IF_SOMETHING"
const TEXT_STUCK := "FISH_STR_GOT_STUCK_IT_GOT_STUCK"
const TEXT_BAG_FULL := "FISH_STR_MY_BAG_WAS_SO_FULL_I"
const TEXT_NOT_CARRY := "FISH_STR_NOT_CARRY_IT"
const TEXT_IT_STUCK := "FISH_STR_IT_GOT_STUCK"

## FISH_tamerTick's results.
const TICK_FISHING := 0
const TICK_ENDED := 1
const TICK_SEADRAMON := 2

var fishing: Fishing
var world: FishingWorld
var pad: Pad
var text_box := FishingTextBox.new()
var bait_menu := FishingBaitMenu.new()
## GameData.fishing()["snagged_items"]: {item {id}, roll_up_to}.
var snag_table: Array = []

# FishingRod (include/dw/fish.h)
var display_rod := false
var state := STATE_NONE
var frames := 0
var item_slot := 0
var bait := -1
var throw_power := 0
var item_taken := false
## swimmerType: the rod, 1 old, 2 amazing.
var rod_type := 2
var display_swimmer := false
var line_start := Vector3i.ZERO
var line_start_mirror := Vector3i.ZERO
var display_line := false
var pressed_frames := 0

# FishingSwimmer: the bobber.
var swimmer_pos := Vector3i.ZERO
var swimmer_state := 3
var swimmer_timer := 0
var swimmer_sprite := 0
var swimmer_mode := MODE_STILL
var swimmer_vel := Vector3i.ZERO
var swimmer_dist := 0
var swimmer_gravity := 0

# FishingItem: the bait (or catch) sprite.
var item_shown := false
var item_pos := Vector3i.ZERO
var item_sprite := 0

# HookedFish.
var hooked := Fishing.Fish.new()
var nibble_time := 0
var catching_time := 0
var anim_mode := 0
var power_left := 0
var power_max := 0
var strike_timer := 0
var escaped := false

# FishingTension.
var tension_display := false
var tension_level := 0
var tension_frames_at_limit := 0
var tension_limit := LIMIT_AMAZING_ROD
var tension_color := Color8(0xFF, 0xFF, 0xFF)

## catchComplete: Seadramon reached the reel target.
var catch_complete := false
## FISH_RECORD_SIZE[8] (main/fish.c:17): the longest per kind (not saved, never shown).
var records: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
## MAIN_D_801351DC: the saved view centre and the camera-control flag (fish.c:4673-4709).
var saved_scroll := Vector2i.ZERO
var camera_control := false
## FISH_ROD_SEGMENT_MATRIX[5] / _POS[5]: the rod's segments for the view.
var segment_matrices: Array[PackedInt32Array] = []
var segment_positions: Array[Vector3i] = []
## FISH_D_8007A5BC[5]: the segments' bends (1-3 set each frame).
var _bends: Array[Vector3i] = [Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO]


func _init() -> void:
	for i in ROD_SEGMENTS.size():
		segment_matrices.append(PsxMath.identity())
		segment_positions.append(Vector3i.ZERO)


## Hooks the rod into the world (F2's fields it feeds).
func setup(fishing_data: Fishing, world_impl: FishingWorld, game_pad: Pad, snags: Array) -> void:
	fishing = fishing_data
	world = world_impl
	pad = game_pad
	snag_table = snags
	text_box.play_sound = world.play_sound
	bait_menu.play_sound = world.play_sound
	fishing.update_rod_pose = update_rod_pose
	fishing.tick_hooked = tick_hooked
	reset()


## FISH_init's rod parts (fish.c:4625-4632).
func reset() -> void:
	bait_menu.shown = false
	bait_menu.box_id = -1
	bait_menu.last_row = -1
	text_box.box_id = -1
	text_box.shown = false
	reset_tension()
	item_shown = false
	_reset_bobber()
	state = STATE_NONE
	display_rod = false
	display_line = false
	display_swimmer = false
	hooked.active = false
	catch_complete = false
	_sync()


## isFishing (main/fish.c:96).
func is_fishing() -> bool:
	return state != STATE_NONE


## FISH_loadFishing (fish.c:4588): the menu's Fishing (initializeFishing).
func load_fishing() -> void:
	if display_rod:
		end_fishing()
	world.set_camera_follow(false)
	_enable_camera_control()
	state = STATE_PAN_TO_TAMER
	display_rod = true
	display_swimmer = false
	display_line = false
	_reset_bobber()
	tick_hooked(HOOKED_ESCAPE)
	rod_type = world.best_rod()
	if rod_type != 1:
		rod_type = 2


## FISH_endFishing (fish.c:4569).
func end_fishing() -> void:
	if display_rod:
		_apply_saved_scroll()
		world.set_camera_follow(true)
		world.start_animation(ANIM_IDLE)
		state = STATE_NONE
		display_line = false
		display_rod = false
	if bait_menu.shown:
		bait_menu.close()
	text_box.shutdown()
	reset_tension()
	item_shown = false
	_reset_bobber()
	_sync()


## FISH_tamerTick (fish.c:4653): TICK_ENDED when the rod is put away (the host sets tamer state 0
## and starts game time), TICK_SEADRAMON when Seadramon is landed (tamerTickFishing then disables
## fishing and calls script section 0x4E4).
func tamer_tick() -> int:
	tick_rod()
	if not is_fishing():
		return TICK_ENDED
	if catch_complete:
		tick_hooked(HOOKED_GONE)
		end_fishing()
		return TICK_SEADRAMON
	return TICK_FISHING


# --- FISH_tickRod (fish.c:3688) ------------------------------------------------------------------

func tick_rod() -> void:
	if text_box.is_visible():
		_scroll_view_to_target()
		return
	match state:
		STATE_PAN_TO_TAMER:
			if not _pan_to_tamer(0x10):
				_set_state(STATE_BAIT_MENU)
		STATE_BAIT_MENU:
			_state_bait_menu()
		STATE_CHOOSE:
			_turn()
			if not world.animation_playing():
				display_swimmer = true
				_cast()
		STATE_PAN_TO_BOBBER:
			if not _pan_to(0x10, swimmer_pos, 0x28, 0x1E):
				_set_state(STATE_AIM)
		STATE_AIM:
			_state_aim()
		STATE_THROWING:
			_state_throwing()
		STATE_FLYING:
			_state_flying()
		STATE_FLOATING:
			_state_floating()
		STATE_BITE:
			_state_bite()
		STATE_REELING:
			_state_reeling()
		STATE_CATCH:
			_state_catch()
		STATE_END:
			if not _pan_to_tamer(0x10):
				end_fishing()
		STATE_LINE_CUT:
			if frames == MESSAGE_FRAME:
				world.play_sound(8, 0xA)
				_show_text([_t(TEXT_LINE_CUT), _t(TEXT_GAUGE), _t(TEXT_CALM)], swimmer_pos)
				_set_state(STATE_END)
		STATE_HOOK_LOST:
			if frames == MESSAGE_FRAME:
				world.play_sound(8, 0xA)
				_show_text([_t(TEXT_HOOK_LOST), _t(TEXT_GAUGE), _t(TEXT_CALM)], swimmer_pos)
				_splash()
		STATE_SNAG:
			_state_snag()
		STATE_SEADRAMON:
			if not _pan_to_tamer(0x10):
				if PsxMath.get_distance(REEL_TARGET.x - hooked.pos.x, 0, REEL_TARGET.z - hooked.pos.z) < REEL_NEAR:
					catch_complete = true
	frames += 1
	tick_bobber_physics()
	_sync()


func _set_state(s: int) -> void:
	state = s
	frames = -1


func _pressed() -> int:
	return pad.polled & ~pad.polled_previous


func _released() -> int:
	return pad.polled_previous & ~pad.polled


## ← / → turn the tamer 0x40 a frame (fish.c:3803-3809).
func _turn() -> void:
	var yaw := world.tamer_yaw()
	if pad.polled & Pad.LEFT:
		yaw -= TURN_STEP
	if pad.polled & Pad.RIGHT:
		yaw += TURN_STEP
	world.set_tamer_yaw(yaw & 0xFFF)


## giveUp (fish.c:3760).
func _give_up() -> void:
	if not _has_food():
		_set_state(STATE_END)
		return
	world.start_animation(ANIM_IDLE)
	display_swimmer = false
	item_shown = false
	_reset_bobber()
	display_line = false
	swimmer_mode = MODE_STILL
	_set_state(STATE_PAN_TO_TAMER)


func _state_bait_menu() -> void:
	if frames == 0:
		bait_menu.open(world.inventory_types(), world.is_food, _tamer_screen())
		return
	if bait_menu.is_visible():
		return
	if bait_menu.selected == -1:
		_set_state(STATE_END)
		return
	item_slot = bait_menu.selected
	bait = int(world.inventory_types()[item_slot])
	item_taken = false
	display_swimmer = false
	world.start_animation(ANIM_TAKE_ROD)
	_set_state(STATE_CHOOSE)


## cast (fish.c:3815).
func _cast() -> void:
	swimmer_pos = rod_tip()
	if item_taken:
		_give_up()
		return
	world.start_animation(ANIM_HOLD)
	bobber_command(CMD_AT_TIP)
	swimmer_mode = MODE_AT_TIP
	display_line = true
	_show_bait_sprite(null, bait)
	move_bait_to_rod_tip(0)
	_set_state(STATE_PAN_TO_BOBBER)


func _state_aim() -> void:
	move_bait_to_rod_tip(0)
	if pad.polled & Pad.ALT:
		_pan_with_dpad()
		return
	if _pressed() & Pad.CONFIRM:
		world.start_animation(ANIM_WIND_UP)
		swimmer_mode = MODE_SWING
		swimmer_vel = Vector3i.ZERO
		swimmer_dist = PsxMath.get_distance(swimmer_pos.x - line_start.x, swimmer_pos.y - line_start.y, swimmer_pos.z - line_start.z)
		swimmer_gravity = GRAVITY_SWING
		_set_state(STATE_THROWING)
		return
	if _pressed() & Pad.CANCEL:
		item_shown = false
		_set_state(STATE_END)
		return
	_turn()
	_pan_to(0x10, swimmer_pos, 0x28, 0x1E)


func _state_throwing() -> void:
	if _pressed() & Pad.CONFIRM:
		_release()
		return
	if _pressed() & Pad.ALT:
		frames = POWER_FRAMES
		_release()
		return
	_pan_to(0x10, swimmer_pos, 0x28, 0x1E)
	if not world.animation_playing():
		_cast()


## release (fish.c:3890).
func _release() -> void:
	world.start_animation(ANIM_CAST)
	update_rod_pose()
	throw_power = frames + POWER_EXTRA
	swimmer_mode = MODE_FLYING
	swimmer_pos = line_start
	swimmer_dist = 0
	swimmer_gravity = GRAVITY_CAST
	var speed := remap_clamped(throw_power, 0, POWER_FRAMES, SPEED_MIN, SPEED_OLD_ROD if rod_type == 1 else SPEED_AMAZING_ROD)
	var rot := Vector3i(0, PsxMath.s16(world.tamer_yaw() + 0x800), CAST_PITCH)
	swimmer_vel = PsxMath.apply_matrix_lv(PsxMath.rot_matrix_yxz(rot), Vector3i(0, 0, speed))
	world.play_sound(8, 0)
	_set_state(STATE_FLYING)


func _state_flying() -> void:
	_pan_to(0, swimmer_pos, 0x28, 0x1E)
	if pad.polled & Pad.ALT:
		_pan_with_dpad()
	else:
		_pan_to(0x10, swimmer_pos, 0x28, 0x1E)
	if _pressed() & Pad.CONFIRM:
		swimmer_vel.x = 0
		swimmer_vel.z = 0
	if swimmer_pos.y < 0:
		if _pressed() & Pad.CANCEL:
			_cast()
		return
	_splash()


## splash (fish.c:3929).
func _splash() -> void:
	item_shown = false
	swimmer_pos.y = 0
	if not _over_water(swimmer_pos):
		_cast()
		return
	world.play_sound(8, 2)
	world.set_animation_loop_count(1)
	bobber_command(CMD_LAND)
	swimmer_mode = MODE_STILL
	_set_state(STATE_FLOATING)


## The bobber's point projects inside the background, on water.
func _over_water(pos: Vector3i) -> bool:
	var s = fishing.camera.project(pos)
	return s != null and fishing.camera.is_in_background(s.x, s.y) and fishing.is_water(s.x, s.y)


## The rod tip's forward motion since last frame, along the line (fish.c:3971-3985, :4119-4143).
func _reel_step(scale_num: int, minus: int, halve: bool) -> void:
	var rot := PsxMath.to_euler_angles(line_start.x - swimmer_pos.x, 0, line_start.z - swimmer_pos.z)
	var m := PsxMath.rot_matrix_yxz(rot)
	var d := line_start - line_start_mirror
	var lv := PsxMath.apply_matrix_lv(PsxMath.transpose(m), d)
	lv.x = 0
	lv.y = 0
	lv.z = PsxMath.div(lv.z * scale_num, 100) - minus
	if lv.z > 0:
		d = PsxMath.apply_matrix_lv(m, lv)
		if halve:
			d = Vector3i(PsxMath.div(d.x, 2), PsxMath.div(d.y, 2), PsxMath.div(d.z, 2))
		swimmer_pos += d


func _state_floating() -> void:
	if pad.polled & Pad.CONFIRM:
		if _pressed() & Pad.CONFIRM or not world.animation_playing():
			world.start_animation(ANIM_REEL_IN)
		_reel_step(100, 0, false)
		# nibbleCheck: the snag (fish.c:3990-4006).
		if item_taken and frames >= SNAG_FROM and frames % SNAG_EVERY == 0 and Rng.custom_random(1, SNAG_ROLL) < SNAG_BELOW:
			var r := Rng.custom_random(0, 0x63)
			var n := 0
			while n < snag_table.size():
				if r <= int(snag_table[n]["roll_up_to"]):
					break
				n += 1
			n = mini(n, snag_table.size() - 1)
			bait = int(snag_table[n]["item"]["id"])
			world.play_sound(8, 9)
			_show_text([_t(TEXT_HUH), _t(TEXT_STUCK)], swimmer_pos)
			_set_state(STATE_SNAG)
			return
	else:
		if _released() & Pad.CONFIRM or not world.animation_playing():
			world.start_animation(ANIM_FLOAT)
		if not item_taken:
			var f := fishing.find_fish_to_bite(swimmer_pos, bait, world.bite_chance)
			if f != null:
				hook_fish(f)
				_set_state(STATE_BITE)
				return
	# visibleCheck (fish.c:4030).
	if not _over_water(swimmer_pos) or is_within_cast_range(swimmer_pos, 0):
		_cast()
		return
	if pad.polled & Pad.ALT:
		_pan_with_dpad()
		return
	_pan_to(0x10, swimmer_pos, 0x28, 0x1E)
	if _pressed() & Pad.CANCEL:
		_cast()


func _state_bite() -> void:
	_pan_to(0x10, swimmer_pos, 0x28, 0x1E)
	if escaped or not hooked.active:
		_show_text([_t(TEXT_TOOK_BAIT)], swimmer_pos)
		_splash()
		return
	var pressed := _pressed()
	if pressed & Pad.CONFIRM:
		if not try_strike():
			if item_taken:
				_show_text([_t(TEXT_TOO_LATE), _t(TEXT_GOT_BAIT)], swimmer_pos)
			else:
				_show_text([_t(TEXT_TOO_FAST), _t(TEXT_STILL_BAIT)], swimmer_pos)
			_splash()
			return
		_show_text([_t(TEXT_HOOKED)], swimmer_pos)
		begin_tension()
		pressed_frames = 0
		_set_state(STATE_REELING)
		return
	if not pressed & Pad.CANCEL:
		return
	tick_hooked(HOOKED_ESCAPE)
	_splash()


func _state_reeling() -> void:
	if pad.polled & Pad.CONFIRM:
		if pressed_frames < 0:
			pressed_frames = 0
		pressed_frames += 1
		if _pressed() & Pad.CONFIRM or not world.animation_playing():
			world.start_animation(ANIM_REEL_FISH)
		_reel_step(200, remap_clamped(hooked.size, 0x32, 0x12C, 1, 0xA), true)
	else:
		if pressed_frames > 0:
			pressed_frames = 0
		pressed_frames -= 1
		if _released() & Pad.CONFIRM:
			world.start_animation(ANIM_HOLD_FISH)
	var s = fishing.camera.project(swimmer_pos)
	if s != null and fishing.camera.is_in_background(s.x, s.y) and not fishing.is_water(s.x, s.y):
		_landed()
		return
	if is_within_cast_range(swimmer_pos, hooked.size):
		_landed()
		return
	match update_tension():
		1:
			tick_hooked(HOOKED_ESCAPE)
			reset_tension()
			world.play_sound(8, 9)
			display_line = false
			bobber_command(CMD_GONE)
			_set_state(STATE_LINE_CUT)
			return
		2:
			tick_hooked(HOOKED_ESCAPE)
			reset_tension()
			world.play_sound(8, 9)
			display_line = true
			bobber_command(CMD_GONE)
			_set_state(STATE_HOOK_LOST)
			return
	if _pressed() & Pad.CANCEL:
		tick_hooked(HOOKED_ESCAPE)
		reset_tension()
		_splash()
		return
	if pad.polled & Pad.ALT:
		_pan_with_dpad()
		return
	_pan_to(0x10, swimmer_pos, 0x28, 0x1E)


## landed (fish.c:4192).
func _landed() -> void:
	reset_tension()
	if hooked.kind == Fishing.SEADRAMON:
		tick_hooked(HOOKED_REEL)
		_set_state(STATE_SEADRAMON)
		return
	tick_hooked(HOOKED_GONE)
	bait = _fish_item(hooked.kind)
	world.play_sound(8, 7)
	_show_bait_sprite(swimmer_pos, bait)
	fishing.spawn_ripple(0, swimmer_pos, 1, 0, int(fishing.map.get("bait_radius", 0)) * 10)
	swimmer_mode = MODE_STILL
	_set_state(STATE_CATCH)


## The item of a fish kind: FISH_KIND_INFO[kind].unk0 (the C adds 0x3E, fish.c:4199).
func _fish_item(kind: int) -> int:
	var k: Dictionary = fishing.kinds[kind] if kind >= 0 and kind < fishing.kinds.size() else {}
	var item = k.get("item")
	return int(item["id"]) if item is Dictionary else kind + 0x3E


func _state_catch() -> void:
	var moving := move_bait_to_rod_tip(CATCH_STEP)
	swimmer_pos = item_pos
	var panning := _pan_to(0x20, swimmer_pos, 0x28, 0x1E)
	if moving or panning:
		return
	_show_bait_sprite(null, bait)
	move_bait_to_rod_tip(0)
	var message := catch_message(hooked.size)
	if hooked.kind >= 0 and hooked.kind < records.size() and hooked.size > records[hooked.kind]:
		records[hooked.kind] = hooked.size
	world.add_fish_caught()
	world.play_sound(8, 8)
	if not world.give_item(bait, 1):
		_show_text([world.item_name(bait), message, _t(TEXT_GOT_ONE), _t(TEXT_LET_GO)], item_pos)
	else:
		_show_text([world.item_name(bait), message, _t(TEXT_GOT_ONE)], item_pos)
	_finish()


## The length line (fish.c:4278-4291). Port-only fix (specs/fishing.md §2.10): from 200 the US C
## divides by 200; the port shows metres and centimetres as from 100.
func catch_message(size: int) -> String:
	if size >= 0xC8:
		return _format(_t(TEXT_GREAT), [size / 100, size % 100])
	if size >= 0x64:
		return _format(_t(TEXT_M_CM), [size / 100, size % 100])
	return _format(_t(TEXT_CM), [size % 100])


## sprintf's %d, one value per marker.
static func _format(fmt: String, values: Array) -> String:
	var out := fmt
	for v in values:
		var i := out.find("%d")
		if i < 0:
			break
		out = out.substr(0, i) + str(v) + out.substr(i + 2)
	return out


## finish (fish.c:4311).
func _finish() -> void:
	world.start_animation(ANIM_HOLD)
	bobber_command(CMD_AT_TIP)
	swimmer_mode = MODE_AT_TIP
	display_line = true
	world.set_tamer_yaw(0)
	_show_bait_sprite(null, bait)
	move_bait_to_rod_tip(0)
	_set_state(STATE_END)


func _state_snag() -> void:
	_show_bait_sprite(null, bait)
	move_bait_to_rod_tip(0)
	world.play_sound(8, 8)
	if not world.give_item(bait, 1):
		_show_text([world.item_name(bait), _t(TEXT_BAG_FULL), _t(TEXT_NOT_CARRY)], item_pos)
	else:
		_show_text([world.item_name(bait), _t(TEXT_IT_STUCK)], item_pos)
	_finish()


# --- The bobber (fish.c:2288-2555) --------------------------------------------------------------

func _reset_bobber() -> void:
	swimmer_state = 3
	swimmer_sprite = 0
	swimmer_timer = 0
	swimmer_mode = MODE_STILL


## FISH_getRodTipPos (fish.c:2306).
func rod_tip() -> Vector3i:
	var bone := _bone(BONE_TIP)
	return bone[0] + PsxMath.apply_matrix_lv(bone[1], TIP_OFFSET) + TIP_LIFT


## [position, rotation matrix] of a bone, as FISH_getBoneTransform then RotMatrixYXZ give them
## (the C goes through matrixToEuler2 and back).
func _bone(index: int) -> Array:
	var m := world.bone_matrix(index)
	var rot := PsxMath.matrix_to_euler2(m)
	return [PsxMath.translation(m), PsxMath.rot_matrix_yxz(rot), rot]


## FISH_bobberCommand (fish.c:2321), commands other than the draw (1).
func bobber_command(command: int) -> void:
	match command:
		CMD_NIBBLE:
			world.play_sound(8, 3)
			fishing.spawn_ripple(-3, swimmer_pos, 0, 0, 0x1000)
			_bobber_state(10)
		CMD_TAKEN, CMD_BIG_NIBBLE:
			# Command 12 runs command 11's code (the snap12 label, fish.c:2416).
			world.play_sound(8, 4)
			fishing.spawn_ripple(-4, swimmer_pos, 0, 0, 0x1000)
			_bobber_state(11)
		CMD_AT_TIP:
			swimmer_pos = rod_tip()
			swimmer_sprite = 1
			_bobber_state(4)
		5, 6:
			swimmer_sprite = 1
			_bobber_state(command)
		CMD_LAND:
			fishing.spawn_ripple(-1, swimmer_pos, 0x64, 0, 0x1000)
			_bobber_state(7)
		CMD_GONE:
			_bobber_state(14)
		CMD_TICK:
			match swimmer_state:
				3:
					swimmer_sprite = 0
				7:
					swimmer_sprite = SEQ_LAND[clampi(swimmer_timer, 0, 7)]
					if swimmer_sprite <= -1:
						_float()
				8:
					if Rng.custom_random(1, 2) == 1:
						swimmer_pos.x += Rng.custom_random(-1, 1)
						swimmer_pos.z += Rng.custom_random(-1, 1)
					if Rng.custom_random(1, 0x3C) == 1:
						fishing.spawn_ripple(-2, swimmer_pos, 0, 0, 0x1000)
						_bobber_state(9)
				9:
					swimmer_sprite = SEQ_BOB[clampi(swimmer_timer / 3, 0, 2)]
					if swimmer_sprite == -1:
						_float()
				10:
					swimmer_sprite = SEQ_NIBBLE[clampi(swimmer_timer, 0, 4)]
					if swimmer_sprite == -1:
						_float()
				12:
					swimmer_sprite = SEQ_UNUSED[clampi(swimmer_timer, 0, 0x11)]
					if swimmer_sprite == -1:
						_float()
				11:
					swimmer_sprite = SEQ_TAKEN[clampi(swimmer_timer, 0, 4)]
					if swimmer_sprite == -1:
						swimmer_state = 13
						swimmer_timer = -1
				14:
					swimmer_sprite = SEQ_GONE[clampi(swimmer_timer, 0, 5)]
					if swimmer_sprite == -1:
						_float()
		_:
			return
	swimmer_timer += 1


func _bobber_state(s: int) -> void:
	swimmer_state = s
	swimmer_timer = -1


## setSprite3: floating (state 8).
func _float() -> void:
	swimmer_sprite = 3
	_bobber_state(8)


## FISH_tickBobberPhysics (fish.c:2473).
func tick_bobber_physics() -> void:
	bobber_command(CMD_TICK)
	match swimmer_mode:
		MODE_AT_TIP:
			swimmer_pos = rod_tip()
		MODE_SWING, MODE_FLYING, 4:
			var old := swimmer_pos
			swimmer_vel = Vector3i(_drag(swimmer_vel.x), _drag(swimmer_vel.y), _drag(swimmer_vel.z))
			swimmer_vel.y += swimmer_gravity
			if swimmer_dist != 0 and swimmer_dist < _line_length():
				swimmer_pos = _onto_line()
				swimmer_vel += swimmer_pos - old
			swimmer_pos += swimmer_vel
			if swimmer_dist != 0 and swimmer_dist < _line_length():
				swimmer_pos = _onto_line()
			var s = fishing.camera.project(Vector3i(swimmer_pos.x, 0, swimmer_pos.z))
			if s == null or not fishing.camera.is_in_background(s.x, s.y):
				swimmer_pos.x = old.x
				swimmer_pos.z = old.z
				swimmer_vel.x = 0
				swimmer_vel.z = 0
			_tick_bait_sprite()


## v -= v × 300 >> 12, at least 1 towards 0.
static func _drag(v: int) -> int:
	var d := (v * DRAG) >> 12
	if d != 0:
		return v - d
	return v - signi(v)


func _line_length() -> int:
	return PsxMath.get_distance(swimmer_pos.x - line_start.x, swimmer_pos.y - line_start.y, swimmer_pos.z - line_start.z)


## The bobber pulled onto the sphere of radius dist around the line start.
func _onto_line() -> Vector3i:
	var rot := PsxMath.to_euler_angles(swimmer_pos.x - line_start.x, swimmer_pos.y - line_start.y, swimmer_pos.z - line_start.z)
	return Fishing.forward(rot, swimmer_dist) + line_start


# --- The bait sprite (fish.c:2119-2242) ---------------------------------------------------------

func _show_bait_sprite(pos: Variant, sprite: int) -> void:
	item_shown = true
	item_sprite = sprite
	if pos != null:
		item_pos = pos


## FISH_moveBaitToRodTip (fish.c:2147): true while still moving (max_step a frame); 0 jumps there.
func move_bait_to_rod_tip(max_step: int) -> bool:
	var bone := _bone(BONE_TIP)
	var target: Vector3i = bone[0] + PsxMath.apply_matrix_lv(bone[1], BAIT_OFFSET) + BAIT_LIFT
	var d := target - item_pos
	var dist := 0 if max_step == 0 else PsxMath.get_distance(d.x, d.y, d.z)
	if max_step != 0 and max_step < dist:
		item_pos += Fishing.forward(PsxMath.to_euler_angles(d.x, d.y, d.z), max_step)
		return true
	item_pos = target
	return false


## FISH_tickBaitSprite (fish.c:2185).
func _tick_bait_sprite() -> void:
	if not item_shown:
		return
	var prev := item_pos
	var rot := PsxMath.to_euler_angles(swimmer_pos.x - line_start.x, swimmer_pos.y - line_start.y, swimmer_pos.z - line_start.z)
	item_pos = Fishing.forward(rot, BAIT_HANG) + swimmer_pos
	if prev.y >= 0 or item_pos.y < 0 or state != STATE_FLYING:
		return
	if not _over_water(Vector3i(item_pos.x, 0, item_pos.z)):
		return
	fishing.spawn_ripple(0, item_pos, 0x64, 0, int(fishing.map.get("bait_radius", 0)) * 75)


# --- The hooked fish (fish.c:3098-3457) ---------------------------------------------------------

## FISH_hookFish (fish.c:3105).
func hook_fish(f: Fishing.Fish) -> void:
	fishing.clear_markers()
	hooked.copy_from(f)
	f.active = false
	fishing.fish_count -= 1
	hooked.rotation = PsxMath.to_euler_angles(swimmer_pos.x - hooked.pos.x, 0, swimmer_pos.z - hooked.pos.z)
	hooked.state = HOOK_NIBBLE
	hooked.frames_on_state = 0
	hooked.anim_phase = 0
	anim_mode = 0
	strike_timer = 0
	if hooked.size < BIG_SIZE:
		nibble_time = Rng.custom_random(0x14, 0x28)
		catching_time = 0x1E
	else:
		nibble_time = Rng.custom_random(0x28, 0x3C)
		catching_time = 0x3C
	power_left = hooked.size + 0x96
	power_max = power_left + 0x64
	escaped = false
	_sync()


## FISH_tryStrike (fish.c:3444): a hit in the first half of catchingTime after the bait was taken.
func try_strike() -> bool:
	if hooked.state == HOOK_TAKEN and hooked.frames_on_state < catching_time / 2:
		strike_timer = 0x14
		tick_hooked(HOOKED_GRAB)
		return true
	tick_hooked(HOOKED_ESCAPE)
	return false


## FISH_tickHookedFish (fish.c:3151).
func tick_hooked(mode: int) -> void:
	if not hooked.active:
		return
	if text_box.is_visible():
		return
	match mode:
		HOOKED_GRAB:
			_grab()
			_hooked_frame()
		HOOKED_ESCAPE:
			_escape()
			_hooked_frame()
		HOOKED_REEL:
			hooked.state = HOOK_SEADRAMON
			hooked.frames_on_state = -1
			_hooked_frame()
		HOOKED_GONE:
			hooked.active = false
		HOOKED_TICK:
			_tick_hooked_state()
			_hooked_frame()
	if hooked.kind == Fishing.SEADRAMON:
		fishing.push_seadramon_segment(hooked.rotation)
	_sync()


func _hooked_frame() -> void:
	hooked.frames_on_state += 1
	hooked.anim_phase += 1
	if strike_timer != 0:
		strike_timer -= 1


## Up to 10 a frame towards the bobber, when 4 or more away (fish.c:3195-3212).
func _towards_bobber() -> void:
	var v := Vector3i(swimmer_pos.x - hooked.pos.x, 0, swimmer_pos.z - hooked.pos.z)
	var d := PsxMath.get_distance(v.x, v.y, v.z)
	if d >= 4:
		hooked.rotation = PsxMath.to_euler_angles(v.x, v.y, v.z)
		d = 1 if d <= 0 else mini(d, 0xA)
		hooked.pos += Fishing.forward(hooked.rotation, d)


func _tick_hooked_state() -> void:
	match hooked.state:
		HOOK_NIBBLE:
			if hooked.frames_on_state != nibble_time:
				if hooked.size < BIG_SIZE:
					if Rng.custom_random(1, 0x14) == 1:
						if nibble_time - hooked.frames_on_state >= 0x14:
							bobber_command(CMD_NIBBLE)
				else:
					if Rng.custom_random(1, 0x14) == 1:
						bobber_command(CMD_BIG_NIBBLE)
				_towards_bobber()
			else:
				bobber_command(CMD_TAKEN)
				item_taken = true
				var types := world.inventory_types()
				if item_slot >= 0 and item_slot < types.size():
					world.remove_item(int(types[item_slot]), 1)
				hooked.state = HOOK_TAKEN
				hooked.frames_on_state = -1
		HOOK_TAKEN:
			_towards_bobber()
			if hooked.frames_on_state >= catching_time:
				_escape()
		HOOK_STRUGGLE:
			_tick_struggle()
		HOOK_PULL:
			_tick_pull()
		HOOK_ESCAPE:
			hooked.pos += Fishing.forward(hooked.rotation, 0x28)
			hooked.transparency = clampi(hooked.transparency - 8, 0, 0x80)
			if hooked.transparency == 0:
				hooked.active = false
		HOOK_SEADRAMON:
			var d := clampi(PsxMath.get_distance(REEL_TARGET.x - hooked.pos.x, 0, REEL_TARGET.z - hooked.pos.z), 0, 0x32)
			hooked.rotation = PsxMath.to_euler_angles(REEL_TARGET.x - hooked.pos.x, 0, REEL_TARGET.z - hooked.pos.z)
			hooked.pos += Fishing.forward(hooked.rotation, d)
			fishing.spawn_ripple(0, hooked.pos, 0x2BC, 1, (hooked.size << 12) / 120)
			if Rng.custom_random(1, 0xA) < 6:
				world.play_sound(8, 6)


## grabbed (fish.c:3246).
func _grab() -> void:
	anim_mode = 1
	hooked.state = HOOK_STRUGGLE
	hooked.frames_on_state = -1


## escape (fish.c:3384).
func _escape() -> void:
	escaped = true
	bobber_command(CMD_LAND)
	_face_away_from_tamer(0x800)
	hooked.state = HOOK_ESCAPE
	hooked.frames_on_state = -1


func _face_away_from_tamer(extra: int) -> void:
	var t := world.tamer_position()
	hooked.rotation = PsxMath.to_euler_angles(t.x - hooked.pos.x, 0, t.z - hooked.pos.z)
	hooked.rotation.y = PsxMath.s16(hooked.rotation.y + extra)


## The heading search: a point 0x12C ahead of the bobber must be water in the background, else a
## heading to a random point of the fish's spot; 30 tries (fish.c:3274-3293).
func _find_water_heading() -> void:
	for i in PROBE_TRIES:
		var probe := swimmer_pos + Fishing.forward(hooked.rotation, PROBE_AHEAD)
		if _over_water(probe):
			continue
		var p := fishing.random_point_in_spot(hooked.kind, Vector3i.ZERO)
		hooked.rotation = PsxMath.to_euler_angles(p.x - hooked.pos.x, 0, p.z - hooked.pos.z)


## The fish moves `step` and drags the bobber (fish.c:3295-3301).
func _drag_bobber(step: int) -> void:
	var probe := swimmer_pos + Fishing.forward(hooked.rotation, step)
	swimmer_pos = probe
	hooked.pos = probe


func _tick_struggle() -> void:
	if Rng.custom_random(0, 0xA) == 0:
		world.play_sound(8, 5)
	if Rng.custom_random(1, 0xA) == 1:
		_face_away_from_tamer(Rng.custom_random(-STRUGGLE_SPREAD, STRUGGLE_SPREAD) + 0x800)
	if Rng.custom_random(1, 4) == 1:
		fishing.spawn_ripple(0, hooked.pos, 0x2BC, hooked.size / 2, (hooked.size << 12) / 120)
		fishing.spawn_ripple(0, hooked.pos, 0x2BC, 0, hooked.size / 2)
	_find_water_heading()
	_drag_bobber(PsxMath.div(hooked.time_this_move, 0xF if power_left <= power_max / 10 else 8))
	# The rest test (fish.c:3302-3326).
	var roll := pressed_frames == -1 or (pressed_frames >= 0x3D and pressed_frames % 3 == 0)
	if not roll and Rng.custom_random(1, 0x14) >= 3:
		if state != STATE_REELING:
			_escape()
		return
	if Rng.custom_random(1, 0x1000) <= PsxMath.div(power_left << 12, power_max):
		_face_away_from_tamer(Rng.custom_random(-STRUGGLE_SPREAD, STRUGGLE_SPREAD) + 0x800)
		hooked.time_this_move = Rng.custom_random(0x14, 0x32)
		nibble_time = Rng.custom_random(9, 0x13)
		hooked.state = HOOK_PULL
		hooked.frames_on_state = -1
		return
	if state != STATE_REELING:
		_escape()


func _tick_pull() -> void:
	if hooked.frames_on_state % 2 == 0:
		power_left = clampi(power_left - 1, 0, power_max)
	if Rng.custom_random(0, 0xA) == 0:
		world.play_sound(8, 6)
	fishing.spawn_ripple(0, hooked.pos, 0x2BC, 1, (hooked.size << 12) / 120)
	_find_water_heading()
	_drag_bobber(hooked.time_this_move)
	if state != STATE_REELING:
		_escape()
		return
	if hooked.frames_on_state >= nibble_time:
		_grab()


# --- Tension (fish.c:2017-2117) -----------------------------------------------------------------

func reset_tension() -> void:
	tension_display = false
	tension_level = 0
	tension_frames_at_limit = 0
	tension_color = Color8(0xFF, 0xFF, 0xFF)


func begin_tension() -> void:
	reset_tension()
	tension_display = true
	tension_limit = LIMIT_OLD_ROD if rod_type == 1 else LIMIT_AMAZING_ROD


## FISH_updateTension (fish.c:2036): 1 the line snaps, 2 the hook comes out, else 0.
func update_tension() -> int:
	var n := (2 if pressed_frames > 0 else 0) + (1 if hooked.state == HOOK_PULL else 0)
	var size := hooked.size
	match n:
		0:
			tension_level += remap_clamped(size, 0x32, 0x12C, -0xA6, -0xA6)
		1:
			tension_level += remap_clamped(size, 0x32, 0x12C, 0x29, 0x53)
		2:
			tension_level += remap_clamped(size, 0x32, 0x12C, 0x47, 0x7D)
		3:
			tension_level += remap_clamped(size, 0x32, 0x12C, 0xA6, 0x1F4)
	var limit := tension_limit
	tension_level = clampi(tension_level, -limit, limit)
	var half := limit / 2
	var r := 0
	var g := 0
	var b := 0
	if tension_level >= half:
		r = remap_clamped(tension_level, half, limit, 0xFF, 0xFF)
		g = remap_clamped(tension_level, half, limit, 0xFF, 0)
		b = remap_clamped(tension_level, half, limit, 0, 0)
	elif tension_level >= 0:
		r = remap_clamped(tension_level, 0, half, 0xFF, 0xFF)
		g = remap_clamped(tension_level, 0, half, 0xFF, 0xFF)
		b = remap_clamped(tension_level, 0, half, 0xFF, 0)
	elif tension_level >= PsxMath.div(-limit, 2):
		r = remap_clamped(tension_level, PsxMath.div(-limit, 2), 0, 0, 0xFF)
		g = remap_clamped(tension_level, PsxMath.div(-limit, 2), 0, 0xFF, 0xFF)
		b = remap_clamped(tension_level, PsxMath.div(-limit, 2), 0, 0xFF, 0xFF)
	else:
		r = remap_clamped(tension_level, -limit, PsxMath.div(-limit, 2), 0, 0)
		g = remap_clamped(tension_level, -limit, PsxMath.div(-limit, 2), 0, 0xFF)
		b = remap_clamped(tension_level, -limit, PsxMath.div(-limit, 2), 0xFF, 0xFF)
	tension_color = Color8(r & 0xFF, g & 0xFF, b & 0xFF)
	if tension_level == -limit:
		return 2
	if tension_level == limit:
		var steps := 4 - remap_clamped(size, 0x32, 0x12C, 1, 3)
		tension_frames_at_limit += 1
		if tension_frames_at_limit == steps * 5:
			return 1
	else:
		tension_frames_at_limit = 0
	return 0


## The gauge's bars (FISH_drawTensionGauge): remap(level, -limit, limit, 0, 9).
func tension_bars() -> int:
	return remap_clamped(tension_level, -tension_limit, tension_limit, 0, 9)


## FISH_remapClamped (fish_model.c:61).
static func remap_clamped(x: int, x0: int, x1: int, y0: int, y1: int) -> int:
	if x1 == x0:
		return y0
	if x1 < x0:
		var t := x0
		x0 = x1
		x1 = t
	x = clampi(x, x0, x1)
	return y0 + PsxMath.div((y1 - y0) * (x - x0) + PsxMath.div(x1 - x0, 2), x1 - x0)


# --- The rod's pose (fish.c:3469) ---------------------------------------------------------------

## FISH_updateRodPose: the 5 segments from the hand, bent towards the bobber by the tension.
func update_rod_pose() -> void:
	var hand := _bone(BONE_HAND)
	var base := PsxMath.mul_matrix0(PsxMath.rot_matrix_yxz(ROD_BASE_ROT),
			PsxMath.rot_matrix_yxz(PsxMath.to_euler_angles(ROD_BASE_DIR.x, ROD_BASE_DIR.y, ROD_BASE_DIR.z)))
	var base_rot := PsxMath.matrix_to_euler2(base)
	var m := PsxMath.mul_matrix0(PsxMath.rot_matrix_yxz(hand[2]), PsxMath.rot_matrix_yxz(base_rot))
	var v0: Vector3i = hand[0] + PsxMath.apply_matrix_lv(m, ROD_BASE_OFFSET)
	var length := ROD_BEND
	if tension_display:
		length = PsxMath.div((tension_level + tension_limit) << 9, tension_limit * 2)
	var d := swimmer_pos - v0
	var lv := PsxMath.apply_matrix_lv(PsxMath.transpose(m), d)
	var e := PsxMath.to_euler_angles(lv.x, lv.y, lv.z)
	var ang := PsxMath.ratan2(lv.y, lv.x)
	var lim_x := PsxMath.s16((-(length * PsxMath.rsin(ang))) >> 12)
	var lim_y := PsxMath.s16((length * PsxMath.rcos(ang)) >> 12)
	# e = (e > 0) ? ((e < lim) ? e : lim) : ((e > lim) ? e : lim) (fish.c:3515-3516).
	e.x = (e.x if e.x < lim_x else lim_x) if e.x > 0 else (e.x if e.x > lim_x else lim_x)
	e.y = (e.y if e.y < lim_y else lim_y) if e.y > 0 else (e.y if e.y > lim_y else lim_y)
	for i in range(1, 4):
		_bends[i] = Vector3i(PsxMath.s16(e.x >> 2), PsxMath.s16(e.y >> 2), PsxMath.s16(e.z >> 2))
	for i in ROD_SEGMENTS.size():
		m = PsxMath.mul_matrix0(m, PsxMath.rot_matrix_yxz(_bends[i]))
		segment_positions[i] = v0
		var sm := m.duplicate()
		sm[9] = v0.x
		sm[10] = v0.y
		sm[11] = v0.z
		segment_matrices[i] = sm
		v0 += PsxMath.apply_matrix_lv(m, Vector3i(0, 0, ROD_SEGMENTS[i]))
	line_start_mirror = line_start
	line_start = segment_positions[4]


# --- The camera (fish.c:969-1053, :4673-4709) ---------------------------------------------------

## FISH_panCameraTo: true while the camera still had to move.
func _pan_to(radius: int, pos: Vector3i, max_dx: int, max_dy: int) -> bool:
	var cam := fishing.camera
	var s = cam.project(pos)
	if s == null:
		return false
	var cx := cam.view_x(0xA0)
	var cy := cam.view_y(0x78)
	var vx: int = s.x
	var vy: int = s.y
	if absi(vx - cx) <= max_dx:
		vx = cx
	else:
		vx += -max_dx if vx > cx else max_dx
	if absi(vy - cy) <= max_dy:
		vy = cy
	else:
		vy += -max_dy if vy > cy else max_dy
	vx = clampi(vx, cam.screen_left(0xA0), cam.screen_right(0xA0))
	vy = clampi(vy, cam.screen_top(0x78), cam.screen_bottom(0x78))
	if vx - cx == 0 and vy - cy == 0:
		return false
	if radius > 0 and PsxMath.get_distance(vx - cx, vy - cy, 0) >= radius:
		var ang := PsxMath.ratan2(vy - cy, vx - cx)
		vx = cx + ((radius * PsxMath.rcos(ang)) >> 12)
		vy = cy + ((radius * PsxMath.rsin(ang)) >> 12)
	_scroll_to(vx, vy)
	return true


func _pan_to_tamer(radius: int) -> bool:
	return _pan_to(radius, world.tamer_position(), 0, 0)


## FISH_panCameraWithDPad: 5 pixels a frame per held direction.
func _pan_with_dpad() -> bool:
	var cam := fishing.camera
	var x := cam.view_x(0xA0)
	var y := cam.view_y(0x78)
	if pad.polled & Pad.UP:
		y -= 5
	if pad.polled & Pad.DOWN:
		y += 5
	if pad.polled & Pad.LEFT:
		x -= 5
	if pad.polled & Pad.RIGHT:
		x += 5
	x = clampi(x, cam.screen_left(0xA0), cam.screen_right(0xA0))
	y = clampi(y, cam.screen_top(0x78), cam.screen_bottom(0x78))
	if x == cam.view_x(0xA0) and y == cam.view_y(0x78):
		return false
	_scroll_to(x, y)
	return true


## FISH_scrollCameraTo: only while camera control is on.
func _scroll_to(x: int, y: int) -> void:
	if not camera_control:
		return
	var cam := fishing.camera
	x = clampi(x, cam.screen_left(0xA0), cam.screen_right(0xA0))
	y = clampi(y, cam.screen_top(0x78), cam.screen_bottom(0x78))
	var dx := x - cam.view_x(0xA0)
	var dy := y - cam.view_y(0x78)
	cam.offset -= Vector2i(dx, dy)
	world.scroll_camera(dx, dy)


## FISH_applySavedCameraScroll: clears the flag before calling FISH_scrollCameraTo, which then
## returns at once, so the saved view is never restored (the C's order, kept).
func _apply_saved_scroll() -> void:
	if camera_control:
		camera_control = false
		_scroll_to(saved_scroll.x, saved_scroll.y)


## FISH_enableCameraControl.
func _enable_camera_control() -> void:
	_apply_saved_scroll()
	camera_control = true
	saved_scroll = Vector2i(fishing.camera.view_x(0xA0), fishing.camera.view_y(0x78))


## FISH_scrollViewToTarget (fish.c:1406): the rod's tick while the text box shows.
func _scroll_view_to_target() -> void:
	if text_box.is_scrolling:
		_pan_to(0x10, text_box.scroll_to, 0, 0)
		text_box.is_scrolling = false


# --- Helpers ------------------------------------------------------------------------------------

## FISH_isWithinCastRange (fish.c:1109).
func is_within_cast_range(pos: Vector3i, extra: int) -> bool:
	var t := world.tamer_position()
	return PsxMath.get_distance(pos.x - t.x, 0, pos.z - t.z) <= int(fishing.map.get("cast_range", 0)) + extra


func _has_food() -> bool:
	for t in world.inventory_types():
		if int(t) != FishingBaitMenu.EMPTY and world.is_food(int(t)):
			return true
	return false


func _show_text(lines: Array, target: Vector3i) -> void:
	text_box.show(lines, target, pad)


func _t(id: String) -> String:
	return world.text(id)


## The tamer's screen point for the bait menu's start (getEntityScreenPos(ENTITY_TABLE[0], 1)):
## bone 1 projected, relative to the screen centre.
func _tamer_screen() -> Vector2i:
	var p = fishing.camera.project(PsxMath.translation(world.bone_matrix(1)))
	if p == null:
		return Vector2i.ZERO
	return Vector2i(p.x - fishing.camera.view_x(0xA0), p.y - fishing.camera.view_y(0x78))


## The fields the world part reads (F2).
func _sync() -> void:
	fishing.bait = bait
	fishing.swimmer_pos = swimmer_pos
	fishing.hooked_active = hooked.active
	fishing.text_box_visible = text_box.is_visible()
	fishing.tamer_pos = world.tamer_position()
