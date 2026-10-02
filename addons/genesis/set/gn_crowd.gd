@tool
extends Node3D

# A crowd: an area filled with people at a real density, in a mood. The
# people come from the library (genesis_assets/people, one model per pose
# and person), drawn as one MultiMesh per model, so thousands stay cheap.
# Everyone faces the node's forward (-Z) give or take, so turning the crowd
# to face the stage is turning the node. Change it in the Inspector.
#
# Densities people plan with: a relaxed standing crowd is 1-2 people per m²,
# a packed concert floor 3-4, and above 5 is dangerous.

const GnAssets := preload("res://addons/genesis/core/gn_assets.gd")

## Which poses make up the crowd, and how many of each.
const MOODS := {
	"Concert": {"cheering": 3, "fist_up": 2, "clapping": 1, "standing": 2, "relaxed": 1, "phone": 1},
	"Seated": {"sitting": 1},
	"Milling about": {"standing": 2, "relaxed": 2, "talking": 3, "walking": 2, "phone": 1},
	"Frustrated": {"arms_crossed": 3, "hands_on_hips": 2, "facepalm": 1, "exasperated": 1, "shrugging": 1,
		"pointing": 1, "phone": 2, "standing": 1},
	"Mixed": {"standing": 2, "relaxed": 2, "talking": 1, "cheering": 1, "clapping": 1, "phone": 1, "arms_crossed": 1},
}

@export_enum("Concert", "Seated", "Milling about", "Frustrated", "Mixed") var mood: String = "Concert":
	set(v): mood = v; _queue()
## Across, metres.
@export_range(1.0, 200.0, 0.5) var width: float = 12.0:
	set(v): width = v; _queue()
## Front to back, metres.
@export_range(1.0, 200.0, 0.5) var depth: float = 8.0:
	set(v): depth = v; _queue()
## People per square metre (seated rows ignore this).
@export_range(0.2, 5.0, 0.1) var density: float = 2.0:
	set(v): density = v; _queue()
## How far each person may turn away from the crowd's forward, degrees.
@export_range(0.0, 180.0, 1.0) var turn_spread: float = 25.0:
	set(v): turn_spread = v; _queue()
## Seated rows: seat width and row spacing, metres.
@export_range(0.4, 1.0, 0.01) var seat_width: float = 0.52:
	set(v): seat_width = v; _queue()
@export_range(0.7, 1.5, 0.01) var row_spacing: float = 0.9:
	set(v): row_spacing = v; _queue()
## Change for a different arrangement of the same crowd.
@export var variation: int = 1:
	set(v): variation = v; _queue()

var _pending := false


func _ready() -> void:
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


## How many people are in it.
func headcount() -> int:
	var n := 0
	for c in get_children():
		if c is MultiMeshInstance3D and c.has_meta(&"gn_generated"):
			n += c.multimesh.instance_count
	return n


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	var by_pose := _people()
	if by_pose.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = variation
	var weights: Dictionary = MOODS.get(mood, MOODS["Concert"])
	var pool: Array = []  # [pose, weight] for poses we have models of
	var total := 0.0
	for pose in weights:
		if by_pose.has(pose):
			pool.append([pose, float(weights[pose])])
			total += float(weights[pose])
	if pool.is_empty():
		return

	# Where everyone stands: rows of seats, or a jittered grid at the density.
	var spots: Array = []
	if mood == "Seated":
		var z := -depth * 0.5 + row_spacing * 0.5
		while z < depth * 0.5:
			var x := -width * 0.5 + seat_width * 0.5
			while x < width * 0.5:
				spots.append(Vector3(x, 0, z))
				x += seat_width
			z += row_spacing
	else:
		var step := 1.0 / sqrt(density)
		var z := -depth * 0.5 + step * 0.5
		while z < depth * 0.5:
			var x := -width * 0.5 + step * 0.5
			while x < width * 0.5:
				var j := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35)) * step
				spots.append(Vector3(x, 0, z) + j)
				x += step
			z += step

	# Deal the spots out to models.
	var dealt := {}  # model path -> Array[Transform3D]
	for at in spots:
		var roll := rng.randf() * total
		var pose: String = pool[0][0]
		for p in pool:
			roll -= p[1]
			if roll <= 0.0:
				pose = p[0]
				break
		var models: Array = by_pose[pose]
		var path: String = models[rng.randi() % models.size()]
		var turn := 0.0 if mood == "Seated" else deg_to_rad(rng.randf_range(-turn_spread, turn_spread))
		var s := rng.randf_range(0.96, 1.04)
		# The models face -Z, as the crowd does.
		var b := Basis(Vector3.UP, turn).scaled(Vector3(s, s, s))
		if not dealt.has(path):
			dealt[path] = []
		dealt[path].append(Transform3D(b, at))

	for path in dealt:
		var mesh := _mesh_of(path)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = dealt[path].size()
		for i in dealt[path].size():
			mm.set_instance_transform(i, dealt[path][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = str(path).get_file().get_basename()
		mmi.multimesh = mm
		mmi.set_meta(&"gn_generated", true)
		add_child(mmi)
	if mood == "Seated":
		_seats(spots)


# Seated crowds need something to sit on: plain stacking chairs, one per
# spot, unless the scene already has its own seating.
func _seats(spots: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	for at in spots:
		# Sitters face -Z with their thighs forward of the hips, so the seat
		# runs forward of the spot and the back is behind it.
		for part in [[Vector3(0.44, 0.04, 0.42), Vector3(0, 0.43, -0.13)], [Vector3(0.44, 0.42, 0.03), Vector3(0, 0.66, 0.1)],
				[Vector3(0.03, 0.43, 0.03), Vector3(-0.19, 0.215, -0.32)], [Vector3(0.03, 0.43, 0.03), Vector3(0.19, 0.215, -0.32)],
				[Vector3(0.03, 0.43, 0.03), Vector3(-0.19, 0.215, 0.07)], [Vector3(0.03, 0.43, 0.03), Vector3(0.19, 0.215, 0.07)]]:
			box.size = part[0]
			st.append_from(box, 0, Transform3D(Basis(), at + part[1]))
	var mi := MeshInstance3D.new()
	mi.name = "Seats"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.12)
	mat.roughness = 0.6
	mi.material_override = mat
	mi.set_meta(&"gn_generated", true)
	add_child(mi)


# pose -> [model paths], from the people in the library.
static func _people() -> Dictionary:
	var out := {}
	for a in GnAssets.of_kind("people", []):
		var pose := str(a.license.get("pose", ""))
		if pose == "":
			continue
		if not out.has(pose):
			out[pose] = []
		out[pose].append(a.path)
	return out


static var _meshes := {}

static func _mesh_of(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var packed := load(path) as PackedScene
	var mesh: Mesh = null
	if packed:
		var inst := packed.instantiate()
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		if inst is MeshInstance3D:
			found.push_front(inst)
		if not found.is_empty():
			mesh = found[0].mesh
		inst.free()
	_meshes[path] = mesh
	return mesh
