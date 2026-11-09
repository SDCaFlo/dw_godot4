class_name CurlingStones
extends RefCounted
## The curling stones and their physics (specs/curling.md §2.1-2.4, step C2): the three rows of five
## stones (KAR_D_8005B5A0), their setup, the per-frame slide, the walls, the collisions, the rings.
## Logic only, in the C's integers (PSX world units, 12-bit angles, int16 speeds); the C's +z points
## towards the camera and this class keeps it. The match state machine (C3) calls tick() once per game
## frame, then check_stopped() / classify_rings() / lit_rings() in its own states.
## Port-only: the C's global match state (MAIN_D_80135244) and selected stone are arguments of tick().
## KAR_debugCollisionStone / KAR_debugCollisionPair are not ported: they `return` at once (kar.c:1733,
## :1815). KAR_registerThrownStone (the end of KAR_classifyStoneRings) belongs to C3.

## KarStone.state (spec §2.1).
const STATE_OUT := -0x65
const STATE_WAITING := -1
const STATE_HELD := 0
const STATE_ICE := 1
const STATE_PEGGED := 2
const STATE_PUSHED := 3

const ROWS := 3
const PER_ROW := 5
## Match states used here (KAR_tickMatchState).
const MATCH_SPINNING := 5
const MATCH_SLIDING := 0xB

## KAR_setupMatch (kar.c:686): the stack's place (:741-744), the spin of a selected stone (:807).
const STACK_X := 0x2BC
const STACK_Y_STEP := 0xAA
const STACK_Y_BASE := 0x50
const STACK_ROTATION_X := 0x96
const OBSTACLE_X_SPREAD := 0x13F
const OBSTACLE_Z_SPREAD := 0x3E8
const OBSTACLE_Z_BASE := 0x3E8
const TYPE_ROLL_SIZE := 10
const OBSTACLE_COUNT_MOD := 3
const SPIN_STEP := 0x14
## KAR_tickStones friction: speed * 98 / 100, stop when move < 2 (kar.c:822-826); a shaking stone's
## step is move / 10 (:834); the pegged type is 3 (:847).
const FRICTION_NUM := 98
const FRICTION_DEN := 100
const MOVE_MIN := 2
const SHAKE_DIVISOR := 10
const TYPE_PEGGED := 3
## Sounds (playSound2(8, n)): hard / soft hit (kar.c:1544-1547), wall (:1488), pegged stick (:849).
const SOUND_HARD_HIT := 1
const SOUND_SOFT_HIT := 2
const SOUND_WALL := 3
const SOUND_PEG := 4
const HARD_HIT_SPEED := 0xBB8
## Walls (kar.c:1492-1521, :1859-1884).
const WALL_FRONT_Z := 0x465
const WALL_SIDE_X := 0x2D5
const WALL_BACK_Z := 0x9DD
const WALL_SPLIT_Z := -0x7D0
const WALL_DIAGONAL := -0xDC4
const WALL_DIAGONAL_X_LEFT := 0x1AA
const WALL_DIAGONAL_X_RIGHT := 0x1A9
const WALL_BACK_LIMIT := -0x9DC
## KAR_findWallContact: t = (z + 0xDC5) ± 2x (kar.c:1904-1908).
const CONTACT_OFFSET := 0xDC5
## Collisions: contact below 0x96 (kar.c:1438), pushed apart until 0x97 (:1596 ...); 11 sub-steps of
## the move (:1409), the last one repeats while a pass collides (:1452).
const CONTACT_DISTANCE := 0x96
const PUSH_DISTANCE := 0x97
const SUBSTEPS := 11
const SUBSTEP_DIVISOR := 10
## KAR_collideMovingStones: no push and a speed ratio under 5 stops B (kar.c:1727).
const MOVING_RATIO_MIN := 5
## Out of play: at rest with z >= 0xBE (kar.c:1352).
const OUT_OF_PLAY_Z := 0xBE
## KAR_classifyStoneRings: only past z -0x564 (kar.c:2157); row 1's rings get 0x10 (:2171).
const RING_LINE_Z := -0x564
const RING_ROW1_FLAG := 0x10
const ZONE_COUNT := 4

