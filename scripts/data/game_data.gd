extends Node
## Runtime access to the data porter output (data_porter/output, see data_porter/CLAUDE.md).
## Autoload "GameData".
##
## Every table is one JSON file of the porter (`digimon/digimon_data.json` = table
## "digimon/digimon_data"), loaded on first use and cached. Records keep the original array
## index as id; references are {"id", "name"}; names are {"string_id", "text": {ja, en_us, en_eu}}.
## What each field means and how the original code used it is in data_porter/specs/<group>.md.
## Numbers inside records are floats, as Godot's JSON parser returns them (int() them where an
## int is needed); the accessors below that return a number return an int.
##
## Output folder: the DW_DATA_OUTPUT environment variable or the "dw/data/output_dir" project
## setting. Mods: folders in DW_DATA_MODS (separated by ";") or the "dw/data/mod_dirs" setting;
## a mod replaces whole table files at the same relative path, later folders win.
## Text language: the "dw/data/language" setting (ja, en_us, en_eu) or set_language().

signal language_changed(language: String)

const SETTING := "dw/data/output_dir"
const DEFAULT_DIR := "res://data_porter/output"
const MODS_SETTING := "dw/data/mod_dirs"
const LANGUAGE_SETTING := "dw/data/language"
const LANGUAGES: PackedStringArray = ["ja", "en_us", "en_eu"]
## TOURNAMENT_SCHEDULE covers 30 days (script_common.c:585).
const SCHEDULE_DAYS := 30

var language := "en_us"

var _root := ""
var _mods := PackedStringArray()
var _tables := {}
## string id -> {language: text}, built on the first text() call.
var _text_ids := {}
## "table|block" -> {index: entry}
var _blocks := {}


func _init() -> void:
	var env := OS.get_environment("DW_DATA_OUTPUT")
	_root = env if env != "" else ProjectSettings.globalize_path(ProjectSettings.get_setting(SETTING, DEFAULT_DIR))
	var mods_env := OS.get_environment("DW_DATA_MODS")
	var mods: PackedStringArray = mods_env.split(";", false) if mods_env != "" else ProjectSettings.get_setting(MODS_SETTING, PackedStringArray())
	for dir in mods:
		_mods.append(ProjectSettings.globalize_path(dir))
	set_language(ProjectSettings.get_setting(LANGUAGE_SETTING, language))


# --- Files and tables ------------------------------------------------------------------------

func root() -> String:
	return _root


func mod_dirs() -> PackedStringArray:
	return _mods


## True when the porter output is there (python -m dwdata convert all has run).
func available() -> bool:
	return FileAccess.file_exists(_root.path_join("catalog.json"))


## File a table is read from: the last mod folder that has it, else the output folder.
func file_for(table_name: String) -> String:
	var rel := table_name + ".json"
	for i in range(_mods.size() - 1, -1, -1):
		var modded := _mods[i].path_join(rel)
		if FileAccess.file_exists(modded):
			return modded
	return _root.path_join(rel)


## Whole table file: table, source, schema, records, used_by, godot. {} if it can't be read
## (reported once).
func table(table_name: String) -> Dictionary:
	if _tables.has(table_name):
		return _tables[table_name]
	var file := file_for(table_name)
	var text := FileAccess.get_file_as_string(file)
	# NUL padding kept in text "variants" ("BackOK\u0000"): Godot strings can't hold NUL, so it
	# is read as the two characters \0 (the YAML spelling) instead of U+FFFD.
	if text.contains("\\u0000"):
		text = text.replace("\\u0000", "\\\\0")
	var json = JSON.parse_string(text) if text != "" else null
	if not json is Dictionary or not json.get("records") is Array:
		push_error("GameData: cannot read table %s from %s (run: python -m dwdata convert all)" % [table_name, file])
		json = {}
	_tables[table_name] = json
	return json


func records(table_name: String) -> Array:
	return table(table_name).get("records", [])


## Record at an original array index, or {}.
func record(table_name: String, index: int) -> Dictionary:
	var rows := records(table_name)
	return rows[index] if index >= 0 and index < rows.size() else {}


## First record whose `field` equals `value`; a reference field ({"id", "name"}) matches on id.
func find(table_name: String, field: String, value: Variant) -> Dictionary:
	for row in records(table_name):
		if _matches(row.get(field), value):
			return row
	return {}


