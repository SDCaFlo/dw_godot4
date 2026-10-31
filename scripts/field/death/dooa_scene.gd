class_name DooaScene
extends Node
## The DOOA overlay (src/dooa/dooa.c; specs/death_reincarnation.md §5, §7): the partner's
## dissolution (DOOA_tick, DOOA_tickDissolve) and the rebirth (DOOA_getSequenceState,
## DOOA_tickRebirth), on the C's frame timeline. Logic only: the states read `frame` (-1 once a
## sequence is over), DeathHost draws it from the state below and `phase_changed`. Not ported (the
## DeathHost draws stand-ins): the shards and wireframes, the flashes, the cutscene camera, the CLUT
## fades of the models.

## A phase began (the values are the C's seq->phase).
signal phase_changed(phase: int)

const NONE := 0
const DISSOLVE := 1
const REBIRTH := 2

## DOOA_tickDissolve's phases.
const PHASE_IRIS := 0
const PHASE_TURN := 1
const PHASE_SHARDS := 2
const PHASE_SQUASH := 0x64
const PHASE_RISE := 0x65
const PHASE_WAIT := 3
const PHASE_EGG := 0x66
const PHASE_END := 4
## DOOA_tickRebirth's phases.
const PHASE_REBIRTH := 0xC9
const PHASE_SHARDS_GATHER := 0xCA
const PHASE_SHARDS_HOLD := 0xCB
const PHASE_SHARDS_FADE := 0xCD
const PHASE_BABY_LOAD := 0xCE
const PHASE_BABY_FADE := 0xCF
const PHASE_SPARKLES := 0xD0
const PHASE_POSE := 7

## The iris closes over frames 0-0x21 and is drawn while frame < 36 (DOOA_renderDissolve).
const IRIS_END := 0x21
const IRIS_DRAWN := 36
## The map changes at 0x23 (a 0-lives death starts there: MURD drew the iris).
const MAP_CHANGE := 0x23
## Partner animations: 1 (lives left: its tired idle), 0x2C (none left), 0xC, 0x21, the baby's 0x1C,
## 0xB.
const ANIM_TIRED := 1
const ANIM_DEAD := 0x2C
const ANIM_FALL := 0xC
const ANIM_GONE := 0x21
const ANIM_HATCH := 0x1C
const ANIM_POSE := 0xB
## loadMapSounds2(0x13): the death's sound set in slot 8.
const SOUND_SET := 0x13
const SOUND_BANK := 8
## The death maps (murd.c:781, dooa.c:1734): 0xCD = ROOM10, 0xDA = ROOM08, entrance 1.
const DEATH_MAP_LATE := 0xCD
const DEATH_MAP_EARLY := 0xDA
const DEATH_MAP_EXIT := 1
const TRIGGER_JIJIMON_EXTENDED := 0xDC
const TRIGGER_CLINIC := 0xD6
const PSTAT_PROSPERITY := 1
## DOOA_SPARKLE_BONE_IDS (dooa.c:291): one entry per frame of the sparkle phase, a sound where >= 0.
const SPARKLE_BONE_IDS := [
	-1, -1, -1, -1, 0, -1, -1, -1, -1, -1, -1, -1,
	-1, -1, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	2, -1, -1, -1, -1, -1, -1, -1, -1, -1, 3, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, 4, 5, -1, 0,
]
const SPARKLES := 47

var partner: Partner
var tamer: Tamer
## The entity table (ENTITY_TABLE: 0 the tamer, 1 the partner, 2-9 the NPCs).
var entities: FieldEntities
var game_state: Node
var evolution: Evolution
var data: Node
## The Sound node; null: silent (the tests).
var sound: Node
## changeMap(map, exit) (the field's map change, MapSession.change_map).
var change_map := Callable()
## setMapLayerEnabled(enabled): the map's objects (doors, overlays, items, chests, poop).
var map_layer := Callable()

## DOOA_REINCARNATION_SEQ: frame (-1 = over), phase, the egg slot (DOO2's panel or rand() % 4).
var frame := -1
var phase := PHASE_IRIS
var egg_slot := 0
var sequence := NONE
## DEATH_MAP_TARGET.
var death_map := DEATH_MAP_EARLY
## The partner's lives when the dissolve started (the C reads partner->lives as it goes; nothing
## changes them meanwhile).
var lives := 0
## fadeoutCLUT1's level on the map's background: 0xFF black (from the map change to the rebirth).
var darkness := 0
## The egg model's fade in (0 hidden .. 0xFF shown, DOO2_fadeClut over frames 0x185-0x1B7).
var egg_fade := 0
## The partner's squash in phase 0x64 (scale y, x / z), 1.0 = none: a stand-in for the curve
## DOOA_DISSOLVE_SCALE_CURVE drives (stretched up, thinned), over the C's frames 0xBF-0xD0.
var squash := Vector2.ONE
var _saved_position := Vector3.ZERO
var _saved_direction := 0
var _sparkle := 0
## DOOA_SAVED_ENTITY_VISIBILITY.
var _visibility: Array = []