## One stone (KarStone). `model` is the model id in KARRING.TMD (type * 3 + the row's id, or the pegged
## model once stuck).
class Stone:
	extends RefCounted
	var state := STATE_OUT
	var type := 0
	var weight := 0
	var speed := 0
	var angle := 0
	var ring := 0
	var prev_ring := 0
	var model := 0
	var target := Vector3i.ZERO
	var rotation := Vector3i.ZERO
	var pos := Vector3i.ZERO


## One side's row (KarStoneRow).
class Row:
	extends RefCounted
	var score := 0
	var thrown := 0
	var plan_power := 0
	var plan_stone := 0
	var stones: Array = []

	func _init() -> void:
		for i in PER_ROW:
			stones.append(Stone.new())


## playSound2(8, id).
signal sound(id: int)

var rows: Array = []
var _data: Dictionary
var _zones: Array


func _init(data: Dictionary) -> void:
	_data = data
	_zones = data["zones"]
	for p in ROWS:
		rows.append(Row.new())


func _stone(index: int) -> Stone:
	return rows[index / PER_ROW].stones[index % PER_ROW]


## Port-only (spec §5.1): puts a stone on the ice (or elsewhere) for C3's copy into row 2 and for tests.
## The type sets the weight and the model from the data.
func place(row: int, i: int, type: int, state: int, pos: Vector3i, speed := 0, angle := 0) -> Stone:
	var s: Stone = rows[row].stones[i]
	_set_type(s, row, type)
	s.state = state
	s.pos = pos
	s.target = pos
	s.speed = speed
	s.angle = angle
	s.rotation = Vector3i.ZERO
	s.ring = 0
	s.prev_ring = 0
	return s


func _set_type(s: Stone, row: int, type: int) -> void:
	s.type = type
	s.model = type * 3 + int(_data["row_models"][row])
	s.weight = int(_data["stone_types"][type]["weight"])


# --- KAR_setupMatch (kar.c:686) ------------------------------------------------------------------------

## `mode` 0 is the match, 1 the demo (stone i has type min(i, 3)). The rand() calls are in the C's order.
func setup(mode: int) -> void:
	var obstacles := Rng.rand() % OBSTACLE_COUNT_MOD
	for p in ROWS:
		var row: Row = rows[p]
		Rng.rand()  # `seed`, unused (:701)
		row.score = 0
		row.thrown = 0
		row.plan_power = 0
		row.plan_stone = 0
		for i in PER_ROW:
			var s: Stone = row.stones[i]
			var n := Rng.rand()
			s.speed = 0
			s.angle = 0
			s.ring = 0
			s.prev_ring = 0
			n = n % TYPE_ROLL_SIZE
			var type: int
			if mode == 0:
				type = int(_data["type_roll"][n])
			else:
				type = mini(i, 3)
			if p < 2:
				s.pos = Vector3i(STACK_X if p != 0 else -STACK_X, i * STACK_Y_STEP - STACK_Y_BASE, 0)
				s.rotation = Vector3i(STACK_ROTATION_X, 0, 0)
				s.state = STATE_WAITING
			elif i < obstacles:
				# The US x: KAR_D_8005AB98[i] - rand() % 0x13F, evaluated before z's rand() (:752-756).
				var x := int(_data["obstacle_x"][i]) - Rng.rand() % OBSTACLE_X_SPREAD
				var z := -(Rng.rand() % OBSTACLE_Z_SPREAD + OBSTACLE_Z_BASE)
				s.pos = Vector3i(x, 0, z)
				s.rotation = Vector3i.ZERO
				s.state = STATE_ICE
				s.speed = 0
			else:
				s.pos = Vector3i.ZERO
				s.rotation = Vector3i.ZERO
				s.state = STATE_OUT
				s.speed = 0
			_set_type(s, p, type)


