extends SceneTree
## GameState (scripts/state/game_state.gd) against specs/game_state.md §4, with the real data
## porter output:
##   godot --headless --path . -s res://tests/test_game_state.gd
## Saves go to user://test_game_state_saves. Exits 1 if a check fails.

const SAVE_DIR := "res://test_game_state_saves"

var _failed := 0


func _initialize() -> void:
	var data: Node = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: no data porter output in %s" % data.root())
		data.free()
		quit(0)
		return
	var gs: Node = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.save_dir = SAVE_DIR
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for file in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute(SAVE_DIR.path_join(file))
	_eq(gs.list_saves(), [], "no saves yet")

	# New game: initializeDefaultSavegame + mode 0 (main_menu.c:4911, main.c:3439).
	gs.new_game()
	var s: Dictionary = gs.state
	_eq(s["boot_mode"], 0, "boot mode new game")
	_eq([s["clock"]["hour"], s["clock"]["minute"], s["clock"]["frame"]], [8, 0, 9600], "clock 08:00 = frame 0x2580")
	_eq(s["world"]["screen"], "dw1:twna01", "start map 0xCC (File City)")
	_eq(s["world"]["exit"], 9, "start exit")
	_eq(s["partner"]["digimon"], "dw1:agumon", "partner Agumon")
	_eq([s["partner"]["lives"], s["partner"]["care"]["remaining_lifetime"], s["partner"]["care"]["age"]], [3, 288, 3], "lives, lifetime, age")
	_eq(s["partner"]["care"].size(), 65, "every PartnerPara field")
	_eq([s["tamer"]["name"], s["partner"]["name"]], ["Player", "Digimon"], "default names (en_us)")
	_eq([s["money"], s["tamer"]["level"], s["tamer"]["raised_count"]], [50000, 0, 1], "money, tamer level, raised")
	_eq(s["inventory"]["size"], 30, "inventory size")
	_eq(s["inventory"]["slots"][0], {"item": "dw1:lrg_recovery", "amount": 40}, "default inventory slot 0")
	_eq(s["inventory"]["slots"][29], null, "default inventory slot 29 empty")
	_eq(s["script"]["card_shop"][0], data.key_of("items/card_data", 0x3A), "card shop starts with card 58")
	_eq(s["script"]["values"].size(), 256, "256 script values")
	gs.new_game("dw1:gabumon")
	_eq(gs.state["partner"]["digimon"], "dw1:gabumon", "new game with Gabumon")
	gs.new_game()

	# Script state helpers (script_interp.c).
	gs.set_trigger(9)
	_eq([gs.is_trigger_set(9), gs.is_trigger_set(8)], [true, false], "trigger 9 set, 8 not")
	gs.set_trigger(9)
	_eq(gs.state["script"]["triggers"], [9], "setting twice keeps one entry")
	gs.clear_trigger(9)
	_eq(gs.is_trigger_set(9), false, "trigger cleared")
	gs.set_script_value(10, 300)
	_eq(gs.script_value(10), 44, "script values are bytes (300 & 0xFF)")
	gs.set_card_count("dw1:phoenixmon", 3)
	_eq([gs.card_count("dw1:phoenixmon"), gs.card_count(1), gs.card_count("dw1:metalgreymon")], [3, 3, 0], "card counts by key and id")
	gs.set_card_count(1, 17)
	_eq(gs.card_count(1), 1, "card counts are nibbles (17 & 15)")

	# Techniques: learned_with replaces the 0x2C / 0x30 literal (utils2.c:320).
	gs.learn_move("dw1:dynamite_kick_44")
	_eq([gs.has_move("dw1:dynamite_kick_44"), gs.has_move(48)], [true, true], "Dynamite Kick 44 also learns 48")
	gs.learn_move("dw1:spit_fire")
	_eq(gs.state["partner"]["learned_moves"], ["dw1:dynamite_kick_44", "dw1:dynamite_kick_48", "dw1:spit_fire"], "learned list, sorted")
	gs.unlearn_move(48)
	_eq(gs.has_move(44), false, "unlearning one of the pair unlearns both")
	gs.set_condition(gs.CONDITION_HUNGRY, true)
	gs.set_condition(gs.CONDITION_SICK, true)
	gs.set_condition(gs.CONDITION_HUNGRY, false)
	_eq([gs.has_condition(gs.CONDITION_SICK), gs.has_condition(gs.CONDITION_HUNGRY), gs.state["partner"]["care"]["condition"]], [true, false, 64], "condition bits")

	# Save / load round trip; script values 35-255 are not saved (main_menu.c:5120).
	gs.state["money"] = 1234
	gs.state["world"]["poop"][5] = {"map": "dw1:mayo01", "x": 40, "y": 52, "size": 2}
	gs.state["script"]["item_keeper"]["dw1:meat"] = 12
	gs.set_trigger(700)
	gs.set_script_value(34, 7)
	gs.set_script_value(35, 8)
	var before: Dictionary = gs.state.duplicate(true)
	_eq(gs.save_game(1), OK, "save slot 1")
	gs.new_game()
	var result: Dictionary = gs.load_game(1)
	_eq([result["ok"], result["missing_keys"]], [true, []], "load slot 1")
	before["script"]["values"][35] = 0
	_eq(gs.state, before, "round trip gives the same state (value 35 reset)")
	_eq(typeof(gs.state["money"]), TYPE_INT, "numbers load as ints")
	_eq([gs.script_value(34), gs.script_value(35)], [7, 0], "value 34 saved, 35 not")
	var listed: Array = gs.list_saves()
	_eq([listed.size(), listed[0]["slot"], listed[0]["preview"]["area"]], [1, 1, "File City"], "list_saves with preview")

	# A save referring to content no loaded pack has, and broken files.
	gs.state["partner"]["digimon"] = "testpack:testmon"
	gs.save_game(2)
	result = gs.load_game(2)
	_eq([result["ok"], result["missing_keys"]], [true, ["testpack:testmon"]], "missing content is reported")
	var file := FileAccess.open(gs.save_path(3), FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	result = gs.load_game(3)
	_eq(result["ok"], false, "a broken file is refused")
	_eq(gs.load_game(9)["ok"], false, "an empty slot is refused")

	gs.free()
	data.free()
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for f in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute(SAVE_DIR.path_join(f))
		DirAccess.remove_absolute(SAVE_DIR)
	print("%s: GameState checks" % ("FAILED %d" % _failed if _failed else "OK"))
	quit(1 if _failed else 0)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failed += 1
		print("FAIL %s: %s != %s" % [what, actual, expected])
