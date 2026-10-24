extends SceneTree
## The field lighting (scripts/field/field_lighting.gd, scripts/content/psx_lit.gd) against
## specs/lighting.md, on the porter output:
##   godot --headless --path . -s res://tests/test_lighting.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	if not Content.exists("maps/MAYO01/map.json"):
		print("SKIP: porter output missing")
		quit(0)
		return false
	_time_of_day()
	_field_map()
	_materials()
	print("%s: lighting checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


# --- §2.1: the lights by the time of day ---------------------------------------------------------

func _time_of_day() -> void:
	var lights := [{"direction": [0, 170, -30], "color": [178, 178, 178]},
			{"direction": [1, 1, 1], "color": [0, 0, 0]}, {"direction": [1, 1, 1], "color": [0, 0, 0]}]
	var day := FieldLighting.lights_at(lights, FieldLighting.DAY)
	_eq(day[0]["color"], Vector3(178, 178, 178) * 16.0 / 4096.0, "day: the map's colour x 16 / 4096")
	_eq((day[0]["dir"] - Vector3(0, -170, 30).normalized()).length() < 0.0001, true,
			"the direction in Godot axes, normalised: (0, 170, -30) points down")
	_eq(FieldLighting.lights_at(lights, FieldLighting.EVENING)[0]["color"], Vector3(178, 124, 124) * 16.0 / 4096.0,
			"evening: green and blue x 7 / 10 (integer: 124), red unchanged")
	_eq(FieldLighting.lights_at(lights, FieldLighting.NIGHT)[0]["color"], Vector3(89, 89, 89) * 16.0 / 4096.0,
			"night: x 5 / 10 (89)")
	_eq(FieldLighting.lights_at([], FieldLighting.DAY).size(), 3, "always 3 lights (black when missing)")


# --- §3: FieldMap sets the globals ---------------------------------------------------------------

func _global(name: String) -> Variant:
	return FieldLighting.current.get(name)


func _field_map() -> void:
	var map := FieldMap.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	map.add_child(camera)
	var doors := Node3D.new()
	doors.name = "Doors"
	map.add_child(doors)
	map.background = Sprite2D.new()
	root.add_child(map.background)
	root.add_child(map)
	map.load_map("MAYO01")
	_eq([_global("psx_ambient"), _global("psx_light_0_color")], [Vector3(0.5, 0.5, 0.5), Vector3(178, 178, 178) / 256.0],
			"MAYO01 by day: ambient 0.5, light 0 at 178")
	map.set_time_of_day(FieldLighting.NIGHT)
	_eq(_global("psx_light_0_color"), Vector3(89, 89, 89) / 256.0, "at night the light halves; the ambient stays")
	map.set_time_of_day(FieldLighting.DAY)
	_eq(_global("psx_light_0_color"), Vector3(178, 178, 178) / 256.0, "back to day")
	map.queue_free()
	map.background.queue_free()


# --- §3: the materials ---------------------------------------------------------------------------

func _surfaces(model: Node) -> Array:
	var out := []
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		for i in (mesh as MeshInstance3D).mesh.get_surface_count():
			out.append((mesh as MeshInstance3D).get_surface_override_material(i))
	return out


func _materials() -> void:
	var agumon := Content.load_model("mmd_files/MMD0/AGUM.gltf")
	var mats := _surfaces(agumon)
	_eq(mats.all(func(m): return m is ShaderMaterial and (m as ShaderMaterial).shader.code.contains("psx_light_0_dir")),
			true, "Agumon's lit materials take the field lighting (PsxLit)")
	_eq((mats[0] as ShaderMaterial).get_shader_parameter("albedo_texture") != null, true, "with their texture")
	agumon.free()
	# HYOG has one unlit material (KHR_materials_unlit) among its 11.
	var hyog := Content.load_model("mmd_files/MMD2/HYOG.gltf")
	var kinds := {"lit": 0, "unlit": 0}
	for m in _surfaces(hyog):
		if m is ShaderMaterial:
			kinds["lit"] += 1
		elif m is BaseMaterial3D and (m as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			kinds["unlit"] += 1
	_eq(kinds["unlit"] >= 1 and kinds["lit"] >= 1, true, "an unlit material stays unshaded, the others are lit: %s" % kinds)
	hyog.free()
	# ISSUES.md I-5: the poop (ETCNA/UNTI): its body has no STP texels (opaque); its shadow disc has
	# them all, drawn subtractively (abr 2) in a blended pass.
	var poop := Content.load_model("tmd_files/ETCNA/UNTI.gltf")
	var passes := []
	for m in _surfaces(poop):
		var next: ShaderMaterial = (m as ShaderMaterial).next_pass
		passes.append("sub" if next != null and next.shader.code.contains("blend_sub") else ("other" if next != null else "opaque"))
	passes.sort()
	_eq(passes, ["opaque", "sub"], "the poop: an opaque body, a shadow with a subtractive pass on its STP texels")
	poop.free()


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])
