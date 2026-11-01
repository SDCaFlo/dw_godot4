class_name DooaScene
extends Node
## The DOOA overlay (src/dooa/dooa.c; specs/death_reincarnation.md §5, §7; specs/death_scene.md):
## the partner's dissolution (DOOA_tick, DOOA_tickDissolve) and the rebirth (DOOA_getSequenceState,
## DOOA_tickRebirth), on the C's frame timeline. Logic only: the states read `frame` (-1 once a
## sequence is over); DeathHost draws the state below (the wireframe share, the shards, the squash,
## the flashes, the egg, the palette fades) and moves the camera through the view callables. The
## shards (DooaShards), the egg's pieces (EggPieceShards) and the flashes (BattleFx) are its own
## objects, ticked after it each frame (their order in the C's object list isn't traced).

## A phase began (the values are the C's seq->phase).
signal phase_changed(phase: int)
## DOOA_spawnShardWave(wave) (B2): the owner answers in the same call with the posed bones
## (shards.spawn_wave), before anything else rolls rand().
signal wave_spawned(wave: int)

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
## DOOA_SPARKLE_BONE_IDS (dooa.c:291): one entry per frame of the sparkle phase; an egg piece breaks
## where >= 0 (G10).
const SPARKLE_BONE_IDS := [
	-1, -1, -1, -1, 0, -1, -1, -1, -1, -1, -1, -1,
	-1, -1, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	2, -1, -1, -1, -1, -1, -1, -1, -1, -1, 3, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, 4, 5, -1, 0,
]
const SPARKLES := 47
## DOOA_SHARD_WAVE_SCHEDULE (dooa.c:263): PARTNER_WIREFRAME_TOTAL over frames 0x69-0x8C (B1).
const WAVE_SCHEDULE := [15, 15, 15, 15, 15, 14, 14, 14, 14, 13, 13, 13, 12, 12, 12, 11, 11, 11, 10, 10, 10, 9, 9, 8,
		8, 7, 7, 6, 6, 5, 5, 4, 3, 2, 1, 0]
const WAVES_START := 0x69
const WAVES_END := 0x8C
## DOOA_DISSOLVE_SCALE_CURVE (dooa.c:273), the squash over 0xBF-0xD0 (C1).
const SCALE_CURVE := [100, 94, 89, 85, 82, 80, 79, 79, 100, 120, 139, 157, 174, 190, 205, 219,
		232, 244, 255, 265, 274, 282, 289, 295, 300, 350, 395, 435, 470, 500, 525, 545]
const ONE := 4096
## WIREFRAME_COLOR_MIN / MAX (model.c:89, 91; reset at 0xD1, dooa.c:493).
const WIRE_MIN := 0x37
const WIRE_MAX := 0xFF
## The room's start drawing offset at 0x56 (dooa.c:376–382, D10): ROOM10 0xBC, ROOM08 0xA0; y 0x78.
const ROOM_OFFSET_LATE := Vector2i(0xBC, 0x78)
const ROOM_OFFSET_EARLY := Vector2i(0xA0, 0x78)
## DOOA_FLASH_POSITION (dooa.c:288).
const REBIRTH_FLASH := Vector3i(0, -100, 0)
## The egg (DOOA_EGG_TMD_PATH, dooa.c:286): 4 eggs × 6 pieces.
const EGG_SIDECAR := "tmd_files/ETCDAT/TAMA.json"
const EGG_PIECES := 6

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
## The camera (FieldMap's view / set_view / restore_map_view, specs/death_scene.md §5).
var get_view := Callable()
var set_view := Callable()
var restore_view := Callable()
## worldPosToScreenPos (FieldMap.world_to_screen: {"screen", "sz"}), for the iris test (B8).
var project := Callable()

