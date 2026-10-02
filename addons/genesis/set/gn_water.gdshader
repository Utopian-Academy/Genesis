shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Water: a flat surface whose ripples are all in the normals, so it stays
// cheap at any size. Two scrolling noise layers make the ripples; Fresnel
// makes it a mirror at a glancing angle and see-through looking down; the
// water gets its colour from how deep the ground under it is.

uniform vec3 shallow : source_color = vec3(0.16, 0.34, 0.33);
uniform vec3 deep : source_color = vec3(0.02, 0.08, 0.1);
uniform float wave_scale = 0.35;
uniform float wave_strength : hint_range(0.0, 2.0) = 0.6;
uniform float speed = 0.35;
uniform float clarity_m = 3.0;
uniform sampler2D depth_tex : hint_depth_texture;

// Ripples as a sum of directional waves (the way ocean shaders do it):
// smooth everywhere, with no grid, and they travel. Returns the slope (d/dx,
// d/dz) of the surface at p.
vec2 slope(vec2 p, float t) {
	vec2 g = vec2(0.0);
	float amp = 1.0;
	float freq = 1.0;
	// Eight waves on golden-angle headings, so no two line up into bands.
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 2.39996 + 0.4;
		vec2 dir = vec2(cos(a), sin(a));
		float phase = dot(p, dir) * freq + t * sqrt(freq) * 1.7;
		g += dir * cos(phase) * amp * freq;
		amp *= 0.7;
		freq *= 1.43;
	}
	return g;
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = slope(world.xz * wave_scale, TIME * speed) * wave_strength * 0.08;
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	// Ripples fade with distance so far water is a calm mirror, not noise.
	float dist = length(VERTEX);
	n_world = normalize(mix(n_world, vec3(0.0, 1.0, 0.0), smoothstep(40.0, 400.0, dist) * 0.8));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// How much water the eye looks through to reach the bottom.
	float scene_d = texture(depth_tex, SCREEN_UV).r;
	vec4 scene_v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_d, 1.0);
	float through = clamp((length(scene_v.xyz / scene_v.w) - length(VERTEX)) / clarity_m, 0.0, 1.0);
	ALBEDO = mix(shallow, deep, through);
	float fres = pow(1.0 - clamp(dot(NORMAL, normalize(-VERTEX)), 0.0, 1.0), 5.0);
	ALPHA = mix(0.55 + 0.4 * through, 1.0, fres);
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 0.9;
}
