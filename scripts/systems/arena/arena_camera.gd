class_name ArenaCamera
extends RefCounted
## The arena's cameras (specs/arena.md §3.4, §5.2): STD_tickVSPhase's states and the functions that
## set them (std_main.c:2173-2865), in PSX integers. The view is either a view matrix (GsSetView2:
## STDVS_CAMERA's rotation and translation, or its coordinate system as the camera's place) or a
## reference view (GsSetRefView2: GS_VIEWPOINT's eye and reference point); world_screen_matrix()
## gives GsWSMATRIX for both, projection() the projection distance.
## Positions and matrices come from `world` (BattleWorld, entity ids: partner 1, opponent).

## Fired by STD_selectRandomCamera mode 5 (STD_addWinScene / STD_addLoseScene): "win" or "lose".
signal scene_requested(kind: String)

## STD_CAMERA_STATE (STD_tickVSPhase, std_main.c:2306).
const STATE_MANUAL := 0
const STATE_ORBIT := 1
const STATE_TOP := 2
const STATE_ENTITY := 3
const STATE_BONE_VIEW := 4
const STATE_ENTITY_2 := 5
const STATE_VIEWPOINT := 6
const STATE_LOOK_AT := 7
const STATE_FIXED := 8
const STATE_CHASE := 9
const STATE_ROTATING := 10
const STATE_CHAMPION := 11

## STD_initializeCamera (std_setup.c:415-430).
const REST_PROJECTION := 500
const REST_ROTATION := Vector3i(100, 0, 0)
const REST_TRANSLATION := Vector3i(0, 500, 3000)
## STD_setCameraOrbit (2224-2262).
const ORBIT_FAR := 0x1068
const ORBIT_CLOSE := 0x12C
const ORBIT_HEIGHT := -0x3E8
const ORBIT_TILT := -0x2BC
## STD_setCameraYXZ (2266-2283).
const TOP_HEIGHT := -0x1F40
const TOP_TILT := -0x400
## STD_applyRotatingCamera (2394-2433): 2 a frame.
const ROTATE_STEP := 2
## STD_setRandomViewpoint (2487-2524), STD_setViewpointFromBone (2551-2577), STD_applyEntityViewpoint
## (2854-2864), STD_setChampionCamera (2526-2539): projection distances.
const VIEWPOINT_DISTANCE := 0x1F4
const BONE_VIEW_DISTANCE := 0x15E
const CHAMPION_DISTANCE := 0x200
## STD_tickCameraChase (2652-2710) and STD_startCameraChase (2717-2751).
const CHASE_START := 0x14
const CHASE_SWITCH := 0x23
const CHASE_SIDE_ANGLE := 0x638
const CHASE_END_ANGLE := 0x293
const CHASE_LOW := -0xB4
const ANIM_IDLE := 0x21
const ANIM_WALK := 0x23
const ANIM_MOVE := 0x2E
## STD_tickCameraIntro / STD_startCameraIntro (2753-2852): 22 keys of the intro's curves.
const INTRO_KEYS := 0x16

var world: BattleWorld
var partner := 1
var opponent := -1

## STD_CAMERA_STATE, STD_CAMERA_TIMER, STD_FOCUSED_ENTITY.
var state := STATE_ROTATING
var timer := 0
var focused := 1
## STDVS_CAMERA's rotation and translation; GS_VIEWPOINT's eye (vp) and reference point (vr).
var rotation := REST_ROTATION
var translation := REST_TRANSLATION
var eye := Vector3i.ZERO
var ref := Vector3i.ZERO
## VIEWPORT_DISTANCE (GsSetProjection is set from it where the C does).
var viewport_distance := REST_PROJECTION
## STD_DEFAULT_CAM_MIN_DISTANCE; MAIN_D_8013510C (the orbit is close).
var min_distance := 1000
var close := false
## The chase (STD_INTRO_CAMERA_CHASE {timer, phase, side}, STD_CAMERA_CHASE_LAST_POS, STD_INTRO_TARGET_POS);
## chase_active = its object 0x1AA.
var chase_timer := 0
var chase_phase := 0
var chase_side := 0
var chase_last := Vector3i.ZERO
var chase_target := Vector3i.ZERO
var chase_active := false
## The intro camera (STD_D_8007B9BC[6..9], STD_D_8007B9D0, the curves); intro_active = object 0x1AD.
var intro_frame := -1
var intro_angle := 0
var intro_distance := 0
var intro_radius := 0
var intro_entity := -1
var intro_target := -1
var intro_distances: Array[int] = []
var intro_heights: Array[int] = []
var intro_active := false

