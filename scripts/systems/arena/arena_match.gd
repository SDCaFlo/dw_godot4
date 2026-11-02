class_name ArenaMatch
extends RefCounted
## One arena match (specs/arena.md §4.4, §5.2): STD_runMatch -> STD_runIntro, STD_combatMain
## (STD_initializeCombat, STD_combatSetup, the fight loop, STD_checkEndCondition,
## STD_tickBattleResultScreen, STD_deinitializeCombat). The C's blocking loops are phases; frame()
## runs one original frame (a loop that ends without a frame moves on in the same call). The
## fighters' animations advance in the world after each frame, as in the battles.
## Visual events (for the views of steps 5-6) go out through `visual(kind, args)`.

signal visual(kind: String, args: Array)

enum Phase { IDLE, INTRO_PARTNER, INTRO_OPPONENT, SETUP_TEXT, SETUP_BURST, FIGHT, RESULT_SCREEN, VERSUS,
		VICTORY, END, DONE }

## STD_runIntro (std_main.c:1885): the walk-in distance, arena 1 / the others.
const INTRO_WALK := [0x7D0, 0x514]
## STD_placePlayer1 / 2 (1568-1607): the start x, arena 1 / the others, and the facings.
const START_X := [0x9C4, 0x708]
const PARTNER_FACING := 0x400
const OPPONENT_FACING := 0xC00
## STD_addFighterCounter(0x63) (std_main.c:4138); STD_tickFighterCounter: -1 every 20 frames (2920).
const TIMER_START := 0x63
const TIMER_STEP := 20
## STD_combatSetup (3939-4035): the start text's 60 frames and the orbit's distance ramp.
const SETUP_FRAMES := 60
const RAMP_NEAR := 200
const RAMP_FAR := 4200
const RAMP_STEP := 400
const RAMP_REST := 1000
## STD_tickBattleResultScreen (4641-4695).
const RESULT_WINDOW := 0x3C
const RESULT_PRESS := 0x3D
const RESULT_END := 0x79
## STD_isVersusModelSceneFinished (std_hud.c:1213).
const VERSUS_FRAMES := 0x51
## STD_deinitializeCombat (4524-4592): the winner's pose, the wait, the heal.
const VICTORY_WON := 0x64
const VICTORY_LOST := 0x78
const END_FRAMES := 0x14
const HEAL_DIV := 5
## STD_addIntroText / STD_tickIntroName / STD_renderIntroName (1625-2160).
const INTRO_NAME_X := 16
const INTRO_NAME_Y := 68
const INTRO_NAME_TOP := -71
const INTRO_NAME_STEP := 28
## STD_addIntroText: the colour by special[0] (STD_INTRO_NAME_COLORS index).
const INTRO_COLORS := [3, 1, 6, 2, 4, 0, 5]
## STD_addIntroStats / STD_tickIntroStats (1700-2005): the counters' start and steps.
const STATS_START := [-100, -100, -10, -10, -10, -10]
const STATS_STEP := [200, 200, 20, 20, 20, 20]
## STD_startWalkingAnimation2 (5652): weak below 1/5 HP or poisoned.
const ANIM_IDLE := 0x21
const ANIM_IDLE_WEAK := 0x22
const ANIM_WALK_WEAK := 0x23
const ANIM_VICTORY := 0x2A
const ANIM_FAINT := 0x2B
## The battle's GAME_STATE: 5 the arena set up / ending, 4 fighting (commands accepted).
const GAME_ARENA := 5
const GAME_FIGHT := 4

var world: BattleWorld
var effects: EffectHost
var data: Node
var camera: ArenaCamera
var battle: ArenaBattle
var start_text: BattleStartText

var phase := Phase.IDLE
var partner := 1
var opponent := -1
var arena := 0
var music := 0x1E
## 1 won, -1 lost (a draw counts as lost).
var result := 0
## STD_TIMER, STD_TIMER_ACTIVE, STD_IS_TIMER_INITIALIZED.
var timer := 0
var timer_active := false
var timer_shown := false
## STD_DAMAGE[2], STD_STARTING_HP[2], STD_IS_DRAW, STD_VICTORY_FRAMES.
var damage: Array[int] = [0, 0]
var starting_hp: Array[int] = [0, 0]
var is_draw := false
var victory_frames := 0
## The intro name (STD_INTRO_DATA_*) and stats (STD_INTRO_STATS_*).
var intro_name := {}
var intro_stats_active := false
var intro_stats: Array[int] = [0, 0, 0, 0, 0, 0]
var intro_stats_entity := -1
## The command menu (STD_COMMAND_MENU_TIMER / _BLINK).
var menu_active := false
var menu_timer := 0
var menu_blink := 0
## Status bars shown (STD_addFighterStatusBars): they apply the damage buffers.
var bars_active := false

