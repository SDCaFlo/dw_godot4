extends SceneTree
## GameData against the real data porter output (run python -m dwdata convert all first):
##   godot --headless --path . -s res://tests/test_game_data.gd
## Exits 1 if a check fails.

var _failed := 0


func _init() -> void:
	var data: Node = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: no data porter output in %s" % data.root())
		data.free()
		quit(0)
		return

	_eq(data.localize(data.digimon(3)["name"]), "Agumon", "digimon(3) name")
	_eq(data.digimon(3)["type"]["name"], "vaccine", "Agumon type")
	_eq(data.digimon_file(3)["mmd"], "CHDAT/MMD0/AGUM.MMD", "Agumon model file")
	_eq(int(data.move(2)["power"]), 66, "Spit Fire power")
	_eq(data.text_entry("main/item", "MOVE_NAMES", 2), "Spit Fire", "MOVE_NAMES[2]")
	_eq(data.localize(data.item(38)["name"]), "Meat", "item(38) name")
	_eq(int(data.item(38)["price"]), 50, "Meat price")
	_eq(data.item_effect(38)["handler"], "handleFood", "Meat handler")
	_eq(data.type_factor(0, 3), 20, "fire vs earth")
	_eq(data.learn_chance(0, 0), 25, "Fire Tower learn chance")
	_eq(data.evolution_paths(1)["to"].map(func(id): return int(id)), [2], "Botamon -> Koromon")
	_eq(data.find("text/main/main_menu", "block", "LABELS").is_empty(), false, "text table with NUL padding")
	_eq(data.evolution_item_target(71)["target"]["id"], 5, "Grey Claws -> Greymon")
	_eq(data.item_take_distance(1), 10, "Botamon take distance")
	_eq(data.battle_commands(99), 3, "commands below brain 100")
	_eq(data.battle_commands(999), 9, "commands from brain 500")
	_eq(data.battle_commands(999, true), 7, "arena commands from brain 500")
	_eq(data.flee_chance(3, 3), 30, "virus vs virus flee")
	_eq(data.flee_chance(0, 1), -1, "flee for an unknown type")
	_eq(data.tournament_win_chance(5, 3), 95, "ultimate beats rookie")
	_eq(data.tournaments_on_day(30), data.tournaments_on_day(0), "schedule wraps every 30 days")
	_eq(data.map(0)["file"], "MAYO01", "map(0)")
	_eq(data.map_id("MAYO04A"), 3, "map_id(MAYO04A)")
	_eq(data.localize(data.map(0)["name"]).strip_edges(), "Native Forest", "map(0) name")
	_eq(data.system("fishing").size(), 1, "system(fishing)")
	_eq(data.record("digimon/digimon_data", 999), {}, "record out of range")

	# Text by id, languages, and an id split over two blocks (each language defined once).
	_eq(data.text("STR_DIGIMON_NAME_AGUMON"), "Agumon", "text(id)")
	_eq(data.text("STR_DIGIMON_NAME_AGUMON", "ja"), "アグモン", "text(id, ja)")
	_eq(data.text("MAIN_D_8013143C", "en_us"), "Technique 1", "split id, en_us")
	_eq(data.text("MAIN_D_8013143C", "ja"), "技１", "split id, ja")
	_eq(data.text("NO_SUCH_STRING"), "", "missing id")
	data.set_language("ja")
	_eq(data.localize(data.digimon(3)["name"]), "アグモン", "localize after set_language")

	data.free()

	# A mod folder replaces a whole table file.
	if OS.get_environment("DW_DATA_MODS") == "":
		var mod := "user://test_game_data_mod"
		DirAccess.make_dir_recursive_absolute(mod + "/items")
		var file := FileAccess.open(mod + "/items/shops.json", FileAccess.WRITE)
		file.store_string('{"records": [{"maps": [1], "shopkeepers": []}]}')
		file.close()
		ProjectSettings.set_setting("dw/data/mod_dirs", PackedStringArray([mod]))
		var modded: Node = load("res://scripts/data/game_data.gd").new()
		_eq(modded.shops()["maps"].size(), 1, "mod overrides items/shops")
		_eq(int(modded.item(38)["price"]), 50, "tables without a mod file are unchanged")
		modded.free()
		DirAccess.remove_absolute(mod + "/items/shops.json")

	print("%s: GameData checks" % ("FAILED %d" % _failed if _failed else "OK"))
	quit(1 if _failed else 0)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failed += 1
		print("FAIL %s: %s != %s" % [what, actual, expected])
