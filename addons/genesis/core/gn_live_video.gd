@tool
extends RefCounted

# Live video into the scene's screens: whatever a show's media server,
# playback app or camera puts out, shown on the LED walls as it plays, so a
# show can be clicked through with its real content.
#
# A source is a short text, saved on the screen that shows it:
#   srt:9710            listen for an SRT stream on that port. Deckboy's
#                       Stream output (and OBS, vMix, a hardware encoder)
#                       sends to srt://<this computer>:9710
#   rtmp:1935           listen for RTMP: rtmp://<this computer>:1935/live/show
#   udp:5000            listen for MPEG-TS over UDP
#   window:<title>      a window on this computer (Windows): a playback
#                       app's output window, for instance
#   screen:<n>          a whole display on this computer
#   device:<name>       a capture card or camera
#   file:<path>         a video file, looping
#   url:<address>       anything FFmpeg can open (srt:// as caller, http, rtsp)
#
# FFmpeg does the receiving and decoding; one copy runs per source, however
# many screens show it, and hands over raw frames through a pipe, read on a
# thread so the editor never waits for the network.

const GnFfmpeg := preload("res://addons/genesis/core/gn_ffmpeg.gd")

## Every source is scaled to this for the screens (a preview, not a
## processor: 720p keeps the pipe and the upload light).
const SIZE := Vector2i(1280, 720)
const FPS := 30
const KINDS := ["srt", "rtmp", "udp", "window", "screen", "device", "file", "url"]
const DEFAULT_SRT_PORT := 9710


class Source:
	extends RefCounted
	var spec := ""
	# Worked out by the registry: FFmpeg's arguments ([] if it can't be done
	# here), and what to say while waiting or when it can't.
	var args: Array = []
	var waiting := ""
	var unsupported := ""
	var texture: ImageTexture
	var users := 0
	var status := "starting"
	var frames := 0
	# Frames FFmpeg delivered (more than shown if the editor draws slower).
	var read_frames := 0
	var fps := 0.0
	var pid := -1
	var running := false
	var restart_at := 0
	# When the last screen let go; the source is kept a moment in case one
	# takes it straight back (a screen rebuilding), so a sender stays connected.
	var idle_since := 0
	var _stdio: FileAccess
	var _stderr: FileAccess
	var _reader: Thread
	var _errors: Thread
	var _mutex := Mutex.new()
	var _latest := PackedByteArray()
	var _fresh := false
	var _count_since := 0
	var _counted := 0
	var _last_error := ""

	func start() -> void:
		var ffmpeg := GnFfmpeg.find()
		if ffmpeg == "":
			status = GnFfmpeg.missing_text()
			return
		if args.is_empty():
			status = unsupported
			return
		var p := OS.execute_with_pipe(ffmpeg, PackedStringArray(args))
		if p.is_empty():
			status = "FFmpeg didn't start."
			return
		_stdio = p.stdio
		_stderr = p.stderr
		pid = p.pid
		running = true
		status = waiting
		_reader = Thread.new()
		_reader.start(_read)
		_errors = Thread.new()
		_errors.start(_read_errors)

	func stop() -> void:
		running = false
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
		pid = -1
		for t in [_reader, _errors]:
			if t and t.is_started():
				t.wait_to_finish()
		_reader = null
		_errors = null

	func _read() -> void:
		var need := SIZE.x * SIZE.y * 3
		var buf := PackedByteArray()
		while running:
			# A pipe hands over what it has, a few kilobytes at a time: gather
			# pieces until the frame is complete. (Asking for a whole frame at
			# once makes every small read allocate the whole frame.)
			var piece := _stdio.get_buffer(mini(need - buf.size(), 65536))
			if piece.is_empty():
				if _stdio.eof_reached() or not OS.is_process_running(pid):
					break
				OS.delay_msec(2)
				continue
			buf.append_array(piece)
			if buf.size() < need:
				continue
			_mutex.lock()
			_latest = buf
			_fresh = true
			read_frames += 1
			_mutex.unlock()
			buf = PackedByteArray()

	# FFmpeg's complaints, drained so its pipe never fills and stalls it;
	# the last one is shown if the picture never arrives.
	func _read_errors() -> void:
		while running:
			var line := _stderr.get_line()
			if line == "" and _stderr.eof_reached():
				break
			if line.strip_edges() != "":
				_mutex.lock()
				_last_error = line.strip_edges()
				_mutex.unlock()

	# On the main thread: puts the newest frame on the texture.
	func tick(now: int) -> void:
		var frame := PackedByteArray()
		_mutex.lock()
		if _fresh:
			frame = _latest
			_fresh = false
		var err := _last_error
		_mutex.unlock()
		if not frame.is_empty():
			texture.update(Image.create_from_data(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8, frame))
			frames += 1
			_counted += 1
			status = "live"
		if now - _count_since >= 1000:
			fps = _counted * 1000.0 / maxf(now - _count_since, 1)
			_counted = 0
			_count_since = now
		# FFmpeg ended (the sender stopped, a file failed): listen again.
		if running and pid > 0 and not OS.is_process_running(pid):
			stop()
			status = ("Stopped: %s" % err) if err != "" else "The source stopped; listening again."
			restart_at = now + 2000
		if not running and restart_at > 0 and now >= restart_at and users > 0:
			restart_at = 0
			start()


