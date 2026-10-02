@tool
extends VBoxContainer

# The finishing of a shot: pick a saved camera, start from a look, adjust.
# Everything here is stored on that camera, so each view keeps its own look.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnLook := preload("res://addons/genesis/core/gn_look.gd")
const ShotPreview := preload("res://addons/genesis/ui/gn_shot_preview.gd")

var _camera: OptionButton
var _hint: Label
var _body: VBoxContainer
var _preview: ShotPreview
var _looks: ItemList
var _controls := {}
var _two_point: CheckBox
var _clay: CheckBox
var _title: LineEdit
var _logo_label: Label
var _logo_corner: OptionButton
var _logo_dialog: EditorFileDialog
var _save_name: LineEdit
var _all_looks := {}


func _init() -> void:
	name = "Look"
	_camera = GnUi.option(self, "Camera", [], func(_t): refresh())
	_hint = GnUi.note(self, "Save a view on the Cameras section first; the look belongs to a camera.")
	_body = VBoxContainer.new()
	add_child(_body)
	_preview = ShotPreview.new()
	_body.add_child(_preview)

	GnUi.heading(_body, "Looks")
	_looks = ItemList.new()
	_looks.custom_minimum_size.y = 120
	_looks.max_columns = 2
	_looks.same_column_width = true
	_looks.item_clicked.connect(func(i, _p, _b): _apply_look(_looks.get_item_text(i)))
	_body.add_child(_looks)

	GnUi.heading(_body, "Light")
	_add("exposure", "Exposure", -2.0, 2.0, 0.05, func(v): return "%+.1f EV" % v)
	_add("contrast", "Contrast", 0.5, 1.6, 0.01, _pct)
	_add("saturation", "Colour", 0.0, 1.8, 0.01, _pct)
	_add("warmth", "Warmth", -1.0, 1.0, 0.01, func(v): return "cooler" if v < -0.05 else ("warmer" if v > 0.05 else "neutral"))
	GnUi.heading(_body, "Lens")
	_two_point = CheckBox.new()
	_two_point.text = "2-point perspective (keep walls vertical)"
	_two_point.toggled.connect(func(on): _set_look("two_point", on))
	_body.add_child(_two_point)
	_add("dof", "Depth of field", 0.0, 1.0, 0.01, func(v): return "off" if v <= 0.0 else _pct(v))
	_add("focus", "Focus distance", 0.0, 100.0, 0.5, func(v): return "auto" if v <= 0.0 else "%.1f m" % v)
	_add("vignette", "Vignette", 0.0, 1.0, 0.01, _pct)
	_add("aberration", "Lens fringing", 0.0, 1.0, 0.01, _pct)
	_add("bloom", "Bloom", 0.0, 1.0, 0.01, _pct)
	_add("flare", "Lens flare", 0.0, 1.0, 0.01, _pct)
	GnUi.heading(_body, "Colour")
	_add("selective", "Keep one colour", 0.0, 1.0, 0.01, func(v): return "off" if v <= 0.0 else _pct(v))
	_add("keep_hue", "Colour kept", 0.0, 1.0, 0.01, func(v): return "■ %d°" % int(v * 360))
	GnUi.heading(_body, "Finish")
	_add("sharpen", "Sharpen", 0.0, 1.0, 0.01, _pct)
	_add("grain", "Film grain", 0.0, 1.0, 0.01, _pct)
	GnUi.heading(_body, "Style")
	_add("sketch", "Pencil sketch", 0.0, 1.0, 0.01, _pct)
	_add("watercolour", "Watercolour", 0.0, 1.0, 0.01, _pct)
	_add("painting", "Painting", 0.0, 1.0, 0.01, _pct)
	_add("outlines", "Outlines", 0.0, 1.0, 0.01, _pct)
	_add("manga", "Manga", 0.0, 1.0, 0.01, _pct)
	_clay = CheckBox.new()
	_clay.text = "Clay model (everything white, to show form)"
	_clay.toggled.connect(func(on): _set_look("clay", on))
	_body.add_child(_clay)
	GnUi.heading(_body, "Title")
	_title = LineEdit.new()
	_title.placeholder_text = "Text on the image, e.g. the project name"
	_title.text_submitted.connect(func(t): _set_look("title", t))
	_title.focus_exited.connect(func(): _set_look("title", _title.text))
	_body.add_child(_title)
	GnUi.heading(_body, "Logo or image")
	var lrow := HBoxContainer.new()
	_logo_label = Label.new()
	_logo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_logo_label.clip_text = true
	lrow.add_child(_logo_label)
	GnUi.button(lrow, "Choose…", _choose_logo)
	GnUi.button(lrow, "Clear", func(): _set_look("logo", ""))
	_body.add_child(lrow)
	_logo_corner = GnUi.option(_body, "Corner", GnLook.CORNERS, func(t): _set_look("logo_corner", t))
	_add("logo_size", "Logo size", 0.03, 0.4, 0.01, _pct)
	_add("logo_opacity", "Logo opacity", 0.1, 1.0, 0.05, _pct)

	GnUi.heading(_body, "Save this look")
	var row := HBoxContainer.new()
	_save_name = LineEdit.new()
	_save_name.placeholder_text = "Name"
	_save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_save_name)
	GnUi.button(row, "Save", _save_look)
	_body.add_child(row)


