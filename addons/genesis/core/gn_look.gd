@tool
extends RefCounted

# The look of a shot: exposure, grading, lens and style, stored on each saved
# camera so every view in a presentation keeps its own. Three kinds of setting:
#   camera   - exposure and depth of field, Godot's CameraAttributesPractical
#   lens     - 2-point perspective, a shifted frustum
#   finish   - everything in gn_post.gdshader, applied to the finished image
# Saved looks are small JSON files under genesis_data/looks.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const POST := preload("res://addons/genesis/core/gn_post.gdshader")

const META := &"gn_look"
const LOOKS_DIR := "res://genesis_data/looks"

const DEFAULTS := {
	"exposure": 0.0, "contrast": 1.0, "saturation": 1.0, "warmth": 0.0,
	"dof": 0.0, "focus": 0.0, "vignette": 0.0, "aberration": 0.0,
	"grain": 0.0, "sharpen": 0.0, "sketch": 0.0, "two_point": false,
	"bloom": 0.0, "flare": 0.0, "keep_hue": 0.0, "selective": 0.0,
	"watercolour": 0.0, "painting": 0.0, "outlines": 0.0, "manga": 0.0,
	"clay": false, "title": "", "title_size": 0.06,
	"logo": "", "logo_size": 0.12, "logo_corner": "Bottom right", "logo_opacity": 1.0,
}
const CORNERS := ["Bottom right", "Bottom left", "Top right", "Top left"]
const FINISH := ["contrast", "saturation", "warmth", "vignette", "aberration", "grain", "sharpen", "sketch",
	"bloom", "flare", "keep_hue", "selective", "watercolour", "painting", "outlines", "manga"]

# Built-in looks. The names say what they are for, not how they are made.
const PRESETS := {
	"Natural": {},
	"Crisp daylight": {"contrast": 1.08, "saturation": 1.08, "sharpen": 0.35, "vignette": 0.15, "two_point": true},
	"Warm afternoon": {"warmth": 0.55, "contrast": 1.05, "saturation": 1.1, "vignette": 0.3, "exposure": 0.15},
	"Cool morning": {"warmth": -0.4, "contrast": 1.02, "saturation": 0.92, "vignette": 0.2},
	"Moody": {"contrast": 1.22, "saturation": 0.75, "exposure": -0.4, "vignette": 0.55, "grain": 0.3},
	"Cinematic": {"contrast": 1.12, "warmth": 0.2, "vignette": 0.45, "aberration": 0.35, "grain": 0.25, "dof": 0.35},
	"Black and white": {"saturation": 0.0, "contrast": 1.2, "vignette": 0.3, "grain": 0.2},
	"Pencil sketch": {"sketch": 1.0, "saturation": 0.0, "contrast": 1.1},
	"Watercolour": {"watercolour": 1.0, "saturation": 1.1},
	"Painting": {"painting": 1.0, "saturation": 1.15, "contrast": 1.05},
	"Outlined": {"outlines": 0.8, "saturation": 0.9},
	"Manga": {"manga": 1.0, "contrast": 1.1},
	"Clay model": {"clay": true, "contrast": 1.05},
	"Golden glow": {"bloom": 0.6, "flare": 0.7, "warmth": 0.4, "vignette": 0.3},
}


static func get_look(cam: Camera3D) -> Dictionary:
	var out := DEFAULTS.duplicate()
	if cam:
		out.merge(cam.get_meta(META, {}), true)
	return out


# One setting, undoable, merging while a slider drags.
static func set_value(cam: Camera3D, key: String, value: Variant) -> void:
	var look: Dictionary = cam.get_meta(META, {}).duplicate()
	look[key] = value
	GnScene.set_props("Genesis: %s" % key.capitalize(), [[cam, "metadata/" + META, look]])


