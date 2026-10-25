extends SceneTree
## The △ menu (scripts/ui/game_menu.gd, scripts/field/hosts/menu_host.gd, the tamer's states 1 / 6 /
## 9 / 13, the partner's 4 / 15) against specs/game_menu.md, on the porter output:
##   godot --headless --path . -s res://tests/test_game_menu.gd
## Exits 1 if a check fails.

## playSound(0, n) calls, in order.
class SoundLog extends Node:
	var played: Array = []

	func play_sound(_slot: int, value: int) -> int:
		played.append(value)
		return 0


var _failed := 0
var _checks := 0
var _started := false
var data: Node
var gs: Node
var map: FieldMap
var boxes: UIBoxes
var area: TextArea
var pad: Pad
var clock: Clock
var care: Care
var tamer: Tamer
var partner: Partner
var menu: GameMenu
var host: MenuHost
var sounds: SoundLog


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("maps/MAYO01/map.json"):
		print("SKIP: porter output missing")
		quit(0)
		return false
	_digits()
	_setup()
	_cursor()
	_open_and_close()
	_sleep_option()
	_praise_scold(GameMenu.PRAISE)
	_praise_scold(GameMenu.SCOLD)
	_pat_height()
	_npc_frozen()
	_teardown()
	print("%s: game menu checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## convertValueToDigits and the digit sprites (§2.7).
func _digits() -> void:
	_check(GameMenu.date_digits(1, 2) == [1], "day 1: one digit")
	_check(GameMenu.date_digits(12, 2) == [1, 2], "day 12")
	_check(GameMenu.date_digits(345, 3) == [3, 4, 5], "year 345")
	_check(GameMenu.date_digits(5, 3) == [5], "year 5: no leading zeros")
	_check(GameMenu.digit_uv(0) == Vector2i(0x78, 0x34), "digit 0's sprite")
	_check(GameMenu.digit_uv(1) == Vector2i(0x60, 0x28), "digit 1's sprite")
	_check(GameMenu.digit_uv(4) == Vector2i(0x78, 0x28), "digit 4's sprite")
	_check(GameMenu.digit_uv(5) == Vector2i(0x50, 0x34), "digit 5's sprite")
	_check(GameMenu.digit_uv(9) == Vector2i(0x70, 0x34), "digit 9's sprite")


func _setup() -> void:
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()
	map = FieldMap.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	map.add_child(camera)
	var doors := Node3D.new()
	doors.name = "Doors"
	map.add_child(doors)
	map.background = Sprite2D.new()
	root.add_child(map.background)
	root.add_child(map)
	map.load_map("MAYO01")
	sounds = SoundLog.new()
	boxes = UIBoxes.new()
	area = TextArea.new(data, "en_us")
	pad = Pad.new()
	clock = Clock.new()
	clock.game_state = gs
	clock.active = true
	clock.running = true
	tamer = load("res://scenes/field/tamer.tscn").instantiate()
	tamer.field = map
	tamer.camera = camera
	tamer.pad = pad
	tamer.game_state = gs
	tamer.data = data
	tamer.sound = sounds
	root.add_child(tamer)
	partner = load("res://scenes/field/partner.tscn").instantiate()
	partner.field = map
	partner.tamer = tamer
	partner.game_state = gs
	partner.sound = sounds
	partner.clock = clock
	root.add_child(partner)
	partner.load_digimon(data, gs.state["partner"]["digimon"])
	tamer.partner = partner
	care = Care.new()
	care.game_state = gs
	care.data = data
	care.clock = clock
	care.partner = partner
	care.tamer = tamer
	partner.care = care
	tamer.care = care
	var spawn := map.spawn(0)
	tamer.place(spawn)
	partner.place_for_spawn(spawn)
	menu = load("res://scenes/ui/game_menu.tscn").instantiate()
	menu.boxes = boxes
	menu.text_area = area
	menu.tamer = tamer
	menu.partner = partner
	menu.care = care
	menu.clock = clock
	menu.pad = pad
	menu.sound = sounds
	menu.game_state = gs
	menu.data = data
	host = MenuHost.new()
	host.tamer = tamer
	host.partner = partner
	host.menu = menu
	root.add_child(host)
	host.add_child(menu)
	tamer.open_menu = host.try_open


func _teardown() -> void:
	host.free()
	tamer.free()
	partner.free()
	care.free()
	clock.free()
	boxes.free()
	sounds.free()
	map.free()
	gs.free()
	data.free()


## One game frame as Field._frame runs it, then a Godot frame of the models.
func _frame(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	tamer.tick()
	if not host.is_open():
		partner.tick()
	host.tick()
	boxes.step()
	tamer._process(0.05)
	partner._process(0.05)


func _frames(n: int) -> void:
	for i in n:
		_frame()


## tickGameMenu's cursor (§2.3, the worked examples): `button` pressed this frame from `from`.
func _move(count: int, from: int, button: int) -> int:
	menu.count = count
	menu.selection = from
	menu.menu_state = GameMenu.STATE_OPENING
	pad.poll(0)
	pad.process()
	pad.poll(button)
	pad.process()
	menu.tick_box(0)
	return menu.selection


func _cursor() -> void:
	_check(_move(7, 1, Pad.UP) == 4, "7 options: up from 1 -> 4")
	_check(_move(7, 5, Pad.DOWN) == 2, "7 options: down from 5 -> 2")
	_check(_move(7, 1, Pad.LEFT) == 6, "7 options: left from 1 -> 6")
	_check(_move(7, 6, Pad.RIGHT) == 1, "7 options: right from 6 -> 1")
	_check(_move(7, 2, Pad.RIGHT) == 3, "7 options: right from 2 -> 3")
	_check(_move(8, 1, Pad.UP) == 7, "8 options: up from 1 -> 7 (Fishing)")
	_check(_move(8, 2, Pad.UP) == 5, "8 options: up from 2 -> 5")
	sounds.played.clear()
	_move(7, 1, Pad.RIGHT)
	_check(sounds.played == [2], "a cursor move plays sound 2")
	sounds.played.clear()
	_move(7, 1, 0)
	_check(sounds.played.is_empty(), "no move, no sound")


## Opens the menu with △ and waits until it is open.
func _open() -> void:
	_frames(2)
	_frame(Pad.TRIANGLE)
	for i in 10:
		if menu.menu_state == GameMenu.STATE_OPEN:
			break
		_frame()


func _open_and_close() -> void:
	gs.state["partner"]["care"]["condition"] = 0
	_frame(Pad.TRIANGLE)
	_check(host.is_open(), "△ in the walking state opens the menu")
	_check(tamer.state == Tamer.STATE_MENU, "the tamer goes to state 1")
	_check(not clock.running, "game time stops")
	_check(not tamer.camera_follow, "the camera stops following him")
	_frame()
	_check(tamer.state == Tamer.STATE_STILL, "state 1 turns into 6 on his next tick")
	_check(menu.selection == GameMenu.ITEMS and menu.count == 7, "Items selected, 7 options (no fishing)")
	for i in 10:
		if menu.menu_state == GameMenu.STATE_OPEN:
			break
		_frame()
	_check(menu.menu_state == GameMenu.STATE_OPEN, "the menu is open once box 0 reached frame 4")
	# ✕ on Player: not ported yet (5e-3b), the menu stays open.
	var told := []
	menu.unported.connect(func(what): told.append(what))
	menu.selection = GameMenu.PLAYER
	sounds.played.clear()
	_frame(Pad.CONFIRM)
	_check(told == ["Player"] and sounds.played == [3], "✕ on Player: sound 3, named as not ported")
	_check(host.is_open(), "the menu stays open")
	_frame()
	sounds.played.clear()
	_frame(Pad.TRIANGLE)
	_check(sounds.played.has(4), "△ plays sound 4")
	_check(not host.is_open() and clock.running, "△ closes the menu, game time runs")
	_check(tamer.state == Tamer.STATE_FREE and tamer.camera_follow, "the tamer is free, the camera follows")
	_frames(8)
	_check(boxes.boxes[0].state == UIBoxes.STATE_CLOSED and boxes.boxes[0].frame == 0, "box 0 is free again")
	# No menu while a box is busy.
	boxes.create_static(0, 0, 0, Rect2i(-10, -10, 20, 20))
	_frame(Pad.TRIANGLE)
	_check(not host.is_open() and tamer.state == Tamer.STATE_FREE, "box 0 in use: △ opens nothing")
	boxes.remove_static(0)
	_frame()


func _sleep_option() -> void:
	gs.state["partner"]["care"]["condition"] = 0
	_open()
	menu.selection = GameMenu.SLEEP
	sounds.played.clear()
	_frame(Pad.CONFIRM)
	_check(sounds.played == [4], "✕ on Sleep while not sleepy: sound 4")
	_check(host.is_open() and partner.state == Partner.STATE_NORMAL, "and nothing else")
	gs.state["partner"]["care"]["condition"] = 1
	_frame()
	_check(not menu.is_disabled(GameMenu.SLEEP), "Sleep is enabled once the partner is sleepy")
	sounds.played.clear()
	_frame(Pad.CONFIRM)
	_check(sounds.played.has(3), "✕ on Sleep: sound 3")
	_check(partner.state == Partner.STATE_SLEEP and not host.is_open(), "the partner sleeps, the menu closes")
	_check(clock.running, "game time runs (the sleep scene stops it itself)")
	partner.set_state(Partner.STATE_NORMAL)
	tamer.set_state(Tamer.STATE_FREE)
	gs.state["partner"]["care"]["condition"] = 0
	care.sleep_enabled = false
	_check(not host.menu_sleep(), "the debug Sleep is refused while not sleepy")
	_frames(8)


## Praise / scold from the menu (§2.5): the scene, its sounds and animations, the care values.
func _praise_scold(entry: int) -> void:
	var label := "praise" if entry == GameMenu.PRAISE else "scold"
	var values: Dictionary = gs.state["partner"]["care"]
	values["discipline"] = 30
	values["happiness"] = 0
	care.item_scold_flag = 0
	tamer.place(map.spawn(0))
	partner.place_for_spawn(map.spawn(0))
	_open()
	menu.selection = entry
	sounds.played.clear()
	_frame(Pad.CONFIRM)
	var wanted := Partner.STATE_PRAISE if entry == GameMenu.PRAISE else Partner.STATE_SCOLD
	_check(partner.state == wanted and not host.is_open(), "%s: partner state %d, the menu closes" % [label, wanted])
	var tamer_animations := {}
	for i in 600:
		_frame()
		tamer_animations[tamer.animation_id()] = true
		if partner.state == Partner.STATE_NORMAL:
			break
	_check(partner.state == Partner.STATE_NORMAL and tamer.state == Tamer.STATE_FREE, "%s: both free at the end" % label)
	if entry == GameMenu.PRAISE:
		_check(sounds.played.has(14), "praise: sound 14")
		_check(tamer_animations.has(Tamer.ANIM_PAT_LOW), "praise: the low pat for a Rookie")
		_check(values["discipline"] == 25 and values["happiness"] == 5, "praise: discipline -5, happiness +30/10+2 (%d, %d)" % [values["discipline"], values["happiness"]])
	else:
		_check(sounds.played.has(13), "scold: sound 13")
		_check(tamer_animations.has(Tamer.ANIM_SCOLD), "scold: the tamer's animation 7")
		_check(values["discipline"] == 32 and values["happiness"] == -10, "scold: discipline +2, happiness -10 (%d, %d)" % [values["discipline"], values["happiness"]])
	_check(tamer.camera_follow, "%s: the camera follows again" % label)


## praise_pat_low: a Champion gets the high pat.
func _pat_height() -> void:
	var own: String = partner.digimon
	partner.digimon = "dw1:greymon"
	tamer.set_state(Tamer.STATE_PRAISE)
	tamer.tick()
	_check(tamer.animation_id() == Tamer.ANIM_PAT_HIGH, "a Champion gets the high pat (0x27)")
	partner.digimon = own
	tamer.set_state(Tamer.STATE_FREE)


## ISSUES.md I-9: while the menu is open a walking NPC stands frozen, animation included
## (overworld.c:1232); its walk goes on afterwards.
func _npc_frozen() -> void:
	var npc: Npc = load("res://scenes/field/npc.tscn").instantiate()
	npc.field = map
	root.add_child(npc)
	npc.load_digimon(data, gs.state["partner"]["digimon"])
	npc.position = tamer.position + Vector3(300, 0, 0)
	npc.start_animation(Partner.ANIM_WALK)
	npc.frozen = true
	var at := npc.position
	var frame: int = npc.animator.frame
	for i in 20:
		npc._process(0.05)
	_check(npc.position == at and npc.animator.frame == frame, "a frozen NPC neither walks nor animates")
	npc.frozen = false
	for i in 20:
		npc._process(0.05)
	_check(npc.position != at, "unfrozen, its walk goes on")
	npc.free()
