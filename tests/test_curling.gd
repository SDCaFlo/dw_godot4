extends SceneTree
## Curling's stones (scripts/systems/curling/curling_stones.gd, step C2) against specs/curling.md §2.1-2.4.
## Acceptance checks written by the reviewer from kar.c; the expected values come from a model of the C
## functions with PsxMath's libgte (rsin = round(4096 sin), ratan2 = round(atan2), SquareRoot0 = floor
## sqrt). Don't change them to make the code pass.
##   godot --headless --path . -s res://tests/test_curling.gd
## Exits 1 if a check fails.

const MATCH_SLIDING := 0xB

var _failed := 0
var _checks := 0
var _started := false
var data: Node
var curling: Dictionary
var sounds: Array = []


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: porter output missing")
		quit(0)
		return false
	PsxMath.setup(data)
	curling = data.curling()
	_maths()
	_setup()
	_slide()
	_walls()
	_collisions()
	_pegged()
	_rings()
	_stopped()
	data.free()
	print("%s: curling stone checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: " + what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	_check(got == want, "%s: got %s, want %s" % [what, got, want])


func _world() -> CurlingStones:
	var w := CurlingStones.new(curling)
	sounds = []
	w.sound.connect(func(id: int) -> void: sounds.append(id))
	return w


## Ticks in match state 0xB until check_stopped() (KAR_tickMatchState 0xB + KAR_checkStonesStopped):
## the frame count.
func _run(w: CurlingStones, limit := 2000) -> int:
	var frames := 0
	while frames < limit:
		w.tick(MATCH_SLIDING)
		frames += 1
		if w.check_stopped():
			break
	return frames


func _stone(w: CurlingStones, row: int, i: int) -> CurlingStones.Stone:
	return w.rows[row].stones[i]


# --- KAR_distance (SquareRoot0), KAR_computeImpactShare, KAR_computeSeparation ----------------------

func _maths() -> void:
	_eq(PsxMath.square_root0(25), 5, "square_root0(25)")
	_eq(PsxMath.square_root0(24), 4, "square_root0(24) floors")
	_eq(CurlingStones.distance(3, 4), 5, "distance(3, 4)")
	_eq(CurlingStones.distance(-0x91, 0), 0x91, "distance(-0x91, 0)")
	_eq(CurlingStones.distance(100, 100), 141, "distance(100, 100)")
	var w := _world()
	var m := w.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, -900), 2000, -0x400)
	_eq(w.impact_share(m, Vector3i(0, 0, -900), Vector3i(0, 0, -1050)), 2000, "impact share, straight on")
	_eq(w.impact_share(m, Vector3i(0, 0, -900), Vector3i(100, 0, -1000)), 1000, "impact share, 45 degrees")
	_eq(w.impact_share(m, Vector3i(0, 0, -900), Vector3i(0, 0, -750)), 0, "impact share, behind")
	_eq(w.separation(m, Vector3i(0, 0, -900), Vector3i(100, 0, -1000)), Vector3i(1, 0, -1), "separation, 45 degrees (r++ until non-zero)")


# --- KAR_setupMatch: the rand() order, the types, the places ------------------------------------------

func _setup() -> void:
	for mode in [0, 1]:
		for seed_value in [1, 7, 42]:
			# The C's rand() calls, in order (kar.c:701-757).
			Rng.set_seed(seed_value)
			var obstacles := Rng.rand() % 3
			var types := []
			var obstacle_pos := []
			for p in 3:
				Rng.rand()
				for i in 5:
					var n := Rng.rand() % 10
					types.append(int(curling["type_roll"][n]) if mode == 0 else mini(i, 3))
					if p == 2 and i < obstacles:
						var x := int(curling["obstacle_x"][i]) - Rng.rand() % 0x13F
						var z := -(Rng.rand() % 0x3E8 + 0x3E8)
						obstacle_pos.append(Vector3i(x, 0, z))
			Rng.set_seed(seed_value)
			var w := _world()
			w.setup(mode)
			var what := "setup(%d), seed %d" % [mode, seed_value]
			for p in 3:
				_eq(w.rows[p].score, 0, what + ": row %d score" % p)
				_eq(w.rows[p].thrown, 0, what + ": row %d thrown" % p)
				for i in 5:
					var s := _stone(w, p, i)
					var t: int = types[p * 5 + i]
					_eq(s.type, t, what + ": row %d stone %d type" % [p, i])
					_eq(s.weight, int(curling["stone_types"][t]["weight"]), what + ": weight")
					_eq(s.model, t * 3 + int(curling["row_models"][p]), what + ": model")
					_eq([s.speed, s.angle, s.ring, s.prev_ring], [0, 0, 0, 0], what + ": speed, angle, rings")
					if p < 2:
						_eq(s.state, CurlingStones.STATE_WAITING, what + ": stack state")
						_eq(s.pos, Vector3i(0x2BC if p else -0x2BC, i * 0xAA - 0x50, 0), what + ": stack place")
						_eq(s.rotation, Vector3i(0x96, 0, 0), what + ": stack rotation")
					elif i < obstacles:
						_eq(s.state, CurlingStones.STATE_ICE, what + ": obstacle state")
						_eq(s.pos, obstacle_pos[i], what + ": obstacle %d place" % i)
					else:
						_eq(s.state, CurlingStones.STATE_OUT, what + ": unused obstacle")


