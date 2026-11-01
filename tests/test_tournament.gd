extends SceneTree
## Step 4e-3, tournament entry (specs/tournament_entry.md): the acceptance checks of steps 2-6,
## written from the C by the reviewer (the expected values are the spec's §3-4, not the port's).
## Don't change them to make the code pass; when one looks wrong, report it with the C line.
##   DW_STEP_4E_3=<n> godot --headless --path . -s res://tests/test_tournament.gd
## Runs the checks of steps 2..n; the later ones print PENDING. Steps 1 and 2's porter checks are
## data_porter/tests/test_tournament_fields.py and asset_porter/tests/test_tournament_cups.py.
## Exits 1 if a check fails.
##
## Classes are loaded by path, so this file parses before they exist.

const CUPS := "res://scripts/systems/tournament_cups.gd"
const REGISTRATION := "res://scripts/systems/tournament_registration.gd"
const ROUTINES_SCENE := "res://scenes/script/tournament_routines.tscn"
const ARENA_SCENE := "res://scenes/field/arena_stand_in.tscn"

## Triggers (trigger.h:805-831) and script values (pstat.h:263-265).
const REGISTERED := 37
const REMIND_DAY := 38
const REMIND_EVENING := 39
const OVERLEVELED := 40
const GRADE_A_WON := 18
const BEATEN_GAME := 50
const ROSTER := 200
const MEDAL_TRIGGER := 0x16C
const V_DAY := 2
const V_CUP := 3
const V_TYPE := 4
const V_OWNER := 0xFE
const V_RESULT := 0xFF
## Digimon ids (dw1 aliases, checked against the keys in _initialize).
const BOTAMON := 1
const AGUMON := 3
const METALGREYMON := 12
## Section 0x0B of the arena scripts (asset_porter/tests/test_tournament_cups.py reads it).
const SECTION_B := [12, 13, 14, 26, 27, 28, 40, 41, 42, 54, 55, 56, 59, 60, 61]


class FakeMusic extends Node:
	var calls: Array = []

	func stop_bgm() -> void:
		calls.append("stop_bgm")


class FakeSound extends Node:
	var music: FakeMusic


var _failed := 0
var _checks := 0
var _step := 0
var _pending: Array[String] = []

var data: Node
var gs: Node

# The routine harness (steps 5-6).
var interp: ScriptInterpreter
var ctx: ScriptContext
var tb: TextBoxes
var boxes: UIBoxes
var area: TextArea
var pad: Pad
var files: ScriptFiles
var routines: ScriptRoutines
var arena: Node
var fake_sound: FakeSound
var sounds: Array = []


func _initialize() -> void:
	_step = int(OS.get_environment("DW_STEP_4E_3")) if OS.get_environment("DW_STEP_4E_3").is_valid_int() else 0
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("scripts/MAPHEAD/script.json"):
		print("SKIP: porter output missing")
		data.free()
		quit(0)
		return
	_eq(data.id_of("digimon/digimon_data", "dw1:botamon"), BOTAMON, "Botamon's id")
	_eq(data.id_of("digimon/digimon_data", "dw1:agumon"), AGUMON, "Agumon's id")
	_eq(data.id_of("digimon/digimon_data", "dw1:metalgreymon"), METALGREYMON, "MetalGreymon's id")

	if _gate(2, "GameData.tournament_cup and the cup component"):
		_test_cup_data()
	if _gate(3, "TournamentCups"):
		_test_enabled()
		_test_eligible()
		_test_board()
		_test_draw()
		_test_finish()
		_test_medals()
	if _gate(4, "TournamentRegistration"):
		_test_registration()
	if _gate(5, "builtins 0x06, 0x16, 0x21"):
		_setup_routines()
		_test_builtin_0x21()
		_test_builtin_0x06()
		_test_builtin_0x16()
		_teardown_routines()
	if _gate(6, "builtin 0x12, the board"):
		_setup_routines()
		_test_board_rows()
		_test_board_cursor()
		_test_board_info()
		_test_board_register()
		_test_board_other_paths()
		_teardown_routines()

	data.free()
	var state := "OK" if _failed == 0 else "FAILED %d" % _failed
	if not _pending.is_empty():
		state += "; PENDING (DW_STEP_4E_3=%d): %s" % [_step, ", ".join(_pending)]
	print("%s: tournament checks (%d run)" % [state, _checks])
	quit(1 if _failed else 0)


func _gate(step: int, what: String) -> bool:
	if _step >= step:
		return true
	_pending.append("step %d: %s" % [step, what])
	return false


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL: ", msg)


func _eq(got: Variant, want: Variant, msg: String) -> void:
	_check(got == want, "%s: got %s, want %s" % [msg, str(got), str(want)])


## A loaded script, or null with a failure.
func _script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		_check(false, "missing " + path)
		return null
	return load(path)


# --- state helpers ------------------------------------------------------------------------------

func _fresh_state() -> void:
	if gs != null:
		gs.free()
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()
	for t in range(ROSTER, ROSTER + 0x70):
		gs.clear_trigger(t)
	gs.state["partner"]["digimon"] = "dw1:agumon"
	for name in ["tournaments_won", "tournament_wins", "tournaments_lost"]:
		gs.state["counters"][name] = 0


