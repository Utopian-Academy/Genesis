@tool
extends VBoxContainer

# Show: run the event before it happens. Live video puts a playback app's
# output (Deckboy, or anything that streams, or a window, a capture card, a
# video file) on the LED walls as it plays; cues record each look of the
# running order and GO clicks through them, telling the playback to go too.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnLiveVideo := preload("res://addons/genesis/core/gn_live_video.gd")
const GnFfmpeg := preload("res://addons/genesis/core/gn_ffmpeg.gd")
const CueList := preload("res://addons/genesis/set/gn_cue_list.gd")
const ShowWindow := preload("res://addons/genesis/ui/gn_show_window.gd")

# What the source menu offers, and the kind of source each one makes.
const SOURCES := [
	["Deckboy, or any SRT sender", "srt"],
	["RTMP sender", "rtmp"],
	["UDP (MPEG-TS)", "udp"],
	["A window on this computer", "window"],
	["A whole display", "screen"],
	["Capture card or camera", "device"],
	["Video file", "file"],
	["Network address (URL)", "url"],
	["Nothing live (the wall's own content)", ""],
]

var _screens: ItemList
var _source: OptionButton
var _port: SpinBox
var _pick: OptionButton
var _url: LineEdit
var _file_row: HBoxContainer
var _file_label: Label
var _file: String = ""
var _file_dialog: EditorFileDialog
var _live_status: Label
var _help: Label

var _cues: ItemList
var _name: LineEdit
var _fade: SpinBox
var _camera: OptionButton
var _send_on: CheckBox
var _target: OptionButton
var _host: LineEdit
var _send_port: SpinBox
var _message: LineEdit
var _status: Label
var _window: Window
var _timer: Timer


func _init() -> void:
	name = "Show"
	GnUi.note(self, "Run the event before it happens: real content on the screens, and a click-through of the cues.")

	GnUi.heading(self, "Live video on the screens")
	GnUi.note(self, "Pick screens (LED walls and flying screens), choose what feeds them, and show it.")
	_screens = ItemList.new()
	_screens.select_mode = ItemList.SELECT_MULTI
	_screens.custom_minimum_size = Vector2(0, 90)
	_screens.auto_height = true
	add_child(_screens)
	_source = GnUi.option(self, "Source", SOURCES.map(func(s): return s[0]), _source_changed)
	_port = _spin_row("Port", 1, 65535, 1, GnLiveVideo.DEFAULT_SRT_PORT)
	var pick_row := HBoxContainer.new()
	_pick = OptionButton.new()
	_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick.clip_text = true
	pick_row.add_child(_pick)
	GnUi.button(pick_row, "Refresh", _fill_pick)
	add_child(pick_row)
	_url = LineEdit.new()
	_url.placeholder_text = "srt://host:port, rtsp://…, http://…"
	add_child(_url)
	_file_row = HBoxContainer.new()
	_file_label = Label.new()
	_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_label.clip_text = true
	_file_label.text = "No file chosen"
	_file_row.add_child(_file_label)
	GnUi.button(_file_row, "Choose…", _choose_file)
	add_child(_file_row)
	GnUi.button(self, "Show it on the chosen screens", _apply_source)
	_help = GnUi.note(self, "")
	_live_status = GnUi.note(self, "")

	GnUi.heading(self, "Cues")
	GnUi.note(self, "Set the look (lights, screens, effects, time, haze), then Record. GO fades to the next cue.")
	_cues = ItemList.new()
	_cues.custom_minimum_size = Vector2(0, 120)
	_cues.item_selected.connect(_cue_selected)
	add_child(_cues)
	_name = _line_row("Name", "Walk-in")
	_fade = _spin_row("Fade (s)", 0.0, 600.0, 0.1, 3.0)
	_camera = GnUi.option(self, "Watch from", [], func(_t): pass)
	_send_on = CheckBox.new()
	_send_on.text = "Also send a command"
	add_child(_send_on)
	_target = GnUi.option(self, "To", CueList.TARGETS, _target_changed)
	_host = _line_row("Host", "127.0.0.1")
	_send_port = _spin_row("Port", 1, 65535, 1, CueList.DECKBOY_PORT)
	_message = _line_row("Command", "GO")
	var rec := HBoxContainer.new()
	GnUi.button(rec, "Record new cue", _record)
	GnUi.button(rec, "Re-record", _rerecord)
	GnUi.button(rec, "Delete", _delete)
	add_child(rec)
	var order := HBoxContainer.new()
	GnUi.button(order, "Move up", _move.bind(-1))
	GnUi.button(order, "Move down", _move.bind(1))
	GnUi.button(order, "Test the command", _test_send)
	add_child(order)
	var run := HBoxContainer.new()
	var go := GnUi.button(run, "GO", _go)
	go.custom_minimum_size = Vector2(90, 40)
	go.add_theme_font_size_override("font_size", 20)
	GnUi.button(run, "Back", _back)
	GnUi.button(run, "Go to selected", _go_selected)
	add_child(run)
	GnUi.button(self, "Open the show view (full screen with F)", _open_window)
	_status = GnUi.note(self, "")

	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_update_live_status)
	add_child(_timer)
	_source_changed(SOURCES[0][0])


