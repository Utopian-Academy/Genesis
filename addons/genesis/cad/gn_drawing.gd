@tool
extends Node3D

# A CAD drawing (DXF, or a PDF plotted from CAD) laid in the scene at its true size: the plan's
# linework on the ground, layer by layer in the drawing's own colours, its
# text lying where it was written, and walls raised from any layers chosen.
# Build the event on top of it: the tape measure snaps to the drawing's
# corners and ends, so what is measured is what was drawn.
#
# The drawing is kept as a file in the project (genesis_data/cad/) and
# read again when the scene opens, so the scene stays small and a new
# revision of the drawing is one file to replace.

const GnDxf := preload("res://addons/genesis/cad/gn_dxf.gd")
const GnPdf := preload("res://addons/genesis/cad/gn_pdf.gd")

const GROUP := &"gn_drawings"
const UNITS := {"From the file": 0.0, "Millimetres": 0.001, "Centimetres": 0.01, "Metres": 1.0, "Inches": 0.0254,
	"Feet": 0.3048}
# Unitless drawings: event and architectural plans are nearly always millimetres.
const UNITLESS_GUESS := 0.001
# More labels than this and the text is left off (it would swamp the editor).
const MAX_LABELS := 4000

## The DXF or PDF, inside the project.
@export_file("*.dxf", "*.pdf") var source: String = "":
	set(v): source = v; _queue(true)
## For a PDF: which page, and the drawing's scale (48 for 1/4" = 1'-0").
@export_range(1, 999) var pdf_page: int = 1:
	set(v): pdf_page = v; _queue(true)
@export_range(1.0, 100000.0) var pdf_scale: float = 100.0:
	set(v): pdf_scale = v; _queue(true)
@export_enum("From the file", "Millimetres", "Centimetres", "Metres", "Inches", "Feet") var units: String = "From the file":
	set(v): units = v; _queue()
## Put the middle of the drawing at this node, rather than the drawing's own
## origin (which on a site plan can be kilometres away).
@export var centre_on_drawing: bool = true:
	set(v): centre_on_drawing = v; _queue()
## Layers left out.
@export var hidden_layers: PackedStringArray = PackedStringArray():
	set(v): hidden_layers = v; _queue()
## Layers whose lines stand up as walls.
@export var wall_layers: PackedStringArray = PackedStringArray():
	set(v): wall_layers = v; _queue()
@export_range(0.1, 30.0, 0.05) var wall_height: float = 3.0:
	set(v): wall_height = v; _queue()
@export var show_text: bool = true:
	set(v): show_text = v; _queue()
## Draw everything in one colour instead of the drawing's.
@export var one_colour: bool = false:
	set(v): one_colour = v; _queue()
@export var line_colour: Color = Color(0.1, 0.1, 0.12):
	set(v): line_colour = v; _queue()
## How far above the node the lines lie, so they never flicker into the floor.
@export_range(0.0, 0.1, 0.001) var lift: float = 0.004:
	set(v): lift = v; _queue()

var drawing: GnDxf.Drawing
var _pending := false
var _reread := false
# Snapping: world-space points by 1 m cell.
var _snap := {}


func _ready() -> void:
	add_to_group(GROUP)
	_reread = true
	_rebuild()


func _queue(reread := false) -> void:
	_reread = _reread or reread
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


## Metres per drawing unit, as the drawing will be placed.
func scale() -> float:
	var chosen := float(UNITS.get(units, 0.0))
	if chosen > 0.0:
		return chosen
	if drawing and GnDxf.UNIT_METRES.has(drawing.units):
		return GnDxf.UNIT_METRES[drawing.units]
	return UNITLESS_GUESS


## Every layer: name -> {"colour", "on" (in the file), "segments", "shown", "walls"}.
func layer_list() -> Dictionary:
	var out := {}
	if drawing == null:
		return out
	var names: Array = drawing.layers.keys()
	names.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	for name in names:
		var n := (drawing.segments.get(name, PackedFloat64Array()) as PackedFloat64Array).size() / 6
		n += drawing.texts.filter(func(t): return t.layer == name).size()
		if n == 0:
			continue
		out[name] = {"colour": drawing.layers[name].colour, "on": drawing.layers[name].on, "count": n,
			"shown": _shown(name), "walls": name in wall_layers}
	return out


func _shown(layer: String) -> bool:
	return not (layer in hidden_layers)


## The drawing's size on the ground, metres.
func size_m() -> Vector2:
	if drawing == null or drawing.lo_x == INF:
		return Vector2.ZERO
	return Vector2(drawing.hi_x - drawing.lo_x, drawing.hi_y - drawing.lo_y) * scale()


func report_text() -> String:
	if drawing == null:
		return ""
	if drawing.error != "":
		return drawing.error
	var s := size_m()
	var lines: Array = ["%s: %.3f × %.3f m" % [source.get_file(), s.x, s.y]]
	if source.get_extension().to_lower() == "pdf":
		lines.append("PDF page %d at 1:%s" % [pdf_page, str(snappedf(pdf_scale, 0.01))])
		lines.append("%d lines on %d layers (one per pen)" % [drawing.segment_count(), layer_list().size()])
		return "\n".join(lines)
	var unit_name: String = units if units != "From the file" else str(GnDxf.UNIT_NAMES.get(drawing.units, "unitless"))
	if units == "From the file" and not GnDxf.UNIT_METRES.has(drawing.units):
		unit_name = "unitless: read as millimetres (change Units if that is wrong)"
	lines.append("Units: %s" % unit_name)
	lines.append("%d lines on %d layers, %d texts" % [drawing.segment_count(), layer_list().size(), drawing.texts.size()])
	if not drawing.skipped.is_empty():
		var parts: Array = []
		for k in drawing.skipped:
			parts.append("%d %s" % [drawing.skipped[k], str(k).to_lower()])
		lines.append("Not drawn: %s" % ", ".join(parts))
	return "\n".join(lines)


