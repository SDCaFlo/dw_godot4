extends SceneTree
## The sound (scripts/audio/, specs/sound.md) with values worked out from the C and the asm:
##   godot --headless --path . -s res://tests/test_sound.gd
## Exits 1 if a check fails. The banks are synthetic; only the pitch table comes from the porter
## output when it exists.

var _failed := 0
var _checks := 0
var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_envelope()
	var sound := SoundSystem.new()
	root.add_child(sound)
	_play_sound(sound)
	_channels(sound)
	_volume_and_pitch(sound)
	_music(sound)
	_animation_sounds()
	print("%s: sound checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


# --- §2.4: the envelope (the same vectors as asset_porter/tests/test_music.py) ----------------------

func _envelope() -> void:
	_eq(SpuEnvelope.new(0, 0).levels(4), [0, 14336, 28672, 0x7FFF], "linear attack, rate 0: +7 << 11 a cycle")
	_eq(SpuEnvelope.new(52 << 8, 0).levels(9), [0, 0, 0, 0, 7, 7, 7, 7, 14], "attack shift 13: a step every 4 cycles")
	_eq(SpuEnvelope.new(0x7F << 8, 0).levels(50).max(), 0, "rate 0x7F never steps")
	var env := SpuEnvelope.new(0x0007, 0x7F << 6)
	var levels := env.levels(60)
	_eq([levels[3], levels[4], env.phase], [0x7FFF, 0x7FFF - 0x4000, SpuEnvelope.SUSTAIN],
			"exponential decay to the sustain level 7")
	env = SpuEnvelope.new(0x000F, 0x7F << 6)
	env.advance(10)
	var start := env.level
	env.key_off()
	_eq(env.levels(2), [start, maxi(0, start - 0x4000)], "linear release, rate 0")
	env.advance(10)
	_eq(env.phase, SpuEnvelope.OFF, "the release ends OFF")
	var bulk := SpuEnvelope.new(0x1A3F, 0x5FC6)
	var single := SpuEnvelope.new(0x1A3F, 0x5FC6)
	bulk.advance(5000)
	for i in 5000:
		single.advance(1)
	_eq([bulk.level, bulk.phase], [single.level, single.phase], "advance(n) = n single cycles")


# --- §2.2: playSound ------------------------------------------------------------------------------

func _tone(max_note: int, extra := {}) -> Dictionary:
	var tone := {"max": max_note, "min": max_note, "vag": 1, "center": 60, "shift": 0, "volume": 127, "pan": 64,
			"mode": 0, "adsr1": 0, "adsr2": 0x7F << 6}
	tone.merge(extra, true)
	return tone


func _play_sound(sound: SoundSystem) -> void:
	var bank := SoundBank.new()
	bank.programs[1] = {"volume": 127, "pan": 64, "tones": [_tone(61), _tone(62), _tone(61)]}
	bank.programs[0] = {"volume": 127, "pan": 64, "tones": [_tone(40)]}
	sound.set_bank(0, bank)
	sound.set_bank(3, bank)
	sound.free_channel_index = 0
	# slot 0: value 0x11 -> program 1, note 0x11 % 16 + 60 = 61: the two tones whose max is 61
	_eq(sound.play_sound(0, 0x11), (1 << 10) | (1 << 11), "slot 0: program value / 16, note value % 16 + 60, every tone with max == note")
	_eq(sound.play_sound(3, 40), 1 << 12, "slots 3-7: program 0, note = value")
	_eq(sound.play_sound(2, 0x11), 0, "slot 2 plays nothing")
	_eq(sound.play_sound(0, 0x15), 0, "no tone with that max: nothing")


func _channels(sound: SoundSystem) -> void:
	for voice in sound.voices:
		voice.keyed = false
		voice.envelope.level = 0
	sound.free_channel_index = 0
	_eq([sound.next_free_channel(), sound.next_free_channel()], [10, 11], "round robin from voice 10")
	sound.voices[2].keyed = true
	sound.voices[2].envelope.level = 100
	_eq(sound.next_free_channel(), 13, "a voice that is on (keyed, envelope > 0) is skipped")
	for voice in sound.voices:
		voice.keyed = true
		voice.envelope.level = 100
	sound.free_channel_index = 5
	_eq(sound.next_free_channel(), 15, "all on: the next in turn anyway")
	sound.voices[0].keyed = true
	sound.voices[0].envelope.level = 100
	sound.stop_sound_mask(1 << 10)
	_eq([sound.voices[0].keyed, sound.voices[0].auto_step < 0, sound.voices[0].auto_end], [false, true, 0],
			"stopSoundMask: fade 127 -> 0 and key off")
	for voice in sound.voices:
		voice.keyed = false
		voice.envelope.level = 0


func _volume_and_pitch(sound: SoundSystem) -> void:
	var prog := {"volume": 127, "pan": 64}
	_eq(SoundSystem.sfx_volume(127, prog, _tone(60)), Vector2i(16383, 16383),
			"0x7F x mvol x 0x3FFF / 127^2, x volumes / 127^2, not squared")
	_eq(SoundSystem.sfx_volume(127, prog, _tone(60, {"pan": 0})), Vector2i(16383, 0), "tone pan 0: right / 63 x 0")
	_eq(SoundSystem.sfx_volume(127, {"volume": 64, "pan": 127}, _tone(60, {"volume": 100})).y, 16383 * 64 * 100 / 16129,
			"program pan 127: the left side goes, the right keeps program x tone volume")
	_eq(sound.note_pitch(60, 60, 0), 0x1000, "the centre note: 0x1000 (44.1 kHz)")
	_eq(sound.note_pitch(72, 60, 0), 0x2000, "an octave up")
	_eq(sound.note_pitch(48, 60, 0), 0x800, "an octave down")
	_eq(sound.note_pitch(61, 60, 0), sound.ptable[16], "a semitone: 16 steps on")
	_eq(sound.note_pitch(60, 60, 64), sound.ptable[8], "the tone's shift / 8")


# --- §2.3: the music --------------------------------------------------------------------------------

func _music(sound: SoundSystem) -> void:
	var data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP music checks: no data porter output")
		data.free()
		return
	var state = load("res://scripts/state/game_state.gd").new()
	state.data = data
	state.new_game()
	var music := sound.music
	music.game_state = state
	state.state["clock"]["hour"] = 12
	state.set_script_value(MusicPlayer.PSTAT_MUSIC_MODE, 0)
	_eq(music.music_override(4), Vector2i(4, 0), "mode 0, 12:00: variant 0 (day)")
	state.state["clock"]["hour"] = 21
	_eq(music.music_override(4), Vector2i(4, 1), "mode 0, 21:00: variant 1 (night)")
	state.state["clock"]["hour"] = 5
	_eq(music.music_override(4), Vector2i(4, 1), "mode 0, 5:00: night")
	state.state["clock"]["hour"] = 6
	_eq(music.music_override(4), Vector2i(4, 0), "mode 0, 6:00: day")
	var expected := {1: Vector2i(4, 0), 2: Vector2i(6, 2), 3: Vector2i(0xB, 2), 4: Vector2i(0xF, 2), 5: Vector2i(0x15, 0),
			6: Vector2i(0x15, 1), 7: Vector2i(0x1A, 0), 8: Vector2i(0x1A, 1), 9: Vector2i(0x1B, 0), 10: Vector2i(0x1B, 1)}
	var got := {}
	for mode in expected:
		state.set_script_value(MusicPlayer.PSTAT_MUSIC_MODE, mode)
		got[mode] = music.music_override(4)
	_eq(got, expected, "handleMusicOverride's table (script value 245)")
	state.set_script_value(MusicPlayer.PSTAT_MUSIC_MODE, 0)
	var changes := []
	music.changed.connect(func(font, track): changes.append([font, track]))
	music.track_counts = {4: 2}
	music.play_bgm(4)
	_eq([music.active_bgm_font, music.active_bgm_track, changes], [4, 0, [[4, 0]]], "playBGM: the font and its day variant")
	music.update_bgm()
	_eq(changes.size(), 1, "updateBGM: nothing changed, no restart")
	music.play_bgm(4)
	_eq(changes.size(), 2, "playBGM again: stopBGM first, so the same song restarts")
	state.state["clock"]["hour"] = 22
	music.update_bgm()
	_eq(changes.back(), [4, 1], "updateBGM at night: the night variant")
	state.set_script_value(MusicPlayer.PSTAT_MUSIC_MODE, 1)
	music.update_bgm()
	_eq(changes.back(), [4, 0], "mode 1: always variant 0")
	_eq(music.play_music(0, 0), 0, "font 0: playMusic does nothing")
	_eq(music.play_music(0x22, 0), 0, "font past 0x21: nothing")
	music.play_music(4, 5)
	_eq(music.current_track, 0, "a track past the font's count plays track 0")
	music.play_bgm(0xFF)
	_eq([music.active_bgm_font, music.current_track], [MusicPlayer.NO_FONT, -1], "SET_BGM 0xFF: resetBGM")
	music.update_bgm()
	_eq(music.active_bgm_font, MusicPlayer.NO_FONT, "updateBGM with no music: stays off")
	music.game_state = null
	state.free()
	data.free()


# --- anim.c:336: the animation sound events -------------------------------------------------------

func _animation_sounds() -> void:
	var gltf := {"animations": [{"name": "walk", "extras": {"events": [
			{"type": "sound", "bank": 1, "sound": 12, "time": 0.1},
			{"type": "sound", "bank": 1, "sound": 13, "time": 0.6},
			{"type": "texture", "time": 0.2}]}}]}
	var sounds := AnimationSounds.new(gltf)
	var heard := []
	sounds.sound.connect(func(bank, value): heard.append([bank, value]))
	var player := AnimationPlayer.new()
	var anim := Animation.new()
	anim.length = 1.0
	anim.loop_mode = Animation.LOOP_LINEAR
	var library := AnimationLibrary.new()
	library.add_animation("walk", anim)
	player.add_animation_library("", library)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	root.add_child(player)
	player.play("walk")
	player.advance(0.0)
	sounds.update(player)
	player.advance(0.3)
	sounds.update(player)
	_eq(heard, [[1, 12]], "the event at 0.1 s after 0.3 s")
	player.advance(0.5)
	sounds.update(player)
	_eq(heard, [[1, 12], [1, 13]], "the event at 0.6 s")
	player.advance(0.4)
	sounds.update(player)
	_eq(heard, [[1, 12], [1, 13], [1, 12]], "after the loop's wrap (1.2 s = 0.2 s): the first event again")
	player.queue_free()


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])
