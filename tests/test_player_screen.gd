extends SceneTree
## The Player screen (scripts/ui/player_screen.gd and its tabs; specs/status_screens.md §4) opened
## from the △ menu, on the porter output:
##   godot --headless --path . -s res://tests/test_player_screen.gd
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
var host: MenuHost
var sounds: SoundLog
var screen: PlayerScreen


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("maps/MAYO01/map.json"):
		print("SKIP: porter output missing")
		quit(0)
		return false
	_setup()
	_open()
	_info()
	_chart()
	_medals()
	_cards()
	_back()
	_teardown()
	print("%s: player screen checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


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
	root.add_child(boxes)
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
	partner.data = data
	root.add_child(partner)
	partner.load_digimon(data, gs.state["partner"]["digimon"])
	tamer.partner = partner
	care = Care.new()
	care.game_state = gs
	care.data = data
	care.clock = clock
	care.partner = partner
	care.tamer = tamer
	care.initialize_partner()
	partner.care = care
	var spawn := map.spawn(0)
	tamer.place(spawn)
	partner.place_for_spawn(spawn)
	var use := ItemUse.new()
	use.game_state = gs
	use.data = data
	use.care = care
	host = MenuHost.new()
	host.tamer = tamer
	host.partner = partner
	host.care = care
	host.clock = clock
	host.boxes = boxes
	host.text_area = area
	host.pad = pad
	host.item_use = use
	root.add_child(host)
	host.start()
	for node in [host.menu, host.player_screen]:
		node.sound = sounds
		node.game_state = gs
		node.data = data
	screen = host.player_screen


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


func _frame(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	tamer.tick()
	if not host.is_open():
		partner.tick()
	host.tick()
	boxes.step()


func _press(button: int) -> void:
	_frame(button)
	_frame()


func _until(done: Callable, limit := 60) -> void:
	for i in limit:
		if done.call():
			return
		_frame()


func _open() -> void:
	# Something to show: Agumon and Greymon raised, medal 3 won, a key item, card 4 twice.
	var agumon: int = data.id_of("digimon/digimon_data", "dw1:agumon")
	var greymon: int = data.id_of("digimon/digimon_data", "dw1:greymon")
	gs.set_trigger(0x200 + agumon)
	gs.set_trigger(0x200 + greymon)
	gs.set_trigger(0x16C + 3)
	gs.set_trigger(0x2D)
	gs.state["script"]["cards"][str(data.card(4).get("key"))] = 2
	_frame(Pad.TRIANGLE)
	_until(func(): return host.menu.menu_state == GameMenu.STATE_OPEN)
	_frame()
	host.menu.selection = GameMenu.PLAYER
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_check(sounds.played.has(3), "✕ on PLAYER: sound 3")
	_until(func(): return screen.is_open and boxes.boxes[1].state == UIBoxes.STATE_OPEN)
	_check(screen.is_open and boxes.boxes[0].state != UIBoxes.STATE_OPEN, "the △ menu closes, the screen opens")
	_until(func(): return screen.menu_state == 1)
	_check(screen.menu_state == 1 and screen.tab == PlayerScreen.TAB_INFO, "Info shown once its strings are drawn")
	_check(not tamer.visible and not partner.visible, "the field's tamer and partner are hidden")


func _info() -> void:
	_check(host.digivice.showing, "the tamer's model shows on Info")
	_check(screen.info_tab.medal_count() == 1, "one medal counted")
	_check(_row_has_ink(PlayerInfoTab.PLAYTIME_ROW), "the play time is drawn into the text area")
	_check(_row_has_ink(0x30), "the tamer's name is drawn into the text area")
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_check(screen.menu_state == 1 and sounds.played.is_empty(), "✕ on Info: nothing")
	_press(Pad.LEFT)
	_check(screen.tab == PlayerScreen.TAB_INFO, "← on the first tab: nothing")


func _row_has_ink(row: int) -> bool:
	for y in range(row, row + 12):
		for x in 80:
			if area.pixel(x, y) != 0:
				return true
	return false


func _chart() -> void:
	var tab := screen.chart_tab
	sounds.played.clear()
	_press(Pad.RIGHT)
	_check(screen.tab == PlayerScreen.TAB_CHART and sounds.played == [2], "→: the chart, sound 2")
	_check(not host.digivice.showing, "the tamer's model goes with Info")
	_until(func(): return screen.menu_state == 1)
	_press(Pad.CONFIRM)
	_check(screen.menu_state == 2 and tab.column == 0 and tab.row == 0, "✕: the cursor at the first cell")
	_check(tab.selected_digimon == 1, "the first cell is Botamon (id 1): %d" % tab.selected_digimon)
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_check(screen.menu_state == 2 and sounds.played == [4], "✕ on a Digimon not raised: refused")
	# Agumon's cell.
	var agumon: int = data.id_of("digimon/digimon_data", "dw1:agumon")
	var b: Array = PlayerChartTab.BOXES[agumon - 1]
	var found := false
	for c in 9:
		for r in 9:
			tab.column = c
			tab.row = r
			if tab.column_x() + 2 == b[0] and r * 0x13 + 0x2B == b[1]:
				found = true
				break
		if found:
			break
	_check(found, "Agumon's cell is in the chart")
	_frame()
	_check(tab.selected_digimon == agumon, "the cursor on Agumon's cell selects Agumon (%d)" % tab.selected_digimon)
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_check(screen.menu_state == 3 and sounds.played == [3], "✕ on a raised Digimon: the detail, sound 3")
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_OPEN)
	_check(boxes.boxes[2].state == UIBoxes.STATE_OPEN, "box 2 opens")
	var paths: Dictionary = data.evolution_paths(agumon)["c"]
	_check(paths["to"].map(func(v): return int(v)).has(data.id_of("digimon/digimon_data", "dw1:greymon")), "Agumon's paths lead to Greymon")
	_press(Pad.CANCEL)
	_check(screen.menu_state == 2, "△: the detail closes")
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_CLOSED and boxes.boxes[2].frame == 0)
	_check(boxes.boxes[2].state == UIBoxes.STATE_CLOSED, "box 2 is free again")
	# The cursor's bounds: the first columns hold even rows only.
	tab.column = 0
	tab.row = 0
	_press(Pad.DOWN)
	_check(tab.row == 2, "↓ in the first column: two rows")
	for i in 12:
		_press(Pad.RIGHT)
	_check(tab.column == 8, "the cursor stops at the last column")
	for i in 12:
		_press(Pad.DOWN)
	_check(tab.row == 6, "the last column has 7 rows")
	_press(Pad.CANCEL)
	_check(screen.menu_state == 1 and tab.selected_digimon == -1, "△: back to the chart")


