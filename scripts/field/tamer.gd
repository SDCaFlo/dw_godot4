@tool
class_name Tamer
extends Node3D
## The player character on a field map (tamer.c: tamerTickWalkingState).
##
## Movement comes from the walk/run animations' root motion, like the game's applyRootMomentum:
## the animation moves bone_0 forward and the entity's yaw turns that into world motion.

const MODEL := "mmd_files/MMD0/BOYS.gltf"
const SIDECAR := "mmd_files/MMD0/BOYS.json"
const ANIM_IDLE := "anim_00"
const ANIM_RUN := "anim_02"
const ANIM_WALK := "anim_03"
## tamerGetState values ported so far: 0 walks freely, 6 stands still while a scene plays, 20 shows
## the award / sickness message box (tamerTickAwardSomething).
const STATE_FREE := 0
## A warp cell's map change (tamerTickChangeMap).
const STATE_CHANGE_MAP := 5
const STATE_STILL := 6
## A script moves him (scriptSetEntityWalking, scriptStartAnimation): only his animation ticks.
const STATE_SCRIPT := 10
const STATE_AWARD := 20
## Picking up an item from the ground (tamerTickPickupItem) and opening a chest (tamerTickTakeChest).
const STATE_PICKUP := 7
const STATE_CHEST := 14
## startAnimation(tamer, 0xC): the pick-up animation.
const ANIM_PICKUP := 0xC
## ITEM_PICKUP_TEXT_AREA / TAKE_CHEST_TEXT_AREA (tamer.c:35, :42): the rows the boxes' text uses.
const PICKUP_TEXT_AREA := Rect2i(0, 12, 256, 200)
## The texts (text/main/tamer.yaml): found, the bag is full, the chest is empty.
const TEXT_FOUND := "MAIN_D_801341FC"
const TEXT_FULL := "MAIN_D_80122D68"
const TEXT_EMPTY := "MAIN_D_80122D80"
## The bone getEntityScreenPos reads for the box's start point (tamer.c:1801).
const SCREEN_BONE := 1

## PSX rotation.vy (4096 per turn).
var direction := 0
var radius := 100
var field: FieldMap
## Entity 0 of the entity table (FieldEntities): on the map and on screen (isInvisible).
var on_screen := true
## The model's animation sound events (anim.c:336: footsteps): emitted when on screen. Bank 4
## (the entity's own slot) is skipped: the tamer has none (specs/sound.md §6).
signal animation_sound(slot: int, value: int)
var _sounds: AnimationSoundsComponent
var on_map := true
## Ground distance his root motion moved during the last game frame (entityMoveForward's step).
var step := 0.0
## animFlag & 2: his step is held this frame (checkMapInteraction: he stands against an NPC).
var step_blocked := false
## The tamer's state (TAMER_STATE); input moves him only in STATE_FREE, which also ends a scene
## animation.
var state := STATE_FREE:
	set(value):
		state = value
		if value == STATE_FREE:
			_scene_playing = false
## setCameraFollowPlayer / unsetCameraFollowPlayer: CAMERA_FOLLOW_PLAYER, kept by the field map
## (its pans set and clear it too); a tamer without a field keeps his own.
var camera_follow: bool:
	get:
		return field.camera_follow if field != null else _camera_follow
	set(value):
		_camera_follow = value
		if field != null:
			field.camera_follow = value
