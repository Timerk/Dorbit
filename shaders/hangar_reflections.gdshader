shader_type sky;

// Broad ceiling strips produce continuous highlights rather than point glints.
// This environment lights reflections; the visible hangar uses actual geometry.
void sky() {
	vec3 d = normalize(EYEDIR);
	float ceiling = smoothstep(0.1, 0.7, d.y);
	float strip_a = exp(-pow((d.x - .32) * 7.0, 2.0)) * ceiling;
	float strip_b = exp(-pow((d.x + .42) * 9.0, 2.0)) * ceiling;
	float rear = exp(-pow((d.z - .65) * 5.0, 2.0)) * smoothstep(-.1, .6, d.y);
	COLOR = vec3(.055, .075, .11) + vec3(.65, .75, .9) * strip_a
		+ vec3(.45, .6, .8) * strip_b + vec3(.45, .28, .13) * rear;
}