# Frames reach the textures from a node in the running tree.
class Ticker:
	extends Node
	var host: Script
	func _process(_delta: float) -> void:
		host.tick()


static var _sources := {}
static var _ticker: Node
static var _slate: Image
# The editor saves power by drawing only when something changes, a few
# times a second when idle; live video needs it drawing every frame. The
# user's own setting comes back when the last source stops.
static var _saved_low_processor := -1


## The texture showing this source. Every call must be matched by release().
static func acquire(spec: String) -> ImageTexture:
	spec = spec.strip_edges()
	if not _sources.has(spec):
		var s := Source.new()
		s.spec = spec
		s.args = ffmpeg_args(spec)
		s.waiting = waiting_text(spec)
		s.unsupported = unsupported_text(spec)
		s.texture = ImageTexture.create_from_image(slate())
		_sources[spec] = s
		s.start()
	var src: Source = _sources[spec]
	src.users += 1
	_ensure_ticker()
	return src.texture


static func release(spec: String) -> void:
	spec = spec.strip_edges()
	if not _sources.has(spec):
		return
	var src: Source = _sources[spec]
	src.users -= 1
	if src.users <= 0:
		src.users = 0
		src.idle_since = Time.get_ticks_msec()


## Stops everything (the plugin going away).
static func stop_all() -> void:
	for spec in _sources:
		(_sources[spec] as Source).stop()
	_sources.clear()
	_keep_drawing(false)
	if is_instance_valid(_ticker):
		_ticker.queue_free()
	_ticker = null


## {"status", "fps", "frames", "users"} for a source, or {} if none runs.
static func info(spec: String) -> Dictionary:
	var src: Source = _sources.get(spec.strip_edges())
	if src == null:
		return {}
	return {"status": src.status, "fps": src.fps, "frames": src.frames, "read": src.read_frames, "users": src.users}


static func sources() -> Array:
	return _sources.keys()


const LINGER_MS := 3000


static func tick() -> void:
	var now := Time.get_ticks_msec()
	for spec in _sources.keys():
		var src: Source = _sources[spec]
		if src.users <= 0 and now - src.idle_since > LINGER_MS:
			src.stop()
			_sources.erase(spec)
			continue
		src.tick(now)
	_keep_drawing(not _sources.is_empty())


static func _keep_drawing(on: bool) -> void:
	if on and _saved_low_processor < 0:
		_saved_low_processor = 1 if OS.low_processor_usage_mode else 0
		OS.low_processor_usage_mode = false
	elif not on and _saved_low_processor >= 0:
		OS.low_processor_usage_mode = _saved_low_processor == 1
		_saved_low_processor = -1


