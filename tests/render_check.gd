extends SceneTree
## Renders a map as the field scene composes it (not headless:
##   godot --path . -s res://tests/render_check.gd -- [MAP] [SCROLL_X SCROLL_Y [FRAMES [PALETTE [FEET_X FEET_Y [MODEL]]]]]):
## a SubViewport whose environment draws the background canvas layer behind the 3D (field.tscn,
## specs/map_objects.md §3). Two frames: without the overlay sprites the screen must be the
## background PNG exactly (the canvas background reaches the screen unchanged); with them, the
## frame is saved to user://render_check_<MAP>.png to look at. Exits 1 if the first differs.
## FEET_X / Y: a model (MODEL, the porter path; Agumon by default) stands on the ground (PSX y 0) whose background pixel that is, in both frames:
## to look at the draw order against the sprites (ISSUES.md I-1).

var _viewport: SubViewport
var _map: FieldMap
var _frames := 0
var _plain: Image
var _map_name := ""
var _scroll := Vector2.ZERO
var _feet := Vector2(-1, -1)
var _model := "mmd_files/MMD0/AGUM.gltf"
## The frame the shot with the overlays is taken (they animate 20 a second).
var _shot_frame := 20
## Env RC_SCALE: the 3D render scale (as the field's, ISSUES.md I-3); above 1 the frame is only
## saved, not compared.
var _scale := maxi(1, int(OS.get_environment("RC_SCALE")))


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var map_name := args[0] if args.size() > 0 else "MAYO01"
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(320, 240) * _scale
	FieldMap.render_scale = _scale
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var layer := CanvasLayer.new()
	layer.layer = -1
	layer.scale = Vector2.ONE * _scale
	_viewport.add_child(layer)
	var bg := Sprite2D.new()
	bg.centered = false
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(bg)
	var env := WorldEnvironment.new()
	# As field.tscn's: the canvas layers up to -1 are the 3D's background.
	env.environment = _environment()
	_viewport.add_child(env)
	_map = FieldMap.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	_map.add_child(camera)
	var doors := Node3D.new()
	doors.name = "Doors"
	_map.add_child(doors)
	_map.background = bg
	_viewport.add_child(_map)
	_map_name = map_name
	_scroll = Vector2(int(args[1]), int(args[2])) if args.size() > 2 else Vector2(-1, -1)
	if args.size() > 3:
		_shot_frame = maxi(int(args[3]), 11)
	# The time-of-day palette (0 day, 1 evening, 2 night): its transparent texels must show black.
	if args.size() > 4:
		_map.time_of_day = int(args[4])
	if args.size() > 6:
		_feet = Vector2(int(args[5]), int(args[6]))
	if args.size() > 7:
		_model = args[7]


func _environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.background_canvas_max_layer = -1
	return e


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		# The map once the nodes are ready (FieldMap's @onready camera and doors).
		_map.load_map(_map_name)
		if _scroll.x >= 0:
			_map.scroll = _scroll
			_map.call("_clamp_scroll")
			_map.call("_apply_scroll")
		_map.overlays.visible = false
		if _feet.x >= 0:
			_place_model()
		return false
	if _frames == 10:
		_plain = _capture()
		_map.overlays.visible = true
	# A game frame of the overlays per rendered frame (no GameLoop here).
	_map.overlays.tick()
	if _frames < _shot_frame:
		return false
	var shot := _capture()
	var path := "user://render_check_%s.png" % _map.map_name
	shot.save_png(path)
	if _scale > 1:
		print("render_check %s at %dx: saved %s" % [_map.map_name, _scale, ProjectSettings.globalize_path(path)])
		quit(0)
		return true
	var bg: Image = _map.background.texture.get_image()
	bg.convert(Image.FORMAT_RGBA8)
	var off := Vector2i(_map.scroll)
	var differ := 0
	var total := 0
	var worst := 0
	var covered := 0
	var holes := 0
	for y in _plain.get_height():
		for x in _plain.get_width():
			var p := Vector2i(x, y) + off
			if p.x >= bg.get_width() or p.y >= bg.get_height():
				continue
			var b := bg.get_pixel(p.x, p.y)
			var a := _plain.get_pixel(x, y)
			if b.a8 == 0:
				# Colour 0x0000 isn't drawn: the frame's black clear shows (GsSortClear, main.c:3960).
				holes += 1
				b = Color.BLACK
			var d := maxi(maxi(absi(a.r8 - b.r8), absi(a.g8 - b.g8)), absi(a.b8 - b.b8))
			total += 1
			if d > 0:
				differ += 1
				worst = maxi(worst, d)
			if shot.get_pixel(x, y) != a:
				covered += 1
	print("render_check %s: background %d / %d pixels differ (largest %d; %d transparent texels on screen, black on the PSX); the overlays change %d pixels; saved %s"
			% [_map.map_name, differ, total, worst, holes, covered, ProjectSettings.globalize_path(path)])
	# With Agumon on screen the first frame shows him too: only the plain check fails.
	quit(1 if differ > 0 and _feet.x < 0 else 0)
	return true


## Agumon on the ground point under background pixel _feet: the ray through it meets PSX y 0.
func _place_model() -> void:
	var a := _map.world_at_pixel(_feet, 1000.0)
	var b := _map.world_at_pixel(_feet, 2000.0)
	var ground := a + (b - a) * (-a.y / (b.y - a.y))
	var model := Content.load_model(_model)
	_map.add_child(model)
	if OS.get_environment("RC_TINT") != "":
		# Diagnostic: each surface a flat colour of its own (which surface shows where).
		var k := 0
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			for i in (mesh as MeshInstance3D).mesh.get_surface_count():
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.albedo_color = Color.from_hsv(fmod(k * 0.27, 1.0), 0.9, 0.9)
				(mesh as MeshInstance3D).set_surface_override_material(i, m)
				print("  surface %d: %s %s" % [k, mesh.name, m.albedo_color.to_html(false)])
				k += 1
	model.position = ground
	var inst := _map.overlays.instance(0)
	var node: MeshInstance3D = inst["node"]
	print("  sprite 0: order %d, quad at %s (depth %d, pixel %s), size %s, visible %s, in tree %s, material %s" % [inst["order"],
			node.global_position, _map.view_depth(node.global_position), _map.background_pixel(node.global_position).round(),
			(node.mesh as QuadMesh).size, node.visible, node.is_inside_tree(), node.material_override])
	print("  Agumon at %s, view depth %d, feet on pixel %s" % [ground, _map.view_depth(ground), _map.background_pixel(ground).round()])


func _capture() -> Image:
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image