var _pressed := 0
var _frames := 0
var _setup_finished := false
var _end_result := 0
var _result_screen: Array = []
var _result_timer := 0
var _result_step := 0
var _versus_timer := -1
var _deinit := [0, 0]
var _effect_slots: Array = []


func _init(battle_world: BattleWorld, effect_host: EffectHost, game_data: Node, arena_camera: ArenaCamera) -> void:
	world = battle_world
	effects = effect_host
	data = game_data
	camera = arena_camera
	battle = ArenaBattle.new(world, effects, data)
	battle.camera = camera
	battle.visual.connect(func(kind: String, args: Array) -> void: visual.emit(kind, args))
	if camera != null:
		camera.scene_requested.connect(func(kind: String) -> void: visual.emit("scene", [kind]))
	start_text = BattleStartText.new(data)


func is_done() -> bool:
	return phase == Phase.DONE


func _arena_table() -> Dictionary:
	var recs: Array = data.system("arena") if data != null else []
	return recs[0] if not recs.is_empty() else {}


# --- STD_runMatch / STD_runIntro (std_setup.c:401, std_main.c:1885) -------------------------------

## STD_runMatch: the intro, then the fight. `arena_id` 0 or 1 (the map's arena_model).
func begin(partner_entity: int, opponent_entity: int, arena_id: int) -> void:
	partner = partner_entity
	opponent = opponent_entity
	arena = arena_id
	var fonts: Array = _arena_table().get("music", {}).get("arena_fonts", [0x1E, 0x20])
	music = int(fonts[arena])
	if camera != null:
		camera.partner = partner
		camera.opponent = opponent
	battle.game_state = GAME_ARENA
	world.stats(opponent)["current"]["vab_id"] = 5
	world.load_digimon_sounds(5, world.digimon_type(opponent))
	_place(partner, START_X[arena], PARTNER_FACING)
	_place(opponent, -START_X[arena], OPPONENT_FACING)
	visual.emit("stat_labels", [])
	if camera != null:
		camera.start_camera_chase(partner, INTRO_WALK[arena], 0)
	add_intro_text(partner)
	world.stop_music()
	world.stop_sounds()
	world.play_music(music, 0)
	phase = Phase.INTRO_PARTNER


## STD_placePlayer1 / STD_placePlayer2.
func _place(e: int, x: int, facing: int) -> void:
	world.set_location(e, Vector3i(x, 0, 0))
	world.set_rotation_y(e, facing)
	world.start_animation(e, ANIM_IDLE)


## STD_setPostIntroPosition (1682): ✕ jumps to the walk's end.
func set_post_intro_position(e: int) -> void:
	if camera == null or camera.chase_timer == -1:
		return
	world.set_location(e, camera.chase_target)
	world.start_animation(e, ANIM_IDLE)
	camera.end_chase()


func _end_intro(e: int) -> void:
	remove_intro_text()
	intro_stats_active = false
	if camera != null:
		camera.remove_chase()
	world.stop_music()
	world.stop_sounds()
	if e == partner:
		world.load_battle_sounds()
		if camera != null:
			camera.start_camera_chase(opponent, -INTRO_WALK[arena], 1)
		add_intro_text(opponent)
		world.play_music(music, 1)
		phase = Phase.INTRO_OPPONENT
	else:
		if camera != null:
			camera.state = ArenaCamera.STATE_ORBIT
		_combat_main()


## STD_addIntroText (1625): the big name (the US release draws nothing, spec §8.1; its timing stays).
func add_intro_text(e: int) -> void:
	var d: Dictionary = data.digimon(world.digimon_type(e)) if data != null else {}
	var special: Array = d.get("c", {}).get("special", [5])
	var s := int(special[0]) if not special.is_empty() else 5
	var length := int(d.get("arena_name", {}).get("length", 0))
	intro_name = {"entity": e, "frame_count": 4, "rendered": 0, "anim_frame": 0, "length": length,
			"x": -length * INTRO_NAME_X, "y": INTRO_NAME_Y,
			"color": INTRO_COLORS[s] if s >= 0 and s < INTRO_COLORS.size() else 0}
	visual.emit("intro_name", [e, true])


