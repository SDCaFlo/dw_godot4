extends Node
## The game state: what the original keeps in a savegame (specs/game_state.md), as plain
## dictionaries and arrays. Autoload "GameState" (after GameData).
##
## Sections (`state` below): boot_mode, clock, tamer, partner, world, money, merit, counters,
## inventory, script. Content references are keys ("dw1:agumon"); numbers keep the original
## units (frames, PSX world units, collision tiles). Systems change the state directly or through
## the helpers, each named after the C function it reproduces, and emit changed(section) for UI.
##
## Savegames are JSON files in the save folder (default user://saves, setting "dw/state/save_dir"):
## readable and editable on purpose, no checksum (specs/game_state.md §3.3).

signal changed(section: String)

const SAVE_DIR_SETTING := "dw/state/save_dir"
const DEFAULT_SAVE_DIR := "user://saves"
const SAVE_FORMAT := 1

## MAIN_STATE (main.c:3438).
const BOOT_NEW_GAME := 0
const BOOT_CONTINUE := 1
const BOOT_GAME_CLEARED := 2
const BOOT_QUIT := 3

## PartnerPara.condition bits (params.h:10-16).
const CONDITION_SLEEPY := 1 << 0
const CONDITION_TIRED := 1 << 1
const CONDITION_HUNGRY := 1 << 2
const CONDITION_POOPY := 1 << 3
const CONDITION_UNHAPPY := 1 << 4
const CONDITION_INJURED := 1 << 5
const CONDITION_SICK := 1 << 6

## Sizes of the original arrays.
const INVENTORY_SLOTS := 30
const TRIGGERS := 800
## The "raised" marks of the evolution chart: trigger 0x200 + Digimon id, ids < 0x3F.
const TRIGGER_RAISED := 0x200
const RAISED_IDS := 0x3F
const SCRIPT_VALUES := 256
## The save copies the first 0x17C bytes of ScriptState: script values 0-34 (main_menu.c:5120).
const SAVED_SCRIPT_VALUES := 35
const POOP_SLOTS := 100
const NPC_SLOTS := 8
const WAYPOINTS := 30
const RECYCLE_SLOTS := 78
const CARD_SHOP_SLOTS := 6
## A card count is a nibble, an item keeper / recycle count at most 99 (script_menu.c).
const MAX_CARD_COUNT := 15
const MAX_STOCK := 99
## One game minute is 20 frames (clock.c:207).
const FRAMES_PER_MINUTE := 20
const FRAMES_PER_HOUR := 1200

## PartnerPara fields in C order (params.h:34-100), snake_case.
const CARE_FIELDS := [
	"condition", "sleepy_hour", "sleepy_minute", "wakeup_hour", "wakeup_minute",
	"hours_awake_default", "hours_asleep_default", "time_awake_today", "sickness_counter",
	"missed_sleep_hours", "tiredness_sleep_timer", "poop_level", "unused1", "unused2", "virus_bar",
	"pooping_timer", "tiredness", "sub_tiredness", "tiredness_hunger_timer", "discipline", "happiness",
	"unused3", "unused4", "times_being_sick", "sickness_tries", "area_effect_timer", "sickness_timer",
	"injury_timer", "next_hunger_hour", "energy_level", "food_level", "starvation_timer", "weight",
	"refused_fav_food", "empty_stomach_timer", "remaining_lifetime", "age", "train_boost_flag",
	"train_boost_value", "train_boost_timer", "care_mistakes", "battles", "evo_timer", "unused5",
	"unused6", "unused7", "fish_caught", "unused8", "unused9", "unused10", "upgrade_hp_counter",
	"upgrade_mp_counter", "upgrade_off_counter", "bugged_upgrade_brains_counter",
	"upgrade_defense_counter", "upgrade_speed_counter", "upgrade_brain_counter", "unused11",
	"suka_backup_hp", "suka_backup_mp", "suka_backup_off", "suka_backup_def", "suka_backup_speed",
	"suka_backup_brain", "unused12",
]

## Content references in the state, checked on load: [path, entity kind]. "*" = every element /
## value, "#" = every key of a dictionary.
const KEY_FIELDS := [
	["partner.digimon", "digimon"], ["partner.learned_moves.*", "move"],
	["partner.stats.base.moves.*", "move"], ["world.screen", "map"], ["world.previous_screen", "map"],
	["world.poop.*.map", "map"], ["inventory.slots.*.item", "item"], ["script.cards.#", "card"],
	["script.item_keeper.#", "item"], ["script.card_shop.*", "card"],
]

