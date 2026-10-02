@tool
extends VBoxContainer

# The library: pick something, click Place, it lands where you are looking.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnAssets := preload("res://addons/genesis/core/gn_assets.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const GnMeasure := preload("res://addons/genesis/core/gn_measure.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

var _search: LineEdit
var _category: OptionButton
var _list: ItemList
var _info: Label
var _assets: Array = []
var _shown: Array = []
var _line: Button
var _spacing: HSlider
var _facing: OptionButton
var measure: GnMeasure


func _init() -> void:
	name = "Assets"
	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _fill())
	add_child(_search)
	_category = GnUi.option(self, "Category", ["All"] + GnAssets.CATEGORIES.map(func(c): return c.capitalize()),
		func(_t): _fill())
	_list = ItemList.new()
	_list.custom_minimum_size.y = 260
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(64, 64)
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.max_columns = 0
	_list.same_column_width = true
	_list.item_selected.connect(_describe)
	_list.item_activated.connect(func(_i): _place())
	add_child(_list)
	GnUi.button(self, "Place in scene", _place)
	_info = GnUi.note(self, "")
	GnUi.button(self, "Rescan library", refresh)

	GnUi.heading(self, "Place along a line")
	GnUi.note(self, "Pick something above, then click the start and the end of the line in the 3D view.")
	_spacing = GnUi.slider(self, "Every", 0.3, 30.0, 0.1, func(v): if measure: measure.line_spacing = v,
		func(v): return "%.1f m" % v)
	GnUi.show_value(_spacing, 5.0)
	_facing = GnUi.option(self, "Facing", ["Along the line", "Across the line", "Random"],
		func(t): if measure: measure.line_facing = {"Along the line": "along", "Across the line": "across"}.get(t, "random"))
	_line = GnUi.button(self, "Start placing along a line", _toggle_line)
	_line.toggle_mode = true


# The list (and its thumbnails, which load every model) is built only while
# the page is showing. At startup the editor may still be importing the
# library, and loading a model mid-import makes Godot start a second,
# nested import that fails.
var _stale := true


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and _stale:
		refresh.call_deferred()


func refresh() -> void:
	if not is_visible_in_tree():
		_stale = true
		return
	_stale = false
	var result := GnAssets.scan()
	_assets = result.assets
	_fill()
	if not result.unlicensed.is_empty():
		_info.text = "%d model(s) skipped: no .license.json beside them." % result.unlicensed.size()


func _fill() -> void:
	_list.clear()
	_shown.clear()
	var want := _category.get_item_text(_category.selected).to_lower()
	var q := _search.text.strip_edges().to_lower()
	for a in _assets:
		if want != "all" and a.category != want:
			continue
		if q != "" and not (q in a.name.to_lower() or q in a.category or q in a.label().to_lower()):
			continue
		var i := _list.add_item(a.label())
		_list.set_item_tooltip(i, "%s · %s" % [a.category, a.license.get("license", "")])
		_shown.append(a)
		if _thumbs.has(a.path) and _thumbs[a.path]:
			_list.set_item_icon(i, _thumbs[a.path])
	# Thumbnails load and render the model, so they come in the background, a
	# few a frame, rather than freezing the editor for a whole library.
	_fill_generation += 1
	_fill_icons.call_deferred(_fill_generation)


var _fill_generation := 0

func _fill_icons(generation: int) -> void:
	# The rows in view first, then on down the list and round to the top.
	var first := maxi(_list.get_item_at_position(Vector2(4, 4), false), 0) if _list.item_count > 0 else 0
	var order: Array = range(first, _shown.size()) + range(0, first)
	var done := 0
	for i in order:
		if generation != _fill_generation or not is_inside_tree():
			return  # the list was rebuilt, or the page closed; start over then
		var path: String = _shown[i].path
		if not _thumbs.has(path):
			var icon := _thumbnail(path)
			if icon and i < _list.item_count:
				_list.set_item_icon(i, icon)
			done += 1
			if done % 3 == 0:
				await get_tree().process_frame


# Godot's background previewer has nothing for an imported model, so the
# thumbnail is rendered from the model's largest mesh, once per session.
static var _thumbs := {}

static func _thumbnail(path: String) -> Texture2D:
	if _thumbs.has(path):
		return _thumbs[path]
	# Not while the editor imports (see above), and not remembered, so it is
	# tried again once the import is done.
	var efs := EditorInterface.get_resource_filesystem()
	if efs.is_scanning() or efs.is_importing() or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	var biggest: Mesh = null
	if packed:
		var inst := packed.instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh and (biggest == null or mi.mesh.get_aabb().get_volume() > biggest.get_aabb().get_volume()):
				biggest = mi.mesh
		if inst is MeshInstance3D and inst.mesh:
			biggest = inst.mesh
		inst.free()
	var tex: Texture2D = null
	# Without a GPU (headless runs, tests) there is nothing to render with.
	if biggest and DisplayServer.get_name() != "headless":
		var made := EditorInterface.make_mesh_previews([biggest], 96)
		tex = made[0] if not made.is_empty() else null
	_thumbs[path] = tex
	return tex


func _describe(index: int) -> void:
	var a = _shown[index]
	_info.text = "%s\n%s · by %s\n%s" % [a.label(), a.license.get("license", "?"),
		a.license.get("author", "?"), a.license.get("attribution", "")]


func _place() -> void:
	var picked := _list.get_selected_items()
	if picked.is_empty():
		_info.text = "Pick something first."
		return
	var a = _shown[picked[0]]
	GnPlacement.place(a.path, a.category)


func _toggle_line() -> void:
	if measure == null:
		return
	var picked := _list.get_selected_items()
	if _line.button_pressed and picked.is_empty():
		_line.button_pressed = false
		_info.text = "Pick something first."
		return
	if _line.button_pressed:
		var a = _shown[picked[0]]
		measure.line_asset = a.path
		measure.line_category = a.category
		measure.line_spacing = _spacing.value
	else:
		measure.line_asset = ""
	measure.active = _line.button_pressed
	_line.text = "Stop placing" if measure.active else "Start placing along a line"
	# Re-select so the editor asks the plugin for viewport input again.
	if GnScene.root():
		GnScene.select(GnScene.root())
