class_name Evolution
extends RefCounted
## Evolution's rules (specs/evolution.md): when and into what the partner evolves (evolution.c,
## tickConditions' end, handleSpecialEvolutions, handleEvoItems) and what evolving does to it
## (EVL_applyEvolution). The literals of the C are records of evolution/rules (GameData
## .evolution_rules); the requirements, paths and gains are the evolution tables. Starting an
## evolution sets Care.evolution_target and puts the tamer in state 6 and the partner in state 13,
## whose scene (EvolutionScene) calls apply_evolution.

const MIN_SCORE := 3
## calculateRequirementScore: the weight within ± 5.
const WEIGHT_RANGE := 5
const LEVEL_ROOKIE := 3
const LEVEL_CHAMPION := 4
const LEVEL_ULTIMATE := 5
## tickConditions: a Champion at evo_timer 360 tries the special evolutions of mode 3.
const SPECIAL_HOUR := 360
const MODE_WAKE_UP := 2
const MODE_PRAISE_SCOLD := 3
## EVL_clampBaseStats.
const MAX_HP_MP := 9999
const MAX_STAT := 999
## EVL_applyEvolution: a new Ultimate (no item used) lives 96 hours more.
const ULTIMATE_LIFETIME := 96
## addTamerLevel(chance, 1) for a new Champion / Ultimate when no script runs.
const TAMER_LEVEL_CHANCE := {LEVEL_CHAMPION: 20, LEVEL_ULTIMATE: 100}
## The partner's base stats in C order (hp, mp, off, def, speed, brain), their names in the
## requirement / gain records, and the Sukamon backups.
const BASE := ["max_hp", "max_mp", "offense", "defense", "speed", "brains"]
const REQ := ["hp", "mp", "offense", "defense", "speed", "brain"]
const BACKUP := ["suka_backup_hp", "suka_backup_mp", "suka_backup_off", "suka_backup_def", "suka_backup_speed",
		"suka_backup_brain"]

var game_state: Node
var data: Node
var care: Care
var clock: Clock
## IS_SCRIPT_PAUSED (the tamer level of a new Champion / Ultimate); null: no script runs.
var script_ctx: ScriptContext
## HAS_USED_EVOITEM: set by an evolution item, cleared only when the game starts
## (initializeStatusObjects at boot), never saved. Every later evolution of the session gets no
## gains (specs/evolution.md §2.5, §6).
var used_item := false


# --- helpers -------------------------------------------------------------------------------------

func _care() -> Dictionary:
	return game_state.state["partner"]["care"]


func _base() -> Dictionary:
	return game_state.state["partner"]["stats"]["base"]


func _partner_id() -> int:
	return _id(game_state.state["partner"]["digimon"])


func _id(ref: Variant) -> int:
	return data.id_of("digimon/digimon_data", ref) if ref is String else int(ref)


func _level_of(digimon: Variant) -> int:
	return int(data.digimon(digimon).get("level", {}).get("id", 0))


func _ref_id(ref: Variant) -> int:
	return int(ref["id"]) if ref is Dictionary else -1


## The partner's base stat i (C order); HP and MP / 10 where the requirements compare them.
func _stat(i: int, scaled := false) -> int:
	var v := int(_base()[BASE[i]])
	return v / 10 if scaled and i < 2 else v


## The first rule record of a kind, or {}.
func _rule(kind: String) -> Dictionary:
	var rules: Array = data.evolution_rules(kind)
	return rules[0] if not rules.is_empty() else {}


## The Digimon the virus bar turns the partner into (rules `virus`), -1 without the rule.
func _virus_target() -> int:
	return _ref_id(_rule("virus").get("target"))


## tamerSetState(6) + partnerSetState(13) with EVOLUTION_TARGET set.
func _start(target: int) -> void:
	care.evolution_target = target
	if care.tamer != null:
		care.tamer.set_state(Tamer.STATE_STILL)
	if care.partner != null:
		care.partner.set_state(Partner.STATE_EVOLVING)


