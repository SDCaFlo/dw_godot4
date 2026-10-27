extends SceneTree
## The debugger's partner tools (scripts/debug/partner_tools.gd):
##   godot --headless --path . -s res://tests/test_partner_tools.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _run() -> void:
	var data: Node = load("res://scripts/data/game_data.gd").new()
	if not data.available() or data.records("evolution/rules").is_empty():
		print("SKIP: data porter output missing")
		data.free()
		quit(0)
		return
	var gs: Node = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	var clock := Clock.new()
	clock.game_state = gs
	var care := Care.new()
	care.game_state = gs
	care.data = data
	care.clock = clock
	var evo := Evolution.new()
	evo.game_state = gs
	evo.data = data
	evo.care = care
	evo.clock = clock
	care.evolution = evo
	gs.new_game("dw1:agumon")
	care.initialize_partner()

	# The candidates: every partner Digimon with a level (the tamer left out), by property.
	var candidates := DebugPartnerTools.candidates(data)
	var ids := candidates.map(func(c): return c[0])
	_check(not ids.has(0), "the tamer isn't a candidate")
	_check(ids.has(data.id_of("digimon/digimon_data", "dw1:agumon")), "Agumon is a candidate")
	_check(candidates.all(func(c): return data.digimon(c[0]).get("partner", false)), "candidates are partners")
	# 64: WereGarurumon (62) is a partner record without a level (no evolution reaches it).
	_check(candidates.size() == 64, "64 candidates (got %d)" % candidates.size())

	# The techniques: the Digimon's own without its finishers; every one = the Techniques screen's.
	var own := DebugPartnerTools.digimon_moves(data, "dw1:agumon")
	_check(not own.is_empty(), "Agumon has techniques")
	_check(own.all(func(m): return data.move(m).get("category") != "finisher"), "no finisher in its techniques")
	var every := DebugPartnerTools.every_move(data)
	_check(every.size() == 58, "58 techniques (got %d)" % every.size())
	_check(own.all(func(m): return every.has(m)), "its techniques are on the Techniques screen")

	var before: int = gs.state["partner"]["learned_moves"].size()
	var added: int = DebugPartnerTools.learn(gs, own)
	_check(added > 0 and gs.state["partner"]["learned_moves"].size() == before + added, "learn its techniques")
	_check(own.all(func(m): return gs.has_move(m)), "its techniques learnt")
	DebugPartnerTools.learn(gs, every)
	_check(every.all(func(m): return gs.has_move(m)), "every technique learnt")
	_check(DebugPartnerTools.learn(gs, every) == 0, "learning again adds nothing")

	# Digivolve to: through Evolution.start; not twice.
	var target: int = data.id_of("digimon/digimon_data", "dw1:greymon")
	_check(DebugPartnerTools.evolve_blocker(null) == "no partner", "no care: blocked")
	_check(DebugPartnerTools.evolve(care, target) == "", "the evolution starts")
	_check(care.evolution_target == target, "evolution target set")
	_check(DebugPartnerTools.evolve(care, target) == "already evolving", "not twice")
	evo.apply_evolution(care.evolution_target)
	_check(gs.state["partner"]["digimon"] == "dw1:greymon", "the partner is Greymon")

	care.free()
	clock.free()
	gs.free()
	data.free()
	print("%s: partner tools checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
