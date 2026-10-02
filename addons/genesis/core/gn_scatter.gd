@tool
extends RefCounted

# Many copies of one model, drawn as MultiMeshes: one draw call per mesh
# surface however many copies there are.
#
# A scatter is a Node3D tagged "scatter" with one MultiMeshInstance3D per mesh
# in the source model. The copies are a list of points (a Transform3D each).
# The MultiMeshes are the only place that list is stored: points() reads it
# back from the first one, and set_points() writes all of them. Keeping a
# second copy in metadata doubled the scene file for nothing.
#
# A model with grown variants (a tree's other seeds, in a variants folder
# beside it) scatters all of them: each copy's variant follows from where it
# stands, so the same point is always the same tree through undo and redo.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

const SOURCE := "gn_source"
const LOCAL := "gn_local"
const VARIANT := "gn_variant"


## The model and its grown variants: beech.tscn, then variants/beech_v2.tscn
## and so on, if they exist.
static func variants(path: String) -> Array[String]:
	var out: Array[String] = [path]
	var dir := path.get_base_dir().path_join("variants")
	var stem := path.get_file().get_basename()
	var more: Array = []
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		if f.begins_with(stem + "_v") and f.get_extension() in ["tscn", path.get_extension()] and f.get_basename().substr(stem.length() + 2).is_valid_int():
			more.append(dir.path_join(f))
	more.sort()
	out.append_array(more)
	return out


## Which of `count` variants stands at a point.
static func variant_at(p: Transform3D, count: int) -> int:
	if count <= 1:
		return 0
	return absi(hash(Vector2i(roundi(p.origin.x * 100.0), roundi(p.origin.z * 100.0)))) % count


