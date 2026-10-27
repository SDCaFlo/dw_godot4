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
uniform float alpha_scale = 1.0;
uniform float color_scale = 1.0;
// The texels drawn (x, y, w, h; a negative size mirrors) and the colour (1.0 = 128).
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
	ALBEDO = srgb_to_linear(clamp(texel.rgb * tint.rgb, 0.0, 1.0)) * color_scale;
	%s
}
"""

static var _shaders := {}

var _quad: QuadMesh
var _pool: Array[MeshInstance3D] = []
var _used := 0
var _materials := {}
## The camera the quads face (the viewport's), found at begin().
var _camera: Camera3D


func _init() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE


func begin() -> void:
	_used = 0
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


func end() -> void:
	for i in range(_used, _pool.size()):
		_pool[i].visible = false


func used() -> int:
	return _used


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
			stp = _pass(["blend_mix", "blend_add", "blend_sub", "blend_add"][abr & 3], texture.stp)
			stp.set_shader_parameter("alpha_scale", 0.5 if (abr & 3) == PsxLit.HALF else 1.0)
			stp.set_shader_parameter("color_scale", 0.25 if (abr & 3) == PsxLit.ADD_QUARTER else 1.0)
		base.next_pass = stp
		_materials[key] = base
	return _materials[key]


static func _pass(blend: String, texture: Texture2D) -> ShaderMaterial:
	if not _shaders.has(blend):
		var shader := Shader.new()
		shader.code = _CODE % [", %s, depth_draw_never" % blend if blend != "" else "",
				"ALPHA = alpha_scale;" if blend != "" else ""]
		_shaders[blend] = shader
	var m := ShaderMaterial.new()
	m.shader = _shaders[blend]
	m.set_shader_parameter("sprite_texture", texture)
	return m