# --- KAR_tickStones: the slide -----------------------------------------------------------------------

func _slide() -> void:
	# The tamer's stone, weight 30, thrown at power 0x7D0 (speed 0x7D0 + 0x258), straight up (-0x400).
	var w := _world()
	var s := w.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(-400, 0, 1400), 0x7D0 + 0x258, -0x400)
	w.tick(MATCH_SLIDING)
	_eq(s.target, Vector3i(-400, 0, 1400), "one tick: target = the position before")
	_eq(s.pos, Vector3i(-400, 0, 1314), "one tick: move = 2600 / 30 = 86")
	_eq(s.speed, 2548, "one tick: speed * 98 / 100")
	_eq(_run(w) + 1, 172, "slide: frames to rest")
	_eq(s.pos, Vector3i(-400, 0, -2433), "slide: rest place (after the back wall)")
	_eq(s.angle, 1024, "slide: angle after the back wall (zone 5: -angle)")
	_eq(sounds, [3], "slide: one wall sound")
	# Spin: in match state 5 the selected stone turns 0x14 a frame, the others are reset to 0.
	w = _world()
	var a := w.place(0, 0, 0, CurlingStones.STATE_WAITING, Vector3i.ZERO)
	var b := w.place(0, 1, 0, CurlingStones.STATE_WAITING, Vector3i.ZERO)
	b.rotation = Vector3i(0, 0x123, 0)
	w.tick(5, 0, 0)
	w.tick(5, 0, 0)
	_eq(a.rotation.y, 0x28, "state 5: the selected stone spins 0x14 a frame")
	_eq(b.rotation.y, 0, "state 5: the others are reset")


# --- KAR_bounceOffWall, KAR_getWallZone ----------------------------------------------------------------

func _walls() -> void:
	var zones := [[Vector2i(0, 0x465), 6], [Vector2i(0, 0x464), 0], [Vector2i(-0x2D5, 0), 1], [Vector2i(-0x2D4, 0), 0],
			[Vector2i(0x2D5, 0), 2], [Vector2i(0x2D4, 0), 0], [Vector2i(-0x2D5, -0x7D0), 1], [Vector2i(-0x2D5, -0x7D1), 0],
			[Vector2i(0, -0x9DD), 5], [Vector2i(0, -0x9DC), 0], [Vector2i(-500, -1300), 0], [Vector2i(-0x1AA, -0x7D1), 0],
			[Vector2i(500, -1300), 0], [Vector2i(0x1A9, -0x7D1), 0], [Vector2i(0x1A8, -0x9DD), 5], [Vector2i(300, -2000), 0],
			[Vector2i(-700, -2200), 3], [Vector2i(700, -2200), 4], [Vector2i(-600, -2100), 0]]
	for z in zones:
		_eq(CurlingStones.wall_zone(z[0].x, z[0].y), z[1], "wall zone at %s" % z[0])
	var w := _world()
	var s := w.place(0, 0, 2, CurlingStones.STATE_ICE, Vector3i(-600, 0, 0), 3000, 0x900)
	_eq(_run(w), 174, "left wall: frames to rest")
	_eq(s.pos, Vector3i(-161, 0, -1438), "left wall: rest place")
	_eq(s.angle, -4352, "left wall: angle (0x800 - angle, then the back wall)")
	_eq(sounds, [3, 3, 3], "left wall: three wall sounds")
	w = _world()
	s = w.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(-300, 0, -1700), 3000, -0x500)
	_eq(_run(w), 179, "back-left diagonal: frames to rest")
	_eq(s.pos, Vector3i(-407, 0, 68), "back-left diagonal: rest place")
	_eq(s.angle, 1280, "back-left diagonal: angle")
	_eq(sounds, [3, 3, 3], "back-left diagonal: wall sounds")


