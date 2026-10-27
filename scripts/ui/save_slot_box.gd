class_name SaveSlotBox
extends RefCounted
## A save-slot selector matching the authentic Digimon World slot browser (main_menu.c:1781-1825,
## renderSelectSlot / renderSaveSlotBox; specs/save.md):
## - Header box: CONTINUE / SAVE GAME / DELETE GAME
## - 5 vertically stacked slot boxes with PSX blue gradient backgrounds (renderMenuBox)
## - Yellow 1-pixel rectangle selection cursor (renderMenuSelector)
## - Multi-save slot navigation with vertical scrolling and page jumps
## - Confirmation dialogs for loading, saving/overwriting, and deleting
##
## Modes:
##   MODE_LOAD   : load a saved game (Continue menu)
##   MODE_SAVE   : save current game (Save machine / Game clear)
##   MODE_SLEEP  : prompt "Do you want to save?" then open save selector on Yes
##   MODE_DELETE : delete an existing save slot (Title menu)

signal finished

## Modes.
const MODE_LOAD := 0
const MODE_SAVE := 1
const MODE_SLEEP := 2
const MODE_DELETE := 3

## UI box slots used in UIBoxes.
const MAIN_BOX := 3
const CONFIRM_BOX := 4
const SLEEP_PROMPT_BOX := 2

## Number of slots visible simultaneously.
const VISIBLE_COUNT := 5
## Default total slots supported (extendable if saves exist beyond).
const DEFAULT_TOTAL_SLOTS := 15

## Text area rows.
const HEADER_V := 60
const SLOTS_V := 74
const SUB_BOX_V := 204

## Box rects (centred, screen coords relative to centre (160, 120)).
const HEADER_RECT := Rect2i(-112, -101, 224, 22)
const SLOT_W := 224
const SLOT_H := 34
const CONFIRM_RECT := Rect2i(-100, -23, 200, 46)
const SLEEP_RECT := Rect2i(-60, -20, 120, 46)

## Internal states.
const STATE_SELECT := 0
const STATE_CONFIRM := 1
const STATE_SAVING := 2
const STATE_SLEEP_PROMPT := 3
const STATE_DONE := 4

var boxes: UIBoxes
var text_area: TextArea
var game_state: Node
var data: Node
var pad: Pad
var sound: Node

var mode := MODE_LOAD
var selected_slot := -1

var _state := STATE_SELECT
var _selected_slot := 1
var _top_slot := 1
var _total_slots := DEFAULT_TOTAL_SLOTS
var _confirm_cursor := 0
var _sleep_cursor := 0
var _saves: Array = []
var _just_opened_main := false
var _just_opened_confirm := false
var _just_opened_sleep := false


func open() -> void:
	selected_slot = -1
	_selected_slot = 1
	_top_slot = 1
	_confirm_cursor = 0
	_sleep_cursor = 0
	_refresh_saves()

	if mode == MODE_SLEEP:
		_state = STATE_SLEEP_PROMPT
		_just_opened_sleep = true
		_draw_sleep_prompt()
		boxes.create_static(SLEEP_PROMPT_BOX, 1, UIBoxes.FEATURE_BLUE_GRADIENT, SLEEP_RECT,
				_tick_sleep_box, _render_sleep_box)
	else:
		_state = STATE_SELECT
		_just_opened_main = true
		_draw_header()
		_draw_slots()
		boxes.create_static(MAIN_BOX, 1, UIBoxes.FEATURE_BLUE_GRADIENT, HEADER_RECT, _tick, _render)


func _refresh_saves() -> void:
	if game_state != null and game_state.has_method("list_saves"):
		_saves = game_state.list_saves()
	else:
		_saves = []
	var highest := 0
	for s in _saves:
		var slot_id: int = int(s.get("slot", 0))
		if slot_id > highest:
			highest = slot_id
	_total_slots = maxi(DEFAULT_TOTAL_SLOTS, highest + 5)


func _get_save_for_slot(slot_id: int) -> Dictionary:
	for s in _saves:
		if int(s.get("slot", -1)) == slot_id:
			return s
	return {}


func _draw_header() -> void:
	if text_area == null:
		return
	text_area.clear(Rect2i(0, HEADER_V, 256, 12))
	text_area.set_text_color(1)
	match mode:
		MODE_LOAD:
			text_area.draw_string("CONTINUE", 4, HEADER_V)
		MODE_SAVE, MODE_SLEEP:
			text_area.draw_string("SAVE GAME", 4, HEADER_V)
		MODE_DELETE:
			text_area.draw_string("DELETE GAME", 4, HEADER_V)


