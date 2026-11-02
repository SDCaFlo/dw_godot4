class_name PsxMath
## The PSX integer maths the battle effects and the battle use (specs/battle_effects.md §3.3), so
## their motion and hit timing come out as the original's:
## - the game's own helpers, exact: _sin / _cos / _atan (math.c, tables from systems/psx_math),
##   getDistance, toEulerAngles, matrixToEuler1 / 2, multiplyRotations (vecmath.c), lerp
##   (effect_common.c);
## - the PSY-Q libgte functions (RotMatrix*, ApplyMatrix*, MulMatrix0, ScaleMatrix, rsin / rcos,
##   ratan2), from their documented behaviour: 4096 = 1.0 and a full turn. libgte's own tables
##   aren't in the decomp; rsin / rcos are round(4096 sin) and ratan2 rounds atan2 (an open point,
##   specs/battle_effects.md §6).
## Matrices are PackedInt32Array(12): m[0][0] m[0][1] m[0][2] m[1][0] … m[2][2], then t x, y, z.
## Vectors are Vector3i. SVECTOR / MATRIX entries are int16: `s16` wraps like a C cast.

const ONE := 4096
const TURN := 4096

static var _sin_table := PackedInt32Array()
static var _atan_table := PackedInt32Array()
static var _rsin := PackedInt32Array()


## Loads the game's tables (GameData.system("psx_math")). Safe to call more than once.
static func setup(data: Node) -> void:
	if not _sin_table.is_empty():
		return
	for record in data.system("psx_math"):
		var values := PackedInt32Array()
		for v in record["values"]:
			values.append(int(v))
		if record["name"] == "SIN_LOOKUP_TABLE":
			_sin_table = values
		elif record["name"] == "ATAN_LOOKUP_TABLE":
			_atan_table = values
	_rsin.resize(TURN)
	for i in TURN:
		_rsin[i] = roundi(sin(TAU * i / TURN) * ONE)


static func ready() -> bool:
	return not _sin_table.is_empty()


# --- C integer helpers ----------------------------------------------------------------------------

## (int16_t) cast.
static func s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## (int8_t) cast.
static func s8(v: int) -> int:
	v &= 0xFF
	return v - 0x100 if v >= 0x80 else v


## (int32_t) cast.
static func s32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


## C division: truncates toward zero. A division by 0 gives 0 (the PSX doesn't trap; the script
## would get garbage).
static func div(a: int, b: int) -> int:
	if b == 0:
		return 0
	var q := absi(a) / absi(b)
	return -q if (a < 0) != (b < 0) else q


## C remainder: the sign of the dividend.
static func mod(a: int, b: int) -> int:
	if b == 0:
		return 0
	return a - div(a, b) * b


static func s16_vec(v: Vector3i) -> Vector3i:
	return Vector3i(s16(v.x), s16(v.y), s16(v.z))


## GTE IR saturation (the result of a matrix product stored into an SVECTOR).
static func _sat16(v: int) -> int:
	return clampi(v, -0x8000, 0x7FFF)


# --- the game's angle helpers (math.c) --------------------------------------------------------

## _sin (math.c:13): 512 = a full turn, from the 128-step quarter table.
static func sin512(input: int) -> int:
	input &= 0x1FF
	if input < 128:
		return _sin_table[input]
	if input < 256:
		return _sin_table[256 - input]
	if input < 384:
		return -_sin_table[input - 256]
	return -_sin_table[512 - input]


## _cos (math.c:29).
static func cos512(input: int) -> int:
	return sin512(input + 128)


## _atan (math.c:34): the angle of (dx, dy) in 4096 units, (value + 2048) & 0xfff.
static func atan(dy: int, dx: int) -> int:
	var direction := 0
	if dy < 0:
		direction = 2 if dx < 0 else 1
	else:
		direction = 3 if dx < 0 else 0
	var ady := absi(dy)
	var adx := absi(dx)
	var value := 0
	if ady >= adx:
		var offset := div(adx * 512, ady) if ady > 0 else 0
		value = _atan_table[mini(offset, 511)]
	else:
		var offset := div(ady * 512, adx) if adx > 0 else 0
		value = 1023 - _atan_table[mini(offset, 511)]
	if direction == 1 or direction == 2:
		value = 2048 - value
	if direction >= 2:
		value = -value
	return (value + 2048) & 0xFFF


