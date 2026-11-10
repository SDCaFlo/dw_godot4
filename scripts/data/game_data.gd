@tool
extends Node
## Content registry: the data porter output (the "dw1" pack) plus content packs merged over it
## (specs/content.md). Autoload "GameData".
##
## Every table is one JSON file of the porter (`digimon/digimon_data.json` = table
## "digimon/digimon_data"), loaded on first use and cached with the packs applied. Entity records
## (Digimon, techniques, items, maps, tournaments) have a content key ("dw1:agumon") and, in dw1,
## a numeric id (the original index): accessors take either. References are {"id", "name"};
## names are {"string_id", "text": {ja, en_us, en_eu}}. What each field means and how the
## original code used it is in data_porter/specs/<group>.md.
## Numbers inside records are floats, as Godot's JSON parser returns them (int() them where an
## int is needed); the accessors below that return a number return an int.
##
## Output folder: the DW_DATA_OUTPUT environment variable or the "dw/data/output_dir" project
## setting. Packs: folders in DW_DATA_PACKS (separated by ";") or the "dw/data/packs" setting,
## applied in that order after dw1 (see "Packs" below).
## Text language: the "dw/data/language" setting (ja, en_us, en_eu) or set_language(), among the
## languages the output has (languages()): all three from the decomp, en_us only from a US disc
## (data_porter/specs/from_disc.md §4).

signal language_changed(language: String)

const SETTING := "dw/data/output_dir"
const DEFAULT_DIR := "res://data_porter/output"
const PACKS_SETTING := "dw/data/packs"
const LANGUAGE_SETTING := "dw/data/language"
const LANGUAGES: PackedStringArray = ["ja", "en_us", "en_eu"]
const BASE_PACK := "dw1"
## TOURNAMENT_SCHEDULE covers 30 days (script_common.c:585).
const SCHEDULE_DAYS := 30
## Entity kind -> its main table (specs/content.md §2-3).
const ENTITIES := {
	"digimon": "digimon/digimon_data",
	"move": "moves/move_data",
	"item": "items/item_data",
	"map": "systems/maps",
	"tournament": "systems/tournaments",
	"card": "items/card_data",
}

var language := "en_us"
## The languages this output has (a font table each), found on the first languages() call.
var _languages := PackedStringArray()

var _root := ""
## Applied packs after dw1, in order: {"id", "dir", "manifest"}.
var _packs: Array[Dictionary] = []
var _tables := {}
## table -> {key: record} and {numeric id: record}, rebuilt when a table is loaded.
var _by_key := {}
var _by_id := {}
## table -> {"key" / "#id" / "@index": [pack ids that changed the record]}
var _changed := {}
## string id -> {language: text}, built on the first text() call.
var _text_ids := {}
## "table|block" -> {index: entry}
var _blocks := {}
## tournament id -> record from scripts/tournament_cups.json, loaded on first use.
var _tournament_cups := {}
var _tournament_cups_loaded := false


func _init() -> void:
	var env := OS.get_environment("DW_DATA_OUTPUT")
	_root = env if env != "" else ProjectSettings.globalize_path(ProjectSettings.get_setting(SETTING, DEFAULT_DIR))
	var packs_env := OS.get_environment("DW_DATA_PACKS")
	var dirs: PackedStringArray = packs_env.split(";", false) if packs_env != "" else ProjectSettings.get_setting(PACKS_SETTING, PackedStringArray())
	_load_packs(dirs)
	set_language(ProjectSettings.get_setting(LANGUAGE_SETTING, language))


# --- Files and tables ------------------------------------------------------------------------

func root() -> String:
	return _root


## True when the porter output is there (python -m dwdata convert all has run).
func available() -> bool:
	return FileAccess.file_exists(_root.path_join("catalog.json"))


## Whole table file (table, source, schema, records, used_by, godot) with the packs applied.
## {} if it can't be read (reported once).
func table(table_name: String) -> Dictionary:
	if _tables.has(table_name):
		return _tables[table_name]
	var file := _root.path_join(table_name + ".json")
	var json = _read_json(file)
	if not json is Dictionary or not json.get("records") is Array:
		push_error("GameData: cannot read table %s from %s (run: python -m dwdata convert all)" % [table_name, file])
		json = {}
	_tables[table_name] = json
	_changed[table_name] = {}
	if not json.is_empty():
		for pack in _packs:
			var pack_file: String = pack["dir"].path_join(table_name + ".json")
			if FileAccess.file_exists(pack_file):
				_apply_pack_table(table_name, json, pack["id"], _read_json(pack_file))
	_index(table_name)
	return json


