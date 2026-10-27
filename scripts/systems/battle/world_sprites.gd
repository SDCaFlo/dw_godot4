class_name WorldSprites
extends Node3D
## Sprites in the 3D world for the battle effects (specs/battle_effects.md §7.2): camera-facing
## quads, depth-tested against the models, so an effect behind a Digimon is hidden by it as in the
## PSX's ordering table. Each frame the owner calls begin(), one sprite() per sprite the C draws
## that frame, then end(); the quads are pooled.
##
## A sprite is a region of a PsxTexture: its texels without the STP bit draw opaque, its STP texels
## with the PSX blend mode (abr 0 half, 1 add, 2 subtract, 3 add a quarter), or opaque too when the
## sprite isn't semi-transparent (abr -1). Sizes are world units (PSX units): the C's screen size
## at a depth is `world · H / depth`, so a size worked out as the C's pixels times depth / H shows
## at the C's size.

const _CODE := """shader_type spatial;
render_mode unshaded, cull_disabled%s;

// The texel's sRGB values, as PsxLit.
uniform sampler2D sprite_texture : filter_nearest;
%s
// The texels drawn (x, y, w, h; a negative size mirrors) and the colour (1.0 = 128); the vertex
// colours (a gouraud polygon's, 1.0 = 128) multiply it.
instance uniform vec4 region;
instance uniform vec4 tint;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec2 size = vec2(textureSize(sprite_texture, 0));
	vec2 t = floor(region.xy + UV * region.zw + 1.0 / 1024.0);
	if (t.x < 0.0 || t.y < 0.0 || t.x >= size.x || t.y >= size.y) {
		discard;
	}
	vec4 texel = texture(sprite_texture, (t + 0.5) / size);
	if (texel.a < 0.5) {
		discard;
	}
	vec3 front = clamp(texel.rgb * tint.rgb * COLOR.rgb, 0.0, 1.0);
	%s
}
"""

static var _shaders := {}
static var _solids := {}

var _quad: QuadMesh
var _pool: Array[MeshInstance3D] = []
var _used := 0
## The free-form quads (quad()): their own meshes.
var _quads: Array[MeshInstance3D] = []
var _quads_used := 0
## This frame's lines by blend mode (-1 opaque, 0-3 the abr): [a, b, colour] each.
var _lines := {}
var _line_mesh: ImmediateMesh
var _line_node: MeshInstance3D
static var _line_materials := {}
var _materials := {}
## The camera the quads face (the viewport's), found at begin().
var _camera: Camera3D


func _init() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE


func begin() -> void:
	_used = 0
	_quads_used = 0
	_lines.clear()
	_camera = get_viewport().get_camera_3d() if is_inside_tree() else null


## One sprite: `texture`'s `region` (texels; a negative width or height mirrors it), centred on
## `at` (Godot world) moved by `offset` (world units, screen right / down), `size` world units,
## turned `angle` radians clockwise on screen, tinted (1.0 = 128).
func sprite(texture: PsxTexture, abr: int, at: Vector3, size: Vector2, region: Rect2, tint := Color.WHITE,
		offset := Vector2.ZERO, angle := 0.0) -> void:
	if _camera == null or texture == null or size.x == 0.0 or size.y == 0.0:
		return
	var quad := _take()
	quad.material_override = _material(texture, abr)
	var view := _camera.global_basis
	var spin := Basis(Vector3.BACK, -angle)
	var basis := view * spin * Basis.from_scale(Vector3(size.x, size.y, 1.0))
	quad.global_transform = Transform3D(basis, at + view * (spin * Vector3(offset.x, -offset.y, 0.0)))
	quad.set_instance_shader_parameter("region", Vector4(region.position.x, region.position.y, region.size.x,
			region.size.y))
	quad.set_instance_shader_parameter("tint", tint)
	quad.visible = true


