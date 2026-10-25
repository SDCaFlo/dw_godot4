class_name Care
extends Node
## Partner care (specs/care.md): partner_impl.c's care rules on GameState.state.partner.care.
## Called by the Partner from its normal state each game frame (partnerTickNormal), before the
## clock ticks. Every method names the C function it reproduces; the data comes from the
## partner's `care` component (raise_data, sleep_patterns) and the properties of specs/care.md §4.

## A scripted event the port can't play yet (callScriptSection): section 0x4DE = the partner
## collapses / dies.
signal script_requested(section: int)
## addConditionBubble: bubble type (0 hungry, 1 poopy, 2 sick, 3 sleepy, 4 tired, 6 injured).
signal bubble_shown(type: int)
## The butterfly of an unhappy partner (setButterfly / unsetButterfly).
signal butterfly_changed(shown: bool)
## world.poop changed (a pile added or eaten).
signal poop_changed

const SLEEPY := 1 << 0
const TIRED := 1 << 1
const HUNGRY := 1 << 2
const POOPY := 1 << 3
const UNHAPPY := 1 << 4
const INJURED := 1 << 5
const SICK := 1 << 6
const LEVEL_FRESH := 1
const LEVEL_IN_TRAINING := 2
const POOP_SLOTS := 100
## createPoopPile: at most this many piles per map before older ones are overwritten.
const POOP_PER_MAP := 16
const SCRIPT_COLLAPSE := 0x4DE
const PSTAT_DEATH := 0xFF
## setTrigger(0x280) while the partner is full (tickHungerMechanics).
const TRIGGER_FULL := 0x280
## PartnerTickNormal and the bubbles only run in these partner states (handleConditionBubble).
const PARTNER_NORMAL := 1
const PARTNER_DYING := 8

var game_state: Node
var data: Node
var clock: Clock
var field: FieldMap
var partner: Partner
var tamer: Tamer
var fade: Fade
## The text area the "<name> is sick" message is drawn into (the tamer's message box shows it).
var text_area: TextArea

## MAP_TILE_DATA.partnerAreaResponse: 0 neutral, 1 liked map, 2 disliked map (set_area_response).
var area_response := 0
## Not saved in the original either (partner_impl.c sbss).
var has_immortal_hour := false
var immortal_hour := -1
var item_scold_flag := 0
var current_poop_id := 0
var is_natural_death := false
var bubble_type := 0
var bubble_timer := 0
var has_butterfly := false
## MENU_OPTIONS[6].disabled: the menu's "Sleep" (setSleepDisabled).
var sleep_enabled := false
## IS_SCRIPT_PAUSED == 0: a script runs (the stand-in for script_requested sets it).
var script_running := false
## EVOLUTION_TARGET: -1 until the evolution step computes it.
var evolution_target := -1

var _raise_key := ""
var _raise_cache := {}


# --- Gates and helpers -------------------------------------------------------------------------

func _care() -> Dictionary:
	return game_state.state["partner"]["care"]


func _clock() -> Dictionary:
	return game_state.state["clock"]


func _hour() -> int:
	return int(_clock()["hour"])


func _minute() -> int:
	return int(_clock()["minute"])


func _frame() -> int:
	return int(_clock()["frame"])


## CURRENT_FRAME != LAST_HANDLED_FRAME: the clock advanced on its last tick (specs/care.md §2.1).
func _advanced() -> bool:
	return int(_clock()["frame"]) != int(_clock()["last_handled_frame"])


## CURRENT_FRAME % n == 0 on a frame the clock advanced.
func _every(n: int) -> bool:
	return _advanced() and _frame() % n == 0


func _val(field_name: String) -> int:
	return int(_care()[field_name])


func _put(field_name: String, value: int) -> void:
	_care()[field_name] = value


func _add(field_name: String, amount: int) -> void:
	_care()[field_name] = int(_care()[field_name]) + amount


func _cond(flag: int) -> bool:
	return _val("condition") & flag != 0


func _flag(flag: int, on: bool) -> void:
	_put("condition", _val("condition") | flag if on else _val("condition") & ~flag)


func _digimon() -> String:
	return game_state.state["partner"]["digimon"]


## The partner's raise_data (care component), cached per Digimon.
func _raise() -> Dictionary:
	if _raise_key != _digimon():
		_raise_key = _digimon()
		_raise_cache = data.entity("digimon", _raise_key).get("care", {}).get("raise", {})
	return _raise_cache


func _raise_int(field_name: String) -> int:
	return int(_raise().get(field_name, 0))


func _level() -> int:
	return int(data.digimon(_digimon()).get("level", {}).get("id", 0))


## For item use (specs/inventory.md §4): the partner's raise_data, its level (DIGIMON_DATA.level),
## the sick message (tamer state 20).
func raise_data() -> Dictionary:
	return _raise()


func partner_level() -> int:
	return _level()