# --- KAR_tickStones (kar.c:797) ------------------------------------------------------------------------

## One game frame of the world object. `match_state` is MAIN_D_80135244; `selected_row` /
## `selected_stone` are MAIN_D_8013523C / _3A (the spin in state 5).
func tick(match_state: int, selected_row := -1, selected_stone := -1) -> void:
	for p in ROWS:
		for i in PER_ROW:
			var s: Stone = rows[p].stones[i]
			if s.state != STATE_PUSHED and s.state != STATE_PEGGED:
				s.target = s.pos
			if match_state == MATCH_SPINNING:
				if i == selected_stone and p == selected_row:
					s.rotation.y = PsxMath.s16(s.rotation.y + SPIN_STEP)
				else:
					s.rotation.y = 0
			if s.state > 0 and s.speed >= 0:
				var move := PsxMath.s16(PsxMath.div(s.speed, s.weight))
				var speed := (s.speed * FRICTION_NUM) & 0xFFFFFFFF
				s.speed = PsxMath.s16(speed / FRICTION_DEN)
				if move < MOVE_MIN:
					s.speed = 0
				if s.state < STATE_PUSHED:
					s.pos.x += PsxMath.div(move * PsxMath.rcos(s.angle), 4096)
					s.pos.z += PsxMath.div(move * PsxMath.rsin(s.angle), 4096)
				if s.state == STATE_PUSHED:
					if s.speed > 0:
						var step := PsxMath.s16(PsxMath.div(move, SHAKE_DIVISOR))
						s.angle -= 0x800
						if s.angle < 0:
							s.angle += 0x1000
						s.pos.x = s.target.x + PsxMath.div(step * PsxMath.rcos(s.angle), 4096)
						s.pos.z = s.target.z + PsxMath.div(step * PsxMath.rsin(s.angle), 4096)
						if step == 0:
							s.speed = 0
					else:
						s.speed = 0
						s.state = STATE_PEGGED
				if s.state == STATE_ICE and move <= 0 and s.type == TYPE_PEGGED:
					s.state = STATE_PEGGED
					s.model = int(_data["pegged_models"][p])
					sound.emit(SOUND_PEG)
	_update_collisions(match_state)


# --- KAR_updateCollisions (kar.c:1362) -------------------------------------------------------------------

func _update_collisions(match_state: int) -> void:
	_bounce_off_wall()
	if match_state != MATCH_SLIDING:
		return
	var cur: Array = []
	var prev: Array = []
	for i in ROWS * PER_ROW:
		cur.append(Vector3i.ZERO)
		prev.append(Vector3i.ZERO)
	var collided := false
	var step := 0
	while step < SUBSTEPS:
		for index in ROWS * PER_ROW:
			var s := _stone(index)
			if s.state > 0:
				var tx1 := s.target.x * (10 - step)
				var tx2 := s.pos.x * step
				var tz1 := s.target.z * (10 - step)
				var tz2 := s.pos.z * step
				# US: cur.vy = target.vy (:1410).
				cur[index] = Vector3i(PsxMath.div(tx1 + tx2, SUBSTEP_DIVISOR), s.target.y,
						PsxMath.div(tz1 + tz2, SUBSTEP_DIVISOR))
		for a in ROWS * PER_ROW:
			if _stone(a).state > 0:
				for b in range(a + 1, ROWS * PER_ROW):
					if _stone(b).state > 0:
						var dist := distance(cur[a].x - cur[b].x, cur[a].z - cur[b].z)
						if dist < CONTACT_DISTANCE:
							collided = true
							if step == 0:
								_resolve_stone_collision(_stone(b), cur[b], _stone(a), cur[a])
							else:
								_resolve_stone_collision(_stone(b), prev[b], _stone(a), prev[a])
		for i in ROWS * PER_ROW:
			prev[i] = cur[i]
		if collided and step == SUBSTEPS - 1:
			step -= 1
		collided = false
		step += 1


# --- KAR_bounceOffWall (kar.c:1468), KAR_getWallZone (:1859) ----------------------------------------------

