shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D turbulence : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 energy_color : source_color = vec4(0.025,0.9,1.0,1.0);

void fragment() {
	vec2 p = UV*2.0-1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float angle = atan(p.y,p.x);
	// Two independently moving spherical texture samples keep the vortex detailed.
	float twist = angle/6.2831853 + r*1.7 - TIME*0.025;
	vec2 flow = vec2(fract(twist),r*0.72-TIME*0.035);
	vec3 gas = texture(turbulence,flow).rgb;
	float detail = max(gas.r,max(gas.g,gas.b));
	vec3 second = texture(turbulence,vec2(fract(-twist+r*0.6),r*1.2+TIME*0.02)).rgb;
	float turbulence_value = detail+max(second.r,max(second.g,second.b))*0.55;
	float spiral = pow(0.5+0.5*sin(angle*5.0-r*27.0+TIME*0.7+detail*6.0),12.0);
	float rings = pow(0.5+0.5*sin(r*115.0-angle*2.0-TIME*1.2+detail*5.0),20.0);
	float inner_rim = exp(-pow((r-0.97)*60.0,2.0));
	float core = exp(-r*r*28.0);
	float envelope = 1.0-smoothstep(0.78,1.0,r);
	vec3 deep = vec3(0.004,0.045,0.065);
	float brightness = min(0.88,0.12+turbulence_value*0.95+spiral*0.22+rings*0.12);
	vec3 light = energy_color.rgb*brightness;
	ALBEDO = deep+light*envelope+energy_color.rgb*inner_rim*0.65+vec3(0.8,1.0,1.0)*core;
}
