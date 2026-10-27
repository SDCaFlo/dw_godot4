class_name Partner
extends FieldDigimon
## The partner Digimon on the field (specs/partner.md, specs/care.md): partnerTickOverworld with
## the normal state (map.c partnerTickCollision, partner.c partnerTickWalking, the care rules) and
## the sleep and wild-poop scenes. Decisions run once per game frame (tick, on GameLoop.frame,
## before the clock); the animation and its root-motion movement run every Godot frame like the
## tamer's (FieldDigimon).

## PartnerPara.condition bits read here (params.h:10-16).
const TIRED_LOOK := 0x1 | 0x2 | 0x20 | 0x40
const UNHAPPY := 0x10
const ANIM_IDLE := 0
const ANIM_TIRED_IDLE := 1
const ANIM_WALK := 2
const ANIM_TIRED_WALK := 3
const ANIM_RUN := 4
const WAYPOINTS := 30
## tickPartnerToilet's squat and its pans' speed.
const ANIM_TOILET := 10
const TOILET_PAN_SPEED := 20

## PARTNER_STATE values ported so far (partnerTickOverworld, partner.c:218-258).
const STATE_NORMAL := 1
const STATE_SLEEP := 3
## The menu's Use: the partner takes the tamer's item (partnerTickFeedItem, specs/inventory.md §2.8).
const STATE_FEED := 5
## The menu's Scold and Praise (partnerTickPraiseScold, specs/game_menu.md §2.5).
const STATE_SCOLD := 4
const STATE_PRAISE := 15
## The toilet scene, started by CALL_DIGIMON_ROUTINE 0 (specs/care.md §2.16).
const STATE_TOILET := 6
const STATE_WILD_POOP := 7
## Waits idling while the tamer is busy (e.g. his message box).
const STATE_IDLE := 11
## A script moves it (scriptSetEntityWalking): nothing ticks but the animation (partner.c:246).
const STATE_SCRIPT := 12
## A training station moves it: only the condition bubble (partner.c:244; specs/training.md §2.6).
const STATE_TRAINING := 10
## An evolution (partnerTickEvolving, specs/evolution.md §2.7).
const STATE_EVOLVING := 13

var tamer: Node3D
var game_state: Node
## The care rules (specs/care.md); null: the partner only follows.
var care: Care
var clock: Clock
var fade: Fade
## The map's toilet (GameData: the map entity's "toilet" component) and the sync bit the scene sets
## (ScriptContext.sync_bit, SOME_SCRIPT_SYNC_BIT).
var data: Node
var script_ctx: ScriptContext
## playSound(0, n) of its scenes (the Sound node).
var sound: Node
## The item rules the feeding scene asks (specs/inventory.md §4).
var item_use: ItemUse
## The evolution's scene (getEvoSequenceState); null: the evolution applies at once.
var evolution_scene: EvolutionScene
## Callable(on_done: Callable) -> void: opens the sleep save prompt (sub-state 5).
var sleep_save_prompt: Callable
var _tamer_hand_reset := false
## PARTNER_STATE / PARTNER_SUB_STATE (partner_impl.c:221), not saved.
var state := STATE_NORMAL
var sub_state := 0

## partner.c state (PARTNER_ANIMATION, STOP_DISTANCE_TIMER, EMOTION_ANIM_TIMEOUT, IS_STANDING_STILL).
var partner_animation := ANIM_IDLE
var stop_distance_timer := 0
var emotion_anim_timeout := 0
var is_standing_still := 0
## MAIN_D_80134E28 (partner.c:121, :378, :381): frames waiting for closeness / approach in care scenes.
var approach_timer := 0

## PARTNER_WAYPOINT_* (map.c): a ring of 30 tiles.
var waypoint_x := []
var waypoint_y := []
var waypoint_current := 0
var waypoint_count := 0
var tamer_previous_tile := Vector2i.ZERO

## DIGIMON_DATA[0].radius: the tamer's collision square (for the tests without an entity table).
var tamer_radius := 0
## TOILET_TARGET_POS1 / 2 (PSX x, z): the point it walks to first and back to, and the toilet.
var toilet_pos1 := Vector2i.ZERO
var toilet_pos2 := Vector2i.ZERO


func _ready() -> void:
	waypoint_x.resize(WAYPOINTS)
	waypoint_y.resize(WAYPOINTS)
	waypoint_x.fill(0)
	waypoint_y.fill(0)


## Loads the model of a Digimon (key or id) through its files component.
func load_digimon(data: Node, ref: Variant) -> bool:
	if not super.load_digimon(data, ref):
		return false
	tamer_radius = int(data.digimon(0).get("radius", 0))
	# stats.current.vabId = 4 (partner_impl.c:465): its sounds are in slot 4.
	sound_slot = 4
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


