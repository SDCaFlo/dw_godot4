class_name Rng
## Random numbers like the original's helpers, on one Godot generator. The PSX rand() sequence is
## not reproduced (its seed differs per run anyway); set_seed() makes runs repeatable in tests.

## rand() range: 0..0x7FFF.
const RAND_MAX := 0x7FFF

static var _rng := RandomNumberGenerator.new()
## customRandom's two LCGs (rng.c): CUSTOM_RNG_VAL1 starts at 0 (bss), VAL2 at 0x13cc25.
static var _custom1 := 0
static var _custom2 := 0x13CC25


static func set_seed(value: int) -> void:
	_rng.seed = value
	_custom1 = 0
	_custom2 = 0x13CC25


## rand() (PSY-Q libc): 0..0x7FFF.
static func rand() -> int:
	return _rng.randi_range(0, RAND_MAX)


## randomLimit (math.c:5): (limit * rand()) >> 15, so 0..limit - 1.
static func random_limit(limit: int) -> int:
	return (limit * rand()) >> 15


## customRandom (rng.c:13): min..max inclusive, from its own two LCGs (not rand()).
static func custom_random(min_value: int, max_value: int) -> int:
	if max_value == min_value:
		return min_value
	if max_value < min_value:
		var t := min_value
		min_value = max_value
		max_value = t
	_custom1 = (_custom1 * 0x41C650AD + 0x3039) & 0xFFFFFFFF
	_custom2 = (_custom2 * 0x41C650AD + 0x3039) & 0xFFFFFFFF
	# C: (uint32) % (uint32)(max - min + 1): the remainder is taken unsigned.
	var mixed := ((_custom1 >> 16) | (_custom2 << 16)) & 0xFFFFFFFF
	return min_value + mixed % (max_value - min_value + 1)
