class_name ArenaSession
extends RefCounted
## A whole tournament (specs/arena.md §4.3, §5.2): STD_tournamentMain (std_setup.c:521) as phases,
## one original frame per frame(): the opening fade, the bracket intro, then per match the bracket
## (ArenaBracket), the opponent (ArenaTournament.initialize_opponent) and the match (ArenaMatch,
## current_match);
## after three wins the champion's bracket and the champion scene's timeline (STD_tickChampionScene;
## its models are the view's); STD_deinitializeTournament. The world spawns and removes the opponents
## and fades through the callables the arena sets.

signal visual(kind: String, args: Array)

enum Phase { IDLE, FADE_OUT, BRACKET_INTRO, BRACKET, MATCH, CHAMPION_BRACKET, CHAMPION_FADE, CHAMPION_IN,
		CHAMPION, END, DONE }

## STD_tournamentMain (std_setup.c:541-556): fadeToBlack(5), STD_tickFrames(5); fadeFromBlack(5),
## STD_tickFrames(0x78). STD_tickFrames(n) runs n + 1 frames (i <= count, std_main.c:6185).
const OPENING_FADE := 5
const OPENING_FRAMES := 5 + 1
const INTRO_FRAMES := 0x78 + 1
## The matches (std_setup.c:559): up to 3, until one is lost.
const MATCHES := 3
## The champion (std_setup.c:582-606): fadeToBlack(0xA) and 11 frames; 2 frames; fadeFromBlack(0xF)
## and at least 0x10 frames (while MAIN_D_801350F0 > 0, which loadChampionModels zeroes).
const CHAMPION_FADE_OUT := 0xA
const CHAMPION_FADE_FRAMES := 0xB
const CHAMPION_FADE_IN := 0xF
const CHAMPION_IN_FRAMES := 0x10
## STD_deinitializeTournament (std_setup.c:432-460): fadeToBlack(1) and 11 frames.
const END_FADE := 1
const END_FRAMES := 0xB
## loadMapSounds(0x10) (std_setup.c:543, :561, :570): the arena's sound set (the bracket's hops,
## shots and hits are slot 8's sounds 1-5).
const ARENA_SOUNDS := 0x10
## The bracket's music tracks (STD_addBracket(track), STD_addBracketIntro).
const TRACK_INTRO := 0
const TRACK_MATCH := 1
const TRACK_CHAMPION := 2
## STD_tickChampionScene (std_effect.c:1259-1349).
const CHAMPION_STATE0 := 0x61
const CHAMPION_ORBIT := 0x50
const CHAMPION_LAST := 0x15
const CHAMPION_RISE := 0x19
const CHAMPION_ZOOM_FRAMES := 8
const CHAMPION_ZOOM := 0x14
const CHAMPION_CAMERA_TOP := -0x7CF
## STD_initializeChampionScene (std_hud.c:1371): the partner on the podium.
const PODIUM_Y := -0x1E
const PODIUM_FACING := 0x200
## STD_loadChampionModels (std_hud.c:1281-1291): the orbit's 79 angles.
const ORBIT_STEPS := 0x28
const ORBIT_SPAN := 0xA00
const ANIM_IDLE := 0x21
const ANIM_VICTORY := 0x2A

var world: BattleWorld
var effects: EffectHost
var data: Node
var camera: ArenaCamera
var tournament: ArenaTournament
var bracket: ArenaBracket
var current_match: ArenaMatch

## func(slot: int, type: int, stats: Dictionary) -> int (the entity): STD_initializeOpponent's model
## and entity (ENTITY_TABLE[slot + 2]).
var spawn_opponent := Callable()
## func(): removeMapEntities.
var remove_opponents := Callable()
## func(kind: "out" / "in", frames: int): fadeToBlack / fadeFromBlack.
var fader := Callable()

var phase := Phase.IDLE
var cup := 0
var arena := 0
var partner := 1
## STD_setupParticipants' result (ArenaTournament).
var participants := {}
## The matches played (the C's i) and STD_MATCH_RESULT.
var played := 0
var match_result := 0
## The tournament's result: matches won (STD_tournamentMain's return).
var result := 0
var champion_done := false
var champion_state := 0
var champion_timer := 0
var champion_angles: Array[int] = []

var _frames := 0
var _bracket_font := 0x1D


func _init(battle_world: BattleWorld, effect_host: EffectHost, game_data: Node, arena_camera: ArenaCamera) -> void:
	world = battle_world
	effects = effect_host
	data = game_data
	camera = arena_camera
	tournament = ArenaTournament.new(data)
	var recs: Array = data.system("arena") if data != null else []
	if not recs.is_empty():
		_bracket_font = int(recs[0].get("music", {}).get("bracket_font", 0x1D))


func is_done() -> bool:
	return phase == Phase.DONE


func _fade(kind: String, frames: int) -> void:
	if fader.is_valid():
		fader.call(kind, frames)


