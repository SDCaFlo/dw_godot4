class_name FieldBattleWorld
extends BattleWorld
## The battle's world on the field (specs/battle.md §5.1): the tamer, the partner and the map
## Digimon of FieldEntities, the field's map and camera, GameState and the sound. Positions are the
## entities' Godot positions in PSX units (Content.psx_to_godot: y and z flipped).

## Bone 1 for the screen tests (getEntityScreenPos(entity, 1)).
const SCREEN := Vector2(320, 240)
## QUADRANTS (map.c:339).
const QUADRANTS := [Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
## BTL_setupFixedCamera's view: the eye's z and the projection.
const FIXED_EYE_Z := -0x7D0
const FIXED_PROJECTION := 0x200

var entities: FieldEntities
var field_map: FieldMap
var camera: Camera3D
var game_state: Node
var sound: Node
## The inventory's box state and opener (MenuHost), the thrown item, the money: callables the
## host sets.
var inventory_is_open := func() -> bool: return false
var inventory_opener := Callable()
var inventory_closer := Callable()
var fader := Callable()
var drop_spawner := Callable()
var map_sound_loader := Callable()
## Throwing items: the item rules (ItemUse with `battle` set) and the tamer, who draws the item.
var item_user := Callable()
var tamer: Tamer

## COMBAT_AREA_X / Y: the screen centre (160 - DRAWING_OFFSET).
var _area := Vector2(160, 120)
## The map layer's objects (doors, overlays, items, chests, poop): func() -> Array, set by the host.
var map_layer_nodes := Callable()
var _map_layer := true
## The nodes the map layer hid, with their visibility before.
var _hidden_layer := {}
## BTL_setupFixedCamera's view is up: the projections the scripts make use it.
var _fixed := false


func _node(id: int) -> Node3D:
	return entities.entity(id) if entities != null else null


func _digimon_node(id: int) -> FieldDigimon:
	return _node(id) as FieldDigimon


# --- the effect context ---------------------------------------------------------------------------

func entity_present(id: int) -> bool:
	return _node(id) != null


func is_on_map(id: int) -> bool:
	var n := _node(id)
	return n != null and bool(n.get("on_map"))


## entity->isOnScreen: only the NPCs' field tick sets it (NPCEntityTickOverworld, overworld.c:1352),
## so through a battle it keeps its value from the battle's start. An enemy on screen then leaves
## the map after the battle even once it has run off (BTL_deinitializeCombat).
func is_on_screen(id: int) -> bool:
	var n := _node(id)
	if n == null:
		return false
	return bool(n.get("on_screen"))


func digimon_type(id: int) -> int:
	if id == 1:
		return int(GameData.id_of("digimon/digimon_data", game_state.state["partner"]["digimon"]))
	if id >= 2 and entities != null:
		return int(entities.slots[id - 2]["type"])
	return -1


func current_hp(id: int) -> int:
	var s := stats(id)
	return int(s["current"]["hp"]) if not s.is_empty() else 0


func is_hit(id: int) -> bool:
	var s := stats(id)
	return not s.is_empty() and int(s["current"]["is_hit"]) != 0


func set_hit(id: int, value: bool) -> void:
	var s := stats(id)
	if not s.is_empty():
		s["current"]["is_hit"] = 1 if value else 0


func location(id: int) -> Vector3i:
	var n := _node(id)
	if n == null:
		return Vector3i.ZERO
	return Vector3i(roundi(n.position.x), roundi(-n.position.y), roundi(-n.position.z))


func rotation_y(id: int) -> int:
	var n := _node(id)
	return int(n.get("direction")) if n != null and n.get("direction") != null else 0


## The bone's world matrix from the model's skeleton, in PSX units (posData[bone].workm): its
## rotation the bone's own (the skeleton's world basis taken back to the PSX's axes: F · B · F with
## F the flip (x, -y, -z)), its translation the bone's position. The effects aim along it (a mouth,
## a hand: getSourceBoneTransform).
func bone_matrix(id: int, bone: int) -> PackedInt32Array:
	var n := _node(id)
	if n == null:
		return PsxMath.identity()
	var bones := int(GameData.digimon(digimon_type(id)).get("bone_count", 1)) if id >= 1 else 1
	if bone >= bones:
		bone = 0
	var p: Vector3 = n.call("bone_position", bone) if n.has_method("bone_position") else n.global_position
	var m := PsxMath.rot_matrix_yxz(Vector3i(0, rotation_y(id), 0))
	if n.has_method("bone_basis"):
		m = psx_matrix(n.call("bone_basis", bone))
	return PsxMath.trans_matrix(m, Vector3i(roundi(p.x), roundi(-p.y), roundi(-p.z)))


## A Godot basis as a PSX rotation matrix (4096 = 1.0; int16 entries): F · B · F.
static func psx_matrix(b: Basis) -> PackedInt32Array:
	var f := [1.0, -1.0, -1.0]
	var m := PsxMath.identity()
	for i in 3:
		for j in 3:
			m[i * 3 + j] = PsxMath.s16(roundi(f[i] * b[j][i] * f[j] * 4096.0))
	return m


func look_at(id: int, target: int) -> void:
	look_at_location(id, location(target))


func world_screen_matrix() -> PackedInt32Array:
	if _fixed:
		return PsxMath.trans_matrix(PsxMath.identity(), Vector3i(0, 0, -FIXED_EYE_Z))
	return field_map.world_screen_matrix() if field_map != null and field_map.has_method("world_screen_matrix") \
			else PsxMath.identity()


## getDrawingOffsetCopy: the field's drawing offset, also while the fixed view is up (the C keeps
## its copy; the screen primitives land relative to the frame's offset).
func drawing_offset() -> Vector2i:
	return Vector2i(field_map.drawing_offset().round()) if field_map != null else super()


## Where a screen primitive lands: on the frame's screen, through the field camera.
func screen_to_world(relative: Vector2, depth: float) -> Vector3:
	return field_map.screen_to_world(relative, depth) if field_map != null else super(relative, depth)


## VIEWPORT_DISTANCE: the map camera's projection distance (the fixed view's 0x200).
func viewport_distance() -> int:
	if _fixed:
		return FIXED_PROJECTION
	return roundi(field_map.projection()) if field_map != null else super()


## setMapLayerEnabled: off (BTL_disableMapLayer, for a frame) hides the map's objects, not its
## background (MAP_LAYER_ENABLED: renderDoors, renderChest, the overlays, the dropped items, the
## poop...); the effect engine's tick turns it back on.
func set_map_layer(enabled: bool) -> void:
	if enabled == _map_layer:
		return
	_map_layer = enabled
	if not enabled:
		var nodes: Array = map_layer_nodes.call() if map_layer_nodes.is_valid() else []
		for n in nodes:
			if n != null and is_instance_valid(n) and "visible" in n:
				_hidden_layer[n] = n.visible
				n.visible = false
	else:
		for n in _hidden_layer:
			if is_instance_valid(n):
				n.visible = _hidden_layer[n]
		_hidden_layer.clear()


## BTL_setupFixedCamera (battle_effect.c:3199): GsSetProjection(0x200) and a view from (0, 0,
## -2000) looking down +z; BTL_restoreCameraView puts the field's back. The scripts bracket a few
## primitives with it within one pass (DG Dimension's grid and fade): it is the projection those
## are made with (GsWSMATRIX, the projection), not a camera the frame is drawn with.
func set_fixed_camera(fixed: bool) -> void:
	_fixed = fixed


## The effects' view states back as the field's (a battle or the gallery ending in the middle).
func restore_view() -> void:
	set_fixed_camera(false)
	set_map_layer(true)


func play_sound(bank: int, id: int) -> void:
	if sound != null:
		sound.play_sound(bank, id)


func play_loop(bank: int, id: int) -> int:
	return sound.play_sound(bank, id) if sound != null else -1


func stop_loop(mask: int) -> void:
	if sound != null and mask >= 0:
		sound.stop_sound_mask(mask)


# --- stats ----------------------------------------------------------------------------------------

func stats(id: int) -> Dictionary:
	if id == 1:
		return game_state.state["partner"]["stats"]
	if id >= 2 and entities != null:
		var slot: Dictionary = entities.slots[id - 2]
		if not slot.has("stats"):
			slot["stats"] = _npc_stats(slot.get("record", {}))
		return slot["stats"]
	return {}


## loadMapDigimon's NPC stats (overworld.c:1049) in the partner's layout.
static func _npc_stats(r: Dictionary) -> Dictionary:
	var moves := []
	for m in r.get("moves", [0xFF, 0xFF, 0xFF, 0xFF]):
		moves.append(null if int(m) == 0xFF else int(m))
	var prio := []
	for p in r.get("move_priority", [0, 0, 0, 0]):
		prio.append(int(p))
	return {"base": {"max_hp": int(r.get("hp", 0)), "max_mp": int(r.get("mp", 0)), "offense": int(r.get("offense", 0)),
			"defense": int(r.get("defense", 0)), "speed": int(r.get("speed", 0)), "brains": int(r.get("brains", 0)),
			"moves": moves, "moves_prio": prio},
			"current": {"hp": int(r.get("current_hp", 0)), "mp": int(r.get("current_mp", 0)),
			"charge_mode": int(r.get("charge_mode", 0)), "is_hit": 0, "efe_sub_effect": -1, "unk1": -1, "vab_id": 0}}


func npc_record(id: int) -> Dictionary:
	if id < 2 or entities == null:
		return {}
	var r: Dictionary = entities.slots[id - 2].get("record", {})
	return {"bits": int(r.get("bits", 0)), "targets_partner": bool(r.get("targets_partner", false)),
			"flee": r.get("flee", [0, 0, 0])}


func partner_condition() -> int:
	return int(game_state.state["partner"]["care"]["condition"])


func partner_discipline() -> int:
	return int(game_state.state["partner"]["care"]["discipline"])


func partner_tiredness() -> int:
	return int(game_state.state["partner"]["care"]["tiredness"])


func set_partner_condition_bit(bit: int) -> void:
	game_state.set_condition(bit, true)


func has_move(t: int) -> bool:
	return game_state.has_move(t)


func learn_move(t: int) -> void:
	game_state.learn_move(t)


func money_held() -> int:
	return int(game_state.state["money"])


func add_money(n: int) -> void:
	game_state.state["money"] = mini(int(game_state.state["money"]) + n, 999999)


# --- animation ------------------------------------------------------------------------------------

func _animator(id: int) -> PsxAnimator:
	var n := _digimon_node(id)
	return n.animator if n != null else null


func start_animation(id: int, anim: int) -> void:
	var n := _node(id)
	if n == null:
		return
	if n is Npc:
		(n as Npc).start_animation(anim)
	elif n.has_method("start_animation"):
		n.call("start_animation", anim)


func animation_id(id: int) -> int:
	var n := _node(id)
	if n == null:
		return -1
	if n.has_method("animation_id"):
		return int(n.call("animation_id"))
	var a := _animator(id)
	return a.anim_id if a != null else -1


func animation_playing(id: int) -> bool:
	if id == 0:
		var t := _node(0)
		return t != null and not bool(t.call("scene_animation_done"))
	var a := _animator(id)
	return a != null and a.playing


func set_animation_playing(id: int, playing: bool) -> void:
	var a := _animator(id)
	if a != null:
		a.playing = playing


func animation_frame(id: int) -> int:
	var n := _node(id)
	if n is Tamer:
		return (n as Tamer).scene_frame()
	var a := _animator(id)
	return a.frame if a != null else 0


func animation_frame_count(id: int) -> int:
	var a := _animator(id)
	return a.frame_count if a != null else 0


func set_step_held(id: int, held: bool) -> void:
	var n := _node(id)
	if n != null:
		n.set("step_blocked", held)


func set_double_speed(id: int, on: bool) -> void:
	var n := _digimon_node(id)
	if n != null:
		n.set_meta("battle_double_speed", on)
		if n.animator != null and n.animator.player != null:
			n.animator.player.speed_scale = 2.0 if on else 1.0


# --- position and movement ------------------------------------------------------------------------

func set_rotation_y(id: int, vy: int) -> void:
	var n := _node(id)
	if n != null and n.has_method("set_direction"):
		n.call("set_direction", vy & 0xFFF)


## entityCheckCollision with the combat area (map.c:3400): the next step's screen box against the
## area, then the map, then the other entities (the tamer is no obstacle to a walking fighter in
## battle, nor a Digimon at HP 0).
func check_collision(id: int, source: int, w: int, h: int) -> int:
	var n := _node(id)
	if n == null:
		return FREE
	# entityMoveForward: the animation's signed forward momentum (a Digimon's), else the step.
	var step_length := float(n.get("forward_step")) if n.get("forward_step") != null else float(n.get("step"))
	var vy := rotation_y(id)
	var angle := (vy - 0x800) * PI / 0x800
	var dx := float(int(sin(angle) * step_length))
	var dz := float(int(cos(angle) * step_length))
	if vy == 0x400 or vy == 0xC00:
		dz = 0.0
	if vy == 0 or vy == 0x800:
		dx = 0.0
	var here := location(id)
	var next := Vector3i(here.x + int(dx), here.y, here.z + int(dz))
	if w != 0 and h != 0 and _left_combat_area(id, here, next, w, h):
		return HIT_AREA
	var radius := int(GameData.digimon(digimon_type(id)).get("radius", 100)) if id >= 1 else 100
	if field_map != null and field_map.blocked(next.x, next.z, int(signf(dx)), int(signf(dz)), radius):
		return HIT_MAP
	if id == 0:
		return FREE
	var d := n as FieldDigimon
	if d == null:
		return FREE
	var table := entities.table()
	for i in table.size():
		var other: Node3D = table[i]
		if other == null or other == n or i == source or FieldEntities.is_invisible(other):
			continue
		if i == 0:
			var anim := animation_id(id)
			if anim == Battle.ANIM_WALK or anim == Battle.ANIM_WALK_WEAK:
				continue
		elif current_hp(i) == 0:
			continue
		if d.hits_square(other, next.x, next.z, dx, dz):
			return i
	return FREE


## entityCheckCombatArea + hasMovedOutsideCombatArea: the two corner points the C tests (a loop
## that reads QUADRANTS[i] for i = 0, 1 only: the near-left at the feet, the near-right 200 up).
func _left_combat_area(id: int, here: Vector3i, next: Vector3i, w: int, h: int) -> bool:
	var radius := int(GameData.digimon(digimon_type(id)).get("radius", 100)) if id >= 1 else 100
	for i in 2:
		var q: Vector2i = QUADRANTS[i]
		var now := _screen(Vector3i(next.x + radius * q.x, next.y - i * 200, next.z + radius * q.y))
		var before := _screen(Vector3i(here.x + radius * q.x, here.y - i * 200, here.z + radius * q.y))
		if now.x - _area.x < -w / 2 and now.x < before.x:
			return true
		if now.x - _area.x > w / 2 and now.x > before.x:
			return true
		if now.y - _area.y < -h / 2 and now.y < before.y:
			return true
		if now.y - _area.y > h / 2 and now.y > before.y:
			return true
	return false


## A PSX world point's screen pixel (0-320, 0-240).
func _screen(p: Vector3i) -> Vector2:
	if field_map == null:
		return Vector2.ZERO
	return field_map.background_pixel(Content.psx_to_godot([p.x, p.y, p.z])) - field_map.scroll


func collision_grace(id: int, source: int, _w: int, _h: int) -> void:
	var n := _digimon_node(id)
	if n != null:
		n.collision_grace(_node(source))


## entityIsOffScreen (map.c:3871): off screen unless one of its 8 corners projects inside.
func is_off_screen(id: int, w: int, h: int) -> bool:
	var here := location(id)
	var d := GameData.digimon(digimon_type(id)) if id >= 1 else {}
	var radius := int(d.get("radius", 100))
	var height := int(d.get("height", 300))
	for i in 2:
		for q: Vector2i in QUADRANTS:
			var s := _screen(Vector3i(here.x + radius * q.x, here.y - i * height, here.z + radius * q.y))
			if absf(s.x - 160) <= w / 2 and absf(s.y - 120) <= h / 2:
				return false
	return true


func path_blocked(a: Vector2i, b: Vector2i) -> bool:
	return field_map != null and field_map.is_linear_path_blocked(a, b)


func wide_path_blocked(a: Vector2i, b: Vector2i) -> bool:
	return field_map != null and field_map.is_five_tile_wide_path_blocked(a, b)


func screen_position(id: int, bone: int) -> Vector2i:
	var n := _node(id)
	if n == null:
		return Vector2i.ZERO
	var p: Vector3 = n.call("bone_position", bone) if n.has_method("bone_position") else n.global_position
	var s := field_map.background_pixel(p) - field_map.scroll if field_map != null else Vector2.ZERO
	return Vector2i(int(s.x) - 160, int(s.y) - 120)


func set_scale(id: int, scale: Vector3i) -> void:
	var n := _node(id)
	if n != null:
		n.scale = Vector3(scale.x, scale.y, scale.z) / 4096.0


## entity->flatSprite: the entity's FlatSprite shows it instead of the model (-1: the model).
func set_flat_sprite(id: int, frame: int) -> void:
	var n := _node(id)
	if n != null and "flat_sprite" in n:
		n.set("flat_sprite", frame)


func set_on_map(id: int, on: bool) -> void:
	var n := _node(id)
	if n != null:
		n.set("on_map", on)
		n.visible = on


func is_invisible(id: int) -> bool:
	var n := _node(id)
	return n == null or FieldEntities.is_invisible(n)


# --- the session ----------------------------------------------------------------------------------

func trigger(id: int) -> bool:
	return game_state.is_trigger_set(id)


func script_value(id: int) -> int:
	return int(game_state.script_value(id))


func inventory_items() -> Array:
	var out := []
	for s in game_state.state["inventory"]["slots"]:
		if s != null and s is Dictionary and s.get("item") != null:
			out.append(int(GameData.id_of("items/item_data", s["item"])))
	return out


func map_record() -> Dictionary:
	return GameData.map(game_state.state["world"]["screen"])


func play_music(font: int, variant: int) -> void:
	if sound != null:
		sound.music.play_music(font, variant)


func stop_music() -> void:
	if sound != null:
		sound.music.stop_bgm()


func stop_sounds() -> void:
	if sound != null:
		sound.stop_sound()


## readVBALLSection(bank, type): the Digimon's VBALL set into the bank (sound.c loadDigimonSounds).
func load_battle_sounds() -> void:
	if sound != null:
		sound.load_battle_sounds()


func load_digimon_sounds(bank: int, digimon: int) -> void:
	if sound == null or digimon < 0:
		return
	var vball = GameData.entity("digimon", digimon).get("sounds", {}).get("vball")
	if vball != null:
		sound.load_bank(bank, "sound/VBALL/set_%02d" % int(vball))


func partner_run_in() -> void:
	var p := _node(1) as Partner
	if p == null:
		return
	p.tick_collision()
	var t := _node(0)
	if t != null and Vector2(p.position.x - t.position.x, p.position.z - t.position.z).length() <= p.radius + 100:
		if animation_id(1) != Battle.ANIM_IDLE and animation_id(1) != Battle.ANIM_IDLE_WEAK:
			start_animation(1, Battle.ANIM_IDLE)


func partner_collision() -> void:
	var p := _node(1) as Partner
	if p == null:
		return
	var hit := p.check_collision()
	if hit >= 0 and hit < FieldDigimon.HIT_MAP:
		p.collision_grace(_node(0))


func partner_waypoint_trail() -> void:
	pass


func tamer_waypoints() -> Dictionary:
	return game_state.state["tamer"]["waypoints"]


func exit_flee_point() -> Vector3i:
	if field_map == null:
		return Vector3i.ZERO
	var spawn: Dictionary = field_map.spawn(int(game_state.state["world"]["exit"])) \
			if field_map.has_method("spawn") else {}
	if spawn.is_empty():
		return Vector3i.ZERO
	var p: Vector3 = spawn["position"]
	var rot := (int(spawn["rotation"]) + 0x800) & 0xFFF
	var out := PsxMath.apply_matrix_lv(PsxMath.rot_matrix(Vector3i(0, rot, 0)), Vector3i(0, 0, -0xBB8))
	return Vector3i(roundi(p.x) + out.x, 0, roundi(-p.z) + out.z)


func project(pos: Vector3i) -> Vector3i:
	if field_map == null:
		return super.project(pos)
	var g := Vector3(pos.x, -pos.y, -pos.z)
	var s := field_map.background_pixel(g) - field_map.scroll
	return Vector3i(int(s.x) - 160, int(s.y) - 120, roundi(field_map.view_depth(g)))


func projection_distance() -> int:
	return roundi(field_map.projection()) if field_map != null else super.projection_distance()


func bone_location(id: int, bone: int) -> Vector3i:
	var n := _node(id)
	if n == null or not n.has_method("bone_position"):
		return location(id)
	var p: Vector3 = n.call("bone_position", bone)
	return Vector3i(roundi(p.x), roundi(-p.y), roundi(-p.z))


func show_thrown_item(item: Variant, pos: Vector3i) -> void:
	if tamer == null:
		return
	if item == null:
		tamer.clear_held_item()
		return
	tamer.held_item = str(item)
	tamer.show_held_item_at(Vector3(pos.x, -pos.y, -pos.z))


func remove_item(item: Variant) -> void:
	game_state.remove_item(item, 1)


func use_item(item: Variant) -> void:
	if item_user.is_valid():
		item_user.call(item)


func inventory_open() -> bool:
	return inventory_is_open.call()


func open_inventory() -> void:
	if inventory_opener.is_valid():
		inventory_opener.call()


func close_inventory() -> void:
	if inventory_closer.is_valid():
		inventory_closer.call()


func fade_to_black(frames: int) -> void:
	if fader.is_valid():
		fader.call(frames)


func reload_map_sounds() -> void:
	if map_sound_loader.is_valid():
		map_sound_loader.call()


func spawn_drop(entity: int, item: int) -> void:
	if drop_spawner.is_valid():
		drop_spawner.call(location(entity), item)


func set_combat_area() -> void:
	_area = Vector2(160, 120)


## The end of a game frame: the root-motion step the collision probes used starts over.
func end_frame() -> void:
	if entities == null:
		return
	for n in entities.table():
		if n != null and n.get("step") != null:
			n.set("step", 0.0)
		if n != null and n.get("forward_step") != null:
			n.set("forward_step", 0.0)
