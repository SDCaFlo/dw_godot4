class_name DeathIrisMath
## The iris of the death scenes (specs/death_scene.md §3 K): its radius (MURD_isDigimonLargerThanIris
## murd.c:374, MURD_renderIris murd.c:578, DOOA_hasIrisClosed dooa.c:620) and whether the partner is
## drawn in front of it (K3).


## `(lerp(200, 0, start, end, t) << 12) / 128`; DOOA clamps t to the end (dooa.c:614).
static func radius(start: int, end: int, t: int, clamp_end: bool) -> int:
	if clamp_end and t > end:
		t = end
	return (PsxMath.lerp_int(200, 0, start, end, t) << 12) / 128


## In front once the iris is smaller than the partner's projected size: `size` =
## getDistance(2r, h, 2r) of its record, `h` VIEWPORT_DISTANCE, `z` the depth of its middle.
static func in_front(r: int, size: int, h: int, z: int) -> bool:
	if z <= 0:
		return true
	var projected := (size * h) / z
	return r <= (projected << 12) / 256


## getDistance(2 × radius, height, 2 × radius) of a Digimon record.
static func size(record: Dictionary) -> int:
	var r := int(record.get("radius", 0))
	return PsxMath.get_distance(r * 2, int(record.get("height", 0)), r * 2)