func show_sick_message() -> void:
	_show_sick_message()


func _sleep_pattern() -> Dictionary:
	return data.sleep_pattern(int(_raise().get("sleep_cycle", {}).get("id", 0)))


func _tamer_state() -> int:
	return tamer.state if tamer != null else 0


func _partner_state() -> int:
	return partner.state if partner != null else PARTNER_NORMAL


func _in_immortal_hour() -> bool:
	return has_immortal_hour and immortal_hour == _hour()


## partnerAreaResponse (loadMapSetup, map.c:4187-4200): liked[0], disliked[0], liked[1], ... are
## tested in turn against the partner's favoured region; the first match wins.
func set_area_response(liked: Array, disliked: Array) -> void:
	area_response = 0
	var region := _raise_int("favored_region")
	for j in 4:
		if j < liked.size() and int(liked[j]) == region:
			area_response = 1
			return
		if j < disliked.size() and int(disliked[j]) == region:
			area_response = 2
			return


# --- tickConditions (partner_impl.c:2059) ------------------------------------------------------

func tick_conditions() -> void:
	if clock == null or not clock.active or not clock.running or _partner_state() != PARTNER_NORMAL \
			or not _advanced() or (fade != null and fade.protection):
		return
	tick_death_condition()
	tick_sleep_mechanics()
	tick_sickness_mechanics()
	tick_tiredness_mechanics()
	tick_hunger_mechanics()
	tick_unhappiness_mechanics()
	tick_condition_boundaries()
	_add("area_effect_timer", 1)
	if _val("area_effect_timer") > 28800:
		_put("area_effect_timer", 0)
	_add("train_boost_timer", -1)
	if _val("train_boost_timer") <= 0:
		_put("train_boost_flag", 0)
		_put("train_boost_timer", 0)
	var happiness := _val("happiness")
	if _frame() % 4800 == 0 and happiness < 80:
		_put("remaining_lifetime", maxi(_val("remaining_lifetime") - ((happiness - 80) / -50 + 1), 0))
	# isInDaytimeTransition() is 1 when no fade runs: the rest waits for the fade to end.
	if field != null and field.is_in_daytime_transition():
		return
	if _in_immortal_hour():
		return
	if has_immortal_hour:
		has_immortal_hour = false
		immortal_hour = -1
	# Evolution targets and the virus bar evolution (:2106-2149) come with the evolution step.


## tickDeathCondition (:1917).
func tick_death_condition() -> void:
	if _in_immortal_hour() or _val("remaining_lifetime") > 0 or _partner_state() == PARTNER_DYING \
			or _tamer_state() != 0 or script_running:
		return
	is_natural_death = true
	game_state.set_script_value(PSTAT_DEATH, 0)
	_put("remaining_lifetime", 0)
	_call_script(SCRIPT_COLLAPSE)


## tickSleepMechanics (:913).
func tick_sleep_mechanics() -> void:
	var was_sleepy := _cond(SLEEPY)
	if _every(20):
		_add("tiredness_sleep_timer", _val("tiredness") * 3 / 10)
	if not was_sleepy and _val("tiredness_sleep_timer") >= 180 and _every(200):
		_add("time_awake_today", -1)
		_put("tiredness_sleep_timer", 0)
		var awake_left := _val("hours_awake_default") * 6 - _val("time_awake_today")
		var hours_late := awake_left / 6
		if awake_left % 6 != 0:
			hours_late += 1
		var sleepy := _val("wakeup_hour") - _val("hours_asleep_default") - hours_late
		_put("sleepy_hour", sleepy + 24 if sleepy < 0 else sleepy)
		_put("sleepy_minute", _val("time_awake_today") % 6 * 10)
	var level := _level()
	if _cond(SLEEPY):
		if level == LEVEL_FRESH:
			if _every(200):
				_add("happiness", -1)
				_add("discipline", -1)
		elif level == LEVEL_IN_TRAINING:
			if _every(300):
				_add("happiness", -1)
				_add("discipline", -1)
		elif _every(1200):
			_add("happiness", -2)
			_add("discipline", -4)
		if _every(1200) and _hour() != _val("sleepy_hour"):
			_add("sickness_counter", 1)
			_add("missed_sleep_hours", 1)
	var hour := _hour()
	var sleepy_hour := _val("sleepy_hour")
	var wakeup := _val("wakeup_hour")
	if _cond(SLEEPY) and ((sleepy_hour < wakeup and sleepy_hour < hour and wakeup <= hour)
			or (wakeup < sleepy_hour and hour < sleepy_hour and wakeup <= hour)):
		# A missed night: the partner wakes up by itself.
		_next_sleep_schedule(level)
		_put("time_awake_today", _val("hours_awake_default") * 6)
		_put("tiredness_sleep_timer", 0)
		_flag(SLEEPY, false)
		_add("care_mistakes", 1)
		if partner != null:
			partner.update_condition_animation()
		if clock != null:
			clock.add_tamer_level(1, -1)
	if not was_sleepy:
		sleepy_hour = _val("sleepy_hour")
		wakeup = _val("wakeup_hour")
		if wakeup < sleepy_hour:
			if hour >= sleepy_hour or hour < wakeup:
				_flag(SLEEPY, true)
		elif wakeup > sleepy_hour:
			if hour >= sleepy_hour and hour < wakeup:
				_flag(SLEEPY, true)
	sleep_enabled = _cond(SLEEPY)