func _bounce_off_wall() -> void:
	for p in ROWS:
		for n in PER_ROW:
			var s: Stone = rows[p].stones[n]
			if s.state <= 0:
				continue
			if s.speed == 0:
				continue
			var zone := wall_zone(PsxMath.s16(s.pos.x), PsxMath.s16(s.pos.z))
			if zone > 0 and zone < 6:
				sound.emit(SOUND_WALL)
			match zone:
				1:
					var d := PsxMath.s16(s.pos.x + WALL_SIDE_X)
					s.pos.x -= d * 2
					s.angle = 0x800 - s.angle
				2:
					s.angle = 0x1800 - s.angle
					var d := PsxMath.s16(s.pos.x - WALL_SIDE_X)
					s.pos.x -= d * 2
				3:
					var contact := _find_wall_contact(s, 0)
					_reflect_off_diagonal(s, 0)
					_place_at_contact(s, contact)
				4:
					var contact := _find_wall_contact(s, 1)
					_reflect_off_diagonal(s, 1)
					_place_at_contact(s, contact)
				5:
					s.angle = -s.angle
					var d := PsxMath.s16(-WALL_BACK_Z - s.pos.z)
					s.pos.z += d * 2
				6:
					if s.target.z < WALL_FRONT_Z:
						sound.emit(SOUND_WALL)
						s.angle = -s.angle
						var d := PsxMath.s16(s.pos.z - WALL_FRONT_Z)
						s.pos.z -= d * 2


## KAR_getWallZone(int16 x, int16 z): 0 none, 1 left, 2 right, 3 / 4 back diagonals, 5 back, 6 front.
static func wall_zone(x: int, z: int) -> int:
	if z >= WALL_FRONT_Z:
		return 6
	if z >= WALL_SPLIT_Z:
		if x < -WALL_SIDE_X + 1:
			return 1
		if x >= WALL_SIDE_X:
			return 2
	else:
		if z + x * 2 < WALL_DIAGONAL and x < WALL_DIAGONAL_X_LEFT:
			return 3
		if z - x * 2 < WALL_DIAGONAL and x >= WALL_DIAGONAL_X_RIGHT:
			return 4
		if z < WALL_BACK_LIMIT:
			return 5
	return 0


## KAR_findWallContact (kar.c:1888): walks back along angle + 0x800 until t > 0.
func _find_wall_contact(s: Stone, flag: int) -> Vector3i:
	var i := 0
	var ang := (s.angle + 0x800) & 0xFFF
	var v := Vector3i.ZERO
	var t := 0
	while true:
		v.x = s.pos.x + PsxMath.div(i * PsxMath.rcos(ang), 4096)
		v.z = s.pos.z + PsxMath.div(i * PsxMath.rsin(ang), 4096)
		i += 1
		if flag == 0:
			t = (v.z + CONTACT_OFFSET) + v.x * 2
		else:
			t = (v.z + CONTACT_OFFSET) - v.x * 2
		if t > 0:
			break
	return v


## KAR_reflectOffDiagonal (kar.c:1916): writes p[3], the stone's angle.
func _reflect_off_diagonal(s: Stone, dir: int) -> void:
	var cur := (s.angle + 0x800) & 0xFFF
	var ang := PsxMath.ratan2(1, 2) if dir == 0 else PsxMath.ratan2(1, -2)
	s.angle = ang * 2 - cur


## KAR_placeAtContact (kar.c:1934).
func _place_at_contact(s: Stone, p: Vector3i) -> void:
	var d := distance(p.x - s.target.x, p.z - s.target.z)
	d = distance(s.target.z - s.pos.z, s.target.x - s.pos.x) - d
	s.pos.x = p.x + PsxMath.div(d * PsxMath.rcos(s.angle), 4096)
	s.pos.z = p.z + PsxMath.div(d * PsxMath.rsin(s.angle), 4096)


