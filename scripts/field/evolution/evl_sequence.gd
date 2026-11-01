class_name EvlSequence
extends RefCounted
## The evolution sequence (EVL_initEvoSequence evl.c:1277, EVL_tickEvoSequence evl.c:345,
## EVL_updateEvoCamera evl.c:702, EVL_calculateCameraVectors evl.c:834; specs/evolution_scene.md §4.1)
## as one state machine, frame for frame: state 0 the field going dark, 1 the camera in, 2 the bones
## breaking, the growth, the flashes and the new body, 3 the hand-back, 4 the wait for animation 0xB.
## It changes nothing outside itself: it reports through its members and signals and asks its owner
## through callables; each callable may be unset (headless: skipped). What it makes in a tick isn't
## ticked until the next one (A3).
##
## The frame is `timer` (EVO_SEQUENCE_DATA.timer): it counts from 0 at the first tick (A2) and
## `timer += 1` closes each state's work (A4, evl.c:588); state 4 sets -1 and returns (evl.c:581).

## Bone `bone` broke (EVL_buildShardSet's moment): the host builds the shard set from the posed bone.
signal bone_broken(bone: int)
## State 0 ends (evl.c:396-408): the others are hidden, the map layer is off, the view is saved.
signal hand_over()
## EVL_applyEvolution has run (evl.c:530-543): the new model is in place.
signal applied()
## State 3 (evl.c:561-577): the entities and the map layer are back, the music, the map's sounds.
signal ended()

## evl.c:384: state 0 lasts 32 frames; the map's level goes 0..0xFF.
const FADE_FRAMES := 0x20
const FADE_MAX := 0xFF
## evl.c:711-713 (EVL_updateEvoCamera): the camera's move in runs 0x20..0x60 (midpoint 0x40).
const CAMERA_START := 0x20
const CAMERA_END := 0x60
## evl.c:755: from this frame the camera orbits (+= 0x16 a frame).
const ORBIT_FROM := 0x61
const ORBIT_STEP := 0x16
## evl.c:728 (MAIN_D_801351F8 = 0x638): the orbit's angle at the start of the move in.
const ANGLE_START := 0x638
## evl.c:412: state 1's last frame; the first bone breaks.
const FIRST_BREAK := 0x6A
## evl.c:426-450: the table covers 0x70..0x9A, every frame from 0x9B to 0x11B breaks a bone.
const BREAK_TABLE_FROM := 0x70
const BREAK_TABLE_TO := 0x9B
const BREAK_END := 0x11C
## EVL_D_80063EFC (evl.c:253): >= 0 on the frames (0x70 + index) a bone breaks in 0x70..0x9A.
const BREAK_TABLE := [
	0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 2, -1, -1, -1, -1, -1,
	-1, -1, 3, -1, -1, -1, 4, -1, 5, -1, 6, 0]