## DOOA_REINCARNATION_SEQ: frame (-1 = over), phase, the egg slot (DOO2's panel or rand() % 4).
var frame := -1
var phase := PHASE_IRIS
var egg_slot := 0
var sequence := NONE
## DEATH_MAP_TARGET.
var death_map := DEATH_MAP_EARLY
## The partner's lives when the dissolution started (the C reads partner->lives as it goes; nothing
## changes them meanwhile).
var lives := 0
## fadeoutCLUT1's level on the map's background: 0xFF black (from the map change to the rebirth).
var darkness := 0
## PARTNER_WIREFRAME_TOTAL and the wireframe's grey range (§3 A, B).
var wireframe_total := 16
var wire_color_min := WIRE_MIN
var wire_color_max := WIRE_MAX
## The partner's root scale (4096 = 1, C3).
var scale := Vector3i(ONE, ONE, ONE)
## DOOA_storeDigimonY: the partner's y when the shards started (PSX).
var stored_y := 0
## The rising flash: its start y (B6) and x / z.
var flash_target_y := 0
var _flash_x := 0
var _flash_z := 0
## The partner drawn in front of the iris (ENTITY_TABLE[1]->isOnMap = 0 while the iris closes, B8).
var partner_front := false
## Jijimon's palette (entity 2, J2): 255 black … 0 full colour.
var jijimon_fade := 255
## MAIN_D_80135324, the egg's face groups shown (G2), and MAIN_D_80135364, the pieces (G8).
var egg_threshold := 0
var piece_flags := PackedInt32Array([0, 0, 0, 0, 0, 0])
## seq->fadeLevel: the spark streaks this frame (I1).
var fade_level := 0
## The tamer's and entities 3 / 4's palettes at the rebirth (J4–J7): 255 black … 0.
var tamer_fade := 0
var others_fade := 0
## The flashes (EFE_FLASH_DATA) and the newest one (FLASH_INSTANCE).
var fx := BattleFx.new()
var last_flash := -1
## DOOA_SHARD_EFFECT, from the map change to the rebirth's frame 132.
var shards := DooaShards.new()
var shards_active := false
## DOO2's egg piece fragments.
var pieces := EggPieceShards.new()

var _saved_position := Vector3.ZERO
var _saved_direction := 0
var _squash_y := 0.0
var _sparkle := 0
var _phase_init := false
## DOOA_CAMERA_START_VIEW (with its offset and projection) and DOOA_SAVED_VIEW (the room's).
var _start_view := {}
var _room_view := {}
var _egg: Dictionary = {}
## DOOA_SAVED_ENTITY_VISIBILITY.
var _visibility: Array = []


## DOOA_tick(partner, buffer, 0) (dooa.c:1700): the dissolution object, from frame 0 (natural death:
## the iris) or 0x23 (no life left: MURD drew it, the partner is already off the map); the old map's
## view kept for the camera (D8); the death map chosen.
func start_dissolve() -> void:
	lives = int(game_state.state["partner"]["lives"])
	frame = 0 if lives != 0 else MAP_CHANGE
	if lives == 0:
		partner.visible = false
	sequence = DISSOLVE
	_set_phase(PHASE_IRIS)
	darkness = 0
	jijimon_fade = 255
	wireframe_total = 16
	scale = Vector3i(ONE, ONE, ONE)
	partner_front = false
	shards = DooaShards.new()
	shards_active = false
	_start_view = get_view.call() if get_view.is_valid() else {}
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
## random (rand() % 4), else the one DOO2's panel (builtin 29) chose. The egg's threshold and its
## pieces start at 0 (dooa.c:1771–1775).
func start_rebirth() -> void:
	if int(game_state.state["partner"]["lives"]) == 0:
		egg_slot = Rng.rand() % 4
	sequence = REBIRTH
	_set_phase(PHASE_REBIRTH)
	frame = 0
	fade_level = 0
	egg_threshold = 0
	piece_flags = PackedInt32Array([0, 0, 0, 0, 0, 0])
	pieces.reset()
	_sparkle = 0
	if _egg.is_empty():
		_load_egg()


## One game frame of the active object (the object list), then its effects' objects.
func tick() -> void:
	match sequence:
		DISSOLVE:
			_tick_dissolve()
		REBIRTH:
			_tick_rebirth()
	if shards_active:
		shards.location = _psx(partner.position)
		shards.tick()
	pieces.tick()
	fx.tick()


func _set_phase(value: int) -> void:
	phase = value
	phase_changed.emit(value)