func remove_intro_text() -> void:
	if not intro_name.is_empty():
		visual.emit("intro_name", [intro_name["entity"], false])
	intro_name = {}


## STD_tickIntroName (2063) then STD_renderIntroName's counting (2087).
func _tick_intro_name() -> void:
	if intro_name.is_empty():
		return
	var n := intro_name
	n["frame_count"] += 1
	if n["length"] == n["rendered"] and n["anim_frame"] == 3:
		if camera != null and camera.chase_timer == 0:
			world.start_animation(n["entity"], ANIM_WALK_WEAK)
			camera.chase_timer = ArenaCamera.CHASE_START
		if n["y"] >= INTRO_NAME_TOP:
			n["y"] -= INTRO_NAME_STEP
		else:
			add_intro_stats(n["entity"])
	if n["frame_count"] % 4 == 0:
		if n["rendered"] < n["length"]:
			n["rendered"] += 1
			n["anim_frame"] = 0
	elif n["anim_frame"] != 3:
		n["anim_frame"] += 1


## STD_addIntroStats (1700).
func add_intro_stats(e: int) -> void:
	if intro_stats_active:
		return
	intro_stats_active = true
	intro_stats_entity = e
	intro_stats.assign(STATS_START)
	visual.emit("intro_stats", [e, true])


## STD_tickIntroStats (1969) and STD_renderIntroStats's sound (2009).
func _tick_intro_stats() -> void:
	if not intro_stats_active:
		return
	var s := world.stats(intro_stats_entity)
	var target := [int(s["current"]["hp"]), int(s["current"]["mp"]), int(s["base"]["offense"]),
			int(s["base"]["defense"]), int(s["base"]["speed"]), int(s["base"]["brains"])]
	var counting := false
	for i in 6:
		intro_stats[i] = mini(intro_stats[i] + STATS_STEP[i], target[i])
		if intro_stats[i] != target[i]:
			counting = true
	if counting:
		world.play_sound(0, 0x16)


# --- STD_combatMain (std_main.c:5582) -------------------------------------------------------------

func _combat_main() -> void:
	world.stop_music()
	world.play_music(music, 2)
	begin_fight(partner, opponent)
	_combat_setup()


## STD_initializeCombat (std_main.c:4124): the battle's set-up, the timer, the HUD.
func begin_fight(partner_entity: int, opponent_entity: int) -> void:
	partner = partner_entity
	opponent = opponent_entity
	if camera != null:
		camera.partner = partner
		camera.opponent = opponent
	damage = [0, 0]
	is_draw = false
	if not timer_shown:
		timer = TIMER_START
		timer_shown = true
		visual.emit("timer", [true])
	victory_frames = 0
	if world.digimon_type(partner) == world.digimon_type(opponent):
		visual.emit("player_marker", [true])
	timer_active = false
	battle.initialize_combat([partner, opponent])
	for i in 2:
		starting_hp[i] = battle.fighters[i].hp()
	bars_active = true
	visual.emit("status_bars", [true])
	menu_active = true
	menu_timer = 0
	menu_blink = 0
	visual.emit("command_menu", [true])


## STD_combatSetup (std_main.c:3939): the poses, the techniques' effects, the start text.
func _combat_setup() -> void:
	battle.game_state = GAME_ARENA
	var p := battle.fighters[0]
	world.start_animation(partner, ANIM_IDLE_WEAK if (p.flags & BattleFighter.POISONED) or p.hp() <= p.max_hp() / 5 else ANIM_IDLE)
	world.look_at_location(partner, world.location(opponent))
	world.start_animation(opponent, ANIM_IDLE)
	world.look_at_location(opponent, world.location(partner))
	_load_effects()
	if camera != null:
		camera.min_distance = RAMP_NEAR
	start_text.start()
	_frames = 0
	_setup_finished = false
	world.play_sound(0, 0x10)
	phase = Phase.SETUP_TEXT