# --- the target selection (evolution.c:674-1050) -------------------------------------------------

## getFreshEvolutionTarget: the fixed target (rules `fresh_target`); evo_timer = 0. -1 for a Fresh
## without one (the C returns an uninitialised value).
func fresh_target(digimon: Variant) -> int:
	var id := _id(digimon)
	var result := -1
	for rule in data.evolution_rules("fresh_target"):
		if _ref_id(rule["from"]) == id:
			result = _ref_id(rule["target"])
	_care()["evo_timer"] = 0
	return result


## The evolution candidates of a Digimon (EVOLUTION_PATHS.to, in order).
func _candidates(digimon: Variant) -> Array:
	return data.evolution_paths(_id(digimon)).get("to", [])


## getInTrainingEvolutionTarget: the highest score >= 3; the first wins a tie.
func in_training_target(digimon: Variant) -> int:
	var current := _id(digimon)
	var best := -1
	var best_score := 0
	for target in _candidates(current):
		var score := requirement_score(current, int(target), best)
		if best_score < score and score >= MIN_SCORE:
			best = int(target)
			best_score = score
	return best


## getRookieEvolutionTarget: _best_average, then the fallback of the partner's level (rules
## `fallback`: a Rookie at evo_timer 96 -> Numemon).
func rookie_target(digimon: Variant) -> int:
	var best := _best_average(digimon)
	if best == -1:
		var level := _level_of(digimon)
		for rule in data.evolution_rules("fallback"):
			if int(rule["level"]) == level and int(_care()["evo_timer"]) >= int(rule["evo_timer_at_least"]):
				best = _ref_id(rule["target"])
	return best


## getChampionEvolutionTarget.
func champion_target(digimon: Variant) -> int:
	return _best_average(digimon)


## The Rookie / Champion selection: among the candidates with a score >= 3, the highest average
## of the stats their requirements name. Quirk kept: the sum and count are reset only when a
## candidate becomes the best, so a candidate that doesn't win leaves its average (already
## divided) and its count to the next one. The best starts at 0: an average of 0 never wins.
func _best_average(digimon: Variant) -> int:
	var current := _id(digimon)
	var best := -1
	var best_score := 0
	var total := 0
	var count := 0
	for target in _candidates(current):
		if requirement_score(current, int(target), best) < MIN_SCORE:
			continue
		var stats: Dictionary = data.evolution_requirements(int(target)).get("stats", {})
		for i in REQ.size():
			# A minimum (a number) or a marked Rookie stat (true); null / false: not named.
			var v = stats.get(REQ[i])
			if v != null and not (v is bool and not v):
				total += _stat(i, true)
				count += 1
		# statTotal /= statCount: no record has a score >= 3 without a stat (a 0 count keeps the sum).
		if count > 0:
			total /= count
		if best_score < total:
			best = int(target)
			best_score = total
			total = 0
			count = 0
	return best


## calculateRequirementScore (evolution.c:928): a point each for the care mistakes, the weight,
## the stats and one bonus; then the "raised" adjustment against the current best.
func requirement_score(current: int, target: int, best: int) -> int:
	var req: Dictionary = data.evolution_requirements(target)
	var c := _care()
	var points := 0
	var care_mistakes: Dictionary = req.get("care_mistakes", {})
	var care_value := int(care_mistakes.get("value", -1))
	if care_mistakes.get("at_most", false):
		if int(c["care_mistakes"]) <= care_value:
			points += 1
	elif int(c["care_mistakes"]) >= care_value:
		points += 1
	var weight_value = req.get("weight", {}).get("value") if req.get("weight") is Dictionary else null
	var w := -1 if weight_value == null else int(weight_value)
	if w - WEIGHT_RANGE <= int(c["weight"]) and int(c["weight"]) <= w + WEIGHT_RANGE:
		points += 1
	var stats: Dictionary = req.get("stats", {})
	if req.get("stat_rule") == "highest":
		# The partner's highest stat (HP and MP / 10); with equal values the last one.
		var highest := 0
		for i in REQ.size():
			var is_highest := true
			for j in REQ.size():
				if _stat(i, true) < _stat(j, true):
					is_highest = false
			if is_highest:
				highest = i
		if stats.get(REQ[highest]) == true:
			points += 1
	else:
		var all_met := true
		for i in REQ.size():
			var v = stats.get(REQ[i])
			if v != null and _stat(i, true) < int(v):
				all_met = false
		if all_met:
			points += 1
	if _bonus(req.get("bonus", {}), current):
		points += 1
	if points >= MIN_SCORE and best != -1:
		var target_raised: bool = game_state.is_raised(_gains_target(target))
		var best_raised: bool = game_state.is_raised(_gains_target(best))
		if target_raised and not best_raised:
			points = 0
		if not target_raised and best_raised:
			points += 1
	return points


