extends SceneTree
## The project's code rules that a script can check (docs/porting_checklist.md "Checked by
## tests/test_rules.gd"; specs/scenes.md §3, specs/content.md §4). Scans every .gd file under
## res://scripts:
##   godot --headless --path . -s res://tests/test_rules.gd
## Exits 1 if a check fails. A rule that has a real exception lists the file in its ALLOWED set
## with the reason; anything else is a finding to fix, not to allow.

const ROOT := "res://scripts"

## specs/scenes.md §3 rule 2: no lookups across the tree. Searching a model's own subtree
## (`model.find_children(...)`) is fine; reaching up or to the root is not.
const TREE_LOOKUPS := [
	["get_tree().root", "reaches the tree root"],
	["get_tree().current_scene", "reaches the current scene"],
	["get_parent().find_child", "searches outside the node"],
	["owner.find_child", "searches outside the node"],
	["get_nodes_in_group(", "group lookup for wiring (debug tools only)"],
]
const TREE_ALLOWED := {
	# scripts/debug/ is the debug overlay: groups are fine there (specs/scenes.md §3 rule 2).
}

## Autoloads are not engine singletons: Engine.has_singleton("GameState") is always false.
const SINGLETON_CALLS := ["Engine.has_singleton(", "Engine.get_singleton("]

## Shaders go in .gdshader files (res://shaders/, or next to their scene) so a mod can replace
## them (specs/scenes.md §3 rule 7). Variants that differ in render_mode share a .gdshaderinc.

## specs/content.md §4: logic reads properties, never ids. A comparison of an id with a number
## other than the "none" sentinels (-1, 0, 0xFF) names a specific record, and so does a
## constant like `BABY_IDS := [1, 15, 29, 43]` (that one is data/systems "babies").
const ID_DIRS := ["res://scripts/systems", "res://scripts/field", "res://scripts/script",
		"res://scripts/state", "res://scripts/training"]
const ID_SENTINELS := ["-1", "0", "0xFF", "0xff", "255"]

var _failed := 0
var _files := 0
var _id_re := RegEx.new()
var _root_re := RegEx.new()
var _id_const_re := RegEx.new()


func _initialize() -> void:
	_root_re.compile("get_node(_or_null)?\\(\"/root/([A-Za-z0-9_]+)")
	_id_const_re.compile("const\\s+\\w*(DIGIMON|ITEM|MOVE|TECHNIQUE|MAP|BABY|BABIES|SPECIES|EGG)\\w*_IDS?\\b")
	_id_re.compile("\\b(digimon|item|move|technique|map|species)(_id)?\\s*(==|!=|>=|<=|<|>)\\s*(-?0x[0-9A-Fa-f]+|-?[0-9]+)\\b")
	for path in _scripts(ROOT):
		_files += 1
		_check(path)
	_ok(_files > 0, "found scripts under %s" % ROOT)
	_stand_ins_6_2()
	print("%s: rule checks (%d files)" % ["FAILED %d" % _failed if _failed else "OK", _files])
	quit(1 if _failed else 0)


## Step 6-2's stand-ins stay gone (specs/death_scene.md §2, §7).
const STAND_INS_6_2 := ["partner_dissolve.gdshader", "_spawn_egg", "_start_dissolve", "_draw_dissolve", "_end_dissolve"]


func _stand_ins_6_2() -> void:
	var found := []
	for path in _scripts(ROOT):
		var text := FileAccess.get_file_as_string(path)
		for name in STAND_INS_6_2:
			if text.contains(name):
				found.append("%s in %s" % [name, path.get_file()])
	if found.is_empty():
		return
	_fail("6-2 stand-ins back: " + ", ".join(found))


func _check(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var in_debug := path.begins_with("res://scripts/debug/")
	var id_scope := ID_DIRS.any(func(d): return path.begins_with(d))
	for i in lines.size():
		var code := _code(lines[i])
		if code.is_empty():
			continue
		var at := "%s:%d" % [path, i + 1]
		for rule in TREE_LOOKUPS:
			if code.contains(rule[0]) and not in_debug and not TREE_ALLOWED.has(path):
				_fail("%s: %s (%s); inject the reference or use an @export / fixed child" % [at, rule[0], rule[1]])
		# The documented service fallback (specs/scenes.md §3 rule 2): an injected var that is
		# still null in _ready takes the autoload by its /root path. Any other node is a finding.
		for m in _root_re.search_all(code):
			if not ProjectSettings.has_setting("autoload/" + m.get_string(2)):
				_fail("%s: /root/%s is not an autoload; inject the reference" % [at, m.get_string(2)])
		for call in SINGLETON_CALLS:
			if code.contains(call):
				_fail("%s: %s doesn't see autoloads; use the autoload name or inject it" % [at, call])
		if code.contains("shader_type"):
			_fail("%s: shader written as a string; put it in a .gdshader file" % at)
		if id_scope:
			if _id_const_re.search(code) != null:
				_fail("%s: record ids kept as a constant; put them in the data (specs/content.md §4)" % at)
			for m in _id_re.search_all(code):
				if not m.get_string(4) in ID_SENTINELS:
					_fail("%s: '%s' names a record by id; read a property (specs/content.md §4)" % [at, m.get_string()])


## The line without its comment. Strings are kept, so a `#` inside quotes cuts the line short;
## that only hides code from the checks, it never reports a false finding.
func _code(line: String) -> String:
	var hash := line.find("#")
	return (line if hash < 0 else line.substr(0, hash)).strip_edges()


func _scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out


func _ok(cond: bool, what: String) -> void:
	if not cond:
		_fail(what)


func _fail(what: String) -> void:
	_failed += 1
	print("FAIL: ", what)
