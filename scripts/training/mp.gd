class_name MpStation
extends TrainingStation
## The Green Gym's MP station, "Waterfall" (TRN_setupMpTraining, TRN_tickMpTraining;
## trn/trn_mp.c; specs/training.md §6.6): the partner walks under the waterfall by its approach;
## the fall's sprites switch to their pouring look and the splash moves to its head. At the end it
## walks back to the approach and stays there.

## TRN_D_8008F330, the approach, and TRN_D_8008F320, the point under the fall (PSX x, z).
@export var approach := Vector2i(0x290, 0x2EE)
@export var point := Vector2i(0x2AC, 0x868)
## MAIN_D_8013536C / 6E: the splash, moved to the partner's head.
@export var splash_start := 0xA4
@export var splash_count := 8
## MAIN_D_80135372 / 74: the calm fall; MAIN_D_80135376 / 78: the fall pouring on the partner.
@export var calm_start := 0x93
@export var calm_count := 0x10
@export var pouring_start := 0xA3
@export var pouring_count := 0x18

## The splash sits 0x14 background pixels above the head.
const SPLASH_ABOVE := 0x14
const ANIM_STAND := 0
const ANIM_BACK := 2
const SOUND_FALL := 2

var _saved: Array = []
## MAIN_D_80135384: the fall's voices.
var _fall_sound := 0


func _init() -> void:
	map = 0x70
	stat = Training.STAT_MP


func setup() -> void:
	count_upgrade("upgrade_mp_counter")
	training.complete = false


## TRN_tickMpTraining.
func tick() -> void:
	var o := overlays()
	var p := partner()
	match state:
		0:
			if o != null:
				_saved = o.store_positions(splash_start, splash_count)
			if tamer() != null:
				tamer().set_state(Tamer.STATE_TRAINING)
			if p != null:
				p.set_state(Partner.STATE_TRAINING)
			partner_animation(ANIM_WALK)
			pan_to(Content.psx_to_godot([point.x, 0, point.y]), 10)
			play(SOUND_START)
			counter = 0
			state = 1
			start_slot_session()
		1:
			if walk_partner(ScriptInterpreter.FREE, approach.x, approach.y):
				state = 2
		2:
			if walk_partner(ScriptInterpreter.FREE, point.x, point.y):
				if o != null:
					o.set_flag(calm_start, 1, calm_count)
					o.set_flag(pouring_start, 0, pouring_count)
					o.move(splash_start, splash_count, 0, head_pixel_y() - SPLASH_ABOVE)
				if p != null:
					p.set_direction(0)
				partner_animation(ANIM_STAND)
				_fall_sound = play_loop(SOUND_FALL)
				state = 3
				start_slot_spin()
		3:
			counter += 1
			if session_over():
				training.award_mp_gains(partner_digimon(), 0, result())
				if o != null:
					o.set_flag(calm_start, 0, calm_count)
					o.set_flag(pouring_start, 1, pouring_count)
					o.load_positions(_saved, splash_start)
				var t := tamer()
				if t != null:
					pan_to(t.position, 10)
				partner_animation(ANIM_BACK)
				play(SOUND_END)
				stop_loop(_fall_sound)
				state = 4
		4:
			if walk_partner(ScriptInterpreter.FREE, approach.x, approach.y):
				partner_animation(ANIM_DONE)
				wait = -1
				state = 5
		5:
			if gains_counted():
				apply_and_close()
				if tamer() != null:
					tamer().set_state(Tamer.STATE_FREE)
				if p != null:
					p.set_state(Partner.STATE_NORMAL)
				counter = 0
				finish()


## getDrawPosition of the partner's head (its location, y − digimon_data.height): the background
## pixel row.
func head_pixel_y() -> int:
	var p := partner()
	var f := field()
	if p == null or f == null or f.data.is_empty():
		return 0
	var height := int(data.digimon(partner_digimon()).get("height", 0))
	var at := partner_xz()
	var y := int(-p.position.y) - height
	return int(f.background_pixel(Content.psx_to_godot([at.x, y, at.y])).y)
