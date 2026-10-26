class_name Training
extends RefCounted
## The training core (trn/trn_reward.c, trn/trn_hud.c, tamer.c:1342; specs/training.md §2.3-2.5):
## the gains of a session and their multiplier, the hour it costs, the copy of the base stats the
## stats box counts into, and TRAINING_COMPLETE, which builtin 0x07 waits for. The stations
## (TrainingStation) run the scenes and call it; TrainingStatsBox draws the box.

## The GameState script, for its condition bits (its autoload name isn't there in -s tests).
const State := preload("res://scripts/state/game_state.gd")
## INITIAL_COMBAT_STATS[0] / STATS_GAINS order, and the partner's base stat fields.
const STATS := ["max_hp", "max_mp", "offense", "defense", "speed", "brains"]
const HP := 0
const MP := 1
const OFFENSE := 2
const DEFENSE := 3
const SPEED := 4
const BRAINS := 5
## TRN_calculateTrainingMultiplier's modes (the stat trained) and the upgrade counter of each.
const MODE_HP := 0
const MODE_MP := 1
const MODE_OFFENSE := 2
const MODE_DEFENSE := 3
const MODE_SPEED := 4
const MODE_BRAINS := 5
## Script value 0xFE, the stat a station trains (builtin 0x07, script_interp.c:1705-1722): not the
## multiplier's mode numbers.
const STAT_HP := 0
const STAT_OFFENSE := 1
const STAT_SPEED := 2
const STAT_DEFENSE := 3
const STAT_MP := 4
const STAT_BRAINS := 5
## The mode of each script stat (the order of STAT_*), and the mode names of the data tables
## (training_spots, slot_machine).
const STAT_MODES := [MODE_HP, MODE_OFFENSE, MODE_SPEED, MODE_DEFENSE, MODE_MP, MODE_BRAINS]
const MODE_NAMES := ["hp", "mp", "offense", "defense", "speed", "brain"]
const UPGRADE_COUNTERS := ["upgrade_hp_counter", "upgrade_mp_counter", "upgrade_off_counter",
		"upgrade_defense_counter", "upgrade_speed_counter", "upgrade_brain_counter"]
## The gyms' "revision" upgrades: × 6 / 5 for modes 0, 3, 4 (0xDB) and 2, 1, 5 (0xFB).
const TRIGGER_REVISION_A := 0xDB
const TRIGGER_REVISION_B := 0xFB
## getItemCount(0x21) > 0, the Trn. manual: its passive effect.
const MANUAL_EFFECT := "training_boost"
## PartnerPara.trainBoostFlag bits (a boost item's stats; trainBoostValue is its percent factor).
const BOOST_OFFENSE := 0x01
const BOOST_DEFENSE := 0x02
const BOOST_SPEED := 0x04
const BOOST_BRAINS := 0x08
const BOOST_HP := 0x10
const BOOST_MP := 0x20
const TIRED_MAX := 100
const GAIN_CAP := 999
## TRN_advanceTrainingTime: tiredness from 70 costs happiness and discipline; the day rolls over at
## 31 here (not 30 as advanceToTime: kept).
const TIRED_PENALTY_FROM := 0x46
const FRAMES_PER_HOUR := 1200
const FRAMES_PER_DAY := 0x7080
const DAY_ROLLOVER := 0x1F
const YEARS := 100
const HAPPY_LIFETIME := 0x50
const STAT_CAP_HP := 9999
const STAT_CAP := 999
## TRN_awardBrainsTrainingGains: the Brains that bring new orders (each with its line(s) of
## text/trn/trn_reward), and those that may teach a technique (TRN_tryLearnMove), or exactly 999.
const ORDER_THRESHOLDS := [[100, ["TRN_D_8008F0D8"]], [200, ["TRN_D_8008F0F0"]],
		[300, ["TRN_D_8008F100", "TRN_D_8008F10C"]], [400, ["TRN_D_8008F11C"]], [500, ["TRN_D_8008F12C"]]]
const LEARN_THRESHOLDS := [150, 250, 350, 450, 550, 650, 750, 800, 850, 900, 950]
## TRN_tryLearnMove: 8 techniques per element in its training order; 0xFF = no element.
const LEARN_RANKS := 8
const NO_ELEMENT := 0xFF

