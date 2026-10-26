extends SceneTree
## Training (scripts/systems/training.gd, scripts/ui/training_stats_box.gd, scripts/training/,
## scripts/script/training_routines.gd, scripts/field/cloud_fx.gd; specs/training.md): the gains,
## the hour, the stats box, builtins 0x07 / 0x27, the stations (HP, and 4d-2: Offense, Speed, Defense,
## MP, Brains) with a stub walker, the Brains boxes and move learning, the sparks.
##   godot --headless --path . -s res://tests/test_training.gd
## Exits 1 if a check fails.

## The interpreter with a walker that arrives when told to.
class FakeInterpreter extends ScriptInterpreter:
	var arrive := true
	var walks: Array = []

	func tick_walk_to(script_id: int, target_id: int, x: int, z: int, _use_camera := false) -> bool:
		walks.append([script_id, target_id, x, z])
		return arrive


## Records playSound calls; every sound "uses" voice mask 7.
class FakeSound extends Node:
	var played: Array = []
	var stopped: Array = []

	func play_sound(slot: int, value: int) -> int:
		played.append([slot, value])
		return 7

	func stop_sound_mask(mask: int) -> void:
		stopped.append(mask)


var _failed := 0
var _checks := 0
var _started := false
var data: Node
var gs: Node
var clock: Clock
var training: Training


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: porter output missing")
		quit(0)
		return false
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()
	clock = Clock.new()
	clock.game_state = gs
	training = Training.new()
	training.game_state = gs
	training.data = data
	training.clock = clock
	_multiplier()
	_hp_gains()
	_hour()
	_stats_box()
	_overlays()
	_clouds()
	_routine_and_station()
	_awards()
	_brains_thresholds()
	_learn_move()
	_sparks()
	_station_choice()
	_offense()
	_speed()
	_defense()
	_mp()
	_brains()
	clock.free()
	gs.free()
	data.free()
	print("%s: training checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _care() -> Dictionary:
	return gs.state["partner"]["care"]


func _clear_bonuses() -> void:
	for t in [Training.TRIGGER_REVISION_A, Training.TRIGGER_REVISION_B]:
		gs.clear_trigger(t)
	for counter in Training.UPGRADE_COUNTERS:
		_care()[counter] = 0
	var slots: Array = gs.state["inventory"]["slots"]
	for i in slots.size():
		slots[i] = null
	_care()["train_boost_flag"] = 0
	_care()["train_boost_value"] = 0
	_care()["tiredness"] = 0


## A Digimon of a level and training type, from the data.
func _digimon_with(level: int, training_type: int) -> String:
	for record in data.records("digimon/digimon_data"):
		var key := str(record.get("key", ""))
		if key == "" or int(record.get("level", {}).get("id", -1)) != level:
			continue
		var raise: Dictionary = data.entity("digimon", key).get("care", {}).get("raise", {})
		if not raise.is_empty() and int(raise.get("training_type", -1)) == training_type:
			return key
	return ""


func _multiplier() -> void:
	_clear_bonuses()
	_check(Training.type_factor(Training.MODE_HP, 0) == 10 and Training.type_factor(Training.MODE_HP, 2) == 9
			and Training.type_factor(Training.MODE_HP, 3) == 11 and Training.type_factor(Training.MODE_HP, 4) == 8,
			"HP / Defense: 10 for types 0-1, 9 for 2, 11 for 3, 8 else")
	_check(Training.type_factor(Training.MODE_MP, 1) == 9 and Training.type_factor(Training.MODE_BRAINS, 2) == 11
			and Training.type_factor(Training.MODE_MP, 3) == 10, "MP / Brains: 9 for 1, 11 for 2, 10 for 0 and 3")
	_check(Training.type_factor(Training.MODE_OFFENSE, 1) == 11 and Training.type_factor(Training.MODE_SPEED, 3) == 9
			and Training.type_factor(Training.MODE_SPEED, 2) == 10, "Offense / Speed: 11 for 1, 9 for 3")
	var rookie := _digimon_with(3, 0)
	_check(rookie != "", "a Rookie of training type 0 exists")
	_check(training.multiplier(rookie, Training.MODE_HP, 0) == 10, "Rookie, type 0, HP: 10 (x1)")
	gs.set_trigger(Training.TRIGGER_REVISION_A)
	_check(training.multiplier(rookie, Training.MODE_HP, 0) == 12, "revision 0xDB: x 6 / 5 = 12")
	_check(training.multiplier(rookie, Training.MODE_HP, 1) == 10, "no bonus with flag != 0")
	_check(training.multiplier(rookie, Training.MODE_MP, 0) == 10, "0xDB doesn't touch MP")
	gs.set_trigger(Training.TRIGGER_REVISION_B)
	_check(training.multiplier(rookie, Training.MODE_MP, 0) == 12, "0xFB for MP")
	_care()["upgrade_hp_counter"] = 10
	_check(training.multiplier(rookie, Training.MODE_HP, 0) == 14, "and the counter: 10 x 36 / 25 = 14 (truncated)")
	_clear_bonuses()
	gs.give_item("dw1:trn_manual", 1)
	_check(training.multiplier(rookie, Training.MODE_HP, 0) == 11, "the Trn. manual: x 11 / 10")
	var champion := _digimon_with(4, 3)
	if champion != "":
		_check(training.multiplier(champion, Training.MODE_HP, 0) == 13, "Champion, type 3, HP, manual: 1331 / 100 = 13")
	var baby := _digimon_with(2, 0)
	_clear_bonuses()
	if baby != "":
		_check(training.multiplier(baby, Training.MODE_HP, 0) == 9, "In-Training: x 9 / 10")


func _set_partner(key: String) -> void:
	gs.state["partner"]["digimon"] = key


func _hp_gains() -> void:
	_clear_bonuses()
	var rookie := _digimon_with(3, 0)
	_set_partner(rookie)
	var stats: Dictionary = gs.state["partner"]["stats"]["base"]
	stats["max_hp"] = 500
	stats["offense"] = 50
	training.save_start_time()
	training.award_hp_gains(rookie, 0, 10)
	_check(training.gains == [80, 0, 2, 0, 0, 0], "Rookie: HP + 80, Offense + 2 (%s)" % [training.gains])
	_check(training.base[Training.HP] == 500 and int(stats["max_hp"]) == 500, "the copy is saved, the partner unchanged")
	_care()["train_boost_flag"] = Training.BOOST_HP
	_care()["train_boost_value"] = 15
	_care()["tiredness"] = 0
	training.save_start_time()
	training.award_hp_gains(rookie, 0, 10)
	_check(training.gains[Training.HP] == 120 and training.gains[Training.OFFENSE] == 2, "boost 0x10 x 15: HP 120")
	_care()["train_boost_flag"] = 0
	_care()["tiredness"] = Training.TIRED_MAX
	training.save_start_time()
	training.award_hp_gains(rookie, 0, 10)
	_check(training.gains == [1, 0, 1, 0, 0, 0], "tiredness 100: 1 and 1")
	_care()["tiredness"] = 0
	training.save_start_time()
	training.award_hp_gains(rookie, 0, 200)
	_check(training.gains[Training.HP] == Training.GAIN_CAP, "HP capped at 999 (%d)" % training.gains[Training.HP])


func _hour() -> void:
	_clear_bonuses()
	var c := _care()
	var ck: Dictionary = gs.state["clock"]
	ck["hour"] = 10
	ck["minute"] = 23
	ck["frame"] = 10 * 1200 + 23 * 20
	ck["day"] = 3
	c["condition"] = 0
	c["tiredness"] = 20
	c["happiness"] = 90
	c["discipline"] = 50
	c["energy_level"] = 40
	c["food_level"] = 100
	c["poop_level"] = 30
	c["remaining_lifetime"] = 200
	c["evo_timer"] = 5
	var raise: Dictionary = data.entity("digimon", gs.state["partner"]["digimon"]).get("care", {}).get("raise", {})
	training.save_start_time()
	ck["minute"] = 24
	training.advance_time(10, 1, 1)
	_check(int(ck["hour"]) == 11 and int(ck["minute"]) == 24 and int(ck["frame"]) == 11 * 1200 + 23 * 20,
			"an hour from the start, the minute kept (%s)" % [ck])
	_check(int(c["tiredness"]) == 30 and int(c["happiness"]) == 89 and int(c["energy_level"]) == 39 - int(raise.get("energy_usage", 0)),
			"tiredness + 10, happiness - 1, energy - 1 - usage")
	_check(int(c["food_level"]) == 40 and int(c["poop_level"]) == 24, "food - 60, poop - 6")
	_check(int(c["remaining_lifetime"]) == 199 and int(c["evo_timer"]) == 6, "lifetime - 1, evolution timer + 1")
	c["tiredness"] = 70
	c["discipline"] = 50
	training.save_start_time()
	training.advance_time(0, 0, 0)
	_check(int(c["happiness"]) == 86 and int(c["discipline"]) == 47, "tiredness 70: happiness and discipline - 3")
	ck["hour"] = 23
	ck["day"] = 30
	var age := int(c["age"])
	var shop_before: Array = gs.state["script"]["card_shop"].duplicate()
	Rng.set_seed(3)
	training.save_start_time()
	training.advance_time(0, 0, 0)
	_check(int(ck["hour"]) == 0 and int(c["age"]) == age + 1, "23 h -> 0 h, age + 1")
	_check(int(ck["day"]) == 0 and int(ck["year"]) == 1, "day 31 rolls over (the training's own rule): day 0, year 1")
	_check(gs.state["script"]["card_shop"] != shop_before, "a new day: the card shop is re-rolled")
	ck["hour"] = 15
	clock.current_time_of_day = Clock.TIME_DAY
	var transitions := []
	clock.daytime_transition.connect(func(p): transitions.append(p))
	training.save_start_time()
	training.advance_time(0, 0, 0)
	_check(transitions == [Clock.PALETTE[Clock.TIME_EVENING]], "16 h: the evening transition")


func _stats_box() -> void:
	var boxes := UIBoxes.new()
	root.add_child(boxes)
	var area := TextArea.new(data, "en_us")
	var pad := Pad.new()
	var box := TrainingStatsBox.new()
	box.training = training
	box.boxes = boxes
	box.text_area = area
	box.pad = pad
	box.data = data
	var sounds := []
	boxes.sound.connect(func(id): sounds.append(id))
	training.base = [500, 100, 50, 50, 50, 50]
	training.gains = [3, 0, 2, 0, 0, 0]
	box.create()
	_check(boxes.boxes[1].state == UIBoxes.STATE_OPENING and box.gained == [true, false, true, false, false, false],
			"the box opens; HP and Offense gained")
	# The box ticks once it is open (5 frames), so the 100 frames' delay starts then.
	for i in 104:
		pad.poll(0)
		pad.process()
		boxes.step()
	_check(training.base[0] == 500 and box.delay == 1, "nothing counts for 100 frames after the opening (%d)" % box.delay)
	sounds.clear()
	for i in 4:
		pad.poll(0)
		pad.process()
		boxes.step()
	_check(training.base[0] == 503 and training.base[2] == 51 and sounds.count(TrainingStatsBox.COUNT_SOUND) == 4,
			"one point a frame, HP first, with its sound (%s)" % [training.base])
	training.gains = [0, 0, 10, 0, 0, 0]
	pad.poll(Pad.CONFIRM)
	pad.process()
	boxes.step()
	_check(training.base[2] == 61 and training.gains[2] == 0, "✕: every gain at once")
	_check(box.done, "done stays set until the next box (MAIN_D_80135394)")
	box.done = false
	training.gains = [20, 0, 0, 0, 0, 0]
	training.base[0] = 9990
	pad.poll(Pad.CONFIRM)
	pad.process()
	boxes.step()
	_check(training.gains[0] == 19, "✕ held from before: no finish, the count goes on")
	pad.poll(0)
	pad.process()
	pad.poll(Pad.CANCEL)
	pad.process()
	boxes.step()
	_check(training.base[0] == 9999, "△ alone finishes; HP capped at 9999")
	_check(training.gains_are_zero(), "all gains counted")
	box.close()
	boxes.free()


func _overlays() -> void:
	var o := MapOverlays.new()
	for k in 4:
		o._instances.append({"x": 10 * k, "y": 100, "flag": 0x10, "frame": -1, "sprites": [], "node": null})
	var saved := o.store_positions(1, 2)
	o.move(1, 2, 3, -2)
	_check(o.instance(1)["x"] == 13 and o.instance(2)["y"] == 98 and o.instance(0)["x"] == 0, "move: only the range moves")
	o.load_positions(saved, 1)
	_check(o.instance(1)["x"] == 10 and o.instance(2)["x"] == 20 and o.instance(1)["flag"] == 0, "load: back, flag bit 0x10 off")
	o.free()


func _clouds() -> void:
	var fx := CloudFX.new()
	for i in 70:
		fx.create(i, i)
	_check(fx.active_count() == CloudFX.SLOTS, "60 slots at most")
	for i in 13:
		fx.tick()
	_check(fx.active_count() == CloudFX.SLOTS, "alive for 13 frames")
	fx.tick()
	_check(fx.active_count() == 0, "freed at state 14")
	fx.create(0, 0)
	fx.remove_all()
	_check(fx.active_count() == 0, "remove_all")
	var made := []
	Rng.set_seed(1)
	Training.cloud_line(0x14 * 6, 0x14, 0x5B5, -0x667, 0x32, -0x32, 6, func(x, z): made.append([x, z]))
	_check(made.size() == 6, "a dust line of 6 on its frame")
	made.clear()
	Training.cloud_line(0x14 * 6 + 1, 0x14, 0x5B5, -0x667, 0x32, -0x32, 6, func(x, z): made.append([x, z]))
	_check(made.is_empty(), "none between")
	fx.free()


func _routine_and_station() -> void:
	_clear_bonuses()
	var boxes := UIBoxes.new()
	root.add_child(boxes)
	var area := TextArea.new(data, "en_us")
	var ctx := ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	var pad := Pad.new()
	var tb := TextBoxes.new(boxes, area, ctx, pad, data, gs)
	var files := ScriptFiles.new()
	var interp := FakeInterpreter.new(ctx, files, tb)
	interp.game_state = gs
	interp.data = data
	interp.clock = clock
	var field := FieldMap.new()
	interp.field = field
	var o := field.overlays
	for k in 0x70:
		o._instances.append({"x": 200, "y": 100, "flag": 0, "frame": -1, "sprites": [], "node": null})
	var sound := FakeSound.new()
	var routines := ScriptRoutines.new()
	var node: TrainingRoutines = load("res://scenes/script/training_routines.tscn").instantiate()
	routines.add_child(node)
	root.add_child(routines)
	routines.configure(ctx, tb, gs, data, sound)
	routines.interpreter = interp
	routines.clouds = CloudFX.new()
	interp.routines = routines
	var rookie := _digimon_with(3, 0)
	_set_partner(rookie)
	var stats: Dictionary = gs.state["partner"]["stats"]["base"]
	stats["max_hp"] = 500
	stats["offense"] = 50
	# 0x27, then value 0xFE = 0, value 0xF6 = 0, 0x07, value 50 = 1, END.
	ctx.current_screen_id = 0x70
	gs.set_script_value(50, 0)
	var code := [0x64, 0x27, 0x1E, 0, 0xFE, 0, 0x1E, 0, 0xF6, 0, 0x64, 0x07, 0x1E, 0, 50, 1, 0xFE, 0]
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code))
	files._cache[500] = bytes
	interp.call_section(500, 1)
	var frame := func(buttons := 0):
		pad.poll(buttons)
		pad.process()
		interp.tick_script()
		routines.tick_objects()
		routines.clouds.tick()
		boxes.step()
	frame.call()
	var station := node.station
	_check(station is HpBoulderStation and station.running, "0x07 on map 0x70 with stat 0: the HP station starts")
	_check(ctx.active_instruction == ScriptContext.OP_CALL_ROUTINE and gs.script_value(50) == 0, "the script waits")
	interp.arrive = false
	frame.call()
	frame.call()
	_check(station.state == 1 and sound.played.has([8, HpBoulderStation.SOUND_START]), "state 1: walking, the start sound")
	_check(interp.walks[-1] == [ScriptContext.OWNER_PARTNER, ScriptInterpreter.FREE, 0x58C, -0x6D0], "to the boulder")
	interp.arrive = true
	frame.call()
	_check(station.state == 2, "there: pushing")
	var x0: int = o.instance(0x53)["x"]
	for i in 120:
		frame.call()
	_check(station.counter == 120, "120 frames pushed (%d)" % station.counter)
	_check(o.instance(0x53)["x"] == x0 + 1 and o.instance(0x53)["y"] == 98 and o.instance(0x62)["y"] == 98
			and o.instance(0x63)["y"] == 100, "one push: (+1, -2) for the 16 instances, the shake back to even")
	_check(routines.clouds.active_count() > 0, "dust rises")
	frame.call(Pad.CANCEL)
	_check(station.state == 3 and station.counter == 1, "△ held: the end, 1 push (%d)" % station.counter)
	_check(node.training.gains == [80, 0, 2, 0, 0, 0] and boxes.boxes[1].state != UIBoxes.STATE_CLOSED,
			"the gains, the box (%s, box %d)" % [node.training.gains, boxes.boxes[1].state])
	var hour := int(gs.state["clock"]["hour"])
	for i in 400:
		frame.call()
		if gs.script_value(50) == 1:
			break
	_check(gs.script_value(50) == 1, "the box counts, the partner walks back, the script goes on")
	_check(int(stats["max_hp"]) == 580 and int(stats["offense"]) == 52, "the stats applied: 580 / 52")
	_check(o.instance(0x53)["x"] == 200 and o.instance(0x53)["y"] == 100, "the boulder back in place")
	_check(not station.running and node.station == null and routines.clouds.active_count() == 0, "done, no dust")
	_check(int(gs.state["clock"]["hour"]) == hour, "the hour was spent at the award (%d)" % hour)
	# Another map: nothing starts, the script waits.
	ctx.current_screen_id = 0x01
	gs.set_script_value(50, 0)
	interp.call_section(500, 1)
	for i in 5:
		frame.call()
	_check(node.station == null and ctx.active_instruction == ScriptContext.OP_CALL_ROUTINE and gs.script_value(50) == 0,
			"no station for the map: the script waits")
	ctx.active_instruction = 0
	routines.free()
	boxes.free()
	field.free()
	sound.free()