var _camera_follow := true
## TAMER_SUB_STATE (reset by tamerSetState = set_state).
var sub_state := 0
## For tick(): the field camera (screen positions), the partner and clock it stops, the message box,
## the pad (GameLoop.pad).
var camera: Camera3D
var partner: Partner
var clock: Clock
var message_box: MessageBox
var pad: Pad
## For the map change (state 5): the fade, TARGET_MAP / CURRENT_EXIT, and the field's changeMap,
## the map name object (map id, -1 = remove) and checkMapInteraction.
var fade: Fade
var target_map := 0
var target_exit := 0
var change_map := Callable()
var show_map_name := Callable()
var map_interaction := Callable()
## For the pickup and the chests (specs/map_items.md): the items on the ground, the chests, the
## pickup / chest box (box 1, no arrow), the GameState and GameData nodes, the sound.
var map_items: MapItems
var map_chests: MapChests
var pickup_box: MessageBox
var game_state: Node
var data: Node
var sound: Node
## PICKED_UP_DROP_ID, HAS_PICKED_UP_ITEM, INTERACTED_CHEST, TAKE_CHEST_STATE (0 taking, 1 the bag
## is full, 2 an empty chest), TAKE_CHEST_ITEM, TAKE_ITEM_FRAME_COUNTER.
var picked_up_drop := -1
var has_picked_up := false
var interacted_chest := -1
var take_chest_state := 0
var take_chest_item: Variant = null
var take_item_frames := 0

var _player: AnimationPlayer
var _skeleton: Skeleton3D
## Scene animations by id (startAnimation on the tamer), e.g. 8 in the sleep scene.
var _scene: PsxAnimator
var _scene_playing := false
## The animation startAnimationTamer set for STATE_SCRIPT (0 idle, 2 run, 3 walk).
var _script_animation := 0


func _ready() -> void:
	var model := Content.load_model(MODEL)
	if model == null:
		return
	_part("Model", func(): return Node3D.new()).add_child(model)
	var sidecar = Content.load_json(SIDECAR)
	if sidecar != null:
		radius = int(sidecar["skeleton"]["radius"])

	_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	_sounds = _part("AnimationSounds", func(): return AnimationSoundsComponent.new())
	_sounds.set_model(Content.load_json(MODEL))
	_sounds.sound.connect(func(bank: int, value: int):
		if bank != 4 and (field == null or field.is_on_screen(global_position)):
			animation_sound.emit(bank, value))
	_part("DropShadow", func(): return DropShadow.new())
	for anim_name in [ANIM_IDLE, ANIM_RUN, ANIM_WALK]:
		_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	# Root motion only when the game runs: the editor checks NodePath properties relative to the
	# node itself, not to root_node, and reports this valid track as an invalid path.
	if not Engine.is_editor_hint():
		var anim_root := _player.get_node(_player.root_node)
		_player.root_motion_track = NodePath("%s:bone_0" % anim_root.get_path_to(_skeleton))
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.play(ANIM_IDLE)
	_scene = PsxAnimator.new(_player, Content.load_json(MODEL))


func place(spawn: Dictionary) -> void:
	position = spawn["position"]
	_set_direction(spawn["rotation"])
	if Engine.is_editor_hint() and _player != null:
		_player.advance(0.0)  # idle pose in the editor (no _process there)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _player == null or field == null:
		return
	# the sound events the last frame's advance passed (every path below advances the player)
	_sounds.update(_player)
	var motion := Vector3.ZERO
	var held := 0
	if _scene_playing:
		motion = _scene.advance(delta)
	elif (state == STATE_CHANGE_MAP and sub_state < 2) or state == STATE_SCRIPT:
		# startAnimationTamer(2): he runs on in his direction through the fade out; in STATE_SCRIPT
		# the script's animation (a walk turned to its point each frame). Only the walk state checks
		# the map's walls (checkMapInteraction), so nothing stops him.
		_play(ANIM_RUN if state == STATE_CHANGE_MAP else _animation_name(_script_animation))
		_player.advance(delta)
		position += _skeleton.global_basis * _player.get_root_motion_position()
		return
	elif state == STATE_CHANGE_MAP:
		# setupTamerOnWarp: placed on the new map with animation 0; he stands through the fade in.
		_play(ANIM_IDLE)
		_player.advance(delta)
	else:
		# tamerTickWalkingState (tamer.c:541): the d-pad bits of POLLED_INPUT; R1 or △ held runs.
		var polled := pad.polled if pad != null else 0
		held = polled & Pad.DIRECTIONS
		if held != 0 and state == STATE_FREE:
			_play(ANIM_RUN if polled & (Pad.R1 | Pad.CANCEL) != 0 else ANIM_WALK)
			_set_direction(_input_direction(held))
		else:
			_play(ANIM_IDLE)
		_player.advance(delta)
		motion = _player.get_root_motion_position()
	var world_motion := _skeleton.global_basis * motion
	step += Vector2(world_motion.x, world_motion.z).length()
	var before := global_position
	if not step_blocked:
		_move(world_motion)
	# tickCameraFollowPlayer (map.c:4464): only free, following and with a direction held, the
	# camera moves by his screen motion (specs/camera.md §2.2).
	if camera_follow and state == STATE_FREE and held != 0:
		field.scroll_by(field.screen_motion(before, global_position), held)


