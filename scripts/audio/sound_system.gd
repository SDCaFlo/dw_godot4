class_name SoundSystem
extends Node
## The game's sound (specs/sound.md), autoload "Sound": sound.c's banks and sound effects, with
## libsnd's voice rules for them, and the music (`music`, a MusicPlayer).
##
## - Slots 0–8 hold the banks like the SPU (§2.1): SS and SL from the start, the map's ESALL set,
##   the partner's VLALL / VBALL sets; slot 2's instruments are inside the rendered songs.
## - play_sound (playSound / startSound, sound.c:641, :602) keys on every tone of the program whose
##   `max` is the note, each on the next free voice of 10–23 (getNextFreeChannel, sound.c:567), and
##   returns the voice mask; stop_sound_mask / stop_sound fade and key off (sound.c:629, :650).

const SLOTS := 9
const FIRST_VOICE := 10
const VOICE_COUNT := 14
## loadPartnerSounds: types outside 1–65 (no VLALL entry) use set 15.
const DEFAULT_VOICE_SET := 15
## The buses (created at start if the project's layout doesn't have them).
const BUS_MUSIC := "Music"
const BUS_SFX := "Sfx"
const BUS_LEFT := "SfxLeft"
const BUS_RIGHT := "SfxRight"
const BUS_REVERB := "SfxReverb"
const BUS_REVERB_LEFT := "SfxReverbLeft"
const BUS_REVERB_RIGHT := "SfxReverbRight"

signal played(slot: int, value: int, mask: int)

## slot -> SoundBank (null: empty)
var banks: Array = []
var voices: Array[SpuVoice] = []
## FREE_CHANNEL_INDEX
var free_channel_index := 0
## ACTIVE_MAP_SOUND_ID (loadMapSounds skips a set already loaded)
var active_map_set := -1
## libsnd's pitch table (_svm_ptable, sound/index.json); a computed one if the output is missing.
var ptable := PackedInt32Array()
var music: MusicPlayer
## Bank folders by slot, to skip reloading the same bank.
var _folders: Array = []


func _init() -> void:
	banks.resize(SLOTS)
	_folders.resize(SLOTS)
	_folders.fill("")
	for i in VOICE_COUNT:
		var voice := SpuVoice.new()
		voice.index = FIRST_VOICE + i
		voices.append(voice)
	music = MusicPlayer.new()


func _ready() -> void:
	ensure_buses()
	for voice in voices:
		add_child(voice)
	add_child(music)
	music.game_state = get_node_or_null("/root/GameState")
	music.load_index()
	if Engine.is_editor_hint():
		return
	var index = Content.load_json("sound/index.json") if Content.exists("sound/index.json") else null
	set_ptable(index.get("tables", {}).get("svm_ptable", []) if index is Dictionary else [])
	# initializeMusic: SS into slot 0, SL into slot 1.
	load_bank(0, "sound/SS")
	load_bank(1, "sound/SL")


func set_ptable(values: Array) -> void:
	ptable = PackedInt32Array(values)
	if ptable.size() != 193:
		ptable.resize(193)
		for i in 193:
			ptable[i] = roundi(4096.0 * pow(2.0, i / 192.0))


## The buses: Music and Sfx to the master; the sound effects' two hard-panned sides, and the
## reverb voices' two sides through a reverb (an approximation of Studio B, by ear).
static func ensure_buses() -> void:
	_bus(BUS_MUSIC, "Master")
	_bus(BUS_SFX, "Master")
	_bus(BUS_LEFT, BUS_SFX, -1.0)
	_bus(BUS_RIGHT, BUS_SFX, 1.0)
	if AudioServer.get_bus_index(BUS_REVERB) == -1:
		_bus(BUS_REVERB, BUS_SFX)
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.45
		reverb.damping = 0.5
		reverb.dry = 1.0
		reverb.wet = 0.3
		AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_REVERB), reverb)
	_bus(BUS_REVERB_LEFT, BUS_REVERB, -1.0)
	_bus(BUS_REVERB_RIGHT, BUS_REVERB, 1.0)


static func _bus(bus_name: String, send: String, pan := 0.0) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, send)
	if pan != 0.0:
		var panner := AudioEffectPanner.new()
		panner.pan = pan
		AudioServer.add_bus_effect(i, panner)


# --- banks ---------------------------------------------------------------------------------------

## readVHBFile / readVHBFileSectors: a bank folder of the porter output into a slot.
func load_bank(slot: int, folder: String) -> bool:
	if _folders[slot] == folder and banks[slot] != null:
		return true
	var bank := SoundBank.load_folder(folder)
	set_bank(slot, bank)
	_folders[slot] = folder if bank != null else ""
	return bank != null


func set_bank(slot: int, bank: SoundBank) -> void:
	banks[slot] = bank


## loadMapSounds / loadMapSounds2 (sound.c:721, sound_async.c:233): the ESALL set into slot 8,
## skipped when it is already the loaded one.
func load_map_sounds(set_id: int) -> void:
	if active_map_set == set_id:
		return
	active_map_set = set_id
	load_bank(8, "sound/ESALL/set_%02d" % set_id)