## The next sleepy / wake-up time after a night (tickSleepMechanics :987-1010, handleSleeping
## :1177-1200): Fresh / In-Training relative to the wake-up, others the sleep pattern again.
func _next_sleep_schedule(level: int) -> void:
	if level < 3:
		var sleepy := _val("wakeup_hour") + _val("hours_awake_default")
		_put("sleepy_hour", sleepy - 24 if sleepy >= 24 else sleepy)
		_put("sleepy_minute", 0)
		var wakeup := _val("sleepy_hour") + _val("hours_asleep_default")
		_put("wakeup_hour", wakeup - 24 if wakeup >= 24 else wakeup)
		_put("wakeup_minute", 0)
	else:
		var pattern := _sleep_pattern()
		_put("sleepy_hour", int(pattern.get("sleepy_hour", 0)))
		_put("sleepy_minute", int(pattern.get("sleepy_minute", 0)))
		_put("wakeup_hour", int(pattern.get("wakeup_hour", 0)))
		_put("wakeup_minute", int(pattern.get("wakeup_minute", 0)))


## tickSicknessMechanics (:1832).
func tick_sickness_mechanics() -> void:
	var was_sick := _cond(SICK)
	if _val("sickness_counter") >= 10 and _every(1200) and not was_sick:
		_add("sickness_tries", 1)
		# uint8_t chance: a negative value wraps to 256 + value (specs/care.md §2.7).
		var chance := ((_val("sickness_tries") - 10) * 5 + (_val("tiredness") - 50)) & 0xFF
		if Rng.random_limit(100) < chance:
			_get_sick()
			_add("happiness", -20)
			_put("sickness_counter", 0)
	if not was_sick and _val("area_effect_timer") > 12000 and _every(1200) and area_response == 2:
		_get_sick()
		_put("area_effect_timer", 0)
	if _every(1200) and _cond(SICK):
		_add("happiness", -10)
		_add("discipline", -5)
		_add("tiredness", 5)
	# Clears a timer left from an earlier sickness. It also resets the 1 just set by getting sick,
	# but that happens on an hourly frame, so the increment below makes it 1 again.
	if not was_sick and _val("sickness_timer") > 0:
		_put("sickness_timer", 0)
	if _every(1200):
		if _cond(SICK):
			_add("sickness_timer", 1)
		if _cond(INJURED):
			_add("injury_timer", 1)
	if _in_immortal_hour():
		return
	if _val("injury_timer") >= 12 and not was_sick and _tamer_state() == 0:
		_get_sick()
		_flag(INJURED, false)
		_put("injury_timer", 0)
	if not was_sick and _cond(SICK):
		_show_sick_message()
	if _val("sickness_timer") >= 12 and _partner_state() != PARTNER_DYING and _tamer_state() == 0 \
			and _val("remaining_lifetime") != 0 and not script_running:
		game_state.set_script_value(PSTAT_DEATH, 0)
		game_state.state["partner"]["lives"] = int(game_state.state["partner"]["lives"]) - 1
		_call_script(SCRIPT_COLLAPSE)
		_put("sickness_timer", 0)


## tickSicknessMechanics' message (partner_impl.c:1898-1904): tamerSetState(0x14) shows the
## message box; the text is the name in colour 10 at row 120, then MAIN_D_801225A0 (" is sick") in
## colour 1 at strlen(name) / 2 * GLYPH_WIDTH. Quirk kept: that is GLYPH_WIDTH per character of the
## (full-width) name, not the name's drawn width, so US leaves a gap after narrow letters.
func _show_sick_message() -> void:
	if tamer != null:
		tamer.set_state(Tamer.STATE_AWARD)
	if text_area == null:
		return
	var partner_name: String = game_state.state["partner"]["name"]
	text_area.clear_all()
	text_area.set_text_color(10)
	text_area.draw_string(partner_name, 0, 120)
	text_area.set_text_color(1)
	text_area.draw_string(data.text("MAIN_D_801225A0"), partner_name.length() * text_area.font.glyph_width, 120)


func _get_sick() -> void:
	_flag(SICK, true)
	_add("times_being_sick", 1)
	_put("sickness_timer", 1)


