extends SceneTree
## Items (specs/inventory.md): the item rules (scripts/systems/item_use.gd), the inventory
## (scripts/ui/inventory.gd) opened from the △ menu, and the feeding scene (partner state 5), on
## the porter output:
##   godot --headless --path . -s res://tests/test_inventory.gd
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
var use: ItemUse
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
	_setup()
	_where()
	_refusing()
	_hunger()
	_effects()
	_open_inventory()
	_cursor_and_options()
	_move()
	_sort()
	_drop()
	_back_to_menu()
	_feeding()
	_refused()
	_teardown()
	print("%s: inventory checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _key(id: int) -> String:
	return str(data.item(id).get("key", ""))


func _care() -> Dictionary:
	return gs.state["partner"]["care"]


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
	partner.care = care
	var spawn := map.spawn(0)
	tamer.place(spawn)
	partner.place_for_spawn(spawn)
	use = ItemUse.new()
	use.game_state = gs
	use.data = data
	use.care = care
	use.clock = clock
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
	host.menu.sound = sounds
	host.menu.game_state = gs
	host.menu.data = data
	host.inventory.sound = sounds
	host.inventory.game_state = gs
	host.inventory.data = data
	var stats: Dictionary = gs.state["partner"]["stats"]
	stats["base"]["max_hp"] = 1000
	stats["base"]["max_mp"] = 1000
	stats["current"]["hp"] = 1000
	stats["current"]["mp"] = 1000


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


## The bag: Meat x3, Sm.recovery x2, Rest pillow x1, empty, then Medicine x1.
func _fill_bag() -> void:
	var slots: Array = gs.state["inventory"]["slots"]
	for i in slots.size():
		slots[i] = null
	slots[0] = {"item": _key(38), "amount": 3}
	slots[1] = {"item": _key(0), "amount": 2}
	slots[2] = {"item": _key(0x22), "amount": 1}
	slots[4] = {"item": _key(14), "amount": 1}


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


## A game frame at 60 fps: the models draw 3 Godot frames per game frame, as in the game (a loop's
## last frame then falls between game frames: ISSUES.md I-11).
func _frame_60(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	tamer.tick()
	if not host.is_open():
		partner.tick()
	host.tick()
	boxes.step()
	for k in 3:
		tamer._process(1.0 / 60.0)
		partner._process(1.0 / 60.0)


func _until(done: Callable, limit := 40) -> void:
	for i in limit:
		if done.call():
			return
		_frame()


## A button pressed for one frame, then released.
func _press(button: int) -> void:
	_frame(button)
	_frame()


# --- ItemUse ---------------------------------------------------------------------------------------

func _where() -> void:
	_check(use.can_use(38), "Meat: usable in the field")
	_check(use.can_use(0), "Sm.recovery (both): usable in the field")
	_check(not use.can_use(15), "a buff disk (battle): not in the field")
	_check(use.can_use(15, ItemUse.BATTLE), "a buff disk: in battle")
	_check(not use.can_use(123), "a key item (none): nowhere")


func _refusing() -> void:
	var c := _care()
	c["condition"] = 0
	care.item_scold_flag = 0
	_check(use.will_refuse(0x22), "a passive chip is always refused")
	_check(use.will_refuse(123), "a key item is always refused")
	_check(not use.will_refuse(126), "Noble Mane (needs a Rookie) is taken by a Rookie")
	_check(use.will_refuse(125), "Giga Hand (needs a Champion) is refused by a Rookie")
	_check(not use.will_refuse(71), "Grey Claws (a Champion target) is taken by a Rookie")
	var to_ultimate := -1
	for id in range(0x47, 0x73):
		var target = data.evolution_item_target(id).get("target")
		if target != null and int(data.digimon(int(target["id"])).get("level", {}).get("id", 0)) == 5:
			to_ultimate = id
			break
	if to_ultimate >= 0:
		_check(use.will_refuse(to_ultimate), "an evolution item two levels up is refused")
	c["discipline"] = 100
	_check(not use.will_refuse(0) and care.item_scold_flag == 0, "full discipline: a recovery item is taken")
	c["discipline"] = 0
	care.item_scold_flag = 2
	_check(not use.will_refuse(0) and care.item_scold_flag == 0, "after a scold the next item is taken")
	# The favourite food (Meat for Agumon): refused 20 % of the time when not hungry, never hungry.
	var refused := 0
	for i in 400:
		if use.will_refuse(38):
			refused += 1
	_check(refused > 40 and refused < 120, "the favourite refused about 20 %% of the time (%d / 400)" % refused)
	c["condition"] = Care.HUNGRY
	refused = 0
	for i in 100:
		if use.will_refuse(38):
			refused += 1
	_check(refused == 0, "a hungry partner never refuses its favourite")
	c["condition"] = 0


func _hunger() -> void:
	var c := _care()
	var threshold := int(care.raise_data()["energy_threshold"])
	c["condition"] = Care.HUNGRY
	c["energy_level"] = threshold
	c["happiness"] = 0
	c["discipline"] = 0
	_check(use.handle_food_feed(39), "hungry and full: it shows it liked it")
	_check(c["happiness"] == 5 and c["discipline"] == 1 and c["condition"] & Care.HUNGRY == 0, "hungry and full: +5 / +1, no longer hungry")
	c["condition"] = Care.HUNGRY
	c["energy_level"] = 0
	_check(not use.handle_food_feed(39) and c["happiness"] == 5, "hungry, not full, not the favourite: nothing")
	_check(use.handle_food_feed(38), "hungry, the favourite: it liked it")
	c["condition"] = 0
	_check(not use.handle_food_feed(39) and c["happiness"] == 2 and c["discipline"] == -1, "fed while not hungry: -3 / -2")
	_check(not use.handle_food_feed(0) and c["happiness"] == 2, "not food: nothing")


func _effects() -> void:
	var c := _care()
	var stats: Dictionary = gs.state["partner"]["stats"]
	var cap := int(care.raise_data()["energy_cap"])
	c["energy_level"] = 0
	c["happiness"] = 0
	c["poop_level"] = 10
	c["train_boost_timer"] = 999
	use.apply(38)
	_check(c["energy_level"] == 12 * 14 / 10 and c["happiness"] == 2, "Meat (the favourite): energy x1.4, happiness +2")
	_check(c["poop_level"] == 9 and c["train_boost_timer"] == 0, "food: poop level -1, the training boost cleared")
	c["energy_level"] = cap
	use.apply(38)
	_check(c["energy_level"] == cap, "energy capped at energy_cap")
	stats["current"]["hp"] = 900
	use.apply(0)
	_check(stats["current"]["hp"] == 1000, "Sm.recovery: HP capped at the maximum")
	stats["current"]["hp"] = 0
	stats["current"]["mp"] = 0
	use.apply(4)
	_check(stats["current"]["mp"] == 0, "HP 0: a recovery item does nothing")
	stats["current"]["hp"] = 1000
	stats["base"]["max_hp"] = 9800
	use.apply(0x1B)
	_check(stats["base"]["max_hp"] == 9999, "an HP chip: the maximum capped at 9999")
	stats["base"]["max_hp"] = 1000
	c["remaining_lifetime"] = 10
	use.apply(0x1D)
	_check(c["remaining_lifetime"] == 0, "a DV chip: lifetime -24, not below 0")
	c["condition"] = Care.SICK | Care.INJURED
	use.apply(14)
	_check(c["condition"] & (Care.SICK | Care.INJURED) == 0, "Medicine: sickness and injury always cured")
	c["condition"] = Care.POOPY
	use.apply(32)
	_check(c["condition"] & Care.POOPY == 0 and c["poop_level"] == int(care.raise_data()["poop_timer"]), "Port. potty: not poopy, the poop timer reset")
	c["condition"] = 0
	use.handle_item_sickness(100)
	_check(c["condition"] & Care.SICK != 0, "a 100 % sickness chance makes it sick")
	c["condition"] = 0
	tamer.set_state(Tamer.STATE_FREE)
	_check(not use.apply(71), "an evolution item: not ported (no effect)")


# --- the inventory --------------------------------------------------------------------------------

func _open_inventory() -> void:
	_fill_bag()
	_care()["condition"] = 0
	tamer.set_state(Tamer.STATE_FREE)
	_frame(Pad.TRIANGLE)
	_until(func(): return host.menu.menu_state == GameMenu.STATE_OPEN)
	_frame()
	_press(Pad.CONFIRM)
	_check(host.menu.menu_state == GameMenu.STATE_ITEMS or host.inventory.active, "✕ on Items: the menu hands over")
	_until(func(): return boxes.boxes[1].state == UIBoxes.STATE_OPEN, 60)
	var inv := host.inventory
	_check(inv.active and boxes.boxes[0].state == UIBoxes.STATE_OPEN, "the inventory's list is open")
	_check(boxes.boxes[1].state == UIBoxes.STATE_OPEN, "and its description box")
	_check(inv.names.size() == inv.size() and inv.names[4] == 4, "the name cells are drawn")
	_check(tamer.animation_id() == 4, "the tamer looks into his bag (animation 4)")


func _cursor_and_options() -> void:
	var inv := host.inventory
	sounds.played.clear()
	_press(Pad.DOWN)
	_check(inv.pointer == 2 and sounds.played == [2], "down: the next row, sound 2")
	_press(Pad.RIGHT)
	_check(inv.pointer == 3, "right: the right column")
	_press(Pad.RIGHT)
	_check(inv.pointer == 3, "right on the right column: nothing")
	_press(Pad.LEFT)
	_press(Pad.UP)
	_check(inv.pointer == 0, "back to the first slot")
	# Held down: repeats after 11 frames.
	for i in 14:
		_frame(Pad.DOWN)
	_frame()
	_check(inv.pointer >= 4, "a held down repeats (%d)" % inv.pointer)
	for i in 30:
		_frame(Pad.UP)
	_frame()
	_check(inv.pointer == 0, "held up back to the top")
	inv.pointer = 3
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_OPEN)
	_check(boxes.boxes[2].state == UIBoxes.STATE_OPEN and inv.option == Inventory.OPTION_USE, "✕: the options open on Use")
	_check(inv.option_color(Inventory.OPTION_USE) == 0xA and inv.option_color(Inventory.OPTION_DROP) == 0xA, "an empty slot: Use and Drop grey")
	_check(inv.option_color(Inventory.OPTION_MOVE) == 9 and inv.option_color(Inventory.OPTION_SORT) == 9, "Move and Sort are always white")
	_press(Pad.CONFIRM)
	_check(boxes.boxes[2].state == UIBoxes.STATE_OPEN and inv.active, "✕ on grey Use does nothing")
	inv.pointer = 0
	_check(inv.option_color(Inventory.OPTION_USE) == 9, "Meat: Use white in the field")
	inv.pointer = 3
	_press(Pad.CANCEL)
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_CLOSED)
	_check(boxes.boxes[2].state == UIBoxes.STATE_CLOSED and inv.active, "△ closes the options only")


