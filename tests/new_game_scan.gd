extends Node
## A new game started the way the game starts it (Game, scenes/game.tscn; specs/new_game.md §3.3):
## ✕ on the title menu's New Game (the cursor starts on it, title_menu.gd), with the intro skipped (DW_SKIP_INTRO=1), then played on by pressing ✕ now and then so File
## City's opening goes on:
##   godot --headless --fixed-fps 60 --path . res://tests/new_game_scan.tscn
## Checks the start (map TWNA01 at exit 9, the partner raised, its first technique, the clock
## stopped) and prints the partner's stats when they change and the help line's messages (script
## instructions not ported yet). Exits 1 if a start check fails.
## Env: NEW_GAME_FRAMES=3000 frames to play on; NEW_GAME_INTRO=1 plays the intro too (✕ through
## Jijimon's lines and choices, types "AAAAAA" for both names, Start through the movie) and checks
## that it reaches the field with those names.

var _game: Game
var _frames := 0
var _limit := 3000
var _failed := false
var _checked := false
var _last_stats := ""
var _messages := {}
var _intro := false


func _ready() -> void:
	_intro = OS.get_environment("NEW_GAME_INTRO") == "1"
	OS.set_environment("DW_SKIP_INTRO", "0" if _intro else "1")
	if OS.get_environment("NEW_GAME_FRAMES").is_valid_int():
		_limit = int(OS.get_environment("NEW_GAME_FRAMES"))
	_game = load("res://scenes/game.tscn").instantiate() as Game
	_game.field_overrides = {"debug_window": false, "render_scale": 1}
	add_child(_game)
	GameLoop.frame.connect(_frame)


func _frame() -> void:
	_frames += 1
	var field := _game.get_child(0) if _game.get_child_count() > 0 else null
	if field is TitleMenu:
		# New Game is the first item and the cursor starts on it; ✕ until the menu fades out.
		if _frames % 6 == 0:
			GameLoop.press("pad_cross")
		if _frames >= _limit:
			_check(false, "the title menu starts a new game within %d frames" % _limit)
			get_tree().quit(1)
		return
	if _intro and (field is NewGameScene or field is MoviePlayer):
		# ✕ on every line, choice and letter (six A's move the cursor to OK); Start ends the movie.
		if _frames % 6 == 0:
			GameLoop.press("pad_start" if field is MoviePlayer else "pad_cross")
		if _frames >= _limit:
			_check(false, "the intro reaches the field within %d frames (stuck in %s)" % [_limit, field.name])
			get_tree().quit(1)
		return
	if field == null or not field.is_node_ready():
		return
	if not _checked:
		_checked = true
		_check_start(field)
		if _intro:
			_check(GameState.state["tamer"]["name"] == "AAAAAA" and GameState.state["partner"]["name"] == "AAAAAA",
					"the names typed in the intro: %s / %s" % [GameState.state["tamer"]["name"],
					GameState.state["partner"]["name"]])
		var scripts: Node = field.get("scripts")
		if scripts != null:
			scripts.message.connect(func(text: String):
				if not _messages.has(text):
					_messages[text] = _frames
					print("frame %d: %s" % [_frames, text]))
	var base: Dictionary = GameState.state["partner"]["stats"]["base"]
	var stats := "off %d def %d spd %d brn %d hp %d mp %d" % [base["offense"], base["defense"], base["speed"],
			base["brains"], base["max_hp"], base["max_mp"]]
	if stats != _last_stats:
		_last_stats = stats
		print("frame %d: partner %s: %s" % [_frames, GameState.state["partner"]["digimon"], stats])
	# ✕ every 10 frames: the opening's text boxes.
	if _frames % 10 == 0:
		GameLoop.press("pad_cross")
	if _frames >= _limit:
		print("map %s, clock %s, %d frames" % [GameState.state["world"]["screen"],
				"running" if field.clock_host.clock.running else "stopped", _frames])
		print("FAILED: new game scan" if _failed else "OK: new game scan")
		get_tree().quit(1 if _failed else 0)


func _check_start(field: Node) -> void:
	var state: Dictionary = GameState.state
	var key: String = state["partner"]["digimon"]
	var first: Variant = state["partner"]["stats"]["base"]["moves"][0]
	_check(state["world"]["screen"] == GameData.key_of("systems/maps", 0xCC), "the start map is TWNA01: %s" % state["world"]["screen"])
	_check(int(state["world"]["exit"]) == 9, "at exit 9")
	_check(GameState.is_raised(key), "%s is marked raised (I-16)" % key)
	_check(first != null, "its first technique is equipped: %s" % [first])
	_check(not field.clock_host.clock.running, "the clock is stopped (stopGameTime)")
	_check(int(state["partner"]["lives"]) == 3, "3 lives")


func _check(ok: bool, what: String) -> void:
	print(("ok: " if ok else "FAIL: ") + what)
	if not ok:
		_failed = true