# --- STD_tournamentMain's head (std_setup.c:521-557) ----------------------------------------------

## `opponents`: the 7 types startTournament drew; `arena_id`: the map's arena_model.
func begin(cup_id: int, opponents: Array, arena_id: int) -> void:
	cup = cup_id
	arena = arena_id
	var list := []
	for o in opponents:
		list.append(tournament.stand_in(int(o)))
	_fade("out", OPENING_FADE)
	world.load_map_sounds(ARENA_SOUNDS)
	world.stop_music()
	world.stop_sounds()
	_frames = 0
	played = 0
	match_result = 0
	result = 0
	champion_done = false
	participants = tournament.setup_participants(world.digimon_type(partner), list)
	bracket = ArenaBracket.new(data, int(participants["player_slot"]), participants["round1"],
			participants["round2"])
	bracket.sound.connect(func(bank: int, id: int) -> void: world.play_sound(bank, id))
	phase = Phase.FADE_OUT


func _begin_intro() -> void:
	# STD_initializeTournament, STD_setVSPhase(0xA), STD_addBracketIntro, fadeFromBlack(5).
	if camera != null:
		camera.initialize_camera()
		camera.set_phase(ArenaCamera.STATE_ROTATING)
	world.set_on_map(partner, false)
	bracket.begin_intro()
	world.stop_music()
	world.stop_sounds()
	world.play_music(_bracket_font, TRACK_INTRO)
	visual.emit("bracket_intro", [true])
	_fade("in", OPENING_FADE)
	_frames = 0
	phase = Phase.BRACKET_INTRO


## STD_addBracket(track).
func _add_bracket(track: int) -> void:
	world.set_on_map(partner, false)
	bracket.begin()
	world.stop_music()
	world.stop_sounds()
	world.play_music(_bracket_font, track)
	visual.emit("bracket", [true])


## STD_removeBracket(mode): the music stops unless it is the champion's (mode 2).
func _remove_bracket(mode: int) -> void:
	world.set_on_map(partner, true)
	visual.emit("bracket", [false])
	if mode != TRACK_CHAMPION:
		world.stop_music()
		world.stop_sounds()


func _start_match() -> void:
	_remove_bracket(TRACK_MATCH)
	var type := int(participants["opponents"][played])
	var stats := tournament.initialize_opponent(type, cup)
	for k in ["is_hit", "efe_sub_effect", "unk1", "vab_id"]:
		if not stats["current"].has(k):
			stats["current"][k] = 0 if k in ["is_hit", "vab_id"] else -1
	if not stats["base"].has("moves_prio"):
		stats["base"]["moves_prio"] = [0, 0, 0, 0]
	var e: int = spawn_opponent.call(played, type, stats) if spawn_opponent.is_valid() else played + 2
	current_match = ArenaMatch.new(world, effects, data, camera)
	current_match.visual.connect(func(kind: String, args: Array) -> void: visual.emit(kind, args))
	current_match.begin(partner, e, arena)
	phase = Phase.MATCH


func _after_match() -> void:
	match_result = current_match.result
	played += 1
	if match_result == 1:
		world.load_map_sounds(ARENA_SOUNDS)
		visual.emit("scene", ["win_off"])
		if camera != null:
			camera.initialize_camera()
			camera.state = ArenaCamera.STATE_ROTATING
	else:
		visual.emit("scene", ["lose_off"])
	if remove_opponents.is_valid():
		remove_opponents.call()
	current_match = null
	if match_result == -1 or played == MATCHES:
		if match_result == 1:
			_load_champion_models()
			_add_bracket(TRACK_CHAMPION)
			phase = Phase.CHAMPION_BRACKET
		else:
			_begin_end()
		return
	_add_bracket(TRACK_MATCH)
	world.load_map_sounds(ARENA_SOUNDS)
	phase = Phase.BRACKET


# --- the champion (std_setup.c:582-606, std_hud.c:1273-1396, std_effect.c:1251-1378) -------------

## STD_loadChampionModels' orbit angles.
func _load_champion_models() -> void:
	champion_angles = []
	for i in range(1, ORBIT_STEPS + 1):
		champion_angles.append(ORBIT_SPAN * (i * i) / (ORBIT_STEPS * ORBIT_STEPS))
	for i in ORBIT_STEPS - 1:
		champion_angles.append(0x1400 - champion_angles[0x26 - i])


## STD_initializeChampionScene: the partner on the podium, the champion camera.
func _initialize_champion_scene() -> void:
	champion_state = 0
	champion_timer = 0
	world.start_animation(partner, ANIM_IDLE)
	world.set_location(partner, Vector3i(0, PODIUM_Y, 0))
	world.set_rotation_y(partner, PODIUM_FACING)
	if camera != null:
		camera.set_champion_camera()
	visual.emit("podium", [true])


