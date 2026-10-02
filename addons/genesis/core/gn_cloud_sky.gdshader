shader_type sky;

// A procedural sky with clouds, for when a photo sky is not wanted: the same
// top/horizon/ground gradient as Godot's procedural sky, the sun's disc
// taken from the scene's sun, and a layer of clouds whose cover is one
// number (Lumion's "cloudiness"). Clouds are two octaves of value noise on
// a dome, lit from the sun's side and greyed as they thicken.

uniform vec3 sky_top : source_color = vec3(0.22, 0.42, 0.78);
uniform vec3 sky_horizon : source_color = vec3(0.66, 0.77, 0.9);
uniform vec3 ground : source_color = vec3(0.3, 0.28, 0.25);
uniform float energy = 1.0;
uniform float cloudiness : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_scale = 1.6;
uniform float seed = 3.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	vec3 col = up > 0.0 ? mix(sky_horizon, sky_top, pow(up, 0.5)) : mix(sky_horizon, ground, pow(-up, 0.35));
	// Sun disc and glow from the first directional light.
	if (LIGHT0_ENABLED) {
		float s = dot(d, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (smoothstep(0.9995, 0.9998, s) * 20.0 + pow(max(s, 0.0), 64.0) * 0.4);
	}
	if (up > 0.0) {
		// Project onto a flat cloud deck: clouds bunch toward the horizon.
		vec2 uv = d.xz / (up + 0.08) * cloud_scale;
		float n = fbm(uv);
		float cover = smoothstep(1.0 - cloudiness, 1.15 - cloudiness * 0.6, n);
		float shade = mix(1.0, 0.55, cloudiness) * (0.85 + 0.15 * fbm(uv * 2.0 + 7.0));
		vec3 cloud = vec3(shade);
		if (LIGHT0_ENABLED) {
			cloud *= mix(vec3(1.0), LIGHT0_COLOR, 0.35) * (0.7 + 0.3 * max(dot(d, LIGHT0_DIRECTION), 0.0));
		}
		col = mix(col, cloud * mix(1.0, 0.9, cloudiness), cover * smoothstep(0.0, 0.08, up));
		// A fully overcast sky flattens toward grey.
		col = mix(col, vec3(0.72, 0.74, 0.77) * 0.9, cloudiness * cloudiness * 0.6);
	}
	COLOR = col * energy;
}
