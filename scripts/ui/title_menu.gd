class_name TitleMenu
extends Control
## The title screen (runMainMenu, main/main.c:3685-3726; renderInitialMenu, main_menu.c:5342):
## the background image, the initial 3-option menu (New Game, Continue Game, Battle Mode), and
## the slot selector for loading a save. Its result tells Game what to do next.
##
## Emits `finished` with the chosen action when done:
##   - "new_game" : start a new game (mode 0)
##   - "load_game": load the save in `selected_slot` (mode 1)
##   - "battle_mode": not implemented yet (stubbed)

const SaveSlotBox := preload("res://scripts/ui/save_slot_box.gd")

signal finished(action: String)

## TITLE2.TIM background (ETCNA).
const TITLE_BACKGROUND := "tim_files/ETCNA/TITLE2.png"

## Menu box: (0x48, 0x32, 0xB0, 0x3A) in US coords -> 4 options (-88, -70, 176, 68).
const MENU_BOX_RECT := Rect2i(-88, -70, 176, 68)

## Menu items.
const ITEMS := ["NEW GAME", "CONTINUE GAME", "DELETE GAME", "BATTLE MODE"]

## Text area rows for the menu items.
const TEXT_V := 200

## The UI box slot for the menu.
const MENU_BOX := 2

## Internal states.
const STATE_MENU := 0
const STATE_SLOTS := 1
const STATE_FADING_OUT := 2
const STATE_DONE := 3

@export var background_texture: Texture2D

## Set before the title is shown, or defaulted in _ready.
var boxes: UIBoxes
var text_area: TextArea
var game_state: Node
var data: Node
var pad: Pad
var sound: Node
var selected_slot := -1

var _state := STATE_MENU
var _cursor := 0
var _has_saves := false
var _slot_box: SaveSlotBox
var _bg_texture: Texture2D
var _fade: Fade
var _next_action := ""
var _connected_loop := false
var _just_opened := true


func _ready() -> void:
	_just_opened = true
	if game_state == null and Engine.get_main_loop() != null:
		game_state = Engine.get_main_loop().root.get_node_or_null("GameState")
	if data == null and Engine.get_main_loop() != null:
		data = Engine.get_main_loop().root.get_node_or_null("GameData")
	if pad == null and Engine.get_main_loop() != null:
		var loop = Engine.get_main_loop().root.get_node_or_null("GameLoop")
		if loop != null:
			pad = loop.pad
	if sound == null and Engine.get_main_loop() != null:
		sound = Engine.get_main_loop().root.get_node_or_null("Sound")
	if text_area == null and data != null:
		text_area = TextArea.new(data, data.language)
	if boxes == null:
		boxes = UIBoxes.new()
		boxes.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(boxes)
		boxes.sound.connect(func(id: int): _sound(id))
	_fade = Fade.new()
	_fade.name = "Fade"
	add_child(_fade)
	_fade.hold(1)
	_fade.fade_from_black(20)

	_has_saves = game_state != null and not game_state.list_saves().is_empty()
	_bg_texture = background_texture
	if _bg_texture == null:
		_bg_texture = Content.load_texture(TITLE_BACKGROUND)

	_draw_menu_text()
	boxes.create_static(MENU_BOX, 1, UIBoxes.FEATURE_BLUE_GRADIENT, MENU_BOX_RECT, _tick_menu, _render_menu)

	var main_loop = Engine.get_main_loop()
	if main_loop != null:
		var loop = main_loop.root.get_node_or_null("GameLoop")
		if loop != null and not loop.frame.is_connected(_frame):
			loop.frame.connect(_frame)
			_connected_loop = true


func _exit_tree() -> void:
	if _connected_loop and Engine.get_main_loop() != null:
		var loop = Engine.get_main_loop().root.get_node_or_null("GameLoop")
		if loop != null and loop.frame.is_connected(_frame):
			loop.frame.disconnect(_frame)
		_connected_loop = false


