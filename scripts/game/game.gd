class_name Game
extends Node
## The game's start (main, main/main.c:3410-3530; specs/save.md, specs/new_game.md §3.1): the
## project's main scene. It shows one part at a time as its child, in the original's order:
## the title menu (TitleMenu), then for a new game (mode 0) the intro (NewGameScene), movie 1,
## then the field on the start map with the partner the answers picked. Continuing a game
## (modes 1 and 2) loads the saved slot and boots directly into the saved map (mode 2 plays
## movie 2 first). The ending (the field's game_ended, MAIN_STATE = 3) frees the field, plays the
## credits (movie 3, not skippable) and starts over at the title (main.c:3522-3527, the boot loop).
## The parts are exported scenes, so a mod can replace one. Running field.tscn on its own keeps
## the field's debug start.
##
## Debug:
##   DW_SKIP_TITLE=1 skips the title menu straight into a new game.
##   DW_SKIP_INTRO=1 skips the intro and the movie (answer 0, the default names).

@export var title_scene: PackedScene = preload("res://scenes/title/title_menu.tscn")
@export var new_game_scene: PackedScene = preload("res://scenes/new_game/new_game.tscn")
@export var movie_scene: PackedScene = preload("res://scenes/movie/movie_player.tscn")
@export var field_scene: PackedScene = preload("res://scenes/field/field.tscn")

## Properties set on the field before it starts (the scans: debug_window, render_scale).
var field_overrides := {}

## The answer's script value (newGameStateMachine steps 8 / 9).
const ANSWER_VALUE := 0xFE

var _part: Node


func _ready() -> void:
	if not GameData.available():
		push_error("Game: no game data (run the data porter)")
		return
	if OS.get_environment("DW_SKIP_TITLE") == "1":
		_new_game()
		return
	_title()


func _title() -> void:
	var title := _show(title_scene) as TitleMenu
	var action: String = await title.finished
	match action:
		"new_game":
			_new_game()
		"load_game":
			_continue_game(title.selected_slot)
		_:
			_new_game()


## Mode 1 (main.c:3460-3473) & Mode 2 (main.c:3474-3491).
func _continue_game(slot: int) -> void:
	var res := GameState.load_game(slot)
	if not res.get("ok", false):
		push_error("Game: failed to load slot %d: %s" % [slot, res.get("error", "")])
		_title()
		return
	var boot_mode: int = int(GameState.state.get("boot_mode", GameState.BOOT_CONTINUE))
	if boot_mode == GameState.BOOT_GAME_CLEARED:
		Sound.music.stop_bgm()
		var movie := _show(movie_scene) as MoviePlayer
		movie.play(2)
		await movie.finished
	_start_field()


## Mode 0 (main.c:3438-3454).
func _new_game() -> void:
	GameState.new_game()
	var new_game: Dictionary = _new_game_record()
	if OS.get_environment("DW_SKIP_INTRO") != "1":
		var intro := _show(new_game_scene)
		await intro.finished
		# finalizeMusic, playMovie(1, 1), initializeMusic.
		Sound.music.stop_bgm()
		var movie := _show(movie_scene) as MoviePlayer
		movie.play(int(new_game.get("movie", 1)))
		await movie.finished
	GameState.start_new_game_partner(GameState.script_value(ANSWER_VALUE))
	_start_field()


## The field on the record's map; its game_ended ends the game.
func _start_field() -> void:
	var field := field_scene.instantiate()
	field.set("boot", true)
	for property in field_overrides:
		field.set(property, field_overrides[property])
	if field.has_signal("game_ended"):
		field.connect("game_ended", _end_game, CONNECT_ONE_SHOT)
	_replace(field)


## main.c:3522-3527: while (MAIN_STATE != 3) gameLoop(); cleanupGame (the field freed), finalizeMusic,
## playMovie(3, 1); then the boot loop again (main.c:3410: the title).
func _end_game() -> void:
	Sound.music.stop_bgm()
	var movie := _show(movie_scene) as MoviePlayer
	movie.play(3)
	await movie.finished
	_title()


func _new_game_record() -> Dictionary:
	var records: Array = GameData.system("new_game")
	return records[0] if not records.is_empty() else {}


func _show(scene: PackedScene) -> Node:
	var node := scene.instantiate()
	_replace(node)
	return node


func _replace(node: Node) -> void:
	if _part != null:
		_part.queue_free()
	_part = node
	add_child(node)
