extends SceneTree
## Release (scripts/core/release.gd) and version.json (specs/distribution.md §4, §6):
##   godot --headless --path . -s res://tests/test_release.gd
## Exits 1 if a check fails.

var _failed := 0


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

	print("FAILED %d" % _failed if _failed else "OK")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		print("FAIL ", what)
