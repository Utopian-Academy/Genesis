@tool
extends EditorPlugin

# Phase 3 acceptance.
#   Part 1: the brush, driven with real mouse events through the same handle()
#           the plugin forwards viewport input to.
#   Part 2: measured, not guessed: frame time, draw calls, and scene
#           save/load for thousands of copies, against plain nodes.

const GnBrush := preload("res://addons/genesis/core/gn_brush.gd")
const GnScatter := preload("res://addons/genesis/core/gn_scatter.gd")
const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")

const GRASS := "res://genesis_assets/grass/grass_tuft.glb"
const TREE := "res://genesis_assets/trees/tree_round.glb"

var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	await _frames(20)
	await _open_scene("res://scenes/test_brush.tscn")
	GnEnvironment.set_up()
	await _brush_tests()
	await _surface_tests()
	await _terrain_water_tests()
	await _benchmark()
	print("GN_LAND RESULT %s" % ("PASS" if _ok else "FAIL"))
	_tree().quit(0 if _ok else 1)


# ---------------------------------------------------------------------------
func _brush_tests() -> void:
	# A camera straight above the origin, 60 m up, looking down.
	var vp := SubViewport.new()
	vp.size = Vector2i(1000, 1000)
	var cam := Camera3D.new()
	vp.add_child(cam)
	EditorInterface.get_base_control().add_child(vp)
	cam.position = Vector3(0, 60, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)

	var brush := GnBrush.new()
	brush.active = true
	brush.asset_path = GRASS
	brush.radius = 5.0
	brush.density = 4.0
	var history := func() -> UndoRedo:
		var ur := EditorInterface.get_editor_undo_redo()
		return ur.get_history_undo_redo(ur.get_object_history_id(GnScene.root()))

	# One stroke from one side of the view to the other.
	var y := 500.0
	_mouse(brush, cam, Vector2(300, y), true)
	for x in range(300, 701, 10):
		_move(brush, cam, Vector2(x, y))
	_mouse(brush, cam, Vector2(700, y), false)
	var group := GnScatter.find_group(GRASS)
	_check("stroke made a scatter", group != null, "")
	if group == null:
		vp.queue_free()
		return
	var n := GnScatter.points(group).size()
	# The stroke covers a band 2r wide along its length, plus two end caps.
	var start := _ground(cam, Vector2(300, y))
	var end := _ground(cam, Vector2(700, y))
	var area := start.distance_to(end) * 2.0 * brush.radius + PI * brush.radius * brush.radius
	var expected := area * brush.density
	print("GN_LAND stroke: %d copies over %.0f m2 = %.2f per m2 (asked for %.1f)" % [n, area, n / area, brush.density])
	_check("density 45-100% of what was asked", n > expected * 0.45 and n <= expected * 1.02, "%d vs %.0f" % [n, expected])

	var mmi := group.get_child(0) as MultiMeshInstance3D
	_check("multimesh count matches points", mmi.multimesh.instance_count == n, str(mmi.multimesh.instance_count))
	var p0: Transform3D = GnScatter.points(group)[0]
	var got := mmi.multimesh.get_instance_transform(0)
	var want: Transform3D = p0 * (mmi.get_meta(GnScatter.LOCAL) as Transform3D)
	_check("buffer layout matches the engine", got.origin.is_equal_approx(want.origin) and got.basis.is_equal_approx(want.basis), "%s vs %s" % [got, want])

	# A second pass over the same spot must not pile copies on top.
	_mouse(brush, cam, Vector2(500, y), true)
	_mouse(brush, cam, Vector2(500, y), false)
	var n2 := GnScatter.points(group).size()
	print("GN_LAND second pass over the same spot: %d -> %d" % [n, n2])
	_check("a repeat pass stays near the density", n2 < n * 1.25, str(n2))

	history.call().undo()
	_check("undo removes exactly the last stroke", GnScatter.points(group).size() == n and mmi.multimesh.instance_count == n,
		"%d points / %d instances" % [GnScatter.points(group).size(), mmi.multimesh.instance_count])
	history.call().redo()
	_check("redo puts it back", GnScatter.points(group).size() == n2 and mmi.multimesh.instance_count == n2,
		str(GnScatter.points(group).size()))

	# Shift-click erases inside the brush.
	var centre := _ground(cam, Vector2(500, y))
	_mouse(brush, cam, Vector2(500, y), true, true)
	_mouse(brush, cam, Vector2(500, y), false, true)
	var left := GnScatter.points(group)
	var inside := left.filter(func(p): return Vector2(p.origin.x - centre.x, p.origin.z - centre.z).length() < brush.radius - 0.01)
	print("GN_LAND erase: %d -> %d" % [n2, left.size()])
	_check("erase clears the brush circle", inside.is_empty() and left.size() < n2, "%d left inside" % inside.size())
	vp.queue_free()