func refresh() -> void:
	var root := GnScene.root()
	# Screens.
	var picked := _picked_screens().map(func(n): return n.get_path())
	_screens.clear()
	for n in CueList.show_objects(root):
		if CueList.kind_of(n) != "screen":
			continue
		var src: String = n.get("live_source")
		var i := _screens.add_item("%s%s" % [n.name, ("   [%s]" % src) if src != "" else ""])
		_screens.set_item_metadata(i, n.get_path())
		if n.get_path() in picked or (picked.is_empty() and EditorInterface.get_selection().get_selected_nodes().has(n)):
			_screens.select(i, false)
	# Cameras.
	var chosen := _camera.get_item_text(_camera.selected) if _camera.selected >= 0 else ""
	_camera.clear()
	_camera.add_item("(keep the last)")
	for c in GnCameras.cameras():
		_camera.add_item(c.name)
		_camera.set_item_metadata(_camera.item_count - 1, str(root.get_path_to(c)) if root else "")
	GnUi.select_text(_camera, chosen)
	_fill_cues()
	_update_live_status()


func _cue_list(create := false) -> Node:
	var root := GnScene.root()
	if root == null:
		return null
	for n in root.find_children("*", "Node", true, false):
		if n.get_script() == CueList:
			return n
	if not create:
		return null
	var cl := CueList.new()
	cl.name = "Show cues"
	GnScene.add_node(cl, root, "Genesis: add cue list", "cues")
	if not cl.went.is_connected(_went):
		cl.went.connect(_went)
		cl.sent.connect(_sent)
	return cl


func _hooked(cl: Node) -> Node:
	if cl and not cl.went.is_connected(_went):
		cl.went.connect(_went)
		cl.sent.connect(_sent)
	return cl


# --- live video ------------------------------------------------------------------

func _picked_screens() -> Array:
	var out: Array = []
	var root := GnScene.root()
	if root == null or _screens == null:
		return out
	for i in _screens.get_selected_items():
		var n := root.get_tree().root.get_node_or_null(_screens.get_item_metadata(i))
		if n:
			out.append(n)
	return out


func _kind() -> String:
	return SOURCES[_source.selected][1] if _source.selected >= 0 else ""


func _source_changed(_text: String) -> void:
	var k := _kind()
	_port.get_parent().visible = k in ["srt", "rtmp", "udp"]
	_pick.get_parent().visible = k in ["window", "screen", "device"]
	_url.visible = k == "url"
	_file_row.visible = k == "file"
	if k == "srt" and _port.value in [1935.0, 5000.0]:
		_port.value = GnLiveVideo.DEFAULT_SRT_PORT
	elif k == "rtmp":
		_port.value = 1935
	elif k == "udp":
		_port.value = 5000
	if k in ["window", "screen", "device"]:
		_fill_pick()
	var ip := GnLiveVideo.local_address()
	match k:
		"srt":
			_help.text = ("In Deckboy: Settings → Video Outputs, add a Stream output to srt://%s:%d (or srt://127.0.0.1:%d on this computer). "
				+ "OBS, vMix and hardware encoders send SRT the same way.") % [ip, int(_port.value), int(_port.value)]
		"rtmp":
			_help.text = "Send RTMP to rtmp://%s:%d/live/show." % [ip, int(_port.value)]
		"window":
			_help.text = "Pick the playback's output window. It is captured as it is on screen, so keep it uncovered." \
				if OS.get_name() == "Windows" else "One window can be captured on Windows; here, capture the display it is on."
		"screen":
			_help.text = "A whole display, for instance the one a playback app puts its output on."
		"device":
			_help.text = "A capture card (SDI or HDMI in) or a camera."
		"file":
			_help.text = "A video file, looping. A wall can also take a video as its own Content."
		_:
			_help.text = ""
	if GnFfmpeg.find() == "" and k != "":
		_help.text = GnFfmpeg.missing_text()