# --- libgte ---------------------------------------------------------------------------------------

static func rsin(a: int) -> int:
	return _rsin[a & 0xFFF]


static func rcos(a: int) -> int:
	return _rsin[(a + 1024) & 0xFFF]


## ratan2(y, x): -2048..2048.
static func ratan2(y: int, x: int) -> int:
	if y == 0 and x == 0:
		return 0
	return roundi(atan2(float(y), float(x)) * 2048.0 / PI)


static func identity() -> PackedInt32Array:
	return PackedInt32Array([ONE, 0, 0, 0, ONE, 0, 0, 0, ONE, 0, 0, 0])


static func _rx(a: int) -> PackedInt32Array:
	var s := rsin(a)
	var c := rcos(a)
	return PackedInt32Array([ONE, 0, 0, 0, c, -s, 0, s, c, 0, 0, 0])


static func _ry(a: int) -> PackedInt32Array:
	var s := rsin(a)
	var c := rcos(a)
	return PackedInt32Array([c, 0, s, 0, ONE, 0, -s, 0, c, 0, 0, 0])


static func _rz(a: int) -> PackedInt32Array:
	var s := rsin(a)
	var c := rcos(a)
	return PackedInt32Array([c, -s, 0, s, c, 0, 0, 0, ONE, 0, 0, 0])


## RotMatrix: Rx · Ry · Rz (the order matrixToEuler1 inverts). Keeps the translation of `into`.
static func rot_matrix(r: Vector3i, into := PackedInt32Array()) -> PackedInt32Array:
	r = s16_vec(r)
	return _with_t(mul_matrix0(mul_matrix0(_rx(r.x), _ry(r.y)), _rz(r.z)), into)


## RotMatrixYXZ: Ry · Rx · Rz (the order matrixToEuler2 inverts).
static func rot_matrix_yxz(r: Vector3i, into := PackedInt32Array()) -> PackedInt32Array:
	r = s16_vec(r)
	return _with_t(mul_matrix0(mul_matrix0(_ry(r.y), _rx(r.x)), _rz(r.z)), into)


## RotMatrixZYX: Rz · Ry · Rx.
static func rot_matrix_zyx(r: Vector3i, into := PackedInt32Array()) -> PackedInt32Array:
	r = s16_vec(r)
	return _with_t(mul_matrix0(mul_matrix0(_rz(r.z), _ry(r.y)), _rx(r.x)), into)


static func _with_t(m: PackedInt32Array, into: PackedInt32Array) -> PackedInt32Array:
	if into.size() == 12:
		m[9] = into[9]
		m[10] = into[10]
		m[11] = into[11]
	return m