var game_state: Node
var data: Node
var clock: Clock
var care: Care
## Opened by the awards (TRN_createPostTrainingStatsBox); null in the logic tests.
var stats_box: TrainingStatsBox
## Box 2 of the Brains award (new orders, a technique mastered); null in the logic tests.
var brains_box: TrainingBrainsBox

## The Bonus Try's session (4d-3); TrainingRoutines ticks it after the station. Its `box` is the
## slot machine's UI part, set when the box exists.
var slot_session := SlotSession.new()

## TRAINING_COMPLETE.
var complete := false
## TRN_CURRENT_FRAME / HOUR / MINUTE.
var start_frame := 0
var start_hour := 0
var start_minute := 0
## INITIAL_COMBAT_STATS[0] and STATS_GAINS.
var base: Array[int] = [0, 0, 0, 0, 0, 0]
var gains: Array[int] = [0, 0, 0, 0, 0, 0]


## The multiplier's mode of a script stat (value 0xFE).
static func mode_of_stat(stat_id: int) -> int:
	return STAT_MODES[stat_id]


## isTrainingComplete: true once, after a station finished.
func is_training_complete() -> bool:
	if complete:
		complete = false
		return true
	return false


func _care() -> Dictionary:
	return game_state.state["partner"]["care"]


func _clock() -> Dictionary:
	return game_state.state["clock"]


static func _s16(value: int) -> int:
	value &= 0xFFFF
	return value - 0x10000 if value >= 0x8000 else value


## TRN_saveTrainingStartTime.
func save_start_time() -> void:
	start_frame = int(_clock()["frame"])
	start_hour = int(_clock()["hour"])
	start_minute = int(_clock()["minute"])


## TRN_saveBaseStats.
func save_base_stats() -> void:
	var stats: Dictionary = game_state.state["partner"]["stats"]["base"]
	for i in STATS.size():
		base[i] = int(stats[STATS[i]])


## TRN_applyBaseStats.
func apply_base_stats() -> void:
	var stats: Dictionary = game_state.state["partner"]["stats"]["base"]
	for i in STATS.size():
		stats[STATS[i]] = base[i]
	game_state.changed.emit("partner")


## TRN_statGainsAreZero.
func gains_are_zero() -> bool:
	for g in gains:
		if g != 0:
			return false
	return true


## The cap of a stat (HP, MP 9999; the others 999).
static func stat_cap(i: int) -> int:
	return STAT_CAP_HP if i < 2 else STAT_CAP


## The Digimon's raise data (training_type) and level.
func _training_type(digimon: Variant) -> int:
	return int(data.entity("digimon", digimon).get("care", {}).get("raise", {}).get("training_type", 0))


func _level(digimon: Variant) -> int:
	var level = data.digimon(digimon).get("level", {})
	return int(level.get("id", 0)) if level is Dictionary else int(level)


## The first factor of TRN_calculateTrainingMultiplier: the mode against the training type.
static func type_factor(mode: int, training_type: int) -> int:
	match mode:
		MODE_HP, MODE_DEFENSE:
			if training_type == 0 or training_type == 1:
				return 10
			return 9 if training_type == 2 else (11 if training_type == 3 else 8)
		MODE_MP, MODE_BRAINS:
			if training_type == 0 or training_type == 3:
				return 10
			return 9 if training_type == 1 else (11 if training_type == 2 else 8)
		MODE_OFFENSE, MODE_SPEED:
			if training_type == 0 or training_type == 2:
				return 10
			return 11 if training_type == 1 else (9 if training_type == 3 else 8)
	return 0


## TRN_calculateTrainingMultiplier (trn_reward.c:594): 10 is ×1.
func multiplier(digimon: Variant, mode: int, flag: int) -> int:
	var num := type_factor(mode, _training_type(digimon))
	var den := 10
	var level := _level(digimon)
	if level == 1 or level == 2:
		num *= 9
	elif level == 3:
		num *= 10
	elif level == 4:
		num *= 11
	else:
		num *= 12
	den *= 10
	if flag == 0:
		if mode in [MODE_HP, MODE_DEFENSE, MODE_SPEED] and game_state.is_trigger_set(TRIGGER_REVISION_A):
			num = num * 6
			den = den * 5
		if mode in [MODE_OFFENSE, MODE_MP, MODE_BRAINS] and game_state.is_trigger_set(TRIGGER_REVISION_B):
			num = num * 6
			den = den * 5
		if int(_care()[UPGRADE_COUNTERS[mode]]) >= 10:
			num = num * 6
			den = den * 5
	if game_state.has_passive_item(MANUAL_EFFECT):
		num = num * 11
		den = den * 10
	return _s16((num * 10) / den)


