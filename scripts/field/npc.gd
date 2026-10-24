class_name Npc
extends FieldDigimon
## A map Digimon on the field (specs/npc.md): one of the 8 NPC slots, ticked once per game frame
## by NPCEntityTickOverworld (overworld.c:1224). Its map data and AI state live in the slot
## (FieldEntities.slots, MAP_DIGIMON_TABLE); this is the entity (ENTITY_TABLE[2 + slot]).
##
## A free NPC wanders its path and reacts to the tamer by its follow mode (specs/npc.md §2.10);
## the AI only picks animations and turns it, the root motion moves it.

## rotateEntity's speed for the AI's turns.
const TURN_SPEED := 0x71
const ANIM_IDLE := 0
const ANIM_WALK := 2
const ANIM_RUN := 4
## AI sections (MapDigimonPath.aiSections).
const SECTION_WAIT := 0
const SECTION_WALK := 1
const SECTION_RUN := 2
const SECTION_END := -1
## TrackingTamer3's wait before walking home, TrackingTamer4's before tracking again (frames).
const TRACK_WAIT := 40
const TRACK_2_WAIT := 80

## The slot (0-7); the entity id is slot + 2.
var slot := 0
## The tamer (the autotalk needs his state).
var tamer: Node3D
## func(npc: Npc): the autotalk's talk (the field starts the NPC's section if no script runs).
var talk := Callable()

## entity->anim.animId: the last animation started (the model may not have it).
var _anim_id := 0


## setEntityPosition / setEntityRotation from the slot's map data (PSX x, y, z; rotation.vy).
func place(psx_position: Array, rotation_vy: int) -> void:
	position = Content.psx_to_godot(psx_position)
	_set_direction(rotation_vy)


## The slot's MAP_DIGIMON_TABLE / NPC_ENTITIES record.
func data() -> Dictionary:
	return entities.slots[slot] if entities != null else {}


func script_id() -> int:
	return int(data().get("script_id", -1))


func autotalk() -> int:
	return int(data().get("autotalk", 0))


## startAnimation sets animFlag to 1 (anim.c:231): the held step and the blocked axes go.
func start_animation(id: int) -> void:
	clear_step_flags()
	_anim_id = id
	super.start_animation(id)


## entity->anim.animId: the animation last started.
func animation_id() -> int:
	return _anim_id


func update_on_screen() -> void:
	if field != null and is_inside_tree():
		on_screen = field.is_on_screen(global_position)


## NPCEntityTick / NPCEntityTickOverworld (overworld.c:1120, :1224), once per game frame.
func tick() -> void:
	if not on_map or entities == null:
		return
	var s := data()
	if int(entities.active_anim[slot]) == 0:
		if int(s["stop_anim"]) == 0:
			if int(s["look_at_tamer_state"]) == 0:
				tick_waypoint_ai()
			tick_follow_mode()
			var hit := check_collision()
			entities.collision_state[slot] = hit
			if hit == HIT_TAMER and tamer != null and tamer.state == Tamer.STATE_FREE and autotalk() == 1:
				step_blocked = true
				if talk.is_valid():
					talk.call(self)
			var anim := animation_id()
			if hit != FREE and int(entities.walking_towards[slot]) == 0 and anim > 1 and anim < 5:
				collision_grace()
		elif int(s["animation"]) != 0:
			s["animation"] = 0
			start_animation(0)
	update_on_screen()
	step = 0.0


# --- The waypoint AI (overworld.c:1359-1781) --------------------------------------------------------

## NPCEntityTickWaypointAI (overworld.c:1359): the active section of the path, which loops.
func tick_waypoint_ai() -> void:
	var s := data()
	var sections: Array = s["ai_sections"]
	match int(sections[int(s["active_section"])]):
		SECTION_WAIT:
			tick_waypoint_wait()
		SECTION_WALK:
			tick_waypoint_walk(ANIM_WALK)
		SECTION_RUN:
			tick_waypoint_walk(ANIM_RUN)
	var active := int(s["active_section"])
	if active >= sections.size() or int(sections[active]) == SECTION_END:
		s["active_section"] = 0


