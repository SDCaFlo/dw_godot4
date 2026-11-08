class_name Fishing
extends RefCounted
## FISHING_DATA of a fishing map (specs/fishing.md): the fish, Seadramon, the ripples and the
## markers, ticked as the world object (FISH_tickFishingWorld, fish.c:4420). Logic only, in the C's
## integers (PSX world units, 12-bit angles); the view draws from the public fields. Step F2 is the
## world (§2.1-2.6 up to the bite test); the rod, the bobber and the hooked fish come with F3 and
## set `bait`, `swimmer_pos` and `hooked_active` here.

## The pools (FishPool.items[33], FishRipplePool.items[16], FishMarkerPool.items[16]).
const FISH_COUNT := 33
const RIPPLE_COUNT := 16
const MARKER_COUNT := 16
## FISH_tickFishPopulation: a fish spawns while fewer than 0x20 live (fish.c:2941).
const POPULATION_MAX := 0x20
## Kind 6 is Seadramon (fish.c:2622).
const SEADRAMON := 6
const KINDS := 6
## FISH_spawnFish / _spawnSeadramon: lifetime customRandom(0x258, 0x4B0) (fish.c:2700, :2624).
const LIFETIME := Vector2i(0x258, 0x4B0)
## FISH_tickFish: the states (fish.c:2722-2831).
const STATE_APPEAR := 0
const STATE_IDLE := 0xA
const STATE_SWIM := 0x14
const STATE_LEAVE := 0x1E
## Fish speeds: appear 0x1E, leave 0x28; transparency ± 8 up to 0x80 (fish.c:2726, :2821, :2729).
const APPEAR_STEP := 0x1E
const LEAVE_STEP := 0x28
const FADE_STEP := 8
const OPAQUE := 0x80
## A swim's speed: distance / 8, at most 0x32, at most the size; slows by >> 3, stops below 8
## (fish.c:2780-2806). Towards the bobber at least 3 (:2792).
const SWIM_DIVISOR := 8
const SWIM_MAX := 0x32
const SWIM_STOP := 8
const APPROACH_MIN := 3
## The bait draws a fish from 0xC9 to 0x257 away (fish.c:2762-2765).
const BAIT_NEAR := 0xC9
const BAIT_FAR := 0x258
## A ripple's attractor scares fish: escapeTimer = 0x1E (fish.c:2753).
const ESCAPE_FRAMES := 0x1E
## Every 20 game frames (VSync(-1) / 3 % 20) Seadramon may come (fish.c:2975); bites are tried
## every 20 (fish) or 8 (Seadramon) frames, within 0xC9, Seadramon at 20 % (fish.c:3063-3073).
const SEADRAMON_EVERY := 20
const BITE_EVERY := 20
const SEADRAMON_BITE_EVERY := 8
const SEADRAMON_BITE_CHANCE := 0x14
const BITE_RANGE := 0xC9
## Markers: sprite 0x2F could bite, 0x30 can't; 10 frames (fish.c:3088, :1791).
const MARKER_BITE := 0x2F
const MARKER_NO_BITE := 0x30
const MARKER_FRAMES := 10
## Seadramon: speed ± 0xA up to 0x32, turns at most 0x80, fades ± 8 (fish.c:2648-2686).
const SEADRAMON_ACCEL := 0xA
const SEADRAMON_TURN := 0x80
## FISH_SEADRAMON_HISTORY[5] (fish.c:2557).
const SEADRAMON_HISTORY := 5

## Ripple frames per kind (FISH_tickRipple, fish.c:1841): kind 0 MAIN_D_80134958[frame / 2], −1
## MAIN_D_80134960[frame], −2 MAIN_D_80134968[frame / 3], −3 MAIN_D_8013496C[frame], −4
## FISH_D_8007A4B4[frame]. −1 or a sprite ≥ 13 ends it.
const RIPPLE_KIND_0 := [1, 2, 3, 4, 5, -1]
const RIPPLE_KIND_1 := [0, 1, 2, 3, 4, 5, -1]
const RIPPLE_KIND_2 := [4, 5, -1]
const RIPPLE_KIND_3 := [2, 3, 4, 5, -1]
const RIPPLE_KIND_4 := [0, 0, 6, 7, 8, 9, 10, 11, 12, 2, 3, 4, 4, 5, 5, 5, -1, 0, 0, 0]
const RIPPLE_LAST_SPRITE := 13


