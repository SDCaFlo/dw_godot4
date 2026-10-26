class_name OffenseStation
extends TrainingStation
## The Offense stations (TRN_setupOffenseTraining, TRN_tickOffenseTraining; trn/trn_off.c;
## specs/training.md §6.3): the partner strikes with its strike animation (GameData
## training_animation); at the hit frame the sparks fly and the target reacts. The Green Gym's
## Tree Striking shakes the tree (states 2-3); Gear Savanna's Striking Special swaps the target's
## sprites (`special`, states 7-8).

## TRN_D_8008F320: where the partner strikes from (PSX x, z), and its rotation there.
@export var point := Vector2i(-0x3D6, -0xA14)
@export var rotation := 0x200
## TRN_D_8008F340: the three sparks (PSX x, y, z).
@export var spark_points: Array = [Vector3i(-0x44C, -0x258, -0xB22), Vector3i(-0x44C, -0x1F4, -0xB22),
		Vector3i(-0x44C, -0x190, -0xB22)]
## MAIN_D_8013536C / 6E: the target's map overlay instances.
@export var overlay_start := 0x64
@export var overlay_count := 8
## Striking Special (the C's instance 6): the target's sprites swap at each hit instead of the shake.
@export var special := false
## The award's `b`: 0 the Green Gym's gains (Offense + Speed), 6 Gear Savanna's (HP + Offense).
@export var award_variant := 0
## Only the Green Gym trains the upgrade counter.
@export var counts_counter := true
## Striking Special: the sprites hidden while the target's show (0x27 x 4), and the count passed to
## resetMapObjectAnimation (the C passes the start, 0x2B).
@export var swap_start := 0x27
@export var swap_count := 4
@export var reset_count := 0x2B

## The tree's shake: (−4, +2) for 3 frames, (+4, −2) for 3, then damped; a strike lasts 0x29.
const SHAKE_IN := 4
const SHAKE_OUT := 7
const STRIKE_FRAMES := 0x29
## Striking Special: frames from the hit to the next strike.
const SPECIAL_FRAMES := 0x2E
const SOUND_HIT := 5
const SOUND_SPECIAL := 0x10
const ANIM_BACK := 2
## A Digimon without a training_animation record (the table's most common values).
const DEFAULT_STRIKE := 0x2E
const DEFAULT_HIT := 10

## MAIN_D_8013537E: frames into the strike.
var hit := 0
var _saved: Array = []


func _init() -> void:
	map = 0x70
	stat = Training.STAT_OFFENSE


func setup() -> void:
	if counts_counter:
		count_upgrade("upgrade_off_counter")
	training.complete = false


func _strike() -> int:
	return int(data.training_animation(partner_digimon()).get("strike_anim", DEFAULT_STRIKE))


func _hit_frame() -> int:
	return int(data.training_animation(partner_digimon()).get("hit_frame", DEFAULT_HIT))


## TRN_tickOffenseTraining.
func tick() -> void:
	var o := overlays()
	var p := partner()
	match state:
		0:
			if o != null:
				_saved = o.store_positions(overlay_start, overlay_count)
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
			start_slot_session()
		1:
			# TRN_func_800888A0(4), the slot result −2, is dead code: nothing sets −2 (not ported).
			if walk_partner(ScriptInterpreter.FREE, point.x, point.y):
				partner_animation(_strike())
				if p != null:
					p.step_blocked = true
				hit = 0
				if p != null:
					p.set_direction(rotation)
				state = 7 if special else 2
				start_slot_spin()
		2:
			hit += 1
			counter += 1
			if p != null:
				p.step_blocked = true
			if hit == _hit_frame():
				spark(spark_points)
				hit = 0
				play(SOUND_HIT)
				state = 3
		3:
			hit += 1
			counter += 1
			if o != null:
				if hit < SHAKE_IN:
					o.move(overlay_start, overlay_count, -4, 2)
				elif hit < SHAKE_OUT:
					o.move(overlay_start, overlay_count, 4, -2)
				elif counter % 2 == 0:
					o.move(overlay_start, overlay_count, (100 - hit) / 20, -(100 - hit) / 50)
				else:
					o.move(overlay_start, overlay_count, -(100 - hit) / 20, (100 - hit) / 50)
			if hit >= STRIKE_FRAMES:
				hit = 0
				partner_animation(_strike())
				state = 2
			if session_over():
				training.award_offense_gains(partner_digimon(), award_variant, result())
				partner_animation(ANIM_DONE)
				if o != null:
					o.load_positions(_saved, overlay_start)
				play(SOUND_END)
				_pan_to_tamer()
				wait = -1
				state = 4
		7:
			counter += 1
			hit += 1
			if hit == _hit_frame():
				spark(spark_points)
				play(SOUND_SPECIAL)
				if o != null:
					o.set_flag(swap_start, 1, swap_count)
					o.set_flag(overlay_start, 0, overlay_count)
					o.reset_animation(overlay_start, reset_count)
				hit = 0
				state = 8
		8:
			counter += 1
			hit += 1
			if hit == SPECIAL_FRAMES:
				_unswap(o)
				partner_animation(_strike())
				hit = 0
				state = 7
			if session_over():
				_unswap(o)
				training.award_offense_gains(partner_digimon(), award_variant, result())
				partner_animation(ANIM_DONE)
				_pan_to_tamer()
				play(SOUND_END)
				wait = -1
				state = 4
		4:
			if gains_counted():
				partner_animation(ANIM_BACK)
				state = 6
		6:
			if walk_partner(ScriptContext.OWNER_TAMER, 0, 0):
				apply_and_close()
				if p != null:
					p.set_state(Partner.STATE_NORMAL)
				if tamer() != null:
					tamer().set_state(Tamer.STATE_FREE)
				set_camera_follow(true)
				counter = 0
				finish()


func _unswap(o: MapOverlays) -> void:
	if o != null:
		o.set_flag(swap_start, 0, swap_count)
		o.set_flag(overlay_start, 1, overlay_count)


func _pan_to_tamer() -> void:
	var t := tamer()
	if t != null:
		pan_to(t.position, 10)