## tickWaypointWait (overworld.c:1695): idle for the frames in the section's waypoint x.
func tick_waypoint_wait() -> void:
	var s := data()
	match int(s["has_waypoint_target"]):
		0:
			if int(s["animation"]) != ANIM_IDLE:
				_set_animation(ANIM_IDLE)
			s["waypoint_wait_timer"] = 0
			s["has_waypoint_target"] = 1
		1:
			s["waypoint_wait_timer"] = int(s["waypoint_wait_timer"]) + 1
			if int(s["waypoint_wait_timer"]) >= int(_waypoint(int(s["active_section"]))[0]):
				s["has_waypoint_target"] = 0
				s["waypoint_wait_timer"] = 0
				s["active_section"] = int(s["active_section"]) + 1


## NPCEntityTickWaypointWalk (overworld.c:1719, US): walk / run to the section's waypoint tile.
func tick_waypoint_walk(animation: int) -> void:
	var s := data()
	match int(s["has_waypoint_target"]):
		0:
			s["target_location"] = _waypoint(int(s["active_section"])).duplicate()
			if int(s["animation"]) != animation:
				_set_animation(animation)
			s["has_waypoint_target"] = 1
		1:
			if _previous_collision() == FREE:
				_turn_to_target()
			if _on_target_tile():
				s["has_waypoint_target"] = 0
				s["active_section"] = int(s["active_section"]) + 1


## The section's waypoint; a section without one in the data reads 0 (the C reads the slot's
## leftover from the previous map, specs/npc.md §6).
func _waypoint(index: int) -> Array:
	var points: Array = data()["waypoints"]
	return points[index] if index < points.size() else [0, 0, 0]


# --- The follow modes (overworld.c:1247-1304, 1389-1690) ---------------------------------------------

## The followMode switch of NPCEntityTickOverworld: a mode's tick runs while the tamer is in its
## range or once it started (lookAtTamerState != 0).
func tick_follow_mode() -> void:
	var s := data()
	var started := int(s["look_at_tamer_state"]) != 0
	match int(s["follow_mode"]):
		2, 11:
			if in_tracking_rect() or started:
				tick_looking_at_tamer()
		3, 4, 5, 12, 13, 14:
			if in_tracking_rect() or started:
				tick_tracking_tamer()
		6, 15:
			if in_tracking_radius() or started:
				tick_tracking_tamer_2(ANIM_WALK)
		7, 16:
			if in_tracking_radius() or started:
				tick_tracking_tamer_2(ANIM_RUN)
		8, 9, 17, 18:
			if in_tracking_rect() or started:
				tick_tracking_tamer_2(ANIM_WALK)


## NPCEntityIsInTrackingRect (overworld.c:1389): the tamer strictly inside the square of half-size
## trackingRange around the NPC's map position.
func in_tracking_rect() -> bool:
	var s := data()
	var r := int(s["tracking_range"])
	var ox := int(s["position"][0])
	var oz := int(s["position"][2])
	var tx := int(tamer.position.x)
	var tz := int(-tamer.position.z)
	return ox + r > tx and ox - r < tx and oz + r > tz and oz - r < tz


## NPCEntityIsInTrackingRadius (overworld.c:1446). Quirk kept: the signed deltas are added, not
## squared (specs/npc.md §2.10.2).
func in_tracking_radius() -> bool:
	var dx := int(position.x) - int(tamer.position.x)
	var dz := int(-position.z) - int(-tamer.position.z)
	var r := int(data()["tracking_range"]) * 6 / 10
	return dx + dz < r * r


## NPCEntityTickLookingAtTamer (overworld.c:1400): idle, turned towards the tamer while he is in
## the rect.
func tick_looking_at_tamer() -> void:
	var s := data()
	if int(s["look_at_tamer_state"]) == 0:
		_set_animation(ANIM_IDLE)
		s["look_at_tamer_state"] = 1
	else:
		_turn_towards(int(tamer.position.x), int(-tamer.position.z))
		if not in_tracking_rect():
			s["look_at_tamer_state"] = 0
			s["has_waypoint_target"] = 0


## NPCEntityTickTrackingTamer (overworld.c:1424): a charge at where the tamer is now.
func tick_tracking_tamer() -> void:
	var s := data()
	if int(s["look_at_tamer_state"]) == 0:
		s["target_location"] = _psx(tamer.position)
		_set_animation(ANIM_WALK)
		s["look_at_tamer_state"] = 1
	else:
		tick_tracking_tamer_3()


