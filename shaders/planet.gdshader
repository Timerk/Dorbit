shader_type spatial;
render_mode unshaded;

varying vec3 local_position;

uniform vec4 ocean_color : source_color = vec4(0.035, 0.16, 0.27, 1.0);
uniform vec4 land_color : source_color = vec4(0.23, 0.30, 0.22, 1.0);
uniform vec4 atmosphere_color : source_color = vec4(0.15, 0.48, 0.85, 1.0);
uniform float ocean_amount = 1.0;
uniform float cloud_amount = 0.65;
uniform float settlement_amount = 1.0;
uniform float mining_amount = 0.0;
uniform float terrain_seed = 0.0;

// Fixed surface sites make bombardment and extraction readable when viewed in orbit.
float site_distance(vec3 d, vec3 site) {
	return length(d - normalize(site));
}

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
	float terrain = fbm(d * 5.0 + vec3(8,3,2) + terrain_seed);
	float continent = mix(1.0, smoothstep(0.47, 0.55, terrain), ocean_amount);
	vec3 ocean = ocean_color.rgb * (0.5 + terrain);
	vec3 land = land_color.rgb * (0.55 + fbm(d*23.0)*0.8);
	vec3 cloud_warp = vec3(fbm(d*4.0), fbm(d*4.0+7.0), fbm(d*4.0+13.0));
	float clouds = smoothstep(0.49,0.70,fbm(d*9.0+cloud_warp*2.5+vec3(4,1,6)));
	vec3 surface = mix(ocean, land, continent);
	// Curved city districts follow the surface, rather than floating over the planet.
	vec2 coordinates = vec2(atan(d.x, d.z), asin(d.y)) * 65.0;
	vec2 grid = abs(fract(coordinates) - 0.5);
	float aa = max(length(fwidth(coordinates)), 0.02);
	float roads = 1.0 - smoothstep(0.035, 0.035 + aa, min(grid.x, grid.y));
	float districts = smoothstep(0.54, 0.70, fbm(d*18.0 + 21.0)) * continent * settlement_amount;
	float blocks = step(0.45, hash3(vec3(floor(coordinates), 3.0)));
	surface = mix(surface, vec3(0.25,0.27,0.28), districts * (0.18 + blocks*0.3));
	float crater = min(site_distance(d, vec3(-0.32,0.25,1.0))*1.3, site_distance(d, vec3(0.18,0.42,1.0))*1.9);
	crater = min(crater, site_distance(d, vec3(0.40,-0.12,1.0))*1.1);
	crater = min(crater, site_distance(d, vec3(-0.5,-0.32,0.8))*1.6);
	crater += (noise3(d*110.0)-0.5)*0.045;
	float scorch = (1.0 - smoothstep(0.085,0.19,crater))*settlement_amount;
	float rim_damage = smoothstep(0.06,0.09,crater) * (1.0-smoothstep(0.09,0.115,crater))*settlement_amount;
	vec3 burned_terrain = vec3(0.045,0.042,0.038)*(0.6+noise3(d*170.0));
	surface = mix(surface, burned_terrain, scorch*0.92);
	surface += vec3(0.065,0.055,0.045)*rim_damage;
	float pit = site_distance(d, vec3(-0.12,0.08,1.0));
	float excavation = (1.0-smoothstep(0.22,0.24,pit))*mining_amount;
	float terraces = smoothstep(0.3,0.6,fract((pit+noise3(d*100.0)*0.003)*48.0));
	surface = mix(surface, land_color.rgb*(0.18+terraces*0.28),excavation);
	float industrial_grid = roads * districts * (1.0-scorch) * (1.0-excavation);
	surface = mix(surface, vec3(0.65,0.72,0.77), clouds*cloud_amount);
	float daylight = smoothstep(-0.12,0.8,dot(d,normalize(vec3(-0.65,0.4,0.7))));
	float rim = pow(1.0-max(dot(normalize(NORMAL),normalize(VIEW)),0.0), 3.5);
	vec3 city_lights = vec3(0.72,0.39,0.12)*industrial_grid*(0.24+0.4*(1.0-daylight))*(1.0-clouds*cloud_amount);
	ALBEDO = surface*(0.12+daylight*1.15) + city_lights + atmosphere_color.rgb*rim*(0.25+daylight*0.7);
}
