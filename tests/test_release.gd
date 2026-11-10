extends SceneTree
## Release (scripts/core/release.gd) and version.json (specs/distribution.md §4, §6):
##   godot --headless --path . -s res://tests/test_release.gd
## Exits 1 if a check fails.

var _failed := 0
var _done := false


func _init() -> void:
	var v := Release.version()
	_check(v.has("game") and v.has("content_format") and v.has("mod_api"), "version.json has game, content_format, mod_api")
	_check(Release.game().split(".").size() == 3, "game is a x.y.z version (%s)" % Release.game())

	# The game reads what this build's dw_convert writes: the two content formats agree.
	var run := FileAccess.get_file_as_string("res://dw_convert/dwconvert/run.py")
	var re := RegEx.create_from_string("(?m)^CONTENT_FORMAT = ([0-9]+)")
	var m := re.search(run)
	_check(m != null and int(m.get_string(1)) == Release.content_format(),
		"content_format %d = dw_convert run.CONTENT_FORMAT %s" % [Release.content_format(), m.get_string(1) if m else "?"])

	_check(not Release.exported(), "the tests run in the editor binary")
	_check(Release.default_dir("assets", "res://asset_porter/output", false) == "res://asset_porter/output", "editor: assets from the asset porter")
	_check(Release.default_dir("data", "res://data_porter/output", true) == "user://content/dw1/data", "exported: data from user://content/dw1")
	_check(Release.default_dir("assets", "res://asset_porter/output", true) == "user://content/dw1/assets", "exported: assets from user://content/dw1")
	if OS.get_environment("DW_PORTER_OUTPUT") == "" and not ProjectSettings.has_setting(Content.SETTING):
		_check(Content.root() == ProjectSettings.globalize_path("res://asset_porter/output"), "Content.root() in the editor")



## The DebugHost checks need the autoloads (GameState, GameData): on the first frame.
func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_dev_tools_checks()
	print("FAILED %d" % _failed if _failed else "OK")
	quit(1 if _failed else 0)
	return false


## Release.dev_tools and DebugHost when they are off (player builds).
func _dev_tools_checks() -> void:
	var cfg_path := "user://test_release_settings.cfg"
	DirAccess.remove_absolute(cfg_path)
	_check(Release.dev_tools(), "editor: developer tools on")
	_check(Release.dev_tools(false, PackedStringArray(), cfg_path), "not exported: on")
	_check(not Release.dev_tools(true, PackedStringArray(), cfg_path), "exported, no setting: off")
	_check(Release.dev_tools(true, PackedStringArray(["--dev"]), cfg_path), "exported with --dev: on")
	var cfg := ConfigFile.new()
	cfg.set_value("dev", "tools", true)
	cfg.save(cfg_path)
	_check(Release.dev_tools(true, PackedStringArray(), cfg_path), "exported, [dev] tools=true: on")
	cfg.set_value("dev", "tools", false)
	cfg.save(cfg_path)
	_check(not Release.dev_tools(true, PackedStringArray(), cfg_path), "exported, [dev] tools=false: off")
	DirAccess.remove_absolute(cfg_path)

	# Off: the help line shows only the messages, the debug keys do nothing.
	var host: Node = load("res://scripts/field/hosts/debug_host.gd").new()
	var label := Label.new()
	host.label = label
	host.enabled = false
	host.maps = PackedStringArray(["a", "b"])
	host.update_label()
	_check(not label.visible and label.text == "", "off: no help line without a message")
	host.show_message("Sleep: only while the partner is sleepy")
	_check(label.visible and label.text == "Sleep: only while the partner is sleepy", "off: a message still shows")
	for i in 100:
		host.tick_message()
	_check(not label.visible, "off: the message goes away")
	var session: Node = load("res://scripts/field/hosts/map_session.gd").new()
	host.map_session = session
	var key := InputEventKey.new()
	key.keycode = KEY_H
	key.pressed = true
	host._unhandled_key_input(key)
	_check(not label.visible, "off: H does nothing")
	host.enabled = true
	host._unhandled_key_input(key)
	_check(label.visible, "on: H toggles the help line")
	session.free()
	label.free()
	host.free()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		print("FAIL ", what)