## The content registry (the GameData autoload); set explicitly where there is no scene tree.
var data: Node
var save_dir := ""
var state := {}


func _ready() -> void:
	if data == null:
		data = get_node_or_null("/root/GameData")
	if save_dir == "":
		save_dir = ProjectSettings.get_setting(SAVE_DIR_SETTING, DEFAULT_SAVE_DIR)
	if state.is_empty():
		new_game()


# --- New game ----------------------------------------------------------------------------------

## initializeDefaultSavegame (main_menu.c:4911) followed by the mode-0 boot (main.c:3439-3454):
## the partner is Agumon, or Gabumon when script value 0xFE is set by the intro (pass it here).
## Partner stats are not part of the default record: the partner initialisation sets them.
func new_game(partner := "dw1:agumon") -> void:
	var care := {}
	for field in CARE_FIELDS:
		care[field] = 0
	care["remaining_lifetime"] = 0x120
	care["age"] = 3
	var slots := []
	slots.resize(INVENTORY_SLOTS)
	for slot in data.inventory_preset("default_savegame").get("slots", []):
		slots[int(slot["slot"])] = {"item": data.key_of("items/item_data", int(slot["item"]["id"])), "amount": int(slot["amount"])}
	var values := []
	values.resize(SCRIPT_VALUES)
	values.fill(0)
	var card_shop := []
	for i in CARD_SHOP_SLOTS:
		card_shop.append(data.key_of("items/card_data", 0x3A + i))
	var recycle := []
	recycle.resize(RECYCLE_SLOTS)
	recycle.fill(0)
	var poop := []
	poop.resize(POOP_SLOTS)
	var npc := []
	npc.resize(NPC_SLOTS)
	npc.fill(0)
	var waypoints := []
	waypoints.resize(WAYPOINTS)
	waypoints.fill(0)
	state = {
		"boot_mode": BOOT_NEW_GAME,
		"clock": {"year": 0, "day": 0, "hour": 8, "minute": 0, "frame": 0x2580, "last_handled_frame": 0x2580,
				"playtime": {"frames": 0, "minutes": 0, "hours": 0}},
		"tamer": {"name": data.text("MAIN_D_801346C4"), "level": 0, "raised_count": 1, "position": [0, 0, 0],
				"waypoints": {"x": waypoints.duplicate(), "y": waypoints.duplicate(), "previous_tile": [0, 0],
						"start_tile": [0, 0], "current": 0, "count": 0, "active": 0}},
		"partner": {"digimon": partner, "name": data.text("MAIN_D_8013468C"), "lives": 3, "position": [0, 0, 0],
				"learned_moves": [], "unk1": 0, "unk2": 0, "care": care,
				"stats": {"base": {"offense": 0, "defense": 0, "speed": 0, "brains": 0, "max_hp": 0, "max_mp": 0,
						"moves": [null, null, null, null], "moves_prio": [0, 0, 0, 0]},
						"current": {"hp": 0, "mp": 0, "unk1": 0, "efe_sub_effect": 0, "is_hit": 0, "vab_id": 0,
								"charge_mode": 0, "unk_0x57": 0}}},
		"world": {"screen": data.key_of("systems/maps", 0xCC), "previous_screen": data.key_of("systems/maps", 0),
				"exit": 9, "previous_exit": 0, "npc_on_map": npc, "poop": poop},
		"money": 50000,
		"merit": 0,
		"counters": {"battles_started": 0, "battles_fled": 0, "tournaments_won": 0, "tournament_wins": 0,
				"tournaments_lost": 0},
		"inventory": {"size": INVENTORY_SLOTS, "slots": slots},
		"script": {"triggers": [], "values": values, "cards": {}, "item_keeper": {}, "recycle_stock": recycle,
				"card_shop": card_shop},
	}
	changed.emit("all")


# --- Script state (script_interp.c) ------------------------------------------------------------

## isTriggerSet (script_interp.c:2763).
func is_trigger_set(trigger: int) -> bool:
	return trigger in state["script"]["triggers"]