func _add(key: String, label: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	_controls[key] = GnUi.slider(_body, label, lo, hi, step, func(v): _set_look(key, v), fmt)


func refresh() -> void:
	var keep := _camera.get_item_text(_camera.selected) if _camera.selected >= 0 else ""
	_camera.clear()
	for cam in GnCameras.cameras():
		_camera.add_item(cam.name)
	GnUi.select_text(_camera, keep)
	if _camera.selected < 0 and _camera.item_count > 0:
		_camera.select(0)
	var cam := _cam()
	_hint.visible = cam == null
	_body.visible = cam != null
	_preview.camera = cam
	if cam == null:
		return
	_all_looks = GnLook.PRESETS.duplicate()
	_all_looks.merge(GnLook.saved_looks())
	_looks.clear()
	for n in _all_looks:
		_looks.add_item(n)
	var look := GnLook.get_look(cam)
	for k in _controls:
		GnUi.show_value(_controls[k], float(look[k]))
	_two_point.set_pressed_no_signal(bool(look.two_point))
	_clay.set_pressed_no_signal(bool(look.clay))
	if not _title.has_focus():
		_title.text = str(look.title)
	_logo_label.text = str(look.get("logo", "")).get_file() if str(look.get("logo", "")) != "" else "No logo"
	GnUi.select_text(_logo_corner, str(look.get("logo_corner", "Bottom right")))


func _cam() -> Camera3D:
	var cams := GnCameras.cameras()
	return cams[_camera.selected] if _camera.selected >= 0 and _camera.selected < cams.size() else null


func _set_look(key: String, value: Variant) -> void:
	if _cam():
		GnLook.set_value(_cam(), key, value)
		if key == "logo":
			refresh()


# A logo is copied into the project, so the scene keeps it wherever it goes.
func _choose_logo() -> void:
	if _logo_dialog == null:
		_logo_dialog = EditorFileDialog.new()
		_logo_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_logo_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_logo_dialog.title = "Choose a logo or image"
		_logo_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp, *.svg", "Images")
		_logo_dialog.file_selected.connect(func(p: String):
			DirAccess.make_dir_recursive_absolute("res://genesis_data/logos")
			var dest := "res://genesis_data/logos/%s" % p.get_file().validate_filename()
			if p.get_extension().to_lower() == "svg":
				# Drawn at a size that stays sharp in a 4K render.
				var img := Image.new()
				img.load_svg_from_buffer(FileAccess.get_file_as_bytes(p), 4.0)
				dest = dest.get_basename() + ".png"
				img.save_png(ProjectSettings.globalize_path(dest))
			else:
				DirAccess.copy_absolute(p, ProjectSettings.globalize_path(dest))
			_set_look("logo", dest))
		add_child(_logo_dialog)
	_logo_dialog.popup_file_dialog()


func _apply_look(look_name: String) -> void:
	if _cam() and _all_looks.has(look_name):
		GnLook.apply_preset(_cam(), _all_looks[look_name])
		refresh()


func _save_look() -> void:
	var n := _save_name.text.strip_edges()
	if n == "" or _cam() == null:
		return
	GnLook.save_look(n, GnLook.get_look(_cam()))
	_save_name.text = ""
	refresh()


static func _pct(v: float) -> String:
	return "%d%%" % int(round(v * 100))
