// A battle effect sprite in the 3D world (WorldSprites, specs/battle_effects.md §7.2). The
// variants next to this file: opaque, or blended (PSX_BLENDED: the PSX's blend in gamma values).
#include "res://shaders/common/psx_color.gdshaderinc"
#ifdef PSX_BLENDED
#include "res://shaders/common/psx_gamma_blend.gdshaderinc"
#endif

// The texel's sRGB values, as PsxLit.
uniform sampler2D sprite_texture : filter_nearest;
// The texels drawn (x, y, w, h; a negative size mirrors) and the colour (1.0 = 128); the vertex
// colours (a gouraud polygon's, 1.0 = 128) multiply it.
instance uniform vec4 region;
instance uniform vec4 tint;

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
#ifdef PSX_BLENDED
	ALBEDO = psx_gamma_blend(front, SCREEN_UV);
#else
	ALBEDO = srgb_to_linear(front);
#endif
}
