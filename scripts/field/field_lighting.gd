class_name FieldLighting
## The field's lights (specs/lighting.md): the map's 3 directional lights (loadMapSetup,
## map.c:4143) scaled by the time of day (updateTimeOfDay, map.c:4301; tickDaytimeTransition at
## the end of its fade, map.c:4560), and the fixed ambient, as the global shader parameters of
## PsxLit.

## GsSetAmbient(0x800, 0x800, 0x800): 0.5 on every map.
const AMBIENT := Vector3(0.5, 0.5, 0.5)
## FieldMap.time_of_day: the palette shown (0 day, 1 evening, 2 night).
const DAY := 0
const EVENING := 1
const NIGHT := 2
const LIGHTS := 3

## The global parameters last set, by name (the headless renderer can't read them back).
static var current := {}


## The lights of a map (map.json setup.lights: direction, colour 0-255) at a time of day: per light
## {dir: Godot direction the light travels, color: 0-1}. Evening: green and blue x 7 / 10, night:
## x 5 / 10, with the C's integer maths; the light colour matrix holds colour x 16 (4096 = 1.0).
static func lights_at(lights: Array, time_of_day: int) -> Array:
	var out := []
	for i in LIGHTS:
		var light: Dictionary = lights[i] if i < lights.size() else {}
		var d: Array = light.get("direction", [0, 0, 0])
		var c: Array = light.get("color", [0, 0, 0])
		var rgb := Vector3i(int(c[0]), int(c[1]), int(c[2]))
		match time_of_day:
			EVENING:
				rgb = Vector3i(rgb.x, rgb.y * 7 / 10, rgb.z * 7 / 10)
			NIGHT:
				rgb = Vector3i(rgb.x * 5 / 10, rgb.y * 5 / 10, rgb.z * 5 / 10)
		var dir := Content.psx_to_godot(d)
		out.append({"dir": dir.normalized() if dir != Vector3.ZERO else Vector3.ZERO,
				"color": Vector3(rgb) * 16.0 / 4096.0})
	return out


## Sets the global shader parameters (GsSetFlatLight for each light, GsSetAmbient).
static func apply(lights: Array, time_of_day: int) -> void:
	var at := lights_at(lights, time_of_day)
	_set_global("psx_ambient", AMBIENT)
	for i in LIGHTS:
		_set_global("psx_light_%d_dir" % i, at[i]["dir"])
		_set_global("psx_light_%d_color" % i, at[i]["color"])


static func _set_global(name: String, value: Vector3) -> void:
	RenderingServer.global_shader_parameter_set(name, value)
	current[name] = value
