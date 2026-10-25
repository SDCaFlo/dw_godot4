class_name ItemUse
extends RefCounted
## Using an item (specs/inventory.md §2.9-2.11, §4): where it can be used, whether the partner takes
## it, what it does, the hunger rule. The C's item rules, one function each; everything it knows
## about an item comes from its properties (item_data `usable`, `droppable`, `feeding`, `handler`;
## item_effects; healing_values), never its id. The inventory asks it, the feeding scene calls it.
##
## Effects dispatch on the item's `handler` (ITEM_FUNCTIONS[type](type)): a pack's new item can
## use an existing handler with its own values. Field branches only (GAME_STATE 0): the battle step
## adds its own inside the same handlers.

const FIELD := "field"
const BATTLE := "battle"
## The caps of addWithLimit on the permanent stats (item.c:2730-2737).
const MAX_HP_MP := 9999
const MAX_STAT := 999
## handleChips' DV chips: lifetime -24 and addTamerLevel(10, -1).
const DV_LIFETIME := -24
## Item effect handlers ported here (ITEM_FUNCTIONS names, item_data `handler`).
const HANDLERS := {
	"handleHPHealingItem": "_handle_hp_healing", "handleMPHealingItem": "_handle_mp_healing",
	"handleDoubleFloppy": "_handle_double_floppy", "handleStatusItems": "_handle_status_items",
	"handleRestore": "_handle_restore", "handleChips": "_handle_chips", "handleFood": "_handle_food",
	"handleEvoItems": "_handle_evo_items",
}
## The partner's food animation when it liked it (partnerHandleFoodFeed).
const ANIM_HAPPY := 0x0B

var game_state: Node
var data: Node
## The care rules (the partner's values, ITEM_SCOLD_FLAG, the food timer, the sick message).
var care: Care
var clock: Clock
## The script interpreter and state (Auto Pilot runs a script section).
var interpreter: ScriptInterpreter
var script_ctx: ScriptContext


# --- where (getItemOptionColor, selectOptionMenu) ----------------------------------------------

## itemColor: field 0 and both 2 in the field, battle 1 and both 2 in battle.
func can_use(item: Variant, context := FIELD) -> bool:
	var usable: String = _item(item).get("usable", {}).get("name", "none")
	return usable == "both" or usable == context


func can_drop(item: Variant) -> bool:
	return bool(_item(item).get("droppable", false))


# --- partnerWillRefuseItem (partner_impl.c:1431) ------------------------------------------------

## True when the partner refuses `item` (specs/inventory.md §2.9).
func will_refuse(item: Variant) -> bool:
	_put("refused_fav_food", 0)
	var chance := Rng.random_limit(10)
	var feeding: String = _item(item).get("feeding", "refused")
	if feeding == "refused":
		return true
	if feeding == "evolution" and _evolution_refused(item):
		return true
	if care.item_scold_flag == 2:
		care.item_scold_flag = 0
		return false
	if feeding == "obedience":
		var roll := Rng.random_limit(100)
		if roll < 110 - (_val("discipline") + (Rng.random_limit(10) + 10)):
			care.item_scold_flag = 1
			return true
	if not _hungry() and _is_favourite(item) and chance < 2:
		_put("refused_fav_food", 2)
	if _val("refused_fav_food") != 0:
		# Dead branch kept: the favourite is only refused when not hungry.
		if _hungry():
			care.item_scold_flag = 1
		return true
	return false


## The evolution items' levels: a fixed required level (item_effects `requires_level`), else
## refused when the target's level equals the partner's, the partner's + 2 or - 1.
func _evolution_refused(item: Variant) -> bool:
	var level := care.partner_level()
	var effect: Dictionary = data.item_effect(item)
	if effect.has("requires_level"):
		return level != int(effect["requires_level"])
	var target := _evolution_target_level(item)
	return target == level or target == level + 2 or target == level - 1


func _evolution_target_level(item: Variant) -> int:
	var target = data.evolution_item_target(item).get("target")
	if target == null:
		return -1
	return int(data.digimon(int(target["id"])).get("level", {}).get("id", 0))


# --- partnerHandleFoodFeed (partner_impl.c:1615), US / JP_TRIAL and later -----------------------

## After feeding: the hunger rule. True when the partner shows it liked it (animation 0xB).
func handle_food_feed(item: Variant) -> bool:
	var food: bool = _item(item).get("feeding", "") == "food"
	if _hungry():
		if not food:
			return false
		var happy := false
		if not _raise_int("energy_threshold") > _val("energy_level"):
			_add("happiness", 5)
			_add("discipline", 1)
			_set_condition(Care.HUNGRY, false)
			care.set_food_timer()
			_put("starvation_timer", 0)
		if _is_favourite(item) or not _val("energy_level") < _raise_int("energy_threshold"):
			happy = true
		return happy
	if food:
		_add("happiness", -3)
		_add("discipline", -2)
	return false