func _draw_slots() -> void:
	if text_area == null:
		return
	text_area.clear(Rect2i(0, SLOTS_V, 256, VISIBLE_COUNT * 24))
	for i in VISIBLE_COUNT:
		var slot_id := _top_slot + i
		var y := SLOTS_V + i * 24
		var s := _get_save_for_slot(slot_id)
		text_area.set_text_color(1)
		text_area.draw_string(str(slot_id), 4, y)
		if not s.is_empty():
			var p: Dictionary = s.get("preview", {})
			var player_str := str(p.get("player", ""))
			var partner_str := str(p.get("partner", ""))
			if partner_str != "":
				partner_str = "/ " + partner_str
			var area_str := str(p.get("area", ""))
			var playtime_str := str(p.get("playtime", ""))
			text_area.draw_string(player_str, 32, y)
			text_area.draw_string(partner_str, 106, y)
			text_area.draw_string(area_str, 32, y + 12)
			text_area.draw_string(playtime_str, 150, y + 12)


func _draw_confirm() -> void:
	if text_area == null:
		return
	text_area.clear(Rect2i(0, SUB_BOX_V, 256, 24))
	text_area.set_text_color(1)
	var s := _get_save_for_slot(_selected_slot)
	var has_save := not s.is_empty()
	match mode:
		MODE_LOAD:
			text_area.draw_string("Load this save?", 4, SUB_BOX_V)
		MODE_SAVE, MODE_SLEEP:
			if has_save:
				text_area.draw_string("Overwrite this data?", 4, SUB_BOX_V)
			else:
				text_area.draw_string("Save to this slot?", 4, SUB_BOX_V)
		MODE_DELETE:
			text_area.draw_string("Delete this save?", 4, SUB_BOX_V)
	text_area.draw_string("Yes", 40, SUB_BOX_V + 12)
	text_area.draw_string("No", 120, SUB_BOX_V + 12)


func _draw_sleep_prompt() -> void:
	if text_area == null:
		return
	text_area.clear(Rect2i(0, SUB_BOX_V, 256, 24))
	text_area.set_text_color(1)
	text_area.draw_string("Do you want to save?", 4, SUB_BOX_V)
	text_area.draw_string("Yes", 16, SUB_BOX_V + 12)
	text_area.draw_string("No", 64, SUB_BOX_V + 12)


func _tick(_id: int) -> void:
	match _state:
		STATE_SELECT:
			_tick_select()
		STATE_CONFIRM:
			pass
		STATE_SAVING:
			pass
		STATE_SLEEP_PROMPT:
			pass
		STATE_DONE:
			pass


func _tick_select() -> void:
	if _just_opened_main:
		_just_opened_main = false
		return
	if pad.is_key_down(Pad.DOWN):
		if _selected_slot < _total_slots:
			_selected_slot += 1
			if _selected_slot >= _top_slot + VISIBLE_COUNT:
				_top_slot += 1
			_sound(2)
			_draw_slots()
	elif pad.is_key_down(Pad.UP):
		if _selected_slot > 1:
			_selected_slot -= 1
			if _selected_slot < _top_slot:
				_top_slot -= 1
			_sound(2)
			_draw_slots()
	elif pad.is_key_down(Pad.RIGHT):
		# Page Down (advance 5 slots).
		if _selected_slot < _total_slots:
			_selected_slot = mini(_selected_slot + VISIBLE_COUNT, _total_slots)
			_top_slot = clampi(_selected_slot - (VISIBLE_COUNT - 1), 1, maxi(1, _total_slots - VISIBLE_COUNT + 1))
			_sound(2)
			_draw_slots()
	elif pad.is_key_down(Pad.LEFT):
		# Page Up (rewind 5 slots).
		if _selected_slot > 1:
			_selected_slot = maxi(_selected_slot - VISIBLE_COUNT, 1)
			_top_slot = clampi(_selected_slot, 1, maxi(1, _total_slots - VISIBLE_COUNT + 1))
			_sound(2)
			_draw_slots()
	elif pad.is_key_down(Pad.CONFIRM):
		var s := _get_save_for_slot(_selected_slot)
		var has_save := not s.is_empty()
		if mode == MODE_LOAD and not has_save:
			_sound(4)
			return
		if mode == MODE_DELETE and not has_save:
			_sound(4)
			return
		_sound(3)
		_draw_confirm()
		_confirm_cursor = 0
		_state = STATE_CONFIRM
		_just_opened_confirm = true
		boxes.create_static(CONFIRM_BOX, 1, UIBoxes.FEATURE_BLUE_GRADIENT, CONFIRM_RECT,
				_tick_confirm_box, _render_confirm_box)
	elif pad.is_key_down(Pad.CANCEL):
		_sound(4)
		_close()


