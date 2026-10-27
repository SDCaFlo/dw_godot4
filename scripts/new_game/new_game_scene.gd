class_name NewGameScene
extends Node
## The new game's intro (newGameScene, main/main.c:3727; loadNewGameScene / tickNewGameJijimon,
## main/new_game.c; specs/new_game.md §2.2): the guide (Jijimon) walks in on a black screen, turns
## to the camera at frame 0x23 and the questions start (NamingRoutines.new_game_tick, while
## script value 0xF3 is 0). When they are done the screen fades to black and `finished` is emitted.
## The staging is exported, defaulting to the C's values, so a mod can restage the intro by
## overriding the scene (scenes/new_game/new_game.tscn).

signal finished

## The guide's Digimon key; empty: systems/new_game's guide.
@export var guide_digimon := ""
## setEntityPosition / setEntityRotation (PSX units, rotation.vy 4096 a turn) and its walk.
@export var guide_position := Vector3i(0x320, 0x96, 0)
@export var guide_rotation := 0x400
@export var guide_animation := 2
## NEW_GAME_JIJIMON_TICK_COUNT == 0x23: it turns, stands and the questions start.
@export var turn_frame := 0x23
@export var turn_rotation := 0x71
@export var turn_animation := 0
## GsSetRefView2: the eye (looking at the origin), GsSetProjection, DRAWING_OFFSET.
@export var eye := Vector3i(0, 0, -0x1068)
@export var projection := 1000.0
@export var drawing_offset := Vector2i(0xA0, 0xB9)
## GsSetFlatLight 0-2 (direction, colour 0-255); GsSetAmbient(0x800) is FieldLighting's.
@export var lights: Array[Dictionary] = [
	{"direction": [0x1E, 0x64, 0x1E], "color": [0x40, 0x40, 0x40]},
	{"direction": [-0x1E, 0x64, 0], "color": [0x28, 0x28, 0x28]},
	{"direction": [0, 0x64, -0x1E], "color": [0x26, 0x26, 0x26]},
]
## fadeFromBlack(0x14) at the start, fadeToBlack(0x28) at the end.
@export var fade_in_frames := 0x14
@export var fade_out_frames := 0x28
## The 3D view's resolution as a multiple of 320 x 240 (like the field's render_scale).
@export_range(1, 4) var render_scale := 4

## Script values: 0xF3 holds the questions until the guide has turned (0xFF, then 0).
const WAIT_VALUE := 0xF3
const NAMING := 0x20

@onready var _viewport: SubViewport = $World/SubViewport
@onready var _camera: Camera3D = $World/SubViewport/Camera3D
@onready var _hud: CanvasLayer = $Hud
@onready var routines: ScriptRoutines = $Routines

var guide: FieldDigimon
var text_area: TextArea
var boxes: UIBoxes
var ctx: ScriptContext
var textboxes: TextBoxes
var fade: Fade
var naming: NamingRoutines
## NEW_GAME_JIJIMON_TICK_COUNT.
var tick_count := 0
var _done := false
var _ended := false


func _ready() -> void:
	if not GameData.available():
		return
	_setup_view()
	_setup_text()
	_setup_guide()
	# newGameScene: initializeNamingBuffer(0), fadeFromBlack, value 0xFE = 0, 0xF3 = 0xFF.
	naming.new_game_start()
	fade.fade_from_black(fade_in_frames)
	GameState.set_script_value(0xFE, 0)
	GameState.set_script_value(WAIT_VALUE, 0xFF)
	GameLoop.frame.connect(_frame)


func _exit_tree() -> void:
	if GameLoop.frame.is_connected(_frame):
		GameLoop.frame.disconnect(_frame)
	if textboxes != null:
		textboxes.pad.set_repeat_mask(0)