func _roster(ids: Array) -> void:
	for t in range(ROSTER, ROSTER + 0x70):
		gs.clear_trigger(t)
	for id in ids:
		gs.set_trigger(ROSTER + int(id))


func _clock(day: int, hour: int, minute: int) -> void:
	var clock: Dictionary = gs.state["clock"]
	clock["day"] = day
	clock["hour"] = hour
	clock["minute"] = minute


func _cup(id: int) -> Dictionary:
	return data.tournament_cup(id)


func _ints(values: Variant) -> Array:
	var out := []
	if values is Array:
		for v in values:
			out.append(int(v))
	return out


func _cups() -> Object:
	var script := _script(CUPS)
	return script.new(gs, data) if script != null else null


# --- step 2: the data ---------------------------------------------------------------------------

func _test_cup_data() -> void:
	var cup := _cup(0)
	_check(not cup.is_empty(), "tournament_cup(0) exists")
	if cup.is_empty():
		return
	_eq(_ints(cup["requirement"]["c_values"]), [0, 0, 0], "Grade D's requirement")
	_eq(_ints(_cup(3)["requirement"]["c_values"]), [8, 4, 2], "Grade A's requirement")
	_eq(str(_cup(3)["requirement"]["also"]["type"]), "count", "Grade A: reqType 2")
	_eq(_ints(_cup(3)["requirement"]["also"]["list"]), SECTION_B, "Grade A: section 0x0B")
	_eq(str(_cup(4)["requirement"]["also"]["type"]), "won", "Grade S: reqType 1")
	_eq(int(_cup(4)["requirement"]["also"]["tournament"]), 3, "Grade S: Grade A won")
	_check(_cup(5)["opponents"] == null, "Grade R: the whole roster")
	_eq(_ints(_cup(0)["eligible"]).slice(0, 3), [3, 4, 5], "Grade D's eligible list")
	_check(str(_cup(0)["info"]["text"]).begins_with("- Grade D -"), "Grade D's info text")
	_eq(_cup(0x16)["info"], _cup(21)["info"], "the Beetle Cup shows the Humanoid Cup's info")
	_eq(data.tournament_cup("dw1:grade_d"), cup, "by key")
	var view: Dictionary = data.entity("tournament", 0)
	_eq(view.get("cup", {}), cup, "the entity's cup component")
	# Step 1's fields, through GameData.
	_eq(int(data.tournament(3).get("won_trigger", -1)), GRADE_A_WON, "Grade A's won_trigger")
	_eq(int(data.tournament(5).get("rounds_to_win", -1)), 2, "Grade R: 2 rounds")
	_eq(int(data.tournament(0).get("rounds_to_win", -1)), 3, "Grade D: 3 rounds")
	_check(bool(data.tournament(0x16).get("open_pool", false)), "the Beetle Cup's open pool")


# --- step 3: TournamentCups ---------------------------------------------------------------------

func _test_enabled() -> void:
	_fresh_state()
	var cups := _cups()
	if cups == null:
		return
	# isTournamentEnabled (dget.c:350).
	_check(cups.is_enabled(0), "Grade D (0, 0, 0): held with no roster")
	var list1 := _ints(_cup(1)["opponents"])
	_roster(list1.slice(0, 7))
	_check(not cups.is_enabled(1), "Grade C (8, 0, 0): 7 of its roster -> not held")
	_roster(list1.slice(0, 8))
	_check(cups.is_enabled(1), "Grade C: 8 of its roster -> held")

	# Grade A (8, 4, 2): 8 of its list 4, then section 0x0B counted on its own.
	var list3 := _ints(_cup(3)["opponents"])
	var outside_b := list3.filter(func(id): return not id in SECTION_B)
	_check(outside_b.size() >= 8, "Grade A's list 4 has 8 ids outside section 0x0B")
	var ids := outside_b.slice(0, 8) + SECTION_B.slice(0, 3)
	_roster(ids)
	_check(not cups.is_enabled(3), "Grade A: 3 of section 0x0B -> not held")
	_roster(ids + [SECTION_B[3]])
	_check(cups.is_enabled(3), "Grade A: 4 of section 0x0B -> held")

	# Grade S (8, 0, 1): trigger 18 (dget.c:392).
	_roster(_ints(_cup(4)["opponents"]).slice(0, 8))
	gs.clear_trigger(GRADE_A_WON)
	_check(not cups.is_enabled(4), "Grade S: Grade A not won -> not held")
	gs.set_trigger(GRADE_A_WON)
	_check(cups.is_enabled(4), "Grade S: Grade A won -> held")
	gs.clear_trigger(GRADE_A_WON)

	# Fire Cup (8, 4, 56): the count stops at the first id > 56 (dget.c:412, `<= reqType`).
	_eq(_ints(_cup(11)["opponents"]).slice(0, 8), [3, 5, 9, 21, 36, 47, 56, 69], "Fire Cup's list 4")
	_roster([3, 5, 9, 69, 88, 101, 104, 105])
	_check(not cups.is_enabled(11), "Fire Cup: 3 ids before the first > 56 -> not held")
	_roster([3, 5, 9, 21, 69, 88, 101, 104])
	_check(cups.is_enabled(11), "Fire Cup: 4 ids before the first > 56 -> held")
	_roster([3, 5, 9, 21, 69, 88, 101])
	_check(not cups.is_enabled(11), "Fire Cup: 7 of the roster -> not held, whatever the count")


