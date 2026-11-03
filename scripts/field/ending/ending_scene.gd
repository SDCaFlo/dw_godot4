class_name EndingScene
extends RefCounted
## The ending's tamer scene (ENDI, endi/endi.c; specs/map_events.md §3.4 N1-N7, §4.4.1): the tamer's
## colours fade to black while sparks gather on his bones, he shrinks and grows, then the sparks fly
## up. The logic of ENDI_tickEnding / ENDI_updateEnding / ENDI_renderParticles; EndingHost does the
## palette, the semi-transparency, the scale and the drawing.

## NUM_ENDI_PARTICLES (endi.h:10).
const PARTICLES := 80
## ENDI_updateEnding (endi.c:172-198): the fade's frames, the shrink's peak, the growth's end.
const FADE_END := 60
const PEAK := 78
const GROW_END := 80
## endi.c:186-188: posData->scale.
const SCALE_ONE := 0x1000
const SCALE_LOW := 0x999
const SCALE_HIGH := 0x1800
## endi.c:194, :205: the release's velocity and its pull per frame.
const VELOCITY := -450
const GRAVITY := 20
## playSound(8, 0 / 1) (endi.c:430, :190).
const SOUND_BANK := 8
const SOUND_START := 0
const SOUND_RELEASE := 1
## ENDI_spawnParticle (endi.c:280-282): the offset rolls, rand() % range - half.
const OFFSET_RANGE := Vector3i(140, 80, 80)
const OFFSET_HALF := Vector3i(70, 40, 40)
## ENDI_renderParticles (endi.c:390-394): colour rand() % 70 + 60, size rand() % 15 + 15.
const COLOR_RANGE := 70
const COLOR_MIN := 60
const SIZE_RANGE := 15
const SIZE_MIN := 15

## ENDI_STATE.
var frame := 0
var phase := 0
var active := false
## ENDI_PARTICLES: {"active" (-1 free), "bone", "pos"}.
var particles: Array[Dictionary] = []
## ENDI_DATA.flag: the particles follow their bones (until the release).
var attached := true
## The render object 0x813 is in the list (ENDI_startParticles to ENDI_stopParticles).
var shown := false
## ENDI_DATA.base (SVECTOR).
var base := Vector3i.ZERO
var velocity := 0
## The tamer's posData->scale (x = y = z).
var scale := SCALE_ONE
## The frame of the last ENDI_fadeClut (0: the colours as they are).
var fade_frame := 0

## Inputs: DIGIMON_DATA[0].boneCount, and bone -> its world matrix (PsxMath's 12 ints).
var bone_count := 1
var bone_matrix := Callable()

## Cleared at the start of each tick(): ["sound", bank, id], "stop_sound".
var events: Array = []


func _init() -> void:
	for i in PARTICLES:
		particles.append({"active": -1, "bone": 0, "pos": Vector3i.ZERO})


## The colour factor of ENDI_fadeClut at a frame: c · (60 − f) / 60 (stand-in: one factor, not the
## C's integer per 5-bit channel; PaletteFade, specs/death_scene.md §4.9).
static func fade_factor(at_frame: int) -> float:
	return (FADE_END - at_frame) / float(FADE_END)


## ENDI_tickEnding(entity, 0) (endi.c:415-431).
func start() -> void:
	frame = 0
	phase = 0
	active = true
	fade_frame = 0
	scale = SCALE_ONE
	for p in particles:
		p["active"] = -1
	attached = true
	shown = true
	events.append(["sound", SOUND_BANK, SOUND_START])


## ENDI_tickEnding(entity, 1): the frame, -1 once over.
func result() -> int:
	return frame


## ENDI_updateEnding (endi.c:159-216), one game frame.
func tick() -> void:
	events.clear()
	if not active:
		return
	frame += 1
	match phase:
		0:
			fade_frame = frame
			_spawn(frame % (bone_count - 1) + 1)
			if frame >= FADE_END:
				phase = 1
		1:
			_spawn(frame % (bone_count - 1) + 1)
			if frame <= PEAK:
				scale = PsxMath.lerp_int(SCALE_ONE, SCALE_LOW, FADE_END, PEAK, frame)
			else:
				scale = PsxMath.lerp_int(SCALE_LOW, SCALE_HIGH, PEAK, GROW_END, frame)
			if frame >= GROW_END:
				events.append(["sound", SOUND_BANK, SOUND_RELEASE])
				phase = 2
				release()
				velocity = VELOCITY
		2:
			base.y = PsxMath.s16(base.y + velocity)
			velocity += GRAVITY
			if velocity >= 0:
				phase = 3
		3:
			events.append("stop_sound")
			shown = false
			frame = -1
			active = false


## ENDI_spawnParticle (endi.c:266-287). port-only guard: no free slot draws nothing (the C writes
## slot 80; the 80 spawns fill exactly the 80 slots, so it never happens).
func _spawn(bone: int) -> void:
	for p in particles:
		if int(p["active"]) < 0:
			p["active"] = 0
			p["bone"] = bone
			var x := Rng.rand() % OFFSET_RANGE.x - OFFSET_HALF.x
			var y := Rng.rand() % OFFSET_RANGE.y - OFFSET_HALF.y
			var z := Rng.rand() % OFFSET_RANGE.z - OFFSET_HALF.z
			p["pos"] = Vector3i(x, y, z)
			return


## ENDI_releaseParticles (endi.c:302-337): the base from bone 0's t[1], t[2], t[3] (N7: one past the
## array; port-only 0 for t[3], which cancels out: pos = world − base, drawn at pos + base), each
## particle's world position kept relative to it.
func release() -> void:
	attached = false
	var m0 := _matrix(0)
	base = PsxMath.s16_vec(Vector3i(m0[10], m0[11], 0))
	for p in particles:
		if int(p["active"]) >= 0:
			p["pos"] = PsxMath.s16_vec(world(p) - base)


## The particle on its bone: s16(pos · scale / 4096) through the bone's matrix plus its translation
## (ApplyMatrixSV, endi.c:327-332, :375-380).
func world(p: Dictionary) -> Vector3i:
	var pos: Vector3i = p["pos"]
	var v := PsxMath.s16_vec(Vector3i(PsxMath.div(pos.x * scale, SCALE_ONE), PsxMath.div(pos.y * scale, SCALE_ONE),
			PsxMath.div(pos.z * scale, SCALE_ONE)))
	var m := _matrix(int(p["bone"]))
	return PsxMath.s16_vec(PsxMath.s16_vec(PsxMath.apply_matrix_lv(m, v)) + PsxMath.translation(m))


func _matrix(bone: int) -> PackedInt32Array:
	return bone_matrix.call(bone) if bone_matrix.is_valid() else PsxMath.identity()


## ENDI_renderParticles (endi.c:368-405): per active particle, its position, then the colour and the
## size rolled (r, g, b, size). Nothing once the render object is gone.
func render() -> Array:
	var out := []
	if not shown:
		return out
	for p in particles:
		if int(p["active"]) < 0:
			continue
		var at := world(p) if attached else PsxMath.s16_vec(p["pos"] + base)
		var r := Rng.rand() % COLOR_RANGE + COLOR_MIN
		var g := Rng.rand() % COLOR_RANGE + COLOR_MIN
		var b := Rng.rand() % COLOR_RANGE + COLOR_MIN
		var size := Rng.rand() % SIZE_RANGE + SIZE_MIN
		out.append({"pos": at, "color": Vector3i(r, g, b), "size": size})
	return out