func _fill_pick() -> void:
	_pick.clear()
	match _kind():
		"window":
			for t in GnLiveVideo.windows():
				_pick.add_item(t)
		"screen":
			for i in DisplayServer.get_screen_count():
				var s := DisplayServer.screen_get_size(i)
				_pick.add_item("Display %d (%d × %d)" % [i + 1, s.x, s.y])
				_pick.set_item_metadata(i, str(i))
		"device":
			for d in GnLiveVideo.devices():
				_pick.add_item(d)
	if _pick.item_count == 0:
		_pick.add_item("(none found)")
		_pick.disabled = true
	else:
		_pick.disabled = false


func _choose_file() -> void:
	if _file_dialog == null:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.title = "Choose a video"
		_file_dialog.add_filter("*.mp4, *.mov, *.m4v, *.webm, *.mkv, *.avi, *.mxf", "Video")
		_file_dialog.file_selected.connect(func(p): _file = p; _file_label.text = p.get_file())
		add_child(_file_dialog)
	_file_dialog.popup_file_dialog()


## The source text for what the controls say, or "" for none.
func source_spec() -> String:
	var k := _kind()
	match k:
		"srt", "rtmp", "udp":
			return "%s:%d" % [k, int(_port.value)]
		"window", "device":
			return "%s:%s" % [k, _pick.get_item_text(_pick.selected)] if not _pick.disabled and _pick.selected >= 0 else ""
		"screen":
			return "screen:%s" % _pick.get_item_metadata(_pick.selected) if not _pick.disabled and _pick.selected >= 0 else ""
		"file":
			return "file:%s" % _file if _file != "" else ""
		"url":
			return "url:%s" % _url.text.strip_edges() if _url.text.strip_edges() != "" else ""
	return ""


func _apply_source() -> void:
	var screens := _picked_screens()
	if screens.is_empty():
		_status.text = "Pick one or more screens in the list first."
		return
	var spec := source_spec()
	if spec == "" and _kind() != "":
		_status.text = "Choose what to show first."
		return
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Genesis: live video", UndoRedo.MERGE_DISABLE, GnScene.root())
	for n in screens:
		ur.add_do_property(n, "live_source", spec)
		ur.add_undo_property(n, "live_source", n.get("live_source"))
	ur.commit_action()
	_status.text = ("%d screen%s now show %s." % [screens.size(), "" if screens.size() == 1 else "s", spec]) if spec != "" \
		else "Back to the walls' own content."
	refresh()


func _update_live_status() -> void:
	if not is_visible_in_tree():
		return
	var lines: Array = []
	for spec in GnLiveVideo.sources():
		var info := GnLiveVideo.info(spec)
		if info.is_empty():
			continue
		var s: String = info.status
		lines.append("%s: %s" % [spec, ("live, %.0f fps" % info.fps) if s == "live" else s])
	_live_status.text = "\n".join(lines)


# --- cues ------------------------------------------------------------------------

func _fill_cues() -> void:
	var cl := _hooked(_cue_list())
	var keep := _cues.get_selected_items()
	_cues.clear()
	if cl == null:
		return
	for i in cl.cues.size():
		var c: Dictionary = cl.cues[i]
		var send: Dictionary = c.get("send", {})
		_cues.add_item("%s%d   %s   (%.1f s)%s" % ["▶ " if i == cl.current else "   ", i + 1, c.get("name", ""), float(c.get("fade", 0.0)),
			("   → %s" % send.get("message", "")) if send.get("on", false) else ""])
	if not keep.is_empty() and keep[0] < _cues.item_count:
		_cues.select(keep[0])


func _selected_cue() -> int:
	var s := _cues.get_selected_items()
	return s[0] if not s.is_empty() else -1


func _cue_selected(i: int) -> void:
	var cl := _cue_list()
	if cl == null or i >= cl.cues.size():
		return
	var c: Dictionary = cl.cues[i]
	_name.text = str(c.get("name", ""))
	_fade.value = float(c.get("fade", 0.0))
	var cam := str(c.get("camera", ""))
	_camera.select(0)
	for k in _camera.item_count:
		if str(_camera.get_item_metadata(k)) == cam and cam != "":
			_camera.select(k)
	var send: Dictionary = c.get("send", {})
	_send_on.button_pressed = send.get("on", false)
	GnUi.select_text(_target, str(send.get("target", CueList.TARGETS[0])))
	_host.text = str(send.get("host", "127.0.0.1"))
	_send_port.value = int(send.get("port", CueList.DECKBOY_PORT))
	_message.text = str(send.get("message", "GO"))


func _send_fields() -> Dictionary:
	return {"on": _send_on.button_pressed, "target": _target.get_item_text(_target.selected), "host": _host.text.strip_edges(),
		"port": int(_send_port.value), "message": _message.text.strip_edges()}


func _camera_field() -> String:
	return str(_camera.get_item_metadata(_camera.selected)) if _camera.selected > 0 else ""


