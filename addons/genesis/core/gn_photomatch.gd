@tool
extends RefCounted

# Photo match: a photograph of the real site or venue behind the design,
# with the design's shadows falling onto the photographed ground.
#
# The photo belongs to a saved camera (copied into the project so the scene
# stays self-contained). Matching the camera to the photo is done by eye with
# three controls a photographer already thinks in: focal length (35 mm
# equivalent), camera height, and where the horizon sits in the frame. The
# gizmo does the rest: move and turn the camera until the design sits right.
#
# At render time the design is composited into the photo by differential
# rendering (see gn_photo_compose.gdshader): Genesis's own ground is
# swapped for a plain stand-in floor, and three passes give the design, its
# shadows and its contact shading on the photographed ground.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const COMPOSE := preload("res://addons/genesis/core/gn_photo_compose.gdshader")

# Scene roles that are the world, not the design, and stay put between passes.
const WORLD_ROLES := ["environment", "sun", "ground", "cameras", "movie"]

const META := &"gn_backplate"
const DIR := "res://genesis_data/backplates"


static func photo(cam: Camera3D) -> String:
	return str(cam.get_meta(META, {}).get("photo", "")) if cam else ""


static func shadow_strength(cam: Camera3D) -> float:
	return float(cam.get_meta(META, {}).get("shadows", 0.7)) if cam else 0.7


# Copies the photo into the project and attaches it to the camera (undoable).
static func set_photo(cam: Camera3D, source: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	# Photos are backgrounds, not textures: keep them out of the importer.
	if not FileAccess.file_exists(DIR + "/.gdignore"):
		FileAccess.open(DIR + "/.gdignore", FileAccess.WRITE).close()
	var dest := "%s/%s" % [DIR, source.get_file()]
	if ProjectSettings.globalize_path(dest) != source.replace("\\", "/"):
		if DirAccess.copy_absolute(source, ProjectSettings.globalize_path(dest)) != OK:
			return "Could not copy %s into the project." % source.get_file()
	var data: Dictionary = cam.get_meta(META, {}).duplicate()
	data["photo"] = dest
	GnScene.set_props("Genesis: photo match", [[cam, "metadata/" + META, data]])
	return ""


static func clear_photo(cam: Camera3D) -> void:
	GnScene.set_props("Genesis: remove photo", [[cam, "metadata/" + META, {}]])


static func set_value(cam: Camera3D, key: String, value: Variant) -> void:
	var data: Dictionary = cam.get_meta(META, {}).duplicate()
	data[key] = value
	GnScene.set_props("Genesis: photo match %s" % key, [[cam, "metadata/" + META, data]])


# The photo as an image, or null. Loaded from disk each time: backplates are
# outside the importer, and they are only read at render and preview time.
static func load_photo(cam: Camera3D) -> Image:
	var p := photo(cam)
	if p == "":
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(p))
	return img if img and not img.is_empty() else null


# Horizon placement: where the horizon sits in the frame (0 top, 1 bottom)
# fixes the camera's tilt for its field of view. Returns the pitch in degrees.
static func pitch_for_horizon(horizon: float, vfov_deg: float) -> float:
	return rad_to_deg(atan((horizon - 0.5) * 2.0 * tan(deg_to_rad(vfov_deg) * 0.5)))


# Tilts the camera so the horizon lands where it is in the photo, keeping
# its heading. Undoable.
static func match_horizon(cam: Camera3D, horizon: float) -> void:
	var fwd := -cam.global_transform.basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	var pitch := deg_to_rad(pitch_for_horizon(horizon, cam.fov))
	var rot := Vector3(pitch, yaw, 0.0)
	GnScene.set_props("Genesis: match horizon", [[cam, "rotation", rot]])


static func set_height(cam: Camera3D, metres: float) -> void:
	var p := cam.position
	p.y = metres
	GnScene.set_props("Genesis: camera height", [[cam, "position", p]])


# -------------------------------------------------------------------------
# Render-time staging. Everything here is temporary and put back by `end`.
# -------------------------------------------------------------------------
class Staging:
	var floor: MeshInstance3D
	var design: Array = []   # nodes toggled between passes
	var hidden: Array = []   # nodes hidden for the whole render
	var env_before: Dictionary = {}


static func begin(cam: Camera3D, parent: Node) -> Staging:
	var st := Staging.new()
	var root := GnScene.root()
	var ground := GnScene.find_role("ground") as Node3D
	if ground and ground.visible:
		ground.visible = false
		st.hidden.append(ground)
	for n in root.get_children():
		if n is Node3D and n.visible and str(n.get_meta(GnScene.ROLE, "")) not in WORLD_ROLES:
			st.design.append(n)
	# A plain matte floor where the photographed ground is: only its
	# darkening matters. Mid-grey, not white: a white floor in sun clips at
	# full brightness and hides how much a shadow darkens it.
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.18)
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	plane.material = mat
	st.floor = MeshInstance3D.new()
	st.floor.mesh = plane
	st.floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(st.floor)
	st.floor.global_position = Vector3(0, 0.002, 0)
	# The sky still lights the scene; it is just not drawn, so the photo shows
	# through. Fog would veil the design differently from the photo.
	var world := GnScene.find_role("environment") as WorldEnvironment
	if world and world.environment:
		var env := world.environment
		st.env_before = {"background_mode": env.background_mode, "fog_enabled": env.fog_enabled,
			"background_color": env.background_color}
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.background_color = Color(0, 0, 0, 0)
		env.fog_enabled = false
	return st


static func show_design(st: Staging, on: bool) -> void:
	for n in st.design:
		n.visible = on


static func end(st: Staging) -> void:
	show_design(st, true)
	for n in st.hidden:
		n.visible = true
	if st.floor:
		st.floor.queue_free()
	var world := GnScene.find_role("environment") as WorldEnvironment
	if world and world.environment:
		for k in st.env_before:
			world.environment.set(k, st.env_before[k])


# The three passes and the photo into one image, on the GPU.
static func compose(with_design: Image, floor_only: Image, design_only: Image, backplate: Image,
		strength: float, host: Node) -> Image:
	var size := with_design.get_size()
	var mat := ShaderMaterial.new()
	mat.shader = COMPOSE
	mat.set_shader_parameter("with_design", ImageTexture.create_from_image(with_design))
	mat.set_shader_parameter("floor_only", ImageTexture.create_from_image(floor_only))
	mat.set_shader_parameter("design_only", ImageTexture.create_from_image(design_only))
	mat.set_shader_parameter("photo", ImageTexture.create_from_image(backplate))
	# Fill the frame with the photo, cropping the overflow, never stretching.
	var fit := maxf(float(size.x) / backplate.get_width(), float(size.y) / backplate.get_height())
	var shown := Vector2(size) / (Vector2(backplate.get_size()) * fit)
	mat.set_shader_parameter("photo_scale", shown)
	mat.set_shader_parameter("photo_offset", (Vector2.ONE - shown) * 0.5)
	mat.set_shader_parameter("strength", strength)
	var sub := SubViewport.new()
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	rect.material = mat
	sub.add_child(rect)
	host.add_child(sub)
	for i in 3:
		await RenderingServer.frame_post_draw
	var out := sub.get_texture().get_image()
	host.remove_child(sub)
	sub.queue_free()
	return out
