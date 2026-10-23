class_name Clock
extends Node
## The game clock (specs/clock.md): clock.c, the hour check of renderMap and the daily update.
## A node of the field scene, like the objects addClock() adds when play starts (clock.c:90).
## Runs once per game frame (GameLoop.frame) on GameState.state.

## The palette to show for the current hour (updateTimeOfDay, map.c:4301).
signal time_of_day_changed(palette: int)
## Start of a fade to the next palette (initializeDaytimeTransition, map.c:4500).
signal daytime_transition(palette: int)
signal minute_passed
signal day_passed
## addTamerLevel awarded a level change (TAMER_LEVELS_AWARDED: +1 / -1).
signal tamer_level_changed(amount: int)

## Script value 0 (PSTAT_TIME_SPEED, pstat.h:261).
const PSTAT_TIME_SPEED := 0
const SPEED_NORMAL := 0
const SPEED_DOUBLE := 1
const SPEED_HALF := 2
const SPEED_RESET := 3
## CURRENT_TIME_OF_DAY values (map.c:4318-4329) and the background palette of each.
const TIME_EVENING := 0
const TIME_NIGHT := 1
const TIME_DAY := 2
const PALETTE := {TIME_DAY: 0, TIME_EVENING: 1, TIME_NIGHT: 2}
## renderMap starts a fade at these hours (map.c:3970-3980).
const TRANSITION_HOURS := {16: TIME_EVENING, 20: TIME_NIGHT, 6: TIME_DAY}
## dailyPStatTrigger (script_common.c:1399-1435).
const CARD_SHOP_ROLL := 0x40
const CARD_SHOP_SKIPPED := 4
const DAILY_COUNTERS := [0x1C, 0x1D, 0x1E, 0x1F]
const PSTAT_TOURNAMENT_DAY := 2
const DAYS_PER_YEAR := 30
const YEARS := 100
const MAX_PLAYTIME_HOURS := 999
const FRAMES_PER_MINUTE := 20
const FRAMES_PER_HOUR := 1200
const MAX_TAMER_LEVEL := 10

## The GameState autoload; set explicitly where there is no scene tree.
var game_state: Node
## The field is in normal play (stands for GAME_STATE == 0, not fishing, map layer shown).
var active := false
## IS_GAMETIME_RUNNING (clock.c:51): scripts stop the time. Not saved.
var running := true
## SUBFRAME_COUNT (clock.c:49), for half speed. Not saved.
var subframe_count := 0
## CURRENT_TIME_OF_DAY (map.c), set by update_time_of_day.
var current_time_of_day := TIME_DAY
## The current map has a day / night cycle (MAP_ENTRIES.flags & 0x40 clear).
var map_has_time_of_day := true


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	var loop := get_node_or_null("/root/GameLoop")
	if loop != null:
		loop.frame.connect(tick)


## One game frame: the clock and playtime objects, then the hour check of renderMap.
func tick() -> void:
	tick_game_clock()
	tick_playtime()
	if active:
		check_daytime_transition()


## tickGameClock (clock.c:96-172).
func tick_game_clock() -> void:
	var clock: Dictionary = game_state.state["clock"]
	clock["last_handled_frame"] = clock["frame"]
	if not active or not running:
		return
	var speed: int = game_state.script_value(PSTAT_TIME_SPEED)
	if speed == SPEED_RESET:
		game_state.set_script_value(PSTAT_TIME_SPEED, SPEED_NORMAL)
		speed = SPEED_NORMAL
	if speed == SPEED_NORMAL:
		clock["frame"] += 1
	elif speed == SPEED_DOUBLE:
		clock["frame"] += 2
		if clock["frame"] % 2 != 0:
			clock["frame"] -= 1
	elif speed == SPEED_HALF:
		subframe_count += 1
		if subframe_count % 2 == 0:
			clock["frame"] += 1
	var minute_tick: bool = clock["frame"] % FRAMES_PER_MINUTE == 0 and (speed != SPEED_HALF or subframe_count % 2 == 0)
	if minute_tick:
		_next_minute(clock)
	if clock["year"] >= YEARS:
		clock["year"] = 0


func _next_minute(clock: Dictionary) -> void:
	var care: Dictionary = game_state.state["partner"]["care"]
	clock["minute"] += 1
	if clock["minute"] == 60:
		clock["hour"] += 1
		clock["minute"] = 0
		care["evo_timer"] += 1
		care["remaining_lifetime"] -= 1
		subframe_count = 0
		if clock["hour"] == 24:
			care["age"] += 1
			clock["day"] += 1
			clock["hour"] = 0
			clock["frame"] = 0
			daily_update()
			if care["remaining_lifetime"] < 0:
				care["remaining_lifetime"] = 0
			if clock["day"] >= DAYS_PER_YEAR:
				clock["day"] = 0
				clock["year"] += 1
				if care["happiness"] == 100:
					add_tamer_level(5, 1)
				elif care["happiness"] < 0:
					add_tamer_level(10, -1)
			day_passed.emit()
	minute_passed.emit()
	game_state.changed.emit("clock")


