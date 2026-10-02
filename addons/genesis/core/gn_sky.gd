@tool
extends RefCounted

# Photographic skies: HDRI panoramas (CC0, fetched by tools/fetch_assets.py)
# used as the sky and as the light source for the whole scene.
#
# The sun that casts shadows is still Godot's DirectionalLight3D, so it has to
# point where the sun in the photo is. That is found once per sky, by looking
# for the brightest spot in the upper hemisphere, and cached beside the HDR in
# a .sun.json. How much brighter that spot is than the rest of the sky says
# whether it is a hard sun (clear), a soft one (sunset) or none (overcast).

const SKY_DIR := "res://genesis_data/external/skies"

# Target brightness of the sky's median pixel once normalised, so every photo
# sky sits at a similar exposure whatever it was shot at.
const SKY_MEDIAN := 0.3


static func names() -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(SKY_DIR):
		for f in DirAccess.get_files_at(SKY_DIR):
			if f.get_extension() == "hdr":
				out.append(f.get_basename())
	out.sort()
	return out


static func label(sky_name: String) -> String:
	return "Photo: " + sky_name.replace("_", " ")


static func from_label(text: String) -> String:
	return text.trim_prefix("Photo: ").replace(" ", "_") if text.begins_with("Photo: ") else ""


# {direction, visibility 0-1, colour, energy} for a sky, measured once.
static func sun(sky_name: String) -> Dictionary:
	var cache := "%s/%s.sun.json" % [SKY_DIR, sky_name]
	if FileAccess.file_exists(cache):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(cache))
		if parsed is Dictionary:
			return _decode(parsed)
	var info := _measure("%s/%s.hdr" % [SKY_DIR, sky_name])
	var f := FileAccess.open(cache, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(info, "  "))
		f.close()
	return _decode(info)


static func _decode(d: Dictionary) -> Dictionary:
	return {
		"direction": direction_from_uv(d.u, d.v),
		"visibility": float(d.visibility),
		"colour": Color(d.r, d.g, d.b),
		"energy": float(d.energy),
	}


# Godot's panorama puts the image centre at +Z; measured, not assumed (a
# bright dot drawn at a known u, v lands at screen centre along this direction).
static func direction_from_uv(u: float, v: float) -> Vector3:
	var az := (u - 0.5) * TAU
	var el := (0.5 - v) * PI
	return Vector3(-sin(az) * cos(el), sin(el), cos(az) * cos(el))


static func _measure(path: String) -> Dictionary:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.convert(Image.FORMAT_RGBF)
	img.resize(512, 256, Image.INTERPOLATE_BILINEAR)
	var best := Vector2i.ZERO
	var peak := 0.0
	var lums: Array[float] = []
	for y in 128:  # upper hemisphere: the sun is never below the horizon here
		for x in 512:
			var l := img.get_pixel(x, y).get_luminance()
			lums.append(l)
			if l > peak:
				peak = l
				best = Vector2i(x, y)
	lums.sort()
	var median := maxf(lums[lums.size() / 2], 0.0001)
	var c := img.get_pixel(best.x, best.y)
	var m := maxf(c.r, maxf(c.g, c.b))
	var colour := Color(c.r / m, c.g / m, c.b / m) if m > 0 else Color.WHITE
	# A clipped sun reads as pure white; real midday sun is a touch warm.
	if colour.is_equal_approx(Color.WHITE):
		colour = Color(1.0, 0.96, 0.9)
	return {
		"u": (best.x + 0.5) / 512.0, "v": (best.y + 0.5) / 256.0,
		# peak/median: ~10^5 for a clear sun, ~25 at sunset, ~3 overcast.
		"visibility": clampf(log(peak / median) / log(10.0) / 4.0, 0.0, 1.0),
		"r": colour.r, "g": colour.g, "b": colour.b,
		"energy": SKY_MEDIAN / median,
	}


static func material(sky_name: String) -> PanoramaSkyMaterial:
	var tex := load("%s/%s.hdr" % [SKY_DIR, sky_name]) as Texture2D
	if tex == null:
		return null
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = tex
	mat.energy_multiplier = sun(sky_name).energy
	mat.resource_name = sky_name
	return mat
