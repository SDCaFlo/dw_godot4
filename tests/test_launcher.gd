extends SceneTree
## The launcher (scripts/launcher/, specs/launcher.md):
##   godot --headless --path . -s res://tests/test_launcher.gd
## LauncherLogic's decisions, ConverterProcess and the launcher scene's pages and conversion,
## with tests/fixtures/fake_convert.py standing in for dw_convert (needs python on PATH). Works in
## user://test_launcher/ (deleted at the end). Exits 1 if a check fails.

const WORK := "user://test_launcher"
const FAKE := "res://tests/fixtures/fake_convert.py"

var _failed := 0
var _checks := 0
var _work := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_work = ProjectSettings.globalize_path(WORK)
	LauncherLogic.remove_tree(_work)
	DirAccess.make_dir_recursive_absolute(_work)
	_logic()
	await _process_checks()
	await _scene_checks()
	LauncherLogic.remove_tree(_work)
	print("FAILED %d" % _failed if _failed else "OK: launcher checks (%d run)" % _checks)
	quit(1 if _failed else 0)


func _logic() -> void:
	var pack := _work.path_join("pack")
	var disc := _work.path_join("disc.cue")
	_write(disc, "")
	_eq(LauncherLogic.decide(pack, "", 1)["action"], LauncherLogic.ASK_DISC, "no pack, no image: ask")
	_eq(LauncherLogic.decide(pack, disc, 1)["action"], LauncherLogic.CONVERT, "no pack, an image: convert")
	_eq(LauncherLogic.decide(pack, _work.path_join("gone.cue"), 1)["action"], LauncherLogic.ASK_DISC, "image gone: ask")
	_make_pack(pack, {"content_format": 1, "ok": true})
	_eq(LauncherLogic.decide(pack, "", 1)["action"], LauncherLogic.READY, "a pack: ready")
	_eq(LauncherLogic.decide(pack, disc, 2)["action"], LauncherLogic.CONVERT, "older content_format: convert again")
	_make_pack(pack, {"content_format": 1, "ok": false})
	_eq(LauncherLogic.decide(pack, disc, 1)["action"], LauncherLogic.CONVERT, "failed checks: convert again")
	_make_pack(pack, {"content_format": 1, "ok": false, "accepted": true})
	_eq(LauncherLogic.decide(pack, disc, 1)["action"], LauncherLogic.READY, "failed checks, accepted: ready")
	DirAccess.remove_absolute(pack.path_join("data/catalog.json"))
	_eq(LauncherLogic.decide(pack, disc, 1)["action"], LauncherLogic.CONVERT, "data missing: convert again")

	_eq(LauncherLogic.parse_progress("PROGRESS 0.250 assets: maps"), [0.25, "assets: maps"], "progress line")
	_eq(LauncherLogic.parse_progress("PROGRESS 1.000"), [1.0, ""], "progress without a message")
	_eq(LauncherLogic.parse_progress("assets maps: 3/3 checks passed"), [], "other line")
	_eq(LauncherLogic.parse_progress("PROGRESS x y"), [], "bad fraction")

	_eq(LauncherLogic.newer("0.2.0", "0.1.9"), true, "0.2.0 > 0.1.9")
	_eq(LauncherLogic.newer("v0.10.0", "0.9.0"), true, "v0.10.0 > 0.9.0 (numbers, not text)")
	_eq(LauncherLogic.newer("0.1.0", "0.1.0"), false, "same version")
	_eq(LauncherLogic.newer("0.1.0-beta", "0.1.0"), false, "suffix ignored")
	_eq(LauncherLogic.newer("0.1", "0.1.1"), false, "shorter")
	_eq(LauncherLogic.update_due(true, "o/r", 0, 100000), true, "a day after: due")
	_eq(LauncherLogic.update_due(true, "o/r", 50000, 100000), false, "within a day: not due")
	_eq(LauncherLogic.update_due(false, "o/r", 0, 100000), false, "turned off")
	_eq(LauncherLogic.update_due(true, "", 0, 100000), false, "no repository")
	_eq(LauncherLogic.parse_release({"tag_name": "v0.2.0", "body": "notes", "html_url": "u"}),
		{"version": "0.2.0", "notes": "notes", "url": "u"}, "release JSON")
	_eq(LauncherLogic.parse_release({"tag_name": "v0.2.0", "body": null}).get("notes"), "", "release without notes")
	_eq(LauncherLogic.parse_release({"message": "Not Found"}), {}, "no release")

	var images := _work.path_join("images")
	DirAccess.make_dir_recursive_absolute(images)
	_eq(LauncherLogic.find_image(images), "", "no image in the folder")
	_write(images.path_join("Game.bin"), "")
	_write(images.path_join("Game.cue"), "")
	_eq(LauncherLogic.find_image(images).get_file(), "Game.cue", "the .cue before the .bin")

	OS.set_environment("DW_CONVERT", "C:/x/dw_convert.py")
	_eq(LauncherLogic.converter_command(), PackedStringArray(["python", "C:/x/dw_convert.py"]), "DW_CONVERT .py")
	OS.set_environment("DW_CONVERT", "")
	_eq(LauncherLogic.converter_command(true)[0].get_file(), "dw_convert.exe", "exported: tools/dw_convert/dw_convert.exe")
	_eq(LauncherLogic.converter_command(true)[0].get_base_dir().get_file(), "dw_convert", "exported: in tools/dw_convert/")

	var a := _work.path_join("swap")
	_make_pack(a + ".new", {"n": 2})
	_make_pack(a, {"n": 1})
	_eq(LauncherLogic.swap_in(a + ".new", a), OK, "swap")
	_eq(LauncherLogic.read_json(a.path_join("content.json")).get("n"), 2.0, "the new pack in place")
	_eq(DirAccess.dir_exists_absolute(a + ".new") or DirAccess.dir_exists_absolute(a + ".old"), false, "no leftovers")


