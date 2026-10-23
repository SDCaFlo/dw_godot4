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

## PSX rotation.vy (4096 per turn).
var direction := 0
var radius := 100
var field: FieldMap

var _player: AnimationPlayer
var _skeleton: Skeleton3D


func _ready() -> void:
	var model := PorterAssets.load_model(MODEL)
	if model == null:
		return
	add_child(model)
	var sidecar = PorterAssets.load_json(SIDECAR)
	if sidecar != null:
		radius = int(sidecar["skeleton"]["radius"])

	_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for anim_name in [ANIM_IDLE, ANIM_RUN, ANIM_WALK]:
		_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	var anim_root := _player.get_node(_player.root_node)
	_player.root_motion_track = NodePath("%s:bone_0" % anim_root.get_path_to(_skeleton))
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.play(ANIM_IDLE)


func place(spawn: Dictionary) -> void:
	position = spawn["position"]
	_set_direction(spawn["rotation"])
	if Engine.is_editor_hint() and _player != null:
		_player.advance(0.0)  # idle pose in the editor (no _process there)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _player == null or field == null:
		return
	var input := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if input != Vector2.ZERO:
		_play(ANIM_RUN if Input.is_key_pressed(KEY_SHIFT) else ANIM_WALK)
		_set_direction(_input_direction(input))
	else:
		_play(ANIM_IDLE)

	_player.advance(delta)
	var motion := _skeleton.global_basis * _player.get_root_motion_position()
	_move(motion)
	field.follow(global_position)


func _play(anim_name: String) -> void:
	if _player.current_animation != anim_name:
		_player.play(anim_name)


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
	rotation.y = PorterAssets.psx_yaw(direction)


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