func records(table_name: String) -> Array:
	return table(table_name).get("records", [])


## Record by content key ("dw1:agumon") or numeric id; tables without ids by array position.
## {} if there is none.
func record(table_name: String, ref: Variant) -> Dictionary:
	table(table_name)
	if ref is String:
		return _by_key.get(table_name, {}).get(ref, {})
	var ids: Dictionary = _by_id.get(table_name, {})
	if not ids.is_empty():
		return ids.get(int(ref), {})
	var rows := records(table_name)
	var index := int(ref)
	return rows[index] if index >= 0 and index < rows.size() else {}


## Numeric id of a record given by key or id; -1 if none (or a pack record without one).
func id_of(table_name: String, ref: Variant) -> int:
	var row := record(table_name, ref)
	return int(row["id"]) if row.get("id") != null else -1


## Content key of a record given by key or id; "" if none.
func key_of(table_name: String, ref: Variant) -> String:
	return record(table_name, ref).get("key", "")


## First record whose `field` equals `value`; a reference field ({"id", "name"}) matches on id.
func find(table_name: String, field: String, value: Variant) -> Dictionary:
	for row in records(table_name):
		if _matches(row.get(field), value):
			return row
	return {}


func find_all(table_name: String, field: String, value: Variant) -> Array:
	return records(table_name).filter(func(row): return _matches(row.get(field), value))


## Drops the cached tables (after changing packs or re-running the porter).
func reload() -> void:
	_tables.clear()
	_by_key.clear()
	_by_id.clear()
	_changed.clear()
	_text_ids.clear()
	_blocks.clear()
	_tournament_cups.clear()
	_tournament_cups_loaded = false


func _index(table_name: String) -> void:
	var keys := {}
	var ids := {}
	for row in records(table_name):
		if row.get("key") != null:
			keys[row["key"]] = row
		if row.get("id") != null:
			ids[int(row["id"])] = row
	_by_key[table_name] = keys
	_by_id[table_name] = ids


static func _matches(field_value: Variant, value: Variant) -> bool:
	if field_value is Dictionary and field_value.has("id"):
		field_value = field_value["id"]
	if typeof(field_value) in [TYPE_INT, TYPE_FLOAT] and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return field_value == value
	return typeof(field_value) == typeof(value) and field_value == value


static func _read_json(file: String) -> Variant:
	var text := FileAccess.get_file_as_string(file)
	# NUL padding kept in text "variants" ("BackOK\u0000"): Godot strings can't hold NUL, so it
	# is read as the two characters \0 (the YAML spelling) instead of U+FFFD.
	if text.contains("\\u0000"):
		text = text.replace("\\u0000", "\\\\0")
	return JSON.parse_string(text) if text != "" else null


# --- Packs (specs/content.md §1, §5) ---------------------------------------------------------
#
# A pack is a folder with pack.json ({"id", "name", "version", "depends": [ids]}) and table files
# at the porter's relative paths (items/item_data.json) holding {"records": [entries]}:
#   {"key": "mypack:x", ...}                    adds a record (its key in the pack's namespace)
#   {"key" | "id" | "index": ..., "patch": {}}  changes fields: dictionaries merge, the rest
#                                               (arrays included) is replaced
#   {"key" | "id" | "index": ..., "remove": true}
# "index" addresses records of tables without keys or ids (array position in dw1). Added
# records have no numeric id: they are reached by key. Pack-added entities list their components
# in "components" (see entity()).

## Ids of the applied packs, dw1 first.
func packs() -> PackedStringArray:
	var ids := PackedStringArray([BASE_PACK])
	for pack in _packs:
		ids.append(pack["id"])
	return ids


## Packs (after dw1) that changed a record, in order.
func changed_by(table_name: String, ref: Variant) -> PackedStringArray:
	var row := record(table_name, ref)
	if row.is_empty():
		return PackedStringArray()
	var changes: Dictionary = _changed.get(table_name, {})
	var id := "#%d" % int(row["id"]) if row.get("id") != null else ""
	return PackedStringArray(changes.get(row.get("key", ""), changes.get(id, [])))