# --- KAR_updateCollisions and the three collision kinds ---------------------------------------------

func _first_hit(w: CurlingStones) -> int:
	for f in range(1, 400):
		var before := sounds.size()
		w.tick(MATCH_SLIDING)
		w.check_stopped()
		for i in range(before, sounds.size()):
			if sounds[i] == 1 or sounds[i] == 2:
				return f
	return -1


func _collisions() -> void:
	# Head-on into a resting opponent stone (collideRestingStone).
	var w := _world()
	var m := w.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, -400), 2600, -0x400)
	var r := w.place(1, 0, 1, CurlingStones.STATE_ICE, Vector3i(0, 0, -1000))
	_eq(_first_hit(w), 6, "head-on: the hit frame")
	_eq([m.pos, m.target, m.speed, m.angle], [Vector3i(0, 0, -844), Vector3i(0, 0, -844), 0, 0], "head-on: the mover after the hit")
	_eq([r.pos, r.target, r.speed, r.angle], [Vector3i(0, 0, -1047), Vector3i(0, 0, -1000), 2303, 3072], "head-on: the hit stone")
	_eq(sounds, [2], "head-on: a soft hit (speeds < 0xBB8)")
	_run(w)
	_eq([m.state, m.pos], [CurlingStones.STATE_ICE, Vector3i(0, 0, 180)], "head-on: the mover at rest (hit again on the way back)")
	_eq([r.state, r.pos], [CurlingStones.STATE_ICE, Vector3i(0, 0, -995)], "head-on: the hit stone at rest")
	_eq(sounds, [2, 3, 2], "head-on: hit, wall, hit")
	# Off-centre.
	w = _world()
	m = w.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, -400), 2600, -0x400)
	r = w.place(1, 0, 1, CurlingStones.STATE_ICE, Vector3i(60, 0, -1000))
	_eq(_first_hit(w), 6, "off-centre: the hit frame")
	_eq([m.pos, m.target, m.speed, m.angle], [Vector3i(-8, 0, -870), Vector3i(0, 0, -859), 590, 2662], "off-centre: the mover")
	_eq([r.pos, r.target, r.speed, r.angle], [Vector3i(68, 0, -1021), Vector3i(60, 0, -1000), 1713, 3309], "off-centre: the hit stone")
	_eq(_run(w), 157, "off-centre: frames to rest after the hit")
	_eq([m.pos, r.pos], [Vector3i(-408, 0, -1436), Vector3i(-471, 0, -2031)], "off-centre: rest places")
	# Two moving stones (collideMovingStones), a hard hit.
	w = _world()
	var a := w.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(-300, 0, -800), 2500, -0x200)
	var b := w.place(1, 0, 1, CurlingStones.STATE_ICE, Vector3i(300, 0, -800), 2500, -0x600)
	_eq(_first_hit(w), 4, "two moving: the hit frame")
	_eq([a.pos, a.target, a.speed, a.angle], [Vector3i(-104, 0, -1018), Vector3i(-96, 0, -1004), 1521, -1362], "two moving: the tamer's stone")
	_eq([b.pos, b.target, b.speed, b.angle], [Vector3i(58, 0, -1080), Vector3i(54, 0, -1045), 3087, -950], "two moving: the opponent's stone")
	_eq(sounds, [1], "two moving: a hard hit (speeds >= 0xBB8)")
	_run(w)
	_eq([a.state, a.pos], [CurlingStones.STATE_ICE, Vector3i(164, 0, -2177)], "two moving: the tamer's stone at rest")
	_eq([b.state, b.pos], [CurlingStones.STATE_OUT, Vector3i(630, 0, 599)], "two moving: the other came back past z 0xBE: out of play")


# --- pegged stones -------------------------------------------------------------------------------------