## Fish (include/dw/fish.h): one of the pool, the hooked one or Seadramon.
class Fish:
	var active := false
	var kind := 0
	var size := 0
	var transparency := 0
	var pos := Vector3i.ZERO
	var rotation := Vector3i.ZERO
	var anim_phase := 0
	var state := 0
	var frames_on_state := 0
	var lifetime := 0
	var time_next_move := 0
	var time_this_move := 0

	func copy_from(f: Fish) -> void:
		active = f.active
		kind = f.kind
		size = f.size
		transparency = f.transparency
		pos = f.pos
		rotation = f.rotation
		anim_phase = f.anim_phase
		state = f.state
		frames_on_state = f.frames_on_state
		lifetime = f.lifetime
		time_next_move = f.time_next_move
		time_this_move = f.time_this_move


## FishRipple.
class Ripple:
	var active := false
	var pos := Vector3i.ZERO
	var kind := 0
	var frame := 0
	var sprite := 0
	var scale := 0


## FishMarker.
class Marker:
	var active := false
	var lifetime := 0
	var sprite := 0
	var pos := Vector3i.ZERO


## GameData.fishing_map(map): spots, water, Seadramon's path and hours, scales.
var map := {}
## GameData.fishing()["kinds"]: size, move_delay, bait per kind (7 with Seadramon).
var kinds: Array = []
var camera := FishingCamera.new()
## The spots' polygons, a copy the session changes: FISH_randomPointInSpot clamps the points it
## picks in the table itself (fish.c:1589-1592).
var spot_points: Array = []

var fish: Array[Fish] = []
## FishPool.next (starts at items[1], fish.c:3024), count, frameCount, escapeTimer.
var fish_next := 1
var fish_count := 0
var frame_count := 0
var escape_timer := 0
var ripples: Array[Ripple] = []
var ripple_next := 0
var ripple_count := 0
## FishRipplePool.attractor / attractRadius: the newest ripple that scares fish.
var attractor: Ripple = null
var attract_radius := 0
var markers: Array[Marker] = []
var marker_next := 0
var marker_count := 0
## FISH_SEADRAMON_HISTORY: the last 5 positions' rotations, newest first (pushed with the position,
## only the rotation is kept: FISH_pushSeadramonSegment, fish.c:2557).
var seadramon_history: Array[Vector3i] = []

# --- What the rest of the game gives (the host each frame; F3's rod) -----------------------------
## fishingDisabled (setFishingDisabled, main/fish.c:45).
var disabled := false
## PARTNER_STATE == 0xD: the evolution stops the world object (fish.c:4426).
var partner_evolving := false
## FISH_isTextBoxVisible: the text box stops the world (fish.c:4432). F3 sets it.
var text_box_visible := false
## rod.bait: the bait's item id; -1 none.
var bait := -1
## swimmer.pos: the bobber.
var swimmer_pos := Vector3i.ZERO
## hooked.fish.active.
var hooked_active := false
## The tamer's position (TAMER_ENTITY.posData->location).
var tamer_pos := Vector3i.ZERO
## VSync(-1) / 3: the game frame count (GameLoop.frame_count).
var vsync_frame := 0
## HOUR.
var hour := 0
## F3: FISH_updateRodPose and FISH_tickHookedFish(0), called from tick_world.
var update_rod_pose := Callable()
var tick_hooked := Callable()


