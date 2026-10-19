shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Vertical locator beam that turns about its own axis to face the camera.
// Model X scale is the half width and Y scale the half height.
uniform vec4 tint : source_color = vec4(1.0, 0.83, 0.42, 1.0);
// Fraction of the half height left clear around the site so the beam frames it.
uniform float gap = 0.1;
varying float proximity;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_camera = INV_VIEW_MATRIX[3].xyz - center;
	vec3 sideways = cross(up, to_camera);
	vec3 right = length(sideways) > 0.001 ? normalize(sideways) : INV_VIEW_MATRIX[0].xyz;
	vec3 world = center + right * VERTEX.x * length(MODEL_MATRIX[0].xyz) + up * VERTEX.y * length(MODEL_MATRIX[1].xyz);
	// Thin out near the axis so the column never fills the screen at the site.
	float axis_distance = length(to_camera - up * dot(to_camera, up));
	proximity = smoothstep(8.0, 70.0, axis_distance);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float y = abs(UV.y * 2.0 - 1.0);
	float core = exp(-x * x * 90.0);
	float halo = pow(max(0.0, 1.0 - x), 4.0);
	// Energy rises along the column; both ends dissolve into space.
	float flow = 0.7 + 0.3 * sin(UV.y * 90.0 + TIME * 4.0);
	float ends = pow(1.0 - y, 1.6) * smoothstep(gap, gap + 0.06, y);
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.96, 0.85), core * 0.6);
	ALPHA = (core * 0.85 + halo * 0.22) * flow * ends * proximity;
}
