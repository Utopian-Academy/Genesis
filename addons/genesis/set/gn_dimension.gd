@tool
extends Node3D

# A measured dimension: a line between two points with ticks at the ends and
# the distance written over the middle, like a dimension on a drawing. It is
# a real object in the scene, so it shows in renders (put it on a layer to
# hide it for the final ones). Change the ends in the Inspector.

@export var start: Vector3 = Vector3.ZERO:
	set(v): start = v; _queue()
@export var end: Vector3 = Vector3(1, 0, 0):
	set(v): end = v; _queue()
@export var colour: Color = Color(1.0, 0.85, 0.2):
	set(v): colour = v; _queue()
## Text height, metres. 0 scales with the length.
@export_range(0.0, 5.0, 0.01) var text_size: float = 0.0:
	set(v): text_size = v; _queue()

var _pending := false


func _ready() -> void:
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


func length() -> float:
	return start.distance_to(end)


## "12.400 m", to the millimetre (millimetres under a metre).
func text() -> String:
	var d := length()
	return "%d mm" % roundi(d * 1000.0) if d < 1.0 else "%.3f m" % d


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	var d := length()
	if d < 0.001:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = colour
	var thick := clampf(d * 0.004, 0.01, 0.2)
	var along := (end - start).normalized()
	var side := along.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	_bar(start, end, thick, mat)
	var tick := thick * 12.0
	for p in [start, end]:
		_bar(p - side * tick * 0.5, p + side * tick * 0.5, thick, mat)
	var label := Label3D.new()
	label.text = text()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = colour
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.outline_size = 12
	label.font_size = 64
	var h := text_size if text_size > 0.0 else clampf(d * 0.06, 0.12, 3.0)
	label.pixel_size = h / 64.0
	label.position = (start + end) * 0.5 + Vector3.UP * (h * 0.6 + thick)
	label.set_meta(&"gn_generated", true)
	add_child(label)


func _bar(a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thick, thick, a.distance_to(b))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) * 0.5
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(b - a, up), mid)
	mi.set_meta(&"gn_generated", true)
	add_child(mi)