## STD_loadMoveEFE for the four slots of both fighters (as BattleSession._finish_loading).
func _load_effects() -> void:
	var entries := []
	var keys := []
	for i in 2:
		var e := battle.fighters[i].entity
		var s := world.stats(e)
		s["current"]["unk1"] = -1
		s["current"]["efe_sub_effect"] = -1
		for j in 4:
			var anim := battle.anim_of_move(s["base"]["moves"][j], e)
			if anim == 0xFF:
				continue
			entries.append({"technique": battle.technique_of(e, anim), "caster": i})
			keys.append([i, j])
	var slots: Array = effects.load_moves(entries) if effects != null else []
	_effect_slots = [[-1, -1, -1, -1], [-1, -1, -1, -1]]
	for k in keys.size():
		_effect_slots[keys[k][0]][keys[k][1]] = slots[k] if k < slots.size() else -1


func _end_setup() -> void:
	for i in 2:
		battle.fighters[i].effect_slot.assign(_effect_slots[i])
	if camera != null:
		camera.min_distance = RAMP_REST
		camera.state = ArenaCamera.STATE_ORBIT
	timer_active = true
	battle.game_state = GAME_FIGHT
	phase = Phase.FIGHT


## STD_checkEndCondition (std_main.c:4038): 0 go on, 1 won, -1 lost, 2 both down / a draw. A
## time-out queues STD_tickBattleResultScreen (the C runs it inside, before returning).
func check_end_condition() -> int:
	var p := battle.fighters[0]
	var o := battle.fighters[1]
	if p.hp_damage != 0 or o.hp_damage != 0:
		return 0
	if _fainted(partner):
		if not battle._all_enemies_dead():
			return -1
		return 2 if _fainted(opponent) else 0
	if _fainted(opponent):
		if p.hp() - p.hp_damage > 0:
			return 1
		return 2 if _fainted(partner) else 0
	if timer == 0:
		if p.hp() - p.hp_damage <= 0:
			return 0
		if battle._all_enemies_dead():
			return 0
		damage[0] = starting_hp[0] - p.hp()
		damage[1] = starting_hp[1] - o.hp()
		p.hp_damage = 0
		o.hp_damage = 0
		if damage[0] > damage[1]:
			_result_screen = [1, 0]
			return -1
		if damage[0] < damage[1]:
			_result_screen = [0, 1]
			return 1
		_result_screen = [1, 1]
		return 2
	return 0


func _fainted(e: int) -> bool:
	return world.animation_id(e) == ANIM_FAINT and not world.animation_playing(e)


## STD_tickFighterCounter (std_main.c:2920).
func tick_fighter_counter() -> void:
	if not timer_active:
		return
	battle.frame_count += 1
	if world.animation_id(partner) != ANIM_FAINT and world.animation_id(opponent) != ANIM_FAINT:
		if battle.frame_count % TIMER_STEP == 0 and timer != 0:
			timer -= 1


## STD_handleCommands (std_hud.c:504): ← / → move (wrapping 1 .. n - 1), ✕ gives the command, R1...
## the finisher once its gauge is full (0x80 is Square in libetc's bits).
func handle_commands(pressed: int) -> void:
	var n := battle.available_commands.size()
	if pressed & Pad.LEFT:
		world.play_sound(0, 2)
		battle.hovered_command += 1
		if battle.hovered_command > n - 1:
			battle.hovered_command = 1
	if pressed & Pad.RIGHT:
		world.play_sound(0, 2)
		battle.hovered_command -= 1
		if battle.hovered_command <= 0:
			battle.hovered_command = n - 1
	if pressed & Pad.CONFIRM:
		world.play_sound(0, 3)
		battle.buffered_command = battle.available_commands[battle.hovered_command]
		battle.command_delay = 0
	if pressed & Pad.SQUARE:
		var f := battle.fighters[0]
		if f.finisher_progress == f.finisher_goal:
			battle.buffered_command = Battle.CMD_FINISHER
			world.play_sound(0, 3)
			battle.command_delay = 0
			battle.current_command = Battle.CMD_FINISHER


## STD_tickTamerTournament (std_hud.c:540): Select toggles the bars; commands while fighting.
func _tamer_tick() -> void:
	if _pressed & Pad.SELECT:
		battle.toggle_lifebar = not battle.toggle_lifebar
	if battle.game_state == GAME_FIGHT:
		handle_commands(_pressed)


