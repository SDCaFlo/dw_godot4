extends SceneTree
## Death, lives and reincarnation (specs/death_reincarnation.md): the MURD and DOOA timelines, the
## tamer's states 17 / 19 and the partner's 8 / 14, reincarnatePartner, builtins 29 and 47, section
## 0x4DE and the death evolutions of script 212:
##   godot --headless --path . -s res://tests/test_death_reincarnation.gd
## Exits 1 if a check fails.

## The Sound node's calls (play_sound, stop_sound, the sound sets), for the checks.
class FakeMusic extends RefCounted:
	var stopped := 0

	func stop_bgm() -> void:
		stopped += 1


class FakeSound extends Node:
	var played: Array = []
	var stops := 0
	var map_sets: Array = []
	var partner_sets := 0
	var music := FakeMusic.new()

	func play_sound(slot: int, value: int) -> int:
		played.append([slot, value])
		return 0

	func stop_sound() -> void:
		stops += 1

	func load_map_sounds(set_id: int) -> void:
		map_sets.append(set_id)

	func load_partner_sounds(_sounds: Dictionary) -> void:
		partner_sets += 1


var _failed := 0
var _checks := 0
var _started := false

var data: Node
var gs: Node
var interp: ScriptInterpreter
var ctx: ScriptContext
var tb: TextBoxes
var boxes: UIBoxes
var area: TextArea
var pad: Pad
var files: ScriptFiles
var routines: ScriptRoutines
var death: DeathRoutines
var care: Care
var evo: Evolution
var sound: FakeSound
var tamer: Tamer
var partner: Partner
var murd: MurdScene
var dooa: DooaScene
## The changeMap calls of the scenes: [map, exit].
var map_changes: Array = []
var map_layer: Array = []


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true

	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("scripts/MAPHEAD/script.json"):
		print("SKIP: porter output missing")
		quit(0)
		return false
	PsxMath.setup(data)
	Rng.set_seed(7)

	_setup()
	_test_reincarnation()
	_test_move_unlearning()
	_test_section_0x4de_dispatch()
	_test_death_evolutions()
	_test_evolution_routines()
	_test_murd_box()
	_test_egg_select()
	_test_murd_lives_left()
	_test_murd_no_life_left()
	_test_natural_death()
	_test_rebirth()
	_test_care_script_paused()

	var summary := "%s: death & reincarnation checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks]
	push_warning(summary)
	print(summary)
	quit(1 if _failed else 0)
	return false


func _setup() -> void:
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()

	boxes = UIBoxes.new()
	area = TextArea.new(data, "en_us")
	pad = Pad.new()
	ctx = ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	tb = TextBoxes.new(boxes, area, ctx, pad, data, gs)
	files = ScriptFiles.new()
	sound = FakeSound.new()

	routines = ScriptRoutines.new()
	death = DeathRoutines.new()
	routines.add_child(death)
	routines.configure(ctx, tb, gs, data)
	death._sound = sound

	interp = ScriptInterpreter.new(ctx, files, tb)
	interp.game_state = gs
	interp.data = data
	interp.routines = routines

	care = Care.new()
	care.game_state = gs
	care.data = data
	evo = Evolution.new()
	evo.game_state = gs
	evo.data = data
	evo.care = care
	care.evolution = evo

	tamer = Tamer.new()
	partner = Partner.new()
	partner.tamer = tamer
	partner.game_state = gs
	partner.data = data
	partner.script_ctx = ctx
	partner.sound = sound
	partner.care = care
	murd = MurdScene.new()
	dooa = DooaScene.new()
	for scene: Node in [murd, dooa]:
		scene.set("partner", partner)
		scene.set("tamer", tamer)
		scene.set("game_state", gs)
		scene.set("sound", sound)
		scene.set("change_map", func(map: int, exit: int) -> void: map_changes.append([map, exit]))
		scene.set("map_layer", func(on: bool) -> void: map_layer.append(on))
	murd.boxes = boxes
	murd.dooa = dooa
	dooa.evolution = evo
	dooa.data = data
	tamer.murd = murd
	tamer.dooa = dooa
	tamer.script_ctx = ctx
	partner.dooa = dooa
	death.dooa = dooa


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL: %s" % msg)


func _eq(got: Variant, want: Variant, msg: String) -> void:
	_check(got == want, "%s (got %s, want %s)" % [msg, got, want])


