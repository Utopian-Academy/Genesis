@tool
extends RefCounted

# The scatter brush. Drag in the 3D view to paint copies of one model onto
# the ground; hold Shift to erase. A whole stroke is one undo step.
#
# It knows nothing about the editor's input plumbing: plugin.gd hands it
# viewport events, and tests hand it the same events, so both run one path.

const GnScatter := preload("res://addons/genesis/core/gn_scatter.gd")
const GnSurface := preload("res://addons/genesis/core/gn_surface.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

signal changed
signal stroke_finished

var active := false
var asset_path := ""
var radius := 4.0            # metres
var density := 2.0           # copies per square metre
var scale_range := Vector2(0.8, 1.2)
var random_turn := true
# Off: the flat ground only, so grass never lands on a terrace or a roof by
# accident. On: whatever surface is under the brush, terrain and roofs included.
var on_surfaces := false
# "plants" paints copies; "raise", "lower", "smooth" and "flatten" sculpt
# the terrain instead.
var mode := "plants"
var sculpt_strength := 0.3  # metres per dab at the brush centre
# "paint" lays one of the terrain's ground layers (1-4), 0 wipes back to the
# surface beneath.
var paint_layer := 1
var paint_strength := 0.35

var _group: Node3D
var _stroke: Array[Transform3D] = []  # the group's points during a stroke
var _before: Array[Transform3D] = []  # and before it, for undo
var _grid := {}                      # cell -> true, for spacing within the stroke
var _erasing := false
var _painting := false
var _last_stamp := Vector3.INF
var _hover := Vector3.INF
var _rng := RandomNumberGenerator.new()
var _surface: GnSurface  # built at the start of a stroke, or on first hover
var _heights_before := PackedFloat32Array()
var _splat_before := PackedByteArray()
var _flatten_to := 0.0


# Sensible starting density for what is being painted: a lawn wants
# thousands, a copse wants a handful.
static func default_density(category: String) -> float:
	match category:
		"grass": return 6.0
		"plants": return 0.4
		"trees": return 0.02
	return 0.2


# Returns true when the event was used and the editor should not also act on
# it (a click would otherwise also select whatever is under the cursor).
func handle(camera: Camera3D, event: InputEvent) -> bool:
	# Painting needs a plant chosen; sculpting only needs terrain.
	if not active or (mode == "plants" and asset_path == ""):
		return false
	if event is InputEventMouse:
		_hover = _ground_hit(camera, event.position)
		changed.emit()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin(event.shift_pressed)
			_stamp(_hover)
		else:
			_end()
		return true
	if event is InputEventMouseMotion and _painting:
		# Stamping on every motion event would make density depend on how fast
		# the mouse reports; stamping every half radius keeps it even.
		if _hover != Vector3.INF and (_last_stamp == Vector3.INF or _hover.distance_to(_last_stamp) >= radius * 0.5):
			_stamp(_hover)
		return true
	return false


func terrain() -> Node3D:
	return GnScene.find_role("terrain") as Node3D


func _begin(erase: bool) -> void:
	if mode != "plants":
		var t := terrain()
		if t:
			_painting = true
			_last_stamp = Vector3.INF
			_heights_before = t.heights.duplicate()
			_splat_before = t.splat.duplicate()
			_flatten_to = _hover.y if _hover != Vector3.INF else 0.0
		return
	_erasing = erase
	_painting = true
	_last_stamp = Vector3.INF
	# Built in both modes: on the ground, it is how a copy knows it would be
	# under a building and gets skipped.
	_surface = GnSurface.new(GnScene.root())
	_group = GnScatter.find_group(asset_path)
	if _group == null and not erase:
		_group = GnScatter.create_group(asset_path)
	_stroke = GnScatter.points(_group) if _group else ([] as Array[Transform3D])
	_before = _stroke.duplicate()
	_grid.clear()
	for p in _stroke:
		_grid[_cell(p.origin)] = true


func _end() -> void:
	if _painting and mode != "plants":
		var t := terrain()
		if t:
			# One undo step for the whole stroke: before and after.
			var ur := EditorInterface.get_editor_undo_redo()
			if mode == "paint":
				ur.create_action("Genesis: paint the ground", UndoRedo.MERGE_DISABLE, GnScene.root())
				ur.add_do_property(t, "splat", t.splat.duplicate())
				ur.add_undo_property(t, "splat", _splat_before)
			else:
				ur.create_action("Genesis: sculpt %s" % mode, UndoRedo.MERGE_DISABLE, GnScene.root())
				ur.add_do_property(t, "heights", t.heights.duplicate())
				ur.add_undo_property(t, "heights", _heights_before)
			ur.commit_action()
			stroke_finished.emit()
		_painting = false
		return
	if _painting and _group:
		var action := "Genesis: erase" if _erasing else "Genesis: paint"
		GnScatter.set_points(_group, _stroke, action, _before)
		stroke_finished.emit()
	_painting = false
	_group = null
	_stroke = []
	_before = []


func _stamp(at: Vector3) -> void:
	if mode != "plants":
		var t := terrain()
		if t and at != Vector3.INF:
			_last_stamp = at
			if mode == "paint":
				t.paint(at, radius, paint_strength, paint_layer)
			else:
				t.sculpt(at, radius, sculpt_strength, mode, _flatten_to)
		return
	if at == Vector3.INF or _group == null:
		return
	_last_stamp = at
	if _erasing:
		var kept: Array[Transform3D] = []
		for p in _stroke:
			if Vector2(p.origin.x - at.x, p.origin.z - at.z).length() > radius:
				kept.append(p)
		_stroke = kept
		_grid.clear()
		for p in _stroke:
			_grid[_cell(p.origin)] = true
	else:
		# Try a Poisson-ish fill: aim for density × area copies, but reject a
		# spot whose grid cell is already taken, so repeated passes thicken a
		# patch up to the density and no further.
		var tries := int(ceil(density * PI * radius * radius))
		for i in tries:
			var r := radius * sqrt(_rng.randf())
			var a := _rng.randf() * TAU
			var spot := at + Vector3(cos(a) * r, 0.0, sin(a) * r)
			if on_surfaces:
				var hit := _surface.drop(spot.x, spot.z)
				if hit.is_empty():
					continue
				spot = hit.position
			else:
				# Ground only, and not under a floor or terrace, or grass
				# grows up through the house.
				if _surface.covered(spot.x, spot.z):
					continue
				# With terrain in the scene, "the ground" is the terrain.
				var t := terrain()
				spot.y = t.height_at(spot) if t else 0.0
			var cell := _cell(spot)
			if _grid.has(cell):
				continue
			_grid[cell] = true
			_stroke.append(GnScatter.make_point(spot, _rng, scale_range, random_turn))
	# Show the stroke as it is painted; the undo step is recorded at the end.
	_preview()


func _preview() -> void:
	GnScatter.show(_group, _stroke)


# One copy per cell, with cells sized so a full grid is exactly the density.
func _cell(p: Vector3) -> Vector2i:
	var size := 1.0 / sqrt(maxf(density, 0.0001))
	return Vector2i(floori(p.x / size), floori(p.z / size))


# Where the mouse ray meets what the brush paints on, or INF.
func _ground_hit(camera: Camera3D, pos: Vector2) -> Vector3:
	if camera == null:
		return Vector3.INF
	if on_surfaces or mode != "plants" or terrain() != null:
		if _surface == null or not _painting or mode != "plants":
			# Rebuilt on hover as well, so the cursor ring follows new geometry.
			_surface = GnSurface.new(GnScene.root())
		var h := _surface.cast(camera.project_ray_origin(pos), camera.project_ray_normal(pos))
		return h.position if not h.is_empty() else Vector3.INF
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(pos), camera.project_ray_normal(pos))
	return hit if hit != null else Vector3.INF


# The brush outline on the ground, as screen points, for the overlay to draw.
func outline(camera: Camera3D) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if _hover == Vector3.INF or camera == null:
		return pts
	for i in 49:
		var a := i * TAU / 48.0
		var p := _hover + Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		if camera.is_position_behind(p):
			return PackedVector2Array()
		pts.append(camera.unproject_position(p))
	return pts
