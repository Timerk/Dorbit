shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 hit_direction = vec3(0.0, 0.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
varying vec3 shell_direction;

void vertex() {
	shell_direction = normalize(VERTEX);
}

void fragment() {
	float angle = acos(clamp(dot(normalize(shell_direction), hit_direction), -1.0, 1.0));
	float wave = exp(-pow((angle - progress * 2.5) / 0.09, 2.0));
	float wake = exp(-angle * 2.8) * exp(-progress * 5.0);
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	float fade = pow(1.0 - progress, 1.5);
	ALBEDO = mix(vec3(0.15, 0.55, 1.0), vec3(0.65, 0.95, 1.0), wave);
	ALPHA = (wave * 0.65 + wake * 0.55 + rim * 0.13) * fade;
}