## FISH_init's pools (fish.c:4619-4637) for a map's data (GameData.fishing_map) and the kinds.
func setup(map_data: Dictionary, kind_data: Array) -> void:
	map = map_data
	kinds = kind_data
	spot_points = []
	for spot in map.get("spots", []):
		var pts: Array = []
		for p in spot["points"]:
			pts.append(Vector2i(int(p[0]), int(p[1])))
		spot_points.append(pts)
	fish = []
	for i in FISH_COUNT:
		fish.append(Fish.new())
	ripples = []
	for i in RIPPLE_COUNT:
		ripples.append(Ripple.new())
	markers = []
	for i in MARKER_COUNT:
		markers.append(Marker.new())
	seadramon_history = []
	for i in SEADRAMON_HISTORY:
		seadramon_history.append(Vector3i.ZERO)
	fish_next = 1
	fish_count = 0
	frame_count = 0
	escape_timer = 0
	ripple_next = 0
	ripple_count = 0
	attractor = null
	marker_next = 0
	marker_count = 0
	disabled = false


## FISH_tickFishingWorld (fish.c:4420).
func tick_world() -> void:
	if disabled or partner_evolving:
		return
	if update_rod_pose.is_valid():
		update_rod_pose.call()
	if text_box_visible:
		return
	tick_ripples()
	tick_markers()
	tick_population()
	if tick_hooked.is_valid():
		tick_hooked.call(0)


# --- Water and spots (§2.1) ----------------------------------------------------------------------

## The map's isWater (FISH_isFishableWater1 / 2, fish.c:4511-4535), from its rule.
func is_water(x: int, y: int) -> bool:
	var water: Dictionary = map.get("water", {})
	var shore: Array = water.get("shore", [])
	match str(water.get("rule", "")):
		"below_shore":
			if camera.screen_bottom(int(water["bottom"])) < y:
				return false
			return lerp_by_x(x, y, shore) >= 0
		"left_of_shore":
			if x >= int(water["max_x"]):
				return false
			if y < int(water["open_above_y"]):
				return true
			return lerp_by_y(x, y, shore) <= 0
	return false


## FISH_lerpTableByX (fish.c:4475): base − the shore's y at x; 0 outside the table.
static func lerp_by_x(x: int, base: int, tbl: Array) -> int:
	var n := tbl.size()
	if n < 2 or x < int(tbl[0][0]) or int(tbl[n - 1][0]) < x:
		return 0
	var i := n - 2
	while i >= 0:
		if x >= int(tbl[i][0]):
			break
		i -= 1
	var x0 := int(tbl[i][0])
	var y0 := int(tbl[i][1])
	var y := y0 + PsxMath.div((x - x0) * (int(tbl[i + 1][1]) - y0), int(tbl[i + 1][0]) - x0)
	return base - y


## FISH_lerpTableByY (fish.c:4493): base − the shore's x at y; 0 outside the table.
static func lerp_by_y(base: int, y: int, tbl: Array) -> int:
	var n := tbl.size()
	if n < 2 or y < int(tbl[0][1]) or int(tbl[n - 1][1]) < y:
		return 0
	var i := n - 2
	while i >= 0:
		if y >= int(tbl[i][1]):
			break
		i -= 1
	var x0 := int(tbl[i][0])
	var y0 := int(tbl[i][1])
	var x := x0 + PsxMath.div((y - y0) * (int(tbl[i + 1][0]) - x0), int(tbl[i + 1][1]) - y0)
	return base - x


