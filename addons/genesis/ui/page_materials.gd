@tool
extends VBoxContainer

# Select something, pick one of its surfaces, click a preset or adjust it.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnMaterials := preload("res://addons/genesis/core/gn_materials.gd")
const GnWeathering := preload("res://addons/genesis/core/gn_weathering.gd")
const GnTiles := preload("res://addons/genesis/core/gn_tiles.gd")

var _hint: Label
var _body: VBoxContainer
var _surfaces: ItemList
var _presets: ItemList
var _color: ColorPickerButton
var _rough: HSlider
var _metal: HSlider
var _opacity: HSlider
var _scale: HSlider
var _scale_row: Control
var _weather: HSlider
var _list: Array = []
var _preset_paths: Array[String] = []
var _tile: HSlider
var _own_note: Label
var _image_dialog: EditorFileDialog
var _tile_layout: OptionButton
var _tile_sliders := {}
var _tile_colours := {}
var _tile_note: Label
var _tile_timer: Timer


func _init() -> void:
	name = "Materials"
	_hint = GnUi.note(self, "Select an object in the scene to change its materials.")
	_body = VBoxContainer.new()
	add_child(_body)
	GnUi.heading(_body, "Surface")
	_surfaces = ItemList.new()
	_surfaces.custom_minimum_size.y = 175
	_surfaces.item_selected.connect(func(_i): _show_surface())
	_body.add_child(_surfaces)

	GnUi.heading(_body, "Presets")
	_presets = ItemList.new()
	_presets.custom_minimum_size.y = 250
	_presets.icon_mode = ItemList.ICON_MODE_TOP
	_presets.fixed_icon_size = Vector2i(56, 56)
	_presets.max_columns = 0
	_presets.same_column_width = true
	_presets.item_clicked.connect(func(i, _p, _b): _apply(i))
	_body.add_child(_presets)

	GnUi.heading(_body, "Your own image")
	_tile = GnUi.slider(_body, "One tile is", 0.1, 10.0, 0.05, func(_v): pass, func(v): return "%.2f m across" % v)
	GnUi.show_value(_tile, 1.0)
	GnUi.button(_body, "Use an image…", _pick_image)
	_own_note = GnUi.note(_body, "A photo or texture map. Normal and roughness maps beside it, named the usual way, come too.")

	GnUi.heading(_body, "Tiles and grout")
	_tile_layout = GnUi.option(_body, "Layout", GnTiles.LAYOUTS, func(_t): _tiles_changed())
	for spec in [["tile_w", "Tile width", 10.0, 1200.0, 5.0, "%d mm"],
			["tile_h", "Tile height", 10.0, 1200.0, 5.0, "%d mm"], ["grout", "Grout joint", 0.5, 20.0, 0.5, "%.1f mm"]]:
		var unit: String = spec[5]
		_tile_sliders[spec[0]] = GnUi.slider(_body, spec[1], spec[2], spec[3], spec[4],
			func(_v): _tiles_changed(), func(v): return unit % v)
	_tile_sliders.gloss = GnUi.slider(_body, "Tile finish", 0.02, 1.0, 0.01, func(_v): _tiles_changed(),
		func(v): return "glazed" if v < 0.15 else ("matte" if v > 0.7 else "satin"))
	_tile_sliders.variation = GnUi.slider(_body, "Shade variation", 0.0, 1.0, 0.05, func(_v): _tiles_changed(),
		func(v): return "none" if v <= 0.0 else "%d%%" % int(v * 100))
	for spec in [["colour", "Tile colour"], ["colour_2", "Second colour"], ["grout_colour", "Grout colour"]]:
		var trow := HBoxContainer.new()
		var tl := Label.new()
		tl.text = spec[1]
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pick := ColorPickerButton.new()
		pick.custom_minimum_size = Vector2(90, 26)
		pick.edit_alpha = false
		pick.popup_closed.connect(_tiles_changed)
		trow.add_child(tl)
		trow.add_child(pick)
		_body.add_child(trow)
		_tile_colours[spec[0]] = pick
	GnUi.button(_body, "Tile this surface", func(): _tile_now())
	_tile_note = GnUi.note(_body, "Real-size tiles with their grout, laid in world space.")
	# Adjusting a tiled surface redraws it once the controls settle.
	_tile_timer = Timer.new()
	_tile_timer.one_shot = true
	_tile_timer.wait_time = 0.4
	_tile_timer.timeout.connect(_tile_now)
	_body.add_child(_tile_timer)
	_show_tiles(GnTiles.DEFAULTS)

	GnUi.heading(_body, "Finish")
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "Colour"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color = ColorPickerButton.new()
	_color.custom_minimum_size = Vector2(90, 26)
	_color.color_changed.connect(func(c): _set_prop("albedo_color", c))
	row.add_child(l)
	row.add_child(_color)
	_body.add_child(row)
	_rough = GnUi.slider(_body, "Roughness", 0.0, 1.0, 0.01,
		func(v): _set_prop("roughness", v), func(v): return "glossy" if v < 0.15 else ("matte" if v > 0.8 else "%.2f" % v))
	_metal = GnUi.slider(_body, "Metallic", 0.0, 1.0, 0.01,
		func(v): _set_prop("metallic", v), func(v): return "%.2f" % v)
	_opacity = GnUi.slider(_body, "Opacity", 0.05, 1.0, 0.01,
		func(v):
			var c := _color.color
			c.a = v
			_color.color = c
			_set_prop("albedo_color", c),
		func(v): return "%d%%" % int(v * 100))
	_scale = GnUi.slider(_body, "Pattern size", 0.25, 4.0, 0.05,
		func(v): _set_pattern(v), func(v): return "%d%%" % int(v * 100))
	_scale_row = _scale.get_parent()
	_weather = GnUi.slider(_body, "Weathering", 0.0, 1.0, 0.2,
		func(v):
			var s := _surface()
			if s:
				GnWeathering.apply(s, v),
		func(v): return ["new", "a little", "weathered", "well weathered", "old", "very old"][clampi(roundi(v * 5), 0, 5)])