## The entity scene's child `part_name` (specs/scenes.md §4.1: `Model`, the components); an entity
## made with .new() (the logic tests) gets it here.
func _part(part_name: String, make: Callable) -> Node:
	var node := get_node_or_null(part_name)
	if node == null:
		node = make.call()
		node.name = part_name
		add_child(node)
	return node


## tamerSetState (tamer.c:1359).
func set_state(value: int) -> void:
	state = value
	sub_state = 0


## The tamer's per-frame state code (the walk's movement is in _process): state 0 checks the map
## (tamerTickWalkingState -> checkMapInteraction, tamer.c:588), 5 the map change, 20 the message box.
func tick() -> void:
	match state:
		STATE_FREE:
			# tamerTickWalkingState (tamer.c:586): checkItemPickup, then checkMapInteraction.
			check_item_pickup()
			if map_interaction.is_valid():
				map_interaction.call()
			else:
				step_blocked = false
		STATE_CHANGE_MAP:
			tick_change_map()
		STATE_AWARD:
			tick_award_something()
		STATE_PICKUP:
			tick_pickup_item()
		STATE_CHEST:
			tick_take_chest()
	if state != STATE_FREE:
		step_blocked = false
	step = 0.0


## tamerTickChangeMap (tamer.c:1367): fade out running (animation 2), the map name at frame 10,
## changeMap at frame 20 (the new map places him standing), fade in, then free.
func tick_change_map() -> void:
	match sub_state:
		0:
			if fade != null:
				fade.fade_to_black(0x14)
			sub_state = 1
		1:
			var out := fade.out_current if fade != null else 0x14
			if out == 10 and show_map_name.is_valid():
				show_map_name.call(target_map)
			if out > 0x13:
				if change_map.is_valid():
					change_map.call(target_map, target_exit)
				if fade != null:
					fade.fade_from_black(0x14)
				if show_map_name.is_valid():
					show_map_name.call(-1)
				sub_state = 2
		2:
			if fade == null or fade.in_current > 0x13:
				set_state(STATE_FREE)
				if partner != null:
					partner.set_state(Partner.STATE_NORMAL)
				if map_interaction.is_valid():
					map_interaction.call()
				if clock != null:
					clock.running = true


## tamerTickAwardSomething (tamer.c:1751): the message box. Its caller has drawn the text into
## rows 120-155 of the text area. Medals and tamer levels (sub-states 1-3, MEDAL_AWARD_PENDING,
## TAMER_LEVEL_AWARD_PENDING) come with the systems that award them; until then sub-state 0 goes
## straight to 4.
func tick_award_something() -> void:
	match sub_state:
		0:
			# stopGameTime, startAnimation(tamer, 0): the walk code idles him outside STATE_FREE.
			if clock != null:
				clock.running = false
			if partner != null:
				partner.set_state(Partner.STATE_IDLE)
			camera_follow = false
			sub_state = 4
		4:
			if message_box != null and message_box.is_available():
				message_box.open(screen_rect())
				sub_state = 5
				_play_sound(7)
		5:
			# POLLED_INPUT & CONFIRM_BUTTON: held, not newly pressed (specs/text.md §2.8).
			if pad != null and pad.is_held(Pad.CONFIRM):
				if message_box != null:
					message_box.close(screen_rect())
				set_state(STATE_FREE)
				if partner != null:
					partner.set_state(Partner.STATE_NORMAL)
				camera_follow = true
				if clock != null:
					clock.running = true
				# setTextColor(1): the next text starts in the default colour.
				if message_box != null and message_box.text_area != null:
					message_box.text_area.set_text_color(1)


