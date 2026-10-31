// The PSX look of a TMD polygon (PsxLit, specs/lighting.md). The variants next to this file set
// the render mode: opaque or blended (PSX_BLENDED: the STP texels with the PSX's blend), culled or
// double-sided.
#include "res://shaders/common/psx_color.gdshaderinc"
#ifdef PSX_BLENDED
#include "res://shaders/common/psx_gamma_blend.gdshaderinc"
#endif

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
// A model lit by its own light instead of the map's 3 (the Digimon / Player screens' model,
// renderDigiviceEntity: one light, the ambient kept).
uniform bool own_light = false;
uniform vec3 own_light_dir;
uniform vec3 own_light_color;
// The effects' UV animation (texels, added per vertex mod 256) and object colour (1.0 = 128).
uniform vec2 uv_offset = vec2(0.0);
uniform vec3 tint = vec3(1.0);

varying vec3 intensity;

// `dir` is the direction the light travels: a surface facing against it is lit.
vec3 shine(vec3 n, vec3 dir, vec3 color) {
	return color * max(0.0, dot(n, -dir));
}

void vertex() {
	if (uv_offset != vec2(0.0)) {
		UV = mod(floor(UV * 256.0 + 0.5) + uv_offset, 256.0) / 256.0;
	}
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

void fragment() {
	vec2 uv = use_texture ? psx_uv(albedo_texture, UV) : UV;
	vec4 texel = use_texture ? texture(albedo_texture, uv) : vec4(1.0);
	bool semi = use_stp && texture(stp_texture, uv).r > 0.5;
	if (texel.a < alpha_cutoff || semi != blended_pass) {
		discard;
	}
	// COLOR: the vertex colour as the porter wrote it (white when the mesh has none).
	vec3 front = clamp(texel.rgb * COLOR.rgb * intensity * tint, 0.0, 1.0);
#ifdef PSX_BLENDED
	ALBEDO = psx_gamma_blend(front, SCREEN_UV);
#else
	ALBEDO = srgb_to_linear(front);
#endif
}
