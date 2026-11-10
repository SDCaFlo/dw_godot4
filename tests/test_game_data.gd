extends SceneTree
## GameData against the real data porter output (run python -m dwdata convert all first):
##   godot --headless --path . -s res://tests/test_game_data.gd
## Also against the disc-mode output (python -m dwdata convert all --disc <folder>; DW_DATA_OUTPUT=<output>):
## a US disc gives en_us only (data_porter/specs/from_disc.md §4), so the ja / en_eu checks become en_us-only ones.
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
	# Fishing (specs/fishing.md §4): the maps by key or id, their resolved polygons, bite chances by bait.
	_eq(data.fishing_map("dw1:mayo10")["spots"].size(), 6, "fishing_map(mayo10) spots")
	_eq(data.fishing_map(8)["spots"][0]["points"].size(), 9, "map 8 spot 0: FISH_D_8007A794's 9 points")
	_eq(data.fishing_map(8)["spots"][0]["points"][0], [-310.0, -13.0], "map 8 spot 0 point 0 (0xfeca, 0xfff3)")
	_eq(data.fishing_map(8)["seadramon_hours"], [], "no Seadramon on map 8 (9999)")
	_eq(data.fishing_map(6)["seadramon_hours"], [17.0, 8.0], "Seadramon on map 6 at 0x6a4 / 0x320")
	_eq(data.fishing_map(6)["water"]["rule"], "left_of_shore", "map 6: FISH_isFishableWater2")
	_eq(data.fishing_map(8)["water"]["shore"].size(), 16, "map 8 shore: FISH_D_8007A890")
	_eq(data.fishing_map(6)["seadramon_path"].size(), 8, "Seadramon path: FISH_D_8007A9CC")
	_eq(data.fishing_map(0), {}, "no fishing on map 0")
	_eq(data.fishing_bite_chance(38, 1), 20, "Meat (0x26), kind 1: FISH_BITE_CHANCE[1]")
	_eq(data.fishing_bite_chance(0x29, 0), 50, "bait 0x29, kind 0: FISH_BITE_CHANCE[18]")
	_eq(data.fishing_bite_chance(0x47, 0), 0, "a bait past the table")
	_eq(data.fishing()["sprites"].size(), 49, "FISH_SPRITES[49]")
	_eq(data.record("digimon/digimon_data", 999), {}, "record out of range")

	# Text by id, languages, and an id split over two blocks (each language defined once).
	var all_languages: bool = data.languages() == PackedStringArray(["ja", "en_us", "en_eu"])
	if not all_languages:
		_eq(data.languages(), PackedStringArray(["en_us"]), "a US disc's output: en_us only")
	_eq(data.text("STR_DIGIMON_NAME_AGUMON"), "Agumon", "text(id)")
	_eq(data.text("MAIN_D_8013143C", "en_us"), "Technique 1", "split id, en_us")
	_eq(data.text("NO_SUCH_STRING"), "", "missing id")
	if all_languages:
		_eq(data.text("STR_DIGIMON_NAME_AGUMON", "ja"), "アグモン", "text(id, ja)")
		_eq(data.text("MAIN_D_8013143C", "ja"), "技１", "split id, ja")
		data.set_language("ja")
		_eq(data.localize(data.digimon(3)["name"]), "アグモン", "localize after set_language")
		data.set_language("en_us")
	else:
		_eq(data.text("STR_DIGIMON_NAME_AGUMON", "ja"), "", "no ja text from a US disc")
		data.set_language("ja")
		_eq(data.language, "en_us", "set_language to a missing language keeps en_us")
		_eq(data.localize(data.digimon(3)["name"]), "Agumon", "localize stays en_us")

	# Keys next to the numeric ids (specs/content.md §2).
	_eq(data.digimon("dw1:agumon"), data.digimon(3), "digimon by key = by id")
	_eq(data.key_of("digimon/digimon_data", 129), "dw1:npc_greymon", "key_of")
	_eq(data.id_of("items/item_data", "dw1:meat"), 38, "id_of")
	_eq(int(data.evolution_paths("dw1:botamon")["id"]), 1, "evolution_paths by key")
	_eq(data.learn_chance("dw1:fire_tower", 0), 25, "learn_chance by key")
	_eq(data.map("dw1:mayo01")["id"], 0.0, "map by key")
	_eq(data.item_effect("dw1:meat")["handler"], "handleFood", "item_effect by key")
	_eq(data.digimon("dw1:nothing"), {}, "unknown key")

	# Entity view (specs/content.md §3).
	var agumon: Dictionary = data.entity("digimon", "dw1:agumon")
	_eq([agumon["key"], agumon["id"]], ["dw1:agumon", 3], "entity key and id")
	for component in ["digimon", "files", "sounds", "care", "evolution"]:
		_eq(agumon.has(component), true, "Agumon has component " + component)
	_eq(agumon.has("card"), false, "cards are not a Digimon component")
	_eq(data.cards_of("dw1:agumon"), [], "Agumon has no card")
	_eq(data.cards_of("dw1:metalgreymon").map(func(c): return c["key"]), ["dw1:metalgreymon"], "MetalGreymon's card")
	_eq(int(data.card("dw1:phoenixmon")["id"]), 1, "card by key")
	_eq(data.entity("card", 1)["key"], "dw1:phoenixmon", "card entity")
	_eq(agumon["care"]["sleep"].is_empty(), false, "Agumon sleep pattern")
	_eq(data.entity("digimon", 129).has("care"), false, "NPC Greymon has no care")
	_eq(data.entity("item", "dw1:meat")["effect"]["handler"], "handleFood", "item entity effect")
	_eq(data.entity("move", 2).has("learn"), true, "Spit Fire can be learned")
	_eq(data.entity("map", "dw1:mayo01").has("toilet"), true, "MAYO01 has a toilet")
	# Care properties (specs/care.md §4) replace the literal ids of partner_impl.c.
	var raise: Dictionary = agumon["care"]["raise"]
	_eq([int(raise["first_technique"]["slot"]), int(raise["first_technique"]["move"]["id"])], [0, 2], "Agumon's first technique")
	_eq([raise["eats_poop"], raise["raises_virus_bar"]], [false, true], "Agumon's poop properties")
	_eq(data.entity("digimon", "dw1:sukamon")["care"]["raise"]["raises_virus_bar"], false, "Sukamon's poop doesn't raise the virus bar")
	_eq(data.item("dw1:rest_pillow")["passive"], "sleep_boost", "Rest Pillow property")

	# Battle properties (specs/battle.md §6) replace the literal ids of the battle code.
	_eq(data.move(0x29)["buff"]["off"].map(func(v): return int(v)), [3, 10], "Muscle Charge buff")
	_eq(data.move(2).has("buff"), false, "Spit Fire is no buff")
	_eq(data.move(0x2D).get("counter", false), true, "Counter property")
	_eq(int(data.digimon(0x73)["battle_music"]), 3, "Machinedramon's battle music")
	_eq(int(data.digimon(0x71)["battle_scale"]), 0x1800, "Meteormon's battle scale")
	_eq(data.map(0x8F).get("no_battle_drops", false), true, "map 0x8f has no battle drops")
	_eq(data.system("battle_command_lists").size(), 6, "battle command lists")
	_eq(data.system("psx_math")[0]["values"].size(), 130, "sine table")

	# The game's font (data_porter/specs/font.md).
	if all_languages:
		_eq([data.font("en_us").size(), data.font("ja").size(), data.font("en_eu").size()], [79, 992, 188], "glyph counts")
	else:
		_eq(data.font("en_us").size(), 79, "US glyph count")
	_eq([int(data.font()[0]["code"]), data.font()[0]["char"], int(data.font()[0]["width"])], [0x8260, "Ａ", 12], "US glyph 0")
	_eq(data.font("en_us").back()["char"], "×", "US sentinel glyph")
	_eq(int(data.font_clut()[1]["raw"]), 0x6B5A, "FONT_CLUT[1]")
	_eq(data.text_colors().size(), 18 if all_languages else 17, "TEXT_COLORS (the EU entry only with the EU release)")
	_eq(int(data.font_ascii()[ord("'") - 0x20]["draw_string_code"]), 0x8175, "drawString's ' override")

	data.free()
	if OS.get_environment("DW_DATA_PACKS") == "":
		_test_packs()

	print("%s: GameData checks" % ("FAILED %d" % _failed if _failed else "OK"))
	quit(1 if _failed else 0)