func _bonus(bonus: Dictionary, current: int) -> bool:
	var c := _care()
	var met := false
	if bonus.get("from_digimon") != null and current == int(bonus["from_digimon"]):
		met = true
	if bonus.get("discipline") != null and int(c["discipline"]) >= int(bonus["discipline"]):
		met = true
	if bonus.get("happiness") != null and int(c["happiness"]) >= int(bonus["happiness"]):
		met = true
	var battles = bonus.get("battles")
	if battles is Dictionary:
		if battles.get("at_most", false):
			if int(c["battles"]) <= int(battles["value"]):
				met = true
		elif int(c["battles"]) >= int(battles["value"]):
			met = true
	if bonus.get("techs") != null and mastered_moves() >= int(bonus["techs"]):
		met = true
	return met


## EVOLUTION_STATS_GAINS[id].targetDigimon.
func _gains_target(id: int) -> int:
	return int(data.evolution_gains(id).get("target", id))


## getNumMasteredMoves: the learned-move bits (one per learned technique).
func mastered_moves() -> int:
	return game_state.state["partner"]["learned_moves"].size()


# --- handleSpecialEvolutions (evolution.c:852) ---------------------------------------------------

## The special evolutions of `mode` (rules `special`, in order; later ones overwrite earlier
## ones), with one roll: only with the tamer in state 0. A result starts the evolution at once.
func special_evolution(mode: int) -> int:
	if care.tamer != null and care.tamer.state != Tamer.STATE_FREE:
		return -1
	var type := _partner_id()
	var level := _level_of(type)
	var c := _care()
	var roll := Rng.random_limit(100)
	var target := -1
	for rule in data.evolution_rules("special"):
		if int(rule["mode"]) != mode:
			continue
		if rule.get("chance") != null and roll >= int(rule["chance"]):
			continue
		var from: Array = rule.get("from", [])
		if not from.is_empty() and not from.any(func(f): return _ref_id(f) == type):
			continue
		if not _special_conditions(rule.get("conditions", {}), level, c):
			continue
		target = _ref_id(rule["target"])
		if rule.get("conditions", {}).get("nanimon_trigger", false):
			care.nanimon_trigger = false
	if target != -1:
		_start(target)
	return target


func _special_conditions(conditions: Dictionary, level: int, c: Dictionary) -> bool:
	for key in conditions:
		var want = conditions[key]
		match key:
			"discipline", "happiness", "tiredness":
				if int(c[key]) != int(want):
					return false
			"evo_timer":
				if int(c["evo_timer"]) != int(want):
					return false
			"evo_timer_at_least":
				if int(c["evo_timer"]) < int(want):
					return false
			"battles_at_least":
				if int(c["battles"]) < int(want):
					return false
			"defense_at_least":
				if int(_base()["defense"]) < int(want):
					return false
			"level":
				if level != int(want):
					return false
			"map":
				if data.id_of("systems/maps", game_state.state["world"]["screen"]) != _ref_id(want):
					return false
			"nanimon_trigger":
				if care.nanimon_trigger != bool(want):
					return false
			_:
				push_error("Evolution: unknown special condition %s" % key)
				return false
	return true