func _medals() -> void:
	var tab := screen.medals_tab
	_press(Pad.RIGHT)
	_check(screen.tab == PlayerScreen.TAB_MEDALS, "→: the medals")
	_until(func(): return screen.menu_state == 1)
	_check(screen.menu_state == 1, "the medal strings drawn")
	_press(Pad.CONFIRM)
	_check(screen.menu_state == 2 and tab.selector == 0, "✕: the cursor on the first medal")
	_check(not host.medal_view.showing, "medal 0 not won: no model")
	for i in 3:
		_press(Pad.RIGHT)
	_check(tab.selector == 3 and screen.menu_state == 3, "→ to the won medal 3: its texture and strings")
	_until(func(): return screen.menu_state == 2)
	_check(screen.menu_state == 2 and tab.active_medal == 3, "medal 3's cell is the active one")
	_frame()
	_check(host.medal_view.showing and tab.rotation > 0, "the medal turns")
	_press(Pad.RIGHT)
	_press(Pad.RIGHT)
	_check(tab.selector == 4, "the cursor stops at the row's end")
	_press(Pad.DOWN)
	_press(Pad.DOWN)
	_press(Pad.DOWN)
	_check(tab.selector == 14, "and at the last row")
	_press(Pad.CANCEL)
	_check(screen.menu_state == 1, "△: back")


func _cards() -> void:
	var tab := screen.cards_tab
	_press(Pad.RIGHT)
	_check(screen.tab == PlayerScreen.TAB_CARDS and not host.medal_view.showing, "→: the cards, the medal goes")
	_until(func(): return screen.menu_state == 1)
	_press(Pad.CONFIRM)
	_check(screen.menu_state == 2 and tab.selected == 0, "✕: the cursor on the first card")
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_check(screen.menu_state == 2 and sounds.played.is_empty(), "✕ on a card not owned: nothing")
	for i in 4:
		_press(Pad.RIGHT)
	_check(tab.selected == 4, "the cursor on card 4")
	_press(Pad.CONFIRM)
	_check(screen.menu_state == 3 and screen.card_amount(4) == 2, "✕ on an owned card: its picture (2 owned)")
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_OPEN and boxes.boxes[3].state == UIBoxes.STATE_OPEN)
	_check(boxes.boxes[2].state == UIBoxes.STATE_OPEN and boxes.boxes[3].state == UIBoxes.STATE_OPEN, "boxes 2 and 3 open")
	_check(tab._picture != null, "the card's picture loads")
	_press(Pad.CANCEL)
	_check(screen.menu_state == 2, "△: the picture closes")
	_until(func(): return boxes.boxes[2].frame == 0 and boxes.boxes[3].frame == 0)
	for i in 8:
		_press(Pad.DOWN)
	_check(tab.selected == 4 + 55, "the cursor stops at the last row")
	_press(Pad.CANCEL)
	_check(screen.menu_state == 1, "△: back")
	_press(Pad.RIGHT)
	_check(screen.tab == PlayerScreen.TAB_CARDS, "→ on the last tab: nothing")


func _back() -> void:
	sounds.played.clear()
	_press(Pad.CANCEL)
	_check(sounds.played.has(4) and not screen.is_open, "△ on a tab closes the screen")
	_until(func(): return host.menu.menu_state == GameMenu.STATE_OPEN, 80)
	_check(host.menu.menu_state == GameMenu.STATE_OPEN and host.is_open(), "the △ menu opens again")
	_check(tamer.visible and partner.visible, "the tamer and the partner are shown again")
