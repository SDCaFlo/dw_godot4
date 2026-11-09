extends SceneTree
## Fishing's world (scripts/systems/fishing/: FishingCamera, Fishing) against specs/fishing.md §2.1-2.6
## (step F2), on MAYO10 (map 8) and MAYO06 (map 6) with the porter output:
##   godot --headless --path . -s res://tests/test_fishing.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false
var data: Node
var maps := {}


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
	for file in ["MAYO10", "MAYO06"]:
		maps[file] = _load_map(file)
	_camera()
	_water()
	_spots()
	_population()
	_fish_states()
	_seadramon()
	_ripples_and_markers()
	_bite()
	for file in maps:
		maps[file]["node"].free()
	print("%s: fishing checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## A FieldMap with the map loaded, and a FishingCamera from it as the field will set it.
func _load_map(file: String) -> Dictionary:
	var map := FieldMap.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	map.add_child(camera)
	var doors := Node3D.new()
	doors.name = "Doors"
	map.add_child(doors)
	map.background = Sprite2D.new()
	map.add_child(map.background)
	root.add_child(map)
	map.load_map(file)
	var cam := FishingCamera.new()
	cam.ws = map.world_screen_matrix()
	cam.h = map.viewport_distance()
	cam.background = Vector2i(map.background_size)
	cam.offset = Vector2i(map.drawing_offset().round())
	return {"node": map, "camera": cam, "data": data.fishing_map("dw1:" + file.to_lower())}


func _fishing(file: String) -> Fishing:
	var f := Fishing.new()
	f.setup(maps[file]["data"], data.fishing()["kinds"])
	f.camera = maps[file]["camera"]
	return f


## FISH_projectPoint and mapToWorldPosition agree with each other and with FieldMap's projection.
func _camera() -> void:
	for file in maps:
		var cam: FishingCamera = maps[file]["camera"]
		var map: FieldMap = maps[file]["node"]
		var worst := 0
		var worst_field := 0.0
		for p in [Vector2i(0, 0), Vector2i(-100, 40), Vector2i(120, 80), Vector2i(-200, 100)]:
			var g = cam.ground_at(p.x, p.y)
			_check(g != null and g.y == 0, "%s: ground_at(%s) is on the ground" % [file, p])
			if g == null:
				continue
			var back = cam.project(g)
			_check(back != null, "%s: the ground point projects" % file)
			if back == null:
				continue
			worst = maxi(worst, maxi(absi(back.x - p.x), absi(back.y - p.y)))
			var field := map.background_pixel(Vector3(g.x, -g.y, -g.z)) - map.background_size / 2
			worst_field = maxf(worst_field, maxf(absf(field.x - back.x), absf(field.y - back.y)))
		_check(worst <= 2, "%s: project(ground_at(p)) within 2 px of p (worst %d)" % [file, worst])
		_check(worst_field <= 2.0, "%s: FISH_projectPoint matches FieldMap.background_pixel (worst %.1f)" % [file, worst_field])
		_check(cam.is_in_background(0, 0) and not cam.is_in_background(cam.background.x, 0),
				"%s: the background test spans ±width / 2 from the projection centre" % file)


## FISH_isFishableWater1 / 2 on both sides of their shores (fish.c:4511-4535).
func _water() -> void:
	var f := _fishing("MAYO10")
	var shore: Array = f.map["water"]["shore"]
	var mid := Vector2i((int(shore[5][0]) + int(shore[6][0])) / 2, (int(shore[5][1]) + int(shore[6][1])) / 2)
	_check(f.is_water(mid.x, mid.y + 6), "map 8: below the shore is water")
	_check(not f.is_water(mid.x, mid.y - 6), "map 8: above the shore is land")
	_check(f.is_water(int(shore[0][0]) - 10, 0), "map 8: left of the shore's table counts as water (lerp 0)")
	_check(not f.is_water(0, f.camera.screen_bottom(0xF0) + 1), "map 8: below the background's bottom is not water")
	_check(Fishing.lerp_by_x(-0x180 + 22, 0, shore) == -(-0x22 + PsxMath.div(22 * (-0x22 - -0x22), 0x2C)),
			"FISH_lerpTableByX between the first two points")
	var g := _fishing("MAYO06")
	var s2: Array = g.map["water"]["shore"]
	var row := Vector2i(int(s2[3][0]), int(s2[3][1]))
	_check(g.is_water(row.x - 6, row.y), "map 6: left of the shore is water")
	_check(not g.is_water(row.x + 6, row.y), "map 6: right of the shore is land")
	_check(g.is_water(0x1AC, 5), "map 6: above y 6 is water")
	_check(not g.is_water(0x1AD, 5), "map 6: from x 0x1AD nothing is water")


## FISH_randomPointInSpot: water inside the background, the C's clamp written into the table.
func _spots() -> void:
	for file in maps:
		var f := _fishing(file)
		Rng.set_seed(7)
		var good := 0
		var total := 0
		for spot in 6:
			for i in 20:
				var p := f.random_point_in_spot(spot)
				total += 1
				var s = f.camera.project(p)
				if p.y == 0 and s != null and f.camera.is_in_background(s.x, s.y) and f.is_water(s.x, s.y):
					good += 1
		_check(good * 100 >= total * 95, "%s: spot points are water in the background (%d / %d)" % [file, good, total])
		# The C clamps the 3 points it picks in the table itself: a point beyond the background's
		# left edge is moved onto it once picked.
		var pts: Array = f.spot_points[0]
		var left := f.camera.screen_left(0)
		pts[0] = Vector2i(left - 50, pts[0].y)
		for i in 60:
			f.random_point_in_spot(0)
			if pts[0].x != left - 50:
				break
		_check(pts[0].x == left, "%s: a picked point beyond the edge is clamped in the table (x %d)" % [file, pts[0].x])
		Rng.set_seed(7)
		var a := f.random_point_in_spot(0)
		Rng.set_seed(7)
		_check(f.random_point_in_spot(0) == a, "%s: a seed repeats its point (customRandom's LCGs)" % file)


## FISH_tickFishPopulation: the first fish is kind 5 (0 / 0 is −1 on the R3000), then the lowest
## count per share; up to 0x20 fish.
func _population() -> void:
	var f := _fishing("MAYO10")
	Rng.set_seed(1)
	var order: Array[int] = []
	for i in 6:
		var before := f.fish_count
		f.tick_population()
		for x in f.fish:
			if x.active and x.frames_on_state == 1 and x.anim_phase == 1:
				order.append(x.kind)
		_check(f.fish_count == before + 1, "one fish spawns per frame (frame %d)" % i)
	_check(order == [5, 4, 3, 2, 1, 0], "spawn order 5, 4, 3, 2, 1, 0 (got %s)" % [order])
	_check(f.fish[1].active and f.fish[0].active == false, "the first fish goes to items[1] (next starts there)")
	_check(Fishing.r3000_div(0, 0) == -1 and Fishing.r3000_div(-5, 0) == 1, "R3000 division by zero")
	for i in 40:
		f.tick_population()
	_check(f.fish_count == Fishing.POPULATION_MAX, "the pool stops at 0x20 fish (%d)" % f.fish_count)
	_check(f.frame_count == 46, "frameCount counts every tick")


## FISH_tickFish's states (fish.c:2722-2831).
func _fish_states() -> void:
	var f := _fishing("MAYO10")
	Rng.set_seed(3)
	var fish := f.alloc_fish()
	fish.active = true
	f.fish_count += 1
	f.spawn_fish(fish, 1)
	_check(fish.size >= 55 and fish.size <= 85, "kind 1 size in 55-85 (%d)" % fish.size)
	_check(fish.lifetime >= 0x258 and fish.lifetime <= 0x4B0, "lifetime in 0x258-0x4B0")
	for i in 15:
		f.tick_fish(fish)
	_check(fish.state == Fishing.STATE_APPEAR and fish.transparency == 0x78, "15 frames: still appearing")
	var start := fish.pos
	f.tick_fish(fish)
	_check(fish.state == Fishing.STATE_IDLE and fish.transparency == 0x80, "16th frame: opaque, idle")
	_check(fish.time_next_move >= 30 and fish.time_next_move <= 60, "waits 30-60 frames (%d)" % fish.time_next_move)
	_check(PsxMath.get_distance(fish.pos.x - start.x, 0, fish.pos.z - start.z) >= 0x1C, "appearing moves 0x1E a frame")
	# The lifetime ends: away from the tamer, fades in 16 frames.
	f.tamer_pos = fish.pos + Vector3i(0, 0, -500)
	fish.lifetime = 1
	f.tick_fish(fish)
	_check(fish.state == Fishing.STATE_LEAVE, "lifetime 0: leaves")
	var away := Fishing.forward(fish.rotation, 0x100)
	_check(away.z > 0, "it swims away from the tamer")
	for i in 16:
		f.tick_fish(fish)
	_check(not fish.active and f.fish_count == 0, "gone after 16 frames of fading")
	# A ripple with an attractor scares it; the population waits 0x1E frames.
	var g := _fishing("MAYO10")
	Rng.set_seed(4)
	var h := g.alloc_fish()
	h.active = true
	g.fish_count += 1
	g.spawn_fish(h, 0)
	h.state = Fishing.STATE_IDLE
	h.time_next_move = 50
	h.transparency = 0x80
	g.spawn_ripple(0, h.pos + Vector3i(50, 0, 0), 0x64, 0, 0x1000)
	g.tick_fish(h)
	_check(h.state == Fishing.STATE_LEAVE and g.escape_timer == 0x1E, "a ripple within its radius scares the fish")
	var before := g.fish_count
	g.tick_population()
	_check(g.fish_count == before and g.escape_timer == 0x1D, "no spawn while escapeTimer counts down")
	# The right bait draws a fish to the bobber (kind 2's bait is item 0x45).
	var k := _fishing("MAYO10")
	Rng.set_seed(5)
	var b := k.alloc_fish()
	b.active = true
	k.fish_count += 1
	k.spawn_fish(b, 2)
	b.state = Fishing.STATE_IDLE
	b.time_next_move = 50
	k.swimmer_pos = b.pos + Vector3i(0x150, 0, 0)
	k.bait = 0x44
	k.tick_fish(b)
	_check(b.state == Fishing.STATE_IDLE, "another bait doesn't draw it")
	k.bait = 0x45
	k.tick_fish(b)
	_check(b.state == Fishing.STATE_SWIM and b.time_this_move == mini(0x150 / 8, b.size), "its bait draws it to the bobber")
	_check(Fishing.forward(b.rotation, 0x100).x > 0xF0, "heading to the bobber")
	k.swimmer_pos = b.pos + Vector3i(0x258, 0, 0)
	b.state = Fishing.STATE_IDLE
	b.time_next_move = 50
	k.tick_fish(b)
	_check(b.state == Fishing.STATE_IDLE, "0x258 away is too far")


## Seadramon: only on map 6, at 8 and 17 h, every 20th frame; it follows its path and fades.
func _seadramon() -> void:
	var f := _fishing("MAYO10")
	f.hour = 17
	f.vsync_frame = 0
	f.escape_timer = 0
	Rng.set_seed(2)
	f.tick_population()
	_check(not f.is_seadramon_spawned(), "no Seadramon on map 8")
	var g := _fishing("MAYO06")
	g.hour = 9
	g.vsync_frame = 0
	g.tick_population()
	_check(not g.is_seadramon_spawned(), "map 6 at 9 h: none")
	g.hour = 17
	g.vsync_frame = 7
	g.tick_population()
	_check(not g.is_seadramon_spawned(), "map 6 at 17 h, frame not a multiple of 20: none")
	g.vsync_frame = 20
	g.hooked_active = true
	g.tick_population()
	_check(not g.is_seadramon_spawned(), "not while a fish is hooked")
	g.hooked_active = false
	g.tick_population()
	_check(g.is_seadramon_spawned(), "map 6 at 17 h on the 20th frame: Seadramon")
	var sea: Fishing.Fish = null
	for x in g.fish:
		if x.active and x.kind == Fishing.SEADRAMON:
			sea = x
	_check(sea != null and sea.size == 300 and sea.state >= 1, "size 300, heading for waypoint 1")
	g.hour = 8
	_check(g._is_seadramon_hour(g.map["seadramon_hours"]), "8 h is a Seadramon hour too")
	var frames := 0
	while sea.active and frames < 3000:
		g.tick_seadramon(sea)
		frames += 1
	_check(not sea.active, "it follows its 8 waypoints and fades out (%d frames)" % frames)
	_check(g.seadramon_history[0] == sea.rotation, "the history holds its last rotation")


## Ripple and marker lifetimes (FISH_tickRipple, FISH_tickMarker).
func _ripples_and_markers() -> void:
	var f := _fishing("MAYO10")
	for case in [[0, 11], [-1, 7], [-2, 7], [-3, 5], [-4, 17]]:
		f.spawn_ripple(case[0], Vector3i(10, -5, 20), 0, 0, 0x1000)
		var r: Fishing.Ripple = null
		for x in f.ripples:
			if x.active:
				r = x
		_check(r.pos.y == 0, "a ripple lies on the water (y 0)")
		var ticks := 0
		while r.active and ticks < 50:
			f.tick_ripples()
			ticks += 1
		_check(ticks == case[1], "ripple kind %d lasts %d ticks (got %d)" % [case[0], case[1], ticks])
	f.spawn_ripple(0, Vector3i.ZERO, 0x64, 0, 0x1000)
	_check(f.attractor != null and f.attract_radius == 0x64, "an attracting ripple becomes the attractor")
	for i in 11:
		f.tick_ripples()
	_check(f.attractor == null, "the attractor goes with its ripple")
	Rng.set_seed(9)
	f.spawn_ripple(0, Vector3i(100, 0, 100), 0, 5, 0x1000)
	var spread_ok := true
	for x in f.ripples:
		if x.active and (absi(x.pos.x - 100) > 5 or absi(x.pos.z - 100) > 5):
			spread_ok = false
	_check(spread_ok, "spread stays within ±5")
	for i in 20:
		f.spawn_marker(0x2F, Vector3i.ZERO)
	_check(f.marker_count == Fishing.MARKER_COUNT, "16 markers at most")
	for i in 10:
		f.tick_markers()
	_check(f.marker_count == 0, "markers last 10 frames")


## FISH_findFishToBite (fish.c:3036).
func _bite() -> void:
	var f := _fishing("MAYO10")
	Rng.set_seed(6)
	var fish := f.alloc_fish()
	fish.active = true
	f.fish_count += 1
	f.spawn_fish(fish, 1)
	fish.state = Fishing.STATE_IDLE
	var always := func(_bait: int, _kind: int) -> int: return 100
	var never := func(_bait: int, _kind: int) -> int: return 0
	f.vsync_frame = 21
	_check(f.find_fish_to_bite(fish.pos, 38, always) == null and f.marker_count == 0, "not on frames off the 20th")
	f.vsync_frame = 40
	_check(f.find_fish_to_bite(fish.pos, 38, always) == fish, "a 100 % chance bites")
	_check(f.marker_count == 1 and f.markers[0].sprite == 0x2F, "with marker 0x2F")
	_check(f.find_fish_to_bite(fish.pos, 38, never) == null, "a 0 % chance never bites")
	var marked := false
	for m in f.markers:
		if m.active and m.sprite == 0x30:
			marked = true
	_check(marked, "and gets marker 0x30")
	_check(f.find_fish_to_bite(fish.pos + Vector3i(0xC9, 0, 0), 38, always) == null, "0xC9 away is out of range")
	fish.state = Fishing.STATE_LEAVE
	_check(f.find_fish_to_bite(fish.pos, 38, always) == null, "a leaving fish doesn't bite")
	fish.state = Fishing.STATE_IDLE
	f.hooked_active = true
	_check(f.find_fish_to_bite(fish.pos, 38, always) == null, "nothing bites while a fish is hooked")
	f.hooked_active = false
	_check(int(data.fishing_bite_chance(38, 1)) == 20, "Meat, kind 1: 20 %")
	var hits := 0
	Rng.set_seed(11)
	for i in 1000:
		if f.find_fish_to_bite(fish.pos, 38, data.fishing_bite_chance) != null:
			hits += 1
	_check(hits > 150 and hits < 250, "Meat bites kind 1 about 20 percent of the checks (%d / 1000)" % hits)
	fish.kind = Fishing.SEADRAMON
	f.vsync_frame = 8
	var sea_hits := 0
	for i in 1000:
		if f.find_fish_to_bite(fish.pos, 0, never) != null:
			sea_hits += 1
	_check(sea_hits > 150 and sea_hits < 250, "Seadramon bites at 20 percent every 8th frame, whatever the bait (%d)" % sea_hits)