## MulMatrix0(a, b): the rotation part a · b (>> 12 per element); the translation is 0.
static func mul_matrix0(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(12)
	for i in 3:
		for j in 3:
			var sum := 0
			for k in 3:
				sum += a[i * 3 + k] * b[k * 3 + j]
			out[i * 3 + j] = s16(sum >> 12)
	return out


## ScaleMatrix(m, s): column j times s[j] (4096 = 1.0).
static func scale_matrix(m: PackedInt32Array, s: Vector3i) -> PackedInt32Array:
	var out := m.duplicate()
	var sc := [s.x, s.y, s.z]
	for i in 3:
		for j in 3:
			out[i * 3 + j] = s16((m[i * 3 + j] * sc[j]) >> 12)
	return out


static func transpose(m: PackedInt32Array) -> PackedInt32Array:
	var out := m.duplicate()
	for i in 3:
		for j in 3:
			out[i * 3 + j] = m[j * 3 + i]
	return out


## TransMatrix: sets the translation.
static func trans_matrix(m: PackedInt32Array, t: Vector3i) -> PackedInt32Array:
	var out := m.duplicate()
	out[9] = t.x
	out[10] = t.y
	out[11] = t.z
	return out


## ApplyMatrixSV: (m · v) >> 12, v and the result SVECTORs (the GTE saturates the result).
static func apply_matrix_sv(m: PackedInt32Array, v: Vector3i) -> Vector3i:
	v = s16_vec(v)
	return Vector3i(_sat16(_row(m, 0, v) >> 12), _sat16(_row(m, 1, v) >> 12), _sat16(_row(m, 2, v) >> 12))


## ApplyMatrixLV / ApplyMatrix: (m · v) >> 12 with 32-bit vectors.
static func apply_matrix_lv(m: PackedInt32Array, v: Vector3i) -> Vector3i:
	return Vector3i(s32(_row(m, 0, v) >> 12), s32(_row(m, 1, v) >> 12), s32(_row(m, 2, v) >> 12))


static func _row(m: PackedInt32Array, i: int, v: Vector3i) -> int:
	return m[i * 3] * v.x + m[i * 3 + 1] * v.y + m[i * 3 + 2] * v.z


static func translation(m: PackedInt32Array) -> Vector3i:
	return Vector3i(m[9], m[10], m[11])


## GsMulCoord0(a, b): a · b, translation a.rot · b.t >> 12 + a.t.
static func gs_mul_coord0(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	var out := mul_matrix0(a, b)
	var t := apply_matrix_lv(a, translation(b)) + translation(a)
	out[9] = t.x
	out[10] = t.y
	out[11] = t.z
	return out


## RTPS / RTPT on one vertex through `ls` (GsSetLsMatrix: rotation and translation) with the
## projection `h`: true when the GTE sets FLAG bit 31. The bits that can set it here: IR1-3
## saturated (24-22), SZ3 out of 0..0xFFFF (18), the divide overflow when SZ3 * 2 <= h (17), SX2 /
## SY2 out of -0x400..0x3FF (14, 13). The geometry offset is 0: GsInitGraph(…, 4 = GsOFSGPU, …)
## (main.c:3563) leaves the offset to the GPU. stand-in: the quotient is the exact h * 0x10000 / SZ3,
## not the GTE's UNR table (at most one off, so SX2 / SY2 can differ at the screen edge by one).
static func rtp_flag_error(ls: PackedInt32Array, v: Vector3i, h: int) -> bool:
	var mac := [((ls[9] << 12) + _row(ls, 0, v)) >> 12, ((ls[10] << 12) + _row(ls, 1, v)) >> 12,
			((ls[11] << 12) + _row(ls, 2, v)) >> 12]
	for c in 3:
		if mac[c] < -0x8000 or mac[c] > 0x7FFF:
			return true
	var sz: int = mac[2]
	if sz < 0 or sz > 0xFFFF or sz * 2 <= h:
		return true
	var q := mini(0x1FFFF, h * 0x10000 / sz)
	var sx: int = (mac[0] * q) >> 16
	var sy: int = (mac[1] * q) >> 16
	return sx < -0x400 or sx > 0x3FF or sy < -0x400 or sy > 0x3FF


## libgs's TMD sort functions (GsSortObject4J's GsTMDfast*, main/graphics.c:62): after RTPT (and
## RTPS for a quad's fourth vertex) `cfc2 $31; bltz` skips the polygon (libgte.s, GsTMDfastTF3L
## 0x8009CC50, GsTMDfastTF4L). So a polygon is not drawn when any vertex sets FLAG bit 31.
static func gs_polygon_dropped(ls: PackedInt32Array, verts: Array, h: int) -> bool:
	for v in verts:
		if rtp_flag_error(ls, v, h):
			return true
	return false


# --- vecmath.c ------------------------------------------------------------------------------------

## The 8-bit square roots of getDistance (vecmath.c DISTANCE_SQRT_LOOKUP).
const _SQRT := [
	0, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5,
	5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
	8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
	9, 9, 9, 9, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 11, 11, 11, 11, 11, 11, 11,
	11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
	12, 12, 12, 12, 12, 12, 12, 12, 12, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
	13, 13, 13, 13, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
	14, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
]


## The GTE's leading-zero count: leading 0 bits of a positive, leading 1 bits of a negative.
static func _lzc(v: int) -> int:
	v &= 0xFFFFFFFF
	if v & 0x80000000:
		v = ~v & 0xFFFFFFFF
	var n := 0
	var bit := 0x80000000
	while n < 32 and (v & bit) == 0:
		n += 1
		bit >>= 1
	return n


## getDistance (vecmath.c:139).
static func get_distance(dx: int, dy: int, dz: int) -> int:
	dx = absi(dx)
	dy = absi(dy)
	dz = absi(dz)
	var shift := s32(dx + dy + dz)
	if shift <= 0:
		return -0x80000000 if shift != 0 else 0
	shift = maxi(17 - _lzc(shift), 0)
	dx >>= shift
	dy >>= shift
	dz >>= shift
	var sq := s32(dx * dx + dy * dy + dz * dz)
	var root: int = _SQRT[sq & 0xFF]
	if sq >= 0x100:
		var lz := _lzc(sq)
		var r := (lz & 1) + 24 - lz
		root = _SQRT[sq >> r] << (r >> 1)
		root += (div(sq, root) - root) >> 1
		root += (div(sq, root) - root) >> 1
	var result := s32(root << shift)
	return -0x80000000 if result < 0 else result


## toEulerAngles (vecmath.c:117): the rotation pointing along (dx, dy, dz).
static func to_euler_angles(dx: int, dy: int, dz: int) -> Vector3i:
	var vy := s16(ratan2(dx, dz))
	var flat := get_distance(dx, 0, dz)
	var vx := s16(-ratan2(dy, flat))
	vx = s16(vx & 0xFFF)
	vx -= 0x1000 if vx >= 0x800 else 0
	vy = s16(vy & 0xFFF)
	vy -= 0x1000 if vy >= 0x800 else 0
	return Vector3i(s16(vx), s16(vy), 0)


static func _abs_max4(a: int, b: int, c: int, d: int) -> int:
	return maxi(maxi(absi(a), absi(b)), maxi(absi(c), absi(d)))


## matrixToEuler1 (vecmath.c:177): the angles of an XYZ (RotMatrix) matrix.
static func matrix_to_euler1(m: PackedInt32Array) -> Vector3i:
	if m[8] == 0 and m[0] == 0:
		return Vector3i(s16(ratan2(m[7], m[4])), 0x400 if m[2] > 0 else -0x400, 0)
	var vx := s16(ratan2(-m[5], m[8]))
	var vz := s16(ratan2(-m[1], m[0]))
	var sx := rsin(vx)
	var cx := rcos(vx)
	var sz := rsin(vz)
	var cz := rcos(vz)
	var top := _abs_max4(sx, cx, sz, cz)
	var value := 0
	if top == absi(sx):
		value = div(m[5] * -0x1000, sx)
	elif top == absi(cx):
		value = div(m[8] << 12, cx)
	elif top == absi(sz):
		value = div(m[1] * -0x1000, sz)
	else:
		value = div(m[0] << 12, cz)
	return Vector3i(vx, s16(ratan2(m[2], value)), vz)


## matrixToEuler2 (vecmath.c:217): the angles of a YXZ (RotMatrixYXZ) matrix.
static func matrix_to_euler2(m: PackedInt32Array) -> Vector3i:
	if m[8] == 0 and m[2] == 0:
		return Vector3i(-0x400 if m[5] > 0 else 0x400, s16(ratan2(-m[6], m[0])), 0)
	var vy := s16(ratan2(m[2], m[8]))
	var vz := s16(ratan2(m[3], m[4]))
	var sy := rsin(vy)
	var cy := rcos(vy)
	var sz := rsin(vz)
	var cz := rcos(vz)
	var top := _abs_max4(sy, cy, sz, cz)
	var value := 0
	if top == absi(sy):
		value = div(m[2] << 12, sy)
	elif top == absi(cy):
		value = div(m[8] << 12, cy)
	elif top == absi(sz):
		value = div(m[3] << 12, sz)
	else:
		value = div(m[4] << 12, cz)
	return Vector3i(s16(ratan2(-m[5], value)), vy, vz)


## multiplyRotations (vecmath.c:279): a then b, as YXZ angles.
static func multiply_rotations(a: Vector3i, b: Vector3i) -> Vector3i:
	if b == Vector3i.ZERO:
		return a
	return matrix_to_euler2(mul_matrix0(rot_matrix_yxz(a), rot_matrix_yxz(b)))


## lerp (effect_common.c:278), with its wrap-around quirk.
static func lerp_int(start: int, end: int, t0: int, t1: int, t: int) -> int:
	if t1 == t0:
		return 0
	var span := end - start
	var result := div(span * (t - t0), t1 - t0)
	if span >= 0:
		result = mod(result, span + 1)
		if result < 0:
			result += span
	else:
		result = mod(result, span - 1)
		if result > 0:
			result += span
	return result + start
