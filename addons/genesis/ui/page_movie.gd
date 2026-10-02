@tool
extends VBoxContainer

# Fly-throughs: string saved cameras into a gliding path, add orbits around
# the building, preview with play and scrub, render to video.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnMovie := preload("res://addons/genesis/core/gn_movie.gd")
const Mover := preload("res://addons/genesis/set/gn_mover.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const GnLook := preload("res://addons/genesis/core/gn_look.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const ShotPreview := preload("res://addons/genesis/ui/gn_shot_preview.gd")
const GnPhasing := preload("res://addons/genesis/core/gn_phasing.gd")

const SIZES := {"1920 × 1080 (HD)": Vector2i(1920, 1080), "2560 × 1440": Vector2i(2560, 1440),
	"3840 × 2160 (4K)": Vector2i(3840, 2160), "1280 × 720 (quick)": Vector2i(1280, 720)}

var _shots: ItemList
var _cams: ItemList
var _path_secs: HSlider
var _orbit_secs: HSlider
var _orbit_deg: HSlider
var _orbit_height: HSlider
var _preview: ShotPreview
var _proxy: Camera3D
var _scrub: HSlider
var _play: Button
var _playing := false
var _time := 0.0
var _size: OptionButton
var _render_button: Button
var _status: Label
var _last := ""
var _lapse: CheckBox
var _lapse_from: HSlider
var _lapse_to: HSlider
var _phase_at: HSlider
var _phase_over: HSlider
var _phase_style: OptionButton


func _init() -> void:
	name = "Movie"
	_proxy = Camera3D.new()
	_proxy.name = "MoviePreview"
	add_child(_proxy)
	_preview = ShotPreview.new()
	_preview.camera = _proxy
	add_child(_preview)
	var transport := HBoxContainer.new()
	_play = GnUi.button(transport, "Play", _toggle_play)
	_scrub = HSlider.new()
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.step = 0.01
	_scrub.value_changed.connect(func(v): _time = v; _pose())
	transport.add_child(_scrub)
	add_child(transport)

	GnUi.heading(self, "Shots")
	_shots = ItemList.new()
	_shots.custom_minimum_size.y = 90
	add_child(_shots)
	var edit := HBoxContainer.new()
	GnUi.button(edit, "Move up", _move_up)
	GnUi.button(edit, "Remove", _remove)
	add_child(edit)

	GnUi.heading(self, "Add a path through cameras")
	GnUi.note(self, "Pick two or more saved cameras; the camera glides through them in list order.")
	_cams = ItemList.new()
	_cams.select_mode = ItemList.SELECT_MULTI
	_cams.custom_minimum_size.y = 80
	add_child(_cams)
	_path_secs = GnUi.slider(self, "Length", 2.0, 60.0, 0.5, func(_v): pass, func(v): return "%.1f s" % v)
	GnUi.show_value(_path_secs, 8.0)
	GnUi.button(self, "Add path", _add_path)

	GnUi.heading(self, "Add an orbit")
	GnUi.note(self, "Circles whatever is selected in the scene (the building, usually).")
	_orbit_deg = GnUi.slider(self, "Turn", 30.0, 360.0, 5.0, func(_v): pass, func(v): return "%d°" % int(v))
	_orbit_height = GnUi.slider(self, "Height", 1.5, 60.0, 0.5, func(_v): pass, func(v): return "%.1f m" % v)
	_orbit_secs = GnUi.slider(self, "Length", 2.0, 60.0, 0.5, func(_v): pass, func(v): return "%.1f s" % v)
	GnUi.show_value(_orbit_deg, 120.0)
	GnUi.show_value(_orbit_height, 8.0)
	GnUi.show_value(_orbit_secs, 10.0)
	GnUi.button(self, "Add orbit", _add_orbit)

	GnUi.heading(self, "Time-lapse")
	_lapse = CheckBox.new()
	_lapse.text = "The sun moves through the film"
	_lapse.toggled.connect(func(_on): _save_lapse())
	add_child(_lapse)
	_lapse_from = GnUi.slider(self, "From", 4.0, 22.0, 0.25, func(_v): _save_lapse(), _clock)
	_lapse_to = GnUi.slider(self, "To", 4.0, 22.0, 0.25, func(_v): _save_lapse(), _clock)
	GnUi.show_value(_lapse_from, 7.0)
	GnUi.show_value(_lapse_to, 19.0)

	GnUi.heading(self, "Moving objects")
	GnUi.note(self, "Traffic, people, boats. Add a path, shape it with Godot's path tool, put things on it; set the speed in the Inspector.")
	var mrow := HBoxContainer.new()
	GnUi.button(mrow, "Add a path", _add_mover)
	GnUi.button(mrow, "Put selection on it", _ride)
	add_child(mrow)

	GnUi.heading(self, "Phasing: build it up")
	GnUi.note(self, "Select objects (a floor, a stage, the trees) and say when they arrive in the film and how.")
	_phase_at = GnUi.slider(self, "Arrive at", 0.0, 120.0, 0.5, func(_v): pass, func(v): return "%.1f s" % v)
	_phase_over = GnUi.slider(self, "Taking", 0.0, 30.0, 0.5, func(_v): pass, func(v): return "%.1f s" % v)
	GnUi.show_value(_phase_over, 2.0)
	_phase_style = GnUi.option(self, "How", GnPhasing.STYLES, func(_t): pass)
	var prow := HBoxContainer.new()
	GnUi.button(prow, "Phase the selection", _phase)
	GnUi.button(prow, "Clear its phasing", func():
		GnPhasing.clear(_selected3d())
		refresh())
	add_child(prow)

	GnUi.heading(self, "Render")
	_size = GnUi.option(self, "Size", SIZES.keys(), func(_t): pass)
	_render_button = GnUi.button(self, "Render movie", _render)
	_status = GnUi.note(self, "")
	GnUi.button(self, "Show renders folder", func():
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(GnRender.OUTPUT_DIR) if _last == "" else _last))


