extends SceneTree
## Partner (scripts/field/partner.gd), PsxAnimator and the FieldMap path helpers against
## specs/partner.md §2, with the real porter output (Agumon's model):
##   godot --headless --path . -s res://tests/test_partner.gd
## Exits 1 if a check fails.

var _failed := 0
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var data: Node = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not DirAccess.dir_exists_absolute(Content.root()):
		print("SKIP: porter output missing")
		quit(0)
		return
	var gs: Node = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()

	_paths()

	var map := FieldMap.new()
	map._collision.resize(100 * 100)
	map._collision.fill(0)
	var tamer := Node3D.new()
	root.add_child(tamer)
	# the entity scene (specs/scenes.md §6): Model and AnimationSounds children
	var partner: Partner = load("res://scenes/field/partner.tscn").instantiate()
	root.add_child(partner)
	partner.field = map
	partner.tamer = tamer
	partner.game_state = gs
	_eq(partner.load_digimon(data, "dw1:agumon"), true, "Agumon's model loads")
	_eq(partner.radius, 120, "Agumon's radius (DIGIMON_DATA)")

	# Placement (loadMapEntities, tamer.c:400-410).
	var cases := {0: Vector2(0, 200), 0x400: Vector2(200, 0), 0x800: Vector2(0, -200), 0xC00: Vector2(-200, 0)}
	for r in cases:
		partner.place_for_spawn({"position": Vector3(1000, 0, -500), "rotation": r})
		_eq([Vector2(partner.position.x - 1000, -partner.position.z - 500), partner.direction], [cases[r], (r + 0x800) % 0x1000], "placement for spawn rotation 0x%X" % r)

	# Closeness (getPartnerTamerCloseness): r = 120 -> near from 300, far beyond 420.
	partner.position = Vector3.ZERO
	var expected := {0: 2, 299: 2, 300: 1, 420: 1, 421: 0}
	for d in expected:
		tamer.position = Vector3(d, 0, 0)
		_eq(partner.closeness(), expected[d], "closeness at distance %d" % d)

	# entityCheckEntityCollision: the partner's leading edge against the tamer's square.
	partner.position = Vector3.ZERO
	tamer.position = Vector3(200, 0, 0)
	var reach: int = partner.radius + partner.tamer_radius
	_eq([partner.hits_tamer(200 - reach, 0, 1, 0), partner.hits_tamer(200 - reach - 1, 0, 1, 0)], [true, false], "the right edge touches the tamer's square at radius + tamer radius")
	_eq(partner.hits_tamer(200 - reach, 0, -1, 0), false, "moving away never bumps")

	# entityCheckCollision probes with the frame's forward motion; collisionGrace skips the tamer.
	partner.position = Vector3(200 - reach + 5, 0, 0)
	partner._set_direction(0xC00)
	partner.step = 0.0
	_eq(partner.probe(partner.direction), Partner.FREE, "idling (no forward motion) bumps nothing")
	partner.step = 10.0
	_eq(partner.probe(partner.direction), Partner.HIT_TAMER, "a walking step towards the tamer bumps him")
	partner.collision_grace()
	_eq(partner.direction, 0xC00, "collisionGrace doesn't turn for the tamer (he is its source; turning here spun the partner)")
	partner.step = 0.0

	# No walls: the original never stops the partner's root motion at the map (only collisionGrace
	# zeroes motion, and the partner gets it for entity hits alone); blocking left it stuck.
	map._collision.fill(0x80)
	partner.position = Vector3(1000, 0, 0)
	partner._set_direction(0xC00)
	partner._move(Vector3(10, 0, 0))
	_eq(partner.position.x, 1010.0, "normal state: a wall doesn't stop the step")
	partner.step = 10.0
	_eq(partner.probe(partner.direction), Partner.HIT_MAP, "entityCheckCollision still reports the map (10)")
	partner.step = 0.0
	map._collision.fill(0)
	_animator(partner)
	_root_motion_timing(partner)
	_walking(partner, tamer, gs)
	_waypoints(partner)

	partner.queue_free()
	tamer.queue_free()
	map.free()
	gs.free()
	data.free()
	print("%s: Partner checks" % ("FAILED %d" % _failed if _failed else "OK"))
	quit(1 if _failed else 0)


func _paths() -> void:
	var map := FieldMap.new()
	map._collision.resize(100 * 100)
	map._collision.fill(0)
	_eq(FieldMap.model_tile(50, -50), Vector2i(50, 50), "getModelTile of a tile centre")
	_eq(FieldMap.model_tile(-1, 1), Vector2i(49, 49), "getModelTile below 0")
	_eq(FieldMap.tile_centre(Vector2i(50, 50)), Vector2i(50, -50), "tile centre")
	_eq(map.is_linear_path_blocked(Vector2i(10, 10), Vector2i(20, 13)), false, "free line")
	map._collision[15 + 11 * 100] = 0x80
	_eq(map.is_linear_path_blocked(Vector2i(10, 10), Vector2i(20, 13)), true, "a wall on the line blocks it")
	_eq(map.is_linear_path_blocked(Vector2i(10, 30), Vector2i(20, 30)), false, "another line is free")
	map._collision[15 + 32 * 100] = 0x80
	_eq(map.is_five_tile_wide_path_blocked(Vector2i(10, 30), Vector2i(20, 30)), true, "5-wide path: a wall 2 tiles aside blocks")
	_eq(map.is_five_tile_wide_path_blocked(Vector2i(10, 40), Vector2i(20, 40)), false, "5-wide path free")
	map.free()


