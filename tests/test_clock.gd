extends SceneTree
## Clock (scripts/systems/clock.gd) against specs/clock.md §2, with the real data porter output:
##   godot --headless --path . -s res://tests/test_clock.gd
## Exits 1 if a check fails.

var _failed := 0
var _data: Node
var _gs: Node
var _clock: Clock


func _initialize() -> void:
	_data = load("res://scripts/data/game_data.gd").new()
	if not _data.available():
		print("SKIP: no data porter output in %s" % _data.root())
		_data.free()
		quit(0)
		return
	_gs = load("res://scripts/state/game_state.gd").new()
	_gs.data = _data
	_clock = load("res://scripts/systems/clock.gd").new()
	_clock.game_state = _gs
	Rng.set_seed(1)

	_speeds()
	_rollovers()
	_daily_update()
	_tamer_level()
	_playtime()
	_time_jumps()
	_time_of_day()

	_clock.free()
	_gs.free()
	_data.free()
	print("%s: Clock checks" % ("FAILED %d" % _failed if _failed else "OK"))
	quit(1 if _failed else 0)


func _fresh() -> Dictionary:
	_gs.new_game()
	_clock.active = true
	_clock.running = true
	_clock.subframe_count = 0
	return _gs.state["clock"]


func _ticks(n: int) -> void:
	for i in n:
		_clock.tick()


## Set the time so that the next frame completes `hour:minute + 1`.
func _just_before(clock: Dictionary, hour: int, minute: int) -> void:
	clock["hour"] = hour
	clock["minute"] = minute
	clock["frame"] = hour * 1200 + minute * 20 + 19


func _speeds() -> void:
	var clock := _fresh()
	_ticks(19)
	_eq([clock["minute"], clock["frame"]], [0, 9619], "19 frames: still 08:00")
	_ticks(1)
	_eq([clock["hour"], clock["minute"], clock["frame"]], [8, 1, 9620], "normal speed: 20 frames per minute")
	_eq(clock["last_handled_frame"], 9619, "LAST_HANDLED_FRAME = frame before the tick")
	clock = _fresh()
	_gs.set_script_value(0, 1)
	_ticks(10)
	_eq(clock["minute"], 1, "double speed: 10 frames per minute")
	clock = _fresh()
	_gs.set_script_value(0, 2)
	_ticks(39)
	_eq(clock["minute"], 0, "half speed: 39 frames are not a minute")
	_ticks(1)
	_eq(clock["minute"], 1, "half speed: 40 frames per minute")
	clock = _fresh()
	_gs.set_script_value(0, 3)
	_ticks(1)
	_eq([_gs.script_value(0), clock["frame"]], [0, 9601], "speed 3 is reset to normal and the frame advances")
	clock = _fresh()
	_clock.active = false
	_ticks(100)
	_eq([clock["frame"], clock["playtime"]["frames"]], [9600, 100], "inactive: no time, but playtime")
	_clock.active = true
	_clock.running = false
	_ticks(100)
	_eq([clock["frame"], clock["playtime"]["frames"]], [9600, 200], "stopped: no time, but playtime")


func _rollovers() -> void:
	var clock := _fresh()
	var care: Dictionary = _gs.state["partner"]["care"]
	_just_before(clock, 8, 59)
	_ticks(1)
	_eq([clock["hour"], clock["minute"], care["evo_timer"], care["remaining_lifetime"]], [9, 0, 1, 287], "new hour: evo timer +1, lifetime -1")
	_just_before(clock, 23, 59)
	_gs.set_script_value(0x1C, 5)
	_gs.set_script_value(0x1D, 0xFF)
	_gs.set_script_value(2, 0x85)
	_ticks(1)
	_eq([clock["day"], clock["hour"], clock["frame"], care["age"]], [1, 0, 0, 4], "new day: day +1, 00:00, frame 0, age +1")
	_eq([_gs.script_value(0x1C), _gs.script_value(0x1D), _gs.script_value(0x1E), _gs.script_value(2)], [6, 0xFF, 1, 0x05], "daily: values 0x1C-0x1F +1 unless 0xFF, value 2 loses bit 7")
	care["remaining_lifetime"] = 0
	_just_before(clock, 23, 59)
	_ticks(1)
	_eq(care["remaining_lifetime"], 0, "lifetime -1 at the hour, clamped to 0 at the new day")
	clock["day"] = 29
	_just_before(clock, 23, 59)
	_ticks(1)
	_eq([clock["year"], clock["day"]], [1, 0], "30 days make a year")
	clock["year"] = 99
	clock["day"] = 29
	_just_before(clock, 23, 59)
	_ticks(1)
	_eq(clock["year"], 0, "year wraps at 100")


