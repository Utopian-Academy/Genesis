extends SceneTree

# Renders plants side by side in daylight, for judging them by eye:
#
#     godot --path . -s tools/preview_plants.gd -- out.png [name_prefix ...]
#
# With no prefixes it shows every tree, plant and grass in the library;
# with them, those and their grown variants.
# Needs a window (a GPU), so not --headless.
#
# GN_ROW=1 lines them up in a single row framed to fit, for showcase sheets;
# GN_EXACT=1 takes the names as whole names (no variants, no oak_young for oak).

const DIRS := ["res://genesis_assets/trees", "res://genesis_assets/plants", "res://genesis_assets/grass"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://plants.png"
	var prefixes := Array(args.slice(1))
	var paths: Array = []
	# Naming plants shows their grown variants beside them too.
	var exact := OS.get_environment("GN_EXACT") != ""
	var row := OS.get_environment("GN_ROW") != ""
	var dirs: Array = DIRS if prefixes.is_empty() else DIRS + ["res://genesis_assets/trees/variants"]
	for d in dirs:
		for f in DirAccess.get_files_at(d):
			var stem := f.get_basename()
			var wanted := prefixes.is_empty() or (prefixes.has(stem) if exact else prefixes.any(func(p): return f.begins_with(p)))
			if f.get_extension() in ["tscn", "glb", "gltf"] and wanted:
				paths.append("%s/%s" % [d, f])
	if exact:
		# In the order asked for.
		paths.sort_custom(func(a, b): return prefixes.find(a.get_file().get_basename()) < prefixes.find(b.get_file().get_basename()))
	else:
		paths.sort()
	# Drawn in a viewport of its own, so the sheet is 1920 x 1080 whatever
	# size the window opens at.
	var view := SubViewport.new()
	view.size = Vector2i(1920, 1080)
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var world := Node3D.new()
	view.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.42, 0.58, 0.82)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.72, 0.8, 0.9)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Part neutral, so a blue sky doesn't turn the leaves teal.
	e.ambient_light_color = Color(0.8, 0.8, 0.76)
	e.ambient_light_sky_contribution = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1000, 1000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.36, 0.26)
	ground.material_override = gm
	world.add_child(ground)

	# Lay them out in rows, each spaced by its own width.
	var x := 0.0
	var z := 0.0
	var row_depth := 0.0
	# Rows about as long as the plants are tall, so small ones fill the frame too.
	var max_row := INF if row else 60.0
	var placed: Array = []  # [instance, bounds, label], for the line-up
	var tallest := 0.0
	var widest := 0.0
	for p in paths:
		var inst := (load(p) as PackedScene).instantiate() as Node3D
		world.add_child(inst)
		var box := _bounds(inst)
		var w := maxf(box.size.x, 0.2) * 1.15 + 0.15
		if x + w > max_row:
			x = 0.0
			z -= row_depth + 2.0
			row_depth = 0.0
		inst.position = Vector3(x - box.position.x, 0, z - box.end.z) if paths.size() > 1 else Vector3.ZERO
		var label := Label3D.new()
		label.text = p.get_file().get_basename()
		var info = JSON.parse_string(FileAccess.get_file_as_string(p.get_basename() + ".license.json")) if FileAccess.file_exists(p.get_basename() + ".license.json") else null
		if info is Dictionary and info.has("label"):
			label.text = str(info.label)
		label.pixel_size = 0.004 if not row else 0.012
		label.position = inst.position + Vector3(box.get_center().x, 0.05, box.end.z + 0.4)
		label.rotation_degrees = Vector3(-60, 0, 0) if not row else Vector3.ZERO
		if row:
			label.outline_size = 8
			label.position.y = 0.0
			label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			placed.append([inst, box, label])
		world.add_child(label)
		x += w
		row_depth = maxf(row_depth, box.size.z)
		tallest = maxf(tallest, box.size.y)
		widest = maxf(widest, x)
	var cam := Camera3D.new()
	world.add_child(cam)
	var span := maxf(widest, -z + tallest)
	cam.fov = 40.0
	if row:
		# Straight on, slightly above, the whole line-up filling the frame.
		cam.fov = 30.0
		var half_v := deg_to_rad(cam.fov * 0.5)
		var half_h := atan(tan(half_v) * 16.0 / 9.0)
		# Names are about 26 px tall whatever the distance, and each plant
		# gets a slot at least as wide as its name; the framing and the name
		# size depend on each other, so settle them in a few rounds.
		var d := 0.0
		for round in 4:
			d = maxf(widest * 0.5 / tan(half_h), tallest * 0.55 / tan(half_v)) * 1.08
			var ps := d * 0.00034
			var slot_x := 0.0
			for it in placed:
				var box: AABB = it[1]
				var label: Label3D = it[2]
				# Names wrap, so a slot needs only its longest word, and fits two
				# lines' worth when the plant is wide enough anyway.
				var longest := 0
				for word in label.text.split(" "):
					longest = maxi(longest, word.length())
				var char_w := 0.62 * label.font_size * ps
				var w := maxf(maxf(box.size.x, 0.2) * 1.15 + 0.15, (longest + 2) * char_w)
				w = maxf(w, minf(label.text.length() * char_w * 0.55, label.text.length() * char_w + 30.0 * ps))
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.width = w / ps - 20.0
				(it[0] as Node3D).position = Vector3(slot_x + (w - box.size.x) * 0.5 - box.position.x, 0, -box.end.z)
				label.position = Vector3(slot_x + w * 0.5, 0.0, 0.4)
				label.pixel_size = ps
				slot_x += w
			widest = slot_x
		cam.look_at_from_position(Vector3(widest * 0.5, tallest * 0.55, d), Vector3(widest * 0.5, tallest * 0.45, 0.0))
	else:
		cam.look_at_from_position(Vector3(widest * 0.5, tallest * 0.7 + span * 0.3, span * 0.9 + tallest * 0.6),
			Vector3(widest * 0.5, tallest * 0.35, z * 0.5))
	# GN_CAM="x,y,z;tx,ty,tz" puts the camera somewhere particular (a close look at a trunk).
	var at := OS.get_environment("GN_CAM")
	if at != "":
		var p := at.split(";")
		var a := p[0].split_floats(",")
		var b := p[1].split_floats(",")
		cam.look_at_from_position(Vector3(a[0], a[1], a[2]), Vector3(b[0], b[1], b[2]))
	cam.current = true
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var shot := view.get_texture().get_image()
	if row:
		# Just the band with the plants and their names in it.
		var top := 1080.0
		for it in placed:
			var box: AABB = it[1]
			var inst: Node3D = it[0]
			top = minf(top, cam.unproject_position(inst.position + Vector3(box.get_center().x, box.end.y, box.get_center().z)).y)
		var bottom := cam.unproject_position(Vector3(widest * 0.5, 0.0, 0.4)).y
		var y0 := clampi(int(top) - 50, 0, 1079)
		var y1 := clampi(int(bottom) + 50, y0 + 1, 1080)
		shot = shot.get_region(Rect2i(0, y0, 1920, y1 - y0))
	shot.save_png(ProjectSettings.globalize_path(out) if out.begins_with("res://") or out.begins_with("user://") else out)
	print("preview: %d plants -> %s" % [paths.size(), out])
	quit()


func _bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b = (mi as MeshInstance3D).transform * b if mi != n else b
		box = b if first else box.merge(b)
		first = false
	return box
