class_name Game
extends Node
## The game's start (main, main/main.c:3410-3530; specs/new_game.md §3.1): the project's main
## scene. It shows one part at a time as its child, in the original's order. A new game (boot
## mode 0): the intro (NewGameScene), movie 1, then the field on the start map with the partner
## the answers picked. The title menu and loading a game (modes 1 and 2) come with step 4e-2.
## The parts are exported scenes, so a mod can replace one. Running field.tscn on its own keeps
## the field's debug start.
##
## Debug: DW_SKIP_INTRO=1 skips the intro and the movie (answer 0, the default names).

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
	_new_game()


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
	var field := field_scene.instantiate()
	field.set("boot", true)
	for property in field_overrides:
		field.set(property, field_overrides[property])
	_replace(field)


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
