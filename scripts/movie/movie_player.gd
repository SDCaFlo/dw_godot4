class_name MoviePlayer
extends Control
## The game's movies (playMovie, main/utils2.c:511; MOV_playMovie, mov/mov.c; specs/new_game.md
## §2.6): the asset porter's Theora file of the STR movie (movies/<file>/movie.ogv), 320 x 176 at
## y = 32 of the black 320 x 240 screen. Start ends a skippable movie (every movie but 3). The movies'
## files and "skippable" come from systems/movies. Without the .ogv (the porter ran without ffmpeg)
## the movie is skipped. A scene of its own (scenes/movie/movie_player.tscn) that Game shows.

signal finished

const PICTURE := Rect2(0, 32, 320, 176)

@onready var video: VideoStreamPlayer = $Video

var _skippable := true
var _done := true


## Plays movie `id` of systems/movies; `finished` is emitted at its end, on Start if it can be
## skipped, or on the next frame if it can't be played.
func play(id: int) -> void:
	_done = false
	var movies: Array = GameData.system("movies") if GameData.available() else []
	var record: Dictionary = movies[id] if id >= 0 and id < movies.size() else {}
	_skippable = bool(record.get("skippable", true))
	var rel := "movies/%s/movie.ogv" % record.get("file", "")
	var stream: VideoStream = null
	if not record.is_empty() and Content.exists(rel):
		var imported := Content.imported(rel)
		if imported != "":
			stream = load(imported)
		else:
			stream = VideoStreamTheora.new()
			stream.file = Content.path(rel)
	if stream == null:
		print("movie %d: no %s (the asset porter writes it with ffmpeg); skipped" % [id, rel])
		_finish.call_deferred()
		return
	video.stream = stream
	video.position = PICTURE.position
	video.size = PICTURE.size
	video.play()


func _ready() -> void:
	video.finished.connect(_finish)
	GameLoop.frame.connect(_frame)


## Start held, read once per game frame as MOV_playMovie polls the pad (PadRead(1) & 0x800).
func _frame() -> void:
	if not _done and _skippable and GameLoop.pad.polled & Pad.START:
		video.stop()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