## A quad with free corners (Godot world; top-left, top-right, bottom-left, bottom-right): a
## POLY_FT4 / POLY_F4 / POLY_GT4. Its texels are `region`, or with `uvs` (4 texel positions, one per
## corner) any four; `colors` are a gouraud polygon's corner colours (1.0 = 128).
func quad(texture: PsxTexture, abr: int, corners: Array, region: Rect2, tint := Color.WHITE, uvs := [],
		colors := []) -> void:
	if texture == null or corners.size() != 4:
		return
	if _quads_used == _quads.size():
		var node := MeshInstance3D.new()
		node.mesh = ArrayMesh.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_quads.append(node)
	var node := _quads[_quads_used]
	_quads_used += 1
	var mesh := node.mesh as ArrayMesh
	mesh.clear_surfaces()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([corners[0], corners[1], corners[2], corners[1], corners[3], corners[2]])
	var uv: Array = uvs if uvs.size() == 4 else [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	if uvs.size() == 4:
		region = Rect2(0, 0, 1, 1)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([uv[0], uv[1], uv[2], uv[1], uv[3], uv[2]])
	if colors.size() == 4:
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([colors[0], colors[1], colors[2], colors[1], colors[3], colors[2]])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.material_override = _material(texture, abr)
	node.global_transform = Transform3D.IDENTITY
	node.set_instance_shader_parameter("region", Vector4(region.position.x, region.position.y, region.size.x,
			region.size.y))
	node.set_instance_shader_parameter("tint", tint)
	node.visible = true


## A one-pixel line (LINE_F2) between two Godot points, in a blend mode (-1 opaque, 0-3 the abr).
func line(a: Vector3, b: Vector3, color: Color, abr := -1) -> void:
	if not _lines.has(abr):
		_lines[abr] = []
	_lines[abr].append([a, b, color])


func end() -> void:
	for i in range(_used, _pool.size()):
		_pool[i].visible = false
	for i in range(_quads_used, _quads.size()):
		_quads[i].visible = false
	_end_lines()


func _end_lines() -> void:
	if _line_mesh == null:
		_line_mesh = ImmediateMesh.new()
		_line_node = MeshInstance3D.new()
		_line_node.mesh = _line_mesh
		_line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_line_node)
	_line_mesh.clear_surfaces()
	for abr in _lines:
		_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material(abr))
		for l in _lines[abr]:
			_line_mesh.surface_set_color(l[2])
			_line_mesh.surface_add_vertex(l[0])
			_line_mesh.surface_set_color(l[2])
			_line_mesh.surface_add_vertex(l[1])
		_line_mesh.surface_end()
	_line_node.global_transform = Transform3D.IDENTITY


## The lines' material of a blend mode: the vertex colour (sRGB, 1.0 = 255), blended as the abr.
static func _line_material(abr: int) -> Material:
	if not _line_materials.has(abr):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		match abr:
			PsxLit.HALF:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color = Color(1, 1, 1, 0.5)
			PsxLit.ADD:
				m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			PsxLit.SUBTRACT:
				m.blend_mode = BaseMaterial3D.BLEND_MODE_SUB
			PsxLit.ADD_QUARTER:
				m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				m.albedo_color = Color(0.25, 0.25, 0.25)
		_line_materials[abr] = m
	return _line_materials[abr]


## The sprites, quads and lines this frame shows.
func used() -> int:
	var lines := 0
	for abr in _lines:
		lines += _lines[abr].size()
	return _used + _quads_used + lines


## A flat colour for the untextured polygons (POLY_F4): one white texel, opaque, or with the STP
## bit when the polygon is semi-transparent (an untextured polygon blends all of it).
static func solid(semi: bool) -> PsxTexture:
	var key := 1 if semi else 0
	if not _solids.has(key):
		var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		white.set_pixel(0, 0, Color.WHITE)
		var empty := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		var t := PsxTexture.new()
		t.base = ImageTexture.create_from_image(empty if semi else white)
		t.stp = ImageTexture.create_from_image(white if semi else empty)
		_solids[key] = t
	return _solids[key]


func _take() -> MeshInstance3D:
	if _used == _pool.size():
		var quad := MeshInstance3D.new()
		quad.mesh = _quad
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quad)
		_pool.append(quad)
	_used += 1
	return _pool[_used - 1]


## The two passes of a texture and mode: the base texels opaque, then the STP texels blended (or
## opaque when not semi-transparent).
func _material(texture: PsxTexture, abr: int) -> Material:
	var key := "%d %d" % [texture.get_instance_id(), abr]
	if not _materials.has(key):
		var base := _pass("", texture.base)
		var stp: ShaderMaterial
		if abr < 0:
			stp = _pass("", texture.stp)
		else:
			# The PSX's blend in its gamma values (PsxLit.GAMMA_BLEND; ISSUES.md I-30).
			stp = _pass("blend_add", texture.stp)
			stp.set_shader_parameter("abr", abr & 3)
		base.next_pass = stp
		_materials[key] = base
	return _materials[key]


static func _pass(blend: String, texture: Texture2D) -> ShaderMaterial:
	if not _shaders.has(blend):
		var shader := Shader.new()
		shader.code = _CODE % [", %s, depth_draw_never" % blend if blend != "" else "",
				PsxLit.GAMMA_BLEND_UNIFORMS if blend != "" else "",
				PsxLit.GAMMA_BLEND if blend != "" else "ALBEDO = srgb_to_linear(front);"]
		_shaders[blend] = shader
	var m := ShaderMaterial.new()
	m.shader = _shaders[blend]
	m.set_shader_parameter("sprite_texture", texture)
	return m