## tickTirednessMechanics (:1388).
func tick_tiredness_mechanics() -> void:
	var timer := _val("area_effect_timer")
	if timer % 1200 == 0 and timer > 0:
		if area_response == 1:
			_add("happiness", 1)
			_add("tiredness", -2)
		if area_response == 2:
			_add("happiness", -1)
			_add("tiredness", 1)
	# sub_tiredness is never increased in the decomp: dead code, kept.
	if _val("sub_tiredness") >= 0x3C:
		_put("tiredness", mini(_val("tiredness") + 1, 0x64))
		_put("sub_tiredness", 0)
	if _val("tiredness") >= 0x32:
		_add("tiredness_hunger_timer", 1)
	else:
		_put("tiredness_hunger_timer", 0)
	if _val("tiredness") >= 0x50:
		_flag(TIRED, true)
		if _every(100):
			_add("happiness", -2)
	else:
		_flag(TIRED, false)


## tickHungerMechanics (:1494).
func tick_hunger_mechanics() -> void:
	if _cond(HUNGRY):
		if _every(10):
			_add("starvation_timer", -1)
	elif _every(20):
		_add("food_level", -1)
	if _every(1200):
		_put("energy_level", maxi(_val("energy_level") - _raise_int("energy_usage"), 0))
	if not _cond(HUNGRY) and _val("food_level") <= 0:
		_put("starvation_timer", 180)
		_flag(HUNGRY, true)
		handle_condition_bubble()
	if _cond(HUNGRY) and _val("starvation_timer") <= 0:
		set_food_timer()
		_put("starvation_timer", 0)
		_flag(HUNGRY, false)
		if _val("energy_level") < _raise_int("energy_threshold"):
			_add("care_mistakes", 1)
	if _val("energy_level") <= 0:
		if _frame() % 200 == 0:
			_put("weight", maxi(_val("weight") - 1, 1))
		if _every(20):
			_add("empty_stomach_timer", 1)
	if _val("tiredness_hunger_timer") >= 50 and _every(1200):
		_add("food_level", -3)
	if _raise_int("energy_threshold") <= _val("energy_level") and not game_state.is_trigger_set(TRIGGER_FULL):
		game_state.set_trigger(TRIGGER_FULL)


## tickUnhappinessMechanics (:1042).
func tick_unhappiness_mechanics() -> void:
	var happiness := _val("happiness")
	if _val("condition") == 0 and happiness < 0 and _every(200):
		if Rng.random_limit(100) < absi(happiness) - _val("discipline"):
			_flag(UNHAPPY, true)
	if _cond(UNHAPPY):
		if _every(15):
			_add("happiness", 1)
		if _every(300):
			var stats: Dictionary = game_state.state["partner"]["stats"]
			var base: Dictionary = stats["base"]
			for stat in ["max_hp", "max_mp", "offense", "defense", "speed", "brains"]:
				var value := int(base[stat])
				base[stat] = maxi(value - value * 2 / 100, 1)
			var current: Dictionary = stats["current"]
			current["hp"] = mini(int(current["hp"]), int(base["max_hp"]))
			current["mp"] = mini(int(current["mp"]), int(base["max_mp"]))
	if _cond(UNHAPPY) and _val("happiness") >= 0:
		_flag(UNHAPPY, false)
		_finish_partner_loop()
		_set_butterfly(false)


## tickConditionBoundaries (:868): every field frame, in every partner state.
func tick_condition_boundaries() -> void:
	_put("happiness", clampi(_val("happiness"), -100, 100))
	_put("discipline", clampi(_val("discipline"), 0, 100))
	_put("tiredness", clampi(_val("tiredness"), 0, 100))
	_put("energy_level", clampi(_val("energy_level"), 0, _raise_int("energy_cap")))
	_put("weight", clampi(_val("weight"), 1, 99))


# --- Poop (partner_impl.c:1656-1772) -----------------------------------------------------------

## tickPoopingMechanic (:1656). Returns true when the partner has to poop now (partner state 7).
func tick_pooping_mechanic() -> bool:
	if _tamer_state() != 0:
		return false
	var poopy := _cond(POOPY)
	if not poopy and _every(200):
		_add("poop_level", -1)
	if not poopy and _val("poop_level") <= 0:
		_flag(POOPY, true)
		_put("pooping_timer", (_val("discipline") + 20) * 1200 / 100)
	if poopy and _advanced():
		_add("pooping_timer", -1)
	if poopy and _val("pooping_timer") <= 0:
		_put("pooping_timer", -1)
		item_scold_flag = 1
		return true
	return false


