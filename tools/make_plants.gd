extends SceneTree

# Builds Genesis's plant library from photographed CC0 leaves, needles,
# blades and bark (ambientCG, fetched by tools/fetch_assets.py). Run headless:
#
#     godot --headless --path . -s tools/make_plants.gd [-- name_prefix ...]
#
# Scanned plant models exist (Poly Haven) but weigh 0.8-7.8 million polygons
# each: beautiful alone, impossible to scatter by the hundred. These are built
# the way real-time archviz plants are: wood as tapered tubes, foliage as
# thousands of textured cards, ~10-40k triangles a tree, with automatic LODs.
#
# How each kind grows:
#   broadleaf trees  space colonisation: branches grow toward points filling
#                    the crown's shape (round, spreading, columnar, weeping,
#                    umbrella...), the method production tree tools use, and
#                    get thick by the pipe model (a limb carries the
#                    cross-section of the twigs beyond it). Leaves sit in
#                    clusters on the twigs.
#   conifers         a straight leader with whorls of drooping branches,
#                    shorter toward the top, clad in needle sprigs.
#   palms            a ringed trunk and modelled fronds: feather or fan.
#   shrubs, flowers, grasses   the same pieces at garden scale.
#
# Each leaf card is cut from the atlas automatically: the leaves are found as
# separate shapes in the atlas's opacity and each card is set along its
# leaf, stem to the twig. Flowers, birch bark and palm bark, which no CC0
# scan offers, are drawn here.
#
# Built in Godot rather than Blender because foliage needs material settings
# glTF cannot carry: alpha-scissored cards lit from behind (sun through leaves).

const EXT := "res://genesis_data/external"
const OUT := "res://genesis_assets"
const DATA := "res://genesis_data/plants"

var _rng := RandomNumberGenerator.new()
var _cells := {}   # atlas -> Array of leaf cells {"rect": Rect2 (uv), "sideways": bool}
var _mats := {}


