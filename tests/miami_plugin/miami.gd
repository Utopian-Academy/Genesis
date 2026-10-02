@tool
extends EditorPlugin

# Demo: an LED wall concert on the rooftop of the 1 Hotel South Beach, Miami
# Beach, during Art Basel week. The neighbourhood comes from OpenStreetMap,
# the ocean is placed at the mapped coastline, and the sun is Miami's real sun
# on 5 December. The hotel's height is in neither OpenStreetMap nor Wikidata,
# so it is set to an estimated 55 m (about 17 floors) for the demo.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnSite := preload("res://addons/genesis/core/gn_site.gd")
const GnSun := preload("res://addons/genesis/core/gn_sun.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnLook := preload("res://addons/genesis/core/gn_look.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const LedWall := preload("res://addons/genesis/set/gn_led_wall.gd")
const Truss := preload("res://addons/genesis/set/gn_truss.gd")
const StageDeck := preload("res://addons/genesis/set/gn_stage_deck.gd")
const Fixture := preload("res://addons/genesis/set/gn_light_fixture.gd")
const WaterBody := preload("res://addons/genesis/set/gn_water_body.gd")
const GnContent := preload("res://addons/genesis/core/gn_content.gd")

const HOTEL_HEIGHT := 55.0
const LAT := 25.7991312
const LON := -80.1273159
var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(900.0).timeout.connect(func(): print("GN_MIAMI FAIL watchdog"); get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var r0 := Node3D.new()
	r0.name = "MiamiRooftop"
	var packed := PackedScene.new()
	packed.pack(r0)
	ResourceSaver.save(packed, "res://scenes/miami_rooftop.tscn")
	r0.free()
	EditorInterface.open_scene_from_path("res://scenes/miami_rooftop.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	var host := get_editor_interface().get_base_control()
	var root := GnScene.root()

	# 1. Miami Beach from OpenStreetMap.
	var counts: Dictionary = await GnSite.bring_in("1 Hotel South Beach, Miami Beach", 260.0, host, func(m): print("GN_MIAMI ", m), true, false)
	_check("neighbourhood arrived", not counts.has("error") and counts.get("buildings", 0) > 20, str(counts))
	if counts.has("error"):
		_finish()
		return
	var hotel: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if n.has_meta(&"gn_plot"):
			hotel = n
	_check("the hotel is the plot", hotel != null, "")
	if hotel == null:
		_finish()
		return
	# Height: estimated (OSM has none); the massing arrives at a default height.
	hotel.scale.y = HOTEL_HEIGHT / hotel.get_aabb().size.y
	hotel.name = "Hotel (height estimated %d m)" % int(HOTEL_HEIGHT)
	# A showpiece, not a site study: the hotel in the same white as its
	# neighbours rather than the orange "your plot" marker.
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.89, 0.86)
	white.roughness = 0.85
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	hotel.material_override = white
	var roof: AABB = hotel.global_transform * hotel.get_aabb()
	print("GN_MIAMI roof: centre %s, %.0f x %.0f m at %.0f m" % [roof.get_center(), roof.size.x, roof.size.z, roof.end.y])

	# 2. The Atlantic, at the mapped coastline.
	var xml: String = await GnSite.fetch(LAT, LON, 400.0, host)
	var coast_x := 150.0
	var xs: Array = []
	# Several coastlines run past the hotel (Indian Creek, just west of Collins
	# Avenue, is one). The Atlantic shore is the easternmost.
	var best_mean := -INF
	var features := GnSite.parse(xml, LAT, LON)
	for f in features:
		if f.tags.get("natural", "") == "coastline":
			var near: Array = []
			for p in f.points:
				if absf(p.y) < 200.0:
					near.append(p.x)
			if near.is_empty():
				continue
			var mean := 0.0
			for x in near:
				mean += x
			mean /= near.size()
			if mean > best_mean:
				best_mean = mean
				xs = near
	if not xs.is_empty():
		xs.sort()
		coast_x = xs[xs.size() / 2]
	print("GN_MIAMI coastline %.0f m east of the hotel" % coast_x)
	var ground := GnScene.find_role("ground") as MeshInstance3D
	# Land ends at the shore: the flat ground stops there, the ocean begins.
	ground.position.x = coast_x - 200.0
	var sea := WaterBody.new()
	sea.kind = "Ocean"
	sea.name = "Atlantic"
	GnScene.add_node(sea, root, "ocean", "water")
	sea.position = Vector3(coast_x + 2000.0, -0.05, 0)

	# 3. The rooftop concert: the stage faces west over the pool deck, the
	# LED wall's back to the ocean.
	var top := roof.end.y
	var spot := _clear_spot(features, roof)
	print("GN_MIAMI stage at %s" % spot)
	var rig := Node3D.new()
	rig.name = "Rooftop concert"
	GnScene.add_node(rig, root, "rig", "stage")
	rig.position = Vector3(spot.x, top, spot.y)
	rig.rotation_degrees.y = -90.0
	var deck := StageDeck.new()
	deck.width = 10
	deck.depth = 5
	deck.height = 0.6
	deck.name = "Stage"
	rig.add_child(deck)
	var wall := LedWall.new()
	wall.panel = "2.6 mm indoor (500 × 500)"
	wall.columns = 18
	wall.rows = 8
	wall.curve_degrees = 18
	wall.bottom = 0.9
	wall.brightness = 1.6
	wall.content = GnContent.concert_visual()
	wall.position = Vector3(0, 0, -2.6)
	wall.name = "LED wall"
	rig.add_child(wall)
	for x in [-6.5, 6.5]:
		var tower := Truss.new()
		tower.length = 6.5
		tower.rotation_degrees = Vector3(0, 0, 90)
		tower.position = Vector3(x, 0, 1.8)
		tower.name = "Truss tower left" if x < 0 else "Truss tower right"
		rig.add_child(tower)
	var span := Truss.new()
	span.length = 13.29
	span.position = Vector3(-6.645, 6.5, 1.8)
	span.name = "Truss span"
	rig.add_child(span)
	for i in 8:
		var f := Fixture.new()
		f.lumens = 17000
		f.beam_degrees = 5
		f.colour = [Color(0.2, 0.55, 1.0), Color(1.0, 0.25, 0.75), Color(1.0, 0.8, 0.3)][i % 3]
		f.pan = 180
		f.tilt = -40
		f.rotation_degrees = Vector3(0, 0, (i - 3.5) * 7.0)
		f.position = Vector3(-5.6 + i * 1.6, 6.1, 1.8)
		f.name = "Beam %d" % (i + 1)
		rig.add_child(f)
	for x in [-3.0, 3.0]:
		var wash := Fixture.new()
		wash.kind = "Wash"
		wash.lumens = 9000
		wash.beam_degrees = 35
		wash.colour = Color(0.6, 0.3, 1.0)
		wash.tilt = 60
		wash.position = Vector3(x, 0.7, 1.6)
		wash.name = "Wash left" if x < 0 else "Wash right"
		rig.add_child(wash)
	var pool := WaterBody.new()
	pool.kind = "Pool"
	pool.width = 16
	pool.length = 5
	pool.name = "Rooftop pool"
	GnScene.add_node(pool, root, "pool", "water")
	pool.position = Vector3(spot.x - 12.0, top + 0.05, spot.y + 14.0)
	var shrub := "res://genesis_assets/plants/round_shrub.tscn" if ResourceLoader.exists("res://genesis_assets/plants/round_shrub.tscn") else "res://genesis_assets/plants/shrub_round.glb"
	for i in 7:
		GnPlacement.place(shrub, "plants", Vector3(spot.x - 22.0 + i * 2.2, top, spot.y - 11.0))

	# 4. Miami, 5 December (Art Basel week).
	GnEnvironment.apply("sky", "Clear")
	GnEnvironment.apply("latitude", 25.799)
	GnEnvironment.apply("longitude", -80.127)
	GnEnvironment.apply("utc_offset", -5.0)
	GnEnvironment.apply("day_of_year", GnSun.day_of_year(12, 5))
	GnEnvironment.apply("real_sun", true)
	GnEnvironment.apply("cloudiness", 0.35)

	await _frames(20)
	var aerial := GnCameras.save_view()
	aerial.name = "Aerial"
	aerial.position = rig.position + Vector3(-48, 30, 42)
	aerial.look_at(rig.position + Vector3(8, 2, 0))
	aerial.fov = 40
	var crowd := GnCameras.save_view()
	crowd.name = "Rooftop"
	crowd.position = rig.global_position + rig.global_transform.basis.z * 16.0 + Vector3(0, 1.7, 0)
	crowd.look_at(rig.global_position + Vector3(0, 3.5, 0))
	crowd.fov = 62

	GnEnvironment.apply("time_of_day", 16.85)  # golden hour; sunset is about 17:30
	GnEnvironment.apply("haze", 0.35)
	GnLook.apply_preset(aerial, GnLook.PRESETS["Warm afternoon"])
	await _shot(aerial, "miami_aerial_dusk", host)
	GnLook.apply_preset(crowd, {"bloom": 0.35, "contrast": 1.08, "warmth": 0.25, "vignette": 0.35})
	await _shot(crowd, "miami_rooftop_dusk", host)
	GnEnvironment.apply("time_of_day", 20.5)
	GnEnvironment.apply("haze", 0.7)
	GnEnvironment.apply("ambient", 0.35)
	GnLook.apply_preset(crowd, {"bloom": 0.55, "contrast": 1.1, "vignette": 0.4})
	await _shot(crowd, "miami_rooftop_night", host)
	GnLook.apply_preset(aerial, {"bloom": 0.45, "contrast": 1.08})
	await _shot(aerial, "miami_aerial_night", host)
	# Parts built in code belong to the scene too, so the saved demo has them.
	_own(root, root)
	EditorInterface.save_scene()
	_finish()


# Sets the scene as owner of everything added by hand under node, leaving
# alone what a node builds for itself and the insides of placed models.
func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		if c.has_meta(&"gn_generated"):
			continue
		if c.owner == null:
			c.owner = root
		if c.scene_file_path == "":
			_own(c, root)


# The hotel is a complex of wings, not a rectangle, so its bounding box
# centre can be thin air. Find a spot where the stage, the audience in front
# of it (west) and the pool all stand on the roof: a box that clipping
# against the footprint leaves nothing of.
func _clear_spot(features: Array, roof: AABB) -> Vector2:
	var outline := PackedVector2Array()
	for f in features:
		if str(f.tags.get("name", "")).begins_with("1 Hotel"):
			outline = f.points
	var fallback := Vector2(roof.get_center().x, roof.get_center().z)
	if outline.size() < 3:
		return fallback
	# Line the parsed outline up with the built massing (their origins can
	# differ by a geocoding hair).
	var lo := outline[0]
	var hi := outline[0]
	for p in outline:
		lo = lo.min(p)
		hi = hi.max(p)
	var shift := fallback - (lo + hi) * 0.5
	for i in outline.size():
		outline[i] += shift
	var best := fallback
	var best_margin := -1.0
	var x := roof.position.x
	while x < roof.end.x:
		var z := roof.position.z
		while z < roof.end.z:
			# Stage deck and wall to +6 m east, audience and pool to 26 m west.
			var box := PackedVector2Array([Vector2(x - 26, z - 12), Vector2(x + 6, z - 12), Vector2(x + 6, z + 18), Vector2(x - 26, z + 18)])
			if Geometry2D.clip_polygons(box, outline).is_empty():
				var margin := INF
				for i in outline.size():
					margin = minf(margin, Vector2(x, z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(x, z), outline[i], outline[(i + 1) % outline.size()])))
				if margin > best_margin:
					best_margin = margin
					best = Vector2(x, z)
			z += 2.0
		x += 2.0
	_check("the stage has roof to stand on", best_margin > 0.0, "no clear spot on the footprint")
	return best


func _shot(cam: Camera3D, label: String, host: Node) -> void:
	var out: String = await GnRender.render(cam, Vector2i(1920, 1080), host)
	_check("%s rendered" % label, out != "", "")
	if out != "":
		DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/%s.png" % label))


func _finish() -> void:
	print("GN_MIAMI RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_MIAMI %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
