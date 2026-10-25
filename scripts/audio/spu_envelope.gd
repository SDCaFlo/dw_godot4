class_name SpuEnvelope
extends RefCounted
## The SPU's ADSR envelope (specs/sound.md §2.4; psx-spx "Envelope Operation depending on
## Shift/Step/Mode/Direction"), the same integer steps as the asset porter's renderer
## (asset_porter/dwporter/formats/spu.py `Envelope`, tests shared by value). Level 0..0x7FFF; a
## counter advances once per 44.1 kHz cycle, the level steps when its bit 15 is set.
## `advance(cycles)` runs many cycles at once, so the sound effects can follow it per frame.

enum { ATTACK, DECAY, SUSTAIN, RELEASE, OFF }

var adsr1 := 0
var adsr2 := 0
var phase := ATTACK
var level := 0
var counter := 0


func _init(attack_decay := 0, sustain_release := 0) -> void:
	adsr1 = attack_decay
	adsr2 = sustain_release


## Key-off: the release from the current level.
func key_off() -> void:
	if phase != OFF:
		phase = RELEASE
		counter = 0


## The ADPCM end without repeat: level 0, silent at once.
func mute() -> void:
	phase = OFF
	level = 0
	counter = 0


## [rate, decreasing, exponential] of the current phase.
func _params() -> Array:
	match phase:
		ATTACK:
			return [(adsr1 >> 8) & 0x7F, false, adsr1 & 0x8000 != 0]
		DECAY:
			return [((adsr1 >> 4) & 0xF) << 2, true, true]
		SUSTAIN:
			return [(adsr2 >> 6) & 0x7F, adsr2 & 0x4000 != 0, adsr2 & 0x8000 != 0]
	return [(adsr2 & 0x1F) << 2, true, adsr2 & 0x20 != 0]


## [level step, counter increment] for the phase and level; increment 0 = never steps.
func _step() -> Array:
	var p := _params()
	var rate: int = p[0]
	var decreasing: bool = p[1]
	var exponential: bool = p[2]
	var shift := rate >> 2
	var value := rate & 3
	var step := (-8 + value) if decreasing else (7 - value)
	step <<= maxi(0, 11 - shift)
	var increment := 0x8000 >> maxi(0, shift - 11)
	if exponential and not decreasing and level > 0x6000:
		if shift < 10:
			step >>= 2
		elif shift >= 11:
			increment >>= 2
		else:
			step >>= 1
			increment >>= 1
	elif exponential and decreasing:
		step = (step * level) >> 15
	if rate == 0x7F or ((phase == DECAY or phase == RELEASE) and rate == 0x1F << 2):
		return [0, 0]
	return [step, maxi(increment, 1)]


func _next_phase() -> void:
	if phase == ATTACK and level >= 0x7FFF:
		phase = DECAY
		counter = 0
	elif phase == DECAY and (level >> 11) <= (adsr1 & 0xF):
		phase = SUSTAIN
		counter = 0
	elif phase == RELEASE and level <= 0:
		phase = OFF
		level = 0


## Runs `cycles` 44.1 kHz cycles.
func advance(cycles: int) -> void:
	while cycles > 0 and phase != OFF:
		var s := _step()
		var step: int = s[0]
		var increment: int = s[1]
		if increment == 0:
			return
		var run := (0x8000 - counter + increment - 1) / increment
		if run > cycles:
			counter += increment * cycles
			return
		cycles -= run
		counter = 0
		var next := level + step
		if phase == DECAY or phase == RELEASE or (phase == SUSTAIN and step < 0):
			next = maxi(next, 0)
		else:
			next = clampi(next, -0x8000, 0x7FFF)
		level = next
		_next_phase()


## The levels of the next n cycles (the level is read, then the envelope ticks): the porter's
## `Envelope.levels`, for the tests.
func levels(n: int) -> Array:
	var out := []
	for i in n:
		out.append(level)
		advance(1)
	return out
