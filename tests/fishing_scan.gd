extends Node
## Fishing in the real field scene (specs/fishing.md §7, steps F4 / F6) on MAYO10 (map 8): the
## fish swim from the map's load, the △ menu's Fishing icon (disabled without a rod), the menu
## starts the rod (tamer state 11, game time stopped), the bait menu (box 3), aiming, and △ puts
## the rod away (tamer state 0, game time running). Then, from the shore with a fixed seed, a whole
## catch: the cast, the splash, a bite (a fish placed by the bobber), the strike, reeling against
## the tension gauge, the catch message and its item, the end:
##   godot --headless --fixed-fps 60 --path . res://tests/fishing_scan.tscn
## Exits 1 if a check fails.

const START_MAP := "MAYO10"
const TIMEOUT := 9000
## The scan's seed (customRandom and rand), for a repeatable catch.
const SEED := 7
## TRIGGER_HAVE_OLD_FISHROD.
const OLD_ROD := 45

var _field: Node
var _phase := 0
var _phase_frame := 0
var _start_frame := 0
var _failed: Array[String] = []
var _minute_at_start := -1
var _caught_before := 0
var _meat_before := 0
## The fish placed by the bobber.
var _bait_fish: Fishing.Fish
## The last phase reached, and the catch's length line.
var _reached := 0
var _length := ""


func _ready() -> void:
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	Rng.set_seed(SEED)
	GameState.new_game("dw1:agumon")
	_field.map_session.partner.load_digimon(GameData, "dw1:agumon")
	_field.map_session.debug_change_map(START_MAP, 0)
	_start_frame = GameLoop.frame_count


func _host() -> FishingHost:
	return _field.fishing_host


func _next(phase: int) -> void:
	_reached = maxi(_reached, phase)
	_phase = phase
	_phase_frame = GameLoop.frame_count


