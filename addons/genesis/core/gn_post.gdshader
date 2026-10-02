shader_type canvas_item;

// Genesis's photographic finishing pass. Runs on the finished image, both
// on the live camera preview in the dock and on the final still, so what the
// preview shows is what renders.

uniform float contrast : hint_range(0.5, 1.6) = 1.0;
uniform float saturation : hint_range(0.0, 1.8) = 1.0;
uniform float warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float aberration : hint_range(0.0, 1.0) = 0.0;
uniform float grain : hint_range(0.0, 1.0) = 0.0;
uniform float sharpen : hint_range(0.0, 1.0) = 0.0;
uniform float sketch : hint_range(0.0, 1.0) = 0.0;
uniform float bloom : hint_range(0.0, 1.0) = 0.0;
uniform float flare : hint_range(0.0, 1.0) = 0.0;
// The sun on screen (0-1 UV), and whether it is in front of the camera.
uniform vec2 sun_uv = vec2(-10.0);
uniform float keep_hue : hint_range(0.0, 1.0) = 0.0;
uniform float selective : hint_range(0.0, 1.0) = 0.0;
uniform float watercolour : hint_range(0.0, 1.0) = 0.0;
uniform float painting : hint_range(0.0, 1.0) = 0.0;
uniform float outlines : hint_range(0.0, 1.0) = 0.0;
uniform float manga : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 from_centre = uv - 0.5;

	// Lens fringing: red and blue land slightly apart toward the edges.
	vec2 ca = from_centre * aberration * 0.006;
	vec3 c = vec3(texture(TEXTURE, uv + ca).r, texture(TEXTURE, uv).g, texture(TEXTURE, uv - ca).b);

	// Painting: a Kuwahara filter. Of four small neighbourhoods, take the
	// mean of the calmest; flat colour patches with crisp edges, like paint.
	if (painting > 0.0) {
		vec3 best = c;
		float best_v = 1e9;
		float r = 4.0;
		for (int q = 0; q < 4; q++) {
			vec2 dir = vec2(q % 2 == 0 ? -1.0 : 1.0, q < 2 ? -1.0 : 1.0);
			vec3 m = vec3(0.0);
			vec3 m2 = vec3(0.0);
			for (int j = 0; j <= 3; j++) {
				for (int i = 0; i <= 3; i++) {
					vec3 t = texture(TEXTURE, uv + dir * vec2(float(i), float(j)) * px * r / 3.0).rgb;
					m += t;
					m2 += t * t;
				}
			}
			m /= 16.0;
			vec3 var3 = m2 / 16.0 - m * m;
			float v = var3.r + var3.g + var3.b;
			if (v < best_v) { best_v = v; best = m; }
		}
		c = mix(c, best, painting);
	}

	// Bloom: bright light spilling into its surroundings.
	if (bloom > 0.0) {
		vec3 glow = vec3(0.0);
		for (int i = 0; i < 16; i++) {
			float a = float(i) * 2.39996;
			float rr = sqrt(float(i) + 0.5) * 6.0;
			vec3 t = texture(TEXTURE, uv + vec2(cos(a), sin(a)) * rr * px * 2.0).rgb;
			glow += max(t - 0.72, 0.0);
		}
		c += glow / 16.0 * bloom * 3.0;
	}

	// Unsharp mask: the image minus its blur, added back.
	if (sharpen > 0.0) {
		vec3 blur = (texture(TEXTURE, uv + vec2(px.x, 0.0)).rgb + texture(TEXTURE, uv - vec2(px.x, 0.0)).rgb
			+ texture(TEXTURE, uv + vec2(0.0, px.y)).rgb + texture(TEXTURE, uv - vec2(0.0, px.y)).rgb) * 0.25;
		c += (c - blur) * sharpen * 1.5;
	}

	// Warmth: sunlit orange against shade blue, as a white-balance shift.
	c *= vec3(1.0 + warmth * 0.08, 1.0, 1.0 - warmth * 0.1);
	float l = luma(c);
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;

	// Keep one colour, fade the rest (a red chair in a grey room).
	if (selective > 0.0) {
		vec3 hsv = rgb2hsv(c);
		float dh = abs(hsv.x - keep_hue);
		dh = min(dh, 1.0 - dh);
		float keep = smoothstep(0.09, 0.03, dh) * smoothstep(0.1, 0.25, hsv.y);
		c = mix(c, vec3(luma(c)), selective * (1.0 - keep));
	}

	// Outlines: the drawing's edges inked over the colour.
	float ex = luma(texture(TEXTURE, uv + vec2(px.x, 0.0)).rgb) - luma(texture(TEXTURE, uv - vec2(px.x, 0.0)).rgb);
	float ey = luma(texture(TEXTURE, uv + vec2(0.0, px.y)).rgb) - luma(texture(TEXTURE, uv - vec2(0.0, px.y)).rgb);
	float edges = clamp(length(vec2(ex, ey)) * 6.0, 0.0, 1.0);
	if (outlines > 0.0) {
		c *= 1.0 - edges * outlines * 0.9;
	}

	// Watercolour: softened, fewer tones, pigment pooling at the edges, on paper.
	if (watercolour > 0.0) {
		vec3 soft = vec3(0.0);
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 2.39996;
			soft += texture(TEXTURE, uv + vec2(cos(a), sin(a)) * sqrt(float(i) + 0.5) * px * 2.5).rgb;
		}
		soft /= 12.0;
		vec3 tones = floor(soft * 6.0 + 0.5) / 6.0;
		vec3 wash = mix(soft, tones, 0.5) * (1.0 - edges * 0.35);
		float paper = 0.94 + 0.06 * hash(floor(uv / px / 3.0));
		wash = mix(vec3(1.0), wash, 0.85) * paper;
		c = mix(c, wash, watercolour);
	}

	// Pencil on paper: edges from the change in brightness, darkened on white.
	if (sketch > 0.0) {
		float gx = luma(texture(TEXTURE, uv + vec2(px.x, 0.0)).rgb) - luma(texture(TEXTURE, uv - vec2(px.x, 0.0)).rgb);
		float gy = luma(texture(TEXTURE, uv + vec2(0.0, px.y)).rgb) - luma(texture(TEXTURE, uv - vec2(0.0, px.y)).rgb);
		float edge = clamp(length(vec2(gx, gy)) * 6.0, 0.0, 1.0);
		float shade = smoothstep(0.15, 0.85, luma(c));
		vec3 paper = vec3(0.97, 0.955, 0.93) * mix(0.82, 1.0, shade);
		vec3 drawn = paper * (1.0 - edge * 0.85);
		c = mix(c, drawn, sketch);
	}

	// Manga: bold ink lines, white paper, solid black shadows, and the
	// midtones in screentone, dots on a 45-degree grid sized by the tone.
	if (manga > 0.0) {
		float lum = luma(c);
		vec2 d2 = px * 1.5;
		float mx = luma(texture(TEXTURE, uv + vec2(d2.x, 0.0)).rgb) - luma(texture(TEXTURE, uv - vec2(d2.x, 0.0)).rgb);
		float my = luma(texture(TEXTURE, uv + vec2(0.0, d2.y)).rgb) - luma(texture(TEXTURE, uv - vec2(0.0, d2.y)).rgb);
		float ink = smoothstep(0.08, 0.2, length(vec2(mx, my)));
		vec2 p = uv / px;
		vec2 r = vec2(p.x + p.y, p.y - p.x) * 0.7071;
		float cell = max(5.0, 1.0 / max(px.y, 1e-6) / 180.0);
		vec2 f = fract(r / cell) - 0.5;
		float dot_r = sqrt(clamp(1.0 - lum, 0.0, 1.0)) * 0.62;
		float in_dot = 1.0 - smoothstep(dot_r - 0.06, dot_r + 0.06, length(f));
		float tone = lum > 0.7 ? 1.0 : (lum < 0.16 ? 0.0 : 1.0 - in_dot);
		vec3 page = vec3(0.98, 0.97, 0.95) * tone * (1.0 - ink);
		c = mix(c, page, manga);
	}

	// Lens flare: a soft glow round the sun and ghosts strung through the
	// frame's centre, only when the sun is in or near the shot.
	if (flare > 0.0 && sun_uv.x > -1.0 && sun_uv.x < 2.0 && sun_uv.y > -1.0 && sun_uv.y < 2.0) {
		vec2 aspect = vec2(TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x, 1.0);
		vec2 to_sun = (uv - sun_uv) * aspect;
		float halo = exp(-length(to_sun) * 9.0) * 0.8;
		vec3 f = vec3(1.0, 0.9, 0.75) * halo;
		vec2 axis = sun_uv - 0.5;
		for (int i = 1; i <= 4; i++) {
			float k = -0.4 * float(i) + 0.3;
			vec2 gp = (uv - (0.5 + axis * k)) * aspect;
			float ghost = smoothstep(0.05 + 0.02 * float(i), 0.0, length(gp));
			f += ghost * vec3(0.3 + 0.2 * float(i % 2), 0.5, 0.9 - 0.15 * float(i)) * 0.25;
		}
		c += f * flare;
	}

	float v = smoothstep(0.85, 0.2, length(from_centre * vec2(1.0, 0.8)));
	c *= mix(1.0, v, vignette);
	c += (hash(uv * 1000.0) - 0.5) * grain * 0.08;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
