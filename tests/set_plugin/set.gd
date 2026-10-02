@tool
extends EditorPlugin

# Event set pieces: a stage, a curved LED wall and a truss goalpost. The
# wall's production report is checked against numbers worked out by hand.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const LedWall := preload("res://addons/genesis/set/gn_led_wall.gd")
const Truss := preload("res://addons/genesis/set/gn_truss.gd")
const StageDeck := preload("res://addons/genesis/set/gn_stage_deck.gd")
const Fixture := preload("res://addons/genesis/set/gn_light_fixture.gd")

var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("GN_SET FAIL watchdog")
		get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var root := Node3D.new()
	root.name = "Stage"
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "res://scenes/set_test.tscn")
	root.free()
	EditorInterface.open_scene_from_path("res://scenes/set_test.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	GnEnvironment.apply("sky", "Photo: sunset" if "Photo: sunset" in GnEnvironment.sky_choices() else "Clear")
	GnEnvironment.apply("heading", 150.0)
	var scene := GnScene.root()

	var deck := StageDeck.new()
	deck.name = "Stage"
	deck.width = 12
	deck.depth = 6
	deck.height = 1.0
	GnScene.add_node(deck, scene, "stage", "stage")

	var wall := LedWall.new()
	wall.name = "LED wall"
	wall.panel = "2.6 mm indoor (500 × 500)"
	wall.columns = 16
	wall.rows = 8
	wall.curve_degrees = 20
	wall.bottom = 1.3
	GnScene.add_node(wall, scene, "wall", "led_wall")
	wall.position = Vector3(0, 0, -3.6)

	var r: Dictionary = wall.report()
	print("GN_SET report:\n" + wall.report_text())
	# 16 x 8 cabinets of 500 mm, 192 px each: 8 x 4 m, 3072 x 1536 px.
	_check("size 8 x 4 m", r.size_m.is_equal_approx(Vector2(8, 4)), str(r.size_m))
	_check("resolution 3072 x 1536", r.resolution == Vector2i(3072, 1536), str(r.resolution))
	_check("128 cabinets, 896 kg", r.cabinets == 128 and is_equal_approx(r.weight_kg, 896.0), "%d, %.0f" % [r.cabinets, r.weight_kg])
	_check("21.8 kW max", is_equal_approx(r.power_max_w, 21760.0), str(r.power_max_w))
	# 3072 * 1536 = 4,718,592 px / 655,360 per port = 7.2, so 8 ports.
	_check("8 data ports", r.data_ports == 8, str(r.data_ports))
	_check("2.6 mm pitch", absf(r.pitch_mm - 2.604) < 0.01, str(r.pitch_mm))
	var px: Image = wall.pixel_map()
	_check("pixel map at native aspect", absf(float(px.get_width()) / px.get_height() - 2.0) < 0.01, str(px.get_size()))

	var goal := Node3D.new()
	goal.name = "Goalpost"
	for x in [-7.0, 7.0]:
		var tower := Truss.new()
		tower.length = 7.0
		tower.rotation_degrees = Vector3(0, 0, 90)
		tower.position = Vector3(x, 0, 1.5)
		goal.add_child(tower)
	var span := Truss.new()
	span.length = 14.29
	span.position = Vector3(-7.145, 7.0, 1.5)
	goal.add_child(span)
	GnScene.add_node(goal, scene, "goalpost", "truss")

	# Six beams on the span, fanned out and crossing, in haze.
	for i in 6:
		var f := Fixture.new()
		f.kind = "Beam (moving head)"
		f.colour = [Color(0.3, 0.5, 1.0), Color(1.0, 0.35, 0.8)][i % 2]
		f.lumens = 17000
		f.beam_degrees = 6
		# Facing the audience, tipped down toward the front of the stage.
		f.pan = 180
		f.tilt = -55
		f.rotation_degrees = Vector3(0, 0, (i - 2.5) * 9.0)
		f.position = Vector3(-6.0 + i * 2.4, 6.6, 1.5)
		GnScene.add_node(f, scene, "beam", "light")
	GnEnvironment.apply("haze", 0.6)

	await _frames(5)
	var cam := GnCameras.save_view()
	cam.position = Vector3(6, 2.2, 14)
	cam.look_at(Vector3(0, 3.2, -2))
	var out: String = await GnRender.render(cam, Vector2i(1600, 900), EditorInterface.get_base_control())
	_check("stage rendered", out != "", out)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/set_stage.png"))
	# And at night, where beams matter.
	GnEnvironment.apply("sky", "Clear")
	GnEnvironment.apply("real_sun", false)
	GnEnvironment.apply("time_of_day", 21.0)
	GnEnvironment.apply("ambient", 0.15)
	var night: String = await GnRender.render(cam, Vector2i(1600, 900), EditorInterface.get_base_control())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(night), ProjectSettings.globalize_path("res://renders/set_night.png"))
	print("GN_SET RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_SET %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
