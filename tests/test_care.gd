extends SceneTree
## Care (scripts/systems/care.gd) against specs/care.md §2, values worked out from the C:
##   godot --headless --path . -s res://tests/test_care.gd
## Exits 1 if a check fails.

var _failed := 0
var _started := false
var data: Node
var gs: Node
var clock: Clock
var care: Care
var c: Dictionary


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: data porter output missing")
		quit(0)
		return
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	clock = Clock.new()
	clock.game_state = gs
	clock.active = true
	care = Care.new()
	care.game_state = gs
	care.data = data
	care.clock = clock
	Rng.set_seed(7)

	_food_timer()
	_hunger()
	_sleep()
	_sickness()
	_lifetime_and_unhappiness()
	_poop()
	_bubbles()
	_sleeping()
	_gates()
	_new_partner()
	_properties()
	_visuals()
	_debug_panel()

	care.free()
	clock.free()
	gs.free()
	data.free()
	print("%s: Care checks" % ("FAILED %d" % _failed if _failed else "OK"))
	quit(1 if _failed else 0)


## A fresh new game with `partner`, its care initialised, at hh:mm.
func _reset(partner := "dw1:agumon", hour := 8, minute := 0) -> void:
	gs.new_game(partner)
	_at(hour, minute)
	care.initialize_partner()
	c = gs.state["partner"]["care"]


## Sets the clock to hh:mm, as the frame the clock has just advanced to.
func _at(hour: int, minute: int) -> void:
	var clk: Dictionary = gs.state["clock"]
	clk["hour"] = hour
	clk["minute"] = minute
	clk["frame"] = hour * 1200 + minute * 20
	clk["last_handled_frame"] = clk["frame"] - 1


## Game frames in the original order: the partner (care) first, then the clock.
func _frames(count: int) -> void:
	for i in count:
		care.tick_conditions()
		care.tick_pooping_mechanic()
		care.tick_condition_boundaries()
		clock.tick_game_clock()


func _food_timer() -> void:
	_reset("dw1:agumon", 14, 30)
	c["next_hunger_hour"] = 13
	care.set_food_timer()
	_eq([c["next_hunger_hour"], c["food_level"]], [17, 150], "Agumon at 14:30 after the 13:00 call: 17:00, 150 minutes")
	_eq(Care.next_hunger_hour([1, 5, 9, 13, 17, 21], 14, 17), 21, "a stored hour still ahead: the listed hour after it")
	_eq(Care.next_hunger_hour([1, 5, 9, 13, 17, 21], 20, 21), 21, "stored 21 at 20:00: nothing after 21, so the next after 20")
	_eq(Care.next_hunger_hour([1, 5, 9, 13, 17, 21], 22, 21), 1, "after the last call of the day: 1 the next day")
	_at(22, 0)
	c["next_hunger_hour"] = 21
	care.set_food_timer()
	_eq(c["food_level"], 180, "22:00 -> 01:00 is 180 minutes")
	var fresh := _with_level(1)
	var in_training := _with_level(2)
	_reset(fresh, 13, 0)
	_eq(c["next_hunger_hour"], 14, "Fresh: every 2 hours (13 -> 14)")
	_reset(in_training, 13, 0)
	_eq(c["next_hunger_hour"], 15, "In-Training: every 3 hours (13 -> 15)")
	_at(23, 0)
	care.set_food_timer()
	_eq([c["next_hunger_hour"], c["food_level"]], [0, 60], "In-Training at 23:00: 24 wraps to 0")