func _init() -> void:
	if not FileAccess.file_exists(EXT + "/atlases/leaves_broad/leaves_broad_Color.jpg"):
		print("No leaf atlases; run tools/fetch_assets.py first. Nothing built.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(DATA)
	var only := Array(OS.get_cmdline_user_args())
	for spec in SPECIES:
		if not only.is_empty() and not only.any(func(p): return str(spec.name).begins_with(p)):
			continue
		var t0 := Time.get_ticks_msec()
		_rng.seed = hash(spec.name)
		_build(spec)
		# Trees also grow VARIANTS more times from other seeds, so a street
		# or a wood of one species isn't a row of clones. They sit in a
		# variants folder beside the tree, out of the library listing; the
		# brush and placement choose among them.
		if spec.kind in ["broadleaf", "conifer", "palm"]:
			for v in range(2, VARIANTS + 1):
				var other: Dictionary = spec.duplicate(true)
				other.name = "%s_v%d" % [spec.name, v]
				other.category = "trees/variants"
				# A different build too: one shorter and broader, one taller and slimmer.
				var tall: float = [0.0, 0.0, 0.9, 1.1][mini(v, 3)]
				var wide: float = [0.0, 0.0, 1.1, 0.9][mini(v, 3)]
				other.height = float(spec.height) * tall
				if spec.has("crown"):
					other.crown = [float(spec.crown[0]) * wide, float(spec.crown[1]) * tall]
				if spec.has("radius"):
					other.radius = float(spec.radius) * wide
				_rng.seed = hash(other.name)
				_build(other)
		print("  (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("plants written")
	quit()


const VARIANTS := 3


func _build(spec: Dictionary) -> void:
	match spec.kind:
		"broadleaf":
			_broadleaf(spec)
		"conifer":
			_conifer(spec)
		"palm":
			_palm(spec)
		"shrub":
			_shrub(spec)
		"topiary":
			_topiary(spec)
		"flowers":
			_flowers(spec)
		"grass":
			_grass(spec)
		"rosette":
			_rosette(spec)
		"potted":
			_potted(spec)


# ---------------------------------------------------------------------------
# The library. Heights in metres. Every tree has a crown `shape`, a leaf
# atlas and a bark; see the builders for what each key does.
# ---------------------------------------------------------------------------
const SPECIES := [
	# Broadleaf trees: summer.
	{"name": "beech", "label": "Beech", "kind": "broadleaf", "height": 14.0, "crown": [7.0, 8.0], "base": 0.25,
		"shape": "round", "atlas": "leaves_broad", "tint": Color(0.8, 0.9, 0.72), "leaf": 0.13, "leaves": 14000, "bark": "bark_smooth_light"},
	{"name": "oak", "label": "Oak, mature", "kind": "broadleaf", "height": 16.0, "crown": [9.0, 8.5], "base": 0.22,
		"shape": "spreading", "atlas": "leaves_oak", "tint": Color(0.75, 0.85, 0.62), "leaf": 0.14, "leaves": 16000, "bark": "bark_oak",
		"gnarl": 0.35, "trunk": 1.35},
	{"name": "oak_young", "label": "Oak, young", "kind": "broadleaf", "height": 8.0, "crown": [4.0, 4.5], "base": 0.3,
		"shape": "round", "atlas": "leaves_oak", "tint": Color(0.78, 0.88, 0.65), "leaf": 0.12, "leaves": 7000, "bark": "bark_oak", "gnarl": 0.2},
	{"name": "maple", "label": "Maple", "kind": "broadleaf", "height": 13.0, "crown": [7.0, 7.5], "base": 0.25,
		"shape": "round", "atlas": "leaves_tree_b", "tint": Color(0.82, 0.9, 0.75), "leaf": 0.15, "leaves": 13000, "bark": "bark_rough_light"},
	{"name": "lime", "label": "Lime (linden)", "kind": "broadleaf", "height": 18.0, "crown": [7.0, 11.0], "base": 0.2,
		"shape": "oval", "atlas": "leaves_green_b", "tint": Color(0.78, 0.9, 0.7), "leaf": 0.12, "leaves": 16000, "bark": "bark_grey_moss"},
	{"name": "plane", "label": "London plane", "kind": "broadleaf", "height": 20.0, "crown": [10.0, 11.0], "base": 0.25,
		"shape": "spreading", "atlas": "leaves_tree_b", "tint": Color(0.75, 0.86, 0.66), "leaf": 0.18, "leaves": 15000, "bark": "bark_plane"},
	{"name": "birch", "label": "Silver birch", "kind": "broadleaf", "height": 13.0, "crown": [4.0, 8.0], "base": 0.25,
		"shape": "oval", "atlas": "leaves_spring", "tint": Color(0.85, 0.95, 0.72), "leaf": 0.07, "leaves": 14000, "bark": "bark_birch",
		"droop": 0.35, "trunk": 0.6},
	{"name": "willow", "label": "Weeping willow", "kind": "broadleaf", "height": 11.0, "crown": [9.0, 7.0], "base": 0.25,
		"shape": "spreading", "atlas": "leaves_mixed", "tint": Color(0.85, 0.95, 0.7), "leaf": 0.1, "leaves": 9000, "bark": "bark_oak",
		"weeping": 1.0, "trunk": 1.2},
	{"name": "poplar", "label": "Lombardy poplar", "kind": "broadleaf", "height": 20.0, "crown": [3.2, 16.0], "base": 0.1,
		"shape": "column", "atlas": "leaves_green_a", "tint": Color(0.8, 0.9, 0.7), "leaf": 0.09, "leaves": 14000, "bark": "bark_grey_moss",
		"upright": 0.8},
	{"name": "cherry_blossom", "label": "Cherry in blossom", "kind": "broadleaf", "height": 7.0, "crown": [6.5, 4.5], "base": 0.3,
		"shape": "vase", "atlas": "blossom_pink", "tint": Color(1, 1, 1), "leaf": 0.4, "leaves": 5000, "bark": "bark_smooth_dark",
		"extra": "leaves_spring", "extra_share": 0.15},
	{"name": "magnolia", "label": "Magnolia in flower", "kind": "broadleaf", "height": 6.0, "crown": [5.0, 4.5], "base": 0.2,
		"shape": "round", "atlas": "blossom_white", "tint": Color(1, 1, 1), "leaf": 0.45, "leaves": 2600, "bark": "bark_smooth_dark"},
	{"name": "olive", "label": "Olive", "kind": "broadleaf", "height": 5.5, "crown": [5.0, 3.6], "base": 0.3,
		"shape": "spreading", "atlas": "leaves_mixed", "tint": Color(0.62, 0.7, 0.62), "leaf": 0.07, "leaves": 11000, "bark": "bark_old",
		"gnarl": 0.6, "trunk": 1.6},
	{"name": "street_tree", "label": "Street tree, young", "kind": "broadleaf", "height": 6.5, "crown": [3.0, 4.0], "base": 0.4,
		"shape": "oval", "atlas": "leaves_green_b", "tint": Color(0.8, 0.9, 0.7), "leaf": 0.1, "leaves": 5000, "bark": "bark_smooth_light", "trunk": 0.8},
	{"name": "young_tree", "label": "Young tree", "kind": "broadleaf", "height": 5.0, "crown": [3.0, 3.2], "base": 0.4,
		"shape": "round", "atlas": "leaves_broad", "tint": Color(0.8, 0.9, 0.72), "leaf": 0.11, "leaves": 4500, "bark": "bark_smooth_light", "trunk": 0.8},
	# Broadleaf trees: autumn and winter.
	{"name": "maple_autumn", "label": "Maple, autumn", "kind": "broadleaf", "height": 13.0, "crown": [7.0, 7.5], "base": 0.25,
		"shape": "round", "atlas": "leaves_maple_autumn", "tint": Color(1, 1, 1), "leaf": 0.15, "leaves": 12000, "bark": "bark_rough_light"},
	{"name": "maple_red", "label": "Maple, autumn red", "kind": "broadleaf", "height": 10.0, "crown": [6.0, 6.0], "base": 0.25,
		"shape": "round", "atlas": "leaves_autumn_red", "tint": Color(1, 1, 1), "leaf": 0.14, "leaves": 11000, "bark": "bark_smooth_dark"},
	{"name": "birch_autumn", "label": "Silver birch, autumn", "kind": "broadleaf", "height": 13.0, "crown": [4.0, 8.0], "base": 0.25,
		"shape": "oval", "atlas": "leaves_autumn_yellow", "tint": Color(1, 1, 1), "leaf": 0.08, "leaves": 11000, "bark": "bark_birch",
		"droop": 0.35, "trunk": 0.6},
	{"name": "oak_winter", "label": "Oak, winter (bare)", "kind": "broadleaf", "height": 16.0, "crown": [9.0, 8.5], "base": 0.22,
		"shape": "spreading", "atlas": "", "leaf": 0.0, "leaves": 0, "bark": "bark_oak", "gnarl": 0.35, "trunk": 1.35, "twiggy": true},
	{"name": "birch_winter", "label": "Silver birch, winter (bare)", "kind": "broadleaf", "height": 13.0, "crown": [4.0, 8.0], "base": 0.25,
		"shape": "oval", "atlas": "", "leaf": 0.0, "leaves": 0, "bark": "bark_birch", "droop": 0.35, "trunk": 0.6, "twiggy": true},
	# Conifers.
	{"name": "spruce", "label": "Spruce", "kind": "conifer", "height": 16.0, "radius": 3.2, "base": 0.08, "atlas": "needles",
		"tint": Color(0.5, 0.66, 0.5), "sprig": 1.0, "bark": "bark_fir", "droop": 0.35},
	{"name": "fir_young", "label": "Fir, young (Christmas tree)", "kind": "conifer", "height": 4.0, "radius": 1.3, "base": 0.05,
		"atlas": "needles", "tint": Color(0.55, 0.72, 0.52), "sprig": 0.55, "bark": "bark_fir", "droop": 0.15},
	{"name": "cypress", "label": "Italian cypress", "kind": "conifer", "height": 14.0, "radius": 1.0, "base": 0.03, "atlas": "needles",
		"tint": Color(0.42, 0.55, 0.42), "sprig": 0.7, "bark": "bark_fir", "droop": -0.5, "column": true},
	{"name": "pine", "label": "Scots pine", "kind": "broadleaf", "height": 18.0, "crown": [9.5, 6.0], "base": 0.58,
		"shape": "pads", "atlas": "pine_tufts", "tint": Color(1, 1, 1), "leaf": 0.9, "leaves": 3200, "bark": "bark_old",
		"gnarl": 0.3, "tufts": true},
	{"name": "stone_pine", "label": "Stone pine (umbrella pine)", "kind": "broadleaf", "height": 14.0, "crown": [12.0, 4.5], "base": 0.62,
		"shape": "umbrella", "atlas": "pine_tufts", "tint": Color(1, 1, 1), "leaf": 1.0, "leaves": 4200, "bark": "bark_old",
		"gnarl": 0.4, "tufts": true, "trunk": 1.2},
	# Palms.
	{"name": "palm_coconut", "label": "Coconut palm", "kind": "palm", "height": 11.0, "lean": 0.18, "fronds": 16, "frond": 4.2,
		"style": "feather", "bark": "bark_palm"},
	{"name": "palm_date", "label": "Date palm", "kind": "palm", "height": 8.0, "lean": 0.02, "fronds": 26, "frond": 4.0,
		"style": "feather", "bark": "bark_palm", "thick": 0.36, "stiff": 0.6},
	{"name": "palm_fan", "label": "Fan palm (Washingtonia)", "kind": "palm", "height": 15.0, "lean": 0.03, "fronds": 34, "frond": 2.4,
		"style": "fan", "bark": "bark_palm", "thick": 0.2, "skirt": 3.2},
	# Shrubs.
	{"name": "round_shrub", "label": "Shrub, round", "kind": "shrub", "height": 0.9, "width": 1.2, "atlas": "leaves_broad",
		"tint": Color(0.75, 0.85, 0.68), "leaf": 0.07, "leaves": 1800},
	{"name": "shrub_large", "label": "Shrub, large", "kind": "shrub", "height": 2.2, "width": 2.6, "atlas": "leaves_green_a",
		"tint": Color(0.72, 0.85, 0.66), "leaf": 0.08, "leaves": 5000},
	{"name": "hedge_shrub", "label": "Hedge, 2 m section", "kind": "topiary", "form": "hedge", "size": Vector3(2.0, 1.4, 0.8),
		"atlas": "leaves_small", "tint": Color(0.7, 0.82, 0.62), "leaf": 0.05},
	{"name": "hedge_tall", "label": "Hedge, tall, 2 m section", "kind": "topiary", "form": "hedge", "size": Vector3(2.0, 2.4, 1.0),
		"atlas": "leaves_small", "tint": Color(0.68, 0.8, 0.6), "leaf": 0.05},
	{"name": "box_ball", "label": "Box ball (topiary)", "kind": "topiary", "form": "ball", "size": Vector3(0.9, 0.9, 0.9),
		"atlas": "leaves_small", "tint": Color(0.66, 0.8, 0.55), "leaf": 0.035},
	{"name": "box_cone", "label": "Box cone (topiary)", "kind": "topiary", "form": "cone", "size": Vector3(0.8, 1.6, 0.8),
		"atlas": "leaves_small", "tint": Color(0.66, 0.8, 0.55), "leaf": 0.035},
	{"name": "rose_bush", "label": "Rose bush, red", "kind": "shrub", "height": 1.1, "width": 1.0, "atlas": "leaves_spring",
		"tint": Color(0.62, 0.78, 0.55), "leaf": 0.05, "leaves": 2400, "flowers": "roses_red", "flower_count": 60, "flower": 0.09},
	{"name": "rose_bush_pink", "label": "Rose bush, pink", "kind": "shrub", "height": 1.0, "width": 1.0, "atlas": "leaves_spring",
		"tint": Color(0.62, 0.78, 0.55), "leaf": 0.05, "leaves": 2400, "flowers": "roses_pink", "flower_count": 60, "flower": 0.09},
	{"name": "hydrangea", "label": "Hydrangea", "kind": "shrub", "height": 1.2, "width": 1.4, "atlas": "leaves_green_a",
		"tint": Color(0.7, 0.85, 0.62), "leaf": 0.09, "leaves": 1600, "flowers": "hydrangea_blue", "flower_count": 30, "flower": 0.22},
	{"name": "lavender", "label": "Lavender", "kind": "flowers", "height": 0.55, "width": 0.7, "stems": 160, "head": "lavender", "grass": 40,
		"blade_atlas": "grass_strands", "tint": Color(0.62, 0.7, 0.58)},
	{"name": "tulips_red", "label": "Tulips, red (bed, 1 m²)", "kind": "flowers", "height": 0.4, "width": 1.0, "stems": 60, "head": "tulip_red",
		"blade_atlas": "plants", "tint": Color(0.65, 0.8, 0.55), "bed": true},
	{"name": "tulips_yellow", "label": "Tulips, yellow (bed, 1 m²)", "kind": "flowers", "height": 0.4, "width": 1.0, "stems": 60,
		"head": "tulip_yellow", "blade_atlas": "plants", "tint": Color(0.65, 0.8, 0.55), "bed": true},
	{"name": "wildflowers", "label": "Wildflower meadow (1 m²)", "kind": "flowers", "height": 0.5, "width": 1.0, "stems": 70, "head": "wild",
		"blade_atlas": "weeds_a", "tint": Color(0.8, 0.9, 0.7), "bed": true, "grass": 90},
	{"name": "fern", "label": "Fern", "kind": "rosette", "height": 0.7, "count": 14, "length": 0.75, "atlas": "needles",
		"tint": Color(0.75, 1.0, 0.6), "arch": 0.5},
	{"name": "hosta", "label": "Hosta", "kind": "rosette", "height": 0.5, "count": 18, "length": 0.5, "atlas": "leaves_green_b",
		"tint": Color(0.65, 0.85, 0.6), "arch": 0.25, "broad": true},
	{"name": "agave", "label": "Agave", "kind": "rosette", "height": 0.9, "count": 26, "length": 0.8, "atlas": "",
		"tint": Color(0.45, 0.6, 0.6), "arch": 0.1, "solid": true},
	{"name": "dandelion", "label": "Dandelion", "kind": "rosette", "height": 0.1, "count": 10, "length": 0.18, "atlas": "dandelion",
		"tint": Color(0.85, 0.95, 0.75), "arch": 0.05, "flat": true},
	# Grasses.
	{"name": "meadow_grass", "label": "Meadow grass", "kind": "grass", "atlas": "grass_blades", "count": 26, "height": [0.3, 0.55],
		"tint": Color(0.92, 1.0, 0.85)},
	{"name": "lawn_clump", "label": "Lawn clump", "kind": "grass", "atlas": "lawn_blades", "count": 40, "height": [0.08, 0.14],
		"tint": Color(0.85, 1.0, 0.8)},
	{"name": "wild_grass", "label": "Wild grass with seed heads", "kind": "grass", "atlas": "weeds_a", "count": 18, "height": [0.5, 0.9],
		"tint": Color(0.95, 1.0, 0.85), "whole": true},
	{"name": "ornamental_grass", "label": "Ornamental grass", "kind": "grass", "atlas": "grass_strands", "count": 70, "height": [0.7, 1.1],
		"tint": Color(0.85, 0.95, 0.75), "spread": 0.18, "arch": 0.35},
	{"name": "pampas_grass", "label": "Pampas grass", "kind": "grass", "atlas": "grass_strands", "count": 90, "height": [1.1, 1.6],
		"tint": Color(0.8, 0.9, 0.7), "spread": 0.25, "arch": 0.45, "plumes": 14},
	{"name": "reeds", "label": "Reeds", "kind": "grass", "atlas": "weeds_c", "count": 40, "height": [1.2, 1.8], "tint": Color(0.9, 0.95, 0.8),
		"whole": true, "spread": 0.3},
	# Potted, for terraces, lobbies and events.
	{"name": "potted_olive", "label": "Olive in a planter", "kind": "potted", "plant": "olive", "pot": "box", "scale": 0.45},
	{"name": "potted_palm", "label": "Palm in a pot", "kind": "potted", "plant": "palm_date", "pot": "round", "scale": 0.3},
	{"name": "potted_box_ball", "label": "Box ball in a pot", "kind": "potted", "plant": "box_ball", "pot": "round", "scale": 0.8},
	{"name": "potted_bay_cone", "label": "Topiary cone in a planter", "kind": "potted", "plant": "box_cone", "pot": "box", "scale": 0.9},
]


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

func _foliage(atlas: String, tint: Color) -> StandardMaterial3D:
	var key := "%s_%s" % [atlas, tint.to_html(false)]
	if _mats.has(key):
		return _mats[key]
	var rgba_path := _atlas_rgba(atlas)
	var m := StandardMaterial3D.new()
	m.resource_name = atlas
	m.albedo_texture = _ref(rgba_path)
	m.albedo_color = tint
	# Each card carries its own shade: leaves are never all one green.
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var normal := "%s/atlases/%s/%s_NormalGL.jpg" % [EXT, atlas, atlas]
	if FileAccess.file_exists(normal):
		_import_settings(normal, true)
		m.normal_enabled = true
		m.normal_texture = _ref(normal)
		m.normal_scale = 0.5
	m.roughness = 0.65
	# Sun through the leaves: what makes a canopy glow instead of looking
	# like painted cardboard.
	m.backlight_enabled = true
	m.backlight = Color(0.18, 0.24, 0.06) if not atlas.begins_with("blossom") else Color(0.25, 0.18, 0.2)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var path := "%s/%s.tres" % [DATA, key]
	ResourceSaver.save(m, path)
	_mats[key] = load(path)
	return _mats[key]


# The atlas as one RGBA PNG (colour and opacity arrive as separate JPGs, or
# are drawn here for flowers).
func _atlas_rgba(atlas: String) -> String:
	var rgba_path := "%s/%s_rgba.png" % [DATA, atlas]
	if FileAccess.file_exists(rgba_path):
		return rgba_path
	var img: Image
	if atlas in DRAWN_ATLASES:
		img = _draw_atlas(atlas)
	else:
		var stem := "%s/atlases/%s/%s" % [EXT, atlas, atlas]
		img = Image.load_from_file(ProjectSettings.globalize_path(stem + "_Color.jpg"))
		var alpha := Image.load_from_file(ProjectSettings.globalize_path(stem + "_Opacity.jpg"))
		img.convert(Image.FORMAT_RGBA8)
		alpha.convert(Image.FORMAT_L8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				c.a = alpha.get_pixel(x, y).r
				img.set_pixel(x, y, c)
	img.save_png(ProjectSettings.globalize_path(rgba_path))
	_import_settings(rgba_path, false)
	return rgba_path


func _bark(name: String) -> StandardMaterial3D:
	var key := "bark_" + name
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.roughness = 1.0
	if name in ["bark_birch", "bark_palm", "bark_plane"]:
		var path := "%s/%s.png" % [DATA, name]
		if not FileAccess.file_exists(path):
			_draw_bark(name).save_png(ProjectSettings.globalize_path(path))
			_import_settings(path, false)
		m.albedo_texture = _ref(path)
		m.roughness = 0.85
	else:
		var stem := "%s/barks/%s/%s" % [EXT, name, name]
		if not FileAccess.file_exists(stem + "_Color.jpg"):
			stem = EXT + "/materials/bark/bark"
		if FileAccess.file_exists(stem + "_Color.jpg"):
			_import_settings(stem + "_Color.jpg", false)
			_import_settings(stem + "_NormalGL.jpg", true)
			m.albedo_texture = _ref(stem + "_Color.jpg")
			m.normal_enabled = true
			m.normal_texture = _ref(stem + "_NormalGL.jpg")
			if FileAccess.file_exists(stem + "_Roughness.jpg"):
				_import_settings(stem + "_Roughness.jpg", false)
				m.roughness_texture = _ref(stem + "_Roughness.jpg")
				m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		else:
			m.albedo_color = Color(0.3, 0.24, 0.18)
	# One repeat of bark every 1.2 m around and along.
	m.uv1_scale = Vector3(1.0 / 1.2, 1.0 / 1.2, 1.0)
	var path := "%s/%s.tres" % [DATA, key]
	ResourceSaver.save(m, path)
	_mats[key] = load(path)
	return _mats[key]


func _plain(name: String, colour: Color, roughness := 0.8) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = colour
	m.roughness = roughness
	m.vertex_color_use_as_albedo = true
	# The colours written here are the colours meant (sRGB), not linear.
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var path := "%s/%s.tres" % [DATA, name]
	ResourceSaver.save(m, path)
	_mats[name] = load(path)
	return _mats[name]


var _refs := {}


# A texture by path, for the material to load when it is used (the images
# may not be imported yet while this runs).
func _ref(path: String) -> Texture2D:
	if not _refs.has(path):
		var t := PlaceholderTexture2D.new()
		t.resource_path = path
		_refs[path] = t
	return _refs[path]


func _import_settings(file: String, normal_map: bool) -> void:
	if FileAccess.get_file_as_string(file + ".import").contains("detect_3d/compress_to=0"):
		return
	var f := FileAccess.open(file + ".import", FileAccess.WRITE)
	f.store_string("\n".join([
		"[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "",
		"[params]", "", "compress/mode=2",
		"compress/normal_map=%d" % (1 if normal_map else 2),
		"mipmaps/generate=true", "detect_3d/compress_to=0", ""]))
	f.close()


# ---------------------------------------------------------------------------
# Finding the leaves in an atlas
# ---------------------------------------------------------------------------

# Each separate shape in the atlas's opacity is a leaf (or a sprig, a blade).
# Returns cells with their UV rectangle; a cell wider than it is tall lies on
# its side, stem on the left (as every such atlas in the set is laid out).
func cells(atlas: String) -> Array:
	if _cells.has(atlas):
		return _cells[atlas]
	var img := Image.load_from_file(ProjectSettings.globalize_path(_atlas_rgba(atlas)))
	var w := 256
	var h := int(256.0 * img.get_height() / img.get_width())
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if img.get_pixel(x, y).a > 0.25 else 0
	# Grow each shape by two pixels so a thin stem stays joined to its leaf.
	var grown := solid.duplicate()
	for y in h:
		for x in w:
			if solid[y * w + x] == 0:
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < w and yy < h:
						grown[yy * w + xx] = 1
	var label := PackedInt32Array()
	label.resize(w * h)
	var out: Array = []
	var stack := PackedInt32Array()
	for start in w * h:
		if grown[start] == 0 or label[start] != 0:
			continue
		var id := out.size() + 1
		var lo := Vector2i(w, h)
		var hi := Vector2i(-1, -1)
		var area := 0
		stack.clear()
		stack.append(start)
		label[start] = id
		while not stack.is_empty():
			var p := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var px := p % w
			var py := p / w
			area += 1
			lo = Vector2i(mini(lo.x, px), mini(lo.y, py))
			hi = Vector2i(maxi(hi.x, px), maxi(hi.y, py))
			for n in [p - 1, p + 1, p - w, p + w]:
				if n >= 0 and n < w * h and grown[n] == 1 and label[n] == 0 and absi((n % w) - px) <= 1:
					label[n] = id
					stack.append(n)
		if area < w * h * 0.002:
			continue
		var rect := Rect2(float(lo.x) / w, float(lo.y) / h, float(hi.x - lo.x + 1) / w, float(hi.y - lo.y + 1) / h)
		out.append({"rect": rect, "sideways": rect.size.x * img.get_width() > rect.size.y * img.get_height() * 1.25,
			"aspect": (rect.size.x * img.get_width()) / maxf(rect.size.y * img.get_height(), 1.0)})
	if out.is_empty():
		out.append({"rect": Rect2(0, 0, 1, 1), "sideways": false, "aspect": 1.0})
	_cells[atlas] = out
	print("atlas %s: %d leaves" % [atlas, out.size()])
	return out


# ---------------------------------------------------------------------------
# Sprays: twigs dressed with an atlas's real leaves
# ---------------------------------------------------------------------------

# One card per leaf cannot fill a big crown; one card per leafy twig can.
# From a leaf atlas this draws four twigs, each carrying 12-18 of its leaves
# turned along it and alternating side to side, as they grow. The result is
# itself an atlas (2 x 2, stems at the bottom), used like any other.
func _spray(atlas: String) -> String:
	var name := "spray_" + atlas
	var rgba_path := "%s/%s_rgba.png" % [DATA, name]
	if not _cells.has(name):
		var q := []
		for cy in 2:
			for cx in 2:
				q.append({"rect": Rect2(cx * 0.5 + 0.01, cy * 0.5 + 0.01, 0.48, 0.48), "sideways": false, "aspect": 1.0})
		_cells[name] = q
	if FileAccess.file_exists(rgba_path):
		return name
	var src := Image.load_from_file(ProjectSettings.globalize_path(_atlas_rgba(atlas)))
	var leaves := cells(atlas)
	var size := 1024
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = hash(name)
	for cy in 2:
		for cx in 2:
			var o := Vector2(cx * 512, cy * 512)
			var base := o + Vector2(256 + r.randf_range(-20, 20), 505)
			var tip := o + Vector2(256 + r.randf_range(-70, 70), 70)
			var bend := Vector2(r.randf_range(-60, 60), 0)
			var twig: Array = []
			for k in 21:
				var t := k / 20.0
				twig.append(base.lerp(tip, t) + bend * sin(t * PI))
			for k in 20:
				_line(img, twig[k], twig[k + 1], lerpf(4.5, 1.5, k / 20.0), Color(0.3, 0.24, 0.16))
			# Thin leaves (needles, willow) need many more to a twig to read.
			var thin := 0.0
			for c in leaves:
				thin += maxf(c.aspect, 1.0 / c.aspect)
			thin /= leaves.size()
			var n := int(r.randi_range(12, 18) * clampf(thin / 2.5, 1.0, 4.0))
			for i in n:
				var t := lerpf(0.12, 1.0, float(i) / (n - 1))
				var k := clampi(int(t * 20.0), 1, 20)
				var at: Vector2 = twig[k]
				var along: Vector2 = (twig[k] - twig[k - 1]).normalized()
				var sidev := 1.0 if i % 2 == 0 else -1.0
				var ang := r.randf_range(0.5, 1.05) * sidev
				if i == n - 1:
					ang = 0.0   # the leader leaf, straight on
				var dir := along.rotated(-ang)
				var cell: Dictionary = leaves[r.randi() % leaves.size()]
				var length := r.randf_range(150, 205) * lerpf(1.0, 0.7, t) * (0.8 if n > 30 else 1.0)
				_blit_leaf(img, src, cell, at, dir, length, r.randf_range(0.8, 1.0))
	img.save_png(ProjectSettings.globalize_path(rgba_path))
	_import_settings(rgba_path, false)
	return name


func _line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		_disc(img, p, width * 0.5, c)


# Draws one leaf from the source atlas onto the spray: stem at `at`, running
# along `dir` for `length` pixels, shaded by `shade`.
func _blit_leaf(img: Image, src: Image, cell: Dictionary, at: Vector2, dir: Vector2, length: float, shade: float) -> void:
	var rect: Rect2 = cell.rect
	var sw := src.get_width()
	var sh := src.get_height()
	var aspect: float = cell.aspect
	var long := maxf(aspect, 1.0 / aspect)
	var width := length / long
	var side := Vector2(-dir.y, dir.x)
	var corners := [at + side * width * 0.5, at - side * width * 0.5, at + dir * length + side * width * 0.5, at + dir * length - side * width * 0.5]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in corners:
		lo = lo.min(c)
		hi = hi.max(c)
	for y in range(maxi(int(lo.y), 0), mini(int(hi.y) + 1, img.get_height())):
		for x in range(maxi(int(lo.x), 0), mini(int(hi.x) + 1, img.get_width())):
			var d := Vector2(x, y) - at
			var a := d.dot(dir) / length          # 0 at the stem, 1 at the tip
			var b := d.dot(side) / width + 0.5    # 0..1 across
			if a < 0.0 or a > 1.0 or b < 0.0 or b > 1.0:
				continue
			var u: float
			var v: float
			if cell.sideways:
				u = rect.position.x + a * rect.size.x
				v = rect.position.y + b * rect.size.y
			else:
				u = rect.position.x + b * rect.size.x
				v = rect.end.y - a * rect.size.y
			var s := src.get_pixel(clampi(int(u * sw), 0, sw - 1), clampi(int(v * sh), 0, sh - 1))
			if s.a < 0.05:
				continue
			var under := img.get_pixel(x, y)
			var col := Color(s.r * shade, s.g * shade, s.b * shade)
			var out := under.lerp(col, s.a)
			out.a = maxf(under.a, s.a)
			img.set_pixel(x, y, out)


# ---------------------------------------------------------------------------
# Drawn atlases and barks (what no CC0 scan offers)
# ---------------------------------------------------------------------------
const DRAWN_ATLASES := ["blossom_pink", "blossom_white", "roses_red", "roses_pink", "hydrangea_blue", "lavender",
	"tulip_red", "tulip_yellow", "wild", "palm_leaflet", "plume", "pine_tufts"]


func _draw_atlas(atlas: String) -> Image:
	var size := 1024
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = hash(atlas)
	match atlas:
		"blossom_pink", "blossom_white":
			# 3 x 3 cells, each a sprig of blossoms: five-petalled flowers
			# clustered along a twig, pink or white with a darker eye.
			var petal := Color(0.97, 0.62, 0.78) if atlas == "blossom_pink" else Color(0.98, 0.95, 0.93)
			var edge := Color(0.88, 0.35, 0.58) if atlas == "blossom_pink" else Color(0.85, 0.55, 0.7)
			for cx in 3:
				for cy in 3:
					var o := Vector2(cx * 341 + 170, cy * 341 + 170)
					for f in 5 + r.randi() % 3:
						var at := o + Vector2(r.randf_range(-110, 110), r.randf_range(-120, 110))
						var fr := r.randf_range(38, 58) if atlas == "blossom_pink" else r.randf_range(60, 95)
						if atlas == "blossom_white":
							_tulip_cup(img, at, fr, petal, edge)
						else:
							_flower(img, at, fr, 5, petal, edge, Color(0.8, 0.3, 0.4))
		"roses_red", "roses_pink", "hydrangea_blue":
			var base := {"roses_red": Color(0.75, 0.05, 0.1), "roses_pink": Color(0.95, 0.55, 0.7),
				"hydrangea_blue": Color(0.45, 0.55, 0.95)}[atlas] as Color
			for cx in 3:
				for cy in 3:
					var o := Vector2(cx * 341 + 170, cy * 341 + 170)
					if atlas == "hydrangea_blue":
						for f in 40:
							var at := o + Vector2(r.randf_range(-1, 1), r.randf_range(-1, 1)).limit_length(1.0) * 130
							_flower(img, at, r.randf_range(22, 30), 4, base.lightened(r.randf_range(0, 0.3)), base.darkened(0.2), base.darkened(0.4))
					else:
						_rose(img, o, 140, base)
		"lavender":
			# Tall spikes of tiny purple florets on a grey-green stalk.
			for s in 8:
				var x := 64 + s * 128
				img.fill_rect(Rect2i(x - 3, 300, 6, 724), Color(0.45, 0.52, 0.4))
				for k in 38:
					var y := 60 + k * 7
					for side in [-1, 1]:
						_disc(img, Vector2(x + side * r.randf_range(6, 16), y + r.randf_range(-3, 3)), r.randf_range(8, 12),
							Color(0.52, 0.42, 0.78).darkened(r.randf_range(0, 0.25)))
		"tulip_red", "tulip_yellow":
			var c := Color(0.85, 0.08, 0.1) if atlas == "tulip_red" else Color(0.98, 0.82, 0.1)
			for cx in 3:
				for cy in 3:
					_tulip_cup(img, Vector2(cx * 341 + 170, cy * 341 + 190), 120, c, c.darkened(0.3))
		"wild":
			# Daisies, poppies, cornflowers, buttercups.
			var kinds := [[Color(1, 1, 1), Color(1, 0.8, 0.1), 12], [Color(0.85, 0.1, 0.1), Color(0.1, 0.05, 0.05), 5],
				[Color(0.3, 0.45, 0.95), Color(0.2, 0.2, 0.6), 8], [Color(1, 0.88, 0.1), Color(0.9, 0.7, 0.05), 5]]
			for cx in 3:
				for cy in 3:
					var k: Array = kinds[(cx + cy * 3) % kinds.size()]
					_flower(img, Vector2(cx * 341 + 170, cy * 341 + 170), 120, k[2], k[0], k[0].darkened(0.15), k[1])
		"pine_tufts":
			# Pine shoots: a twig with bursts of needles all along it, the
			# needles drawn thick enough to survive being seen from afar
			# (real ones, a pixel wide in a scan, vanish at any distance).
			for cy in 2:
				for cx in 2:
					var o := Vector2(cx * 512, cy * 512)
					var base := o + Vector2(256, 500)
					var tip := o + Vector2(256 + r.randf_range(-40, 40), 90)
					_line(img, base, tip, 5.0, Color(0.4, 0.28, 0.16))
					for k in 14:
						var t := lerpf(0.15, 1.0, k / 13.0)
						var at := base.lerp(tip, t)
						var along := (tip - base).normalized()
						for nn in 26:
							var ang := r.randf_range(-1.1, 1.1)
							var dir := along.rotated(ang)
							var length := r.randf_range(55, 95) * lerpf(1.0, 0.75, t)
							var c := Color(0.16, 0.27, 0.12).lerp(Color(0.26, 0.38, 0.18), r.randf())
							_line(img, at, at + dir * length, 3.2, c)
		"plume":
			# Feathery cream plumes (pampas).
			for s in 4:
				var x := 128 + s * 256
				for k in 900:
					var t := r.randf()
					var y := 60 + t * 900
					var spread := sin(t * PI) * 80 + 10
					_disc(img, Vector2(x + r.randf_range(-spread, spread), y), r.randf_range(3, 6),
						Color(0.95, 0.9, 0.78, 0.9).darkened(r.randf_range(0, 0.15)))
	return img


func _disc(img: Image, at: Vector2, radius: float, c: Color) -> void:
	var rr := int(ceil(radius))
	for y in range(-rr, rr + 1):
		for x in range(-rr, rr + 1):
			var d := Vector2(x, y).length() / radius
			if d > 1.0:
				continue
			var px := int(at.x) + x
			var py := int(at.y) + y
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			var shade := c.darkened(d * 0.15)
			shade.a = c.a
			img.set_pixel(px, py, shade)


func _flower(img: Image, at: Vector2, radius: float, petals: int, petal: Color, edge: Color, eye: Color) -> void:
	for p in petals:
		var a := TAU * p / petals
		var dir := Vector2(cos(a), sin(a))
		for k in 10:
			var t := k / 9.0
			_disc(img, at + dir * radius * (0.25 + 0.5 * t), radius * (0.18 + 0.22 * sin(t * PI)), petal.lerp(edge, t * 0.6))
	_disc(img, at, radius * 0.18, eye)


func _rose(img: Image, at: Vector2, radius: float, c: Color) -> void:
	# Rings of overlapping petals, darker toward the heart.
	for ring in 5:
		var rr := radius * (1.0 - ring * 0.18)
		var n := 9 - ring
		for p in n:
			var a := TAU * p / n + ring * 0.6
			_disc(img, at + Vector2(cos(a), sin(a)) * rr * 0.45, rr * 0.42, c.darkened(ring * 0.1).lightened(0.1 if ring == 0 else 0.0))
	_disc(img, at, radius * 0.15, c.darkened(0.45))


func _tulip_cup(img: Image, at: Vector2, radius: float, c: Color, edge: Color) -> void:
	# A closed cup of petals seen from the side.
	for p in 3:
		var x := (p - 1) * radius * 0.35
		for k in 14:
			var t := k / 13.0
			_disc(img, at + Vector2(x, radius * 0.55 - t * radius * 1.1), radius * (0.3 + 0.12 * sin(t * PI)), c.lerp(edge, 1.0 - t))


func _draw_bark(name: String) -> Image:
	var w := 512
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = hash(name)
	var noise := FastNoiseLite.new()
	noise.seed = hash(name)
	noise.frequency = 0.02
	match name:
		"bark_birch":
			# Chalk white, with dark horizontal lenticels and black patches.
			for y in h:
				for x in w:
					var n := noise.get_noise_2d(x * 0.5, y * 3.0)
					img.set_pixel(x, y, Color(0.9, 0.89, 0.85).darkened(0.08 + n * 0.08))
			for k in 260:
				var y := r.randi() % h
				var x := r.randi() % w
				var len := r.randi_range(10, 60)
				img.fill_rect(Rect2i(x, y, len, r.randi_range(2, 4)), Color(0.18, 0.16, 0.15))
			for k in 18:
				var cx := r.randi() % w
				var cy := r.randi() % h
				for j in 120:
					var p := Vector2i(cx + r.randi_range(-30, 30), cy + r.randi_range(-10, 10))
					if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h:
						img.set_pixel(p.x, p.y, Color(0.12, 0.11, 0.1))
		"bark_plane":
			# The London plane's camouflage: grey, olive and cream flakes.
			var cols := [Color(0.62, 0.6, 0.5), Color(0.75, 0.72, 0.58), Color(0.5, 0.52, 0.42), Color(0.85, 0.82, 0.68)]
			for y in h:
				for x in w:
					var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
					img.set_pixel(x, y, cols[clampi(int(n * 4.0), 0, 3)])
		"bark_palm":
			# Ringed: the scars of old fronds, every few centimetres.
			for y in h:
				var ring := 0.5 + 0.5 * cos(y * TAU / 32.0)
				for x in w:
					var n := noise.get_noise_2d(x * 2.0, y * 0.5)
					img.set_pixel(x, y, Color(0.5, 0.44, 0.36).darkened(ring * 0.3 + n * 0.1))
	return img


# ---------------------------------------------------------------------------
# Broadleaf trees: space colonisation
# ---------------------------------------------------------------------------

# Points filling the crown, for the branches to grow toward.
func _crown_points(spec: Dictionary, count: int) -> PackedVector3Array:
	var height: float = spec.height
	var cw: float = spec.crown[0]
	var base := height * float(spec.base)
	# The crown runs from where it starts to the top of the tree.
	var ch := height - base
	var top := height
	var pts := PackedVector3Array()
	var shape: String = spec.shape
	# Spreading crowns are a few overlapping lobes, not one ellipsoid.
	var lobes: Array = []
	if shape == "spreading":
		for i in 5:
			var a := TAU * i / 5.0 + _rng.randf_range(-0.3, 0.3)
			lobes.append([Vector3(cos(a) * cw * 0.22, base + ch * _rng.randf_range(0.45, 0.6), sin(a) * cw * 0.22), cw * 0.34, ch * 0.42])
		lobes.append([Vector3(0, base + ch * 0.65, 0), cw * 0.3, ch * 0.35])
	# An old pine's crown: flat clouds of needles at different heights, each
	# off to its own side, with a broad flat-topped one crowning it.
	if shape == "pads":
		var n := 4
		var a0 := _rng.randf() * TAU
		for i in n:
			var t := lerpf(0.1, 0.62, float(i) / (n - 1)) + _rng.randf_range(-0.04, 0.04)
			# Round the trunk, a pad to each side in turn.
			var a := a0 + i * 2.2 + _rng.randf_range(-0.4, 0.4)
			var reach := cw * lerpf(0.36, 0.2, t) * _rng.randf_range(0.8, 1.1)
			lobes.append([Vector3(cos(a) * reach, base + ch * t, sin(a) * reach), cw * 0.22, ch * 0.08])
		lobes.append([Vector3(_rng.randf_range(-0.08, 0.08) * cw, base + ch * 0.86, _rng.randf_range(-0.08, 0.08) * cw), cw * 0.36, ch * 0.13])
	var tries := 0
	while pts.size() < count and tries < count * 40:
		tries += 1
		var p := Vector3(_rng.randf_range(-0.5, 0.5) * cw, _rng.randf_range(base, top), _rng.randf_range(-0.5, 0.5) * cw)
		var t := (p.y - base) / ch
		var rad := Vector2(p.x, p.z).length() / (cw * 0.5)
		var inside := false
		match shape:
			"round":
				inside = Vector2(rad, (t - 0.5) * 2.0).length() < 1.0
			"oval":
				inside = Vector2(rad, (t - 0.5) * 2.0).length() < 1.0 and rad < sin(clampf(t, 0.02, 1.0) * PI) * 1.05
			"column":
				inside = rad < sin(clampf(t, 0.0, 1.0) * PI) * 0.9 + 0.1 and t < 0.98
			"vase":
				inside = rad < lerpf(0.35, 1.0, t) and Vector2(rad, (t - 0.55) * 2.2).length() < 1.2
			"umbrella":
				inside = rad < 1.0 and t > 0.25 and t < 1.0 - rad * rad * 0.55
			"spreading", "pads":
				for l in lobes:
					var d: Vector3 = p - l[0]
					if Vector3(d.x / l[1], d.y / l[2], d.z / l[1]).length() < 1.0:
						inside = true
		if inside:
			pts.append(p)
	return pts


class Skeleton:
	var pos := PackedVector3Array()
	var parent := PackedInt32Array()
	var radius := PackedFloat32Array()
	var kids: Array = []   # indices of children per node


func _grow(spec: Dictionary) -> Skeleton:
	var tree := Skeleton.new()
	var height: float = spec.height
	var base := height * float(spec.base)
	# A fine step and a dense cloud of points: many branches, many twigs.
	var step := clampf(height / 60.0, 0.08, 0.28)
	var influence := step * 9.0
	var kill := step * 1.6
	var points := _crown_points(spec, int(clampf(height * height * 22.0, 1200, 7000)))
	# The trunk: up to where the crown begins, wandering a little.
	var gnarl := float(spec.get("gnarl", 0.1))
	var p := Vector3.ZERO
	tree.pos.append(p)
	tree.parent.append(-1)
	var dir := Vector3(_rng.randf_range(-0.04, 0.04), 1, _rng.randf_range(-0.04, 0.04)).normalized()
	while p.y < base + step:
		dir = (dir + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * gnarl * 0.15).normalized()
		dir.y = maxf(dir.y, 0.7)
		dir = dir.normalized()
		p += dir * step
		tree.pos.append(p)
		tree.parent.append(tree.pos.size() - 2)
	# Colonise.
	var alive := points
	var up := float(spec.get("upright", 0.0))
	for iter in 400:
		if alive.is_empty():
			break
		var grid := _hash(tree.pos, influence)
		var pull := {}
		var dead := PackedInt32Array()
		for ai in alive.size():
			var a := alive[ai]
			var best := -1
			var best_d := influence
			var cell := Vector3i((a / influence).floor())
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for dz in range(-1, 2):
						for ni in grid.get(cell + Vector3i(dx, dy, dz), []):
							var d := a.distance_to(tree.pos[ni])
							if d < best_d:
								best_d = d
								best = ni
			if best < 0:
				continue
			if best_d < kill:
				dead.append(ai)
				continue
			pull[best] = pull.get(best, Vector3.ZERO) + (a - tree.pos[best]).normalized()
		if pull.is_empty():
			break
		for ni in pull:
			var d: Vector3 = (pull[ni] as Vector3).normalized()
			d += Vector3.UP * (0.08 + up) + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * gnarl * 0.3
			var np: Vector3 = tree.pos[ni] + d.normalized() * step
			tree.pos.append(np)
			tree.parent.append(ni)
		var keep := PackedVector3Array()
		var dead_set := {}
		for i in dead:
			dead_set[i] = true
		for ai in alive.size():
			if not dead_set.has(ai):
				keep.append(alive[ai])
		alive = keep
		if pull.size() < 2 and dead.is_empty() and iter > 60:
			break
	# Children lists and the pipe model's radii, from the tips down.
	var n := tree.pos.size()
	tree.kids.resize(n)
	for i in n:
		tree.kids[i] = []
	for i in range(1, n):
		tree.kids[tree.parent[i]].append(i)
	tree.radius.resize(n)
	var tip := clampf(height * 0.0012, 0.004, 0.012)
	for i in range(n - 1, -1, -1):
		var kids: Array = tree.kids[i]
		if kids.is_empty():
			tree.radius[i] = tip
		else:
			var s := 0.0
			for k in kids:
				s += pow(tree.radius[k], 2.4)
			tree.radius[i] = pow(s, 1.0 / 2.4)
	# The trunk at its base to the species' proportions.
	var want := height * 0.022 * float(spec.get("trunk", 1.0))
	var k := want / maxf(tree.radius[0], 0.0001)
	if OS.get_environment("GN_DEBUG") != "":
		print("  nodes %d, r0 %.4f r1 %.4f r5 %.4f r10 %.4f want %.3f k %.2f" % [n, tree.radius[0], tree.radius[1],
			tree.radius[mini(5, n - 1)], tree.radius[mini(10, n - 1)], want, k])
	if k < 1.0:
		for i in n:
			tree.radius[i] = maxf(tree.radius[i] * k, tip)
	else:
		for i in n:
			tree.radius[i] = tree.radius[i] * lerpf(1.0, k, clampf(tree.radius[i] / tree.radius[0], 0.0, 1.0))
	# Birch-like drooping twigs: the thin wood sags.
	var droop := float(spec.get("droop", 0.0))
	if droop > 0.0:
		for i in range(1, n):
			var thin := 1.0 - clampf(tree.radius[i] / (want * 0.25), 0.0, 1.0)
			tree.pos[i] = tree.pos[i] - Vector3(0, droop * thin * thin * step * 3.0, 0)
	return tree


func _hash(pos: PackedVector3Array, size: float) -> Dictionary:
	var grid := {}
	for i in pos.size():
		var c := Vector3i((pos[i] / size).floor())
		if not grid.has(c):
			grid[c] = []
		grid[c].append(i)
	return grid


func _broadleaf(spec: Dictionary) -> void:
	var tree := _grow(spec)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	_wood(wood, tree, spec)
	var height: float = spec.height
	var centre := Vector3(0, height * (1.0 + float(spec.base)) * 0.5, 0)
	var surfaces := [[wood, _bark(spec.bark)]]
	if int(spec.leaves) > 0:
		var leaves := SurfaceTool.new()
		leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
		var extra := SurfaceTool.new()
		extra.begin(Mesh.PRIMITIVE_TRIANGLES)
		var twigs := _twigs(tree, spec)
		# Leafy twigs, not single leaves (pine tufts and blossom clusters are
		# already clusters).
		var sprays: bool = not (spec.atlas in DRAWN_ATLASES)
		var main_atlas: String = _spray(spec.atlas) if sprays else spec.atlas
		var total := int(spec.leaves) / (4 if sprays else 1)
		var size := float(spec.leaf) * (4.0 if sprays else 1.0)
		var extra_share := float(spec.get("extra_share", 0.0))
		var extra_atlas: String = _spray(spec.extra) if extra_share > 0.0 else ""
		for i in total:
			var t: int = twigs[_rng.randi() % twigs.size()]
			var use_extra := extra_share > 0.0 and _rng.randf() < extra_share
			var into := extra if use_extra else leaves
			_leaf_on_twig(into, tree, t, 0.45 if use_extra else size, extra_atlas if use_extra else main_atlas, centre, spec)
		surfaces.append([leaves, _foliage(main_atlas, spec.tint)])
		if extra_share > 0.0:
			surfaces.append([extra, _foliage(extra_atlas, Color(0.8, 0.9, 0.7))])
	if spec.get("weeping", 0.0) > 0.0:
		var strands := SurfaceTool.new()
		strands.begin(Mesh.PRIMITIVE_TRIANGLES)
		_weeping(strands, tree, spec, centre)
		surfaces.append([strands, _foliage(_spray(spec.atlas), spec.tint)])
	_save(spec, surfaces, "trees")


# The twigs leaves hang on: thin wood, out toward the crown's edge.
func _twigs(tree: Skeleton, spec: Dictionary) -> Array:
	var out: Array = []
	var thin := tree.radius[0] * 0.12
	for i in tree.pos.size():
		if tree.radius[i] <= thin and tree.pos[i].y > float(spec.height) * float(spec.base) * 0.8:
			out.append(i)
			if tree.kids[i].is_empty():
				out.append(i)   # tips twice: the outside of a crown is its leaves
	if out.is_empty():
		out.append(tree.pos.size() - 1)
	return out


# The wood as limbs: from the base, each limb follows its thickest child
# onward; every other child starts a limb of its own, from inside its
# parent. Along a limb the rings share their vertices and turn with the
# limb without twisting, so a trunk is one smooth piece of bark.
func _wood(st: SurfaceTool, tree: Skeleton, spec: Dictionary) -> void:
	var twiggy := bool(spec.get("twiggy", false))
	var skip := 0.0 if twiggy else tree.radius[0] * 0.04
	var starts: Array = [[0, -1]]   # [first node, the node it grows from]
	while not starts.is_empty():
		var s: Array = starts.pop_back()
		var chain: Array = []
		if s[1] >= 0:
			chain.append(s[1])
		var i: int = s[0]
		while true:
			chain.append(i)
			var main := _main_child(tree, i)
			for k in tree.kids[i]:
				if k != main and (tree.radius[k] >= skip or twiggy):
					starts.append([k, i])
			if main < 0 or (tree.radius[main] < skip and not twiggy):
				break
			i = main
		_limb(st, tree, chain, s[1] >= 0)


func _limb(st: SurfaceTool, tree: Skeleton, chain: Array, forks: bool) -> void:
	if chain.size() < 2:
		return
	var n := chain.size()
	var first_r := tree.radius[chain[1]] * 1.05 if forks else tree.radius[chain[0]] * 1.5   # a fork starts inside its parent; the trunk flares
	var sides := clampi(int(first_r * 70.0), 3, 12)
	var rings: Array = []
	var ref := Vector3.RIGHT
	var along := 0.0
	for k in n:
		var p: Vector3 = tree.pos[chain[k]]
		var prev: Vector3 = tree.pos[chain[maxi(k - 1, 0)]]
		var next: Vector3 = tree.pos[chain[mini(k + 1, n - 1)]]
		var t := (next - prev).normalized()
		if t.length() < 0.5:
			t = Vector3.UP
		# Carry the ring's reference round with the limb (parallel transport).
		ref = (ref - t * ref.dot(t))
		if ref.length() < 0.01:
			ref = t.cross(Vector3.FORWARD)
		ref = ref.normalized()
		var side := t.cross(ref)
		var r := first_r if k == 0 else tree.radius[chain[k]]
		if k > 0:
			along += p.distance_to(prev)
		var ring: Array = []
		for j in sides + 1:
			var a := TAU * j / sides
			var nrm := (ref * cos(a) + side * sin(a))
			ring.append([p + nrm * r, nrm, Vector2(float(j) / sides * maxf(first_r * TAU, 0.05), along)])
		rings.append(ring)
	for k in n - 1:
		for j in sides:
			var q: Array = [rings[k][j], rings[k + 1][j], rings[k + 1][j + 1], rings[k][j], rings[k + 1][j + 1], rings[k][j + 1]]
			for v in q:
				st.set_color(Color(1, 1, 1))
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])


func _main_child(tree: Skeleton, i: int) -> int:
	var best := -1
	var best_r := -1.0
	for k in tree.kids[i]:
		if tree.radius[k] > best_r:
			best_r = tree.radius[k]
			best = k
	return best


func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, va: float, vb: float,
		shade := Color(1, 1, 1)) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var n0 := u * cos(a0) + w * sin(a0)
		var n1 := u * cos(a1) + w * sin(a1)
		var uv0 := float(i) / sides * maxf(ra * TAU, 0.05)
		var uv1 := float(i + 1) / sides * maxf(ra * TAU, 0.05)
		var quad := [
			[a + n0 * ra, n0, Vector2(uv0, va)], [b + n0 * rb, n0, Vector2(uv0, vb)], [b + n1 * rb, n1, Vector2(uv1, vb)],
			[a + n0 * ra, n0, Vector2(uv0, va)], [b + n1 * rb, n1, Vector2(uv1, vb)], [a + n1 * ra, n1, Vector2(uv1, va)],
		]
		for v in quad:
			st.set_color(shade)
			st.set_normal(v[1])
			st.set_uv(v[2])
			st.add_vertex(v[0])