## The UI boxes stepped `frames` times (their opening and closing frames).
func _close_boxes(frames := 30) -> void:
	for i in frames:
		boxes.step()


# --- reincarnatePartner (evolution.c:1054), setReincarnateStats (partner_impl.c:810) -----------

func _test_reincarnation() -> void:
	var eggs := evo.reincarnation_eggs()
	_eq(eggs.size(), 4, "4 reincarnation eggs (systems/babies)")
	_eq(eggs.map(func(e): return int(e["digimon"]["id"])), [1, 15, 29, 43], "eggs give Botamon, Punimon, Poyomon, Yuramon")
	_eq(eggs[0].get("base_stats", {}).get("max_hp"), 90.0, "the eggs carry setReincarnateStats' values")

	# Natural death at tamer level 10: 10 % of the dead partner's base stats.
	gs.new_game("dw1:agumon")
	gs.state["tamer"]["level"] = 10
	var base: Dictionary = gs.state["partner"]["stats"]["base"]
	base.merge({"max_hp": 500, "max_mp": 800, "offense": 150, "defense": 120, "speed": 100, "brains": 90}, true)
	base["moves"] = ["dw1:spit_fire", "dw1:heat_laser", null, "dw1:pepper_breath"]
	var c: Dictionary = gs.state["partner"]["care"]
	c.merge({"age": 15, "remaining_lifetime": 0, "care_mistakes": 5, "evo_timer": 30, "happiness": 90}, true)
	gs.state["partner"]["lives"] = 1
	var raised: int = gs.state["tamer"]["raised_count"]
	care.is_natural_death = true
	care.evolution_target = 12
	care.has_immortal_hour = true
	var key := evo.reincarnate(0)
	_eq(key, "dw1:botamon", "egg 0: Botamon")
	_eq([base["max_hp"], base["max_mp"], base["offense"], base["defense"], base["speed"], base["brains"]],
			[140, 190, 25, 23, 19, 19], "natural death, level 10: the egg's stats + 10 %")
	var current: Dictionary = gs.state["partner"]["stats"]["current"]
	_eq([current["hp"], current["mp"]], [140, 190], "HP / MP full")
	_eq(care.is_natural_death, false, "IS_NATURAL_DEATH cleared (partner_impl.c:844)")
	var slot0: String = data.key_of("moves/move_data", int(data.digimon(1)["moves"][0]["move"]["id"]))
	_eq(base["moves"], [slot0, null, null, null], "techniques: slot 0 = the baby's technique slot 0 (0x2E), the rest empty")
	_eq([gs.state["partner"]["lives"], c["remaining_lifetime"], c["age"], c["evo_timer"], c["care_mistakes"]],
			[3, 360, 0, 0, 0], "3 lives, 360 hours, age / evo timer / care mistakes 0")
	_eq([c["happiness"], c["discipline"]], [50, 50], "happiness and discipline 50")
	_eq([care.evolution_target, care.has_immortal_hour, care.immortal_hour], [-1, false, -1],
			"EVOLUTION_TARGET -1, no immortal hour")
	_eq(c["weight"], int(data.raise_data(1).get("default_weight", 0)), "the baby's default weight")
	_eq(gs.state["tamer"]["raised_count"], raised + 1, "raised count + 1")
	_check(gs.is_raised("dw1:botamon"), "Botamon marked raised")

	# No life left (IS_NATURAL_DEATH 0): nothing inherited.
	base["max_hp"] = 1000
	base["offense"] = 500
	evo.reincarnate(1)
	_eq([gs.state["partner"]["digimon"], base["max_hp"], base["offense"]], ["dw1:punimon", 120, 16],
			"egg 1 after the last life: Punimon, no inheritance")
	_eq(evo.reincarnate(4), "", "an egg slot out of range: nothing")


# --- builtin 47: lostAllLives (script_common.c:2456) -------------------------------------------

func _learn_techniques(count: int) -> void:
	gs.state["partner"]["learned_moves"] = []
	for i in range(1, count + 1):
		gs.learn_move(i)
	gs.learn_move(0x3A)


