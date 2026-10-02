@tool
extends VBoxContainer

# Plans: build on the real drawings. A floor plan (image or PDF page) laid on
# the ground at true scale, or the CAD drawing itself (DXF, or DWG through
# the free ODA converter), with its layers, text and walls. The tape measure
# snaps to a drawing's corners, so the event is set out to the millimetre.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnMeasure := preload("res://addons/genesis/core/gn_measure.gd")
const GnCadImport := preload("res://addons/genesis/cad/gn_cad_import.gd")
const Underlay := preload("res://addons/genesis/cad/gn_underlay.gd")
const Drawing := preload("res://addons/genesis/cad/gn_drawing.gd")

var measure: GnMeasure

var _plan_width: SpinBox
var _pdf_ratio: SpinBox
var _pdf_page: SpinBox
var _plan_dialog: EditorFileDialog
var _cad_dialog: EditorFileDialog
var _scale_button: Button
var _real_row: HBoxContainer
var _real: SpinBox
var _picked: Array = []
var _plan_report: Label
var _cad_report: Label
var _units: OptionButton
var _layers: VBoxContainer
var _wall_height: SpinBox
var _message: Label
var _tools: Label


func _init() -> void:
	name = "Plans"
	GnUi.note(self, "Build on the real drawings: a floor plan under the scene, or the CAD drawing itself, at true size.")

	GnUi.heading(self, "Floor plan")
	_plan_width = _spin(self, "Image: plan width (m)", 1.0, 5000.0, 0.1, 30.0)
	_pdf_ratio = _spin(self, "PDF: scale 1 :", 1.0, 100000.0, 1.0, 100.0)
	var presets := GnUi.option(self, "PDF: the sheet says", ["…"] + GnCadImport.SCALES.keys(), func(t):
		if GnCadImport.SCALES.has(t):
			_pdf_ratio.value = GnCadImport.SCALES[t])
	presets.tooltip_text = "Pick the scale printed on the drawing; it sets the ratio above."
	_pdf_page = _spin(self, "PDF: page", 1.0, 999.0, 1.0, 1.0)
	GnUi.button(self, "Bring in a plan (image or PDF)…", _pick_plan)
	_scale_button = GnUi.button(self, "Set its scale: click two points on it", _start_scale)
	_real_row = HBoxContainer.new()
	var l := Label.new()
	l.text = "Real distance (m)"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_real_row.add_child(l)
	_real = SpinBox.new()
	_real.min_value = 0.001
	_real.max_value = 100000.0
	_real.step = 0.001
	_real.value = 10.0
	_real_row.add_child(_real)
	GnUi.button(_real_row, "Apply", _apply_scale)
	_real_row.visible = false
	add_child(_real_row)
	_plan_report = GnUi.note(self, "")

	GnUi.heading(self, "CAD drawing")
	GnUi.button(self, "Bring in a drawing (DXF, DWG or CAD PDF)…", _pick_cad)
	GnUi.note(self, "A PDF plotted from CAD comes in as its real lines, at the PDF scale above; each pen is a layer (the heaviest is usually the walls).")
	_tools = GnUi.note(self, "")
	_cad_report = GnUi.note(self, "")
	_units = GnUi.option(self, "Units", Drawing.UNITS.keys(), _set_units)
	_wall_height = _spin(self, "Wall height (m)", 0.1, 30.0, 0.05, 3.0)
	_wall_height.value_changed.connect(_set_wall_height)
	GnUi.note(self, "Layers: tick to show; Walls raises that layer's lines as walls.")
	_layers = VBoxContainer.new()
	add_child(_layers)
	_message = GnUi.note(self, "")


func refresh() -> void:
	var plan := _selected(Underlay)
	var drawing := _selected(Drawing)
	_scale_button.disabled = plan == null
	_plan_report.text = plan.report_text() if plan else "Select a plan to set its scale."
	var oda := GnCadImport.find_oda() != ""
	var pdf := GnCadImport.find_tool(["pdftoppm", "mutool"]) != ""
	_tools.text = "DWG: %s. PDF: %s." % ["ODA File Converter found" if oda else "needs the free ODA File Converter",
		"ready" if pdf else "needs Poppler or MuPDF (or bring the page in as a PNG)"]
	_cad_report.text = drawing.report_text() if drawing else "Select a drawing to see its layers."
	_units.get_parent().visible = drawing != null
	_wall_height.get_parent().visible = drawing != null
	for c in _layers.get_children():
		c.queue_free()
	if drawing == null:
		return
	GnUi.select_text(_units, drawing.units)
	_wall_height.set_value_no_signal(drawing.wall_height)
	var list: Dictionary = drawing.layer_list()
	for layer in list:
		var info: Dictionary = list[layer]
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = info.colour
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var shown := CheckBox.new()
		shown.text = "%s (%d)" % [layer, info.count]
		shown.button_pressed = info.shown
		shown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shown.clip_text = true
		shown.toggled.connect(_toggle_layer.bind(drawing, layer, "hidden_layers", true))
		row.add_child(shown)
		var walls := CheckBox.new()
		walls.text = "Walls"
		walls.button_pressed = info.walls
		walls.toggled.connect(_toggle_layer.bind(drawing, layer, "wall_layers", false))
		row.add_child(walls)
		_layers.add_child(row)


