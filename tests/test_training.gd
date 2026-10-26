extends SceneTree
## Training (scripts/systems/training.gd, scripts/ui/training_stats_box.gd, scripts/training/,
## scripts/script/training_routines.gd, scripts/field/cloud_fx.gd; specs/training.md): the gains,
## the hour, the stats box, builtins 0x07 / 0x27 and the HP station with a stub walker.
##   godot --headless --path . -s res://tests/test_training.gd
## Exits 1 if a check fails.

## The interpreter with a walker that arrives when told to.
class FakeInterpreter extends ScriptInterpreter:
	var arrive := true
	var walks: Array = []

	func tick_walk_to(script_id: int, target_id: int, x: int, z: int, _use_camera := false) -> bool:
		walks.append([script_id, target_id, x, z])
		return arrive


## Records playSound calls.
class FakeSound extends Node:
	var played: Array = []

	func play_sound(slot: int, value: int) -> int:
		played.append([slot, value])
		return 0


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