func _hunger() -> void:
	_reset("dw1:agumon", 10, 0)
	c["food_level"] = 1
	_at(10, 1)
	care.tick_conditions()
	_eq([gs.has_condition(Care.HUNGRY), c["starvation_timer"]], [true, 180], "hungry when food reaches 0, 180 to wait")
	c["energy_level"] = 0
	var mistakes: int = c["care_mistakes"]
	_frames(1800)
	_eq(gs.has_condition(Care.HUNGRY), false, "the call ends after 1800 frames")
	_eq(c["care_mistakes"], mistakes + 1, "unfed (energy below the threshold): a care mistake")
	_eq(c["next_hunger_hour"], 17, "the next call: the stored 13 is still ahead, so the listed hour after it")
	_reset("dw1:agumon", 10, 0)
	c["food_level"] = 1
	c["energy_level"] = 40
	_at(10, 1)
	care.tick_conditions()
	_frames(1800)
	_eq(c["care_mistakes"], 0, "fed enough (energy at the threshold): no care mistake")
	_reset("dw1:agumon", 10, 0)
	var energy: int = c["energy_level"]
	_at(11, 0)
	care.tick_conditions()
	_eq(c["energy_level"], energy - 5, "energy - energy_usage (5) every hour")
	c["energy_level"] = 0
	var weight: int = c["weight"]
	_at(11, 10)
	care.tick_conditions()
	_eq(c["weight"], weight - 1, "at 0 energy: weight - 1 every 10 minutes")


func _sleep() -> void:
	_reset("dw1:agumon", 18, 59)
	_eq([c["sleepy_hour"], c["wakeup_hour"], c["hours_awake_default"], c["hours_asleep_default"]], [19, 4, 15, 9],
			"Agumon's pattern: sleepy 19:00, awake 04:00")
	care.tick_conditions()
	_eq(gs.has_condition(Care.SLEEPY), false, "not sleepy at 18:59")
	_at(19, 0)
	care.tick_conditions()
	_eq([gs.has_condition(Care.SLEEPY), care.sleep_enabled], [true, true], "sleepy at 19:00, the menu's Sleep enabled")
	var happiness: int = c["happiness"]
	var discipline: int = c["discipline"]
	_at(20, 0)
	care.tick_conditions()
	_eq([c["happiness"], c["discipline"], c["missed_sleep_hours"]], [happiness - 2, discipline - 4, 1],
			"sleepy Rookie: -2 / -4 per hour, a missed sleep hour")
	_at(4, 0)
	care.tick_conditions()
	_eq([gs.has_condition(Care.SLEEPY), c["care_mistakes"], c["sleepy_hour"]], [false, 1, 19],
			"a missed night at 04:00: awake, care mistake, same schedule")
	# Tiredness moves bedtime earlier: 100 tiredness -> +30 per minute, 180 after 6 minutes.
	_reset("dw1:agumon", 10, 0)
	c["tiredness"] = 100
	c["tiredness_sleep_timer"] = 180
	_at(10, 10)
	care.tick_conditions()
	_eq([c["time_awake_today"], c["sleepy_hour"], c["sleepy_minute"]], [89, 18, 50],
			"10 awake minutes less: sleepy at 18:50")


func _sickness() -> void:
	# sickness_tries 1, tiredness 0: (1 - 10) * 5 + (0 - 50) = -95 -> uint8 161, always sick.
	for seed_value in [1, 2, 3]:
		Rng.set_seed(seed_value)
		_reset("dw1:agumon", 10, 0)
		c["sickness_counter"] = 10
		_at(11, 0)
		care.tick_conditions()
		_eq(gs.has_condition(Care.SICK), true, "missed sleep: the wrapped chance makes it certain (seed %d)" % seed_value)
	_eq([c["happiness"], c["discipline"], c["tiredness"], c["sickness_timer"], c["times_being_sick"]], [20, 45, 5, 1, 1],
			"getting sick: -20, then the hourly -10 / -5 / +5; the timer ends at 1")
	_reset("dw1:agumon", 10, 0)
	# (31 - 10) * 5 + (0 - 50) = 55: a real percentage.
	var sick := 0
	for i in 200:
		c["condition"] = 0
		c["sickness_counter"] = 10
		c["sickness_tries"] = 30
		c["tiredness"] = 0
		_at(11, 0)
		care.tick_sickness_mechanics()
		if gs.has_condition(Care.SICK):
			sick += 1
	_eq(sick > 80 and sick < 140, true, "a 55 %% chance (%d / 200)" % sick)
	_reset("dw1:agumon", 10, 0)
	gs.set_condition(Care.INJURED, true)
	c["injury_timer"] = 11
	var messages := []
	care.message.connect(func(t): messages.append(t))
	_at(11, 0)
	care.tick_conditions()
	_eq([gs.has_condition(Care.SICK), gs.has_condition(Care.INJURED), c["injury_timer"], c["sickness_timer"]],
			[true, false, 0, 1], "injured for 12 hours: sick")
	_eq(messages.size(), 1, "the 'is sick' message")
	var scripts := []
	care.script_requested.connect(func(s): scripts.append(s))
	c["sickness_timer"] = 11
	var lives: int = gs.state["partner"]["lives"]
	_at(12, 0)
	care.tick_conditions()
	_eq([gs.state["partner"]["lives"], c["sickness_timer"], scripts], [lives - 1, 0, [0x4DE]],
			"sick for 12 hours: a life lost, script 0x4DE")
	care.script_running = false