func _selected(script: Script) -> Node:
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n.get_script() == script:
			return n
	return null


func _spin(parent: Control, text: String, lo: float, hi: float, step: float, value: float) -> SpinBox:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	row.add_child(s)
	parent.add_child(row)
	return s


func _pick_plan() -> void:
	if _plan_dialog == null:
		_plan_dialog = _file_dialog("Bring in a floor plan", GnCadImport.PLAN_EXTENSIONS, _add_plan)
	_plan_dialog.popup_file_dialog()


func _pick_cad() -> void:
	if _cad_dialog == null:
		_cad_dialog = _file_dialog("Bring in a CAD drawing", GnCadImport.CAD_EXTENSIONS, _add_cad)
	_cad_dialog.popup_file_dialog()


func _file_dialog(title: String, extensions: Array, chosen: Callable) -> EditorFileDialog:
	var d := EditorFileDialog.new()
	d.access = EditorFileDialog.ACCESS_FILESYSTEM
	d.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	d.title = title
	d.add_filter(", ".join(extensions.map(func(e): return "*." + e)), title)
	d.file_selected.connect(chosen)
	add_child(d)
	return d


func _add_plan(path: String) -> void:
	_message.text = "Bringing in %s…" % path.get_file()
	var r := GnCadImport.add_plan(path, _plan_width.value, _pdf_ratio.value, int(_pdf_page.value))
	_message.text = r.error if r.has("error") else (
		"%s is on the ground at 1:%d. Check it against a known length with Set its scale." % [path.get_file(), _pdf_ratio.value]
		if path.get_extension().to_lower() == "pdf" else
		"%s is on the ground, %.0f m wide for now: set its scale with two clicks." % [path.get_file(), _plan_width.value])
	refresh()


func _add_cad(path: String) -> void:
	_message.text = "Reading %s…" % path.get_file()
	var r := GnCadImport.add_drawing(path, int(_pdf_page.value), _pdf_ratio.value)
	_message.text = r.error if r.has("error") else "%s is in the scene. Measuring snaps to its corners and ends." % path.get_file()
	refresh()


func _start_scale() -> void:
	var plan := _selected(Underlay)
	if plan == null or measure == null:
		return
	_picked = []
	measure.line_asset = ""
	measure.pick = func(a: Vector3, b: Vector3):
		_picked = [plan, a, b]
		_real_row.visible = true
		_message.text = "Those points are %.3f m apart on the plan now. Type the real distance and Apply." % Vector2(b.x - a.x, b.z - a.z).length()
	measure.active = true
	_message.text = "Click the first point on the plan, then the second (Esc to cancel)."
	GnScene.select(plan)


func _apply_scale() -> void:
	if _picked.size() != 3:
		return
	var plan: Node3D = _picked[0]
	var ur := EditorInterface.get_editor_undo_redo()
	var old_mpp: float = plan.metres_per_pixel
	var old_pos: Vector3 = plan.position
	var k: float = plan.calibrate(_picked[1], _picked[2], _real.value)
	ur.create_action("Genesis: set plan scale", UndoRedo.MERGE_DISABLE, GnScene.root())
	ur.add_do_property(plan, "metres_per_pixel", plan.metres_per_pixel)
	ur.add_do_property(plan, "position", plan.position)
	ur.add_undo_property(plan, "metres_per_pixel", old_mpp)
	ur.add_undo_property(plan, "position", old_pos)
	ur.commit_action(false)
	_real_row.visible = false
	_picked = []
	_message.text = "Scaled by %.4f: the plan is now to size." % k
	refresh()


func _set_units(text: String) -> void:
	var d := _selected(Drawing)
	if d:
		_change(d, "units", text, "Genesis: drawing units")


func _set_wall_height(v: float) -> void:
	var d := _selected(Drawing)
	if d:
		_change(d, "wall_height", v, "Genesis: wall height")


func _toggle_layer(on: bool, drawing: Node, layer: String, property: String, inverted: bool) -> void:
	var list := PackedStringArray(drawing.get(property))
	var want_in := (not on) if inverted else on
	if want_in and not (layer in list):
		list.append(layer)
	elif not want_in and layer in list:
		list.remove_at(list.find(layer))
	_change(drawing, property, list, "Genesis: drawing layer")


func _change(node: Object, property: String, value: Variant, action: String) -> void:
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action(action, UndoRedo.MERGE_DISABLE, GnScene.root())
	ur.add_do_property(node, property, value)
	ur.add_undo_property(node, property, node.get(property))
	ur.commit_action()
