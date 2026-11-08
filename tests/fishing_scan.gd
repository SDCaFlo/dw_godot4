extends Node
## Fishing in the real field scene (specs/fishing.md §7, steps F4 / F6) on MAYO10 (map 8): the
## fish swim from the map's load, the △ menu's Fishing icon (disabled without a rod), the menu
## starts the rod (tamer state 11, game time stopped), the bait menu (box 3), aiming, and △ puts
## the rod away (tamer state 0, game time running):
##   godot --headless --fixed-fps 60 --path . res://tests/fishing_scan.tscn
## Exits 1 if a check fails.

const START_MAP := "MAYO10"
const TIMEOUT := 4000
## TRIGGER_HAVE_OLD_FISHROD.
const OLD_ROD := 45

var _field: Node
var _phase := 0
var _phase_frame := 0
var _start_frame := 0
var _failed: Array[String] = []
var _minute_at_start := -1


func _ready() -> void:
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	GameState.new_game("dw1:agumon")
	_field.map_session.partner.load_digimon(GameData, "dw1:agumon")
	_field.map_session.debug_change_map(START_MAP, 0)
	_start_frame = GameLoop.frame_count


func _host() -> FishingHost:
	return _field.fishing_host


func _next(phase: int) -> void:
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
			_check(host.rod.bait_menu.items[0] >= 0 and host.rod.bait_menu.total_rows == 1, "one row: the Meat")
			_next(5)
		5:
			if in_phase == 10:
				GameLoop.press("pad_cross")
			if host.rod.state == FishingRod.STATE_AIM:
				_check(host.rod.bait == GameData.id_of("items/item_data", "dw1:meat"), "Meat is the bait")
				_check(host.rod.display_line and host.rod.display_swimmer, "the line and the bobber show")
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
				_done()
			elif in_phase > 600:
				_fail("the rod wasn't put away (rod state %x)" % host.rod.state)
				_done()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed.append(what)


func _fail(what: String) -> void:
	_failed.append(what)


func _done() -> void:
	_phase = -1
	for line in _failed:
		print("FAIL: ", line)
	print("%s: fishing scan (%s)" % ["OK" if _failed.is_empty() else "FAILED %d" % _failed.size(), START_MAP])
	get_tree().quit(1 if not _failed.is_empty() else 0)


func _screen() -> String:
	return str(GameData.map(GameState.state["world"]["screen"]).get("file", ""))
