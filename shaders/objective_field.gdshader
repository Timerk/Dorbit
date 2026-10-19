shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Holographic scan field on a unit sphere scaled to the scan radius. Progress fills
// it from the bottom while a sweep band crosses the grid.
uniform vec4 tint : source_color = vec4(1.0, 0.83, 0.42, 1.0);
uniform vec4 fill_tint : source_color = vec4(0.49, 1.0, 0.82, 1.0);
uniform float progress = 0.0;
varying vec3 direction;
varying float outside;

void vertex() {
	direction = VERTEX;
	// Seen from within, the shell dims so the pilot's view stays clear.
	vec3 center = MODEL_MATRIX[3].xyz;
	outside = smoothstep(0.85, 1.05, length(INV_VIEW_MATRIX[3].xyz - center) / length(MODEL_MATRIX[0].xyz));
}

// Antialiased grid line at integer values of `value`.
float grid(float value, float width) {
	float distance_to_line = abs(fract(value + 0.5) - 0.5);
	float w = fwidth(value) * 1.2 + width;
	return 1.0 - smoothstep(width, w, distance_to_line);
}

void fragment() {
	vec3 n = normalize(direction);
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	float latitude = asin(clamp(n.y, -1.0, 1.0)) / PI * 10.0;
	float longitude = (atan(n.z, n.x) / TAU + TIME * 0.01) * 24.0;
	float lines = max(grid(latitude, 0.02), grid(longitude, 0.02));
	float level = mix(-1.05, 1.05, clamp(progress, 0.0, 1.0));
	float filled = smoothstep(level + 0.015, level - 0.015, n.y);
	float surface = exp(-pow((n.y - level) / 0.025, 2.0)) * step(0.001, progress);
	float sweep_height = sin(TIME * 0.8) * 0.95;
	float sweep = exp(-pow((n.y - sweep_height) / 0.035, 2.0)) * (1.0 - filled);
	vec3 color = mix(tint.rgb, fill_tint.rgb, max(filled, surface));
	ALBEDO = mix(color, vec3(1.0), surface * 0.6);
	float shell = mix(0.3, 1.0, outside);
	ALPHA = (rim * 0.38 + lines * (0.07 + rim * 0.3) + sweep * 0.3 + filled * (0.05 + lines * 0.18)) * shell + surface * mix(0.45, 0.8, outside);
}
