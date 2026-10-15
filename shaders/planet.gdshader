shader_type spatial;
render_mode unshaded;
varying vec3 local_position;
uniform sampler2D surface_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform float surface_desaturation = 0.0;
uniform float surface_rotation = 0.0;
uniform vec4 atmosphere_color : source_color = vec4(0.15,0.48,0.85,1.0);
uniform float settlement_amount = 1.0;
uniform float mining_amount = 0.0;
uniform float terrain_seed = 0.0;
uniform float war_damage = 0.0;
float hash3(vec3 p) {
	p = fract(p*0.3183099+vec3(0.11,0.23,0.37));
	p *= 17.0;
	return fract(p.x*p.y*p.z*(p.x+p.y+p.z));
}
float noise3(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { local_position = VERTEX; }
void fragment() {
	vec3 d = normalize(local_position);
	vec2 uv = vec2(fract(atan(d.x,d.z)/6.2831853+0.5+surface_rotation),acos(clamp(d.y,-1.0,1.0))/3.1415927);
	vec3 painted = texture(surface_map,uv).rgb;
	float seam = 0.5*(1.0-smoothstep(0.0,0.018,min(uv.x,1.0-uv.x)));
	painted = mix(painted,texture(surface_map,vec2(1.0-uv.x,uv.y)).rgb,seam);
	vec3 surface = mix(painted,vec3(dot(painted,vec3(0.2126,0.7152,0.0722))),surface_desaturation)*surface_tint.rgb;
	// The extraction site stays aligned with the real orbital stream endpoint.
	float pit = length((d.xy-vec2(-0.12,0.08))*vec2(1.0,1.4));
	pit += (noise3(d*95.0)-0.5)*0.012;
	float excavation = (1.0-smoothstep(0.11,0.125,pit))*step(0.0,d.z)*mining_amount;
	float terraces = smoothstep(0.1,0.4,fract(pit*155.0));
	surface = mix(surface,surface*(0.35+terraces*0.36),excavation);
	float daylight = smoothstep(-0.18,0.85,dot(d,normalize(vec3(-0.65,0.4,0.7))));
	float rim = pow(1.0-max(dot(normalize(NORMAL),normalize(VIEW)),0.0),5.0);
	// Surviving city clusters are interrupted by dead districts, without a global grid.
	float inhabited = smoothstep(0.58,0.78,noise3(d*32.0+terrain_seed));
	float land = smoothstep(-0.015,0.04,painted.r-painted.b)*(1.0-step(0.55,painted.b));
	float windows = pow(noise3(d*900.0),12.0)*inhabited*land*settlement_amount;
	// The colony's blackened districts no longer produce surviving window lights.
	float survival = smoothstep(0.018,0.075,max(painted.r,max(painted.g,painted.b)));
	windows *= mix(1.0,survival,war_damage);
	vec3 city_lights = vec3(0.9,0.48,0.18)*windows*(1.0-daylight)*(1.0-excavation)*1.4;
	ALBEDO = surface*(0.045+daylight*1.1)+city_lights+atmosphere_color.rgb*rim*(0.1+daylight*0.35);
}
