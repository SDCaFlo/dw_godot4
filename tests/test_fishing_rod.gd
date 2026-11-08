extends SceneTree
## The rod's logic (scripts/systems/fishing/: FishingRod, FishingTextBox, FishingBaitMenu) against
## specs/fishing.md §2.4, §2.6-2.13 (step F3), on MAYO10's camera with a fake FishingWorld:
##   godot --headless --path . -s res://tests/test_fishing_rod.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false
var data: Node
var map_node: FieldMap
var camera := FishingCamera.new()


## A tamer on land above MAYO10's shore, facing the water; a fake inventory, sounds and texts.
class FakeWorld:
	extends FishingWorld
	var data: Node
	var pos := Vector3i.ZERO
	var yaw := 0
	var playing := false
	var anims: Array[int] = []
	var types: Array = []
	var given: Array = []
	var removed: Array = []
	var bag_full := false
	var rod := 2
	var caught := 0
	var sounds: Array = []
	var scrolls: Array = []
	var follow := true
	var chance := 0
	var loop_count := -1

	func bone_matrix(bone: int) -> PackedInt32Array:
		var m := PsxMath.identity()
		var lift: int = {1: -200, 6: -500, 9: -300}.get(bone, -100)
		m[9] = pos.x
		m[10] = pos.y + lift
		m[11] = pos.z
		return m

	func tamer_position() -> Vector3i:
		return pos

	func tamer_yaw() -> int:
		return yaw

	func set_tamer_yaw(v: int) -> void:
		yaw = v

	func start_animation(id: int) -> void:
		anims.append(id)

	func animation_playing() -> bool:
		return playing

	func set_animation_loop_count(n: int) -> void:
		loop_count = n

	func inventory_types() -> Array:
		return types

	func is_food(item: int) -> bool:
		return item >= 0x26 and item <= 0x46

	func give_item(item: int, count: int) -> bool:
		given.append([item, count])
		return not bag_full

	func remove_item(item: int, count: int) -> void:
		removed.append([item, count])

	func best_rod() -> int:
		return rod

	func add_fish_caught() -> void:
		caught += 1

	func play_sound(bank: int, id: int) -> void:
		sounds.append([bank, id])

	func text(id: String) -> String:
		return data.text(id, "en_us")

	func item_name(item: int) -> String:
		return data.localize(data.item(item).get("name", {}), "en_us")

	func bite_chance(_bait: int, _kind: int) -> int:
		return chance

	func scroll_camera(dx: int, dy: int) -> void:
		scrolls.append(Vector2i(dx, dy))

	func set_camera_follow(on: bool) -> void:
		follow = on


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("maps/MAYO10/map.json"):
		print("SKIP: porter output missing")
		quit(0)
		return false
	PsxMath.setup(data)
	map_node = FieldMap.new()
	var cam3d := Camera3D.new()
	cam3d.name = "Camera3D"
	map_node.add_child(cam3d)
	var doors := Node3D.new()
	doors.name = "Doors"
	map_node.add_child(doors)
	map_node.background = Sprite2D.new()
	map_node.add_child(map_node.background)
	root.add_child(map_node)
	map_node.load_map("MAYO10")
	_remap_and_tension()
	_text_box()
	_bait_menu()
	_bobber()
	_start_and_cast()
	_bite_and_strike()
	_catch()
	_snag()
	_line_cut_and_hook_lost()
	_seadramon()
	_rod_pose_and_camera()
	map_node.free()
	print("%s: fishing rod checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## A fresh session: the fishing world, the rod, the fake world, a pad. The tamer stands on land
## 40 px above the shore's middle; `water` is a ground point in the water straight below.
func _session() -> Dictionary:
	var cam := FishingCamera.new()
	cam.ws = map_node.world_screen_matrix()
	cam.h = map_node.viewport_distance()
	cam.background = Vector2i(map_node.background_size)
	cam.offset = Vector2i(map_node.drawing_offset().round())
	var f := Fishing.new()
	f.setup(data.fishing_map(8), data.fishing()["kinds"])
	f.camera = cam
	var shore: Array = f.map["water"]["shore"]
	var mid := Vector2i((int(shore[6][0]) + int(shore[7][0])) / 2, (int(shore[6][1]) + int(shore[7][1])) / 2)
	var w := FakeWorld.new()
	w.data = data
	w.pos = cam.ground_at(mid.x, mid.y - 40)
	var water: Vector3i = cam.ground_at(mid.x, mid.y + 60)
	w.yaw = (PsxMath.to_euler_angles(water.x - w.pos.x, 0, water.z - w.pos.z).y - 0x800) & 0xFFF
	w.types = [38]
	for i in 29:
		w.types.append(0xFF)
	var pad := Pad.new()
	var rod := FishingRod.new()
	rod.setup(f, w, pad, data.fishing()["snagged_items"])
	return {"fishing": f, "rod": rod, "world": w, "pad": pad, "water": water}


func _press(pad: Pad, bits: int) -> void:
	pad.polled_previous = pad.polled
	pad.polled = bits


## One game frame: the rod (the tamer's tick), then the world object, then the boxes' ticks.
func _frame(s: Dictionary, bits := 0) -> void:
	var pad: Pad = s["pad"]
	_press(pad, bits)
	var rod: FishingRod = s["rod"]
	rod.tick_rod()
	s["fishing"].tick_world()
	if rod.bait_menu.shown:
		rod.bait_menu.tick(pad)
	rod.text_box.tick(pad)


## FISH_remapClamped (fish_model.c:61) and FISH_updateTension (fish.c:2036).
func _remap_and_tension() -> void:
	_check(FishingRod.remap_clamped(0, 0, 0x14, 0x64, 0x190) == 0x64, "remap at x0")
	_check(FishingRod.remap_clamped(0x14, 0, 0x14, 0x64, 0x190) == 0x190, "remap at x1")
	_check(FishingRod.remap_clamped(40, 0, 0x14, 0x64, 0x190) == 0x190, "remap clamps past x1")
	_check(FishingRod.remap_clamped(10, 0, 0x14, 0x64, 0x190) == 0xFA, "remap halfway (rounded)")
	_check(FishingRod.remap_clamped(5, 10, 0, 1, 3) == 2, "remap with x1 < x0 swaps them")
	var s := _session()
	var rod: FishingRod = s["rod"]
	rod.rod_type = 1
	rod.begin_tension()
	_check(rod.tension_limit == 5000 and rod.tension_display, "old rod: limit 5000")
	rod.rod_type = 2
	rod.begin_tension()
	_check(rod.tension_limit == 10000, "amazing rod: limit 10000")
	rod.hooked.size = 50
	rod.hooked.state = FishingRod.HOOK_STRUGGLE
	rod.pressed_frames = 0
	rod.update_tension()
	_check(rod.tension_level == -0xA6, "✕ up, not pulling: −0xA6")
	rod.tension_level = 0
	rod.pressed_frames = 1
	rod.update_tension()
	_check(rod.tension_level == 0x47, "✕ down, size 50: +0x47")
	rod.tension_level = 0
	rod.hooked.state = FishingRod.HOOK_PULL
	rod.hooked.size = 300
	rod.update_tension()
	_check(rod.tension_level == 0x1F4, "✕ down, pulling, size 300: +0x1F4")
	rod.tension_level = 0
	rod.pressed_frames = 0
	rod.update_tension()
	_check(rod.tension_level == 0x53, "✕ up, pulling, size 300: +0x53")
	for size in [[50, 15], [175, 10], [300, 5]]:
		rod.begin_tension()
		rod.hooked.size = size[0]
		rod.hooked.state = FishingRod.HOOK_PULL
		rod.pressed_frames = 1
		rod.tension_level = rod.tension_limit
		var frames := 0
		var result := 0
		while result == 0 and frames < 40:
			result = rod.update_tension()
			frames += 1
		_check(result == 1 and frames == size[1], "size %d: the line snaps after %d frames at the limit (%d)" % [size[0], size[1], frames])
	rod.begin_tension()
	rod.hooked.size = 50
	rod.hooked.state = FishingRod.HOOK_STRUGGLE
	rod.pressed_frames = 0
	rod.tension_level = -rod.tension_limit + 0x50
	_check(rod.update_tension() == 2, "at −limit the hook comes out")
	_check(rod.tension_color == Color8(0, 0, 0xFF), "−limit is blue")
	rod.tension_level = rod.tension_limit / 2 - 0x47
	rod.pressed_frames = 1
	rod.update_tension()
	_check(rod.tension_color == Color8(0xFF, 0xFF, 0), "+limit / 2 is yellow")
	rod.tension_level = 0x29
	rod.pressed_frames = 0
	rod.hooked.state = FishingRod.HOOK_STRUGGLE
	rod.hooked.size = 300
	rod.update_tension()
	_check(rod.tension_level == -0x7D and rod.tension_bars() == 4, "the gauge: remap(level, ±limit, 0, 9)")
	rod.tension_level = 0
	_check(rod.tension_bars() == 5, "level 0 shows 5 bars (rounded)")


## FISH_showTextBox / _tickTextBox (fish.c:1452-1541).
func _text_box() -> void:
	var box := FishingTextBox.new()
	var sounds := []
	box.play_sound = func(b: int, i: int) -> void: sounds.append([b, i])
	var pad := Pad.new()
	pad.polled = Pad.CONFIRM
	box.show(["a", "b"], Vector3i(1, 2, 3), pad)
	_check(pad.polled == 0 and box.is_visible() and box.lines == ["a", "b", "", ""], "show: the pad cleared, 4 lines")
	for i in 5:
		_press(pad, 0)
		box.tick(pad)
	_press(pad, Pad.CONFIRM)
	box.tick(pad)
	_check(box.is_visible(), "✕ before 10 frames doesn't close it")
	for i in 4:
		_press(pad, 0)
		box.tick(pad)
	_press(pad, Pad.CONFIRM)
	box.tick(pad)
	_check(not box.is_visible() and sounds == [[0, 3]] and pad.polled == 0, "✕ from 10 frames closes it, sound 0 / 3")
	box.show(["x"], Vector3i.ZERO, pad)
	_press(pad, Pad.CANCEL)
	box.tick(pad)
	_check(not box.is_visible(), "△ closes it at once")


## FISH_openBaitMenu / _tickBaitMenu (fish.c:1154-1385).
func _bait_menu() -> void:
	var menu := FishingBaitMenu.new()
	var inv := [38, 0xFF, 1, 40, 41, 42, 43]
	for i in 23:
		inv.append(0xFF)
	var food := func(t: int) -> bool: return t >= 0x26 and t <= 0x46
	_check(menu.open(inv, food, Vector2i(10, 20)), "opens with food")
	_check(menu.items.slice(0, 6) == [0, 3, 4, 5, 6, -1] and menu.total_rows == 3, "food slots in order, 2 a row")
	_check(menu.start_rect == Rect2i(5, 15, 10, 10) and menu.features() == 2, "grows from the tamer's point")
	var pad := Pad.new()
	for i in 4:
		_press(pad, Pad.DOWN)
		menu.tick(pad)
		_press(pad, 0)
		menu.tick(pad)
	_check(menu.cursor_row == 2, "↓ stops at the last row")
	_press(pad, Pad.LEFT)
	menu.tick(pad)
	_check(menu.column == 1, "← from column 0 wraps to 1")
	_press(pad, Pad.CONFIRM)
	menu.tick(pad)
	_check(menu.shown, "✕ on an empty cell does nothing")
	_press(pad, Pad.UP)
	menu.tick(pad)
	var row_before := menu.cursor_row
	for i in 12:
		_press(pad, Pad.UP)
		menu.tick(pad)
	_check(row_before == 1 and menu.cursor_row == 0, "held ↑ repeats after 11 unchanged frames, then stops at 0")
	_press(pad, Pad.CONFIRM)
	menu.tick(pad)
	_check(not menu.shown and menu.selected == 3, "✕ chooses the slot (row 0, column 1 = slot 3)")
	menu.open(inv, food, Vector2i.ZERO)
	_press(pad, Pad.CANCEL)
	menu.tick(pad)
	_check(not menu.shown and menu.selected == -1, "△ cancels")
	_check(not menu.open([1, 2], food, Vector2i.ZERO), "no food: it doesn't open")


## FISH_bobberCommand's sequences and the drag (fish.c:2321-2555).
func _bobber() -> void:
	var s := _session()
	var rod: FishingRod = s["rod"]
	rod.bobber_command(FishingRod.CMD_LAND)
	var seq: Array[int] = []
	for i in 9:
		rod.bobber_command(FishingRod.CMD_TICK)
		seq.append(rod.swimmer_sprite)
	_check(seq.slice(0, 7) == [1, 2, 3, 4, 5, 4, 3] and rod.swimmer_state == 8 or rod.swimmer_state == 9,
			"landing: sprites 1 2 3 4 5 4 3, then floating (%s)" % [seq])
	rod.bobber_command(FishingRod.CMD_BIG_NIBBLE)
	_check(rod.swimmer_state == 11, "command 12 enters state 11 like command 11")
	seq = []
	for i in 6:
		rod.bobber_command(FishingRod.CMD_TICK)
		seq.append(rod.swimmer_sprite)
	_check(seq.slice(0, 4) == [4, 5, 6, 7] and rod.swimmer_state == 13, "taken: 4 5 6 7, then under (13)")
	_check(s["world"].sounds.has([8, 4]), "the bobber goes under: sound 8 / 4")
	_check(FishingRod._drag(100) == 93 and FishingRod._drag(5) == 4 and FishingRod._drag(-5) == -4 and FishingRod._drag(0) == 0,
			"drag: v − v × 300 >> 12, at least 1")


## The menu to the bobber in the water (states 2, 3, 1, 0xE96, 6, 7, 8, 9).
func _start_and_cast() -> void:
	var s := _session()
	var rod: FishingRod = s["rod"]
	var w: FakeWorld = s["world"]
	w.rod = 0
	rod.load_fishing()
	_check(rod.rod_type == 2, "no rod falls through to type 2 (fish.c:4608)")
	w.rod = 1
	rod.load_fishing()
	_check(rod.rod_type == 1 and rod.state == FishingRod.STATE_PAN_TO_TAMER and rod.display_rod, "old rod; state 2, the rod shown")
	_check(not w.follow and rod.camera_control, "the camera stops following; fishing scrolls it")
	var frames := 0
	while rod.state == FishingRod.STATE_PAN_TO_TAMER and frames < 200:
		_frame(s)
		frames += 1
	_check(rod.state == FishingRod.STATE_BAIT_MENU, "panned to the tamer, then the bait menu (%d frames)" % frames)
	_frame(s)
	_check(rod.bait_menu.shown and rod.bait_menu.items[0] == 0, "frame 0 of state 3 opens the menu")
	_frame(s, Pad.CONFIRM)
	_frame(s)
	_check(rod.state == FishingRod.STATE_CHOOSE and rod.bait == 38 and w.anims.back() == 0x1B, "Meat chosen: anim 0x1B, state 1")
	w.playing = true
	_frame(s, Pad.RIGHT)
	_check(w.yaw != rod.state and rod.state == FishingRod.STATE_CHOOSE, "→ turns while 0x1B plays")
	w.yaw = (w.yaw - 0x40) & 0xFFF
	w.playing = false
	_frame(s)
	_check(rod.state == FishingRod.STATE_PAN_TO_BOBBER and rod.display_swimmer and rod.display_line, "cast: the bobber and the line show")
	_check(rod.swimmer_mode == FishingRod.MODE_AT_TIP and w.anims.back() == 0x1C and rod.item_shown, "at the rod tip, anim 0x1C, the bait shows")
	frames = 0
	while rod.state == FishingRod.STATE_PAN_TO_BOBBER and frames < 200:
		_frame(s)
		frames += 1
	_check(rod.state == FishingRod.STATE_AIM, "panned to the bobber: aiming")
	w.playing = true
	_frame(s, Pad.CONFIRM)
	_check(rod.state == FishingRod.STATE_THROWING and w.anims.back() == 0x1D and rod.swimmer_gravity == 0x1E, "✕: the wind-up")
	for i in 4:
		_frame(s)
	_frame(s, Pad.ALT)
	_check(rod.state == FishingRod.STATE_FLYING and rod.throw_power == 0x19 and w.sounds.has([8, 0]), "○: full power (0x14 + 5), sound 8 / 0")
	_check(rod.swimmer_gravity == 3 and rod.swimmer_dist == 0 and w.anims.back() == 0x1E, "flying: gravity 3, no line length, anim 0x1E")
	frames = 0
	while rod.state == FishingRod.STATE_FLYING and frames < 300:
		_frame(s)
		frames += 1
	_check(rod.state == FishingRod.STATE_FLOATING, "the bobber splashes into the water (%d frames)" % frames)
	_check(w.sounds.has([8, 2]) and w.loop_count == 1 and rod.swimmer_state == 7, "splash: sound 8 / 2, loopCount 1, command 7")
	_check(rod.swimmer_pos.y == 0 and not rod.item_shown, "on the water; the bait sprite hidden")
	_check(not rod.is_within_cast_range(rod.swimmer_pos, 0), "beyond the cast range")


## A session with the bobber floating at `water` (the splash done by hand).
func _floating() -> Dictionary:
	var s := _session()
	var rod: FishingRod = s["rod"]
	rod.load_fishing()
	rod.camera_control = true
	rod.bait = 38
	rod.item_slot = 0
	rod.display_swimmer = true
	rod.display_line = true
	rod.swimmer_pos = s["water"]
	rod._splash()
	return s


func _hook_a_fish(s: Dictionary, kind: int, size: int) -> Fishing.Fish:
	var f: Fishing = s["fishing"]
	var rod: FishingRod = s["rod"]
	var fish := f.alloc_fish()
	fish.active = true
	f.fish_count += 1
	f.spawn_fish(fish, mini(kind, 5))
	fish.kind = kind
	fish.size = size
	fish.pos = rod.swimmer_pos + Vector3i(20, 0, 0)
	fish.state = Fishing.STATE_IDLE
	fish.transparency = 0x80
	return fish


func _bite_and_strike() -> void:
	var s := _floating()
	var rod: FishingRod = s["rod"]
	var w: FakeWorld = s["world"]
	var f: Fishing = s["fishing"]
	_check(rod.state == FishingRod.STATE_FLOATING, "floating")
	_check(f.attractor != null and f.attract_radius == 0x64, "the splash's ripple scares fish within 0x64")
	f.vsync_frame = 1
	for i in 8:
		_frame(s)
	_check(f.attractor == null, "until its 7 frames are over")
	Rng.set_seed(21)
	var bitten := _hook_a_fish(s, 1, 60)
	w.chance = 100
	f.vsync_frame = 19
	_frame(s)
	_check(rod.state == FishingRod.STATE_FLOATING, "no bite off the 20th frame")
	f.vsync_frame = 20
	_frame(s)
	# (The same frame's population tick spawns another fish, so the count stays.)
	_check(rod.state == FishingRod.STATE_BITE and rod.hooked.active and not bitten.active, "a bite: state 0xA, the fish leaves the pool")
	_check(rod.nibble_time >= 0x14 and rod.nibble_time <= 0x28 and rod.catching_time == 0x1E, "small fish: nibble 0x14-0x28, catching 0x1E")
	_check(rod.power_left == 60 + 0x96 and rod.power_max == rod.power_left + 0x64, "power = size + 0x96, max + 0x64")
	# Too fast: a strike while it nibbles.
	_frame(s, Pad.CONFIRM)
	_check(rod.text_box.lines[0] == "Too fast!" and rod.text_box.lines[1] == "But I still got my bait!", "too fast (%s)" % [rod.text_box.lines])
	_check(rod.hooked.state == FishingRod.HOOK_ESCAPE and rod.state == FishingRod.STATE_FLOATING, "the fish escapes; the bobber floats again")
	# Hooked in time.
	var t := _floating()
	rod = t["rod"]
	w = t["world"]
	f = t["fishing"]
	Rng.set_seed(22)
	_hook_a_fish(t, 1, 60)
	w.chance = 100
	f.vsync_frame = 40
	_frame(t)
	var frames := 0
	while rod.hooked.state == FishingRod.HOOK_NIBBLE and frames < 100:
		_frame(t)
		frames += 1
	_check(rod.hooked.state == FishingRod.HOOK_TAKEN and rod.item_taken and w.removed == [[38, 1]], "it takes the bait: the Meat leaves the bag")
	_check(frames == rod.nibble_time, "after nibbleTime frames (%d)" % frames)
	_frame(t, Pad.CONFIRM)
	_check(rod.text_box.lines[0] == "Hooked!" and rod.state == FishingRod.STATE_REELING and rod.tension_display, "a strike in time: Hooked!, reeling")
	_check(rod.hooked.state == FishingRod.HOOK_STRUGGLE and rod.strike_timer == 0x13, "the fish struggles (strikeTimer 0x14 − 1)")
	# Too late.
	var u := _floating()
	rod = u["rod"]
	w = u["world"]
	f = u["fishing"]
	Rng.set_seed(23)
	_hook_a_fish(u, 1, 60)
	w.chance = 100
	f.vsync_frame = 60
	_frame(u)
	while rod.hooked.state == FishingRod.HOOK_NIBBLE:
		_frame(u)
	for i in rod.catching_time / 2:
		_frame(u)
	_frame(u, Pad.CONFIRM)
	_check(rod.text_box.lines[0] == "Too late!" and rod.text_box.lines[1] == "They got my bait!", "too late (%s)" % [rod.text_box.lines])
	# It escapes by itself after catchingTime.
	var v := _floating()
	rod = v["rod"]
	w = v["world"]
	f = v["fishing"]
	Rng.set_seed(24)
	_hook_a_fish(v, 1, 60)
	w.chance = 100
	f.vsync_frame = 80
	_frame(v)
	while rod.hooked.state == FishingRod.HOOK_NIBBLE:
		_frame(v)
	for i in rod.catching_time + 2:
		_frame(v)
	_check(rod.text_box.lines[0] == "They took my bait!", "unstruck, it swims off with the bait (%s)" % [rod.text_box.lines])


## Reeled in to the shore: the catch, the message, the item (fish.c:4192-4331).
func _catch() -> void:
	for full in [false, true]:
		var s := _floating()
		var rod: FishingRod = s["rod"]
		var w: FakeWorld = s["world"]
		w.bag_full = full
		Rng.set_seed(31)
		var fish := _hook_a_fish(s, 1, 70)
		rod.hook_fish(fish)
		rod._set_state(FishingRod.STATE_REELING)
		rod.begin_tension()
		rod.tick_hooked(FishingRod.HOOKED_GRAB)
		rod.swimmer_pos = w.pos + Vector3i(0, 0, 50)
		_frame(s)
		_check(rod.state == FishingRod.STATE_CATCH and rod.bait == 63 and w.sounds.has([8, 7]), "landed within the cast range: the fish's item (63)")
		_check(not rod.hooked.active and not rod.tension_display, "the hooked fish is gone, the gauge too")
		var frames := 0
		while rod.state == FishingRod.STATE_CATCH and frames < 100:
			_frame(s)
			frames += 1
		_check(w.given == [[63, 1]] and w.caught == 1, "given, fishCaught + 1")
		var expected := ["Digisnapper", "Total length 70 cm", "I got one!", "It looks sad. Let it go." if full else ""]
		_check(rod.text_box.lines == expected, "the message %s (%s)" % [expected, rod.text_box.lines])
		_check(rod.state == FishingRod.STATE_END and w.yaw == 0 and w.anims.back() == 0x1C, "finish: facing 0, anim 0x1C")
		for i in 12:
			_frame(s)
		_frame(s, Pad.CONFIRM)
		frames = 0
		var result := FishingRod.TICK_FISHING
		while result == FishingRod.TICK_FISHING and frames < 200:
			_press(s["pad"], 0)
			result = rod.tamer_tick()
			frames += 1
		_check(result == FishingRod.TICK_ENDED and not rod.display_rod and w.follow and w.anims.back() == 0, "the box closed, the camera back on the tamer: fishing ends")
		_check(rod.records[1] == 70, "the record for kind 1")
	var r := _session()["rod"] as FishingRod
	_check(r.catch_message(250) == "Great! Total length 2 m 50 cm", "250: 2 m 50 cm (port-only fix of the US / 200)")
	_check(r.catch_message(150) == "Total length 1 m 50 cm", "150: 1 m 50 cm")
	_check(r.catch_message(55) == "Total length 55 cm", "55: 55 cm")


## The snag: ✕ held after the bait was taken (fish.c:3990-4006, :4367-4394).
func _snag() -> void:
	var s := _floating()
	var rod: FishingRod = s["rod"]
	var w: FakeWorld = s["world"]
	rod.item_taken = true
	Rng.set_seed(41)
	w.playing = true
	var frames := 0
	while rod.state == FishingRod.STATE_FLOATING and frames < 5000:
		rod.swimmer_pos = s["water"]
		_frame(s, Pad.CONFIRM)
		frames += 1
	_check(rod.state == FishingRod.STATE_SNAG, "a snag within %d frames" % frames)
	var ids := []
	for e in data.fishing()["snagged_items"]:
		ids.append(int(e["item"]["id"]))
	_check(rod.bait in ids and rod.text_box.lines[0] == "Huh?! I wonder if something", "a snag item, the message")
	_check(w.sounds.has([8, 9]), "sound 8 / 9")
	_press(s["pad"], Pad.CANCEL)
	rod.text_box.tick(s["pad"])
	_frame(s)
	_check(w.given == [[rod.bait, 1]] and rod.text_box.lines[1] == "It got stuck!" and rod.state == FishingRod.STATE_END, "given: It got stuck!")


func _reeling(size: int) -> Dictionary:
	var s := _floating()
	var rod: FishingRod = s["rod"]
	Rng.set_seed(51)
	var fish := _hook_a_fish(s, 1, size)
	rod.hook_fish(fish)
	rod.begin_tension()
	rod.tick_hooked(FishingRod.HOOKED_GRAB)
	rod._set_state(FishingRod.STATE_REELING)
	return s


func _line_cut_and_hook_lost() -> void:
	var s := _reeling(50)
	var rod: FishingRod = s["rod"]
	var w: FakeWorld = s["world"]
	rod.tension_level = rod.tension_limit
	rod.tension_frames_at_limit = 14
	rod.hooked.state = FishingRod.HOOK_PULL
	rod.pressed_frames = 1
	w.playing = true
	_frame(s, Pad.CONFIRM)
	_check(rod.state == FishingRod.STATE_LINE_CUT and not rod.display_line and rod.swimmer_state == 14, "the line snaps: state 0x4B0")
	for i in 11:
		_frame(s)
	_check(rod.text_box.lines[0] == "My line got cut!" and w.sounds.has([8, 0xA]) and rod.state == FishingRod.STATE_END, "frame 0xA: My line got cut!")
	var t := _reeling(50)
	rod = t["rod"]
	rod.tension_level = -rod.tension_limit + 0x10
	rod.hooked.state = FishingRod.HOOK_STRUGGLE
	_frame(t, 0)
	_check(rod.state == FishingRod.STATE_HOOK_LOST and rod.display_line, "the hook comes out: state 0x4B1, the line stays")
	for i in 11:
		_frame(t)
	_check(rod.text_box.lines[0] == "My hook got lost!", "frame 0xA: My hook got lost!")


## Seadramon landed: it swims to the reel target, then catchComplete (fish.c:4194-4196, :4401-4413).
func _seadramon() -> void:
	var s := _reeling(300)
	var rod: FishingRod = s["rod"]
	var w: FakeWorld = s["world"]
	rod.hooked.kind = Fishing.SEADRAMON
	rod.swimmer_pos = w.pos + Vector3i(0, 0, 50)
	_frame(s, 0)
	_check(rod.state == FishingRod.STATE_SEADRAMON and rod.hooked.state == FishingRod.HOOK_SEADRAMON, "Seadramon landed: state 0x11AF, the fish 0x64")
	var frames := 0
	var result := FishingRod.TICK_FISHING
	while result == FishingRod.TICK_FISHING and frames < 3000:
		_press(s["pad"], 0)
		result = rod.tamer_tick()
		s["fishing"].tick_world()
		frames += 1
	_check(result == FishingRod.TICK_SEADRAMON and not rod.hooked.active and not rod.display_rod, "near the world origin: catchComplete, fishing ends (%d frames)" % frames)


func _rod_pose_and_camera() -> void:
	var s := _session()
	var rod: FishingRod = s["rod"]
	var w: FakeWorld = s["world"]
	rod.swimmer_pos = s["water"]
	rod.begin_tension()
	rod.tension_level = -rod.tension_limit
	rod.update_rod_pose()
	var length := 0xFC + 0xB9 + 0x65 + 0x4B
	var d := rod.line_start - rod.segment_positions[0]
	_check(absi(PsxMath.get_distance(d.x, d.y, d.z) - length) <= 4, "no bend at −limit: the segments add up to 0x2A5 (%d)" % PsxMath.get_distance(d.x, d.y, d.z))
	var mirror := rod.line_start
	rod.reset_tension()
	rod.update_rod_pose()
	_check(rod.line_start_mirror == mirror and rod.line_start != mirror, "the line start bends with the bobber; the last one kept")
	rod.camera_control = true
	var offset := rod.fishing.camera.offset
	var moved := rod._pan_to_tamer(0x10)
	_check(moved and rod.fishing.camera.offset != offset and not w.scrolls.is_empty(), "a pan scrolls the camera")
	# The step is cut to the radius with >> 12 (rounding towards −inf): up to 16 + √2.
	_check(w.scrolls[0].length() <= 16.0 + 1.5, "at most about 0x10 px a frame (%s)" % w.scrolls[0])
	var frames := 0
	while rod._pan_to_tamer(0x10) and frames < 300:
		frames += 1
	_check(not rod._pan_to_tamer(0x10), "centred: the pan returns 0")
	var count := w.scrolls.size()
	rod.display_rod = true
	rod.end_fishing()
	_check(w.scrolls.size() == count, "endFishing doesn't scroll back (the saved scroll is skipped, as in the C)")