# A leaf (or a needle tuft, a blossom) on a twig: its stem at the twig, the
# blade out along the twig and away from it, facing the sky and the outside.
func _leaf_on_twig(st: SurfaceTool, tree: Skeleton, twig: int, size: float, atlas: String, centre: Vector3, spec: Dictionary) -> void:
	var p := tree.pos[twig]
	var parent := tree.parent[twig]
	var along := (p - tree.pos[parent]).normalized() if parent >= 0 else Vector3.UP
	var out := (p - centre)
	out.y *= 0.5
	out = out.normalized()
	var at := p + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * size * 0.6
	var dir := (along * 0.6 + out * 0.5 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.8), _rng.randf_range(-1, 1)) * 0.7).normalized()
	if bool(spec.get("tufts", false)):
		# Pine needles stand out from the twig all round, as a tuft.
		dir = (along * 0.8 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1), _rng.randf_range(-1, 1)) * 0.6).normalized()
	_card(st, at, dir, out, size * _rng.randf_range(0.8, 1.25), atlas, out)


# One card cut from an atlas cell: from `at` along `dir` for `length`,
# facing roughly `face`. Normals lean to `normal_out` so a crown shades as
# one soft volume, the way a tree reads from a distance.
func _card(st: SurfaceTool, at: Vector3, dir: Vector3, face: Vector3, length: float, atlas: String, normal_out: Vector3) -> void:
	var all := cells(atlas)
	var cell: Dictionary = all[_rng.randi() % all.size()]
	var aspect: float = cell.aspect
	var long := maxf(aspect, 1.0 / aspect)
	var width := length / long
	var side := dir.cross(face)
	if side.length() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var fwd := side.cross(dir).normalized()
	var n := (fwd * 0.35 + normal_out * 0.65).normalized()
	var r: Rect2 = cell.rect
	var p0 := at - side * width * 0.5
	var p1 := at + side * width * 0.5
	var p2 := p1 + dir * length
	var p3 := p0 + dir * length
	# UV corners for stem (s0, s1) and tip (t1, t0) of the cell.
	var s0: Vector2
	var s1: Vector2
	var t1: Vector2
	var t0: Vector2
	if cell.sideways:
		# Stem on the left: the leaf runs rightwards in the atlas.
		s0 = Vector2(r.position.x, r.end.y)
		s1 = Vector2(r.position.x, r.position.y)
		t1 = Vector2(r.end.x, r.position.y)
		t0 = Vector2(r.end.x, r.end.y)
	else:
		s0 = Vector2(r.position.x, r.end.y)
		s1 = Vector2(r.end.x, r.end.y)
		t1 = Vector2(r.end.x, r.position.y)
		t0 = Vector2(r.position.x, r.position.y)
	var shade := Color.from_hsv(_rng.randf_range(-0.02, 0.03), _rng.randf_range(0.0, 0.12), _rng.randf_range(0.82, 1.0))
	shade = Color(1, 1, 1).lerp(shade, 0.8)
	for v in [[p0, s0], [p1, s1], [p2, t1], [p0, s0], [p2, t1], [p3, t0]]:
		st.set_color(shade)
		st.set_normal(n)
		st.set_uv(v[1])
		st.add_vertex(v[0])