# --- tickConditions' end (partner_impl.c:2106-2149) -------------------------------------------------

## The hourly check, after the hour's care: the timed evolution (partner state 1, tamer state 0;
## the clock advanced this frame: Care calls it only then), the virus bar, then state 13 for any
## target.
func hourly_check() -> void:
	var c := _care()
	var type := _partner_id()
	var level := _level_of(type)
	var evo_timer := int(c["evo_timer"])
	var tamer_free := care.tamer == null or care.tamer.state == Tamer.STATE_FREE
	var partner_normal := care.partner == null or care.partner.state == Partner.STATE_NORMAL
	if partner_normal and tamer_free:
		for rule in data.evolution_rules("hours"):
			if int(rule["level"]) != level or evo_timer < int(rule["evo_timer_at_least"]):
				continue
			match str(rule["select"]):
				"fixed":
					care.evolution_target = fresh_target(type)
				"best_score":
					care.evolution_target = in_training_target(type)
				"best_average":
					# getRookieEvolutionTarget / getChampionEvolutionTarget: the fallback rules are per level.
					care.evolution_target = rookie_target(type)
			break
		if level == LEVEL_CHAMPION and evo_timer == SPECIAL_HOUR:
			care.evolution_target = special_evolution(MODE_PRAISE_SCOLD)
	var virus := _rule("virus")
	if not virus.is_empty() and int(c["virus_bar"]) >= int(virus["bar_at_least"]) and type != _ref_id(virus["target"]):
		care.evolution_target = _ref_id(virus["target"])
		game_state.set_script_value(int(virus["backup_value"]), type)
		for i in BASE.size():
			c[BACKUP[i]] = int(_base()[BASE[i]])
		c["virus_bar"] = 0
	if care.evolution_target != -1 and (care.partner == null or care.partner.state != Partner.STATE_EVOLVING):
		_start(care.evolution_target)


# --- handleEvoItems (item.c:2190) ------------------------------------------------------------------

## An evolution item: its target (evolution/item_targets); a target with needs_level only when the
## partner is at that level (target level - 1). Sets HAS_USED_EVOITEM and starts the evolution.
## The caller removes the item. False when nothing happens.
func item_evolution(item: Variant) -> bool:
	var entry: Dictionary = data.evolution_item_target(item)
	var target := _ref_id(entry.get("target"))
	if target < 0:
		return false
	if entry.get("needs_level") != null and _level_of(target) - 1 != _level_of(_partner_id()):
		return false
	used_item = true
	_start(target)
	return true


# --- EVL_applyEvolution (evl.c:1332) -------------------------------------------------------------

## Applies the evolution into `target`: stats, care, the new technique, the new Digimon in the game
## state (the field swaps the model), the raised mark, evo_timer on a level change. Returns the new
## Digimon's key.
func apply_evolution(target: int) -> String:
	var gains: Dictionary = data.evolution_gains(target)
	var new_id := int(gains.get("target", target))
	var old_type := _partner_id()
	var old_level := _level_of(old_type)
	var level := _level_of(target)
	var scaled: bool = level < LEVEL_ROOKIE or old_type == _virus_target() \
			or data.evolution_rules("scaled_target").any(func(r): return _ref_id(r["target"]) == target)
	if scaled:
		scale_base_stats(roundi(float(gains.get("scale", 1.0)) * 10))
	elif not used_item:
		var g: Dictionary = gains.get("gains", {})
		var base := _base()
		for i in BASE.size():
			var s := int(base[BASE[i]])
			var gain := int(g.get(REQ[i], 0))
			base[BASE[i]] = s + gain / 10 if s >= gain else (gain + s) / 2
		clamp_base_stats()
		if script_ctx == null or script_ctx.is_paused:
			var new_level := _level_of(new_id)
			if TAMER_LEVEL_CHANCE.has(new_level) and clock != null:
				clock.add_tamer_level(TAMER_LEVEL_CHANCE[new_level], 1)
	var c := _care()
	c["weight"] = int(data.raise_data(new_id).get("default_weight", 0))
	c["care_mistakes"] = 0
	c["battles"] = 0
	if _level_of(new_id) == LEVEL_ULTIMATE and not used_item:
		c["remaining_lifetime"] = int(c["remaining_lifetime"]) + ULTIMATE_LIFETIME
	_learn_technique(new_id)
	# initializeEvolvedPartner: the new Digimon, condition 0, its sleep times and care reset.
	var key: String = data.key_of("digimon/digimon_data", new_id)
	game_state.state["partner"]["digimon"] = key
	c["condition"] = 0
	care.set_sleep_times()
	care.reset_partner_para()
	care.has_immortal_hour = false
	care.immortal_hour = -1
	game_state.set_raised(new_id)
	if old_level != _level_of(new_id):
		c["evo_timer"] = 0
	game_state.changed.emit("partner")
	return key