func _test_eligible() -> void:
	_fresh_state()
	var cups := _cups()
	if cups == null:
		return
	_check(cups.is_eligible(0, AGUMON), "Agumon may enter Grade D")
	_check(not cups.is_eligible(0, BOTAMON), "Botamon may not enter Grade D")
	_check(cups.is_overleveled(0, METALGREYMON), "MetalGreymon is too strong for Grade D")
	_check(not cups.is_overleveled(0, AGUMON), "Agumon isn't too strong for Grade D")


func _test_board() -> void:
	_fresh_state()
	var cups := _cups()
	if cups == null:
		return
	# fillEnabledTournamentTable (dget.c:101). No roster: only Grade D is held. Days 0-4 all hold it.
	var b: PackedByteArray = cups.fill_board(0, 600, AGUMON)
	_eq(b.size(), 30, "the board is 30 bytes")
	_eq(b[0], 0x80, "day 0, 10:00: Grade D eligible")
	_eq(b[1], 0xFF, "day 0: nothing after it")
	_eq(b[6], 0x80, "day 1: Grade D eligible")
	_eq(b[12], 0x00, "day 2: no bits")
	_eq(b[18], 0x00, "day 3: no bits")
	_eq(b[24], 0x00, "day 4: no bits")
	b = cups.fill_board(0, 601, AGUMON)
	_eq(b[0], 0x00, "day 0 after 10:00: no bits")
	_eq(b[6], 0x80, "day 1 after 10:00: eligible")
	b = cups.fill_board(0, 600, METALGREYMON)
	_eq(b[0], 0xC0, "MetalGreymon in Grade D: eligible and over-levelled")
	b = cups.fill_board(28, 600, AGUMON)
	_eq(b[12], 0x00, "day 30 wraps to schedule day 0")
	_eq(b[13], 0xFF, "day 30 wraps to schedule day 0 (only Grade D held)")

	# Day 2 holds [0, 1, 3, 6]: with Grade C and Version 1 held but Grade A not, the cells pack left.
	_roster([5, 6, 7, 8, 9, 10, 11, 19, 3, 4, 12])
	_check(cups.is_enabled(1) and cups.is_enabled(6) and not cups.is_enabled(3), "day 2's setup")
	b = cups.fill_board(2, 601, BOTAMON)
	_eq(Array(b.slice(0, 4)), [0, 1, 6, 0xFF], "day 2: the held cups packed left")


func _test_draw() -> void:
	_fresh_state()
	var cups := _cups()
	if cups == null:
		return
	Rng.set_seed(1)
	# startTournament (utils2.c:592-657). Version 1 Cup (6): list 4 = 3..14, not open.
	_eq(_ints(_cup(6)["opponents"]), [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], "Version 1's list 4")
	_roster([3, 4, 5, 6, 7, 8, 9])
	_eq(cups.draw_opponents(6, AGUMON), [3, 4, 5, 6, 7, 8, 9], "7 in the pool: all, in order, the partner's type kept")

	_roster([3, 4, 5])
	var drawn: Array = cups.draw_opponents(6, AGUMON)
	_eq(drawn.size(), 7, "3 in the pool: 7 drawn")
	_eq(drawn.slice(0, 3), [3, 4, 5], "3 in the pool: those first")
	_check(drawn.all(func(id): return id in [3, 4, 5]), "3 in the pool: the rest repeat them")

	_roster(range(3, 15))
	for i in 20:
		drawn = cups.draw_opponents(6, AGUMON)
		var distinct := {}
		for id in drawn:
			distinct[id] = true
		_check(drawn.size() == 7 and distinct.size() == 7, "12 in the pool: 7 distinct")
		_check(not AGUMON in drawn, "12 in the pool: not the partner's type")
		_check(drawn.all(func(id): return id >= 4 and id <= 14), "12 in the pool: from the pool")

	# The Beetle Cup (open_pool) takes its whole list without roster triggers (utils2.c:603).
	_roster([])
	drawn = cups.draw_opponents(0x16, AGUMON)
	var beetle := _ints(_cup(0x16)["opponents"])
	_check(drawn.size() == 7 and drawn.all(func(id): return id in beetle), "the Beetle Cup: from its list, no roster")

	# Grade R's list 4 starts >= 0xFE: the whole roster (utils2.c:616-622).
	_roster([20, 3, 9, 7, 30, 25, 11])
	_eq(cups.draw_opponents(5, AGUMON), [3, 7, 9, 11, 20, 25, 30], "Grade R: the roster in id order")

	# An empty pool (spec §8.1, port-only): 7 x 0xFF.
	_roster([])
	_eq(cups.draw_opponents(6, AGUMON), [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF], "an empty pool")


