shader_type canvas_item;

// Photo match by differential rendering, the film-VFX way of putting CG into
// a photograph:
//   with_design   - design standing on a plain white stand-in floor
//   floor_only    - the same floor, design hidden
//   design_only   - the design alone on a transparent background
// Where the floor shows, with_design / floor_only is how much the design
// darkens the ground there: its shadows and its contact shading. The photo
// is darkened by exactly that, and the design is laid over the top.

uniform sampler2D with_design : filter_linear;
uniform sampler2D floor_only : filter_linear;
uniform sampler2D design_only : filter_linear;
uniform sampler2D photo : filter_linear;
// The photo fills the frame (cropped, never stretched): its UV = uv * scale + offset.
uniform vec2 photo_scale = vec2(1.0);
uniform vec2 photo_offset = vec2(0.0);
uniform float strength : hint_range(0.0, 1.0) = 0.75;

// The passes arrive as display-encoded images; light adds and divides in
// linear space, so decode before taking the ratio.
float luma(vec3 c) {
	return dot(pow(c, vec3(2.2)), vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec4 a = texture(with_design, UV);
	vec4 b = texture(floor_only, UV);
	vec4 d = texture(design_only, UV);
	vec3 p = texture(photo, UV * photo_scale + photo_offset).rgb;
	float shade = 1.0;
	if (b.a > 0.5) {
		shade = clamp(luma(a.rgb) / max(luma(b.rgb), 0.002), 0.0, 1.0);
	}
	// shade is a linear-light factor; the photo is display-encoded, so the
	// same darkening is shade^(1/2.2) on its values.
	vec3 ground = p * pow(mix(1.0, shade, strength), 1.0 / 2.2);
	COLOR = vec4(mix(ground, d.rgb, d.a), 1.0);
}
