@tool
extends EditorPlugin

# Phase 2 acceptance, and the demo scene. Everything goes through the same
# Genesis systems the dock buttons call, in the order a user would click
# them: bring in a building, add a world, plant, light, frame, render.

const GnImport := preload("res://addons/genesis/core/gn_import.gd")
const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const GnScatter := preload("res://addons/genesis/core/gn_scatter.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnMaterials := preload("res://addons/genesis/core/gn_materials.gd")
const GnLook := preload("res://addons/genesis/core/gn_look.gd")
const GnMovie := preload("res://addons/genesis/core/gn_movie.gd")
const GnPasses := preload("res://addons/genesis/core/gn_passes.gd")

const SCENE := "res://scenes/demo.tscn"
const A := "res://genesis_assets"


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var root := Node3D.new()
	root.name = "Demo"
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, SCENE)
	root.free()
	EditorInterface.open_scene_from_path(SCENE)
	await _frames(10)

	var err: String = await GnImport.import_building(ProjectSettings.globalize_path(A + "/architecture/demo_house.glb"))
	_check("import building", err == "", err)
	var t_import := Time.get_ticks_msec()

	GnEnvironment.set_up()
	_check("environment", GnEnvironment.is_set_up(), "sun/sky missing")

	# The photographic plants when their textures have been fetched, the
	# generated placeholders otherwise.
	var real := ResourceLoader.exists(A + "/trees/beech.tscn")
	var broad := A + ("/trees/beech.tscn" if real else "/trees/tree_round.glb")
	var tall := A + ("/trees/poplar.tscn" if real else "/trees/tree_tall.glb")
	var shrub := A + ("/plants/round_shrub.tscn" if real else "/plants/shrub_round.glb")
	var hedge := A + ("/plants/hedge_shrub.tscn" if real else "/plants/shrub_round.glb")
	var grass := A + ("/grass/meadow_grass.tscn" if real else "/grass/grass_tuft.glb")
	for p in [Vector3(-14, 0, -9), Vector3(12, 0, -11), Vector3(19, 0, 2)]:
		GnPlacement.place(broad, "trees", p)
	for p in [Vector3(-20, 0, -3), Vector3(4, 0, -14), Vector3(-6, 0, -15)]:
		GnPlacement.place(tall, "trees", p)
	for p in [Vector3(-10.5, 0, 6.5), Vector3(7, 0, 7), Vector3(9, 0, 6)]:
		GnPlacement.place(shrub, "plants", p)
	for x in range(-8, 8, 2):
		GnPlacement.place(hedge, "plants", Vector3(x * 1.1 - 12, 0, 9.5))
	var g1 := GnScatter.fill_circle(grass, Vector3(9, 0, 12), 7.0, 2500, Vector2(0.7, 1.2), 1)
	var g2 := GnScatter.fill_circle(grass, Vector3(-12, 0, 13), 8.0, 3000, Vector2(0.7, 1.2), 2)
	_check("scatter", g1 != null and g2 != null, "grass scatter failed")

	# Early morning, the sun low over the camera's right shoulder: it rakes
	# across the glazed front and lights the side the camera sees.
	GnEnvironment.apply("time_of_day", 8.25)
	var skies := GnEnvironment.sky_choices()
	GnEnvironment.apply("sky", "Photo: partly cloudy" if "Photo: partly cloudy" in skies else "Clear")
	# Turn the site so the sun rakes across the glazed front from the right.
	GnEnvironment.apply("heading", 115.0 if "Photo: partly cloudy" in skies else 10.0)
	GnEnvironment.apply("fog", 0.25)

	var cam := GnCameras.save_view()
	_check("save camera", cam != null, "no camera")
	cam.position = Vector3(15, 3.2, 21)
	cam.look_at(Vector3(-2.5, 3.5, 0))
	GnCameras.set_focal_length(cam, 32.0)

	await _materials()

	# The shipped demo is not linked to the test's temporary copy of the house.
	for n in EditorInterface.get_edited_scene_root().find_children("*", "Node3D", true, false):
		if n.has_meta(&"gn_source") and not str(n.get_meta(&"gn_source")).begins_with("res://"):
			n.remove_meta(&"gn_source")
			n.remove_meta(&"gn_source_time")
	EditorInterface.save_scene()
	var t_scene := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string(SCENE)
	_check("saved scene keeps the material overrides", text.contains("surface_material_override/") and text.contains("[editable path="), "")
	var path: String = await GnRender.render(cam, Vector2i(1920, 1080), EditorInterface.get_base_control())
	_check("render", path != "", "no image")
	var t_render := Time.get_ticks_msec()
	print("GN_DEMO image %s" % ProjectSettings.globalize_path(path))
	# The same shot through several looks, for a person to compare. A higher
	# camera for these so 2-point perspective has converging verticals to fix.
	cam.position = Vector3(16, 7.5, 20)
	cam.look_at(Vector3(-2.5, 2.0, 0))
	for look_name in ["Natural", "Crisp daylight", "Warm afternoon", "Cinematic", "Pencil sketch",
			"Watercolour", "Painting", "Outlined", "Manga", "Clay model", "Golden glow"]:
		GnLook.apply_preset(cam, GnLook.PRESETS[look_name])
		var p: String = await GnRender.render(cam, Vector2i(1280, 720), EditorInterface.get_base_control())
		var named := "res://renders/look_%s.png" % look_name.to_lower().replace(" ", "_")
		DirAccess.rename_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(named))
		_check("look %s rendered" % look_name, FileAccess.file_exists(named), p)
		if look_name == "Manga":
			# Screentone: black and near-white, almost nothing in between.
			var m := Image.load_from_file(ProjectSettings.globalize_path(named))
			var mid := 0
			var n := 0
			for y in range(0, 720, 12):
				for x in range(0, 1280, 12):
					var l := m.get_pixel(x, y).get_luminance()
					mid += 1 if l > 0.25 and l < 0.75 else 0
					n += 1
			_check("manga is ink and paper (%.0f%% midtones)" % (100.0 * mid / n), float(mid) / n < 0.2, "")
	# A logo in the corner of the render.
	var logo := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	logo.fill(Color(1.0, 0.1, 0.6))
	DirAccess.make_dir_recursive_absolute("res://genesis_data/logos")
	logo.save_png(ProjectSettings.globalize_path("res://genesis_data/logos/test_logo.png"))
	GnLook.apply_preset(cam, {"logo": "res://genesis_data/logos/test_logo.png", "logo_size": 0.1, "logo_corner": "Top right"})
	var lp: String = await GnRender.render(cam, Vector2i(1280, 720), EditorInterface.get_base_control())
	var li := Image.load_from_file(ProjectSettings.globalize_path(lp))
	var corner := li.get_pixel(1280 - 29 - 20, 29 + 20)
	_check("the logo sits in the top right (%s)" % corner, corner.r > 0.8 and corner.g < 0.3 and corner.b > 0.4, str(corner))
	GnLook.apply_preset(cam, GnLook.PRESETS["Natural"])
	await _passes(cam)
	await _movie(cam)
	print("GN_DEMO timings ms: import %d, scene %d, render %d" % [t_import - t0, t_scene - t_import, t_render - t_scene])
	print("GN_DEMO RESULT %s" % ("PASS" if _ok else "FAIL"))
	EditorInterface.get_base_control().get_tree().quit(0 if _ok else 1)


