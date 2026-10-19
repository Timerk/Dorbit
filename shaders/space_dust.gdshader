shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// Drifting dust motes that wrap around the camera; motion stretches them into streaks.

uniform float box_size = 140.0;
uniform vec3 velocity = vec3(0.0);
uniform float streak_time = 0.06; // Seconds of travel each streak represents.
uniform vec4 dust_color : source_color = vec4(0.62, 0.74, 0.92, 1.0);

varying float fade;
varying float along;

void vertex() {
	// Seeds come from per-instance custom data, independent of the node transform.
	vec3 camera = CAMERA_POSITION_WORLD;
	vec3 seed = INSTANCE_CUSTOM.xyz * box_size;
	vec3 center = camera + mod(seed - camera, vec3(box_size)) - vec3(box_size * 0.5);
	vec3 to_camera = camera - center;
	float distance_to_camera = length(to_camera);
	float speed = length(velocity);
	vec3 axis = speed > 0.5 ? velocity / speed : INV_VIEW_MATRIX[1].xyz;
	vec3 side = cross(axis, to_camera);
	side = length(side) > 0.001 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
	float length_m = 0.06 + speed * streak_time;
	// Keep distant motes about two pixels wide at 1080p instead of vanishing below one.
	float width = max(0.04, distance_to_camera * 0.0032);
	vec3 world = center + side * VERTEX.x * width + axis * VERTEX.y * length_m;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	// Hide motes that pop at the wrap boundary or sit right on the lens.
	float edge = 1.0 - smoothstep(box_size * 0.32, box_size * 0.5, distance_to_camera);
	float near = smoothstep(1.5, 6.0, distance_to_camera);
	// Faster flight thins each streak's brightness so boost does not wash out the view.
	fade = edge * near * INSTANCE_CUSTOM.w / (1.0 + speed * 0.012);
	along = UV.y;
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float tail = smoothstep(0.0, 0.35, along) * smoothstep(1.0, 0.8, along);
	ALBEDO = dust_color.rgb;
	ALPHA = clamp(across * tail * fade * 0.9, 0.0, 1.0);
}
