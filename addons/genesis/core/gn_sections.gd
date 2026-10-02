@tool
extends RefCounted

# Cameras that cut the design open. A camera's near clip is a cutting plane
# at right angles to its view: everything nearer than it is cut away. So a
# plan is a camera looking straight down from above the roof, orthographic,
# with its near clip at the cut height; a section is one looking across, with
# its near clip at the cut line. The same near clip on any saved camera cuts
# a perspective view open, the dollhouse shot.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")

# What is not "the design": the world around it and our own helpers.
const NOT_DESIGN := ["ground", "environment", "sun", "site", "cameras", "dimension", "weather", "terrain", "movie"]


## The bounding box of the selection, or of the whole design if nothing
## usable is selected.
static func design_bounds() -> AABB:
	var nodes: Array = EditorInterface.get_selection().get_selected_nodes()
	var box := _bounds(nodes)
	if box.size == Vector3.ZERO and GnScene.root():
		box = _bounds(GnScene.root().get_children())
	return box


static func _bounds(nodes: Array) -> AABB:
	var box := AABB()
	var first := true
	for n in nodes:
		if not n is Node3D or _excluded(n):
			continue
		var found: Array = n.find_children("*", "GeometryInstance3D", true, false)
		if n is GeometryInstance3D:
			found.append(n)
		for g in found:
			if _excluded(g) or not (g as Node3D).is_visible_in_tree():
				continue
			var b: AABB = (g as Node3D).global_transform * (g as VisualInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box


static func _excluded(n: Node) -> bool:
	while n != null and n != GnScene.root():
		if n.get_meta(GnScene.ROLE, "") in NOT_DESIGN:
			return true
		n = n.get_parent()
	return false


## A plan: looking straight down, cut at `cut_height` metres.
static func plan(cut_height: float, bounds := AABB()) -> Camera3D:
	var box := bounds if bounds.size != Vector3.ZERO else design_bounds()
	var cam := Camera3D.new()
	cam.name = "Plan at %.1f m" % cut_height
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.x, box.size.z) * 1.15 + 1.0
	var top := box.end.y + 5.0
	cam.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(box.get_center().x, top, box.get_center().z))
	cam.near = maxf(top - cut_height, 0.05)
	cam.far = top - box.position.y + 10.0
	return _keep(cam)


## A section: looking north (-Z) across the design, cut on the line z = at.
## Looking east (-X) instead with `across_x`, cut on x = at.
static func section(at: float, across_x := false, bounds := AABB()) -> Camera3D:
	var box := bounds if bounds.size != Vector3.ZERO else design_bounds()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = box.size.y * 1.3 + 1.0
	var c := box.get_center()
	if across_x:
		cam.name = "Section x %.1f m" % at
		var x := box.end.x + 5.0
		cam.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, c.y, c.z))
		cam.near = maxf(x - at, 0.05)
		cam.far = x - box.position.x + 10.0
	else:
		cam.name = "Section z %.1f m" % at
		var z := box.end.z + 5.0
		cam.transform = Transform3D(Basis(), Vector3(c.x, c.y, z))
		cam.near = maxf(z - at, 0.05)
		cam.far = z - box.position.z + 10.0
	return _keep(cam)


## An elevation: a section that cuts nothing.
static func elevation(across_x := false) -> Camera3D:
	var box := design_bounds()
	var cam := section(box.end.x + 1.0 if across_x else box.end.z + 1.0, across_x, box)
	cam.name = "Elevation %s" % ("east" if across_x else "south")
	return cam


static func _keep(cam: Camera3D) -> Camera3D:
	GnCameras.add(cam)
	return cam