## loadSB (sound_async.c:208): the battle's sound bank SOUND\SB into slot 8, where the techniques'
## sounds play (BTL_playEFESound: playSound(8, id)); the map's set is forgotten, so the battle's
## end loads it again (loadMapSounds2).
func load_battle_sounds() -> void:
	active_map_set = -1
	load_bank(8, "sound/SB")


## loadPartnerSounds (sound.c:676): the voice set (slot 3; `vlall`, none -> set 15) and the sound
## set (slot 4, loadDigimonSounds; `vball`) of the partner's Digimon record.
func load_partner_sounds(sounds: Dictionary) -> void:
	var vlall = sounds.get("vlall")
	load_bank(3, "sound/VLALL/set_%02d" % (int(vlall) if vlall != null else DEFAULT_VOICE_SET))
	if sounds.get("vball") != null:
		load_bank(4, "sound/VBALL/set_%02d" % int(sounds["vball"]))


# --- sound effects -------------------------------------------------------------------------------

## playSound (sound.c:641): slots 0, 1, 8 -> program value / 16, note value % 16 + 60; slots 3–7 ->
## program 0, note value; others nothing. Returns the voice mask.
func play_sound(slot: int, value: int) -> int:
	var mask := 0
	if slot == 0 or slot == 1 or slot == 8:
		mask = start_sound(slot, value / 16, value % 16 + 0x3C)
	elif slot > 2 and slot < 8:
		mask = start_sound(slot, 0, value)
	played.emit(slot, value, mask)
	return mask


## startSound (sound.c:602): every tone of the program whose max is the note, each on a voice.
func start_sound(slot: int, program: int, note: int) -> int:
	var bank: SoundBank = banks[slot] if slot < SLOTS else null
	if bank == null or not bank.programs.has(program):
		return 0
	var prog: Dictionary = bank.programs[program]
	var mask := 0
	var tones: Array = prog["tones"]
	for i in tones.size():
		var tone: Dictionary = tones[i]
		if int(tone["max"]) != note:
			continue
		var channel := next_free_channel()
		var vol := sfx_volume(bank.master_volume, prog, tone)
		var voice := voices[channel - FIRST_VOICE]
		voice.key_on(bank.stream(int(tone["vag"])), note_pitch(note, int(tone["center"]), int(tone["shift"])),
				vol.x, vol.y, int(tone["adsr1"]), int(tone["adsr2"]), int(tone["mode"]) & 4 != 0)
		mask |= 1 << channel
	return mask


## getNextFreeChannel (sound.c:567): from after the last voice used, the first of 10–23 that isn't
## on; all on: the next one anyway.
func next_free_channel() -> int:
	var channel := -1
	var i := 0
	while i < VOICE_COUNT:
		channel = (i + free_channel_index) % VOICE_COUNT + FIRST_VOICE
		if not voices[channel - FIRST_VOICE].is_on():
			break
		i += 1
	if i == VOICE_COUNT:
		channel = free_channel_index + FIRST_VOICE
	free_channel_index = (channel - 9) % VOICE_COUNT
	return channel


## stopSoundMask (sound.c:629): SsUtAutoVol(voice, 0x7F, 0, 6), then SsUtKeyOffV.
func stop_sound_mask(mask: int) -> void:
	for voice in voices:
		if mask & (1 << voice.index):
			voice.auto_vol(0x7F, 0, 6)
			voice.key_off()


## stopSound (sound.c:650): every sound-effect voice that is on.
func stop_sound() -> void:
	for voice in voices:
		if voice.is_on():
			voice.auto_vol(0x7F, 0, 6)
			voice.key_off()


## The volume registers of a sound effect (SsUtKeyOnV(.., 0x7F, 0x7F) -> _SsVmKeyOnNow, DW asm):
## v = 0x7F · mvol · 0x3FFF / 127², · program volume · tone volume / 127²; the tone, program
## and key-on (0x40) pan stages; not squared (sequence notes only).
static func sfx_volume(master_volume: int, prog: Dictionary, tone: Dictionary) -> Vector2i:
	var v := 0x7F * (master_volume * 0x3FFF) / (127 * 127)
	v = v * int(prog["volume"]) * int(tone["volume"]) / (127 * 127)
	var lr := Vector2i(v, v)
	for pan in [int(tone["pan"]), int(prog["pan"]), 0x40]:
		if pan < 0x40:
			lr.y = lr.y * pan / 63
		else:
			lr.x = lr.x * (127 - pan) / 63
	return lr


## note2pitch2(note, 0) (libsnd): the tone's fine tune / 8 picks one of 16 steps per semitone.
func note_pitch(note: int, center: int, shift: int) -> int:
	var fine := shift / 8
	var carry := 0
	if fine >= 16:
		carry = 1
		fine -= 16
	var n := note + 60 - center + carry
	var octave := n / 12
	var pos := n % 12
	if pos < 0:
		pos += 12
		octave -= 1
	var p := ptable[pos * 16 + fine]
	octave -= 5
	if octave > 0:
		p <<= octave
	elif octave < 0:
		p >>= -octave
	return p & 0xFFFF
