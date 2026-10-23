class_name Partner
extends Node3D
## The partner Digimon on the field (specs/partner.md, specs/care.md): partnerTickOverworld with
## the normal state (map.c partnerTickCollision, partner.c partnerTickWalking, the care rules) and
## the sleep and wild-poop scenes. Decisions run once per game frame (tick, on GameLoop.frame,
## before the clock); the animation and its root-motion movement run every Godot frame like the
## tamer's.

## PartnerPara.condition bits read here (params.h:10-16).
const TIRED_LOOK := 0x1 | 0x2 | 0x20 | 0x40
const UNHAPPY := 0x10
const ANIM_IDLE := 0
const ANIM_TIRED_IDLE := 1
const ANIM_WALK := 2
const ANIM_TIRED_WALK := 3
const ANIM_RUN := 4
const WAYPOINTS := 30
## COLLISION_GRACE_ROTATION (map.c:346): directions collisionGrace tries, by rotation / 512.
const GRACE := [
	[0x000, 0x400, 0xC00, 0x800], [0x400, 0x000, 0x800, 0xC00], [0x400, 0x800, 0x000, 0xC00],
	[0x800, 0x400, 0xC00, 0x000], [0x800, 0xC00, 0x400, 0x000], [0xC00, 0x800, 0x000, 0x400],
	[0xC00, 0x000, 0x800, 0x400], [0x000, 0xC00, 0x400, 0x800],
]
## entityCheckCollision results.
const FREE := -1
const HIT_TAMER := 0
const HIT_MAP := 10

## PARTNER_STATE values ported so far (partnerTickOverworld, partner.c:218-258).
const STATE_NORMAL := 1
const STATE_SLEEP := 3
const STATE_WILD_POOP := 7
## Waits idling while the tamer is busy (e.g. his message box).
const STATE_IDLE := 11

var field: FieldMap
var tamer: Node3D
var game_state: Node
## The care rules (specs/care.md); null: the partner only follows.
var care: Care
var clock: Clock
var fade: Fade
## PARTNER_STATE / PARTNER_SUB_STATE (partner_impl.c:221), not saved.
var state := STATE_NORMAL
var sub_state := 0
var digimon := ""
## DIGIMON_DATA.radius.
var radius := 100
## PSX rotation.vy (4096 per turn).
var direction := 0
var animator: PsxAnimator
var on_screen := true

## partner.c state (PARTNER_ANIMATION, STOP_DISTANCE_TIMER, EMOTION_ANIM_TIMEOUT, IS_STANDING_STILL).
var partner_animation := ANIM_IDLE
var stop_distance_timer := 0
var emotion_anim_timeout := 0
var is_standing_still := 0

## PARTNER_WAYPOINT_* (map.c): a ring of 30 tiles.
var waypoint_x := []
var waypoint_y := []
var waypoint_current := 0
var waypoint_count := 0
var tamer_previous_tile := Vector2i.ZERO

## DIGIMON_DATA[0].radius: the tamer's collision square.
var tamer_radius := 0
## Ground distance the root motion moved during the last game frame: the step entityMoveForward
## probes with (the animation's forward momentum; 0 while idling).
var step := 0.0

var _skeleton: Skeleton3D
var _model: Node3D


func _ready() -> void:
	waypoint_x.resize(WAYPOINTS)
	waypoint_y.resize(WAYPOINTS)
	waypoint_x.fill(0)
	waypoint_y.fill(0)


## Loads the model of a Digimon (key or id) through its files component.
func load_digimon(data: Node, ref: Variant) -> bool:
	var record: Dictionary = data.digimon(ref)
	var mmd: String = data.digimon_file(ref).get("mmd", "")
	if record.is_empty() or mmd == "":
		push_error("Partner: no model for %s" % ref)
		return false
	var rel := "mmd_files/%s/%s.gltf" % [mmd.get_slice("/", 1), mmd.get_file().get_basename()]
	var model := Content.load_model(rel)
	if model == null:
		return false
	if _model != null:
		_model.queue_free()
	_model = model
	add_child(model)
	digimon = record.get("key", str(ref))
	radius = int(record["radius"])
	tamer_radius = int(data.digimon(0).get("radius", 0))
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var anim_root := player.get_node(player.root_node)
	player.root_motion_track = NodePath("%s:bone_0" % anim_root.get_path_to(_skeleton))
	animator = PsxAnimator.new(player, Content.load_json(rel))
	start_animation(ANIM_IDLE)
	return true