func _test_finish() -> void:
	_fresh_state()
	var cups := _cups()
	if cups == null:
		return
	var counters: Dictionary = gs.state["counters"]
	# utils2.c:664-681.
	gs.set_trigger(REGISTERED)
	cups.finish(0, 3)
	_eq(int(counters["tournaments_won"]), 1, "Grade D, 3 rounds: won + 1")
	_eq(int(counters["tournaments_lost"]), 0, "Grade D, 3 rounds: not lost")
	_eq(int(counters["tournament_wins"]), 3, "Grade D, 3 rounds: wins + 3")
	_check(gs.is_trigger_set(15), "Grade D won: trigger 15")
	_check(not gs.is_trigger_set(REGISTERED), "trigger 37 unset")
	_eq(gs.script_value(V_RESULT), 3, "value 0xFF = the result")

	cups.finish(0, 2)
	_eq(int(counters["tournaments_won"]), 1, "Grade D, 2 rounds: not won")
	_eq(int(counters["tournaments_lost"]), 1, "Grade D, 2 rounds: lost + 1")
	_eq(int(counters["tournament_wins"]), 5, "Grade D, 2 rounds: wins + 2")
	_eq(gs.script_value(V_RESULT), 2, "value 0xFF = 2")

	cups.finish(5, 2)
	_eq(int(counters["tournaments_won"]), 2, "Grade R, 2 rounds: won")
	_check(gs.is_trigger_set(20), "Grade R won: trigger 20")

	# The Beetle Cup's won trigger is 37 itself: unset (:664), then set again (:674) (spec §4.9 quirk).
	gs.set_trigger(REGISTERED)
	cups.finish(0x16, 3)
	_check(gs.is_trigger_set(REGISTERED), "the Beetle Cup won: trigger 37 set again")
	cups.finish(0x16, 2)
	_check(not gs.is_trigger_set(REGISTERED), "the Beetle Cup lost: trigger 37 unset")

	var wins_cap: int = data.script_stat_limit(0x12)
	var won_cap: int = data.script_stat_limit(0x11)
	var lost_cap: int = data.script_stat_limit(0x13)
	counters["tournament_wins"] = wins_cap - 1
	counters["tournaments_won"] = won_cap
	counters["tournaments_lost"] = lost_cap
	cups.finish(0, 3)
	_eq(int(counters["tournament_wins"]), wins_cap, "wins capped (limit 0x12)")
	_eq(int(counters["tournaments_won"]), won_cap, "won capped (limit 0x11)")
	cups.finish(0, 0)
	_eq(int(counters["tournaments_lost"]), lost_cap, "lost capped (limit 0x13)")


func _test_medals() -> void:
	_fresh_state()
	var cups := _cups()
	if cups == null:
		return
	# checkTournamentMedalConditions (tournament.c:168).
	for m in 0x13:
		gs.clear_trigger(MEDAL_TRIGGER + m)
	for t in range(15, 37):
		gs.clear_trigger(t)
	gs.clear_trigger(BEATEN_GAME)
	_eq(cups.medal_condition(), -1, "nothing met")
	for t in range(15, 21):
		gs.set_trigger(t)
	_eq(cups.medal_condition(), 0, "the 6 Grade cups won")
	_eq(cups.medal_of(0), 0, "condition 0's medal")
	for t in range(21, 26):
		gs.set_trigger(t)
	gs.set_trigger(MEDAL_TRIGGER + 0)
	_eq(cups.medal_condition(), -1, "medal 0 owned: -1, the Version cups not tested")
	gs.clear_trigger(15)
	_eq(cups.medal_condition(), 1, "the 5 Version cups won")
	for t in range(15, 37):
		gs.clear_trigger(t)
	gs.state["counters"]["tournament_wins"] = 99
	_eq(cups.medal_condition(), -1, "99 wins")
	gs.state["counters"]["tournament_wins"] = 100
	_eq(cups.medal_condition(), 4, "100 wins")
	gs.state["counters"]["tournament_wins"] = 0
	for card in 0x42:
		gs.set_card_count(card, 1)
	_eq(cups.medal_condition(), -1, "every card, game not beaten")
	gs.set_trigger(BEATEN_GAME)
	_eq(cups.medal_condition(), 5, "every card and the game beaten")
	_eq(cups.medal_of(5), 0xC, "condition 5's medal")
	gs.set_card_count(0x41, 0)
	_eq(cups.medal_condition(), -1, "one card missing")


# --- step 4: TournamentRegistration -------------------------------------------------------------

var _reg_sections: Array = []
var _reg_paused := true
var _reg_tamer := 0
var _reg_partner := 1
var _reg_boxes_closed := true


func _registration() -> Object:
	var script := _script(REGISTRATION)
	if script == null:
		return null
	var r: Object = script.new(gs)
	r.script_paused = func(): return _reg_paused
	r.tamer_state = func(): return _reg_tamer
	r.partner_state = func(): return _reg_partner
	r.partner_type = func(): return AGUMON
	r.boxes_closed = func(): return _reg_boxes_closed
	r.section_requested.connect(func(section): _reg_sections.append(section))
	return r


func _register(day: int) -> void:
	gs.set_trigger(REGISTERED)
	gs.set_trigger(REMIND_DAY)
	gs.set_trigger(REMIND_EVENING)
	gs.set_script_value(V_DAY, day)
	gs.set_script_value(V_TYPE, AGUMON)
	gs.set_script_value(V_CUP, 0)