func _load_packs(dirs: PackedStringArray) -> void:
	var known := PackedStringArray([BASE_PACK])
	for dir in dirs:
		var path := ProjectSettings.globalize_path(dir)
		var manifest = _read_json(path.path_join("pack.json"))
		if not manifest is Dictionary or not manifest.get("id") is String:
			push_error("GameData: %s has no pack.json with an id, skipped" % path)
			continue
		var id: String = manifest["id"]
		var missing: Array = manifest.get("depends", []).filter(func(d): return not d in known)
		if id in known or RegEx.create_from_string("^[a-z0-9_]+$").search(id) == null:
			push_error("GameData: pack %s: id must be new, lowercase a-z 0-9 _ (skipped)" % id)
		elif not missing.is_empty():
			push_error("GameData: pack %s depends on %s, not loaded before it (skipped)" % [id, missing])
		else:
			_packs.append({"id": id, "dir": path, "manifest": manifest})
			known.append(id)


func _apply_pack_table(table_name: String, json: Dictionary, pack: String, pack_json: Variant) -> void:
	if not pack_json is Dictionary or not pack_json.get("records") is Array:
		push_error("GameData: pack %s: %s.json has no records array" % [pack, table_name])
		return
	var rows: Array = json["records"]
	for entry in pack_json["records"]:
		if not entry is Dictionary:
			continue
		if entry.has("patch") or entry.get("remove", false):
			var at := _find_target(rows, entry)
			if at < 0:
				push_error("GameData: pack %s: %s has no record %s" % [pack, table_name, _address(entry)])
				continue
			_note_change(table_name, rows[at], at, pack)
			if entry.get("remove", false):
				rows.remove_at(at)
			else:
				_merge(rows[at], entry["patch"])
		else:
			var key: String = entry.get("key", "")
			var keyed: bool = not rows.is_empty() and rows[0].has("key")
			if keyed and not key.begins_with(pack + ":"):
				push_error("GameData: pack %s: a new %s record needs a key \"%s:<name>\" (got \"%s\")" % [pack, table_name, pack, key])
				continue
			if key != "" and _find_target(rows, {"key": key}) >= 0:
				push_error("GameData: pack %s: %s already has %s (use patch)" % [pack, table_name, key])
				continue
			var added: Dictionary = entry.duplicate(true)
			added.erase("id")  # numeric ids are dw1 aliases only
			rows.append(added)
			_note_change(table_name, added, rows.size() - 1, pack)


static func _find_target(rows: Array, entry: Dictionary) -> int:
	for i in rows.size():
		var row: Dictionary = rows[i]
		if entry.has("key") and row.get("key") == entry["key"]:
			return i
		if entry.has("id") and row.get("id") != null and int(row["id"]) == int(entry["id"]):
			return i
	if entry.has("index") and not entry.has("key") and not entry.has("id"):
		var index := int(entry["index"])
		return index if index >= 0 and index < rows.size() else -1
	return -1


static func _address(entry: Dictionary) -> String:
	for field in ["key", "id", "index"]:
		if entry.has(field):
			return "%s %s" % [field, entry[field]]
	return "(no key / id / index)"


func _note_change(table_name: String, row: Dictionary, index: int, pack: String) -> void:
	var address: String = row.get("key", "#%d" % int(row["id"]) if row.get("id") != null else "@%d" % index)
	var changes: Dictionary = _changed[table_name]
	if not changes.has(address):
		changes[address] = []
	changes[address].append(pack)


static func _merge(target: Dictionary, patch: Dictionary) -> void:
	for field in patch:
		if target.get(field) is Dictionary and patch[field] is Dictionary:
			_merge(target[field], patch[field])
		else:
			target[field] = patch[field].duplicate(true) if patch[field] is Dictionary or patch[field] is Array else patch[field]


# --- Entities (specs/content.md §3) ----------------------------------------------------------

## One entity with its components, e.g. entity("digimon", "dw1:agumon") ->
## {"kind", "key", "id", "digimon": record, "files", "sounds", "care", "evolution",
## "enemy_music"}. Cards are entities of their own that show a Digimon (cards_of()). Components a Digimon doesn't have are left out. dw1 components come from their
## tables by numeric id; a pack-added entity brings its own in its "components" dictionary.
func entity(kind: String, ref: Variant) -> Dictionary:
	if not ENTITIES.has(kind):
		push_error("GameData: unknown entity kind %s (one of %s)" % [kind, ENTITIES.keys()])
		return {}
	var main := record(ENTITIES[kind], ref)
	if main.is_empty():
		return {}
	var view := {"kind": kind, "key": main.get("key", ""), "id": int(main["id"]) if main.get("id") != null else -1}
	view[kind] = main
	if main.get("id") != null:
		var components: Dictionary = call("_components_" + kind, int(main["id"]), main)
		for name in components:
			if not components[name].is_empty():
				view[name] = components[name]
	view.merge(main.get("components", {}), true)
	return view


