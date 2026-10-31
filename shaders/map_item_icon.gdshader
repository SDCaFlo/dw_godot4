// An item lying on the map (MapItems): its icon, a region of the item texture.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 region;

void fragment() {
	vec4 c = texture(tex, region.xy + UV * region.zw);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
}
