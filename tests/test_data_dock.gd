extends SceneTree
## The "DW Data" dock (addons/dw_tools/data_dock.gd) outside the editor: renders every entity page,
## every table page and the overview, and runs the asset check. Needs both porters' output:
##   godot --headless --path . -s res://tests/test_data_dock.gd
## Exits 1 if a check fails (script errors are printed by Godot).

var _failed := 0
var _dock: Control


func _initialize() -> void:
	_dock = load("res://addons/dw_tools/data_dock.gd").new()
	root.add_child(_dock)


## First frame: the dock is in the tree (its _ready has run).
func _process(_delta: float) -> bool:
	if _dock != null:
		var dock := _dock
		_dock = null
		_run(dock)
	return false


func _run(dock: Control) -> void:
	var data: Node = dock._data
	if not data.available():
		print("SKIP: no data porter output")
		quit(0)
		return

	var pages := 0
	for kind in ["digimon", "move", "item", "card", "map", "tournament"]:
		dock._select_kind(kind)
		_eq(dock._list.item_count, data.records(data.ENTITIES[kind]).size(), kind + ": one list row per record")
		for row in dock._rows:
			var text: String = dock.entity_text(kind, row[0])
			pages += 1
			if text.begins_with("[color=red]"):
				_failed += 1
				print("FAIL %s %s: %s" % [kind, row[0], text])
	dock._select_kind("tables")
	for row in dock._rows:
		dock._open("tables", row[0])
		pages += 1

	var agumon: String = dock.entity_text("digimon", "dw1:agumon")
	for expected in ["Agumon", "dw1:agumon", "Rookie · Vaccine · Fire / Battle", "[url=move:2]Spit Fire[/url]", "[url=digimon:5]Greymon[/url]", "specs/digimon.md", "Used by the C code"]:
		_eq(agumon.contains(expected), true, "Agumon page shows " + expected)
	_eq(dock.entity_text("card", "dw1:phoenixmon").contains("[url=digimon:59]Phoenixmon[/url]"), true, "card links its Digimon")
	_eq(dock.asset_path("digimon", data.digimon(30)), "mmd_files/MMD1/TOKO.gltf", "model path uses the id / 30 folder")

	dock._select_kind("digimon")
	dock._open("digimon", "dw1:agumon")
	_eq(dock._player != null and dock._anim_button.item_count > 0, true, "Agumon preview has animations")
	dock._search.text = "grey"
	dock._fill_list()
	_eq(dock._rows.size() >= 3, true, "search 'grey' finds the Greymon entries")

	var report: String = dock.check_assets()
	print(report)
	_eq(report.contains("digimon: 178/180 found"), true, "all Digimon models but the two known gaps")
	_eq(report.contains("card: 66/66 found"), true, "every card image")
	_eq(report.contains("map: 242/244 found"), true, "every map background but YAKA01 / YAKA21")
	dock._data.set_language("ja")
	_eq(dock.entity_text("digimon", 3).contains("アグモン"), true, "Japanese names")
	dock._data.set_language("en_us")

	print("%d pages rendered" % pages)
	dock.queue_free()
	print("%s: DW Data dock checks" % ("FAILED %d" % _failed if _failed else "OK"))
	quit(1 if _failed else 0)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failed += 1
		print("FAIL %s: %s != %s" % [what, actual, expected])
