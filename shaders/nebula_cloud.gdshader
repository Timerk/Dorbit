shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Large camera-facing gas wisps inside the sector. Additive layers give the
// nebula parallax depth; they thin out as the camera flies into them.

uniform vec4 gas_cool : source_color = vec4(0.13, 0.36, 0.58, 1.0);
uniform vec4 gas_light : source_color = vec4(0.45, 0.72, 0.82, 1.0);
uniform float density = 0.3;

varying float near_fade;
varying float seed;

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
	float amplitude = 0.5;
	for (int octave = 0; octave < 6; octave++) {
		total += noise2(p) * amplitude;
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(3.1, 7.7);
		amplitude *= 0.5;
	}
	return total;
}

void vertex() {
	seed = INSTANCE_CUSTOM.x;
	vec3 center = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 world = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	// Flat cards would be obvious up close, so each wisp dissolves as the camera enters it.
	near_fade = smoothstep(size * 0.12, size * 0.55, distance(CAMERA_POSITION_WORLD, center));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 offset = vec2(seed * 37.0, seed * 91.0);
	// Domain warping turns round noise into filaments; slow drift keeps the gas alive.
	vec2 warp = vec2(fbm(p * 1.7 + offset), fbm(p * 1.7 + offset + vec2(5.2, 1.3)));
	float gas = fbm(p * 2.2 + warp * 1.6 + offset + TIME * 0.004);
	float shape = 1.0 - smoothstep(0.35, 1.0, length(p) + (warp.x - 0.5) * 0.5);
	float body = smoothstep(0.38, 0.8, gas) * shape;
	ALBEDO = mix(gas_cool.rgb, gas_light.rgb, smoothstep(0.55, 0.85, gas));
	ALPHA = clamp(body * density * near_fade, 0.0, 1.0);
}
