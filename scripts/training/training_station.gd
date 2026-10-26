class_name TrainingStation
extends Node
## A gym's training station (the TRN_setup…Training / TRN_tick…Training pairs; specs/training.md
## §2.2, §3): a scene under TrainingRoutines that says which map and stat it trains, starts when
## builtin 0x07 asks for them, and runs its scene one game frame at a time (ticked by the field
## after the script, as the C's object list). When it is done it sets Training.complete
## (TRAINING_COMPLETE) and the script goes on.

## The map (CURRENT_SCREEN_ID) and stat (script value 0xFE) this station trains.
@export var map := -1
@export var stat := 0

## Set by TrainingRoutines when it starts the station.
var training: Training
var interpreter: ScriptInterpreter
var clouds: CloudFX
var sparks: ParticleFX
var pad: Pad
var sound: Node
var game_state: Node
var data: Node

## The station's object is in the list (addObject … removeObject).
var running := false
## MAIN_D_80135370: value 0xF6, the slot-machine bonus ("Bonus Try", specs/training.md §7).
var slots := false
## TRAINING_STATE, MAIN_D_8013537A, MAIN_D_8013537C.
var state := 0
var counter := 0
var wait := 0

## The slot result without the slots (r = 10: × 1).
const NORMAL_RESULT := 10
## The session: 1200 frames (a minute) or △ held.
const SESSION_FRAMES := 0x4B0
## After the counted gains, frames before the station's last part.
const AFTER_GAINS := 0x14
## A Fresh / In-Training partner trains its upgrade counter (level < 3).
const COUNTER_LEVEL := 3
## playSound(8, …) at the start and the end of every session.
const SOUND_START := 9
const SOUND_END := 0xA
## The partner's animations every station uses: walk to the point, done.
const ANIM_WALK := 4
const ANIM_DONE := 0x12


func matches(map_id: int, stat_id: int) -> bool:
	return map_id == map and stat_id == stat


## The setup (TRN_setup…Training(map)): the station's own part, then the start time and state 0.
func start(slot_flag: bool) -> void:
	slots = slot_flag
	setup()
	training.save_start_time()
	state = 0
	running = true


## The station's part of its setup; override.
func setup() -> void:
	pass


## One frame of the station's object; override.
func tick() -> void:
	pass


## removeObject + TRAINING_COMPLETE = 1.
func finish() -> void:
	running = false
	state = 0
	training.complete = true


# --- what the stations use ----------------------------------------------------------------------

func partner() -> Partner:
	return interpreter.partner if interpreter != null else null


func tamer() -> Tamer:
	return interpreter.tamer if interpreter != null else null


func field() -> FieldMap:
	return interpreter.field if interpreter != null else null


## startAnimation on the partner: animFlag = 1, so the held root motion and blocked axes clear.
func partner_animation(id: int) -> void:
	var p := partner()
	if p == null:
		return
	p.start_animation(id)
	p.step_blocked = false
	p.blocked_axes = 0


## playSound(8, id): the map's own set.
func play(id: int) -> void:
	if sound != null:
		sound.play_sound(8, id)


## playSound2(8, id): the voices' mask, for stop_loop (thunkStopSoundMask).
func play_loop(id: int) -> int:
	return int(sound.play_sound(8, id)) if sound != null else 0


func stop_loop(mask: int) -> void:
	if sound != null and mask != 0:
		sound.stop_sound_mask(mask)


## startAnimation on the tamer.
func tamer_animation(id: int) -> void:
	var t := tamer()
	if t != null:
		t.start_animation(id)
		t.step_blocked = false


## tickEntityWalkTo(0xFD, target, x, z, 0).
func walk_tamer(target: int, x: int, z: int) -> bool:
	return interpreter == null or interpreter.tick_walk_to(ScriptContext.OWNER_TAMER, target, x, z)


## NPC_ENTITIES[i] (ENTITY_TABLE[2 + i]), or null.
func npc(i: int) -> Node3D:
	return interpreter.actor(2 + i) if interpreter != null else null


## entityLookAtLocation(who, &at->posData->location).
static func look_at(who: Node3D, at: Node3D) -> void:
	if who != null and at != null:
		who.look_at_psx(int(at.position.x), int(-at.position.z))


## createParticleFX(0, 0, &point, NULL, 0) at each point (PSX x, y, z).
func spark(points: Array) -> void:
	if sparks == null:
		return
	for p in points:
		sparks.create(0, 0, Vector3i(p))


## set / unsetCameraFollowPlayer.
func set_camera_follow(on: bool) -> void:
	var t := tamer()
	if t != null:
		t.camera_follow = on


## The session's end: without the slots a minute, or △ held; with them, the session's result.
func session_over() -> bool:
	return (not slots and (counter >= SESSION_FRAMES or cancel_held())) or slot_result_ready()


## The slots' session has paid out (r >= 0).
func slot_result_ready() -> bool:
	return slots and result() >= 0


## The awards' `c`: the slot session's result with the slots (−1 until it has paid out), else 10.
func result() -> int:
	return training.slot_session.result() if slots else NORMAL_RESULT


## The station's multiplier mode (the slots' stat), from its script stat.
func slot_mode() -> int:
	return Training.mode_of_stat(stat)


## TRN_startSlotSessionIfEnabled(mode): in the station's state 0, after its own work.
func start_slot_session() -> void:
	if slots:
		training.slot_session.configure(data, play)
		training.slot_session.start(slot_mode())


## TRN_startSlotSpin, if MAIN_D_80135370 == 1: when the partner reaches its point.
func start_slot_spin() -> void:
	if slots:
		training.slot_session.machine.start_spin()


## Fresh / In-Training: the upgrade counter `field` of the care + 1.
func count_upgrade(field_name: String) -> void:
	if partner_level() < COUNTER_LEVEL:
		var care: Dictionary = game_state.state["partner"]["care"]
		care[field_name] = int(care[field_name]) + 1


## The shared states after the award: once the box has counted the gains, `AFTER_GAINS` frames;
## true on the frame they are over.
func gains_counted() -> bool:
	if wait < 0:
		if training.gains_are_zero():
			wait = 0
		return false
	wait += 1
	return wait >= AFTER_GAINS


## The partner's (x, z) in PSX units.
func partner_xz() -> Vector2i:
	var p := partner()
	return Vector2i(int(p.position.x), int(-p.position.z)) if p != null else Vector2i.ZERO


## The end every station shares: the base stats applied, the stats box closed, then the object
## removed and TRAINING_COMPLETE.
func apply_and_close() -> void:
	training.apply_base_stats()
	if training.stats_box != null:
		training.stats_box.close()


## tickEntityWalkTo(0xFC, target, x, z, 0).
func walk_partner(target: int, x: int, z: int) -> bool:
	return interpreter == null or interpreter.tick_walk_to(ScriptContext.OWNER_PARTNER, target, x, z)


## createCameraMovement(point, speed).
func pan_to(point: Vector3, speed: int) -> void:
	var f := field()
	if f != null:
		f.start_pan(point, speed)


func overlays() -> MapOverlays:
	var f := field()
	return f.overlays if f != null else null


func cancel_held() -> bool:
	return pad != null and pad.polled & Pad.CANCEL != 0


## The partner's Digimon (its key) and DIGIMON_DATA level.
func partner_digimon() -> Variant:
	return game_state.state["partner"]["digimon"]


func partner_level() -> int:
	var level = data.digimon(partner_digimon()).get("level", {})
	return int(level.get("id", 0)) if level is Dictionary else int(level)
