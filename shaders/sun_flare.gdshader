shader_type canvas_item;
render_mode blend_add, unshaded;
// Screen-space glare, anamorphic streak and lens ghosts for the visible sun.

uniform vec2 sun_position = vec2(0.5);
uniform float intensity = 0.0;
uniform float aspect = 1.777;
uniform vec4 sun_color : source_color = vec4(1.0, 0.87, 0.74, 1.0);

float disc(vec2 p, vec2 center, float radius, float softness) {
	vec2 d = (p - center) * vec2(aspect, 1.0);
	return 1.0 - smoothstep(radius * (1.0 - softness), radius, length(d));
}

void fragment() {
	vec2 p = UV;
	vec2 d = (p - sun_position) * vec2(aspect, 1.0);
	float distance_to_sun = length(d);
	vec3 light = sun_color.rgb * (exp(-distance_to_sun * 9.0) * 0.35 + exp(-distance_to_sun * 40.0) * 0.6);
	// A thin horizontal streak, like light scattered across a camera lens.
	light += vec3(0.55, 0.75, 1.0) * exp(-abs(d.y) * 260.0) * exp(-abs(d.x) * 2.2) * 0.35;
	// Ghosts sit on the line from the sun through the screen centre.
	vec2 axis = vec2(0.5) - sun_position;
	light += vec3(0.4, 0.75, 1.0) * disc(p, sun_position + axis * 0.55, 0.035, 0.6) * 0.14;
	light += vec3(1.0, 0.6, 0.3) * disc(p, sun_position + axis * 1.25, 0.06, 0.35) * 0.08;
	light += vec3(0.5, 1.0, 0.7) * disc(p, sun_position + axis * 1.6, 0.02, 0.5) * 0.12;
	float halo = disc(p, sun_position + axis * 2.0, 0.16, 0.12) - disc(p, sun_position + axis * 2.0, 0.145, 0.2);
	light += vec3(0.6, 0.55, 1.0) * max(halo, 0.0) * 0.07;
	COLOR = vec4(light * intensity, 1.0);
}