## DOOA_tick(partner, buffer, 0) (dooa.c:1700): the dissolution object, from frame 0 (natural death:
## the iris) or 0x23 (no life left: MURD drew it, the partner is already off the map); the death
## map chosen.
func start_dissolve() -> void:
	lives = int(game_state.state["partner"]["lives"])
	frame = 0 if lives != 0 else MAP_CHANGE
	if lives == 0:
		partner.visible = false
	sequence = DISSOLVE
	_set_phase(PHASE_IRIS)
	darkness = 0
	egg_fade = 0
	squash = Vector2.ONE
	_saved_position = partner.position
	_saved_direction = partner.direction
	if lives != 0:
		partner.start_animation(ANIM_TIRED)
	death_map = choose_death_map(game_state)


## The death map (setDeathMap's target, murd.c:781 / dooa.c:1734): ROOM10 (0xCD) once the clinic
## or Jijimon's extended house is open (triggers 0xDC, 0xD6) or prosperity (script value 1) is 50,
## else ROOM08 (0xDA).
static func choose_death_map(gs: Node) -> int:
	if gs.is_trigger_set(TRIGGER_JIJIMON_EXTENDED) or gs.is_trigger_set(TRIGGER_CLINIC) \
			or int(gs.script_value(PSTAT_PROSPERITY)) >= 50:
		return DEATH_MAP_LATE
	return DEATH_MAP_EARLY


## DOOA_getSequenceState(0, 0) (dooa.c:1748): the rebirth object; with no life left the egg is
## random (rand() % 4), else the one DOO2's panel (builtin 29) chose.
func start_rebirth() -> void:
	if int(game_state.state["partner"]["lives"]) == 0:
		egg_slot = Rng.rand() % 4
	sequence = REBIRTH
	_set_phase(PHASE_REBIRTH)
	frame = 0
	_sparkle = 0


## One game frame of the active object (the object list).
func tick() -> void:
	match sequence:
		DISSOLVE:
			_tick_dissolve()
		REBIRTH:
			_tick_rebirth()


func _set_phase(value: int) -> void:
	phase = value
	phase_changed.emit(value)


func _play(id: int) -> void:
	if sound != null:
		sound.play_sound(SOUND_BANK, id)


func _stop() -> void:
	if sound != null:
		sound.stop_sound()


## DOOA_tickDissolve (dooa.c:310).
func _tick_dissolve() -> void:
	frame += 1
	if partner.animator != null and partner.animator.anim_id == ANIM_FALL \
			and partner.animator.frame >= partner.animator.frame_count:
		partner.start_animation(ANIM_TIRED)
		_saved_position = partner.position
		_saved_direction = partner.direction
	match phase:
		PHASE_IRIS:
			if frame < MAP_CHANGE:
				return
			if change_map.is_valid():
				change_map.call(death_map, DEATH_MAP_EXIT)
			if sound != null:
				sound.music.stop_bgm()
				sound.load_map_sounds(SOUND_SET)
			# setSomeDyingState: the tamer stands, the partner's dying state waits for this object.
			tamer.set_state(Tamer.STATE_STILL)
			partner.state = Partner.STATE_DYING
			partner.sub_state = 2
			tamer.camera_follow = false
			partner.position = _saved_position
			partner.set_direction(_saved_direction)
			if lives != 0:
				partner.start_animation(ANIM_TIRED)
			else:
				partner.start_animation(ANIM_DEAD)
			_set_others_visible(false)
			_set_phase(PHASE_TURN)
			if map_layer.is_valid():
				map_layer.call(false)
			_hide_all_but_partner()
			darkness = 0xFF
		PHASE_TURN:
			partner.visible = true
			if frame >= 0x56:
				_saved_position = partner.position
				_saved_direction = partner.direction
				partner.position = Vector3.ZERO
				partner.look_at_psx(int(tamer.position.x), int(-tamer.position.z))
				_set_phase(PHASE_SHARDS)
				if lives != 0:
					partner.start_animation(ANIM_FALL)
		PHASE_SHARDS:
			if frame == 0x69:
				_play(0)
			if frame == 0x8C:
				_stop()
			if frame >= 0xBF:
				_stop()
				_play(1)
				_set_phase(PHASE_SQUASH)
		PHASE_SQUASH:
			var index := PsxMath.lerp_int(0, 0x1F, 0xBF, 0xD0, frame)
			var t := float(index) / 0x1F
			squash = Vector2(1.0 + t, maxf(1.0 - t * 0.5, 0.0))
			if frame >= 0xD1:
				squash = Vector2.ONE
				partner.start_animation(ANIM_GONE)
				partner.visible = false
				partner.position = Vector3(partner.position.x, _saved_position.y, partner.position.z)
				_play(2)
				_set_phase(PHASE_RISE)
		PHASE_RISE:
			if frame >= 0x135:
				_play(3)
				_set_phase(PHASE_WAIT)
		PHASE_WAIT:
			if frame >= 0x17B:
				_set_phase(PHASE_EGG)
		PHASE_EGG:
			if frame >= 0x185 and frame < 0x1B8:
				var npc := entities.entity(2) if entities != null else null
				if npc != null:
					npc.visible = true
				egg_fade = 0xFF - PsxMath.lerp_int(0xFF, 0, 0x185, 0x1B7, frame)
			if frame >= 0x1B7:
				egg_fade = 0xFF
				_set_phase(PHASE_END)
		PHASE_END:
			# The camera back on the tamer's map position, the object removed.
			sequence = NONE
			frame = -1
			_stop()


