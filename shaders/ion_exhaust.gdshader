shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Ion drive plume on an open unit cone: +Y is the nozzle, -Y the tail.

uniform vec4 core_color : source_color = vec4(0.78, 0.97, 1.0, 1.0);
uniform vec4 plume_color : source_color = vec4(0.18, 0.5, 1.0, 1.0);
uniform vec4 boost_color : source_color = vec4(0.72, 0.38, 1.0, 1.0);
uniform float throttle : hint_range(0.0, 1.0) = 0.0;
uniform float boost : hint_range(0.0, 1.0) = 0.0;

varying float along;
varying vec3 axis;

void vertex() {
	along = 0.5 - VERTEX.y;
	axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	// Bright through the middle and soft at the silhouette, like a glowing gas column.
	float facing = abs(dot(NORMAL, VIEW));
	// Looking down the axis from the chase camera, the view crosses the whole column.
	float body = max(pow(facing, 1.6), pow(abs(dot(axis, VIEW)), 2.0) * 0.8);
	float fade = pow(1.0 - along, 1.8) * smoothstep(0.0, 0.04, along);
	// Pulses travel down the plume and spread as it stretches; boost packs them tighter and faster.
	float pulse = pow(0.5 + 0.5 * sin((along * mix(3.0, 5.0, boost) - TIME * mix(2.5, 4.5, boost)) * TAU), 6.0);
	// Helical filaments read as a magnetically confined stream instead of flame.
	float filaments = 0.75 + 0.25 * sin(UV.x * TAU * 5.0 + along * 9.0 - TIME * 11.0);
	float flicker = 0.93 + 0.07 * sin(TIME * 41.0 + UV.x * 13.0);
	vec3 tail = mix(plume_color.rgb, boost_color.rgb, boost);
	ALBEDO = mix(core_color.rgb, tail, smoothstep(0.0, 0.55, along));
	float glow = body * filaments * 0.8 + pulse * (0.3 + 0.5 * body);
	ALPHA = clamp(glow * fade * flicker * throttle * (1.0 + 0.5 * boost), 0.0, 1.0);
}