# --- 4d-2 (specs/training.md §6) ---------------------------------------------------------------

func _awards() -> void:
	_clear_bonuses()
	var rookie := _digimon_with(3, 0)
	_set_partner(rookie)
	var cases := [["offense", 0, [0, 0, 8, 0, 2, 0]], ["offense", 6, [10, 0, 8, 0, 0, 0]],
			["speed", 0, [10, 0, 0, 0, 8, 0]], ["speed", 6, [10, 0, 0, 0, 8, 0]], ["defense", 0, [0, 0, 0, 8, 0, 2]],
			["mp", 0, [0, 80, 0, 2, 0, 0]], ["brains", 0, [0, 10, 0, 0, 0, 8]], ["brains", 9, [0, 0, 0, 0, 0, 15]],
			["offense", 3, [0, 0, 0, 0, 0, 0]]]
	for c in cases:
		training.save_start_time()
		training.call("award_%s_gains" % c[0], rookie, c[1], 10)
		_check(training.gains == c[2], "%s b %d: %s (%s)" % [c[0], c[1], c[2], training.gains])
	var tired := int(_care()["tiredness"])
	training.save_start_time()
	training.award_offense_gains(rookie, 0, 10)
	_check(int(_care()["tiredness"]) == tired + 9, "Offense costs 9 tiredness")
	_clear_bonuses()
	gs.set_trigger(Training.TRIGGER_REVISION_B)
	training.award_offense_gains(rookie, 0, 10)
	_check(training.gains == [0, 0, 9, 0, 2, 0], "0xFB: Offense x 12 / 10 (%s)" % [training.gains])
	training.award_offense_gains(rookie, 6, 10)
	_check(training.gains == [10, 0, 8, 0, 0, 0], "Gear Savanna (b 6): no revision bonus")
	_clear_bonuses()
	_care()["upgrade_brain_counter"] = 10
	training.award_brains_gains(rookie, 0, 10)
	_check(training.gains == [0, 10, 0, 0, 0, 8], "Brains ignores its own counter (mode 1)")
	_care()["upgrade_mp_counter"] = 10
	training.award_brains_gains(rookie, 0, 10)
	_check(training.gains == [0, 12, 0, 0, 0, 9], "and takes the MP counter (%s)" % [training.gains])
	_clear_bonuses()
	_care()["train_boost_flag"] = Training.BOOST_SPEED
	_care()["train_boost_value"] = 20
	training.award_offense_gains(rookie, 0, 10)
	_check(training.gains == [0, 0, 8, 0, 4, 0], "boost 0x04 x 20 doubles Offense's Speed")
	_clear_bonuses()
	_care()["tiredness"] = Training.TIRED_MAX
	training.award_offense_gains(rookie, 0, 10)
	var off0 := training.gains.duplicate()
	_care()["tiredness"] = Training.TIRED_MAX
	training.award_offense_gains(rookie, 6, 10)
	_check(off0 == [0, 0, 1, 0, 1, 0] and training.gains == [1, 0, 1, 0, 0, 0], "tiredness 100: 1s by variant")
	_care()["tiredness"] = Training.TIRED_MAX
	training.award_brains_gains(rookie, 9, 10)
	_check(training.gains == [0, 0, 0, 0, 0, 1], "Brains b 9 tired: Brains 1 only")
	_clear_bonuses()
	training.award_mp_gains(rookie, 0, 200)
	_check(training.gains[Training.MP] == Training.GAIN_CAP and training.gains[Training.DEFENSE] == 40, "MP capped at 999")