func refresh() -> void:
	var list := GnMovie.shots()
	var lapse := GnMovie.timelapse()
	_lapse.set_pressed_no_signal(not lapse.is_empty())
	if not lapse.is_empty():
		GnUi.show_value(_lapse_from, float(lapse.from))
		GnUi.show_value(_lapse_to, float(lapse.to))
	_shots.clear()
	for i in list.size():
		_shots.add_item("%d. %s" % [i + 1, _describe(list[i])])
	var keep := _cams.get_selected_items()
	_cams.clear()
	for cam in GnCameras.cameras():
		_cams.add_item(cam.name)
	for k in keep:
		if k < _cams.item_count:
			_cams.select(k, false)
	var total := GnMovie.duration(list)
	_scrub.max_value = maxf(total, 0.01)
	_render_button.disabled = total <= 0.0
	if total <= 0:
		_status.text = "Add a shot to start."
	else:
		var blocked := GnMovie.obstructions(list)
		var lines: Array = ["%d shots, %.1f seconds." % [list.size(), total]]
		for b in blocked:
			lines.append("Camera passes through %s at %.1f–%.1f s." % [b.what, b.from, b.to])
		var phased := GnPhasing.phased(GnScene.root()).size()
		if phased > 0:
			lines.append("%d object%s phased in, the last done at %.1f s." % [phased, "" if phased == 1 else "s", GnPhasing.last_end(GnScene.root())])
		_status.text = "\n".join(lines)
	_pose()


func _describe(s: Dictionary) -> String:
	if s.type == "orbit":
		return "Orbit %d° (%.1f s)" % [int(s.degrees), float(s.seconds)]
	return "Path %s (%.1f s)" % [" → ".join(s.cameras), float(s.seconds)]


func _process(delta: float) -> void:
	if not _playing:
		return
	_time += delta
	if _time > _scrub.max_value:
		_time = 0.0
	_scrub.set_value_no_signal(_time)
	_pose()


func _pose() -> void:
	# The film's moment is shown only while this page is: elsewhere the scene
	# is as built (no half-risen phasing while editing).
	if not is_visible_in_tree():
		return
	GnMovie.show_time(_time, GnMovie.shots())
	var at := GnMovie.sample(GnMovie.shots(), _time)
	if at.is_empty():
		return
	_proxy.global_transform = at.transform
	_proxy.fov = at.fov
	_proxy.set_meta(GnLook.META, at.look)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and GnScene.root():
		GnPhasing.finish(GnScene.root())


func _selected3d() -> Array:
	return EditorInterface.get_selection().get_selected_nodes().filter(func(n): return n is Node3D)


func _phase() -> void:
	var picked := _selected3d()
	if picked.is_empty():
		_status.text = "Select what should be built in the film first."
		return
	GnPhasing.finish(GnScene.root())
	GnPhasing.set_phase(picked, _phase_at.value, _phase_over.value, _phase_style.get_item_text(_phase_style.selected))
	_status.text = "%d object%s arrive at %.1f s. Scrub the film to see it." % [picked.size(), "" if picked.size() == 1 else "s", _phase_at.value]
	refresh()