## partnerTickOverworld (partner.c:213): one game frame of the partner's state, then the screen
## test and the care boundaries.
func tick() -> void:
	if animator == null or field == null or tamer == null:
		return
	if state != STATE_NORMAL:
		clear_step_flags()
	match state:
		STATE_NORMAL:
			tick_normal()
		STATE_SLEEP:
			tick_sleep()
		STATE_SCOLD, STATE_PRAISE:
			tick_praise_scold()
		STATE_FEED:
			tick_feed_item()
		STATE_TOILET:
			tick_toilet()
		STATE_WILD_POOP:
			tick_wild_poop()
		STATE_IDLE:
			tick_idle()
		STATE_TRAINING:
			if care != null:
				care.handle_condition_bubble()
		STATE_EVOLVING:
			tick_evolving()
	step = 0.0
	on_screen = field.is_on_screen(global_position)
	if care != null:
		care.tick_condition_boundaries()
	if game_state != null:
		game_state.state["partner"]["position"] = _psx(position)
		game_state.state["tamer"]["position"] = _psx(tamer.position)


## partnerSetState (partner.c:1087).
func set_state(value: int) -> void:
	clear_step_flags()
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
			clear_step_flags()
			if closeness() != 2:
				start_animation(ANIM_WALK)
			tamer.state = Tamer.STATE_STILL
			tick_partner_waypoints()
			sub_state = 1
			approach_timer = 0
		1:
			approach_timer += 1
			tamer.look_at_psx(int(position.x), int(-position.z))
			look_at_psx(int(tamer.position.x), int(-tamer.position.z))
			if closeness() == 2 or approach_timer > 150:
				_play_sound(15)
				tamer.play_scene_animation(8)
				start_animation(ANIM_IDLE)
				sub_state = 2
		2:
			if tamer.scene_animation_done():
				play_or_skip(11)
				sub_state = 3
		3:
			if animator.frame >= animator.frame_count:
				play_or_skip(9)
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
				if sleep_save_prompt.is_valid():
					sub_state = 51
					sleep_save_prompt.call(func(): sub_state = 6)
				else:
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
				_special_evolution(Evolution.MODE_WAKE_UP)
				if clock != null:
					clock.running = true


# --- partnerTickPraiseScold (partner.c:368) ---------------------------------------------------

## The menu's Praise (state 15) and Scold (4): it walks up to the tamer; close to him the praise's
## sound and the tamer's pat (state 13) or his scold (state 9); when his animation is over,
## handlePraiseScold; when its own answer ends, both are free, and the special evolutions of mode 3.
func tick_praise_scold() -> void:
	match sub_state:
		0:
			tamer.camera_follow = false
			tick_partner_waypoints()
			clear_step_flags()
			if closeness() != 2:
				start_animation(ANIM_WALK)
			sub_state = 1
			approach_timer = 0
		1:
			approach_timer += 1
			tamer.look_at_psx(int(position.x), int(-position.z))
			look_at_psx(int(tamer.position.x), int(-tamer.position.z))
			if closeness() == 2 or approach_timer > 150:
				start_animation(ANIM_IDLE)
				if state == STATE_PRAISE:
					_play_sound(14)
					tamer.set_state(Tamer.STATE_PRAISE)
				else:
					tamer.set_state(Tamer.STATE_SCOLD)
				sub_state = 2
		2:
			if tamer.animation_id() == 0:
				if care != null:
					care.handle_praise_scold(state)
				sub_state = 3
		3:
			if animator.loop_count == PsxAnimator.ENDLESS:
				animator.finish_loop()
			if animator.frame >= animator.frame_count:
				set_state(STATE_NORMAL)
				tamer.set_state(Tamer.STATE_FREE)
				tamer.camera_follow = true
				_special_evolution(Evolution.MODE_PRAISE_SCOLD)


## handleSpecialEvolutions(mode) (evolution.c:852).
func _special_evolution(mode: int) -> void:
	if care != null and care.evolution != null:
		care.evolution.special_evolution(mode)


# --- partnerTickEvolving (partner.c:741) ------------------------------------------------------