func _play(id: int) -> void:
	if sound != null:
		sound.play_sound(SOUND_BANK, id)


func _stop() -> void:
	if sound != null:
		sound.stop_sound()


static func _psx(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x), roundi(-p.y), roundi(-p.z))


## DIGIMON_DATA[type].height of the partner (D14).
func height() -> int:
	if data == null or game_state == null:
		return 0
	return int(data.digimon(game_state.state["partner"]["digimon"]).get("height", 0))


## DOOA_storeDigimonY.
func _store_y() -> void:
	stored_y = _psx(partner.position).y
	shards.stored_y = stored_y


func _camera(start: Dictionary, s: int, e: int, f: int) -> void:
	if start.is_empty() or not set_view.is_valid():
		return
	var v := CutsceneCamera.view(start, _psx(partner.position), partner.direction, height(), s, e, f)
	if not v.is_empty():
		set_view.call(v)


## DOOA_tickDissolve (dooa.c:310).
func _tick_dissolve() -> void:
	frame += 1
	if partner.animator != null and partner.animator.anim_id == ANIM_FALL \
			and partner.animator.frame >= partner.animator.frame_count:
		partner.start_animation(ANIM_TIRED)
		_store_y()
		_saved_position = partner.position
		_saved_direction = partner.direction
	match phase:
		PHASE_IRIS:
			_check_iris()
			if frame < MAP_CHANGE:
				return
			var old_view: Dictionary = get_view.call() if get_view.is_valid() else {}
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
			partner_front = true
			shards = DooaShards.new()
			shards_active = true
			# DOOA_SAVED_VIEW: the room's view, its start offset fixed per death map; the old view back.
			var room: Dictionary = get_view.call() if get_view.is_valid() else {}
			if not room.is_empty():
				_room_view = room.duplicate()
				_room_view["offset"] = ROOM_OFFSET_LATE if death_map == DEATH_MAP_LATE else ROOM_OFFSET_EARLY
			if not old_view.is_empty() and set_view.is_valid():
				set_view.call(old_view)
			partner.position = _saved_position
			partner.set_direction(_saved_direction)
			if lives != 0:
				partner.start_animation(ANIM_TIRED)
			else:
				partner.start_animation(ANIM_DEAD)
				if partner.animator != null:
					partner.animator.playing = false
			_set_others_visible(false)
			_set_phase(PHASE_TURN)
			if map_layer.is_valid():
				map_layer.call(false)
			_hide_all_but_partner()
			darkness = 0xFF
		PHASE_TURN:
			partner.visible = true
			partner_front = false
			if frame >= 0x56:
				_start_view = _room_view
				_saved_position = partner.position
				_saved_direction = partner.direction
				partner.position = Vector3.ZERO
				partner.look_at_psx(int(tamer.position.x), int(-tamer.position.z))
				_set_phase(PHASE_SHARDS)
				_phase_init = true
				_camera(_start_view, 0, 0x64, 0x63)
			else:
				_camera(_start_view, 0x23, 0x55, frame)
		PHASE_SHARDS:
			if _phase_init:
				# dooa.c:435: the partner at the origin, falling (lives left), its y stored (B4).
				_phase_init = false
				partner.position = Vector3.ZERO
				if lives != 0:
					partner.start_animation(ANIM_FALL)
				_store_y()
			if frame == WAVES_START:
				_play(0)
			if frame == WAVES_END:
				_stop()
			if frame < WAVES_START:
				return
			if frame <= WAVES_END:
				var k := frame - WAVES_START
				wireframe_total = WAVE_SCHEDULE[k]
				if k == 0 or WAVE_SCHEDULE[k - 1] != WAVE_SCHEDULE[k]:
					shards.location = _psx(partner.position)
					wave_spawned.emit(wireframe_total)
			if frame >= 0xBF:
				_squash_y = partner.position.y
				flash_target_y = stored_y - (height() + 100)
				var at := _psx(partner.position)
				_flash_x = at.x
				_flash_z = at.z
				_stop()
				_play(1)
				_set_phase(PHASE_SQUASH)
		PHASE_SQUASH:
			_squash()
			if frame >= 0xD1:
				wire_color_min = WIRE_MIN
				wire_color_max = WIRE_MAX
				wireframe_total = 16
				partner.start_animation(ANIM_GONE)
				partner.visible = false
				if partner.animator != null:
					partner.animator.playing = false
				partner.position.y = _squash_y
				_play(2)
				_set_phase(PHASE_RISE)
		PHASE_RISE:
			_rising_flash()
			if frame >= 0x135:
				shards.flash = not shards.flash
				_play(3)
				_set_phase(PHASE_WAIT)
		PHASE_WAIT:
			if frame >= 0x17B:
				_load_egg()
				_set_phase(PHASE_EGG)
			_camera(_start_view, 0x149, 0x17B, 0x2C4 - frame)
		PHASE_EGG:
			if frame >= 0x185 and frame < 0x1B8:
				var npc := entities.entity(2) if entities != null else null
				if npc != null:
					npc.visible = true
				jijimon_fade = PsxMath.lerp_int(0xFF, 0, 0x185, 0x1B7, frame)
			if frame >= 0x1B7:
				_set_phase(PHASE_END)
		PHASE_END:
			# The map's drawing offset and camera back, the follow on (D13); the object removed.
			if restore_view.is_valid():
				restore_view.call()
			sequence = NONE
			frame = -1
			_stop()


