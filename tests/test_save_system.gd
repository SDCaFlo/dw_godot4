extends SceneTree
## Tests for the save system, title menu, and save routines (specs/save.md):
##   godot --headless --path . -s res://tests/test_save_system.gd
## Exits 1 if a check fails.

const SaveSlotBox := preload("res://scripts/ui/save_slot_box.gd")
const TitleMenu := preload("res://scripts/ui/title_menu.gd")

var _failed := 0
var _checks := 0
var _started := false

var data: Node
var gs: Node
var boxes: UIBoxes
var area: TextArea
var pad: Pad
var ctx: ScriptContext
var tb: TextBoxes
var files: ScriptFiles
var interp: ScriptInterpreter
var routines: ScriptRoutines
var temp_dir := "res://test_saves"


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: porter output missing")
		quit(0)
		return false
	_setup()
	_test_recalculate_pp_and_arena()
	_test_save_pstat0_masking()
	_test_save_slot_box_save_and_load()
	_test_save_slot_box_sleep_mode()
	_test_save_routines()
	_test_title_menu()
	_teardown()
	var summary := "%s: save system checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks]
	print(summary)
	push_warning(summary)
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _setup() -> void:
	# Clean up any leftover test saves.
	if DirAccess.dir_exists_absolute(temp_dir):
		for f in DirAccess.get_files_at(temp_dir):
			DirAccess.remove_absolute(temp_dir.path_join(f))
	else:
		DirAccess.make_dir_recursive_absolute(temp_dir)

	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.save_dir = temp_dir
	gs.new_game()

	boxes = UIBoxes.new()
	root.add_child(boxes)
	area = TextArea.new(data, "en_us")
	pad = Pad.new()

	ctx = ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	tb = TextBoxes.new(boxes, area, ctx, pad, data, gs)
	files = ScriptFiles.new()
	interp = ScriptInterpreter.new(ctx, files, tb)
	interp.game_state = gs
	interp.data = data

	routines = ScriptRoutines.new()
	routines.add_child(load("res://scenes/script/save_routines.tscn").instantiate())
	root.add_child(routines)
	routines.configure(ctx, tb, gs, data)
	interp.routines = routines


func _teardown() -> void:
	routines.free()
	boxes.free()
	gs.free()
	data.free()
	if DirAccess.dir_exists_absolute(temp_dir):
		for f in DirAccess.get_files_at(temp_dir):
			DirAccess.remove_absolute(temp_dir.path_join(f))
		DirAccess.remove_absolute(temp_dir)


