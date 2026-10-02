@tool
extends Node3D

# A floor plan to build on: a scanned drawing, a screenshot of a venue's
# plan, a page of a PDF, laid flat on the ground at its true size. Its white
# paper can be made clear so only the linework shows over the floor.
#
# Set its size once with two clicks: click two points whose real distance is
# known (a dimensioned wall, a doorway, a scale bar) and type the distance;
# everything is then to scale. The node's position is the plan's middle.

## The plan image, inside the project.
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var image: String = "":
	set(v): image = v; _texture = null; _queue()
## Metres per pixel of the image.
@export_range(0.00001, 1.0, 0.00001, "or_greater") var metres_per_pixel: float = 0.01:
	set(v): metres_per_pixel = v; _queue()
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.85:
	set(v): opacity = v; _queue()
## Make white paper see-through, leaving the linework.
@export var white_is_clear: bool = true:
	set(v): white_is_clear = v; _queue()
## How far above the node it lies, so it never flickers into the floor.
@export_range(0.0, 0.1, 0.001) var lift: float = 0.002:
	set(v): lift = v; _queue()

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D plan : source_color, filter_linear_mipmap_anisotropic;
uniform float opacity = 0.85;
uniform bool white_is_clear = true;
void fragment() {
	vec4 c = texture(plan, UV);
	float ink = 1.0 - dot(c.rgb, vec3(0.299, 0.587, 0.114));
	if (white_is_clear) {
		// A pixel is ink laid over white paper: take the paper back out, so
		// a thin line softened by the image's filtering stays its own colour.
		float k = max(ink, 0.001);
		ALBEDO = clamp((c.rgb - vec3(1.0 - k)) / k, 0.0, 1.0);
		ALPHA = opacity * c.a * clamp(ink * 1.6, 0.0, 1.0);
	} else {
		ALBEDO = c.rgb;
		ALPHA = opacity * c.a;
	}
}
"""

var _pending := false
var _texture: Texture2D
var _mesh: MeshInstance3D


func _ready() -> void:
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


func pixels() -> Vector2i:
	var t := _load()
	return Vector2i(t.get_width(), t.get_height()) if t else Vector2i.ZERO


## The plan's size on the ground, metres.
func size_m() -> Vector2:
	return Vector2(pixels()) * metres_per_pixel


## Rescales the plan so the distance between two points on it (world
## positions, clicked on the plan) is `real` metres, keeping the first point
## where it is. Returns the factor it changed by.
func calibrate(a: Vector3, b: Vector3, real: float) -> float:
	var la := global_transform.affine_inverse() * a
	var lb := global_transform.affine_inverse() * b
	var measured := Vector2(lb.x - la.x, lb.z - la.z).length()
	if measured < 1e-6 or real <= 0.0:
		return 1.0
	var k := real / measured
	metres_per_pixel *= k
	# The plan scales about its middle (this node); move it so point a stays put.
	var a_flat := Vector3(la.x, 0.0, la.z)
	position += global_transform.basis * (a_flat - a_flat * k)
	_rebuild()
	return k


func report_text() -> String:
	var s := size_m()
	if s == Vector2.ZERO:
		return "No image."
	return "%s: %.2f × %.2f m, %.1f mm per pixel" % [image.get_file(), s.x, s.y, metres_per_pixel * 1000.0]


func _load() -> Texture2D:
	if _texture == null and image != "":
		var img := Image.load_from_file(ProjectSettings.globalize_path(image))
		if img:
			img.generate_mipmaps()
			_texture = ImageTexture.create_from_image(img)
	return _texture


func _rebuild() -> void:
	_pending = false
	if _mesh == null:
		for c in get_children():
			if c.has_meta(&"gn_generated"):
				remove_child(c)
				c.queue_free()
		_mesh = MeshInstance3D.new()
		_mesh.name = "Plan"
		_mesh.set_meta(&"gn_generated", true)
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)
	var tex := _load()
	var size := size_m()
	if tex == null or size == Vector2.ZERO:
		_mesh.mesh = null
		return
	var plane := PlaneMesh.new()
	plane.size = size
	_mesh.mesh = plane
	_mesh.position = Vector3(0, lift, 0)
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	mat.shader = shader
	mat.set_shader_parameter("plan", tex)
	mat.set_shader_parameter("opacity", opacity)
	mat.set_shader_parameter("white_is_clear", white_is_clear)
	_mesh.material_override = mat
