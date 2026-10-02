@tool
extends Node3D

# A run of truss along local +X: chords with zig-zag bracing on every face,
# at the standard section sizes: box (four chords), triangle (three) and
# ladder (two, flat). Rotate the node to stand it up as a tower. With a
# radius it bends into an arc in the horizontal plane, and at a length of
# 2πr it closes into a circle, the way circular truss hangs over a stage.
# Dimensions are typical of each size class; a real rig should use the
# manufacturer's own figures for loads.

const SECTIONS := {
	"290 mm box": {"size": 0.29, "chord": 0.048, "brace": 0.016, "chords": 4},
	"400 mm box": {"size": 0.40, "chord": 0.051, "brace": 0.020, "chords": 4},
	"520 mm box": {"size": 0.52, "chord": 0.051, "brace": 0.025, "chords": 4},
	"290 mm triangle": {"size": 0.29, "chord": 0.048, "brace": 0.016, "chords": 3},
	"400 mm triangle": {"size": 0.40, "chord": 0.051, "brace": 0.020, "chords": 3},
	"300 mm ladder": {"size": 0.30, "chord": 0.048, "brace": 0.016, "chords": 2},
	"220 mm ladder (flat)": {"size": 0.22, "chord": 0.035, "brace": 0.012, "chords": 2},
}

@export_enum("290 mm box", "400 mm box", "520 mm box", "290 mm triangle", "400 mm triangle", "300 mm ladder",
	"220 mm ladder (flat)") var section: String = "290 mm box":
	set(v): section = v; _queue()
## Along the run (for an arc, along the curve), metres.
@export_range(0.5, 100.0, 0.5, "or_greater") var length: float = 6.0:
	set(v): length = v; _queue()
## 0 for straight; otherwise the arc's radius in metres, bending towards +Z.
@export_range(0.0, 30.0, 0.25) var radius: float = 0.0:
	set(v): radius = v; _queue()

var _pending := false


func _ready() -> void:
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


## Makes a full circle of the given radius.
func make_circle(r: float) -> void:
	radius = r
	length = TAU * r


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	var s: Dictionary = SECTIONS.get(section, SECTIONS["290 mm box"])
	var half := float(s.size) * 0.5 - float(s.chord) * 0.5
	var corners: Array = []
	match int(s.chords):
		3:
			# Apex up, as triangle truss usually hangs.
			for k in 3:
				var a := PI * 0.5 + TAU * k / 3.0
				corners.append(Vector2(cos(a), sin(a)) * half * 1.1)
		2:
			corners = [Vector2(0, -half), Vector2(0, half)]
		_:
			corners = [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
	var faces := corners.size() if corners.size() > 2 else 1
	var tris := PackedVector3Array()
	var bay := float(s.size)
	var bays := maxi(int(round(length / bay)), 1)
	var step := length / bays
	# Chords are laid bay by bay, so an arc bends smoothly.
	for c in corners:
		for i in bays:
			_tube(tris, Vector3(i * step, c.x, c.y), Vector3((i + 1) * step, c.x, c.y), float(s.chord) * 0.5)
	# Bracing: a zig-zag on each face, one diagonal per bay.
	for f in faces:
		var a: Vector2 = corners[f]
		var b: Vector2 = corners[(f + 1) % corners.size()]
		for i in bays:
			var p := a if i % 2 == 0 else b
			var q := b if i % 2 == 0 else a
			_tube(tris, Vector3(i * step, p.x, p.y), Vector3((i + 1) * step, q.x, q.y), float(s.brace) * 0.5)
			if corners.size() == 2:
				# Ladder truss has a rung at every bay too.
				_tube(tris, Vector3(i * step, a.x, a.y), Vector3(i * step, b.x, b.y), float(s.brace) * 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in tris:
		st.add_vertex(_bend(v))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.79, 0.8)
	mat.metallic = 0.9
	mat.roughness = 0.35
	var mi := MeshInstance3D.new()
	mi.name = "Truss"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.set_meta(&"gn_generated", true)
	add_child(mi)


# Straight truss coordinates (x along the run, z across) onto the arc.
func _bend(v: Vector3) -> Vector3:
	if radius <= 0.0:
		return v
	var theta := v.x / radius
	var r := radius - v.z
	return Vector3(r * sin(theta), v.y, radius - r * cos(theta))


static func _tube(tris: PackedVector3Array, a: Vector3, b: Vector3, r: float) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u)
	var sides := 6
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var n0 := (u * cos(a0) + w * sin(a0)) * r
		var n1 := (u * cos(a1) + w * sin(a1)) * r
		for v in [a + n0, b + n0, b + n1, a + n0, b + n1, a + n1]:
			tris.append(v)