static func _ensure_ticker() -> void:
	if is_instance_valid(_ticker):
		return
	_ticker = Ticker.new()
	_ticker.host = load("res://addons/genesis/core/gn_live_video.gd")
	_ticker.name = "GenesisLiveVideo"
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_ticker)


## What a screen shows before its picture arrives: colour bars.
static func slate() -> Image:
	if _slate == null:
		_slate = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
		var bars := [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0),
			Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
		var w := SIZE.x / bars.size()
		for i in bars.size():
			_slate.fill_rect(Rect2i(i * w, 0, w + 1, int(SIZE.y * 0.67)), bars[i])
		_slate.fill_rect(Rect2i(0, int(SIZE.y * 0.67), SIZE.x, SIZE.y), Color(0.05, 0.05, 0.08))
		for i in 4:
			_slate.fill_rect(Rect2i(int(SIZE.x * (0.1 + i * 0.2)), int(SIZE.y * 0.75), int(SIZE.x * 0.12), int(SIZE.y * 0.15)),
				Color(0.2 * i, 0.2 * i, 0.2 * i).lerp(Color.WHITE, 0.15))
	return _slate


## FFmpeg's arguments for a source, or [] if it can't be done here.
static func ffmpeg_args(spec: String) -> Array:
	var kind := spec.get_slice(":", 0).to_lower()
	var value := spec.substr(kind.length() + 1) if spec.contains(":") else ""
	var os := OS.get_name()
	var input: Array = []
	var net := ["-fflags", "nobuffer", "-flags", "low_delay", "-probesize", "500000", "-analyzeduration", "500000"]
	match kind:
		"srt":
			input = net + ["-i", "srt://0.0.0.0:%d?mode=listener&latency=120000" % int(value if value != "" else str(DEFAULT_SRT_PORT))]
		"rtmp":
			input = net + ["-listen", "1", "-i", "rtmp://0.0.0.0:%d/live/show" % int(value if value != "" else "1935")]
		"udp":
			input = net + ["-i", "udp://0.0.0.0:%d?fifo_size=1000000&overrun_nonfatal=1" % int(value if value != "" else "5000")]
		"url":
			input = net + ["-i", value]
		"file":
			var path := ProjectSettings.globalize_path(value)
			if not FileAccess.file_exists(path):
				return []
			input = ["-stream_loop", "-1", "-re", "-i", path]
		"window":
			if os != "Windows":
				return []
			# Windows Graphics Capture reads the window's own picture, so
			# it keeps working when other windows cover it (a playback
			# app's output under the editor, say); the older grab copies
			# whatever is on screen there.
			if GnFfmpeg.has_filter("gfxcapture"):
				input = ["-f", "lavfi", "-i", "gfxcapture=window_title=%s:capture_cursor=0:max_framerate=%d,hwdownload,format=bgra" % [
					title_pattern(value), FPS]]
			else:
				input = ["-f", "gdigrab", "-framerate", str(FPS), "-draw_mouse", "0", "-i", "title=%s" % value]
		"screen":
			var n := clampi(int(value), 0, DisplayServer.get_screen_count() - 1)
			var at := DisplayServer.screen_get_position(n)
			var size := DisplayServer.screen_get_size(n)
			match os:
				"Windows":
					input = ["-f", "gdigrab", "-framerate", str(FPS), "-draw_mouse", "0", "-offset_x", str(at.x), "-offset_y", str(at.y),
						"-video_size", "%dx%d" % [size.x, size.y], "-i", "desktop"]
				"macOS":
					input = ["-f", "avfoundation", "-framerate", str(FPS), "-capture_cursor", "0", "-i", "Capture screen %d:none" % n]
				_:
					var display := OS.get_environment("DISPLAY") if OS.get_environment("DISPLAY") != "" else ":0"
					input = ["-f", "x11grab", "-framerate", str(FPS), "-draw_mouse", "0", "-video_size", "%dx%d" % [size.x, size.y],
						"-i", "%s+%d,%d" % [display, at.x, at.y]]
		"device":
			match os:
				"Windows":
					input = ["-f", "dshow", "-rtbufsize", "100M", "-i", "video=%s" % value]
				"macOS":
					input = ["-f", "avfoundation", "-framerate", str(FPS), "-i", "%s:none" % value]
				_:
					input = ["-f", "v4l2", "-i", value]
		_:
			return []
	return ["-hide_banner", "-loglevel", "error", "-nostdin"] + input + ["-an",
		"-vf", "scale=%d:%d:flags=bilinear,fps=%d" % [SIZE.x, SIZE.y, FPS],
		"-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"]