## STD_tickChampionScene's timeline (the letters and the podium rising are the view's).
func _tick_champion() -> void:
	match champion_state:
		0:
			champion_timer += 1
			if champion_timer >= CHAMPION_STATE0:
				champion_timer = 0
				champion_state = 1
				world.start_animation(partner, ANIM_IDLE)
		1:
			champion_timer += 1
			var loc := world.location(partner)
			world.set_location(partner, Vector3i(loc.x, loc.y - CHAMPION_RISE, loc.z))
			if champion_timer < CHAMPION_ORBIT:
				if camera != null:
					var rot := Vector3i(0, champion_angles[champion_timer - 1] & 0xFFF, 0)
					camera.ref.y = loc.y - CHAMPION_RISE - world.height(partner) * 2 / 3
					var out := PsxMath.apply_matrix_lv(PsxMath.rot_matrix(rot),
							Vector3i(0, 0, -(world.radius(partner) * 2 + 0x320)))
					camera.eye.x = out.x
					camera.eye.z = out.z
			else:
				world.start_animation(partner, ANIM_VICTORY)
				world.set_step_held(partner, true)
				champion_timer = 0
				champion_state = 2
		2:
			if not world.animation_playing(partner):
				if camera != null and camera.eye.y >= CHAMPION_CAMERA_TOP:
					var ys: Array = _champion_camera_y()
					camera.eye.y = int(ys[mini(champion_timer, ys.size() - 1)]) * 2
				champion_timer += 1
				if champion_timer < CHAMPION_ZOOM_FRAMES and camera != null:
					camera.viewport_distance += CHAMPION_ZOOM
			if champion_timer >= CHAMPION_LAST:
				champion_done = true


func _champion_camera_y() -> Array:
	var recs: Array = data.system("arena") if data != null else []
	return recs[0].get("scenes", {}).get("champion_camera_y", [0]) if not recs.is_empty() else [0]


# --- STD_deinitializeTournament (std_setup.c:432) -------------------------------------------------

func _begin_end() -> void:
	world.stop_music()
	world.stop_sounds()
	visual.emit("arena", [false])
	_fade("out", END_FADE)
	_frames = 0
	phase = Phase.END


func _finish() -> void:
	var loc := world.location(partner)
	world.set_location(partner, Vector3i(loc.x, 0, loc.z))
	result = played if match_result == 1 else played - 1
	phase = Phase.DONE


# --- the frame ------------------------------------------------------------------------------------

## The arena's objects of a frame outside a match: the camera (STD_tickVSPhase).
func _objects() -> void:
	if camera != null:
		camera.tick()
		camera.tick_objects()


## One original frame; `pressed` = the newly pressed buttons.
func frame(pressed: int) -> void:
	for _guard in 4:
		if _step(pressed):
			return


func _step(pressed: int) -> bool:
	match phase:
		Phase.FADE_OUT:
			if _frames >= OPENING_FRAMES:
				_begin_intro()
				return false
			_objects()
			_frames += 1
			return true
		Phase.BRACKET_INTRO:
			if _frames >= INTRO_FRAMES:
				visual.emit("bracket_intro", [false])
				_add_bracket(TRACK_MATCH)
				world.load_map_sounds(ARENA_SOUNDS)
				phase = Phase.BRACKET
				return false
			bracket.intro_frame()
			_objects()
			_frames += 1
			return true
		Phase.BRACKET, Phase.CHAMPION_BRACKET:
			if bracket.finished:
				if phase == Phase.BRACKET:
					_start_match()
				else:
					_fade("out", CHAMPION_FADE_OUT)
					_frames = 0
					phase = Phase.CHAMPION_FADE
				return false
			bracket.frame(match_result)
			_objects()
			return true
		Phase.MATCH:
			if current_match.is_done():
				_after_match()
				return false
			current_match.frame(pressed)
			return true
		Phase.CHAMPION_FADE:
			if _frames >= CHAMPION_FADE_FRAMES:
				_remove_bracket(TRACK_CHAMPION)
				_initialize_champion_scene()
				_frames = 0
				phase = Phase.CHAMPION_IN
				return false
			bracket.frame(match_result)
			_objects()
			_frames += 1
			return true
		Phase.CHAMPION_IN:
			# Two frames, fadeFromBlack(0xF), then at least 0x10 frames.
			if _frames == 2:
				_fade("in", CHAMPION_FADE_IN)
			if _frames >= 2 + CHAMPION_IN_FRAMES:
				visual.emit("champion", [true])
				champion_done = false
				phase = Phase.CHAMPION
				return false
			_objects()
			_frames += 1
			return true
		Phase.CHAMPION:
			if champion_done:
				visual.emit("podium", [false])
				visual.emit("champion", [false])
				champion_done = true
				_begin_end()
				return false
			_tick_champion()
			_objects()
			return true
		Phase.END:
			if _frames >= END_FRAMES:
				_finish()
				return true
			_objects()
			_frames += 1
			return true
	return true
