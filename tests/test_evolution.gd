extends SceneTree
## Evolution (scripts/systems/evolution.gd), partner state 13 and the evolution scene's loading
## part against specs/evolution.md §2, values worked out from the C:
##   godot --headless --path . -s res://tests/test_evolution.gd
## Exits 1 if a check fails.

## The real tables, with some requirement / path records replaced (the selection cases).
class StubData extends "res://scripts/data/game_data.gd":
	var reqs := {}
	var paths := {}

	func evolution_requirements(ref: Variant) -> Dictionary:
		var id := _digimon_id(ref)
		return reqs[id] if reqs.has(id) else super.evolution_requirements(ref)

	func evolution_paths(ref: Variant) -> Dictionary:
		var id := _digimon_id(ref)
		return paths[id] if paths.has(id) else super.evolution_paths(ref)


## A scene without models: it applies the evolution after 3 ticks, then ends. Its timer is what
## partner state 13 reads (specs/evolution_scene.md A1).
class StubScene extends EvolutionScene:
	var started := -1
	var left := 0

	func start(evolution_target: int) -> void:
		started = evolution_target
		left = 3
		timer = 3

	func tick() -> int:
		if timer < 0:
			return -1
		left -= 1
		timer = left
		if left == 0:
			evolution.apply_evolution(started)
			timer = -1
		return timer


## One frame of partner state 13: the partner, then the scene's object tick (specs/evolution_scene.md
## A1: the scene is an object of the frame; the partner only reads its timer).
static func _frame_13(partner: Partner, scene: EvolutionScene) -> void:
	partner.tick_evolving()
	scene.tick()