func _lifetime_and_unhappiness() -> void:
	for case in [[50, 1], [0, 2], [-30, 3], [-100, 4]]:
		_reset("dw1:agumon", 3, 59)
		c["happiness"] = case[0]
		var life: int = c["remaining_lifetime"]
		_at(4, 0)
		care.tick_conditions()
		_eq(life - int(c["remaining_lifetime"]), case[1], "every 4 hours at happiness %d: lifetime -%d" % case)
	_reset("dw1:agumon", 10, 0)
	c["happiness"] = -100
	c["discipline"] = 0
	var base: Dictionary = gs.state["partner"]["stats"]["base"]
	base["max_hp"] = 100
	base["offense"] = 0
	_at(10, 10)
	care.tick_conditions()
	_eq(gs.has_condition(Care.UNHAPPY), true, "happiness -100, discipline 0: unhappy (roll < 100)")
	_at(10, 15)
	care.tick_conditions()
	_eq([base["max_hp"], base["offense"]], [98, 1], "every 15 minutes: stats -2 %, never below 1")
	c["happiness"] = -1
	_at(10, 16)
	clock_frame_offset(15 - (int(gs.state["clock"]["frame"]) % 15))
	care.tick_conditions()
	_eq([c["happiness"], gs.has_condition(Care.UNHAPPY)], [0, false], "+1 every 15 frames; at 0 no longer unhappy")


## Moves the clock frame forward by `frames` (still an advanced frame).
func clock_frame_offset(frames: int) -> void:
	var clk: Dictionary = gs.state["clock"]
	clk["frame"] = int(clk["frame"]) + frames
	clk["last_handled_frame"] = int(clk["frame"]) - 1


func _poop() -> void:
	_reset("dw1:agumon", 10, 0)
	_eq(c["poop_level"], 24, "Agumon's poop timer")
	c["poop_level"] = 1
	_at(10, 10)
	care.tick_pooping_mechanic()
	_eq([gs.has_condition(Care.POOPY), c["pooping_timer"]], [true, 840], "poopy; (50 + 20) * 1200 / 100 frames")
	var accident := false
	for i in 840:
		clock_frame_offset(1)
		accident = care.tick_pooping_mechanic()
		if accident:
			break
	_eq([accident, c["pooping_timer"], care.item_scold_flag], [true, -1, 1], "after 840 frames: the accident")
	var weight: int = c["weight"]
	care.handle_wild_poop()
	_eq([gs.has_condition(Care.POOPY), c["poop_level"], c["care_mistakes"], c["happiness"], c["discipline"]],
			[false, 48, 1, 40, 45], "handleWildPoop: US doubles the timer")
	_eq(c["weight"], weight - 2, "weight - (0..3 + 8) / 4 = 2")
	gs.state["world"]["screen"] = "dw1:mayo04a"
	var poop: Array = gs.state["world"]["poop"]
	var slot := care.create_poop_pile(Vector2i(50, 50), 0)
	_eq([slot, poop[0]], [0, {"map": "dw1:mayo04a", "x": 50, "y": 49, "size": 8}], "rotation 0: the tile at y - 1")
	care.create_poop_pile(Vector2i(50, 50), 0)
	_eq(poop[1] != null and Vector2i(poop[1]["x"], poop[1]["y"]) != Vector2i(50, 49), true, "same tile: moved aside")
	care.create_poop_pile(Vector2i(60, 60), 0x800)
	_eq(Vector2i(poop[2]["x"], poop[2]["y"]), Vector2i(60, 61), "rotation 0x800: y + 1")
	care.create_poop_pile(Vector2i(60, 60), 0x600)
	_eq(Vector2i(poop[3]["x"], poop[3]["y"]), Vector2i(61, 61), "rotation 0x600: diagonal x + 1, y + 1")
	for i in range(4, 16):
		care.create_poop_pile(Vector2i(10 + i * 3, 10), 0)
	_eq(poop[16], null, "16 piles on this map")
	care.current_poop_id = 0
	care.create_poop_pile(Vector2i(90, 90), 0)
	_eq([poop[16], Vector2i(poop[0]["x"], poop[0]["y"])], [null, Vector2i(90, 89)], "the 17th overwrites a pile of this map")
	_eq(c["virus_bar"], 17, "each pile + 1 on the virus bar")
	for i in poop.size():
		poop[i] = null