func _option(index: int) -> void:
	var inv := host.inventory
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_OPEN)
	for i in index:
		_press(Pad.DOWN)
	_check(inv.option == index, "option %d selected" % index)
	_press(Pad.CONFIRM)


func _move() -> void:
	var inv := host.inventory
	inv.pointer = 0
	_option(Inventory.OPTION_MOVE)
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_CLOSED)
	_check(boxes.boxes[0].state == UIBoxes.STATE_MENU and inv.move_source == 0, "Move: the list marks the source")
	_press(Pad.RIGHT)
	sounds.played.clear()
	_press(Pad.CONFIRM)
	_check(inv.item_at(0) == _key(0) and inv.item_at(1) == _key(38), "the two slots swapped")
	_check(sounds.played.has(4) and boxes.boxes[0].state == UIBoxes.STATE_OPEN, "sound 4, the list back to normal")
	_option(Inventory.OPTION_MOVE)
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_CLOSED)
	sounds.played.clear()
	_press(Pad.CANCEL)
	_check(sounds.played.has(3) and boxes.boxes[0].state == UIBoxes.STATE_OPEN, "△ cancels a move with sound 3")


func _sort() -> void:
	var inv := host.inventory
	_option(Inventory.OPTION_SORT)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN)
	_check(boxes.boxes[3].state == UIBoxes.STATE_OPEN, "Sort: its box opens")
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_CLOSED, 60)
	# The action goes back to 0 the frame after box 2 has closed.
	_frame()
	var order: Array = data.sort_order(11)["categories"].map(func(x): return int(x))
	var ranks := []
	for slot in inv.size():
		if inv.item_at(slot) == "":
			ranks.append(1000)
			continue
		var record: Dictionary = data.item(inv.item_at(slot))
		ranks.append(order.find(int(record["sort_category"])) * 200 + int(record["id"]))
	var sorted := ranks.duplicate()
	sorted.sort()
	_check(ranks == sorted, "sorted by the mode's category order, then id; empty slots last")
	_check(inv.action == Inventory.ACTION_NONE, "both boxes closed after sorting")


