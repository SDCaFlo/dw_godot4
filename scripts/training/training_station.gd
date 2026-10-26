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
var pad: Pad
var sound: Node
var game_state: Node
var data: Node

## The station's object is in the list (addObject … removeObject).
var running := false
## MAIN_D_80135370: value 0xF6, the slot-machine bonus (4d-3; until then the station runs as Normal).
var slots := false
## TRAINING_STATE, MAIN_D_8013537A, MAIN_D_8013537C.
var state := 0
var counter := 0
var wait := 0


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
