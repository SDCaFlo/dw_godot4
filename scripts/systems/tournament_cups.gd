class_name TournamentCups
extends RefCounted
## Tournament cup logic (specs/tournament_entry.md §4.2, §4.3, §4.9, §4.10): requirements, board
## packing, opponent draw, results and medals. Every method names the C function it reproduces.
## The cup data comes from scripts/tournament_cups.json via GameData.tournament_cup.

## dget.c:371 TRIGGER_OGRE_FORTRESS_OPENED (triggers 200..311 for Digimon 0..0x6F).
const ROSTER_TRIGGER := 200
## utils2.c:617; dget.c:385 (200..311).
const ROSTER_SIZE := 0x70
## dget.c:109.
const BOARD_DAYS := 5
## dget.c:111.
const BOARD_SLOTS := 6
## dget.c:138.
const ELIGIBLE := 0x80
## dget.c:141.
const OVERLEVELED := 0x40
## dget.c:138 (id & 0x3F).
const ID_MASK := 0x3F
## dget.c:672 (memset(DGET_BUFFER, 0xff, TOURNAMENT_ARRAY_SIZE): an empty cell).
const EMPTY := 0xFF
## dget.c:125 (minutesOfDay() <= 600, today enterable until 10:00).
const TODAY_UNTIL := 600
## utils2.c:586 (7 opponents drawn).
const OPPONENTS := 7
## trigger.h:827 TRIGGER_TOURNAMENT_REGISTERED; utils2.c:664.
const TRIGGER_REGISTERED := 37
## unlockMedal / hasMedal (script_common.c:3026, :3033): a medal is trigger 0x16C + medal.
const TRIGGER_MEDAL_BASE := 0x16C
## utils2.c:673 (enforceStatsLimits 0x11, TOURNAMENTS_WON limit).
const STAT_LIMIT_WON := 0x11
## utils2.c:679 (enforceStatsLimits 0x12, TOURNAMENT_WINS limit).
const STAT_LIMIT_WINS := 0x12
## utils2.c:680 (enforceStatsLimits 0x13, TOURNAMENTS_LOST limit).
const STAT_LIMIT_LOST := 0x13
## utils2.c:681 (writePStat(0xff, result)).
const SCRIPT_VALUE_RESULT := 0xFF

var game_state: Node
var game_data: Node


func _init(p_game_state: Node, p_game_data: Node) -> void:
	game_state = p_game_state
	game_data = p_game_data


## isTournamentEnabled (dget.c:350-427): whether the cup is held based on roster progress.
func is_enabled(id: int) -> bool:
	var cup: Dictionary = game_data.tournament_cup(id)
	if cup.is_empty():
		return false

	var req: Dictionary = cup.get("requirement", {})
	var min_roster: int = int(req.get("min_roster", 0))
	if min_roster == 0:
		return true

	var opponents = cup.get("opponents")
	var count := 0
	if opponents != null:
		for opp in opponents:
			if game_state.is_trigger_set(ROSTER_TRIGGER + int(opp)):
				count += 1
	else:
		for i in range(ROSTER_SIZE):
			if game_state.is_trigger_set(ROSTER_TRIGGER + i):
				count += 1

	if count < min_roster:
		return false

	var also: Dictionary = req.get("also", {})
	var req_type: String = str(also.get("type", "none"))
	match req_type:
		"none":
			return true
		"won":
			var target_cup: int = int(also.get("tournament", -1))
			var won_trig: int = int(game_data.tournament(target_cup).get("won_trigger", -1))
			return won_trig >= 0 and game_state.is_trigger_set(won_trig)
		"count":
			var wins_count := 0
			var list: Array = also.get("list", [])
			var min_wins: int = int(also.get("min", 0))
			for b_id in list:
				if game_state.is_trigger_set(ROSTER_TRIGGER + int(b_id)):
					wins_count += 1
			return wins_count >= min_wins
		"count_until":
			var until: int = int(also.get("until", 0))
			var min_wins: int = int(also.get("min", 0))
			var wins_count := 0
			if opponents != null:
				for opp in opponents:
					var num := int(opp)
					if num > until:
						break
					if game_state.is_trigger_set(ROSTER_TRIGGER + num):
						wins_count += 1
			return wins_count >= min_wins
		_:
			return false


