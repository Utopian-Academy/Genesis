@tool
extends EditorPlugin

# Site context end to end, against the live OpenStreetMap services: 49a Mall
# Road, Hammersmith (James's test address), 300 m around, with the real sun
# for London on 21 June at 16:00 BST. Needs the internet.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnSite := preload("res://addons/genesis/core/gn_site.gd")
const GnSun := preload("res://addons/genesis/core/gn_sun.gd")

var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(400.0).timeout.connect(func():
		print("GN_SITE FAIL watchdog")
		get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var root := Node3D.new()
	root.name = "MallRoad"
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://scenes/mall_road.tscn")
	root.free()
	EditorInterface.open_scene_from_path("res://scenes/mall_road.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	GnEnvironment.apply("sky", "Photo: clear" if "Photo: clear" in GnEnvironment.sky_choices() else "Clear")

	var counts: Dictionary = await GnSite.bring_in("49a Mall Road, London", 300.0, get_editor_interface().get_base_control(),
		func(m): print("GN_SITE status: ", m), true, false)
	print("GN_SITE result: ", counts)
	_check("found the place", not counts.has("error"), str(counts.get("error", "")))
	if counts.has("error"):
		_finish()
		return
	_check("buildings arrived", counts.buildings > 50, str(counts.buildings))
	_check("roads arrived", counts.roads > 20, str(counts.roads))
	_check("the Thames arrived", counts.water > 0, str(counts.water))

	# London, 21 June, 16:00 BST: the sun should be west-south-west, about 43 degrees up.
	GnEnvironment.apply("sky", "Clear")
	GnEnvironment.apply("utc_offset", 1.0)
	GnEnvironment.apply("day_of_year", GnSun.day_of_year(6, 21))
	GnEnvironment.apply("time_of_day", 16.0)
	var expect := GnSun.position(GnEnvironment.value("latitude"), GnEnvironment.value("longitude"), 172, 16.0, 1.0)
	var to_sun := -(-GnEnvironment.sun().global_transform.basis.z)
	var el := rad_to_deg(asin(to_sun.y))
	var az := fposmod(rad_to_deg(atan2(to_sun.x, -to_sun.z)), 360.0)
	print("GN_SITE sun: az %.1f el %.1f (expected az %.1f el %.1f)" % [az, el, expect.azimuth, expect.elevation])
	_check("sun where the solar calculation puts it", absf(az - expect.azimuth) < 1.0 and absf(el - expect.elevation) < 1.0, "")

	await _frames(10)
	var cam := GnCameras.save_view()
	cam.position = Vector3(-120, 140, 170)
	cam.look_at(Vector3(0, 0, 0))
	cam.fov = 40
	var aerial: String = await GnRender.render(cam, Vector2i(1600, 900), get_editor_interface().get_base_control())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(aerial), ProjectSettings.globalize_path("res://renders/site_aerial.png"))
	var street := GnCameras.save_view()
	street.position = Vector3(18, 1.7, 22)
	street.look_at(Vector3(0, 4, 0))
	street.fov = 60
	var ground: String = await GnRender.render(street, Vector2i(1600, 900), get_editor_interface().get_base_control())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(ground), ProjectSettings.globalize_path("res://renders/site_street.png"))
	_check("site rendered", aerial != "" and ground != "", "")
	_finish()


func _finish() -> void:
	# Kept: the runner copies it into the project as a demo scene to open.
	EditorInterface.save_scene()
	print("GN_SITE RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_SITE %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