func _mouse(brush: GnBrush, cam: Camera3D, pos: Vector2, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.shift_pressed = shift
	brush.handle(cam, e)


func _move(brush: GnBrush, cam: Camera3D, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = pos
	brush.handle(cam, e)


func _ground(cam: Camera3D, pos: Vector2) -> Vector3:
	return Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(pos), cam.project_ray_normal(pos))


# A raised planter 1 m tall. Painted with "any surface" on, the copies sit on
# top of it. With it off they stay on the ground and keep out from under it.
func _surface_tests() -> void:
	await _open_scene("res://scenes/test_surface.tscn")
	var root := GnScene.root()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8, 1, 8)
	box.mesh = bm
	box.position = Vector3(0, 0.5, 0)
	root.add_child(box)
	box.owner = root
	var vp := SubViewport.new()
	vp.size = Vector2i(1000, 1000)
	var cam := Camera3D.new()
	vp.add_child(cam)
	EditorInterface.get_base_control().add_child(vp)
	cam.position = Vector3(0, 60, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	var centre := Vector2(500, 500)

	for on in [true, false]:
		var brush := GnBrush.new()
		brush.active = true
		brush.asset_path = GRASS if on else TREE
		brush.radius = 3.0
		brush.density = 3.0
		brush.on_surfaces = on
		# Ground-only paints across the planter's edge, half on open ground.
		var at := centre if on else centre + Vector2(66, 0)
		_mouse(brush, cam, at, true)
		_mouse(brush, cam, at, false)
		var g := GnScatter.find_group(brush.asset_path)
		var pts: Array[Transform3D] = GnScatter.points(g) if g else ([] as Array[Transform3D])
		var heights := pts.map(func(p): return snappedf(p.origin.y, 0.01))
		var all_top := not pts.is_empty() and heights.all(func(h): return absf(h - 1.0) < 0.02)
		var all_ground := not pts.is_empty() and heights.all(func(h): return absf(h) < 0.02)
		print("GN_LAND surface painting %s: %d copies, heights %s" % ["on" if on else "off", pts.size(), str(heights.slice(0, 5))])
		if on:
			_check("any-surface paints on top of the planter", all_top, str(heights.slice(0, 8)))
		else:
			var under := pts.filter(func(p): return absf(p.origin.x) < 4.0 and absf(p.origin.z) < 4.0)
			_check("ground-only stays on the ground", all_ground, str(heights.slice(0, 8)))
			_check("and keeps out from under the planter", under.is_empty(), "%d under it" % under.size())

	# Grown variants: two other trees beside the stand-in, so a painted
	# wood is a mix of all three, and the mix survives undo and redo.
	var vdir := TREE.get_base_dir().path_join("variants")
	DirAccess.make_dir_recursive_absolute(vdir)
	for spec in [[2, BoxMesh.new()], [3, SphereMesh.new()]]:
		var vmi := MeshInstance3D.new()
		vmi.mesh = spec[1]
		var vpacked := PackedScene.new()
		vpacked.pack(vmi)
		ResourceSaver.save(vpacked, vdir.path_join("tree_round_v%d.tscn" % spec[0]))
		vmi.free()
	_check("the stand-in tree has its two variants", GnScatter.variants(TREE).size() == 3, str(GnScatter.variants(TREE)))
	var wood_brush := GnBrush.new()
	wood_brush.active = true
	wood_brush.asset_path = TREE
	wood_brush.radius = 6.0
	wood_brush.density = 2.0
	var old_group := GnScatter.find_group(TREE)
	# The group painted above predates the variants; set it aside.
	if old_group:
		old_group.set_meta(GnScatter.SOURCE, "")
	_mouse(wood_brush, cam, centre + Vector2(-250, -250), true)
	_mouse(wood_brush, cam, centre + Vector2(-250, -250), false)
	var wood := GnScatter.find_group(TREE)
	var per_variant := [0, 0, 0]
	if wood:
		for mmi in wood.get_children():
			if mmi is MultiMeshInstance3D:
				per_variant[int(mmi.get_meta(GnScatter.VARIANT, 0))] = maxi(per_variant[int(mmi.get_meta(GnScatter.VARIANT, 0))], mmi.multimesh.instance_count)
	var wood_total: int = per_variant[0] + per_variant[1] + per_variant[2]
	print("GN_LAND variants in the painted wood %s" % str(per_variant))
	_check("a painted wood mixes all three trees", per_variant.all(func(c): return c > 0), str(per_variant))
	_check("every copy is one of them", wood != null and GnScatter.points(wood).size() == wood_total, "")
	var vur := EditorInterface.get_editor_undo_redo()
	var vhist := vur.get_history_undo_redo(vur.get_object_history_id(GnScene.root()))
	vhist.undo()
	var after_undo := GnScatter.points(wood).size() if wood else -1
	vhist.redo()
	var again := GnScatter.points(wood).size() if wood else -1
	_check("undo takes the stroke away and redo brings the same mix back", after_undo == 0 and again == wood_total,
		"%d then %d" % [after_undo, again])
	vp.queue_free()


# Terrain: sculpt a hill with the brush, undo it, paint grass that follows
# it. Water: a pond and the ocean, rendered for a person to judge.
func _terrain_water_tests() -> void:
	await _open_scene("res://scenes/test_terrain.tscn")
	GnEnvironment.set_up()
	var Terrain = load("res://addons/genesis/set/gn_terrain.gd")
	var WaterBody = load("res://addons/genesis/set/gn_water_body.gd")
	var root := GnScene.root()
	var t: Node3D = Terrain.new()
	t.name = "Terrain"
	GnScene.add_node(t, root, "terrain", "terrain")
	# As the Add terrain button does: the flat ground makes way.
	(GnScene.find_role("ground") as Node3D).visible = false
	await _frames(3)
	var vp := SubViewport.new()
	vp.size = Vector2i(1000, 1000)
	var cam := Camera3D.new()
	vp.add_child(cam)
	EditorInterface.get_base_control().add_child(vp)
	cam.position = Vector3(0, 80, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	var brush := GnBrush.new()
	brush.active = true
	brush.mode = "raise"
	brush.radius = 15.0
	brush.sculpt_strength = 1.5
	for i in 5:
		_mouse(brush, cam, Vector2(500, 500), true)
		_mouse(brush, cam, Vector2(500, 500), false)
	var peak: float = t.height_at(Vector3.ZERO)
	print("GN_LAND terrain peak after 5 strokes: %.2f m" % peak)
	_check("raising sculpts a hill", peak > 5.0, str(peak))
	var ur := EditorInterface.get_editor_undo_redo()
	ur.get_history_undo_redo(ur.get_object_history_id(root)).undo()
	await _frames(2)
	_check("undo takes one stroke off", t.height_at(Vector3.ZERO) < peak - 0.5, str(t.height_at(Vector3.ZERO)))
	ur.get_history_undo_redo(ur.get_object_history_id(root)).redo()
	await _frames(2)
	brush.mode = "plants"
	brush.asset_path = GRASS
	brush.density = 3.0
	brush.radius = 8.0
	_mouse(brush, cam, Vector2(500, 500), true)
	_mouse(brush, cam, Vector2(500, 500), false)
	var g := GnScatter.find_group(GRASS)
	var pts: Array[Transform3D] = GnScatter.points(g) if g else ([] as Array[Transform3D])
	var off := pts.filter(func(p): return absf(p.origin.y - t.height_at(p.origin)) > 0.05)
	print("GN_LAND grass on terrain: %d copies, %d off the surface" % [pts.size(), off.size()])
	_check("grass follows the terrain", not pts.is_empty() and off.is_empty(), "%d of %d off" % [off.size(), pts.size()])
	# Painting the ground: gravel on the hilltop, sand to one side.
	t.layers = PackedStringArray(["gravel", "sand"])
	brush.mode = "paint"
	brush.radius = 10.0
	brush.paint_strength = 0.6
	brush.paint_layer = 1
	for i in 3:
		_mouse(brush, cam, Vector2(500, 500), true)
		_mouse(brush, cam, Vector2(500, 500), false)
	brush.paint_layer = 2
	for i in 3:
		_mouse(brush, cam, Vector2(700, 500), true)
		_mouse(brush, cam, Vector2(700, 500), false)
	await _frames(2)
	var mid: int = (t.cells / 2 * (t.cells + 1) + t.cells / 2) * 4
	print("GN_LAND ground at the top: gravel %d, sand %d" % [t.splat[mid], t.splat[mid + 1]])
	_check("the brush lays gravel where it paints", t.splat[mid] > 200 and t.splat[mid + 1] < 40, str(t.splat.slice(mid, mid + 4)))
	var sand_seen := false
	for i in range(0, t.splat.size(), 4):
		if t.splat[i + 1] > 200:
			sand_seen = true
	_check("and sand where it paints sand", sand_seen, "")
	var surface := t.find_child("Surface", false, false) as MeshInstance3D
	_check("the ground blends its layers in a shader", surface and surface.material_override is ShaderMaterial, "")
	brush.paint_layer = 0
	_mouse(brush, cam, Vector2(500, 500), true)
	_mouse(brush, cam, Vector2(500, 500), false)
	_check("wiping takes it back toward the surface", t.splat[mid] < 150, str(t.splat[mid]))
	ur.get_history_undo_redo(ur.get_object_history_id(root)).undo()
	await _frames(2)
	_check("and undo puts the gravel back", t.splat[mid] > 200, str(t.splat[mid]))
	brush.mode = "plants"
	vp.queue_free()
	var pond: Node3D = WaterBody.new()
	pond.kind = "Pond"
	pond.width = 30
	pond.length = 20
	GnScene.add_node(pond, root, "pond", "water")
	pond.position = Vector3(40, 0.3, 30)
	var sea: Node3D = WaterBody.new()
	sea.kind = "Ocean"
	GnScene.add_node(sea, root, "sea", "water")
	sea.position = Vector3(0, -0.4, 0)
	var shot := GnCameras.save_view()
	shot.position = Vector3(70, 12, 75)
	shot.look_at(Vector3(0, 3, 0))
	var out: String = await GnRender.render(shot, Vector2i(1280, 720), EditorInterface.get_base_control())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/land_terrain_water.png"))
	_check("terrain and water rendered", out != "", "")


# ---------------------------------------------------------------------------
func _benchmark() -> void:
	# Each size in its own fresh scene: trees and grass over a 200 m field,
	# seen from an eye-level architectural camera.
	var rows := []
	for grass in [0, 5000, 20000, 50000]:
		rows.append(await _measure("multimesh", grass, 300))
	rows.append(await _measure("nodes", 0, 300))
	rows.append(await _measure("nodes", 0, 2000))
	rows.append(await _measure("multimesh", 0, 2000))
	print("GN_LAND BENCH mode        trees  grass  frame_ms  draw_calls  tscn_KB  save_ms  load_ms")
	for r in rows:
		print("GN_LAND BENCH %-10s %6d %6d %9.2f %11d %8.0f %8d %8d" % r)
	var big: Array = rows[3]
	_check("50k grass + 300 trees under 33 ms a frame (30 fps)", big[3] < 33.0, "%.1f ms" % big[3])


func _measure(mode: String, grass: int, trees: int) -> Array:
	var path := "res://scenes/bench_%s_%d_%d.tscn" % [mode, trees, grass]
	await _open_scene(path)
	GnEnvironment.set_up()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	if mode == "multimesh":
		if trees > 0:
			var pts: Array[Transform3D] = []
			for i in trees:
				pts.append(GnScatter.make_point(Vector3(rng.randf_range(-100, 100), 0, rng.randf_range(-100, 20)), rng, Vector2(0.8, 1.2)))
			GnScatter.set_points(GnScatter.create_group(TREE), pts, "trees")
		if grass > 0:
			var g: Array[Transform3D] = []
			for i in grass:
				g.append(GnScatter.make_point(Vector3(rng.randf_range(-100, 100), 0, rng.randf_range(-100, 30)), rng, Vector2(0.7, 1.1)))
			GnScatter.set_points(GnScatter.create_group(GRASS), g, "grass")
	else:
		# The naive way: one instanced scene per tree, as click-to-place makes.
		var root := GnScene.root()
		var packed := load(TREE) as PackedScene
		for i in trees:
			var t := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
			t.position = Vector3(rng.randf_range(-100, 100), 0, rng.randf_range(-100, 20))
			root.add_child(t, true)
			t.owner = root

	var t0 := Time.get_ticks_usec()
	EditorInterface.save_scene()
	var save_ms := (Time.get_ticks_usec() - t0) / 1000
	var kb := FileAccess.get_file_as_bytes(path).size() / 1024.0
	var frame := await _frame_time()
	t0 = Time.get_ticks_usec()
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var inst := loaded.instantiate()
	var load_ms := (Time.get_ticks_usec() - t0) / 1000
	inst.free()
	return [mode, trees, grass, frame.ms, frame.draws, kb, save_ms, load_ms]


# Renders the open scene through an eye-level 1080p camera for 60 frames with
# vsync and the editor's power saving off, and reports the average.
func _frame_time() -> Dictionary:
	var sub := SubViewport.new()
	sub.size = Vector2i(1920, 1080)
	sub.world_3d = EditorInterface.get_editor_viewport_3d(0).find_world_3d()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.far = 2000
	sub.add_child(cam)
	EditorInterface.get_base_control().add_child(sub)
	cam.position = Vector3(0, 1.7, 40)
	cam.look_at(Vector3(0, 1.5, 0))
	cam.make_current()
	var low := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	var vsync := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 15:
		await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_usec()
	for i in 60:
		await RenderingServer.frame_post_draw
	var ms := (Time.get_ticks_usec() - t0) / 60000.0
	var draws := RenderingServer.viewport_get_render_info(sub.get_viewport_rid(),
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	DisplayServer.window_set_vsync_mode(vsync)
	OS.low_processor_usage_mode = low
	sub.queue_free()
	return {"ms": ms, "draws": draws}


func _open_scene(path: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var root := Node3D.new()
	root.name = path.get_file().get_basename().to_pascal_case()
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()
	EditorInterface.open_scene_from_path(path)
	await _frames(5)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_LAND %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _tree() -> SceneTree:
	return EditorInterface.get_base_control().get_tree()


func _frames(n: int) -> void:
	for i in n:
		await _tree().process_frame