func _brains_thresholds() -> void:
	_check(Training.new_orders(95, 103) == [["TRN_D_8008F0D8"]], "100: Give it all you got!")
	_check(Training.new_orders(290, 310) == [["TRN_D_8008F100", "TRN_D_8008F10C"]], "300: two lines")
	_check(Training.new_orders(195, 410).size() == 3 and Training.new_orders(100, 108).is_empty(), "each crossed, in order")
	_check(Training.teaches_technique(145, 153) and Training.teaches_technique(990, 999)
			and not Training.teaches_technique(100, 108), "the technique thresholds and 999")
	var boxes := UIBoxes.new()
	root.add_child(boxes)
	var area := TextArea.new(data, "en_us")
	area.clear_all()
	var box := TrainingBrainsBox.new()
	box.boxes = boxes
	box.text_area = area
	box.data = data
	box.show_orders(Training.new_orders(290, 310))
	_check(boxes.boxes[2].state == UIBoxes.STATE_OPENING and boxes.boxes[2].final == TrainingBrainsBox.ORDERS_RECT,
			"box 2 opens for the orders")
	_check(_row_inked(area, 0x78) and _row_inked(area, 0x84) and _row_inked(area, 0x94),
			"the orders at 0x78 / 0x84, New orders! at 0x94")
	for i in 6:
		boxes.step()
	box.close()
	_check(boxes.boxes[2].state == UIBoxes.STATE_CLOSING, "it closes at the end")
	for i in 6:
		boxes.step()
	area.clear_all()
	box.show_mastered(2)
	_check(box.name_length == data.text_entry("main/item", "MOVE_NAMES", 2).length()
			and boxes.boxes[2].final == TrainingBrainsBox.MASTERED_RECT and _row_inked(area, 0x84), "mastered: name, length, box")
	boxes.free()


