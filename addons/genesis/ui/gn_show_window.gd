@tool
extends Window

# The show view: the scene through the running cue's camera, in a window of
# its own that can go full screen on a second display, for clicking through
# a show with a client or a crew. Space or Enter is GO, Backspace goes back
# a cue, F toggles full screen, Esc closes.

const ShotPreview := preload("res://addons/genesis/ui/gn_shot_preview.gd")

var cue_list: Node

var _preview: Control
var _caption: Label
var _last_camera: Camera3D


func _init() -> void:
	title = "Genesis show"
	size = Vector2i(1280, 720)
	wrap_controls = false
	transient = false
	exclusive = false
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_preview = ShotPreview.new()
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_preview)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -44
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 20)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	add_child(_caption)
	close_requested.connect(queue_free)


func _process(_delta: float) -> void:
	if not is_instance_valid(cue_list):
		queue_free()
		return
	var i: int = cue_list.current
	var cam: Camera3D = cue_list.camera_of(i)
	if cam == null:
		cam = _last_camera if is_instance_valid(_last_camera) else _first_camera()
	_last_camera = cam
	_preview.camera = cam
	var cues: Array = cue_list.cues
	var now := "%d  %s" % [i + 1, cues[i].get("name", "")] if i >= 0 and i < cues.size() else "Standing by"
	var next := "   ·   next: %s" % cues[i + 1].get("name", "") if i + 1 < cues.size() else "   ·   end of the list"
	_caption.text = "%s%s      (Space: GO   Backspace: back   F: full screen)" % [now, next]


func _first_camera() -> Camera3D:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	for c in root.find_children("*", "Camera3D", true, false):
		return c
	return null


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_PAGEDOWN, KEY_RIGHT:
			cue_list.go()
		KEY_BACKSPACE, KEY_PAGEUP, KEY_LEFT:
			cue_list.back()
		KEY_F:
			mode = Window.MODE_WINDOWED if mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		KEY_ESCAPE:
			if mode == Window.MODE_FULLSCREEN:
				mode = Window.MODE_WINDOWED
			else:
				queue_free()
		_:
			return
	set_input_as_handled()