# Weeping willow: curtains of leafy strands hanging from the outer branches.
func _weeping(st: SurfaceTool, tree: Skeleton, spec: Dictionary, centre: Vector3) -> void:
	var tips: Array = []
	for i in tree.pos.size():
		if tree.kids[i].is_empty() and tree.pos[i].y > centre.y - 1.0:
			tips.append(i)
	var strands := mini(tips.size(), 260)
	for s in strands:
		var start: Vector3 = tree.pos[tips[_rng.randi() % tips.size()]]
		var hang := _rng.randf_range(0.5, 0.95) * start.y
		var outward := Vector3(start.x, 0, start.z).normalized() * _rng.randf_range(0.2, 0.6)
		var steps := int(hang / 0.3)
		for k in steps:
			var t := float(k) / steps
			var at := start + outward * sin(t * PI * 0.5) - Vector3(0, hang * t, 0)
			var dir := Vector3(_rng.randf_range(-0.4, 0.4), -1, _rng.randf_range(-0.4, 0.4)).normalized()
			var out := (at - centre)
			out.y = 0
			_card(st, at, dir, out.normalized(), float(spec.leaf) * 3.0 * _rng.randf_range(0.8, 1.2), _spray(spec.atlas), out.normalized())


# ---------------------------------------------------------------------------
# Conifers: a leader, whorls of branches, needle sprigs
# ---------------------------------------------------------------------------
func _conifer(spec: Dictionary) -> void:
	var height: float = spec.height
	var radius: float = spec.radius
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var needles := SurfaceTool.new()
	needles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_r := height * 0.018
	var base := height * float(spec.base)
	var column := bool(spec.get("column", false))
	_tube(wood, Vector3.ZERO, Vector3(0, height, 0), trunk_r * 1.3, 0.01, 10, 0.0, height)
	var droop := float(spec.droop)
	var sprig: float = spec.sprig
	var y := base
	var whorl := 0
	var centre := Vector3(0, height * 0.45, 0)
	while y < height - sprig * 0.5:
		var t := (y - base) / (height - base)
		# Longest branches low down, shortening to the tip: a cone (or, for
		# a cypress, nearly a column that rounds off at the top).
		var reach := radius * (pow(1.0 - t, 0.9) if not column else (sin(clampf(1.0 - t, 0.0, 1.0) * PI * 0.5) * 0.9 + 0.1) * (1.0 - t * 0.3))
		var count := 5 + _rng.randi() % 3 if not column else 8
		var turn := _rng.randf() * TAU
		for b in count:
			var a := turn + TAU * b / count + _rng.randf_range(-0.2, 0.2)
			var out := Vector3(cos(a), 0, sin(a))
			var length := reach * _rng.randf_range(0.8, 1.05)
			var start := Vector3(0, y, 0)
			var tip := start + out * length + Vector3(0, -droop * length * 0.5 + (length * 0.25 if column else 0.0), 0)
			var mid := start + out * length * 0.5 + Vector3(0, length * 0.08, 0)
			var br := maxf(trunk_r * 0.18 * (1.0 - t * 0.6), 0.006)
			_tube(wood, start, mid, br, br * 0.6, 4, y, y + length * 0.5)
			_tube(wood, mid, tip, br * 0.6, 0.004, 3, y + length * 0.5, y + length)
			# Sprigs along the branch and fanning at its tip.
			var n := int(length / (sprig * 0.35)) + 2
			for k in n:
				var s := float(k) / maxf(n - 1, 1)
				var at := (start.lerp(mid, s * 2.0) if s < 0.5 else mid.lerp(tip, s * 2.0 - 1.0))
				var side := out.cross(Vector3.UP).normalized() * (1.0 if k % 2 == 0 else -1.0)
				var dir := (out * 0.6 + side * 0.6 + Vector3(0, -droop * 0.4 + _rng.randf_range(-0.15, 0.2), 0)).normalized()
				var face := (Vector3.UP * 0.8 + out * 0.2).normalized()
				_card(needles, at, dir, face, sprig * lerpf(0.7, 1.0, s), spec.atlas, (at - centre).normalized())
				# A second sprig, steeper, fills the branch's depth.
				var dir2 := (out * 0.7 - side * 0.3 + Vector3(0, 0.25 - droop * 0.3, 0)).normalized()
				_card(needles, at, dir2, (Vector3.UP * 0.5 + side * 0.5).normalized(), sprig * lerpf(0.6, 0.9, s), spec.atlas,
					(at - centre).normalized())
		y += lerpf(0.45, 0.25, t) * (0.6 if column else 1.0) * clampf(height / 12.0, 0.5, 1.2)
		whorl += 1
	# The leader's tip.
	for k in 6:
		var dir := Vector3(_rng.randf_range(-0.3, 0.3), 1, _rng.randf_range(-0.3, 0.3)).normalized()
		_card(needles, Vector3(0, height - sprig * 0.6, 0), dir, Vector3.RIGHT, sprig * 0.8, spec.atlas, Vector3.UP)
	_save(spec, [[wood, _bark(spec.bark)], [needles, _foliage(spec.atlas, spec.tint)]], "trees")