## setTrigger (script_interp.c:2430).
func set_trigger(trigger: int) -> void:
	if trigger < 0 or trigger >= TRIGGERS:
		push_error("GameState: trigger %d out of range 0-%d" % [trigger, TRIGGERS - 1])
		return
	var triggers: Array = state["script"]["triggers"]
	if not trigger in triggers:
		triggers.append(trigger)
		triggers.sort()
		changed.emit("script")


## unsetTrigger (script_interp.c:2441).
func clear_trigger(trigger: int) -> void:
	var triggers: Array = state["script"]["triggers"]
	if trigger in triggers:
		triggers.erase(trigger)
		changed.emit("script")


## The boot's partner (main.c:3445-3452): initializePartner(answer == 0 ? Agumon : Gabumon), read
## from systems/new_game, then setDigimonRaised. The care values, the techniques and the lives
## are the CareHost's (Care.initialize_partner, run for a new game).
func start_new_game_partner(answer: int) -> void:
	var records: Array = data.system("new_game")
	for entry in records[0].get("partners", []) if not records.is_empty() else []:
		if int(entry["answer"]) == answer:
			state["partner"]["digimon"] = data.key_of("digimon/digimon_data", int(entry["digimon"]["id"]))
	set_raised(state["partner"]["digimon"])
	changed.emit("partner")


## setDigimonRaised (script_common.c:3011): trigger 0x200 + id, for ids below 0x3F.
func set_raised(digimon: Variant) -> void:
	var id := _digimon_id(digimon)
	if id >= 0 and id < RAISED_IDS:
		set_trigger(TRIGGER_RAISED + id)


## hasDigimonRaised (script_common.c:3019).
func is_raised(digimon: Variant) -> bool:
	return is_trigger_set(TRIGGER_RAISED + _digimon_id(digimon))


## readPStat (script_interp.c:2722).
func script_value(index: int) -> int:
	return state["script"]["values"][index]


## writePStat (script_interp.c:2775): a byte.
func set_script_value(index: int, value: int) -> void:
	state["script"]["values"][index] = value & 0xFF
	changed.emit("script")


## getCardAmount (script_interp.c:2483).
func card_count(card: Variant) -> int:
	return state["script"]["cards"].get(_key("items/card_data", card), 0)


## setCardAmount (script_interp.c:2497): a nibble, 0-15.
func set_card_count(card: Variant, count: int) -> void:
	var key := _key("items/card_data", card)
	if count & MAX_CARD_COUNT == 0:
		state["script"]["cards"].erase(key)
	else:
		state["script"]["cards"][key] = count & MAX_CARD_COUNT
	changed.emit("script")


# --- Partner -----------------------------------------------------------------------------------

## hasMove (utils2.c:311).
func has_move(move: Variant) -> bool:
	return _key("moves/move_data", move) in state["partner"]["learned_moves"]


## learnMove (utils2.c:320): also learns the techniques sharing its flag (`learned_with`, the
## original's literal 0x2C / 0x30 pair).
func learn_move(move: Variant) -> void:
	var learned: Array = state["partner"]["learned_moves"]
	for key in _with_shared(move):
		if not key in learned:
			learned.append(key)
	learned.sort()
	changed.emit("partner")


## unlearnMove (utils2.c).
func unlearn_move(move: Variant) -> void:
	for key in _with_shared(move):
		state["partner"]["learned_moves"].erase(key)
	changed.emit("partner")


## getItemCount(id) != 0 for a passive item (sleepRegen's Rest Pillow, …): the inventory holds an
## item whose `passive` property is `effect` (items/item_data, specs/care.md §4).
func has_passive_item(effect: String) -> bool:
	for slot in state["inventory"]["slots"]:
		if slot != null and int(slot.get("amount", 0)) > 0 and data.item(slot["item"]).get("passive") == effect:
			return true
	return false


# --- Inventory (item.c) --------------------------------------------------------------------------

## getItemCount (item.c:2549): the amount in the first slot holding the item (within the size).
func item_count(item: Variant) -> int:
	var key := _key("items/item_data", item)
	var slots: Array = state["inventory"]["slots"]
	for i in mini(int(state["inventory"]["size"]), slots.size()):
		if slots[i] != null and slots[i]["item"] == key:
			return int(slots[i]["amount"])
	return 0


