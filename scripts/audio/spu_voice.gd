class_name SpuVoice
extends Node
## One SPU voice playing a sound effect (specs/sound.md §2.2, §2.4): the tone's sample at its
## pitch, its left / right volume, the ADSR envelope and the reverb send. Two players (one per side,
## on hard-panned buses) play the mono sample together, so the exact L / R gains of libsnd's pan
## stages are kept. The envelope runs exactly (SpuEnvelope) but is applied once per frame.

const RATE := 44100
## libsnd's tick (SS_TICK240): the auto-volume fade steps once per tick.
const TICKS_PER_SECOND := 240
## Envelope cycles run at key-on (half a 60 Hz frame).
const START_CYCLES := RATE / 120

## The SPU voice number (10–23 for sound effects).
var index := 0
var envelope := SpuEnvelope.new()
## Volume registers (0..0x3FFF = volume / 2).
var volume_left := 0
var volume_right := 0
## SsUtAutoVol: the voice's volume factor 0..127, its step per tick (0 = no fade) and target.
var auto_volume := 127
var auto_step := 0
var auto_end := 0
## Key status: keyed on and not keyed off.
var keyed := false

var _left := AudioStreamPlayer.new()
var _right := AudioStreamPlayer.new()
var _cycles := 0.0
var _ticks := 0.0
var _looping := false


func _ready() -> void:
	add_child(_left)
	add_child(_right)


## SpuGetKeyStatus(voice) == SPU_ON: keyed on and the envelope above 0.
func is_on() -> bool:
	return keyed and envelope.level > 0


## Still sounding (attack to release).
func is_sounding() -> bool:
	return envelope.phase != SpuEnvelope.OFF


func key_on(stream: AudioStreamWAV, pitch: int, left: int, right: int, adsr1: int, adsr2: int, reverb: bool) -> void:
	envelope = SpuEnvelope.new(adsr1, adsr2)
	volume_left = left
	volume_right = right
	auto_volume = 127
	auto_step = 0
	keyed = true
	# The volume is set once per frame: start the envelope half a frame on, so a fast attack is
	# heard from the sample's start instead of one frame late.
	envelope.advance(START_CYCLES)
	_cycles = -START_CYCLES
	_ticks = 0.0
	_looping = stream != null and stream.loop_mode != AudioStreamWAV.LOOP_DISABLED
	for player in [_left, _right]:
		player.stop()
		player.stream = stream
		player.pitch_scale = maxf(pitch, 1) / 4096.0
	_left.bus = SoundSystem.BUS_REVERB_LEFT if reverb else SoundSystem.BUS_LEFT
	_right.bus = SoundSystem.BUS_REVERB_RIGHT if reverb else SoundSystem.BUS_RIGHT
	_apply()
	if stream != null:
		_left.play()
		_right.play()
	else:
		envelope.mute()


func key_off() -> void:
	keyed = false
	envelope.key_off()


## SsUtAutoVol(voice, start, end, delta): the volume factor goes from start to end, one step per
## libsnd tick (DW's SeAutoVol: (start - end) / delta per tick when the change is at least delta).
func auto_vol(start: int, end: int, delta: int) -> void:
	if start == end:
		return
	auto_volume = start
	var change := absi(start - end)
	auto_step = signi(end - start) * maxi(1, change / maxi(delta, 1))
	auto_end = end


func _process(delta: float) -> void:
	if envelope.phase == SpuEnvelope.OFF and not _left.playing:
		return
	_cycles += delta * RATE
	var cycles := int(_cycles)
	_cycles -= cycles
	envelope.advance(cycles)
	if auto_step != 0:
		_ticks += delta * TICKS_PER_SECOND
		while _ticks >= 1.0 and auto_step != 0:
			_ticks -= 1.0
			auto_volume += auto_step
			if (auto_step > 0 and auto_volume >= auto_end) or (auto_step < 0 and auto_volume <= auto_end):
				auto_volume = auto_end
				auto_step = 0
	if not _looping and not _left.playing:
		envelope.mute()
	if envelope.phase == SpuEnvelope.OFF:
		_left.stop()
		_right.stop()
		keyed = false
		return
	_apply()


## The players' volume: sample · envelope / 0x8000 · volume·2 / 0x8000 · the auto-volume factor.
func _apply() -> void:
	var common := envelope.level / 32768.0 * auto_volume / 127.0
	_left.volume_db = linear_to_db(maxf(common * volume_left * 2 / 32768.0, 0.0))
	_right.volume_db = linear_to_db(maxf(common * volume_right * 2 / 32768.0, 0.0))