## getEntityScreenPos(tamer, 1) as the 10 x 10 rect the boxes grow from / shrink to
## (screenPos - 5, 10, 10), relative to the screen centre.
func screen_rect() -> Rect2i:
	var p := screen_position()
	return Rect2i(p.x - 5, p.y - 5, 10, 10)


## posData[node].posMatrix.workm.t: the world position of a bone (SPAWN_SPRITE_AT_ENTITY).
func bone_position(node: int) -> Vector3:
	if _skeleton == null or node < 0 or node >= _skeleton.get_bone_count():
		return global_position
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(node).origin


# --- items and chests (specs/map_items.md) -------------------------------------------------------

## checkItemPickup (tamer.c:618): next to an item (one tile), state 7, once until he has left it.
func check_item_pickup() -> void:
	if map_items == null:
		return
	picked_up_drop = map_items.near(tile())
	if picked_up_drop >= 0:
		if not has_picked_up:
			set_state(STATE_PICKUP)
			has_picked_up = true
	else:
		has_picked_up = false


## The tamer's collision tile (getModelTile).
func tile() -> Vector2i:
	return FieldMap.model_tile(int(position.x), int(-position.z))


## tamerTickPickupItem (tamer.c:1401), tamer state 7.
func tick_pickup_item() -> void:
	match sub_state:
		0:
			play_scene_animation(ANIM_PICKUP)
			camera_follow = false
			_draw_found(map_items.item_at(picked_up_drop))
			take_chest_state = 0
			take_item_frames = 0
			sub_state = 1
		1:
			if pickup_box != null and pickup_box.is_available():
				take_chest_item = map_items.item_at(picked_up_drop)
				_pickup_strings()
				pickup_box.open(screen_rect())
				sub_state = 2
		2:
			take_item_frames += 1
			if pad != null and pad.is_key_down(Pad.CONFIRM) and take_item_frames > 4:
				if take_item_frames < 0x3C:
					_play_sound(3)
				if not game_state.give_item(map_items.item_at(picked_up_drop), 0):
					_draw_full()
					take_item_frames = 0
					sub_state = 3
				else:
					_play_sound(7)
					sub_state = 4
		3:
			take_item_frames += 1
			if pad != null and pad.is_key_down(Pad.CONFIRM) and take_item_frames > 4:
				if take_item_frames < 0x3C:
					_play_sound(3)
				sub_state = 4
		4:
			if pickup_box != null:
				pickup_box.close(screen_rect())
			if take_chest_state == 0:
				# pickupItem (item.c:2633): the item leaves the ground if it went into the bag.
				if game_state.give_item(map_items.item_at(picked_up_drop), 1):
					map_items.remove(picked_up_drop)
			set_state(STATE_FREE)
			camera_follow = true
	take_item_frames = mini(take_item_frames, 10)