var _failed := 0
var _checks := 0
var _started := false
var data: StubData
var gs: Node
var clock: Clock
var care: Care
var evo: Evolution
var c: Dictionary


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	data = StubData.new()
	if not data.available() or data.records("evolution/rules").is_empty():
		print("SKIP: data porter output missing")
		quit(0)
		return
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	clock = Clock.new()
	clock.game_state = gs
	clock.active = true
	clock.running = true
	care = Care.new()
	care.game_state = gs
	care.data = data
	care.clock = clock
	evo = Evolution.new()
	evo.game_state = gs
	evo.data = data
	evo.care = care
	evo.clock = clock
	care.evolution = evo

	_fresh_and_in_training()
	_averages()
	_score()
	_special()
	_hourly()
	_items()
	_apply()
	_technique()
	_state_13()
	_scene_loading()
	_script_routines()

	care.free()
	clock.free()
	gs.free()
	data.free()
	print("%s: evolution checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)


## A new game with `partner` and its care initialised, at 8:00 (the clock just advanced).
func _reset(partner: String) -> void:
	gs.new_game(partner)
	var clk: Dictionary = gs.state["clock"]
	clk["hour"] = 8
	clk["minute"] = 0
	clk["frame"] = 8 * 1200
	clk["last_handled_frame"] = clk["frame"] - 1
	care.initialize_partner()
	care.evolution_target = -1
	care.nanimon_trigger = false
	care.partner = null
	care.tamer = null
	evo.used_item = false
	evo.script_ctx = null
	c = gs.state["partner"]["care"]


func _base() -> Dictionary:
	return gs.state["partner"]["stats"]["base"]


func _set_stats(hp: int, mp: int, off: int, def: int, speed: int, brain: int) -> void:
	var b := _base()
	b["max_hp"] = hp
	b["max_mp"] = mp
	b["offense"] = off
	b["defense"] = def
	b["speed"] = speed
	b["brains"] = brain


## Seeds Rng so that its next randomLimit(100) satisfies `want`.
func _roll(want: Callable) -> void:
	for s in range(1, 5000):
		Rng.set_seed(s)
		if want.call(Rng.random_limit(100)):
			Rng.set_seed(s)
			return
	push_error("no seed found")


## A requirement record that every partner meets except where `extra` says (minimum rule, every
## stat unset, care >= 0, the weight of a fresh partner, bonus discipline >= 0).
func _req(extra := {}) -> Dictionary:
	var r := {"stat_rule": "minimum", "stats": {"hp": null, "mp": null, "offense": null, "defense": null,
			"speed": null, "brain": null}, "care_mistakes": {"value": 0, "at_most": false},
			"weight": {"value": int(c["weight"])}, "bonus": {"from_digimon": null, "discipline": 0,
			"happiness": null, "battles": null, "techs": null}}
	for k in extra:
		if r[k] is Dictionary and extra[k] is Dictionary:
			r[k].merge(extra[k], true)
		else:
			r[k] = extra[k]
	return r


# --- selection -------------------------------------------------------------------------------------

func _fresh_and_in_training() -> void:
	_reset("dw1:botamon")
	c["evo_timer"] = 7
	_eq(evo.fresh_target("dw1:botamon"), 2, "Botamon's fixed target is Koromon")
	_eq(c["evo_timer"], 0, "getFreshEvolutionTarget resets evo_timer")
	_eq(evo.fresh_target("dw1:agumon"), -1, "a Digimon without a fixed target: -1 (the C's uninitialised value)")

	_reset("dw1:koromon")
	data.paths[2] = {"to": [3, 4]}
	data.reqs[3] = _req()
	data.reqs[4] = _req()
	_eq(evo.in_training_target(2), 3, "In-Training: equal scores, the first candidate wins")
	data.reqs[3] = _req({"bonus": {"discipline": 101}})
	_eq(evo.in_training_target(2), 4, "In-Training: the higher score wins")
	data.reqs[4] = _req({"bonus": {"discipline": 101}, "care_mistakes": {"value": 5}})
	_eq(evo.in_training_target(2), 3, "In-Training: a score of 2 never wins")
	data.reqs.clear()
	data.paths.clear()


func _averages() -> void:
	_reset("dw1:agumon")
	data.paths[3] = {"to": [5, 9, 21]}
	data.reqs[5] = _req({"stats": {"offense": 0}})
	data.reqs[9] = _req({"stats": {"defense": 0}})
	data.reqs[21] = _req({"stats": {"speed": 0}})
	_set_stats(500, 500, 50, 10, 70, 0)
	# 5: 50 -> best. 9: 10 <= 50, its sum and count stay. 21: (10 + 70) / 2 = 40 <= 50 (alone: 70).
	_eq(evo.rookie_target(3), 5, "Rookie: the averaging quirk carries a losing candidate's sum into the next")
	_set_stats(500, 500, 50, 10, 95, 0)
	_eq(evo.rookie_target(3), 21, "Rookie: (10 + 95) / 2 = 52 beats 50")
	data.reqs[5] = _req({"stats": {"hp": 0, "offense": 0}})
	_set_stats(1000, 500, 20, 10, 20, 0)
	# 5: (100 + 20) / 2 = 60; 9: 10; 21: (10 + 20) / 2 = 15.
	_eq(evo.rookie_target(3), 5, "Rookie: HP counts / 10 in the average")
	_set_stats(0, 0, 0, 0, 0, 0)
	c["evo_timer"] = 95
	_eq(evo.rookie_target(3), -1, "an average of 0 never wins")
	c["evo_timer"] = 96
	_eq(evo.rookie_target(3), 11, "no candidate at evo_timer 96: Numemon")
	_reset("dw1:greymon")
	data.paths[5] = {"to": [12]}
	data.reqs[12] = _req({"care_mistakes": {"value": 9}})
	c["evo_timer"] = 200
	_eq(evo.champion_target(5), -1, "Champion: no fallback")
	data.reqs.clear()
	data.paths.clear()


func _score() -> void:
	_reset("dw1:agumon")
	# Greymon (5): care <= 1, weight 30, Off / Def / Speed / Brain >= 100, bonus discipline 90 / techs 35.
	c["care_mistakes"] = 0
	c["weight"] = 30
	c["discipline"] = 90
	_set_stats(10, 10, 100, 100, 100, 100)
	_eq(evo.requirement_score(3, 5, -1), 4, "Greymon: all four points")
	c["care_mistakes"] = 2
	_eq(evo.requirement_score(3, 5, -1), 3, "care mistakes above an at-most requirement: no point")
	c["weight"] = 36
	_eq(evo.requirement_score(3, 5, -1), 2, "weight 36 against 30 ± 5: no point")
	c["weight"] = 25
	_eq(evo.requirement_score(3, 5, -1), 3, "weight 25: within ± 5")
	_base()["brains"] = 99
	_eq(evo.requirement_score(3, 5, -1), 2, "one stat below: no stat point")
	_base()["brains"] = 100
	c["discipline"] = 89
	_eq(evo.requirement_score(3, 5, -1), 2, "no bonus met")
	for i in 35:
		gs.state["partner"]["learned_moves"].append("dw1:move_x%d" % i)
	_eq(evo.mastered_moves() >= 35, true, "learned techniques counted")
	_eq(evo.requirement_score(3, 5, -1), 3, "the techniques bonus")
	gs.state["partner"]["learned_moves"].clear()

	# Rookie targets: the partner's highest stat (HP, MP / 10) must be marked; equal values, the last.
	_reset("dw1:koromon")
	data.reqs[3] = _req({"stat_rule": "highest", "stats": {"hp": true, "mp": false, "offense": true,
			"defense": false, "speed": false, "brain": false}, "bonus": {"discipline": 101}})
	_set_stats(1000, 0, 50, 0, 0, 0)
	_eq(evo.requirement_score(2, 3, -1), 3, "highest stat HP (1000 / 10) is marked")
	_set_stats(500, 0, 50, 0, 0, 50)
	_eq(evo.requirement_score(2, 3, -1), 2, "Offense and Brain tie at 50: the last (Brain) isn't marked")
	_set_stats(500, 0, 50, 0, 0, 40)
	_eq(evo.requirement_score(2, 3, -1), 3, "Offense alone highest")

	# The bonus flags: battles at most (0x01).
	data.reqs[3] = _req({"bonus": {"discipline": null, "battles": {"value": 2, "at_most": true}}})
	c["battles"] = 3
	_eq(evo.requirement_score(2, 3, -1), 3, "battles above an at-most bonus: no bonus")
	c["battles"] = 2
	_eq(evo.requirement_score(2, 3, -1), 4, "battles at most 2")
	data.reqs[3] = _req({"bonus": {"discipline": null, "from_digimon": 2}})
	_eq(evo.requirement_score(2, 3, -1), 4, "the bonus: comes from Koromon")
	_eq(evo.requirement_score(15, 3, -1), 3, "the bonus: from another Digimon, no point")

	# Raised: a raised target against a best not raised -> 0; the other way + 1.
	data.reqs[3] = _req()
	data.reqs[4] = _req()
	gs.set_raised(3)
	_eq(evo.requirement_score(2, 3, 4), 0, "a raised target against a best not raised: 0")
	_eq(evo.requirement_score(2, 4, 3), 5, "a target not raised against a raised best: + 1")
	_eq(evo.requirement_score(2, 4, -1), 4, "no best: no adjustment")
	gs.clear_trigger(GameState.TRIGGER_RAISED + 3)
	data.reqs.clear()


# --- special evolutions ------------------------------------------------------------------------------

func _special() -> void:
	_reset("dw1:birdramon")
	c["discipline"] = 100
	c["happiness"] = 100
	c["tiredness"] = 0
	_roll(func(r): return r < 30)
	_eq(evo.special_evolution(2), 7, "mode 2: Birdramon at discipline / happiness 100, tiredness 0 -> Airdramon")
	_eq(care.evolution_target, 7, "the target is set at once")
	_roll(func(r): return r >= 30)
	_eq(evo.special_evolution(2), -1, "mode 2: a roll of 30 or more: nothing")
	c["tiredness"] = 1
	_roll(func(r): return r < 30)
	_eq(evo.special_evolution(2), -1, "mode 2: tired: nothing")
	var tamer := Tamer.new()
	care.tamer = tamer
	tamer.set_state(Tamer.STATE_STILL)
	c["tiredness"] = 0
	_roll(func(r): return r < 30)
	_eq(evo.special_evolution(2), -1, "only with the tamer in state 0")
	tamer.set_state(Tamer.STATE_FREE)
	var partner := Partner.new()
	care.partner = partner
	_roll(func(r): return r < 30)
	evo.special_evolution(2)
	_eq([tamer.state, partner.state], [Tamer.STATE_STILL, Partner.STATE_EVOLVING], "a result: tamer state 6, partner state 13")

	_reset("dw1:koromon")
	gs.state["world"]["screen"] = "dw1:mayo02"
	_roll(func(r): return r >= 30 and r < 50)
	_eq(evo.special_evolution(2), 32, "mode 2: an In-Training at Kunemon's Bed, roll < 50 -> Kunemon")
	gs.state["world"]["screen"] = "dw1:mayo01"
	_roll(func(r): return r < 50)
	_eq(evo.special_evolution(2), -1, "elsewhere: nothing")

	_reset("dw1:whamon")
	c["evo_timer"] = 200
	_roll(func(r): return r < 30)
	_eq(evo.special_evolution(3), 49, "mode 3: Whamon at evo_timer 200 -> Coelamon")
	c["evo_timer"] = 240
	care.nanimon_trigger = true
	_roll(func(r): return r < 50)
	_eq([evo.special_evolution(3), care.nanimon_trigger], [28, false], "the later rule (Vademon) overwrites Nanimon; the trigger is cleared")
	care.nanimon_trigger = true
	_roll(func(r): return r >= 50)
	_eq([evo.special_evolution(3), care.nanimon_trigger], [53, false], "Nanimon, the trigger cleared")

	_reset("dw1:agumon")
	c["discipline"] = 0
	c["happiness"] = -100
	care.handle_praise_scold(4)
	_eq(care.nanimon_trigger, true, "a Rookie scolded at discipline 0 and happiness -100 sets the trigger")
	care.handle_praise_scold(4)
	_eq(care.nanimon_trigger, false, "the next scold clears it")
	care.tamer = null
	care.partner = null
	tamer.free()
	partner.free()


# --- the hourly check ---------------------------------------------------------------------------------

func _hourly() -> void:
	_reset("dw1:botamon")
	c["evo_timer"] = 5
	evo.hourly_check()
	_eq(care.evolution_target, -1, "Fresh at evo_timer 5: not yet")
	c["evo_timer"] = 6
	evo.hourly_check()
	_eq([care.evolution_target, c["evo_timer"]], [2, 0], "Fresh at 6: Koromon, evo_timer reset")

	_reset("dw1:botamon")
	c["evo_timer"] = 6
	var tamer := Tamer.new()
	var partner := Partner.new()
	care.tamer = tamer
	care.partner = partner
	tamer.set_state(Tamer.STATE_STILL)
	evo.hourly_check()
	_eq(care.evolution_target, -1, "the tamer busy: no timed evolution")
	tamer.set_state(Tamer.STATE_FREE)
	partner.set_state(Partner.STATE_SLEEP)
	evo.hourly_check()
	_eq(care.evolution_target, -1, "the partner not in state 1: no timed evolution")
	partner.set_state(Partner.STATE_NORMAL)
	evo.hourly_check()
	_eq([care.evolution_target, tamer.state, partner.state], [2, Tamer.STATE_STILL, Partner.STATE_EVOLVING], "state 13 started")

	# Through Care.tick_conditions, after the hour's care.
	_reset("dw1:botamon")
	c["evo_timer"] = 6
	care.tick_conditions()
	_eq(care.evolution_target, 2, "Care's tickConditions runs the hourly check")

	_reset("dw1:greymon")
	c["evo_timer"] = 360
	_roll(func(r): return r < 50)
	evo.hourly_check()
	_eq(care.evolution_target, 28, "Champion at evo_timer 360: the special evolutions of mode 3 (Vademon)")

	_reset("dw1:agumon")
	_set_stats(1200, 800, 90, 80, 70, 60)
	c["virus_bar"] = 16
	evo.hourly_check()
	_eq([care.evolution_target, gs.script_value(5), c["virus_bar"]], [0x27, 3, 0], "virus bar 16: Sukamon, script value 5 = Agumon, the bar emptied")
	_eq([c["suka_backup_hp"], c["suka_backup_mp"], c["suka_backup_off"], c["suka_backup_def"], c["suka_backup_speed"],
			c["suka_backup_brain"]], [1200, 800, 90, 80, 70, 60], "the base stats backed up")
	_reset("dw1:sukamon")
	c["virus_bar"] = 20
	evo.hourly_check()
	_eq(care.evolution_target, -1, "Sukamon itself: no virus evolution")
	care.tamer = null
	care.partner = null
	tamer.free()
	partner.free()


# --- items -------------------------------------------------------------------------------------------

func _items() -> void:
	_reset("dw1:koromon")
	_eq(evo.item_evolution(0x47), false, "an item for a Champion target on an In-Training: nothing")
	_eq([evo.used_item, care.evolution_target], [false, -1], "no flag, no target")
	_eq(evo.item_evolution(0x7D), true, "item 0x7D: no level check")
	_eq([evo.used_item, care.evolution_target], [true, 0x40], "Gigadramon, the flag set")
	_reset("dw1:agumon")
	_eq([evo.item_evolution(0x47), care.evolution_target], [true, 5], "a Rookie with the Champion item: its target")
	evo.used_item = true
	_set_stats(1000, 1000, 100, 100, 100, 100)
	evo.apply_evolution(5)
	_eq([_base()["max_hp"], _base()["offense"]], [1000, 100], "after an item: no gains")
	_eq(evo.used_item, true, "the flag stays for the session")

	# The ItemUse handler.
	var use := ItemUse.new()
	use.game_state = gs
	use.data = data
	use.care = care
	_reset("dw1:agumon")
	_eq(use.apply(0x47), true, "ItemUse: the evolution item's handler starts it")
	_eq(care.evolution_target, 5, "ItemUse: the target")


# --- EVL_applyEvolution ------------------------------------------------------------------------------

func _apply() -> void:
	# Gains: s + g / 10 if s >= g, else (g + s) / 2; the clamp.
	_reset("dw1:agumon")
	var g: Dictionary = data.evolution_gains(5)["gains"]
	_set_stats(int(g["hp"]) + 5, 0, 9990, int(g["defense"]) - 10, 0, 999)
	gs.state["tamer"]["level"] = 0
	c["evo_timer"] = 80
	c["care_mistakes"] = 3
	c["battles"] = 4
	var key := evo.apply_evolution(5)
	var b: Dictionary = _base()
	_eq(key, "dw1:greymon", "the new Digimon")
	_eq(gs.state["partner"]["digimon"], "dw1:greymon", "the game state's partner")
	_eq(b["max_hp"], int(g["hp"]) + 5 + int(g["hp"]) / 10, "HP at or above the gain: + gain / 10")
	_eq(b["max_mp"], int(g["mp"]) / 2, "MP 0: (gain + 0) / 2")
	_eq(b["defense"], (int(g["defense"]) * 2 - 10) / 2, "Defense below the gain: the mean")
	_eq([b["offense"], b["brains"]], [999, 999], "stats clamped at 999")
	_eq([c["care_mistakes"], c["battles"], c["evo_timer"]], [0, 0, 0], "care mistakes, battles, evo_timer (level change) reset")
	_eq(c["weight"], int(data.raise_data(5)["default_weight"]), "the new Digimon's weight")
	_eq(gs.is_raised(5), true, "Greymon marked raised")
	_eq(gs.state["tamer"]["level"], 0, "a new Champion: 20 % tamer level (roll dependent); checked with the Ultimate")

	# An Ultimate: lifetime + 96, tamer level + 1 when no script runs; none while one runs.
	_reset("dw1:greymon")
	gs.state["tamer"]["level"] = 0
	var life := int(c["remaining_lifetime"])
	evo.apply_evolution(27 if data.digimon(27).get("level", {}).get("id") == 5 else 26)
	_eq(int(c["remaining_lifetime"]), life + 96, "an Ultimate: 96 hours more")
	_eq(gs.state["tamer"]["level"], 1, "an Ultimate without a script: tamer level + 1")
	_reset("dw1:greymon")
	gs.state["tamer"]["level"] = 0
	var ctx := ScriptContext.new()
	ctx.is_paused = false
	evo.script_ctx = ctx
	evo.apply_evolution(26)
	_eq(gs.state["tamer"]["level"], 0, "an Ultimate while a script runs: no tamer level")
	evo.script_ctx = null

	# Scaled: Numemon x 0.8 (its scale), current HP / MP cut.
	_reset("dw1:agumon")
	_set_stats(1000, 500, 100, 50, 30, 10)
	gs.state["partner"]["stats"]["current"]["hp"] = 1000
	gs.state["partner"]["stats"]["current"]["mp"] = 100
	var pct := roundi(float(data.evolution_gains(11)["scale"]) * 10)
	evo.apply_evolution(11)
	b = _base()
	_eq([b["max_hp"], b["max_mp"], b["offense"], b["defense"], b["speed"], b["brains"]],
			[1000 * pct / 10, 500 * pct / 10, 100 * pct / 10, 50 * pct / 10, 30 * pct / 10, 10 * pct / 10], "Numemon: stats scaled")
	_eq([gs.state["partner"]["stats"]["current"]["hp"], gs.state["partner"]["stats"]["current"]["mp"]], [1000 * pct / 10, 100],
			"current HP cut to the new maximum, MP kept")

	# From Sukamon: backup + (stat - backup / 2) / 2, virus_bar 0; same level: evo_timer kept.
	_reset("dw1:sukamon")
	_set_stats(100, 100, 10, 10, 10, 10)
	for f in ["suka_backup_hp", "suka_backup_mp", "suka_backup_off", "suka_backup_def", "suka_backup_speed", "suka_backup_brain"]:
		c[f] = 40
	c["virus_bar"] = 5
	c["evo_timer"] = 50
	evo.apply_evolution(5)
	b = _base()
	_eq([b["max_hp"], b["offense"], c["virus_bar"]], [40 + (100 - 20) / 2, 40 + (10 - 20) / 2, 0], "from Sukamon: the backup formula, the bar emptied")
	_eq(c["evo_timer"], 50 if data.digimon(5)["level"]["id"] == data.digimon(0x27)["level"]["id"] else 0, "evo_timer only reset on a level change")

	# Below Rookie: scaled.
	_reset("dw1:botamon")
	_set_stats(100, 100, 10, 10, 10, 10)
	var fresh_pct := roundi(float(data.evolution_gains(2)["scale"]) * 10)
	evo.apply_evolution(2)
	b = _base()
	_eq(b["max_hp"], 100 * fresh_pct / 10, "Koromon (level < 3): scaled")

	# Item used: no scaling either.
	_reset("dw1:agumon")
	_set_stats(1000, 500, 100, 50, 30, 10)
	evo.used_item = true
	evo.apply_evolution(11)
	b = _base()
	_eq(b["max_hp"], 1000, "after an item: no scaling")
	evo.used_item = false


func _technique() -> void:
	# Greymon (fire): the block 0..8, the lowest non-zero power among its moves there, from the first.
	_reset("dw1:agumon")
	evo.apply_evolution(5)
	var rec: Dictionary = data.digimon(5)
	var block := [0, 8]
	for r in data.evolution_rules("technique_block"):
		if int(r["element"]["id"]) == int(rec["elements"][0]["id"]):
			block = [int(r["first"]), int(r["last"])]
	var best := -1
	var finisher = null
	for s in rec["moves"]:
		var id := int(s["move"]["id"])
		if id >= block[0] and id <= block[1]:
			var p := int(data.move(id)["power"])
			if best == -1 or (int(data.move(best)["power"]) > p and p != 0):
				best = id
		if data.move(id).get("category") == "finisher":
			finisher = data.move(id)["key"]
	var moves: Array = _base()["moves"]
	_eq(moves[0], data.key_of("moves/move_data", best), "slot 0: the block's weakest technique")
	_eq(gs.has_move(best), true, "learnt")
	_eq([moves[1], moves[2], moves[3]], [null, null, finisher], "slots 1, 2 empty; slot 3 the last finisher")
	_reset("dw1:botamon")
	evo.apply_evolution(2)
	_eq(_base()["moves"][0], data.key_of("moves/move_data", int(data.digimon(2)["moves"][0]["move"]["id"])),
			"below Rookie: slot 0 is the first move slot")


# --- partner state 13 ---------------------------------------------------------------------------------

func _state_13() -> void:
	_reset("dw1:botamon")
	var tamer := Tamer.new()
	var partner := Partner.new()
	var scene := StubScene.new()
	scene.evolution = evo
	partner.tamer = tamer
	partner.care = care
	partner.clock = clock
	partner.evolution_scene = scene
	care.tamer = tamer
	care.partner = partner
	clock.running = true
	c["evo_timer"] = 6
	evo.hourly_check()
	_eq(partner.state, Partner.STATE_EVOLVING, "state 13")
	tamer.position = Vector3(1000, 0, 0)
	partner.tick_evolving()
	_eq([clock.running, tamer.camera_follow, partner.sub_state], [false, false, 1], "sub-state 0: time stops, the camera stays")
	partner.tick_evolving()
	_eq([partner.sub_state, scene.started], [1, -1], "far from the tamer: walks on")
	tamer.position = Vector3(150, 0, 0)
	partner.tick_evolving()
	_eq([partner.sub_state, scene.started], [2, 2], "close: the scene starts with the target")
	for i in 4:
		_frame_13(partner, scene)
	_eq([gs.state["partner"]["digimon"], clock.running, care.evolution_target, partner.state, tamer.state, tamer.camera_follow],
			["dw1:koromon", true, -1, Partner.STATE_NORMAL, Tamer.STATE_FREE, true], "the end: Koromon, time runs, the tamer free")

	# A script evolution: the sync bit is set instead, the tamer stays.
	var ctx := ScriptContext.new()
	partner.script_ctx = ctx
	ctx.sync_bit = 0
	tamer.set_state(Tamer.STATE_SCRIPT)
	care.evolution_target = 3
	partner.set_state(Partner.STATE_EVOLVING)
	for i in 6:
		_frame_13(partner, scene)
	_eq([gs.state["partner"]["digimon"], ctx.sync_bit, tamer.state], ["dw1:agumon", 1, Tamer.STATE_SCRIPT], "a script's evolution sets the sync bit")
	care.tamer = null
	care.partner = null
	scene.free()
	tamer.free()
	partner.free()


## The loading part of getEvoSequenceState (main/evl.c) with the real partner model.
func _scene_loading() -> void:
	if not DirAccess.dir_exists_absolute(Content.root()):
		print("SKIP scene: asset porter output missing")
		return
	_reset("dw1:agumon")
	var map := FieldMap.new()
	var tamer := Node3D.new()
	root.add_child(tamer)
	var partner: Partner = load("res://scenes/field/partner.tscn").instantiate()
	root.add_child(partner)
	partner.field = map
	partner.tamer = tamer
	partner.game_state = gs
	partner.load_digimon(data, "dw1:agumon")
	var scene := EvolutionScene.new()
	scene.partner = partner
	scene.evolution = evo
	scene.game_state = gs
	scene.data = data
	scene.start(5)
	_eq([scene.digimon_id, partner.animator.anim_id], [5, 0], "start: the target's Digimon, the partner idles")
	var frames := 0
	while scene.state == EvolutionScene.STATE_LOADING:
		scene.tick()
		frames += 1
	_eq([frames, partner.animator.anim_id], [57, 1], "state 0: 57 frames (timer 0 past 55), then animation 1")
	while scene.state == EvolutionScene.STATE_LOADED:
		scene.tick()
		frames += 1
	_eq(frames, 57 + 56, "state 1: 56 more frames (from timer 1 past 55), then the evolution")
	# specs/evolution_scene.md A2, J5, K3: the sequence starts at timer 0; its first tick is the
	# next frame; frame 0x11C applies the evolution (0x11D ticks); the end when 0xB has played.
	_eq([scene.timer, partner.digimon, scene.get("sequence") != null], [0, "dw1:agumon", true],
			"the loading ends with the sequence at timer 0, no evolution yet")
	var ticks := 0
	while partner.digimon != "dw1:greymon" and ticks < 0x200:
		scene.tick()
		ticks += 1
	_eq([ticks, gs.state["partner"]["digimon"]], [0x11D, "dw1:greymon"], "frame 0x11C applies the evolution")
	var guard := 0
	var value := 0
	while value != -1 and guard < 0x200:
		if partner.animator != null and partner.animator.anim_id == 0xB:
			if partner.animator.loop_count == PsxAnimator.ENDLESS:
				partner.animator.finish_loop()
			partner.animator.frame = partner.animator.frame_count
		value = scene.tick()
		guard += 1
	_eq(value, -1, "the pose ends: timer -1")
	partner.free()
	tamer.free()
	map.free()
	scene.free()


# --- CALL_DIGIMON_ROUTINE 2 / 10 -----------------------------------------------------------------------

func _script_routines() -> void:
	_reset("dw1:sukamon")
	var ctx := ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	var files := ScriptFiles.new()
	var interp := ScriptInterpreter.new(ctx, files, null)
	interp.game_state = gs
	interp.data = data
	var partner := Partner.new()
	interp.partner = partner
	interp.care = care
	gs.set_script_value(5, 3)
	interp.call_digimon_routine(2)
	_eq([care.evolution_target, partner.state, ctx.sync_bit], [3, Partner.STATE_EVOLVING, 0], "routine 2: back to script value 5, state 13, the sync bit cleared")
	gs.set_script_value(0xFE, 41)
	interp.call_digimon_routine(10)
	_eq(care.evolution_target, 41, "routine 10: script value 0xFE")
	partner.free()
	_remodel()


## The Factorial Town remodel (script 156, section 5) end to end with Mamemon and 5000 bits.
func _remodel() -> void:
	if not Content.load_json("scripts/DG/script_156.json") is Dictionary:
		print("SKIP remodel: asset porter output missing")
		return
	_reset("dw1:mamemon")
	gs.state["money"] = 5000
	var boxes := UIBoxes.new()
	var area := TextArea.new(data, "en_us")
	var ctx := ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	var pad := Pad.new()
	var tb := TextBoxes.new(boxes, area, ctx, pad, data, gs)
	var interp := ScriptInterpreter.new(ctx, ScriptFiles.new(), tb)
	interp.game_state = gs
	interp.data = data
	var tamer := Tamer.new()
	var partner := Partner.new()
	var scene := StubScene.new()
	var map := FieldMap.new()
	map._collision.resize(100 * 100)
	map._collision.fill(0)
	partner.field = map
	scene.evolution = evo
	partner.tamer = tamer
	partner.care = care
	partner.clock = clock
	partner.script_ctx = ctx
	partner.evolution_scene = scene
	interp.tamer = tamer
	interp.partner = partner
	interp.care = care
	interp.clock = clock
	ctx.current_script_id = 156
	# STORE_RANDOM 10 is the section's only roll: seeded for a success (1-5, MetalMamemon).
	for seed in range(1, 1000):
		Rng.set_seed(seed)
		var r := Rng.random_limit(10)
		if r >= 1 and r <= 5:
			Rng.set_seed(seed)
			break
	interp.call_section(156, 5, 0)
	var frames := 0
	var evolved := false
	while not ctx.is_paused and frames < 5000:
		pad.poll(Pad.CONFIRM if frames % 2 == 1 else 0)
		pad.process()
		interp.tick_script()
		boxes.step()
		if partner.state == Partner.STATE_EVOLVING:
			evolved = true
			_frame_13(partner, scene)
		frames += 1
	var roll: int = gs.script_value(110)
	_eq(roll >= 1 and roll <= 5, true, "the remodel's roll is the seeded one (%d)" % roll)
	var expected := "dw1:giromon" if roll == 0 else "dw1:metalmamemon" if roll <= 5 else "dw1:mamemon"
	_eq([ctx.is_paused, gs.state["money"]], [true, 3000], "the remodel: the section ends, 2000 bits paid")
	_eq([gs.state["partner"]["digimon"], evolved], [expected, roll <= 5], "the remodel (roll %d): the evolution of the script" % roll)
	scene.free()
	tamer.free()
	partner.free()
	map.free()
	boxes.free()


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])
