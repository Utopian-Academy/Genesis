@tool
extends VBoxContainer

# Saved views. Frame the shot in the editor, save it, and it shows here as a
# live picture of exactly what the render will be.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const ShotPreview := preload("res://addons/genesis/ui/gn_shot_preview.gd")
const GnPhotomatch := preload("res://addons/genesis/core/gn_photomatch.gd")
const GnSections := preload("res://addons/genesis/core/gn_sections.gd")

var _list: ItemList
var _focal: HSlider
var _cut: HSlider
var _plan_height: HSlider
var _preview: ShotPreview
var _match: VBoxContainer
var _photo_label: Label
var _horizon: HSlider
var _height: HSlider
var _shadows: HSlider
var _dialog: EditorFileDialog
var _cams: Array[Camera3D] = []


func _init() -> void:
	name = "Cameras"
	GnUi.note(self, "Frame the shot in the 3D view, then save it.")
	GnUi.button(self, "Save this view", _save)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 110
	_list.item_selected.connect(_pick)
	add_child(_list)
	_focal = GnUi.slider(self, "Lens", 14.0, 135.0, 1.0, _set_focal, func(v): return "%d mm" % int(v))

	_cut = GnUi.slider(self, "Cut away nearer than", 0.1, 60.0, 0.1, _set_cut,
		func(v): return "nothing cut" if v <= 0.11 else "%.1f m" % v)

	_preview = ShotPreview.new()
	add_child(_preview)

	GnUi.heading(self, "Plans and sections")
	GnUi.note(self, "Cameras that slice the design (the selection, or everything) open.")
	_plan_height = GnUi.slider(self, "Plan cut", 0.3, 30.0, 0.1, func(_v): pass, func(v): return "%.1f m up" % v)
	GnUi.show_value(_plan_height, 1.2)
	var srow := HBoxContainer.new()
	GnUi.button(srow, "Plan", func(): GnSections.plan(_plan_height.value); refresh())
	GnUi.button(srow, "Section", func(): GnSections.section(GnSections.design_bounds().get_center().z); refresh())
	GnUi.button(srow, "Elevation", func(): GnSections.elevation(); refresh())
	add_child(srow)

	# Photo match: a photo of the real site behind this camera's shot.
	_match = VBoxContainer.new()
	add_child(_match)
	GnUi.heading(_match, "Photo match")
	_photo_label = GnUi.note(_match, "")
	var row := HBoxContainer.new()
	GnUi.button(row, "Site photo…", _pick_photo)
	GnUi.button(row, "Remove", func(): if _selected(): GnPhotomatch.clear_photo(_selected()); refresh())
	_match.add_child(row)
	_horizon = GnUi.slider(_match, "Horizon in photo", 0.0, 1.0, 0.005,
		func(v): if _selected(): GnPhotomatch.match_horizon(_selected(), v),
		func(v): return "%d%% down" % int(v * 100))
	_height = GnUi.slider(_match, "Camera height", 0.3, 50.0, 0.05,
		func(v): if _selected(): GnPhotomatch.set_height(_selected(), v),
		func(v): return "%.2f m" % v)
	_shadows = GnUi.slider(_match, "Shadows on photo", 0.0, 1.0, 0.01,
		func(v): if _selected(): GnPhotomatch.set_value(_selected(), "shadows", v),
		func(v): return "%d%%" % int(v * 100))


func refresh() -> void:
	var keep := _selected()
	_cams = GnCameras.cameras()
	_list.clear()
	for cam in _cams:
		_list.add_item(cam.name)
	var i := _cams.find(keep)
	if i >= 0:
		_list.select(i)
	_preview.camera = _selected()
	_focal.get_parent().visible = _selected() != null
	_match.visible = _selected() != null
	_cut.get_parent().visible = _selected() != null
	if _selected():
		var cam := _selected()
		GnUi.show_value(_focal, GnCameras.focal_length(cam))
		GnUi.show_value(_cut, cam.near)
		var p := GnPhotomatch.photo(cam)
		_photo_label.text = "Photo: %s. Match the lens, height and horizon, then move the camera until the design sits right." % p.get_file() 			if p != "" else "Put the design into a photo of the real site or venue."
		for c in [_horizon, _height, _shadows]:
			c.get_parent().visible = p != ""
		GnUi.show_value(_height, cam.position.y)
		GnUi.show_value(_shadows, GnPhotomatch.shadow_strength(cam))


func selected_camera() -> Camera3D:
	return _selected()


func _selected() -> Camera3D:
	var picked := _list.get_selected_items()
	if picked.is_empty() or picked[0] >= _cams.size() or not is_instance_valid(_cams[picked[0]]):
		return null
	return _cams[picked[0]]


func _save() -> void:
	var cam := GnCameras.save_view()
	refresh()
	if cam:
		_list.select(_cams.find(cam))
		refresh()


func _pick(_index: int) -> void:
	GnScene.select(_selected())
	refresh()


func _set_cut(metres: float) -> void:
	if _selected():
		GnScene.set_props("Genesis: section cut", [[_selected(), "near", maxf(metres, 0.1)]])


func _set_focal(mm: float) -> void:
	if _selected():
		GnCameras.set_focal_length(_selected(), mm)


func _pick_photo() -> void:
	if _selected() == null:
		return
	if _dialog == null:
		_dialog = EditorFileDialog.new()
		_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_dialog.title = "Photo of the site"
		_dialog.add_filter("*.jpg, *.jpeg, *.png, *.webp", "Photos")
		_dialog.file_selected.connect(func(p):
			var err := GnPhotomatch.set_photo(_selected(), p)
			if err != "":
				_photo_label.text = err
			refresh())
		add_child(_dialog)
	_dialog.popup_file_dialog()