## State 13: time stops, the tamer stands and looks at it, it walks to him; close to him the scene
## starts (EvolutionScene: the evolution is applied inside it); at its end time runs again, and
## either the script's sync bit is set (a script evolution) or the tamer is free. The C also closes
## the △ menu, the inventory and box 1 and disables fishing: the partner doesn't tick while the menu
## is open, and the items start it after the menu closed, so the port has nothing to close.
func tick_evolving() -> void:
	match sub_state:
		0:
			if clock != null:
				clock.running = false
			tamer.camera_follow = false
			tamer.look_at_psx(int(position.x), int(-position.z))
			start_animation(ANIM_WALK)
			sub_state = 1
		1:
			look_at_psx(int(tamer.position.x), int(-tamer.position.z))
			if closeness() > 0:
				if evolution_scene != null:
					evolution_scene.start(care.evolution_target)
				sub_state = 2
		2:
			var value := -1
			if evolution_scene != null:
				value = evolution_scene.tick()
			elif care != null and care.evolution != null and care.evolution_target != -1:
				load_digimon(data, care.evolution.apply_evolution(care.evolution_target))
			if value == -1:
				if clock != null:
					clock.running = true
				if care != null:
					care.evolution_target = -1
				set_state(STATE_NORMAL)
				if script_ctx != null and script_ctx.sync_bit == 0:
					script_ctx.sync_bit = 1
				else:
					tamer.set_state(Tamer.STATE_FREE)
					tamer.camera_follow = true


# --- partnerTickFeedItem (partner.c:425) ------------------------------------------------------

## Use: it gets within its take distance (walking away first if too close), the tamer holds the
## item out, it eats it or refuses it; eaten, the item's effect, one of it out of the bag and the
## hunger rule. What the item does is ItemUse's.
func tick_feed_item() -> void:
	match sub_state:
		0:
			clear_step_flags()
			sub_state = 1 if check_eat_distance() else 2
			start_animation(ANIM_WALK)
			_set_direction(direction + 0x800)
			tick_partner_waypoints()
			approach_timer = 0
		1:
			approach_timer += 1
			tamer.look_at_psx(int(position.x), int(-position.z))
			if not check_eat_distance() or approach_timer > 150:
				sub_state = 3
		2:
			approach_timer += 1
			tamer.look_at_psx(int(position.x), int(-position.z))
			look_at_psx(int(tamer.position.x), int(-tamer.position.z))
			if check_eat_distance() or approach_timer > 150:
				sub_state = 3
		3:
			look_at_psx(int(tamer.position.x), int(-tamer.position.z))
			tamer.play_scene_animation(5)
			_play_sound(12)
			start_animation(ANIM_IDLE)
			tamer.show_held_item(true)
			_tamer_hand_reset = false
			sub_state = 4
		4:
			if tamer.scene_frame() > 7:
				if item_use != null and item_use.will_refuse(tamer.held_item):
					play_or_skip(13)
					sub_state = 7
				else:
					play_or_skip(8)
					sub_state = 5
		5:
			# The C tests frames 11 and 15 exactly; the port's animation may step over one, so from
			# those frames on (once).
			if animator.anim_id == 8 and animator.frame >= 11:
				tamer.show_held_item(false)
			if animator.frame >= 15 and not _tamer_hand_reset:
				tamer.start_animation(0)
				_tamer_hand_reset = true
			if animator.frame >= animator.frame_count:
				sub_state = 6
		6:
			if animator.frame >= animator.frame_count:
				var item: String = tamer.held_item
				set_state(STATE_NORMAL)
				tamer.set_state(Tamer.STATE_FREE)
				tamer.camera_follow = true
				if item_use != null:
					item_use.apply(item)
					item_use.remove_one(item)
				tamer.clear_held_item()
				if item_use != null and item_use.handle_food_feed(item):
					partner_animation = ItemUse.ANIM_HAPPY
					play_or_skip(ItemUse.ANIM_HAPPY)
		7:
			if animator.frame >= animator.frame_count:
				tamer.show_held_item(false)
				start_animation(ANIM_IDLE)
				tamer.play_scene_animation(4)
				sub_state = 8
		8:
			if tamer.scene_animation_ended():
				tamer.set_state(Tamer.STATE_FREE)
				set_state(STATE_NORMAL)
				tamer.clear_held_item()
				tamer.camera_follow = true


## checkEatDistance (partner.c:1094): within ITEM_TAKE_DISTANCE * 200 / 10 + 160 of the tamer.
func check_eat_distance() -> bool:
	var distance := int(data.item_take_distance(digimon)) if data != null else 0
	var target := distance * 200 / 10 + 160
	var dx := int(tamer.position.x) - int(position.x)
	var dz := int(-tamer.position.z) - int(-position.z)
	return target * target >= dx * dx + dz * dz


func _play_sound(value: int) -> void:
	if sound != null:
		sound.play_sound(0, value)


# --- tickPartnerToilet (partner.c:536) --------------------------------------------------------