## STD_tickCommandMenu (std_main.c:7540).
func _tick_command_menu() -> void:
	if not menu_active:
		return
	menu_timer += 1
	if battle.game_state == GAME_FIGHT and menu_timer % 8 == 0:
		menu_blink = (menu_blink + 1) & 1


## STD_battleTickFrame: the objects' ticks, then their draws that change state.
func _objects() -> void:
	_tamer_tick()
	if camera != null:
		camera.tick()
		camera.tick_objects()
	_tick_intro_name()
	_tick_intro_stats()
	tick_fighter_counter()
	_tick_command_menu()
	if effects != null:
		effects.tick()
	battle.tick_finisher_chargeup()
	if phase == Phase.SETUP_TEXT:
		start_text.tick_assemble()
	elif phase == Phase.SETUP_BURST:
		start_text.tick_burst()
	if _versus_timer >= 0:
		_versus_timer += 1
	if bars_active:
		battle.apply_damage_buffers()
	if effects != null:
		effects.draw()


# --- the frame ------------------------------------------------------------------------------------

## One original frame; `pressed` = the newly pressed buttons.
func frame(pressed: int) -> void:
	_pressed = pressed
	battle.pad_pressed = pressed
	for _guard in 4:
		if _step():
			return


## One phase's frame; false when the phase ended without a frame (the next one runs now).
func _step() -> bool:
	match phase:
		Phase.INTRO_PARTNER, Phase.INTRO_OPPONENT:
			var e := partner if phase == Phase.INTRO_PARTNER else opponent
			if not world.animation_playing(e):
				_end_intro(e)
				return false
			_objects()
			if _pressed & Pad.CONFIRM:
				set_post_intro_position(e)
				_end_intro(e)
			return true
		Phase.SETUP_TEXT:
			if not (_frames < SETUP_FRAMES or not _setup_finished):
				start_text.start_burst()
				world.play_sound(0, 0x11)
				phase = Phase.SETUP_BURST
				return false
			if camera != null and camera.min_distance < RAMP_FAR:
				camera.min_distance += RAMP_STEP
			_frames += 1
			_setup_finished = start_text.finished
			_objects()
			return true
		Phase.SETUP_BURST:
			if start_text.finished:
				_end_setup()
				return false
			if camera != null and camera.min_distance > RAMP_REST:
				camera.min_distance -= RAMP_STEP
			_objects()
			return true
		Phase.FIGHT:
			var r := check_end_condition()
			if r != 0:
				_end_result = r
				if not _result_screen.is_empty():
					_begin_result_screen()
				else:
					_begin_deinit()
				return false
			battle.tick_partner_ai()
			battle.tick_enemy_ai()
			battle.tick_fighter_states()
			_objects()
			return true
		Phase.RESULT_SCREEN:
			return _frame_result_screen()
		Phase.VERSUS:
			if _versus_timer >= VERSUS_FRAMES:
				_versus_timer = -1
				visual.emit("versus", [false])
				if _result_step == 3:
					_result_step = 0
					_begin_deinit()
				else:
					_after_versus()
				return false
			_objects()
			return true
		Phase.VICTORY:
			if _frames >= victory_frames:
				_frames = 0
				battle.game_state = GAME_ARENA
				phase = Phase.END
				return false
			_objects()
			var w := battle.fighters[_deinit[0]].entity
			if not world.animation_playing(w):
				world.start_animation(w, ANIM_VICTORY)
			_frames += 1
			return true
		Phase.END:
			if _frames >= END_FRAMES:
				_finish_deinit()
				return true
			_objects()
			_frames += 1
			return true
	return true


# --- STD_tickBattleResultScreen (std_main.c:4641) -------------------------------------------------

func _begin_result_screen() -> void:
	_result_timer = 0
	visual.emit("timeout_text", [true])
	world.stop_music()
	var lost := _result_screen
	var p := battle.fighters[0]
	var o := battle.fighters[1]
	if lost[0] == lost[1]:
		is_draw = true
		battle.battle_idle(p)
		battle.battle_idle(o)
		_result_step = 0
	else:
		battle.battle_idle(battle.fighters[lost[0]])
		var loser: BattleFighter = battle.fighters[lost[1]]
		battle.faint(loser, lost[1])
		_result_step = 10
	phase = Phase.RESULT_SCREEN