# ---------------------------------------------------------------------------
# Palms
# ---------------------------------------------------------------------------
func _palm(spec: Dictionary) -> void:
	var height: float = spec.height
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := SurfaceTool.new()
	fronds.begin(Mesh.PRIMITIVE_TRIANGLES)
	var thick := float(spec.get("thick", 0.17))
	var lean := float(spec.lean)
	var lean_dir := Vector3(cos(_rng.randf() * TAU), 0, sin(_rng.randf() * TAU))
	# The trunk curves: it leans out, then rises toward the light.
	var pts: Array = []
	for k in 13:
		var t := k / 12.0
		var off := lean_dir * height * lean * (t * t * 0.9 + t * 0.4)
		pts.append(Vector3(off.x, height * t, off.z))
	for k in 12:
		var r0 := thick * lerpf(1.25, 0.9, k / 12.0)
		var r1 := thick * lerpf(1.25, 0.9, (k + 1) / 12.0)
		_tube(wood, pts[k], pts[k + 1], r0, r1, 10, height * k / 12.0, height * (k + 1) / 12.0)
	var crown: Vector3 = pts[12]
	# A knob of old frond bases at the crown.
	_tube(wood, crown - Vector3(0, 0.5, 0), crown + Vector3(0, 0.25, 0), thick * 1.25, thick * 0.7, 10, 0.0, 0.75)
	var count: int = spec.fronds
	var length: float = spec.frond
	var green := Color(0.16, 0.27, 0.08)
	if spec.style == "fan":
		# A round head: fans pointing every way from straight up to hanging,
		# spread evenly over it (a golden-angle spiral).
		var live := Color(0.22, 0.34, 0.15)
		for f in count:
			var up := lerpf(1.0, -0.55, (f + 0.5) / count)
			var a := f * 2.39996 + _rng.randf_range(-0.1, 0.1)
			_fan_leaf(fronds, crown + Vector3(0, 0.1, 0), Vector3(cos(a), 0, sin(a)), up, length * _rng.randf_range(0.9, 1.08), live)
		# The skirt: dead fans hanging down the trunk under the head.
		var skirt := float(spec.get("skirt", 0.0))
		var rings := int(skirt / 0.8)
		for ring in rings:
			for f in 14:
				var a := TAU * (f + 0.5 * (ring % 2)) / 14.0 + _rng.randf_range(-0.12, 0.12)
				var out := Vector3(cos(a), 0, sin(a))
				var dead := Color(0.46, 0.37, 0.24).lerp(Color(0.33, 0.26, 0.17), _rng.randf())
				_fan_leaf(fronds, crown - Vector3(0, 0.35 + ring * 0.8, 0) + out * thick, out, -1.0, length * 0.6, dead, true)
		_save(spec, [[wood, _bark(spec.bark)], [fronds, _plain("palm_frond", Color(1, 1, 1), 0.6)]], "trees")
		return
	for f in count:
		var a := TAU * f / count + _rng.randf_range(-0.15, 0.15)
		var out := Vector3(cos(a), 0, sin(a))
		# Young fronds stand up in the middle; old ones droop at the bottom.
		var age := float(f % 3) / 2.0
		var rise := lerpf(0.9, -0.1, age) * float(spec.get("stiff", 1.0))
		var l := length * _rng.randf_range(0.85, 1.1)
		if spec.style == "fan":
			_fan_leaf(fronds, crown + Vector3(0, 0.1, 0), out, rise, l, green)
		else:
			_feather_frond(fronds, crown + Vector3(0, 0.15, 0), out, rise, l, green)
	_save(spec, [[wood, _bark(spec.bark)], [fronds, _plain("palm_frond", Color(1, 1, 1), 0.6)]], "trees")


