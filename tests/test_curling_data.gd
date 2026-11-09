extends SceneTree
## Curling's data and assets on the Godot side (specs/curling.md §4, step C1): GameData.curling(),
## GameData.curling_map(map) and the FRZL17 sheet through Content. Acceptance checks written by the
## reviewer; don't change them to make the code pass.
##   godot --headless --path . -s res://tests/test_curling_data.gd
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
	var c: Dictionary = data.curling()
	_check(not c.is_empty(), "GameData.curling() returns the record")
	# checkCurlingMap (src/main/kar.c:10): map 136 only, by key or id.
	_check(not data.curling_map("dw1:frzl17").is_empty(), "curling_map(\"dw1:frzl17\")")
	_check(not data.curling_map(136).is_empty(), "curling_map(136)")
	_check(data.curling_map(134).is_empty(), "no curling on FRZL15 (134)")
	_check(data.curling_map("dw1:mayo10").is_empty(), "no curling on MAYO10")
	var weights := []
	for t in c.get("stone_types", []):
		weights.append(int(t["weight"]))
	_check(weights == [30, 25, 35, 30], "weights (MAIN_D_80134A08): %s" % [weights])
	_check(int(c.get("pstat_opponent", -1)) == 0x7A and int(c.get("pstat_result", -1)) == 0x79, "pstats 0x7A / 0x79")
	# The sheet the HUD and the stones read (asset porter, maps family).
	_check(Content.exists("maps/FRZL17/curling/sheet.json"), "maps/FRZL17/curling/sheet.json")
	for n in [1, 3, 7, 8, 9, 10, 11, 12]:
		_check(Content.exists("maps/FRZL17/curling/sheet.p%02d.png" % n), "sheet palette %d" % n)
	_check(Content.exists("tmd_files/ETCDAT/KARRING.gltf"), "KARRING.gltf")
	data.free()
	print("%s: curling data checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: " + what)