func _drop() -> void:
	var inv := host.inventory
	var slot := -1
	for i in inv.size():
		if inv.item_at(i) == _key(0):
			slot = i
	inv.pointer = slot
	_option(Inventory.OPTION_DROP)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN)
	_check(inv.drop_option == 1, "the question starts on No")
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_CLOSED)
	_check(inv.item_at(slot) == _key(0), "No keeps the item")
	_press(Pad.CANCEL)
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_CLOSED)
	_option(Inventory.OPTION_DROP)
	_until(func(): return boxes.boxes[3].state == UIBoxes.STATE_OPEN)
	_press(Pad.LEFT)
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[2].state == UIBoxes.STATE_CLOSED, 60)
	_frame()
	_check(inv.item_at(slot) == "", "Yes drops the whole slot")


func _back_to_menu() -> void:
	_press(Pad.CANCEL)
	_until(func(): return not host.inventory.active, 60)
	_check(not host.inventory.active, "△ on the list closes the inventory")
	_until(func(): return host.menu.menu_state == GameMenu.STATE_OPEN, 60)
	_check(host.menu.active and host.menu.selection == GameMenu.ITEMS and host.is_open(), "the △ menu opens again, on Items")


func _feeding() -> void:
	var inv := host.inventory
	var c := _care()
	c["condition"] = Care.HUNGRY
	c["discipline"] = 100
	care.item_scold_flag = 0
	var meat_before: int = gs.item_count(38)
	_press(Pad.CONFIRM)
	_until(func(): return boxes.boxes[1].state == UIBoxes.STATE_OPEN, 60)
	for i in inv.size():
		if inv.item_at(i) == _key(38):
			inv.pointer = i
			break
	_option(Inventory.OPTION_USE)
	_until(func(): return partner.state == Partner.STATE_FEED, 60)
	_check(partner.state == Partner.STATE_FEED and tamer.held_item == _key(38), "Use: the tamer holds the Meat, the partner comes")
	_check(not host.is_open() and not inv.active, "the menu and the inventory are gone")
	sounds.played.clear()
	# The hold-out pose (anim 5) loops only its frames 10-11 (ISSUES.md I-10): once there it doesn't start over.
	var reached := false
	var restarted := false
	for i in 600:
		if partner.state == Partner.STATE_NORMAL:
			break
		_frame()
		if tamer.animation_id() == 5:
			if tamer.scene_frame() >= 10:
				reached = true
			elif reached:
				restarted = true
	_check(reached and not restarted, "the tamer holds the item out without taking it from the bag again")
	_check(partner.state == Partner.STATE_NORMAL and tamer.state == Tamer.STATE_FREE, "the scene ends, both free")
	_check(sounds.played.has(12), "sound 12 when he holds it out")
	_check(gs.item_count(38) == meat_before - 1, "eaten: one Meat less (%d -> %d)" % [meat_before, gs.item_count(38)])
	_check(tamer.held_item == "", "his hands are empty")


## A refused item (ISSUES.md I-11): a key item is always refused; the tamer puts it back (anim 4,
## a loop that ends a pass) and both are free; the item stays in the bag.
func _refused() -> void:
	var key := _key(115)
	var slots: Array = gs.state["inventory"]["slots"]
	slots[10] = {"item": key, "amount": 1}
	tamer.set_state(Tamer.STATE_FREE)
	host.start_feeding(key)
	_check(partner.state == Partner.STATE_FEED, "a key item handed over")
	var refused := false
	for i in 600:
		if partner.state == Partner.STATE_NORMAL:
			break
		_frame_60()
		if partner.sub_state == 7:
			refused = true
	_check(refused, "the partner refuses it")
	_check(partner.state == Partner.STATE_NORMAL and tamer.state == Tamer.STATE_FREE and tamer.camera_follow, "refused: both free, the camera follows")
	_check(tamer.held_item == "" and gs.item_count(key) == 1, "refused: his hands empty, the item still in the bag")