func _feather_frond(st: SurfaceTool, start: Vector3, out: Vector3, rise: float, length: float, green: Color) -> void:
	# The midrib arcs up and out, then droops under its own weight.
	var rib: Array = []
	for k in 17:
		var t := k / 16.0
		rib.append(start + out * length * t + Vector3(0, length * (rise * t - 0.75 * t * t), 0))
	var side := out.cross(Vector3.UP).normalized()
	for k in range(1, 16):
		var p: Vector3 = rib[k]
		var dir: Vector3 = (rib[k + 1] - rib[k - 1]).normalized()
		var t := k / 16.0
		var leaflet := length * 0.28 * sin(clampf(t * 1.15, 0.05, 1.0) * PI) + 0.08
		for s in [-1.0, 1.0]:
			# Leaflets angle forward and droop, in a shallow V.
			var ldir: Vector3 = (side * s + dir * 0.55 + Vector3(0, -0.45, 0)).normalized()
			var tipp := p + ldir * leaflet
			var w := leaflet * 0.07
			var up: Vector3 = ldir.cross(dir).normalized() * s
			var c := green.lerp(Color(0.3, 0.34, 0.12), _rng.randf() * 0.4)
			for v in [p - dir * w, p + dir * w, tipp]:
				st.set_color(c)
				st.set_normal((Vector3.UP * 0.7 + up * 0.3).normalized())
				st.set_uv(Vector2(0, 0))
				st.add_vertex(v)
	# The midrib itself.
	for k in 16:
		_tube(st, rib[k], rib[k + 1], 0.025 * (1.0 - k / 16.0) + 0.006, 0.02 * (1.0 - (k + 1) / 16.0) + 0.005, 3, 0.0, 0.0,
			Color(0.5, 0.52, 0.3))