func _bubbles() -> void:
	_reset("dw1:agumon", 10, 0)
	var shown := []
	care.bubble_shown.connect(func(t): shown.append(t))
	care.bubble_type = 0
	care.bubble_timer = 0
	gs.set_condition(Care.HUNGRY, true)
	for i in 59:
		care.handle_condition_bubble()
	_eq(shown, [], "the type starts as 0 (hungry): no hungry bubble until it is forgotten at 60")
	for i in 3:
		care.handle_condition_bubble()
	_eq(shown, [0], "then the hungry bubble")
	shown.clear()
	for i in 61:
		care.handle_condition_bubble()
	_eq(shown, [0], "one condition: again after 61 frames")
	gs.set_condition(Care.SLEEPY, true)
	shown.clear()
	for i in 150:
		care.handle_condition_bubble()
	_eq(shown.slice(0, 3), [3, 0, 3], "two conditions alternate, sleepy first")
	gs.set_condition(Care.HUNGRY, false)
	gs.set_condition(Care.SLEEPY, false)
	gs.set_condition(Care.UNHAPPY, true)
	care.handle_condition_bubble()
	_eq(care.has_butterfly, true, "only unhappy: the butterfly")


func _sleeping() -> void:
	_reset("dw1:agumon", 20, 0)
	gs.set_condition(Care.SLEEPY, true)
	gs.set_condition(Care.POOPY, true)
	gs.set_condition(Care.SICK, true)
	gs.state["world"]["screen"] = "dw1:mayo04a"
	gs.state["inventory"]["slots"].fill(null)
	var stats: Dictionary = gs.state["partner"]["stats"]
	stats["base"]["max_hp"] = 100
	stats["base"]["max_mp"] = 100
	c["tiredness"] = 50
	care.area_response = 1
	care.sleep_regen()
	# 8 hours of 9: factor 88, liked map x1.2 = 105; HP + 105 * (100 * (70..79) / 100) / 100.
	_eq(stats["current"]["hp"] >= 73 and stats["current"]["hp"] <= 82, true, "sleepRegen HP %d in 73..82" % stats["current"]["hp"])
	_eq(c["weight"], 14, "weight - default_weight / 10")
	var life: int = c["remaining_lifetime"]
	var evo: int = c["evo_timer"]
	var day: int = gs.state["clock"]["day"]
	care.handle_sleeping()
	var clk: Dictionary = gs.state["clock"]
	_eq([clk["hour"], clk["day"]], [4, day + 1], "wakes up at 04:00 the next day")
	_eq([c["remaining_lifetime"], c["evo_timer"]], [life - 8, evo + 9], "lifetime - hours slept, evo + hours asleep")
	_eq([gs.has_condition(Care.SLEEPY), gs.has_condition(Care.POOPY), care.has_immortal_hour, care.immortal_hour],
			[false, false, true, 4], "awake, poop left on the map, immortal hour 4")
	_eq([c["sickness_timer"], c["poop_level"]], [8, 24], "sick: timer + 8 hours slept; poop timer not doubled")
	_eq(gs.state["world"]["poop"][0] != null, true, "the pile")
	gs.state["world"]["poop"][0] = null
	care.area_response = 0