## One gain: `amount × v × trainBoostValue / 100` when the boost covers it, else `amount × v / 10`.
func _boosted(amount: int, v: int, boost_bit: int) -> int:
	var care := _care()
	if int(care["train_boost_flag"]) & boost_bit:
		return _s16((amount * (v * int(care["train_boost_value"]))) / 100)
	return _s16((amount * v) / 10)


## TRN_awardHpTrainingGains (trn_reward.c:151): HP 80 and Offense 2, scaled; tiredness + 10,
## energy and happiness - 1.
func award_hp_gains(digimon: Variant, b: int, c: int) -> void:
	var v := multiplier(digimon, MODE_HP, b)
	var hp := _gain(80, v, BOOST_HP, c)
	var offense := _gain(2, v, BOOST_OFFENSE, c)
	if _tired():
		hp = 1
		offense = 1
	if hp >= 1000:
		hp = GAIN_CAP
	_award([hp, 0, offense, 0, 0, 0], 10, 1, 1)


## A gain boosted, then scaled by the slot result `c` (10 = × 1).
func _gain(amount: int, v: int, boost_bit: int, c: int) -> int:
	return _s16((_boosted(amount, v, boost_bit) * c) / 10)


func _tired() -> bool:
	return int(_care()["tiredness"]) == TIRED_MAX


## TRN_awardOffenseTrainingGains (trn_reward.c:234): b 0 (the Green Gym) Offense 8 + Speed 2, b 6
## (Gear Savanna) HP 10 + Offense 8; tiredness + 9. Any other b gains and costs nothing.
func award_offense_gains(digimon: Variant, b: int, c: int) -> void:
	var hp := 0
	var offense := 0
	var speed := 0
	var costs := [0, 0, 0]
	match b:
		0:
			offense = 8
			speed = 2
			costs = [9, 1, 1]
		6:
			hp = 10
			offense = 8
			costs = [9, 1, 1]
	var v := multiplier(digimon, MODE_OFFENSE, b)
	hp = _gain(hp, v, BOOST_HP, c)
	offense = _gain(offense, v, BOOST_OFFENSE, c)
	speed = _gain(speed, v, BOOST_SPEED, c)
	if _tired():
		if b == 0:
			speed = 1
		else:
			hp = 1
		offense = 1
	_award([hp, 0, offense, 0, speed, 0], costs[0], costs[1], costs[2])


## TRN_awardSpeedTrainingGains (trn_reward.c:308): b 0 or 6, HP 10 + Speed 8; tiredness + 8.
func award_speed_gains(digimon: Variant, b: int, c: int) -> void:
	var hp := 0
	var speed := 0
	var costs := [0, 0, 0]
	if b == 0 or b == 6:
		hp = 10
		speed = 8
		costs = [8, 1, 1]
	var v := multiplier(digimon, MODE_SPEED, b)
	hp = _gain(hp, v, BOOST_HP, c)
	speed = _gain(speed, v, BOOST_SPEED, c)
	if _tired():
		hp = 1
		speed = 1
	if hp >= 1000:
		hp = GAIN_CAP
	_award([hp, 0, 0, 0, speed, 0], costs[0], costs[1], costs[2])


## TRN_awardDefenseTrainingGains (trn_reward.c:374): Defense 8 + Brains 2; tiredness + 9.
func award_defense_gains(digimon: Variant, b: int, c: int) -> void:
	var v := multiplier(digimon, MODE_DEFENSE, b)
	var defense := _gain(8, v, BOOST_DEFENSE, c)
	var brains := _gain(2, v, BOOST_BRAINS, c)
	if _tired():
		defense = 1
		brains = 1
	_award([0, 0, 0, defense, 0, brains], 9, 1, 1)


