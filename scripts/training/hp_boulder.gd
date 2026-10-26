class_name HpBoulderStation
extends TrainingStation
## The Green Gym's HP station, "Boulder Moving" (TRN_setupHpTraining, TRN_tickHpTraining;
## trn/trn_hp.c; specs/training.md §2.2): the partner pushes the boulder (map overlay instances)
## while the dust rises, for a minute or until △ is held; then the gains, and it walks back.

## TRN_D_8008F320: where the partner pushes (PSX x, z).
@export var point := Vector2i(0x58C, -0x6D0)
## MAIN_D_8013536C / 6E: the boulder's overlay instances.
@export var overlay_start := 0x53
@export var overlay_count := 0x10
## The three dust lines of state 2 (TRN_createCloudFXLine): every, x, z, dx, dz, count.
@export var dust_lines: Array = [[0xF, 0x550, -0x604, 0x64, -0x32, 8], [0x14, 0x5B5, -0x667, 0x32, -0x32, 6],
		[0x12, 0x514, -0x525, 0x14, -0x32, 4]]
## A push every 120 frames (the session is SESSION_FRAMES).
const PUSH_FRAMES := 120
## The partner's rotation while pushing, and its push animation (walk and done: the base's).
const PUSH_ROTATION := 0xA00
const ANIM_PUSH := 0x1B
## playSound(8, 0): the push (start and end: the base's).
const SOUND_PUSH := 0

## TRN_D_8008F368 / 388: the boulder's saved positions.
var _saved: Array = []


func _init() -> void:
	map = 0x70
	stat = Training.STAT_HP


## TRN_setupHpTraining's part for its map.
func setup() -> void:
	count_upgrade("upgrade_hp_counter")
	training.complete = false


## TRN_tickHpTraining.
func tick() -> void:
	var o := overlays()
	var p := partner()
	match state:
		0:
			if o != null:
				_saved = o.store_positions(overlay_start, overlay_count)
			if tamer() != null:
				tamer().set_state(Tamer.STATE_TRAINING)
			if p != null:
				p.set_state(Partner.STATE_TRAINING)
			partner_animation(ANIM_WALK)
			pan_to(Content.psx_to_godot([point.x, 0, point.y]), 10)
			play(SOUND_START)
			counter = 0
			state = 1
		1:
			if walk_partner(ScriptInterpreter.FREE, point.x, point.y):
				partner_animation(ANIM_PUSH)
				if p != null:
					p.set_direction(PUSH_ROTATION)
				play(SOUND_PUSH)
				state = 2
		2:
			_push(o, p)
		3:
			if training.gains_are_zero():
				state = 4
				wait = 0
		4:
			wait += 1
			if wait >= AFTER_GAINS:
				partner_animation(ANIM_WALK)
				state = 5
		5:
			counter -= 1
			if counter > 0 and o != null:
				o.move(overlay_start, overlay_count, -1, 2)
			var back := walk_partner(ScriptContext.OWNER_TAMER, 0, 0)
			if back and counter <= 0:
				training.apply_base_stats()
				if training.stats_box != null:
					training.stats_box.close()
				if p != null:
					p.set_state(Partner.STATE_NORMAL)
				if o != null:
					o.load_positions(_saved, overlay_start)
				if tamer() != null:
					tamer().set_state(Tamer.STATE_FREE)
				if clouds != null:
					clouds.remove_all()
				counter = 0
				finish()


## State 2: the pushes, the shake, the sound and the dust; then the end of the session.
func _push(o: MapOverlays, p: Partner) -> void:
	if p != null:
		p.step_blocked = true
	if counter % PUSH_FRAMES == 0 and counter < SESSION_FRAMES + 1:
		if p != null:
			p.step_blocked = false
		if o != null:
			o.move(overlay_start, overlay_count, 1, -2)
	if o != null:
		o.move(overlay_start, overlay_count, 2 if counter % 2 == 0 else -2, 0)
	if counter % 10 == 0:
		play(SOUND_PUSH)
	if clouds != null:
		for line in dust_lines:
			Training.cloud_line(counter, line[0], line[1], line[2], line[3], line[4], line[5], clouds.create)
	counter += 1
	# The slot session (4d-3) replaces this test with its result.
	if counter >= SESSION_FRAMES or cancel_held():
		counter = (counter % SESSION_FRAMES) / PUSH_FRAMES
		play(SOUND_END)
		state = 3
		partner_animation(ANIM_DONE)
		training.award_hp_gains(partner_digimon(), 0, NORMAL_RESULT)
		var t := tamer()
		if t != null:
			pan_to(t.position, 10)