## The toilet scene (specs/care.md §2.16): the camera pans to the toilet, the partner runs there in
## two legs and squats, handleToilet, the camera pans back, it walks back to the first point and
## sets the sync bit. The script's end gives the field back.
func tick_toilet() -> void:
	match sub_state:
		0:
			tamer.set_state(Tamer.STATE_STILL)
			tamer.camera_follow = false
			var toilet := _toilet()
			if toilet.is_empty():
				# No toilet on this map (the C reads TOILET_DATA[-1]): the scene ends at once.
				_set_sync_bit()
				sub_state = 5
				return
			toilet_pos1 = Vector2i(int(toilet["walk_to"][0]), int(toilet["walk_to"][1]))
			toilet_pos2 = Vector2i(int(toilet["camera_to"][0]), int(toilet["camera_to"][1]))
			field.start_pan(Vector3(toilet_pos2.x, position.y, -toilet_pos2.y), TOILET_PAN_SPEED)
			start_animation(ANIM_RUN)
			sub_state = 1
		1:
			tamer.look_at_psx(int(position.x), int(-position.z))
			if ScriptInterpreter.tick_entity_walk_to(self, toilet_pos1.x, toilet_pos1.y):
				sub_state = 2
		2:
			tamer.look_at_psx(int(position.x), int(-position.z))
			if ScriptInterpreter.tick_entity_walk_to(self, toilet_pos2.x, toilet_pos2.y):
				play_or_skip(ANIM_TOILET)
				sub_state = 3
		3:
			if animator.frame >= animator.frame_count:
				if care != null:
					care.handle_toilet()
				field.start_pan(tamer.position, TOILET_PAN_SPEED)
				start_animation(ANIM_WALK)
				sub_state = 4
		4:
			# The C turns the tamer to a point made of stack values here (&location, §2.16): the port
			# leaves him facing the toilet.
			if ScriptInterpreter.tick_entity_walk_to(self, toilet_pos1.x, toilet_pos1.y):
				_set_sync_bit()


func _toilet() -> Dictionary:
	if data == null or game_state == null:
		return {}
	var map: Dictionary = data.entity("map", game_state.state["world"]["screen"])
	return map.get("toilet", {})


func _set_sync_bit() -> void:
	if script_ctx != null:
		script_ctx.sync_bit = 1


## partnerTickIdle (partner.c:733).
func tick_idle() -> void:
	if sub_state == 0:
		start_animation(ANIM_IDLE)
		sub_state = 1


## startAnimation of a scene animation; one the model lacks counts as played, so the scene goes
## on (the original would wait on the previous animation forever).
func play_or_skip(id: int) -> void:
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
				play_or_skip(10)
				sub_state = 2
		2:
			if animator.frame >= animator.frame_count:
				if care != null:
					care.create_poop_pile(tile(), direction)
					care.handle_wild_poop()
				play_or_skip(12)
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
	# An entity collision (0-9: the tamer or an NPC) keeps the old rotation and turns along the
	# obstacle; collisionGrace gets the tamer as the source, so only the others make it turn.
	var hit := check_collision()
	if hit >= 0 and hit < HIT_MAP:
		_set_direction(previous_direction)
		collision_grace(tamer)
	tamer_previous_tile = tamer_tile


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
				var bumped := check_collision() == HIT_TAMER
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


# --- Movement (like the tamer: specs/partner.md §3) --------------------------------------------

## No walls (specs/partner.md §3): the original never stops the partner's root motion at the map.
## Its entity checks only test (the position is restored), a map hit (10) changes nothing in
## partnerTickCollision or partnerTickWalking, and only collisionGrace sets the animFlag axis bits
## that zero the motion, which the partner gets for entity hits alone. The waypoints keep it off
## walls; blocking it here left it pressed into corners forever.

## Without an entity table (the tests) the tamer is entity 0.
func _fallback_entities() -> Array:
	return [tamer]


## partnerTickCollision's collisionGrace(tamer, partner): the tamer is always the source, so
## bumping only him keeps the old rotation.
func collision_grace(source: Node3D = null) -> void:
	super.collision_grace(tamer if source == null else source)


## The tamer's square is DIGIMON_DATA[0].radius.
func radius_of(other: Node3D) -> int:
	return tamer_radius if other == tamer else super.radius_of(other)


## entityCheckEntityCollision against the tamer: the step to (x, z) touches his square.
func hits_tamer(x: float, z: float, dx: float, dz: float) -> bool:
	return tamer != null and hits_square(tamer, x, z, dx, dz)


func _condition() -> int:
	return game_state.state["partner"]["care"]["condition"] if game_state != null else 0


func _waypoint(index: int) -> Vector2i:
	return Vector2i(waypoint_x[index], waypoint_y[index])
