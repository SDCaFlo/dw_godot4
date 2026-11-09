class_name CurlingAi
extends RefCounted
## The opponent's shot (specs/curling.md §2.5, step C3): KAR_chooseOpponentShot (kar.c:2306) and its
## helpers, in the C's integers. It writes row 1's plan (`plan_stone` = KarStoneRow.unk4, `plan_power`
## = unk2) and the chosen stone's `angle`; CurlingMatch reads them in states 5, 6 and 8.
## `opponent` is the opponent's entity slot (MAIN_D_80135248: 2 Penguinmon, 3 MetalMamemon), a script
## value (pstat 0x7A + 2), not a record id. The thrower's point is read as each C function reads it:
## Penguinmon's location (KAR_findClearShotAngle, kar.c:2537) or MetalMamemon's bone 4 (:2540, :2359,
## :2680). `rand()` is Rng.rand().

## The opponent slots the C tests (`MAIN_D_80135248 == 2`, kar.c:2316, :2543, :2724).
const PENGUINMON := 2
## The bone whose world translation is MetalMamemon's point (posData[4], kar.c:2359, :2540, :2680).
const BONE_THROWER := 4
## Targets (x, z): the GOOD centre (kar.c:2318), the back-left point (:2330), the left GOOD ring (:2363);
## the bank shot's target, the BAD ring (:2427).
const CENTRE_X := 0
const CENTRE_Z := -0x6A4
const BACK_LEFT_X := -0x190
const BACK_LEFT_Z := -0x960
const BACK_LEFT_PLAN_X := 0
const LEFT_RING_X := -0x190
const LEFT_RING_Z := -0x8FC
const BANK_TARGET_X := 0x190
const BANK_TARGET_Z := -0x8FC
## aimAtStoneInRing's keys: its own stone in ring 4 (0x14 = ring 4 | row 1's 0x10, kar.c:2322), a tamer
## stone in ring 2 (:2326).
const KEY_OWN_RING4 := 0x14
const KEY_TAMER_RING2 := 2
## The power set over the plan after a random / bank shot (kar.c:2336, :2351, :2429).
const FIXED_POWER := 0x960
## The random offset of a shot at the centre: ± rand() % 100 (kar.c:2375-2377).
const RANDOM_SPREAD := 100
## MetalMamemon's "no plan yet" mark in unk4 (kar.c:2392, :2396, :2400).
const NO_PLAN := 6
## The pegged type (kar.c:2385, :2432).
const TYPE_PEGGED := 3
## The tamer's last stone's rings that make MetalMamemon go for the left ring: BAD (3) or none (kar.c:2405).
const RING_BAD := 3
## KAR_findClearShotAngle: the path's step, 30 for Penguinmon, 10 otherwise (kar.c:2545-2547); a stone
## closer than 0x97 blocks it (:2557).
const STEP_PENGUINMON := 30
const STEP_OTHER := 10
const BLOCK_DISTANCE := 0x97
## The opponent's spot, where the power and the random aim are measured from (kar.c:2658, :2715).
const SPOT_X := 0x190
const SPOT_Z := 0x578
## KAR_aimAtRandomStone's angle when the tamer's last stone is gone: ratan2(-0xC1C, -0x190) (kar.c:2636).
const GONE_DY := -0xC1C
const GONE_DX := -0x190
## KAR_aimBankShot: 150 units behind the stone (kar.c:2676), mirrored in the left wall x = -0x2D5 (:2678).
const BANK_BEHIND := 150
const LEFT_WALL_X := 0x2D5
## KAR_computeThrowPower: the friction run backwards (speed * 100 / 98, kar.c:2720) and the power
## offsets, 0x258 Penguinmon / 0x1F4 MetalMamemon (:2725, :2727).
const POWER_SCALE := 100
const FRICTION_NUM := 98
const POWER_OFFSET_PENGUINMON := 0x258
const POWER_OFFSET_OTHER := 0x1F4

var stones: CurlingStones
var world: CurlingWorld
## KAR_D_8005B418: the stone types to try per plan row (data `shot_plans`).
var _plans: Array


## `data` is GameData.curling() (port-only argument: the shot plans live in the data).
func _init(p_stones: CurlingStones, p_world: CurlingWorld, data: Dictionary) -> void:
	stones = p_stones
	world = p_world
	_plans = data["shot_plans"]


# --- KAR_chooseOpponentShot (kar.c:2306) ---------------------------------------------------------------