## TRN_awardMpTrainingGains (trn_reward.c:422): MP 80 + Defense 2; tiredness + 7.
func award_mp_gains(digimon: Variant, b: int, c: int) -> void:
	var v := multiplier(digimon, MODE_MP, b)
	var mp := _gain(80, v, BOOST_MP, c)
	var defense := _gain(2, v, BOOST_DEFENSE, c)
	if _tired():
		mp = 1
		defense = 1
	if mp >= 1000:
		mp = GAIN_CAP
	_award([0, mp, 0, defense, 0, 0], 7, 1, 1)


## TRN_awardBrainsTrainingGains (trn_reward.c:474): b 0 MP 10 + Brains 8, b 9 Brains 15; tiredness
## + 6. The multiplier is computed as MP's (mode 1), as in the C. Then the new orders, or a
## technique (TRN_tryLearnMove), by the Brains thresholds crossed.
func award_brains_gains(digimon: Variant, b: int, c: int) -> void:
	var before := int(game_state.state["partner"]["stats"]["base"]["brains"])
	var mp := 0
	var brains := 0
	var costs := [0, 0, 0]
	match b:
		0:
			mp = 10
			brains = 8
			costs = [6, 1, 1]
		9:
			brains = 15
			costs = [6, 1, 1]
	var v := multiplier(digimon, MODE_MP, b)
	mp = _gain(mp, v, BOOST_MP, c)
	brains = _gain(brains, v, BOOST_BRAINS, c)
	if _tired():
		if b == 0:
			mp = 1
		brains = 1
	if mp >= 1000:
		mp = GAIN_CAP
	if brains >= 1000:
		brains = GAIN_CAP
	_award([0, mp, 0, 0, 0, brains], costs[0], costs[1], costs[2])
	var total := _s16(before + brains)
	var orders := new_orders(before, total)
	if not orders.is_empty():
		if brains_box != null:
			brains_box.show_orders(orders)
	elif teaches_technique(before, total):
		var move := try_learn_move(digimon)
		if move >= 0 and brains_box != null:
			brains_box.show_mastered(move)


## The new orders crossed from `before` to `total`, in the C's order: an array of text id lists.
static func new_orders(before: int, total: int) -> Array:
	var found := []
	for t in ORDER_THRESHOLDS:
		if before < t[0] and total >= t[0]:
			found.append(t[1])
	return found


## Whether the Brains crossed a technique threshold, or are exactly 999.
static func teaches_technique(before: int, total: int) -> bool:
	for t in LEARN_THRESHOLDS:
		if before < t and total >= t:
			return true
	return total == GAIN_CAP


## TRN_tryLearnMove (trn_reward.c:811): per element slot, the first technique of its training
## order the partner lacks and has in its technique list; the best weighted one is learnt when its
## weight beats randomLimit(100). Returns its id, or -1.
func try_learn_move(digimon: Variant) -> int:
	var raw: Dictionary = data.digimon(digimon).get("c", {})
	var special: Array = raw.get("special", [])
	var slots: Array = raw.get("moves", [])
	var move_id := [-1, -1, -1]
	var weight := [-1, -1, -1]
	for i in mini(special.size(), 3):
		if int(special[i]) == NO_ELEMENT:
			continue
		var order: Array = data.training_learning(int(special[i])).get("moves", [])
		for k in mini(order.size(), LEARN_RANKS):
			var candidate := int(order[k]["move"]["id"])
			if game_state.has_move(candidate):
				continue
			for slot in slots:
				if int(slot) == candidate:
					move_id[i] = candidate
					weight[i] = data.training_learn_weight(k, i)
			if move_id[i] != -1 and weight[i] != -1:
				break
	var move: int = move_id[0]
	var best: int = weight[0]
	if best < weight[1]:
		move = move_id[1]
		best = weight[1]
	if best < weight[2]:
		move = move_id[2]
		best = weight[2]
	var r := Rng.random_limit(100)
	if best > r:
		game_state.learn_move(move)
		return move
	return -1


## The awards' common end: the copy, the gains, the box, the hour.
func _award(values: Array, tired: int, energy: int, happy: int) -> void:
	save_base_stats()
	for i in STATS.size():
		gains[i] = int(values[i])
	if stats_box != null:
		stats_box.create()
	advance_time(tired, energy, happy)


