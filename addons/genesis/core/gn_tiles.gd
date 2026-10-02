@tool
extends RefCounted

# Tiles and grout: floor and wall tiles drawn at their real size, with the
# grout joint, its colour and a small bevel on each tile edge, in a layout.
# The colour, normal and roughness maps are drawn once per design and kept
# in the project, and laid on in world space like the other presets.
#
# Tiles are drawn at exactly their size. Godot's world-space mapping shares
# one scale between a floor's depth and the width of walls facing east or
# west, so on those walls a pattern whose repeat isn't square comes out a
# fraction wider or narrower; the repeat is chosen to keep that as small as
# it can, and `report` says what it is.

const GnMaterials := preload("res://addons/genesis/core/gn_materials.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

const DIR := "res://genesis_data/tiles"
const META := &"gn_tiles"
const LAYOUTS := ["Grid", "Half bond", "Third bond", "Checkerboard"]
const MAX_PX := 2048

const DEFAULTS := {
	"layout": "Grid",
	"tile_w": 0.3,        # metres
	"tile_h": 0.3,
	"grout": 0.003,
	"colour": Color(0.92, 0.91, 0.88),
	"colour_2": Color(0.12, 0.12, 0.13),  # the second checkerboard colour
	"grout_colour": Color(0.62, 0.61, 0.58),
	"gloss": 0.35,        # tile roughness
	"variation": 0.25,    # tile to tile shade differences, 0-1
}


## The design on a surface, or the defaults if it isn't tiled.
static func design(s: GnMaterials.Surface) -> Dictionary:
	var mat := s.material() if s else null
	var d := DEFAULTS.duplicate()
	if mat and mat.has_meta(META):
		d.merge(mat.get_meta(META), true)
	return d


## Puts the tile design on a surface, as one undo step. Settings not given
## keep their defaults.
static func apply(s: GnMaterials.Surface, settings: Dictionary) -> void:
	var d := DEFAULTS.duplicate()
	d.merge(settings, true)
	var p := plan(d)
	var maps := textures(d)
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Tiles %s" % size_text(d)
	mat.albedo_texture = maps.albedo
	mat.normal_enabled = true
	mat.normal_texture = maps.normal
	mat.normal_scale = 1.0
	mat.roughness = 1.0
	mat.roughness_texture = maps.roughness
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(1.0 / p.width, 1.0 / p.height, 1.0 / p.height)
	mat.set_meta(META, d)
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Genesis: tiles", UndoRedo.MERGE_DISABLE, GnScene.root())
	GnMaterials._allow_override(ur, s.mesh)
	ur.add_do_property(s.mesh, s.property(), mat)
	ur.add_undo_property(s.mesh, s.property(), s.mesh.get(s.property()))
	ur.commit_action()


static func size_text(d: Dictionary) -> String:
	return "%d × %d mm, %.1f mm grout" % [roundi(d.tile_w * 1000), roundi(d.tile_h * 1000), d.grout * 1000]


## How the design repeats: {width, height (m), across, rows, and the
## stretch east and west facing walls get (a fraction)}.
static func plan(d: Dictionary) -> Dictionary:
	var a: float = d.tile_w + d.grout
	var r := _bond_rows(d.layout)
	var b: float = r * (d.tile_h + d.grout)
	var best := {}
	for m in range(1, 13):
		# A checkerboard needs an even count across to carry on across the edge.
		if d.layout == "Checkerboard" and m % 2 == 1:
			continue
		var n := maxi(1, roundi(m * a / b))
		var err := absf(m * a - n * b) / (n * b)
		if best.is_empty() or err < best.stretch - 0.0001:
			best = {"width": m * a, "height": n * b, "across": m, "rows": n * r, "stretch": err}
		if err < 0.001:
			break
	# A few tiles each way at the least, so shade variation doesn't repeat
	# on every tile.
	while best.across < 4 and maxf(best.width, best.height) * 2.0 <= 4.0:
		for k in ["width", "height"]:
			best[k] *= 2.0
		best.across *= 2
		best.rows *= 2
	return best


## A one-line account of the design.
static func report(d: Dictionary) -> String:
	var p := plan(d)
	var text := "%s, %s, repeating every %.2f × %.2f m." % [d.layout, size_text(d), p.width, p.height]
	if p.stretch >= 0.0005:
		text += " Exact on floors and on walls facing north or south; %.1f%% %s on walls facing east or west." % [
			p.stretch * 100.0, "wider" if p.height > p.width else "narrower"]
	return text


## The colour, normal and roughness maps for a design, drawn the first time.
static func textures(d: Dictionary) -> Dictionary:
	var key := "%x" % hash(var_to_str([d.layout, snappedf(d.tile_w, 0.0001), snappedf(d.tile_h, 0.0001),
		snappedf(d.grout, 0.0001), d.colour.to_html(), d.colour_2.to_html(), d.grout_colour.to_html(),
		snappedf(d.gloss, 0.01), snappedf(d.variation, 0.01)]))
	var paths := {}
	for k in ["albedo", "normal", "roughness"]:
		paths[k] = "%s/%s_%s.res" % [DIR, key, k]
	if not paths.values().all(func(pp): return ResourceLoader.exists(pp)):
		DirAccess.make_dir_recursive_absolute(DIR)
		var imgs := draw(d)
		for k in imgs:
			var img: Image = imgs[k]
			img.generate_mipmaps()
			var tex := PortableCompressedTexture2D.new()
			var mode := PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS if k == "normal" \
				else PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY
			tex.create_from_image(img, mode, k == "normal", 0.92)
			ResourceSaver.save(tex, paths[k])
	var out := {}
	for k in paths:
		out[k] = load(paths[k])
	return out


## Draws the three maps (colour, normal, roughness) for one repeat.
static func draw(d: Dictionary) -> Dictionary:
	var p := plan(d)
	var longest := maxf(p.width, p.height)
	var ppm := minf(MAX_PX / longest, maxf(1024.0 / longest, 3.0 / maxf(d.grout, 0.0005)))
	var nw := clampi(roundi(p.width * ppm), 16, MAX_PX)
	var nh := clampi(roundi(p.height * ppm), 16, MAX_PX)
	# Pixels per metre each way, so a whole repeat is a whole image.
	var px := Vector2(nw / p.width, nh / p.height)
	var albedo := Image.create(nw, nh, false, Image.FORMAT_RGB8)
	var normal := Image.create(nw, nh, false, Image.FORMAT_RGB8)
	var rough := Image.create(nw, nh, false, Image.FORMAT_RGB8)
	albedo.fill(d.grout_colour)
	normal.fill(Color(0.5, 0.5, 1.0))
	rough.fill(Color(0.92, 0.92, 0.92))
	var r := _bond_rows(d.layout)
	var a: float = d.tile_w + d.grout
	var row_h: float = d.tile_h + d.grout
	var tile_w := maxi(1, roundi(d.tile_w * px.x))
	var tile_h := maxi(1, roundi(d.tile_h * px.y))
	var bevel := clampi(roundi(minf(0.0015, d.tile_w * 0.04) * px.x), 1, maxi(1, mini(tile_w, tile_h) / 6))
	# 45° would read as a chipped edge; this is a softer eased one.
	var s := 0.55
	var c := sqrt(1.0 - s * s)
	var edge := {
		"left": Color(0.5 - s * 0.5, 0.5, c * 0.5 + 0.5), "right": Color(0.5 + s * 0.5, 0.5, c * 0.5 + 0.5),
		"top": Color(0.5, 0.5 + s * 0.5, c * 0.5 + 0.5), "bottom": Color(0.5, 0.5 - s * 0.5, c * 0.5 + 0.5),
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(d.layout) ^ int(d.tile_w * 1e4)
	for row in p.rows:
		var y := roundi((row * row_h + d.grout * 0.5) * px.y)
		var offset: float = 0.0 if d.layout == "Checkerboard" else (row % r) * a / r
		for col in p.across + 1:
			var x := roundi((col * a - offset + d.grout * 0.5) * px.x)
			var tint: Color = d.colour_2 if d.layout == "Checkerboard" and (row + col) % 2 == 1 else d.colour
			var shade: float = 1.0 + (rng.randf() - 0.5) * 0.18 * d.variation
			var hue: float = (rng.randf() - 0.5) * 0.02 * d.variation
			var col_c := Color.from_hsv(fposmod(tint.h + hue, 1.0), tint.s, clampf(tint.v * shade, 0.0, 1.0))
			var g := clampf(d.gloss * (1.0 + (rng.randf() - 0.5) * 0.2 * d.variation), 0.0, 1.0)
			# Each tile is drawn again one repeat to the left and above, so
			# ones crossing the edge carry on at the other side.
			for wrap in [Vector2i(0, 0), Vector2i(-nw, 0), Vector2i(0, -nh), Vector2i(-nw, -nh)]:
				var at: Vector2i = Vector2i(x, y) + wrap
				var rect := Rect2i(at, Vector2i(tile_w, tile_h))
				if not rect.intersects(Rect2i(0, 0, nw, nh)):
					continue
				albedo.fill_rect(rect, col_c)
				rough.fill_rect(rect, Color(g, g, g))
				normal.fill_rect(Rect2i(at, Vector2i(bevel, tile_h)), edge.left)
				normal.fill_rect(Rect2i(at + Vector2i(tile_w - bevel, 0), Vector2i(bevel, tile_h)), edge.right)
				normal.fill_rect(Rect2i(at, Vector2i(tile_w, bevel)), edge.top)
				normal.fill_rect(Rect2i(at + Vector2i(0, tile_h - bevel), Vector2i(tile_w, bevel)), edge.bottom)
	return {"albedo": albedo, "normal": normal, "roughness": rough}


static func _bond_rows(layout: String) -> int:
	return {"Half bond": 2, "Third bond": 3, "Checkerboard": 2}.get(layout, 1)