func _toggle_play() -> void:
	_playing = not _playing
	_play.text = "Pause" if _playing else "Play"


func _add_path() -> void:
	var names: Array = []
	for i in _cams.get_selected_items():
		names.append(_cams.get_item_text(i))
	if names.size() < 2:
		_status.text = "Pick at least two cameras for a path."
		return
	var list := GnMovie.shots()
	list.append(GnMovie.path_shot(names, _path_secs.value))
	GnMovie.set_shots(list, "Genesis: add path")
	_status.text = ""
	refresh()


func _add_orbit() -> void:
	var picked := EditorInterface.get_selection().get_selected_nodes()
	var box := AABB()
	var found := false
	for n in picked:
		if n is Node3D:
			for vi in ([n] if n is VisualInstance3D else []) + n.find_children("*", "VisualInstance3D", true, false):
				var b: AABB = vi.global_transform * vi.get_aabb()
				box = b if not found else box.merge(b)
				found = true
	var centre := box.get_center() if found else Vector3.ZERO
	var radius := maxf(box.size.length() * 0.9, 12.0) if found else 25.0
	var list := GnMovie.shots()
	list.append(GnMovie.orbit_shot(Vector3(centre.x, 0.0, centre.z), radius, _orbit_height.value,
		_orbit_deg.value, _orbit_secs.value))
	GnMovie.set_shots(list, "Genesis: add orbit")
	_status.text = ""
	refresh()


func _move_up() -> void:
	var sel := _shots.get_selected_items()
	if sel.is_empty() or sel[0] == 0:
		return
	var list := GnMovie.shots()
	var i: int = sel[0]
	var s = list[i]
	list.remove_at(i)
	list.insert(i - 1, s)
	GnMovie.set_shots(list, "Genesis: reorder shots")
	refresh()


func _remove() -> void:
	var sel := _shots.get_selected_items()
	if sel.is_empty():
		return
	var list := GnMovie.shots()
	list.remove_at(sel[0])
	GnMovie.set_shots(list, "Genesis: remove shot")
	refresh()


func _render() -> void:
	var list := GnMovie.shots()
	var scene := GnScene.root()
	var movie_name := "%s_movie" % (scene.name if scene else "scene")
	_render_button.disabled = true
	_playing = false
	var size: Vector2i = SIZES[_size.get_item_text(_size.selected)]
	var out: String = await GnMovie.render(list, size, self, movie_name,
		func(f, total): _status.text = "Rendering frame %d of %d…" % [f, total])
	_render_button.disabled = false
	_last = out
	_status.text = "Saved %s" % out if out.ends_with(".mp4") \
		else ("Frames saved in %s (ffmpeg wasn't found to make a video)." % out if out != "" else "Nothing to render.")


static func _clock(hours: float) -> String:
	return "%02d:%02d" % [int(hours), int(round(fmod(hours, 1.0) * 60.0)) % 60]


func _save_lapse() -> void:
	if GnScene.root() == null:
		return
	GnMovie.set_timelapse(_lapse_from.value, _lapse_to.value, _lapse.button_pressed)


func _add_mover() -> void:
	if GnScene.root() == null:
		return
	var m := Mover.new()
	m.name = "Moving objects"
	m.position = GnPlacement.drop_point()
	GnScene.add_node(m, GnScene.root(), "Genesis: add a moving-objects path", "mover")
	GnScene.select(m)


# Moves the selected objects onto the most recently selected path, or the
# only one there is.
func _ride() -> void:
	var picked := EditorInterface.get_selection().get_selected_nodes()
	var movers: Array = GnScene.root().get_tree().get_nodes_in_group(Mover.GROUP) if GnScene.root() else []
	var path: Node = null
	for n in picked:
		if n.get_script() == Mover:
			path = n
	if path == null and movers.size() == 1:
		path = movers[0]
	if path == null:
		_status.text = "Select the path too (or have just one)."
		return
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Genesis: put on the path", UndoRedo.MERGE_DISABLE, GnScene.root())
	for n in picked:
		if n == path or not n is Node3D:
			continue
		ur.add_do_method(n.get_parent(), "remove_child", n)
		ur.add_do_method(path, "add_child", n, true)
		ur.add_do_property(n, "owner", GnScene.root())
		ur.add_undo_method(path, "remove_child", n)
		ur.add_undo_method(n.get_parent(), "add_child", n, true)
		ur.add_undo_property(n, "owner", GnScene.root())
		ur.add_undo_property(n, "transform", n.transform)
	ur.add_do_method(path, "at_time", _time)
	ur.commit_action()