func refresh() -> void:
	var picked := EditorInterface.get_selection().get_selected_nodes()
	var target: Node = picked[0] if not picked.is_empty() else null
	var keep := _surfaces.get_selected_items()
	_list = GnMaterials.surfaces(target)
	_hint.visible = _list.is_empty()
	_body.visible = not _list.is_empty()
	_surfaces.clear()
	for s in _list:
		_surfaces.add_item(s.label)
	if not _list.is_empty():
		_surfaces.select(keep[0] if not keep.is_empty() and keep[0] < _list.size() else 0)
	if _presets.item_count == 0:
		_fill_presets()
	_show_surface()


func _fill_presets() -> void:
	_preset_paths = GnMaterials.presets()
	for i in _preset_paths.size():
		_presets.add_item(GnMaterials.preset_name(_preset_paths[i]))
		EditorInterface.get_resource_previewer().queue_resource_preview(_preset_paths[i], self, "_on_preview", i)


func _on_preview(_path: String, preview: Texture2D, _thumb: Texture2D, index: int) -> void:
	if preview and index < _presets.item_count:
		_presets.set_item_icon(index, preview)


func _surface() -> GnMaterials.Surface:
	var picked := _surfaces.get_selected_items()
	if picked.is_empty() or picked[0] >= _list.size():
		return null
	return _list[picked[0]]


func _show_surface() -> void:
	var s := _surface()
	var mat := s.material() as BaseMaterial3D if s else null
	for c in [_color, _rough, _metal, _opacity, _scale]:
		(c as Control).get_parent().modulate.a = 1.0 if mat else 0.4
	if mat == null:
		return
	_color.color = mat.albedo_color
	GnUi.show_value(_rough, mat.roughness)
	GnUi.show_value(_metal, mat.metallic)
	GnUi.show_value(_opacity, mat.albedo_color.a)
	GnUi.show_value(_weather, float(mat.get_meta(&"gn_weathering", 0.0)))
	_scale_row.visible = mat.uv1_triplanar and not mat.has_meta(GnTiles.META)
	if mat.has_meta(GnTiles.META):
		_show_tiles(GnTiles.design(s))
	if mat.uv1_triplanar:
		GnUi.show_value(_scale, 1.0 / maxf(mat.uv1_scale.x, 0.0001) / _preset_tile(mat))