## NPCEntityTickTrackingTamer3 (overworld.c:1548): run to the target, wait, walk home.
func tick_tracking_tamer_3() -> void:
	var s := data()
	match int(s["look_at_tamer_state"]):
		1:
			_set_animation(ANIM_RUN)
			s["look_at_tamer_state"] = 2
		2:
			if _previous_collision() == FREE:
				_turn_to_target()
			if _on_target_tile() or _previous_collision() == HIT_TAMER:
				_set_animation(ANIM_IDLE)
				s["waypoint_wait_timer"] = 0
				s["look_at_tamer_state"] = 3
		3:
			s["waypoint_wait_timer"] = int(s["waypoint_wait_timer"]) + 1
			if int(s["waypoint_wait_timer"]) >= TRACK_WAIT:
				_set_animation(ANIM_WALK)
				s["target_location"] = (s["position"] as Array).duplicate()
				s["waypoint_wait_timer"] = 0
				s["look_at_tamer_state"] = 4
		4:
			if _previous_collision() == FREE:
				_turn_to_target()
			if _on_target_tile():
				_set_animation(ANIM_IDLE)
				s["waypoint_wait_timer"] = 0
				s["look_at_tamer_state"] = 0
				s["has_waypoint_target"] = 0


## NPCEntityTickTrackingTamer2 (overworld.c:1465): the mode's walk or run, then the chase.
func tick_tracking_tamer_2(animation: int) -> void:
	var s := data()
	if int(s["look_at_tamer_state"]) == 0:
		if int(s["animation"]) != animation:
			_set_animation(animation)
		s["look_at_tamer_state"] = 1
	else:
		tick_tracking_tamer_4()


## NPCEntityTickTrackingTamer4 (overworld.c:1626): turn to the tamer while he is in the radius,
## then walk home and wait.
func tick_tracking_tamer_4() -> void:
	var s := data()
	match int(s["look_at_tamer_state"]):
		1:
			if in_tracking_radius():
				if _previous_collision() == FREE:
					_turn_towards(int(tamer.position.x), int(-tamer.position.z))
			else:
				s["look_at_tamer_state"] = 2
				s["target_location"] = (s["position"] as Array).duplicate()
		2:
			if _previous_collision() == FREE:
				_turn_to_target()
			if _on_target_tile():
				_set_animation(ANIM_IDLE)
				s["waypoint_wait_timer"] = 0
				s["look_at_tamer_state"] = 3
		3:
			s["waypoint_wait_timer"] = int(s["waypoint_wait_timer"]) + 1
			if int(s["waypoint_wait_timer"]) >= TRACK_2_WAIT:
				s["look_at_tamer_state"] = 0
				s["has_waypoint_target"] = 0
				s["waypoint_wait_timer"] = 0


# --- Shared by the AI ------------------------------------------------------------------------------

## mapDigimon->animation = id; startAnimation(entity, id).
func _set_animation(id: int) -> void:
	data()["animation"] = id
	start_animation(id)


## NPC_COLLISION_STATE[slot]: the AI runs before this frame's entityCheckCollision, so it sees the
## previous frame's.
func _previous_collision() -> int:
	return int(entities.collision_state[slot])


## getRotationDifference + rotateEntity at 0x71 towards a PSX point.
func _turn_towards(x: int, z: int) -> void:
	var turned := rotate_entity(direction, x - int(position.x), z - int(-position.z), TURN_SPEED)
	_set_direction(turned[0])


func _turn_to_target() -> void:
	var target: Array = data()["target_location"]
	_turn_towards(int(target[0]), int(target[2]))


## getModelTile(location) == getModelTile(targetLocation).
func _on_target_tile() -> bool:
	var target: Array = data()["target_location"]
	return tile() == FieldMap.model_tile(int(target[0]), int(target[2]))


## getEntityScreenPos(npc, 1) relative to the screen centre: bone 1 projected, as the tamer's.
func screen_position(camera: Camera3D) -> Vector2i:
	if camera == null or not camera.is_inside_tree():
		return Vector2i.ZERO
	var world := global_position
	if _skeleton != null and _skeleton.get_bone_count() > 1:
		world = _skeleton.global_transform * _skeleton.get_bone_global_pose(1).origin
	var s := FieldMap.unproject(camera, world)
	return Vector2i(roundi(s.x) - 160, roundi(s.y) - 120)