func _daily_update() -> void:
	_fresh()
	var allowed := {}
	for id in range(1, 65):
		if id != 4:
			allowed[_data.key_of("items/card_data", id)] = true
	var bad := []
	for i in 300:
		_clock.daily_update()
		for card in _gs.state["script"]["card_shop"]:
			if not allowed.has(card):
				bad.append(card)
	_eq(bad, [], "card shop rolls cards 1-64, never card 4 (300 days)")
	_eq(_gs.state["script"]["card_shop"].size(), 6, "6 card shop slots")


func _tamer_level() -> void:
	_fresh()
	var tamer: Dictionary = _gs.state["tamer"]
	var awarded := []
	_clock.tamer_level_changed.connect(func(amount): awarded.append(amount))
	_clock.add_tamer_level(100, 1)
	_eq([tamer["level"], awarded], [1, [1]], "a sure +1 raises the tamer level")
	_clock.add_tamer_level(0, 1)
	_eq(tamer["level"], 1, "a 0 % chance never changes it")
	tamer["level"] = 10
	_clock.add_tamer_level(100, 1)
	_eq([tamer["level"], awarded.size()], [10, 1], "capped at 10, no award past it")
	tamer["level"] = 0
	_clock.add_tamer_level(100, -1)
	_eq([tamer["level"], awarded.size()], [0, 1], "never below 0, no award below it")


func _playtime() -> void:
	var clock := _fresh()
	var playtime: Dictionary = clock["playtime"]
	playtime["frames"] = 1199
	_clock.tick_playtime()
	_eq([playtime["minutes"], playtime["frames"]], [1, 1200], "1200 frames make a playtime minute")
	playtime["minutes"] = 59
	playtime["frames"] = 1200 * 60 - 1
	_clock.tick_playtime()
	_eq([playtime["hours"], playtime["minutes"], playtime["frames"]], [1, 0, 0], "60 minutes make an hour")
	playtime["hours"] = 999
	playtime["minutes"] = 3
	_clock.tick_playtime()
	_eq([playtime["hours"], playtime["minutes"]], [999, 59], "capped at 999:59")


func _time_jumps() -> void:
	var clock := _fresh()
	_clock.advance_to_time(6, 30)
	_eq([clock["day"], clock["hour"], clock["minute"], clock["frame"], _gs.state["partner"]["care"]["age"]], [1, 6, 30, 7800, 4], "jumping back to 06:30 starts the next day")
	_clock.advance_to_time(10, 0)
	_eq([clock["day"], clock["hour"]], [1, 10], "jumping forward stays on the day")
	# Quirk kept: only an earlier hour starts a new day; 25 is compared as 25, then wraps (clock.c:196-205).
	_clock.advance_to_time(24 + 1, 0)
	_eq([clock["day"], clock["hour"]], [1, 1], "hour 25 wraps to 01:00 of the same day")


func _time_of_day() -> void:
	var expected := {5: 1, 6: 2, 15: 2, 16: 0, 19: 0, 20: 1, 23: 1}
	for hour in expected:
		_eq(Clock.time_of_day_for(hour), expected[hour], "time of day at %d:00" % hour)
	var clock := _fresh()
	var palettes := []
	var fades := []
	_clock.time_of_day_changed.connect(func(p): palettes.append(p))
	_clock.daytime_transition.connect(func(p): fades.append(p))
	clock["hour"] = 17
	_clock.update_time_of_day()
	_clock.map_has_time_of_day = false
	_clock.update_time_of_day()
	_clock.map_has_time_of_day = true
	_eq(palettes, [1, 0], "17:00 shows the evening palette; a map without a cycle palette 0")
	clock["hour"] = 20
	clock["frame"] = 20 * 1200
	_clock.check_daytime_transition()
	_clock.check_daytime_transition()
	clock["frame"] += 1
	_clock.check_daytime_transition()
	_eq(fades, [2], "20:00 starts one fade to night (palette 2)")
	var weights := [0, 4, 5, 10, 15, 20, 24, 25].map(func(f): return snappedf(Clock.transition_weight(f), 0.001))
	_eq(weights, [0.167, 0.167, 0.2, 0.25, 0.333, 0.5, 0.5, 1.0], "fade weights 1/6 ... 1/2, then the target")


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failed += 1
		print("FAIL %s: %s != %s" % [what, actual, expected])
