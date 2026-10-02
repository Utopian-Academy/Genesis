@tool
extends VBoxContainer

# Event set pieces built to real specifications: LED walls from cabinet
# specs, truss at standard sizes, stage decks from standard modules. Each is
# a parametric object: select it and change it in Godot's Inspector.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const LedWall := preload("res://addons/genesis/set/gn_led_wall.gd")
const Truss := preload("res://addons/genesis/set/gn_truss.gd")
const StageDeck := preload("res://addons/genesis/set/gn_stage_deck.gd")
const Fixture := preload("res://addons/genesis/set/gn_light_fixture.gd")
const GnAssets := preload("res://addons/genesis/core/gn_assets.gd")
const Crowd := preload("res://addons/genesis/set/gn_crowd.gd")
const LineArray := preload("res://addons/genesis/set/gn_line_array.gd")
const Effect := preload("res://addons/genesis/set/gn_effect.gd")
const FlyingScreen := preload("res://addons/genesis/set/gn_flying_screen.gd")
const AreaLight := preload("res://addons/genesis/set/gn_area_light.gd")

var _report: Label
var _export: Button
var _message: Label


func _init() -> void:
	name = "Set"
	GnUi.note(self, "Stage, screens and rigging at real sizes. Select one to change it in the Inspector.")
	GnUi.heading(self, "Add")
	GnUi.button(self, "LED wall", func(): _add(LedWall.new(), "LED wall", "led_wall"))
	GnUi.button(self, "Stage deck", func(): _add(StageDeck.new(), "Stage", "stage"))
	GnUi.button(self, "Truss span", func(): _add_span())
	GnUi.button(self, "Goalpost (two towers and a span)", _add_goalpost)
	GnUi.button(self, "Circle truss, 8 m across", _add_circle)
	GnUi.button(self, "Flying screen (LED wall under a helicopter)", _add_flying_screen)
	GnUi.heading(self, "Sound")
	GnUi.button(self, "Line array, flown", _add_line_array)
	GnUi.heading(self, "Lights")
	GnUi.note(self, "Beams show in the air with Stage haze on (Environment).")
	for k in ["Beam (moving head)", "Wash", "Downlight", "Bulb"]:
		GnUi.button(self, k, _add_light.bind(k))
	GnUi.button(self, "Moving spot (real fixture)", _add_light.bind("Beam (moving head)", "spot_gigapointe"))
	GnUi.button(self, "LED wash (real fixture)", _add_light.bind("Wash", "wash_aurora"))
	var area_row := HBoxContainer.new()
	for spec in [["Area light", "Rectangle", Vector2(1.2, 0.6)], ["Light strip", "Strip", Vector2(2.4, 0.05)], ["Round panel", "Disc", Vector2(0.6, 0.6)]]:
		var b := GnUi.button(area_row, spec[0], _add_area.bind(spec[1], spec[2]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(area_row)
	GnUi.heading(self, "Effects")
	GnUi.note(self, "Warmed up, so a still shows them in full. Size and amount are in the Inspector.")
	var grid := GridContainer.new()
	grid.columns = 2
	for k in Effect.KINDS:
		var b := GnUi.button(grid, k, _add_effect.bind(k))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)
	GnUi.heading(self, "People")
	GnUi.note(self, "A crowd faces its forward: turn it to face the stage. Density is people per m².")
	for m in ["Concert", "Seated", "Milling about", "Frustrated"]:
		GnUi.button(self, {"Concert": "Concert crowd", "Seated": "Seated audience",
			"Milling about": "People milling about", "Frustrated": "Frustrated queue"}[m], _add_crowd.bind(m))
	GnUi.heading(self, "Selected")
	_report = GnUi.note(self, "")
	_export = GnUi.button(self, "Save pixel map for the processor…", _save_map)
	_message = GnUi.note(self, "")


func refresh() -> void:
	var wall := _wall()
	_export.visible = wall != null
	_report.text = "Select an LED wall, flying screen, line array or crowd to see its numbers."
	if wall:
		_report.text = wall.report_text()
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n.get_script() == LineArray or n.get_script() == FlyingScreen or n.get_script() == AreaLight:
			_report.text = n.report_text()
		elif n.get_script() == Crowd:
			_report.text = "%d people on %.0f m²" % [n.headcount(), n.width * n.depth]


func _wall() -> Node:
	var picked := EditorInterface.get_selection().get_selected_nodes()
	for n in picked:
		if n.get_script() == LedWall:
			return n
	return null


func _add(node: Node3D, label: String, role: String) -> void:
	if GnScene.root() == null:
		_message.text = "Open or make a scene first."
		return
	node.name = label
	node.position = GnPlacement.drop_point()
	GnScene.add_node(node, GnScene.root(), "Genesis: add %s" % label, role)
	GnScene.select(node)
	refresh()


func _add_span() -> void:
	var t := Truss.new()
	t.position = GnPlacement.drop_point() + Vector3(-3, 5, 0)
	t.name = "Truss"
	GnScene.add_node(t, GnScene.root(), "Genesis: add truss", "truss")
	GnScene.select(t)


func _add_circle() -> void:
	var t := Truss.new()
	t.name = "Circle truss"
	t.section = "400 mm triangle"
	t.make_circle(4.0)
	# The circle is drawn from its first point; centre it on the drop point.
	t.position = GnPlacement.drop_point() + Vector3(0, 7, -4)
	GnScene.add_node(t, GnScene.root(), "Genesis: add circle truss", "truss")
	GnScene.select(t)


# Two 6 m towers and an 8 m span across their tops: the commonest rig there is.
func _add_goalpost() -> void:
	var root := GnScene.root()
	if root == null:
		return
	var at := GnPlacement.drop_point()
	var group := Node3D.new()
	group.name = "Goalpost"
	group.position = at
	var span := 8.0
	var height := 6.0
	for x in [-span * 0.5, span * 0.5]:
		var tower := Truss.new()
		tower.name = "Tower"
		tower.length = height
		tower.rotation_degrees = Vector3(0, 0, 90)
		tower.position = Vector3(x, 0, 0)
		group.add_child(tower)
	var top := Truss.new()
	top.name = "Span"
	top.length = span + 0.29
	top.position = Vector3(-span * 0.5 - 0.145, height, 0)
	group.add_child(top)
	GnScene.add_node(group, root, "Genesis: add goalpost", "truss")
	GnScene.select(group)


func _add_line_array() -> void:
	if GnScene.root() == null:
		_message.text = "Open or make a scene first."
		return
	if LineArray.elements().is_empty():
		_message.text = "No line array boxes in the library: run Genesis's setup."
		return
	var a := LineArray.new()
	a.name = "Line array"
	a.position = GnPlacement.drop_point() + Vector3(0, 9, 0)
	GnScene.add_node(a, GnScene.root(), "Genesis: add line array", "speakers")
	GnScene.select(a)


# A soft light from a surface, hung facing down 3 m up.
func _add_area(shape: String, size: Vector2) -> void:
	if GnScene.root() == null:
		_message.text = "Open or make a scene first."
		return
	var a := AreaLight.new()
	a.name = {"Rectangle": "Area light", "Strip": "Light strip", "Disc": "Round panel"}[shape]
	a.shape = shape
	a.size = size
	a.lumens = {"Rectangle": 4000.0, "Strip": 2400.0, "Disc": 1800.0}[shape]
	a.position = GnPlacement.drop_point() + Vector3(0, 3, 0)
	a.rotation_degrees = Vector3(-90, 0, 0)
	GnScene.add_node(a, GnScene.root(), "Genesis: add %s" % a.name.to_lower(), "light")
	GnScene.select(a)


func _add_flying_screen() -> void:
	if GnScene.root() == null:
		_message.text = "Open or make a scene first."
		return
	if FlyingScreen.lifters().is_empty():
		_message.text = "No heavy-lift helicopter in the library: run Genesis's setup."
		return
	var f := FlyingScreen.new()
	f.name = "Flying screen"
	# High enough that the screen's bottom clears the ground by about 10 m.
	f.position = GnPlacement.drop_point() + Vector3(0, 40, 0)
	GnScene.add_node(f, GnScene.root(), "Genesis: add flying screen", "flying_screen")
	GnScene.select(f)


func _add_crowd(mood: String) -> void:
	var c := Crowd.new()
	c.mood = mood
	match mood:
		"Seated":
			c.width = 10.0
			c.depth = 9.0
		"Frustrated":
			c.width = 2.0
			c.depth = 10.0
			c.density = 1.5
			c.turn_spread = 40.0
		"Milling about":
			c.density = 0.8
			c.turn_spread = 180.0
	_add(c, "%s crowd" % mood, "people")


func _add_light(kind: String, model := "") -> void:
	if GnScene.root() == null:
		return
	var f := Fixture.new()
	f.kind = kind
	if model != "":
		f.model = GnAssets.find("lighting", model)
	f.name = kind.get_slice(" ", 0)
	match kind:
		"Wash":
			f.lumens = 8000.0
			f.beam_degrees = 40.0
		"Downlight":
			f.lumens = 700.0
			f.beam_degrees = 60.0
			f.tilt = -90.0
		"Bulb":
			f.lumens = 400.0
	f.position = GnPlacement.drop_point() + Vector3(0, 6 if kind in ["Beam (moving head)", "Wash"] else 2.7, 0)
	GnScene.add_node(f, GnScene.root(), "Genesis: add %s" % kind, "light")
	GnScene.select(f)


func _save_map() -> void:
	var wall := _wall()
	if wall == null:
		return
	DirAccess.make_dir_recursive_absolute("res://renders")
	var r: Dictionary = wall.report()
	var path := "res://renders/%s_pixel_map_%dx%d.png" % [str(wall.name).to_snake_case(), r.resolution.x, r.resolution.y]
	var img: Image = wall.pixel_map()
	# The processor wants the true native resolution.
	if img.get_size() != Vector2i(r.resolution):
		img.resize(r.resolution.x, r.resolution.y, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	_message.text = "Saved %s" % path


func _add_effect(kind: String) -> void:
	var e := Effect.new()
	e.kind = kind
	_add(e, kind, "effect")