## TRN_advanceTrainingTime (trn_reward.c:721): the session costs exactly an hour from its start
## (the minute stays where the clock is), and that hour's care.
func advance_time(tired: int, energy: int, happy: int) -> void:
	var c := _care()
	c["tiredness"] = int(c["tiredness"]) + tired
	c["energy_level"] = int(c["energy_level"]) - energy
	c["happiness"] = int(c["happiness"]) - happy
	if int(c["tiredness"]) >= TIRED_PENALTY_FROM:
		c["happiness"] = int(c["happiness"]) - 3
		c["discipline"] = int(c["discipline"]) - 3
	var clock_state := _clock()
	clock_state["frame"] = start_frame + FRAMES_PER_HOUR
	clock_state["hour"] = start_hour + 1
	if int(clock_state["hour"]) >= 24:
		c["age"] = int(c["age"]) + 1
		clock_state["day"] = int(clock_state["day"]) + 1
		if clock != null:
			clock.daily_update()
		clock_state["hour"] = int(clock_state["hour"]) - 24
		clock_state["frame"] = int(clock_state["frame"]) - FRAMES_PER_DAY
		if int(clock_state["day"]) >= DAY_ROLLOVER:
			clock_state["day"] = 0
			clock_state["year"] = int(clock_state["year"]) + 1
			if int(clock_state["year"]) >= YEARS:
				clock_state["year"] = 0
		if clock != null:
			clock.day_passed.emit()
	var hour := int(clock_state["hour"])
	# updateMinuteHand: the HUD clock follows the state.
	game_state.changed.emit("clock")
	if hour % 4 == 0 and int(c["happiness"]) < HAPPY_LIFETIME:
		c["remaining_lifetime"] = int(c["remaining_lifetime"]) - ((int(c["happiness"]) - HAPPY_LIFETIME) / -50 + 1)
	if clock != null:
		if hour == 16:
			clock.initialize_daytime_transition(Clock.TIME_EVENING)
		elif hour == 20:
			clock.initialize_daytime_transition(Clock.TIME_NIGHT)
		elif hour == 6:
			clock.initialize_daytime_transition(Clock.TIME_DAY)
	_hourly_care(c)
	if care != null:
		care.tick_condition_boundaries()
	game_state.changed.emit("partner")


## The hour's care of TRN_advanceTrainingTime (trn_reward.c:766-801).
func _hourly_care(c: Dictionary) -> void:
	var condition := int(c["condition"])
	var raise: Dictionary = data.entity("digimon", game_state.state["partner"]["digimon"]).get("care", {}).get("raise", {})
	if condition & State.CONDITION_SLEEPY:
		c["sickness_counter"] = int(c["sickness_counter"]) + 1
		c["missed_sleep_hours"] = int(c["missed_sleep_hours"]) + 1
	if condition & State.CONDITION_HUNGRY:
		c["starvation_timer"] = int(c["starvation_timer"]) - 0x78
		if int(c["starvation_timer"]) <= 0 and int(c["energy_level"]) < int(raise.get("energy_threshold", 0)):
			c["care_mistakes"] = int(c["care_mistakes"]) + 1
	else:
		c["food_level"] = int(c["food_level"]) - 0x3C
	c["energy_level"] = int(c["energy_level"]) - int(raise.get("energy_usage", 0))
	if condition & State.CONDITION_POOPY:
		c["pooping_timer"] = int(c["pooping_timer"]) - 0x4B0
	else:
		c["poop_level"] = int(c["poop_level"]) - 6
	c["remaining_lifetime"] = maxi(int(c["remaining_lifetime"]) - 1, 0)
	c["evo_timer"] = int(c["evo_timer"]) + 1
	if condition & State.CONDITION_INJURED:
		c["injury_timer"] = int(c["injury_timer"]) + 1
	if condition & State.CONDITION_SICK:
		c["sickness_timer"] = int(c["sickness_timer"]) + 1


## TRN_createCloudFXLine (trn_reward.c:127): every `b` frames, `n` clouds along a line that moves
## out with the pushes. `create` is func(x, z).
static func cloud_line(a: int, b: int, x: int, z: int, dx: int, dz: int, n: int, create: Callable) -> void:
	if a % b != 0:
		return
	var d := (mini(a, 1200) / 120) * b
	for i in n:
		var r := Rng.random_limit(100)
		create.call(x + d - r, z + d - r)
		x += dx
		z += dz
