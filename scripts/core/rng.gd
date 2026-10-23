class_name Rng
## Random numbers like the original's helpers, on one Godot generator. The PSX rand() sequence is
## not reproduced (its seed differs per run anyway); set_seed() makes runs repeatable in tests.

## rand() range: 0..0x7FFF.
const RAND_MAX := 0x7FFF

static var _rng := RandomNumberGenerator.new()


static func set_seed(value: int) -> void:
	_rng.seed = value


## rand() (PSY-Q libc): 0..0x7FFF.
static func rand() -> int:
	return _rng.randi_range(0, RAND_MAX)


## randomLimit (math.c:5): (limit * rand()) >> 15, so 0..limit - 1.
static func random_limit(limit: int) -> int:
	return (limit * rand()) >> 15