## KAR_distance (kar.c:1530): SquareRoot0 of the uint32 sum of squares.
static func distance(x: int, y: int) -> int:
	var xx := (x * x) & 0xFFFFFFFF
	var yy := (y * y) & 0xFFFFFFFF
	return PsxMath.square_root0(xx + yy)


# --- KAR_resolveStoneCollision (kar.c:1541) and the three kinds ---------------------------------------------

func _resolve_stone_collision(sa: Stone, a: Vector3i, sb: Stone, b: Vector3i) -> void:
	var speed := PsxMath.s16(sa.speed + sb.speed)
	if speed >= HARD_HIT_SPEED:
		sound.emit(SOUND_HARD_HIT)
	else:
		sound.emit(SOUND_SOFT_HIT)
	var a_pegged := sa.state == STATE_PEGGED or sa.state == STATE_PUSHED
	var b_pegged := sb.state == STATE_PEGGED or sb.state == STATE_PUSHED
	if a_pegged or b_pegged:
		if a_pegged:
			_collide_pegged_stone(sa, a, sb, b)
		else:
			_collide_pegged_stone(sb, b, sa, a)
	elif sa.speed <= 0 or sb.speed <= 0:
		if sa.speed <= 0:
			_collide_resting_stone(sa, a, sb, b)
		else:
			_collide_resting_stone(sb, b, sa, a)
	else:
		_collide_moving_stones(sb, b, sa, a)


## KAR_collidePeggedStone (kar.c:1569).
func _collide_pegged_stone(pegged: Stone, a: Vector3i, mover: Stone, b: Vector3i) -> void:
	var ang1 := PsxMath.ratan2(mover.target.z - mover.pos.z, mover.target.x - mover.pos.x) & 0xFFF
	var r := PsxMath.ratan2(b.z - a.z, b.x - a.x) & 0xFFF
	var da := r * 2 - ang1
	if da >= 0x1000:
		da = PsxMath.mod(da, 0x1000)
	var dd := absi(r - ang1)
	dd = PsxMath.mod(dd, 0x400)
	dd = 0x400 - dd
	r = distance(mover.pos.x - b.x, mover.pos.z - b.z)
	r = PsxMath.div(dd * r, 0x400)
	while true:
		mover.pos.x = b.x + PsxMath.div(r * PsxMath.rcos(da), 4096)
		mover.pos.z = b.z + PsxMath.div(r * PsxMath.rsin(da), 4096)
		r += 1
		var dist := distance(mover.pos.x - pegged.pos.x, mover.pos.z - pegged.pos.z)
		if dist >= PUSH_DISTANCE:
			break
	var t := PsxMath.div((mover.speed >> 1) * dd, 0x400)
	pegged.speed = PsxMath.s16(t)
	mover.speed = PsxMath.s16(mover.speed - t)
	pegged.angle = PsxMath.ratan2(mover.target.z - b.z, mover.target.x - b.x)
	mover.angle = da
	pegged.state = STATE_PUSHED
	mover.target = b