## tournamentCheckEligible (dget.c:429-446): whether partner is in list 3 (eligible).
func is_eligible(id: int, digimon_type: int) -> bool:
	var cup: Dictionary = game_data.tournament_cup(id)
	var eligible: Array = cup.get("eligible", [])
	for entry in eligible:
		if int(entry) == digimon_type:
			return true
	return false


## tournamentCheckFair (dget.c:331-348): whether partner is in list 2 (over-levelled).
func is_overleveled(id: int, digimon_type: int) -> bool:
	var cup: Dictionary = game_data.tournament_cup(id)
	var overleveled: Array = cup.get("overleveled", [])
	for entry in overleveled:
		if int(entry) == digimon_type:
			return true
	return false


## fillEnabledTournamentTable (dget.c:101-145): 30-byte board table with 0x80/0x40 bits.
func fill_board(day: int, minutes: int, digimon_type: int) -> PackedByteArray:
	var table := PackedByteArray()
	table.resize(BOARD_DAYS * BOARD_SLOTS)
	table.fill(EMPTY)

	for j in range(BOARD_DAYS):
		var scheduled_cups: Array = game_data.tournaments_on_day(day + j)
		var out_slot := 0
		for t in scheduled_cups:
			var t_id := int(t)
			if t_id == EMPTY:
				break
			if is_enabled(t_id):
				table[j * BOARD_SLOTS + out_slot] = t_id
				out_slot += 1
				if out_slot >= BOARD_SLOTS:
					break

	var start_col := 0 if minutes <= TODAY_UNTIL else 1
	for col in range(start_col, 2):
		for slot in range(BOARD_SLOTS):
			var idx := col * BOARD_SLOTS + slot
			var cup_id := table[idx]
			if cup_id == EMPTY:
				break
			var bits := 0
			if is_eligible(cup_id, digimon_type):
				bits |= ELIGIBLE
			if is_overleveled(cup_id, digimon_type):
				bits |= OVERLEVELED
			table[idx] = cup_id | bits

	return table


## startTournament opponent draw (utils2.c:592-657): draw 7 opponents.
func draw_opponents(id: int, digimon_type: int) -> Array:
	var cup: Dictionary = game_data.tournament_cup(id)
	var opponents = cup.get("opponents")
	var open_pool: bool = bool(game_data.tournament(id).get("open_pool", false))
	var pool: Array = []

	if opponents != null:
		if open_pool:
			for opp in opponents:
				pool.append(int(opp))
		else:
			for opp in opponents:
				var opp_id := int(opp)
				if game_state.is_trigger_set(ROSTER_TRIGGER + opp_id):
					pool.append(opp_id)
	else:
		for i in range(ROSTER_SIZE):
			if game_state.is_trigger_set(ROSTER_TRIGGER + i):
				pool.append(i)

	# port-only (specs/tournament_entry.md §8.1, decided 2026-11-02): no Digimon of the cup's list has
	# joined (the C reads the pool's old memory, utils2.c:596): the whole list, as an open pool.
	if pool.is_empty() and opponents != null:
		push_warning("TournamentCups: no opponent of tournament %d has joined; drawing from its whole list" % id)
		for opp in opponents:
			pool.append(int(opp))
	if pool.is_empty():
		push_warning("TournamentCups: opponent pool is empty for tournament %d" % id)
		return [EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY]

	if pool.size() < OPPONENTS:
		var drawn: Array = pool.duplicate()
		var count := pool.size()
		for i in range(count, OPPONENTS):
			drawn.append(pool[Rng.random_limit(count)])
		return drawn
	elif pool.size() == OPPONENTS:
		return pool.slice(0, OPPONENTS)
	else:
		var partner_idx := pool.find(digimon_type)
		if partner_idx != -1:
			pool.remove_at(partner_idx)

		var drawn: Array = []
		for i in range(OPPONENTS):
			var k: int = Rng.random_limit(pool.size())
			drawn.append(pool[k])
			pool.remove_at(k)
		return drawn