## tamerTickTakeChest (tamer.c:1493), tamer state 14.
func tick_take_chest() -> void:
	var chest := map_chests.chest(interacted_chest) if map_chests != null else {}
	if chest.is_empty():
		set_state(STATE_FREE)
		return
	match sub_state:
		0:
			play_scene_animation(0)
			if partner != null:
				partner.set_state(Partner.STATE_IDLE)
			camera_follow = false
			var at: Vector3i = chest["location"]
			look_at_psx(at.x, at.z)
			if not chest["taken"]:
				_draw_found(chest["item"])
				take_chest_state = 0
			else:
				var area := pickup_box.text_area if pickup_box != null else null
				if area != null:
					area.clear(PICKUP_TEXT_AREA)
					area.draw_string(_tamer_name(), 0, 0xC)
					area.draw_string(data.text(TEXT_EMPTY), 0, 0x18)
				take_chest_state = 2
			sub_state = 1
		1:
			if pickup_box != null and pickup_box.is_available():
				if map_chests.tick_open(interacted_chest):
					take_chest_item = chest["item"]
					_pickup_strings()
					pickup_box.open(screen_rect())
					take_item_frames = 0
					sub_state = 2 if take_chest_state == 0 else 4
		2:
			take_item_frames += 1
			# POLLED_INPUT: held, not newly pressed
			if pad != null and pad.is_held(Pad.CONFIRM) and take_item_frames > 5:
				take_item_frames = 0
				if not game_state.give_item(take_chest_item, 0):
					_draw_full()
					sub_state = 3
				else:
					game_state.set_trigger(int(chest["trigger"]))
					sub_state = 4
		3:
			if map_chests.tick_close(interacted_chest):
				sub_state = 4
		4:
			take_item_frames += 1
			if pad != null and pad.is_held(Pad.CONFIRM) and take_item_frames > 5:
				if pickup_box != null:
					pickup_box.close(screen_rect())
				if take_chest_state == 0:
					game_state.give_item(take_chest_item, 1)
				set_state(STATE_FREE)
				if partner != null:
					partner.set_state(Partner.STATE_NORMAL)
				camera_follow = true
	take_item_frames = mini(take_item_frames, 10)


## Sub-state 0's text: the tamer's name at row 0xC (not shown by the US box), the item's name at
## row 0x18, "Woah!" at row 0x24.
func _draw_found(item: Variant) -> void:
	var area := pickup_box.text_area if pickup_box != null else null
	if area == null or data == null:
		return
	area.clear(PICKUP_TEXT_AREA)
	area.draw_string(_tamer_name(), 0, 0xC)
	area.draw_string(data.localize(data.item(item).get("name")).strip_edges(), 0, 0x18)
	area.draw_string(data.text(TEXT_FOUND), 0, 0x24)


## The bag is full: row 0x18 becomes the full-bag text (TAKE_CHEST_STATE 1).
func _draw_full() -> void:
	var area := pickup_box.text_area if pickup_box != null else null
	if area != null and data != null:
		area.draw_string(data.text(TEXT_FULL), 0, 0x18)
	take_chest_state = 1
	_pickup_strings()


## renderItemPickupTextbox (tamer.c:801, US): the box's lines for TAKE_CHEST_STATE.
func _pickup_strings() -> void:
	if pickup_box == null:
		return
	match take_chest_state:
		0:
			pickup_box.strings = [[0, -125, 0x39, 0x5A, 12, 0, 0x24, false], [0xF, -125, 0x2D, 0x60, 12, 0, 0x18, false]]
		1:
			pickup_box.strings = [[0, -125, 0x39, 0xF0, 12, 0, 0x18, false]]
		_:
			pickup_box.strings = [[0, -125, 0x39, 0x90, 12, 0, 0x18, false]]


func _tamer_name() -> String:
	return str(game_state.state["tamer"]["name"]) if game_state != null else ""


func _play_sound(value: int) -> void:
	if sound != null:
		sound.play_sound(0, value)


## getEntityScreenPos (utils.c:176): bone 1 projected, relative to the screen centre.
func screen_position() -> Vector2i:
	if camera == null or _skeleton == null or not camera.is_inside_tree():
		return Vector2i.ZERO
	var world := _skeleton.global_transform * _skeleton.get_bone_global_pose(mini(SCREEN_BONE, _skeleton.get_bone_count() - 1)).origin
	var screen := FieldMap.unproject(camera, world)
	return Vector2i(roundi(screen.x) - 160, roundi(screen.y) - 120)


## startAnimation on the tamer: a scene animation by id; it holds its last frame until the tamer
## is free again.
func play_scene_animation(id: int) -> void:
	_scene_playing = _scene != null and _scene.play(id)


