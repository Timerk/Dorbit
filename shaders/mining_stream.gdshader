shader_type spatial;
render_mode unshaded;

// Motion belongs to the material: no particles, physics, timers or network traffic.
void fragment() {
	float flow = smoothstep(0.45,0.65,fract(UV.y*9.0-TIME*0.35));
	ALBEDO = vec3(0.08,0.65,0.56)*(0.4+flow*0.6);
}
