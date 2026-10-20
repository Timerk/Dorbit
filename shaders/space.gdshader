shader_type sky;

// The dark visible nebula needs a brighter radiance exposure for metal surfaces.
// The visible sky samples its texture separately, without the reflection exposure.
uniform float reflection_energy : hint_range(1.0, 4.0) = 3.0;
uniform vec4 nebula_cool : source_color = vec4(0.08, 0.24, 0.46, 1.0);
uniform vec4 nebula_warm : source_color = vec4(0.12, 0.38, 0.54, 1.0);
uniform vec4 nebula_light : source_color = vec4(0.22, 0.55, 0.68, 1.0);
uniform vec3 cloud_offset = vec3(5.0, 1.0, 9.0);
uniform sampler2D nebula_panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float panorama_rotation = 0.0;
// Direction toward the sector's star; scripts keep it aligned with the Sun light.
uniform vec3 sun_direction = vec3(-0.5, 0.5, 0.71);
uniform vec4 sun_color : source_color = vec4(1.0, 0.87, 0.74, 1.0);

// Direction-space noise remains continuous across the panorama seam and poles.
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11,0.23,0.37));
	p *= 17.0;
	return fract(p.x*p.y*p.z*(p.x+p.y+p.z));
}
float noise3(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
vec3 stars(vec3 d, float scale, float threshold) {
	vec3 p = d*scale;
	vec3 cell = floor(p);
	float seed = hash3(cell);
	vec3 center = vec3(hash3(cell+13.0),hash3(cell+29.0),hash3(cell+47.0));
	float point = 1.0-smoothstep(0.025,0.23,length(fract(p)-center));
	return mix(vec3(0.56,0.72,1.0),vec3(1.0,0.81,0.58),hash3(cell+7.0))*point*step(threshold,seed);
}
void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = vec2(fract(atan(d.x,-d.z)/6.2831853+0.5+panorama_rotation),acos(clamp(d.y,-1.0,1.0))/3.1415927);
	vec3 painted = texture(nebula_panorama,uv).rgb;
	float seam_blend = 0.5*(1.0-smoothstep(0.0,0.025,min(uv.x,1.0-uv.x)));
	painted = mix(painted,texture(nebula_panorama,vec2(1.0-uv.x,uv.y)).rgb,seam_blend);
	float value = max(painted.r,max(painted.g,painted.b));
	float warm = smoothstep(0.02,0.42,value);
	vec3 gas = mix(nebula_cool.rgb,nebula_warm.rgb,warm);
	// The edge blend closes the seam; fade the polar caps to avoid pinching.
	float poles = smoothstep(0.0,0.06,min(uv.y,1.0-uv.y));
	gas /= max(gas.r,max(gas.g,gas.b));
	float filaments = noise3(d*140.0+cloud_offset);
	vec3 nebula = gas*pow(value,1.15)*(0.42+filaments*0.32) + nebula_light.rgb*pow(value,2.5)*0.45;
	float corridor = mix(0.2,1.0,smoothstep(0.12,0.65,length(d.xy-vec2(0.0,0.08))));
	vec3 background = vec3(0.002,0.004,0.009)+nebula*poles*corridor;
	// A small hot disc with a wide corona; scattering slightly dims nearby gas.
	float sun_angle = max(dot(d,normalize(sun_direction)),0.0);
	float disc = smoothstep(0.99955,0.99975,sun_angle);
	float corona = pow(sun_angle,900.0)*1.6+pow(sun_angle,90.0)*0.35+pow(sun_angle,12.0)*0.06;
	vec3 sun = sun_color.rgb*(corona+disc*6.0);
	if (AT_CUBEMAP_PASS) {
		COLOR = background*reflection_energy+sun_color.rgb*pow(sun_angle,12.0)*0.15;
	} else {
		// Sample the panorama directly so the visible sky retains full texture detail.
		COLOR = background*(1.0-min(corona,0.6))+sun+stars(d,620.0,0.945)*1.0+stars(d,180.0,0.992)*1.4;
	}
}