## DOOA_hasIrisClosed(entity, 0, 0x21, frame) (dooa.c:602): the partner moves in front of the iris.
func _check_iris() -> void:
	if not project.is_valid() or not get_view.is_valid() or data == null:
		return
	var at := _psx(partner.position)
	at.y -= height() / 2
	var z := int(project.call(at).get("sz", 0))
	var h := int(get_view.call().get("projection", 0))
	var record: Dictionary = data.digimon(game_state.state["partner"]["digimon"])
	if DeathIrisMath.in_front(DeathIrisMath.radius(0, IRIS_END, frame, true), DeathIrisMath.size(record), h, z):
		partner_front = true


## Phase 0x64 (dooa.c:472–490, C2–C4).
func _squash() -> void:
	var index := PsxMath.lerp_int(0, 0x1F, 0xBF, 0xD0, frame)
	var curve: int = SCALE_CURVE[clampi(index, 0, SCALE_CURVE.size() - 1)]
	var work := PsxMath.div((curve - 100) * 200, 100) + 100
	var sy := PsxMath.div(work << 12, 100)
	var sx := PsxMath.div(PsxMath.div(10000, work) << 12, 100)
	sx = PsxMath.lerp_int(sx, PsxMath.div(sx * 50, 100), 0xBF, 0xD0, frame)
	if curve >= 0x12D:
		var mirrored := 0x12C - (curve - 0x12C)
		sy = PsxMath.div((PsxMath.div((mirrored - 100) * 200, 100) + 100) << 12, 100)
		if partner.animator != null:
			partner.animator.playing = false
		# lerp(y, targetY, f - 1, f, f): the target at once.
		partner.position.y = -flash_target_y
	scale = Vector3i(sx, sy, sx)


## Phase 0x65 (dooa.c:505–529, E1 / E2): a flash a frame, rising from below the floor and wobbling.
func _rising_flash() -> void:
	var at := Vector3i(_flash_x, PsxMath.lerp_int(flash_target_y, 0, 0xD1, 0x135, frame), _flash_z)
	var start := Vector3i(Rng.rand() % 100 + 60, Rng.rand() % 100 + 60, Rng.rand() % 100 + 60)
	last_flash = fx.create_flash(0, at, -1, 8, 0, 0x14, start, Vector3i(0x14, 0x14, 0x14))
	var wobble := PsxMath.div(PsxMath.sin512(PsxMath.lerp_int(0, 0x600, 0xD1, 0x135, frame)) * 10, 4096)
	fx.set_flash_offset(last_flash, wobble, 0)


## The egg's sidecar (G1: loaded at 0x17B).
func _load_egg() -> void:
	if Content.exists(EGG_SIDECAR):
		var json: Variant = Content.load_json(EGG_SIDECAR)
		_egg = json if json is Dictionary else {}