## tickPlaytime (clock.c:174): runs while game time is stopped too.
func tick_playtime() -> void:
	var playtime: Dictionary = game_state.state["clock"]["playtime"]
	playtime["frames"] += 1
	if playtime["frames"] % FRAMES_PER_HOUR == 0:
		playtime["minutes"] += 1
		if playtime["minutes"] > 59:
			playtime["hours"] += 1
			playtime["minutes"] = 0
			playtime["frames"] = 0
			if playtime["hours"] > MAX_PLAYTIME_HOURS:
				playtime["hours"] = MAX_PLAYTIME_HOURS
	if playtime["hours"] == MAX_PLAYTIME_HOURS:
		playtime["minutes"] = 59


## advanceToTime (clock.c:194): a target earlier in the day starts a new day first.
func advance_to_time(hour: int, minute: int) -> void:
	var clock: Dictionary = game_state.state["clock"]
	if hour < clock["hour"] or (hour == clock["hour"] and minute < clock["minute"]):
		clock["day"] += 1
		game_state.state["partner"]["care"]["age"] += 1
		daily_update()
		if clock["day"] >= DAYS_PER_YEAR:
			clock["day"] = 0
			clock["year"] += 1
		day_passed.emit()
	clock["hour"] = hour % 24
	clock["minute"] = minute
	clock["frame"] = clock["hour"] * FRAMES_PER_HOUR + minute * FRAMES_PER_MINUTE
	update_time_of_day()
	minute_passed.emit()
	game_state.changed.emit("clock")


## dailyPStatTrigger (script_common.c:1399): re-rolls the card shop, counts days in script values
## 0x1C-0x1F, clears bit 7 of the tournament day.
func daily_update() -> void:
	var data: Node = game_state.data
	var shop: Array = game_state.state["script"]["card_shop"]
	for i in shop.size():
		shop[i] = null
	for i in shop.size():
		var card := CARD_SHOP_SKIPPED
		while card == CARD_SHOP_SKIPPED:
			card = Rng.random_limit(CARD_SHOP_ROLL) + 1
		# The original's duplicate check compares with slot i itself (just cleared), so it never
		# rejects: duplicates are possible, kept (script_common.c:1418-1422).
		shop[i] = data.key_of("items/card_data", card)
	for index in DAILY_COUNTERS:
		var value: int = game_state.script_value(index)
		if value != 0xFF:
			game_state.set_script_value(index, value + 1)
	var day: int = game_state.script_value(PSTAT_TOURNAMENT_DAY)
	if day != 0xFF:
		game_state.set_script_value(PSTAT_TOURNAMENT_DAY, day & 0x7F)


## addTamerLevel (tamer.c:1309): chance % to add `amount`; the level stays 0-10.
func add_tamer_level(chance: int, amount: int) -> void:
	if Rng.random_limit(100) >= chance:
		return
	var tamer: Dictionary = game_state.state["tamer"]
	tamer["level"] += amount
	if tamer["level"] >= 0 and tamer["level"] < MAX_TAMER_LEVEL + 1:
		tamer_level_changed.emit(1 if amount >= 1 else -1)
	tamer["level"] = clampi(tamer["level"], 0, MAX_TAMER_LEVEL)
	game_state.changed.emit("tamer")


## The CURRENT_TIME_OF_DAY value for an hour (map.c:4317-4330).
static func time_of_day_for(hour: int) -> int:
	if hour >= 16 and hour < 20:
		return TIME_EVENING
	if hour < 6 or hour >= 20:
		return TIME_NIGHT
	return TIME_DAY


## updateTimeOfDay (map.c:4301): maps without a cycle always show palette 0.
func update_time_of_day() -> void:
	if not map_has_time_of_day:
		time_of_day_changed.emit(0)
		return
	current_time_of_day = time_of_day_for(game_state.state["clock"]["hour"])
	time_of_day_changed.emit(PALETTE[current_time_of_day])


## The hour check of renderMap (map.c:3967-3980), every frame while the map is drawn.
func check_daytime_transition() -> void:
	var clock: Dictionary = game_state.state["clock"]
	if map_has_time_of_day and clock["frame"] % FRAMES_PER_HOUR == 0 and TRANSITION_HOURS.has(clock["hour"]):
		initialize_daytime_transition(TRANSITION_HOURS[clock["hour"]])


## initializeDaytimeTransition (map.c:4500). The partner / tamer state conditions come with the
## partner port.
func initialize_daytime_transition(time_of_day: int) -> void:
	if current_time_of_day == time_of_day:
		return
	current_time_of_day = time_of_day
	daytime_transition.emit(PALETTE[time_of_day])


## Weight of the target palette on frame f of a fade (tickDaytimeTransition, map.c:4581): the
## colours move 1/6 ... 1/2 of the way, then the target at frame 25.
static func transition_weight(frame: int) -> float:
	return 1.0 if frame >= 25 else 1.0 / (6 - frame / 5)