func _test_registration() -> void:
	_fresh_state()
	var r := _registration()
	if r == null:
		return
	# updateTournamentRegistration (tournament.c:42).
	_reg_sections.clear()
	_clock(4, 12, 0)
	_check(r.tick(), "not registered: the lights update")
	_eq(_reg_sections, [], "not registered: no section")

	_register(4)
	gs.set_script_value(V_TYPE, METALGREYMON)
	_check(not r.tick(), "another partner: no light update")
	_check(not gs.is_trigger_set(REGISTERED), "another partner: registration cancelled")
	_eq(_reg_sections, [], "another partner: no section")

	_register(0x80 | 5)
	_check(not r.tick(), "registered for tomorrow: no light update")
	_eq(_reg_sections, [], "registered for tomorrow: no section")

	_register(4)
	_clock(4, 11, 59)
	_check(not r.tick(), "11:59: no light update")
	_eq(_reg_sections, [], "11:59: no section")

	# 12:00, idle: the first reminder, once (38).
	_clock(4, 12, 0)
	_reg_paused = false
	_check(not r.tick(), "a script running: no light update")
	_reg_paused = true
	_reg_tamer = 2
	_check(not r.tick(), "the tamer busy: no light update")
	_reg_tamer = 0
	_reg_partner = 3
	_check(not r.tick(), "the partner busy: no light update")
	_reg_partner = 1
	_reg_boxes_closed = false
	_check(not r.tick(), "a box open: no light update")
	_reg_boxes_closed = true
	_eq(_reg_sections, [], "not idle: no section")
	_check(gs.is_trigger_set(REMIND_DAY), "not idle: trigger 38 kept")
	_check(r.tick(), "12:00, idle: the reminder, then the lights")
	_eq(_reg_sections, [0x4D9], "12:00: section 0x4D9")
	_check(not gs.is_trigger_set(REMIND_DAY), "12:00: trigger 38 cleared")
	_check(gs.is_trigger_set(REGISTERED), "12:00: still registered")
	_reg_sections.clear()
	_clock(4, 19, 59)
	_check(not r.tick(), "19:59, 38 used: no light update")
	_eq(_reg_sections, [], "19:59: no section")

	# 20:00: the second reminder (39).
	_clock(4, 20, 0)
	_check(r.tick(), "20:00: the reminder, then the lights")
	_eq(_reg_sections, [0x4D9], "20:00: section 0x4D9")
	_check(not gs.is_trigger_set(REMIND_EVENING), "20:00: trigger 39 cleared")
	_reg_sections.clear()
	_check(not r.tick(), "20:00, 39 used: no light update")
	_eq(_reg_sections, [], "20:00 again: no section")

	# 23:00 still the day; 23:01 is too late (0x565).
	_register(4)
	gs.clear_trigger(REMIND_DAY)
	_clock(4, 23, 0)
	_check(r.tick(), "23:00: the evening reminder")
	_eq(_reg_sections, [0x4D9], "23:00: section 0x4D9")
	_reg_sections.clear()
	_register(4)
	_clock(4, 23, 1)
	_check(not r.tick(), "23:01: no light update")
	_eq(_reg_sections, [0x4DA], "23:01: section 0x4DA")
	_check(not gs.is_trigger_set(REGISTERED), "23:01: registration cancelled")
	_reg_sections.clear()

	# Another day: missed, but only from 12:00.
	_register(4)
	_clock(5, 11, 0)
	_check(not r.tick(), "the next day, 11:00: no light update")
	_eq(_reg_sections, [], "the next day, 11:00: no section")
	_clock(5, 12, 0)
	r.tick()
	_eq(_reg_sections, [0x4DA], "the next day, 12:00: section 0x4DA")
	_check(not gs.is_trigger_set(REGISTERED), "the next day: registration cancelled")
	_reg_sections.clear()

	# Day 29, registered for tomorrow: 30 never matches (spec §4.7 quirk).
	_register(30)
	_clock(0, 12, 0)
	r.tick()
	_eq(_reg_sections, [0x4DA], "registered for day 30: missed")
	_reg_sections.clear()


# --- the routine harness (steps 5-6; the shape of tests/test_town_services.gd) ------------------

func _setup_routines() -> void:
	_fresh_state()
	sounds.clear()
	boxes = UIBoxes.new()
	root.add_child(boxes)
	area = TextArea.new(data, "en_us")
	ctx = ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	pad = Pad.new()
	tb = TextBoxes.new(boxes, area, ctx, pad, data, gs)
	tb.sound.connect(func(id): sounds.append(id))
	files = ScriptFiles.new()
	interp = ScriptInterpreter.new(ctx, files, tb)
	interp.game_state = gs
	interp.data = data
	fake_sound = FakeSound.new()
	fake_sound.music = FakeMusic.new()
	routines = ScriptRoutines.new()
	if ResourceLoader.exists(ROUTINES_SCENE):
		routines.add_child(load(ROUTINES_SCENE).instantiate())
	else:
		_check(false, "missing " + ROUTINES_SCENE)
	root.add_child(routines)
	routines.configure(ctx, tb, gs, data, fake_sound)
	interp.routines = routines
	arena = null
	if ResourceLoader.exists(ARENA_SCENE):
		arena = load(ARENA_SCENE).instantiate()
		root.add_child(arena)
	else:
		_check(false, "missing " + ARENA_SCENE)
	routines.set("arena", arena)


