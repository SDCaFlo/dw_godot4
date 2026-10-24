class_name Npc
extends FieldDigimon
## A map Digimon on the field (specs/npc.md): one of the 8 NPC slots, ticked once per game frame
## by NPCEntityTickOverworld (overworld.c:1224). Its map data and AI state live in the slot
## (FieldEntities.slots, MAP_DIGIMON_TABLE); this is the entity (ENTITY_TABLE[2 + slot]).
##
## Option A (specs/npc.md §2.3): the waypoint AI and the follow modes (step 3b) are empty, so a
## free NPC stands in its animation; the collision, autotalk and collisionGrace run as the C.

## The slot (0-7); the entity id is slot + 2.
var slot := 0
## The tamer (the autotalk needs his state).
var tamer: Node3D
## func(npc: Npc): the autotalk's talk (the field starts the NPC's section if no script runs).
var talk := Callable()

var _reported := {}


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


## startAnimation clears animFlag (the held step).
func start_animation(id: int) -> void:
	step_blocked = false
	super.start_animation(id)


## The animation playing (entity->anim.animId); -1 without a model.
func animation_id() -> int:
	return animator.anim_id if animator != null else -1


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
			# entityCheckCollision clears animFlag & 2 first.
			step_blocked = false
			var hit := probe(direction)
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


## NPCEntityTickWaypointAI / NPCEntityTickWaypointWalk (overworld.c:1359, :1723): step 3b.
func tick_waypoint_ai() -> void:
	_report_once("waypoint AI")


## The followMode branches of NPCEntityTickOverworld (overworld.c:1247-1304): step 3b.
func tick_follow_mode() -> void:
	var mode := int(data().get("follow_mode", 0))
	if mode >= 2 and mode <= 18 and mode != 10:
		_report_once("follow mode %d" % mode)


func _report_once(what: String) -> void:
	if not _reported.has(what):
		_reported[what] = true
		print_verbose("Npc: %s not ported yet (step 3b)" % what)


## getEntityScreenPos(npc, 1) relative to the screen centre: bone 1 projected, as the tamer's.
func screen_position(camera: Camera3D) -> Vector2i:
	if camera == null or not camera.is_inside_tree():
		return Vector2i.ZERO
	var world := global_position
	if _skeleton != null and _skeleton.get_bone_count() > 1:
		world = _skeleton.global_transform * _skeleton.get_bone_global_pose(1).origin
	var s := camera.unproject_position(world)
	return Vector2i(roundi(s.x) - 160, roundi(s.y) - 120)
