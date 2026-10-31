// The upscaling filter of the text and windows (PsxUiFilter, ISSUES.md D-3): Scale4x, or the
// texels as square blocks when the global psx_ui_filter is off. The variants next to this file set
// the blend mode (mix, add, sub).

global uniform bool psx_ui_filter;

// The draw's tint (modulate, the vertex colour) alone: in fragment() COLOR already holds the
// texture's colour times it, and the filter samples the texture itself.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

vec4 px(sampler2D tex, ivec2 size, ivec2 p) {
	return texelFetch(tex, clamp(p, ivec2(0), size - 1), 0);
}

bool same(vec4 a, vec4 b) {
	return all(equal(a, b));
}

// Scale2x (EPX): sub-pixel q (0 / 1 on each axis) of texel p.
vec4 scale2x(sampler2D tex, ivec2 size, ivec2 p, ivec2 q) {
	vec4 b = px(tex, size, p + ivec2(0, -1));
	vec4 d = px(tex, size, p + ivec2(-1, 0));
	vec4 e = px(tex, size, p);
	vec4 f = px(tex, size, p + ivec2(1, 0));
	vec4 h = px(tex, size, p + ivec2(0, 1));
	if (!same(b, h) && !same(d, f)) {
		if (q == ivec2(0, 0) && same(d, b)) return d;
		if (q == ivec2(1, 0) && same(b, f)) return f;
		if (q == ivec2(0, 1) && same(d, h)) return d;
		if (q == ivec2(1, 1) && same(h, f)) return f;
	}
	return e;
}

// A pixel of the 2x picture (Scale2x of the texture).
vec4 px2(sampler2D tex, ivec2 size, ivec2 p) {
	return scale2x(tex, size, p >> ivec2(1), p & ivec2(1));
}

// Scale4x: Scale2x of the 2x picture, at a texel position (texels, fractional).
vec4 scale4x(sampler2D tex, ivec2 size, vec2 t) {
	vec2 t2 = t * 2.0;
	ivec2 p = ivec2(floor(t2));
	ivec2 q = ivec2(floor(fract(t2) * 2.0));
	vec4 b = px2(tex, size, p + ivec2(0, -1));
	vec4 d = px2(tex, size, p + ivec2(-1, 0));
	vec4 e = px2(tex, size, p);
	vec4 f = px2(tex, size, p + ivec2(1, 0));
	vec4 h = px2(tex, size, p + ivec2(0, 1));
	if (!same(b, h) && !same(d, f)) {
		if (q == ivec2(0, 0) && same(d, b)) return d;
		if (q == ivec2(1, 0) && same(b, f)) return f;
		if (q == ivec2(0, 1) && same(d, h)) return d;
		if (q == ivec2(1, 1) && same(h, f)) return f;
	}
	return e;
}

void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	vec2 t = UV * vec2(size);
	vec4 c = psx_ui_filter ? scale4x(TEXTURE, size, t) : px(TEXTURE, size, ivec2(floor(t)));
	COLOR = c * tint;
}
