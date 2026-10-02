@tool
extends EditorPlugin

# The whole user journey through the Genesis dock's real controls: buttons
# are found by their labels and pressed, lists are clicked, sliders are
# moved, and the brush is driven by mouse events sent into Godot's own 3D
# viewport, so the editor's input forwarding is under test too. A screenshot
# of the editor is saved after every step for a person to look at.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnScatter := preload("res://addons/genesis/core/gn_scatter.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")

const SHOTS := "res://ui_shots"
const HOUSE := "res://genesis_assets/architecture/demo_house.glb"

var _ok := true
var _dock: Control
var _shot := 0


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	await _frames(30)
	DirAccess.make_dir_recursive_absolute(SHOTS)
	FileAccess.open(SHOTS + "/.gdignore", FileAccess.WRITE).close()
	for d in EditorInterface.get_base_control().find_children("*", "EditorDock", true, false):
		if d.get("title") == "Genesis":
			_dock = d
	_check("dock is in the editor", _dock != null, "")
	if _dock == null:
		_quit()
		return
	# Make the dock visible whichever dock tab it landed behind.
	_dock.make_visible()
	await _screenshot("empty")

	# 1. Scene: name it, New scene.
	await _tab("Scene")
	var name_box := _find("LineEdit", func(c): return c.placeholder_text == "Scene name") as LineEdit
	name_box.text = "My House"
	_press("New scene")
	await _frames(20)
	var root := GnScene.root()
	_check("New scene opened a scene", root != null and root.name == "MyHouse", str(root))
	_check("and it came with sun, sky and ground", GnEnvironment.is_set_up(), "")
	# Landscape first, on open ground: the editor camera starts at the origin,
	# which is where the house is about to go.
	await _tab("Landscape")
	var plant := _find("OptionButton", func(c): return _option_index(c, "Grass Tuft (grass)") >= 0) as OptionButton
	plant.select(_option_index(plant, "Grass Tuft (grass)"))
	plant.item_selected.emit(plant.selected)
	var brush_button := _button("Start painting")
	brush_button.button_pressed = true
	await _frames(5)
	await _drag_in_viewport(Vector2(0.3, 0.75), Vector2(0.7, 0.75))
	var grass := GnScatter.find_group("res://genesis_assets/grass/grass_tuft.glb")
	var painted := GnScatter.points(grass).size() if grass else 0
	print("GN_UI brush painted %d copies through the real viewport" % painted)
	_check("dragging in the 3D view painted grass", painted > 50, str(painted))
	var count_label := _find("Label", func(c): return c.text.ends_with("painted copies in this scene."))
	_check("copy count updates after the stroke", count_label != null and count_label.text.begins_with(str(painted)), count_label.text if count_label else "none")
	await _screenshot("landscape_tab")
	brush_button.button_pressed = false
	await _frames(3)

	# The file dialog is Godot's; what it calls when a file is chosen is ours.
	var scene_page := _page("Scene")
	await scene_page._import(ProjectSettings.globalize_path(HOUSE))
	_check("building brought in", root.find_child("DemoHouse", false, false) != null, "")
	await _screenshot("scene_tab")

	# 2. Assets: pick a tree, Place.
	await _tab("Assets")
	await _frames(30)  # thumbnails render in the background
	var list := _find("ItemList", func(c): return c.item_count > 0 and _has_item(c, "Tree Round")) as ItemList
	_check("asset library lists the demo assets", list != null, "")
	# A few a frame, the rows in view first; give a long library time to reach it.
	for i in 600:
		if list == null or list.get_item_icon(_item(list, "Tree Round")) != null:
			break
		await _frames(1)
	_check("assets have thumbnails", list != null and list.get_item_icon(_item(list, "Tree Round")) != null, "")
	if list:
		list.select(_item(list, "Tree Round"))
		list.item_selected.emit(_item(list, "Tree Round"))
		_press("Place in scene")
		await _frames(5)
		_check("Place put a tree in the scene", root.find_child("TreeRound", false, false) != null, "")
		var tree := root.find_child("TreeRound", false, false) as Node3D
		if tree:
			tree.position = Vector3(-12, 0, -8)
	await _screenshot("assets_tab")

	# 3. Environment: late afternoon.
	await _tab("Environment")
	var time := _slider("Time of day")
	time.value = 17.0
	await _frames(3)
	_check("time slider moved the sun", is_equal_approx(GnEnvironment.value("time_of_day"), 17.0), str(GnEnvironment.value("time_of_day")))
	await _screenshot("environment_tab")

	# 5. Materials: select the house, choose Plaster, click Brick.
	GnScene.select(root.find_child("DemoHouse", false, false))
	await _frames(3)
	await _tab("Materials")
	var surfaces := _find("ItemList", func(c): return _has_item(c, "Plaster")) as ItemList
	var presets := _find("ItemList", func(c): return _has_item(c, "Brick")) as ItemList
	_check("Materials lists the house's surfaces and the presets", surfaces != null and presets != null, "")
	if surfaces and presets:
		surfaces.select(_item(surfaces, "Plaster"))
		surfaces.item_selected.emit(_item(surfaces, "Plaster"))
		presets.item_clicked.emit(_item(presets, "Brick"), Vector2.ZERO, MOUSE_BUTTON_LEFT)
		await _frames(3)
		var mesh := root.find_child("DemoHouse", false, false).find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var bricked := false
		for i in mesh.get_surface_override_material_count():
			var m := mesh.get_surface_override_material(i)
			bricked = bricked or (m != null and m.resource_name == "Brick")
		_check("clicking Brick bricked the plaster", bricked, "")
	await _screenshot("materials_tab")

	# 6. Cameras: save the view the editor is showing.
	await _tab("Cameras")
	_press("Save this view")
	await _frames(5)
	var cams := GnCameras.cameras()
	_check("Save this view made Camera 01", cams.size() == 1 and cams[0].name == "Camera 01", str(cams))
	if not cams.is_empty():
		cams[0].position = Vector3(15, 3.2, 21)
		cams[0].look_at(Vector3(-2.5, 3.0, 0))
	var cam_list := _find("ItemList", func(c): return _has_item(c, "Camera 01")) as ItemList
	if cam_list:
		cam_list.select(0)
		cam_list.item_selected.emit(0)
	await _frames(10)
	await _screenshot("cameras_tab")

	# 7. Render.
	await _tab("Render")
	_page("Render").refresh()
	_press("Render still")
	var deadline := Time.get_ticks_msec() + 30000
	var result := _find("Label", func(c): return c.text.begins_with("Saved ") or c.text.begins_with("The render failed")) as Label
	while result == null and Time.get_ticks_msec() < deadline:
		await _frames(5)
		result = _find("Label", func(c): return c.text.begins_with("Saved ") or c.text.begins_with("The render failed")) as Label
	_check("Render still saved an image", result != null and result.text.begins_with("Saved "), result.text if result else "timed out")
	await _screenshot("render_tab")
	if result and result.text.begins_with("Saved "):
		var img := Image.load_from_file(ProjectSettings.globalize_path(result.text.trim_prefix("Saved ")))
		img.save_png(SHOTS + "/final_render.png")

	EditorInterface.save_scene()
	_quit()


