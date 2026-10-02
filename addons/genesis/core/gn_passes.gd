@tool
extends RefCounted

# Render passes for compositing, as Lumion Pro exports them: depth, normals,
# object ID and an alpha mask, plus a clay render. Each pass re-renders the
# same camera with one thing changed, and puts everything back afterwards.
#   depth    - linear distance as grey (white near), via a full-screen quad
#   normal   - Godot's own normal buffer (a viewport debug view)
#   id       - every object flat in its own colour, for selecting in Photoshop
#   mask     - the design white on black, sky and ground excluded
#   clay     - everything plain white matte, lit as normal

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnStaging := preload("res://addons/genesis/core/gn_staging.gd")

const PASSES := ["depth", "normal", "id", "mask", "clay"]


# Renders the passes named in `which` for a camera. Returns {pass: path}.
static func render(camera: Camera3D, size: Vector2i, host: Node, which: Array = PASSES) -> Dictionary:
	var out := {}
	var stem := "%s/%s" % [GnRender.OUTPUT_DIR, str(camera.name).replace(" ", "")]
	for pass_name in which:
		var undo := GnStaging.stage(pass_name)
		var path: String = await GnRender.render(camera, size, host, false,
			Viewport.DEBUG_DRAW_NORMAL_BUFFER if pass_name == "normal" else Viewport.DEBUG_DRAW_DISABLED,
			pass_name == "mask")
		GnStaging.unstage(undo)
		if path != "":
			var named := "%s_%s.png" % [stem, pass_name]
			DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(named))
			if pass_name == "mask":
				_alpha_to_mask(named)
			out[pass_name] = named
	return out


# The mask pass renders the design over transparency; turn that into the
# white-on-black mask compositors expect.
static func _alpha_to_mask(path: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.convert(Image.FORMAT_RGBA8)
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_L8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			out.set_pixel(x, y, Color(a, a, a))
	out.save_png(path)