## FISH_randomPointInSpot (fish.c:1559): a ground point in water inside the spot's polygon. A point
## that isn't on the ground keeps `fallback` (the C leaves the output as it was).
func random_point_in_spot(index: int, fallback := Vector3i.ZERO) -> Vector3i:
	if index < 0 or index >= KINDS or index >= spot_points.size():
		return Vector3i.ZERO
	var pts: Array = spot_points[index]
	var count := pts.size()
	while true:
		var picked: Array[int] = []
		for t in 3:
			while true:
				var k := Rng.custom_random(0, count - 1)
				if not k in picked:
					picked.append(k)
					break
		for k in picked:
			var p: Vector2i = pts[k]
			pts[k] = Vector2i(clampi(p.x, camera.screen_left(0), camera.screen_right(0x140)),
					clampi(p.y, camera.screen_top(0), camera.screen_bottom(0xF0)))
		var p0: Vector2i = pts[picked[0]]
		var p1: Vector2i = pts[picked[1]]
		var p2: Vector2i = pts[picked[2]]
		var t1 := Rng.custom_random(0, 0x1000)
		var x := PsxMath.s16((p0.x * t1 + p1.x * (0x1000 - t1)) >> 12)
		var y := PsxMath.s16((p0.y * t1 + p1.y * (0x1000 - t1)) >> 12)
		var t2 := Rng.custom_random(0, 0x1000)
		x = PsxMath.s16((p2.x * t2 + x * (0x1000 - t2)) >> 12)
		y = PsxMath.s16((p2.y * t2 + y * (0x1000 - t2)) >> 12)
		if not camera.is_in_background(x, y):
			continue
		if not is_water(x, y):
			continue
		var ground = camera.ground_at(x, y)
		return ground if ground != null else fallback
	return fallback


# --- Fish (§2.2) ---------------------------------------------------------------------------------

## FISH_allocFish (fish.c:2883): the next free fish from `fish_next`, wrapping; null when full.
func alloc_fish() -> Fish:
	if fish_count >= FISH_COUNT:
		return null
	var i := fish_next
	while true:
		if not fish[i].active:
			fish_next = i
			return fish[i]
		i = (i + 1) % FISH_COUNT
		if i == fish_next:
			break
	return null


## FISH_isSeadramonSpawned (fish.c:2909).
func is_seadramon_spawned() -> bool:
	for f in fish:
		if f.active and f.kind == SEADRAMON:
			return true
	return false


## FISH_tickFishPopulation (fish.c:2925).
func tick_population() -> void:
	frame_count += 1
	if escape_timer > 0:
		escape_timer -= 1
	else:
		if fish_count < POPULATION_MAX:
			var counts: Array[int] = [0, 0, 0, 0, 0, 0]
			var total := 0
			for f in fish:
				if f.active and f.kind >= 0 and f.kind < KINDS:
					counts[f.kind] += 1
					total += 1
			var best_kind := 0
			var best := 0x2711
			for i in KINDS:
				var share := int(map["spots"][i]["share"])
				counts[i] = r3000_div(counts[i] * 10000, total * share)
				if counts[i] <= best:
					best = counts[i]
					best_kind = i
			var f := alloc_fish()
			if f != null:
				f.active = true
				fish_count += 1
				spawn_fish(f, best_kind)
		if vsync_frame % SEADRAMON_EVERY == 0:
			var hours: Array = map.get("seadramon_hours", [])
			if _is_seadramon_hour(hours) and not is_seadramon_spawned() and not hooked_active:
				var sea := alloc_fish()
				if sea != null:
					sea.active = true
					fish_count += 1
					spawn_seadramon(sea)
	for f in fish:
		if f.active:
			tick_fish(f)


## seadramonTime1 / 100 == HOUR or seadramonTime2 / 100 == HOUR (fish.c:2979; the minutes aren't read).
func _is_seadramon_hour(hours: Array) -> bool:
	for h in hours:
		if int(h) == hour:
			return true
	return false


## The R3000's division (FISH_tickFishPopulation.s:93 has no break on a zero divisor): by 0 the
## quotient is −1 for a dividend ≥ 0, else 1 (psx-spx); otherwise C's truncating division.
static func r3000_div(a: int, b: int) -> int:
	if b == 0:
		return -1 if a >= 0 else 1
	return PsxMath.div(a, b)


## FISH_spawnFish (fish.c:2694).
func spawn_fish(f: Fish, kind: int) -> void:
	f.kind = kind
	var size: Array = kinds[kind]["size"]
	f.size = Rng.custom_random(int(size[0]), int(size[1]))
	f.lifetime = Rng.custom_random(LIFETIME.x, LIFETIME.y)
	f.state = STATE_APPEAR
	f.frames_on_state = 0
	f.transparency = 0
	f.pos = random_point_in_spot(f.kind, f.pos)
	var v := random_point_in_spot(f.kind, Vector3i.ZERO)
	f.rotation = PsxMath.to_euler_angles(v.x - f.pos.x, 0, v.z - f.pos.z)


