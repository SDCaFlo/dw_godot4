extends SceneTree
## The debugger's State tab (scripts/debug/state_tab.gd): its actions on a fresh game state.
##   godot --headless --path . -s res://tests/test_debug_state.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var data: Node = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: porter output missing")
		quit(0)
		return false
	var gs: Node = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()
	var tab := DebugStateTab.new()
	tab.game_state = gs
	tab.data = data
	root.add_child(tab)
	_check(tab.name == "State", "the tab is named State")

	tab.set_trigger(221, true)
	_check(gs.is_trigger_set(221), "Set: trigger 221")
	tab.set_trigger(221, false)
	_check(not gs.is_trigger_set(221), "Clear: trigger 221")

	var presets: Array = tab.presets()
	var birdramon: Array = presets.filter(func(p): return str(p["name"]).begins_with("Birdramon"))
	_check(birdramon.size() == 1 and birdramon[0]["triggers"] == [221, 190, 188, 351, 147, 210],
			"the Birdramon preset holds every destination's trigger: %s" % [birdramon])
	tab.set_triggers(birdramon[0]["triggers"], true)
	var all := true
	for record in data.system("birdramon_transport"):
		all = all and gs.is_trigger_set(int(record["trigger"]))
	_check(all, "the preset sets them all")
	var jukebox: Array = presets.filter(func(p): return str(p["name"]).begins_with("Jukebox"))
	_check(jukebox.size() == 1 and jukebox[0]["triggers"] == [50], "the jukebox preset: trigger 50")

	tab.set_money(1234567, 12345)
	_check(int(gs.state["money"]) == 999999 and int(gs.state["merit"]) == 9999, "bits and merit, capped")
	tab.set_stats([120, 50, 30, 20, 10, 95000])
	var base: Dictionary = gs.state["partner"]["stats"]["base"]
	_check(int(base["max_hp"]) == 120 and int(base["speed"]) == 10 and int(base["brains"]) == 999, "the partner's stats, capped")
	_check(tab.give(data.id_of("items/item_data", "dw1:meat"), 5) and gs.item_count("dw1:meat") == 5, "Give: 5 Meat")
	tab.set_card(1, 4)
	_check(gs.card_count(1) == 4, "a card count")
	tab.all_cards(1)
	var priced: Array = data.records("items/card_data").filter(func(r): return r.get("price") != null)
	_check(priced.all(func(r): return gs.card_count(int(r["id"])) == 1), "All cards: every priced card once")
	tab.refresh()

	tab.free()
	gs.free()
	data.free()
	print("%s: debug state checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)