## removeOneSelectedItem: one of the item leaves the bag.
func remove_one(item: Variant) -> void:
	game_state.remove_item(item, 1)


# --- ITEM_FUNCTIONS (item.c:1932) ---------------------------------------------------------------

## ITEM_FUNCTIONS[type](type): the item's handler. Returns false for an item whose effect isn't
## ported (evolution items: specs/inventory.md §6).
func apply(item: Variant) -> bool:
	var handler = _item(item).get("handler")
	if handler is Dictionary:
		handler = handler.get("name")
	if handler == null or not HANDLERS.has(handler):
		return true
	return call(HANDLERS[handler], item) != false


## Whether the item's effect is ported (the inventory refuses the others for now).
func is_ported(item: Variant) -> bool:
	var handler = _item(item).get("handler")
	if handler is Dictionary:
		handler = handler.get("name")
	return handler != "handleEvoItems"


## handleHPHealingItem (item.c:2377): unless HP is 0, HP + HEALING_VALUES[id].
func _handle_hp_healing(item: Variant) -> void:
	if _current("hp") != 0:
		_heal("hp", int(_values(item).get("heal", 0)))


## handleMPHealingItem (item.c:2366).
func _handle_mp_healing(item: Variant) -> void:
	if _current("hp") != 0:
		_heal("mp", int(_values(item).get("heal", 0)))


## handleDoubleFloppy (item.c:2351): unless HP is 0, HP and MP + 1500.
func _handle_double_floppy(item: Variant) -> void:
	if _current("hp") != 0:
		var values := _values(item)
		_heal("hp", int(values.get("heal_hp", 1500)))
		_heal("mp", int(values.get("heal_mp", 1500)))


## handleStatusItems (item.c:2218), field branches: 9 is a Double floppy outside battle; 13 / 14
## call handleMedicineHealing with their chances (item_effects `code`). 8 and 10 are battle items.
func _handle_status_items(item: Variant) -> void:
	if _current("hp") == 0:
		return
	var effect: Dictionary = data.item_effect(item)
	var code := " ".join(effect.get("code", []))
	var medicine := RegEx.create_from_string("handleMedicineHealing\\((\\d+),(\\d+)\\)").search(code)
	if medicine != null:
		handle_medicine_healing(int(medicine.get_string(1)), int(medicine.get_string(2)))
	elif code.contains("handleDoubleFloppy"):
		_heal("hp", 1500)
		_heal("mp", 1500)


## handleMedicineHealing (item.c:2937): injured -> cured when random(3) < injury_chance; sick ->
## cured when random(10) < sickness_chance. True when the sickness was cured.
func handle_medicine_healing(injury_chance: int, sickness_chance: int) -> bool:
	if _condition(Care.INJURED) and Rng.random_limit(3) < injury_chance:
		_set_condition(Care.INJURED, false)
		_put("injury_timer", 0)
	if _condition(Care.SICK) and Rng.random_limit(10) < sickness_chance:
		_set_condition(Care.SICK, false)
		_put("sickness_timer", 0)
		_put("area_effect_timer", 0)
		return true
	return false


## handleRestore (item.c:2315), field: HP + the item's `amount` (12: 9999), or half the max HP when
## the case computes it (11, a battle item).
func _handle_restore(item: Variant) -> void:
	var values := _values(item)
	_heal("hp", int(values["amount"]) if values.has("amount") else _base("max_hp") / 2)


## handleChips (item.c:2248): permanent stats with their caps, the DV chips' lifetime and tamer
## level, Auto Pilot's script, the Port. potty. The passive chips have no case: nothing.
func _handle_chips(item: Variant) -> void:
	var effect: Dictionary = data.item_effect(item)
	var code := " ".join(effect.get("code", []))
	if code.contains("callScriptSection"):
		# Auto Pilot: while no script runs, script section 0x4DD of script 0.
		if script_ctx == null or script_ctx.is_paused:
			var section := RegEx.create_from_string("callScriptSection\\(0,0x([0-9a-fA-F]+),0\\)").search(code)
			if interpreter != null and section != null:
				interpreter.call_section(0, section.get_string(1).hex_to_int(), 0)
		return
	if code.contains("handlePortaPotty"):
		handle_porta_potty()
		return
	var values := _values(item)
	_add_stat("max_hp", int(values.get("hp", 0)), MAX_HP_MP)
	_add_stat("max_mp", int(values.get("mp", 0)), MAX_HP_MP)
	_add_stat("offense", int(values.get("off", 0)), MAX_STAT)
	_add_stat("defense", int(values.get("def", 0)), MAX_STAT)
	_add_stat("speed", int(values.get("speed", 0)), MAX_STAT)
	_add_stat("brains", int(values.get("brain", 0)), MAX_STAT)
	var lifetime := int(values.get("lifetime", 0))
	_put("remaining_lifetime", maxi(_val("remaining_lifetime") + lifetime, 0))
	# The DV chips (0x1D-0x1F): the ones that take lifetime.
	if lifetime == DV_LIFETIME and clock != null:
		clock.add_tamer_level(10, -1)