## Points shared out among `count` variants.
static func split(pts: Array[Transform3D], count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append([] as Array[Transform3D])
	for p in pts:
		(out[variant_at(p, count)] as Array[Transform3D]).append(p)
	return out


static func _count(group: Node3D) -> int:
	return int(group.get_meta(VARIANT, 1))


## Draws points into the group's MultiMeshes straight away (no undo), as the
## brush does while a stroke is being painted.
static func show(group: Node3D, pts: Array[Transform3D]) -> void:
	var shares := split(pts, _count(group))
	for mmi in group.get_children():
		if mmi is MultiMeshInstance3D:
			var mine: Array[Transform3D] = shares[int(mmi.get_meta(VARIANT, 0))]
			mmi.multimesh.instance_count = mine.size()
			mmi.multimesh.buffer = buffer(mine, mmi.get_meta(LOCAL, Transform3D.IDENTITY))


# The scatter for this model, if the scene already has one.
static func find_group(path: String) -> Node3D:
	var root := GnScene.root()
	if root == null:
		return null
	for node in root.find_children("*", "Node3D", true, false):
		if node.get_meta(GnScene.ROLE, "") == "scatter" and node.get_meta(SOURCE, "") == path:
			return node
	return null


static func points(group: Node3D) -> Array[Transform3D]:
	# Each variant's first MultiMesh holds that variant's points.
	var out: Array[Transform3D] = []
	var seen := {}
	for mmi in group.get_children():
		var v := int(mmi.get_meta(VARIANT, 0))
		if mmi is MultiMeshInstance3D and not seen.has(v):
			seen[v] = true
			var mm: MultiMesh = mmi.multimesh
			var unlocal := (mmi.get_meta(LOCAL, Transform3D.IDENTITY) as Transform3D).affine_inverse()
			for i in mm.instance_count:
				out.append(mm.get_instance_transform(i) * unlocal)
	return out


# Makes an empty scatter for the model at `path` and adds it to the scene as
# one undo step. Returns null if the model has no meshes.
static func create_group(path: String) -> Node3D:
	var root := GnScene.root()
	if root == null or not load(path) is PackedScene:
		return null
	var group := Node3D.new()
	group.name = "%s scatter" % path.get_file().get_basename().to_pascal_case()
	group.set_meta(GnScene.ROLE, "scatter")
	group.set_meta(SOURCE, path)
	var models := variants(path)
	if models.size() > 1:
		group.set_meta(VARIANT, models.size())
	for v in models.size():
		var packed := load(models[v]) as PackedScene
		if packed == null:
			continue
		var source := packed.instantiate()
		# Each mesh keeps its offset inside the model, so multi-part assets
		# stay in one piece. A model can be a mesh itself (a generated plant)
		# or hold meshes inside.
		var meshes: Array = [source] if source is MeshInstance3D else []
		meshes.append_array(source.find_children("*", "MeshInstance3D", true, false))
		for mi in meshes:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mi.mesh
			var mmi := MultiMeshInstance3D.new()
			mmi.name = mi.name if v == 0 else "%s %d" % [mi.name, v + 1]
			mmi.multimesh = mm
			mmi.set_meta(LOCAL, _local_to(source, mi))
			if models.size() > 1:
				mmi.set_meta(VARIANT, v)
			group.add_child(mmi)
		source.free()
	if group.get_child_count() == 0:
		group.free()
		return null
	GnScene.add_node(group, root, "Genesis: new %s" % group.name)
	return group


# Replaces the group's points as one undo step. Every MultiMesh gets its whole
# buffer swapped rather than instances edited one by one: the undo history
# then holds two flat arrays per stroke instead of thousands of calls.
static func set_points(group: Node3D, new_points: Array[Transform3D], action: String,
		old_points: Array[Transform3D] = points(group)) -> void:
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action(action, UndoRedo.MERGE_DISABLE, GnScene.root())
	# `old_points` must be the state before the stroke. The brush draws its
	# stroke into the MultiMeshes as it paints, so it passes the points it
	# started from rather than letting them be read back here.
	var new_shares := split(new_points, _count(group))
	var old_shares := split(old_points, _count(group))
	for mmi in group.get_children():
		if not mmi is MultiMeshInstance3D:
			continue
		var mm: MultiMesh = mmi.multimesh
		var local: Transform3D = mmi.get_meta(LOCAL, Transform3D.IDENTITY)
		var v := int(mmi.get_meta(VARIANT, 0))
		var now: Array[Transform3D] = new_shares[v]
		var was: Array[Transform3D] = old_shares[v]
		# instance_count first: setting it clears the buffer.
		ur.add_do_property(mm, "instance_count", now.size())
		ur.add_do_property(mm, "buffer", buffer(now, local))
		ur.add_undo_property(mm, "instance_count", was.size())
		ur.add_undo_property(mm, "buffer", buffer(was, local))
	ur.commit_action()


# MultiMesh's TRANSFORM_3D layout: 12 floats per instance, row-major basis
# rows with the origin in the fourth column.
static func buffer(pts: Array[Transform3D], local: Transform3D) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(pts.size() * 12)
	var i := 0
	for p in pts:
		var t := p * local
		var b := t.basis
		buf[i] = b.x.x; buf[i + 1] = b.y.x; buf[i + 2] = b.z.x; buf[i + 3] = t.origin.x
		buf[i + 4] = b.x.y; buf[i + 5] = b.y.y; buf[i + 6] = b.z.y; buf[i + 7] = t.origin.y
		buf[i + 8] = b.x.z; buf[i + 9] = b.y.z; buf[i + 10] = b.z.z; buf[i + 11] = t.origin.z
		i += 12
	return buf


# One copy: random turn about the vertical and a random size within the range.
static func make_point(at: Vector3, rng: RandomNumberGenerator, scale_range: Vector2, turn := true) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU) if turn else Basis()
	return Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(scale_range.x, scale_range.y)), at)


# Scatters `count` copies inside a circle on the ground, adding to any copies
# already there. Returns the scatter group, or null.
static func fill_circle(path: String, centre: Vector3, radius: float, count: int,
		scale_range := Vector2(0.8, 1.2), seed := 0) -> Node3D:
	var group := find_group(path)
	if group == null:
		group = create_group(path)
	if group == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else randi()
	var pts := points(group)
	for i in count:
		# sqrt keeps the density even; without it copies bunch at the centre.
		var r := radius * sqrt(rng.randf())
		var a := rng.randf() * TAU
		pts.append(make_point(centre + Vector3(cos(a) * r, 0.0, sin(a) * r), rng, scale_range))
	set_points(group, pts, "Genesis: scatter %d" % count)
	return group


# The transform of `node` relative to `ancestor`, without either being in a tree.
static func _local_to(ancestor: Node, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