## How the last view was set: "matrix" (GsSetView2, super NULL), "coord" (GsSetView2 with the
## camera's coordinate system as super) or "ref" (GsSetRefView2).
var view_kind := "matrix"
var _view := PsxMath.identity()
var _projection := REST_PROJECTION
var _arena: Dictionary = {}


func _init(battle_world: BattleWorld, partner_entity := 1) -> void:
	world = battle_world
	partner = partner_entity
	focused = partner
	var d: Node = world.data if world != null else null
	if d != null and d.has_method("system"):
		var recs: Array = d.system("arena")
		if not recs.is_empty():
			_arena = recs[0]
	initialize_camera()


func _cam(key: String) -> Variant:
	return _arena.get("camera", {}).get(key, [])


func _vec(name: String) -> Vector3i:
	var v: Array = _arena.get("camera", {}).get("vectors", {}).get(name, [0, 0, 0])
	return Vector3i(int(v[0]), int(v[1]), int(v[2]))


func _h(e: int) -> int:
	return world.height(e)


func _r(e: int) -> int:
	return world.radius(e)


func _other(e: int) -> int:
	return opponent if e == partner else partner


## STD_initializeCamera (std_setup.c:415).
func initialize_camera() -> void:
	viewport_distance = REST_PROJECTION
	_projection = REST_PROJECTION
	rotation = REST_ROTATION
	translation = REST_TRANSLATION
	_set_view_matrix()


## STD_setVSPhase (std_main.c:2445).
func set_phase(arg: int) -> void:
	state = arg
	timer = 0


## The chase's and the intro camera's objects (0x1AA, 0x1AD): they come after STD_tickVSPhase's
## (0x1A8, added first by STD_tournamentMain) in the object list, so they tick after tick().
func tick_objects() -> void:
	if chase_active:
		tick_camera_chase()
	if intro_active:
		tick_camera_intro()


## STD_tickVSPhase (std_main.c:2306).
func tick() -> void:
	match state:
		STATE_MANUAL:
			apply_manual_camera()
		STATE_ORBIT:
			set_camera_orbit()
		STATE_TOP:
			set_camera_yxz()
		STATE_ENTITY, STATE_ENTITY_2:
			set_camera_to_entity()
		STATE_BONE_VIEW, STATE_VIEWPOINT:
			set_viewpoint_rotation_from_entity()
		STATE_CHASE:
			apply_entity_viewpoint()
		STATE_LOOK_AT:
			set_camera_look_at_entity()
		STATE_FIXED, STATE_CHAMPION:
			apply_viewpoint()
		STATE_ROTATING:
			apply_rotating_camera()


# --- the views ------------------------------------------------------------------------------------

## GsSetView2 with super NULL: the view is RotMatrix(rotation) with the translation.
func _set_view_matrix() -> void:
	_view = PsxMath.trans_matrix(PsxMath.rot_matrix(rotation), translation)
	view_kind = "matrix"


## GsSetView2 with super = the camera's coordinate system: GsWSMATRIX is its inverse.
func _set_view_coord() -> void:
	var c := PsxMath.trans_matrix(PsxMath.rot_matrix_yxz(rotation), translation)
	var rt := PsxMath.transpose(c)
	var t := PsxMath.apply_matrix_lv(rt, translation)
	_view = PsxMath.trans_matrix(rt, Vector3i(-t.x, -t.y, -t.z))
	view_kind = "coord"


