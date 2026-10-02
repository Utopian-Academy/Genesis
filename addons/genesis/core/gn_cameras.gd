@tool
extends RefCounted

# Saved views. A saved view is an ordinary Camera3D under a "Cameras" node,
# named "Camera 01", "Camera 02"... in the order they were made.
#
# Godot 4.7 gives plugins no way to move the editor's own camera, so a view
# is recalled by selecting its camera and showing what it sees in the dock's
# preview, which is also exactly what gets rendered.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

# Full-frame 35 mm: 24 mm tall. The cameras keep height, so the focal length
# maps to the vertical field of view.
const SENSOR_HEIGHT_MM := 24.0


static func container() -> Node3D:
	return GnScene.find_role("cameras") as Node3D


static func cameras() -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	var c := container()
	if c:
		for child in c.get_children():
			if child is Camera3D:
				out.append(child)
	return out


# Copies what the editor view currently shows into a new saved camera.
static func save_view() -> Camera3D:
	var root := GnScene.root()
	var vp := EditorInterface.get_editor_viewport_3d(0)
	if root == null or vp == null or vp.get_camera_3d() == null:
		return null
	var editor_cam := vp.get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "Camera %02d" % (cameras().size() + 1)
	cam.global_transform = editor_cam.global_transform
	cam.fov = editor_cam.fov
	cam.near = 0.1
	cam.far = 2000.0
	add(cam)
	return cam


## Keeps a camera made elsewhere (a plan, a section) with the saved views.
static func add(cam: Camera3D) -> void:
	var root := GnScene.root()
	if root == null:
		return
	var c := container()
	if c == null:
		c = Node3D.new()
		c.name = "Cameras"
		c.set_meta(GnScene.ROLE, "cameras")
		c.add_child(cam)
		GnScene.add_nodes([c], root, "Genesis: save %s" % cam.name)
	else:
		GnScene.add_node(cam, c, "Genesis: save %s" % cam.name)
	GnScene.select(cam)


static func focal_length(cam: Camera3D) -> float:
	return SENSOR_HEIGHT_MM / (2.0 * tan(deg_to_rad(cam.fov) / 2.0))


static func set_focal_length(cam: Camera3D, mm: float) -> void:
	var fov := rad_to_deg(2.0 * atan(SENSOR_HEIGHT_MM / (2.0 * mm)))
	GnScene.set_props("Genesis: focal length", [[cam, "fov", fov]])