## giveItem (item.c:2562): adds to the item's slot (at most 99; a full stack of 99 fails and no other
## slot is tried), else fills the first empty slot. False when nothing was added.
func give_item(item: Variant, amount: int) -> bool:
	var key := _key("items/item_data", item)
	var slots: Array = state["inventory"]["slots"]
	var size := mini(int(state["inventory"]["size"]), slots.size())
	for i in size:
		if slots[i] != null and slots[i]["item"] == key:
			if int(slots[i]["amount"]) == 99:
				return false
			# A uint8 count: the sum wraps at 256 before the cap.
			var count := (int(slots[i]["amount"]) + amount) & 0xFF
			slots[i]["amount"] = 99 if count >= 100 else count
			changed.emit("inventory")
			return true
	for i in size:
		if slots[i] == null:
			slots[i] = {"item": key, "amount": amount & 0xFF}
			changed.emit("inventory")
			return true
	return false


## removeItem (item.c:2616): takes `amount` from every slot holding the item; a slot that runs
## out is emptied.
func remove_item(item: Variant, amount: int) -> void:
	var key := _key("items/item_data", item)
	var slots: Array = state["inventory"]["slots"]
	for i in mini(int(state["inventory"]["size"]), slots.size()):
		if slots[i] != null and slots[i]["item"] == key:
			if amount < int(slots[i]["amount"]):
				slots[i]["amount"] = int(slots[i]["amount"]) - amount
			else:
				slots[i] = null
	changed.emit("inventory")


## setInventorySize (item.c:2388).
func set_inventory_size(size: int) -> void:
	state["inventory"]["size"] = size
	changed.emit("inventory")


func has_condition(flag: int) -> bool:
	return state["partner"]["care"]["condition"] & flag != 0


func set_condition(flag: int, on: bool) -> void:
	var care: Dictionary = state["partner"]["care"]
	care["condition"] = care["condition"] | flag if on else care["condition"] & ~flag
	changed.emit("partner")


func _with_shared(move: Variant) -> PackedStringArray:
	var record: Dictionary = data.move(move)
	var keys := PackedStringArray([record.get("key", str(move))])
	var shared = record.get("learned_with")
	for other in (shared if shared is Array else [shared] if shared != null else []):
		keys.append(data.key_of("moves/move_data", int(other)))
	return keys


func _digimon_id(ref: Variant) -> int:
	return data.id_of("digimon/digimon_data", ref) if ref is String else int(ref)


func _key(table: String, ref: Variant) -> String:
	return ref if ref is String else data.key_of(table, ref)


# --- Savegames ---------------------------------------------------------------------------------

func save_path(slot: int) -> String:
	return save_dir.path_join("slot_%02d.json" % slot)


## recalculatePPandArena (main.c:3902): called before every save. Recalculates Prosperity Points
## (script value 1) from the recruited Digimon, and resets arena triggers when script value 3 >= 23.
func recalculate_pp_and_arena() -> void:
	var pp := 0
	for i in range(3, 0x3B):
		var key: String = data.key_of("digimon/digimon_data", i)
		var record: Dictionary = data.digimon(key)
		var level: int = int(record.get("level", {}).get("id", 0)) if record.get("level") is Dictionary else int(record.get("level", 0))
		if level >= 3 and is_trigger_set(0xC8 + i):
			if i == 0x0B or i == 0x27 or i == 0x35:
				pp += 1
			else:
				pp += level - 2
	set_script_value(1, pp)
	if script_value(3) >= 0x17:
		clear_trigger(0x25)
		clear_trigger(0x26)
		clear_trigger(0x27)


## Prepares the state for saving (writeSavegame, main_menu.c:5071): recalculates PP, masks
## script value 0 during the write, and writes the slot. Returns OK or the file error.
func save_game(slot: int) -> Error:
	recalculate_pp_and_arena()
	var restore_pstat0 := false
	if script_value(0) == 3:
		set_script_value(0, 0)
		restore_pstat0 = true
	DirAccess.make_dir_recursive_absolute(save_dir)
	var saved: Dictionary = state.duplicate(true)
	saved["script"]["values"] = saved["script"]["values"].slice(0, SAVED_SCRIPT_VALUES)
	var file := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("GameState: cannot write %s (%s)" % [save_path(slot), error_string(FileAccess.get_open_error())])
		if restore_pstat0:
			set_script_value(0, 3)
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"format": SAVE_FORMAT, "game": "dw1", "packs": Array(data.packs()),
			"preview": preview(), "state": saved}, "\t"))
	file.close()
	if restore_pstat0:
		set_script_value(0, 3)
	return OK