## tickPoopDetection (:1688): a poop eater (raise_data.eats_poop; the C tests ids 0xb and 0x27)
## finds a pile the tamer stands near. Returns its slot, or -1. Eating it (partner state 9,
## partnerTickEatShit) comes with the poop eaters.
func tick_poop_detection() -> int:
	if not _raise().get("eats_poop", false) or tamer == null:
		return -1
	var poop: Array = game_state.state["world"]["poop"]
	var tamer_x := int(tamer.position.x)
	var tamer_z := int(-tamer.position.z)
	for i in poop.size():
		var pile = poop[i]
		if pile == null or pile["map"] != game_state.state["world"]["screen"]:
			continue
		var radius := 200 if int(pile["size"]) < 11 else 300
		var centre := FieldMap.tile_centre(Vector2i(int(pile["x"]), int(pile["y"])))
		if centre.x - radius < tamer_x and tamer_x < centre.x + radius \
				and centre.y - radius < tamer_z and tamer_z < centre.y + radius:
			return i
	return -1


## createPoopPile (:1242): a pile on the tile in front of the partner (by its rotation), moved
## aside from piles on the same tile; at most 16 per map. Returns the slot used.
func create_poop_pile(tile: Vector2i, rotation_vy: int) -> int:
	var x := tile.x
	var y := tile.y
	if (rotation_vy >= 0 and rotation_vy <= 0x300) or rotation_vy >= 0xD00:
		y -= 1
	if rotation_vy >= 0x100 and rotation_vy < 0x700:
		x += 1
	if rotation_vy >= 0x500 and rotation_vy <= 0xB00:
		y += 1
	if rotation_vy >= 0x900 and rotation_vy <= 0xF00:
		x -= 1
	var poop: Array = game_state.state["world"]["poop"]
	var screen: String = game_state.state["world"]["screen"]
	var size := _raise_int("poop_size")
	var count := 0
	var i := 0
	while i < POOP_SLOTS:
		var pile = poop[i]
		if pile != null and int(pile["x"]) == x and int(pile["y"]) == y and pile["map"] == screen:
			var step := Rng.random_limit(4)
			if step == 0:
				x -= 1
			elif step == 1:
				x += 1
			elif step == 2:
				y -= 1
			else:
				y += 1
			i = 0
			count = 0
			continue
		if count >= POOP_PER_MAP:
			break
		if pile != null:
			if pile["map"] == screen:
				count += 1
		else:
			poop[i] = {"map": screen, "x": x, "y": y, "size": size}
			break
		i += 1
	if i >= POOP_SLOTS:
		poop[current_poop_id] = {"map": screen, "x": x, "y": y, "size": size}
		current_poop_id += 1
	if count >= POOP_PER_MAP:
		var j := current_poop_id
		while true:
			if j < POOP_SLOTS and poop[j] != null and poop[j]["map"] == screen:
				poop[j] = {"map": screen, "x": x, "y": y, "size": size}
				current_poop_id += 1
				break
			if j >= POOP_SLOTS - 1:
				j = -1
				current_poop_id = 0
			j += 1
	# createPoopPile: `type != 0x27` (raise_data.raises_virus_bar).
	if _raise().get("raises_virus_bar", true):
		_add("virus_bar", 1)
	if current_poop_id >= POOP_SLOTS:
		current_poop_id = 0
	# createCloudFX at the pile: later with the effects.
	poop_changed.emit()
	return i


## handleWildPoop (:1757): US doubles the poop timer.
func handle_wild_poop() -> void:
	_flag(POOPY, false)
	_add("care_mistakes", 1)
	_add("happiness", -10)
	_add("discipline", -5)
	_put("poop_level", _raise_int("poop_timer") * 2)
	handle_poop_weight_loss()


## handleToilet (:1730): US doubles the poop timer.
func handle_toilet() -> void:
	_add("happiness", 2)
	_add("discipline", 2)
	_put("poop_level", _raise_int("poop_timer") * 2)
	_flag(POOPY, false)
	handle_poop_weight_loss()


## handlePoopWeightLoss (:1745).
func handle_poop_weight_loss() -> void:
	_put("weight", maxi(_val("weight") - (Rng.random_limit(4) + _raise_int("poop_size")) / 4, 1))


## handleEatingPoop (:1774): HP / MP / weight by the pile's size, a chance to be cured.
func handle_eating_poop(slot: int) -> void:
	var poop: Array = game_state.state["world"]["poop"]
	var stats: Dictionary = game_state.state["partner"]["stats"]
	var base: Dictionary = stats["base"]
	var current: Dictionary = stats["current"]
	var size := int(poop[slot]["size"]) if poop[slot] != null else 0
	var cure_chance := 0
	if size < 11:
		current["hp"] = int(current["hp"]) + int(base["max_hp"]) / 20
		current["mp"] = int(current["mp"]) + int(base["max_mp"]) / 50
		_add("weight", 1)
		cure_chance = 2
	elif size < 14:
		current["hp"] = int(current["hp"]) + int(base["max_hp"]) / 10
		current["mp"] = int(current["mp"]) + int(base["max_mp"]) / 20
		_add("weight", 3)
		cure_chance = 7
	else:
		current["hp"] = int(current["hp"]) + int(base["max_hp"]) / 2
		current["mp"] = int(current["mp"]) + int(base["max_mp"]) / 10
		_add("weight", 10)
		cure_chance = 20
	current["hp"] = mini(int(current["hp"]), int(base["max_hp"]))
	current["mp"] = mini(int(current["mp"]), int(base["max_mp"]))
	_put("weight", mini(_val("weight"), 99))
	if Rng.random_limit(100) < cure_chance:
		if _cond(INJURED):
			_flag(INJURED, false)
			_put("injury_timer", 0)
		if _cond(SICK):
			_flag(SICK, false)
			_put("sickness_timer", 0)
			_put("area_effect_timer", 0)
	poop[slot] = null
	poop_changed.emit()