## GsSetRefView2 (twist 0): GsWSMATRIX from the eye and the reference point. `port-only`: the axes are
## computed in floats, as the field's camera (FieldMap._basis_from_eye).
func _set_ref_view() -> void:
	var f := Vector3(ref - eye)
	f = f.normalized() if f != Vector3.ZERO else Vector3(0, 0, 1)
	var r := Vector3(0, 1, 0).cross(f)
	r = r.normalized() if r != Vector3.ZERO else Vector3(1, 0, 0)
	var dn := f.cross(r)
	var m := PsxMath.identity()
	var rows: Array[Vector3] = [r, dn, f]
	for i in 3:
		m[i * 3] = roundi(rows[i].x * 4096.0)
		m[i * 3 + 1] = roundi(rows[i].y * 4096.0)
		m[i * 3 + 2] = roundi(rows[i].z * 4096.0)
		m[9 + i] = roundi(-rows[i].dot(Vector3(eye)))
	_view = m
	view_kind = "ref"


## GsWSMATRIX.
func world_screen_matrix() -> PackedInt32Array:
	return _view


## The projection distance (GsSetProjection).
func projection() -> int:
	return _projection


# --- the states (std_main.c:2173-2440) ------------------------------------------------------------

## STD_applyManualCamera (2173): pad 2 moves it; the port has no pad 2 (`port-only`), so it holds.
func apply_manual_camera() -> void:
	_set_view_matrix()


## STD_setCameraOrbit (2224): beside the two fighters, as far as their distance asks.
func set_camera_orbit() -> void:
	var a := world.location(opponent)
	var b := world.location(partner)
	var dx := a.x - b.x
	var dz := a.z - b.z
	var dist := int(sqrt(float(dx * dx + dz * dz)))
	if dist == 0:
		return
	var d := dist * viewport_distance / 200
	if d < PsxMath.s16(min_distance):
		d = min_distance
	close = d < PsxMath.s16(min_distance) + ORBIT_CLOSE
	if d > ORBIT_FAR:
		d = ORBIT_FAR
	var ang := 0x1000 - PsxMath.atan(dx, dz)
	translation = Vector3i(b.x + dx / 2 + d * dz / dist, ORBIT_HEIGHT, b.z + dz / 2 - d * dx / dist)
	rotation = Vector3i(PsxMath.atan(d, ORBIT_TILT) + 0x800, ang + 0x800, 0)
	_set_view_coord()


## STD_setCameraYXZ (2266): straight down over the midpoint.
func set_camera_yxz() -> void:
	var a := world.location(partner)
	var b := world.location(opponent)
	translation = Vector3i(a.x + (b.x - a.x) / 2, TOP_HEIGHT, a.z + (b.z - a.z) / 2)
	rotation = Vector3i(TOP_TILT, 0, 0)
	_set_view_coord()


## STD_setCameraToEntity (2286): STDVS_CAMERA in the focused fighter's frame.
func set_camera_to_entity() -> void:
	var rot := rotation
	rot.y = (rot.y - world.rotation_y(focused)) & 0xFFF
	var m := PsxMath.rot_matrix(rot)
	var out := PsxMath.apply_matrix_lv(m, world.location(focused))
	_view = PsxMath.trans_matrix(m, translation - out)
	view_kind = "matrix"


## STD_setViewpointRotationFromEntity (2347): look at the focused fighter's bone 1.
func set_viewpoint_rotation_from_entity() -> void:
	ref = PsxMath.translation(world.bone_matrix(focused, 1))
	_set_ref_view()


## STD_setCameraLookAtEntity (2358): turn STDVS_CAMERA towards the other fighter.
func set_camera_look_at_entity() -> void:
	var here := world.location(focused)
	var there := world.location(_other(focused))
	rotation.y = (-PsxMath.atan(there.z - here.z, there.x - here.x) + 0x800) & 0xFFF
	var m := PsxMath.rot_matrix(rotation)
	var out := PsxMath.apply_matrix_lv(m, here)
	_view = PsxMath.trans_matrix(m, translation - out)
	view_kind = "matrix"


## STD_applyViewpoint (2388).
func apply_viewpoint() -> void:
	_projection = viewport_distance
	_set_ref_view()


## STD_applyRotatingCamera (2394): turns 2 a frame (pad 2's moves left out, `port-only`).
func apply_rotating_camera() -> void:
	rotation.y = (rotation.y + ROTATE_STEP) & 0xFFF
	_set_view_matrix()