func _process_checks() -> void:
	var p := ConverterProcess.new()
	var lines: Array[String] = []
	var codes: Array[int] = []
	p.line.connect(func(t: String) -> void: lines.append(t))
	p.finished.connect(func(c: int) -> void: codes.append(c))
	var out := _work.path_join("proc_out")
	_eq(p.start(_fake(), PackedStringArray(["run", "problems.cue", out])), true, "process starts")
	await _until(func() -> bool: p.poll(); return not codes.is_empty())
	_eq(codes, [2], "exit code 2 from the fake")
	_eq("PROGRESS 1.000 done in 0 s" in lines, true, "stdout lines read")
	_eq("a warning on stderr" in lines, true, "stderr lines read")
	_eq(p.running(), false, "not running after finished")


func _scene_checks() -> void:
	OS.set_environment("DW_CONVERT", ProjectSettings.globalize_path(FAKE))
	var packed: PackedScene = load("res://scenes/launcher/launcher.tscn")

	# A ready pack: starting (never leaves: live = false).
	var ready := _work.path_join("ready")
	_make_pack(ready, {"content_format": Release.content_format(), "ok": true})
	var l := await _launcher(packed, ready)
	_eq(l.page, "starting", "ready pack: starts the game")
	l.queue_free()

	# No pack: the disc page; then the conversion with the fake.
	var pack := _work.path_join("dw1")
	l = await _launcher(packed, pack)
	_eq(l.page, "disc", "no pack: asks for the disc")
	var disc := _work.path_join("Digimon World (USA).cue")
	_write(disc, "")
	l._path.text = disc
	l._identify()
	await _until(func() -> bool: return not l._busy())
	_eq(l._status.text.begins_with("Digimon World, US release"), true, "identify message shown")
	l._convert()
	_eq(l.page, "progress", "converting: progress page")
	await _until(func() -> bool: return l.page != "progress")
	_eq(l.page, "done", "converted")
	_eq(l._bar.value, 1.0, "progress bar at the end")
	_eq(FileAccess.file_exists(pack.path_join("content.json")), true, "the pack moved in place")
	_eq(DirAccess.dir_exists_absolute(pack + ".new"), false, "no .new folder left")
	_eq(LauncherLogic.load_settings(l.settings_file).get_value("disc", "path", ""), disc, "disc path remembered")
	_eq(LauncherLogic.decide(pack, disc, Release.content_format())["action"], LauncherLogic.READY, "ready afterwards")
	l.queue_free()

	# Checks failed (exit 2): "Use it anyway" accepts the pack.
	var bad := _work.path_join("problems")
	l = await _launcher(packed, bad)
	var disc2 := _work.path_join("problems.cue")
	_write(disc2, "")
	l._path.text = disc2
	l._convert()
	await _until(func() -> bool: return l.page != "progress")
	_eq(l.page, "failed", "exit 2: the problems page")
	l._accept_and_finish(bad + ".new")
	_eq(l.page, "done", "used anyway")
	_eq(LauncherLogic.decide(bad, disc2, Release.content_format())["action"], LauncherLogic.READY, "accepted pack is ready")
	l.queue_free()
	OS.set_environment("DW_CONVERT", "")


func _launcher(packed: PackedScene, dir: String) -> Control:
	var l: Control = packed.instantiate()
	if not "live" in l:
		_eq(false, true, "the launcher script loads")
		quit(1)
	l.live = false
	l.content_dir = dir
	l.settings_file = dir + "_settings.cfg"
	root.add_child(l)
	await process_frame
	return l


func _until(cond: Callable, seconds := 30.0) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			_eq(false, true, "timed out")
			return
		await process_frame


func _fake() -> PackedStringArray:
	return PackedStringArray(["python", ProjectSettings.globalize_path(FAKE)])


func _make_pack(dir: String, info: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir.path_join("assets"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("data"))
	_write(dir.path_join("data/catalog.json"), "{}")
	_write(dir.path_join("content.json"), JSON.stringify(info))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _eq(got: Variant, want: Variant, what: String) -> void:
	_checks += 1
	if got != want:
		_failed += 1
		print("FAIL %s: got %s, want %s" % [what, got, want])
