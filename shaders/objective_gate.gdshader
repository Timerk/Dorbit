shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Camera-facing holographic waypoint. The quad's model scale is the gate's outer radius.
uniform vec4 tint : source_color = vec4(1.0, 0.83, 0.42, 1.0);
uniform float spin = 0.06;
// Completion bursts drive this from 0 to 1; negative values draw the idle gate.
instance uniform float burst = -1.0;
varying float proximity;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 world = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * scale;
	// Fade while flying through so the gate never floods the view.
	proximity = smoothstep(scale * 0.3, scale * 1.2, length(INV_VIEW_MATRIX[3].xyz - center));
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

// Gaussian ring widened to at least a pixel and dimmed to match, which keeps
// distant gates from shimmering.
float band(float r, float center, float width) {
	float w = max(width, fwidth(r) * 1.2);
	return exp(-pow((r - center) / w, 2.0)) * (width / w);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float turn = atan(p.y, p.x) / TAU + 0.5;
	vec3 hot = mix(tint.rgb, vec3(1.0, 0.97, 0.88), 0.75);
	if (burst >= 0.0) {
		float wave = band(r, mix(0.35, 0.98, burst), 0.035) * (1.0 - burst);
		float flash = exp(-r * r * 14.0) * pow(1.0 - burst, 3.0);
		ALBEDO = mix(tint.rgb, hot, flash);
		// Stay readable but restrained for the pilot completing the objective at its center.
		ALPHA = (wave * 1.4 + flash * 1.2) * mix(0.3, 1.0, proximity);
	} else {
		float hoop = band(r, 0.72, 0.010);
		float halo = band(r, 0.72, 0.075);
		// Twelve bracket arcs turn slowly outside the hoop; fine ticks counter-rotate inside.
		float arcs = smoothstep(0.30, 0.34, fract(turn * 12.0 + TIME * spin)) * band(r, 0.84, 0.008);
		float ticks = step(0.82, fract(turn * 60.0 - TIME * spin * 0.6)) * band(r, 0.645, 0.014);
		// Four corner brackets breathe to draw the eye.
		float corners = step(0.86, fract(turn * 4.0 + 0.0625)) * band(r, 0.93, 0.012) * (0.55 + 0.45 * sin(TIME * 2.4));
		float phase = fract(TIME * 0.4);
		float pulse = band(r, mix(0.72, 1.0, phase), 0.018) * pow(1.0 - phase, 2.0);
		float fill = smoothstep(0.72, 0.15, r) * 0.035;
		ALBEDO = mix(tint.rgb, hot, hoop * 0.8);
		ALPHA = (hoop * 1.1 + halo * 0.28 + arcs * 0.7 + ticks * 0.45 + corners * 0.8 + pulse * 0.5 + fill) * proximity;
	}
}
