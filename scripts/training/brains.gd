class_name BrainsStation
extends TrainingStation
## The Brains stations (TRN_setupBrainsTraining, TRN_tickBrainsTraining; trn/trn_brain.c;
## specs/training.md §6.7): the tamer walks to his place and the partner to its own; the Green
## Gym's Classroom has the tamer teach, Misty Trees' teaching has the map's first NPC (Cherrymon)
## teach (`with_npc`). Then the gains, the new orders or a technique (box 2); nobody walks back.

## TRN_D_8008F358, the tamer's place, and TRN_D_8008F320, the partner's (PSX x, z).
@export var tamer_place := Vector2i(-0x5AC, 0x61B)
@export var partner_place := Vector2i(-0x4E1, 0x3F3)
## The teacher is NPC_ENTITIES[0] (the C's instance 9), not the tamer.
@export var with_npc := false
@export var counts_counter := true

const ANIM_STAND := 0
const ANIM_TAMER_WALK := 2
const ANIM_PARTNER_WALK := 2
const ANIM_TEACH := 9
const ANIM_LISTEN := 0x16
const ANIM_NPC_TEACH := 0x1E
const TEACH_EVERY := 0x1E
const NPC_SOUND_EVERY := 0x3C
const LISTEN_EVERY := 0x23
const SOUND_TEACH := 3
const SOUND_NPC := 0x12


func _init() -> void:
	map = 0x70
	stat = Training.STAT_BRAINS


func setup() -> void:
	if counts_counter:
		count_upgrade("upgrade_brain_counter")
	training.complete = false


## TRN_tickBrainsTraining.
func tick() -> void:
	var t := tamer()
	var p := partner()
	var teacher := npc(0)
	match state:
		0:
			if t != null:
				t.set_state(Tamer.STATE_NONE)
			tamer_animation(ANIM_TAMER_WALK)
			if p != null:
				p.set_state(Partner.STATE_TRAINING)
			partner_animation(ANIM_STAND)
			play(SOUND_START)
			pan_to(Content.psx_to_godot([tamer_place.x, 0, tamer_place.y]), 10)
			counter = 0
			state = 1
			start_slot_session()
		1:
			if walk_tamer(ScriptInterpreter.FREE, tamer_place.x, tamer_place.y):
				tamer_animation(ANIM_STAND)
				look_at(t, p)
				partner_animation(ANIM_PARTNER_WALK)
				state = 2
		2:
			if walk_partner(ScriptInterpreter.FREE, partner_place.x, partner_place.y):
				if with_npc:
					look_at(t, p)
					look_at(p, teacher)
					look_at(teacher, p)
					partner_animation(ANIM_LISTEN)
					if teacher != null:
						teacher.start_animation(ANIM_NPC_TEACH)
				else:
					look_at(t, p)
					look_at(p, t)
					tamer_animation(ANIM_TEACH)
					partner_animation(ANIM_LISTEN)
				state = 3
				start_slot_spin()
		3:
			counter += 1
			if with_npc:
				if teacher is FieldDigimon and teacher.animator != null \
						and teacher.animator.frame >= teacher.animator.frame_count:
					teacher.start_animation(ANIM_NPC_TEACH)
				if counter % NPC_SOUND_EVERY == 0:
					play(SOUND_NPC)
			else:
				if counter % TEACH_EVERY == 0:
					play(SOUND_TEACH)
					tamer_animation(ANIM_TEACH)
				if t != null:
					t.step_blocked = true
			if counter % LISTEN_EVERY == 0:
				partner_animation(ANIM_LISTEN)
			if session_over():
				# b is 0 for both teachings (trn_brain.c:143), as in the C.
				training.award_brains_gains(partner_digimon(), 0, result())
				partner_animation(ANIM_DONE)
				if t != null:
					pan_to(t.position, 10)
				if teacher != null:
					teacher.start_animation(ANIM_STAND)
				wait = -1
				state = 4
				play(SOUND_END)
		4:
			if gains_counted():
				apply_and_close()
				if training.brains_box != null:
					training.brains_box.close()
				if t != null:
					t.set_state(Tamer.STATE_FREE)
				if p != null:
					p.set_state(Partner.STATE_NORMAL)
				counter = 0
				finish()