static func apply_preset(cam: Camera3D, look: Dictionary) -> void:
	var merged := DEFAULTS.duplicate()
	merged.merge(look, true)
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Genesis: apply look", UndoRedo.MERGE_DISABLE, GnScene.root())
	ur.add_do_property(cam, "metadata/" + META, merged)
	ur.add_undo_property(cam, "metadata/" + META, cam.get_meta(META, {}))
	ur.commit_action()


static func saved_looks() -> Dictionary:
	var out := {}
	if DirAccess.dir_exists_absolute(LOOKS_DIR):
		for f in DirAccess.get_files_at(LOOKS_DIR):
			if f.get_extension() == "json":
				var d = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [LOOKS_DIR, f]))
				if d is Dictionary:
					out[f.get_basename().replace("_", " ")] = d
	return out


static func save_look(name: String, look: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(LOOKS_DIR)
	var path := "%s/%s.json" % [LOOKS_DIR, name.strip_edges().validate_filename().replace(" ", "_")]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(look, "  "))
	f.close()
	return path


# The finishing shader, set up for a look.
static func post_material(look: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = POST
	update_post(m, look)
	return m


static func update_post(m: ShaderMaterial, look: Dictionary) -> void:
	for k in FINISH:
		m.set_shader_parameter(k, float(look.get(k, DEFAULTS[k])))
	m.set_shader_parameter("seed", randf() * 100.0)


# Where the sun lands on screen for a camera (UV, 0-1), or far off-screen
# when it is behind the camera, for the lens flare.
static func sun_uv(cam: Camera3D, size: Vector2) -> Vector2:
	var sun := GnScene.find_role("sun") as DirectionalLight3D
	if sun == null:
		return Vector2(-10, -10)
	var toward := sun.global_transform.basis.z  # a light shines along -Z
	var far := cam.global_position + toward * 1000.0
	if cam.is_position_behind(far):
		return Vector2(-10, -10)
	return cam.unproject_position(far) / size


# Exposure and depth of field onto a camera (the preview's or the render's).
# `focus_auto` is the distance to whatever is in the middle of the frame,
# used when the look's focus is 0.
static func apply_camera(target: Camera3D, look: Dictionary, focus_auto: float) -> void:
	var attrs := CameraAttributesPractical.new()
	attrs.exposure_multiplier = pow(2.0, float(look.exposure))
	var dof := float(look.dof)
	if dof > 0.0:
		var focus: float = float(look.focus) if float(look.focus) > 0.0 else focus_auto
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = focus * 1.15
		attrs.dof_blur_far_transition = maxf(focus * 0.8, 1.0)
		attrs.dof_blur_near_enabled = true
		attrs.dof_blur_near_distance = focus * 0.6
		attrs.dof_blur_near_transition = maxf(focus * 0.3, 0.3)
		attrs.dof_blur_amount = dof * 0.25
	target.attributes = attrs


# 2-point perspective: the camera is levelled so verticals stay vertical, and
# the frustum is shifted to keep the same framing, the way a shift lens does.
static func apply_lens(target: Camera3D, source: Camera3D, look: Dictionary) -> void:
	target.global_transform = source.global_transform
	target.fov = source.fov
	# The near clip is also the section cut (see gn_sections.gd).
	target.near = source.near
	target.far = source.far
	if source.projection == Camera3D.PROJECTION_ORTHOGONAL:
		target.projection = Camera3D.PROJECTION_ORTHOGONAL
		target.size = source.size
		return
	target.projection = Camera3D.PROJECTION_PERSPECTIVE
	if not look.get("two_point", false):
		return
	var fwd := -source.global_transform.basis.z
	var pitch := asin(clampf(fwd.y, -0.99, 0.99))
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	if flat.length() < 0.01:
		return
	target.global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), source.global_transform.origin)
	target.projection = Camera3D.PROJECTION_FRUSTUM
	target.size = 2.0 * target.near * tan(deg_to_rad(source.fov) * 0.5)
	target.frustum_offset = Vector2(0.0, target.near * tan(pitch))