func _row_inked(area: TextArea, y: int) -> bool:
	for x in 200:
		for dy in 11:
			if area.pixel(x, y + dy) != 0:
				return true
	return false


func _learn_move() -> void:
	gs.new_game()
	var agumon := "dw1:agumon"
	_set_partner(agumon)
	Rng.set_seed(5)
	for m in [2, 5, 0x2B]:
		gs.unlearn_move(m)
	# Fire's first candidate is Spit Fire (2), rank 0 of the first slot: weight 0. Sonic Jab (0x2B,
	# battle, rank 0 of slot 2, 10 %) wins.
	var learnt := _learn_until(agumon)
	_check(learnt == 0x2B, "without Spit Fire: Sonic Jab (%d)" % learnt)
	gs.unlearn_move(0x2B)
	gs.learn_move(2)
	# Spit Fire known: Heat Laser (5, rank 1, 25 %) beats Sonic Jab.
	learnt = _learn_until(agumon)
	_check(learnt == 5 and gs.has_move(5), "with Spit Fire: Heat Laser (%d)" % learnt)
	for m in data.digimon(agumon)["c"]["moves"]:
		if int(m) != 0xFF:
			gs.learn_move(int(m))
	var none := true
	for i in 50:
		if training.try_learn_move(agumon) != -1:
			none = false
	_check(none, "nothing left to learn: never")
	gs.new_game()