func find_all(table_name: String, field: String, value: Variant) -> Array:
	return records(table_name).filter(func(row): return _matches(row.get(field), value))


## Drops the cached tables (after changing mods or re-running the porter).
func reload() -> void:
	_tables.clear()
	_text_ids.clear()
	_blocks.clear()


static func _matches(field_value: Variant, value: Variant) -> bool:
	if field_value is Dictionary and field_value.has("id"):
		field_value = field_value["id"]
	if typeof(field_value) in [TYPE_INT, TYPE_FLOAT] and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return field_value == value
	return typeof(field_value) == typeof(value) and field_value == value


# --- Text (specs/text.md) --------------------------------------------------------------------

func set_language(value: String) -> void:
	if not value in LANGUAGES:
		push_error("GameData: unknown language %s (one of %s)" % [value, LANGUAGES])
		return
	if value == language:
		return
	language = value
	language_changed.emit(language)


## Named string by C id (STR_DIGIMON_NAME_AGUMON), as written (control codes kept);
## "" if it doesn't exist in that language's release.
func text(string_id: String, lang := "") -> String:
	if _text_ids.is_empty():
		_index_text()
	var texts: Dictionary = _text_ids.get(string_id, {})
	var value = texts.get(lang if lang != "" else language)
	return value if value != null else ""


## Entry of an entries block by array index: text_entry("main/item", "MOVE_NAMES", 2) = "Spit Fire".
func text_entry(table_name: String, block: String, index: int, lang := "") -> String:
	var entry: Dictionary = _block(table_name, block).get(index, {})
	return localize(entry, lang)


## Text of a name reference ({"string_id", "text"}) or a string record ({"text"}); "" otherwise.
func localize(value: Variant, lang := "") -> String:
	if not value is Dictionary or not value.get("text") is Dictionary:
		return ""
	var text_value = value["text"].get(lang if lang != "" else language)
	return text_value if text_value != null else ""


func _block(table_name: String, block: String) -> Dictionary:
	var key := table_name + "|" + block
	if not _blocks.has(key):
		var entries := {}
		var row := find("text/" + table_name, "block", block)
		for entry in row.get("entries", []):
			entries[int(entry["index"])] = entry
		_blocks[key] = entries
	return _blocks[key]


# Some ids are defined in two blocks, each for other releases (e.g. MAIN_D_8013143C): per
# language the first defined text wins.
func _index_text() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(_root.path_join("catalog.json")))
	if not catalog is Dictionary:
		push_error("GameData: cannot read %s (run: python -m dwdata convert all)" % _root.path_join("catalog.json"))
		return
	for info in catalog["tables"]:
		if info["group"] != "text":
			continue
		for row in records(info["table"]):
			for string in row.get("strings", []) + row.get("entries", []):
				if string.get("id") == null:
					continue
				var texts: Dictionary = _text_ids.get_or_add(string["id"], {})
				for lang in string["text"]:
					if string["text"][lang] != null and not texts.has(lang):
						texts[lang] = string["text"][lang]


# --- Digimon (specs/digimon.md) --------------------------------------------------------------

func digimon(id: int) -> Dictionary:
	return record("digimon/digimon_data", id)


## Model / texture files (CHDAT/MMD0/AGUM.MMD), the names of the asset porter output.
func digimon_file(id: int) -> Dictionary:
	return record("digimon/file_names", id)


func digimon_sounds(id: int) -> Dictionary:
	return record("digimon/sound_ids", id)


## Partner care data (66 partner ids).
func raise_data(id: int) -> Dictionary:
	return record("digimon/raise_data", id)


func sleep_pattern(id: int) -> Dictionary:
	return record("digimon/sleep_patterns", id)


## ITEM_TAKE_DISTANCE[id - 1]; -1 if the Digimon has none.
func item_take_distance(digimon_id: int) -> int:
	return find("digimon/item_take_distance", "digimon", digimon_id).get("distance", -1)


# --- Evolution (specs/evolution.md) ----------------------------------------------------------

func evolution_requirements(id: int) -> Dictionary:
	return record("evolution/requirements", id)


## EVOLUTION_PATHS has no row for id 0: looked up by id.
func evolution_paths(id: int) -> Dictionary:
	return find("evolution/paths", "id", id)