# A drawing point (64-bit, drawing units) to this node's space, metres.
# Drawing X is east (+X), drawing Y is north (-Z), drawing Z is up.
func _to_local(x: float, y: float, z: float) -> Vector3:
	var s := scale()
	var ox := 0.0
	var oy := 0.0
	if centre_on_drawing and drawing.lo_x != INF:
		ox = (drawing.lo_x + drawing.hi_x) * 0.5
		oy = (drawing.lo_y + drawing.hi_y) * 0.5
	return Vector3((x - ox) * s, z * s + lift, -(y - oy) * s)


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	_snap.clear()
	if _reread or drawing == null:
		_reread = false
		if source.get_extension().to_lower() == "pdf":
			drawing = GnPdf.read(ProjectSettings.globalize_path(source), pdf_page, pdf_scale)
		else:
			drawing = GnDxf.read(ProjectSettings.globalize_path(source)) if source != "" else null
	if drawing == null or drawing.error != "":
		return
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.86, 0.86, 0.84)
	wall_mat.roughness = 0.9
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for layer in drawing.segments:
		if not _shown(layer):
			continue
		var segs: PackedFloat64Array = drawing.segments[layer]
		var cols: PackedColorArray = drawing.colours[layer]
		if segs.is_empty():
			continue
		var verts := PackedVector3Array()
		var vcols := PackedColorArray()
		verts.resize(segs.size() / 3)
		vcols.resize(segs.size() / 3)
		for q in segs.size() / 6:
			var a := _to_local(segs[q * 6], segs[q * 6 + 1], segs[q * 6 + 2])
			var b := _to_local(segs[q * 6 + 3], segs[q * 6 + 4], segs[q * 6 + 5])
			verts[q * 2] = a
			verts[q * 2 + 1] = b
			var c: Color = line_colour if one_colour else cols[q]
			vcols[q * 2] = c
			vcols[q * 2 + 1] = c
			_add_snap(a)
			_add_snap(b)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = vcols
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		mesh.surface_set_material(0, line_mat)
		var mi := MeshInstance3D.new()
		mi.name = "Layer %s" % layer.validate_node_name()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta(&"gn_generated", true)
		mi.set_meta(&"gn_layer", layer)
		add_child(mi)
		if layer in wall_layers:
			_walls(layer, verts, wall_mat)
	if show_text and drawing.texts.size() <= MAX_LABELS:
		var s := scale()
		for t in drawing.texts:
			if not _shown(t.layer):
				continue
			var label := Label3D.new()
			label.text = t.text
			label.font_size = 64
			label.outline_size = 0
			label.modulate = line_colour if one_colour else t.colour
			# Cap height in the drawing is the text height; Godot's font size
			# is its line height, about 1.4 cap heights.
			label.pixel_size = t.height * s * 1.4 / label.font_size
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			label.shaded = false
			label.double_sided = true
			label.position = _to_local(t.x, t.y, t.z) + Vector3(0, 0.001, 0)
			# Lying flat, reading from the drawing's south, turned as written.
			label.rotation = Vector3(-PI * 0.5, t.angle, 0)
			label.set_meta(&"gn_generated", true)
			add_child(label)


# Every line on a wall layer stands up as a wall, wall_height tall.
func _walls(layer: String, verts: PackedVector3Array, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3(0, wall_height, 0)
	for q in verts.size() / 2:
		var a := verts[q * 2] - Vector3(0, lift, 0)
		var b := verts[q * 2 + 1] - Vector3(0, lift, 0)
		if a.distance_to(b) < 0.0005:
			continue
		var n := (b - a).cross(Vector3.UP).normalized()
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(b + up)
		st.add_vertex(a)
		st.add_vertex(b + up)
		st.add_vertex(a + up)
	var mi := MeshInstance3D.new()
	mi.name = "Walls %s" % layer.validate_node_name()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.set_meta(&"gn_generated", true)
	add_child(mi)


func _add_snap(p: Vector3) -> void:
	var key := Vector2i(floori(p.x), floori(p.z))
	if not _snap.has(key):
		_snap[key] = PackedVector3Array()
	var list: PackedVector3Array = _snap[key]
	list.append(p)
	_snap[key] = list


## The drawing's nearest line end or corner to a world point, within
## radius metres; Vector3.INF if there is none.
func snap(world: Vector3, radius: float) -> Vector3:
	var local := global_transform.affine_inverse() * world
	var best := Vector3.INF
	var best_d := radius
	var reach := ceili(radius)
	var cx := floori(local.x)
	var cz := floori(local.z)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var list: PackedVector3Array = _snap.get(Vector2i(cx + dx, cz + dz), PackedVector3Array())
			for p in list:
				var d := Vector2(p.x - local.x, p.z - local.z).length()
				if d < best_d:
					best_d = d
					best = p
	if best == Vector3.INF:
		return best
	var out := global_transform * best
	return Vector3(out.x, out.y - lift, out.z)
