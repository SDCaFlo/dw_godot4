class_name DigiviceView
extends Node
## renderDigiviceEntity (game_menu.c:3953; specs/status_screens.md §5): an entity's model drawn
## into the Digimon / Player screen with its own view: projection 0x200, the eye at
## DIGIVICE_ENTITY_VIEW (1300, 0, -3280) looking at the origin, one white light (0x80) from
## (100, 100, 100) (GsSetFlatLight; the field's ambient kept), the model at its RAISE_DATA view
## point, rotation 0, animation 0's first pose.
##
## A separate copy of the model in its own SubViewport and World3D: the field's entities stay as
## they are (the screens hide them meanwhile). The viewport covers the whole 320 x 240 screen, so
## the PSX projection's centre is the screen's. The screen draws it (`draw_on`) first in its box:
## the C sorts the model's ordering table in last, so it lies under the window's contents.

## True while a model is shown.
var showing := false

const PROJECTION := 0x200
const EYE := [1300, 0, -3280]
const LIGHT_DIRECTION := [100, 100, 100]
const LIGHT_COLOR := 0x80

var _viewport: SubViewport
var _camera: Camera3D
var _model: Node3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(320, 240) * maxi(FieldMap.render_scale, 1)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	# The PSX projection: 120 pixels up from the centre at distance 0x200.
	_camera.fov = rad_to_deg(2.0 * atan(120.0 / PROJECTION))
	_camera.near = 10.0
	_camera.far = 20000.0
	_viewport.add_child(_camera)
	_camera.position = Content.psx_to_godot(EYE)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.current = true


## Shows the model `rel` (a porter glTF path) at the PSX view point `view` ([x, y, z]).
func show_model(rel: String, view: Array) -> void:
	hide_model()
	var model := Content.load_model(rel)
	if model == null:
		return
	_model = model
	_viewport.add_child(model)
	model.position = Content.psx_to_godot(view)
	model.rotation.y = Content.psx_yaw(0)
	var light_dir := Content.psx_to_godot(LIGHT_DIRECTION).normalized()
	var light := Vector3.ONE * LIGHT_COLOR * 16.0 / 4096.0
	PsxLit.use_own_light(model, light_dir, light)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player: AnimationPlayer = players[0]
		if player.has_animation("anim_00"):
			player.play("anim_00")
			player.seek(0.0, true)
			player.pause()
	showing = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func hide_model() -> void:
	showing = false
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _model != null:
		_model.queue_free()
		_model = null


## Draws the model over the whole screen (the viewport's centre is the screen's).
func draw_on(canvas: CanvasItem) -> void:
	if showing:
		canvas.draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, Vector2(320, 240)), false)


## The partner's model and view point (its Digimon's raise_data `view`).
func show_digimon(data: Node, digimon: Variant) -> void:
	var mmd: String = data.digimon_file(digimon).get("mmd", "")
	var view: Dictionary = data.raise_data(digimon).get("view", {})
	if mmd == "":
		return
	var rel := "mmd_files/%s/%s.gltf" % [mmd.get_slice("/", 1), mmd.get_file().get_basename()]
	show_model(rel, [int(view.get("x", 0)), int(view.get("y", 0)), int(view.get("z", 0))])
