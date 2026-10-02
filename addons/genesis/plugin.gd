@tool
extends EditorPlugin

# Registration only, plus the one job only an EditorPlugin can do: receive
# mouse input from the 3D viewport and hand it to the scatter brush.

const GenesisDock := preload("res://addons/genesis/ui/gn_dock.gd")
const GnBrush := preload("res://addons/genesis/core/gn_brush.gd")
const GnWeather := preload("res://addons/genesis/core/gn_weather.gd")
const GnMeasure := preload("res://addons/genesis/core/gn_measure.gd")
const GnLiveVideo := preload("res://addons/genesis/core/gn_live_video.gd")
const GnLiveLink := preload("res://addons/genesis/core/gn_live_link.gd")

var _dock: EditorDock
var _brush: GnBrush
var _measure: GnMeasure


func _enter_tree() -> void:
	_brush = GnBrush.new()
	_brush.changed.connect(update_overlays)
	_measure = GnMeasure.new()
	_measure.changed.connect(update_overlays)
	_dock = GenesisDock.new()
	_dock.brush = _brush
	_dock.measure = _measure
	add_dock(_dock)
	scene_changed.connect(_on_scene_changed)
	# The live link looks for re-exported buildings every two seconds.
	var watch := Timer.new()
	watch.wait_time = 2.0
	watch.autostart = true
	watch.timeout.connect(func():
		if GnLiveLink.poll() > 0 and _dock:
			_dock.refresh())
	add_child(watch)


func _exit_tree() -> void:
	# Live video runs FFmpeg in the background: stop it with the plugin.
	GnLiveVideo.stop_all()
	# remove_dock only detaches it; the dock and everything under it must be
	# freed here or every disable/enable cycle leaks a full panel.
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _dock:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
	_brush = null
	_measure = null


# The editor only forwards viewport input to a plugin that handles the
# selected object. While the brush or the tape measure is on, that is any 3D
# node, so they work whatever happens to be selected.
func _handles(object: Object) -> bool:
	return object is Node3D and ((_brush != null and _brush.active) or (_measure != null and _measure.active))


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _measure and _measure.handle(camera, event):
		return AFTER_GUI_INPUT_STOP
	if _brush and _brush.handle(camera, event):
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if _measure and _measure.active:
		var line := _measure.preview(cam)
		if not line.is_empty():
			overlay.draw_line(line.from, line.to, Color(1.0, 0.85, 0.2), 2.0, true)
			overlay.draw_string(overlay.get_theme_default_font(), (line.from + line.to) * 0.5 + Vector2(8, -8),
				line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.85, 0.2))
	if _brush == null or not _brush.active:
		return
	var ring := _brush.outline(cam)
	if ring.size() > 1:
		overlay.draw_polyline(ring, Color(1, 1, 1, 0.85), 2.0, true)


func _on_scene_changed(root: Node) -> void:
	# Particles and seasonal leaf tints are not stored in the scene; put them
	# back whenever a scene is opened.
	if root:
		GnWeather.apply()
	_dock.refresh()