## FISH_tickFish (fish.c:2709).
func tick_fish(f: Fish) -> void:
	if f.kind == SEADRAMON:
		tick_seadramon(f)
		return
	match f.state:
		STATE_APPEAR:
			_move(f, APPEAR_STEP)
			f.transparency = clampi(f.transparency + FADE_STEP, 0, OPAQUE)
			if f.transparency == OPAQUE:
				_pick_next_move(f)
		STATE_IDLE:
			f.lifetime -= 1
			if f.lifetime == 0:
				_face_away(f, tamer_pos)
			else:
				f.time_next_move -= 1
				if f.time_next_move == 0:
					_new_target(f)
				else:
					_checks(f)
		STATE_SWIM:
			_move(f, f.time_this_move)
			f.time_this_move -= f.time_this_move >> 3
			if f.time_this_move < SWIM_STOP:
				_pick_next_move(f)
			else:
				_checks(f)
		STATE_LEAVE:
			_move(f, LEAVE_STEP)
			f.transparency = clampi(f.transparency - FADE_STEP, 0, OPAQUE)
			if f.transparency == 0:
				f.active = false
				fish_count -= 1
	f.frames_on_state += 1
	f.anim_phase += 1


## pickNextMove: wait customRandom(moveDelayMin, moveDelayMax) frames.
func _pick_next_move(f: Fish) -> void:
	var delay: Array = kinds[f.kind]["move_delay"]
	f.time_next_move = Rng.custom_random(int(delay[0]), int(delay[1]))
	f.state = STATE_IDLE
	f.frames_on_state = -1


## checkAttractor and the bait (fish.c:2748-2768).
func _checks(f: Fish) -> void:
	if attractor != null:
		if PsxMath.get_distance(attractor.pos.x - f.pos.x, 0, attractor.pos.z - f.pos.z) <= attract_radius:
			escape_timer = ESCAPE_FRAMES
			_face_away(f, attractor.pos)
			return
	var kind_bait = kinds[f.kind].get("bait")
	if kind_bait == null or bait != int(kind_bait["id"]):
		return
	var d := PsxMath.get_distance(swimmer_pos.x - f.pos.x, 0, swimmer_pos.z - f.pos.z)
	if d < BAIT_NEAR or d >= BAIT_FAR:
		return
	f.rotation = PsxMath.to_euler_angles(swimmer_pos.x - f.pos.x, 0, swimmer_pos.z - f.pos.z)
	f.time_this_move = clampi(PsxMath.get_distance(swimmer_pos.x - f.pos.x, 0, swimmer_pos.z - f.pos.z) / SWIM_DIVISOR,
			APPROACH_MIN, SWIM_MAX)
	f.time_this_move = APPROACH_MIN if f.time_this_move < APPROACH_MIN else mini(f.time_this_move, f.size)
	f.state = STATE_SWIM
	f.frames_on_state = -1


## newTarget (fish.c:2776).
func _new_target(f: Fish) -> void:
	var target := random_point_in_spot(f.kind, Vector3i.ZERO)
	f.rotation = PsxMath.to_euler_angles(target.x - f.pos.x, 0, target.z - f.pos.z)
	f.time_this_move = PsxMath.get_distance(target.x - f.pos.x, 0, target.z - f.pos.z) / SWIM_DIVISOR
	f.time_this_move = clampi(f.time_this_move, 0, SWIM_MAX)
	f.time_this_move = clampi(f.time_this_move, 0, f.size)
	f.state = STATE_SWIM
	f.frames_on_state = -1


## faceAttractor / faceTamer: heading away from `from` (+0x800), state 0x1E.
func _face_away(f: Fish, from: Vector3i) -> void:
	f.rotation = PsxMath.to_euler_angles(from.x - f.pos.x, 0, from.z - f.pos.z)
	f.rotation.y = PsxMath.s16(f.rotation.y + 0x800)
	f.state = STATE_LEAVE
	f.frames_on_state = -1