func _gates() -> void:
	_reset("dw1:agumon", 10, 0)
	c["food_level"] = 1
	clock.running = false
	_at(10, 1)
	care.tick_conditions()
	_eq(gs.has_condition(Care.HUNGRY), false, "nothing while game time is stopped")
	clock.running = true
	var clk: Dictionary = gs.state["clock"]
	clk["last_handled_frame"] = clk["frame"]
	care.tick_conditions()
	_eq(gs.has_condition(Care.HUNGRY), false, "nothing when the clock didn't advance")
	_reset("dw1:agumon", 10, 0)
	c["remaining_lifetime"] = 0
	care.has_immortal_hour = true
	care.immortal_hour = 10
	var scripts := []
	var record := func(s): scripts.append(s)
	care.script_requested.connect(record)
	_at(10, 1)
	care.tick_conditions()
	_eq(scripts, [], "no death in the immortal hour")
	care.has_immortal_hour = false
	_at(10, 2)
	care.tick_conditions()
	_eq([scripts, care.is_natural_death], [[0x4DE], true], "lifetime 0: natural death, script 0x4DE")
	care.script_requested.disconnect(record)
	care.script_running = false
	# Partner before clock: the care sees the frame the clock advanced to on its last tick.
	_reset("dw1:agumon", 10, 0)
	c["food_level"] = 1
	clk = gs.state["clock"]
	clk["frame"] = 10 * 1200 + 19
	clk["last_handled_frame"] = clk["frame"]
	_frames(1)
	_eq(gs.has_condition(Care.HUNGRY), false, "the clock reaches 10:01 in this frame: the care sees it next frame")
	_frames(1)
	_eq(gs.has_condition(Care.HUNGRY), true, "and gets hungry then")


func _new_partner() -> void:
	_reset("dw1:agumon", 8, 0)
	var moves: Array = gs.state["partner"]["stats"]["base"]["moves"]
	_eq(moves[0], "dw1:spit_fire", "first technique from raise_data.first_technique")
	_eq(gs.has_move("dw1:spit_fire"), true, "and learned")
	_eq(data.move(moves[3]).get("category"), "finisher", "slot 3: the last finisher of the list")
	_eq([c["remaining_lifetime"], c["energy_level"], c["poop_level"], c["weight"], c["happiness"], c["discipline"]],
			[360, 20, 24, 15, 50, 50], "initializePartner's values for Agumon")
	_eq([gs.state["partner"]["lives"], c["next_hunger_hour"], c["food_level"]], [3, 9, 60], "3 lives; hungry at 09:00")


func _properties() -> void:
	_reset("dw1:numemon", 10, 0)
	var tamer := Tamer.new()
	care.tamer = tamer
	gs.state["world"]["screen"] = "dw1:mayo04a"
	gs.state["world"]["poop"][5] = {"map": "dw1:mayo04a", "x": 50, "y": 50, "size": 8}
	tamer.position = Vector3(50, 0, 50)
	_eq(care.tick_poop_detection(), 5, "a poop eater (raise_data.eats_poop) finds the pile")
	_reset("dw1:agumon", 10, 0)
	_eq(care.tick_poop_detection(), -1, "Agumon doesn't eat poop")
	_reset("dw1:sukamon", 10, 0)
	care.create_poop_pile(Vector2i(20, 20), 0)
	_eq(c["virus_bar"], 0, "Sukamon's poop doesn't raise the virus bar (raises_virus_bar)")
	gs.state["inventory"]["slots"][0] = {"item": "dw1:rest_pillow", "amount": 1}
	_eq(gs.has_passive_item("sleep_boost"), true, "Rest Pillow: item_data.passive")
	care.tamer = null
	tamer.free()


