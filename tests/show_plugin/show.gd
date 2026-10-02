@tool
extends EditorPlugin

# A concert built from the production kit: stage, LED wall, truss, flown line
# arrays, ground subs, real moving heads, a front-of-house position with
# consoles and a camera, a crowd, and a frustrated queue at the bar. Checks
# the numbers that can be checked (headcount, array height, where each
# moving head's beam really points) and renders it at night.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnLook := preload("res://addons/genesis/core/gn_look.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const GnAssets := preload("res://addons/genesis/core/gn_assets.gd")
const LedWall := preload("res://addons/genesis/set/gn_led_wall.gd")
const Truss := preload("res://addons/genesis/set/gn_truss.gd")
const StageDeck := preload("res://addons/genesis/set/gn_stage_deck.gd")
const Fixture := preload("res://addons/genesis/set/gn_light_fixture.gd")
const Crowd := preload("res://addons/genesis/set/gn_crowd.gd")
const LineArray := preload("res://addons/genesis/set/gn_line_array.gd")
const GnContent := preload("res://addons/genesis/core/gn_content.gd")

const KIT := "res://genesis_assets"
var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(1100.0).timeout.connect(func():
		print("GN_SHOW FAIL watchdog")
		get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var r0 := Node3D.new()
	r0.name = "Show"
	var packed := PackedScene.new()
	packed.pack(r0)
	ResourceSaver.save(packed, "res://scenes/show_test.tscn")
	r0.free()
	EditorInterface.open_scene_from_path("res://scenes/show_test.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	var scene := GnScene.root()

	# The library knows the kit.
	var kinds := {}
	for a in GnAssets.scan().assets:
		kinds[a.category] = kinds.get(a.category, 0) + 1
	print("GN_SHOW library: %s" % kinds)
	for c in ["people", "audio", "lighting", "control", "av"]:
		_check("library has %s" % c, kinds.get(c, 0) > 0, str(kinds))

	# Stage, wall, rig.
	var deck := StageDeck.new()
	deck.name = "Stage"
	deck.width = 16
	deck.depth = 9
	deck.height = 1.5
	GnScene.add_node(deck, scene, "stage", "stage")
	var wall := LedWall.new()
	wall.name = "LED wall"
	wall.panel = "3.9 mm indoor/outdoor (500 × 1000)"
	wall.columns = 24
	wall.rows = 6
	wall.curve_degrees = 0
	wall.bottom = 1.9
	wall.brightness = 1.4
	wall.content = GnContent.concert_visual(1536, 768)
	GnScene.add_node(wall, scene, "wall", "led_wall")
	wall.position = Vector3(0, 0, -4.2)
	for x in [-9.0, 9.0]:
		var tower := Truss.new()
		tower.section = "520 mm box"
		tower.length = 11.0
		tower.rotation_degrees = Vector3(0, 0, 90)
		tower.position = Vector3(x, 0, -1.0)
		GnScene.add_node(tower, scene, "tower", "truss")
	var span := Truss.new()
	span.section = "520 mm box"
	span.length = 18.52
	span.position = Vector3(-9.26, 11.0, -1.0)
	GnScene.add_node(span, scene, "span", "truss")

	# A circle of triangle truss over the thrust, and it must close.
	var ring := Truss.new()
	ring.name = "Circle truss"
	ring.section = "400 mm triangle"
	ring.make_circle(3.5)
	GnScene.add_node(ring, scene, "circle", "truss")
	ring.position = Vector3(0, 8.5, 0.5)
	await _frames(2)
	var ring_box: AABB = (ring.get_child(0) as MeshInstance3D).get_aabb()
	_check("circle truss closes (%.2f × %.2f m)" % [ring_box.size.x, ring_box.size.z],
		# Square if it closes; 7 m plus the section's reach outside the curve.
		absf(ring_box.size.x - ring_box.size.z) < 0.05 and ring_box.size.x > 7.0 and ring_box.size.x < 7.5, str(ring_box.size))
	for s in ["290 mm triangle", "300 mm ladder", "220 mm ladder (flat)"]:
		var t := Truss.new()
		t.section = s
		t.length = 3.0
		add_child(t)
		_check("%s builds" % s, t.get_child_count() == 1 and (t.get_child(0) as MeshInstance3D).mesh.get_faces().size() > 100, "")
		t.free()

	# Crowd barrier along the front of the stage, audience side out.
	for i in 22:
		var bar := GnPlacement.place(GnAssets.find("props", "barrier_crowd"), "props", Vector3(-10.5 + i * 1.0, 0, 7.0))
		if bar:
			bar.rotation_degrees.y = 180

	# Real moving heads on the span, hung, aimed down at the stage and out.
	var worst := 0.0
	for i in 10:
		var f := Fixture.new()
		f.name = "Spot %d" % (i + 1)
		f.model = GnAssets.find("lighting", "spot_gigapointe" if i % 2 == 0 else "wash_aurora")
		f.kind = "Beam (moving head)" if i % 2 == 0 else "Wash"
		f.lumens = 20000 if i % 2 == 0 else 9000
		f.beam_degrees = 6 if i % 2 == 0 else 25
		f.colour = [Color(0.3, 0.5, 1.0), Color(1.0, 0.3, 0.8), Color(1.0, 0.85, 0.5)][i % 3]
		f.pan = (i - 4.5) * 9.0
		f.tilt = -55.0 - (i % 3) * 10.0
		f.position = Vector3(-8.1 + i * 1.8, 10.6, -0.4)
		f.rotation_degrees = Vector3(0, 180, 0)
		GnScene.add_node(f, scene, "fixture", "light")
		await _frames(2)
		# The model's head must point where pan and tilt say.
		var want := f.global_basis * (Basis(Vector3.UP, deg_to_rad(f.pan)) * Basis(Vector3.RIGHT, deg_to_rad(f.tilt))) * Vector3.FORWARD
		var lights := f.find_children("*", "SpotLight3D", true, false)
		if lights.is_empty():
			_check("fixture %d has its light" % i, false, "")
			continue
		var got: Vector3 = -(lights[0] as Node3D).global_basis.z
		worst = maxf(worst, rad_to_deg(want.angle_to(got)))
	_check("moving heads aim where pan and tilt say (worst %.2f°)" % worst, worst < 0.5, "%.2f°" % worst)

	# Audience light, as a real rig has it: warm washes on the span turned
	# out over the crowd, and blinders along the downstage edge.
	for i in 6:
		var w := Fixture.new()
		w.name = "Audience wash %d" % (i + 1)
		w.model = GnAssets.find("lighting", "wash_impresso")
		w.kind = "Wash"
		# Low, and barely in the haze: lit faces, not a wall of fog.
		w.lumens = 4000
		w.beam_in_haze = 0.12
		w.beam_degrees = 38
		w.colour = Color(1.0, 0.72, 0.45)
		w.pan = (i - 2.5) * 12.0
		w.tilt = -32.0
		w.position = Vector3(-7.5 + i * 3.0, 10.6, -1.6)
		w.rotation_degrees = Vector3(0, 180, 0)
		GnScene.add_node(w, scene, "fixture", "light")
	for i in 4:
		var b := Fixture.new()
		b.name = "Blinder %d" % (i + 1)
		b.model = GnAssets.find("lighting", "blinder_moley_4")
		b.kind = "Wash"
		b.lumens = 1500
		b.beam_in_haze = 0.08
		b.beam_degrees = 70
		b.colour = Color(1.0, 0.8, 0.55)
		b.tilt = -8.0
		b.hung = false
		b.position = Vector3(-6.0 + i * 4.0, 1.75, 4.2)
		b.rotation_degrees = Vector3(0, 180, 0)
		GnScene.add_node(b, scene, "fixture", "light")

	# PA: a line array each side, facing the audience (+Z), subs on the deck front.
	for x in [-11.5, 11.5]:
		var pa := LineArray.new()
		pa.name = "PA %s" % ("left" if x < 0 else "right")
		pa.element = GnAssets.find("audio", "line_array_kilo2")
		pa.boxes = 12
		pa.position = Vector3(x, 12.5, 0.5)
		pa.rotation_degrees = Vector3(0, 180 + (8 if x < 0 else -8), 0)
		GnScene.add_node(pa, scene, "line array", "speakers")
	await _frames(4)
	var left := scene.get_node("PA left")
	var drop: float = -left.bottom_height()
	print("GN_SHOW " + left.report_text().replace("\n", " | "))
	# Twelve 0.36 m boxes hang about 4.3 m; splay shortens it a little.
	_check("line array hangs about 4 m", drop > 3.6 and drop < 4.6, "%.2f m" % drop)
	for i in 8:
		var sub := GnPlacement.place(GnAssets.find("audio", "sub_kay_ess_29"), "audio", Vector3(-7.0 + i * 2.0, 0, 5.2))
		if sub:
			sub.rotation_degrees.y = 180

	# The audience, facing the stage (their forward, -Z, is the stage's way).
	var crowd := Crowd.new()
	crowd.name = "Audience"
	crowd.width = 34.0
	crowd.depth = 16.0
	crowd.density = 2.2
	GnScene.add_node(crowd, scene, "crowd", "people")
	crowd.position = Vector3(0, 0, 15.5)
	var back := Crowd.new()
	back.name = "Audience behind FOH"
	back.width = 40.0
	back.depth = 10.0
	back.density = 1.4
	back.variation = 7
	GnScene.add_node(back, scene, "crowd", "people")
	back.position = Vector3(0, 0, 34.0)
	var queue := Crowd.new()
	queue.name = "Bar queue"
	queue.mood = "Frustrated"
	queue.width = 2.0
	queue.depth = 12.0
	queue.density = 1.6
	queue.turn_spread = 40.0
	GnScene.add_node(queue, scene, "crowd", "people")
	queue.position = Vector3(-24.0, 0, 20.0)
	queue.rotation_degrees.y = 90
	await _frames(4)
	var heads: int = crowd.headcount() + back.headcount() + queue.headcount()
	print("GN_SHOW headcount %d (front %d, back %d, queue %d)" % [heads, crowd.headcount(), back.headcount(), queue.headcount()])
	_check("crowd at the density asked", absf(crowd.headcount() - 34.0 * 16.0 * 2.2) < 34.0 * 16.0 * 2.2 * 0.12,
		str(crowd.headcount()))
	_check("queue is frustrated", queue.headcount() > 10, str(queue.headcount()))

	# Front of house, facing the stage.
	var foh := Vector3(0, 0, 26.0)
	GnPlacement.place(GnAssets.find("control", "foh_table"), "control", foh)
	GnPlacement.place(GnAssets.find("control", "lighting_console_grandpa_full"), "control", foh + Vector3(-0.6, 0.8, 0))
	GnPlacement.place(GnAssets.find("control", "audio_console_digidoc_sd8"), "control", foh + Vector3(0.9, 0.8, 0))
	GnPlacement.place(GnAssets.find("av", "camera_studio_box_lens"), "av", foh + Vector3(3.2, 0, 0.5))
	GnPlacement.place(GnAssets.find("av", "camera_jib"), "av", Vector3(-13.0, 0, 7.0))

	# Night, haze.
	GnEnvironment.apply("sky", "Clear")
	GnEnvironment.apply("real_sun", false)
	GnEnvironment.apply("time_of_day", 21.5)
	GnEnvironment.apply("haze", 0.65)
	GnEnvironment.apply("ambient", 0.25)
	await _frames(20)

	var cam := GnCameras.save_view()
	cam.name = "FOH view"
	cam.position = foh + Vector3(0, 2.6, 2.5)
	cam.look_at(Vector3(0, 5.5, -2))
	cam.fov = 58
	GnLook.apply_preset(cam, {"bloom": 0.5, "contrast": 1.1, "vignette": 0.3})
	await _shot(cam, "show_foh")
	# The wide shot at last light, so the site reads round the show.
	GnEnvironment.apply("time_of_day", 18.4)
	GnEnvironment.apply("haze", 0.5)
	await _frames(10)
	var wide := GnCameras.save_view()
	wide.name = "Wide"
	wide.position = Vector3(-38, 24, 48)
	wide.look_at(Vector3(0, 3, 10))
	wide.fov = 45
	GnLook.apply_preset(wide, {"bloom": 0.4, "contrast": 1.08})
	await _shot(wide, "show_wide")
	var pit := GnCameras.save_view()
	pit.name = "Photo pit"
	pit.position = Vector3(4.0, 1.4, 6.6)
	pit.look_at(Vector3(-2.0, 1.8, 16.0))
	pit.fov = 70
	GnLook.apply_preset(pit, {"bloom": 0.5, "contrast": 1.1, "vignette": 0.35})
	await _shot(pit, "show_crowd")
	EditorInterface.save_scene()
	print("GN_SHOW RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _shot(cam: Camera3D, label: String) -> void:
	var out: String = await GnRender.render(cam, Vector2i(1920, 1080), EditorInterface.get_base_control())
	_check("%s rendered" % label, out != "", "")
	if out != "":
		DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/%s.png" % label))


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_SHOW %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