func _learn_until(digimon: String) -> int:
	for i in 200:
		var learnt := training.try_learn_move(digimon)
		if learnt >= 0:
			return learnt
	return -1


func _sparks() -> void:
	var fx := ParticleFX.new()
	for i in 6:
		fx.create(0, 0, Vector3i(0, -100, 0))
	_check(fx.active_count() == ParticleFX.SLOTS, "4 slots at most")
	for i in 0x13 - 1:
		fx.tick()
	_check(fx.active_count() == 4 and fx.effects[0]["state"] == 0x12 and fx.effects[0]["color"] == [0xFF, 0x6E, 0x46],
			"alive until its timer; kind 0's colour")
	fx.tick()
	_check(fx.active_count() == 0, "freed at state 0x13 (end frame < 0)")
	_check(ParticleFX.lerp_c(0xFF, 0, 0, 0x13, 0) == 0xFF and ParticleFX.lerp_c(0xFF, 0, 0, 0x13, 5) == 0xBC
			and ParticleFX.lerp_c(0, 0x6E, 0, 0x13, 0x13) == 0x6E
			and ParticleFX.lerp_c(0, 0x6E, 0, 0x13, 0) == 0, "lerp with the C's remainder")
	_check(fx.directions.size() == ParticleFX.PARTICLES, "50 particle directions")
	_check(ParticleFX.burst_factor(0x13, 0) == 0 and ParticleFX.burst_factor(0x13, 0x12) == 30,
			"the burst grows: state 0x12, _sin(104 of 512) >> 7 = 30 (%d)" % ParticleFX.burst_factor(0x13, 0x12))
	fx.create(9, 0, Vector3i.ZERO)
	fx.create(0, 5, Vector3i.ZERO)
	_check(fx.active_count() == 0, "an unknown kind or mode: nothing")
	fx.free()


