class_name PauseHost
extends Node
## The pause in the field, battles and tournament matches (specs/pause.md): runs Pause at the end
## of the frames whose loop calls handlePause, shows box 5, and freezes the game (the scene tree
## paused) while handlePause's wait loop would run. Processes while the tree is paused, to read START.

var boxes: UIBoxes
var text_area: TextArea
## The Sound autoload (play_sound).
var sound: Node
var data: Node
var pause := Pause.new()
## Tests: returns the pad bits instead of the START action.
var read_pad := Callable()

## START presses since the last read, so a tap shorter than a frame still counts (as GameLoop's).
var _tapped := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause.box_created.connect(_on_box_created)
	pause.box_removed.connect(_on_box_removed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pad_start", false):
		_tapped |= Pad.START


## The end of a game frame. `in_loop`: the frame belongs to a loop that calls handlePause
## (gameLoop, BTL_battleMain's fight, the match's STD loop); outside them only a box left from the
## last pause closes (removePauseBox after those loops). `blocked`: Pause.is_blocked.
func frame(in_loop: bool, blocked: bool) -> void:
	var input := _read()
	if not in_loop:
		pause.remove_box()
		pause.box_visible = 0
		return
	if pause.handle(input, blocked):
		_set_frozen(true)


## handlePause's wait loop, once per Godot frame while frozen.
func _process(_delta: float) -> void:
	if not pause.is_paused():
		return
	if not pause.poll(_read()):
		_set_frozen(false)


func is_frozen() -> bool:
	return pause.is_paused()


func _set_frozen(on: bool) -> void:
	if is_inside_tree():
		get_tree().paused = on


func _read() -> int:
	if read_pad.is_valid():
		return int(read_pad.call())
	var down := _tapped
	_tapped = 0
	if Input.is_action_pressed("pad_start"):
		down |= Pad.START
	return down


## createPauseBox: "Pause" into the text area, box 5 with renderPauseBox, the sound. pauseFrame
## twice: the port draws only the boxes (UIBoxes.render_frame), not the other objects' ticks
## (specs/pause.md §4).
func _on_box_created() -> void:
	if text_area != null and data != null:
		text_area.draw_string(data.text(Pause.TEXT_ID), Pause.TEXT_U, Pause.TEXT_V)
	if boxes != null:
		boxes.create_static(Pause.BOX_ID, Pause.BOX_COLOR, 0, Pause.BOX_RECT, Callable(), _render_box)
		boxes.render_frame()
		boxes.render_frame()
	_play_sound()


## removeStaticUIBox(5) and the sound.
func _on_box_removed() -> void:
	if boxes != null:
		boxes.remove_static(Pause.BOX_ID)
	_play_sound()


func _play_sound() -> void:
	if sound != null:
		sound.play_sound(Pause.SOUND_BANK, Pause.SOUND_ID)


## renderPauseBox (utils2.c:462): the half-dark screen at layer 2, behind the box (layer 1) and in
## front of the other boxes, then the text at layer 0. UIBoxes drew the frame before this call, so
## it is drawn again over the dark.
func _render_box(canvas: CanvasItem, id: int) -> void:
	PsxDraw.box(canvas, Pause.DIM_RECT, Color.BLACK, true)
	var b: UIBoxes.Box = boxes.boxes[id]
	boxes.draw_box(canvas, b)
	if text_area != null:
		text_area.render_string(canvas, 0, b.final.position.x + Pause.TEXT_OFFSET, b.final.position.y + Pause.TEXT_OFFSET,
				Pause.TEXT_W, Pause.TEXT_H, Pause.TEXT_U, Pause.TEXT_V, true)