## rotateVector(rotation, (0, 0, step)) added to the position.
static func forward(rotation: Vector3i, step: int) -> Vector3i:
	return PsxMath.apply_matrix_lv(PsxMath.rot_matrix_yxz(rotation), Vector3i(0, 0, step))


func _move(f: Fish, step: int) -> void:
	f.pos += forward(f.rotation, step)


# --- Seadramon (§2.3) ----------------------------------------------------------------------------

## The waypoint i on the ground, or `fallback`.
func _waypoint(i: int, fallback: Vector3i) -> Vector3i:
	var path: Array = map.get("seadramon_path", [])
	if i < 0 or i >= path.size():
		return fallback
	var g = camera.ground_at(int(path[i][0]), int(path[i][1]))
	return g if g != null else fallback


## FISH_spawnSeadramon (fish.c:2618).
func spawn_seadramon(f: Fish) -> void:
	f.kind = SEADRAMON
	var size: Array = kinds[SEADRAMON]["size"]
	f.size = Rng.custom_random(int(size[0]), int(size[1]))
	f.lifetime = Rng.custom_random(LIFETIME.x, LIFETIME.y)
	f.state = 0
	f.frames_on_state = 0
	f.transparency = 0
	f.time_this_move = 0
	f.pos = _waypoint(0, f.pos)
	f.state = 1
	var next := _waypoint(1, Vector3i.ZERO)
	f.rotation = PsxMath.to_euler_angles(next.x - f.pos.x, 0, next.z - f.pos.z)


## FISH_tickSeadramon (fish.c:2642).
func tick_seadramon(f: Fish) -> void:
	var path_length: int = map.get("seadramon_path", []).size()
	if f.state >= path_length:
		f.time_this_move = clampi(f.time_this_move + SEADRAMON_ACCEL, 0, SWIM_MAX)
		_move(f, f.time_this_move)
		f.transparency = clampi(f.transparency - FADE_STEP, 0, OPAQUE)
		if f.transparency <= 0:
			f.active = false
			fish_count -= 1
			return
	else:
		var target := _waypoint(f.state, f.pos)
		f.transparency = clampi(f.transparency + FADE_STEP, 0, OPAQUE)
		var rot := PsxMath.to_euler_angles(target.x - f.pos.x, 0, target.z - f.pos.z)
		var turn := (rot.y - f.rotation.y) & 0xFFF
		if turn >= 0x800:
			turn -= 0x1000
		f.time_this_move += -SEADRAMON_ACCEL if turn != 0 else SEADRAMON_ACCEL
		f.time_this_move = clampi(f.time_this_move, 0, SWIM_MAX)
		f.rotation.y = PsxMath.s16(f.rotation.y + clampi(turn, -SEADRAMON_TURN, SEADRAMON_TURN))
		_move(f, f.time_this_move)
		var d := PsxMath.get_distance(target.x - f.pos.x, 0, target.z - f.pos.z)
		if d <= maxi(f.time_this_move, SEADRAMON_ACCEL):
			f.state += 1
		f.time_this_move = maxi(d / 10, 1)
	f.frames_on_state += 1
	f.anim_phase += 1
	push_seadramon_segment(f.rotation)


## FISH_pushSeadramonSegment (fish.c:2557).
func push_seadramon_segment(rotation: Vector3i) -> void:
	for i in range(SEADRAMON_HISTORY - 1, 0, -1):
		seadramon_history[i] = seadramon_history[i - 1]
	seadramon_history[0] = rotation


# --- Ripples and markers (§2.5) ------------------------------------------------------------------

## FISH_allocRipple (fish.c:1918).
func _alloc_ripple() -> Ripple:
	if ripple_count >= RIPPLE_COUNT:
		return null
	var i := ripple_next
	while true:
		if not ripples[i].active:
			ripple_next = i
			return ripples[i]
		i = (i + 1) % RIPPLE_COUNT
		if i == ripple_next:
			break
	ripple_count = RIPPLE_COUNT
	return null