func _target_changed(t: String) -> void:
	if t == "Deckboy (TCP)":
		_send_port.value = CueList.DECKBOY_PORT
		if _message.text == "":
			_message.text = "GO"
	elif t == "OSC (UDP)" and not _message.text.begins_with("/"):
		_message.text = "/go"


# Cue edits go through undo, as a whole new list.
func _commit(cl: Node, cues: Array, action: String) -> void:
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action(action, UndoRedo.MERGE_DISABLE, GnScene.root())
	ur.add_do_property(cl, "cues", cues)
	ur.add_undo_property(cl, "cues", cl.cues.duplicate(true))
	ur.add_do_method(self, "_fill_cues")
	ur.add_undo_method(self, "_fill_cues")
	ur.commit_action()


func _record() -> void:
	var root := GnScene.root()
	if root == null:
		_status.text = "Open or make a scene first."
		return
	var cl := _cue_list(true)
	var snap: Dictionary = cl.snapshot(root)
	var cue := {"name": _name.text.strip_edges() if _name.text.strip_edges() != "" else "Cue %d" % (cl.cues.size() + 1),
		"fade": _fade.value, "camera": _camera_field(), "send": _send_fields(), "state": snap.state, "env": snap.env}
	var cues: Array = cl.cues.duplicate(true)
	# After the selected cue, or at the end.
	var at := _selected_cue()
	var idx := at + 1 if at >= 0 else cues.size()
	cues.insert(idx, cue)
	_commit(cl, cues, "Genesis: record cue")
	_cues.select(idx)
	_status.text = "Recorded cue %d: %s. %d objects in it." % [idx + 1, cues[idx].name, (cues[idx].state as Dictionary).size()]
	_name.text = "Cue %d" % (cues.size() + 1)


func _rerecord() -> void:
	var cl := _cue_list()
	var i := _selected_cue()
	if cl == null or i < 0:
		_status.text = "Select a cue to re-record."
		return
	var cues: Array = cl.cues.duplicate(true)
	var snap: Dictionary = cl.snapshot(GnScene.root())
	cues[i].state = snap.state
	cues[i].env = snap.env
	cues[i].name = _name.text.strip_edges()
	cues[i].fade = _fade.value
	cues[i].camera = _camera_field()
	cues[i].send = _send_fields()
	_commit(cl, cues, "Genesis: re-record cue")
	_status.text = "Cue %d re-recorded." % (i + 1)


func _delete() -> void:
	var cl := _cue_list()
	var i := _selected_cue()
	if cl == null or i < 0:
		return
	var cues: Array = cl.cues.duplicate(true)
	cues.remove_at(i)
	_commit(cl, cues, "Genesis: delete cue")


func _move(by: int) -> void:
	var cl := _cue_list()
	var i := _selected_cue()
	if cl == null or i < 0 or i + by < 0 or i + by >= cl.cues.size():
		return
	var cues: Array = cl.cues.duplicate(true)
	var c = cues[i]
	cues.remove_at(i)
	cues.insert(i + by, c)
	_commit(cl, cues, "Genesis: move cue")
	_cues.select(i + by)


func _go() -> void:
	var cl := _hooked(_cue_list())
	if cl == null or cl.cues.is_empty():
		_status.text = "Record some cues first."
		return
	cl.go()


func _back() -> void:
	var cl := _hooked(_cue_list())
	if cl:
		cl.back()


func _go_selected() -> void:
	var cl := _hooked(_cue_list())
	if cl and _selected_cue() >= 0:
		cl.go_to(_selected_cue())


func _went(i: int) -> void:
	var cl := _cue_list()
	_fill_cues()
	if cl and i < cl.cues.size():
		_status.text = "Cue %d: %s" % [i + 1, cl.cues[i].get("name", "")]


func _sent(result: String) -> void:
	_status.text += "\n" + result


func _test_send() -> void:
	var cl := _hooked(_cue_list(true))
	var fields := _send_fields()
	fields.on = true
	_status.text = "Sending \"%s\"…" % fields.message
	cl._send(fields)


func _open_window() -> void:
	var cl := _hooked(_cue_list())
	if cl == null:
		_status.text = "Record some cues first."
		return
	if is_instance_valid(_window):
		_window.grab_focus()
		return
	_window = ShowWindow.new()
	_window.cue_list = cl
	EditorInterface.get_base_control().add_child(_window)
	_window.popup_centered(Vector2i(1280, 720))


func _spin_row(text: String, lo: float, hi: float, step: float, value: float) -> SpinBox:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	row.add_child(s)
	add_child(row)
	return s


func _line_row(text: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(150, 0)
	row.add_child(e)
	add_child(row)
	return e
