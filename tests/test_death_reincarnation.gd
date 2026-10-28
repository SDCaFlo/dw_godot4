extends SceneTree
## Tests for Death, Lives, Reincarnation, and Death Digivolution (specs/death_reincarnation.md):
##   godot --headless --path . -s res://tests/test_death_reincarnation.gd
## Exits 1 if a check fails.

const DeathRoutines := preload("res://scripts/script/death_routines.gd")
const MurdBox := preload("res://scripts/ui/murd_box.gd")
const EggSelectBox := preload("res://scripts/ui/egg_select_box.gd")
const DeathHost := preload("res://scripts/field/hosts/death_host.gd")
const DeathIris := preload("res://scripts/ui/death_iris.gd")

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

	_setup()
	_test_reincarnation_math()
	_test_move_unlearning()
	_test_section_0x4de_dispatch()
	_test_death_digivolutions()
	_test_murd_box()
	_test_egg_select_box()
	_test_death_host_integration()
	_teardown()

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

	routines = ScriptRoutines.new()
	death = DeathRoutines.new()
	routines.add_child(death)
	routines.configure(ctx, tb, gs, data)

	interp = ScriptInterpreter.new(ctx, files, tb)
	interp.game_state = gs
	interp.data = data
	interp.routines = routines


func _teardown() -> void:
	pass


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL: %s" % msg)


# --- 1. Reincarnation Math & Resets -----------------------------------------------------------

func _test_reincarnation_math() -> void:
	# Natural death with Tamer Level 10: 10% stat inheritance
	gs.new_game()
	gs.state["tamer"]["level"] = 10
	var prev_base: Dictionary = gs.state["partner"]["stats"]["base"]
	prev_base["max_hp"] = 500
	prev_base["max_mp"] = 800
	prev_base["offense"] = 150
	prev_base["defense"] = 120
	prev_base["speed"] = 100
	prev_base["brains"] = 90
	gs.state["partner"]["care"]["age"] = 15
	gs.state["partner"]["care"]["remaining_lifetime"] = 0
	gs.state["partner"]["care"]["care_mistakes"] = 5
	gs.state["partner"]["lives"] = 1

	# Reincarnate into Botamon (id 1): base stats (90, 110, 10, 11, 9, 10) + 10%
	gs.reincarnate_partner(1, true)
	var new_base: Dictionary = gs.state["partner"]["stats"]["base"]
	var care: Dictionary = gs.state["partner"]["care"]

	_check(new_base["max_hp"] == 90 + 50, "Botamon natural death HP (90 + 50 = 140)")
	_check(new_base["max_mp"] == 110 + 80, "Botamon natural death MP (110 + 80 = 190)")
	_check(new_base["offense"] == 10 + 15, "Botamon natural death Offense (10 + 15 = 25)")
	_check(new_base["defense"] == 11 + 12, "Botamon natural death Defense (11 + 12 = 23)")
	_check(new_base["speed"] == 9 + 10, "Botamon natural death Speed (9 + 10 = 19)")
	_check(new_base["brains"] == 10 + 9, "Botamon natural death Brains (10 + 9 = 19)")

	_check(gs.state["partner"]["lives"] == 3, "Lives reset to 3")
	_check(care["remaining_lifetime"] == 360, "Remaining lifetime reset to 360")
	_check(care["age"] == 0, "Age reset to 0")
	_check(care["care_mistakes"] == 0, "Care mistakes reset to 0")
	_check(care["happiness"] == 50 and care["discipline"] == 50, "Happiness and discipline reset to 50")
	_check(gs.state["partner"]["digimon"] == "dw1:botamon", "Partner digimon key set to botamon")
	_check(gs.is_raised("dw1:botamon"), "Botamon marked as raised")

	# Loss of all lives (is_natural_death = false): 0% stat inheritance
	gs.state["tamer"]["level"] = 10
	prev_base["max_hp"] = 1000
	gs.reincarnate_partner(15, false)  # Poyomon / Punimon
	var uninherited_base: Dictionary = gs.state["partner"]["stats"]["base"]
	_check(uninherited_base["max_hp"] == 120, "0 lives lost: 0% inheritance, base HP 120")
	_check(uninherited_base["offense"] == 16, "0 lives lost: base offense 16")


# --- 2. Move Forgetting: Builtin 47 (lostAllLives) ---------------------------------------------