## The root motion one tick late (ISSUES.md I-28): startAnimation resets the momentum (anim.c:248)
## and tickAnimation moves it (tickMomentum, anim.c:290) before reading the frame's keyframes, so
## an animation moves 0 on its first tick and tick k's keyframe delta on tick k + 1. Agumon's walk
## (0x24): 0 after tick 1, 30 after tick 2 (the porter's simulate). The partner's _process is
## called by hand, three Godot frames (1/60 s) per game frame, GameLoop paused for the frame count.
func _root_motion_timing(partner: Partner) -> void:
	var loop: Node = root.get_node_or_null("GameLoop")
	_eq(loop != null, true, "GameLoop autoload (the game frame count)")
	if loop == null:
		return
	var was_paused: bool = loop.paused
	var was_frame: int = loop.frame_count
	loop.paused = true
	partner.position = Vector3(1000, 0, 0)
	partner._set_direction(0xC00)
	loop.frame_count = 5000
	var start := partner.position
	partner.start_animation(0x24)
	for i in 3:
		partner._process(1.0 / 60.0)
	_eq(partner.position.distance_to(start) < 0.01, true, "a walk's first game frame doesn't move (tick 1: momentum reset)")
	_eq(absf(partner.step - 30.0) < 0.5, true, "but its step (the momentum frame 1 set) is 30 for the probes: %.2f" % partner.step)
	_eq(absf(partner.forward_step - 30.0) < 0.5, true, "forward_step, the same along the facing: %.2f" % partner.forward_step)
	loop.frame_count += 1
	for i in 3:
		partner._process(1.0 / 60.0)
	_eq(absf(partner.position.distance_to(start) - 30.0) < 0.5, true, "the second game frame moves the 30 (%.2f)" % partner.position.distance_to(start))
	# Restarted every tick (the cornered fighter of I-28): it never moves.
	var held := partner.position
	for t in 6:
		loop.frame_count += 1
		partner.start_animation(0x21 if t % 2 == 0 else 0x24)
		for i in 3:
			partner._process(1.0 / 60.0)
	# The first restart's frame still moves what was left of the walk's tick 2 (nothing at 60 fps).
	_eq(partner.position.distance_to(held) < 0.5, true, "a walk restarted every tick stays put (%.2f)" % partner.position.distance_to(held))
	partner.start_animation(0)
	partner.step = 0.0
	partner.forward_step = 0.0
	loop.frame_count = was_frame
	loop.paused = was_paused


func _animator(partner: Partner) -> void:
	var a := partner.animator
	a.play(2)
	_eq([a.anim_id, a.loop_count, a.playing, a.frame], [2, 0xFF, true, 1], "walk starts endless")
	for i in 40:
		a.advance(0.05)
	_eq([a.loop_count, a.playing], [0xFF, true], "an endless walk keeps playing")
	a.finish_loop()
	_eq(a.loop_count, 1, "finish_loop sets the count to 1")
	for i in 40:
		a.advance(0.05)
	_eq([a.loop_count, a.playing, a.frame], [0, false, a.frame_count], "then it plays to the end and stops")
	a.play(5)
	_eq([a.loop_count, a.playing], [0, true], "happy (5) has no loop")
	for i in 100:
		a.advance(0.05)
	_eq(a.playing, false, "and ends")
	_eq(a.play(250), false, "an animation the model lacks is not started")


func _walking(partner: Partner, tamer: Node3D, gs: Node) -> void:
	var care: Dictionary = gs.state["partner"]["care"]
	partner.position = Vector3.ZERO
	partner.start_animation(0)
	partner.partner_animation = 0
	tamer.position = Vector3(1000, 0, 0)
	partner.tick_walking()
	_eq(partner.animator.anim_id, 4, "far: runs")
	tamer.position = Vector3(350, 0, 0)
	partner.tick_walking()
	_eq(partner.animator.anim_id, 2, "near: from the run straight to the walk")
	care["condition"] = 0x2
	partner.start_animation(4)
	partner.tick_walking()
	_eq(partner.animator.anim_id, 3, "near and tired: tired walk")
	care["condition"] = 0x10
	tamer.position = Vector3(1000, 0, 0)
	partner.start_animation(0)
	partner.partner_animation = 0
	partner.tick_walking()
	_eq(partner.animator.anim_id, 2, "far and unhappy: walks instead of running")
	care["condition"] = 0
	partner.start_animation(2)
	partner.partner_animation = 2
	tamer.position = Vector3(100, 0, 0)
	partner.tick_walking()
	_eq([partner.animator.anim_id, partner.animator.loop_count], [2, 1], "close: the walk finishes its loop first")
	for i in 40:
		partner.animator.advance(0.05)
	partner.tick_walking()
	_eq(partner.animator.anim_id, 0, "then idles")
	care["happiness"] = 40
	partner.stop_distance_timer = 10000
	partner.tick_walking()
	_eq(partner.animator.anim_id, 5, "standing long and happy: happy animation")
	care["happiness"] = 0


func _waypoints(partner: Partner) -> void:
	partner.initialize_waypoints()
	partner.set_waypoint(0, Vector2i(3, 4))
	partner.set_waypoint(1, Vector2i(5, 6))
	_eq([partner.waypoint_count, partner._waypoint(1)], [2, Vector2i(5, 6)], "two waypoints")
	partner.pop_waypoint()
	_eq([partner.waypoint_count, partner.waypoint_current], [1, 1], "pop moves to the next")
	partner.waypoint_current = 29
	partner.pop_waypoint()
	_eq(partner.waypoint_current, 0, "the ring wraps at 30")


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failed += 1
		print("FAIL %s: %s != %s" % [what, actual, expected])
