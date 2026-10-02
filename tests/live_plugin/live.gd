@tool
extends EditorPlugin

# Live video and show cues, end to end: a video file playing on an LED wall;
# a real SRT stream (sent by a second FFmpeg, as Deckboy's Stream output
# would) arriving on another; two walls sharing one source; cues that fade
# lights, a screen and the time of day; a cue's GO reaching a TCP listener
# that answers like Deckboy; OSC encoding; the show view following the
# cue's camera.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnFfmpeg := preload("res://addons/genesis/core/gn_ffmpeg.gd")
const GnLiveVideo := preload("res://addons/genesis/core/gn_live_video.gd")
const LedWall := preload("res://addons/genesis/set/gn_led_wall.gd")
const Fixture := preload("res://addons/genesis/set/gn_light_fixture.gd")
const CueList := preload("res://addons/genesis/set/gn_cue_list.gd")
const ShowWindow := preload("res://addons/genesis/ui/gn_show_window.gd")

const SRT_PORT := 9731
const FAKE_DECKBOY_PORT := 5599

var _ok := true
var _sender := -1
var _windows: Array = []  # stand-in program windows, closed at the end


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(400.0).timeout.connect(func(): print("GN_LIVE FAIL watchdog"); _finish())
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var r0 := Node3D.new()
	r0.name = "Live"
	var packed := PackedScene.new()
	packed.pack(r0)
	ResourceSaver.save(packed, "res://scenes/live_test.tscn")
	r0.free()
	EditorInterface.open_scene_from_path("res://scenes/live_test.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	GnEnvironment.apply("time_of_day", 21.0)
	var root := GnScene.root()
	var host := get_editor_interface().get_base_control()
	var ffmpeg := GnFfmpeg.find()
	var f0 := Engine.get_process_frames()
	var t0 := Time.get_ticks_msec()
	await _seconds(2.0)
	print("GN_LIVE editor frame rate before any video: %.1f per second (low processor %s)" % [
		(Engine.get_process_frames() - f0) * 1000.0 / (Time.get_ticks_msec() - t0), OS.low_processor_usage_mode])
	_check("FFmpeg is found (%s)" % ffmpeg, ffmpeg != "", "")
	if ffmpeg == "":
		_finish()
		return

	# 1. A video file as a wall's content.
	var video := OS.get_user_data_dir().path_join("bars.mp4")
	OS.execute(ffmpeg, PackedStringArray(["-y", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
		"testsrc2=size=640x360:rate=30", "-t", "4", "-pix_fmt", "yuv420p", video]))
	_check("a test video is made", FileAccess.file_exists(video), video)
	var film := LedWall.new()
	film.name = "Film wall"
	film.columns = 8
	film.rows = 5
	film.content = video
	film.position = Vector3(-5, 0, 0)
	GnScene.add_node(film, root, "wall", "led_wall")
	var spec := "file:%s" % video
	_check("a video as content plays as a live source", film.live_spec() == spec, film.live_spec())
	var info := await _wait_live(spec, 15.0)
	print("GN_LIVE file: %s" % info)
	_check("the video plays on the wall (%s)" % info.get("status", "?"), info.get("status", "") == "live" and info.get("frames", 0) > 5, str(info))

	# 2. SRT, sent by another program, as Deckboy's Stream output sends it.
	var live := LedWall.new()
	live.name = "Live wall"
	live.columns = 8
	live.rows = 5
	live.position = Vector3(5, 0, 0)
	live.live_source = "srt:%d" % SRT_PORT
	GnScene.add_node(live, root, "wall", "led_wall")
	await _frames(10)
	var waiting: Dictionary = GnLiveVideo.info("srt:%d" % SRT_PORT)
	print("GN_LIVE before the sender: %s" % waiting)
	_check("an SRT wall waits, saying where to send", str(waiting.get("status", "")).contains("srt://"), str(waiting))
	_sender = OS.create_process(ffmpeg, PackedStringArray(["-hide_banner", "-loglevel", "error", "-re", "-f", "lavfi", "-i",
		"testsrc2=size=1280x720:rate=30", "-t", "60", "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
		"-g", "30", "-f", "mpegts", "srt://127.0.0.1:%d?mode=caller" % SRT_PORT]))
	var srt := await _wait_live("srt:%d" % SRT_PORT, 20.0)
	# Over 3 seconds: frames delivered (should keep up with the 30 fps
	# sender) and frames shown (one per editor redraw, however fast this
	# machine's editor draws).
	var read0: int = srt.get("read", 0)
	var shown0: int = srt.get("frames", 0)
	var draws0 := Engine.get_frames_drawn()
	var s0 := Time.get_ticks_msec()
	await _seconds(3.0)
	srt = GnLiveVideo.info("srt:%d" % SRT_PORT)
	var secs := (Time.get_ticks_msec() - s0) / 1000.0
	var delivered: float = (int(srt.get("read", 0)) - read0) / secs
	var shown: int = int(srt.get("frames", 0)) - shown0
	var draws := Engine.get_frames_drawn() - draws0
	print("GN_LIVE srt: %s; delivered %.1f fps, shown %d frames in %d editor redraws" % [srt, delivered, shown, draws])
	_check("the SRT stream arrives (%s)" % srt.get("status", "?"), srt.get("status", "") == "live", str(srt))
	_check("it is received at the sender's rate (%.1f of 30 fps)" % delivered, delivered >= 24.0, str(srt))
	_check("and every editor redraw shows a new frame (%d of %d)" % [shown, draws], shown >= draws - 2 and shown > 0, "")
	# The picture on the wall is the stream, not the bars slate.
	var tex: Texture2D = live._live_texture
	var img := tex.get_image() if tex else null
	_check("and the wall shows it, not the waiting slate", img != null and not _same(img, GnLiveVideo.slate()), "")
	# A second wall on the same source shares it.
	var twin := LedWall.new()
	twin.name = "Twin wall"
	twin.live_source = "srt:%d" % SRT_PORT
	twin.position = Vector3(5, 0, 8)
	GnScene.add_node(twin, root, "wall", "led_wall")
	await _frames(5)
	_check("two walls on one source share one receiver (%d users)" % GnLiveVideo.info("srt:%d" % SRT_PORT).get("users", 0),
		GnLiveVideo.info("srt:%d" % SRT_PORT).get("users", 0) == 2 and GnLiveVideo.sources().size() == 2, str(GnLiveVideo.sources()))

	# 2b. A program's window, as a playback app's output is taken in: a
	# teal window (its title has a colon, as show names do), then a magenta
	# one opened right over it. The wall must show the teal one's own
	# picture, not whatever covers it on screen.
	var ffplay := GnFfmpeg.find("ffplay")
	if OS.get_name() == "Windows" and ffplay != "" and GnFfmpeg.has_filter("gfxcapture"):
		var title := "GN window test: teal"
		_windows.append(OS.create_process(ffplay, PackedStringArray(["-hide_banner", "-loglevel", "error", "-an", "-f", "lavfi",
			"-i", "color=c=0x20c080:s=480x270:r=30", "-window_title", title, "-left", "80", "-top", "80", "-noborder"])))
		await _seconds(1.5)
		_windows.append(OS.create_process(ffplay, PackedStringArray(["-hide_banner", "-loglevel", "error", "-an", "-f", "lavfi",
			"-i", "color=c=0xd020c0:s=480x270:r=30", "-window_title", "GN window test cover", "-left", "80", "-top", "80", "-noborder"])))
		await _seconds(1.5)
		var shown_wall := LedWall.new()
		shown_wall.name = "Window wall"
		shown_wall.live_source = "window:%s" % title
		shown_wall.position = Vector3(0, 0, -8)
		GnScene.add_node(shown_wall, root, "wall", "led_wall")
		var win_info := await _wait_live("window:%s" % title, 15.0)
		print("GN_LIVE window: %s" % win_info)
		_check("a program's window plays on a wall (%s)" % win_info.get("status", "?"), win_info.get("status", "") == "live", str(win_info))
		var wtex: Texture2D = shown_wall._live_texture
		var wimg := wtex.get_image() if wtex else null
		var mid := wimg.get_pixel(wimg.get_width() / 2, wimg.get_height() / 2) if wimg else Color.BLACK
		print("GN_LIVE window centre %s" % mid)
		_check("it shows that window even with another over it (%s)" % mid.to_html(false),
			mid.g > 0.55 and mid.r < 0.3 and mid.b < 0.6, str(mid))
		for pid in _windows:
			OS.kill(pid)
		_windows.clear()
		shown_wall.queue_free()
	else:
		print("GN_LIVE window capture skipped: needs Windows, ffplay and FFmpeg's gfxcapture")

	# 3. Cues.
	var f := Fixture.new()
	f.name = "Beam"
	f.position = Vector3(0, 6, 4)
	GnScene.add_node(f, root, "beam", "fixture")
	var cam_a := GnCameras.save_view()
	cam_a.name = "Wide"
	cam_a.position = Vector3(0, 4, 18)
	cam_a.look_at(Vector3(0, 2, 0))
	var cam_b := GnCameras.save_view()
	cam_b.name = "Close"
	cam_b.position = Vector3(5, 2, 8)
	cam_b.look_at(Vector3(5, 2, 0))
	var cl := CueList.new()
	cl.name = "Show cues"
	GnScene.add_node(cl, root, "cues", "cues")
	# Cue 1: red at full, 21:00, no haze.
	f.colour = Color(1, 0, 0)
	f.dimmer = 1.0
	f.pan = 0.0
	live.brightness = 1.0
	GnEnvironment.apply("haze", 0.0, false)
	cl.record(root, "Walk-in", 0.0, str(root.get_path_to(cam_a)), {})
	# Cue 2: blue at 20%, panned, the wall down, haze in, over 1 s, telling "Deckboy" to GO.
	f.colour = Color(0, 0, 1)
	f.dimmer = 0.2
	f.pan = 90.0
	live.brightness = 0.25
	GnEnvironment.apply("haze", 0.8, false)
	cl.record(root, "Headliner", 1.0, str(root.get_path_to(cam_b)),
		{"on": true, "target": "Deckboy (TCP)", "host": "127.0.0.1", "port": FAKE_DECKBOY_PORT, "message": "GO"})
	_check("two cues recorded, with the light, both walls and the environment",
		cl.cues.size() == 2 and (cl.cues[0].state as Dictionary).size() >= 4 and cl.cues[0].env.has("haze"), str(cl.cues[0].state.keys()))
	cl.go_to(0)
	await _frames(2)
	_check("cue 1 puts it all back: red, full, pan 0, wall up, no haze", f.colour.is_equal_approx(Color(1, 0, 0)) and is_equal_approx(f.dimmer, 1.0)
		and is_equal_approx(f.pan, 0.0) and is_equal_approx(live.brightness, 1.0) and is_equal_approx(float(GnEnvironment.value("haze")), 0.0), "")
	# A listener that answers like Deckboy.
	var server := TCPServer.new()
	var heard := []
	server.listen(FAKE_DECKBOY_PORT, "127.0.0.1")
	var answers := []
	cl.sent.connect(func(r): answers.append(r))
	cl.go()
	var peer: StreamPeerTCP = null
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and heard.is_empty():
		if peer == null and server.is_connection_available():
			peer = server.take_connection()
		if peer:
			peer.poll()
			if peer.get_available_bytes() > 0:
				heard.append(peer.get_utf8_string(peer.get_available_bytes()).strip_edges())
				peer.put_data("OK GO\n".to_utf8_buffer())
		await get_tree().process_frame
	await _seconds(0.45)
	var mid := f.dimmer
	print("GN_LIVE half way: dimmer %.2f, pan %.0f, wall %.2f" % [f.dimmer, f.pan, live.brightness])
	_check("GO fades: half way the level is between (%.2f)" % mid, mid < 0.95 and mid > 0.25, "")
	await _seconds(1.0)
	_check("and lands on cue 2: blue at 20%%, pan 90, wall at 25%%", f.colour.is_equal_approx(Color(0, 0, 1)) and absf(f.dimmer - 0.2) < 0.01
		and absf(f.pan - 90.0) < 0.1 and absf(live.brightness - 0.25) < 0.01, "%s %.2f %.1f %.2f" % [f.colour, f.dimmer, f.pan, live.brightness])
	_check("with the haze in (%.2f)" % float(GnEnvironment.value("haze")), absf(float(GnEnvironment.value("haze")) - 0.8) < 0.01, "")
	_check("the cue sent GO to the show software", heard == ["GO"], str(heard))
	await _seconds(0.5)
	_check("and reports its answer (%s)" % str(answers), answers.size() == 1 and str(answers[0]).contains("OK GO"), str(answers))
	server.stop()
	cl.back()
	await _frames(2)
	_check("Back returns to cue 1 at once", cl.current == 0 and is_equal_approx(f.dimmer, 1.0), "")
	var osc: PackedByteArray = CueList.osc_packet("/go 1 2.5 hi")
	var expect := PackedByteArray([47, 103, 111, 0, 44, 105, 102, 115, 0, 0, 0, 0, 0, 0, 0, 1, 64, 32, 0, 0, 104, 105, 0, 0])
	_check("OSC messages are encoded to the spec", osc == expect, str(osc))

	# 4. The show view follows the cue's camera.
	var win := ShowWindow.new()
	win.cue_list = cl
	host.add_child(win)
	win.popup_centered(Vector2i(960, 540))
	cl.go_to(1, 0.0)
	await _frames(5)
	_check("the show view watches from the cue's camera", win._preview.camera == cam_b, str(win._preview.camera))
	win.queue_free()

	# 5. How it looks: the stream on the wall, at night.
	var out: String = await GnRender.render(cam_a, Vector2i(1280, 720), host)
	_check("it renders", out != "", "")
	if out != "":
		DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/live_walls.png"))
	# Letting go stops the receiver (after its short grace).
	for w in [live, twin, film]:
		w.get_parent().remove_child(w)
		w.free()
	await _seconds(3.5)
	_check("with no screen left, the receivers stop", GnLiveVideo.sources().is_empty(), str(GnLiveVideo.sources()))
	_finish()


func _wait_live(spec: String, seconds: float) -> Dictionary:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		var i := GnLiveVideo.info(spec)
		if i.get("status", "") == "live" and i.get("frames", 0) > 5:
			return i
		await get_tree().process_frame
	return GnLiveVideo.info(spec)


func _same(a: Image, b: Image) -> bool:
	for p in [Vector2i(100, 100), Vector2i(640, 200), Vector2i(1100, 600)]:
		if not a.get_pixelv(p).is_equal_approx(b.get_pixelv(p)):
			return false
	return true


func _finish() -> void:
	if _sender > 0:
		OS.kill(_sender)
	for pid in _windows:
		OS.kill(pid)
	GnLiveVideo.stop_all()
	print("GN_LIVE RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_LIVE %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
