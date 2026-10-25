class_name PsxLit
## The PSX look of a TMD polygon's material (specs/lighting.md):
## - the field lighting of the lit polygons: the GTE lights each vertex with the map's 3 lights and
##   the ambient (GsSetFlatLight, GsSetAmbient), the colour is interpolated, and the GPU multiplies
##   the texel by it (128 = 1.0), clamped per channel. The lights are global shader parameters
##   (project.godot [shader_globals]), set by FieldLighting;
## - semi-transparency: a semi-transparent polygon blends only the texels whose colour has the STP
##   bit, with its tpage's abr mode (0 half / half, 1 add, 2 subtract, 3 add a quarter); the other
##   texels are opaque (asset_porter/specs/tmd.md "STP masks"). One pass each.

## The tpage's semi-transparency modes (abr).
const HALF := 0
const ADD := 1
const SUBTRACT := 2
const ADD_QUARTER := 3

const _CODE := """shader_type spatial;
render_mode unshaded%s;

global uniform vec3 psx_ambient;
global uniform vec3 psx_light_0_dir;
global uniform vec3 psx_light_0_color;
global uniform vec3 psx_light_1_dir;
global uniform vec3 psx_light_1_color;
global uniform vec3 psx_light_2_dir;
global uniform vec3 psx_light_2_color;

// The texel's sRGB values: the PSX multiplies its 5-bit colours, so the maths stays there.
uniform sampler2D albedo_texture : filter_nearest;
uniform bool use_texture = true;
uniform bool lit = true;
uniform float alpha_cutoff = 0.5;
// The STP mask (255 = bit set); the opaque pass skips those texels, the blended pass draws only them.
uniform sampler2D stp_texture : filter_nearest;
uniform bool use_stp = false;
uniform bool blended_pass = false;
uniform float alpha_scale = 1.0;
uniform float color_scale = 1.0;
// A model lit by its own light instead of the map's 3 (the Digimon / Player screens' model,
// renderDigiviceEntity: one light, the ambient kept).
uniform bool own_light = false;
uniform vec3 own_light_dir;
uniform vec3 own_light_color;

varying vec3 intensity;

// `dir` is the direction the light travels: a surface facing against it is lit.
vec3 shine(vec3 n, vec3 dir, vec3 color) {
	return color * max(0.0, dot(n, -dir));
}

void vertex() {
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (own_light) {
		intensity = lit ? psx_ambient + shine(n, own_light_dir, own_light_color) : vec3(1.0);
	} else {
		intensity = lit ? psx_ambient + shine(n, psx_light_0_dir, psx_light_0_color)
				+ shine(n, psx_light_1_dir, psx_light_1_color) + shine(n, psx_light_2_dir, psx_light_2_color) : vec3(1.0);
	}
}

// The GPU's texel: floor of the interpolated texel coordinate. The porter's UVs are texel / 256,
// on a texel's edge: a polygon whose UVs sit on one texel column (a strip mapped onto a face)
// would flip between two texels per pixel by rounding (ISSUES.md I-6). A nudge of 1 / 1024 texel
// keeps it on the PSX's texel.
vec2 psx_uv(sampler2D tex, vec2 uv) {
	vec2 size = vec2(textureSize(tex, 0));
	return (floor(uv * size + 1.0 / 1024.0) + 0.5) / size;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec2 uv = use_texture ? psx_uv(albedo_texture, UV) : UV;
	vec4 texel = use_texture ? texture(albedo_texture, uv) : vec4(1.0);
	bool semi = use_stp && texture(stp_texture, uv).r > 0.5;
	if (texel.a < alpha_cutoff || semi != blended_pass) {
		discard;
	}
	// COLOR: the vertex colour as the porter wrote it (white when the mesh has none).
	ALBEDO = srgb_to_linear(clamp(texel.rgb * COLOR.rgb * intensity, 0.0, 1.0)) * color_scale;
	%s
}
"""

static var _shaders := {}


## The material for a glTF material's texture and modes. `abr` -1: not semi-transparent (or no STP
## mask: every texel opaque). `lit` false: the texel as is (an unlit semi-transparent polygon).
static func material(texture: Texture2D, double_sided: bool, alpha_cutoff := 0.5, abr := -1,
		stp_texture: Texture2D = null, lit := true) -> ShaderMaterial:
	var semi := abr >= 0 and stp_texture != null
	var base := _pass("", double_sided, texture, alpha_cutoff, lit)
	if not semi:
		return base
	base.set_shader_parameter("use_stp", true)
	base.set_shader_parameter("stp_texture", stp_texture)
	var blend: String = ["blend_mix", "blend_add", "blend_sub", "blend_add"][abr & 3]
	var blended := _pass(blend, double_sided, texture, alpha_cutoff, lit)
	blended.set_shader_parameter("use_stp", true)
	blended.set_shader_parameter("stp_texture", stp_texture)
	blended.set_shader_parameter("blended_pass", true)
	blended.set_shader_parameter("alpha_scale", 0.5 if (abr & 3) == HALF else 1.0)
	blended.set_shader_parameter("color_scale", 0.25 if (abr & 3) == ADD_QUARTER else 1.0)
	base.next_pass = blended
	return base


## Lights a loaded model with its own light instead of the map's (`dir` the Godot direction the
## light travels, `color` 0-1, like FieldLighting's): copies of its PsxLit materials, every pass.
static func use_own_light(model: Node, dir: Vector3, color: Vector3) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.get_surface_override_material_count():
			var source := mesh_instance.get_active_material(i)
			if not source is ShaderMaterial:
				continue
			var copy := (source as ShaderMaterial).duplicate(true) as ShaderMaterial
			var pass_material: Material = copy
			while pass_material is ShaderMaterial:
				pass_material.set_shader_parameter("own_light", true)
				pass_material.set_shader_parameter("own_light_dir", dir)
				pass_material.set_shader_parameter("own_light_color", color)
				pass_material = pass_material.next_pass
			mesh_instance.set_surface_override_material(i, copy)


## One pass: opaque (`blend` "") or blended in a semi-transparency mode.
static func _pass(blend: String, double_sided: bool, texture: Texture2D, alpha_cutoff: float, lit: bool) -> ShaderMaterial:
	var key := "%s %s" % [blend, double_sided]
	if not _shaders.has(key):
		var modes := ""
		if blend != "":
			modes += ", %s, depth_draw_never" % blend
		if double_sided:
			modes += ", cull_disabled"
		var shader := Shader.new()
		shader.code = _CODE % [modes, "ALPHA = alpha_scale;" if blend != "" else ""]
		_shaders[key] = shader
	var m := ShaderMaterial.new()
	m.shader = _shaders[key]
	m.set_shader_parameter("albedo_texture", texture)
	m.set_shader_parameter("use_texture", texture != null)
	m.set_shader_parameter("alpha_cutoff", alpha_cutoff)
	m.set_shader_parameter("lit", lit)
	return m