## handlePortaPotty (item.c:2954).
func handle_porta_potty() -> void:
	if _condition(Care.POOPY):
		_put("poop_level", _raise_int("poop_timer"))
		_set_condition(Care.POOPY, false)
		care.handle_poop_weight_loss()


## handleFood (item.c:2685).
func _handle_food(item: Variant) -> void:
	var v := _values(item)
	var energy := int(v.get("energy", 0))
	var happiness := int(v.get("happiness", 0))
	if _is_favourite(item):
		energy = energy * 14 / 10
		happiness += 2
	# addEnergy, reduceTiredness, addHappiness, addDiscipline, addWeight (item.c:2955-3010)
	_put("energy_level", mini(_val("energy_level") + energy, _raise_int("energy_cap")))
	_put("tiredness", maxi(_val("tiredness") - int(v.get("tiredness", 0)), 0))
	_put("happiness", mini(_val("happiness") + happiness, 100))
	_put("discipline", mini(_val("discipline") + int(v.get("discipline", 0)), 100))
	var weight := _val("weight") + int(v.get("weight", 0))
	_put("weight", 99 if weight >= 100 else maxi(weight, 1))
	_add("poop_level", -1)
	# setTrainingBoost runs for every food: one without a boost clears a running one.
	_put("train_boost_flag", int(v.get("trainFlag", 0)))
	_put("train_boost_value", int(v.get("trainValue", 0)))
	_put("train_boost_timer", int(v.get("trainDuration", 0)) * 1200)
	handle_item_sickness(int(v.get("sicknessChance", 0)))
	_add("remaining_lifetime", int(v.get("lifetime", 0)))
	_add_stat("max_hp", int(v.get("addedHP", 0)), MAX_HP_MP)
	_add_stat("max_mp", int(v.get("addedMP", 0)), MAX_HP_MP)
	_heal("hp", int(v.get("healedHP", 0)))
	_heal("mp", int(v.get("healedMP", 0)))
	_add_stat("offense", int(v.get("addedOffense", 0)), MAX_STAT)
	_add_stat("defense", int(v.get("addedDefense", 0)), MAX_STAT)
	_add_stat("speed", int(v.get("addedSpeed", 0)), MAX_STAT)
	_add_stat("brains", int(v.get("addedBrain", 0)), MAX_STAT)


## handleItemSickness (item.c:3035): random(100) < chance and not sick -> sick, an injury cured,
## the sick message.
func handle_item_sickness(chance: int) -> void:
	if Rng.random_limit(100) < chance and not _condition(Care.SICK):
		_set_condition(Care.SICK, true)
		_add("times_being_sick", 1)
		_put("sickness_timer", 1)
		if _condition(Care.INJURED):
			_set_condition(Care.INJURED, false)
			_put("injury_timer", 0)
		care.show_sick_message()


## handleEvoItems (item.c:2190): starts an evolution, which isn't ported (specs/inventory.md §6).
func _handle_evo_items(_item_ref: Variant) -> bool:
	return false


# --- helpers ---------------------------------------------------------------------------------------

func _item(item: Variant) -> Dictionary:
	return data.item(item) if data != null else {}


func _values(item: Variant) -> Dictionary:
	return data.item_effect(item).get("values", {})


func _care() -> Dictionary:
	return game_state.state["partner"]["care"]


func _val(field_name: String) -> int:
	return int(_care()[field_name])


func _put(field_name: String, value: int) -> void:
	_care()[field_name] = value


func _add(field_name: String, amount: int) -> void:
	_put(field_name, _val(field_name) + amount)


func _condition(flag: int) -> bool:
	return _val("condition") & flag != 0


func _set_condition(flag: int, on: bool) -> void:
	_put("condition", _val("condition") | flag if on else _val("condition") & ~flag)


func _hungry() -> bool:
	return _condition(Care.HUNGRY)


func _raise_int(field_name: String) -> int:
	return int(care.raise_data().get(field_name, 0))


func _is_favourite(item: Variant) -> bool:
	var favourite = care.raise_data().get("favorite_food")
	if favourite == null:
		return false
	var id = favourite.get("id") if favourite is Dictionary else favourite
	return int(id) == int(_item(item).get("id", -1))


func _stats() -> Dictionary:
	return game_state.state["partner"]["stats"]


func _current(field_name: String) -> int:
	return int(_stats()["current"][field_name])


func _base(field_name: String) -> int:
	return int(_stats()["base"][field_name])


## addWithLimit on a current value: HP / MP up to their maxima.
func _heal(field_name: String, amount: int) -> void:
	var limit := _base("max_" + field_name)
	_stats()["current"][field_name] = mini(_current(field_name) + amount, limit)


## addWithLimit on a permanent stat.
func _add_stat(field_name: String, amount: int, limit: int) -> void:
	_stats()["base"][field_name] = mini(_base(field_name) + amount, limit)