# --- Bubbles (handleConditionBubble, :1551) ----------------------------------------------------

## Every frame in partner states 1 and 10: which condition bubble to show (specs/care.md §2.11).
func handle_condition_bubble() -> void:
	var state := _partner_state()
	if state != PARTNER_NORMAL and state != 10:
		return
	var cond := _val("condition")
	var next := -1
	for rule: Array in [[SICK, 2], [INJURED, 6], [POOPY, 1], [HUNGRY, 0], [TIRED, 4], [SLEEPY, 3]]:
		if cond & int(rule[0]) and bubble_type != int(rule[1]):
			next = int(rule[1])
	if cond & UNHAPPY and next == -1 and not has_butterfly and cond == UNHAPPY:
		_set_butterfly(true)
		return
	if next != bubble_type and next != -1 and bubble_timer >= 50:
		if has_butterfly:
			_set_butterfly(false)
			_flag(UNHAPPY, false)
			_finish_partner_loop()
		bubble_timer = 0
		bubble_type = next
		bubble_shown.emit(next)
	bubble_timer += 1
	if bubble_timer >= 60:
		bubble_type = -1


func _set_butterfly(shown: bool) -> void:
	if has_butterfly != shown:
		has_butterfly = shown
		butterfly_changed.emit(shown)


## anim.loopCount = 1 (tickUnhappinessMechanics, handleConditionBubble).
func _finish_partner_loop() -> void:
	if partner != null and partner.animator != null:
		partner.animator.finish_loop()


# --- Schedules (setSleepTimes :618, setFoodTimer :664, resetPartnerPara :593) ------------------

## setSleepTimes (:618).
func set_sleep_times() -> void:
	var level := _level()
	var pattern := _sleep_pattern()
	if level < 3:
		var awake_base := 3 if level == LEVEL_FRESH else 7
		# randomLimit(1) is always 0; kept.
		var roll := Rng.random_limit(1)
		_put("sleepy_hour", (_hour() + awake_base + roll) % 24)
		_put("sleepy_minute", 0)
		_put("wakeup_hour", (_val("sleepy_hour") + int(pattern.get("sleepy_hours", 0))) % 24)
		_put("wakeup_minute", 0)
		_put("hours_awake_default", awake_base + roll)
		_put("hours_asleep_default", int(pattern.get("sleepy_hours", 0)))
	else:
		_put("sleepy_hour", int(pattern.get("sleepy_hour", 0)))
		_put("sleepy_minute", int(pattern.get("sleepy_minute", 0)))
		_put("wakeup_hour", int(pattern.get("wakeup_hour", 0)))
		_put("wakeup_minute", int(pattern.get("wakeup_minute", 0)))
		_put("hours_awake_default", int(pattern.get("awake_hours", 0)))
		_put("hours_asleep_default", int(pattern.get("sleepy_hours", 0)))
	_put("time_awake_today", _val("hours_awake_default") * 6)
	_put("sickness_counter", 0)
	_put("tiredness_sleep_timer", 0)


## scriptUpdateEnergyBoundaries (script_interp.c:846), after a script changes a stat: energy at
## most energyCap; a hungry partner whose energy reached energyThreshold is fed (food timer set,
## starvation timer 0).
func update_energy_boundaries() -> void:
	if _val("energy_level") > _raise_int("energy_cap"):
		_put("energy_level", _raise_int("energy_cap"))
	if _cond(HUNGRY) and _raise_int("energy_threshold") <= _val("energy_level"):
		_flag(HUNGRY, false)
		set_food_timer()
		_put("starvation_timer", 0)


## setFoodTimer (:664), US version: the next hunger hour, and food_level = minutes until then.
func set_food_timer() -> void:
	var level := _level()
	var hour := _hour()
	if level == LEVEL_FRESH:
		_put("next_hunger_hour", (hour / 2 * 2 + 2) % 24)
	elif level == LEVEL_IN_TRAINING:
		_put("next_hunger_hour", (hour / 3 * 3 + 3) % 24)
	else:
		_put("next_hunger_hour", next_hunger_hour(_raise().get("hunger_hours", []), hour, _val("next_hunger_hour")))
	var next := _val("next_hunger_hour")
	if hour <= next:
		_put("food_level", (next - hour) * 60 - _minute())
	else:
		_put("food_level", (24 - hour) * 60 + next * 60 - _minute())