func _components_digimon(id: int, _main: Dictionary) -> Dictionary:
	var raise := record("digimon/raise_data", id)
	var care := {}
	if not raise.is_empty():
		care = {"raise": raise, "sleep": sleep_pattern(int(raise["sleep_cycle"]["id"])),
				"item_take_distance": item_take_distance(id)}
	var evolution := {}
	for part in [["requirements", evolution_requirements(id)], ["paths", evolution_paths(id)], ["gains", evolution_gains(id)]]:
		if not part[1].is_empty():
			evolution[part[0]] = part[1]
	var music := enemy_music(id)
	return {"files": digimon_file(id), "sounds": digimon_sounds(id), "care": care, "evolution": evolution,
			"enemy_music": {"track": music} if music >= 0 else {}}


func _components_move(id: int, _main: Dictionary) -> Dictionary:
	return {"learn": record("moves/learn_chances", id)}


func _components_item(id: int, _main: Dictionary) -> Dictionary:
	return {"effect": item_effect(id), "evolution_target": evolution_item_target(id)}


func _components_map(id: int, main: Dictionary) -> Dictionary:
	return {"toilet": toilet(int(main["toilet"])) if main.get("toilet") != null else {},
			"training_spots": training_spots(id)}


func _components_tournament(id: int, _main: Dictionary) -> Dictionary:
	return {"cup": tournament_cup(id)}


func _components_card(_id: int, _main: Dictionary) -> Dictionary:
	return {}


# --- Text (specs/text.md) --------------------------------------------------------------------

## The languages of this output, in LANGUAGES order: those with a font table. A US disc gives en_us
## only (data_porter/specs/from_disc.md §4); without any output, en_us.
func languages() -> PackedStringArray:
	if _languages.is_empty():
		for lang in LANGUAGES:
			if FileAccess.file_exists(_root.path_join("font/%s.json" % lang)):
				_languages.append(lang)
		if _languages.is_empty():
			_languages.append("en_us")
	return _languages


## Switches the text language. A language this output doesn't have keeps the current one (or, if that
## one is missing too, picks en_us or the first there is).
func set_language(value: String) -> void:
	if not value in LANGUAGES:
		push_error("GameData: unknown language %s (one of %s)" % [value, LANGUAGES])
		return
	var have := languages()
	if not value in have:
		push_warning("GameData: no %s text in this output (it has %s)" % [value, have])
		if language in have:
			return
		value = "en_us" if "en_us" in have else have[0]
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
## Pack records can give their names inline the same way: {"text": {"en_us": "…"}}.
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
# Accessors take a numeric id or a content key ("dw1:agumon").

func digimon(ref: Variant) -> Dictionary:
	return record("digimon/digimon_data", ref)


## Model / texture files (CHDAT/MMD0/AGUM.MMD), the names of the asset porter output.
func digimon_file(ref: Variant) -> Dictionary:
	return record("digimon/file_names", _digimon_id(ref))


func digimon_sounds(ref: Variant) -> Dictionary:
	return record("digimon/sound_ids", _digimon_id(ref))


## Partner care data (66 partner ids).
func raise_data(ref: Variant) -> Dictionary:
	return record("digimon/raise_data", _digimon_id(ref))


func sleep_pattern(id: int) -> Dictionary:
	return record("digimon/sleep_patterns", id)


## ITEM_TAKE_DISTANCE[id - 1]; -1 if the Digimon has none.
func item_take_distance(digimon_ref: Variant) -> int:
	return find("digimon/item_take_distance", "digimon", _digimon_id(digimon_ref)).get("distance", -1)


## TRN_TRAINING_ANIM_IDS[type]: {strike_anim, hit_frame} of the Offense stations, or {}.
func training_animation(digimon_ref: Variant) -> Dictionary:
	return find("digimon/training_animations", "digimon", _digimon_id(digimon_ref))


## CONDITION_FX_OFFSETS[getOriginalType(type)]: {offset {x, y, z}, bone}, or {} (an original type
## of -1, or none in the table).
func condition_fx_offset(digimon_ref: Variant) -> Dictionary:
	var original := int(digimon(digimon_ref).get("original_type", -1))
	return record("digimon/condition_fx_offsets", original) if original >= 0 else {}


## BTL_AURA_PROJECTILE_TYPES[getOriginalType(type)]: {u, …}, or {}.
func aura_projectile_type(digimon_ref: Variant) -> Dictionary:
	var original := int(digimon(digimon_ref).get("original_type", -1))
	return record("digimon/aura_projectile_types", original) if original >= 0 else {}


