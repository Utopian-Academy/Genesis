@tool
extends RefCounted

# Finding FFmpeg, which Genesis uses to encode movies and to take live
# video into screens. It is free, but not bundled: its licence and size are
# better served by the user's own copy. Looked for on the PATH, then where
# the usual installers put it.

const URL := "https://ffmpeg.org/download.html"


## The ffmpeg program, or "" if there is none.
static func find(program := "ffmpeg") -> String:
	var sep := ";" if OS.get_name() == "Windows" else ":"
	var exe := ".exe" if OS.get_name() == "Windows" else ""
	var dirs: Array = Array(OS.get_environment("PATH").split(sep, false))
	match OS.get_name():
		"Windows":
			dirs.append_array(["C:/ffmpeg/bin", OS.get_environment("ProgramFiles").path_join("ffmpeg/bin"),
				OS.get_environment("LOCALAPPDATA").path_join("Microsoft/WinGet/Links"),
				OS.get_environment("USERPROFILE").path_join("scoop/shims")])
		"macOS":
			dirs.append_array(["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"])
		_:
			dirs.append_array(["/usr/bin", "/usr/local/bin", "/snap/bin"])
	for d in dirs:
		var p: String = str(d).path_join(program + exe)
		if FileAccess.file_exists(p):
			return p
	return ""


## Whether the FFmpeg found here has a filter (asked once per name).
static func has_filter(name: String) -> bool:
	if not _filters.has(name):
		var out: Array = []
		var ffmpeg := find()
		if ffmpeg != "":
			OS.execute(ffmpeg, PackedStringArray(["-hide_banner", "-filters"]), out, true)
		_filters[name] = " %s " % name in "\n".join(out).replace("\t", " ")
	return _filters[name]


static var _filters := {}


static func missing_text() -> String:
	return "This needs FFmpeg, which is free: %s. Install it and restart Godot." % URL
