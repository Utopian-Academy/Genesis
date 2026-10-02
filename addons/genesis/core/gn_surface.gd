@tool
extends RefCounted

# Ray tests against the scene's own meshes, for painting onto terrain, roofs
# and planters rather than only the flat ground. No collision shapes needed:
# Godot builds a TriangleMesh from any Mesh, and those are cached per mesh.
#
# Built once per stroke (meshes do not move while you paint), then queried
# hundreds of times.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

static var _tri_cache := {}  # Mesh instance id -> TriangleMesh

var _targets: Array = []  # [MeshInstance3D, TriangleMesh, inverse transform, world AABB]


func _init(root: Node) -> void:
	if root == null:
		return
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree() or _in_scatter(mi):
			continue
		var tri := _triangles(mi.mesh)
		if tri == null:
			continue
		var xf: Transform3D = mi.global_transform
		_targets.append([mi, tri, xf.affine_inverse(), xf * mi.get_aabb()])


# The nearest hit along a ray, as {position, normal}, or {} for a miss.
func cast(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for t in _targets:
		var aabb: AABB = t[3]
		if not aabb.grow(0.01).intersects_ray(origin, dir):
			continue
		var inv: Transform3D = t[2]
		var hit: Dictionary = (t[1] as TriangleMesh).intersect_ray(inv * origin, (inv.basis * dir).normalized())
		if hit.is_empty():
			continue
		var world: Vector3 = (t[0] as MeshInstance3D).global_transform * (hit.position as Vector3)
		var d := origin.distance_to(world)
		if d < best_d:
			best_d = d
			var n: Vector3 = ((t[0] as MeshInstance3D).global_transform.basis.inverse().transposed() * (hit.normal as Vector3)).normalized()
			best = {"position": world, "normal": n, "node": _named(t[0])}
	return best


# The highest surface straight below a point, for dropping a copy onto it.
func drop(x: float, z: float) -> Dictionary:
	return cast(Vector3(x, 10000.0, z), Vector3.DOWN)


# Whether something low covers the ground here: a floor, slab, terrace or
# planter, anything within `height` metres. Grass painted there would grow up
# through it. Tree canopies are higher, so grass still goes under trees.
func covered(x: float, z: float, height := 1.2) -> bool:
	var up := cast(Vector3(x, 0.01, z), Vector3.UP)
	return not up.is_empty() and (up.position as Vector3).y < height


static func _triangles(mesh: Mesh) -> TriangleMesh:
	var key := mesh.get_instance_id()
	if not _tri_cache.has(key):
		_tri_cache[key] = mesh.generate_triangle_mesh()
	return _tri_cache[key]


# Painting onto the copies already painted would stack grass on grass.
static func _in_scatter(node: Node) -> bool:
	var n := node
	while n:
		if n.get_meta(GnScene.ROLE, "") == "scatter":
			return true
		n = n.get_parent()
	return false


# The name a person would recognise: the placed object, not its inner mesh.
static func _named(mi: Node) -> String:
	var n := mi
	var root := GnScene.root()
	while n and n.get_parent() and n.get_parent() != root:
		n = n.get_parent()
	return str(n.name) if n else str(mi.name)