func _test_move_unlearning() -> void:
	gs.new_game()
	# Learn 10 moves
	var move_keys: Array = []
	for i in range(1, 11):
		var k: String = data.key_of("moves/move_data", i)
		move_keys.append(k)
		gs.learn_move(k)

	_check(gs.state["partner"]["learned_moves"].size() == 10, "10 moves initially learned")

	# Tamer Level 0: (10 - 0) * 2% = 20% of 10 moves = 2 moves forgotten
	gs.state["tamer"]["level"] = 0
	death.start(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_check(ctx.read_pstat(DeathRoutines.PSTAT_REMAINING_FORGOTTEN) == 2, "Tamer lvl 0: 2 moves to forget")

	# Acknowledge first move
	ctx.state_2 = 3
	death.tick(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_check(ctx.read_pstat(DeathRoutines.PSTAT_REMAINING_FORGOTTEN) == 1, "1 move remaining to forget")

	# Acknowledge second move
	ctx.state_2 = 3
	death.tick(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_check(ctx.active_instruction == 0, "Builtin 47 finishes when count reaches 0")
	_check(gs.state["partner"]["learned_moves"].size() == 8, "Exactly 2 moves unlearned (8 left)")

	# Tamer Level 10: (10 - 10) * 2% = 0% forgotten
	gs.state["tamer"]["level"] = 10
	var active := death.start(DeathRoutines.BUILTIN_LOST_ALL_LIVES)
	_check(not active and ctx.active_instruction == 0, "Tamer lvl 10: 0 moves forgotten, completes immediately")
	_check(gs.state["partner"]["learned_moves"].size() == 8, "No moves unlearned at level 10")


# --- 3. Section 0x4DE Dispatching -------------------------------------------------------------

func _test_section_0x4de_dispatch() -> void:
	# Case A: 0 Lives Left -> CALL_DIGIMON_ROUTINE 7 and SECTION_ON_EXIT 73
	gs.new_game()
	gs.state["partner"]["lives"] = 0
	gs.state["partner"]["care"]["remaining_lifetime"] = 100
	gs.set_trigger(1)
	gs.clear_trigger(41)
	ctx.current_script_id = 212
	ctx.active_instruction = 0

	interp.call_section(0, 0x4DE)
	# MAPHEAD section 0x4DE calls routine 7 then WAIT_FOR_ENTITY 255.
	interp.tick_script()
	# The cutscene routine completes, setting sync_bit = 1
	ctx.sync_bit = 1
	interp.tick_script()
	_check(not gs.is_trigger_set(1) and gs.is_trigger_set(41), "Section 0x4DE: trigger 1 unset, trigger 41 set")
	_check(ctx.code_id == 212 and ctx.pointer == ScriptFiles.section(files.script(212), 73),
			"0 lives: routes to script 212 section 73")

	# Case B: Natural Death (lifetime <= 0, lives > 0) -> CALL_DIGIMON_ROUTINE 3 and SECTION_ON_EXIT 71
	gs.new_game()
	gs.state["partner"]["lives"] = 2
	gs.state["partner"]["care"]["remaining_lifetime"] = 0
	ctx.current_script_id = 212
	ctx.active_instruction = 0

	interp.call_section(0, 0x4DE)
	interp.tick_script()
	ctx.sync_bit = 1
	interp.tick_script()
	_check(ctx.code_id == 212 and ctx.pointer == ScriptFiles.section(files.script(212), 71),
			"lifetime 0: routes to script 212 section 71")

	# Case C: Battle Loss / Fainting (lives > 0, lifetime > 0) -> CALL_DIGIMON_ROUTINE 9 and SECTION_ON_EXIT 72
	gs.new_game()
	gs.state["partner"]["lives"] = 2
	gs.state["partner"]["care"]["remaining_lifetime"] = 200
	ctx.current_script_id = 212
	ctx.active_instruction = 0

	interp.call_section(0, 0x4DE)
	interp.tick_script()
	ctx.sync_bit = 1
	interp.tick_script()
	_check(ctx.code_id == 212 and ctx.pointer == ScriptFiles.section(files.script(212), 72),
			"lives > 0: routes to script 212 section 72")


# --- 4. Death Digivolutions (Script 212 Section 72) --------------------------------------------

func _test_death_digivolutions() -> void:
	# Rookie with roll < 10 -> Bakemon (id 37)
	gs.new_game("dw1:agumon")
	gs.state["partner"]["digimon"] = "dw1:agumon"
	gs.set_script_value(110, 5)    # Roll < 10 (successful roll)
	_run_script_212_section_72(2138)
	_check(gs.state["partner"]["digimon"] == "dw1:bakemon", "Agumon roll 5 evolves to Bakemon")
	_check(gs.is_raised("dw1:bakemon"), "Bakemon marked as raised")

	# Rookie with roll >= 10 -> stays Rookie
	gs.new_game("dw1:agumon")
	gs.set_script_value(110, 15)   # Roll >= 10 (fail roll)
	_run_script_212_section_72(2138)
	_check(gs.state["partner"]["digimon"] == "dw1:agumon", "Agumon roll 15 stays Agumon")

	# MetalGreymon (12) with roll < 10 -> SkullGreymon (26)
	gs.new_game("dw1:metalgreymon")
	gs.set_script_value(110, 4)
	_run_script_212_section_72(2214)
	_check(gs.state["partner"]["digimon"] == "dw1:skullgreymon", "MetalGreymon roll 4 evolves to SkullGreymon")

	# Kokatorimon (50) with roll < 10 -> Phoenixmon (59)
	gs.new_game("dw1:kokatorimon")
	gs.set_script_value(110, 8)
	_run_script_212_section_72(2290)
	_check(gs.state["partner"]["digimon"] == "dw1:phoenixmon", "Kokatorimon roll 8 evolves to Phoenixmon")

	# Angemon (20) with discipline <= 49 and roll < 50 -> Devimon (6)
	gs.new_game("dw1:angemon")
	gs.state["partner"]["care"]["discipline"] = 40
	gs.set_script_value(110, 30)
	_run_script_212_section_72(2366)
	_check(gs.state["partner"]["digimon"] == "dw1:devimon", "Angemon discipline 40 roll 30 evolves to Devimon")

	# Angemon (20) with discipline > 49 and roll < 50 -> does not evolve
	gs.new_game("dw1:angemon")
	gs.state["partner"]["care"]["discipline"] = 60
	gs.set_script_value(110, 30)
	_run_script_212_section_72(2366)
	_check(gs.state["partner"]["digimon"] == "dw1:angemon", "Angemon discipline 60 does not evolve")


# --- 5. Phase 2 UI Components: MurdBox & EggSelectBox -----------------------------------------

func _test_murd_box() -> void:
	var murd := MurdBox.new(boxes)
	murd.open(2) # 2 lives remaining (losing the 3rd life)
	_check(murd.is_open, "MurdBox is open")
	_check(murd.lives == 2, "MurdBox tracks 2 remaining lives")
	_check(murd.state == 0, "MurdBox begins in state 0")

	# Advance 10 frames -> state 1 (blinking)
	for i in 10:
		murd.tick()
	_check(murd.state == 1, "MurdBox enters state 1 at frame 10")

	# Advance to 30 frames -> state 2 (empty heart)
	for i in 20:
		murd.tick()
	_check(murd.state == 2, "MurdBox enters state 2 at frame 30")

	murd.close()
	_check(not murd.is_open, "MurdBox is closed")


func _test_egg_select_box() -> void:
	var egg_box := EggSelectBox.new(boxes, pad)
	egg_box.open(0)
	_check(egg_box.is_open, "EggSelectBox is open")
	_check(egg_box.selected_egg == 0, "Default egg selection is 0 (Botamon)")

	# Ready for input
	egg_box.ready_for_input = true

	# Navigate Right -> egg 1 (Poyomon)
	pad.changed = Pad.RIGHT
	egg_box.tick()
	_check(egg_box.selected_egg == 1, "Egg selection moves right to 1 (Poyomon)")

	# Navigate Right -> egg 2 (Punimon)
	pad.changed = Pad.RIGHT
	egg_box.tick()
	_check(egg_box.selected_egg == 2, "Egg selection moves right to 2 (Punimon)")

	# Navigate Left -> egg 1
	pad.changed = Pad.LEFT
	egg_box.tick()
	_check(egg_box.selected_egg == 1, "Egg selection moves left back to 1")

	# Confirm selection
	pad.changed = Pad.CONFIRM
	egg_box.tick()
	_check(egg_box.confirmed, "Egg selection is confirmed on Pad.CONFIRM")

	# Integration test with DeathRoutines & Builtin 29
	death.selected_egg = 0
	ctx.current_script_id = 212
	ctx.active_instruction = 0
	death.start(DeathRoutines.BUILTIN_EGG_SELECT)
	death.egg_select_box.ready_for_input = true

	# Move to egg 3 (Yuramon)
	pad.changed = Pad.LEFT
	death.tick(DeathRoutines.BUILTIN_EGG_SELECT)
	pad.changed = Pad.CONFIRM
	death.tick(DeathRoutines.BUILTIN_EGG_SELECT)
	_check(death.selected_egg == 3, "DeathRoutines updates selected_egg to 3")
	_check(ctx.active_instruction == 0, "Builtin 29 completes active_instruction on confirmation")


# --- 6. Phase 3: DeathHost & Iris Integration ------------------------------------------------

func _test_death_host_integration() -> void:
	var death_host := DeathHost.new()
	death_host.configure(boxes, null, null, null, ctx, interp, null)
	interp.death_host = death_host

	# Test hospital map routing formula
	gs.new_game()
	gs.clear_trigger(DeathHost.TRIGGER_CLINIC_OPEN)
	gs.clear_trigger(DeathHost.TRIGGER_JIJIMON_EXTENDED)
	gs.set_script_value(1, 10) # Prosperity = 10
	_check(death_host.determine_death_map() == DeathHost.MAP_JIJIMON_HOUSE_EARLY,
			"Low prosperity (<50) without clinic routes to Jijimon House early (Map 218)")

	gs.set_script_value(1, 55) # Prosperity = 55
	_check(death_host.determine_death_map() == DeathHost.MAP_JIJIMON_HOUSE_LATE,
			"High prosperity (>=50) routes to Jijimon House late (Map 205)")

	gs.set_script_value(1, 20)
	gs.set_trigger(DeathHost.TRIGGER_CLINIC_OPEN)
	_check(death_host.determine_death_map() == DeathHost.MAP_JIJIMON_HOUSE_LATE,
			"Clinic open trigger routes to Jijimon House late (Map 205)")

	# Test cutscene progression for Battle Loss
	var fade := Fade.new()
	fade._ready()
	death_host.fade = fade
	ctx.sync_bit = 0
	death_host.start_scene(ScriptInterpreter.ROUTINE_BATTLE_LOSS)
	_check(death_host.is_active, "DeathHost is active upon starting battle loss")
	_check(death_host.scene_phase == 1, "DeathHost begins in phase 1 (Iris contraction)")

	# Complete Iris contraction (35 frames)
	for i in 36:
		death_host.tick()
	_check(death_host.scene_phase == 2, "DeathHost advances to phase 2 (MurdBox)")
	_check(death_host.murd_box.is_open, "MurdBox is opened in phase 2")

	# Advance MurdBox (60 frames) -> Phase 3 -> Phase 4
	for i in 61:
		death_host.tick()
	_check(death_host.scene_phase == 4, "DeathHost advances to phase 4 (Warp completed)")
	_check(not death_host.iris.visible, "DeathIris is hidden upon warp")
	_check(fade.in_current > 0, "Fade from black is initiated after hospital warp")

	# Advance warp delay (10 frames) -> Scene finishes and sync_bit is set
	for i in 11:
		death_host.tick()
	_check(not death_host.is_active, "DeathHost finishes scene after warp")
	_check(ctx.sync_bit == 1, "DeathHost sets script sync_bit upon completion")

	# Tick fade to completion
	for i in 25:
		fade.tick()
	_check(fade.progress == 0 and not fade.visible, "Fade finishes completely clear (no black screen)")

	# Test 0 lives partner invisibility during Digitama talk, then model reload on ROUTINE_REBIRTH
	var mock_partner := Partner.new()
	mock_partner.digimon = "dw1:agumon"
	mock_partner.visible = true
	death_host.partner = mock_partner
	interp.partner = mock_partner
	gs.state["partner"]["lives"] = 0
	death_host._warp_to_recovery_hospital()
	_check(not mock_partner.visible, "Partner is hidden after 0 lives death warp (dissolved)")

	# Execute Routine 4 (ROUTINE_REBIRTH)
	interp.call_digimon_routine(ScriptInterpreter.ROUTINE_REBIRTH)
	_check(mock_partner.visible, "Partner becomes visible upon baby rebirth")
	_check(mock_partner.digimon in ["dw1:botamon", "dw1:punimon", "dw1:poyomon", "dw1:yuramon"],
			"Partner model reloaded to baby Digimon: %s" % mock_partner.digimon)

	interp.death_host = null


func _run_script_212_section_72(start_offset: int) -> void:
	ctx.code = files.script(212)
	ctx.code_id = 212
	ctx.pointer = start_offset
	ctx.active_instruction = 0
	ctx.is_paused = false
	_run_script_frames(30)


func _run_script_frames(max_frames: int) -> void:
	var frames := 0
	while not ctx.is_paused and frames < max_frames:
		interp.tick_script()
		# Dismiss any textboxes automatically
		if tb.entries[0].flags & TextBoxes.FLAG_OPEN != 0:
			pad.polled = Pad.CONFIRM
			pad.changed = Pad.CONFIRM
			tb.tick_textbox_handling()
			pad.polled = 0
			pad.changed = 0
		frames += 1