var _ok := true


# Compositing passes: each must carry real information, not a flat image.
func _passes(cam: Camera3D) -> void:
	GnLook.apply_preset(cam, GnLook.PRESETS["Natural"])
	var out: Dictionary = await GnPasses.render(cam, Vector2i(960, 540), EditorInterface.get_base_control())
	_check("all five passes rendered", out.size() == 5, str(out.keys()))
	if out.has("depth"):
		var d := Image.load_from_file(ProjectSettings.globalize_path(out.depth))
		var near := d.get_pixel(480, 500).r
		# The farthest point along the top of the frame: sky somewhere,
		# whichever trees reach up into the shot.
		var far := 1.0
		for x in range(0, 960, 16):
			far = minf(far, d.get_pixel(x, 30).r)
		_check("depth pass varies (near brighter than sky)", near > far + 0.05, "%.2f vs %.2f" % [near, far])
	if out.has("id"):
		var img := Image.load_from_file(ProjectSettings.globalize_path(out.id))
		var colours := {}
		for y in range(0, 540, 12):
			for x in range(0, 960, 12):
				colours[img.get_pixel(x, y).to_html(false)] = true
		_check("ID pass has many object colours", colours.size() >= 6, str(colours.size()))
	if out.has("mask"):
		var m := Image.load_from_file(ProjectSettings.globalize_path(out.mask))
		var white := 0
		var black := 0
		for y in range(0, 540, 10):
			for x in range(0, 960, 10):
				if m.get_pixel(x, y).r > 0.9: white += 1
				elif m.get_pixel(x, y).r < 0.1: black += 1
		_check("mask has design and background", white > 50 and black > 50, "%d white, %d black" % [white, black])
	for k in out:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(out[k]), ProjectSettings.globalize_path("res://renders/pass_%s.png" % k))


