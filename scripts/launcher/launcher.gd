extends Control
## The launcher (specs/launcher.md; specs/distribution.md §5): the exported game's first scene.
## It checks the converted dw1 pack (LauncherLogic.decide), asks for the disc image and runs
## dw_convert with a progress view when needed, checks once a day for a newer release (U1: a
## notice with a link), then starts the game. Hold Shift while it starts (or pass --launcher)
## for its settings: another image, convert again, the update check.
##
## Plain Godot controls on the engine's default theme: the game's font and windows come from
## the converted content, which may not exist yet.

signal page_shown(page: String)

@export_file("*.tscn") var game_scene := "res://scenes/game.tscn"
## The pack folder; tests point it elsewhere.
@export var content_dir := Release.CONTENT_DIR
## Settings file; tests point it elsewhere.
@export var settings_file := LauncherLogic.SETTINGS_FILE
## False: decide and show a page, but never leave for the game or reach the network (tests).
@export var live := true

const FONT_SIZE := 22
const UPDATE_TIMEOUT := 4.0

var page := ""
var _settings: ConfigFile
var _proc: ConverterProcess
var _converted := false
var _last_exit := 0
var _scale_mode: Window.ContentScaleMode
var _scale_size: Vector2i

var _root: VBoxContainer
var _title: Label
var _body: Label
var _path: LineEdit
var _status: Label
var _bar: ProgressBar
var _log: TextEdit
var _buttons: HBoxContainer
var _dialog: FileDialog
var _http: HTTPRequest


func _ready() -> void:
	# The game draws at 320x240 scaled up; the launcher's controls at the window's size.
	_scale_mode = get_window().content_scale_mode
	_scale_size = get_window().content_scale_size
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_settings = LauncherLogic.load_settings(settings_file)
	_build()
	var disc := _disc_path()
	if disc == "":
		disc = LauncherLogic.find_image(OS.get_executable_path().get_base_dir()) if Release.exported() else ""
		_set_disc(disc, false)
	var decision := LauncherLogic.decide(_dir(), _disc_path(), Release.content_format())
	var settings_asked := Input.is_key_pressed(KEY_SHIFT) or "--launcher" in OS.get_cmdline_user_args()
	match decision["action"]:
		LauncherLogic.READY:
			if settings_asked:
				_show_settings()
			else:
				_check_updates_then_play()
		LauncherLogic.CONVERT:
			_show_disc(decision["reason"])
			_identify()
		_:
			_show_disc(decision["reason"])


func _process(_delta: float) -> void:
	if _proc:
		_proc.poll()


func _dir() -> String:
	return ProjectSettings.globalize_path(content_dir)


func _disc_path() -> String:
	return str(_settings.get_value("disc", "path", ""))


func _set_disc(path: String, save := true) -> void:
	_settings.set_value("disc", "path", path)
	if _path:
		_path.text = path
	if save:
		_settings.save(settings_file)


# --- Pages ------------------------------------------------------------------------------------

func _build() -> void:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	theme = t
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 16)
	margin.add_child(_root)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 36)
	_root.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_body)

	var row := HBoxContainer.new()
	_path = LineEdit.new()
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.placeholder_text = "Digimon World (USA).cue"
	_path.text = _disc_path()
	_path.text_submitted.connect(func(text: String) -> void: _set_disc(text.strip_edges()); _identify())
	row.add_child(_path)
	row.add_child(_button("Browse...", _browse))
	row.name = "DiscRow"
	_root.add_child(row)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_status)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.custom_minimum_size.y = 32
	_root.add_child(_bar)
	_log = TextEdit.new()
	_log.editable = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("font_size", 16)
	_root.add_child(_log)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	_root.add_child(_buttons)

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.filters = PackedStringArray(["*.cue, *.iso, *.bin ; Disc images"])
	_dialog.file_selected.connect(func(path: String) -> void: _set_disc(path); _identify())
	add_child(_dialog)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 44)
	b.pressed.connect(action)
	return b