## loadMapEntities (tamer.c:400-410): 200 units from the tamer's spawn on the side its rotation
## points to, facing the tamer; then setupPartnerOnWarp (partner_impl.c:848).
func place_for_spawn(spawn: Dictionary) -> void:
	var p: Vector3 = spawn["position"]
	var rotation_vy: int = spawn["rotation"]
	var x := int(p.x)
	var z := int(-p.z)
	if rotation_vy <= 0x200 or rotation_vy > 0xE00:
		z += 200
	elif rotation_vy <= 0x600:
		x += 200
	elif rotation_vy <= 0xA00:
		z -= 200
	else:
		x -= 200
	position = Vector3(x, p.y, -z)
	_set_direction((rotation_vy + 0x800) % 0x1000)
	start_animation(ANIM_IDLE)
	initialize_waypoints()
	# setupPartnerOnWarp: normal state, and the time on the map starts over.
	set_state(STATE_NORMAL)
	if game_state != null:
		game_state.state["partner"]["care"]["area_effect_timer"] = 0


func _process(delta: float) -> void:
	if animator == null or field == null:
		return
	var motion := _skeleton.global_basis * animator.advance(delta)
	step += Vector2(motion.x, motion.z).length()
	_move(motion)


## partnerTickOverworld (partner.c:213): one game frame of the partner's state, then the screen
## test and the care boundaries.
func tick() -> void:
	if animator == null or field == null or tamer == null:
		return
	match state:
		STATE_NORMAL:
			tick_normal()
		STATE_SLEEP:
			tick_sleep()
		STATE_WILD_POOP:
			tick_wild_poop()
		STATE_IDLE:
			tick_idle()
	step = 0.0
	on_screen = field.is_on_screen(global_position)
	if care != null:
		care.tick_condition_boundaries()
	if game_state != null:
		game_state.state["partner"]["position"] = _psx(position)
		game_state.state["tamer"]["position"] = _psx(tamer.position)


## partnerSetState (partner.c:1087).
func set_state(value: int) -> void:
	state = value
	sub_state = 0


## partnerTickNormal (partner.c:268).
func tick_normal() -> void:
	tick_collision()
	tick_walking()
	if care == null:
		return
	care.tick_conditions()
	if care.tick_pooping_mechanic():
		set_state(STATE_WILD_POOP)
	# A poop eater found a pile: partnerTickEatShit (state 9) comes with the poop eaters.
	care.tick_poop_detection()
	care.handle_condition_bubble()


# --- partnerTickSleep (partner.c:278) ----------------------------------------------------------

## The sleep scene, started by the menu's "Sleep" (specs/care.md §2.13). The save prompt after it
## (sub-state 5) is skipped until the menus exist.
func tick_sleep() -> void:
	match sub_state:
		0:
			if clock != null:
				clock.running = false
			tamer.camera_follow = false
			if closeness() != 2:
				start_animation(ANIM_WALK)
			tamer.state = Tamer.STATE_STILL
			tick_partner_waypoints()
			sub_state = 1
		1:
			tamer.look_at_psx(int(position.x), int(-position.z))
			look_at_psx(int(tamer.position.x), int(-tamer.position.z))
			if closeness() == 2:
				# playSound(0, 15): later with audio.
				tamer.play_scene_animation(8)
				start_animation(ANIM_IDLE)
				sub_state = 2
		2:
			if tamer.scene_animation_done():
				_play_or_skip(11)
				sub_state = 3
		3:
			if animator.frame >= animator.frame_count:
				_play_or_skip(9)
				sub_state = 4
		4:
			if animator.frame >= animator.frame_count - 5:
				if fade != null:
					fade.fade_to_black(40)
				sub_state = 5
		5:
			if fade == null or fade.out_current > 39:
				if care != null:
					care.sleep_regen()
					care.handle_sleeping()
				sub_state = 6
		6:
			if fade != null:
				fade.fade_from_black(40)
			start_animation(ANIM_IDLE)
			if clock != null:
				clock.update_time_of_day()
			sub_state = 7
		7:
			if fade == null or fade.in_current > 34:
				set_state(STATE_NORMAL)
				tamer.state = Tamer.STATE_FREE
				tamer.camera_follow = true
				# handleSpecialEvolutions(2): the evolution step.
				if clock != null:
					clock.running = true


