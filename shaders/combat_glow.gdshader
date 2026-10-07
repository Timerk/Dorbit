shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.25, 0.8, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform bool beam = false;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	if (beam) {
		up = normalize(MODEL_MATRIX[1].xyz);
		vec3 sideways = cross(up, INV_VIEW_MATRIX[3].xyz - center);
		right = length(sideways) > 0.001 ? normalize(sideways) : INV_VIEW_MATRIX[0].xyz;
	}
	vec3 world = center + right * VERTEX.x * length(MODEL_MATRIX[0].xyz)
		+ up * VERTEX.y * length(MODEL_MATRIX[1].xyz);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = beam ? abs(p.x) : length(p);
	float halo = pow(max(0.0, 1.0 - radius), 3.0);
	float core = exp(-radius * radius * 110.0);
	float ends = beam ? smoothstep(0.0, 0.07, UV.y) * smoothstep(0.0, 0.07, 1.0 - UV.y) : 1.0;
	ALBEDO = mix(tint.rgb, vec3(1.0), core * 0.8);
	ALPHA = (halo * 0.65 + core * 0.35) * ends * opacity * tint.a;
}
