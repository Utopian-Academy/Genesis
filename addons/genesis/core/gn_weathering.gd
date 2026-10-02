@tool
extends RefCounted

# Weathering: a surface as it looks after years outdoors. Rain streaks run
# down from ledges, grime settles, damp stains and a little moss creep in,
# and the finish goes duller and rougher. Laid over any material as its
# detail layer (multiplied over the colour), so the material itself is kept
# and the effect can be turned back down to nothing.
#
# Presets map in world space with up as up, so on a wall the streaks fall
# straight down, as rain does.

const GnMaterials := preload("res://addons/genesis/core/gn_materials.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

const DIR := "res://genesis_data/weathering"
const LEVELS := 5
const META := &"gn_weathering"


## How weathered a surface is, 0-1.
static func amount(s: GnMaterials.Surface) -> float:
	var mat := s.material()
	return float(mat.get_meta(META, 0.0)) if mat else 0.0


## Weathers a surface by `a` (0 takes it all off again), as one undo step.
static func apply(s: GnMaterials.Surface, a: float) -> void:
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Genesis: weathering", UndoRedo.MERGE_ENDS, GnScene.root())
	var mat := s.mesh.get(s.property()) as BaseMaterial3D
	if mat == null:
		var active := s.material() as BaseMaterial3D
		mat = active.duplicate() if active else StandardMaterial3D.new()
		GnMaterials._allow_override(ur, s.mesh)
		ur.add_do_property(s.mesh, s.property(), mat)
		ur.add_undo_property(s.mesh, s.property(), null)
	# The unweathered finish, remembered the first time.
	var clean: Dictionary = mat.get_meta(&"gn_clean", {"roughness": mat.roughness, "albedo": mat.albedo_color})
	var level := clampi(roundi(a * LEVELS), 0, LEVELS)
	# A little duller and darker, keeping its opacity.
	var c: Color = clean.albedo
	var lum := c.get_luminance()
	var worn := c.lerp(Color(lum, lum, lum, c.a), a * 0.2).darkened(0.12 * a)
	worn.a = c.a
	var changes := {
		"detail_enabled": level > 0,
		"detail_blend_mode": BaseMaterial3D.BLEND_MODE_MUL,
		"detail_uv_layer": BaseMaterial3D.DETAIL_UV_1,
		"detail_albedo": texture(level) if level > 0 else null,
		"roughness": minf(float(clean.roughness) + 0.25 * a, 1.0),
		"albedo_color": worn,
		"metadata/gn_weathering": a,
		"metadata/gn_clean": clean,
	}
	for k in changes:
		ur.add_do_property(mat, k, changes[k])
		ur.add_undo_property(mat, k, mat.get(k))
	ur.commit_action()


## The grime for one level, drawn and saved the first time it is asked for.
static func texture(level: int) -> Texture2D:
	var path := "%s/grime_%d.res" % [DIR, level]
	if ResourceLoader.exists(path):
		return load(path)
	DirAccess.make_dir_recursive_absolute(DIR)
	var img := _draw(float(level) / LEVELS, level)
	img.generate_mipmaps()
	var tex := PortableCompressedTexture2D.new()
	tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, false, 0.9)
	ResourceSaver.save(tex, path)
	return load(path)


# White where clean; darker streaks, grime and tinted stains where weathered.
# It tiles, so it repeats with the material's own pattern.
static func _draw(a: float, seed: int) -> Image:
	var w := 256
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var grime := FastNoiseLite.new()
	grime.seed = 11 + seed
	grime.frequency = 0.03
	grime.fractal_octaves = 4
	var stain := FastNoiseLite.new()
	stain.seed = 23 + seed
	stain.frequency = 0.012
	var r := RandomNumberGenerator.new()
	r.seed = 5 + seed
	# Rain streaks: columns that darken downward from where water gathers.
	var streak := PackedFloat32Array()
	streak.resize(w * h)
	for s in int(40 * a) + 4:
		var x := r.randi_range(0, w - 1)
		var y0 := r.randi_range(0, h - 1)
		var length := r.randi_range(h / 6, h / 2)
		var width := r.randf_range(1.5, 6.0)
		var strength := r.randf_range(0.3, 1.0)
		for dy in length:
			var y := (y0 + dy) % h
			var fade := sin(PI * float(dy) / length) * strength
			var wobble := sin(dy * 0.05 + s) * 1.5
			for dx in range(-int(width) - 2, int(width) + 3):
				var xx := posmod(x + dx + int(wobble), w)
				var k := clampf(1.0 - absf(dx) / width, 0.0, 1.0) * fade
				streak[y * w + xx] = maxf(streak[y * w + xx], k)
	# Seamless noise, so the texture tiles.
	var grime_img := grime.get_seamless_image(w, h)
	var stain_img := stain.get_seamless_image(w, h)
	for y in h:
		for x in w:
			var g := grime_img.get_pixel(x, y).r
			var st := stain_img.get_pixel(x, y).r
			var dark := a * (0.35 * smoothstep(0.35, 0.9, g) + 0.45 * streak[y * w + x])
			var c := Color(1, 1, 1).darkened(dark)
			# Damp and moss: greenish-brown blotches, only when well weathered.
			var damp := smoothstep(0.62, 0.85, st) * smoothstep(0.4, 1.0, a) * 0.5
			c = c.lerp(Color(0.62, 0.66, 0.5), damp)
			img.set_pixel(x, y, c)
	return img
