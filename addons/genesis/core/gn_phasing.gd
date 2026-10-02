@tool
extends RefCounted

# Phasing: a building put up in a film. Any object can be given a moment to
# arrive and a time to take over it: it rises out of the ground, grows up
# from its base, or simply appears. A site going up floor by floor, a stage
# being built, trees planted, all in one fly-through.
#
# Phasing only acts while a film is previewed or rendered; afterwards every
# object is put back whole, so the scene is never left half built.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

const META := &"gn_phase"          # {"start", "grow", "style"}, saved with the scene
const BASE := &"gn_phase_base"     # the object's own transform, while a film plays
const STYLES := ["Rise from the ground", "Grow up", "Appear"]


## Gives objects a phase, as one undo step. `grow` 0 makes them arrive at once.
static func set_phase(nodes: Array, start: float, grow: float, style: String) -> void:
	var changes: Array = []
	for n in nodes:
		changes.append([n, "metadata/gn_phase", {"start": start, "grow": grow, "style": style}])
	GnScene.set_props("Genesis: phasing", changes)


static func clear(nodes: Array) -> void:
	var changes: Array = []
	for n in nodes:
		if (n as Node).has_meta(META):
			changes.append([n, "metadata/gn_phase", null])
	if not changes.is_empty():
		GnScene.set_props("Genesis: clear phasing", changes)


static func phased(root: Node) -> Array:
	if root == null:
		return []
	return root.find_children("*", "Node3D", true, false).filter(func(n): return n.has_meta(META))


## The latest moment any phase ends, seconds.
static func last_end(root: Node) -> float:
	var t := 0.0
	for n in phased(root):
		var p: Dictionary = n.get_meta(META)
		t = maxf(t, float(p.get("start", 0.0)) + float(p.get("grow", 0.0)))
	return t


## Puts every phased object where it is `t` seconds into the film.
static func show(root: Node, t: float) -> void:
	for n in phased(root):
		var node := n as Node3D
		var p: Dictionary = node.get_meta(META)
		if not node.has_meta(BASE):
			node.set_meta(BASE, {"transform": node.transform, "visible": node.visible, "height": _height(node)})
		var base: Dictionary = node.get_meta(BASE)
		var start := float(p.get("start", 0.0))
		var grow := float(p.get("grow", 0.0))
		var k := 1.0 if grow <= 0.0 else clampf((t - start) / grow, 0.0, 1.0)
		if t < start:
			k = 0.0
		# Eased: things slow as they settle into place.
		var e := 1.0 - pow(1.0 - k, 2.0)
		var xf: Transform3D = base.transform
		node.visible = bool(base.visible) and k > 0.0
		match str(p.get("style", STYLES[0])):
			"Grow up":
				node.transform = Transform3D(xf.basis * Basis.from_scale(Vector3(1, maxf(e, 0.001), 1)), xf.origin)
			"Appear":
				node.transform = xf
				node.visible = bool(base.visible) and t >= start
			_:
				node.transform = Transform3D(xf.basis, xf.origin - Vector3(0, float(base.height) * (1.0 - e), 0))


## Every phased object back as it was built.
static func finish(root: Node) -> void:
	for n in phased(root) + (root.find_children("*", "Node3D", true, false).filter(func(x): return x.has_meta(BASE)) if root else []):
		var node := n as Node3D
		if not node.has_meta(BASE):
			continue
		var base: Dictionary = node.get_meta(BASE)
		node.transform = base.transform
		node.visible = base.visible
		node.remove_meta(BASE)


# How tall an object is, for rising out of the ground by its own height.
static func _height(node: Node3D) -> float:
	var h := 0.0
	var first := true
	var box := AABB()
	for mi in node.find_children("*", "VisualInstance3D", true, false) + ([node] if node is VisualInstance3D else []):
		var b: AABB = (mi as VisualInstance3D).get_aabb()
		b = (node.global_transform.affine_inverse() * (mi as Node3D).global_transform) * b
		box = b if first else box.merge(b)
		first = false
	h = box.end.y - minf(box.position.y, 0.0) if not first else 1.0
	return maxf(h, 0.1)