## DOOA_tickRebirth (dooa.c:1003).
func _tick_rebirth() -> void:
	frame += 1
	match phase:
		PHASE_REBIRTH:
			if frame >= 10:
				_stop()
				_play(5)
				_set_phase(PHASE_SHARDS_GATHER)
		PHASE_SHARDS_GATHER:
			if frame >= 50:
				_set_phase(PHASE_SHARDS_HOLD)
		PHASE_SHARDS_HOLD:
			if frame >= 100:
				_set_phase(PHASE_SHARDS_FADE)
		PHASE_SHARDS_FADE:
			if frame >= 132:
				_play(6)
				_set_phase(PHASE_BABY_LOAD)
		PHASE_BABY_LOAD:
			if frame >= 152:
				var key := evolution.reincarnate(egg_slot) if evolution != null else ""
				if key != "":
					partner.load_digimon(data, key)
				if sound != null and key != "":
					sound.load_partner_sounds(data.digimon_sounds(key))
				partner.position = Vector3.ZERO
				partner.set_direction(0)
				partner.start_animation(Partner.ANIM_IDLE)
				_set_others_visible(true)
				var npc := entities.entity(2) if entities != null else null
				if npc != null:
					npc.visible = true
				tamer.visible = true
				partner.visible = false
				egg_fade = 0
				if map_layer.is_valid():
					map_layer.call(true)
				_set_phase(PHASE_BABY_FADE)
		PHASE_BABY_FADE:
			if frame >= 202:
				darkness = 0
				partner.visible = true
				partner.start_animation(ANIM_HATCH)
				_sparkle = 0
				_set_phase(PHASE_SPARKLES)
			elif frame >= 152:
				darkness = PsxMath.lerp_int(255, 0, 152, 202, frame)
		PHASE_SPARKLES:
			if _sparkle < SPARKLES:
				if int(SPARKLE_BONE_IDS[_sparkle]) >= 0:
					_play(7)
				_sparkle += 1
			elif frame >= 262:
				partner.start_animation(ANIM_POSE)
				_set_phase(PHASE_POSE)
		PHASE_POSE:
			# As EvolutionScene's pose: a looping 0xB plays once more to its end (animFrame == frameCount).
			if partner.animator != null and partner.animator.loop_count == PsxAnimator.ENDLESS:
				partner.animator.finish_loop()
			if partner.animator == null or partner.animator.frame >= partner.animator.frame_count:
				sequence = NONE
				frame = -1


## DOOA_setOtherEntitiesVisible (dooa.c:692): off with their visibility kept, or back as kept.
func _set_others_visible(restore: bool) -> void:
	var table: Array = entities.table() if entities != null else [tamer, partner]
	if not restore:
		_visibility = []
		for e in table:
			var shown: bool = e != null and e != partner and e.visible
			_visibility.append(shown)
			if shown:
				e.visible = false
	else:
		for i in mini(table.size(), _visibility.size()):
			if table[i] != null and table[i] != partner:
				table[i].visible = _visibility[i]


## DOOA_hideAllButPartner (dooa.c:716).
func _hide_all_but_partner() -> void:
	var table: Array = entities.table() if entities != null else [tamer, partner]
	for i in table.size():
		if i != 1 and table[i] != null:
			table[i].visible = false
