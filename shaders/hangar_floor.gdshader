shader_type spatial;
varying vec3 room_position;

void vertex() {
	room_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = room_position.xz;
	vec2 cell = abs(fract(p * .8) - .5);
	float joint = smoothstep(.478, .49, max(cell.x, cell.y));
	float ring = 1.0 - smoothstep(.018, .04, abs(length(p) - 4.1));
	float guides = step(abs(abs(p.x) - 5.7), .04) * step(abs(p.y), 8.0);
	float marking = max(ring, guides) * .72;
	ALBEDO = mix(mix(vec3(.065, .082, .10), vec3(.018, .023, .03), joint), vec3(.49, .22, .025), marking);
	METALLIC = .7;
	ROUGHNESS = .43 + joint * .18;
}