## EVL_D_80063F28 (evl.c:262): the rings' pattern, 18 frames.
const PARTICLE_TABLE := [1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
## evl.c:200, :422-423: the ring colour is (0x0A, lerp(0x32, 0xE6, 1, 5, v), 0x0A).
const PARTICLE_RED_BLUE := 0x0A
const PARTICLE_GREEN := [0x32, 0xE6]
## evl.c:426-428: the brighten runs while the frame is < 0xCD, from 0x70 to its end 0x9A.
const BRIGHTEN_FROM := 0x70
const BRIGHTEN_END := 0x9A
const BRIGHTEN_LAST := 0xCC
## evl.c:973-975 (EVL_brightenDigimonClut): the three factors are rand() % 100.
const BRIGHTEN_RANGE := 100
## evl.c:462-480: the size is the old one's below 0xCC, grows over 0xCC..0x107, the new one's from 0x108.
const GROW_FROM := 0xCC
const GROW_TO := 0x108
## evl.c:466-472: the scale is lerp(0x1000, (r_new << 12) / r_old, ..); 0x1000 is 1.
const SCALE_ONE := 0x1000
## evl.c:481-486: the second orbit starts at 0xA5; its step ramps 0..0x16 over 0xA4..0xC2, full from 0xC3.
const SPIN_FROM := 0xA5
const SPIN_RAMP := [0xA4, 0xC2]
const SPIN_FULL := 0xC3
## evl.c:731-736, :762-767, :489-494: the orbit's distance is max(height, radius) * 5 + 0x4B0.
const DISTANCE_FACTOR := 5
const DISTANCE_BASE := 0x4B0
## evl.c:503-529: the sounds at 0xD6, the centre flashes on the even frames 0xD7..0x11B.
const CENTRE_STOP := 0xD6
const CENTRE_FROM := 0xD7
const CENTRE_TO := 0x11C
## evl.c:508-528: create_flash(0, bone 1, depth, 10, 0, lerp(0x333, 0x4800, ..), start, 0x14): the start
## colour is lerp(0x32, 0x78, ..) + rand() % 100 per channel, depth 0x21 when (f & lerp(5, 1, ..)) == 0
## else 0xFA0.
const CENTRE_T_MAX := 0xA
const CENTRE_SCALE := [0x333, 0x4800]
const CENTRE_BASE := [0x32, 0x78]
const CENTRE_COLOR_RANGE := 100
const CENTRE_COLOR_END := Vector3i(0x14, 0x14, 0x14)
const CENTRE_DEPTH_FRONT := 0x21
const CENTRE_DEPTH_BEHIND := 0xFA0
const CENTRE_MASK := [5, 1]
## evl.c:443-454: a bone's flash: mode 1, depth -1, 10 frames, scale 0..0x333, colour 0x96 -> 0x14.
const BREAK_FLASH_T_MAX := 0xA
const BREAK_FLASH_SCALE := 0x333
const BREAK_FLASH_START := Vector3i(0x96, 0x96, 0x96)
const BREAK_FLASH_END := Vector3i(0x14, 0x14, 0x14)
## evl.c:530-543: the apply at 0x11C; evl.c:544-546: the new body fills in 0x126..0x14E.
const APPLY_FRAME := 0x11C
const BODY_FROM := 0x126
const BODY_TO := 0x14F
const BODY_FULL := 0x14E
## evl.c:547: state 3 starts at 0x162 (its tick is 0x163).
const HAND_BACK := 0x162
## evl.c:442: a spark lives until 0x11C.
const SPARK_END := 0x11C
## evl.c:1297-1327 (EVL_D_80067994, 40 entries) and evl.c:536 (SUB[0..0x27]).
const BONES := 40
## model.c:83, :2493: PARTNER_WIREFRAME_TOTAL / _SUB's normal-model value, 0x10.
const WIREFRAME_FULL := 16
## evl.c:377, :403, :538, :571: the animation ids (fall, evolving, idle, pose).
const ANIM_FALL := 0xC
const ANIM_EVOLVING := 1
const ANIM_IDLE := 0
const ANIM_POSE := 0xB
## evl.c:408, :439, :505: the sounds are in slot 8: (8, 1) (8, 0) at 0x6A, (8, rand() % 3 + 2) a bone, (8, 5) at 0xD6.
const SOUND_SLOT := 8
const SOUND_FIRST := [1, 0]
const SOUND_BREAK_MODULO := 3
const SOUND_BREAK_BASE := 2
const SOUND_CENTRE := 5

# --- the owner's callables (each may be unset) -------------------------------------------------------

## The camera: {"eye": Vector3i, "ref": Vector3i, "offset": Vector2i, "projection": int} (GS_VIEWPOINT,
## DRAWING_OFFSET, VIEWPORT_DISTANCE).
var get_view := Callable()
var set_view := Callable()
## The saved view back (evl.c:550-566).
var restore_view := Callable()
## posData[bone].posMatrix.workm.t as PSX ints; bone 0 is the location (C1).
var bone_position := Callable()
## EVL_applyEvolution (the new model in place of the old).
var apply_evolution := Callable()
var play_sound := Callable()
var stop_sound := Callable()
var start_animation := Callable()
## The animation last started has played to its end (animFrame == frameCount).
var animation_done := Callable()

# --- the sequence's state (EVO_SEQUENCE_DATA and the C's statics) ------------------------------------

var timer := 0
var state := 0
## EVL_D_80067994 (40): the bones in the order they break, -1 free, -2 the end.
var bone_order := PackedInt32Array()
## data->unk_0x8: the next entry of bone_order.
var next_bone := 0
## MAIN_D_801351F8: the camera's angle.
var angle := 0
## The map's fade level, 0..0xFF (B1): the host darkens the background (and the CLUT2 nodes) with it.
var map_fade := 0
## The two CLUT banks' factor, 1 = full colour (B4): bank 0 the tamer's, bank 1 entities 2-4.
var bank0_factor := 1.0
var bank1_factor := 1.0
## EVL_brightenDigimonClut's three factors and its t (-1: none) (G1, G2).
var brighten := Vector3i.ZERO
var brighten_t := -1
## The partner's root scale (4096 = 1; J3, J6).
var scale := Vector3i(SCALE_ONE, SCALE_ONE, SCALE_ONE)
## PARTNER_WIREFRAME_TOTAL and PARTNER_WIREFRAME_SUB (40).
var wireframe_total := WIREFRAME_FULL
var wireframe_sub := PackedInt32Array()
## The view when the others were hidden (EVL_D_800688E8, MAIN_D_801351E4..EC).
var saved_view := {}
## The animation id last started (anim.animId; A5 reads it).
var animation := -1
## The sequence's own flash slots (I5: initializeFlashData(EVL_D_800677B0)).
var fx := BattleFx.new()
## The shard sets (the owner builds one on bone_broken, E), the sparks (F) and the rings (H).
var shards := EvlShardSets.new()
var sparks := EvlSparks.new()
var particles := EvlParticles.new()

var _bone_count := 0
var _bone_objects := PackedInt32Array()
var _location := Vector3i.ZERO
var _rotation_y := 0
var _old := Vector2i.ZERO
var _new := Vector2i.ZERO
## The view as the camera has it now (what the C leaves untouched stays).
var _view := {}


## EVL_initEvoSequence: timer 0, state 0, the partner's location kept (EVL_D_80064D40), the bone
## order rolled: boneCount - 1 rand() (D1). The sizes are (radius, height).
func init(bone_count: int, bone_objects: PackedInt32Array, location: Vector3i, rotation_y: int,
		old_size: Vector2i, new_size: Vector2i) -> void:
	_bone_count = bone_count
	_bone_objects = bone_objects
	_location = location
	_rotation_y = rotation_y
	_old = old_size
	_new = new_size
	timer = 0
	state = 0
	next_bone = 0
	wireframe_total = WIREFRAME_FULL
	wireframe_sub = PackedInt32Array()
	wireframe_sub.resize(BONES)
	wireframe_sub.fill(WIREFRAME_FULL)
	bone_order = PackedInt32Array()
	bone_order.resize(BONES)
	bone_order.fill(-1)
	# evl.c:1306: EVL_D_80067994[boneCount - 1] = -2.
	if bone_count >= 1 and bone_count <= BONES:
		bone_order[bone_count - 1] = -2
	# evl.c:1308-1310: order[i] = rand() & 0xFFF for i = 1 .. boneCount - 1.
	var order := PackedInt32Array()
	order.resize(BONES + 1)
	for i in range(1, bone_count):
		order[i] = Rng.rand() & 0xFFF
	# evl.c:1312-1325: the lowest roll first (strict >: the lowest index wins a tie), then 0x1000.
	for i in range(1, bone_count):
		var best := 1
		var best_val := order[1]
		for j in range(2, bone_count):
			if best_val > order[j]:
				best = j
				best_val = order[j]
		bone_order[i - 1] = best
		order[best] = 0x1000


## One game frame (EVL_tickEvoSequence).
func tick() -> void:
	_tick_effects()
	var frame := timer
	# evl.c:377-380 (A5): animation 0xC's end starts animation 1.
	if animation == ANIM_FALL and _animation_done():
		_start_animation(ANIM_EVOLVING)
	match state:
		0:
			_state_0(frame)
		1:
			_state_1(frame)
		2:
			_state_2(frame)
		3:
			_state_3()
		4:
			# evl.c:578-585: 0xB has played to its end: the object is removed, timer -1.
			if _animation_done():
				timer = -1
				return
	timer += 1


## What the sequence made in earlier ticks (A3): the flashes, the shard sets, the sparks and the
## rings.
func _tick_effects() -> void:
	fx.tick()
	shards.tick()
	sparks.tick()
	particles.tick()


## State 0 (evl.c:383-409): the fades, then at 0x20 the hand-over.
func _state_0(frame: int) -> void:
	# evl.c:384-390: lerp(0, 0xFF, 0, 0x20, f) below 0x20, else 0xFF (fadeoutCLUT1 / 2).
	map_fade = PsxMath.lerp_int(0, FADE_MAX, 0, FADE_FRAMES, frame) if frame < FADE_FRAMES else FADE_MAX
	# evl.c:391-395: even frames bank 0, odd frames bank 1 (each rolls 3 rand(), unused: B7).
	if frame & 1 == 0:
		bank0_factor = _fade_bank(0, FADE_FRAMES, frame)
	else:
		bank1_factor = _fade_bank(0, FADE_FRAMES, frame)
	if frame < FADE_FRAMES:
		return
	state = 1
	if get_view.is_valid():
		saved_view = (get_view.call() as Dictionary).duplicate()
	_view = saved_view.duplicate()
	hand_over.emit()


## EVL_fadeClutBank0 / 1 (evl.c:595-677): 3 unused rand() % 100, then the factor
## (end - frame) / (end - start).
func _fade_bank(start: int, end_frame: int, frame: int) -> float:
	for i in 3:
		Rng.rand()
	return float(end_frame - frame) / float(end_frame - start)


## State 1 (evl.c:410-424): the camera, and at 0x6A the first break (the `goto shards`).
func _state_1(frame: int) -> void:
	_update_camera(frame)
	if frame != FIRST_BREAK:
		return
	state = 2
	_play(SOUND_FIRST[0])
	_play(SOUND_FIRST[1])
	_start_animation(ANIM_FALL)
	_break_next_bone(frame)
	_size_and_spin(frame)
	_finish_state_2(frame)


## State 2 (evl.c:425-559).
func _state_2(frame: int) -> void:
	# evl.c:421-425 (H1): a ring particle where the table says.
	var ring: int = PARTICLE_TABLE[frame % PARTICLE_TABLE.size()]
	if ring != 0:
		var green := PsxMath.lerp_int(PARTICLE_GREEN[0], PARTICLE_GREEN[1], 1, 5, ring)
		particles.spawn(_location, Vector3i(PARTICLE_RED_BLUE, green, PARTICLE_RED_BLUE))
	# evl.c:426-428: the brighten's three rolls come before everything else (G1, G2).
	if frame >= BRIGHTEN_FROM and frame <= BRIGHTEN_LAST:
		brighten = Vector3i(Rng.rand() % BRIGHTEN_RANGE, Rng.rand() % BRIGHTEN_RANGE, Rng.rand() % BRIGHTEN_RANGE)
		brighten_t = mini(frame, BRIGHTEN_END)
	# evl.c:429-460: a bone on the table's frames below 0x9B, on every frame from 0x9B to 0x11B.
	if frame >= BREAK_TABLE_FROM and frame < BREAK_TABLE_TO:
		if int(BREAK_TABLE[frame - BREAK_TABLE_FROM]) >= 0:
			_break_next_bone(frame)
	elif frame >= BREAK_TABLE_TO and frame < BREAK_END:
		_break_next_bone(frame)
	_size_and_spin(frame)
	_finish_state_2(frame)


## evl.c:431-460 (the `shards:` block): the next bone in the list that has an object breaks; those
## without one are skipped in the same frame (D4); nothing once the list is spent.
func _break_next_bone(frame: int) -> void:
	while next_bone < _bone_count - 1:
		var bone := bone_order[next_bone]
		next_bone += 1
		var object := _bone_objects[bone] if bone >= 0 and bone < _bone_objects.size() else -1
		if object == -1:
			continue
		# evl.c:439: playSound2(8, rand() % 3 + 2).
		_play(Rng.rand() % SOUND_BREAK_MODULO + SOUND_BREAK_BASE)
		# evl.c:440: EVL_buildShardSet (the host's answer to the signal).
		bone_broken.emit(bone)
		# evl.c:441: PARTNER_WIREFRAME_SUB[bone] = 0.
		wireframe_sub[bone] = 0
		# evl.c:442: EVL_spawnSpark(bone, 0x11C - f).
		sparks.spawn(bone, SPARK_END - frame)
		# evl.c:443-454: the flash at the bone, its position copied (D6, D7).
		fx.create_flash(1, _bone_pos(bone), -1, BREAK_FLASH_T_MAX, 0, BREAK_FLASH_SCALE, BREAK_FLASH_START, BREAK_FLASH_END)
		return


## evl.c:461-502: the size (and the scale while it grows), the second orbit's camera.
func _size_and_spin(frame: int) -> void:
	var size := _size_at(frame)
	if frame >= GROW_FROM and frame < GROW_TO:
		# evl.c:466-472.
		var r_ratio := PsxMath.div(_new.x << 12, _old.x)
		var h_ratio := PsxMath.div(_new.y << 12, _old.y)
		var sx := PsxMath.lerp_int(SCALE_ONE, r_ratio, GROW_FROM, GROW_TO, frame)
		var sy := PsxMath.lerp_int(SCALE_ONE, h_ratio, GROW_FROM, GROW_TO, frame)
		scale = Vector3i(sx, sy, sx)
	if frame >= SPIN_FROM:
		# evl.c:481-486: += lerp(0, 0x16, 0xA4, 0xC2, f) below 0xC3, else 0x16.
		if frame >= SPIN_FULL:
			angle += ORBIT_STEP
		else:
			angle += PsxMath.lerp_int(0, ORBIT_STEP, SPIN_RAMP[0], SPIN_RAMP[1], frame)
		_set_orbit(size)


## The radius and height at frame `frame` (C10): the old Digimon's below 0xCC, lerped to the new
## one's over 0xCC..0x107, the new one's from 0x108.
func _size_at(frame: int) -> Vector2i:
	if frame < GROW_FROM:
		return _old
	if frame < GROW_TO:
		return Vector2i(PsxMath.lerp_int(_old.x, _new.x, GROW_FROM, GROW_TO, frame),
				PsxMath.lerp_int(_old.y, _new.y, GROW_FROM, GROW_TO, frame))
	return _new


## The rest of state 2 after the bones, size and orbit (evl.c:503-559): the centre flashes, the apply,
## the new body's fill, the hand-back at 0x162.
func _finish_state_2(frame: int) -> void:
	# evl.c:503-506 (I1).
	if frame == CENTRE_STOP:
		if stop_sound.is_valid():
			stop_sound.call()
		_play(SOUND_CENTRE)
	# evl.c:507-528 (I2, I3): on the even frames.
	if frame >= CENTRE_FROM and frame < CENTRE_TO and frame & 1 == 0:
		var mask := PsxMath.lerp_int(CENTRE_MASK[0], CENTRE_MASK[1], CENTRE_STOP, CENTRE_TO, frame)
		var depth := CENTRE_DEPTH_FRONT if frame & mask == 0 else CENTRE_DEPTH_BEHIND
		var scale_max := PsxMath.lerp_int(CENTRE_SCALE[0], CENTRE_SCALE[1], CENTRE_STOP, CENTRE_TO, frame)
		var base := PsxMath.lerp_int(CENTRE_BASE[0], CENTRE_BASE[1], CENTRE_STOP, CENTRE_TO, frame)
		var start := Vector3i(base + Rng.rand() % CENTRE_COLOR_RANGE, base + Rng.rand() % CENTRE_COLOR_RANGE,
				base + Rng.rand() % CENTRE_COLOR_RANGE)
		fx.create_flash(0, _bone_pos(1), depth, CENTRE_T_MAX, 0, scale_max, start, CENTRE_COLOR_END)
	# evl.c:530-543 (J5, J6): the apply; the new model is at scale 0x1000 (model.c:2853).
	if frame == APPLY_FRAME:
		wireframe_total = 0
		wireframe_sub.fill(WIREFRAME_FULL)
		if apply_evolution.is_valid():
			apply_evolution.call()
		scale = Vector3i(SCALE_ONE, SCALE_ONE, SCALE_ONE)
		# G5: the glow's palette belonged to the old model.
		brighten_t = -1
		_start_animation(ANIM_IDLE)
		applied.emit()
	# evl.c:544-546 (J7).
	if frame >= BODY_FROM and frame < BODY_TO:
		wireframe_total = PsxMath.lerp_int(0, WIREFRAME_FULL, BODY_FROM, BODY_FULL, frame)
	if frame < HAND_BACK:
		return
	# evl.c:547-559 (K1): state 3. The C also puts the saved view back here, one frame before the
	# colours, the others and the map come back (state 3, evl.c:561-577): a frame of the map's view,
	# still dark, with the rings. Port-only (the user, 2026-11-01): the view comes back with the
	# rest, at 0x163 (C13).
	state = 3
	wireframe_total = WIREFRAME_FULL


## State 3 (evl.c:561-577, K2).
func _state_3() -> void:
	state = 4
	if restore_view.is_valid():
		restore_view.call()
	# evl.c:567-570: fadeoutCLUT1(0), fadeoutCLUT2(0), both banks back (6 unused rolls).
	map_fade = 0
	bank0_factor = _fade_bank(0, 1, 0)
	bank1_factor = _fade_bank(0, 1, 0)
	ended.emit()
	_start_animation(ANIM_POSE)
	# evl.c:575 (H8): the particles released.
	particles.release_all()


## EVL_updateEvoCamera (evl.c:702-776), called in state 1 only (C5): from 0x20 to 0x60 the
## move in (C6), from 0x61 the orbit (C8).
func _update_camera(frame: int) -> void:
	if frame >= APPLY_FRAME:
		return
	if frame >= CAMERA_START and frame < ORBIT_FROM:
		angle = ANGLE_START
		if not saved_view.is_empty():
			# CutsceneCamera.orbit adds 0x638 itself (DOOA's D1); EVL's angle holds it already, so
			# the rotation y comes out as angle + rotation.y (evl.c:729-730).
			var v := CutsceneCamera.view(saved_view, _bone_pos(0), _rotation_y, _old.y, CAMERA_START, CAMERA_END, frame,
					_distance(_old))
			if not v.is_empty():
				_view = v
				_set_view()
	if frame >= ORBIT_FROM:
		angle += ORBIT_STEP
		_set_orbit(_old)


## evl.c:490-502, :762-775: the eye and the reference point at the angle; the offset and the
## projection stay where they are.
func _set_orbit(size: Vector2i) -> void:
	var o := CutsceneCamera.orbit(_bone_pos(0), angle + _rotation_y - CutsceneCamera.ORBIT_TURN, size.y, _distance(size))
	_view["ref"] = o[0]
	_view["eye"] = o[1]
	_set_view()


## C2: max(height, radius) * 5 + 0x4B0 (evl.c:731-736).
func _distance(size: Vector2i) -> int:
	return maxi(size.x, size.y) * DISTANCE_FACTOR + DISTANCE_BASE


func _set_view() -> void:
	if set_view.is_valid():
		set_view.call(_view.duplicate())


func _bone_pos(bone: int) -> Vector3i:
	if bone_position.is_valid():
		return bone_position.call(bone)
	return _location


func _play(value: int) -> void:
	if play_sound.is_valid():
		play_sound.call(SOUND_SLOT, value)


func _start_animation(id: int) -> void:
	animation = id
	if start_animation.is_valid():
		start_animation.call(id)


func _animation_done() -> bool:
	return not animation_done.is_valid() or bool(animation_done.call())