## Writes row 1's plan for the opponent in slot `opponent`. `last_stone` is KAR_D_80063914, the copy of
## the tamer's last stone.
func choose(opponent: int, last_stone: CurlingStones.Stone) -> void:
	var row1: CurlingStones.Row = stones.rows[1]
	var angle: int
	if opponent == PENGUINMON:
		angle = find_clear_shot_angle(opponent, CENTRE_X, CENTRE_Z)
		if angle == -1:
			if stones.rows[0].score > row1.score:
				# The tamer leads: its own stone in ring 4 first (kar.c:2322).
				var hit := aim_at_stone_in_ring(opponent, 1, KEY_OWN_RING4)
				if hit.x != -1:
					set_shot(opponent, 0, hit.x, hit.y, hit.z)
				else:
					_penguinmon_chain(opponent, last_stone)
			else:
				_penguinmon_chain(opponent, last_stone)
		else:
			set_shot(opponent, 1, angle, CENTRE_X, CENTRE_Z)  # kar.c:2356
		return
	var bone := world.bone_translation(opponent, BONE_THROWER)
	var px := PsxMath.s16(bone.x)
	var pz := PsxMath.s16(bone.z)
	var clear: int
	if row1.thrown == 0:
		# The first stone (kar.c:2362).
		angle = PsxMath.ratan2(LEFT_RING_Z - pz, LEFT_RING_X - px)
		clear = find_clear_shot_angle(opponent, LEFT_RING_X, LEFT_RING_Z)
		if angle == clear:
			set_shot(opponent, 1, angle, LEFT_RING_X, LEFT_RING_Z)
		else:
			angle = PsxMath.ratan2(CENTRE_Z - pz, CENTRE_X - px)
			clear = find_clear_shot_angle(opponent, CENTRE_X, CENTRE_Z)
			if angle == clear:
				set_shot(opponent, 1, angle, CENTRE_X, CENTRE_Z)
			else:
				_centre_with_offset(opponent, px, pz)
		return
	# Later stones: the first waiting stone of row 1 (kar.c:2382-2398).
	for i in CurlingStones.PER_ROW:
		var s: CurlingStones.Stone = row1.stones[i]
		if s.state == CurlingStones.STATE_WAITING:
			if s.type == TYPE_PEGGED:
				row1.plan_stone = i
				angle = PsxMath.ratan2(CENTRE_Z - pz, CENTRE_X - px)
				clear = find_clear_shot_angle(opponent, CENTRE_X, CENTRE_Z)
				if angle == clear:
					set_shot(opponent, 1, angle, CENTRE_X, CENTRE_Z)
				else:
					row1.plan_stone = NO_PLAN
				break
			row1.plan_stone = NO_PLAN
	if row1.plan_stone != NO_PLAN:
		return
	# Answer the tamer's last stone (kar.c:2400).
	match last_stone.type:
		0, 1, 2:
			if last_stone.ring == RING_BAD or last_stone.ring == 0:
				angle = PsxMath.ratan2(LEFT_RING_Z - pz, LEFT_RING_X - px)
				clear = find_clear_shot_angle(opponent, LEFT_RING_X, LEFT_RING_Z)  # unused (kar.c:2407)
				set_shot(opponent, 1, angle, LEFT_RING_X, LEFT_RING_Z)
			elif last_stone.state < 0:
				_centre_with_offset(opponent, px, pz)
			elif Rng.rand() % 2 != 0:
				angle = PsxMath.ratan2(LEFT_RING_Z - pz, LEFT_RING_X - px)
				clear = find_clear_shot_angle(opponent, LEFT_RING_X, LEFT_RING_Z)
				if angle == clear:
					set_shot(opponent, 1, angle, LEFT_RING_X, LEFT_RING_Z)
				else:
					angle = PsxMath.ratan2(last_stone.pos.z - pz, last_stone.pos.x - px)
					set_shot(opponent, 0, angle, PsxMath.s16(last_stone.pos.x), PsxMath.s16(last_stone.pos.z))
			else:
				angle = aim_bank_shot(opponent, last_stone, BANK_TARGET_X, BANK_TARGET_Z)
				set_shot(opponent, 0, angle, BANK_TARGET_X, BANK_TARGET_Z)
				row1.plan_power = FIXED_POWER
		TYPE_PEGGED:
			_centre_with_offset(opponent, px, pz)