## STD_setCameraParams (2435).
func set_camera_params(p: Array) -> void:
	rotation = Vector3i(int(p[0]), int(p[1]), int(p[2]))
	translation = Vector3i(int(p[3]), int(p[4]), int(p[5]))


## STD_applyEntityViewpoint (2854): look at the focused fighter, 2/3 of its height up.
func apply_entity_viewpoint() -> void:
	viewport_distance = BONE_VIEW_DISTANCE
	_projection = viewport_distance
	var t := PsxMath.translation(world.bone_matrix(focused, 0))
	ref = Vector3i(t.x, -_h(focused) * 2 / 3, t.z)
	_set_ref_view()


# --- the cuts -------------------------------------------------------------------------------------

## STD_selectRandomCamera (2457): 1 in 3 (always for mode 5) a preset beside `entity`; mode 5 is the
## end: the win / lose letters, then the intro camera on the partner.
func select_random_camera(entity: int, mode: int, sub: int) -> void:
	if mode != 5:
		if Rng.random_limit(3) != 0:
			return
	focused = entity
	var presets: Array = _cam("presets")
	var p: Array = presets[mode] if sub != 3 else presets[Rng.random_limit(3) + 6]
	set_camera_params(p)
	if mode < 5:
		state = STATE_ENTITY
		return
	scene_requested.emit("win" if entity != partner else "lose")
	focused = partner
	start_camera_intro(partner, opponent)


## STD_setRandomViewpoint (2487): 1 in 3, not while the camera looks at a fighter (7).
func set_random_viewpoint(entity: int, idx: int) -> void:
	if Rng.random_limit(3) != 0:
		return
	if state == STATE_LOOK_AT:
		return
	viewport_distance = VIEWPOINT_DISTANCE
	var vps: Array = _cam("random_viewpoints")
	var v := Vector3i(int(vps[idx][0]), int(vps[idx][1]), int(vps[idx][2]))
	if idx < 4:
		focused = entity
		state = STATE_BONE_VIEW
		var m := PsxMath.rot_matrix(Vector3i(0, world.rotation_y(entity), 0))
		var out := PsxMath.apply_matrix_lv(m, v)
		var loc := world.location(entity)
		eye = Vector3i(out.x + loc.x, out.y, out.z + loc.z)
	else:
		state = STATE_VIEWPOINT
		eye = v


## STD_setChampionCamera (2526).
func set_champion_camera() -> void:
	state = STATE_CHAMPION
	eye = Vector3i(0, -0xC8, -(_r(partner) * 2 + 0x320))
	ref = Vector3i(0, -_h(partner) * 2 / 3, 0)
	viewport_distance = CHAMPION_DISTANCE
	_projection = viewport_distance
	_set_ref_view()


## STD_setViewpointFromBone (2551): the reference point on bone `offset`'s frame (the SVECTOR's pad is
## 0: bone 0), at bone 1's height; the eye `dist` away along `rot` (RotMatrixZYX).
func set_viewpoint_from_bone(entity: int, offset: Vector3i, rot: Vector3i, dist: int) -> void:
	var m1 := world.bone_matrix(entity, 0)
	var out1 := PsxMath.apply_matrix_sv(m1, offset)
	var t1 := PsxMath.translation(m1)
	ref = t1 + out1
	var m2 := world.bone_matrix(entity, 1)
	ref.y = PsxMath.translation(m2).y
	var m3 := PsxMath.rot_matrix_zyx(rot)
	eye = PsxMath.apply_matrix_lv(m3, Vector3i(0, 0, dist)) + ref
	viewport_distance = BONE_VIEW_DISTANCE


## STD_getFighterDistance (2541): how far `pos` went from `from` towards `to`, in %.
func fighter_distance(from: Vector3i, to: Vector3i, pos: Vector3i) -> int:
	var walked := PsxMath.get_distance(from.x - pos.x, from.y - pos.y, from.z - pos.z)
	var total := PsxMath.get_distance(to.x - from.x, to.y - from.y, to.z - from.z)
	return walked * 100 / total if total != 0 else 0


## STD_isPositionNearEntity (2614): within 50 on x and z.
func is_position_near(entity: int, pos: Vector3i) -> bool:
	var loc := world.location(entity)
	return absi(loc.x - pos.x) <= 50 and absi(loc.z - pos.z) <= 50


