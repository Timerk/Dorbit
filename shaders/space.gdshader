shader_type sky;

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
float fbm(vec3 p) {
	return noise3(p)*0.51+noise3(p*2.03)*0.26+noise3(p*4.11)*0.13+noise3(p*8.21)*0.065+noise3(p*16.4)*0.035;
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
	if (AT_CUBEMAP_PASS) {
		// Static clouds bake once; flight only samples the cubemap and draws sharp stars.
		float shape = fbm(d*3.2+vec3(5,1,9));
		vec3 warp = vec3(fbm(d*4.0),fbm(d*4.0+7.0),fbm(d*4.0+19.0));
		float cloud = fbm(d*8.0+warp*3.2);
		float ribbon = exp(-pow((d.y+d.x*0.32-0.10+(shape-0.5)*0.5)*3.6,2.0));
		float luminous = smoothstep(0.30,0.78,cloud)*ribbon;
		float dust = smoothstep(0.38,0.67,fbm(d*17.0+warp*4.0));
		vec3 gas = mix(vec3(0.035,0.095,0.19),vec3(0.23,0.075,0.27),smoothstep(0.38,0.65,shape));
		vec3 nebula = gas*luminous*(0.5+cloud)*1.35;
		nebula *= 1.0-dust*0.72;
		nebula += vec3(0.08,0.22,0.27)*pow(luminous,3.0)*0.65;
		COLOR = vec3(0.003,0.005,0.012)+nebula;
	} else {
		COLOR = texture(RADIANCE,d).rgb+stars(d,420.0,0.974)+stars(d,125.0,0.993)*1.5;
	}
}