## The routines scene on a field with overlays, a partner and a tamer; the stations walk at once.
func _rig() -> Dictionary:
	var r := {}
	r.boxes = UIBoxes.new()
	root.add_child(r.boxes)
	var area := TextArea.new(data, "en_us")
	r.ctx = ScriptContext.new()
	r.ctx.game_state = gs
	r.ctx.data = data
	r.pad = Pad.new()
	var tb := TextBoxes.new(r.boxes, area, r.ctx, r.pad, data, gs)
	r.interp = FakeInterpreter.new(r.ctx, ScriptFiles.new(), tb)
	r.interp.game_state = gs
	r.interp.data = data
	r.interp.clock = clock
	r.field = FieldMap.new()
	r.interp.field = r.field
	r.partner = Partner.new()
	r.tamer = Tamer.new()
	r.interp.partner = r.partner
	r.interp.tamer = r.tamer
	r.o = r.field.overlays
	for k in 0xC0:
		r.o._instances.append({"x": 200, "y": 100, "flag": 0, "frame": -1, "timer": 0, "sprites": [], "node": null})
	r.sound = FakeSound.new()
	r.routines = ScriptRoutines.new()
	r.node = load("res://scenes/script/training_routines.tscn").instantiate()
	r.routines.add_child(r.node)
	root.add_child(r.routines)
	r.routines.configure(r.ctx, tb, gs, data, r.sound)
	r.routines.interpreter = r.interp
	r.routines.clouds = CloudFX.new()
	r.routines.sparks = ParticleFX.new()
	r.interp.routines = r.routines
	_clear_bonuses()
	_set_partner(_digimon_with(3, 0))
	return r


func _free_rig(r: Dictionary) -> void:
	r.routines.clouds.free()
	r.routines.sparks.free()
	r.routines.free()
	r.boxes.free()
	r.field.free()
	r.sound.free()
	r.partner.free()
	r.tamer.free()


## Builtin 0x07's setup on a map with value 0xFE = stat: the station started, or null.
func _start(r: Dictionary, map_id: int, stat: int) -> TrainingStation:
	r.ctx.current_screen_id = map_id
	gs.set_script_value(TrainingRoutines.PSTAT_STAT, stat)
	gs.set_script_value(TrainingRoutines.PSTAT_SLOTS, 0)
	r.node.station = null
	r.node.start(TrainingRoutines.TRAINING)
	return r.node.station


## One frame of the station (and the box, the dust and the sparks), with `buttons` held.
func _frame(r: Dictionary, buttons := 0) -> void:
	r.pad.poll(buttons)
	r.pad.process()
	r.routines.tick_objects()
	r.routines.clouds.tick()
	r.routines.sparks.tick()
	r.boxes.step()


## Frames until the station is done (at most `limit`); true when it finished.
func _run_out(r: Dictionary, station: TrainingStation, limit := 600) -> bool:
	for i in limit:
		_frame(r)
		if not station.running:
			return true
	return false