func _teardown_routines() -> void:
	routines.free()
	boxes.free()
	if arena != null:
		arena.free()
	fake_sound.music.free()
	fake_sound.free()
	gs.free()
	gs = null


func _frame(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	interp.tick_script()
	boxes.step()


func _press(button: int) -> void:
	_frame()
	_frame(button)
	_frame()


func _until(done: Callable, limit := 200) -> bool:
	for i in limit:
		if done.call():
			return true
		_frame()
	return done.call()


## value 0xFE = `owner`, CALL_ROUTINE `routine`, value 50 = 1, END.
func _run(routine: int, owner := 5) -> void:
	gs.set_script_value(50, 0)
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray([0x1E, 0, 0xFE, owner, 0x64, routine, 0x1E, 0, 50, 1, 0xFE, 0]))
	files._cache[500] = bytes
	interp.call_section(500, 1)
	_frame()


func _ended() -> bool:
	return gs.script_value(50) == 1


func _waiting_text() -> bool:
	return ctx.textbox_mode in [1, 2] and boxes.boxes[0].state == UIBoxes.STATE_OPEN \
			and tb.entries[0].write_count == tb.entries[0].render_count and tb.entries[0].idle == 0


func _choice_shown() -> bool:
	return _waiting_text() and ctx.textbox_mode == 2


func _box_open(id: int) -> bool:
	return boxes.boxes[id].state == UIBoxes.STATE_OPEN


func _box_closed(id: int) -> bool:
	return boxes.boxes[id].state == 0


func _node() -> Node:
	return routines.node_for(0x12)


func _board() -> Object:
	var node := _node()
	return node.get("board") if node != null else null


func _board_ready() -> bool:
	return _box_open(1) and _box_open(2) and tb.fresh_dialogue == 0 and _box_closed(3)


## A text-area row's bytes up to (and with) its terminateString.
func _row(row: int) -> Array:
	var out := []
	var at := row * tb.line_size
	while at < (row + 1) * tb.line_size:
		out.append(tb.lines[at])
		if out.size() >= 4 and out.slice(-4) in [[1, 1, 0xD, 0], [1, 1, 0, 0]]:
			break
		at += 1
	return out


# --- step 5: builtins 0x21, 0x06, 0x16 ----------------------------------------------------------

func _test_builtin_0x21() -> void:
	_check(routines.node_for(0x21) != null and routines.node_for(0x21) == routines.node_for(0x06),
			"0x21 and 0x06 run by the tournament routines")
	# script_interp.c:1800-1813.
	_clock(0x16, 9, 0)
	gs.set_script_value(V_CUP, 0xFF)
	_run(0x21)
	_until(_ended)
	_check(_ended(), "0x21 doesn't wait")
	for t in [REGISTERED, REMIND_DAY, REMIND_EVENING]:
		_check(gs.is_trigger_set(t), "0x21: trigger %d" % t)
	_eq(gs.script_value(V_DAY), 0x16, "0x21 on day 0x16: value 2 = 0x16")
	_eq(gs.script_value(V_CUP), 0x16, "0x21: value 3 = the Beetle Cup")
	_eq(gs.script_value(V_TYPE), AGUMON, "0x21: value 4 = the partner")
	_clock(3, 9, 0)
	_run(0x21)
	_until(_ended)
	_eq(gs.script_value(V_DAY), 0x95, "0x21 on another day: value 2 = 0x95")

	# The interpreter's own 0x21 branch is gone: without the routines it changes nothing.
	interp.routines = null
	gs.set_script_value(V_CUP, 0xFF)
	_run(0x21)
	_until(_ended)
	_eq(gs.script_value(V_CUP), 0xFF, "0x21 without the routine node: nothing written")
	interp.routines = routines


func _test_builtin_0x06() -> void:
	if arena == null:
		return
	# Grade D with exactly 7 of its pool: the opponents are known.
	var pool := _ints(_cup(0)["opponents"]).slice(0, 7)
	_roster(pool)
	gs.set_trigger(REGISTERED)
	gs.set_script_value(V_CUP, 0)
	arena.set("stand_in_result", 3)
	fake_sound.music.calls.clear()
	var won: int = gs.state["counters"]["tournaments_won"]
	_run(0x06)
	_until(_ended)
	_check(_ended(), "0x06 ends after the arena")
	_eq(int(arena.get("last_cup")), 0, "the arena ran Grade D")
	_eq(arena.get("last_opponents"), pool, "the arena got the 7 drawn")
	_eq(fake_sound.music.calls, ["stop_bgm"], "stopBGM before the arena (utils2.c:660)")
	_eq(int(gs.state["counters"]["tournaments_won"]), won + 1, "won + 1")
	_check(gs.is_trigger_set(15), "Grade D won: trigger 15")
	_check(not gs.is_trigger_set(REGISTERED), "trigger 37 unset")
	_eq(gs.script_value(V_RESULT), 3, "value 0xFF = 3")

	# A second run: `finished` is reset, the result read again.
	gs.set_script_value(V_CUP, 0)
	arena.set("stand_in_result", 1)
	_run(0x06)
	_until(_ended)
	_eq(gs.script_value(V_RESULT), 1, "a second run: value 0xFF = 1")