## FISH_spawnRipple (fish.c:1946).
func spawn_ripple(kind: int, pos: Vector3i, attract: int, spread: int, scale: int) -> void:
	var r := _alloc_ripple()
	if r == null:
		return
	ripple_count += 1
	r.active = true
	r.pos = pos
	r.kind = kind
	r.frame = 0
	r.sprite = 0
	r.pos.x += Rng.custom_random(-spread, spread)
	r.pos.z += Rng.custom_random(-spread, spread)
	r.pos.y = 0
	r.scale = scale
	if attract != 0:
		attractor = r
		attract_radius = attract


func _free_ripple(r: Ripple) -> void:
	if r.active:
		r.active = false
		ripple_count -= 1


## FISH_tickRipple (fish.c:1841).
func tick_ripple(r: Ripple) -> void:
	if not r.active:
		return
	match r.kind:
		0:
			r.sprite = RIPPLE_KIND_0[r.frame / 2]
		-1:
			r.sprite = RIPPLE_KIND_1[r.frame]
		-2:
			r.sprite = RIPPLE_KIND_2[r.frame / 3]
		-3:
			r.sprite = RIPPLE_KIND_3[r.frame]
		-4:
			r.sprite = RIPPLE_KIND_4[r.frame]
		_:
			_free_ripple(r)
			return
	r.frame += 1
	if r.sprite == -1 or r.sprite >= RIPPLE_LAST_SPRITE:
		_free_ripple(r)


## FISH_tickRipples (fish.c:1973).
func tick_ripples() -> void:
	for r in ripples:
		if r.active:
			tick_ripple(r)
	if attractor != null and not attractor.active:
		attractor = null


## FISH_allocMarker (fish.c:1752).
func _alloc_marker() -> Marker:
	if marker_count >= MARKER_COUNT:
		return null
	var i := marker_next
	while true:
		if not markers[i].active:
			marker_next = i
			return markers[i]
		i = (i + 1) % MARKER_COUNT
		if i == marker_next:
			break
	marker_count = MARKER_COUNT
	return null


## FISH_spawnMarker (fish.c:1780).
func spawn_marker(sprite: int, pos: Vector3i) -> void:
	var m := _alloc_marker()
	if m == null:
		return
	marker_count += 1
	m.active = true
	m.pos = pos
	m.sprite = sprite
	m.lifetime = MARKER_FRAMES


## FISH_tickMarkers (fish.c:1795).
func tick_markers() -> void:
	for m in markers:
		if m.active:
			m.lifetime -= 1
			if m.lifetime == 0:
				m.active = false
				marker_count -= 1


## FISH_clearMarkers (fish.c:1819).
func clear_markers() -> void:
	for m in markers:
		m.active = false
	marker_count = 0


# --- The bite test (§2.6) ------------------------------------------------------------------------

## FISH_findFishToBite (fish.c:3036): the first fish near `loc` that takes the bait, or null. Each
## fish tried gets a marker. `bite_chance` is GameData.fishing_bite_chance (bait, kind -> %).
func find_fish_to_bite(loc: Vector3i, bait_item: int, bite_chance: Callable) -> Fish:
	if hooked_active:
		return null
	for f in fish:
		if not f.active:
			continue
		if PsxMath.get_distance(f.pos.x - loc.x, 0, f.pos.z - loc.z) >= BITE_RANGE:
			continue
		var chance := 0
		if f.kind == SEADRAMON:
			if vsync_frame % SEADRAMON_BITE_EVERY != 0:
				continue
			chance = SEADRAMON_BITE_CHANCE
		else:
			if vsync_frame % BITE_EVERY != 0:
				continue
			if f.state != STATE_IDLE and f.state != STATE_SWIM:
				continue
			chance = int(bite_chance.call(bait_item, f.kind)) if bite_chance.is_valid() else 0
		spawn_marker(MARKER_NO_BITE if chance == 0 else MARKER_BITE, f.pos)
		if chance < Rng.custom_random(1, 100):
			continue
		return f
	return null