func _station_choice() -> void:
	var r := _rig()
	var expected := [[0x70, Training.STAT_OFFENSE, "OffenseStation", false],
			[0x70, Training.STAT_SPEED, "SpeedStation", false], [0x70, Training.STAT_DEFENSE, "DefenseStation", false],
			[0x70, Training.STAT_MP, "MpStation", false], [0x70, Training.STAT_BRAINS, "BrainsStation", false],
			[0x4E, Training.STAT_OFFENSE, "OffenseStation", true], [0x4E, Training.STAT_SPEED, "SpeedStation", true],
			[0x77, Training.STAT_BRAINS, "BrainsStation", true]]
	for e in expected:
		var s := _start(r, e[0], e[1])
		var variant := false
		if s is OffenseStation:
			variant = s.special
		elif s is SpeedStation:
			variant = not s.wrap_x
		elif s is BrainsStation:
			variant = s.with_npc
		_check(s != null and s.get_script().get_global_name() == e[2] and variant == e[3],
				"map 0x%x, 0xFE %d: %s" % [e[0], e[1], e[2]])
		if s != null:
			s.running = false
	_check(_start(r, 0x4E, Training.STAT_MP) == null, "no MP station on Gear Savanna")
	var before := int(_care()["upgrade_off_counter"])
	_start(r, 0x4E, Training.STAT_OFFENSE).running = false
	_check(int(_care()["upgrade_off_counter"]) == before, "Gear Savanna doesn't train the counter")
	_free_rig(r)


func _offense() -> void:
	var r := _rig()
	var s: OffenseStation = _start(r, 0x70, Training.STAT_OFFENSE)
	var strike: Dictionary = data.training_animation(gs.state["partner"]["digimon"])
	_check(not strike.is_empty(), "the partner has a strike")
	_frame(r)
	_check(s.state == 1 and r.tamer.state == Tamer.STATE_TRAINING and not r.tamer.camera_follow, "state 1; tamer 8, no follow")
	_frame(r)
	_check(s.state == 2 and r.partner.step_blocked and r.partner.direction == 0x200, "at the tree: striking, held")
	for i in int(strike["hit_frame"]):
		_frame(r)
	_check(s.state == 3 and r.routines.sparks.active_count() == 3 and r.sound.played.has([8, OffenseStation.SOUND_HIT]),
			"the hit: three sparks, sound 5")
	_frame(r)
	_check(r.o.instance(0x64)["x"] == 196 and r.o.instance(0x6B)["y"] == 102 and r.o.instance(0x6C)["x"] == 200,
			"the tree shakes (-4, +2), only its 8 sprites")
	_frame(r, Pad.CANCEL)
	_check(s.state == 4 and s.training.gains == [0, 0, 8, 0, 2, 0] and r.o.instance(0x64)["x"] == 200,
			"△ after a hit: the gains, the tree back")
	_check(_run_out(r, s), "the box counts, the partner walks back")
	_check(r.tamer.state == Tamer.STATE_FREE and r.partner.state == Partner.STATE_NORMAL and r.tamer.camera_follow,
			"tamer 0, partner 1, follow on")
	var sp: OffenseStation = _start(r, 0x4E, Training.STAT_OFFENSE)
	_frame(r)
	_frame(r)
	_check(sp.state == 7 and r.partner.direction == 0x800, "Striking Special: state 7")
	for i in int(strike["hit_frame"]):
		_frame(r)
	_check(sp.state == 8 and r.o.instance(0x27)["flag"] == 1 and r.o.instance(0x2B)["flag"] == 0
			and r.o.instance(0x48)["flag"] == 0, "the hit: 0x27 x 4 hidden, 0x2B x 0x1E shown")
	for i in OffenseStation.SPECIAL_FRAMES:
		_frame(r)
	_check(sp.state == 7 and r.o.instance(0x27)["flag"] == 0 and r.o.instance(0x2B)["flag"] == 1, "0x2E later: back")
	sp.running = false
	_free_rig(r)


func _speed() -> void:
	var r := _rig()
	var s: SpeedStation = _start(r, 0x70, Training.STAT_SPEED)
	_frame(r)
	_frame(r)
	_check(s.state == 2 and r.partner.direction == 0xC00, "running, rotation 0xC00")
	r.partner.on_screen = true
	r.partner.position.x = 500
	for i in 0x3C:
		_frame(r)
	_check(r.partner.position.x == 500, "on screen: no wrap")
	r.partner.on_screen = false
	for i in 0x3B:
		_frame(r)
	_check(r.partner.position.x == 500, "not before a multiple of 60")
	_frame(r)
	_check(r.partner.position.x == -0xBB8, "off screen on frame 120: back to x -0xBB8")
	_frame(r, Pad.CANCEL)
	_check(s.state == 3 and s.training.gains == [10, 0, 0, 0, 8, 0], "△: HP 10, Speed 8")
	_check(_run_out(r, s) and r.tamer.state == Tamer.STATE_TRAINING, "done; the tamer left in state 8")
	var sv: SpeedStation = _start(r, 0x4E, Training.STAT_SPEED)
	_frame(r)
	_frame(r)
	r.partner.on_screen = false
	for i in 0x3C:
		_frame(r)
	_check(-int(r.partner.position.z) == 0x7D0, "Savanna Course: back to z 0x7D0")
	sv.running = false
	_free_rig(r)