func _test_builtin_0x16() -> void:
	for m in 0x13:
		gs.clear_trigger(MEDAL_TRIGGER + m)
	for t in range(15, 37):
		gs.clear_trigger(t)
	gs.state["counters"]["tournament_wins"] = 0
	# Nothing met: no wait (script_interp.c:1662).
	_run(0x16)
	_frame()
	_check(_ended(), "0x16, nothing met: the script goes on at once")
	_check(_box_closed(0), "0x16, nothing met: no box")

	# Grade and Version cups won, no medal owned (tournament.c:242). The medal's line, then state 0
	# again: condition 0 is still the first one met and its medal is now owned, so -1 and the end.
	# Medal 1 is not given in the same call (the quirk of §4.10).
	for t in range(15, 26):
		gs.set_trigger(t)
	_run(0x16)
	_check(_until(_waiting_text), "0x16: the medal's line")
	_check(gs.is_trigger_set(MEDAL_TRIGGER + 0), "0x16: medal 0 unlocked")
	_press(Pad.CROSS)
	_check(_until(_ended), "0x16: ends after the line")
	_check(not gs.is_trigger_set(MEDAL_TRIGGER + 1), "0x16: medal 1 not given (condition 0 checked first)")

	# The next call, with the Grade cups no longer all won: medal 1.
	gs.clear_trigger(15)
	_run(0x16)
	_check(_until(_waiting_text), "0x16 again: medal 1's line")
	_check(gs.is_trigger_set(MEDAL_TRIGGER + 1), "0x16 again: medal 1 unlocked")
	_press(Pad.CROSS)
	_check(_until(_ended), "0x16 again: ends")


# --- step 6: builtin 0x12 -------------------------------------------------------------------------

func _open_board() -> bool:
	gs.clear_trigger(REGISTERED)
	sounds.clear()
	_run(0x12)
	return _until(_board_ready)


func _test_board_rows() -> void:
	_clock(0, 9, 0)
	gs.set_trigger(REGISTERED)
	_run(0x12)
	_until(_ended, 10)
	_check(_ended(), "0x12 while registered: ends at once")
	_check(_box_closed(1) and _box_closed(2), "0x12 while registered: no board")

	_check(_open_board(), "0x12: the board opens")
	var board := _board()
	_check(board != null, "the routine's board")
	if board == null:
		return
	_eq(gs.script_value(V_CUP), 0xFF, "value 3 = 0xFF while choosing")
	_eq(pad.repeat_mask, 0xF000, "the d-pad repeats (dget.c:681)")
	var table: PackedByteArray = board.get("table")
	_eq(table[0], 0x80, "the table: today's Grade D eligible")
	_eq(table[6], 0x80, "the table: tomorrow's Grade D eligible")
	_eq(table[12], 0x00, "the table: day 2 not enterable")

	# buildScheduleEntries (dget.c:229-268): row 10 = the first slot of each day.
	var d := 0x44  # "D", ASCII (US TOURNAMENT_GRADES)
	_eq(_row(10), [1, 1, d, 1, 1, d, 1, 3, d, 1, 3, d, 1, 3, d, 1, 1, 0xD, 0], "row 10: Grade D x 5")
	var empty := [1, 1, 0x81, 0x40]
	_eq(_row(11), empty + empty + empty + empty + empty + [1, 1, 0xD, 0], "row 11: empty cells")
	_eq(_row(15), empty + empty + empty + empty + empty + [1, 1, 0, 0], "row 15: the last row ends with 00")
	# buildScheduleLabels (dget.c:176-197): the days 1-5, a full-width space after a 1-digit first.
	var header := [1, 1]
	header.append_array(Array(TextBoxes.int_to_string_sjis(1, 2, 0)))
	header.append_array([0x81, 0x40])
	for n in [2, 3, 4, 5]:
		header.append_array(Array(TextBoxes.int_to_string_sjis(n, 2, 0)))
	header.append_array([1, 1, 0, 0])
	_eq(_row(9), header, "row 9: the day header")
	_eq(tb.lines[8 * tb.line_size + 16], 0x0D, "row 8 cut at byte 16 (dget.c:174)")
	_press(Pad.TRIANGLE)
	_until(_ended)