# A short fly-through: a path through three cameras, then an orbit.
func _movie(first: Camera3D) -> void:
	GnLook.apply_preset(first, GnLook.PRESETS["Natural"])
	first.position = Vector3(15, 3.2, 21)
	first.look_at(Vector3(-2.5, 3.0, 0))
	var c2 := GnCameras.save_view()
	c2.position = Vector3(2, 2.2, 16)
	c2.look_at(Vector3(-1, 2.5, 0))
	var c3 := GnCameras.save_view()
	c3.position = Vector3(-14, 2.8, 14)
	c3.look_at(Vector3(-2, 3, 0))
	var list := [GnMovie.path_shot(["Camera 01", "Camera 02", "Camera 03"], 4.0),
		GnMovie.orbit_shot(Vector3(-1, 0, 0), 22.0, 6.0, 90.0, 4.0)]
	GnMovie.set_shots(list, "test movie")
	# That orbit clips the beech at the garden's edge; the check must say so.
	var blocked := GnMovie.obstructions(GnMovie.shots())
	print("GN_DEMO movie obstructions: %s" % str(blocked))
	_check("clearance check finds the tree in the orbit", blocked.any(func(b): return str(b.what).begins_with("Beech") or str(b.what).begins_with("TreeRound")), str(blocked))
	list[1] = GnMovie.orbit_shot(Vector3(-1, 0, 0), 30.0, 7.0, 90.0, 4.0)
	GnMovie.set_shots(list, "test movie, wider orbit")
	_check("the wider orbit is clear", GnMovie.obstructions(GnMovie.shots()).is_empty(), str(GnMovie.obstructions(GnMovie.shots())))
	# Smooth: frame-to-frame steps never jump far beyond the average step.
	var prev := Vector3.INF
	var steps: Array[float] = []
	for f in int(GnMovie.duration(list) * 30):
		var p: Vector3 = (GnMovie.sample(GnMovie.shots(), f / 30.0).transform as Transform3D).origin
		if prev != Vector3.INF:
			steps.append(prev.distance_to(p))
		prev = p
	var mean := 0.0
	for x in steps:
		mean += x
	mean /= steps.size()
	var worst: float = steps.max()
	print("GN_DEMO movie: mean step %.3f m, worst %.3f m" % [mean, worst])
	# The seam between shots is a cut, which is allowed to jump once.
	var jumps := steps.filter(func(x): return x > mean * 6.0)
	_check("fly-through moves smoothly (one cut between shots allowed)", jumps.size() <= 1, "%d jumps" % jumps.size())
	var out: String = await GnMovie.render(GnMovie.shots(), Vector2i(1280, 720), EditorInterface.get_base_control(), "demo_movie")
	var frames := DirAccess.get_files_at("res://renders/demo_movie").size()
	print("GN_DEMO movie: %d frames, %s" % [frames, out])
	_check("movie rendered 240 frames", frames == 240, str(frames))
	_check("movie encoded to mp4", out.ends_with(".mp4") and FileAccess.file_exists(out), out)


# The imported house's own materials swapped for presets, as a user would on
# the Materials tab: pick the house, pick a surface, click a preset.
func _materials() -> void:
	var house := EditorInterface.get_edited_scene_root().find_child("DemoHouse", false, false)
	var surfaces := GnMaterials.surfaces(house)
	var by_name := {}
	for s in surfaces:
		by_name[s.label] = s
	print("GN_DEMO house surfaces: %s" % ", ".join(by_name.keys()))
	_check("house lists its five materials", by_name.size() == 5, str(by_name.keys()))
	var plan := {"Wood": "wood", "Concrete": "concrete", "Glass": "glass", "Frame": "metal"}
	for surface_name in plan:
		if by_name.has(surface_name):
			GnMaterials.apply_preset(by_name[surface_name], "%s/%s.tres" % [GnMaterials.PRESET_DIR, plan[surface_name]])
	var wood: GnMaterials.Surface = by_name.get("Wood")
	var applied := wood.mesh.get(wood.property()) as BaseMaterial3D if wood else null
	_check("preset applied as an override", applied != null and applied.albedo_texture != null and applied.uv1_triplanar, "")
	_check("house became editable so the override is saved",
		EditorInterface.get_edited_scene_root().is_editable_instance(house), "")

	# One adjustment, then undo it, then undo the preset: back to the import.
	var plaster: GnMaterials.Surface = by_name.get("Plaster")
	var before: Material = plaster.material()
	GnMaterials.set_param(plaster, "albedo_color", Color(0.9, 0.85, 0.75))
	_check("adjusting makes an override", plaster.mesh.get(plaster.property()) != null, "")
	var ur := EditorInterface.get_editor_undo_redo()
	ur.get_history_undo_redo(ur.get_object_history_id(EditorInterface.get_edited_scene_root())).undo()
	_check("undo returns the imported material", plaster.material() == before and plaster.mesh.get(plaster.property()) == null, "")
	# Then the scanned plaster for the render.
	GnMaterials.apply_preset(plaster, "%s/plaster.tres" % GnMaterials.PRESET_DIR)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_DEMO %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await EditorInterface.get_base_control().get_tree().process_frame
