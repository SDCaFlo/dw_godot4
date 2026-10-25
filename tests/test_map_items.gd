extends SceneTree
## The items on the ground and the chests (scripts/field/map_items.gd, map_chests.gd, the tamer's
## states 7 and 14) against specs/map_items.md §2, on the porter output:
##   godot --headless --path . -s res://tests/test_map_items.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false
var data: Node
var gs: Node
var map: FieldMap
var items: MapItems
var chests: MapChests
var interp: ScriptInterpreter
var ctx: ScriptContext
var boxes: UIBoxes
var area: TextArea
var pad: Pad
var tamer: Tamer
var partner: Partner


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
	_spawn_items()
	_pickup()
	_bag_full()
	_spawn_chests()
	_take_chest()
	_chest_full()
	_real_setup()
	_teardown()
	print("%s: map item checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


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
	items = MapItems.new()
	items.data = data
	root.add_child(items)
	chests = MapChests.new()
	chests.field = map
	chests.game_state = gs
	root.add_child(chests)
	boxes = UIBoxes.new()
	area = TextArea.new(data, "en_us")
	ctx = ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	pad = Pad.new()
	var tb := TextBoxes.new(boxes, area, ctx, pad, data, gs)
	interp = ScriptInterpreter.new(ctx, ScriptFiles.new(), tb)
	interp.game_state = gs
	interp.data = data
	interp.field = map
	interp.pad = pad
	interp.map_items = items
	interp.map_chests = chests
	partner = Partner.new()
	tamer = Tamer.new()
	tamer.partner = partner
	tamer.pad = pad
	tamer.map_items = items
	tamer.map_chests = chests
	tamer.game_state = gs
	tamer.data = data
	tamer.pickup_box = MessageBox.new(boxes, area)
	tamer.pickup_box.arrow = false
	interp.tamer = tamer


func _teardown() -> void:
	tamer.free()
	partner.free()
	boxes.free()
	gs.free()
	data.free()


func _run(code: Array) -> void:
	var bytes := PackedByteArray([8, 0, 1, 0, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code))
	interp.files._cache[500] = bytes
	interp.call_section(500, 1)
	interp.tick_script()


## One frame of the tamer with the pad holding `buttons`.
func _frame(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	tamer.tick()
	boxes.step()


## Frames (holding `buttons`) until `done` is true, at most 30.
func _until(done: Callable, buttons: int) -> void:
	for i in 30:
		if done.call():
			return
		_frame(buttons)


func _empty_bag() -> void:
	for i in gs.state["inventory"]["slots"].size():
		gs.state["inventory"]["slots"][i] = null


# --- §2.1: spawnItem ------------------------------------------------------------------------------

func _spawn_items() -> void:
	items.clear()
	_eq(items.spawn(1, Vector2i(50, 50)), 0, "the first free slot")
	_eq(items.slots[0]["point"], Vector3(50, 0, -50), "the tile's centre: (tile - 50) * 100 + 50, (50 - tile) * 100 - 50")
	_eq(items.slots[0]["item"], data.item(1)["key"], "kept by key")
	for k in 10:
		items.spawn(2, Vector2i(10 + k, 10))
	_eq(items.spawn(3, Vector2i(5, 5)), -1, "11 slots: a 12th item finds none")
	_eq([items.near(Vector2i(51, 49)), items.near(Vector2i(52, 50))], [0, -1], "near: within one tile on both axes")
	items.clear()
	# SPAWN_ITEM item, x, z
	_run([0x74, 4, 40, 0, 60, 0, 0xFE, 0])
	_eq([items.item_at(0), items.slots[0]["tile"]], [data.item(4)["key"], Vector2i(40, 60)], "SPAWN_ITEM item, tile x, tile z")
	items.clear()


# --- §2.2: the pickup -------------------------------------------------------------------------------

func _pickup() -> void:
	_empty_bag()
	items.spawn(1, Vector2i(50, 50))
	tamer.position = Content.psx_to_godot([150, 0, -150])  # tile (51, 51)
	tamer.set_state(Tamer.STATE_FREE)
	tamer.has_picked_up = false
	_frame()
	_eq([tamer.state, tamer.picked_up_drop, tamer.has_picked_up], [Tamer.STATE_PICKUP, 0, true],
			"next to the item: tamer state 7")
	_frame()
	_eq([tamer.sub_state, tamer.camera_follow], [1, false], "sub-state 0: the text, the camera stops")
	_frame()
	_eq([tamer.sub_state, boxes.boxes[1].state], [2, UIBoxes.STATE_OPENING], "sub-state 1: box 1 opens")
	_frame(Pad.CONFIRM)
	_eq(tamer.sub_state, 2, "✕ in the first 4 frames: ignored")
	for i in 5:
		_frame()
	_frame(Pad.CONFIRM)
	_eq(tamer.sub_state, 4, "✕ after 4 frames: the item fits (sound 3 and 7)")
	_frame()
	_eq([tamer.state, gs.item_count(1), items.item_at(0), tamer.camera_follow], [Tamer.STATE_FREE, 1, "", true],
			"sub-state 4: in the bag, off the ground, free")


func _bag_full() -> void:
	_empty_bag()
	gs.give_item(1, 99)
	items.spawn(1, Vector2i(50, 50))
	tamer.set_state(Tamer.STATE_FREE)
	tamer.has_picked_up = false
	_frame()
	for i in 8:
		_frame()
	_frame(Pad.CONFIRM)
	_eq([tamer.sub_state, tamer.take_chest_state], [3, 1], "the item at 99: the bag is full (TAKE_CHEST_STATE 1)")
	for i in 5:
		_frame()
	_frame(Pad.CONFIRM)
	_frame()
	_eq([tamer.state, gs.item_count(1), items.item_at(0) != ""], [Tamer.STATE_FREE, 99, true],
			"the box closes, the item stays on the ground")
	_frame()
	_eq(tamer.state, Tamer.STATE_FREE, "HAS_PICKED_UP_ITEM: not again while he stays next to it")
	tamer.position = Content.psx_to_godot([1050, 0, -1050])
	_frame()
	tamer.position = Content.psx_to_godot([150, 0, -150])
	_frame()
	_eq(tamer.state, Tamer.STATE_PICKUP, "after leaving it, again")
	tamer.set_state(Tamer.STATE_FREE)
	items.clear()
	_empty_bag()
	_eq([gs.give_item(5, 0), gs.state["inventory"]["slots"][0]], [true, {"item": data.item(5)["key"], "amount": 0}],
			"giveItem(item, 0) takes an empty slot with 0")
	_empty_bag()


# --- §2.3: spawnChest -------------------------------------------------------------------------------

func _spawn_chests() -> void:
	chests.clear()
	map.load_map("MAYO01")
	gs.clear_trigger(700)
	var k := chests.spawn(6, Vector3i(250, 0, -250), 0, 700)
	var c := chests.chest(k)
	var tile := FieldMap.model_tile(250, -250)
	_eq([c["taken"], c["tray"], c["location"]], [false, 0, Vector3i(tile.x * 100 - 4950, 0, 4950 - tile.y * 100)],
			"not taken: tray in; the chest at its tile's centre")
	_eq(c["tile"], tile + Vector2i(0, 4), "rotation 0: the interaction tile is tileY + 4")
	var blocked := 0
	for tz in range(tile.y - 3, tile.y + 3):
		for tx in range(tile.x - 3, tile.x + 3):
			if map._cell(tx, tz) == 0x80:
				blocked += 1
	_eq([map._cell(tile.x - 2, tile.y - 2), map._cell(tile.x + 1, tile.y + 1), blocked >= 16], [0x80, 0x80, true],
			"setImpassableSquare(x, y, 2): cells x - 2 .. x + 1 blocked")
	var fronts := []
	for r in [0x800, 0x400, 0xC00]:
		fronts.append(chests.chest(chests.spawn(6, Vector3i(250, 0, -250), r, 701)).get("tile") - tile)
	_eq(fronts, [Vector2i(0, -4), Vector2i(-4, 0), Vector2i(4, 0)], "0x800: y - 4, 0x400: x - 4, 0xC00: x + 4")
	gs.set_trigger(702)
	_eq(chests.chest(chests.spawn(6, Vector3i(0, 0, 0), 0, 702))["tray"], MapChests.TRAY_OUT, "its trigger set: taken, tray out")
	chests.clear()
	# SPAWN_CHEST item, x, y, z, rotation, trigger
	_run([0x75, 7, 0xFA, 0, 0, 0, 0x06, 0xFF, 0, 0x08, 0xBC, 0x02, 0xFE, 0])
	var s := chests.chest(0)
	_eq([s.get("item"), s.get("rotation"), s.get("trigger")], [7, 0x800, 700], "SPAWN_CHEST item, x, y, z, rotation, trigger")
	chests.clear()


# --- §2.4: taking a chest --------------------------------------------------------------------------

func _take_chest() -> void:
	_empty_bag()
	map.load_map("MAYO01")
	gs.clear_trigger(700)
	var k := chests.spawn(6, Vector3i(250, 0, -250), 0, 700)
	var front: Vector2i = chests.chest(k)["tile"]
	var at := FieldMap.tile_centre(front)
	tamer.position = Content.psx_to_godot([at.x, 0, at.y])
	_eq(chests.near(tamer.tile()), k, "checkChestCollision: at the interaction tile")
	tamer.interacted_chest = k
	tamer.set_state(Tamer.STATE_CHEST)
	_frame()
	_eq([tamer.sub_state, partner.state, tamer.take_chest_state], [1, Partner.STATE_IDLE, 0], "sub-state 0: the partner idles")
	var frames := 0
	while tamer.sub_state == 1 and frames < 20:
		_frame()
		frames += 1
	_eq([frames, chests.chest(k)["tray"], chests.chest(k)["taken"]], [8, MapChests.TRAY_OUT, true],
			"the tray slides out 20 a frame: 8 frames to -160, then taken")
	for i in 6:
		_frame(Pad.CONFIRM)
	_eq([tamer.sub_state, gs.is_trigger_set(700), gs.item_count(6)], [4, true, 0], "✕ held after 5 frames: the trigger set")
	for i in 7:
		_frame(Pad.CONFIRM)
	_eq([tamer.state, gs.item_count(6), partner.state], [Tamer.STATE_FREE, 1, Partner.STATE_NORMAL],
			"sub-state 4: the item given as the box closes")
	tamer.interacted_chest = k
	tamer.set_state(Tamer.STATE_CHEST)
	_frame()
	_eq(tamer.take_chest_state, 2, "the second time: empty (TAKE_CHEST_STATE 2)")
	var waited := 0
	while tamer.sub_state == 1 and waited < 10:
		_frame()
		waited += 1
	_eq([tamer.sub_state, chests.chest(k)["tray"]], [4, MapChests.TRAY_OUT],
			"its tray is already out: straight to the box once box 1 is free (the last one was closing)")
	for i in 7:
		_frame(Pad.CONFIRM)
	_eq([tamer.state, gs.item_count(6)], [Tamer.STATE_FREE, 1], "nothing more")
	chests.clear()


func _chest_full() -> void:
	_empty_bag()
	gs.give_item(6, 99)
	gs.clear_trigger(700)
	var k := chests.spawn(6, Vector3i(250, 0, -250), 0, 700)
	tamer.interacted_chest = k
	tamer.set_state(Tamer.STATE_CHEST)
	_until(func(): return tamer.sub_state == 2, 0)
	_until(func(): return tamer.sub_state != 2, Pad.CONFIRM)
	_eq([tamer.sub_state, tamer.take_chest_state, gs.is_trigger_set(700)], [3, 1, false], "the bag is full: no trigger")
	_until(func(): return tamer.sub_state != 3, 0)
	_eq([tamer.sub_state, chests.chest(k)["tray"], chests.chest(k)["taken"]], [4, 0, false],
			"the tray slides back: it can be opened again")
	for i in 7:
		_frame(Pad.CONFIRM)
	_eq([tamer.state, gs.item_count(6)], [Tamer.STATE_FREE, 99], "closed, nothing given")
	chests.clear()
	_empty_bag()


# --- a real map setup ---------------------------------------------------------------------------------

func _real_setup() -> void:
	# OGRE11's 0xFE section (script 137): SPAWN_CHEST item 110, trigger 672.
	map.load_map("OGRE11")
	chests.clear()
	gs.clear_trigger(672)
	ctx.current_script_id = 137
	interp.call_section(137, 0xFE, 0)
	for i in 5:
		interp.tick_script()
	var c := chests.chest(0)
	_eq([c.get("item"), c.get("trigger"), c.get("taken")], [110, 672, false], "OGRE11's setup spawns its chest")
	chests.clear()


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])
