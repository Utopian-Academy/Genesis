@tool
extends RefCounted

# 360-degree panoramas: from a saved camera's position, six 90-degree views
# (one per cube face) stitched into an equirectangular image, the format
# every 360 viewer and social site reads. The look's grading applies; lens
# effects that make no sense in 360 (depth of field, 2-point perspective,
# vignette) are left out.

const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnLook := preload("res://addons/genesis/core/gn_look.gd")
const EQUIRECT := preload("res://addons/genesis/core/gn_equirect.gdshader")

# Face name -> the direction its camera looks and its up vector.
const FACES := {
	"px": [Vector3.RIGHT, Vector3.UP], "nx": [Vector3.LEFT, Vector3.UP],
	"py": [Vector3.UP, Vector3.BACK], "ny": [Vector3.DOWN, Vector3.FORWARD],
	"pz": [Vector3.BACK, Vector3.UP], "nz": [Vector3.FORWARD, Vector3.UP],
}


const EQUIRECT_STEREO := preload("res://addons/genesis/core/gn_equirect_stereo.gdshader")
# Stereo: strips round the circle per eye, each this wide and this tall.
const STRIPS := 24
const STRIP_HFOV := 18.0
const STRIP_VFOV := 125.0
## The distance between a person's eyes, metres.
const IPD := 0.064


## A stereo 360 panorama for VR headsets and 3D 360 players: the left eye
## above the right (top-bottom), `width` wide and as tall. Returns the saved
## path, or "".
static func render_stereo(camera: Camera3D, width: int, host: Node) -> String:
	var look := GnLook.get_look(camera)
	var flat := look.duplicate()
	for k in ["dof", "vignette", "aberration", "two_point"]:
		flat[k] = GnLook.DEFAULTS[k]
	var probe := Camera3D.new()
	probe.name = "PanoramaStrip"
	host.add_child(probe)
	probe.keep_aspect = Camera3D.KEEP_HEIGHT
	probe.near = 0.05
	probe.far = camera.far
	probe.set_meta(GnLook.META, flat)
	var centre := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var yaw := atan2(fwd.x, -fwd.z)
	var half_h := tan(deg_to_rad(STRIP_HFOV * 0.5))
	var half_v := tan(deg_to_rad(STRIP_VFOV * 0.5))
	var sh := maxi(width / 2, 512)
	var sw := maxi(int(round(sh * half_h / half_v)), 16)
	# The straight-up and straight-down views, shared by both eyes.
	probe.fov = 90.0
	var poles := {}
	for face in ["py", "ny"]:
		probe.global_transform = Transform3D(Basis.looking_at(FACES[face][0], FACES[face][1]), centre)
		var p: String = await GnRender.render(probe, Vector2i(sh / 2, sh / 2), host, false)
		if p == "":
			probe.queue_free()
			return ""
		poles[face] = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(p)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var eyes: Array = []
	for eye in [-1.0, 1.0]:
		var atlas := Image.create(sw * STRIPS, sh, false, Image.FORMAT_RGB8)
		probe.fov = STRIP_VFOV
		for k in STRIPS:
			var lon := -PI + (k + 0.5) * TAU / STRIPS + yaw
			var ahead := Vector3(sin(lon), 0, -cos(lon))
			var right := Vector3(cos(lon), 0, sin(lon))
			# The eye as the head turns to face this way: half the eye
			# distance to that side of the centre.
			probe.global_transform = Transform3D(Basis.looking_at(ahead, Vector3.UP), centre + right * eye * IPD * 0.5)
			var p: String = await GnRender.render(probe, Vector2i(sw, sh), host, false)
			if p == "":
				probe.queue_free()
				return ""
			var img := Image.load_from_file(ProjectSettings.globalize_path(p))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			img.convert(Image.FORMAT_RGB8)
			if img.get_size() != Vector2i(sw, sh):
				img.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
			atlas.blit_rect(img, Rect2i(0, 0, sw, sh), Vector2i(k * sw, 0))
		var mat := ShaderMaterial.new()
		mat.shader = EQUIRECT_STEREO
		mat.set_shader_parameter("strips", ImageTexture.create_from_image(atlas))
		mat.set_shader_parameter("count", STRIPS)
		mat.set_shader_parameter("half_h", half_h)
		mat.set_shader_parameter("half_v", half_v)
		mat.set_shader_parameter("py", poles.py)
		mat.set_shader_parameter("ny", poles.ny)
		mat.set_shader_parameter("yaw", yaw)
		eyes.append(await _draw(mat, Vector2i(width, width / 2), host))
	probe.queue_free()
	var out := Image.create(width, width, false, Image.FORMAT_RGB8)
	for i in 2:
		var e: Image = eyes[i]
		e.convert(Image.FORMAT_RGB8)
		out.blit_rect(e, Rect2i(0, 0, width, width / 2), Vector2i(0, i * (width / 2)))
	var file := "%s/%s_360_stereo.png" % [GnRender.OUTPUT_DIR, str(camera.name).replace(" ", "")]
	return file if out.save_png(file) == OK else ""


# Draws a full-frame material into an image of `size`.
static func _draw(mat: Material, size: Vector2i, host: Node) -> Image:
	var sub := SubViewport.new()
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	rect.material = mat
	sub.add_child(rect)
	host.add_child(sub)
	var low_power := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	for i in 3:
		await RenderingServer.frame_post_draw
	OS.low_processor_usage_mode = low_power
	var out := sub.get_texture().get_image()
	host.remove_child(sub)
	sub.queue_free()
	return out


# `width` is the panorama's width; its height is half that. Returns the
# saved path, or "".
static func render(camera: Camera3D, width: int, host: Node) -> String:
	var face_px := maxi(width / 4, 256)
	var look := GnLook.get_look(camera)
	var flat := look.duplicate()
	for k in ["dof", "vignette", "aberration", "two_point"]:
		flat[k] = GnLook.DEFAULTS[k]
	var probe := Camera3D.new()
	probe.name = "PanoramaFace"
	host.add_child(probe)
	probe.fov = 90.0
	probe.keep_aspect = Camera3D.KEEP_HEIGHT
	probe.near = 0.05
	probe.far = camera.far
	probe.set_meta(GnLook.META, flat)
	var mat := ShaderMaterial.new()
	mat.shader = EQUIRECT
	for face in FACES:
		var look_dir: Vector3 = FACES[face][0]
		var up: Vector3 = FACES[face][1]
		probe.global_transform = Transform3D(Basis.looking_at(look_dir, up), camera.global_position)
		var path: String = await GnRender.render(probe, Vector2i(face_px, face_px), host)
		if path == "":
			probe.queue_free()
			return ""
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		mat.set_shader_parameter(face, ImageTexture.create_from_image(img))
	probe.queue_free()
	# Centre the panorama on where the saved camera was looking.
	var fwd := -camera.global_transform.basis.z
	mat.set_shader_parameter("yaw", atan2(fwd.x, -fwd.z))
	var size := Vector2i(width, width / 2)
	var sub := SubViewport.new()
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	rect.material = mat
	sub.add_child(rect)
	host.add_child(sub)
	var low_power := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	for i in 3:
		await RenderingServer.frame_post_draw
	OS.low_processor_usage_mode = low_power
	var out := sub.get_texture().get_image()
	host.remove_child(sub)
	sub.queue_free()
	var file := "%s/%s_360.png" % [GnRender.OUTPUT_DIR, str(camera.name).replace(" ", "")]
	return file if out.save_png(file) == OK else ""