## Packs merged over dw1 (specs/content.md §5): add, patch (by key, id, index), remove, entity
## components of an added Digimon, and a pack whose dependency is missing.
func _test_packs() -> void:
	var dir := "user://test_game_data_pack"
	var bad := "user://test_game_data_bad_pack"
	_write(dir + "/pack.json", {"id": "testpack", "depends": ["dw1"]})
	_write(dir + "/items/item_data.json", {"records": [
		{"key": "dw1:meat", "patch": {"price": 80, "name": {"text": {"en_us": "Big Meat"}}}},
		{"id": 0, "patch": {"merit": 7}},
		{"key": "dw1:metalbanana", "remove": true},
		{"key": "testpack:super_meat", "name": {"text": {"en_us": "Super Meat"}}, "price": 500},
		{"key": "dw1:stolen", "price": 1},
	]})
	_write(dir + "/digimon/digimon_data.json", {"records": [
		{"key": "testpack:testmon", "name": {"text": {"en_us": "Testmon"}},
		 "components": {"care": {"raise": {"favorite_food": "testpack:super_meat"}}}},
	]})
	_write(dir + "/systems/flee_chances.json", {"records": [{"index": 0, "patch": {"chance": 61}}]})
	_write(dir + "/digimon/raise_data.json", {"records": [{"id": 3, "patch": {"eats_poop": true}}]})
	_write(bad + "/pack.json", {"id": "badpack", "depends": ["nothere"]})
	ProjectSettings.set_setting("dw/data/packs", PackedStringArray([dir, bad]))

	var data: Node = load("res://scripts/data/game_data.gd").new()
	_eq(data.packs(), PackedStringArray(["dw1", "testpack"]), "pack with a missing dependency is skipped")
	_eq(int(data.item("dw1:meat")["price"]), 80, "patch by key")
	_eq(data.localize(data.item(38)["name"]), "Big Meat", "patch merges into a dictionary")
	_eq(data.item(38)["name"]["string_id"], "STR_ITEM_NAME_MEAT", "patch keeps the other fields")
	_eq(int(data.item(0)["merit"]), 7, "patch by id")
	_eq(data.item("dw1:metalbanana"), {}, "remove")
	_eq(data.item(127), {}, "removed id is gone")
	_eq(int(data.item(126)["id"]), 126, "ids after a removal still resolve")
	_eq(data.localize(data.item("testpack:super_meat")["name"]), "Super Meat", "added record by key")
	_eq(data.id_of("items/item_data", "testpack:super_meat"), -1, "added records have no numeric id")
	_eq(data.item("dw1:stolen"), {}, "a pack can't add keys in another namespace")
	_eq(data.changed_by("items/item_data", "dw1:meat"), PackedStringArray(["testpack"]), "changed_by")
	_eq(data.changed_by("items/item_data", "dw1:sm_recovery"), PackedStringArray(["testpack"]), "changed_by (patched by id)")
	_eq(data.changed_by("items/item_data", "dw1:med_recovery"), PackedStringArray(), "changed_by (untouched)")
	_eq(data.flee_chance(1, 1), 61, "patch by index (table without keys)")
	var testmon: Dictionary = data.entity("digimon", "testpack:testmon")
	_eq([testmon["key"], testmon["id"]], ["testpack:testmon", -1], "added entity")
	_eq(testmon["care"]["raise"]["favorite_food"], "testpack:super_meat", "added entity's own components")
	_eq(testmon.has("card"), false, "added entity has no dw1 components")
	_eq(int(data.digimon(3)["radius"]), 120, "tables the pack doesn't touch are unchanged")
	_eq(data.entity("digimon", "dw1:agumon")["care"]["raise"]["eats_poop"], true, "a pack can patch a care property")
	data.free()
	ProjectSettings.set_setting("dw/data/packs", PackedStringArray())


func _write(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failed += 1
		print("FAIL %s: %s != %s" % [what, actual, expected])
