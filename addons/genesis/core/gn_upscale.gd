@tool
extends RefCounted

# AI upscaling of a finished render with Real-ESRGAN (BSD-3-Clause, by
# Xintao Wang et al.), the open image upscaler, run as its own small
# program on the GPU. It is not bundled: the first upscale downloads the
# build for this computer from the project's GitHub release (about 45 MB),
# checks it against the fingerprint below, and keeps it in the project.
#
# It sharpens edges and fine texture well; like every AI upscaler it can
# invent detail in very fine repeating patterns and smooth away hairlines.

const DIR := "res://genesis_data/external/realesrgan"
const VERSION := "v0.2.5.0"
const LICENSE_URL := "https://raw.githubusercontent.com/xinntao/Real-ESRGAN/master/LICENSE"
const MODEL := "realesrgan-x4plus"
## The largest picture Godot can hold, and so the largest upscale.
const MAX_SIDE := 16384

const BUILDS := {
	"Windows": ["realesrgan-ncnn-vulkan-20220424-windows.zip",
		"abc02804e17982a3be33675e4d471e91ea374e65b70167abc09e31acb412802d", 45474481],
	"macOS": ["realesrgan-ncnn-vulkan-20220424-macos.zip",
		"e0ad05580abfeb25f8d8fb55aaf7bedf552c375b5b4d9bd3c8d59764d2cc333a", 51817124],
	"Linux": ["realesrgan-ncnn-vulkan-20220424-ubuntu.zip",
		"e5aa6eb131234b87c0c51f82b89390f5e3e642b7b70f2b9bbe95b6a285a40c96", 46931474],
}


static func available() -> bool:
	return BUILDS.has(_os())


static func installed() -> bool:
	return FileAccess.file_exists(exe()) and FileAccess.file_exists("%s/models/%s.bin" % [_dir(), MODEL])


static func exe() -> String:
	return _dir().path_join("realesrgan-ncnn-vulkan" + (".exe" if _os() == "Windows" else ""))


## How big the first-time download is, for the button to say.
static func download_mb() -> int:
	return roundi(float(BUILDS.get(_os(), ["", "", 0])[2]) / 1e6)


## Downloads, checks and unpacks the upscaler. Returns "" or what went wrong.
## `progress` is called with (bytes so far, total bytes).
static func install(host: Node, progress := Callable()) -> String:
	if not available():
		return "There's no Real-ESRGAN build for this system."
	var build: Array = BUILDS[_os()]
	DirAccess.make_dir_recursive_absolute(_dir())
	# Keep Godot from importing the models and sample pictures.
	FileAccess.open(_dir().path_join(".gdignore"), FileAccess.WRITE).close()
	var zip := _dir().path_join(build[0])
	var url := "https://github.com/xinntao/Real-ESRGAN/releases/download/%s/%s" % [VERSION, build[0]]
	var err := await _download(url, zip, host, progress, build[2])
	if err != "":
		return err
	if FileAccess.get_sha256(zip) != build[1]:
		DirAccess.remove_absolute(zip)
		return "The downloaded upscaler didn't match its fingerprint, so it wasn't used."
	var reader := ZIPReader.new()
	if reader.open(zip) != OK:
		return "The upscaler download couldn't be opened."
	for f in reader.get_files():
		# Only the program, its runtime libraries and the one model used.
		var name := f.get_file()
		var wanted := name.begins_with("realesrgan-ncnn-vulkan") or name.ends_with(".dll") or name.ends_with(".dylib") \
			or (f.begins_with("models/") and name.begins_with(MODEL + "."))
		if not wanted or f.ends_with("/"):
			continue
		var out := _dir().path_join(f)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var w := FileAccess.open(out, FileAccess.WRITE)
		w.store_buffer(reader.read_file(f))
		w.close()
	reader.close()
	DirAccess.remove_absolute(zip)
	if _os() != "Windows":
		OS.execute("chmod", PackedStringArray(["+x", ProjectSettings.globalize_path(exe())]))
	# Its licence travels with it.
	await _download(LICENSE_URL, _dir().path_join("LICENSE.txt"), host, Callable(), 0)
	return "" if installed() else "The upscaler was downloaded but isn't complete."


## Upscales a picture by 2 or 4 and saves it beside the original as
## name_x2.png or name_x4.png. Returns {"path": ..., "error": ...}.
static func upscale(path: String, factor: int, host: Node) -> Dictionary:
	var src := ProjectSettings.globalize_path(path)
	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		return {"path": "", "error": "There's no picture at %s." % path.get_file()}
	if maxi(img.get_width(), img.get_height()) * factor > MAX_SIDE:
		return {"path": "", "error": "×%d would be wider than %d pixels; render smaller, or choose ×2." % [factor, MAX_SIDE]}
	var out := src.get_basename() + "_x%d.png" % factor
	# The model always enlarges by 4; ×2 is that, brought down cleanly.
	var args := PackedStringArray(["-i", src, "-o", out, "-n", MODEL, "-s", "4", "-m", ProjectSettings.globalize_path(_dir().path_join("models"))])
	var pid := OS.create_process(ProjectSettings.globalize_path(exe()), args)
	if pid <= 0:
		return {"path": "", "error": "The upscaler wouldn't start."}
	while OS.is_process_running(pid):
		await host.get_tree().create_timer(0.25).timeout
	var big := Image.load_from_file(out)
	if big == null or big.is_empty():
		return {"path": "", "error": "The upscaler didn't produce a picture (it needs a Vulkan graphics driver)."}
	var size := img.get_size() * factor
	if big.get_size() != size:
		big.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		big.save_png(out)
	return {"path": ProjectSettings.localize_path(out) if out.begins_with(ProjectSettings.globalize_path("res://")) else out, "error": ""}


static func _download(url: String, to: String, host: Node, progress: Callable, expected: int) -> String:
	var http := HTTPRequest.new()
	http.download_file = ProjectSettings.globalize_path(to)
	http.use_threads = true
	host.add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return "The download couldn't start."
	var done: Array = []
	http.request_completed.connect(func(result, code, _h, _b): done.append([result, code]))
	while done.is_empty():
		if progress.is_valid():
			progress.call(http.get_downloaded_bytes(), expected if expected > 0 else http.get_body_size())
		await host.get_tree().create_timer(0.2).timeout
	http.queue_free()
	if done[0][0] != HTTPRequest.RESULT_SUCCESS or done[0][1] != 200:
		return "The download failed (%s). Check the internet connection and try again." % (
			("HTTP %d" % done[0][1]) if done[0][0] == HTTPRequest.RESULT_SUCCESS else "error %d" % done[0][0])
	return ""


static func _dir() -> String:
	return ProjectSettings.globalize_path(DIR)


static func _os() -> String:
	return "Linux" if OS.get_name() in ["Linux", "FreeBSD"] else OS.get_name()