func evolution_gains(id: int) -> Dictionary:
	return record("evolution/stat_gains", id)


func evolution_item_target(item_id: int) -> Dictionary:
	return find("evolution/item_targets", "item", item_id)


# --- Moves (specs/moves.md) ------------------------------------------------------------------

func move(id: int) -> Dictionary:
	return record("moves/move_data", id)


## TYPE_FACTORS[attacker][defender], 10 = x1 (BTL_calculateDamage); -1 for an unknown element.
func type_factor(attacker_element: int, defender_element: int) -> int:
	var against: Array = record("moves/type_factors", attacker_element).get("against", [])
	if defender_element < 0 or defender_element >= against.size():
		return -1
	return against[defender_element]["factor"]


## MOVE_LEARN_CHANCES[move][slot], slot = index of the matching element among the partner's 3;
## -1 for a technique that can't be learned this way.
func learn_chance(move_id: int, element_slot: int) -> int:
	var chances: Array = record("moves/learn_chances", move_id).get("chances", [])
	return chances[element_slot] if element_slot >= 0 and element_slot < chances.size() else -1


# --- Items (specs/items.md) ------------------------------------------------------------------

func item(id: int) -> Dictionary:
	return record("items/item_data", id)


## The effect values of an item's handler case, or {} (passive items have none).
func item_effect(item_id: int) -> Dictionary:
	return find("items/item_effects", "item", item_id)


## "boot" or "default_savegame".
func inventory_preset(inventory_name: String) -> Dictionary:
	return find("items/inventories", "inventory", inventory_name)


func sort_order(mode: int) -> Dictionary:
	return find("items/sort_orders", "mode", mode)


func recyclable_items() -> Array:
	return records("items/recyclable_items")


## Shop maps and shopkeeper Digimon (the stock is in the event scripts).
func shops() -> Dictionary:
	return record("items/shops", 0)


func card(id: int) -> Dictionary:
	return record("items/card_data", id)


# --- Systems (specs/systems.md) --------------------------------------------------------------

## Records of a systems table: system("fishing")[0], system("jukebox").
func system(table_name: String) -> Array:
	return records("systems/" + table_name)


## Number of battle commands: MAP[brain / 100] below brain 500, then the last row
## (battle_setup.c:124-128, std_main.c:4220-4225). arena = tournament battles (no Run).
func battle_commands(brain: int, arena := false) -> int:
	var rows := system("battle_commands")
	for row in rows:
		if brain < row["brain"][1]:
			return row["arena_commands" if arena else "commands"]
	return rows.back()["arena_commands" if arena else "commands"] if not rows.is_empty() else 0


## FLEE_CHANCES by Digimon type (1 data, 2 vaccine, 3 virus); -1 for another type.
func flee_chance(partner_type: int, enemy_type: int) -> int:
	for row in system("flee_chances"):
		if row.has("partner_type") and _matches(row["partner_type"], partner_type) and _matches(row["enemy_type"], enemy_type):
			return row["chance"]
	return -1


## Battle music track of an enemy Digimon; -1 if it has no entry.
func enemy_music(digimon_id: int) -> int:
	return find("systems/enemy_music", "digimon", digimon_id).get("track", -1)


func tournament(id: int) -> Dictionary:
	return record("systems/tournaments", id)


## Tournament ids of a day (DAY % 30), before isTournamentEnabled filters them.
func tournaments_on_day(day: int) -> Array:
	return record("systems/tournament_schedule", posmod(day, SCHEDULE_DAYS)).get("tournaments", [])


## Chance (%) that a participant of level_a beats one of level_b (levels 3-6); -1 otherwise.
func tournament_win_chance(level_a: int, level_b: int) -> int:
	for row in system("tournament_win_chances"):
		if row["level_a"] == level_a and row["level_b"] == level_b:
			return row["chance"]
	return -1


func map(id: int) -> Dictionary:
	return record("systems/maps", id)


## Map id of a map file name (MAYO04A), the folder name of the asset porter's maps; -1 if none.
func map_id(file: String) -> int:
	return find("systems/maps", "file", file).get("id", -1)


func toilet(id: int) -> Dictionary:
	return record("systems/toilets", id)


## Training spots of a gym map, or {}.
func training_spots(map_id_value: int) -> Dictionary:
	return find("systems/training_spots", "map", map_id_value)