## Penguinmon's chain after its own ring-4 stone (kar.c:2326-2338, the same as :2341-2353).
func _penguinmon_chain(opponent: int, last_stone: CurlingStones.Stone) -> void:
	var hit := aim_at_stone_in_ring(opponent, 0, KEY_TAMER_RING2)
	if hit.x != -1:
		set_shot(opponent, 0, hit.x, hit.y, hit.z)
		return
	var angle := find_clear_shot_angle(opponent, BACK_LEFT_X, BACK_LEFT_Z)
	if angle != -1:
		set_shot(opponent, 1, angle, BACK_LEFT_PLAN_X, BACK_LEFT_Z)
	else:
		angle = aim_at_random_stone(last_stone)
		set_shot(opponent, 0, angle, BACK_LEFT_PLAN_X, BACK_LEFT_Z)
		stones.rows[1].plan_power = FIXED_POWER


## MetalMamemon's shot at the centre with ± rand() % 100 (+ on an odd count, kar.c:2373-2379, :2410-2416,
## :2433-2439), plan row 0.
func _centre_with_offset(opponent: int, px: int, pz: int) -> void:
	var angle := PsxMath.ratan2(CENTRE_Z - pz, CENTRE_X - px)
	if PsxMath.mod(stones.rows[1].thrown, 2) != 0:
		angle += Rng.rand() % RANDOM_SPREAD
	else:
		angle -= Rng.rand() % RANDOM_SPREAD
	set_shot(opponent, 0, angle, CENTRE_X, CENTRE_Z)


# --- KAR_findClearShotAngle (kar.c:2525) ---------------------------------------------------------------

## The angle from the thrower to (x, z) if no stone with state > 0 is within 0x97 of the path; when one
## is, -1 for Penguinmon, else the angle from (x, z) to that stone (not the shot's direction).
func find_clear_shot_angle(opponent: int, x: int, z: int) -> int:
	x = PsxMath.s16(x)
	z = PsxMath.s16(z)
	var loc := world.location(opponent)
	var px := PsxMath.s16(loc.x)
	var pz := PsxMath.s16(loc.z)
	if opponent != PENGUINMON:
		var bone := world.bone_translation(opponent, BONE_THROWER)
		px = PsxMath.s16(bone.x)
		pz = PsxMath.s16(bone.z)
	var ang := PsxMath.ratan2(z - pz, x - px)
	var step := STEP_PENGUINMON if opponent == PENGUINMON else STEP_OTHER
	while z < pz:
		# Each step truncated to int16, and px / pz are int16 (kar.c:2549-2550).
		px = PsxMath.s16(px + PsxMath.s16(PsxMath.div(step * PsxMath.rcos(ang), 4096)))
		pz = PsxMath.s16(pz + PsxMath.s16(PsxMath.div(step * PsxMath.rsin(ang), 4096)))
		for p in CurlingStones.ROWS:
			for n in CurlingStones.PER_ROW:
				var s: CurlingStones.Stone = stones.rows[p].stones[n]
				if s.state > 0:
					var dist := CurlingStones.distance(px - s.pos.x, pz - s.pos.z)
					if dist < BLOCK_DISTANCE:
						if opponent == PENGUINMON:
							return -1
						return PsxMath.ratan2(s.pos.z - z, s.pos.x - x)
	return ang


# --- KAR_aimAtStoneInRing (kar.c:2576) -----------------------------------------------------------------

## The first stone of `row` with state < 2 and ring == key: Vector3i(find_clear_shot_angle at it, its
## int16 x, its int16 z). None: x = -1 (the C returns -1 and leaves outX / outZ unset).
func aim_at_stone_in_ring(opponent: int, row: int, key: int) -> Vector3i:
	for i in CurlingStones.PER_ROW:
		var s: CurlingStones.Stone = stones.rows[row].stones[i]
		if s.state < CurlingStones.STATE_PEGGED and s.ring == key:
			var r := find_clear_shot_angle(opponent, PsxMath.s16(s.pos.x), PsxMath.s16(s.pos.z))
			return Vector3i(r, PsxMath.s16(s.pos.x), PsxMath.s16(s.pos.z))
	return Vector3i(-1, 0, 0)


# --- KAR_setOpponentShot (kar.c:2600) ------------------------------------------------------------------

