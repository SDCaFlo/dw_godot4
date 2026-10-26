class_name SpeedStation
extends TrainingStation
## The Speed stations (TRN_setupSpeedTraining, TRN_tickSpeedTraining; trn/trn_speed.c;
## specs/training.md §6.4): the partner runs on from its point with its run's root motion; off
## screen, on a counter divisible by 60, it is put back at the start of the course.

## TRN_D_8008F320: the start (PSX x, z), and the rotation it runs in.
@export var point := Vector2i(0x2D, -0x184)
@export var rotation := 0xC00
## The wrap: the coordinate set back (x, or z when false) and its value.
@export var wrap_x := true
@export var wrap_value := -0xBB8
## The award's `b` (0 the Green Gym, 6 Gear Savanna: the same gains).
@export var award_variant := 0
@export var counts_counter := true

const WRAP_EVERY := 0x3C


func _init() -> void:
	map = 0x70
	stat = Training.STAT_SPEED


func setup() -> void:
	if counts_counter:
		count_upgrade("upgrade_speed_counter")
	training.complete = false


## TRN_tickSpeedTraining.
func tick() -> void:
	var p := partner()
	match state:
		0:
			if tamer() != null:
				tamer().set_state(Tamer.STATE_TRAINING)
			set_camera_follow(false)
			if p != null:
				p.set_state(Partner.STATE_TRAINING)
			partner_animation(ANIM_WALK)
			pan_to(Content.psx_to_godot([point.x, 0, point.y]), 10)
			play(SOUND_START)
			counter = 0
			state = 1
		1:
			if walk_partner(ScriptInterpreter.FREE, point.x, point.y):
				if p != null:
					p.set_direction(rotation)
				partner_animation(ANIM_WALK)
				state = 2
		2:
			counter += 1
			if p != null and not p.on_screen and counter % WRAP_EVERY == 0:
				if wrap_x:
					p.position.x = wrap_value
				else:
					p.position.z = -wrap_value
				partner_animation(ANIM_WALK)
			if session_over():
				training.award_speed_gains(partner_digimon(), award_variant, result())
				partner_animation(ANIM_DONE)
				play(SOUND_END)
				var t := tamer()
				if t != null:
					pan_to(t.position, 10)
				wait = -1
				state = 3
		3:
			if gains_counted():
				partner_animation(ANIM_WALK)
				state = 5
		5:
			if walk_partner(ScriptContext.OWNER_TAMER, 0, 0):
				apply_and_close()
				if p != null:
					p.set_state(Partner.STATE_NORMAL)
				# The tamer stays in state 8: the script's end frees him (setMovementEnabled).
				set_camera_follow(true)
				counter = 0
				finish()