func _test_move_unlearning() -> void:
	gs.new_game()
	_learn_techniques(10)
	gs.state["tamer"]["level"] = 0
	ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
	ctx.state_2 = 0
	_eq(death.start(DeathRoutines.BUILTIN_LOST_ALL_LIVES), true, "builtin 47 waits")
	_eq(gs.state["partner"]["learned_moves"].size(), 11, "nothing forgotten when it starts (the C's tick does it)")
	death.tick(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_eq([ctx.read_pstat(DeathRoutines.PSTAT_REMAINING_FORGOTTEN), ctx.state_2], [2, 2],
			"level 0: 20 % of 10 techniques (the finisher not counted) = 2, step 2")
	death.tick(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_eq(gs.state["partner"]["learned_moves"].size(), 10, "step 2: one technique unlearnt")
	_eq([ctx.state_2, ctx.next_state_2, ctx.textbox_mode], [1, 3, 1], "its line shown, ✕ goes to step 3")
	var forgotten: int = ctx.read_pstat(DeathRoutines.PSTAT_FORGOTTEN_MOVE)
	_check(forgotten >= 1 and forgotten <= 10 and not gs.has_move(forgotten), "script value 0xF3 = the forgotten technique")
	ctx.state_2 = 3
	death.tick(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_eq([ctx.read_pstat(DeathRoutines.PSTAT_REMAINING_FORGOTTEN), ctx.state_2], [1, 2], "step 3: one left, step 2")
	death.tick(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	ctx.state_2 = 3
	death.tick(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_eq(ctx.active_instruction, 0, "the last one: the routine ends")
	_eq(gs.state["partner"]["learned_moves"].size(), 9, "2 techniques forgotten")
	_check(gs.has_move(0x3A), "the finisher stays")

	# Rounding: level 7, 9 techniques: 6 * 9 = 54 % -> 1 (54 % 100 >= 50 rounds up).
	_learn_techniques(9)
	gs.state["tamer"]["level"] = 7
	ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
	ctx.state_2 = 0
	death.tick(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_eq(ctx.read_pstat(DeathRoutines.PSTAT_REMAINING_FORGOTTEN), 1, "level 7, 9 techniques: 54 / 100 rounds up to 1")

	gs.state["tamer"]["level"] = 10
	ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
	ctx.state_2 = 0
	death.tick(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_eq(ctx.active_instruction, 0, "level 10: none to forget, the routine ends")


# --- section 0x4DE (MAPHEAD) ---------------------------------------------------------------

func _run_0x4de() -> void:
	ctx.current_script_id = 212
	ctx.active_instruction = 0
	interp.call_section(0, 0x4DE)
	interp.tick_script()
	ctx.sync_bit = 1
	interp.tick_script()


func _test_section_0x4de_dispatch() -> void:
	gs.new_game()
	gs.state["partner"]["lives"] = 0
	gs.state["partner"]["care"]["remaining_lifetime"] = 100
	gs.set_trigger(1)
	gs.clear_trigger(41)
	_run_0x4de()
	_check(not gs.is_trigger_set(1) and gs.is_trigger_set(41), "0x4DE: trigger 1 unset, 41 set")
	_check(ctx.code_id == 212 and ctx.pointer == ScriptFiles.section(files.script(212), 73), "no life left: script 212 section 73")

	gs.new_game()
	gs.state["partner"]["lives"] = 2
	gs.state["partner"]["care"]["remaining_lifetime"] = 0
	_run_0x4de()
	_check(ctx.code_id == 212 and ctx.pointer == ScriptFiles.section(files.script(212), 71), "lifetime 0: section 71")

	gs.new_game()
	gs.state["partner"]["lives"] = 2
	gs.state["partner"]["care"]["remaining_lifetime"] = 200
	_run_0x4de()
	_check(ctx.code_id == 212 and ctx.pointer == ScriptFiles.section(files.script(212), 72), "a life lost: section 72")


# --- script 212 section 72: the death evolutions --------------------------------------------

## From the roll on (the script value 110 is set by the test), with the partner and Care the
## routine needs: CALL_DIGIMON_ROUTINE 10 then sets EVOLUTION_TARGET and state 13, and waits.
func _death_evolution(digimon: String, roll: int, offset: int, discipline := 50) -> int:
	gs.new_game(digimon)
	gs.state["partner"]["care"]["discipline"] = discipline
	gs.set_script_value(110, roll)
	care.evolution_target = -1
	partner.state = Partner.STATE_NORMAL
	interp.partner = partner
	interp.care = care
	ctx.code = files.script(212)
	ctx.code_id = 212
	ctx.pointer = offset
	ctx.active_instruction = 0
	ctx.is_paused = false
	for i in 30:
		if ctx.is_paused or partner.state == Partner.STATE_EVOLVING:
			break
		interp.tick_script()
		if tb.entries[0].flags & TextBoxes.FLAG_OPEN != 0:
			pad.polled = Pad.CONFIRM
			pad.changed = Pad.CONFIRM
			tb.tick_textbox_handling()
			pad.polled = 0
			pad.changed = 0
	interp.partner = null
	interp.care = null
	return care.evolution_target


func _test_death_evolutions() -> void:
	_eq(_death_evolution("dw1:agumon", 5, 2138), 37, "a Rookie, roll 5: evolution into Bakemon")
	_eq(gs.state["partner"]["digimon"], "dw1:agumon", "the routine only starts the evolution (the scene applies it)")
	_eq(_death_evolution("dw1:agumon", 15, 2138), -1, "roll 15: no evolution")
	_eq(_death_evolution("dw1:metalgreymon", 4, 2214), 26, "MetalGreymon, roll 4: SkullGreymon")
	_eq(_death_evolution("dw1:kokatorimon", 8, 2290), 59, "Kokatorimon, roll 8: Phoenixmon")
	_eq(_death_evolution("dw1:angemon", 30, 2366, 40), 6, "Angemon, discipline 40, roll 30: Devimon")
	_eq(_death_evolution("dw1:angemon", 30, 2366, 60), -1, "Angemon, discipline 60: no evolution")


## CALL_DIGIMON_ROUTINE 2 / 10 as the C (partner.c:1152, :1203): EVOLUTION_TARGET and state 13,
## the Digimon untouched (EVL_applyEvolution reads it as the old one); a DELAY keeps its length.
func _test_evolution_routines() -> void:
	gs.new_game("dw1:agumon")
	interp.partner = partner
	interp.care = care
	gs.set_script_value(0xFE, 37)
	interp.call_digimon_routine(ScriptInterpreter.ROUTINE_EVOLVE)
	_eq([care.evolution_target, partner.state, ctx.sync_bit], [37, Partner.STATE_EVOLVING, 0],
			"routine 10: the target, state 13, the sync bit cleared")
	_eq(gs.state["partner"]["digimon"], "dw1:agumon", "routine 10 leaves the Digimon to the evolution scene")
	tb.delay_frames = 550
	ctx.active_instruction = ScriptContext.OP_DELAY
	partner.state = Partner.STATE_NORMAL
	interp._tick_waiting_instruction()
	_check(tb.delay_frames >= 549, "a DELAY after an evolution keeps its frames")
	ctx.active_instruction = 0
	interp.partner = null
	interp.care = null


# --- the UI boxes ----------------------------------------------------------------------------

func _test_murd_box() -> void:
	var box := MurdBox.new(boxes)
	box.open(2)
	_eq([box.is_open, box.lives, box.state], [true, 2, 0], "MurdBox opens on 2 lives, state 0")
	for i in 10:
		box.tick()
	_eq(box.state, 1, "the lost heart blinks from frame 10")
	for i in 20:
		box.tick()
	_eq(box.state, 2, "empty from frame 30")
	box.remove_static()
	_eq(boxes.boxes[MurdBox.BOX_ID].state, UIBoxes.STATE_CLOSED, "removeStaticUIBox: box 3 free at once")


func _test_egg_select() -> void:
	sound.played.clear()
	dooa.egg_slot = 2
	ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
	_eq(death.start(DeathRoutines.BUILTIN_EGG_SELECT), true, "builtin 29 waits")
	_eq([dooa.egg_slot, sound.played], [0, [[8, 4]]], "DOO2_openEggBox: egg slot 0, playSound(8, 4)")
	_close_boxes(6)
	_eq(boxes.boxes[EggSelectBox.BOX_ID].state, UIBoxes.STATE_OPEN, "the egg box opened")
	pad.changed = Pad.LEFT
	death.egg_select_box.tick()
	pad.changed = 0
	death.tick(DeathRoutines.BUILTIN_EGG_SELECT)
	_eq(dooa.egg_slot, 3, "left from 0: egg 3 (Yuramon), in DOOA's sequence")
	pad.changed = Pad.CONFIRM
	death.egg_select_box.tick()
	pad.changed = 0
	death.tick(DeathRoutines.BUILTIN_EGG_SELECT)
	_eq(ctx.active_instruction, ScriptContext.OP_CALL_ROUTINE, "✕: the box closes, the routine waits for it")
	_close_boxes()
	death.tick(DeathRoutines.BUILTIN_EGG_SELECT)
	_eq(ctx.active_instruction, 0, "the box closed: builtin 29 ends")


# --- MURD (murd.c) with the tamer's states 17 / 19 ---------------------------------------------

func _start_lost_life(routine: int, lives: int) -> void:
	gs.new_game("dw1:agumon")
	gs.state["partner"]["lives"] = lives
	gs.set_script_value(1, 10)
	map_changes.clear()
	map_layer.clear()
	sound.played.clear()
	tamer.visible = true
	partner.visible = true
	interp.partner = partner
	interp.tamer = tamer
	interp.call_digimon_routine(routine)
	interp.partner = null
	interp.tamer = null


## Frames until `done` (at most `limit`); a check fails if it never is.
func _until(done: Callable, what: String, limit := 1000) -> void:
	for i in limit:
		if done.call():
			return
		_frame()
	_check(false, "%s: not reached in %d frames (MURD %d/%d, DOOA %d/%d)" % [what, limit, murd.timer, murd.phase,
			dooa.frame, dooa.phase])


## One game frame: the tamer and the partner, then the objects (Field._frame's order).
func _frame() -> void:
	tamer.tick()
	match partner.state:
		Partner.STATE_DYING:
			partner.tick_dying()
		Partner.STATE_REBIRTH:
			partner.tick_rebirth()
	murd.tick()
	dooa.tick()
	boxes.step()


func _test_murd_lives_left() -> void:
	_start_lost_life(ScriptInterpreter.ROUTINE_BATTLE_LOSS, 2)
	_eq([tamer.state, partner.state, ctx.sync_bit], [Tamer.STATE_BATTLE_LOST_LIFE, Partner.STATE_SCRIPT, 0],
			"routine 9: tamer state 19, partner state 12, sync bit 0")
	_frame()
	_eq([murd.active, murd.timer, murd.death_map], [true, 1, DooaScene.DEATH_MAP_EARLY],
			"MURD starts; prosperity 10: the death map is ROOM08 (0xDA)")
	for i in 0x22:
		_frame()
	_eq([murd.phase, tamer.visible, partner.visible], [MurdScene.PHASE_BOX, false, true],
			"frame 0x23: the iris closed, the others hidden, the partner shown")
	_check(boxes.boxes[MurdBox.BOX_ID].state != UIBoxes.STATE_CLOSED and murd.darkness == 0xFF and map_layer == [false],
			"the lives box opens, the background is black, the map layer off")
	_eq(sound.music.stopped, 1, "stopBGM")
	_until(func() -> bool: return murd.timer >= 0x5F, "MURD to 0x5F")
	_frame()
	_eq(murd.phase, MurdScene.PHASE_DARKEN, "frame 0x5F: lives left, the screen darkens")
	_until(func() -> bool: return murd.timer >= 0x87, "MURD to 0x87")
	_eq([murd.phase, murd.darken], [MurdScene.PHASE_BLACK, MurdScene.DARKEN_MAX], "0x87: darkened to 0xA0, the box removed")
	_frame()
	_frame()
	_eq(map_changes, [[DooaScene.DEATH_MAP_EARLY, 1]], "changeToDeathMap: ROOM08, entrance 1")
	_eq([tamer.state, tamer.sub_state, partner.state, tamer.visible], [Tamer.STATE_BATTLE_LOST_LIFE, 1, Partner.STATE_IDLE, true],
			"tamerSetFullState(0x13, 1), partner state 11, the tamer shown")
	_until(func() -> bool: return not murd.active, "MURD to its end")
	_eq([murd.timer, murd.darken, map_layer], [MurdScene.OVER, 0, [false, true]], "0xB9: lightened, the object gone, the map layer on")
	_eq(ctx.sync_bit, 0, "the sync bit is set on the tamer's next tick")
	_frame()
	_eq(ctx.sync_bit, 1, "tamerTickBattleLostLife: MURD over, the sync bit set")


func _test_murd_no_life_left() -> void:
	_start_lost_life(ScriptInterpreter.ROUTINE_COLLAPSE, 0)
	_eq(tamer.state, Tamer.STATE_SICKNESS_LOST_LIFE, "routine 7: tamer state 17")
	_until(func() -> bool: return murd.timer >= 0x5F, "MURD to 0x5F")
	_frame()
	_eq(murd.phase, MurdScene.PHASE_BOX_OUT, "no life left: the box closes back onto the partner")
	_close_boxes()
	_frame()
	_frame()
	# DOOA_tick(.., 0) adds its object behind MURD's: it ticks in the same frame, from 0x23.
	_eq([murd.timer, dooa.sequence, dooa.frame, partner.visible], [MurdScene.OVER, DooaScene.DISSOLVE, DooaScene.MAP_CHANGE + 1, false],
			"MURD hands over to DOOA's dissolution at frame 0x23, the partner off the map")
	_eq(map_changes, [[DooaScene.DEATH_MAP_EARLY, 1]], "DOOA changes to the death map at once")
	_eq([tamer.state, partner.state, partner.sub_state], [Tamer.STATE_STILL, Partner.STATE_DYING, 2],
			"setSomeDyingState: tamer state 6, partner state 8 sub-state 2")
	_eq(sound.map_sets, [DooaScene.SOUND_SET], "loadMapSounds2(0x13)")
	_until(func() -> bool: return dooa.frame == -1, "DOOA to its end")
	_check(not partner.visible, "the partner is gone after the dissolution")
	_frame()
	_eq([ctx.sync_bit, gs.state["partner"]["care"]["remaining_lifetime"]], [1, 360],
			"partnerTickDying: lifetime 360, the sync bit set")


# --- DOOA: the natural death (partnerTickDying) ------------------------------------------------

func _test_natural_death() -> void:
	gs.new_game("dw1:agumon")
	gs.state["partner"]["lives"] = 2
	gs.state["partner"]["care"]["remaining_lifetime"] = 0
	gs.set_trigger(DooaScene.TRIGGER_CLINIC)
	map_changes.clear()
	sound.played.clear()
	sound.map_sets.clear()
	ctx.sync_bit = 1
	interp.partner = partner
	interp.call_digimon_routine(ScriptInterpreter.ROUTINE_DYING)
	interp.partner = null
	_eq([partner.state, ctx.sync_bit], [Partner.STATE_DYING, 0], "routine 3: partner state 8, sync bit 0")
	tamer.set_state(Tamer.STATE_FREE)
	tamer.position = Vector3(400, 0, 0)
	partner.position = Vector3.ZERO
	partner.tick_dying()
	_eq([partner.sub_state, sound.map_sets], [1, [DooaScene.SOUND_SET]], "sub-state 0: it walks to the tamer, the death's sounds")
	partner.tick_dying()
	_eq([partner.sub_state, dooa.sequence], [1, DooaScene.NONE], "far from the tamer: it keeps walking")
	tamer.position = Vector3(60, 0, 0)
	partner.tick_dying()
	_eq([partner.sub_state, tamer.state, dooa.sequence, dooa.frame], [2, Tamer.STATE_STILL, DooaScene.DISSOLVE, 0],
			"close: the dissolution from frame 0 (the iris), the tamer stands")
	_eq(dooa.death_map, DooaScene.DEATH_MAP_LATE, "the clinic trigger: the death map is ROOM10 (0xCD)")
	var phases := []
	dooa.phase_changed.connect(func(p: int) -> void: phases.append(p))
	_until(func() -> bool: return dooa.frame == -1, "DOOA to its end")
	_eq(phases, [DooaScene.PHASE_TURN, DooaScene.PHASE_SHARDS, DooaScene.PHASE_SQUASH, DooaScene.PHASE_RISE,
			DooaScene.PHASE_WAIT, DooaScene.PHASE_EGG, DooaScene.PHASE_END], "DOOA_tickDissolve's phases in order")
	_eq(map_changes, [[DooaScene.DEATH_MAP_LATE, 1]], "the map changed at 0x23")
	_eq(sound.played, [[8, 0], [8, 1], [8, 2], [8, 3]], "its sounds: playSound2(8, 0) at 0x69, (8, 1) at 0xBF, (8, 2) at 0xD1, (8, 3) at 0x135")
	_check(not partner.visible and dooa.darkness == 0xFF and dooa.jijimon_fade == 0,
			"lives left or not, the partner is gone; the background stays black, Jijimon faded in")
	_frame()
	_eq([ctx.sync_bit, gs.state["partner"]["care"]["remaining_lifetime"], gs.state["partner"]["lives"]], [1, 360, 2],
			"the end: lifetime 360, the sync bit set, the lives untouched")
	gs.clear_trigger(DooaScene.TRIGGER_CLINIC)


# --- DOOA: the rebirth (partnerTickDying2) -----------------------------------------------------

func _test_rebirth() -> void:
	sound.played.clear()
	sound.partner_sets = 0
	care.is_natural_death = true
	gs.state["tamer"]["level"] = 0
	dooa.egg_slot = 2
	ctx.sync_bit = 1
	interp.partner = partner
	interp.call_digimon_routine(ScriptInterpreter.ROUTINE_REBIRTH)
	interp.partner = null
	_eq([partner.state, ctx.sync_bit, gs.state["partner"]["digimon"]], [Partner.STATE_REBIRTH, 0, "dw1:agumon"],
			"routine 4: partner state 14, nothing reincarnated yet")
	_frame()
	_eq([dooa.sequence, dooa.phase], [DooaScene.REBIRTH, DooaScene.PHASE_REBIRTH], "DOOA_getSequenceState: the rebirth object")
	_until(func() -> bool: return dooa.frame >= 152, "rebirth to 152")
	_eq([gs.state["partner"]["digimon"], care.is_natural_death], ["dw1:poyomon", false],
			"frame 152: reincarnatePartner with egg 2 (Poyomon)")
	_check(partner.visible == false and partner.position == Vector3.ZERO, "the baby at the room's centre, still hidden")
	_eq(sound.partner_sets, 1, "the baby's sounds loaded")
	_until(func() -> bool: return dooa.frame >= 202, "rebirth to 202")
	_check(partner.visible and dooa.darkness == 0, "frame 202: the baby shown, the background back")
	_until(func() -> bool: return dooa.phase == DooaScene.PHASE_POSE, "rebirth to the pose")
	_frame()
	_eq(dooa.phase, DooaScene.PHASE_POSE, "the pose waits for its animation's end")
	# Headless the model's animation doesn't play: its end.
	if partner.animator != null:
		partner.animator.frame = partner.animator.frame_count
	_until(func() -> bool: return dooa.frame == -1, "DOOA to its end")
	_eq(sound.played.slice(0, 2), [[8, 5], [8, 6]], "playSound(8, 5) at 10, (8, 6) at 132")
	_eq(sound.played.count([8, 7]), 6, "a sparkle sound for each of the 6 bones")
	_frame()
	var c: Dictionary = gs.state["partner"]["care"]
	_eq([ctx.sync_bit, c["remaining_lifetime"], c["evo_timer"], gs.script_value(Clock.PSTAT_TIME_SPEED), partner.sub_state],
			[1, 360, 0, 0, 2], "partnerTickDying2's end: lifetime 360, evo timer 0, time speed 0, the sync bit")

	# No life left: the egg is random.
	gs.state["partner"]["lives"] = 0
	dooa.egg_slot = 9
	dooa.start_rebirth()
	_check(dooa.egg_slot >= 0 and dooa.egg_slot < 4, "no life left: rand() % 4 picks the egg")


# --- Care reads IS_SCRIPT_PAUSED -------------------------------------------------------------

func _test_care_script_paused() -> void:
	gs.new_game("dw1:agumon")
	care.script_ctx = ctx
	care.tamer = tamer
	care.partner = partner
	tamer.set_state(Tamer.STATE_FREE)
	partner.state = Partner.STATE_NORMAL
	care.is_natural_death = false
	gs.state["partner"]["care"]["remaining_lifetime"] = 0
	ctx.is_paused = false
	care.tick_death_condition()
	_eq(care.is_natural_death, false, "a script runs: no natural death yet")
	ctx.is_paused = true
	care.script_running = true
	care.tick_death_condition()
	_eq(care.is_natural_death, true, "the script paused: the natural death (script_running no longer blocks it)")
	care.script_ctx = null
	care.tamer = null
	care.partner = null
