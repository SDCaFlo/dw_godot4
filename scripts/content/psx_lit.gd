class_name PsxLit
## The field lighting of the lit PSX polygons (specs/lighting.md): the GTE lights each vertex with
## the map's 3 lights and the ambient (GsSetFlatLight, GsSetAmbient), the colour is interpolated,
## and the GPU multiplies the texel by it (128 = 1.0), clamped per channel. The lights are global
## shader parameters (project.godot [shader_globals]), set by FieldLighting.

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
uniform float alpha_cutoff = 0.5;

varying vec3 intensity;

// `dir` is the direction the light travels: a surface facing against it is lit.
vec3 lit(vec3 n, vec3 dir, vec3 color) {
	return color * max(0.0, dot(n, -dir));
}

void vertex() {
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	intensity = psx_ambient + lit(n, psx_light_0_dir, psx_light_0_color)
			+ lit(n, psx_light_1_dir, psx_light_1_color) + lit(n, psx_light_2_dir, psx_light_2_color);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec4 texel = use_texture ? texture(albedo_texture, UV) : vec4(1.0);
	// COLOR: the vertex colour as the porter wrote it (white when the mesh has none).
	ALBEDO = srgb_to_linear(clamp(texel.rgb * COLOR.rgb * intensity, 0.0, 1.0));
	%s
}
"""

static var _shaders := {}


## A lit material for a glTF material's texture and modes: BLEND (semi-transparent) blends the
## texel's alpha, otherwise texels below alpha_cutoff are discarded (MASK).
static func material(texture: Texture2D, blend: bool, double_sided: bool, alpha_cutoff := 0.5) -> ShaderMaterial:
	var key := Vector2i(int(blend), int(double_sided))
	if not _shaders.has(key):
		var modes := ""
		if blend:
			modes += ", blend_mix, depth_draw_opaque"
		if double_sided:
			modes += ", cull_disabled"
		var alpha := "ALPHA = texel.a;" if blend else "if (texel.a < alpha_cutoff) {\n\t\tdiscard;\n\t}"
		var shader := Shader.new()
		shader.code = _CODE % [modes, alpha]
		_shaders[key] = shader
	var m := ShaderMaterial.new()
	m.shader = _shaders[key]
	m.set_shader_parameter("albedo_texture", texture)
	m.set_shader_parameter("use_texture", texture != null)
	m.set_shader_parameter("alpha_cutoff", alpha_cutoff)
	return m