func _pegged() -> void:
	# A pegged stone (type 3) sticks the frame after it stops: move <= 0 (kar.c:847).
	var w := _world()
	var s := w.place(0, 0, 3, CurlingStones.STATE_ICE, Vector3i(0, 0, -400), 1500, -0x400)
	_eq(_run(w), 145, "pegged: frames to rest")
	_eq([s.state, s.model], [CurlingStones.STATE_ICE, 11], "pegged: still state 1 on the stopping frame")
	w.tick(0xC)
	_eq([s.state, s.model], [CurlingStones.STATE_PEGGED, int(curling["pegged_models"][0])], "pegged: state 2, the pegged model, next frame")
	_eq(sounds, [3, 4], "pegged: the stick sound (8, 4)")
	# A mover hits a pegged obstacle (collidePeggedStone): it shakes (state 3), the mover bounces.
	w = _world()
	var peg := w.place(2, 0, 3, CurlingStones.STATE_PEGGED, Vector3i(0, 0, -1000))
	var m := w.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(30, 0, -400), 2600, -0x400)
	_eq(_first_hit(w), 6, "into a pegged stone: the hit frame")
	_eq([peg.state, peg.pos, peg.speed, peg.angle], [CurlingStones.STATE_PUSHED, Vector3i(0, 0, -1000), 1004, 1024], "into a pegged stone: it shakes")
	_eq([m.pos, m.target, m.speed, m.angle], [Vector3i(43, 0, -821), Vector3i(30, 0, -852), 1299, 764], "into a pegged stone: the mover")
	_run(w)
	_eq([peg.state, peg.pos], [CurlingStones.STATE_PEGGED, Vector3i(0, 0, -1000)], "into a pegged stone: back to state 2 where it was")
	_eq(m.state, CurlingStones.STATE_OUT, "into a pegged stone: the mover came back out of play")


# --- KAR_classifyStoneRings, KAR_updateRingMarkers (0xB) -------------------------------------------------

func _rings() -> void:
	var w := _world()
	var spots := [Vector3i(0, 0, -0x6B6 + 0x91), Vector3i(0, 0, -0x6B6 + 0x92), Vector3i(0x177, 0, -0x6B6),
			Vector3i(0x178, 0, -0x6B6), Vector3i(0, 0, -0x564)]
	for i in 5:
		w.place(0, i, 0, CurlingStones.STATE_ICE, spots[i])
	w.place(1, 0, 0, CurlingStones.STATE_ICE, Vector3i(0x190, 0, -0x90E))
	w.place(1, 1, 0, CurlingStones.STATE_ICE, Vector3i(-0x190, 0, -0x90E - 0xCD))
	w.place(1, 2, 0, CurlingStones.STATE_WAITING, Vector3i(0, 0, -0x6B6))
	w.place(1, 3, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, -0x565))
	_stone(w, 0, 0).ring = 2
	w.rows[0].score = 9
	w.classify_rings()
	var got := []
	for p in 2:
		for i in 5:
			got.append(_stone(w, p, i).ring)
	_eq(got, [1, 2, 2, 0, 0, 0x13, 0x14, 0, 0x12, 0], "rings: edges (<= radius in), the -0x564 line, row 1's 0x10")
	_eq(_stone(w, 0, 0).prev_ring, 2, "rings: prev_ring keeps the last ring")
	_eq(w.rows[0].score, 0, "rings: the score is cleared")
	# Lit markers while sliding: the first zone not yet lit (kar.c:1268-1285).
	w = _world()
	w.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, -0x6B6), 100)
	w.place(0, 1, 0, CurlingStones.STATE_ICE, Vector3i(10, 0, -0x6B6), 100)
	w.place(1, 0, 0, CurlingStones.STATE_ICE, Vector3i(0x190, 0, -0x90E), 100)
	w.place(1, 1, 0, CurlingStones.STATE_ICE, Vector3i(-0x190, 0, -0x90E), 0)
	_eq(w.lit_rings(), 0b0111, "lit rings: 1, then 2 for the second stone, 3; not a stone at rest")


# --- KAR_checkStonesStopped --------------------------------------------------------------------------------

func _stopped() -> void:
	var w := _world()
	var a := w.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, 0xBE))
	var b := w.place(0, 1, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, 0xBD))
	var c := w.place(0, 2, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, 0x200), 50)
	_eq(w.check_stopped(), false, "stopped: a stone still moving")
	_eq([a.state, b.state, c.state], [CurlingStones.STATE_OUT, CurlingStones.STATE_ICE, CurlingStones.STATE_ICE], "out of play: at rest with z >= 0xBE")
	c.speed = 0
	_eq(w.check_stopped(), true, "stopped: none moving")
	_eq(c.state, CurlingStones.STATE_OUT, "out of play once it stops")
	var n := w.place(1, 0, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, -1000), -5)
	w.check_stopped()
	_eq(n.speed, 0, "stopped: a negative speed is reset to 0")