## STD_interpolateClamped2 (2634).
static func interpolate_clamped(lo: int, hi: int, t: int, start: int, end: int) -> int:
	if hi < lo:
		var tmp := lo
		lo = hi
		hi = tmp
	t = clampi(t, lo, hi)
	if lo >= t:
		return start
	return start + (end - start) * (t - lo) / (hi - lo)


## STD_updateCameraLerp (2580): the chase's second half, swinging round the fighter.
func update_camera_lerp(t: int, flip: int) -> void:
	var off := _vec("intro_stage2_pos")
	var rot := _vec("intro_stage2_rot")
	var base := (_h(focused) + _r(focused)) / 2 * 0x62C / 450
	var dbl := base * 2
	rot.x = PsxMath.lerp_int(0x2AA, 0xE3, 0, 0x64, t)
	rot.y = PsxMath.lerp_int(0x5C7, 0xA38, 0, 0x64, t)
	var dist := 0
	if rot.y < 0x801:
		dist = PsxMath.lerp_int(base, dbl, 0x5C7, 0x800, rot.y)
	else:
		dist = PsxMath.lerp_int(dbl, base, 0x800, 0xA38, rot.y)
	if flip != 0:
		rot.y = -rot.y
	rot.y += world.rotation_y(focused)
	off.y = -_h(focused) * 2 / 3
	set_viewpoint_from_bone(focused, off, rot, dist)


## STD_startCameraChase (2717): the intro's walk-in, the camera on `entity`'s side `side`.
func start_camera_chase(entity: int, dx: int, side: int) -> void:
	focused = entity
	chase_last = world.location(entity)
	chase_target = Vector3i(chase_last.x - dx, chase_last.y, chase_last.z)
	world.start_animation(entity, ANIM_IDLE)
	state = STATE_CHASE
	chase_timer = 0
	chase_phase = 0
	chase_side = side
	chase_active = true
	var off := _vec("chase_offset")
	var rot := _vec("chase_rotation")
	rot.y = -CHASE_SIDE_ANGLE if side == 0 else CHASE_SIDE_ANGLE
	rot.y += world.rotation_y(entity)
	off.y = -_h(entity) * 2 / 3
	var dist := (_h(entity) + _r(entity)) / 2 * 0x5AA / 450
	set_viewpoint_from_bone(entity, off, rot, dist)
	eye.y = mini(off.y * 3 / 10, CHASE_LOW)


## STD_tickCameraChase (2652): waits for the intro name (which sets the timer to 0x14), walks, swings
## round, and at the target starts the fighter's first technique pose.
func tick_camera_chase() -> void:
	if chase_timer < CHASE_START:
		return
	if chase_timer == CHASE_START:
		world.start_animation(focused, ANIM_WALK)
	var loc := world.location(focused)
	if chase_phase == 0:
		var dist := fighter_distance(chase_last, chase_target, loc)
		if dist >= CHASE_SWITCH:
			chase_last = loc
			chase_phase = 1
			state = STATE_FIXED
		else:
			var off := _vec("intro_stage1_pos")
			var rot := _vec("intro_stage1_rot")
			if chase_side == 0:
				rot.y = PsxMath.lerp_int(-CHASE_SIDE_ANGLE, -CHASE_END_ANGLE, 0, CHASE_SWITCH, dist)
			else:
				rot.y = PsxMath.lerp_int(CHASE_SIDE_ANGLE, CHASE_END_ANGLE, 0, CHASE_SWITCH, dist)
			rot.y += world.rotation_y(focused)
			off.y = -_h(focused) * 7 / 10
			var d2 := (_h(focused) + _r(focused)) / 2 * 0x5AA / 450
			set_viewpoint_from_bone(focused, off, rot, d2)
			eye.y = mini(off.y * 7 / 10, CHASE_LOW)
			chase_timer += 1
			return
	var t := fighter_distance(chase_last, chase_target, loc)
	update_camera_lerp(t, chase_side)
	if is_position_near(focused, chase_target):
		var moves: Array = world.stats(focused)["base"]["moves"]
		for i in 3:
			if moves[i] != null and int(moves[i]) != 0xFF:
				world.start_animation(focused, int(moves[i]))
				break
		world.set_step_held(focused, true)
		chase_timer = -1
		return
	chase_timer += 1


