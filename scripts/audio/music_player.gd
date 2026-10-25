class_name MusicPlayer
extends Node
## The music (specs/sound.md §2.3): sound.c's playMusic / stopBGM and the script side's playBGM /
## updateBGM / forceUpdateBGM / resetBGM / handleMusicOverride (script_interp.c:2587–2645, :1584).
## The songs are the asset porter's renders (asset_porter/specs/sound.md "Music render"), which
## already hold libsnd's mix, the SEQ volume 0x50 and the reverb: one player, loops from the WAV.

## ACTIVE_BGM_FONT / ACTIVE_BGM_TRACK (0xFF: no music).
const NO_FONT := 0xFF
## handleMusicOverride: script value 245.
const PSTAT_MUSIC_MODE := 245
## playMusic plays fonts 1–0x21.
const LAST_FONT := 0x21

signal changed(font: int, track: int)

var active_bgm_font := NO_FONT
var active_bgm_track := 0
## CURRENT_SEQ_FONT / CURRENT_SEQ_TRACK (-1: closed).
var current_font := -1
var current_track := -1
## The GameState node (script values, the hour).
var game_state: Node
## font -> track count (music/index.json; a font with no entry has one track).
var track_counts := {}
var player := AudioStreamPlayer.new()


func _ready() -> void:
	player.bus = SoundSystem.BUS_MUSIC
	add_child(player)


func load_index() -> void:
	if Engine.is_editor_hint() or not Content.exists("music/index.json"):
		return
	var index = Content.load_json("music/index.json")
	if not index is Dictionary:
		return
	for t in index.get("tracks", []):
		var font := int(t["font"])
		track_counts[font] = maxi(track_counts.get(font, 0), int(t["track"]) + 1)


## playMusic (sound.c:753): 0 for a font outside 1–0x21; nothing when this song already plays;
## a track past the font's count plays track 0 (seqOpen).
func play_music(font: int, track: int) -> int:
	if font <= 0 or font > LAST_FONT:
		return 0
	if font == current_font and track == current_track:
		return 1
	player.stop()
	current_font = font
	current_track = track
	if track >= track_counts.get(font, 1) or track < 0:
		current_track = 0
	var rel := "music/font_%02d/track_%d.wav" % [font, current_track]
	player.stream = Content.load_audio(rel) if Content.exists(rel) else null
	if player.stream != null:
		player.play()
	changed.emit(font, current_track)
	return 1


## stopBGM (sound.c:779): stop and close; CURRENT_SEQ_TRACK = -1, so the next playMusic restarts.
func stop_bgm() -> void:
	player.stop()
	current_track = -1


## resetBGM (script_interp.c:2377).
func reset_bgm() -> void:
	active_bgm_font = NO_FONT
	stop_bgm()


## playBGM (script_interp.c:2587): SET_BGM.
func play_bgm(id: int) -> void:
	if id == NO_FONT:
		reset_bgm()
		return
	var song := music_override(id)
	active_bgm_font = song.x
	active_bgm_track = song.y
	stop_bgm()
	play_music(song.x, song.y)


## updateBGM (script_interp.c:2608, every running frame of the clock): restarts only when the
## override gives another font or variant (the day / night switch at 6:00 and 21:00).
func update_bgm() -> void:
	if active_bgm_font == NO_FONT:
		reset_bgm()
		return
	var song := music_override(active_bgm_font)
	if song.x != active_bgm_font or song.y != active_bgm_track:
		active_bgm_font = song.x
		active_bgm_track = song.y
		stop_bgm()
		play_music(song.x, song.y)


## forceUpdateBGM (script_interp.c:2629): always restarts.
func force_update_bgm() -> void:
	if active_bgm_font == NO_FONT:
		reset_bgm()
		return
	var song := music_override(active_bgm_font)
	active_bgm_font = song.x
	active_bgm_track = song.y
	stop_bgm()
	play_music(song.x, song.y)


## handleMusicOverride (script_interp.c:1584): (font, variant) for script value 245. Mode 0: the
## variant by the hour (0 from 6:00 to 20:59, else 1). Unknown modes leave the variant unset in
## the C (a stack byte); here the current one.
func music_override(font: int) -> Vector2i:
	var mode: int = game_state.script_value(PSTAT_MUSIC_MODE) if game_state != null else 0
	var hour: int = int(game_state.state["clock"]["hour"]) if game_state != null else 12
	match mode:
		0:
			return Vector2i(font, 0 if hour >= 6 and hour < 21 else 1)
		1:
			return Vector2i(font, 0)
		2:
			return Vector2i(6, 2)
		3:
			return Vector2i(0xB, 2)
		4:
			return Vector2i(0xF, 2)
		5:
			return Vector2i(0x15, 0)
		6:
			return Vector2i(0x15, 1)
		7:
			return Vector2i(0x1A, 0)
		8:
			return Vector2i(0x1A, 1)
		9:
			return Vector2i(0x1B, 0)
		10:
			return Vector2i(0x1B, 1)
	return Vector2i(font, active_bgm_track)