## KAR_collideRestingStone (kar.c:1607).
func _collide_resting_stone(resting: Stone, a: Vector3i, mover: Stone, b: Vector3i) -> void:
	if resting.speed == 0 and mover.speed == 0:
		resting.pos = a
		mover.pos = b
		return
	var share := impact_share(mover, b, a)
	var p1 := separation(mover, b, a)
	resting.pos.x = resting.pos.x + p1.x
	resting.pos.z = resting.pos.z + p1.z
	mover.pos.x = mover.pos.x - p1.x
	mover.pos.z -= p1.z
	var d := distance(resting.pos.x - mover.pos.x, resting.pos.z - mover.pos.z)
	var ang := PsxMath.ratan2(p1.z, p1.x)
	var n := distance(p1.x, p1.z)
	var r := 0
	p1 = resting.pos
	var p2 := mover.pos
	if n != 0:
		while d < PUSH_DISTANCE:
			resting.pos.x = p1.x + PsxMath.div(r * PsxMath.rcos(ang), 4096)
			resting.pos.z = p1.z + PsxMath.div(r * PsxMath.rsin(ang), 4096)
			mover.pos.x = p2.x - PsxMath.div(r * PsxMath.rcos(ang), 4096)
			mover.pos.z = p2.z - PsxMath.div(r * PsxMath.rsin(ang), 4096)
			d = distance(resting.pos.x - mover.pos.x, resting.pos.z - mover.pos.z)
			r += 1
	else:
		var push_ang := PsxMath.ratan2(mover.pos.z - resting.pos.z, mover.pos.x - resting.pos.x)
		while d < PUSH_DISTANCE:
			mover.pos.x = p2.x + PsxMath.div(r * PsxMath.rcos(push_ang), 4096)
			mover.pos.z = p2.z + PsxMath.div(r * PsxMath.rsin(push_ang), 4096)
			d = distance(resting.pos.x - mover.pos.x, resting.pos.z - mover.pos.z)
			r += 1
	resting.target = a
	mover.target = b
	mover.speed = PsxMath.s16(mover.speed - share)
	resting.speed = PsxMath.s16(share)
	resting.angle = PsxMath.ratan2(resting.pos.z - a.z, resting.pos.x - a.x) & 0xFFF
	mover.angle = PsxMath.ratan2(mover.pos.z - b.z, mover.pos.x - b.x) & 0xFFF


## KAR_collideMovingStones (kar.c:1665). US pushes A along +ang (JP: -ang).
func _collide_moving_stones(sa: Stone, a: Vector3i, sb: Stone, b: Vector3i) -> void:
	var share1 := impact_share(sa, a, b)
	var share2 := impact_share(sb, b, a)
	var p1 := separation(sb, b, a)
	var p2 := separation(sa, a, b)
	var delta := Vector3i(p2.x - p1.x, 0, p2.z - p1.z)
	var ang := distance(delta.x, delta.z)
	if ang != 0:
		ang = PsxMath.ratan2(delta.z, delta.x)
		sb.pos.x = sb.pos.x + delta.x
		sb.pos.z = sb.pos.z + delta.z
		sa.pos.x = sa.pos.x - delta.x
		sa.pos.z -= delta.z
		var d := distance(sa.pos.x - sb.pos.x, sa.pos.z - sb.pos.z)
		var r := 0
		p1 = sa.pos
		p2 = sb.pos
		sa.speed = PsxMath.s16(sa.speed + PsxMath.s16(share2 - share1))
		sb.speed = PsxMath.s16(sb.speed + PsxMath.s16(share1 - share2))
		if sa.speed > sb.speed:
			while d < PUSH_DISTANCE:
				sa.pos.x = p1.x + PsxMath.div(r * PsxMath.rcos(ang), 4096)
				sa.pos.z = p1.z + PsxMath.div(r * PsxMath.rsin(ang), 4096)
				d = distance(sb.pos.x - sa.pos.x, sb.pos.z - sa.pos.z)
				r += 1
		else:
			while d < PUSH_DISTANCE:
				sb.pos.x = p2.x + PsxMath.div(r * PsxMath.rcos(ang), 4096)
				sb.pos.z = p2.z + PsxMath.div(r * PsxMath.rsin(ang), 4096)
				d = distance(sb.pos.x - sa.pos.x, sb.pos.z - sa.pos.z)
				r += 1
		sa.target = a
		sb.target = b
		sa.angle = PsxMath.ratan2(sa.pos.z - a.z, sa.pos.x - a.x)
		sb.angle = PsxMath.ratan2(sb.pos.z - b.z, sb.pos.x - b.x)
	else:
		if PsxMath.div(sb.speed, sa.weight) < MOVING_RATIO_MIN or PsxMath.div(sa.speed, sb.weight) < MOVING_RATIO_MIN:
			sb.speed = 0
			sb.pos = sb.target
			sa.pos = sa.target
		else:
			sb.pos = b
			sa.pos = a