## The US loop of setFoodTimer (:699-736) on the hunger hours (without the -1 padding).
static func next_hunger_hour(hours: Array, hour: int, previous: int) -> int:
	if hours.is_empty():
		return previous
	for h in hours:
		if hour <= previous:
			if previous < int(h):
				return int(h)
		elif hour < int(h):
			return int(h)
	for h in hours:
		if hour < int(h):
			return int(h)
	return int(hours[0])


## resetPartnerPara (:593): after an evolution or a rebirth.
func reset_partner_para() -> void:
	_put("poop_level", _raise_int("poop_timer"))
	for field_name in ["unused2", "unused1", "tiredness", "sub_tiredness", "tiredness_hunger_timer",
			"times_being_sick", "area_effect_timer", "sickness_timer", "injury_timer", "sickness_tries", "unused4",
			"empty_stomach_timer", "care_mistakes", "battles"]:
		_put(field_name, 0)
	_put("pooping_timer", -1)
	set_food_timer()
	_put("starvation_timer", -1)
	_put("weight", _raise_int("default_weight"))


## initializePartner's care part (:450-527): a new partner of the current Digimon. The first
## technique comes from raise_data.first_technique (the C tests ids 3 and 0x11), the finisher slot
## from the technique category (the C tests ids 0x3a-0x70).
func initialize_partner() -> void:
	_put("condition", 0)
	set_sleep_times()
	_put("missed_sleep_hours", 0)
	_put("poop_level", _raise_int("poop_timer"))
	_put("pooping_timer", -1)
	_put("virus_bar", 0)
	_put("tiredness", 0)
	_put("discipline", 50)
	_put("happiness", 50)
	_put("unused3", 50)
	set_food_timer()
	_put("energy_level", _raise_int("energy_threshold"))
	_put("remaining_lifetime", 360)
	_put("weight", _raise_int("default_weight"))
	for field_name in ["train_boost_flag", "train_boost_value", "train_boost_timer", "care_mistakes", "battles",
			"evo_timer", "times_being_sick", "area_effect_timer", "sickness_timer", "injury_timer"]:
		_put(field_name, 0)
	var partner_state: Dictionary = game_state.state["partner"]
	partner_state["lives"] = 3
	var moves: Array = partner_state["stats"]["base"]["moves"]
	var first = _raise().get("first_technique")
	if first is Dictionary:
		moves[0] = data.key_of("moves/move_data", int(first["move"]["id"]))
		game_state.learn_move(int(first["move"]["id"]))
	moves[1] = null
	moves[2] = null
	moves[3] = null
	var slots: Array = data.digimon(_digimon()).get("moves", [])
	for k in range(slots.size() - 1, -1, -1):
		var move: Dictionary = data.move(int(slots[k]["move"]["id"]))
		if move.get("category") == "finisher":
			moves[3] = move.get("key")
			break
	has_immortal_hour = false
	immortal_hour = -1


# --- Sleeping (sleepRegen :1331, handleSleeping :1158) -----------------------------------------

func _hours_until_wakeup() -> int:
	var wakeup := _val("wakeup_hour")
	return wakeup - _hour() if _hour() < wakeup else wakeup + (24 - _hour())


## sleepRegen (:1331): HP / MP back by the hours slept, tiredness down, weight down.
func sleep_regen() -> void:
	var asleep := maxi(_val("hours_asleep_default"), 1)
	var hours := _hours_until_wakeup()
	if _minute() > 0 and _hour() != _val("sleepy_hour"):
		hours += 1
	var factor := hours * 100 / asleep
	# getItemCount(0x22) != 0: an item whose `passive` is sleep_boost (Rest Pillow).
	if game_state.has_passive_item("sleep_boost"):
		factor = factor * 12 / 10
	if area_response == 1:
		factor = factor * 12 / 10
	elif area_response == 2:
		factor = factor * 8 / 10
	var stats: Dictionary = game_state.state["partner"]["stats"]
	var max_hp := int(stats["base"]["max_hp"])
	var max_mp := int(stats["base"]["max_mp"])
	var roll := Rng.random_limit(10)
	stats["current"]["hp"] = int(stats["current"]["hp"]) + factor * (max_hp * (roll + 70) / 100) / 100
	stats["current"]["mp"] = int(stats["current"]["mp"]) + factor * (max_mp * (roll + 70) / 100) / 100
	roll = Rng.random_limit(20)
	_add("tiredness", -(factor * (_val("tiredness") * (roll + 80) / 100) / 100))
	stats["current"]["hp"] = mini(int(stats["current"]["hp"]), max_hp)
	stats["current"]["mp"] = mini(int(stats["current"]["mp"]), max_mp)
	_put("tiredness", maxi(_val("tiredness"), 0))
	_put("weight", maxi(_val("weight") - _raise_int("default_weight") / 10, 1))


