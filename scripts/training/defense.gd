class_name DefenseStation
extends TrainingStation
## The Green Gym's Defense station, "Punching Glove" (TRN_setupDefenseTraining,
## TRN_tickDefenseTraining; trn/trn_def.c; specs/training.md §6.5): the glove (map overlay
## instances) punches the guarding partner, which is knocked back and walks back to its point. A
## session is whole punches: △ (counter = 1200) only ends it back at the point.

## TRN_D_8008F320: the point (PSX x, z).
@export var point := Vector2i(-0x33B, -0x662)
## TRN_D_8008F340: the three sparks (PSX x, y, z).
@export var spark_points: Array = [Vector3i(-0x384, -0x1F4, -0x7D0), Vector3i(-0x3B6, -0x1F4, -0x76C),
		Vector3i(-0x3B6, -0x1F4, -0x834)]
## MAIN_D_8013536C / 6E: the glove.
@export var overlay_start := 0x47
@export var overlay_count := 0xD

## The guard: rotation and animation.
const GUARD_ROTATION := 0x400
const ANIM_GUARD := 0x25
## States 2-9: the glove's move (dx) and its limit past its saved x; after the punch (state 3) and
## the bounce (4) the partner is knocked back.
const GLOVE := {2: [0x32, 0x64], 3: [-0x32, 0x32], 4: [0x32, 0x5A], 5: [-0x1E, 0x3C], 6: [0x14, 0x5A],
		7: [-0xA, 0x46], 8: [5, 0x5A], 9: [-4, 0]}
const KNOCK_BACK := 0x64
## The cloud of the knock-back, behind the partner.
const CLOUD_BEHIND := 0x64
const SOUND_PUNCH := 4

var _saved: Array = []
## MAIN_D_80135384: the punch's voices.
var _punch_sound := 0


func _init() -> void:
	map = 0x70
	stat = Training.STAT_DEFENSE


func setup() -> void:
	count_upgrade("upgrade_defense_counter")
	training.complete = false


## TRN_tickDefenseTraining.
func tick() -> void:
	var o := overlays()
	var p := partner()
	if state >= 2 and state <= 10 and cancel_held():
		counter = SESSION_FRAMES
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
		1:
			if walk_partner(ScriptInterpreter.FREE, point.x, point.y):
				_guard(p)
				state = 2
		2, 3, 4, 5, 6, 7, 8, 9:
			counter += 1
			if state == 3 or state == 4:
				_knock_back(p)
			if _glove(o, state):
				if state == 2:
					spark(spark_points)
					_punch_sound = play_loop(SOUND_PUNCH)
				if state == 9:
					if o != null:
						o.load_positions(_saved, overlay_start)
					partner_animation(ANIM_WALK)
					state = 10
				else:
					state += 1
		10:
			if walk_partner(ScriptInterpreter.FREE, point.x, point.y):
				if not slots and counter >= SESSION_FRAMES:
					training.award_defense_gains(partner_digimon(), 0, result())
					partner_animation(ANIM_DONE)
					play(SOUND_END)
					stop_loop(_punch_sound)
					var t := tamer()
					if t != null:
						pan_to(t.position, 10)
					wait = -1
					state = 12
				else:
					_guard(p)
					state = 2
		12:
			if gains_counted():
				partner_animation(ANIM_WALK)
				state = 14
		14:
			if walk_partner(ScriptContext.OWNER_TAMER, 0, 0):
				apply_and_close()
				if o != null:
					o.load_positions(_saved, overlay_start)
				if tamer() != null:
					tamer().set_state(Tamer.STATE_FREE)
				set_camera_follow(true)
				if p != null:
					p.set_state(Partner.STATE_NORMAL)
				counter = 0
				finish()


func _guard(p: Partner) -> void:
	if p != null:
		p.set_direction(GUARD_ROTATION)
	partner_animation(ANIM_GUARD)


## The glove's move of a state; true when it reached its limit (saved x + the state's offset).
func _glove(o: MapOverlays, s: int) -> bool:
	if o == null or _saved.is_empty():
		return true
	var g: Array = GLOVE[s]
	return o.move_with_limit(overlay_start, overlay_count, g[0], 0, _saved[0].x + g[1], 0)


## States 3-4: the partner + 0x64 in x, guarding again, with a cloud behind it.
func _knock_back(p: Partner) -> void:
	if p == null:
		return
	p.position.x += KNOCK_BACK
	_guard(p)
	var at := partner_xz()
	if clouds != null:
		clouds.create(at.x, at.y - CLOUD_BEHIND)
