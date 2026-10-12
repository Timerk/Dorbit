shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(0.15,0.48,0.85,1.0);
varying vec3 direction;
void vertex() { direction = normalize(VERTEX); }
void fragment() {
	float facing = max(dot(normalize(NORMAL),normalize(VIEW)),0.0);
	float edge = pow(1.0-facing,7.0);
	float day = smoothstep(-0.3,0.7,dot(direction,normalize(vec3(-0.65,0.4,0.7))));
	ALBEDO = tint.rgb*1.3;
	ALPHA = edge*(0.05+day*0.38);
}
