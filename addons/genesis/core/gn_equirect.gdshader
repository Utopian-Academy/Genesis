shader_type canvas_item;

// Six 90-degree cube faces into one equirectangular 360 image, the format
// every panorama viewer reads. Faces are named for where they look in
// Godot's world: +X, -X, +Y, -Y, +Z, -Z.

uniform sampler2D px : filter_linear, repeat_disable;
uniform sampler2D nx : filter_linear, repeat_disable;
uniform sampler2D py : filter_linear, repeat_disable;
uniform sampler2D ny : filter_linear, repeat_disable;
uniform sampler2D pz : filter_linear, repeat_disable;
uniform sampler2D nz : filter_linear, repeat_disable;
// Turns the panorama so its centre is the camera's heading.
uniform float yaw = 0.0;

void fragment() {
	// Longitude across, latitude down; the centre of the image looks along -Z.
	float lon = (UV.x - 0.5) * TAU + yaw;
	float lat = (0.5 - UV.y) * PI;
	vec3 d = vec3(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat));
	vec3 a = abs(d);
	vec2 f;
	vec4 c;
	// Each face camera looks down its axis with a 90-degree view; map the
	// direction onto that face's image (x right, y down).
	if (a.x >= a.y && a.x >= a.z) {
		if (d.x > 0.0) { f = vec2(d.z, -d.y) / a.x; c = texture(px, f * 0.5 + 0.5); }
		else { f = vec2(-d.z, -d.y) / a.x; c = texture(nx, f * 0.5 + 0.5); }
	} else if (a.y >= a.z) {
		// Up face: its "up" is +Z, so image-down is -Z. Down face: up is -Z.
		if (d.y > 0.0) { f = vec2(d.x, -d.z) / a.y; c = texture(py, f * 0.5 + 0.5); }
		else { f = vec2(d.x, d.z) / a.y; c = texture(ny, f * 0.5 + 0.5); }
	} else {
		if (d.z > 0.0) { f = vec2(-d.x, -d.y) / a.z; c = texture(pz, f * 0.5 + 0.5); }
		else { f = vec2(d.x, -d.y) / a.z; c = texture(nz, f * 0.5 + 0.5); }
	}
	COLOR = vec4(c.rgb, 1.0);
}