# ---------------------------------------------------------------------------
func _drag_in_viewport(from: Vector2, to: Vector2) -> void:
	# A person doesn't drag the moment a scene is made; the editor is still
	# scanning the project (a thousand-odd library files) and input waits
	# for it. Wait as they would.
	var efs := EditorInterface.get_resource_filesystem()
	for i in 480:
		if not efs.is_scanning() and not efs.is_importing():
			break
		await get_tree().create_timer(0.25).timeout
	await _frames(5)
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var container := vp.get_parent() as Control
	var rect := container.get_global_rect()
	var a := rect.position + rect.size * from
	var b := rect.position + rect.size * to
	var move := InputEventMouseMotion.new()
	move.position = a
	move.global_position = a
	Input.parse_input_event(move)
	await _frames(2)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = a
	press.global_position = a
	Input.parse_input_event(press)
	await _frames(2)
	for i in 21:
		var m := InputEventMouseMotion.new()
		m.position = a.lerp(b, i / 20.0)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.relative = (b - a) / 20.0
		Input.parse_input_event(m)
		await _frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = b
	release.global_position = b
	Input.parse_input_event(release)
	await _frames(3)


# Sections are chosen the way a user does: by pressing their button.
func _tab(title: String) -> void:
	var b := _find("Button", func(c): return c.text == title.to_upper()) as Button
	_check("section button %s is there" % title.to_upper(), b != null, "")
	if b:
		b.button_pressed = true
		b.pressed.emit()
	await _frames(3)


func _page(title: String) -> Control:
	for scroll in _dock.find_children(title, "ScrollContainer", true, false):
		return scroll.get_child(0)
	return null


func _find(type: String, pred: Callable) -> Control:
	for c in _dock.find_children("*", type, true, false):
		if c.is_visible_in_tree() and pred.call(c):
			return c
	return null


func _button(text: String) -> Button:
	return _find("Button", func(c): return c.text == text) as Button


func _press(text: String) -> void:
	var b := _button(text)
	_check("button \"%s\" is there and enabled" % text, b != null and not b.disabled, "")
	if b and not b.disabled:
		b.pressed.emit()


func _slider(label: String) -> HSlider:
	var l := _find("Label", func(c): return c.text == label)
	return l.get_parent().get_parent().get_child(1) as HSlider


func _has_item(list: ItemList, text: String) -> bool:
	return _item(list, text) >= 0


func _item(list: ItemList, text: String) -> int:
	for i in list.item_count:
		if list.get_item_text(i) == text:
			return i
	return -1


func _option_index(o: OptionButton, text: String) -> int:
	for i in o.item_count:
		if o.get_item_text(i) == text:
			return i
	return -1


func _screenshot(label: String) -> void:
	# The editor idles without redrawing; force frames or this waits forever.
	var low := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	OS.low_processor_usage_mode = low
	_shot += 1
	var img := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [SHOTS, _shot, label])


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_UI %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _quit() -> void:
	print("GN_UI RESULT %s" % ("PASS" if _ok else "FAIL"))
	EditorInterface.get_base_control().get_tree().quit(0 if _ok else 1)


func _frames(n: int) -> void:
	var low := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	for i in n:
		await EditorInterface.get_base_control().get_tree().process_frame
	OS.low_processor_usage_mode = low