func _digimon_id(ref: Variant) -> int:
	return id_of("digimon/digimon_data", ref) if ref is String else int(ref)


# --- Evolution (specs/evolution.md) ----------------------------------------------------------

func evolution_requirements(ref: Variant) -> Dictionary:
	return record("evolution/requirements", _digimon_id(ref))


## EVOLUTION_PATHS has no row for id 0: looked up by id.
func evolution_paths(ref: Variant) -> Dictionary:
	return record("evolution/paths", _digimon_id(ref))


func evolution_gains(ref: Variant) -> Dictionary:
	return record("evolution/stat_gains", _digimon_id(ref))


func evolution_item_target(item_ref: Variant) -> Dictionary:
	return find("evolution/item_targets", "item", _item_id(item_ref))


## The evolution rules of one kind (`hours`, `fresh_target`, `fallback`, `virus`, `scaled_target`,
## `special`, `technique_block`), in table order.
func evolution_rules(rule: String) -> Array:
	return find_all("evolution/rules", "rule", rule)


# --- Moves (specs/moves.md) ------------------------------------------------------------------

func move(ref: Variant) -> Dictionary:
	return record("moves/move_data", ref)


## TYPE_FACTORS[attacker][defender], 10 = x1 (BTL_calculateDamage); -1 for an unknown element.
func type_factor(attacker_element: int, defender_element: int) -> int:
	var against: Array = record("moves/type_factors", attacker_element).get("against", [])
	if defender_element < 0 or defender_element >= against.size():
		return -1
	return against[defender_element]["factor"]


## MOVE_LEARN_CHANCES[move][slot], slot = index of the matching element among the partner's 3;
## -1 for a technique that can't be learned this way.
func learn_chance(move_ref: Variant, element_slot: int) -> int:
	var move_id := id_of("moves/move_data", move_ref) if move_ref is String else int(move_ref)
	var chances: Array = record("moves/learn_chances", move_id).get("chances", [])
	return chances[element_slot] if element_slot >= 0 and element_slot < chances.size() else -1


## TRN_D_8008F14C: an element's 8 techniques in the order the Brains training teaches them
## ({element, moves [{rank, move}]}), or {}.
func training_learning(element: int) -> Dictionary:
	return find("moves/training_learning", "element", element)


## TRN_D_8008F184[rank][slot] (%); -1 outside the table.
func training_learn_weight(rank: int, element_slot: int) -> int:
	var weights: Array = table("moves/training_learning").get("weights", [])
	if rank < 0 or rank >= weights.size() or element_slot < 0 or element_slot >= weights[rank].size():
		return -1
	return int(weights[rank][element_slot])


# --- Items (specs/items.md) ------------------------------------------------------------------

func item(ref: Variant) -> Dictionary:
	return record("items/item_data", ref)


## The effect values of an item's handler case, or {} (passive items have none).
func item_effect(item_ref: Variant) -> Dictionary:
	return find("items/item_effects", "item", _item_id(item_ref))


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


## A collectible card (its own content kind: rarity, price, merit, the Digimon it shows).
func card(ref: Variant) -> Dictionary:
	return record("items/card_data", ref)


## Cards showing a Digimon ([] for most: not every Digimon has a card).
func cards_of(digimon_ref: Variant) -> Array:
	return find_all("items/card_data", "digimon", _digimon_id(digimon_ref))


func _item_id(ref: Variant) -> int:
	return id_of("items/item_data", ref) if ref is String else int(ref)


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
func enemy_music(digimon_ref: Variant) -> int:
	return find("systems/enemy_music", "digimon", _digimon_id(digimon_ref)).get("track", -1)


func tournament(ref: Variant) -> Dictionary:
	return record("systems/tournaments", ref)


## Tournament cup data (specs/tournament_entry.md §5.1c): requirement, eligible and over-levelled
## Digimon lists, opponent pool and info textbox from scripts/tournament_cups.json.
## ref may be a numeric tournament id or a content key ("dw1:grade_d"); {} when missing.
func tournament_cup(ref: Variant) -> Dictionary:
	var id := id_of("systems/tournaments", ref) if ref is String else int(ref)
	if id < 0:
		return {}
	if not _tournament_cups_loaded:
		_tournament_cups.clear()
		var json: Variant = Content.load_json("scripts/tournament_cups.json")
		if json is Dictionary and json.get("records") is Array:
			for record in json["records"]:
				if record is Dictionary and record.has("id"):
					_tournament_cups[int(record["id"])] = record
		_tournament_cups_loaded = true
	return _tournament_cups.get(id, {})


