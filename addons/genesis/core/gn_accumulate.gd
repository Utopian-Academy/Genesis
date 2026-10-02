@tool
extends RefCounted

# Photoreal stills by accumulation: the same picture rendered many times,
# each time from a slightly different camera and sun, and averaged. What a
# single real-time frame fakes, the average does for real:
#
#   - antialiasing: each sample is nudged by a fraction of a pixel, so edges
#     and thin mullions come out as a true area average;
#   - depth of field: each sample looks through a different point of the
#     lens aperture, re-aimed at the focus distance (a thin lens), so blur
#     grows with distance from the focus exactly as a camera's does, with
#     no halo round foreground edges;
#   - soft shadows: each sample sees the sun from a different point of its
#     disc, so penumbrae widen with distance from what casts them.
#
# The running mean is kept on the GPU in a float viewport that never
# clears; each new sample is drawn over it at 1/n opacity.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

## Aperture radius in metres at the look's full depth of field (1.0): a
## 50 mm lens wide open, near f/1.2.
const APERTURE_M := 0.02
## The sun's disc, degrees across.
const SUN_DEG := 0.55
## Frames per sample, so every screen-space effect sees the new pose.
const FRAMES := 2

static var ENCODE: Shader:
	get:
		if _encode == null:
			_encode = Shader.new()
			_encode.code = """shader_type canvas_item;
void fragment() {
	vec3 c = max(texture(TEXTURE, UV).rgb, vec3(0.0));
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
	COLOR = vec4(mix(hi, lo, vec3(lessThan(c, vec3(0.0031308)))), 1.0);
}"""
		return _encode
static var _encode: Shader


## Renders `samples` jittered frames through `cam` (already in `sub`) and
## returns their average. `focus` is the focus distance in metres and
## `dof` the look's depth of field (0 keeps everything sharp).
static func capture(sub: SubViewport, cam: Camera3D, samples: int, focus: float, dof: float, host: Node) -> Image:
	var base := cam.global_transform
	var ortho := cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	# Perspective cameras become an equivalent off-axis frustum, so the
	# jitter can shift the picture without turning the camera.
	var base_offset := Vector2.ZERO
	if not ortho:
		if cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
			cam.projection = Camera3D.PROJECTION_FRUSTUM
			cam.size = 2.0 * cam.near * tan(deg_to_rad(cam.fov) * 0.5)
		else:
			base_offset = cam.frustum_offset
	# Godot's blur would blur the lens's own blur again.
	if cam.attributes is CameraAttributesPractical:
		var attrs := (cam.attributes as CameraAttributesPractical).duplicate() as CameraAttributesPractical
		attrs.dof_blur_far_enabled = false
		attrs.dof_blur_near_enabled = false
		cam.attributes = attrs
	var sun := GnScene.find_role("sun") as DirectionalLight3D
	var sun_basis := sun.global_basis if sun else Basis()
	var sun_soft := sun.light_angular_distance if sun else 0.0
	if sun:
		sun.light_angular_distance = 0.0
	var aperture := APERTURE_M * clampf(dof, 0.0, 2.0)

	var acc := SubViewport.new()
	acc.size = sub.size
	acc.use_hdr_2d = true
	acc.transparent_bg = false
	acc.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	acc.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var layer := TextureRect.new()
	layer.texture = sub.get_texture()
	layer.size = Vector2(sub.size)
	layer.material = CanvasItemMaterial.new()
	acc.add_child(layer)
	host.add_child(acc)

	for n in samples:
		# Low-discrepancy points, so 16 samples cover the pixel, the lens
		# and the sun far more evenly than 16 random ones would.
		var pixel := Vector2(_halton(n + 1, 2), _halton(n + 1, 3)) - Vector2(0.5, 0.5)
		var lens := _disc(_halton(n + 1, 5), _halton(n + 1, 7)) * aperture
		var sun_at := _disc(_halton(n + 1, 11), _halton(n + 1, 13)) * deg_to_rad(SUN_DEG * 0.5)
		var shifted := base
		shifted.origin += base.basis.x * lens.x + base.basis.y * lens.y
		cam.global_transform = shifted
		if ortho:
			var px := cam.size / sub.size.y
			cam.global_transform.origin += base.basis.x * pixel.x * px + base.basis.y * pixel.y * px
		else:
			var px := cam.size / sub.size.y
			# Re-aim through the lens point so the focus plane stays put.
			cam.frustum_offset = base_offset + pixel * px - lens * cam.near / maxf(focus, 0.1)
		if sun:
			sun.global_basis = sun_basis * Basis(Vector3.RIGHT, sun_at.y) * Basis(Vector3.UP, sun_at.x)
		for f in FRAMES:
			await RenderingServer.frame_post_draw
		# Draw this sample over the mean so far at 1/n: an exact running average.
		layer.self_modulate.a = 1.0 / (n + 1)
		acc.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw

	# The float viewport averages in linear light (the right place to add
	# light up); one pass on the GPU brings it back to sRGB like every other
	# render, at full precision so the shadows don't band.
	var out := SubViewport.new()
	out.size = sub.size
	out.render_target_update_mode = SubViewport.UPDATE_ONCE
	var encode := TextureRect.new()
	encode.texture = acc.get_texture()
	encode.size = Vector2(sub.size)
	var mat := ShaderMaterial.new()
	mat.shader = ENCODE
	encode.material = mat
	out.add_child(encode)
	host.add_child(out)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := out.get_texture().get_image()
	for v in [out, acc]:
		host.remove_child(v)
		v.queue_free()
	cam.global_transform = base
	if sun:
		sun.global_basis = sun_basis
		sun.light_angular_distance = sun_soft
	if image:
		image.convert(Image.FORMAT_RGBA8)
	return image


static func _halton(i: int, b: int) -> float:
	var f := 1.0
	var r := 0.0
	while i > 0:
		f /= b
		r += f * (i % b)
		i /= b
	return r


# A point in the unit disc, spread evenly (concentric mapping).
static func _disc(u: float, v: float) -> Vector2:
	var a := 2.0 * u - 1.0
	var b := 2.0 * v - 1.0
	if a == 0.0 and b == 0.0:
		return Vector2.ZERO
	if absf(a) > absf(b):
		var t := PI / 4.0 * (b / a)
		return Vector2(cos(t), sin(t)) * a
	var t := PI / 2.0 - PI / 4.0 * (a / b)
	return Vector2(cos(t), sin(t)) * b
