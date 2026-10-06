shader_type spatial;
render_mode unshaded;

varying vec3 local_position;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.23, 0.37));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise3(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i+vec3(1,0,0)), f.x), mix(hash3(i+vec3(0,1,0)), hash3(i+vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i+vec3(0,0,1)), hash3(i+vec3(1,0,1)), f.x), mix(hash3(i+vec3(0,1,1)), hash3(i+vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	return noise3(p)*0.53 + noise3(p*2.03)*0.27 + noise3(p*4.11)*0.13 + noise3(p*8.31)*0.07;
}
void vertex() {
	local_position = VERTEX;
}
void fragment() {
	vec3 d = normalize(local_position);
	float terrain = fbm(d * 5.0 + vec3(8,3,2));
	float continent = smoothstep(0.52, 0.58, terrain);
	vec3 ocean = mix(vec3(0.015,0.05,0.09), vec3(0.04,0.20,0.24), terrain);
	vec3 land = mix(vec3(0.16,0.20,0.14), vec3(0.42,0.39,0.28), fbm(d*23.0));
	vec3 cloud_warp = vec3(fbm(d*4.0), fbm(d*4.0+7.0), fbm(d*4.0+13.0));
	float clouds = smoothstep(0.49,0.70,fbm(d*9.0+cloud_warp*2.5+vec3(4,1,6)));
	vec3 surface = mix(mix(ocean, land, continent), vec3(0.63,0.73,0.79), clouds*0.7);
	float daylight = smoothstep(-0.12,0.8,dot(d,normalize(vec3(-0.65,0.4,0.7))));
	float rim = pow(1.0-max(dot(normalize(NORMAL),normalize(VIEW)),0.0), 3.5);
	ALBEDO = surface*(0.025+daylight*0.85) + vec3(0.08,0.34,0.55)*rim*(0.2+daylight*0.8);
}
