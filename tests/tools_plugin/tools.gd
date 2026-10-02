@tool
extends EditorPlugin

# The drawing tools on the demo house: the tape measure driven by real
# clicks in the 3D view, layers hiding and showing with undo, and plan,
# section and elevation cameras that must actually cut (a cut render has to
# differ from an uncut one where the cut is).

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnMeasure := preload("res://addons/genesis/core/gn_measure.gd")
const GnLayers := preload("res://addons/genesis/core/gn_layers.gd")
const GnSections := preload("res://addons/genesis/core/gn_sections.gd")
const Effect := preload("res://addons/genesis/set/gn_effect.gd")
const Mover := preload("res://addons/genesis/set/gn_mover.gd")
const Fixture := preload("res://addons/genesis/set/gn_light_fixture.gd")
const GnIes := preload("res://addons/genesis/core/gn_ies.gd")
const GnMovie := preload("res://addons/genesis/core/gn_movie.gd")
const GnAssets := preload("res://addons/genesis/core/gn_assets.gd")
const GnImport := preload("res://addons/genesis/core/gn_import.gd")
const GnLiveLink := preload("res://addons/genesis/core/gn_live_link.gd")
const GnMaterials := preload("res://addons/genesis/core/gn_materials.gd")
const FlyingScreen := preload("res://addons/genesis/set/gn_flying_screen.gd")
const AreaLight := preload("res://addons/genesis/set/gn_area_light.gd")
const GnPhasing := preload("res://addons/genesis/core/gn_phasing.gd")
const GnWeathering := preload("res://addons/genesis/core/gn_weathering.gd")
const GnTiles := preload("res://addons/genesis/core/gn_tiles.gd")
const GnUpscale := preload("res://addons/genesis/core/gn_upscale.gd")
const A := "res://genesis_assets"