# A Washingtonia leaf: a long stalk, then a round pleated fan whose segments
# are joined near the stalk and split into drooping strips toward the edge.
# `up` aims it: 1 straight up, 0 level, -1 hanging. `dead` fans hang flat
# against the trunk, as the skirt does.
func _fan_leaf(st: SurfaceTool, start: Vector3, out: Vector3, up: float, length: float, colour: Color, dead := false) -> void:
	var tilt := clampf(up, -1.0, 1.0) * PI * 0.45
	var along := (out * cos(tilt) + Vector3.UP * sin(tilt)).normalized()
	var stalk := length * (0.2 if dead else 0.55)
	var hub := start + along * stalk
	if not dead:
		_tube(st, start, hub, 0.035, 0.02, 3, 0.0, 0.0, Color(0.45, 0.46, 0.28))
	var side := out.cross(Vector3.UP).normalized()
	# The blade carries on from the stalk and a little down under its weight.
	var fwd := (along + Vector3.DOWN * (0.05 if dead else 0.25)).normalized()
	var normal := fwd.cross(side).normalized()
	if normal.dot(Vector3.UP) < 0.0 and not dead:
		normal = -normal
	var radius := length * (0.75 if dead else 0.5)
	var segs := 34
	var spread := 1.45 if not dead else 0.8
	var steps := 5
	var join := 0.68
	for k in segs:
		var a := lerpf(-spread, spread, (k + 0.5) / segs)
		var half := spread / segs
		var dir := fwd * cos(a) + side * sin(a)
		var across := side * cos(a) - fwd * sin(a)
		var len_k := radius * _rng.randf_range(0.85, 1.0) * (1.0 - 0.12 * absf(a) / spread)
		var pleat := 0.035 if k % 2 == 0 else -0.035
		var c := colour.lerp(colour.darkened(0.25), _rng.randf() * 0.5)
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in steps + 1:
			var s := float(i) / steps
			var r := len_k * s
			# Gravity bends the outer, split part down the most.
			var sag := (s * s * 0.3 + maxf(s - join, 0.0) * 0.9) * len_k * (0.3 if dead else 1.0)
			var centre := hub + dir * r + Vector3.DOWN * sag + normal * pleat * s
			# Joined: as wide as its share of the fan. Split: tapering strips.
			var w := r * sin(half) * (1.0 if s <= join else lerpf(0.6, 0.05, (s - join) / (1.0 - join)))
			var l := centre - across * w
			var rr := centre + across * w
			if i > 0:
				for v in [prev_l, prev_r, rr, prev_l, rr, l]:
					st.set_color(c)
					st.set_normal(normal)
					st.set_uv(Vector2(0, 0))
					st.add_vertex(v)
			prev_l = l
			prev_r = rr


# ---------------------------------------------------------------------------
# Shrubs, topiary, flowers, rosettes, grasses, pots
# ---------------------------------------------------------------------------
func _shrub(spec: Dictionary) -> void:
	# A bush is a small tree with many stems from the ground.
	var h: float = spec.height
	var w: float = spec.width
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0, h * 0.5, 0)
	var twigs: Array = []
	for s in 7:
		var a := _rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * w * 0.08
		var top := Vector3(cos(a) * w * _rng.randf_range(0.15, 0.4), h * _rng.randf_range(0.6, 0.95), sin(a) * w * _rng.randf_range(0.15, 0.4))
		_tube(wood, base, top, 0.012, 0.004, 4, 0.0, h)
	for i in int(spec.leaves):
		var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 1), _rng.randf_range(-1, 1)).normalized()
		var r := pow(_rng.randf(), 0.3)
		var p := Vector3(d.x * w * 0.5, h * 0.5 + d.y * h * 0.5, d.z * w * 0.5) * Vector3(r, 1, r)
		p.y = clampf(p.y * r + h * 0.5 * (1.0 - r), 0.03, h)
		var out := (p - centre * 0.6).normalized()
		var dir := (out * 0.6 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1), _rng.randf_range(-1, 1)) * 0.6).normalized()
		_card(leaves, p, dir, out, float(spec.leaf) * _rng.randf_range(0.8, 1.2), spec.atlas, out)
	var surfaces := [[wood, _bark("bark_smooth_dark")], [leaves, _foliage(spec.atlas, spec.tint)]]
	if spec.has("flowers"):
		var bloom := SurfaceTool.new()
		bloom.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in int(spec.flower_count):
			var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.1, 1), _rng.randf_range(-1, 1)).normalized()
			var p := Vector3(d.x * w * 0.48, h * 0.5 + d.y * h * 0.48, d.z * w * 0.48)
			var out := (p - centre).normalized()
			# Flowers face out; the card is centred on the bloom.
			var dir := out.cross(Vector3.UP).normalized()
			if dir.length() < 0.1:
				dir = Vector3.RIGHT
			var s: float = spec.flower
			_card(bloom, p - dir * s * 0.5, dir, out, s, spec.flowers, out)
		surfaces.append([bloom, _foliage(spec.flowers, Color(1, 1, 1))])
	_save(spec, surfaces, "plants")


func _topiary(spec: Dictionary) -> void:
	# Clipped: small leaves packed on the surface of a box, ball or cone.
	var size: Vector3 = spec.size
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := SurfaceTool.new()
	inner.begin(Mesh.PRIMITIVE_TRIANGLES)
	var form: String = spec.form
	var area := 0.0
	match form:
		"hedge":
			area = 2.0 * (size.x * size.y + size.z * size.y) + size.x * size.z
		"ball":
			area = PI * size.x * size.x
		"cone":
			area = PI * size.x * 0.5 * size.y
	var count := int(area * 2600.0)
	for i in count:
		var p: Vector3
		var n: Vector3
		match form:
			"hedge":
				var face := _rng.randf() * (area)
				var u := _rng.randf()
				var v := _rng.randf()
				if face < size.x * size.z:
					p = Vector3((u - 0.5) * size.x, size.y, (v - 0.5) * size.z)
					n = Vector3.UP
				elif face < size.x * size.z + 2.0 * size.x * size.y:
					var s := 1.0 if _rng.randf() < 0.5 else -1.0
					p = Vector3((u - 0.5) * size.x, v * size.y, s * size.z * 0.5)
					n = Vector3(0, 0, s)
				else:
					var s := 1.0 if _rng.randf() < 0.5 else -1.0
					p = Vector3(s * size.x * 0.5, v * size.y, (u - 0.5) * size.z)
					n = Vector3(s, 0, 0)
			"ball":
				n = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
				p = Vector3(0, size.y * 0.5, 0) + n * size.x * 0.5
			"cone":
				var t := sqrt(_rng.randf())
				var a := _rng.randf() * TAU
				var r := size.x * 0.5 * t
				p = Vector3(cos(a) * r, size.y * (1.0 - t), sin(a) * r)
				n = Vector3(cos(a), size.x * 0.5 / size.y, sin(a)).normalized()
		# Clipped surfaces are a little ragged: leaves stand proud by a few centimetres.
		p += n * _rng.randf_range(-0.01, 0.05)
		var dir := (n * 0.5 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.8).normalized()
		_card(leaves, p, dir, n, float(spec.leaf) * _rng.randf_range(0.8, 1.2), spec.atlas, n)
	# A dark core, so light never shows through a clipped hedge.
	match form:
		"hedge":
			_box(inner, Vector3(0, size.y * 0.5 - 0.02, 0), size - Vector3(0.1, 0.1, 0.1), Color(0.12, 0.18, 0.08))
		"ball":
			_ball(inner, Vector3(0, size.y * 0.5, 0), size.x * 0.46, Color(0.12, 0.18, 0.08))
		"cone":
			_cone(inner, size.x * 0.36, size.y * 0.9, Color(0.12, 0.18, 0.08))
	_save(spec, [[inner, _plain("foliage_core", Color(1, 1, 1), 1.0)], [leaves, _foliage(spec.atlas, spec.tint)]], "plants")


func _flowers(spec: Dictionary) -> void:
	var h: float = spec.height
	var w: float = spec.width
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heads := SurfaceTool.new()
	heads.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := SurfaceTool.new()
	blades.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bed := bool(spec.get("bed", false))
	var head: String = spec.head
	for i in int(spec.stems):
		var base := Vector3(_rng.randf_range(-0.5, 0.5) * w, 0, _rng.randf_range(-0.5, 0.5) * w) if bed else \
			Vector3(_rng.randf_range(-0.12, 0.12), 0, _rng.randf_range(-0.12, 0.12))
		var lean := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * (0.05 if bed else w * 0.5)
		var top := base + lean + Vector3(0, h * _rng.randf_range(0.75, 1.0), 0)
		var c := Color(0.35, 0.5, 0.25)
		_tube(stems, base, top, 0.004, 0.003, 3, 0.0, 0.0)
		var s := 0.1 if head.begins_with("tulip") else (0.22 if head == "lavender" else 0.06)
		if head == "lavender":
			# The spike is the upper part of the stalk.
			var dir := (top - base).normalized()
			_card(heads, top - dir * s * 0.8, dir, Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), s * 1.2, head, Vector3.UP)
		else:
			var face := Vector3(_rng.randf_range(-1, 1), 0.4 if head.begins_with("tulip") else 2.0, _rng.randf_range(-1, 1)).normalized()
			var side := face.cross(Vector3.FORWARD).normalized()
			_card(heads, top - side * s * 0.5 - Vector3(0, s * 0.3, 0), side, face, s, head, face)
	# Leaves or grass at the foot.
	var n := int(spec.get("grass", int(spec.stems) * 2 / 3))
	for i in n:
		var base := Vector3(_rng.randf_range(-0.5, 0.5) * w, 0, _rng.randf_range(-0.5, 0.5) * w) if bed else \
			Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15))
		var dir := Vector3(_rng.randf_range(-0.5, 0.5), 1, _rng.randf_range(-0.5, 0.5)).normalized()
		var face := Vector3(dir.z, 0, -dir.x).normalized()
		if face.length() < 0.1:
			face = Vector3.RIGHT
		_card(blades, base, dir, face, h * _rng.randf_range(0.4, 0.8), spec.blade_atlas, Vector3.UP)
	_save(spec, [[stems, _plain("green_stem", Color(0.3, 0.45, 0.2))], [heads, _foliage(head, Color(1, 1, 1))],
		[blades, _foliage(spec.blade_atlas, spec.tint)]], "plants")