## The plan: the first unused row-1 stone of the types KAR_D_8005B418[plan_row] lists, its angle, and the
## power to reach (x, z).
func set_shot(opponent: int, plan_row: int, angle: int, x: int, z: int) -> void:
	var row1: CurlingStones.Row = stones.rows[1]
	# The C leaves `stone` uninitialised when no type has an unused stone. That can't happen while a
	# row-1 stone waits (the four types cover every stone), and state 0x11 only runs on the opponent's
	# turn, when it has one. Here `stone` would stay null.
	var stone: CurlingStones.Stone = null
	for i in 4:
		var n := find_unused_stone_of_type(int(_plans[plan_row][i]))
		if n >= 0:
			row1.plan_stone = n
			stone = row1.stones[n]
			break
	stone.angle = angle
	var power := compute_throw_power(opponent, stone.weight, x, z)
	row1.plan_power = PsxMath.s16(power)  # unk2 is int16


# --- KAR_aimAtRandomStone (kar.c:2624) -----------------------------------------------------------------

## The angle from the opponent's spot to a random tamer stone on the ice (rand() % count), or to the
## centre when there is none; a fixed angle when the tamer's last stone is gone.
func aim_at_random_stone(last_stone: CurlingStones.Stone) -> int:
	if last_stone.state < 0:
		return PsxMath.ratan2(GONE_DY, GONE_DX)
	var cands: Array = []
	for i in CurlingStones.PER_ROW:
		var s: CurlingStones.Stone = stones.rows[0].stones[i]
		if s.state == CurlingStones.STATE_ICE:
			cands.append(s)
	var px: int
	var pz: int
	if cands.is_empty():
		px = CENTRE_X
		pz = CENTRE_Z
	else:
		var idx := (Rng.rand() % cands.size()) & 0xFF  # uint8 idx, uint8 count
		px = PsxMath.s16(cands[idx].pos.x)
		pz = PsxMath.s16(cands[idx].pos.z)
	return PsxMath.ratan2(pz - SPOT_Z, px - SPOT_X)


# --- KAR_aimBankShot (kar.c:2663) ----------------------------------------------------------------------

## The angle from bone 4 to the point 150 units behind `stone` (away from (x, z)), mirrored in the left
## wall.
func aim_bank_shot(opponent: int, stone: CurlingStones.Stone, x: int, z: int) -> int:
	x = PsxMath.s16(x)
	z = PsxMath.s16(z)
	var ang := PsxMath.ratan2(stone.pos.z - z, stone.pos.x - x)
	var cx := stone.pos.x + PsxMath.div(PsxMath.rcos(ang) * BANK_BEHIND, 4096)
	var cz := stone.pos.z + PsxMath.div(PsxMath.rsin(ang) * BANK_BEHIND, 4096)
	var t := cx + LEFT_WALL_X
	cx = -LEFT_WALL_X - t
	var bone := world.bone_translation(opponent, BONE_THROWER)
	return PsxMath.ratan2(cz - bone.z, cx - bone.x)


# --- KAR_findUnusedStoneOfType (kar.c:2686) -------------------------------------------------------------

## The first row-1 stone waiting in the stack (state -1) with that type, else -1.
func find_unused_stone_of_type(type: int) -> int:
	for i in CurlingStones.PER_ROW:
		var s: CurlingStones.Stone = stones.rows[1].stones[i]
		if s.state == CurlingStones.STATE_WAITING and s.type == type:
			return i
	return -1


# --- KAR_computeThrowPower (kar.c:2704) ----------------------------------------------------------------

## The power that slides a stone of `weight` from the opponent's spot to (x, z): the friction loop run
## backwards in uint32, minus the opponent's offset. Returned as the C's int32.
func compute_throw_power(opponent: int, weight: int, x: int, z: int) -> int:
	x = PsxMath.s16(x)
	z = PsxMath.s16(z)
	var a := weight & 0xFFFFFFFF
	var dist := CurlingStones.distance(SPOT_X - x, SPOT_Z - z)
	var acc := 0
	var cur := a
	var value := (cur * POWER_SCALE) & 0xFFFFFFFF
	# All non-negative uint32 values: PsxMath.div is the unsigned division here.
	while acc < dist:
		acc = (acc + PsxMath.div(cur, a)) & 0xFFFFFFFF
		value = PsxMath.div((value * POWER_SCALE) & 0xFFFFFFFF, FRICTION_NUM)
		cur = PsxMath.div(value, POWER_SCALE)
	if opponent == PENGUINMON:
		cur = (cur - POWER_OFFSET_PENGUINMON) & 0xFFFFFFFF
	else:
		cur = (cur - POWER_OFFSET_OTHER) & 0xFFFFFFFF
	return PsxMath.s32(cur)