var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(500.0).timeout.connect(func(): print("GN_TOOLS FAIL watchdog"); get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var r0 := Node3D.new()
	r0.name = "Tools"
	var packed := PackedScene.new()
	packed.pack(r0)
	ResourceSaver.save(packed, "res://scenes/tools_test.tscn")
	r0.free()
	EditorInterface.open_scene_from_path("res://scenes/tools_test.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	GnEnvironment.apply("time_of_day", 13.0)
	var house := GnPlacement.place(A + "/architecture/demo_house.glb", "architecture", Vector3.ZERO)
	await _frames(5)
	var host := get_editor_interface().get_base_control()

	# Measure, by clicking where two known points are on screen.
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	cam.global_transform = Transform3D(Basis(), Vector3(0, 18, 30))
	cam.look_at(Vector3(0, 0, 8))
	await _frames(3)
	var tape := GnMeasure.new()
	tape.active = true
	var made: Array = []
	tape.measured.connect(func(d): made.append(d))
	var a := Vector3(-6, 0, 12)
	var b := Vector3(6, 0, 12)
	for p in [a, b]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = cam.unproject_position(p)
		tape.handle(cam, click)
	await _frames(3)
	_check("two clicks leave one dimension", made.size() == 1, str(made.size()))
	if made.size() == 1:
		var d: Node3D = made[0]
		print("GN_TOOLS measured %s" % d.text())
		_check("it measures the 12 m between the clicks", absf(d.length() - 12.0) < 0.1, d.text())
		_check("it is labelled", d.find_children("*", "Label3D", true, false).size() == 1, "")
	var roof_y: float = GnSections.design_bounds().end.y
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	cam.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 30, 0))
	await _frames(2)
	down.position = cam.unproject_position(Vector3(0, 0, 0))
	tape.handle(cam, down)
	down.position = cam.unproject_position(Vector3(3, 0, 0))
	tape.handle(cam, down)
	if made.size() == 2:
		var roof: Node3D = made[1]
		_check("measuring snaps to the roof it clicks on (%.2f m up)" % roof.start.y,
			absf(roof.start.y - roof_y) < 0.2, "%.2f vs roof %.2f" % [roof.start.y, roof_y])
	tape.active = false

	# A line of trees along the front, placed by the same two clicks.
	var tree := A + ("/trees/beech.tscn" if ResourceLoader.exists(A + "/trees/beech.tscn") else "/trees/tree_round.glb")
	tape.line_asset = tree
	tape.line_category = "trees"
	tape.line_spacing = 4.0
	tape.active = true
	cam.global_transform = Transform3D(Basis(), Vector3(0, 25, 40))
	cam.look_at(Vector3(0, 0, 15))
	await _frames(2)
	var before := GnScene.root().get_child_count()
	for p in [Vector3(-10, 0, 16), Vector3(10, 0, 16)]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = cam.unproject_position(p)
		tape.handle(cam, click)
	var added := GnScene.root().get_child_count() - before
	_check("20 m every 4 m is 6 trees (%d)" % added, added == 6, str(added))
	var row: Array = GnScene.root().get_children().slice(before)
	if row.size() == 6:
		var gap: float = (row[1] as Node3D).position.distance_to((row[0] as Node3D).position)
		_check("4 m apart (%.2f)" % gap, absf(gap - 4.0) < 0.1, "%.2f" % gap)
		_check("facing along the line", absf(absf((row[0] as Node3D).rotation.y) - PI * 0.5) < 0.05,
			str((row[0] as Node3D).rotation.y))
	var ur0 := EditorInterface.get_editor_undo_redo()
	ur0.get_history_undo_redo(ur0.get_object_history_id(GnScene.root())).undo()
	_check("one undo takes the whole line away", GnScene.root().get_child_count() == before,
		str(GnScene.root().get_child_count() - before))
	tape.line_asset = ""
	tape.active = false

	# Every effect builds, and fire shows in a night render.
	for k in Effect.KINDS:
		var e := Effect.new()
		e.kind = k
		add_child(e)
		var ps: GPUParticles3D = e.particles()
		_check("%s builds" % k, ps != null and ps.amount > 0 and ps.process_material != null, "")
		e.free()
	var fx_nodes: Array = []
	for spec in [["Fire", Vector3(0, 0, 12), 2.0], ["Cold sparks", Vector3(4, 0.3, 12), 1.0], ["Fountain", Vector3(-4, 0, 12), 1.0]]:
		var e := Effect.new()
		e.kind = spec[0]
		e.size = spec[2]
		GnScene.add_node(e, GnScene.root(), "effect", "effect")
		e.position = spec[1]
		fx_nodes.append(e)
	GnEnvironment.apply("time_of_day", 21.0)
	var fx_cam := Camera3D.new()
	fx_cam.position = Vector3(0, 2.5, 22)
	GnScene.add_node(fx_cam, GnScene.root(), "fx cam")
	fx_cam.look_at(Vector3(0, 2, 12))
	await _frames(10)
	var fx: String = await GnRender.render(fx_cam, Vector2i(960, 540), host)
	if fx != "":
		DirAccess.copy_absolute(ProjectSettings.globalize_path(fx), ProjectSettings.globalize_path("res://renders/tools_effects.png"))
		var img := Image.load_from_file(ProjectSettings.globalize_path(fx))
		# The fire sits a little below the middle of this shot: round there
		# the picture must be bright and warm (its core burns out to white).
		var sum := Color(0, 0, 0, 0)
		var n := 0
		for y in range(250, 340, 3):
			for x in range(440, 520, 3):
				sum += img.get_pixel(x, y)
				n += 1
		var mean := sum / n
		print("GN_TOOLS fire area %s" % mean)
		_check("the fire glows at night", mean.get_luminance() > 0.3 and mean.r > mean.b * 1.2, str(mean))
	GnEnvironment.apply("time_of_day", 13.0)
	for e in fx_nodes:
		e.visible = false

	# IES: a downlight's file gives its cone, beam shape and lumens.
	var ies_path := OS.get_user_data_dir().path_join("test_downlight.ies")
	var f := FileAccess.open(ies_path, FileAccess.WRITE)
	f.store_string("IESNA:LM-63-2002\n[TEST] Genesis test downlight\nTILT=NONE\n" +
		"1 1000 1 7 1 1 2 0.1 0.1 0.05\n1 1 12\n0 10 20 25 30 40 90\n0\n" +
		"900 850 600 300 20 0 0\n")
	f.close()
	var prof := GnIes.load_file(ies_path)
	_check("an IES file reads (%s lm)" % (prof.lumens if prof else "?"), prof != null and absf(prof.lumens - 1000.0) < 0.1, "")
	var dl := Fixture.new()
	dl.kind = "Downlight"
	dl.tilt = -90.0
	dl.ies = ies_path
	GnScene.add_node(dl, GnScene.root(), "downlight", "light")
	await _frames(3)
	var spots := dl.find_children("*", "SpotLight3D", true, false)
	if not spots.is_empty():
		var sp := spots[0] as SpotLight3D
		_check("its cone opens to where the light runs out (%.0f°)" % sp.spot_angle, sp.spot_angle >= 25.0 and sp.spot_angle <= 30.0, str(sp.spot_angle))
		_check("with the beam's shape as its projector", sp.light_projector != null, "")
		_check("and the file's lumens", absf(sp.light_energy - 1000.0 / 1500.0) < 0.01, str(sp.light_energy))
	dl.visible = false

	# Moving objects: two cars on a 40 m road, 10 m/s.
	var road := Mover.new()
	road.name = "Road"
	road.speed = 10.0
	GnScene.add_node(road, GnScene.root(), "road", "mover")
	road.curve.set_point_position(0, Vector3(-20, 0, 20))
	road.curve.set_point_position(1, Vector3(20, 0, 20))
	var car_path := GnAssets.find("vehicles", "hatchback_red")
	var cars: Array = []
	for i in 2:
		var car := (load(car_path) as PackedScene).instantiate() as Node3D if car_path != "" else Node3D.new()
		road.add_child(car)
		car.owner = GnScene.root()
		cars.append(car)
	road.at_time(0.0)
	var start: Vector3 = cars[0].position
	var apart: float = cars[0].position.distance_to(cars[1].position)
	road.at_time(1.5)
	var moved: float = cars[0].position.distance_to(start)
	_check("cars spread out along the road (%.1f m apart)" % apart, absf(apart - 20.0) < 0.5, "%.1f" % apart)
	_check("and travel 15 m in 1.5 s at 10 m/s (%.1f)" % moved, absf(moved - 15.0) < 0.3, "%.1f" % moved)
	var heading: Vector3 = -(cars[0] as Node3D).basis.z
	_check("facing the way they go", heading.dot(Vector3.RIGHT) > 0.99, str(heading))
	# A walker on a footpath steps in time with the ground it covers.
	var walker_path := GnAssets.find("people", "walker_1")
	if walker_path != "":
		var path_walk := Mover.new()
		path_walk.speed = 1.3
		GnScene.add_node(path_walk, GnScene.root(), "footpath", "mover")
		var walker := (load(walker_path) as PackedScene).instantiate() as Node3D
		path_walk.add_child(walker)
		walker.owner = GnScene.root()
		var ap := walker.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_check("walkers come with their walk", ap != null and ap.has_animation("walk"), "")
		if ap and ap.has_animation("walk"):
			path_walk.at_time(0.5)
			var len_s := ap.get_animation("walk").length
			var want := fposmod(0.5 * 1.3 / 1.4, 1.0) * len_s
			_check("and step in time with the ground (%.2f s into the cycle)" % ap.current_animation_position,
				absf(ap.current_animation_position - want) < 0.02, "%.2f vs %.2f" % [ap.current_animation_position, want])
		path_walk.visible = false

	# Time-lapse: the sun moves through the film and is put back after.
	GnMovie.set_shots([GnMovie.orbit_shot(Vector3.ZERO, 30.0, 8.0, 90.0, 4.0)], "shots")
	GnMovie.set_timelapse(7.0, 19.0, true)
	GnEnvironment.apply("time_of_day", 13.0)
	var list := GnMovie.shots()
	var sun: Node3D = GnEnvironment.sun()
	var h0 := GnMovie.show_time(0.0, list)
	var morning := sun.global_basis.z
	var noon := GnMovie.show_time(2.0, list)
	var midday := sun.global_basis.z
	var h1 := GnMovie.show_time(4.0, list)
	_check("the film starts at 07:00, is at 13:00 halfway and ends at 19:00 (%.1f, %.1f, %.1f)" % [h0, noon, h1],
		absf(h0 - 7.0) < 0.01 and absf(noon - 13.0) < 0.01 and absf(h1 - 19.0) < 0.01, "")
	_check("and the sun really moves (%.0f° by midday)" % rad_to_deg(morning.angle_to(midday)), morning.angle_to(midday) > deg_to_rad(40), "")
	GnEnvironment.apply("time_of_day", 13.0)
	var film: String = await GnMovie.render(list, Vector2i(320, 180), host, "tools_timelapse", Callable(), 1)
	_check("a time-lapse renders", film != "", "")
	_check("and leaves the time as it was", absf(float(GnEnvironment.value("time_of_day")) - 13.0) < 0.01,
		str(GnEnvironment.value("time_of_day")))
	road.visible = false

	# Live link: bring a model in from outside the project, re-export over
	# it, and the one in the scene becomes the new version.
	var outside := OS.get_user_data_dir().path_join("live_link_test")
	DirAccess.make_dir_recursive_absolute(outside)
	var source := outside.path_join("linked_model.glb")
	# Single-file models, as a CAD export would be: a tree, then the house.
	DirAccess.copy_absolute(ProjectSettings.globalize_path(A + "/trees/tree_round.glb"), source)
	var err: String = await GnImport.import_building(source)
	_check("a building comes in from outside", err == "", err)
	var linked: Node3D = GnScene.root().find_child("LinkedModel", false, false)
	_check("and is linked to its source", linked != null and linked.has_meta(GnLiveLink.SOURCE), "")
	if linked:
		linked.position = Vector3(30, 0, 0)
		var small := GnSections._bounds([linked]).size.x
		await get_tree().create_timer(1.2).timeout  # file times tick in seconds
		DirAccess.copy_absolute(ProjectSettings.globalize_path(A + "/architecture/demo_house.glb"), source)
		var n := GnLiveLink.poll()
		_check("the re-export is noticed", n == 1, str(n))
		var efs := EditorInterface.get_resource_filesystem()
		for i in 600:
			await get_tree().process_frame
			if i > 20 and not efs.is_importing() and not efs.is_scanning():
				break
		await _frames(10)
		linked = GnScene.root().find_child("LinkedModel", false, false)
		var big := GnSections._bounds([linked]).size.x if linked else 0.0
		print("GN_TOOLS live link: %.1f m -> %.1f m wide" % [small, big])
		_check("and the scene shows the new version, where it stood", linked != null and big > small * 1.5
			and linked.position.distance_to(Vector3(30, 0, 0)) < 0.01, "%.1f -> %.1f" % [small, big])
		if linked:
			linked.visible = false

	# Your own texture: a colour map with its normal and roughness partners.
	var tex_dir := OS.get_user_data_dir().path_join("own_texture_test")
	DirAccess.make_dir_recursive_absolute(tex_dir)
	var checker := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			checker.set_pixel(x, y, Color(0.8, 0.2, 0.1) if (x / 8 + y / 8) % 2 == 0 else Color(0.9, 0.9, 0.85))
	checker.save_png(tex_dir.path_join("tiles_Color.png"))
	var flat := Image.create(64, 64, false, Image.FORMAT_RGB8)
	flat.fill(Color(0.5, 0.5, 1.0))
	flat.save_png(tex_dir.path_join("tiles_NormalGL.png"))
	flat.fill(Color(0.6, 0.6, 0.6))
	flat.save_png(tex_dir.path_join("tiles_Roughness.png"))
	var maps := GnMaterials.partner_maps(tex_dir.path_join("tiles_Color.png"))
	_check("finds the normal and roughness maps beside it", maps.normal.ends_with("tiles_NormalGL.png")
		and maps.roughness.ends_with("tiles_Roughness.png"), str(maps))
	var surf: Array = GnMaterials.surfaces(house)
	if not surf.is_empty():
		var terr: String = await GnMaterials.apply_image(surf[0], tex_dir.path_join("tiles_Color.png"), 0.6)
		var own := surf[0].mesh.get(surf[0].property()) as StandardMaterial3D
		_check("your own image goes on (%s)" % (terr if terr != "" else "ok"), terr == "" and own != null
			and own.albedo_texture != null and own.normal_texture != null and own.roughness_texture != null, terr)
		if own:
			_check("tiling at 0.6 m", absf(own.uv1_scale.x - 1.0 / 0.6) < 0.001, str(own.uv1_scale))
			# Weathering: grime and streaks over the same material, and off again.
			var clean_rough := own.roughness
			GnWeathering.apply(surf[0], 0.8)
			var worn := surf[0].mesh.get(surf[0].property()) as StandardMaterial3D
			var grime := worn.detail_albedo.get_image() if worn.detail_albedo else null
			var streaky := false
			if grime:
				var lo := 1.0
				for y in range(0, grime.get_height(), 8):
					for x in range(0, grime.get_width(), 8):
						lo = minf(lo, grime.get_pixel(x, y).get_luminance())
				streaky = lo < 0.75
			_check("weathering lays grime over the material", worn.detail_enabled and worn.detail_blend_mode == BaseMaterial3D.BLEND_MODE_MUL
				and streaky and worn.roughness >= minf(clean_rough + 0.2, 1.0) and worn.albedo_texture == own.albedo_texture,
				"detail %s mode %d streaky %s rough %.2f->%.2f same tex %s" % [worn.detail_enabled, worn.detail_blend_mode,
				streaky, clean_rough, worn.roughness, worn.albedo_texture == own.albedo_texture])
			GnWeathering.apply(surf[0], 0.0)
			_check("and comes off again", not worn.detail_enabled and absf(worn.roughness - clean_rough) < 0.001, "")

	# Tiles and grout: 600 x 300 mm tiles in half bond with a 5 mm dark
	# joint, measured in the drawn map, then laid on a floor.
	var tiles_d := GnTiles.DEFAULTS.merged({"layout": "Half bond", "tile_w": 0.6, "tile_h": 0.3, "grout": 0.005,
		"grout_colour": Color(0.15, 0.15, 0.16), "colour": Color(0.85, 0.84, 0.8)}, true)
	var tplan := GnTiles.plan(tiles_d)
	var tmaps := GnTiles.draw(tiles_d)
	var talb: Image = tmaps.albedo
	var tpx := Vector2(talb.get_width() / tplan.width, talb.get_height() / tplan.height)
	var is_grout := func(x_m: float, y_m: float) -> bool:
		return talb.get_pixelv(Vector2i(roundi(x_m * tpx.x), roundi(y_m * tpx.y))).get_luminance() < 0.3
	var trow_h := 0.305
	_check("the joint between two tiles is grout", is_grout.call(0.605, trow_h * 0.5), "")
	_check("the tile beside it is tile", not is_grout.call(0.3, trow_h * 0.5), "")
	_check("the next row is offset by half a tile", is_grout.call(0.3025, trow_h * 1.5) and not is_grout.call(0.605, trow_h * 1.5), "")
	var run := 0
	var ty := roundi(trow_h * 0.5 * tpx.y)
	for x in range(0, talb.get_width()):
		if talb.get_pixel(x, ty).get_luminance() >= 0.3:
			run += 1
		elif run > 0:
			break
	var tile_mm := run / tpx.x * 1000.0
	print("GN_TOOLS tile drawn %.1f mm wide at %.0f px/m, repeat %.3f x %.3f m" % [tile_mm, tpx.x, tplan.width, tplan.height])
	_check("a tile is drawn 600 mm wide, to the pixel (%.1f mm)" % tile_mm, absf(tile_mm - 600.0) <= 1000.0 / tpx.x + 0.01, "")
	var floor_mi := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8, 8)
	floor_mi.mesh = floor_mesh
	GnScene.add_node(floor_mi, GnScene.root(), "tiled floor")
	floor_mi.position = Vector3(40, 0.01, 0)
	var floor_s: GnMaterials.Surface = GnMaterials.surfaces(floor_mi)[0]
	GnTiles.apply(floor_s, tiles_d)
	var tmat := floor_s.material() as StandardMaterial3D
	_check("the floor is tiled", tmat != null and tmat.has_meta(GnTiles.META) and tmat.normal_texture != null
		and absf(tmat.uv1_scale.x * tplan.width - 1.0) < 0.001 and absf(tmat.uv1_scale.z * tplan.height - 1.0) < 0.001, "")
	_check("the design reads back", is_equal_approx(GnTiles.design(floor_s).tile_w, 0.6), "")
	print("GN_TOOLS %s" % GnTiles.report(tiles_d))
	var tcam := Camera3D.new()
	GnScene.add_node(tcam, GnScene.root(), "tile cam")
	tcam.position = Vector3(40, 1.6, 3.2)
	tcam.look_at(Vector3(40, 0, -0.5))
	await _frames(5)
	var tshot: String = await GnRender.render(tcam, Vector2i(960, 540), host)
	if tshot != "":
		DirAccess.copy_absolute(ProjectSettings.globalize_path(tshot), ProjectSettings.globalize_path("res://renders/tools_tiles.png"))
	floor_mi.visible = false

	# Photoreal by accumulation: the house from the front, standard and
	# accumulated, then accumulated with lens blur focused on the porch.
	var acam := Camera3D.new()
	GnScene.add_node(acam, GnScene.root(), "accum cam")
	acam.position = Vector3(3, 1.7, 16)
	acam.look_at(Vector3(0, 2.5, 0))
	await _frames(3)
	var the_sun := GnScene.find_role("sun") as DirectionalLight3D
	var sun_before := [the_sun.global_basis, the_sun.light_angular_distance] if the_sun else []
	var shots := {}
	for spec in [["std", 0, 0.0], ["acc", 16, 0.0], ["dof", 16, 1.0]]:
		acam.set_meta(&"gn_look", {"dof": spec[2], "focus": 3.0} if spec[2] > 0.0 else {})
		var t0 := Time.get_ticks_msec()
		var p: String = await GnRender.render(acam, Vector2i(960, 540), host, true, Viewport.DEBUG_DRAW_DISABLED, false, spec[1])
		print("GN_TOOLS accumulate %s took %.1f s" % [spec[0], (Time.get_ticks_msec() - t0) / 1000.0])
		if p != "":
			DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path("res://renders/tools_accum_%s.png" % spec[0]))
			shots[spec[0]] = Image.load_from_file(ProjectSettings.globalize_path(p))
	_check("photoreal stills render", shots.size() == 3, str(shots.keys()))
	if shots.size() == 3:
		var means := {}
		for k in shots:
			var sum := 0.0
			var img: Image = shots[k]
			for y in range(0, img.get_height(), 6):
				for x in range(0, img.get_width(), 6):
					sum += img.get_pixel(x, y).get_luminance()
			means[k] = sum / ((img.get_height() / 6 + 1) * (img.get_width() / 6 + 1))
		print("GN_TOOLS accumulate means %s" % str(means))
		_check("a photoreal still is as bright as a standard one", absf(means.acc - means.std) < 0.02, str(means))
		# Detail in the house's face: lens blur focused 3 m away softens it.
		var detail := func(img: Image) -> float:
			var s := 0.0
			for y in range(150, 330, 2):
				for x in range(310, 640, 2):
					s += absf(4.0 * img.get_pixel(x, y).get_luminance() - img.get_pixel(x - 1, y).get_luminance()
						- img.get_pixel(x + 1, y).get_luminance() - img.get_pixel(x, y - 1).get_luminance()
						- img.get_pixel(x, y + 1).get_luminance())
			return s
		var sharp: float = detail.call(shots.acc)
		var soft: float = detail.call(shots.dof)
		print("GN_TOOLS accumulate detail sharp %.1f, lens blur %.1f" % [sharp, soft])
		_check("lens blur softens what is out of focus", soft < sharp * 0.75, "%.1f vs %.1f" % [soft, sharp])
	_check("the sun is put back after a photoreal still", the_sun == null or (the_sun.global_basis.is_equal_approx(sun_before[0])
		and is_equal_approx(the_sun.light_angular_distance, sun_before[1])), "")

	# AI upscaling: the photoreal still ×2 with Real-ESRGAN (fetched and
	# fingerprint-checked the first time), sharper than a plain resize.
	if GnUpscale.available() and FileAccess.file_exists("res://renders/tools_accum_acc.png"):
		if not GnUpscale.installed():
			var t_dl := Time.get_ticks_msec()
			var dl_err: String = await GnUpscale.install(host)
			print("GN_TOOLS upscaler installed in %.1f s: %s" % [(Time.get_ticks_msec() - t_dl) / 1000.0, dl_err if dl_err != "" else "ok"])
			_check("the upscaler downloads and checks out", dl_err == "" and GnUpscale.installed(), dl_err)
		var t_up := Time.get_ticks_msec()
		var up: Dictionary = await GnUpscale.upscale("res://renders/tools_accum_acc.png", 2, host)
		print("GN_TOOLS upscale took %.1f s: %s" % [(Time.get_ticks_msec() - t_up) / 1000.0, up])
		var big := Image.load_from_file(ProjectSettings.globalize_path(up.path)) if up.path != "" else null
		_check("a render upscales ×2", big != null and big.get_size() == Vector2i(1920, 1080), str(big.get_size() if big else up.error))
		if big:
			var plain := Image.load_from_file(ProjectSettings.globalize_path("res://renders/tools_accum_acc.png"))
			plain.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
			var edges := func(img: Image) -> float:
				var s := 0.0
				for y in range(300, 660, 3):
					for x in range(620, 1280, 3):
						s += absf(img.get_pixel(x + 1, y).get_luminance() - img.get_pixel(x, y).get_luminance())
				return s
			var e_ai: float = edges.call(big)
			var e_plain: float = edges.call(plain)
			print("GN_TOOLS upscale edges: ai %.1f, plain %.1f" % [e_ai, e_plain])
			_check("and comes out sharper than a plain resize", e_ai > e_plain * 1.1, "%.1f vs %.1f" % [e_ai, e_plain])
	else:
		print("GN_TOOLS upscale skipped: no build for this system")

	# Animals keep their painted coats (vertex colours) in Godot.
	var horse_path := GnAssets.find("animals", "horse_bay_standing")
	_check("the library has a bay horse", horse_path != "", "")
	if horse_path != "":
		var horse := (load(horse_path) as PackedScene).instantiate()
		var coated := false
		for mi in horse.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i) as BaseMaterial3D
				var arrays := mesh.surface_get_arrays(i)
				if m and m.vertex_color_use_as_albedo and arrays[Mesh.ARRAY_COLOR] != null:
					coated = true
		_check("and its coat is painted on (vertex colours in use)", coated, "")
		horse.free()

	# Boats float on their waterline; aircraft are there to fly.
	var boats := GnAssets.of_kind("boats", ["boat"]).size()
	var aircraft := GnAssets.of_kind("aircraft", []).size()
	_check("the library has boats (%d) and aircraft (%d)" % [boats, aircraft], boats >= 10 and aircraft >= 8, "")
	var cat_path := GnAssets.find("boats", "boat_catamaran")
	_check("including a catamaran", cat_path != "", "")
	if cat_path != "":
		var cat := (load(cat_path) as PackedScene).instantiate() as Node3D
		var lo := INF
		var hi := -INF
		for mi in cat.find_children("*", "MeshInstance3D", true, false):
			var bb := (mi as MeshInstance3D).get_aabb()
			lo = minf(lo, bb.position.y)
			hi = maxf(hi, bb.end.y)
		_check("it sits in the water: hulls below the origin, mast above (%.1f to %.1f m)" % [lo, hi],
			lo < -0.3 and lo > -2.0 and hi > 15.0, "")
		cat.free()

	# The plant library (when setup has built it): species of every kind,
	# each light enough to scatter by the hundred.
	if ResourceLoader.exists(A + "/trees/beech.tscn"):
		var trees := GnAssets.of_kind("trees", []).size()
		var shrubs := GnAssets.of_kind("plants", []).size()
		var kinds := {}
		var heaviest := ""
		var worst := 0
		for cat in ["trees", "plants", "grass"]:
			for plant in GnAssets.of_kind(cat, []):
				kinds[str(plant.license.get("kind", "?"))] = true
				var tris := int(plant.license.get("triangles", 0))
				if tris > worst:
					worst = tris
					heaviest = plant.path.get_file()
		print("GN_TOOLS plants: %d trees, %d garden plants, kinds %s, heaviest %s (%d triangles)" % [trees, shrubs, kinds.keys(), heaviest, worst])
		_check("a real plant library: 25+ trees and 20+ garden plants", trees >= 25 and shrubs >= 20, "%d, %d" % [trees, shrubs])
		_check("broadleaf, conifer, palm, shrub, topiary, flowers and grass all present",
			kinds.has_all(["broadleaf", "conifer", "palm", "shrub", "topiary", "flowers", "grass"]), str(kinds.keys()))
		_check("every plant light enough to scatter (heaviest %d triangles)" % worst, worst <= 120000, heaviest)
		var beech := (load(A + "/trees/beech.tscn") as PackedScene).instantiate() as MeshInstance3D
		_check("a tree has bark and foliage, each its own surface", beech.mesh.get_surface_count() >= 2, str(beech.mesh.get_surface_count()))
		beech.free()

	# Area lights: a panel that lights the floor under it, warm or cool.
	var warm := AreaLight.kelvin_colour(2700.0)
	var cool := AreaLight.kelvin_colour(6500.0)
	_check("2,700 K is warmer than 6,500 K", warm.r / warm.b > cool.r / cool.b * 1.5, "%s %s" % [warm, cool])
	var panel := AreaLight.new()
	panel.size = Vector2(1.6, 1.6)
	panel.lumens = 20000.0
	panel.position = Vector3(40, 3, 40)
	panel.rotation_degrees = Vector3(-90, 0, 0)
	GnScene.root().add_child(panel)
	await _frames(3)
	var panel_spots := panel.find_children("*", "SpotLight3D", true, false)
	var energy := 0.0
	for s in panel_spots:
		energy += (s as SpotLight3D).light_energy
	_check("its output is shared by %d lights (%.2f in all)" % [panel_spots.size(), energy], panel_spots.size() >= 4 and absf(energy - 20000.0 / 1500.0) < 0.01, "")
	_check("each with a soft-shadow size", panel_spots.size() > 0 and (panel_spots[0] as SpotLight3D).light_size > 0.2, "")
	GnEnvironment.apply("time_of_day", 23.0)
	var floor_cam := Camera3D.new()
	GnScene.root().add_child(floor_cam)
	floor_cam.global_position = Vector3(44, 2.5, 44)
	floor_cam.look_at(Vector3(40, 0, 40))
	var lums: Array = []
	for level in [0.0, 1.0]:
		panel.dimmer = level
		await _frames(3)
		var shot: String = await GnRender.render(floor_cam, Vector2i(480, 270), host, false)
		var img := Image.load_from_file(ProjectSettings.globalize_path(shot)) if shot != "" else null
		var sum := 0.0
		if img:
			for y in range(135, 270, 6):
				for x in range(120, 360, 6):
					sum += img.get_pixel(x, y).get_luminance()
		lums.append(sum)
	print("GN_TOOLS area light: floor %.1f off, %.1f on" % lums)
	_check("the floor under it lights up when it comes on", lums[1] > lums[0] * 1.5 + 1.0, str(lums))
	GnEnvironment.apply("time_of_day", 13.0)
	panel.free()
	floor_cam.free()

	# Phasing: a block rises out of the ground at 1 s, taking 2 s; another grows.
	var block := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 3, 2)
	block.mesh = bm
	block.position = Vector3(60, 1.5, 60)
	GnScene.root().add_child(block)
	block.owner = GnScene.root()
	var tower := block.duplicate() as MeshInstance3D
	tower.position = Vector3(64, 1.5, 60)
	GnScene.root().add_child(tower)
	tower.owner = GnScene.root()
	GnPhasing.set_phase([block], 1.0, 2.0, "Rise from the ground")
	GnPhasing.set_phase([tower], 1.0, 2.0, "Grow up")
	GnMovie.show_time(0.5, [])
	_check("before its moment a phased block is not there", not block.visible and not tower.visible, "")
	GnMovie.show_time(1.6, [])
	print("GN_TOOLS phasing at 1.6 s: block at %.2f m, tower scale %.2f" % [block.position.y, tower.scale.y])
	_check("half way it is rising out of the ground", block.visible and block.position.y < 1.4 and block.position.y > -1.5, str(block.position))
	_check("and the other growing up", tower.visible and tower.scale.y > 0.05 and tower.scale.y < 0.95, str(tower.scale))
	GnMovie.show_time(3.5, [])
	_check("at the end both stand built", absf(block.position.y - 1.5) < 0.001 and absf(tower.scale.y - 1.0) < 0.001, "")
	GnMovie.show_time(1.2, [])
	GnPhasing.finish(GnScene.root())
	_check("after the film the scene is back as built", block.visible and absf(block.position.y - 1.5) < 0.001
		and absf(tower.scale.y - 1.0) < 0.001 and not block.has_meta(GnPhasing.BASE), "")
	block.free()
	tower.free()

	# The flying screen: an LED wall on a long line under a heavy lifter.
	var fly := FlyingScreen.new()
	fly.position = Vector3(0, 40, -20)
	GnScene.root().add_child(fly)
	fly.owner = GnScene.root()
	await _frames(3)
	_check("a flying screen picks a heavy lifter", fly.helicopter.contains("heli_heavy"), fly.helicopter)
	var screen := fly.wall()
	_check("and hangs a real LED wall", screen != null and screen.report().resolution == Vector2i(16 * 84, 5 * 168),
		str(screen.report().resolution) if screen else "none")
	if screen:
		var hook := fly.global_transform * fly.hook_point()
		var top := screen.global_position.y + float(screen.report().size_m.y)
		var r := fly.report()
		print("GN_TOOLS flying screen: hook %.1f m, wall top %.1f m, payload %.0f kg of %.0f, period %.1f s" % [
			hook.y, top, r.payload_kg, r.hook_limit_kg, r.period_s])
		_check("below the hook by the long line and the bridle (%.1f m)" % (hook.y - top),
			hook.y - top > fly.long_line and hook.y - top < fly.long_line + 10.0, "")
		_check("its payload is within the hook limit", r.payload_kg > 1000.0 and r.payload_kg < r.hook_limit_kg, str(r))
		_check("and it swings like a pendulum that long (%.1f s)" % r.period_s,
			absf(r.period_s - TAU * sqrt(fly._pendulum() / 9.81)) < 0.01 and r.period_s > 8.0, "")
		GnMovie.show_time(2.0, [])
		var swung := absf(fly.get_node("Load").rotation.x)
		_check("the movie clock swings it (%.2f°)" % rad_to_deg(swung), swung > deg_to_rad(0.3), "")
		GnMovie.show_time(0.0, [])
		var shot := Camera3D.new()
		GnScene.root().add_child(shot)
		shot.global_position = Vector3(18, 22, 30)
		shot.look_at(Vector3(0, 26, -20))
		shot.fov = 60.0
		var fly_out: String = await GnRender.render(shot, Vector2i(960, 720), host)
		_check("and it renders", fly_out != "", "")
		if fly_out != "":
			DirAccess.copy_absolute(ProjectSettings.globalize_path(fly_out), ProjectSettings.globalize_path("res://renders/tools_flying.png"))
		shot.free()
	# Off again, so the plans below frame the house alone.
	fly.free()

	# Layers.
	GnLayers.assign([house], "Building")
	_check("layer listed", GnLayers.layers().has("Building"), str(GnLayers.layers().keys()))
	GnLayers.show("Building", false)
	_check("hiding the layer hides it", not house.visible, "")
	var ur := EditorInterface.get_editor_undo_redo()
	ur.get_history_undo_redo(ur.get_object_history_id(GnScene.root())).undo()
	_check("and undo brings it back", house.visible, "")

	# Plans and sections: a cut has to change the picture where it cuts.
	EditorInterface.get_selection().clear()
	var box := GnSections.design_bounds()
	print("GN_TOOLS design %s" % box)
	_check("design bounds are the house, not the ground", box.size.x < 30.0 and box.size.x > 10.0, str(box))
	var roof_plan := GnSections.plan(box.end.y + 1.0)
	var cut_plan := GnSections.plan(1.5)
	var elevation := GnSections.elevation()
	var cut := GnSections.section(box.get_center().z)
	var imgs := {}
	for pair in [["roof", roof_plan], ["plan", cut_plan], ["elevation", elevation], ["section", cut]]:
		var out: String = await GnRender.render(pair[1], Vector2i(960, 720), host)
		_check("%s rendered" % pair[0], out != "", "")
		if out != "":
			DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/tools_%s.png" % pair[0]))
			imgs[pair[0]] = Image.load_from_file(ProjectSettings.globalize_path(out))
	if imgs.size() == 4:
		var dp := _difference(imgs.roof, imgs.plan)
		var ds := _difference(imgs.elevation, imgs.section)
		print("GN_TOOLS plan differs from roof by %.3f, section from elevation by %.3f" % [dp, ds])
		_check("the plan cut opens the roof", dp > 0.02, "%.3f" % dp)
		_check("the section cut opens the front", ds > 0.02, "%.3f" % ds)
	# And the preview/render keep an orthographic camera orthographic.
	_check("plans are orthographic", cut_plan.projection == Camera3D.PROJECTION_ORTHOGONAL, "")

	EditorInterface.save_scene()
	print("GN_TOOLS RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


# Mean absolute difference of two images, 0..1.
func _difference(x: Image, y: Image) -> float:
	var w := mini(x.get_width(), y.get_width())
	var h := mini(x.get_height(), y.get_height())
	var total := 0.0
	var n := 0
	for j in range(0, h, 4):
		for i in range(0, w, 4):
			var p := x.get_pixel(i, j)
			var q := y.get_pixel(i, j)
			total += (absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)) / 3.0
			n += 1
	return total / maxi(n, 1)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_TOOLS %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