## animFrame >= frameCount of the scene animation (also true when the model lacks it).
func scene_animation_done() -> bool:
	return not _scene_playing or not _scene.playing


## entityLookAtLocation (map.c:3389).
func look_at_psx(target_x: int, target_z: int) -> void:
	var dx := target_x - int(position.x)
	var dz := target_z - int(-position.z)
	if dx != 0 or dz != 0:
		_set_direction((0x800 + roundi(atan2(dx, dz) * 0x800 / PI)) & 0xFFF)


## startAnimationTamer(id), as STATE_SCRIPT plays it: the loops (0 idle, 2 run, 3 walk) through his
## AnimationPlayer, the others as scene animations (PsxAnimator, held on their last frame).
func start_animation(id: int) -> void:
	_script_animation = id
	if id == 0 or id == 2 or id == 3:
		_scene_playing = false
	else:
		play_scene_animation(id)


## entity->anim.animId: the scene animation playing, else the loop's id.
func animation_id() -> int:
	if _scene_playing and _scene != null:
		return _scene.anim_id
	if _player == null:
		return _script_animation if state == STATE_SCRIPT else 0
	return int(_player.current_animation.trim_prefix("anim_")) if _player.current_animation != "" else 0


## PSX rotation.vy, for the scripts (ENTITY_SET_ROTATION, tickLookAtEntity).
func set_direction(vy: int) -> void:
	_set_direction(vy)


func _animation_name(id: int) -> String:
	var anim_name := "anim_%02d" % id
	return anim_name if _player.has_animation(anim_name) else ANIM_IDLE


func _play(anim_name: String) -> void:
	if _player.current_animation != anim_name:
		_player.play(anim_name)
		if _sounds != null:
			_sounds.restart()


## Held d-pad bits (POLLED_INPUT & 0xF000, not 0) to rotation.vy: the camera's direction
## (getMapRotation) snapped to 45 degrees, plus the direction's offset (_direction_offset).
func _input_direction(held: int) -> int:
	var rotation := field.map_rotation()
	var quadrant := rotation / 0x200
	if rotation % 0x200 >= 0x100:
		quadrant += 1
	rotation = quadrant * 0x200
	return (rotation + _direction_offset(held)) & 0xFFF


## tamerTickWalkingState's direction chain (tamer.c:565): up = away from the camera (+0x800), down
## +0, left +0x400, right +0xC00, diagonals in between; up wins over down, left over right.
static func _direction_offset(held: int) -> int:
	if held & Pad.UP != 0:
		return 0x600 if held & Pad.LEFT != 0 else (0xA00 if held & Pad.RIGHT != 0 else 0x800)
	if held & Pad.DOWN != 0:
		return 0x200 if held & Pad.LEFT != 0 else (0xE00 if held & Pad.RIGHT != 0 else 0x000)
	if held & Pad.LEFT != 0:
		return 0x400
	return 0xC00


func _set_direction(vy: int) -> void:
	direction = vy & 0xFFF
	rotation.y = Content.psx_yaw(direction)


## entityCheckCollision: the move is undone when the map blocks it. The game then turns the
## tamer along the wall (collisionGrace); here the move slides along the free axis instead.
func _move(motion: Vector3) -> void:
	var x := position.x
	var z := -position.z
	var dx := motion.x
	var dz := -motion.z
	if direction == 0x400 or direction == 0xC00:
		dz = 0.0
	if direction == 0 or direction == 0x800:
		dx = 0.0
	if not _blocked(x + dx, z + dz, dx, dz):
		pass
	elif not _blocked(x + dx, z, dx, 0.0):
		dz = 0.0
	elif not _blocked(x, z + dz, 0.0, dz):
		dx = 0.0
	else:
		return
	position.x += dx
	position.z -= dz


func _blocked(x: float, z: float, dx: float, dz: float) -> bool:
	return field.blocked(int(x), int(z), int(signf(dx)), int(signf(dz)), radius)
