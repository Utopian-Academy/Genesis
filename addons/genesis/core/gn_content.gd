@tool
extends RefCounted

# Sample content for screens and LED walls, generated here so it is ours to
# use in any render: a show visual, bands of colour with a bright horizon.

const DIR := "res://genesis_data/content"


static func concert_visual(w := 1728, h := 768) -> String:
	var path := "%s/concert_visual_%dx%d.png" % [DIR, w, h]
	if FileAccess.file_exists(path):
		return path
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.004
	for y in h:
		for x in w:
			var n := noise.get_noise_2d(x, y * 2.5)
			var t := float(y) / h
			var band := 0.5 + 0.5 * sin(x * 0.012 + n * 6.0)
			var col := Color(0.95, 0.2, 0.6).lerp(Color(0.15, 0.4, 1.0), t).lerp(Color(1.0, 0.75, 0.3), band * (1.0 - t) * 0.6)
			var glow := exp(-pow((t - 0.62) * 9.0, 2.0)) * 0.9
			var out := col * (0.45 + 0.4 * band) + Color(glow, glow * 0.85, glow * 0.7)
			img.set_pixel(x, y, Color(minf(out.r, 1.0), minf(out.g, 1.0), minf(out.b, 1.0)))
	DirAccess.make_dir_recursive_absolute(DIR)
	img.save_png(path)
	return path
