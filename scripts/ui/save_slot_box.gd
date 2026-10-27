class_name SaveSlotBox
extends RefCounted
## A save-slot selector drawn inside a UI box (specs/save.md §2.3): slots with preview information
## (player, partner, area, playtime), a cursor, and confirmation sub-boxes. Reused by the title
## menu (Load mode), the save machine (Save mode), and the sleep save prompt (Sleep mode).
##
## The caller creates it, configures references, calls open(), and awaits `finished`.
## The result is in `selected_slot` (-1 = cancelled, or slot ID >= 1).

signal finished

## Modes.
const MODE_LOAD := 0
const MODE_SAVE := 1
const MODE_SLEEP := 2

## UI box slots used.
const MAIN_BOX := 3
const CONFIRM_BOX := 4
const SLEEP_PROMPT_BOX := 2

## The text area rows this box uses (free from the dialogue and the tamer's box).
const TEXT_V := 140
## Slot preview height in text rows.
const SLOT_HEIGHT := 24
## Sub-box text row (confirm / sleep prompt), well within DRAW_LIMIT (244).
const SUB_BOX_V := 204
## Box rect (centred, screen coords relative to centre).
const BOX_RECT := Rect2i(-130, -70, 262, 108)
## Overwrite confirm box.
const CONFIRM_RECT := Rect2i(-100, -20, 200, 46)
## Sleep prompt box rect (renderSleepMenu: (0x6C, 0x65, 0x68, 0x26) -> relative (-52, -19, 104, 38)).
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
var _cursor := 0
var _confirm_cursor := 0
var _sleep_cursor := 0
var _page := 0
var _slots: Array = []  # [{slot, preview}] for the current page
var _save_existed: Array = [false, false]
var _just_opened_main := false
var _just_opened_confirm := false
var _just_opened_sleep := false


func open() -> void:
	selected_slot = -1
	_cursor = 0
	_confirm_cursor = 0
	_sleep_cursor = 0
	if mode == MODE_SLEEP:
		_state = STATE_SLEEP_PROMPT
		_just_opened_sleep = true
		_draw_sleep_prompt()
		boxes.create_static(SLEEP_PROMPT_BOX, 1, 0, SLEEP_RECT,
				_tick_sleep_box, _render_sleep_box)
	else:
		_state = STATE_SELECT
		_just_opened_main = true
		_load_page(_page)
		_draw_slots()
		boxes.create_static(MAIN_BOX, 1, UIBoxes.FEATURE_TITLE, BOX_RECT, _tick, _render)


func _load_page(page_index: int) -> void:
	var saves: Array = game_state.list_saves()
	_slots = []
	_save_existed = [false, false]
	var base_slot := page_index * 2 + 1
	for i in 2:
		var slot_id := base_slot + i
		var found := {}
		for s in saves:
			if int(s.get("slot", -1)) == slot_id:
				found = s
				break
		if found.is_empty():
			_slots.append({"slot": slot_id, "preview": {}})
			_save_existed[i] = false
		else:
			_slots.append(found)
			_save_existed[i] = true


func _draw_slots() -> void:
	text_area.clear(Rect2i(0, TEXT_V, 256, SLOT_HEIGHT * 2 + 24))
	for i in 2:
		var y := TEXT_V + i * (SLOT_HEIGHT + 12)
		var slot_id: int = int(_slots[i]["slot"])
		var p: Dictionary = _slots[i]["preview"]
		if p.is_empty():
			text_area.set_text_color(1)
			text_area.draw_string("Slot %d  -  Empty" % slot_id, 4, y)
		else:
			text_area.set_text_color(1)
			text_area.draw_string("Slot %d" % slot_id, 4, y)
			var player_str := str(p.get("player", ""))
			var partner_str := str(p.get("partner", ""))
			text_area.draw_string(player_str, 56, y)
			if partner_str != "":
				text_area.draw_string("/ " + partner_str, 120, y)
			text_area.draw_string(str(p.get("area", "")), 4, y + 12)
			var playtime_str: String = str(p.get("playtime", ""))
			text_area.draw_string(playtime_str, 190, y + 12)


func _draw_confirm() -> void:
	text_area.clear(Rect2i(0, SUB_BOX_V, 256, 24))
	text_area.set_text_color(1)
	if (mode == MODE_SAVE or mode == MODE_SLEEP) and _save_existed[_cursor]:
		text_area.draw_string("Overwrite this data?", 4, SUB_BOX_V)
	elif mode == MODE_SAVE or mode == MODE_SLEEP:
		text_area.draw_string("Save to this slot?", 4, SUB_BOX_V)
	else:
		text_area.draw_string("Load this save?", 4, SUB_BOX_V)
	text_area.draw_string("Yes", 40, SUB_BOX_V + 12)
	text_area.draw_string("No", 120, SUB_BOX_V + 12)


func _draw_sleep_prompt() -> void:
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
		_cursor = (_cursor + 1) % 2
		_sound(2)
	elif pad.is_key_down(Pad.UP):
		_cursor = (_cursor + 1) % 2
		_sound(2)
	elif pad.is_key_down(Pad.LEFT):
		if _page > 0:
			_page -= 1
			_load_page(_page)
			_draw_slots()
			_sound(2)
	elif pad.is_key_down(Pad.RIGHT):
		_page += 1
		_load_page(_page)
		_draw_slots()
		_sound(2)
	elif pad.is_key_down(Pad.CONFIRM):
		# In load mode, refuse empty slots.
		if mode == MODE_LOAD and _slots[_cursor]["preview"].is_empty():
			_sound(4)
			return
		_sound(3)
		_draw_confirm()
		_confirm_cursor = 0
		_state = STATE_CONFIRM
		_just_opened_confirm = true
		boxes.create_static(CONFIRM_BOX, 1, 0, CONFIRM_RECT,
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
			selected_slot = int(_slots[_cursor]["slot"])
			if mode == MODE_SAVE or mode == MODE_SLEEP:
				_state = STATE_SAVING
				var err: int = game_state.save_game(selected_slot)
				if err != OK:
					push_error("SaveSlotBox: save failed: %s" % error_string(err))
					selected_slot = -1
				_close()
			else:
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
			_load_page(_page)
			_draw_slots()
			boxes.create_static(MAIN_BOX, 1, UIBoxes.FEATURE_TITLE, BOX_RECT, _tick, _render)
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
	# Slot cursor.
	var cursor_y := -66 + _cursor * (SLOT_HEIGHT + 12)
	PsxDraw.selection_cursor(canvas, -126, cursor_y, 252, SLOT_HEIGHT + 4)
	# Render the slot text.
	for i in 2:
		var y := TEXT_V + i * (SLOT_HEIGHT + 12)
		text_area.render_string(canvas, 0, -126, -66 + i * (SLOT_HEIGHT + 12), 240, SLOT_HEIGHT, 0, y, false)


func _render_confirm_box(canvas: CanvasItem, _id: int) -> void:
	text_area.render_string(canvas, 0, -96, -16, 192, 24, 0, SUB_BOX_V, false)
	# Yes/No cursor.
	var cx := -96 + 36 + _confirm_cursor * 80
	PsxDraw.selection_cursor(canvas, cx - 4, -16 + 10, 30, 13)


func _render_sleep_box(canvas: CanvasItem, _id: int) -> void:
	text_area.render_string(canvas, 0, -56, -16, 112, 24, 0, SUB_BOX_V, false)
	# Yes/No cursor.
	var cx := -56 + 12 + _sleep_cursor * 48
	PsxDraw.selection_cursor(canvas, cx - 4, -16 + 10, 30, 13)
