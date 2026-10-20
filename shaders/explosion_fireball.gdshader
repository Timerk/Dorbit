shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Camera-facing turbulent puff: white-hot core, orange flame, then dark smoke as it cools.

instance uniform float progress = 0.0;
instance uniform float seed = 0.0;
instance uniform float heat = 1.0;

varying float spin;

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float noise2(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.55;
	for (int octave = 0; octave < 4; octave++) {
		total += noise2(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.4);
		amplitude *= 0.5;
	}
	return total;
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * length(MODEL_MATRIX[0].xyz);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	spin = seed * 6.2831853;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * p;
	float t = clamp(progress, 0.0, 1.0);
	// Billows roll outward as the puff expands.
	float turbulence = fbm(p * 2.6 + vec2(seed * 31.0, seed * 17.0) - p * t * 1.5);
	float radius = length(p) + (turbulence - 0.5) * 0.55;
	float edge = 0.45 + 0.4 * sqrt(t);
	float body = 1.0 - smoothstep(edge - 0.3, edge, radius);
	// Heat drains from the outside in; the late puff is mostly smoke.
	float detail = fbm(p * 6.0 + vec2(seed * 13.0, t * 2.0));
	float temperature = clamp((1.0 - radius / edge) * 1.5 * heat * (1.0 - t * 1.7) + (turbulence + detail * 0.5) * 0.4 - 0.15 - t * 0.25, 0.0, 1.0);
	vec3 smoke = vec3(0.085, 0.075, 0.07) * (0.45 + turbulence + detail * 0.4);
	vec3 flame = mix(vec3(0.65, 0.1, 0.02), vec3(1.0, 0.5, 0.1), smoothstep(0.15, 0.5, temperature));
	flame = mix(flame, vec3(1.0, 0.9, 0.68), smoothstep(0.62, 0.95, temperature));
	float glowing = smoothstep(0.04, 0.32, temperature);
	ALBEDO = mix(smoke, flame * (0.7 + detail * 0.6) * (1.0 + temperature * 3.0), glowing);
	float smoke_alpha = 0.85 * (1.0 - smoothstep(0.6, 1.0, t));
	ALPHA = clamp(body * mix(smoke_alpha, 1.0, glowing), 0.0, 1.0);
}
