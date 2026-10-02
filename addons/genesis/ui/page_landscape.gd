@tool
extends VBoxContainer

# Paint vegetation onto the ground. Pick a plant, switch the brush on, drag.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnAssets := preload("res://addons/genesis/core/gn_assets.gd")
const GnBrush := preload("res://addons/genesis/core/gn_brush.gd")
const GnScatter := preload("res://addons/genesis/core/gn_scatter.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const Terrain := preload("res://addons/genesis/set/gn_terrain.gd")
const WaterBody := preload("res://addons/genesis/set/gn_water_body.gd")

const PAINTABLE := ["grass", "plants", "trees"]

var brush: GnBrush:
	set(b):
		brush = b
		brush.stroke_finished.connect(refresh)
		_sync_from_brush()

var _asset: OptionButton
var _paint: Button
var _radius: HSlider
var _density: HSlider
var _scale_min: HSlider
var _scale_max: HSlider
var _turn: CheckBox
var _surfaces: CheckBox
var _count: Label
var _mode: OptionButton
var _ground: OptionButton
var _paint_strength: HSlider
var _strength: HSlider
var _assets: Array = []


func _init() -> void:
	name = "Landscape"
	GnUi.note(self, "Drag in the 3D view to paint. Hold Shift to erase. Each stroke is one undo.")
	_mode = GnUi.option(self, "Brush", ["Paint plants", "Raise ground", "Lower ground", "Smooth ground", "Flatten ground",
		"Paint the ground", "Wipe the ground"], func(t): _set_mode(t))
	_asset = GnUi.option(self, "Plant", [], func(_t): _choose())
	_ground = GnUi.option(self, "Ground", Terrain.GROUNDS.map(func(g): return str(g).capitalize()), func(t): _choose_ground(t))
	_paint = Button.new()
	_paint.text = "Start painting"
	_paint.toggle_mode = true
	_paint.toggled.connect(_toggle)
	add_child(_paint)
	GnUi.heading(self, "Brush")
	_radius = GnUi.slider(self, "Size", 0.5, 30.0, 0.5,
		func(v): brush.radius = v, func(v): return "%.1f m" % v)
	# Density spans grass (tens per m²) to trees (one per 50 m²), so the slider
	# is logarithmic: log10 of copies per square metre.
	_density = GnUi.slider(self, "Density", -2.0, 1.5, 0.05,
		func(v): brush.density = pow(10.0, v), _per_m2)
	GnUi.heading(self, "Variation")
	_scale_min = GnUi.slider(self, "Smallest", 0.3, 2.0, 0.05,
		func(v): brush.scale_range.x = minf(v, brush.scale_range.y), func(v): return "%d%%" % int(v * 100))
	_scale_max = GnUi.slider(self, "Largest", 0.3, 2.0, 0.05,
		func(v): brush.scale_range.y = maxf(v, brush.scale_range.x), func(v): return "%d%%" % int(v * 100))
	_turn = CheckBox.new()
	_turn.text = "Random rotation"
	_turn.button_pressed = true
	_turn.toggled.connect(func(on): brush.random_turn = on)
	add_child(_turn)
	_surfaces = CheckBox.new()
	_surfaces.text = "Paint on any surface (terrain, roofs, planters)"
	_surfaces.toggled.connect(func(on): brush.on_surfaces = on)
	add_child(_surfaces)
	_strength = GnUi.slider(self, "Sculpt strength", 0.02, 2.0, 0.01,
		func(v): brush.sculpt_strength = v, func(v): return "%.2f m" % v)
	_paint_strength = GnUi.slider(self, "Paint strength", 0.05, 1.0, 0.01,
		func(v): brush.paint_strength = v, func(v): return "%d%%" % int(v * 100))
	_count = GnUi.note(self, "")
	_ground.get_parent().visible = false
	_paint_strength.get_parent().visible = false
	GnUi.heading(self, "Terrain and water")
	GnUi.button(self, "Add terrain (replaces the flat ground)", _add_terrain)
	var row := HBoxContainer.new()
	for k in ["Pond", "Pool", "River", "Ocean"]:
		GnUi.button(row, k, _add_water.bind(k))
	add_child(row)


func refresh() -> void:
	var keep := _asset.get_item_text(_asset.selected) if _asset.selected >= 0 else ""
	_assets = GnAssets.scan().assets.filter(func(a): return a.category in PAINTABLE)
	_asset.clear()
	for a in _assets:
		_asset.add_item("%s (%s)" % [a.label(), a.category])
	GnUi.select_text(_asset, keep)
	if _asset.selected < 0 and _asset.item_count > 0:
		_asset.select(0)
	if brush and brush.asset_path == "" and not _assets.is_empty():
		_choose()
	var total := 0
	var root := GnScene.root()
	if root:
		for g in root.find_children("*", "Node3D", true, false):
			if g.get_meta(GnScene.ROLE, "") == "scatter":
				total += GnScatter.points(g).size()
	_count.text = "%d painted copies in this scene." % total
	_paint.disabled = root == null or _assets.is_empty()


func _set_mode(label: String) -> void:
	brush.mode = {"Paint plants": "plants", "Raise ground": "raise", "Lower ground": "lower",
		"Smooth ground": "smooth", "Flatten ground": "flatten", "Paint the ground": "paint",
		"Wipe the ground": "paint"}.get(label, "plants")
	var painting_ground := brush.mode == "paint"
	_asset.get_parent().visible = brush.mode == "plants"
	_ground.get_parent().visible = label == "Paint the ground"
	_strength.get_parent().visible = brush.mode != "plants" and not painting_ground
	_paint_strength.get_parent().visible = painting_ground
	if brush.mode != "plants" and brush.terrain() == null:
		_count.text = "Add terrain first (below) to sculpt or paint."
	elif label == "Wipe the ground":
		brush.paint_layer = 0
	elif painting_ground:
		_choose_ground(_ground.get_item_text(maxi(_ground.selected, 0)))


# The ground to paint: one of the terrain's four layers, taken on the first
# time it is chosen.
func _choose_ground(label: String) -> void:
	var t := brush.terrain() if brush else null
	if t == null:
		return
	var name := label.to_lower().replace(" ", "_")
	var layers: PackedStringArray = t.layers
	var i := layers.find(name)
	if i < 0:
		if layers.size() >= 4:
			_count.text = "This terrain already has four grounds (%s). Wipe one away first, or choose one of those." % ", ".join(layers)
			return
		var more := layers.duplicate()
		more.append(name)
		GnScene.set_props("Genesis: ground layer", [[t, "layers", more]])
		i = more.size() - 1
	brush.paint_layer = i + 1
	_count.text = "Painting %s." % label.to_lower()


func _add_terrain() -> void:
	var root := GnScene.root()
	if root == null or GnScene.find_role("terrain"):
		return
	var t := Terrain.new()
	t.name = "Terrain"
	var ur := EditorInterface.get_editor_undo_redo()
	var ground := GnScene.find_role("ground") as Node3D
	GnScene.add_node(t, root, "Genesis: add terrain", "terrain")
	if ground and ground.visible:
		GnScene.set_props("Genesis: hide flat ground", [[ground, "visible", false]])
	GnScene.select(t)
	refresh()


func _add_water(kind: String) -> void:
	var root := GnScene.root()
	if root == null:
		return
	var w := WaterBody.new()
	w.kind = kind
	w.name = kind
	if kind == "Pool":
		w.width = 10.0
		w.length = 4.0
	elif kind == "River":
		w.width = 30.0
		w.length = 200.0
	w.position = Vector3.ZERO if kind == "Ocean" else GnPlacement.drop_point() + Vector3(0, 0.05, 0)
	if kind == "Ocean":
		w.position = Vector3(0, -0.2, 0)
	GnScene.add_node(w, root, "Genesis: add %s" % kind.to_lower(), "water")
	GnScene.select(w)


func _choose() -> void:
	if _asset.selected < 0 or _asset.selected >= _assets.size():
		return
	var a = _assets[_asset.selected]
	brush.asset_path = a.path
	brush.density = GnBrush.default_density(a.category)
	_sync_from_brush()


func _toggle(on: bool) -> void:
	brush.active = on
	_paint.text = "Stop painting" if on else "Start painting"
	# The editor asks the plugin whether it wants viewport input only when
	# the selection changes, so re-select to make it ask again.
	var target: Node = GnScene.find_role("ground")
	if target == null:
		target = GnScene.root()
	if target:
		GnScene.select(target)


func _sync_from_brush() -> void:
	if brush == null or _radius == null:
		return
	GnUi.show_value(_radius, brush.radius)
	GnUi.show_value(_density, log(brush.density) / log(10.0))
	GnUi.show_value(_scale_min, brush.scale_range.x)
	GnUi.show_value(_scale_max, brush.scale_range.y)
	if _strength:
		GnUi.show_value(_strength, brush.sculpt_strength)
	if _paint_strength:
		GnUi.show_value(_paint_strength, brush.paint_strength)


static func _per_m2(v: float) -> String:
	var d := pow(10.0, v)
	return "%.1f per m²" % d if d >= 1.0 else "1 per %d m²" % int(round(1.0 / d))