func _defense() -> void:
	var r := _rig()
	var s: DefenseStation = _start(r, 0x70, Training.STAT_DEFENSE)
	_frame(r)
	_frame(r)
	_check(s.state == 2 and r.partner.direction == 0x400, "guarding")
	_frame(r)
	_check(s.state == 2 and r.o.instance(0x47)["x"] == 250, "the glove comes: + 0x32")
	_frame(r)
	_check(s.state == 3 and r.routines.sparks.active_count() == 3 and r.sound.played.has([8, DefenseStation.SOUND_PUNCH]),
			"the punch at + 0x64: sparks, the punch sound")
	var x0: float = r.partner.position.x
	var clouds: int = r.routines.clouds.active_count()
	_frame(r)
	_check(s.state == 4 and r.partner.position.x == x0 + 0x64 and r.routines.clouds.active_count() == clouds + 1,
			"knocked back + 0x64 with a cloud")
	for i in 60:
		_frame(r)
		if s.state == 10:
			break
	_frame(r)
	_check(s.state == 2 and r.o.instance(0x47)["x"] == 200, "the swings, back in place, walked back, another punch")
	_frame(r, Pad.CANCEL)
	_check(s.state == 2 and s.counter == DefenseStation.SESSION_FRAMES + 1, "△: counter 1200, the punch goes on")
	for i in 60:
		_frame(r)
		if s.state == 12:
			break
	_check(s.state == 12 and s.training.gains == [0, 0, 0, 8, 0, 2] and r.sound.stopped.has(7),
			"back at the point: the gains, the punch sound stopped")
	_check(_run_out(r, s) and r.tamer.state == Tamer.STATE_FREE, "done")
	_free_rig(r)


func _mp() -> void:
	var r := _rig()
	var s: MpStation = _start(r, 0x70, Training.STAT_MP)
	_frame(r)
	_frame(r)
	_check(s.state == 2 and r.interp.walks[-1][2] == 0x290, "by the approach")
	_frame(r)
	_check(s.state == 3 and r.o.instance(0x93)["flag"] == 1 and r.o.instance(0xA2)["flag"] == 1
			and r.o.instance(0xA3)["flag"] == 0 and r.o.instance(0xA4)["y"] == 100 - MpStation.SPLASH_ABOVE,
			"under the fall: calm hidden, pouring shown, the splash at the head (no map: pixel 0)")
	_frame(r, Pad.CANCEL)
	_check(s.state == 4 and s.training.gains == [0, 80, 0, 2, 0, 0] and r.o.instance(0x93)["flag"] == 0
			and r.o.instance(0xA3)["flag"] == 1 and r.o.instance(0xA4)["y"] == 100 and r.sound.stopped.has(7),
			"△: the gains, the fall back, the sound stopped")
	var walks: int = r.interp.walks.size()
	_check(_run_out(r, s), "done")
	var to_tamer := false
	for w in r.interp.walks.slice(walks):
		if w[1] == ScriptContext.OWNER_TAMER:
			to_tamer = true
	_check(not to_tamer and r.tamer.state == Tamer.STATE_FREE, "no walk back to the tamer")
	_free_rig(r)


func _brains() -> void:
	var r := _rig()
	var s: BrainsStation = _start(r, 0x70, Training.STAT_BRAINS)
	_frame(r)
	_check(s.state == 1 and r.tamer.state == Tamer.STATE_NONE, "the tamer: state -1")
	_frame(r)
	_check(s.state == 2 and r.interp.walks[-1][0] == ScriptContext.OWNER_TAMER and r.interp.walks[-1][2] == -0x5AC,
			"the tamer walks to his place first")
	_frame(r)
	_check(s.state == 3 and r.interp.walks[-1][0] == ScriptContext.OWNER_PARTNER, "then the partner")
	for i in BrainsStation.TEACH_EVERY:
		_frame(r)
	_check(r.sound.played.has([8, BrainsStation.SOUND_TEACH]) and r.tamer.step_blocked, "every 30 frames, the lesson's sound")
	gs.state["partner"]["stats"]["base"]["brains"] = 95
	_frame(r, Pad.CANCEL)
	_check(s.state == 4 and s.training.gains == [0, 10, 0, 0, 0, 8] and r.boxes.boxes[2].state == UIBoxes.STATE_OPENING,
			"△: MP 10, Brains 8; 95 -> 103: new orders, box 2")
	_check(_run_out(r, s) and r.boxes.boxes[2].state != UIBoxes.STATE_OPEN and r.tamer.state == Tamer.STATE_FREE,
			"done: box 2 closes, the tamer free")
	_free_rig(r)