## Reads a slot into the state. Returns {"ok", "error", "missing_keys"}: missing_keys lists content
## the loaded packs don't have (e.g. the save was made with another pack); the state is loaded
## anyway, so the caller decides. Fields absent from the file keep their new-game value.
func load_game(slot: int) -> Dictionary:
	var result := {"ok": false, "error": "", "missing_keys": []}
	var text := FileAccess.get_file_as_string(save_path(slot))
	if text == "":
		result["error"] = "no save in slot %d (%s)" % [slot, save_path(slot)]
		return result
	var json = JSON.parse_string(text)
	if not json is Dictionary or not json.get("state") is Dictionary:
		result["error"] = "%s is not a savegame (broken or edited file)" % save_path(slot)
		return result
	if json.get("game") != "dw1" or int(json.get("format", 0)) > SAVE_FORMAT:
		result["error"] = "%s is format %s of game %s, this build reads format %d of dw1" % [
				save_path(slot), json.get("format"), json.get("game"), SAVE_FORMAT]
		return result
	new_game()
	_merge(state, _ints(json["state"]))
	var values: Array = state["script"]["values"]
	values.resize(SCRIPT_VALUES)
	for i in range(SAVED_SCRIPT_VALUES, SCRIPT_VALUES):
		values[i] = 0
	result["missing_keys"] = missing_keys()
	for key in result["missing_keys"]:
		push_warning("GameState: slot %d refers to %s, which no loaded pack has" % [slot, key])
	result["ok"] = true
	changed.emit("all")
	return result


## Deletes a save slot (slot_XX.json). Returns OK or error.
func delete_save(slot: int) -> Error:
	var path := save_path(slot)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var err := DirAccess.remove_absolute(path)
	if err == OK:
		changed.emit("saves")
	return err


## The saved slots with their preview: [{"slot", "preview"}], sorted by slot.
func list_saves() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(save_dir):
		return out
	for file in DirAccess.get_files_at(save_dir):
		if file.begins_with("slot_") and file.ends_with(".json") and file.substr(5, 2).is_valid_int():
			var json = JSON.parse_string(FileAccess.get_file_as_string(save_dir.path_join(file)))
			out.append({"slot": file.substr(5, 2).to_int(), "preview": json.get("preview", {}) if json is Dictionary else {}})
	out.sort_custom(func(a, b): return a["slot"] < b["slot"])
	return out


## What the load menu shows (SaveSlotPreview, main_menu.c:79).
func preview() -> Dictionary:
	var playtime: Dictionary = state["clock"]["playtime"]
	return {"player": state["tamer"]["name"], "partner": state["partner"]["name"],
			"digimon": state["partner"]["digimon"],
			"area": data.localize(data.map(state["world"]["screen"]).get("name")).strip_edges(),
			"playtime": "%d:%02d" % [playtime["hours"], playtime["minutes"]]}


## Content keys in the state that no loaded pack defines.
func missing_keys() -> Array:
	var missing := []
	for field in KEY_FIELDS:
		for key in _values_at(state, field[0].split(".")):
			if key is String and data.record(data.ENTITIES[field[1]], key).is_empty() and not key in missing:
				missing.append(key)
	return missing


static func _values_at(value: Variant, path: PackedStringArray) -> Array:
	if path.is_empty():
		return [value]
	var head := path[0]
	var rest := path.slice(1)
	var out := []
	if head == "*" and (value is Array or value is Dictionary):
		for v in (value if value is Array else value.values()):
			out.append_array(_values_at(v, rest))
	elif head == "#" and value is Dictionary:
		out.append_array(value.keys())
	elif value is Dictionary and value.has(head):
		out.append_array(_values_at(value[head], rest))
	return out


## Loaded values over the new-game state: dictionaries merge (absent fields keep their default),
## everything else is replaced.
static func _merge(target: Dictionary, loaded: Dictionary) -> void:
	for k in loaded:
		if target.get(k) is Dictionary and loaded[k] is Dictionary and not k in ["cards", "item_keeper"]:
			_merge(target[k], loaded[k])
		else:
			target[k] = loaded[k]


## JSON numbers come back as floats; the state holds integers only.
static func _ints(value: Variant) -> Variant:
	if value is float:
		return int(value)
	if value is Array:
		return value.map(func(v): return _ints(v))
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _ints(value[k])
		return out
	return value
