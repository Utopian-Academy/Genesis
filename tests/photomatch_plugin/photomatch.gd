@tool
extends EditorPlugin

# Photo match, end to end, against a genuine photograph: a view out of a CC0
# HDRI panorama shot in a real field. Its camera is known exactly, and the
# same panorama lights the scene, so the design should sit in the photo with
# its shadows falling the way the photo's own shadows do.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnPhotomatch := preload("res://addons/genesis/core/gn_photomatch.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

const SCENE := "res://scenes/photomatch_test.tscn"
var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	# A script error stops _run without quitting the editor; don't wait forever.
	get_tree().create_timer(300.0).timeout.connect(func():
		print("GN_PM FAIL watchdog: gave up after 5 minutes")
		get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var root := Node3D.new()
	root.name = "PhotoMatch"
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, SCENE)
	root.free()
	EditorInterface.open_scene_from_path(SCENE)
	await _frames(10)
	GnEnvironment.set_up()
	GnEnvironment.apply("sky", "Photo: field")
	GnEnvironment.apply("heading", 0.0)

	# 1. The "site photo": looking down at the grass in front of a person
	# standing in the field, where the photographed ground really is about
	# 1.6 m below the camera. Only the panorama: Genesis's ground is hidden.
	var cam := GnCameras.save_view()
	cam.position = Vector3(0, 1.6, 0)
	cam.rotation_degrees = Vector3(-18, 200, 0)
	cam.fov = 55
	var ground := GnScene.find_role("ground") as Node3D
	ground.visible = false
	var photo_png: String = await GnRender.render(cam, Vector2i(1600, 900), EditorInterface.get_base_control(), false)
	ground.visible = true
	var photo_abs := ProjectSettings.globalize_path(photo_png)
	_check("site photo made", FileAccess.file_exists(photo_png), photo_png)

	# 2. The design: a plain 2 m block on the grass 7 m ahead, and a tree.
	var fwd := -cam.global_transform.basis.z
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	var block := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 2, 2)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.85, 0.85, 0.82)
	bm.material = white
	block.mesh = bm
	block.name = "Block"
	GnScene.add_node(block, GnScene.root(), "test block")
	block.position = flat * 7.0 + Vector3(0, 1, 0)
	var tree_path := "res://genesis_assets/trees/beech.tscn" if ResourceLoader.exists("res://genesis_assets/trees/beech.tscn") else "res://genesis_assets/trees/tree_round.glb"
	GnPlacement.place(tree_path, "trees", flat * 12.0 + Vector3(flat.z, 0, -flat.x) * 6.0)

	# 3. Photo match on, render composited.
	_check("photo attached", GnPhotomatch.set_photo(cam, photo_abs) == "", "")
	var out: String = await GnRender.render(cam, Vector2i(1600, 900), EditorInterface.get_base_control())
	var comp := Image.load_from_file(ProjectSettings.globalize_path(out))
	var photo := Image.load_from_file(photo_abs)
	# Where things are on screen, from where they are in 3D.
	var render_cam := Camera3D.new()
	var sub := SubViewport.new()
	sub.size = Vector2i(1600, 900)
	sub.add_child(render_cam)
	EditorInterface.get_base_control().add_child(sub)
	render_cam.global_transform = cam.global_transform
	render_cam.fov = cam.fov
	var sky_px := Vector2i(render_cam.unproject_position(cam.global_position + flat * 100.0 + Vector3(-flat.z, 0, flat.x) * 70.0 + Vector3(0, 4, 0)))
	sky_px = sky_px.clamp(Vector2i(4, 4), Vector2i(1595, 895))
	var block_px := Vector2i(render_cam.unproject_position(block.global_position - flat * 1.0))
	sub.queue_free()
	var sky_diff := _diff(comp.get_pixelv(sky_px), photo.get_pixelv(sky_px))
	# The block's face is flat and even; the photo there is busy trees and
	# grass. Compare how much each varies over a small patch.
	var block_diff := _spread(photo, block_px) - _spread(comp, block_px)
	print("GN_PM sky at %s diff %.3f, block at %s diff %.3f" % [sky_px, sky_diff, block_px, block_diff])
	_check("sky is the untouched photo", sky_diff < 0.06, str(sky_diff))
	_check("the design covers the photo (flat block where the photo was busy)", block_diff > 0.02, "%.3f" % block_diff)
	# A caught shadow darkens the photo without changing its colour: every
	# channel scaled by about the same factor. The block itself is not that.
	var shadowed := 0
	for y in range(block_px.y, 900, 4):
		for x in range(0, 1600, 4):
			var a := photo.get_pixel(x, y)
			var b := comp.get_pixel(x, y)
			if a.get_luminance() < 0.08 or b.get_luminance() > a.get_luminance() * 0.85:
				continue
			var k := b.get_luminance() / a.get_luminance()
			if absf(b.r - a.r * k) < 0.04 and absf(b.g - a.g * k) < 0.04 and absf(b.b - a.b * k) < 0.04:
				shadowed += 1
	print("GN_PM photo pixels darkened like a shadow: %d" % shadowed)
	_check("shadows fall on the photographed ground", shadowed > 60, str(shadowed))
	DirAccess.copy_absolute(photo_abs, ProjectSettings.globalize_path("res://renders/pm_photo.png"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/pm_composite.png"))
	print("GN_PM RESULT %s" % ("PASS" if _ok else "FAIL"))
	EditorInterface.get_base_control().get_tree().quit(0 if _ok else 1)


func _spread(img: Image, at: Vector2i) -> float:
	var lums: Array[float] = []
	for y in range(-12, 13, 3):
		for x in range(-12, 13, 3):
			lums.append(img.get_pixelv(at + Vector2i(x, y)).get_luminance())
	var mean := 0.0
	for l in lums:
		mean += l
	mean /= lums.size()
	var v := 0.0
	for l in lums:
		v += (l - mean) * (l - mean)
	return sqrt(v / lums.size())


func _diff(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_PM %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await EditorInterface.get_base_control().get_tree().process_frame