func _tick_confirm_box(_id: int) -> void:
	if _just_opened_confirm:
		_just_opened_confirm = false
		return
	if pad.is_key_down(Pad.LEFT) or pad.is_key_down(Pad.RIGHT) or pad.is_key_down(Pad.UP) or pad.is_key_down(Pad.DOWN):
		_confirm_cursor = 1 - _confirm_cursor
		_sound(2)
	elif pad.is_key_down(Pad.CONFIRM):
		boxes.remove_static(CONFIRM_BOX)
		if _confirm_cursor == 0:  # Yes
			_sound(3)
			selected_slot = _selected_slot
			if mode == MODE_SAVE or mode == MODE_SLEEP:
				_state = STATE_SAVING
				var err: int = game_state.save_game(selected_slot)
				if err != OK:
					push_error("SaveSlotBox: save failed: %s" % error_string(err))
					selected_slot = -1
				_close()
			elif mode == MODE_DELETE:
				if game_state != null and game_state.has_method("delete_save"):
					game_state.delete_save(selected_slot)
				_refresh_saves()
				_state = STATE_SELECT
				_draw_slots()
			else:
				# MODE_LOAD
				_close()
		else:  # No
			_sound(4)
			_state = STATE_SELECT
	elif pad.is_key_down(Pad.CANCEL):
		_sound(4)
		boxes.remove_static(CONFIRM_BOX)
		_state = STATE_SELECT


func _tick_sleep_box(_id: int) -> void:
	if _just_opened_sleep:
		_just_opened_sleep = false
		return
	if pad.is_key_down(Pad.LEFT) or pad.is_key_down(Pad.RIGHT) or pad.is_key_down(Pad.UP) or pad.is_key_down(Pad.DOWN):
		_sleep_cursor = 1 - _sleep_cursor
		_sound(2)
	elif pad.is_key_down(Pad.CONFIRM):
		boxes.remove_static(SLEEP_PROMPT_BOX)
		if _sleep_cursor == 0:  # Yes -> open save slot selector
			_sound(3)
			_state = STATE_SELECT
			_just_opened_main = true
			_draw_header()
			_draw_slots()
			boxes.create_static(MAIN_BOX, 1, UIBoxes.FEATURE_BLUE_GRADIENT, HEADER_RECT, _tick, _render)
		else:  # No -> close and wake
			_sound(4)
			_close()
	elif pad.is_key_down(Pad.CANCEL):
		_sound(4)
		boxes.remove_static(SLEEP_PROMPT_BOX)
		_close()


func _close() -> void:
	_state = STATE_DONE
	if boxes.boxes[CONFIRM_BOX].state != UIBoxes.STATE_CLOSED:
		boxes.remove_static(CONFIRM_BOX)
	if boxes.boxes[MAIN_BOX].state != UIBoxes.STATE_CLOSED:
		boxes.remove_static(MAIN_BOX)
	if boxes.boxes[SLEEP_PROMPT_BOX].state != UIBoxes.STATE_CLOSED:
		boxes.remove_static(SLEEP_PROMPT_BOX)
	finished.emit()


func _sound(id: int) -> void:
	if sound != null:
		sound.play_sound(0, id)
	elif Engine.get_main_loop() != null:
		var root_sound = Engine.get_main_loop().root.get_node_or_null("Sound")
		if root_sound != null:
			root_sound.play_sound(0, id)


func _render(canvas: CanvasItem, _id: int) -> void:
	if text_area == null:
		return
	var corners: Texture2D = boxes.corners if boxes != null else null

	# Render header text inside Header Box.
	text_area.render_string(canvas, 0, -102, -96, 200, 12, 0, HEADER_V, false)

	# Render the 5 slot boxes.
	var cursor_idx := _selected_slot - _top_slot
	for i in VISIBLE_COUNT:
		var slot_y := -79 + i * 36
		var slot_rect := Rect2i(-112, slot_y, SLOT_W, SLOT_H)
		PsxDraw.menu_box(canvas, slot_rect, corners)
		text_area.render_string(canvas, 0, -104, slot_y + 4, 208, 24, 0, SLOTS_V + i * 24, false)
		if i == cursor_idx:
			PsxDraw.menu_cursor(canvas, -110, slot_y + 2, 220, 30)


func _render_confirm_box(canvas: CanvasItem, _id: int) -> void:
	if text_area == null:
		return
	text_area.render_string(canvas, 0, -96, -19, 192, 24, 0, SUB_BOX_V, false)
	# Yes/No cursor.
	if _confirm_cursor == 0:
		PsxDraw.menu_cursor(canvas, -64, -23 + 24, 30, 13)
	else:
		PsxDraw.menu_cursor(canvas, 16, -23 + 24, 30, 13)


func _render_sleep_box(canvas: CanvasItem, _id: int) -> void:
	if text_area == null:
		return
	text_area.render_string(canvas, 0, -56, -16, 112, 24, 0, SUB_BOX_V, false)
	# Yes/No cursor.
	if _sleep_cursor == 0:
		PsxDraw.menu_cursor(canvas, -44, -20 + 24, 28, 13)
	else:
		PsxDraw.menu_cursor(canvas, 4, -20 + 24, 28, 13)