## KAR_computeImpactShare (kar.c:1762): the part of the stone's speed that goes along a -> b.
func impact_share(stone: Stone, a: Vector3i, b: Vector3i) -> int:
	var ang := stone.angle & 0xFFF
	var impact_ang := PsxMath.ratan2(b.z - a.z, b.x - a.x) & 0xFFF
	var d := (ang - impact_ang) & 0xFFF
	var ret := 0
	if d < 0x400 or d > 0xC00:
		if d > 0xC00:
			d = (0x1000 - d) & 0xFFF
		d = 0x400 - PsxMath.mod(d, 0x400)
		ret = PsxMath.div(d * stone.speed, 0x400)
	return ret


## KAR_computeSeparation (kar.c:1784): the vector `out` (the C returns it by pointer and its int32
## return value is never set).
func separation(stone: Stone, a: Vector3i, b: Vector3i) -> Vector3i:
	var cur := stone.angle & 0xFFF
	var ang := PsxMath.ratan2(b.z - a.z, b.x - a.x) & 0xFFF
	var d := absi(cur - ang)
	var v := Vector3i.ZERO
	if d < 0x400 or d > 0xC00:
		d = PsxMath.mod(d, 0x400)
		var dist := distance(stone.pos.z - a.z, stone.pos.x - a.x)
		var r := PsxMath.div((0x400 - d) * dist, 0x400)
		while true:
			v.x = PsxMath.div(r * PsxMath.rcos(ang), 4096)
			v.z = PsxMath.div(r * PsxMath.rsin(ang), 4096)
			var n := distance(v.x, v.z)
			r += 1
			if n != 0:
				break
	return v


# --- KAR_checkStonesStopped (kar.c:1319) -----------------------------------------------------------------------

## True where the C sets match state 0xC (no stone with state > 0 and speed > 0). The caller runs it in
## state 0xB; the out-of-play rule always runs (the C's first loop breaks out of a row at the first
## moving stone, so the speed reset of the rest of that row is skipped).
func check_stopped() -> bool:
	var moving := false
	for p in ROWS:
		for n in PER_ROW:
			var s: Stone = rows[p].stones[n]
			if s.state > 0:
				if s.speed > 0:
					moving = true
					break
				s.speed = 0
	for p in ROWS:
		for n in PER_ROW:
			var s: Stone = rows[p].stones[n]
			if s.state > 0:
				if s.pos.z >= OUT_OF_PLAY_Z:
					if s.speed <= 0:
						s.state = STATE_OUT
	return not moving


# --- KAR_classifyStoneRings (kar.c:2140), KAR_updateRingMarkers state 0xB (:1248) -----------------------------

## Without KAR_registerThrownStone (C3). The first KAR_distance at :2160 is unused.
func classify_rings() -> void:
	for p in 2:
		rows[p].score = 0
		for i in PER_ROW:
			var s: Stone = rows[p].stones[i]
			s.prev_ring = s.ring
			s.ring = 0
			if s.state <= 0:
				continue
			if s.pos.z >= RING_LINE_Z:
				continue
			for zi in ZONE_COUNT:
				var z: Dictionary = _zones[zi]
				var dist := distance(s.pos.x + int(z["dx"]), s.pos.z + int(z["dz"]))
				if dist > int(z["radius"]):
					continue
				s.ring = zi + 1
				if p != 0:
					s.ring |= RING_ROW1_FLAG
				break


## The bit mask (MAIN_D_80135257) the ring markers light in match state 0xB: for each moving stone of
## rows 0-1, the first zone not yet lit that has distance < radius.
func lit_rings() -> int:
	var lit := 0
	for p in 2:
		for i in PER_ROW:
			var s: Stone = rows[p].stones[i]
			if s.state > 0 and s.speed > 0:
				for zi in ZONE_COUNT:
					if (lit >> zi) & 1 == 0:
						var z: Dictionary = _zones[zi]
						var dist := distance(s.pos.x + int(z["dx"]), s.pos.z + int(z["dz"]))
						if dist < int(z["radius"]):
							lit |= 1 << zi
							break
	return lit
