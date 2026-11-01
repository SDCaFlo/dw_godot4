// The drop shadow (DropShadow, specs/drop_shadow.md). The PSX subtracts in its own (gamma) colour
// values; Godot blends in linear light, where a dark ground (the night's backgrounds) is so close
// to 0 that even the spot's faint edge would wipe it to black. So the shader does the subtraction
// itself: the screen behind it (the copy Godot makes before the transparent pass: the background
// and the opaque models) to gamma, minus the raw texel values (no source_color: the PSX's own)
// times the colour, back to linear. It outputs what that takes away and draws with blend_sub, so
// shadows over each other subtract twice as the PSX's do (drop_shadow.c: each a subtractive polygon
// at OT 0xFFD; ISSUES.md I-39: with blend_mix the second shadow replaced the first one's darkening).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_sub;
#include "res://shaders/common/psx_color.gdshaderinc"

uniform sampler2D tex : filter_nearest;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform vec4 region;
uniform float color_scale;

void fragment() {
	vec4 c = texture(tex, region.xy + UV * region.zw);
	if (c.a < 0.5) {
		discard;
	}
	vec3 behind = clamp(texture(screen, SCREEN_UV).rgb, 0.0, 1.0);
	vec3 shadowed = srgb_to_linear(max(linear_to_srgb(behind) - c.rgb * color_scale, vec3(0.0)));
	ALBEDO = behind - shadowed;
	ALPHA = 1.0;
}