func _test_board_cursor() -> void:
	_clock(0, 9, 0)
	_check(_open_board(), "the board opens (cursor)")
	var board := _board()
	if board == null:
		return
	_eq([board.get("column"), board.get("row")], [0, 0], "the cursor starts at (0, 0)")
	_press(Pad.LEFT)
	_eq(board.get("column"), 4, "← from column 0 wraps to 4")
	_press(Pad.RIGHT)
	_eq(board.get("column"), 0, "→ from column 4 wraps to 0")
	_press(Pad.UP)
	_eq(board.get("row"), 5, "↑ from row 0 wraps to 5")
	_press(Pad.DOWN)
	_eq(board.get("row"), 0, "↓ from row 5 wraps to 0")
	_eq(sounds.filter(func(s): return s == 2).size(), 4, "a move: sound 2 each")

	_press(Pad.RIGHT)
	_press(Pad.RIGHT)
	sounds.clear()
	_press(Pad.CROSS)
	_eq(sounds, [0xB], "✕ on a day-2 cup: refused, sound 0xB")
	_check(_board_ready(), "refused: the board stays")
	_eq(gs.script_value(V_CUP), 0xFF, "refused: no cup")

	_press(Pad.DOWN)
	sounds.clear()
	_press(Pad.START)
	_eq(sounds, [0xB], "START on an empty cell: sound 0xB")
	_check(_box_closed(3), "START on an empty cell: no info box")

	sounds.clear()
	_press(Pad.TRIANGLE)
	_eq(sounds.slice(0, 1), [4], "△: sound 4")
	_check(_until(_ended), "△: the routine ends")
	_eq(gs.script_value(V_CUP), 0xFF, "△: no cup")
	_check(not gs.is_trigger_set(REGISTERED), "△: not registered")
	_eq(pad.repeat_mask, 0, "the repeat mask cleared")


func _test_board_info() -> void:
	_clock(0, 9, 0)
	_check(_open_board(), "the board opens (info)")
	var board := _board()
	if board == null:
		return
	sounds.clear()
	_press(Pad.START)
	_eq(sounds, [3], "START on a cup: sound 3")
	_check(_until(func(): return _box_open(3)), "START: box 3 opens")
	_eq(board.get("info_from_board"), 0, "box 3 from the board (MAIN_D_801353B0 = 0)")
	sounds.clear()
	_until(func(): return tb.fresh_dialogue == 0 and tb.entries[3].write_count == tb.entries[3].render_count)
	_press(Pad.START)
	_check(_until(func(): return _box_closed(3)), "START again: box 3 closes")
	_eq(sounds, [3], "box 3 closes with sound 3")
	_check(_board_ready(), "the board is back")
	_press(Pad.TRIANGLE)
	_until(_ended)


## ✕ on (column, row 0), the confirm line, then the choice `enter` (0 = Enter, 1 = Don't enter).
func _pick(column: int, enter: int) -> void:
	for i in column:
		_press(Pad.RIGHT)
	_press(Pad.CROSS)
	_check(_until(_waiting_text), "the confirm line")
	_check(_until(func(): return _box_open(3), 40), "box 3 shows the cup's info")
	_press(Pad.CROSS)
	_check(_until(_choice_shown), "the Enter / Don't enter choice")
	if enter == 1:
		_press(Pad.DOWN)
	_press(Pad.CROSS)
	_check(_until(_ended), "the routine ends after the choice")


func _test_board_register() -> void:
	_clock(0, 9, 0)
	_check(_open_board(), "the board opens (register today)")
	_pick(0, 0)
	_eq(gs.script_value(V_CUP), 0, "value 3 = Grade D")
	for t in [REGISTERED, REMIND_DAY, REMIND_EVENING]:
		_check(gs.is_trigger_set(t), "registered: trigger %d" % t)
	_check(not gs.is_trigger_set(OVERLEVELED), "Agumon in Grade D: trigger 40 unset")
	_eq(gs.script_value(V_DAY), 0, "today: value 2 = DAY")
	_eq(gs.script_value(V_TYPE), AGUMON, "value 4 = the partner")
	_check(_until(func(): return _box_closed(3)), "box 3 closed")

	_clock(0, 9, 0)
	_check(_open_board(), "the board opens (register tomorrow)")
	_pick(1, 0)
	_eq(gs.script_value(V_DAY), 0x81, "tomorrow: value 2 = (DAY + 1) | 0x80")


func _test_board_other_paths() -> void:
	# Over-levelled: line 3 and trigger 40 (dget.c:703-705).
	gs.state["partner"]["digimon"] = "dw1:metalgreymon"
	_clock(0, 9, 0)
	_check(_open_board(), "the board opens (over-levelled)")
	_pick(0, 0)
	_check(gs.is_trigger_set(OVERLEVELED), "MetalGreymon in Grade D: trigger 40")
	_eq(gs.script_value(V_TYPE), METALGREYMON, "value 4 = MetalGreymon")
	gs.state["partner"]["digimon"] = "dw1:agumon"

	# Don't enter: nothing registered (state 6).
	_clock(0, 9, 0)
	_check(_open_board(), "the board opens (don't enter)")
	_pick(0, 1)
	_check(not gs.is_trigger_set(REGISTERED), "Don't enter: not registered")
	_check(_until(func(): return _box_closed(3)), "Don't enter: box 3 closed")

	# After 10:00, today's column can't be entered.
	_clock(0, 10, 1)
	_check(_open_board(), "the board opens (10:01)")
	sounds.clear()
	_press(Pad.CROSS)
	_eq(sounds, [0xB], "10:01: today's Grade D refused")
	_press(Pad.TRIANGLE)
	_until(_ended)