## handleSleeping (:1158): jump to the wake-up time and apply the night.
func handle_sleeping() -> void:
	var hours := _hours_until_wakeup()
	if clock != null:
		clock.advance_to_time(_val("wakeup_hour"), _val("wakeup_minute"))
	_add("evo_timer", _val("hours_asleep_default"))
	_put("remaining_lifetime", maxi(_val("remaining_lifetime") - hours, 0))
	_next_sleep_schedule(_level())
	set_food_timer()
	_put("starvation_timer", 0)
	_flag(HUNGRY, false)
	_put("time_awake_today", _val("hours_awake_default") * 6)
	_put("tiredness_sleep_timer", 0)
	_put("sickness_counter", 0)
	_flag(SLEEPY, false)
	sleep_enabled = false
	has_immortal_hour = true
	immortal_hour = _hour()
	if _cond(POOPY):
		create_poop_pile(partner.tile() if partner != null else Vector2i.ZERO, partner.direction if partner != null else 0)
		_flag(POOPY, false)
		_put("poop_level", _raise_int("poop_timer"))
		_put("pooping_timer", -1)
	# Quirk kept: hungry was cleared above, so this never applies.
	if _cond(HUNGRY):
		_add("weight", -1)
	if _cond(SICK):
		_add("sickness_timer", hours)
		_add("happiness", -20)
		_add("discipline", -10)
		_add("tiredness", 10)
	if _cond(INJURED):
		_add("injury_timer", hours)
		_add("happiness", -10)
		_add("discipline", -5)
		_add("tiredness", 5)


# --- Functions whose scenes come later (specs/care.md §3.4) ------------------------------------

## skipHours (:1990), US version: the care side of a scripted time skip (the script moves the
## clock itself).
func skip_hours(hours: int) -> void:
	_add("evo_timer", hours)
	_add("remaining_lifetime", -hours)
	if _hour() + hours >= 24:
		_add("age", (_hour() + hours) / 24)
	if clock != null:
		clock.update_time_of_day()
	if _hour() + hours % 4 == 0 and _val("happiness") < 80:
		_add("remaining_lifetime", -((_val("happiness") - 80) / -50 + 1))
	_put("remaining_lifetime", maxi(_val("remaining_lifetime"), 0))
	if _cond(SLEEPY):
		_add("sickness_counter", hours)
		_add("missed_sleep_hours", hours)
	if _cond(HUNGRY):
		_add("starvation_timer", -hours * 120)
		if _val("starvation_timer") <= 0 and _val("energy_level") < _raise_int("energy_threshold"):
			_add("care_mistakes", 1)
	else:
		_add("food_level", -hours * 60)
	_add("energy_level", -_raise_int("energy_usage"))
	if _cond(POOPY):
		_add("pooping_timer", -1200)
	else:
		_add("poop_level", -hours * 6)
	if _cond(SICK):
		_add("sickness_tries", hours)
	if _cond(INJURED):
		_add("injury_timer", hours)
	if _cond(SICK):
		_add("sickness_timer", hours)


## handlePraiseScold (:1113): partner state 4 = scold, 15 = praise.
func handle_praise_scold(state: int) -> bool:
	var old_discipline := _val("discipline")
	var old_happiness := _val("happiness")
	var discipline_delta := 0
	# Uninitialised in the C when ITEM_SCOLD_FLAG == 1 (specs/care.md §6): 0 here.
	var happiness_delta := 0
	if state == 4:
		if item_scold_flag == 1:
			discipline_delta = 8
			item_scold_flag = 2
		else:
			discipline_delta = 2
			happiness_delta = -10
		_put("refused_fav_food", 0)
		_flag(UNHAPPY, false)
		_set_butterfly(false)
	else:
		discipline_delta = -5
		happiness_delta = _val("discipline") / 10 + 2
	_add("discipline", discipline_delta)
	_add("happiness", happiness_delta)
	# NANIMON_TRIGGER (Rookie scolded at discipline 0 and happiness -100): the evolution step reads it.
	return state == 4 and _level() == 3 and old_discipline == 0 and old_happiness == -100


## handlePostBattleTiredness (:2040). Quirk kept: the MP factor is computed as
## (diff / max_mp) * 10, which is 0 unless all MP is used.
func handle_post_battle_tiredness() -> void:
	_add("tiredness", 5)
	var stats: Dictionary = game_state.state["partner"]["stats"]
	var max_mp := int(stats["base"]["max_mp"])
	var mp := int(stats["current"]["mp"])
	var diff := max_mp * 2 / 10
	if mp < max_mp - diff and max_mp > 0:
		diff = max_mp - mp
		_add("tiredness", (diff / max_mp) * 10)
	_add("food_level", -15)


func _call_script(section: int) -> void:
	script_running = true
	script_requested.emit(section)
