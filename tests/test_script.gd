extends SceneTree
## The event-script interpreter (scripts/script/) against specs/script.md §2, values worked out
## from the C, then every section of every real script (asset porter output):
##   godot --headless --path . -s res://tests/test_script.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false
var data: Node
var gs: Node
var interp: ScriptInterpreter
var ctx: ScriptContext
var boxes: UIBoxes
var pad: Pad
var files: ScriptFiles
var unported := []


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or data.records("systems/script_stat_limits").is_empty():
		print("SKIP: data porter output missing")
		quit(0)
		return false
	_setup()
	_flow()
	_if_and_switch()
	_values_and_caps()
	_items_cards_stats()
	_dates()
	_ends_and_unported()
	_delay_and_text()
	_walk_to()
	_step4()
	_map_entry()
	_real_scripts()
	_teardown()
	print("%s: script checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _setup() -> void:
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()
	boxes = UIBoxes.new()
	var area := TextArea.new(data, "en_us")
	ctx = ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	pad = Pad.new()
	var tb := TextBoxes.new(boxes, area, ctx, pad, data, gs)
	files = ScriptFiles.new()
	interp = ScriptInterpreter.new(ctx, files, tb)
	interp.game_state = gs
	interp.data = data
	interp.unported.connect(func(op, what): unported.append(what))


func _teardown() -> void:
	boxes.free()
	gs.free()
	data.free()


## A synthetic script: section `id` at the code (after a one-entry table), loaded as script 500.
func _run(code: Array, frames := 1, id := 1) -> void:
	var bytes := PackedByteArray([8, 0, id & 0xFF, id >> 8, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code))
	files._cache[500] = bytes
	interp.call_section(500, id)
	for i in frames:
		_frame()


func _frame(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	interp.tick_script()
	boxes.step()


## Code offsets: the code starts at 8.
func _flow() -> void:
	# 8 JUMP_AND_LINK 18; 12 SET_PSTAT 11 = 6; 16 END; 18 SET_PSTAT 10 = 5; 22 JUMP_RETURN
	_run([0x13, 0, 18, 0, 0x1E, 0, 11, 6, 0xFE, 0, 0x1E, 0, 10, 5, 0x15, 0])
	_eq([gs.script_value(10), gs.script_value(11), ctx.is_paused, ctx.stack.size()], [5, 6, true, 0],
			"link, return, then END with an empty stack: the script ended")
	# A link left on the stack: END unwinds it (type 1 is skipped).
	_run([0x13, 0, 12, 0, 0xFE, 0])
	_eq([ctx.is_paused, ctx.stack.size()], [true, 0], "END unwinds a link entry")
	# JUMP_TO over a SET_PSTAT.
	gs.set_script_value(12, 0)
	_run([0x16, 0, 16, 0, 0x1E, 0, 12, 1, 0xFE, 0])
	_eq(gs.script_value(12), 0, "JUMP_TO skips")


func _if_and_switch() -> void:
	# SWITCH pstat 20, count 2, offsets [16, 24]: value 5 clamps to 1 -> 24 (SET_PSTAT 21 = 2).
	gs.set_script_value(20, 5)
	_run([0x18, 20, 2, 0, 16, 0, 24, 0, 0x1E, 0, 21, 1, 0xFE, 0, 0, 0, 0x1E, 0, 21, 2, 0xFE, 0])
	_eq(gs.script_value(21), 2, "SWITCH clamps to count - 1")
	# IF: trigger 7 set AND pstat 30 >= 3 -> jump-if-true to 28 (SET_PSTAT 31 = 9), else 24 (= 1).
	gs.set_trigger(7)
	gs.set_script_value(30, 3)
	var cond := [0x19, 0, 0x00, 0, 7, 0, 0x8A, 0, 30, 3, 0x10, 0, 28, 0, 0x19, 0]   # 8..23
	_run(cond + [0x1E, 0, 31, 1, 0x1E, 0, 31, 9, 0xFE, 0])
	_eq(gs.script_value(31), 9, "IF: trigger AND pstat >= -> jump if true")
	gs.set_script_value(30, 2)
	_run(cond + [0x1E, 0, 31, 1, 0xFE, 0])
	_eq(gs.script_value(31), 1, "IF false: no jump, the script goes on after 0x19")
	# OR: not-set trigger 8 (op 1) OR pstat 30 == 2 -> true.
	_run([0x19, 0, 0x01, 0, 8, 0, 0x48, 0, 30, 2, 0x18, 0, 26, 0, 0x19, 0, 0x1E, 0, 32, 4, 0xFE, 0, 0, 0, 0x1E, 0, 32, 5, 0xFE, 0])
	_eq(gs.script_value(32), 4, "IF: OR, jump-if-false not taken")
	_eq([ScriptInterpreter.compare(2, 3, 3), ScriptInterpreter.compare(4, 3, 3), ScriptInterpreter.compare(5, 2, 3),
			ScriptInterpreter.compare(1, 2, 3)], [1, 0, 1, 1], "comparisons >= > < !=")


func _values_and_caps() -> void:
	gs.set_script_value(40, 250)
	gs.set_script_value(41, 3)
	_run([0x1F, 0, 40, 10, 0x20, 0, 41, 10, 0xFE, 0])
	_eq([gs.script_value(40), gs.script_value(41)], [255, 0], "ADD_TO_PSTAT caps at 255, REDUCE_PSTAT at 0")
	gs.state["money"] = 999990
	_run([0x2A, 0, 100, 0, 0, 0, 0xFE, 0])
	_eq(gs.state["money"], 999999, "ADD_MONEY caps at 999,999")
	_run([0x2B, 0, 0x40, 0x42, 0x0F, 0, 0xFE, 0])   # 1,000,000
	_eq(gs.state["money"], 0, "REDUCE_MONEY stops at 0")
	_run([0x31, 0, 0xE0, 0x2E, 0xFE, 0])   # 12000
	_eq(gs.state["merit"], 9999, "SET_MERIT caps at 9,999")
	_run([0x33, 0, 10, 0, 0xFE, 0])
	_eq(gs.state["merit"], 0, "quirk: REDUCE_MERIT 10 clears merit (MERIT = -10, then 0)")
	gs.set_trigger(ScriptInterpreter.TRIGGER_NO_TURN)
	_run([0x1D, 0, 0x2C, 0, 0x1C, 0, 0x2D, 0, 0xFE, 0])
	_eq([gs.is_trigger_set(0x2C), gs.is_trigger_set(0x2D)], [false, true], "SET_TRIGGER / UNSET_TRIGGER")


func _items_cards_stats() -> void:
	var slots: Array = gs.state["inventory"]["slots"]
	slots.fill(null)
	slots[0] = {"item": data.key_of("items/item_data", 38), "amount": 99}
	_run([0x28, 0, 38, 1, 0xFE, 0])
	_eq([gs.is_trigger_set(0), slots[1]], [true, null], "GIVE_ITEM to a full stack fails: trigger 0, no other slot")
	_run([0x28, 0, 40, 3, 0x28, 0, 40, 200, 0xFE, 0])
	_eq([gs.is_trigger_set(0), gs.item_count(40)], [false, 99], "a new item: the first empty slot; 3 + 200 caps at 99")
	_run([0x29, 0, 40, 5, 0xFE, 0])
	_eq(gs.item_count(40), 94, "REMOVE_ITEM")
	gs.set_card_count(3, 9)
	_run([0x2F, 3, 0x2F, 4, 0xFE, 0])
	_eq([gs.card_count(3), gs.card_count(4)], [9, 1], "GIVE_CARD stops at 9")
	var care: Dictionary = gs.state["partner"]["care"]
	care["happiness"] = 90
	_run([0x35, 9, 20, 0, 0xFE, 0])
	_eq(care["happiness"], 100, "ADD_STAT happiness caps at 100 (STATS_LIMIT_ARRAY)")
	_run([0x36, 9, 0xF4, 0x01, 0xFE, 0])   # -500
	_eq(care["happiness"], -100, "REDUCE_STAT happiness stops at -100")
	_run([0x34, 22, 3, 0, 0xFE, 0])
	_eq(gs.state["partner"]["lives"], 1, "quirk: SET_STAT lives 3 -> 1 (the limit read past the array)")
	gs.state["partner"]["stats"]["base"]["max_hp"] = 500
	gs.state["partner"]["stats"]["current"]["hp"] = 300
	_run([0x34, 6, 0xE8, 0x03, 0xFE, 0])   # 1000
	_eq(gs.state["partner"]["stats"]["current"]["hp"], 500, "SET_STAT HP caps at max HP")
	gs.set_script_value(50, 150)
	_run([0x69, 50, 0xFE, 0])
	_eq(gs.state["partner"]["stats"]["current"]["hp"], 1, "DEAL_DAMAGE 150 %: at least 1 HP left")


func _dates() -> void:
	for i in 4:
		gs.set_script_value(60 + i, [1, 2, 3, 4][i])   # year 1, day 2, 03:04
	# COMPARE_DATE pstat 60, trigger 0x100, >=, year 1, day 2, 03:00, _
	_run([0x2C, 60, 0x00, 0x01, 2, 1, 2, 3, 0, 0, 0xFE, 0])
	_eq(gs.is_trigger_set(0x100), true, "COMPARE_DATE: 1/2 03:04 >= 1/2 03:00 sets the trigger")
	# ADD_MINUTES_TO_DATE_AT pstat 60, +60 * 24 * 29 (29 days): day 2 + 29 -> year 2, day 1.
	var m := 60 * 24 * 29
	_run([0x38, 60, m & 0xFF, (m >> 8) & 0xFF, (m >> 16) & 0xFF, 0, 0xFE, 0])
	_eq([gs.script_value(60), gs.script_value(61), gs.script_value(62), gs.script_value(63)], [2, 1, 3, 4],
			"ADD_MINUTES_TO_DATE_AT: 30-day years")
	_eq(ScriptInterpreter.minutes_to_date(255 * 43200), [25, 14, 23, 59], "secondsToDate's cap")


func _ends_and_unported() -> void:
	gs.set_script_value(70, 0)
	_run([0x12, 0, 0x1E, 0, 70, 1, 0xFE, 0])
	_eq([gs.script_value(70), ctx.is_paused], [0, true], "quirk: UNUSED_12 ends the script (its 00 is opcode 0)")
	unported.clear()
	# SPAWN_ITEM item, x, z (5 bytes) is skipped exactly; the next instruction runs.
	_run([0x74, 48, 44, 0, 31, 0, 0x1E, 0, 71, 7, 0x74, 48, 0, 0, 0, 0, 0xFE, 0])
	_eq([gs.script_value(71), unported], [7, ["SPAWN_ITEM"]], "an unported opcode skips its bytes, reported once")
	# WARP_TO without the field's map change: reported, the script ends.
	_run([0x4B, 5, 0, 0xFF, 0x1E, 0, 72, 1, 0xFE, 0])
	_eq([gs.script_value(72), ctx.is_paused, unported.back()], [0, true, "map change (WARP_TO)"],
			"WARP_TO before step 2: the script ends")


func _delay_and_text() -> void:
	gs.set_script_value(80, 0)
	var set_at := -1
	_run([0x67, 0, 3, 0, 0x1E, 0, 80, 1, 0xFE, 0], 0)
	for f in 6:
		_frame()
		if set_at < 0 and gs.script_value(80) == 1:
			set_at = f + 1
	_eq(set_at, 4, "DELAY 3: the next instruction runs on the 4th frame")
	# SET_DIALOG_OWNER none, SHOW_TEXTBOX "Ａ", END: the box waits for confirm, then the script ends.
	_run([0x1B, 0xFF, 0x1A, 0, 0x82, 0x60, 0x0D, 0, 0, 0, 0xFE, 0], 0)
	for f in 4:
		_frame()
	_eq([ctx.active_instruction, boxes.boxes[0].state], [ScriptContext.OP_SHOW_TEXTBOX, UIBoxes.STATE_OPEN], "the text waits")
	_frame(Pad.CONFIRM)
	_frame()
	_eq([ctx.is_paused, boxes.boxes[0].state], [true, UIBoxes.STATE_CLOSED], "confirm: the script ends, the box closes")
	# scriptPauseGame and the end of the script: the tamer still (6), the partner idle (11), time
	# stopped, script value 0 = 3; afterwards all back and script value 0 restored.
	var tamer := Tamer.new()
	var partner := Partner.new()
	var clock := Clock.new()
	clock.game_state = gs
	clock.running = true
	interp.tamer = tamer
	interp.partner = partner
	interp.clock = clock
	gs.set_script_value(0, 7)
	# ENTITY_SET_ROTATION (unported, pauses first), DELAY 2, END.
	_run([0x4D, 0xFD, 0, 8, 0x67, 0, 2, 0, 0xFE, 0])
	_eq([tamer.state, partner.state, clock.running, gs.script_value(0), tamer.camera_follow],
			[Tamer.STATE_STILL, Partner.STATE_IDLE, false, 3, false], "scriptPauseGame: the script takes over the field")
	for f in 4:
		_frame()
	_eq([ctx.is_paused, tamer.state, partner.state, clock.running, gs.script_value(0), tamer.camera_follow],
			[true, Tamer.STATE_FREE, Partner.STATE_NORMAL, true, 7, true], "the end of the script gives the field back")
	interp.tamer = null
	interp.partner = null
	interp.clock = null
	tamer.free()
	partner.free()
	clock.free()


## ENTITY_WALK_TO (specs/script.md §2.7): the walk animation and script state, the slot turning the
## actor to its point each frame, done on the point's tile; WAIT_FOR_ENTITY waits for it. The
## actors have no model here, so the test moves them.
func _walk_to() -> void:
	var tamer := Tamer.new()
	var partner := Partner.new()
	interp.tamer = tamer
	interp.partner = partner
	unported.clear()
	# ENTITY_WALK_TO tamer, x 1000, z 0, anim 0; WAIT_FOR_ENTITY tamer; END.
	_run([0x4E, 0xFD, 0xE8, 0x03, 0, 0, 0, 0, 0x4A, 0xFD, 0xFE, 0])
	_eq([tamer.state, tamer._script_animation, interp.movement[0], ctx.active_instruction],
			[Tamer.STATE_SCRIPT, 2, ScriptInterpreter.MOVE_WALK_TO, ScriptInterpreter.OP_WAIT_FOR_ENTITY],
			"ENTITY_WALK_TO: run animation (anim + 2), tamer state 10, slot 0 type 2; the script waits")
	_frame()
	_eq([tamer.direction, interp.movement[0], ctx.is_paused], [0xC00, ScriptInterpreter.MOVE_WALK_TO, false],
			"each frame the slot turns him to the point (+x = 0xC00)")
	tamer.position = Vector3(1050, 0, 0)
	_frame()
	_eq([interp.movement[0], tamer._script_animation, ctx.is_paused, tamer.state],
			[ScriptInterpreter.FREE, 0, true, Tamer.STATE_FREE],
			"on the point's tile: the slot is freed, animation 0, the wait ends and the script gives him back")
	# The partner: anim 1 -> (1 + 1) << 1 = 4 (run), state 12.
	_run([0x4E, 0xFC, 0, 0, 0xE8, 0x03, 1, 0, 0xFE, 0])
	_eq([interp.movement[1], partner.state], [ScriptInterpreter.MOVE_WALK_TO, Partner.STATE_NORMAL],
			"a walk the script doesn't wait for: the script ends, the field is given back, the slot stays set but isn't ticked (as in the C)")
	_run([0x4E, 0xFC, 0, 0, 0xE8, 0x03, 1, 0, 0x67, 0, 5, 0, 0xFE, 0])
	_eq([interp.movement[1], partner.state, interp.movement_args[1]["z"]],
			[ScriptInterpreter.MOVE_WALK_TO, Partner.STATE_SCRIPT, 1000], "the partner: slot 1, state 12")
	_force_end()
	# An NPC's walk without the entity table (tests/test_npc.gd has them): its bytes skipped.
	gs.set_script_value(73, 0)
	_run([0x4E, 0x05, 0, 0, 0, 0, 0, 0, 0x1E, 0, 73, 1, 0xFE, 0])
	_eq(gs.script_value(73), 1, "an NPC's walk without NPCs: bytes skipped, the script goes on")
	# Green Gym's walk-out (script 108, section 0x33): the tamer runs to (2200, -3000), then WARP_TO.
	if Content.load_json("scripts/index.json") != null:
		var warps := []
		interp.tick_map_change = func(map_id: int, _exit: int, _show: int) -> bool:
			warps.append([map_id, tamer.state, interp.movement[0], tamer.direction])
			return false
		tamer.position = Vector3(1800, 0, 3000)
		interp.call_section(108, 0x33)
		_frame()
		_frame()
		_eq(warps.size() > 0 and warps[0][1] == Tamer.STATE_SCRIPT and warps[0][2] == ScriptInterpreter.MOVE_WALK_TO
				and warps[0][3] == 0xC00, true,
				"Green Gym 0x33: during WARP_TO's fade he walks to (2200, -3000) (state 10, slot 0, facing +x): %s" % [warps])
		interp.tick_map_change = Callable()
		_force_end()
	interp.tamer = null
	interp.partner = null
	tamer.free()
	partner.free()


## Step 4's slot types without the camera (specs/script.md §2.7 "Step 4"): the moves slide by
## (target - position) / speed and keep the animation, the axis moves, a walk to an entity, the
## shared delta, the sync bit. The camera's (types 4-7, 15) are in tests/test_camera.gd.
func _step4() -> void:
	var tamer := Tamer.new()
	var partner := Partner.new()
	interp.tamer = tamer
	interp.partner = partner
	unported.clear()
	# ENTITY_MOVE_TO tamer, x 1005, z 0, speed 10, _; WAIT_FOR_ENTITY tamer; END.
	tamer._script_animation = 3
	_run([0x6C, 0xFD, 0xED, 0x03, 0, 0, 10, 0, 0x4A, 0xFD, 0xFE, 0])
	_frame()
	_eq([interp.movement[0], tamer.position.x], [ScriptInterpreter.MOVE_TO, 0.0],
			"ENTITY_MOVE_TO: slot 0 type 8; its first frame takes the delta (1005 / 10 = 100), nothing moves")
	var xs := []
	for f in 11:
		_frame()
		xs.append(int(tamer.position.x))
	_eq(xs, [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1005],
			"then 100 a frame; done past the point after 11 frames (the rounding's +1), set to it")
	_eq([interp.movement[0], ctx.is_paused, tamer._script_animation], [ScriptInterpreter.FREE, true, 3],
			"the slot is freed, the wait ends; a move keeps the animation (no startAnimation(0))")
	# ENTITY_MOVE_TO_AXIS tamer, -300, axis 1 (y), speed 3; WAIT; END: PSX y -100, -200, -300.
	tamer.position = Vector3.ZERO
	_run([0x72, 0xFD, 0xD4, 0xFE, 1, 3, 0x4A, 0xFD, 0xFE, 0])
	_frame()
	var ys := []
	for f in 3:
		_frame()
		ys.append(int(tamer.position.y))
	_eq([ys, ctx.is_paused], [[100, 200, 300], true], "ENTITY_MOVE_TO_AXIS on y: 3 steps of -100 (PSX y up), done on the value")
	# Two moves at once: slot 0 takes the delta and sets the shared "started" flag, so slot 1
	# skips its own first frame and moves by the tamer's delta (MOVE_TO_DELTA_X / Z).
	tamer.position = Vector3.ZERO
	partner.position = Vector3.ZERO
	_run([0x6C, 0xFD, 0xE8, 0x03, 0, 0, 10, 0, 0x6C, 0xFC, 0xD0, 0x07, 0, 0, 1, 0, 0x67, 0, 30, 0, 0xFE, 0])
	_frame()
	_eq([tamer.position.x, partner.position.x], [0.0, 100.0],
			"quirk: one MOVE_TO_DELTA for every slot: the partner's move (speed 1) starts with the tamer's 100")
	_force_end()
	interp._previous_camera_pos_initialized = false
	# ENTITY_WALK_TO_ENTITY tamer, anim 0, the partner; WAIT tamer; END. The target is taken every
	# frame; done on its tile.
	tamer.position = Vector3.ZERO
	partner.position = Vector3(1000, 0, 0)
	_run([0x51, 0xFD, 0, 0xFC, 0x4A, 0xFD, 0xFE, 0])
	_eq([interp.movement[0], tamer.state, tamer._script_animation], [ScriptInterpreter.MOVE_WALK_TO_ENTITY, Tamer.STATE_SCRIPT, 2],
			"ENTITY_WALK_TO_ENTITY: slot 0 type 3, the walk animation and script state")
	_frame()
	_eq(tamer.direction, 0xC00, "he faces the partner (+x)")
	partner.position = Vector3(-1000, 0, 0)
	_frame()
	_eq([tamer.direction, ctx.is_paused], [0x400, false], "the partner moved behind him: he turns to it (-x)")
	tamer.position = Vector3(-1020, 0, 0)
	_frame()
	_eq([interp.movement[0], tamer._script_animation, ctx.is_paused], [ScriptInterpreter.FREE, 0, true],
			"on the partner's tile: done, animation 0")
	# CALL_DIGIMON_ROUTINE 0 (the toilet): partner state 6, the sync bit cleared; WAIT_FOR_ENTITY
	# 0xC9 waits until the scene sets it (the partner has no model here, so the scene doesn't run).
	_run([0x49, 0, 0x4A, 0xC9, 0xFE, 0])
	_eq([partner.state, ctx.sync_bit, ctx.active_instruction], [Partner.STATE_TOILET, 0, ScriptInterpreter.OP_WAIT_FOR_ENTITY],
			"CALL_DIGIMON_ROUTINE 0: partner state 6, the sync bit 0, the wait")
	for f in 3:
		_frame()
	_eq(ctx.is_paused, false, "the wait holds while the bit is clear")
	ctx.sync_bit = 1
	_frame()
	_eq([ctx.is_paused, partner.state], [true, Partner.STATE_NORMAL], "the scene set the bit: the script ends, the partner is given back")
	# Another routine: reported, the bit stays set, the wait ends at once.
	gs.set_script_value(74, 0)
	_run([0x49, 3, 0x4A, 0xC9, 0x1E, 0, 74, 1, 0xFE, 0])
	_frame()
	_eq([gs.script_value(74), unported.has("CALL_DIGIMON_ROUTINE 3")], [1, true],
			"CALL_DIGIMON_ROUTINE 3 (not ported): reported, the wait on the bit ends at once")
	interp.tamer = null
	interp.partner = null
	tamer.free()
	partner.free()


## Map entry through MAPHEAD and a script's map change (specs/script.md §2.4, §3): the field's
## hooks are recorded here.
func _map_entry() -> void:
	if Content.load_json("scripts/index.json") == null:
		print("SKIP map entry: asset porter output missing")
		return
	var calls := []
	interp.load_map = func(map_id: int): calls.append(["load", map_id])
	interp.setup_map = func(): calls.append(["setup"])
	unported.clear()
	# MAYO04A (3): MAPHEAD section 3 = SET_SCRIPT 4, map 3, ...; at its end setupMap, then script 4's
	# section 0xFE (item spawns), then the end.
	interp.run_map_head(3)
	_eq([calls, ctx.current_script_id, ctx.current_screen_id], [[["load", 3], ["setup"]], 4, 3],
			"run_map_head: SET_SCRIPT loads the map, the section's end sets it up")
	_eq([ctx.code_id, ctx.is_paused], [4, true], "then the map's 0xFE section ran, and the script ended")
	# WARP_TO 3, exit 0, section 0x51: the map change (the field's, here two frames) runs the new
	# map's MAPHEAD section; the pushed type-4 entry then continues in script 4's section 0x51.
	var frames := [0]
	interp.tick_map_change = func(map_id: int, _exit: int, _show: int) -> bool:
		frames[0] += 1
		if frames[0] < 2:
			return false
		interp.run_map_head(map_id)
		return true
	calls.clear()
	_run([0x4B, 3, 0, 0x51, 0xFE, 0], 4)
	_eq([calls.size() > 0, ctx.code_id, ctx.active_instruction], [true, 4, ScriptContext.OP_DELAY],
			"WARP_TO: after the map change the script goes on in the new map's section 0x51 (its first DELAY)")
	_force_end()
	interp.load_map = Callable()
	interp.setup_map = Callable()
	interp.tick_map_change = Callable()


## Choice pointer -> how often the player came to it.
var _visits := {}


## One frame of a real section, played like a player: ✕ every other frame for texts; at a choice,
## the options in turn on each visit, then △ (so menus that come back, and "let me rethink" loops,
## are left through their other options or by cancelling).
func _player_frame(frames: int) -> void:
	if frames % 2 == 0:
		_frame(0)
		return
	var tb := interp.textboxes
	if ctx.active_instruction == ScriptContext.OP_SET_SELECTION and boxes.boxes[0].state == UIBoxes.STATE_OPEN:
		var key := "%d:%d" % [ctx.code_id, tb.selection["pointer"]]
		# The options in turn, then △ (some menus, e.g. Mr. Handy's, are only left by cancelling).
		var count: int = maxi(tb.selection["count"], 1)
		var want: int = _visits.get(key, 0) % (count + 1)
		if want < count and tb.selection["current"] != want:
			_frame(Pad.DOWN)
			return
		_frame(Pad.CONFIRM if want < count else Pad.CANCEL)
		# A visit counts once the choice took the press (it may still be flipping its page).
		if ctx.active_instruction != ScriptContext.OP_SET_SELECTION or "%d:%d" % [ctx.code_id, tb.selection["pointer"]] != key:
			_visits[key] = _visits.get(key, 0) + 1
		return
	_frame(Pad.CONFIRM)


## Ends a section that didn't end, as a script end would (boxes closed), for the next one; a map
## change it was in and its stack entries are dropped.
func _force_end() -> void:
	ctx.is_paused = true
	ctx.map_change = 0
	ctx.stack.clear()
	interp.textboxes.close_all_textboxes()
	for i in UIBoxes.COUNT:
		if boxes.boxes[i].registered:
			boxes.remove_static(i)


## Every section of MAPHEAD and of every DG script runs to its end: waits finish, texts are
## confirmed, choices are left. Sections that start with a text and no dialogue box (the caller
## sets the box up, e.g. tournament jump tables) would hang in the original too: they are listed
## apart. The C reads of the unported opcodes equal the asset porter's instruction sizes.
func _real_scripts() -> void:
	var index = Content.load_json("scripts/index.json")
	if not index is Dictionary:
		print("SKIP real scripts: asset porter output missing")
		return
	var size_bad := {}
	var sections := 0
	var unfinished := []
	var no_box := []
	var out_of_range := []
	unported.clear()
	for id in range(0, 222):
		var json = Content.load_json("scripts/MAPHEAD/script.json" if id == 0 else "scripts/DG/script_%03d.json" % id)
		if not json is Dictionary:
			continue
		for ins in json["instructions"]:
			var op := int(ins["op"])
			if ScriptInterpreter.UNPORTED.has(op) and 1 + int(ScriptInterpreter.UNPORTED[op][0]) != int(ins["size"]):
				size_bad[ins["name"]] = int(ins["size"])
		if id == 0:
			continue
		var seen := {}
		for s in json["header"]["sections"]:
			var section := int(s["id"])
			if seen.has(section):
				continue
			seen[section] = true
			sections += 1
			ctx.current_script_id = id
			interp.call_section(id, section, 1 if section < 0x33 else 0)
			var frames := 0
			while not ctx.is_paused and frames < 20000:
				_player_frame(frames)
				frames += 1
				if ctx.pointer < 0 or ctx.pointer > ctx.code.size():
					out_of_range.append("%d:0x%X" % [id, section])
					break
			if not ctx.is_paused:
				var where := "%d:0x%X in %d at %d (op 0x%02X, waiting 0x%02X)" % [id, section, ctx.code_id,
						ctx.pointer, ctx.byte_at(ctx.pointer), ctx.active_instruction]
				if ctx.active_instruction == ScriptContext.OP_SHOW_TEXTBOX and interp.textboxes.entries[0].vram_rows == 0:
					no_box.append(where)
				else:
					unfinished.append(where)
				_force_end()
	# The MAPHEAD map sections, as the map entry runs them (with the map's 0xFE section after).
	var map_sections := 0
	for m in index["maps"]:
		ctx.current_script_id = int(m["script"])
		interp.call_section(0, int(m["maphead_section"]), 1)
		map_sections += 1
		var frames := 0
		while not ctx.is_paused and frames < 20000:
			_player_frame(frames)
			frames += 1
		if not ctx.is_paused:
			unfinished.append("MAPHEAD 0x%X" % int(m["maphead_section"]))
			_force_end()
	_eq(size_bad, {}, "the C's argument bytes of the unported opcodes equal the instruction sizes")
	_eq(out_of_range, [], "no section's pointer leaves its script")
	_eq(unfinished, [], "all %d sections and %d map setups end" % [sections, map_sections])
	# Only the arena registration jump tables (section 0xA: a SWITCH target list, entered after
	# their caller set the dialogue owner) start with a text and no box.
	_eq(no_box.map(func(w: String): return w.get_slice(" ", 0)), ["102:0xA", "168:0xA", "209:0xA", "213:0xA"],
			"the only sections that need their caller's dialogue box")
	print("unported in the real scripts: ", ", ".join(unported))
	if not unfinished.is_empty():
		print("unfinished: ", unfinished)
	print("sections that need a dialogue box from their caller: ", no_box)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])
