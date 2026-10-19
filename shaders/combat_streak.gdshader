shader_type spatial;
render_mode unshaded, blend_add, cull_back, shadows_disabled;

// Shared by laser cores and sparks; each mesh instance sets its own tint and fade.
instance uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
