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
## The bone getEntityScreenPos reads for the box's start point (tamer.c:1801).
const SCREEN_BONE := 1

## PSX rotation.vy (4096 per turn).
var direction := 0
var radius := 100
var field: FieldMap
## Entity 0 of the entity table (FieldEntities): on the map and on screen (isInvisible).
var on_screen := true
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
	add_child(model)
	var sidecar = Content.load_json(SIDECAR)
	if sidecar != null:
		radius = int(sidecar["skeleton"]["radius"])

	_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
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
		var input := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
		held = _held_directions(input)
		if input != Vector2.ZERO and state == STATE_FREE:
			_play(ANIM_RUN if Input.is_key_pressed(KEY_SHIFT) else ANIM_WALK)
			_set_direction(_input_direction(input))
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


## tamerSetState (tamer.c:1359).
func set_state(value: int) -> void:
	state = value
	sub_state = 0


## The tamer's per-frame state code (the walk's movement is in _process): state 0 checks the map
## (tamerTickWalkingState -> checkMapInteraction, tamer.c:588), 5 the map change, 20 the message box.
func tick() -> void:
	match state:
		STATE_FREE:
			if map_interaction.is_valid():
				map_interaction.call()
			else:
				step_blocked = false
		STATE_CHANGE_MAP:
			tick_change_map()
		STATE_AWARD:
			tick_award_something()
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
				# playSound(0, 7): later with audio.
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


## getEntityScreenPos (utils.c:176): bone 1 projected, relative to the screen centre.
func screen_position() -> Vector2i:
	if camera == null or _skeleton == null or not camera.is_inside_tree():
		return Vector2i.ZERO
	var world := _skeleton.global_transform * _skeleton.get_bone_global_pose(mini(SCREEN_BONE, _skeleton.get_bone_count() - 1)).origin
	var screen := camera.unproject_position(world)
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


## The d-pad bits of a held direction (POLLED_INPUT & 0xF000).
static func _held_directions(input: Vector2) -> int:
	var held := 0
	if input.x < 0:
		held |= Pad.LEFT
	elif input.x > 0:
		held |= Pad.RIGHT
	if input.y < 0:
		held |= Pad.UP
	elif input.y > 0:
		held |= Pad.DOWN
	return held


## Pad direction to rotation.vy: the camera's direction (getMapRotation) snapped to 45 degrees,
## then up = away from the camera (+0x800), left +0x400, right +0xC00, diagonals in between.
func _input_direction(input: Vector2) -> int:
	var rotation := field.map_rotation()
	var quadrant := rotation / 0x200
	if rotation % 0x200 >= 0x100:
		quadrant += 1
	rotation = quadrant * 0x200
	var offsets := {
		Vector2i(0, -1): 0x800, Vector2i(-1, -1): 0x600, Vector2i(1, -1): 0xA00,
		Vector2i(0, 1): 0x000, Vector2i(-1, 1): 0x200, Vector2i(1, 1): 0xE00,
		Vector2i(-1, 0): 0x400, Vector2i(1, 0): 0xC00,
	}
	var key := Vector2i(signi(roundi(input.x)), signi(roundi(input.y)))
	return (rotation + offsets.get(key, 0)) & 0xFFF


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