func _frame(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	tb.tick_textbox_handling()
	boxes.step()


func _press(button: int) -> void:
	_frame()
	_frame(button)
	_frame()


func _test_recalculate_pp_and_arena() -> void:
	gs.new_game()
	# Initial prosperity points should be 0.
	gs.recalculate_pp_and_arena()
	_check(gs.script_value(1) == 0, "initial PP is 0")

	# Recruit Numemon (0x0B, trigger 0xC8 + 0x0B = 0xD3): level 4 (Champion), but exception rule adds 1.
	gs.set_trigger(0xC8 + 0x0B)
	gs.recalculate_pp_and_arena()
	_check(gs.script_value(1) == 1, "Numemon recruit gives 1 PP")

	# Recruit Meramon (0x17, trigger 0xC8 + 0x17 = 0xDF): level 4 (Champion), adds level - 2 = 2.
	gs.set_trigger(0xC8 + 0x17)
	gs.recalculate_pp_and_arena()
	_check(gs.script_value(1) == 3, "Meramon recruit adds 2 PP (total 3)")

	# Recruit MetalGreymon (0x0E, trigger 0xC8 + 0x0E = 0xD6): level 5 (Ultimate), adds level - 2 = 3.
	gs.set_trigger(0xC8 + 0x0E)
	gs.recalculate_pp_and_arena()
	_check(gs.script_value(1) == 6, "MetalGreymon recruit adds 3 PP (total 6)")

	# Arena triggers reset when script value 3 >= 23 (0x17).
	gs.set_script_value(3, 22)
	gs.set_trigger(0x25)
	gs.set_trigger(0x26)
	gs.set_trigger(0x27)
	gs.recalculate_pp_and_arena()
	_check(gs.is_trigger_set(0x25) and gs.is_trigger_set(0x26) and gs.is_trigger_set(0x27),
			"arena triggers kept when pstat 3 < 23")

	gs.set_script_value(3, 23)
	gs.recalculate_pp_and_arena()
	_check(not gs.is_trigger_set(0x25) and not gs.is_trigger_set(0x26) and not gs.is_trigger_set(0x27),
			"arena triggers 0x25-0x27 cleared when pstat 3 >= 23")


func _test_save_pstat0_masking() -> void:
	gs.new_game()
	gs.set_script_value(0, 3)
	var err: int = gs.save_game(1)
	_check(err == OK, "save_game returns OK")
	_check(gs.script_value(0) == 3, "pstat 0 restored to 3 after save")

	# Check the file contents on disk: saved script value 0 should be 0.
	var text := FileAccess.get_file_as_string(gs.save_path(1))
	var json: Dictionary = JSON.parse_string(text)
	var saved_values: Array = json["state"]["script"]["values"]
	_check(int(saved_values[0]) == 0, "pstat 0 was written as 0 to disk")


func _test_save_slot_box_save_and_load() -> void:
	var slot_box := SaveSlotBox.new()
	slot_box.boxes = boxes
	slot_box.text_area = area
	slot_box.game_state = gs
	slot_box.data = data
	slot_box.pad = pad
	slot_box.mode = SaveSlotBox.MODE_SAVE

	var finished_called := [false]
	slot_box.finished.connect(func(): finished_called[0] = true)
	slot_box.open()

	# In Save Mode: cursor starts on Slot 1. Confirm opens confirm box.
	_press(Pad.CONFIRM)
	_check(boxes.boxes[SaveSlotBox.CONFIRM_BOX].state != UIBoxes.STATE_CLOSED,
			"confirm box opened on slot selection")

	# Confirm Yes on overwrite/save.
	_press(Pad.CONFIRM)
	_check(finished_called[0], "slot box finished signal emitted")
	_check(slot_box.selected_slot == 1, "selected slot is 1")
	_check(FileAccess.file_exists(gs.save_path(1)), "slot 1 save file exists on disk")

	# Now test Load Mode.
	slot_box = SaveSlotBox.new()
	slot_box.boxes = boxes
	slot_box.text_area = area
	slot_box.game_state = gs
	slot_box.data = data
	slot_box.pad = pad
	slot_box.mode = SaveSlotBox.MODE_LOAD
	finished_called = [false]
	slot_box.finished.connect(func(): finished_called[0] = true)
	slot_box.open()

	# Move cursor down to empty Slot 2.
	_press(Pad.DOWN)
	# Confirm on empty slot should refuse (confirm box remains closed).
	_press(Pad.CONFIRM)
	_check(boxes.boxes[SaveSlotBox.CONFIRM_BOX].state == UIBoxes.STATE_CLOSED,
			"cannot load empty slot 2")

	# Move cursor back up to Slot 1.
	_press(Pad.UP)
	_press(Pad.CONFIRM)
	_check(boxes.boxes[SaveSlotBox.CONFIRM_BOX].state != UIBoxes.STATE_CLOSED,
			"confirm box opened for slot 1 in load mode")
	# Confirm Yes.
	_press(Pad.CONFIRM)
	_check(finished_called[0] and slot_box.selected_slot == 1,
			"load mode selected slot 1 successfully")


func _test_save_slot_box_sleep_mode() -> void:
	var slot_box := SaveSlotBox.new()
	slot_box.boxes = boxes
	slot_box.text_area = area
	slot_box.game_state = gs
	slot_box.data = data
	slot_box.pad = pad
	slot_box.mode = SaveSlotBox.MODE_SLEEP

	var finished_called := [false]
	slot_box.finished.connect(func(): finished_called[0] = true)
	slot_box.open()

	# Sleep mode starts with sleep prompt box ("Do you want to save?").
	_check(boxes.boxes[SaveSlotBox.SLEEP_PROMPT_BOX].state != UIBoxes.STATE_CLOSED,
			"sleep prompt box open")
	var has_yes_ink := false
	for px in range(16, 32):
		for py in range(SaveSlotBox.SUB_BOX_V + 12, SaveSlotBox.SUB_BOX_V + 24):
			if area.pixel(px, py) != 0:
				has_yes_ink = true
				break
		if has_yes_ink:
			break
	_check(has_yes_ink, "sleep prompt 'Yes' text drawn inside text area")

	# Select No (move right, press Confirm).
	_press(Pad.RIGHT)
	_press(Pad.CONFIRM)
	_check(finished_called[0], "sleep prompt closed on No")
	_check(slot_box.selected_slot == -1, "no slot selected when No chosen")

	# Test Yes branch:
	slot_box = SaveSlotBox.new()
	slot_box.boxes = boxes
	slot_box.text_area = area
	slot_box.game_state = gs
	slot_box.data = data
	slot_box.pad = pad
	slot_box.mode = SaveSlotBox.MODE_SLEEP
	finished_called = [false]
	slot_box.finished.connect(func(): finished_called[0] = true)
	slot_box.open()

	# Confirm Yes on sleep prompt.
	_press(Pad.CONFIRM)
	# Sleep prompt closed, Main slot box opened!
	_check(boxes.boxes[SaveSlotBox.SLEEP_PROMPT_BOX].state == UIBoxes.STATE_CLOSED,
			"sleep prompt closed after Yes")
	_check(boxes.boxes[SaveSlotBox.MAIN_BOX].state != UIBoxes.STATE_CLOSED,
			"main slot box opened after Yes")

	# Select Slot 1, confirm overwrite.
	_press(Pad.CONFIRM)
	_press(Pad.CONFIRM)
	_check(finished_called[0] and slot_box.selected_slot == 1,
			"sleep save completed successfully to slot 1")


func _test_save_routines() -> void:
	var save_routine: Node = routines.node_for(0x30)
	_check(save_routine != null, "routine 0x30 handled by SaveRoutines")
	_check(routines.node_for(0x36) != null, "routine 0x36 handled by SaveRoutines")

	# Test 0x30 (Save machine).
	ctx.active_instruction = 0x10
	var waits: bool = routines.start(0x30)
	_check(waits, "routine 0x30 waits for user")
	_check(int(gs.state["boot_mode"]) == 1,
			"save machine sets boot_mode to BOOT_CONTINUE")

	# Select Slot 1 and confirm.
	_press(Pad.CONFIRM)
	_press(Pad.CONFIRM)
	routines.tick(0x30)
	_check(ctx.active_instruction == 0,
			"routine 0x30 clears active_instruction when save finished")

	# Test 0x36 (Game-clear save).
	ctx.active_instruction = 0x10
	waits = routines.start(0x36)
	_check(waits, "routine 0x36 waits for user")
	_check(int(gs.state["boot_mode"]) == 2,
			"game clear sets boot_mode to BOOT_GAME_CLEARED")
	_check(gs.state["world"]["screen"] == data.key_of("systems/maps", 0xCC),
			"game clear saves map as File City (0xCC)")
	_press(Pad.CANCEL)  # Cancel slot selection.
	routines.tick(0x36)
	_check(ctx.active_instruction == 0,
			"routine 0x36 finishes on cancel")


func _test_title_menu() -> void:
	var title = load("res://scenes/title/title_menu.tscn").instantiate()
	title.boxes = boxes
	title.text_area = area
	title.game_state = gs
	title.data = data
	title.pad = pad
	root.add_child(title)

	var title_action := [""]
	title.finished.connect(func(act: String): title_action[0] = act)

	# In TitleMenu: cursor 0 is "NEW GAME". Press Confirm.
	_press(Pad.CONFIRM)
	# Advance 25 frames for fade out.
	for i in 25:
		title._frame()
	_check(title_action[0] == "new_game", "title menu emits new_game")
	title.free()

	# Test Continue selection:
	title = load("res://scenes/title/title_menu.tscn").instantiate()
	title.boxes = boxes
	title.text_area = area
	title.game_state = gs
	title.data = data
	title.pad = pad
	root.add_child(title)
	title_action[0] = ""
	title.finished.connect(func(act: String): title_action[0] = act)

	# Move to Continue (pos 1).
	_press(Pad.DOWN)
	# Confirm Continue -> opens slot box.
	_press(Pad.CONFIRM)
	_check(boxes.boxes[SaveSlotBox.MAIN_BOX].state != UIBoxes.STATE_CLOSED,
			"slot box opened from title continue")

	# In slot box: confirm Slot 1, then confirm Yes.
	_press(Pad.CONFIRM)
	_press(Pad.CONFIRM)
	for i in 25:
		title._frame()
	_check(title_action[0] == "load_game" and title.selected_slot == 1,
			"title menu loads slot 1 on continue")
	title.free()
