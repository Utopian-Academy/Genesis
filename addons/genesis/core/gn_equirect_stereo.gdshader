shader_type canvas_item;

// One eye of a stereo 360 panorama: strips rendered round the circle (each
// from the eye's place as the head turns to face it) joined into an
// equirectangular image, with the top and bottom from single straight-up
// and straight-down views, where stereo fades to nothing anyway.

uniform sampler2D strips : filter_linear, repeat_disable;   // `count` strips side by side
uniform int count = 24;
uniform float half_h = 0.2;    // tan of half a strip's horizontal view
uniform float half_v = 1.73;   // tan of half its vertical view
uniform sampler2D py : filter_linear, repeat_disable;
uniform sampler2D ny : filter_linear, repeat_disable;
uniform float yaw = 0.0;
// Latitudes past this come from the up and down views (radians).
uniform float pole = 0.96;

vec3 from_strips(vec3 d, float x01) {
	float n = float(count);
	float k = clamp(floor(x01 * n), 0.0, n - 1.0);
	float centre = -PI + (k + 0.5) * TAU / n + yaw;
	vec3 fwd = vec3(sin(centre), 0.0, -cos(centre));
	vec3 right = vec3(cos(centre), 0.0, sin(centre));
	float z = dot(d, fwd);
	float u = dot(d, right) / z / half_h;
	float v = d.y / z / half_v;
	return texture(strips, vec2((k + u * 0.5 + 0.5) / n, 0.5 - v * 0.5)).rgb;
}

vec3 from_poles(vec3 d) {
	vec3 a = abs(d);
	if (d.y > 0.0) {
		vec2 f = vec2(d.x, -d.z) / a.y;
		return texture(py, f * 0.5 + 0.5).rgb;
	}
	vec2 f = vec2(d.x, d.z) / a.y;
	return texture(ny, f * 0.5 + 0.5).rgb;
}

void fragment() {
	float lon = (UV.x - 0.5) * TAU + yaw;
	float lat = (0.5 - UV.y) * PI;
	vec3 d = vec3(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat));
	float blend = smoothstep(pole - 0.08, pole, abs(lat));
	vec3 c = blend >= 1.0 ? from_poles(d) : mix(from_strips(d, UV.x), from_poles(d), blend);
	COLOR = vec4(c, 1.0);
}