func _frame() -> void:
	if _fade != null:
		_fade.tick()
	if _state == STATE_FADING_OUT:
		if _fade.out_current >= 20:
			_state = STATE_DONE
			if _connected_loop and Engine.get_main_loop() != null:
				var loop = Engine.get_main_loop().root.get_node_or_null("GameLoop")
				if loop != null and loop.frame.is_connected(_frame):
					loop.frame.disconnect(_frame)
				_connected_loop = false
			finished.emit(_next_action)
		return
	if boxes != null:
		boxes.step()


func _draw_menu_text() -> void:
	if text_area == null:
		return
	text_area.clear(Rect2i(0, TEXT_V, 256, 60))
	for i in ITEMS.size():
		if (i == 1 or i == 2) and not _has_saves:
			text_area.set_text_color(3)  # Dimmed.
		else:
			text_area.set_text_color(1)
		text_area.draw_string(ITEMS[i], 4, TEXT_V + i * 14)


func _draw() -> void:
	if _bg_texture != null:
		draw_texture_rect(_bg_texture, Rect2(Vector2.ZERO, Vector2(320, 240)), false)


func _sound(id: int) -> void:
	if sound != null:
		sound.play_sound(0, id)


func _tick_menu(_id: int) -> void:
	if _state != STATE_MENU:
		return
	if _just_opened:
		_just_opened = false
		return
	if pad.is_key_down(Pad.DOWN):
		_cursor = (_cursor + 1) % ITEMS.size()
		_sound(2)
	elif pad.is_key_down(Pad.UP):
		_cursor = (_cursor - 1 + ITEMS.size()) % ITEMS.size()
		_sound(2)
	elif pad.is_key_down(Pad.CONFIRM):
		match _cursor:
			0:  # New Game
				_sound(3)
				boxes.remove_static(MENU_BOX)
				_start_exit("new_game")
			1:  # Continue
				if _has_saves:
					_sound(3)
					_open_slot_selector(SaveSlotBox.MODE_LOAD)
				else:
					_sound(4)
			2:  # Delete Game
				if _has_saves:
					_sound(3)
					_open_slot_selector(SaveSlotBox.MODE_DELETE)
				else:
					_sound(4)
			3:  # Battle Mode
				_sound(4)  # Stubbed until Arena/VS step.


func _open_slot_selector(slot_mode: int = SaveSlotBox.MODE_LOAD) -> void:
	boxes.remove_static(MENU_BOX)
	_state = STATE_SLOTS
	_slot_box = SaveSlotBox.new()
	_slot_box.boxes = boxes
	_slot_box.text_area = text_area
	_slot_box.game_state = game_state
	_slot_box.data = data
	_slot_box.pad = pad
	_slot_box.sound = sound
	_slot_box.mode = slot_mode
	_slot_box.finished.connect(_on_slot_finished)
	_slot_box.open()


func _on_slot_finished() -> void:
	_has_saves = game_state != null and not game_state.list_saves().is_empty()
	if _slot_box.mode == SaveSlotBox.MODE_LOAD and _slot_box.selected_slot >= 0:
		selected_slot = _slot_box.selected_slot
		_start_exit("load_game")
	else:
		# Cancelled or deleted: go back to the menu.
		_state = STATE_MENU
		_cursor = 1 if _has_saves else 0
		_draw_menu_text()
		boxes.create_static(MENU_BOX, 1, UIBoxes.FEATURE_BLUE_GRADIENT, MENU_BOX_RECT, _tick_menu, _render_menu)


func _start_exit(action: String) -> void:
	_next_action = action
	_state = STATE_FADING_OUT
	if _fade != null:
		_fade.fade_to_black(20)


func _render_menu(canvas: CanvasItem, _id: int) -> void:
	if text_area == null:
		return
	for i in ITEMS.size():
		text_area.render_string(canvas, 0, -78, -64 + i * 14, 160, 12, 0, TEXT_V + i * 14, false)
	PsxDraw.menu_cursor(canvas, -82, -66 + _cursor * 14, 164, 14)
