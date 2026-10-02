@tool
extends RefCounted

# One beautiful still. An offscreen SubViewport the size of the output looks
# into the same 3D world the editor is showing, through a copy of the chosen
# camera, and its texture is saved as a PNG. Godot's renderer does all of the
# work; the only decision here is how many frames to let it settle.

const SIZES := {
	"1920 × 1080 (HD)": Vector2i(1920, 1080),
	"2560 × 1440 (QHD)": Vector2i(2560, 1440),
	"3840 × 2160 (4K)": Vector2i(3840, 2160),
	"2160 × 2700 (portrait 4:5)": Vector2i(2160, 2700),
	"2048 × 2048 (square)": Vector2i(2048, 2048),
	"7680 × 4320 (8K)": Vector2i(7680, 4320),
}

const OUTPUT_DIR := "res://renders"
const GnQuality := preload("res://addons/genesis/core/gn_quality.gd")
const GnLook := preload("res://addons/genesis/core/gn_look.gd")
const GnSurface := preload("res://addons/genesis/core/gn_surface.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnPhotomatch := preload("res://addons/genesis/core/gn_photomatch.gd")
const GnStaging := preload("res://addons/genesis/core/gn_staging.gd")
const GnAccumulate := preload("res://addons/genesis/core/gn_accumulate.gd")

# Rendering at a multiple of the output size and filtering down is the
# cleanest antialiasing there is: no shimmer on thin mullions, no jaggies on
# roof edges. Kept lower for huge outputs so the GPU is not asked for 16K.
static func supersample(size: Vector2i) -> float:
	var px := size.x * size.y
	if px <= 2560 * 1440:
		return 2.0
	return 1.5 if px <= 3840 * 2160 else 1.0



# `host` is any node inside the editor tree; the SubViewport lives under it
# only for the capture. Returns the saved path, or "" on failure.
# `debug_draw` and `transparent` are for render passes: a viewport debug view
# (the normal buffer), and a transparent background instead of the sky.
# `samples` above 1 makes a photoreal still by accumulation (gn_accumulate.gd):
# true lens blur, soft sun shadows and perfect edges, at that many renders.
static func render(camera: Camera3D, size: Vector2i, host: Node, high := true,
		debug_draw := Viewport.DEBUG_DRAW_DISABLED, transparent := false, samples := 0) -> String:
	var editor_vp := EditorInterface.get_editor_viewport_3d(0)
	if camera == null or editor_vp == null:
		return ""
	var accumulate := samples > 1 and high and debug_draw == Viewport.DEBUG_DRAW_DISABLED and not transparent \
		and GnPhotomatch.load_photo(camera) == null
	# Accumulation antialiases by itself; supersampling on top only costs.
	var ss := supersample(size) if high and not accumulate else 1.0
	var sub := SubViewport.new()
	sub.size = Vector2i(roundi(size.x * ss), roundi(size.y * ss))
	sub.world_3d = editor_vp.find_world_3d()
	sub.msaa_3d = Viewport.MSAA_4X
	sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.debug_draw = debug_draw
	sub.transparent_bg = transparent
	var look := GnLook.get_look(camera)
	var cam := Camera3D.new()
	cam.near = camera.near
	cam.far = camera.far
	cam.keep_aspect = camera.keep_aspect
	sub.add_child(cam)
	host.add_child(sub)
	GnLook.apply_lens(cam, camera, look)
	GnLook.apply_camera(cam, look, focus_distance(camera))
	cam.make_current()
	# The editor only redraws when something changes, and barely at all while
	# its window is unfocused, so waiting for frames could take minutes. Force
	# continuous drawing for the few frames the capture needs.
	var low_power := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	var quality: GnQuality.State = GnQuality.begin_high() if high else null
	var frames := GnQuality.SETTLE_HIGH if high else GnQuality.SETTLE_DRAFT
	var image: Image
	var backplate := GnPhotomatch.load_photo(camera)
	# The Clay look: every surface plain white matte for the capture.
	var clay: Array = GnStaging.stage("clay") if look.get("clay", false) else []
	# A camera that cuts the design open (a plan, a section, a cut-away view)
	# shows its cut walls filled solid.
	var cut: Array = GnStaging.stage("cut") if camera.near > 0.15 else []
	if backplate:
		image = await _photo_match(sub, camera, backplate, frames, host)
	elif accumulate:
		for i in frames:
			await RenderingServer.frame_post_draw
		var focus: float = float(look.focus) if float(look.get("focus", 0.0)) > 0.0 else focus_distance(camera)
		image = await GnAccumulate.capture(sub, cam, samples, focus, float(look.get("dof", 0.0)), host)
	else:
		image = await _capture(sub, frames)
	GnStaging.unstage(clay)
	GnStaging.unstage(cut)
	if quality:
		GnQuality.end(quality)
	OS.low_processor_usage_mode = low_power
	if image and image.get_size() != size:
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	if image and not image.is_empty() and debug_draw == Viewport.DEBUG_DRAW_DISABLED and not transparent:
		look["_sun_uv"] = GnLook.sun_uv(cam, Vector2(sub.size))
		image = await finish(image, look, host)
	host.remove_child(sub)
	sub.queue_free()
	if image == null or image.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	# Renders are output, not assets: keep Godot from importing every PNG.
	if not FileAccess.file_exists(OUTPUT_DIR + "/.gdignore"):
		FileAccess.open(OUTPUT_DIR + "/.gdignore", FileAccess.WRITE).close()
	var scene := EditorInterface.get_edited_scene_root()
	var stem := "%s_%s_%s" % [
		scene.name if scene else "scene",
		camera.name.replace(" ", ""),
		Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_"),
	]
	var path := "%s/%s.png" % [OUTPUT_DIR, stem]
	if image.save_png(path) != OK:
		return ""
	return path


static func _capture(sub: SubViewport, frames: int) -> Image:
	for i in frames:
		await RenderingServer.frame_post_draw
	return sub.get_texture().get_image()


# Three passes composited over the photo (see gn_photo_compose.gdshader):
# the design on a white stand-in floor, the floor alone, the design alone.
static func _photo_match(sub: SubViewport, camera: Camera3D, backplate: Image, frames: int, host: Node) -> Image:
	sub.transparent_bg = true
	var st := GnPhotomatch.begin(camera, sub)
	var with_design := await _capture(sub, frames)
	GnPhotomatch.show_design(st, false)
	var floor_only := await _capture(sub, frames)
	GnPhotomatch.show_design(st, true)
	st.floor.visible = false
	var design_only := await _capture(sub, frames)
	GnPhotomatch.end(st)
	return await GnPhotomatch.compose(with_design, floor_only, design_only, backplate,
		GnPhotomatch.shadow_strength(camera), host)


# What the camera is looking at, for auto-focus: the distance to the first
# surface in the middle of the frame, or 10 m into open sky.
static func focus_distance(camera: Camera3D) -> float:
	var probe := GnSurface.new(GnScene.root())
	var fwd := -camera.global_transform.basis.z
	var hit := probe.cast(camera.global_position, fwd)
	return camera.global_position.distance_to(hit.position) if not hit.is_empty() else 10.0


# The finishing pass: the look's grading, lens and style drawn over the
# image by the same shader the camera preview uses.
static func finish(image: Image, look: Dictionary, host: Node) -> Image:
	var neutral := str(look.get("title", "")) == "" and str(look.get("logo", "")) == ""
	for k in GnLook.FINISH:
		neutral = neutral and is_equal_approx(float(look.get(k, GnLook.DEFAULTS[k])), float(GnLook.DEFAULTS[k]))
	if neutral:
		return image
	var sub := SubViewport.new()
	sub.size = image.get_size()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.size = Vector2(image.get_size())
	var post := GnLook.post_material(look)
	post.set_shader_parameter("sun_uv", look.get("_sun_uv", Vector2(-10, -10)))
	rect.material = post
	sub.add_child(rect)
	# Title overlay: the project name or a caption, bottom-left, sized to the image.
	var title := str(look.get("title", ""))
	if title != "":
		var label := Label.new()
		label.text = title
		var px := int(image.get_height() * float(look.get("title_size", 0.06)))
		label.add_theme_font_size_override("font_size", px)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		label.add_theme_constant_override("shadow_offset_x", maxi(px / 20, 1))
		label.add_theme_constant_override("shadow_offset_y", maxi(px / 20, 1))
		label.position = Vector2(image.get_width() * 0.04, image.get_height() * 0.96 - px * 1.4)
		sub.add_child(label)
	# Logo or image overlay: a practice's logo, a client's, a watermark.
	var logo_path := str(look.get("logo", ""))
	if logo_path != "" and FileAccess.file_exists(logo_path):
		var logo := Image.load_from_file(ProjectSettings.globalize_path(logo_path))
		if logo and not logo.is_empty():
			var h := image.get_height() * float(look.get("logo_size", 0.12))
			var w := h * logo.get_width() / maxf(logo.get_height(), 1.0)
			var margin := image.get_height() * 0.04
			var corner := str(look.get("logo_corner", "Bottom right"))
			var x := margin if corner.ends_with("left") else image.get_width() - margin - w
			var y := margin if corner.begins_with("Top") else image.get_height() - margin - h
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(logo)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			tr.position = Vector2(x, y)
			tr.size = Vector2(w, h)
			tr.modulate.a = float(look.get("logo_opacity", 1.0))
			sub.add_child(tr)
	host.add_child(sub)
	var low_power := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	for i in 3:
		await RenderingServer.frame_post_draw
	OS.low_processor_usage_mode = low_power
	var out := sub.get_texture().get_image()
	host.remove_child(sub)
	sub.queue_free()
	return out if out and not out.is_empty() else image
