@tool
extends RefCounted

# Puts a model into the scene. Once it is there, moving, rotating, scaling,
# duplicating and deleting are Godot's own gizmos, shortcuts and undo; this
# only decides where a new thing lands.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnSurface := preload("res://addons/genesis/core/gn_surface.gd")
const GnScatter := preload("res://addons/genesis/core/gn_scatter.gd")

# Vegetation looks copy-pasted if every instance faces the same way.
const RANDOM_TURN_CATEGORIES := ["trees", "plants", "grass"]


static func place(path: String, category := "", at = null) -> Node3D:
	var root := GnScene.root()
	if root == null:
		push_warning("Genesis: open or create a 3D scene first.")
		return null
	# A tree with grown variants comes in as any one of them.
	var packed := load(_pick(path, category)) as PackedScene
	if packed == null:
		push_warning("Genesis: %s is not a model Godot can import." % path)
		return null
	var node := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	if node == null:
		return null
	node.name = path.get_file().get_basename().to_pascal_case()
	node.position = at if at is Vector3 else drop_point()
	if category in RANDOM_TURN_CATEGORIES:
		node.rotation.y = randf() * TAU
	# Remembered so other tools know a tree from a building (the fly-through
	# clearance check treats a tree's whole crown as solid).
	if category != "":
		node.set_meta(&"gn_category", category)
	GnScene.add_node(node, root, "Genesis: place %s" % node.name)
	GnScene.select(node)
	return node


# The model itself, or for vegetation any one of its grown variants.
static func _pick(path: String, category: String) -> String:
	if not category in RANDOM_TURN_CATEGORIES:
		return path
	var all := GnScatter.variants(path)
	return all[randi() % all.size()]


# Where the middle of the editor view meets the ground (y = 0). Looking at the
# sky, fall back to a point in front of the camera so a click always does
# something visible.
static func drop_point() -> Vector3:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		return Vector3.ZERO
	var centre := vp.get_visible_rect().size / 2.0
	var origin := cam.project_ray_origin(centre)
	var dir := cam.project_ray_normal(centre)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if hit != null and origin.distance_to(hit) < 500.0:
		return hit
	var ahead := origin + dir * 20.0
	return Vector3(ahead.x, 0.0, ahead.z)


## Copies of a model every `spacing` metres from a to b, each dropped onto
## whatever surface is below it: an avenue of trees, a row of bollards, a
## line of chairs. Facing: "along" the line, "across" it, or "random".
## One undo step for the lot. Returns the copies.
static func along_line(path: String, category: String, a: Vector3, b: Vector3, spacing: float,
		facing := "along") -> Array:
	var root := GnScene.root()
	if root == null or not load(path) is PackedScene or spacing <= 0.0:
		return []
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var run := a.distance_to(b)
	var count := int(floor(run / spacing + 0.001)) + 1
	var heading := atan2(-flat.x, -flat.z) if flat.length() > 0.001 else 0.0
	var surface := GnSurface.new(root)
	var nodes: Array = []
	for i in count:
		var p := a.lerp(b, (i * spacing) / maxf(run, 0.001)) if run > 0.0 else a
		var hit := surface.drop(p.x, p.z)
		if not hit.is_empty():
			p.y = (hit.position as Vector3).y
		var packed := load(_pick(path, category)) as PackedScene
		var node := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		node.name = "%s%d" % [path.get_file().get_basename().to_pascal_case(), i + 1]
		node.position = p
		match facing:
			"across":
				node.rotation.y = heading + PI * 0.5
			"random":
				node.rotation.y = randf() * TAU
			_:
				node.rotation.y = heading
		if category != "":
			node.set_meta(&"gn_category", category)
		nodes.append(node)
	GnScene.add_nodes(nodes, root, "Genesis: %d × %s along a line" % [count, path.get_file().get_basename()])
	return nodes