## Shows a page: which parts are visible, the buttons [[text, Callable], ...].
func _page(page_name: String, title: String, body: String, parts: Array, buttons: Array) -> void:
	page = page_name
	_title.text = title
	_body.text = body
	_root.get_node("DiscRow").visible = "disc" in parts
	_status.visible = "status" in parts
	_bar.visible = "bar" in parts
	_log.visible = "log" in parts
	for b in _buttons.get_children():
		b.queue_free()
	var first: Button = null
	for spec in buttons:
		var b := _button(spec[0], spec[1])
		_buttons.add_child(b)
		if first == null:
			first = b
	if first:
		first.call_deferred("grab_focus")
	page_shown.emit(page_name)


func _show_disc(reason: String) -> void:
	_page("disc", "dw_godot4",
		reason + "\n\nThis port needs your own copy of Digimon World (US release, SLUS-01032). "
		+ "Choose its disc image (.cue, .bin or .iso): the game content is converted from it once, "
		+ "on this computer, into " + _dir() + ". It takes about 25 minutes.",
		["disc", "status"], [["Convert", _convert], ["Quit", _quit]])
	_status.text = ""


func _show_settings() -> void:
	var info := LauncherLogic.read_json(_dir().path_join("content.json"))
	_page("settings", "Settings",
		"Game %s. Content converted %s from %s.\nThe disc image below is used when the content has to be converted again."
			% [Release.game(), str(info.get("converted", "?")), str(info.get("boot", "?"))],
		["disc", "status"],
		[["Play", _play], ["Convert again", _convert], [_update_toggle_text(), _toggle_updates], [_dev_toggle_text(), _toggle_dev], ["Quit", _quit]])
	_status.text = ""


func _update_toggle_text() -> String:
	return "Update check: " + ("on" if _settings.get_value("updates", "check", true) else "off")


func _toggle_updates() -> void:
	_settings.set_value("updates", "check", not _settings.get_value("updates", "check", true))
	_settings.save(settings_file)
	_show_settings()


## The debugger window and the debug keys in the game (Release.dev_tools).
func _dev_toggle_text() -> String:
	return "Developer tools: " + ("on" if _settings.get_value("dev", "tools", false) else "off")


func _toggle_dev() -> void:
	_settings.set_value("dev", "tools", not _settings.get_value("dev", "tools", false))
	_settings.save(settings_file)
	_show_settings()


func _browse() -> void:
	var current := _path.text.strip_edges()
	if current != "":
		_dialog.current_dir = current.get_base_dir()
	_dialog.popup_centered_ratio(0.7)


# --- The disc and the conversion --------------------------------------------------------------

## dw_convert identify on the image in the path field: the status line says if it is usable.
func _identify() -> void:
	var image := _path.text.strip_edges()
	if image == "" or _busy():
		return
	if image != _disc_path():
		_set_disc(image)
	if not FileAccess.file_exists(image):
		_status.text = "File not found: " + image
		return
	_status.text = "Checking the disc image..."
	_run(PackedStringArray(["identify", image]), _on_identify_line, _on_identified)


func _on_identify_line(text: String) -> void:
	if text.strip_edges() != "":
		_status.text = text


func _on_identified(code: int) -> void:
	if code != 0 and _status.text == "Checking the disc image...":
		_status.text = "This image can't be used (dw_convert exit code %d)." % code


func _convert() -> void:
	var image := _path.text.strip_edges()
	if image == "" or not FileAccess.file_exists(image):
		_status.text = "Choose the disc image first."
		return
	if _busy():
		return
	_set_disc(image)
	var out := _dir() + ".new"
	LauncherLogic.remove_tree(out)
	DirAccess.make_dir_recursive_absolute(out)
	_page("progress", "Converting the game content", "From " + image, ["status", "bar", "log"],
		[["Cancel", _cancel]])
	_bar.value = 0
	_log.text = ""
	_status.text = "Starting dw_convert..."
	_run(PackedStringArray(["run", image, out]), _on_convert_line, _on_converted)


func _on_convert_line(text: String) -> void:
	var p := LauncherLogic.parse_progress(text)
	if p.is_empty():
		_log.text += text + "\n"
		_log.scroll_vertical = _log.get_line_count()
	else:
		_bar.value = p[0]
		_status.text = p[1]


