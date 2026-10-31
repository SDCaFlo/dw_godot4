// The death scenes' iris (MURD_renderIris, DOOA_renderIrisWindow) and the map background's
// darkening (fadeoutCLUT1): black outside a circle of `radius` PSX pixels around `center`, and
// `darkness` (0-1) of black inside it. Drawn on the background layer, under the 3D world, so the
// partner stays in front (the C draws it over the iris once it is larger than the window).
shader_type canvas_item;

uniform vec2 center = vec2(160.0, 120.0);
uniform float radius = 400.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform vec2 screen_size = vec2(320.0, 240.0);

void fragment() {
	vec2 pixel = UV * screen_size;
	float outside = length(pixel - center) > radius ? 1.0 : 0.0;
	COLOR = vec4(0.0, 0.0, 0.0, max(outside, darkness));
}