## partnerTickIdle (partner.c:733).
func tick_idle() -> void:
	if sub_state == 0:
		start_animation(ANIM_IDLE)
		sub_state = 1


## startAnimation of a scene animation; one the model lacks counts as played, so the scene goes
## on (the original would wait on the previous animation forever).
func _play_or_skip(id: int) -> void:
	if not animator.play(id):
		animator.frame = animator.frame_count


# --- tickWildPoop (partner.c:593) --------------------------------------------------------------

func tick_wild_poop() -> void:
	match sub_state:
		0:
			start_animation(ANIM_RUN)
			tamer.state = Tamer.STATE_STILL
			tamer.look_at_psx(int(position.x), int(-position.z))
			tamer.camera_follow = false
			sub_state = 1
		1:
			look_at_psx(int(tamer.position.x), int(-tamer.position.z))
			if closeness() > 0:
				_play_or_skip(10)
				sub_state = 2
		2:
			if animator.frame >= animator.frame_count:
				if care != null:
					care.create_poop_pile(tile(), direction)
					care.handle_wild_poop()
				_play_or_skip(12)
				sub_state = 3
		3:
			if animator.frame >= animator.frame_count:
				tamer.state = Tamer.STATE_FREE
				set_state(STATE_NORMAL)
				tamer.camera_follow = true
				if clock != null:
					clock.add_tamer_level(1, -1)


# --- tickPartnerWaypoints (map.c:3588) ---------------------------------------------------------

## An off-screen partner drops the waypoints up to the newest off-screen one, then jumps to the
## first off-screen tile on the line from the tamer to it (getClosestTileOffScreen).
func tick_partner_waypoints() -> void:
	if on_screen:
		return
	var count := waypoint_count
	var index := 0
	while count > 0:
		index = (waypoint_current + count - 1) % WAYPOINTS
		if field.is_tile_off_screen(_waypoint(index)):
			break
		count -= 1
	if count != 0:
		while waypoint_current != index:
			pop_waypoint()
		pop_waypoint()
	var to := closest_tile_off_screen(_tile(tamer.position), tile())
	if to.x != -1:
		var centre := FieldMap.tile_centre(to)
		position = Vector3(centre.x, position.y, -centre.y)


