// The PSX's semi-transparency blend in its gamma values (PsxLit, ISSUES.md I-30). Godot's 3D
// blends in linear light, where an added texel brightens a lit background far less and a halved
// one darkens it more. So a blended pass does the PSX's sum itself: the screen behind it (the copy
// Godot makes before the transparent pass: the background and the opaque models) to gamma,
// blended with the texel's colour `front` (gamma, already modulated and clamped) by the tpage's
// abr (0 half / half, 1 add, 2 subtract, 3 add a quarter), back to linear. It returns the
// difference to what was behind, for a pass drawn with render mode blend_add, so effects drawn over
// each other still add up.
#ifndef PSX_GAMMA_BLEND
#define PSX_GAMMA_BLEND

#include "res://shaders/common/psx_color.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform int abr = 1;

vec3 psx_gamma_blend(vec3 front, vec2 screen_uv) {
	vec3 behind = clamp(texture(screen_texture, screen_uv).rgb, 0.0, 1.0);
	vec3 g = linear_to_srgb(behind);
	vec3 f = abr == 3 ? front * 0.25 : front;
	vec3 blended = abr == 0 ? (g + f) * 0.5 : (abr == 2 ? g - f : g + f);
	return srgb_to_linear(clamp(blended, 0.0, 1.0)) - behind;
}

#endif