## STD_setPostIntroPosition's camera half (1682): the chase ends.
func end_chase() -> void:
	chase_timer = -1


## The chase's object (0x1AA) is removed (STD_runIntro).
func remove_chase() -> void:
	chase_active = false


## STD_startCameraIntro (2782): the end camera, swinging round `target` from `entity`'s side; its
## distance and height follow 22 keyed values, some random (customRandom).
func start_camera_intro(target: int, entity: int) -> void:
	intro_frame = 0
	intro_entity = entity
	if target < 0:
		target = _other(focused)
	intro_target = target
	state = STATE_FIXED
	intro_active = true
	var off := _vec("intro_offset")
	var rot := _vec("intro_rotation")
	var el := world.location(entity)
	var tl := world.location(target)
	var dx := el.x - tl.x
	var dz := el.z - tl.z
	intro_angle = (-PsxMath.atan(dz, dx) + 0x7DE) & 0xFFF
	rot.y = intro_angle
	intro_distance = maxi(PsxMath.get_distance(dx, 0, dz) + 0x2BC, 0x5DC)
	set_viewpoint_from_bone(target, off, rot, intro_distance)
	intro_radius = _r(target) * 3 * 2
	ref.y = -_h(target) * 2 / 3
	eye.y = -_h(entity)
	intro_heights = []
	intro_heights.resize(INTRO_KEYS)
	intro_heights[0] = _h(entity)
	intro_heights[1] = _h(entity)
	intro_heights[2] = _h(entity) * 200 / 100
	intro_heights[3] = _h(target) * 380 / 100
	intro_heights[4] = _h(target) * 250 / 100
	for i in range(5, INTRO_KEYS):
		intro_heights[i] = Rng.custom_random(0x50, _h(target) * 180 / 100)
	var d := PsxMath.get_distance(dx, 0, dz) + 0x2BC
	intro_distances = []
	intro_distances.resize(INTRO_KEYS)
	intro_distances[0] = d
	intro_distances[1] = d
	d = maxi(d, 0x5DC)
	intro_distances[2] = d * 120 / 100
	intro_distances[3] = d * 80 / 100
	intro_distances[4] = intro_radius
	for i in range(5, INTRO_KEYS):
		intro_distances[i] = Rng.custom_random(intro_radius * 45 * 2 / 100, intro_radius * 45 * 4 / 100)


## processSomeArenaArrays (effect_common.c:622) with the slopes initializeSomeArenaArrays zeroes: the
## value at the key before `t` plus the integer slope to the next one. `port-only`: equal keys (past
## the last key) keep the value instead of dividing by zero.
func curve(t: int, values: Array[int]) -> int:
	var keys: Array = _cam("intro_keys")
	var lo := 0
	var hi := INTRO_KEYS - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if int(keys[mid]) < t:
			lo = mid + 1
		else:
			hi = mid
	if lo > 0:
		lo -= 1
	var dx := int(keys[lo + 1]) - int(keys[lo])
	if dx == 0:
		return values[lo]
	var dt := t - int(keys[lo])
	return values[lo] + dt * ((values[lo + 1] - values[lo]) / dx)


## STD_tickCameraIntro (2753).
func tick_camera_intro() -> void:
	var p0 := intro_frame
	if p0 >= 0x1E and p0 < 0x3C:
		intro_distance = PsxMath.lerp_int(intro_distance, intro_radius, p0, 0x3C, p0 + 1)
	if p0 >= 0x1E:
		intro_angle = PsxMath.s16(intro_angle + interpolate_clamped(0x1E, 0x3C, p0, 0, 0x5B))
	var off := Vector3i.ZERO
	var rot := Vector3i(0, intro_angle, 0)
	intro_distance = curve(p0, intro_distances)
	set_viewpoint_from_bone(intro_entity, off, rot, intro_distance)
	ref.y = -_h(intro_target) * 2 / 3
	eye.y = -curve(p0, intro_heights)
	intro_frame += 1


## STD_removeCameraIntro (2848).
func remove_camera_intro() -> void:
	intro_active = false
	intro_frame = -1