func _frame_result_screen() -> bool:
	if _result_step < 10:
		# The draw: two frames, the window, up to 0x3D frames (✕ ends it), then the versus scene.
		if _result_step < 2:
			_objects()
			_result_step += 1
			if _result_step == 2:
				visual.emit("timeout_window", [true])
			return true
		if _result_timer < RESULT_PRESS and not (_pressed & Pad.CONFIRM):
			_objects()
			_result_timer += 1
			return true
		visual.emit("timeout_window", [false])
		_result_step = 3
		_start_versus()
		return false
	if _result_timer < RESULT_END:
		if _result_timer >= RESULT_PRESS and _pressed & Pad.CONFIRM:
			_end_result_screen()
			return false
		if _result_timer == RESULT_WINDOW:
			visual.emit("timeout_window", [true])
		_objects()
		_result_timer += 1
		return true
	_end_result_screen()
	return false


func _end_result_screen() -> void:
	var lost := _result_screen
	var winner: BattleFighter = battle.fighters[lost[0]]
	var loser: BattleFighter = battle.fighters[lost[1]]
	if camera != null:
		camera.select_random_camera(loser.entity, ArenaBattle.CAMERA_END, 0)
	world.look_at_location(winner.entity, world.location(loser.entity))
	visual.emit("timeout_window", [false])
	_result_screen = []
	_begin_deinit()


func _start_versus() -> void:
	_versus_timer = 0
	visual.emit("versus", [true])
	phase = Phase.VERSUS


# --- STD_deinitializeCombat (std_main.c:4524) -----------------------------------------------------

func _begin_deinit() -> void:
	var a := 1
	var b := 0
	match _end_result:
		1:
			a = 0
			b = 1
		2:
			a = 1
			b = 1
	_deinit = [a, b]
	_deinit_start()
	if a == b:
		if timer != 0 or not is_draw:
			_start_versus()
			return
	_after_versus()


func _after_versus() -> void:
	var a: int = _deinit[0]
	var b: int = _deinit[1]
	_frames = 0
	if a != b:
		victory_frames = VICTORY_WON if a == 0 else VICTORY_LOST
		world.start_animation(battle.fighters[a].entity, ANIM_VICTORY)
		world.stop_music()
		world.stop_sounds()
		world.play_music(music, 3 if a == 0 else 4)
		phase = Phase.VICTORY
	else:
		phase = Phase.END


## STD_deinitializeCombat's head: the charge mode back, the combat objects and statuses off.
func _deinit_start() -> void:
	battle.fighters[0].set_charge_mode(battle.saved_charge_mode)
	battle.game_state = GAME_ARENA
	if battle.fighters.size() >= 2 and world.digimon_type(partner) == world.digimon_type(opponent):
		visual.emit("player_marker", [false])
	for i in battle.fighters.size():
		battle.remove_move_effect(battle.fighters[i])
	for i in battle.fighters.size():
		var f := battle.fighters[i]
		visual.emit("entity_text", [i, false])
		battle.reset_flatten(i)
		battle.remove_status_effects(f)
		f.flags = 0


## STD_deinitializeCombat's tail: the HUD off, the partner's stats back and the 1/5 heal.
func _deinit_end() -> int:
	bars_active = false
	visual.emit("status_bars", [false])
	menu_active = false
	visual.emit("command_menu", [false])
	if timer_shown:
		timer_shown = false
		visual.emit("timer", [false])
	world.stop_music()
	world.stop_sounds()
	var p := battle.fighters[0]
	var b := p.base()
	var init: Array = battle.initial_stats[0]
	b["offense"] = int(init[2])
	b["defense"] = int(init[3])
	b["speed"] = int(init[4])
	b["brains"] = int(init[5])
	p.set_hp(mini(p.hp() + p.max_hp() / HEAL_DIV, p.max_hp()))
	p.set_mp(mini(p.mp() + p.max_mp() / HEAL_DIV, p.max_mp()))
	return 1 if _deinit[0] == 0 else -1


## The whole of STD_deinitializeCombat's bookkeeping at once (no frames): the tests' entry.
func deinitialize(a: int, b: int) -> int:
	_deinit = [a, b]
	_deinit_start()
	return _deinit_end()


func _finish_deinit() -> void:
	result = _deinit_end()
	# STD_runMatch's tail (std_setup.c:410-411).
	if camera != null:
		camera.remove_camera_intro()
		camera.state = ArenaCamera.STATE_ROTATING
	phase = Phase.DONE
