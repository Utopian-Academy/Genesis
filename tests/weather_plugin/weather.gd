@tool
extends EditorPlugin

# Weather, seasons and clouds on one scene, one render each, for a person to
# compare; plus checks that the settings reach what they drive.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnWeather := preload("res://addons/genesis/core/gn_weather.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const GnScatter := preload("res://addons/genesis/core/gn_scatter.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const A := "res://genesis_assets"

var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(400.0).timeout.connect(func(): print("GN_WX FAIL watchdog"); get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var root := Node3D.new()
	root.name = "Weather"
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://scenes/weather_test.tscn")
	root.free()
	EditorInterface.open_scene_from_path("res://scenes/weather_test.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	GnEnvironment.apply("time_of_day", 15.0)
	GnPlacement.place(A + "/architecture/demo_house.glb", "architecture", Vector3.ZERO)
	var tree := A + ("/trees/beech.tscn" if ResourceLoader.exists(A + "/trees/beech.tscn") else "/trees/tree_round.glb")
	for p in [Vector3(-14, 0, -8), Vector3(12, 0, -9), Vector3(16, 0, 6)]:
		GnPlacement.place(tree, "trees", p)
	var cam := GnCameras.save_view()
	cam.position = Vector3(15, 3.5, 21)
	cam.look_at(Vector3(-1, 3, 0))
	var host := get_editor_interface().get_base_control()
	var shots := [
		["clear", {"kind": "Clear", "wet": 0.0, "season": "Summer"}, 0.3],
		["rain", {"kind": "Rain", "amount": 0.8, "wet": 0.9, "puddles": 0.8, "season": "Summer"}, 0.9],
		["snow", {"kind": "Snow", "amount": 0.8, "wet": 0.0, "season": "Winter"}, 0.8],
		["autumn", {"kind": "Clear", "wet": 0.0, "season": "Autumn"}, 0.45],
		["winter", {"kind": "Clear", "wet": 0.0, "season": "Winter"}, 0.2],
	]
	for s in shots:
		for k in s[1]:
			GnWeather.set_value(k, s[1][k])
		GnEnvironment.apply("cloudiness", s[2])
		await _frames(10)
		var out: String = await GnRender.render(cam, Vector2i(960, 540), host)
		DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/wx_%s.png" % s[0]))
		_check("%s rendered" % s[0], out != "", "")
		if s[0] == "rain":
			var pd := GnWeather.node().find_child("Puddles", false, false)
			_check("puddles lie on the ground in the rain (%d)" % (pd.get_child_count() if pd else 0),
				pd != null and pd.get_child_count() > 20 and pd.get_child(0) is Decal, "")
			GnWeather.set_value("puddles", 0.0)
	var n := GnWeather.node()
	_check("weather node saved its state", n != null and n.get_meta(GnWeather.META, {}).get("season") == "Winter", "")
	print("GN_WX RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_WX %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
