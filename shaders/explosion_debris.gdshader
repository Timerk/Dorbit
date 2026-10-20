shader_type spatial;
render_mode cull_back, shadows_disabled;
// Lit hull fragment whose glowing edges cool with the instance heat.

instance uniform float heat = 1.0;

void fragment() {
	ALBEDO = vec3(0.09, 0.09, 0.1);
	METALLIC = 0.6;
	ROUGHNESS = 0.55;
	EMISSION = vec3(1.0, 0.38, 0.08) * heat * heat * 3.0;
}