## The whole title as a pattern FFmpeg can take without any escaping:
## letters, digits and spaces as themselves, anything else as "any one
## character", anchored at both ends.
static func title_pattern(title: String) -> String:
	var out := "^"
	for ch in title:
		var c := ch.unicode_at(0)
		var plain := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 32
		out += ch if plain else "."
	return out + "$"


static func unsupported_text(spec: String) -> String:
	var kind := spec.get_slice(":", 0).to_lower()
	if kind == "window":
		return "Capturing one window works on Windows; here, capture its screen instead (screen:<n>)."
	if kind == "file":
		return "The video file isn't there: %s" % spec.substr(5)
	return "Not a source Genesis knows: \"%s\"." % spec


static func waiting_text(spec: String) -> String:
	var kind := spec.get_slice(":", 0).to_lower()
	var port := spec.get_slice(":", 1)
	match kind:
		"srt":
			return "Waiting for SRT on port %s: send to srt://%s:%s" % [port, local_address(), port]
		"rtmp":
			return "Waiting for RTMP: send to rtmp://%s:%s/live/show" % [local_address(), port]
		"udp":
			return "Waiting for UDP on port %s" % port
	return "Starting…"


## This computer's address on the local network, for the sender to use.
static func local_address() -> String:
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254."):
			return a
	return "127.0.0.1"


## Titled windows on this computer (Windows only; [] elsewhere).
static func windows() -> Array:
	if OS.get_name() != "Windows":
		return []
	var out: Array = []
	OS.execute("tasklist", PackedStringArray(["/v", "/fo", "csv", "/nh"]), out, false)
	var titles: Array = []
	for line in "\n".join(out).split("\n", false):
		var cols := line.strip_edges().trim_prefix("\"").trim_suffix("\"").split("\",\"")
		if cols.size() >= 9:
			var t := cols[cols.size() - 1]
			if t != "N/A" and t != "" and not titles.has(t):
				titles.append(t)
	titles.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	return titles


## Capture cards and cameras FFmpeg can see.
static func devices() -> Array:
	var ffmpeg := GnFfmpeg.find()
	var out: Array = []
	var names: Array = []
	match OS.get_name():
		"Windows":
			if ffmpeg != "":
				OS.execute(ffmpeg, PackedStringArray(["-hide_banner", "-list_devices", "true", "-f", "dshow", "-i", "dummy"]), out, true)
				for line in "\n".join(out).split("\n", false):
					if line.contains("(video)"):
						var q0 := line.find("\"")
						var q1 := line.find("\"", q0 + 1)
						if q0 >= 0 and q1 > q0:
							names.append(line.substr(q0 + 1, q1 - q0 - 1))
		"macOS":
			if ffmpeg != "":
				OS.execute(ffmpeg, PackedStringArray(["-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""]), out, true)
				var video := false
				for line in "\n".join(out).split("\n", false):
					if line.contains("video devices"):
						video = true
					elif line.contains("audio devices"):
						video = false
					elif video and line.contains("] ["):
						var name := line.substr(line.find("] [") + 3)
						name = name.substr(name.find("] ") + 2)
						if not name.begins_with("Capture screen"):
							names.append(name)
		_:
			for f in DirAccess.get_files_at("/dev"):
				if f.begins_with("video"):
					names.append("/dev/" + f)
	return names
