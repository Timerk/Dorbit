shader_type sky;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	float ribbon = exp(-abs(d.y + 0.26 * sin(d.x * 3.0) - 0.12) * 7.0);
	float cloud = 0.5 + 0.5 * sin(d.x * 13.0 + sin(d.z * 8.0) * 2.0) * sin(d.y * 19.0 + d.z * 4.0);
	vec3 nebula = mix(vec3(0.025, 0.045, 0.10), vec3(0.115, 0.035, 0.16), cloud);
	vec2 cell = SKY_COORDS * vec2(1800.0, 900.0);
	float seed = hash(floor(cell));
	float star = step(0.997, seed) * (1.0 - smoothstep(0.06, 0.46, length(fract(cell) - 0.5)));
	COLOR = vec3(0.006, 0.009, 0.023) + nebula * ribbon * (0.25 + cloud) + vec3(0.65, 0.8, 1.0) * star;
}