## The egg piece `piece` of the chosen egg (TAMA's object egg_slot × 6 + piece), or {}.
func egg_object(piece: int) -> Dictionary:
	var objects: Array = _egg.get("tmd", {}).get("objects", [])
	var i := egg_slot * EGG_PIECES + piece
	return objects[i] if i < objects.size() else {}


## DOOA_tickRebirth (dooa.c:1020).
func _tick_rebirth() -> void:
	frame += 1
	fade_level = 0
	match phase:
		PHASE_REBIRTH:
			if frame >= 10:
				shards.state = 1
				_stop()
				_play(5)
				_set_phase(PHASE_SHARDS_GATHER)
		PHASE_SHARDS_GATHER:
			if frame >= 50:
				_set_phase(PHASE_SHARDS_HOLD)
		PHASE_SHARDS_HOLD:
			if frame >= 100:
				shards.state = 3
				_set_phase(PHASE_SHARDS_FADE)
		PHASE_SHARDS_FADE:
			egg_threshold = 16 if frame >= 130 else PsxMath.lerp_int(1, 16, 100, 132, frame)
			if frame >= 132:
				# DOOA_removeShardEffect; DOO2_resetShardSets.
				shards.shards.clear()
				shards_active = false
				pieces.reset()
				_play(6)
				_set_phase(PHASE_BABY_LOAD)
		PHASE_BABY_LOAD:
			if frame < 147:
				fade_level = PsxMath.lerp_int(5, 0, 132, 150, frame)
			_rebirth_flash()
			if frame >= 152:
				var key := evolution.reincarnate(egg_slot) if evolution != null else ""
				if key != "":
					partner.load_digimon(data, key)
				if sound != null and key != "":
					sound.load_partner_sounds(data.digimon_sounds(key))
				partner.position = Vector3.ZERO
				partner.set_direction(0)
				partner.start_animation(Partner.ANIM_IDLE)
				# C7: the squash's root scale goes with the old model (port-only reset).
				scale = Vector3i(ONE, ONE, ONE)
				_set_others_visible(true)
				var npc := entities.entity(2) if entities != null else null
				if npc != null:
					npc.visible = true
				tamer.visible = true
				partner.visible = false
				# J4: the tamer's and entities 3 / 4's palettes black.
				tamer_fade = 255
				others_fade = 255
				if map_layer.is_valid():
					map_layer.call(true)
				_set_phase(PHASE_BABY_FADE)
		PHASE_BABY_FADE:
			if frame >= 202:
				darkness = 0
				tamer_fade = 0
				others_fade = 0
				partner.visible = true
				partner.start_animation(ANIM_HATCH)
				_sparkle = 0
				_set_phase(PHASE_SPARKLES)
			elif frame >= 152:
				# J5: the background every frame; the tamer's palette on even frames, 3 / 4's on odd.
				var level := PsxMath.lerp_int(255, 0, 152, 202, frame)
				darkness = level
				if frame & 1 == 0:
					tamer_fade = level
				else:
					others_fade = level
		PHASE_SPARKLES:
			if _sparkle < SPARKLES:
				var piece := int(SPARKLE_BONE_IDS[_sparkle])
				if piece >= 0:
					var object := egg_object(piece)
					if not object.is_empty():
						pieces.build(object)
					piece_flags[piece] = -1
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
				pieces.reset()
				sequence = NONE
				frame = -1


## Phase 0xCE (dooa.c:1083–1098, E4): the big flash at (0, -100, 0) shrinking.
func _rebirth_flash() -> void:
	var size := PsxMath.lerp_int(20, 10, 132, 152, frame)
	var level := PsxMath.lerp_int(120, 10, 132, 152, frame)
	var spread := maxi(level * 50 / 120, 1)
	var start := Vector3i(level + Rng.rand() % spread, level + Rng.rand() % spread, level + Rng.rand() % spread)
	last_flash = fx.create_flash(0, REBIRTH_FLASH, -1, 4, 0, size * 25 * 4096 / 1000, start,
			Vector3i(level / 6, level / 6, level / 6))


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
