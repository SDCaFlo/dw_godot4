// Stand-in for DOOA's shards (DOOA_spawnShardWave, DOOA_updateShards): the partner's textured
// faces sink to its feet and fade while its wireframe stays (specs/death_reincarnation.md §5).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform float fall_progress : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	float p = clamp(fall_progress, 0.0, 1.0);
	VERTEX.y = mix(VERTEX.y, 0.0, p);
	float seed = float(VERTEX_ID);
	VERTEX.x += (fract(sin(seed * 12.9898) * 43758.5453) - 0.5) * p * 0.15;
	VERTEX.z += (fract(cos(seed * 78.233) * 43758.5453) - 0.5) * p * 0.15;
}

void fragment() {
	vec4 col = texture(albedo_texture, UV);
	ALBEDO = col.rgb;
	ALPHA = col.a * alpha;
}