## Bubbles, bars and the STP split (specs/care.md §2.11, §2.14).
func _visuals() -> void:
	_eq([ConditionBubbles.lerp_psx(0, -65, 0, 10, 0), ConditionBubbles.lerp_psx(0, -65, 0, 10, -5),
			ConditionBubbles.lerp_psx(0, 0x6000, 0, 10, 5)], [0, -33, 0x3000], "lerp with its wrap (rise 0 .. -59)")
	var bubbles := ConditionBubbles.new()
	bubbles.show_bubble(3)
	_eq([bubbles.current, bubbles.bubbles[0]["base_height"]], [0, 20], "a sleepy bubble in slot 0, base height -height + 20")
	for i in 11:
		bubbles.tick()
	_eq(bubbles.bubbles[0]["icon"], 1, "sleepy: the Z sequence moves on after 10 frames")
	for i in 40:
		bubbles.tick()
	_eq([bubbles.bubbles[0]["frame"], bubbles.bubbles[0]["height"], bubbles.bubbles[0]["scale"]], [51, 20 - 230, 0xF000],
			"frame 50: the burst, 230 higher at scale 0xF000")
	bubbles.tick()
	_eq(bubbles.bubbles[0], null, "then the bubble is gone")
	bubbles.show_bubble(0)
	bubbles.show_bubble(1)
	_eq([bubbles.current, bubbles.bubbles[0]["icons"], bubbles.bubbles[1]], [0, ConditionBubbles.TYPES[1], null],
			"a new bubble replaces the previous one (first free slot again)")
	bubbles.free()
	if DirAccess.dir_exists_absolute(Content.root()):
		var texture := PsxTexture.load_palette("etctim/03_feel_ef", 4)
		var stp := texture.stp.get_image()
		var base := texture.base.get_image()
		# The bubble (u 0xA0, v 0x90, 32 x 32) has semi-transparent texels and an opaque outline.
		var counts := [0, 0]
		for y in range(0x90 - 128, 0x90 - 128 + 32):
			for x in range(0xA0, 0xA0 + 32):
				counts[0] += 1 if stp.get_pixel(x, y).a > 0.0 else 0
				counts[1] += 1 if base.get_pixel(x, y).a > 0.0 else 0
		_eq(counts[0] > 0 and counts[1] > 0, true, "feel_ef p4: the bubble has STP texels (%d) and opaque ones (%d)" % counts)
	var bars := StatusBars.new()
	bars.clock = clock
	clock.running = false
	for i in 3:
		bars._on_frame()
	_eq(bars.offset_x, 225, "bars slide out by 50 per frame while time is stopped")
	bars._on_frame()
	_eq(bars.offset_x, StatusBars.OFFSET_HIDDEN, "up to 240")
	clock.running = true
	for i in 5:
		bars._on_frame()
	_eq(bars.offset_x, StatusBars.OFFSET_SHOWN, "and back to 75")
	bars.free()


## The debug panel (specs/care.md §3.5) and the game speed.
func _debug_panel() -> void:
	var loop: Node = load("res://scripts/core/game_loop.gd").new()
	var count := [0]
	loop.frame.connect(func(): count[0] += 1)
	loop.speed = 10
	loop._process(0.05)
	_eq(count[0], 10, "speed x10: 10 game frames per original frame")
	_reset("dw1:agumon", 10, 30)
	var panel := CareDebugPanel.new()
	panel.care = care
	panel.clock = clock
	panel.game_state = gs
	panel.game_loop = loop
	root.add_child(panel)
	panel._set_speed(60)
	_eq(loop.speed, 60, "speed buttons set the game loop")
	var evo: int = c["evo_timer"]
	panel._skip_hour()
	_eq([gs.state["clock"]["hour"], gs.state["clock"]["minute"], c["evo_timer"]], [11, 30, evo + 1],
			"+1 hour: skipHours and the clock")
	panel._poop_now()
	_eq([gs.has_condition(Care.POOPY), c["pooping_timer"]], [true, 1], "poop now: the accident on the next frame")
	panel._toilet()
	_eq([gs.has_condition(Care.POOPY), c["poop_level"]], [false, 48], "toilet: handleToilet (US doubles the timer)")
	c["happiness"] = 95
	panel._add("happiness", 10)
	_eq(c["happiness"], 100, "+10 stays within the boundaries")
	panel._set_condition(true, Care.SICK)
	_eq(gs.has_condition(Care.SICK), true, "condition toggles")
	panel.queue_free()
	loop.free()


func _with_level(level: int) -> String:
	for record in data.records("digimon/raise_data"):
		var digimon: Dictionary = data.digimon(int(record["id"]))
		if int(digimon.get("level", {}).get("id", 0)) == level:
			return digimon["key"]
	return ""


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failed += 1
		print("FAIL %s: %s != %s" % [what, actual, expected])