## The new technique: in the block of the new Digimon's first element (rules `technique_block`,
## first..last inclusive), the candidate of lowest non-zero power, starting from the first; learnt
## and equipped in slot 0 (below Rookie: the first move slot); slots 1, 2 empty; slot 3 the last
## finisher.
func _learn_technique(new_id: int) -> void:
	var record: Dictionary = data.digimon(new_id)
	var slots: Array = record.get("moves", [])
	var elements: Array = record.get("elements", [])
	var element := _ref_id(elements[0]) if not elements.is_empty() else -1
	var first := 0
	var last := -1
	for rule in data.evolution_rules("technique_block"):
		if _ref_id(rule["element"]) == element:
			first = int(rule["first"])
			last = int(rule["last"])
	var candidates := []
	for slot in slots:
		var id := _ref_id(slot.get("move"))
		if id >= first and id <= last:
			candidates.append(id)
	var moves: Array = _base()["moves"]
	var best := -1
	if not candidates.is_empty():
		best = int(candidates[0])
		for id in candidates:
			var power := int(data.move(id).get("power", 0))
			if int(data.move(best).get("power", 0)) > power and power != 0:
				best = id
		game_state.learn_move(best)
	moves[0] = data.key_of("moves/move_data", best) if best >= 0 else null
	moves[1] = null
	moves[2] = null
	if _level_of(new_id) < LEVEL_ROOKIE:
		moves[0] = data.key_of("moves/move_data", _ref_id(slots[0].get("move"))) if not slots.is_empty() else null
	moves[3] = null
	for k in range(slots.size() - 1, -1, -1):
		var move: Dictionary = data.move(_ref_id(slots[k].get("move")))
		if move.get("category") == "finisher":
			moves[3] = move.get("key")
			break


## EVL_scaleBaseStats: nothing after an evolution item; each stat × pct / 10, or from Sukamon the
## backup formula (virus_bar = 0); then the clamp and the current HP / MP cut.
func scale_base_stats(pct: int) -> void:
	if used_item:
		return
	var base := _base()
	var c := _care()
	if _partner_id() != _virus_target():
		for name in BASE:
			base[name] = int(base[name]) * pct / 10
	else:
		for i in BASE.size():
			var backup := int(c[BACKUP[i]])
			base[BASE[i]] = backup + (int(base[BASE[i]]) - backup / 2) / 2
		c["virus_bar"] = 0
	clamp_base_stats()
	var current: Dictionary = game_state.state["partner"]["stats"]["current"]
	current["hp"] = mini(int(current["hp"]), int(base["max_hp"]))
	current["mp"] = mini(int(current["mp"]), int(base["max_mp"]))


## EVL_clampBaseStats: HP / MP at most 9999, the others 999.
func clamp_base_stats() -> void:
	var base := _base()
	for i in BASE.size():
		var limit := MAX_HP_MP if i < 2 else MAX_STAT
		if int(base[BASE[i]]) > limit:
			base[BASE[i]] = limit