## The camera (GsSetRefView2, GsSetProjection, DRAWING_OFFSET), the black screen, the lights.
func _setup_view() -> void:
	var container: SubViewportContainer = $World
	_viewport.size = Vector2i(FieldMap.SCREEN) * render_scale
	container.size = Vector2(_viewport.size)
	container.scale = Vector2.ONE / render_scale
	_camera.position = Content.psx_to_godot([eye.x, eye.y, eye.z])
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	# The projection centre's offset from the screen centre (the field's frustum, FieldMap).
	var centre := Vector2(drawing_offset) - FieldMap.SCREEN / 2
	var scale := FieldMap.NEAR / projection
	_camera.set_frustum(FieldMap.SCREEN.y * scale, Vector2(-centre.x, centre.y) * scale, FieldMap.NEAR, FieldMap.FAR)
	FieldLighting.apply(lights, FieldLighting.DAY)


## The text area, the six UI boxes, the script state and text boxes (as ScriptHost.start makes
## them), the routine node, the fade.
func _setup_text() -> void:
	text_area = TextArea.new(GameData, GameData.language)
	boxes = UIBoxes.new()
	boxes.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctx = ScriptContext.new()
	ctx.game_state = GameState
	ctx.data = GameData
	textboxes = TextBoxes.new(boxes, text_area, ctx, GameLoop.pad, GameData, GameState)
	# The lines are MAPHEAD's (in the field the interpreter hands the text boxes its files).
	textboxes.files = ScriptFiles.new()
	boxes.sound.connect(func(id: int): Sound.play_sound(0, id))
	textboxes.sound.connect(func(id: int): Sound.play_sound(0, id))
	textboxes.initialize_textbox()
	routines.configure(ctx, textboxes, GameState, GameData, Sound)
	naming = routines.node_for(NAMING) as NamingRoutines
	naming.guide_screen_position = _guide_screen_position
	fade = Fade.new()
	fade.name = "Fade"
	fade.hold(1)
	_hud.add_child(boxes)
	_hud.add_child(fade)


## loadNewGameScene: the guide at its place, walking in.
func _setup_guide() -> void:
	var key := guide_digimon
	if key == "":
		var record: Array = GameData.system("new_game")
		key = GameData.key_of("digimon/digimon_data", int(record[0]["guide"]["id"])) if not record.is_empty() else ""
	guide = load("res://scenes/field/digimon.tscn").instantiate() as FieldDigimon
	guide.name = "Guide"
	guide.moves_without_map = true
	_viewport.add_child(guide)
	if key == "" or not guide.load_digimon(GameData, key):
		return
	var shadow := guide.get_node_or_null("DropShadow")
	if shadow != null:
		shadow.visible = false
	guide.position = Content.psx_to_godot([guide_position.x, guide_position.y, guide_position.z])
	guide.set_direction(guide_rotation)
	guide.start_animation(guide_animation)


## One game frame (newGameScene's loop): the text boxes, the questions once the guide has turned,
## the guide's tick, the UI boxes, the fade; at the end, the fade to black.
func _frame() -> void:
	textboxes.tick_textbox_handling()
	if not _done and GameState.script_value(WAIT_VALUE) == 0:
		_done = naming.new_game_tick()
	_tick_guide()
	boxes.step()
	fade.tick()
	if _done and fade.out_current == 0:
		fade.fade_to_black(fade_out_frames)
	if _done and fade.out_current >= fade_out_frames and not _ended:
		_ended = true
		finished.emit()


## tickNewGameJijimon: the count, the turn at turn_frame (value 0xF3 = 0 starts the questions).
func _tick_guide() -> void:
	if tick_count < 30000:
		tick_count += 1
	if tick_count == turn_frame and guide != null:
		guide.set_direction(turn_rotation)
		guide.start_animation(turn_animation)
		GameState.set_script_value(WAIT_VALUE, 0)


## getEntityScreenPos(guide, bone 1), from the screen centre; null for another Digimon type.
func _guide_screen_position(type: int):
	if guide == null or GameData.id_of("digimon/digimon_data", guide.digimon) != type:
		return null
	var p := _camera.unproject_position(guide.bone_position(1)) / float(render_scale)
	return Vector2i(roundi(p.x) - 160, roundi(p.y) - 120)
