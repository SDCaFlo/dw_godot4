extends SceneTree
## The Digimon screen (scripts/ui/digimon_screen.gd and its tabs; specs/status_screens.md §3) opened
## from the △ menu, on the porter output:
##   godot --headless --path . -s res://tests/test_digimon_screen.gd
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
var screen: DigimonScreen


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
	_status()
	_techniques_summary()
	_grid_cells()
	_equipping()
	_help()
	_back()
	_teardown()
	print("%s: digimon screen checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
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
	for node in [host.menu, host.digimon_screen]:
		node.sound = sounds
		node.game_state = gs
		node.data = data
	screen = host.digimon_screen


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
	_frame(Pad.TRIANGLE)
	_until(func(): return host.menu.menu_state == GameMenu.STATE_OPEN)
	_frame()
	host.menu.selection = GameMenu.DIGIMON
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_check(sounds.played.has(3), "✕ on DIGIMON: sound 3")
	_until(func(): return screen.is_open and boxes.boxes[1].state == UIBoxes.STATE_OPEN)
	_check(screen.is_open and boxes.boxes[0].state != UIBoxes.STATE_OPEN, "the △ menu closes, the screen opens")
	_until(func(): return screen.menu_state == 1)
	_check(screen.menu_state == 1 and screen.tab == DigimonScreen.TAB_STATUS, "Status shown once its strings are drawn")
	_check(not tamer.visible and not partner.visible, "the field's tamer and partner are hidden")


func _status() -> void:
	_check(host.digivice.showing, "the partner's model shows on Status")
	_check(screen.digimon_name() != "", "the partner's Digimon has a name")
	sounds.played.clear()
	_press(Pad.LEFT)
	_check(screen.tab == DigimonScreen.TAB_STATUS and sounds.played.is_empty(), "← on the first tab: nothing")


func _techniques_summary() -> void:
	sounds.played.clear()
	_press(Pad.RIGHT)
	_check(screen.tab == DigimonScreen.TAB_TECHNIQUES and sounds.played == [2], "→: the Techniques tab, sound 2")
	_check(not host.digivice.showing, "the model goes with the Status tab")
	_until(func(): return screen.menu_state == 1)
	var spit_fire: int = data.id_of("moves/move_data", "dw1:spit_fire")
	_check(screen.equipped(0) == spit_fire, "Agumon starts with Spit Fire equipped (%d)" % screen.equipped(0))


func _grid_cells() -> void:
	var tab := screen.techniques_tab
	var all_match := true
	var count := 0
	for row in 7:
		for col in 8:
			var id := tab.technique_at(Vector2i(col, row))
			if id < 0:
				all_match = false
				continue
			count += 1
			var cell: Dictionary = data.move(id)["menu_cell"]
			if int(cell["row"]) != row or int(cell["column"]) != col:
				all_match = false
	_check(all_match and count == 56, "every grid cell's technique has that menu_cell (%d cells)" % count)


func _equipping() -> void:
	var tab := screen.techniques_tab
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_until(func(): return screen.menu_state == 6)
	_check(screen.menu_state == 6, "✕: the grid opens after the window's transition")
	var spit_fire: int = data.id_of("moves/move_data", "dw1:spit_fire")
	var cell: Dictionary = data.move(spit_fire)["menu_cell"]
	tab.cursor = DigimonTechniquesTab.CURSOR_MIN + Vector2i(int(cell["column"]) * 0x12, int(cell["row"]) * 0xF)
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_check(screen.equipped(0) == -1 and sounds.played == [3], "✕ on the equipped Spit Fire unequips it")
	sounds.played.clear()
	_press(Pad.CANCEL)
	_check(screen.menu_state == 6 and sounds.played == [4], "△ without an attack equipped: stays in the grid")
	_press(Pad.CONFIRM)
	_check(screen.equipped(0) == spit_fire, "✕ again equips it in the first free slot")
	# Not learned: Fire Tower (Agumon can use it, but hasn't learned it).
	var fire_tower: int = data.id_of("moves/move_data", "dw1:fire_tower")
	var ft: Dictionary = data.move(fire_tower)["menu_cell"]
	tab.cursor = DigimonTechniquesTab.CURSOR_MIN + Vector2i(int(ft["column"]) * 0x12, int(ft["row"]) * 0xF)
	if not gs.has_move(fire_tower):
		sounds.played.clear()
		_press(Pad.CONFIRM)
		_check(sounds.played == [4] and screen.equipped(1) == -1, "a technique not learned: refused")
	# Learned but not one of Agumon's: refused.
	var other := -1
	for record in data.records("moves/move_data"):
		if record.has("menu_cell") and not record.has("learned_with") and not screen.digimon_moves().has(int(record["id"])):
			other = int(record["id"])
			break
	gs.learn_move(other)
	var oc: Dictionary = data.move(other)["menu_cell"]
	tab.cursor = DigimonTechniquesTab.CURSOR_MIN + Vector2i(int(oc["column"]) * 0x12, int(oc["row"]) * 0xF)
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_check(sounds.played == [4], "a learned technique Agumon can't use: refused")
	# Three slots full: the fourth is refused.
	var usable := screen.digimon_moves()
	var equipped_now := 1
	for id in usable:
		if equipped_now >= 4 or id == spit_fire or not data.move(id).has("menu_cell"):
			continue
		gs.learn_move(id)
		var c: Dictionary = data.move(id)["menu_cell"]
		tab.cursor = DigimonTechniquesTab.CURSOR_MIN + Vector2i(int(c["column"]) * 0x12, int(c["row"]) * 0xF)
		sounds.played.clear()
		_press(Pad.CONFIRM)
		equipped_now += 1
	_check(equipped_now == 4 and sounds.played == [4], "the fourth technique: no free slot, refused")
	_check(screen.equipped(1) >= 0 and screen.equipped(2) >= 0, "slots 2 and 3 filled")
	# The cursor stays in the grid.
	for i in 12:
		_press(Pad.UP)
	_check(tab.cursor.y == DigimonTechniquesTab.CURSOR_MIN.y, "the cursor stops at the top row")
	for i in 12:
		_press(Pad.RIGHT)
	_check(tab.cursor.x == DigimonTechniquesTab.CURSOR_MIN.x + 7 * 0x12, "and at the last column")


func _help() -> void:
	sounds.played.clear()
	_press(Pad.SQUARE)
	_check(sounds.played == [3], "□: the help page, sound 3")
	_until(func(): return screen.menu_state == 8)
	_check(screen.menu_state == 8, "the help page shows once its 8 lines are drawn")
	sounds.played.clear()
	_press(Pad.CANCEL)
	_check(sounds.played == [4], "△ on the help page: sound 4")
	_until(func(): return screen.menu_state == 6)
	_check(screen.menu_state == 6, "back to the grid")
	_press(Pad.CANCEL)
	_until(func(): return screen.menu_state == 1)
	_check(screen.menu_state == 1, "△ with an attack equipped: back to the summary")


func _back() -> void:
	sounds.played.clear()
	_press(Pad.CANCEL)
	_check(sounds.played.has(4) and not screen.is_open, "△ on the summary closes the screen")
	_until(func(): return host.menu.menu_state == GameMenu.STATE_OPEN, 80)
	_check(host.menu.menu_state == GameMenu.STATE_OPEN and host.is_open(), "the △ menu opens again")
	_check(tamer.visible and partner.visible, "the tamer and the partner are shown again")
