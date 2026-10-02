@tool
extends RefCounted

# The two-click tool. As a tape measure: click a point on any surface, then
# another, and a dimension is left between them. As a line placer (set
# `line_asset`): the same two clicks put copies of a model along the line.
# Esc or a right click drops the first point. Like the brush, it knows
# nothing of the editor's plumbing; plugin.gd hands it events.

const GnSurface := preload("res://addons/genesis/core/gn_surface.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const Dimension := preload("res://addons/genesis/set/gn_dimension.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const Drawing := preload("res://addons/genesis/cad/gn_drawing.gd")

signal changed
signal measured(dimension: Node3D)

var active := false:
	set(v):
		active = v
		_first = Vector3.INF
		_hover = Vector3.INF
		_surface = null
		changed.emit()

# Line placing: the model, its category, the gap and which way copies face.
# Empty `line_asset` means measuring.
var line_asset := ""
var line_category := ""
var line_spacing := 5.0
var line_facing := "along"
# Picking two points for something else (setting a plan's scale): called
# with both points instead of leaving a dimension.
var pick := Callable()

var _first := Vector3.INF
var _hover := Vector3.INF
var _surface: GnSurface


func handle(camera: Camera3D, event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventMouseMotion:
		_hover = _hit(camera, event.position)
		changed.emit()
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_first = Vector3.INF
		changed.emit()
		return true
	if not (event is InputEventMouseButton and event.pressed):
		return false
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_first = Vector3.INF
		changed.emit()
		return true
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	var p := _hit(camera, event.position)
	if p == Vector3.INF:
		return true
	if _first == Vector3.INF:
		_first = p
	else:
		if pick.is_valid():
			var done := pick
			pick = Callable()
			active = false
			done.call(_first, p)
			return true
		if line_asset != "":
			GnPlacement.along_line(line_asset, line_category, _first, p, line_spacing, line_facing)
			_surface = null
		else:
			measure(_first, p)
		_first = Vector3.INF
	changed.emit()
	return true


## Leaves a dimension between two points, as one undo step.
func measure(a: Vector3, b: Vector3) -> Node3D:
	var root := GnScene.root()
	if root == null:
		return null
	var dim := Dimension.new()
	dim.start = a
	dim.end = b
	dim.name = "Dimension %s" % dim.text()
	GnScene.add_node(dim, root, "Genesis: measure %s" % dim.text(), "dimension")
	_surface = null  # the new dimension is itself something to snap to next time
	measured.emit(dim)
	return dim


## Screen points for the overlay: the line from the first point to the
## cursor, and the running length.
func preview(camera: Camera3D) -> Dictionary:
	if _first == Vector3.INF or _hover == Vector3.INF or camera == null:
		return {}
	if camera.is_position_behind(_first) or camera.is_position_behind(_hover):
		return {}
	var run := _first.distance_to(_hover)
	var text := "%.3f m" % run
	if line_asset != "":
		text += ", %d copies" % (int(floor(run / maxf(line_spacing, 0.01) + 0.001)) + 1)
	return {"from": camera.unproject_position(_first), "to": camera.unproject_position(_hover), "text": text}


func _hit(camera: Camera3D, pos: Vector2) -> Vector3:
	return _snapped(camera, _surface_hit(camera, pos))


# A CAD drawing's line ends and corners pull the point to them when it is
# within about 12 pixels, so measuring and placing work to what was drawn.
func _snapped(camera: Camera3D, p: Vector3) -> Vector3:
	if p == Vector3.INF or GnScene.root() == null:
		return p
	var high := maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
	var radius := camera.global_position.distance_to(p) * tan(deg_to_rad(camera.fov * 0.5)) * 2.0 / high * 12.0
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		radius = camera.size / high * 12.0
	var best := p
	var best_d := INF
	for d in GnScene.root().get_tree().get_nodes_in_group(Drawing.GROUP):
		if not (d as Node3D).is_visible_in_tree():
			continue
		var s: Vector3 = d.snap(p, radius)
		if s != Vector3.INF and s.distance_to(p) < best_d:
			best_d = s.distance_to(p)
			best = s
	return best


func _surface_hit(camera: Camera3D, pos: Vector2) -> Vector3:
	if _surface == null:
		_surface = GnSurface.new(GnScene.root())
	var hit := _surface.cast(camera.project_ray_origin(pos), camera.project_ray_normal(pos))
	if hit.is_empty():
		# Nothing there: the ground plane at height 0.
		var plane := Plane(Vector3.UP, 0.0)
		var at = plane.intersects_ray(camera.project_ray_origin(pos), camera.project_ray_normal(pos))
		return at if at != null else Vector3.INF
	return hit.position