func _apply(index: int) -> void:
	var s := _surface()
	if s and index < _preset_paths.size():
		GnMaterials.apply_preset(s, _preset_paths[index])
		_show_surface()


func _set_prop(prop: String, value: Variant) -> void:
	var s := _surface()
	if s and s.material() is BaseMaterial3D:
		GnMaterials.set_param(s, prop, value)


# Pattern size is shown relative to the preset's own tile, so 100% is a
# real-sized brick whichever preset it is.
func _set_pattern(factor: float) -> void:
	var s := _surface()
	var mat := s.material() as BaseMaterial3D if s else null
	if mat and mat.uv1_triplanar:
		GnMaterials.set_param(s, "uv1_scale", Vector3.ONE / (_preset_tile(mat) * factor))


func _tile_design() -> Dictionary:
	var d := {"layout": _tile_layout.get_item_text(maxi(_tile_layout.selected, 0))}
	for k in ["tile_w", "tile_h", "grout"]:
		d[k] = (_tile_sliders[k] as HSlider).value / 1000.0
	for k in ["gloss", "variation"]:
		d[k] = (_tile_sliders[k] as HSlider).value
	for k in _tile_colours:
		d[k] = (_tile_colours[k] as ColorPickerButton).color
	return d


func _show_tiles(d: Dictionary) -> void:
	GnUi.select_text(_tile_layout, d.layout)
	for k in ["tile_w", "tile_h", "grout"]:
		GnUi.show_value(_tile_sliders[k], d[k] * 1000.0)
	for k in ["gloss", "variation"]:
		GnUi.show_value(_tile_sliders[k], d[k])
	for k in _tile_colours:
		(_tile_colours[k] as ColorPickerButton).color = d[k]
	(_tile_colours.colour_2 as ColorPickerButton).get_parent().visible = d.layout == "Checkerboard"
	_tile_note.text = GnTiles.report(d)


# A change to the controls: shown straight away, and redrawn on the surface
# if it is already tiled.
func _tiles_changed() -> void:
	var d := _tile_design()
	(_tile_colours.colour_2 as ColorPickerButton).get_parent().visible = d.layout == "Checkerboard"
	_tile_note.text = GnTiles.report(d)
	var s := _surface()
	var mat := s.material() if s else null
	if mat and mat.has_meta(GnTiles.META):
		_tile_timer.start()


func _tile_now() -> void:
	var s := _surface()
	if s == null:
		_tile_note.text = "Pick a surface first."
		return
	GnTiles.apply(s, _tile_design())
	_show_surface()


func _preset_tile(mat: BaseMaterial3D) -> float:
	var base := mat.get_meta("gn_tile_m", 0.0) as float
	return base if base > 0.0 else 1.0


func _pick_image() -> void:
	if _surface() == null:
		_own_note.text = "Pick a surface first."
		return
	if _image_dialog == null:
		_image_dialog = EditorFileDialog.new()
		_image_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_image_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_image_dialog.title = "Use an image as a material"
		for ext in ["png", "jpg", "jpeg", "webp", "tga", "exr"]:
			_image_dialog.add_filter("*.%s" % ext)
		_image_dialog.file_selected.connect(_use_image)
		EditorInterface.get_base_control().add_child(_image_dialog)
	_image_dialog.popup_file_dialog()


func _use_image(path: String) -> void:
	var s := _surface()
	if s == null:
		return
	_own_note.text = "Bringing in %s…" % path.get_file()
	var err: String = await GnMaterials.apply_image(s, path, _tile.value)
	var maps := GnMaterials.partner_maps(path)
	var extra: Array = []
	if maps.normal != "":
		extra.append("normal map")
	if maps.roughness != "":
		extra.append("roughness map")
	_own_note.text = err if err != "" else "%s is on, %.2f m a tile%s." % [path.get_file(), _tile.value,
		"" if extra.is_empty() else ", with its " + " and ".join(extra)]
	_show_surface()
