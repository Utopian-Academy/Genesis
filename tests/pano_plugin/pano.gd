@tool
extends EditorPlugin

# 360 stitching, checked with six coloured blocks, one in each direction
# around the camera: each must land where an equirectangular image puts it.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnPanorama := preload("res://addons/genesis/core/gn_panorama.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnTour := preload("res://addons/genesis/core/gn_tour.gd")

var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): print("GN_PANO FAIL watchdog"); get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var root := Node3D.new()
	root.name = "Pano"
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://scenes/pano_test.tscn")
	root.free()
	EditorInterface.open_scene_from_path("res://scenes/pano_test.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	GnEnvironment.apply("time_of_day", 12.0)
	var scene := GnScene.root()
	var eye := Vector3(0, 20, 0)
	var markers := {
		"-Z (ahead)": [Vector3.FORWARD, Color(1, 0, 0), Vector2(0.5, 0.5)],
		"+X (right)": [Vector3.RIGHT, Color(0, 1, 0), Vector2(0.75, 0.5)],
		"-X (left)": [Vector3.LEFT, Color(0, 0, 1), Vector2(0.25, 0.5)],
		"+Z (behind)": [Vector3.BACK, Color(1, 1, 0), Vector2(0.02, 0.5)],
		"+Y (up)": [Vector3.UP, Color(1, 0, 1), Vector2(0.5, 0.03)],
		"-Y (down)": [Vector3.DOWN, Color(0, 1, 1), Vector2(0.5, 0.97)],
	}
	for k in markers:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4, 4, 4)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = markers[k][1]
		bm.material = m
		box.mesh = bm
		GnScene.add_node(box, scene, "marker")
		box.position = eye + (markers[k][0] as Vector3) * 8.0
	var cam := GnCameras.save_view()
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), eye)
	var out: String = await GnPanorama.render(cam, 2048, get_editor_interface().get_base_control())
	_check("panorama rendered", out != "", out)
	var img := Image.load_from_file(ProjectSettings.globalize_path(out))
	_check("2:1 equirectangular", img.get_width() == 2 * img.get_height(), str(img.get_size()))
	for k in markers:
		var uv: Vector2 = markers[k][2]
		var c := img.get_pixel(int(uv.x * (img.get_width() - 1)), int(uv.y * (img.get_height() - 1)))
		# Tone mapping shifts saturated colours, so ask which marker the
		# pixel is nearest to, not whether it matches exactly.
		var nearest := ""
		var best := INF
		for other in markers:
			var w: Color = markers[other][1]
			# Hue survives tone mapping far better than raw RGB does.
			var dh := absf(c.h - w.h)
			var d := minf(dh, 1.0 - dh)
			if d < best:
				best = d
				nearest = other
		_check("%s lands in place" % k, nearest == k, "got %s, nearest %s" % [c, nearest])
	DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/pano_test.png"))

	# Stereo: both eyes, left above right, each with the markers in place,
	# and different from each other by the parallax of a near object.
	var near := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.3, 0.3, 0.3)
	near.mesh = nb
	GnScene.add_node(near, scene, "near marker")
	near.position = eye + Vector3(0.5, 0, -1.2)
	var sout: String = await GnPanorama.render_stereo(cam, 1024, get_editor_interface().get_base_control())
	_check("stereo panorama rendered", sout != "", sout)
	if sout != "":
		var s := Image.load_from_file(ProjectSettings.globalize_path(sout))
		_check("top-bottom, square", s.get_width() == s.get_height(), str(s.get_size()))
		var half := s.get_height() / 2
		for k in markers:
			var uv: Vector2 = markers[k][2]
			if absf(uv.y - 0.5) > 0.2:
				continue  # the poles are shared by both eyes
			for e in 2:
				var c := s.get_pixel(int(uv.x * (s.get_width() - 1)), e * half + int(uv.y * (half - 1)))
				var w: Color = markers[k][1]
				var dh := absf(c.h - w.h)
				_check("%s in place for the %s eye" % [k, "left" if e == 0 else "right"], minf(dh, 1.0 - dh) < 0.08, str(c))
		var diff := 0.0
		var n := 0
		for y in range(half / 4, half * 3 / 4, 4):
			for x in range(0, s.get_width(), 4):
				var a := s.get_pixel(x, y)
				var b := s.get_pixel(x, y + half)
				diff += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				n += 1
		diff /= n
		print("GN_PANO eyes differ by %.4f" % diff)
		_check("the eyes see from different places (%.4f)" % diff, diff > 0.001 and diff < 0.2, "")
		DirAccess.copy_absolute(ProjectSettings.globalize_path(sout), ProjectSettings.globalize_path("res://renders/pano_stereo.png"))

	# A virtual tour: a second camera 3 m to the right (+X), then one web
	# page with both views and rings pointing each to the other.
	var cam2 := GnCameras.save_view()
	cam2.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), eye + Vector3(3, 0, 0))
	var tour_path: String = await GnTour.export_tour([cam, cam2], "Pano test", false, 1024, get_editor_interface().get_base_control())
	_check("the tour is written", tour_path != "" and FileAccess.file_exists(tour_path), tour_path)
	if tour_path != "":
		var html := FileAccess.get_file_as_string(tour_path)
		var start := html.find("const TOUR = ") + "const TOUR = ".length()
		var tour = JSON.parse_string(html.substr(start, html.find("\n", start) - start).strip_edges().trim_suffix(";"))
		_check("it holds both views", tour is Dictionary and tour.stops.size() == 2, "")
		if tour is Dictionary and tour.stops.size() == 2:
			var s0: Array = tour.stops[0].spots
			var s1: Array = tour.stops[1].spots
			_check("the first view's ring is to its right", s0.size() == 1 and absf(s0[0].lon - PI / 2) < 0.01 and absf(s0[0].lat) < 0.01, str(s0))
			_check("the second view's ring is to its left", s1.size() == 1 and absf(s1[0].lon + PI / 2) < 0.01, str(s1))
			var raw := Marshalls.base64_to_raw(str(tour.stops[1].image).trim_prefix("data:image/jpeg;base64,"))
			var pic := Image.new()
			_check("its pictures are 360s", pic.load_jpg_from_buffer(raw) == OK and pic.get_size() == Vector2i(1024, 512), str(pic.get_size()))
		DirAccess.copy_absolute(ProjectSettings.globalize_path(tour_path), ProjectSettings.globalize_path("res://renders/pano_tour.html"))
	print("GN_PANO RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_PANO %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
