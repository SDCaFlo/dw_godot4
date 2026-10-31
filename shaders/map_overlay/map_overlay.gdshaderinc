// A map's overlay sprite (MapOverlays). The texels without the STP bit are opaque; with it, a
// semi-transparent sprite blends them (tim.md): one pass each. 50 / 50 is a mix at half alpha,
// +25 % an add of a quarter. The variants next to this file set the blend mode (mix, add, sub).
uniform sampler2D tex : source_color, filter_nearest;
uniform sampler2D stp : filter_nearest;
uniform bool use_stp = false;
uniform bool blended_pass = false;
uniform float alpha_scale = 1.0;
uniform float color_scale = 1.0;

void fragment() {
	vec4 c = texture(tex, UV);
	bool semi = use_stp && texture(stp, UV).r > 0.5;
	if (c.a < 0.5 || semi != blended_pass) {
		discard;
	}
	ALBEDO = c.rgb * color_scale;
	ALPHA = blended_pass ? alpha_scale : 1.0;
}