func _rosette(spec: Dictionary) -> void:
	# Leaves from one crown at the ground, arching out: fern, hosta, agave.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = spec.count
	var length: float = spec.length
	var arch: float = spec.arch
	var solid := bool(spec.get("solid", false))
	for i in count:
		var a := TAU * i / count * 2.618   # golden spiral, like real rosettes
		var out := Vector3(cos(a), 0, sin(a))
		var inner := float(i) / count
		var rise := lerpf(1.6, 0.35, inner) if not bool(spec.get("flat", false)) else 0.15
		var l := length * lerpf(0.6, 1.0, inner) * _rng.randf_range(0.85, 1.1)
		if solid:
			# Agave: thick, stiff, pointed leaves, as solid geometry.
			var tip := out * l * 0.8 + Vector3(0, l * rise * 0.6, 0)
			var w := l * 0.1
			var side := out.cross(Vector3.UP).normalized()
			var c := Color(0.2, 0.33, 0.3).lerp(Color(0.3, 0.38, 0.25), _rng.randf() * 0.4)
			var base := Vector3(0, 0.05, 0)
			for tri in [[base - side * w, base + side * w, tip], [base - side * w + Vector3(0, w * 0.6, 0), tip, base + side * w + Vector3(0, w * 0.6, 0)]]:
				for v in tri:
					st.set_color(c)
					st.set_normal((Vector3.UP + out * 0.5).normalized())
					st.set_uv(Vector2.ZERO)
					st.add_vertex(v)
			continue
		if bool(spec.get("broad", false)):
			# A broad leaf: one card, the whole length, tilted up and out.
			var tipb := out * l * 0.85 + Vector3(0, l * rise * 0.45, 0)
			_card(st, Vector3(0, 0.03, 0), tipb.normalized(), Vector3.UP, l, spec.atlas, (Vector3.UP * 0.7 + out * 0.3).normalized())
			continue
		# A leaf in three cards along an arc, so it bends.
		var prev := Vector3(0, 0.02, 0)
		for k in 3:
			var t := (k + 1) / 3.0
			var p := out * l * t + Vector3(0, l * (rise * t - arch * 1.4 * t * t), 0)
			var dir := (p - prev).normalized()
			_card(st, prev, dir, Vector3.UP, prev.distance_to(p) * 1.15, spec.atlas, (Vector3.UP * 0.7 + out * 0.3).normalized())
			prev = p
			if bool(spec.get("broad", false)):
				break
	var mat := _plain("agave", Color(1, 1, 1), 0.55) if solid else _foliage(spec.atlas, spec.tint)
	_save(spec, [[st, mat]], "plants")


func _grass(spec: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hr: Array = spec.height
	var spread := float(spec.get("spread", 0.1))
	var arch := float(spec.get("arch", 0.15))
	for i in int(spec.count):
		var root := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * spread
		var h := _rng.randf_range(hr[0], hr[1])
		var yaw := _rng.randf() * TAU
		var out := Vector3(cos(yaw), 0, sin(yaw))
		var face := out.cross(Vector3.UP)
		if bool(spec.get("whole", false)):
			# A whole plant from the atlas (a stalk with its seed head).
			var dir := (Vector3.UP + out * _rng.randf_range(0.05, 0.3)).normalized()
			_card(st, root, dir, face, h, spec.atlas, Vector3.UP)
			continue
		# A blade in three bending pieces.
		var prev := root
		for k in 3:
			var t := (k + 1) / 3.0
			var p := root + Vector3.UP * h * t + out * h * arch * t * t
			_card(st, prev, (p - prev).normalized(), face, prev.distance_to(p) * 1.1, spec.atlas, Vector3.UP)
			prev = p
	var surfaces := [[st, _foliage(spec.atlas, spec.tint)]]
	if spec.has("plumes"):
		var plumes := SurfaceTool.new()
		plumes.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in int(spec.plumes):
			var yaw := _rng.randf() * TAU
			var out := Vector3(cos(yaw), 0, sin(yaw))
			var base := out * _rng.randf_range(0.0, 0.2) + Vector3(0, hr[1] * 0.8, 0)
			var dir := (Vector3.UP + out * 0.35).normalized()
			_tube(plumes, out * 0.05, base, 0.006, 0.005, 3, 0.0, 0.0)
			_card(plumes, base, dir, out.cross(Vector3.UP), hr[1] * 0.5, "plume", Vector3.UP)
		surfaces.append([plumes, _foliage("plume", Color(1, 1, 1))])
	_save(spec, surfaces, "grass")


func _potted(spec: Dictionary) -> void:
	# The plant (built first) in its pot.
	var plant: Dictionary = {}
	for s in SPECIES:
		if s.name == spec.plant:
			plant = s
	var mesh_path := "%s/%s.mesh.res" % [DATA, spec.plant]
	if not FileAccess.file_exists(mesh_path):
		print("  %s needs %s built first" % [spec.name, spec.plant])
		return
	var pot := SurfaceTool.new()
	pot.begin(Mesh.PRIMITIVE_TRIANGLES)
	var soil := SurfaceTool.new()
	soil.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k: float = spec.scale
	var pot_h := 0.55 if spec.pot == "round" else 0.6
	var pot_w := 0.6 if spec.pot == "round" else 0.8
	if spec.pot == "round":
		_cone_pot(pot, pot_w * 0.5, pot_w * 0.38, pot_h, Color(0.55, 0.3, 0.2))
	else:
		_box(pot, Vector3(0, pot_h * 0.5, 0), Vector3(pot_w, pot_h, pot_w), Color(0.2, 0.2, 0.21))
	_box(soil, Vector3(0, pot_h - 0.04, 0), Vector3(pot_w * 0.86, 0.02, pot_w * 0.86), Color(0.2, 0.14, 0.1))
	var im := ImporterMesh.new()
	var src: ArrayMesh = load(mesh_path)
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = verts[i] * k + Vector3(0, pot_h - 0.03, 0)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_INDEX] = null
		arrays[Mesh.ARRAY_TANGENT] = null
		# LOD arrays are rebuilt; keep only the base geometry.
		var clean := []
		clean.resize(Mesh.ARRAY_MAX)
		for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
			clean[a] = arrays[a]
		var idx: PackedInt32Array = src.surface_get_arrays(s)[Mesh.ARRAY_INDEX] if src.surface_get_arrays(s)[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		clean[Mesh.ARRAY_INDEX] = idx if not idx.is_empty() else null
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, clean, [], {}, src.surface_get_material(s), src.surface_get_name(s))
	_save(spec, [[pot, _plain("planter", Color(1, 1, 1), 0.7)], [soil, _plain("soil", Color(1, 1, 1), 1.0)]], "plants", im,
		{"height_m": float(plant.get("height", 1.0)) * k + pot_h})


func _box(st: SurfaceTool, centre: Vector3, size: Vector3, c: Color) -> void:
	var h := size * 0.5
	var faces := [[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := centre + n * h
		var du := u * h
		var dv := v * h
		var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(c)
			st.set_normal(n)
			st.set_uv(Vector2(q[i].x + q[i].z, q[i].y))
			st.add_vertex(q[i])


func _ball(st: SurfaceTool, centre: Vector3, r: float, c: Color) -> void:
	var rings := 8
	var segs := 12
	for i in rings:
		for j in segs:
			var pts: Array = []
			for d in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var th: float = PI * (i + d[0]) / rings
				var ph: float = TAU * (j + d[1]) / segs
				pts.append(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)))
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(c)
				st.set_normal(pts[k])
				st.set_uv(Vector2.ZERO)
				st.add_vertex(centre + pts[k] * r)


func _cone(st: SurfaceTool, r: float, h: float, c: Color) -> void:
	for j in 12:
		var a0 := TAU * j / 12.0
		var a1 := TAU * (j + 1) / 12.0
		for v in [Vector3(cos(a0) * r, 0, sin(a0) * r), Vector3(0, h, 0), Vector3(cos(a1) * r, 0, sin(a1) * r)]:
			st.set_color(c)
			st.set_normal(Vector3(v.x, r, v.z).normalized())
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v)


func _cone_pot(st: SurfaceTool, top_r: float, bottom_r: float, h: float, c: Color) -> void:
	var sides := 20
	for j in sides:
		var a0 := TAU * j / sides
		var a1 := TAU * (j + 1) / sides
		var q := [Vector3(cos(a0) * bottom_r, 0, sin(a0) * bottom_r), Vector3(cos(a1) * bottom_r, 0, sin(a1) * bottom_r),
			Vector3(cos(a1) * top_r, h, sin(a1) * top_r), Vector3(cos(a0) * top_r, h, sin(a0) * top_r)]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(c)
			st.set_normal(Vector3(q[i].x, 0.2, q[i].z).normalized())
			st.set_uv(Vector2(float(j) / sides * 2.0, q[i].y))
			st.add_vertex(q[i])
		# The rim.
		_tube(st, Vector3(cos(a0) * top_r, h, sin(a0) * top_r), Vector3(cos(a1) * top_r, h, sin(a1) * top_r), 0.025, 0.025, 4, 0.0, 0.0)


# ---------------------------------------------------------------------------
func _save(spec: Dictionary, surfaces: Array, category: String, im: ImporterMesh = null, extra := {}) -> void:
	# A variant says where it goes itself.
	category = spec.get("category", category)
	# Through ImporterMesh so Godot builds distance LODs, as it would for an
	# imported model.
	if im == null:
		im = ImporterMesh.new()
	for s in surfaces:
		var st: SurfaceTool = s[0]
		var arrays := st.commit_to_arrays()
		if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		st.generate_tangents()
		arrays = st.commit_to_arrays()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, s[1], (s[1] as Material).resource_name)
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	var mesh_path := "%s/%s.mesh.res" % [DATA, spec.name]
	ResourceSaver.save(mesh, mesh_path)
	var mi := MeshInstance3D.new()
	mi.name = str(spec.name).to_pascal_case()
	mi.mesh = load(mesh_path)
	var packed := PackedScene.new()
	packed.pack(mi)
	DirAccess.make_dir_recursive_absolute("%s/%s" % [OUT, category])
	ResourceSaver.save(packed, "%s/%s/%s.tscn" % [OUT, category, spec.name])
	var box := mesh.get_aabb()
	var tris := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		tris += ((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	var sources: Array = []
	for s in surfaces:
		var m: Material = s[1]
		if m is StandardMaterial3D and (m as StandardMaterial3D).albedo_texture:
			sources.append(m.resource_name)
	var info := {
		"label": spec.get("label", spec.name),
		"kind": spec.kind,
		"height_m": snappedf(box.end.y, 0.01),
		"width_m": snappedf(maxf(box.size.x, box.size.z), 0.01),
		"triangles": tris,
		"source": "Generated by tools/make_plants.gd%s" % ((" from ambientCG textures (%s)" % ", ".join(sources)) if not sources.is_empty() else ""),
		"author": "Utopian Academy; textures by ambientCG",
		"license": "CC0-1.0",
		"attribution": "None required",
	}
	info.merge(extra, true)
	var f := FileAccess.open("%s/%s/%s.license.json" % [OUT, category, spec.name], FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "  ") + "\n")
	f.close()
	print("PLANT %s: %d triangles, %.1f m tall" % [spec.name, tris, box.end.y])