## Tournament ids of a day (DAY % 30), before isTournamentEnabled filters them.
func tournaments_on_day(day: int) -> Array:
	return record("systems/tournament_schedule", posmod(day, SCHEDULE_DAYS)).get("tournaments", [])


## Chance (%) that a participant of level_a beats one of level_b (levels 3-6); -1 otherwise.
func tournament_win_chance(level_a: int, level_b: int) -> int:
	for row in system("tournament_win_chances"):
		if row["level_a"] == level_a and row["level_b"] == level_b:
			return row["chance"]
	return -1


func map(ref: Variant) -> Dictionary:
	return record("systems/maps", ref)


## Map id of a map file name (MAYO04A), the folder name of the asset porter's maps; -1 if none.
func map_id(file: String) -> int:
	return find("systems/maps", "file", file).get("id", -1)


func toilet(id: int) -> Dictionary:
	return record("systems/toilets", id)


## Training spots of a gym map, or {}.
func training_spots(map_ref: Variant) -> Dictionary:
	var id := id_of("systems/maps", map_ref) if map_ref is String else int(map_ref)
	return find("systems/training_spots", "map", id)


## The training slot machine's table (TRN_D_8008F1AC reels, TRN_D_8008F2CC assist draw, the symbols
## and the payouts), or {}.
func slot_machine() -> Dictionary:
	var rows := system("slot_machine")
	return rows[0] if not rows.is_empty() else {}


## The fishing table (specs/fishing.md §4: kinds, bite_chance_by_bait, snagged_items, maps, sprites),
## or {}.
func fishing() -> Dictionary:
	var rows := system("fishing")
	return rows[0] if not rows.is_empty() else {}


## The fishing data of a map (checkFishingMap, main/fish.c:126: spots, water, Seadramon's path and
## hours, scales), by key or id; {} for a map without fishing.
func fishing_map(map_ref: Variant) -> Dictionary:
	var key := key_of("systems/maps", map_ref) if not map_ref is String else str(map_ref)
	for m in fishing().get("maps", []):
		if str(m["map"]["key"]) == key:
			return m
	return {}


## FISH_BITE_CHANCE for a bait item and a fish kind (FISH_findFishToBite, fish.c:3080-3089): the %
## per check; 0 for a bait outside the table.
func fishing_bite_chance(bait: Variant, kind: int) -> int:
	var id := id_of("items/item_data", bait) if bait is String else int(bait)
	for row in fishing().get("bite_chance_by_bait", []):
		if int(row["bait"]["id"]) == id:
			var chances: Array = row["chances"]
			return int(chances[kind]) if kind >= 0 and kind < chances.size() else 0
	return 0


## The curling table (specs/curling.md §4: map, pstats, stone_types, zones, hints, sprites), or {}.
func curling() -> Dictionary:
	var rows := system("curling")
	return rows[0] if not rows.is_empty() else {}


## The curling data of a map (checkCurlingMap, src/main/kar.c:10: map 136 only), by key or id;
## {} for a map without curling.
func curling_map(map_ref: Variant) -> Dictionary:
	var key := key_of("systems/maps", map_ref) if not map_ref is String else str(map_ref)
	var c := curling()
	return c if not c.is_empty() and str(c["map"]["key"]) == key else {}


## enforceStatsLimits' cap of a script stat (STATS_LIMIT_ARRAY; stat 22 reads past it, see the
## table); -1 for an unknown stat.
func script_stat_limit(stat: int) -> int:
	return int(record("systems/script_stat_limits", stat).get("limit", -1))


# --- Font (data_porter/specs/font.md) --------------------------------------------------------

## The glyphs of a language's font (font.c: code, rows, width), in table order; the last is the
## sentinel drawGlyph falls back to. lang "" = the current language.
func font(lang := "") -> Array:
	return records("font/" + (lang if lang != "" else language))


## FONT_CLUT: the 16 colours of the text area (index 0 transparent).
func font_clut() -> Array:
	return records("font/clut")


## TEXT_COLORS: renderString's tint per colour (0x80 = x1.0).
func text_colors() -> Array:
	return records("font/text_colors")


## ASCII 0x20-0x7E -> full-width Shift-JIS (convertAsciiToJis, drawString's overrides).
func font_ascii() -> Array:
	return records("font/ascii")