## startTournament lines 664-681 (utils2.c:664-681): counters, won trigger, script value 0xFF.
func finish(id: int, result: int) -> void:
	game_state.clear_trigger(TRIGGER_REGISTERED)
	var tourn: Dictionary = game_data.tournament(id)
	var expected: int = int(tourn.get("rounds_to_win", 3))
	var won_trigger: int = int(tourn.get("won_trigger", -1))
	var counters: Dictionary = game_state.state["counters"]
	var won_limit: int = game_data.script_stat_limit(STAT_LIMIT_WON)
	var wins_limit: int = game_data.script_stat_limit(STAT_LIMIT_WINS)
	var lost_limit: int = game_data.script_stat_limit(STAT_LIMIT_LOST)

	if result == expected:
		var won: int = int(counters.get("tournaments_won", 0)) + 1
		counters["tournaments_won"] = min(won, won_limit) if won_limit >= 0 else won
		if won_trigger >= 0:
			game_state.set_trigger(won_trigger)
	else:
		counters["tournaments_lost"] = int(counters.get("tournaments_lost", 0)) + 1

	var wins: int = int(counters.get("tournament_wins", 0)) + result
	counters["tournament_wins"] = min(wins, wins_limit) if wins_limit >= 0 else wins

	var lost: int = int(counters.get("tournaments_lost", 0))
	counters["tournaments_lost"] = min(lost, lost_limit) if lost_limit >= 0 else lost

	game_state.set_script_value(SCRIPT_VALUE_RESULT, result)


## checkTournamentMedalConditions (tournament.c:168-240): returns the first met condition (0..5), or -1.
func medal_condition() -> int:
	var medal_records: Array = game_data.system("tournament_medals")
	for rec in medal_records:
		var cond_idx: int = int(rec.get("condition", -1))
		var medal_id: int = int(rec.get("medal", {}).get("id", -1))
		var condition_met := false

		if rec.has("cups"):
			var cups: Array = rec.get("cups", [])
			var all_won := true
			for cup_info in cups:
				var cup_id: int = int(cup_info.get("id", -1))
				var won_trig: int = int(game_data.tournament(cup_id).get("won_trigger", -1))
				if won_trig < 0 or not game_state.is_trigger_set(won_trig):
					all_won = false
					break
			condition_met = all_won
		elif rec.has("min_wins"):
			var min_wins: int = int(rec.get("min_wins", 0))
			var wins: int = int(game_state.state["counters"].get("tournament_wins", 0))
			condition_met = wins >= min_wins
		elif rec.get("all_cards", false):
			var trigger_id: int = int(rec.get("trigger", -1))
			if trigger_id < 0 or game_state.is_trigger_set(trigger_id):
				var cards: Array = game_data.records("items/card_data")
				var all_owned := true
				for card_rec in cards:
					if game_state.card_count(card_rec.get("key")) < 1:
						all_owned = false
						break
				condition_met = all_owned

		if condition_met:
			if medal_id >= 0 and game_state.is_trigger_set(TRIGGER_MEDAL_BASE + medal_id):
				return -1
			return cond_idx

	return -1


## TOURNAMENT_MEDAL_IDS[condition] (tournament.c:37-39): medal id for condition.
func medal_of(condition: int) -> int:
	var medal_records: Array = game_data.system("tournament_medals")
	for rec in medal_records:
		if int(rec.get("condition", -1)) == condition:
			return int(rec.get("medal", {}).get("id", -1))
	return -1