func _process(_delta: float) -> void:
	if _phase < 0 or _field == null:
		return
	var tamer: Tamer = _field.map_session.tamer
	var host := _host()
	var frames := GameLoop.frame_count - _start_frame
	var in_phase := GameLoop.frame_count - _phase_frame
	if frames > TIMEOUT:
		_fail("stuck in phase %d (tamer %d, rod %s)" % [_phase, tamer.state, str(host.rod.state) if host.rod != null else "none"])
		_done()
		return
	var menu: GameMenu = _field.menu_host.menu
	match _phase:
		0:
			var ctx: ScriptContext = _field.scripts.script_ctx
			if frames % 4 == 0 and not ctx.is_paused:
				GameLoop.press("pad_cross")
			if _screen() != START_MAP or not ctx.is_paused or tamer.state != Tamer.STATE_FREE \
					or _field.care_host.fade.in_current <= 0x13:
				return
			_check(host.fishing != null and host.rod != null, "MAYO10 has fishing (checkFishingMap)")
			_check(_field.clock_host.clock.running, "checkFishingMap starts game time")
			_next(1)
		1:
			# The world object runs from the map's load: the population grows one fish a frame.
			if in_phase < 40:
				return
			_check(host.fishing.fish_count >= 20, "fish swim on the map (%d after 40 frames)" % host.fishing.fish_count)
			_check(host.view != null and host.view.sprites.used() >= 10, "their shadows are drawn (F5: %d quads)" % (host.view.sprites.used() if host.view != null else 0))
			_check(not host.view.get_node("Rod").visible, "no rod while walking")
			for i in 30:
				GameState.state["inventory"]["slots"][i] = null
			_check(host.availability() == 1, "no rod and no food: the icon shows, disabled (availability 1)")
			GameState.set_trigger(OLD_ROD)
			_check(host.availability() == 1, "a rod but no food: still 1")
			GameState.give_item("dw1:meat", 3)
			_check(host.availability() == 2, "a rod and food: 2")
			GameLoop.press("pad_triangle")
			_next(2)
		2:
			if not menu.is_open or menu.menu_state != GameMenu.STATE_OPEN:
				if in_phase > 200:
					_fail("the △ menu didn't open")
					_done()
				return
			_check(menu.count == 8 and menu.selection == GameMenu.FISHING and not menu.is_disabled(GameMenu.FISHING),
					"the menu has 8 options, on Fishing, enabled")
			GameLoop.press("pad_cross")
			_next(3)
		3:
			if tamer.state != Tamer.STATE_FISHING:
				if in_phase > 60:
					_fail("Fishing didn't start (tamer state %d)" % tamer.state)
					_done()
				return
			_check(not menu.is_open, "the menu closed (IS_IN_MENU 0)")
			_check(not _field.clock_host.clock.running and host.is_fishing(), "game time stays stopped while fishing")
			_check(host.rod.display_rod and host.rod.rod_type == 1, "the old rod")
			_minute_at_start = int(GameState.state["clock"]["minute"])
			_next(4)
		4:
			if host.rod.state != FishingRod.STATE_BAIT_MENU or not host.rod.bait_menu.shown:
				if in_phase > 300:
					_fail("no bait menu (rod state %d)" % host.rod.state)
					_done()
				return
			var b: UIBoxes.Box = _field.scripts.boxes.boxes[FishingBaitMenu.BOX_ID]
			_check(b.registered and b.animated, "the bait menu is UI box 3, animated")
			_check(b.render.is_valid() and b.on_render.is_valid(), "with FishingWindows' contents (F5)")
			_check(host.rod.bait_menu.items[0] >= 0 and host.rod.bait_menu.total_rows == 1, "one row: the Meat")
			_next(5)
		5:
			if in_phase == 10:
				GameLoop.press("pad_cross")
			if host.rod.state == FishingRod.STATE_AIM:
				_check(host.rod.bait == GameData.id_of("items/item_data", "dw1:meat"), "Meat is the bait")
				_check(host.rod.display_line and host.rod.display_swimmer, "the line and the bobber show")
				_check(host.view.get_node("Rod").visible, "the rod model shows (F5)")
				_check(not host.hud._shown, "no tension gauge before a fish is hooked")
				_next(6)
			elif in_phase > 600:
				_fail("didn't reach aiming (rod state %x)" % host.rod.state)
				_done()
		6:
			if in_phase == 5:
				GameLoop.press("pad_triangle")
			if tamer.state == Tamer.STATE_FREE:
				_check(not host.is_fishing() and not host.rod.display_rod, "△ put the rod away")
				_check(_field.clock_host.clock.running, "game time runs again (FISH_tamerTick's startGameTime)")
				_check(int(GameState.state["clock"]["minute"]) == _minute_at_start, "the clock stood while fishing")
				_check(tamer.camera_follow, "the camera follows the tamer again")
				_to_the_shore(tamer, host)
				host.start_from_menu()
				_next(7)
			elif in_phase > 600:
				_fail("the rod wasn't put away (rod state %x)" % host.rod.state)
				_done()
		7:
			# Again from the shore: the bait menu, Meat, aiming.
			if host.rod.state == FishingRod.STATE_BAIT_MENU and host.rod.bait_menu.shown and in_phase % 10 == 5:
				GameLoop.press("pad_cross")
			if host.rod.state == FishingRod.STATE_AIM:
				_meat_before = GameState.item_count("dw1:meat")
				_caught_before = int(GameState.state["partner"]["care"]["fish_caught"])
				GameLoop.press("pad_cross")
				_next(8)
			elif in_phase > 600:
				_fail("no second aim (rod state %x)" % host.rod.state)
				_done()
		8:
			if host.rod.state == FishingRod.STATE_THROWING and in_phase >= 2 and in_phase % 2 == 0:
				GameLoop.press("pad_circle")
			if host.rod.state == FishingRod.STATE_FLOATING:
				_check(host.rod.throw_power == 0x19, "○: the full-power cast (0x19)")
				_check(not host.rod.is_within_cast_range(host.rod.swimmer_pos, 0), "the bobber lands beyond the cast range")
				_next(9)
			elif host.rod.state == FishingRod.STATE_PAN_TO_BOBBER and in_phase > 10:
				_fail("the cast didn't reach the water (back to the rod tip)")
				_done()
			elif in_phase > 600:
				_fail("no splash (rod state %x)" % host.rod.state)
				_done()
		9:
			# A fish of kind 1 by the bobber once the splash's ripple stopped scaring them (7 frames).
			if in_phase == 12:
				_bait_fish = _place_fish(host)
			if host.rod.state == FishingRod.STATE_BITE:
				_check(host.rod.hooked.active and not _bait_fish.active, "a bite: the fish is on the hook")
				_next(10)
			elif in_phase > 1500 or host.rod.state != FishingRod.STATE_FLOATING:
				_fail("no bite (rod state %x)" % host.rod.state)
				_done()
		10:
			if host.rod.hooked.state == FishingRod.HOOK_TAKEN:
				_check(GameState.item_count("dw1:meat") == _meat_before - 1, "the fish took the Meat from the bag")
				GameLoop.press("pad_cross")
				_next(11)
			elif in_phase > 300 or host.rod.state != FishingRod.STATE_BITE:
				_fail("it never took the bait (hooked state %x, rod %x)" % [host.rod.hooked.state, host.rod.state])
				_done()
		11:
			if in_phase == 1:
				_check(host.rod.state == FishingRod.STATE_REELING and host.rod.tension_display, "struck in time: reeling, the gauge on")
				_check(host.hud._shown, "the gauge is drawn")
			# Hold ✕ below half the limit, let go above it (the rod is out of the text box's way).
			if not host.rod.text_box.is_visible() and host.rod.tension_level < host.rod.tension_limit / 2:
				GameLoop.press("pad_cross")
			if host.rod.text_box.is_visible() and in_phase > 1 and in_phase % 12 == 0:
				GameLoop.press("pad_cross")
			if host.rod.state == FishingRod.STATE_CATCH:
				_next(12)
			elif host.rod.state in [FishingRod.STATE_LINE_CUT, FishingRod.STATE_HOOK_LOST, FishingRod.STATE_FLOATING]:
				_fail("lost the fish while reeling (rod state %x, tension %d)" % [host.rod.state, host.rod.tension_level])
				_done()
			elif in_phase > 3000:
				_fail("never landed it (tension %d)" % host.rod.tension_level)
				_done()
		12:
			if host.rod.state == FishingRod.STATE_END and host.rod.text_box.is_visible():
				var item := GameData.id_of("items/item_data", "dw1:digisnapper")
				_check(GameState.item_count(item) == 1, "the Digisnapper is in the bag")
				_check(int(GameState.state["partner"]["care"]["fish_caught"]) == _caught_before + 1, "fishCaught + 1")
				var lines := host.rod.text_box.lines
				_length = lines[1]
				_check(lines[0] == "Digisnapper" and lines[1].begins_with("Total length ") and lines[2] == "I got one!",
						"the catch message (%s)" % [lines])
				_check(_field.scripts.boxes.boxes[FishingTextBox.BOX_ID].registered, "in UI box 2")
				_next(13)
			elif in_phase > 400:
				_fail("no catch message (rod state %x)" % host.rod.state)
				_done()
		13:
			if in_phase == 15:
				GameLoop.press("pad_cross")
			if tamer.state == Tamer.STATE_FREE:
				_check(not host.is_fishing() and _field.clock_host.clock.running, "the catch ends fishing; time runs")
				_done()
			elif in_phase > 600:
				_fail("fishing didn't end after the catch (rod state %x)" % host.rod.state)
				_done()