func _on_converted(code: int) -> void:
	_last_exit = code
	var out := _dir() + ".new"
	if code == 0:
		_finish(out)
		return
	var log_path := out.path_join("convert.log")
	var why: String = {
		-1: "The conversion was cancelled.",
		1: "The disc image can't be used, or dw_convert stopped with an error.",
		2: "The content was converted, but some of the porters' checks failed: the game may show wrong things.",
	}.get(code, "dw_convert ended with exit code %d." % code)
	var buttons := [["Try again", _convert], ["Choose another image", func() -> void: _show_disc("")],
		["Open the log", func() -> void: OS.shell_open(log_path)], ["Quit", _quit]]
	if code == 2:
		buttons.insert(0, ["Use it anyway", func() -> void: _accept_and_finish(out)])
	_page("failed", "Conversion failed" if code != 2 else "Conversion finished with problems",
		why + "\nThe log: " + log_path, ["log"], buttons)


func _accept_and_finish(out: String) -> void:
	var path := out.path_join("content.json")
	var info := LauncherLogic.read_json(path)
	info["accepted"] = true
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(info, " ") + "\n")
	f.close()
	_finish(out)


func _finish(out: String) -> void:
	_status.text = "Putting the content in place..."
	var err := LauncherLogic.swap_in(out, _dir())
	if err != OK:
		_page("failed", "Conversion failed", "Couldn't move %s to %s (error %d)." % [out, _dir(), err],
			[], [["Try again", _convert], ["Quit", _quit]])
		return
	_converted = true
	_page("done", "Ready", "The game content is converted. It stays in " + _dir()
		+ "; you won't need the disc image again unless an update changes the converter.",
		[], [["Play", _play], ["Quit", _quit]])


func _cancel() -> void:
	if _proc:
		_proc.kill()


func _busy() -> bool:
	return _proc != null and _proc.running()


func _run(args: PackedStringArray, on_line: Callable, on_done: Callable) -> void:
	var command := LauncherLogic.converter_command()
	_proc = ConverterProcess.new()
	_proc.line.connect(func(text: String) -> void: print("dw_convert: ", text))
	_proc.line.connect(on_line)
	_proc.finished.connect(on_done)
	if not _proc.start(command, args):
		_proc = null
		on_line.call("Couldn't start " + command[-1])
		on_done.call(1)


# --- Updates and the game ---------------------------------------------------------------------

func _check_updates_then_play() -> void:
	var now := int(Time.get_unix_time_from_system())
	var due := LauncherLogic.update_due(_settings.get_value("updates", "check", true), Release.repo(),
		int(_settings.get_value("updates", "last_check", 0)), now)
	if not live or not due:
		_page("starting", "dw_godot4", "Starting...", [], [])
		if live:
			_play.call_deferred()
		return
	_page("starting", "dw_godot4", "Checking for a new version...", [], [])
	_http = HTTPRequest.new()
	_http.timeout = UPDATE_TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_release.bind(now))
	var err := _http.request(LauncherLogic.RELEASES_API % Release.repo(),
		PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: dw_godot4-launcher"]))
	if err != OK:
		_play()


func _on_release(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray, now: int) -> void:
	_settings.set_value("updates", "last_check", now)
	_settings.save(settings_file)
	var release := {}
	if result == HTTPRequest.RESULT_SUCCESS and status == 200:
		release = LauncherLogic.parse_release(JSON.parse_string(body.get_string_from_utf8()))
	if not release.is_empty() and LauncherLogic.newer(release["version"], Release.game()):
		_show_update(release)
	else:
		_play()


func _show_update(release: Dictionary) -> void:
	_page("update", "Version %s is out" % release["version"],
		"You have %s. Download the new zip from the release page and unzip it over this folder: your saves and the converted content are kept." % Release.game(),
		["log"], [["Open the release page", func() -> void: OS.shell_open(release["url"])], ["Later", _play]])
	_log.text = release["notes"]


func _play() -> void:
	if not live:
		return
	if _converted:
		# The autoloads (GameData, Sound) read the content when the game starts: start again.
		OS.set_restart_on_exit(true, OS.get_cmdline_args())
		get_tree().quit()
		return
	get_window().content_scale_mode = _scale_mode
	get_window().content_scale_size = _scale_size
	get_tree().change_scene_to_file(game_scene)


func _quit() -> void:
	if _proc:
		_proc.kill()
	get_tree().quit()
