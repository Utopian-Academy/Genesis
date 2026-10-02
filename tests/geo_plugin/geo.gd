@tool
extends EditorPlugin

# The real ground under a site, end to end against the live services:
# Lombard Street, San Francisco, the famous crooked block on Russian Hill.
# Its terrain must rise and fall as the hill does, the aerial photograph must
# be the sharp USGS one, the buildings must stand on the slope, and a view
# down the hill must render. Needs the internet.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnSite := preload("res://addons/genesis/core/gn_site.gd")
const GnGeo := preload("res://addons/genesis/core/gn_geo.gd")

var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(500.0).timeout.connect(func():
		print("GN_GEO FAIL watchdog")
		get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var r0 := Node3D.new()
	r0.name = "RussianHill"
	var packed := PackedScene.new()
	packed.pack(r0)
	ResourceSaver.save(packed, "res://scenes/russian_hill.tscn")
	r0.free()
	EditorInterface.open_scene_from_path("res://scenes/russian_hill.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	GnEnvironment.apply("sky", "Clear")
	var host := get_editor_interface().get_base_control()

	var counts: Dictionary = await GnSite.bring_in("Lombard Street, San Francisco", 250.0, host,
		func(m): print("GN_GEO status: ", m), true, true)
	print("GN_GEO result: ", counts)
	_check("found the place", not counts.has("error"), str(counts.get("error", "")))
	if counts.has("error"):
		_finish()
		return
	_check("buildings arrived", counts.buildings > 30, str(counts.buildings))
	_check("Russian Hill is a hill (%.0f m of relief)" % counts.get("relief_m", 0.0), counts.get("hilly", false)
		and counts.relief_m > 20.0 and counts.relief_m < 200.0, str(counts))
	_check("with the aerial photograph", counts.get("photo", false), str(counts.get("notes", [])))
	var site := GnScene.find_role("site")
	var attribution := str(site.get_meta(&"gn_site", {}).get("attribution", "")) if site else ""
	print("GN_GEO attribution: ", attribution)
	_check("credited: OpenStreetMap, the elevation and the USGS photograph", attribution.contains("OpenStreetMap")
		and attribution.contains("Terrain Tiles") and attribution.contains("USGS"), attribution)
	var ground := GnScene.find_role("terrain") as Node3D
	_check("the ground is a terrain the landscape tools can work on", ground != null and ground.get_script() != null, "")
	if ground == null:
		_finish()
		return
	# Buildings stand on the slope: on the ground under their lowest corner.
	var seated := 0
	var high := 0
	for b in site.find_child("Buildings", false, false).get_children():
		var at := (b as Node3D).position
		if absf(at.y) > 3.0:
			high += 1
		# Its base is at the ground under its lowest footprint corner.
		var low := INF
		for v in (b as MeshInstance3D).mesh.get_faces():
			if absf(v.y) < 0.001:
				low = minf(low, GnSite._ground(ground, v.x, v.z))
		if at.y <= low + 0.05:
			seated += 1
	print("GN_GEO %d of %d buildings off the centre's level, %d not floating" % [high, site.find_child("Buildings", false, false).get_child_count(), seated])
	_check("buildings follow the hill (%d stand more than 3 m up or down)" % high, high > 10, "")
	_check("and none float above the ground", seated == site.find_child("Buildings", false, false).get_child_count(), "")

	# Views: from the air, and down the hill.
	await _frames(10)
	var cam := GnCameras.save_view()
	cam.name = "Aerial"
	cam.position = Vector3(-260, 90, 160)
	cam.look_at(Vector3(0, 0, 0))
	cam.fov = 45
	var aerial: String = await GnRender.render(cam, Vector2i(1600, 900), host)
	_check("the aerial view renders", aerial != "", "")
	if aerial != "":
		DirAccess.copy_absolute(ProjectSettings.globalize_path(aerial), ProjectSettings.globalize_path("res://renders/geo_aerial.png"))
		# The photograph is on the ground: the view is not the flat grey of no imagery.
		var img := Image.load_from_file(ProjectSettings.globalize_path(aerial))
		var spread := 0.0
		var mean := Color(0, 0, 0)
		var n := 0
		for y in range(500, 900, 20):
			for x in range(0, 1600, 20):
				mean += img.get_pixel(x, y)
				n += 1
		mean /= n
		for y in range(500, 900, 20):
			for x in range(0, 1600, 20):
				var c := img.get_pixel(x, y)
				spread += absf(c.r - mean.r) + absf(c.g - mean.g) + absf(c.b - mean.b)
		spread /= n
		_check("the ground shows the photograph's detail (variation %.3f)" % spread, spread > 0.08, "")
	var street := GnCameras.save_view()
	street.name = "Down the hill"
	# Lombard Street runs east-west through the site's centre: stand on it,
	# up the hill to the west, and look down it.
	var eye := Vector3(-70, 0, 0)
	street.position = Vector3(eye.x, GnSite._ground(ground, eye.x, eye.z) + 1.7, eye.z)
	var look := Vector3(60, 0, 0)
	street.look_at(Vector3(look.x, GnSite._ground(ground, look.x, look.z) + 1.0, look.z))
	street.fov = 60
	var down: String = await GnRender.render(street, Vector2i(1600, 900), host)
	_check("the street view renders", down != "", "")
	if down != "":
		DirAccess.copy_absolute(ProjectSettings.globalize_path(down), ProjectSettings.globalize_path("res://renders/geo_street.png"))
	_finish()


func _finish() -> void:
	EditorInterface.save_scene()
	print("GN_GEO RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_GEO %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