## The tamer on land 40 px above the shore's middle, facing the water (as test_fishing_rod.gd).
func _to_the_shore(tamer: Tamer, host: FishingHost) -> void:
	var cam := host.fishing.camera
	var shore: Array = host.fishing.map["water"]["shore"]
	var mid := Vector2i((int(shore[6][0]) + int(shore[7][0])) / 2, (int(shore[6][1]) + int(shore[7][1])) / 2)
	var land: Vector3i = cam.ground_at(mid.x, mid.y - 40)
	var water: Vector3i = cam.ground_at(mid.x, mid.y + 60)
	tamer.position = Content.psx_to_godot([land.x, land.y, land.z])
	tamer.set_direction((PsxMath.to_euler_angles(water.x - land.x, 0, water.z - land.z).y - 0x800) & 0xFFF)


## A kind-1 fish (Digisnapper, 55-85) next to the bobber, idle for long (FISH_spawnFish's fields).
func _place_fish(host: FishingHost) -> Fishing.Fish:
	var f := host.fishing
	var fish := f.alloc_fish()
	if fish == null:
		for x in f.fish:
			if x.active and x.kind != Fishing.SEADRAMON:
				fish = x
				break
	else:
		fish.active = true
		f.fish_count += 1
	f.spawn_fish(fish, 1)
	fish.pos = host.rod.swimmer_pos + Vector3i(30, 0, 0)
	fish.state = Fishing.STATE_IDLE
	fish.transparency = Fishing.OPAQUE
	fish.time_next_move = 5000
	fish.lifetime = 5000
	return fish


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed.append(what)


func _fail(what: String) -> void:
	_failed.append(what)


func _done() -> void:
	_phase = -1
	if _reached < 13 and _failed.is_empty():
		_failed.append("stopped before the end (phase %d)" % _reached)
	for line in _failed:
		print("FAIL: ", line)
	print("%s: fishing scan (%s; reached phase %d; %s)" % ["OK" if _failed.is_empty() else "FAILED %d" % _failed.size(), START_MAP,
			_reached, _length])
	get_tree().quit(1 if not _failed.is_empty() else 0)


func _screen() -> String:
	return str(GameData.map(GameState.state["world"]["screen"]).get("file", ""))