## getClosestTileOffScreen (map.c:2956): walks the line from `from` towards `to` and returns the
## first tile off screen, or (-1, -1).
func closest_tile_off_screen(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx := to.x - from.x
	var dy := to.y - from.y
	var x := from.x
	var y := from.y
	var major_x := absi(dx) >= absi(dy)
	var dist := absi(dx) if major_x else absi(dy)
	if dist == 0:
		# Division by zero in the C; the partner is on the tamer's tile.
		return Vector2i(-1, -1)
	var minor := dy if major_x else dx
	var quot := minor / dist
	var rem := minor % dist
	var rem_sign := -1 if rem < 0 else 1
	rem = absi(rem)
	var acc := dist
	for _i in dist:
		var side := 0
		if rem != 0:
			acc -= rem
			if acc <= 0:
				side = rem_sign
				acc += dist
		else:
			side = quot
		if major_x:
			y += side
			x += 1 if dx > 0 else -1
		else:
			x += side
			y += 1 if dy > 0 else -1
		if field.is_tile_off_screen(Vector2i(x, y)):
			return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- partnerTickCollision (map.c:3267) ---------------------------------------------------------

func tick_collision() -> void:
	var tamer_tile := _tile(tamer.position)
	if tamer_tile != tamer_previous_tile:
		var partner_tile := _tile(position)
		if field.is_five_tile_wide_path_blocked(tamer_tile, partner_tile):
			if waypoint_count != 0:
				var last := (waypoint_current + waypoint_count - 1) % WAYPOINTS
				if field.is_five_tile_wide_path_blocked(tamer_tile, _waypoint(last)):
					set_waypoint((waypoint_current + waypoint_count) % WAYPOINTS, tamer_previous_tile)
			else:
				# Quirk kept: initializePartnerWaypoint resets the "previous" tile to the tamer's
				# current tile first, so the first waypoint is where the tamer is now.
				initialize_waypoints()
				set_waypoint(waypoint_current, tamer_previous_tile)
		else:
			initialize_waypoints()
	if waypoint_count >= 2:
		for i in 3:
			# posmod: the C index can go negative here (undefined in C).
			var index := posmod(waypoint_current + waypoint_count - 2 - i, WAYPOINTS)
			if not field.is_five_tile_wide_path_blocked(tamer_tile, _waypoint(index)):
				waypoint_count -= i + 1
				break
			if index == waypoint_current:
				break
	if waypoint_count != 0 and field.is_tile_off_screen(_waypoint(waypoint_current)) and not on_screen:
		var centre := FieldMap.tile_centre(_waypoint(waypoint_current))
		position = Vector3(centre.x, position.y, -centre.y)
		pop_waypoint()
	var previous_direction := direction
	if waypoint_count != 0:
		var target := _waypoint(waypoint_current)
		var centre := FieldMap.tile_centre(target)
		look_at_psx(centre.x, centre.y)
		if _tile(position) == target:
			pop_waypoint()
	else:
		look_at_psx(int(tamer.position.x), int(-tamer.position.z))
	# An entity collision (0-9) keeps the old rotation and turns along the obstacle.
	if probe(direction) == HIT_TAMER:
		_set_direction(previous_direction)
		collision_grace()
	tamer_previous_tile = tamer_tile


## entityCheckCollision as a probe (map.c:3400): one step (entityMoveForward: the animation's
## forward motion of a game frame, `step`) along `rotation_vy` from here. FREE, HIT_TAMER or
## HIT_MAP; the position is not changed. `ignore_tamer`: the tamer is the `source` argument,
## which the entity loop skips.
func probe(rotation_vy: int, ignore_tamer := false) -> int:
	var angle := (rotation_vy - 0x800) * PI / 0x800
	# The C deltas are whole units: a step under 1 unit (idling) probes nothing.
	var dx := float(int(sin(angle) * step))
	var dz := float(int(cos(angle) * step))
	if rotation_vy == 0x400 or rotation_vy == 0xC00:
		dz = 0.0
	if rotation_vy == 0 or rotation_vy == 0x800:
		dx = 0.0
	var x := position.x
	var z := -position.z
	if _blocked(x + dx, z + dz, dx, dz):
		return HIT_MAP
	if not ignore_tamer and hits_tamer(x + dx, z + dz, dx, dz):
		return HIT_TAMER
	return FREE


## collisionGrace (map.c:3466): try the 4 directions of COLLISION_GRACE_ROTATION and turn at
## most 0x50 per frame towards the first free one; with none free, turn 32. partnerTickCollision
## passes the tamer as the source, so the tamer never blocks here: bumping only the tamer keeps
## the old rotation and nothing else.
func collision_grace() -> void:
	if probe(direction, true) == FREE:
		return
	var start := direction
	for candidate: int in GRACE[start / 512]:
		if probe(candidate, true) == FREE:
			var clockwise: int = start - candidate
			if clockwise < 0:
				clockwise = (clockwise + 0x1000) & 0xFFF
			var counter: int = candidate - start
			if counter < 0:
				counter = (counter + 0x1000) & 0xFFF
			if clockwise - counter < 0:
				_set_direction(start + 0xFB0 if clockwise >= 0x51 else start + 0x1000 - clockwise)
			else:
				_set_direction(start + 0x50 if counter >= 0x51 else start + counter)
			return
	_set_direction(start + 32)


## initializePartnerWaypoint (map.c:2926).
func initialize_waypoints() -> void:
	waypoint_current = 0
	waypoint_count = 0
	if tamer != null:
		tamer_previous_tile = _tile(tamer.position)
	waypoint_x.fill(0)
	waypoint_y.fill(0)


## setPartnerWaypoint (map.c:3375).
func set_waypoint(index: int, tile: Vector2i) -> void:
	waypoint_x[index] = tile.x
	waypoint_y[index] = tile.y
	waypoint_count += 1


## popPartnerWaypoint (map.c:2942).
func pop_waypoint() -> void:
	waypoint_count -= 1
	waypoint_current = (waypoint_current + 1) % WAYPOINTS


## entityLookAtLocation (map.c:3389): rotation.vy = _atan(dz, dx) = 0x800 + atan2(dx, dz).
func look_at_psx(target_x: int, target_z: int) -> void:
	var dx := target_x - int(position.x)
	var dz := target_z - int(-position.z)
	if dx == 0 and dz == 0:
		return
	_set_direction((0x800 + roundi(atan2(dx, dz) * 0x800 / PI)) & 0xFFF)


# --- partnerTickWalking (partner.c:827) --------------------------------------------------------

## getPartnerTamerCloseness (partner.c:971): 0 far, 1 near, 2 close.
func closeness() -> int:
	var dx := int(tamer.position.x) - int(position.x)
	var dz := int(-tamer.position.z) - int(-position.z)
	var distance := dx * dx + dz * dz
	var walk := (radius * 5 / 2) * (radius * 5 / 2)
	var sprint := (radius * 7 / 2) * (radius * 7 / 2)
	if distance > sprint:
		return 0
	if distance >= walk:
		return 1
	return 2


func tick_walking() -> void:
	var a := animator
	var unhappy := _condition() & UNHAPPY != 0
	match closeness():
		0:
			if (a.anim_id == ANIM_WALK or a.anim_id == ANIM_TIRED_WALK) and not unhappy:
				if a.loop_count == PsxAnimator.ENDLESS:
					a.finish_loop()
				if a.loop_count == 0:
					partner_animation = ANIM_RUN
			elif a.anim_id != ANIM_RUN and not unhappy:
				partner_animation = ANIM_RUN
			else:
				partner_animation = ANIM_WALK if unhappy else ANIM_RUN
				if partner_animation != a.anim_id:
					start_animation(partner_animation)
			is_standing_still = 1
		1:
			if a.anim_id == ANIM_RUN:
				set_slow_walking()
			elif a.anim_id != ANIM_WALK and a.anim_id != ANIM_TIRED_WALK:
				if a.loop_count == PsxAnimator.ENDLESS:
					a.finish_loop()
				if a.frame >= a.frame_count:
					set_slow_walking()
			elif a.loop_count == 0:
				set_slow_walking()
			emotion_anim_timeout = -1
			is_standing_still = 1
		2:
			if (a.anim_id == ANIM_IDLE or a.anim_id == ANIM_TIRED_IDLE) and is_standing_still != 2:
				update_condition_animation()
			if a.anim_id > 1 and a.anim_id < 5:
				# entityCheckCollision == 0: the step runs into the tamer.
				var bumped := probe(direction) == HIT_TAMER
				if a.loop_count == PsxAnimator.ENDLESS:
					a.finish_loop()
				if a.loop_count == 0 or bumped:
					_stop_and_idle()
			if (a.anim_id == ANIM_IDLE or a.anim_id == ANIM_TIRED_IDLE) and stop_distance_timer > a.frame_count * emotion_anim_timeout:
				update_condition_animation()
			if a.anim_id >= 5 and a.anim_id < 8 and not a.playing:
				_stop_and_idle()
			elif a.anim_id != ANIM_IDLE and a.anim_id != ANIM_TIRED_IDLE and not a.playing:
				_stop_and_idle()
			stop_distance_timer += 1
			is_standing_still = 2
	if partner_animation != a.anim_id:
		start_animation(partner_animation)
		stop_distance_timer = 0


func _stop_and_idle() -> void:
	emotion_anim_timeout = Rng.random_limit(5) + 1
	set_idle()
	stop_distance_timer = 0


## setPartnerSlowWalking (partner.c:998).
func set_slow_walking() -> void:
	partner_animation = ANIM_TIRED_WALK if _condition() & TIRED_LOOK else ANIM_WALK
	start_animation(partner_animation)


## setPartnerIdle (partner.c:1065), US / JP_TRIAL-and-later version.
func set_idle() -> void:
	if (partner_animation != ANIM_TIRED_IDLE and partner_animation != ANIM_IDLE) or is_standing_still != 2:
		partner_animation = ANIM_TIRED_IDLE if _condition() & TIRED_LOOK else ANIM_IDLE
		start_animation(partner_animation)


## updateConditionAnimation (partner.c:1012).
func update_condition_animation() -> void:
	var cond := _condition()
	var current := animator.anim_id
	if cond == 0:
		var happiness: int = game_state.state["partner"]["care"]["happiness"] if game_state != null else 0
		if happiness < -0x1E:
			partner_animation = 7
		elif happiness >= 0x1F:
			partner_animation = 5
		else:
			set_idle()
	elif cond & 0x20 or cond & 0x40:
		if current != 0x0E:
			partner_animation = 0x0E
	elif cond & 0x08:
		if current != 0x10:
			partner_animation = 0x10
	elif cond & 0x04:
		if current != 0x0F:
			partner_animation = 0x0F
	elif cond & 0x02:
		if current != 0x12:
			partner_animation = 0x12
	elif cond & 0x01:
		if current != 0x11:
			partner_animation = 0x11
	elif cond & 0x10:
		if current != 0x13:
			partner_animation = 0x13


func start_animation(id: int) -> void:
	if animator != null:
		animator.play(id)


# --- Movement (like the tamer: specs/partner.md §3) --------------------------------------------

## Root motion against the map only: the original's entity checks restore the position and steer
## (tick_collision, tick_walking) but never block the momentum, so the partner reaches the close
## range and stops there. The map blocks only in the normal state: the scenes (sleep, wild poop)
## never call entityCheckCollision, so the partner walks straight to the tamer, walls or not
## (specs/care.md §2.10; blocking there left it running into a wall forever).
func _move(motion: Vector3) -> void:
	var x := position.x
	var z := -position.z
	var dx := motion.x
	var dz := -motion.z
	if direction == 0x400 or direction == 0xC00:
		dz = 0.0
	if direction == 0 or direction == 0x800:
		dx = 0.0
	if dx == 0.0 and dz == 0.0:
		return
	if state != STATE_NORMAL:
		pass
	elif not _blocked(x + dx, z + dz, dx, dz):
		pass
	elif not _blocked(x + dx, z, dx, 0.0):
		dz = 0.0
	elif not _blocked(x, z + dz, 0.0, dz):
		dx = 0.0
	else:
		return
	position.x += dx
	position.z -= dz


## entityCheckEntityCollision (map.c:3740), the non-tamer branch: after the step to (x, z), the
## partner's box edge on the side it moves touches the tamer's square (isRectInRect).
func hits_tamer(x: float, z: float, dx: float, dz: float) -> bool:
	if tamer == null:
		return false
	var tx := tamer.position.x
	var tz := -tamer.position.z
	var square := Rect2(tx - tamer_radius, tz - tamer_radius, tamer_radius * 2, tamer_radius * 2)
	var left := x - radius
	var right := x + radius
	var near := z - radius
	var far := z + radius
	if dx < 0 and _touches(square, left, near, left, far):
		return true
	if dx > 0 and _touches(square, right, near, right, far):
		return true
	if dz < 0 and _touches(square, left, near, right, near):
		return true
	if dz > 0 and _touches(square, left, far, right, far):
		return true
	return false


static func _touches(square: Rect2, x1: float, z1: float, x2: float, z2: float) -> bool:
	return x2 >= square.position.x and x1 <= square.end.x and z2 >= square.position.y and z1 <= square.end.y


func _blocked(x: float, z: float, dx: float, dz: float) -> bool:
	return field.blocked(int(x), int(z), int(signf(dx)), int(signf(dz)), radius)


func _set_direction(vy: int) -> void:
	direction = vy & 0xFFF
	rotation.y = Content.psx_yaw(direction)


func _condition() -> int:
	return game_state.state["partner"]["care"]["condition"] if game_state != null else 0


## getModelTile of the partner.
func tile() -> Vector2i:
	return _tile(position)


func _waypoint(index: int) -> Vector2i:
	return Vector2i(waypoint_x[index], waypoint_y[index])


static func _tile(p: Vector3) -> Vector2i:
	return FieldMap.model_tile(int(p.x), int(-p.z))


static func _psx(p: Vector3) -> Array:
	return [int(p.x), int(-p.y), int(-p.z)]
