@tool
extends RefCounted

# Site context from OpenStreetMap: look up an address, fetch the map around
# it, and build the neighbourhood as simple massing (buildings, roads, green
# space and water), the way Lumion Pro, Enscape and D5 do.
#
# OpenStreetMap data is ODbL, not CC0: renders that show it must credit
# "© OpenStreetMap contributors". The site node records that, and the dock
# says so wherever the context is used.
#
# Coordinates become metres around the address, with north as -Z and east as
# +X, the same convention as the sun.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnGeo := preload("res://addons/genesis/core/gn_geo.gd")
const Terrain := preload("res://addons/genesis/set/gn_terrain.gd")

const UA := "Genesis site context (Utopian Academy; https://github.com/Utopian-Academy)"
const ATTRIBUTION := "Map data © OpenStreetMap contributors (ODbL)"
const METRES_PER_DEG_LAT := 110540.0
const METRES_PER_DEG_LON := 111320.0

# Road widths in metres, by OpenStreetMap highway class.
const ROAD_WIDTH := {
	"motorway": 14.0, "trunk": 12.0, "primary": 10.0, "secondary": 9.0, "tertiary": 8.0,
	"residential": 6.5, "unclassified": 6.0, "service": 4.0, "living_street": 5.0,
	"footway": 2.0, "path": 1.6, "cycleway": 2.2, "pedestrian": 6.0, "steps": 2.0, "track": 3.0,
}
const ROAD_SKIP := ["proposed", "construction", "corridor", "elevator", "platform"]


# ---------------------------------------------------------------------------
# Network: an address to coordinates, coordinates to map data. `host` is any
# node in the tree, needed to run HTTPRequests.
# ---------------------------------------------------------------------------
static func geocode(address: String, host: Node) -> Dictionary:
	var url := "https://nominatim.openstreetmap.org/search?format=json&limit=1&q=" + address.uri_encode()
	var body := await _http_get(url, host)
	var parsed = JSON.parse_string(body)
	if parsed is Array and not parsed.is_empty():
		var r: Dictionary = parsed[0]
		return {"lat": float(r.lat), "lon": float(r.lon), "name": str(r.display_name)}
	return {}


# The OpenStreetMap API's map call: every node, way and relation in a box.
# Chosen over Overpass because it is the canonical service and was the one
# still answering when Overpass's main server was down (tested).
static func fetch(lat: float, lon: float, radius: float, host: Node) -> String:
	var dlat := radius / METRES_PER_DEG_LAT
	var dlon := radius / (METRES_PER_DEG_LON * cos(deg_to_rad(lat)))
	var url := "https://api.openstreetmap.org/api/0.6/map?bbox=%f,%f,%f,%f" % [lon - dlon, lat - dlat, lon + dlon, lat + dlat]
	return await _http_get(url, host)


static func _http_get(url: String, host: Node) -> String:
	# On its own thread: a busy editor (importing, rendering) polls a
	# main-thread download so rarely that the server gives up on a big map
	# mid-transfer. One retry, for a dropped connection.
	for attempt in 2:
		var req := HTTPRequest.new()
		req.timeout = 90.0
		req.use_threads = true
		host.add_child(req)
		var err := req.request(url, PackedStringArray(["User-Agent: " + UA]))
		if err != OK:
			req.queue_free()
			return ""
		var result: Array = await req.request_completed
		req.queue_free()
		if result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200:
			return (result[3] as PackedByteArray).get_string_from_utf8()
		if result[1] >= 400:
			break  # the server said no; asking again won't change that
	return ""


# ---------------------------------------------------------------------------
# Parsing: OSM XML into ways with tags and point lists (metres).
# ---------------------------------------------------------------------------
class Feature:
	var tags: Dictionary
	var points: PackedVector2Array  # x east, y south (becomes +Z)
	var id: String


static func parse(xml: String, lat0: float, lon0: float) -> Array:
	var p := XMLParser.new()
	if p.open_buffer(xml.to_utf8_buffer()) != OK:
		return []
	var kx := METRES_PER_DEG_LON * cos(deg_to_rad(lat0))
	var nodes := {}
	var ways := {}
	var way_order: Array = []
	var relations: Array = []
	var cur: Dictionary = {}
	var kind := ""
	while p.read() == OK:
		if p.get_node_type() == XMLParser.NODE_ELEMENT:
			var n := p.get_node_name()
			if n == "node":
				var la := float(p.get_named_attribute_value_safe("lat"))
				var lo := float(p.get_named_attribute_value_safe("lon"))
				# x east; y is south, so north lands on -Z like the sun expects.
				nodes[p.get_named_attribute_value_safe("id")] = Vector2((lo - lon0) * kx, -(la - lat0) * METRES_PER_DEG_LAT)
			elif n == "way" or n == "relation":
				kind = n
				cur = {"id": p.get_named_attribute_value_safe("id"), "tags": {}, "nds": [], "members": []}
				if n == "way":
					ways[cur.id] = cur
					way_order.append(cur.id)
				else:
					relations.append(cur)
			elif n == "nd" and kind == "way":
				cur.nds.append(p.get_named_attribute_value_safe("ref"))
			elif n == "member" and kind == "relation" and p.get_named_attribute_value_safe("type") == "way":
				cur.members.append([p.get_named_attribute_value_safe("ref"), p.get_named_attribute_value_safe("role")])
			elif n == "tag" and not cur.is_empty():
				cur.tags[p.get_named_attribute_value_safe("k")] = p.get_named_attribute_value_safe("v")
	var out: Array = []
	for id in way_order:
		var w: Dictionary = ways[id]
		var pts := PackedVector2Array()
		for r in w.nds:
			if nodes.has(r):
				pts.append(nodes[r])
		if pts.size() >= 2:
			var f := Feature.new()
			f.id = id
			f.tags = w.tags
			f.points = pts
			out.append(f)
	# Multipolygon relations (a river is usually one): stitch outer ways into
	# closed rings and give them the relation's tags.
	for rel in relations:
		if rel.tags.get("type", "") != "multipolygon":
			continue
		var pieces: Array = []
		for m in rel.members:
			if m[1] == "outer" and ways.has(m[0]):
				var pts := PackedVector2Array()
				for r in ways[m[0]].nds:
					if nodes.has(r):
						pts.append(nodes[r])
				if pts.size() >= 2:
					pieces.append(pts)
		for ring in _stitch(pieces):
			var f := Feature.new()
			f.id = "r" + str(rel.id)
			f.tags = rel.tags
			f.points = ring
			out.append(f)
	return out


# Joins open way pieces end to end into rings. Pieces cut off at the edge
# of the downloaded box stay open and are closed straight across.
static func _stitch(pieces: Array) -> Array:
	var rings: Array = []
	var left := pieces.duplicate()
	while not left.is_empty():
		var ring: PackedVector2Array = left.pop_back()
		var grew := true
		while grew and ring[0].distance_to(ring[-1]) > 0.01:
			grew = false
			for i in left.size():
				var p: PackedVector2Array = left[i]
				if p[0].distance_to(ring[-1]) < 0.01:
					ring.append_array(p.slice(1))
				elif p[-1].distance_to(ring[-1]) < 0.01:
					var r := p.duplicate()
					r.reverse()
					ring.append_array(r.slice(1))
				else:
					continue
				left.remove_at(i)
				grew = true
				break
		rings.append(ring)
	return rings


# The whole job: address -> map -> massing, and the sun moved to the place.
# `status` gets progress messages. Returns counts, or {"error": ...}.
## `ground`: the real lie of the land under the site (hills, slopes);
## `photo`: an aerial photograph laid over it.
static func bring_in(address: String, radius: float, host: Node, status: Callable, ground := true, photo := true) -> Dictionary:
	status.call("Finding %s…" % address)
	var at := await geocode(address, host)
	if at.is_empty():
		return {"error": "Couldn't find \"%s\" on OpenStreetMap." % address}
	status.call("Downloading the map around %s…" % str(at.name).get_slice(",", 0))
	var xml := await fetch(at.lat, at.lon, radius, host)
	if xml == "":
		return {"error": "OpenStreetMap didn't answer. Check the internet connection and try again."}
	var features := parse(xml, at.lat, at.lon)
	# A river or lake is one huge multipolygon; the box only holds fragments
	# of its outline. Fetch its whole outline and clip it to the site.
	var partial := {}
	for f in features:
		if f.id.begins_with("r") and _is_water(f.tags):
			partial[f.id] = true
	var clipped: Array = []
	var box := PackedVector2Array([Vector2(-radius, -radius), Vector2(radius, -radius), Vector2(radius, radius), Vector2(-radius, radius)])
	for rid in partial.keys().slice(0, 3):
		status.call("Fetching the whole outline of the water nearby…")
		var full := await _http_get("https://api.openstreetmap.org/api/0.6/relation/%s/full" % rid.substr(1), host)
		for f in parse(full, at.lat, at.lon):
			if f.id != rid:
				continue
			for piece in Geometry2D.intersect_polygons(f.points, box):
				var g := Feature.new()
				g.id = rid
				g.tags = f.tags
				g.points = piece
				clipped.append(g)
	features = features.filter(func(f): return not partial.has(f.id))
	features.append_array(clipped)
	# The ground itself: its shape, and what it looks like from above.
	var terrain: Node3D = null
	var notes: Array = []
	var attribution: Array = [ATTRIBUTION]
	var info_photo := {}
	var counts_extra := {}
	if ground or photo:
		var size := radius * 2.0
		var cells := clampi(int(size / 2.5), 64, 256)
		var heights := PackedFloat32Array()
		heights.resize((cells + 1) * (cells + 1))
		var relief := 0.0
		var hilly := false
		if ground:
			status.call("Fetching the lie of the land…")
			var elev: Dictionary = await GnGeo.elevation(at.lat, at.lon, size, cells, host)
			if elev.has("error"):
				notes.append("No elevation: %s" % elev.error)
			else:
				relief = elev.relief
				if not elev.flat:
					heights = elev.heights
					hilly = true
					attribution.append(elev.attribution)
				else:
					notes.append("The site is flat (%.0f m of relief)." % relief)
		var mat: Material = null
		if photo:
			status.call("Fetching the aerial photograph…")
			var pic: Dictionary = await GnGeo.imagery(at.lat, at.lon, size, str(at.name).get_slice(",", 0), host)
			if pic.has("error"):
				notes.append("No aerial photograph: %s" % pic.error)
			else:
				mat = GnGeo.imagery_material(pic.texture)
				attribution.append(pic.attribution)
				info_photo = pic
		if hilly or mat != null:
			var t := Terrain.new()
			t.name = "Ground"
			t.size = size
			t.cells = cells
			t.heights = heights
			if mat:
				t.material = mat
			t.set_meta(GnScene.ROLE, "terrain")
			terrain = t
		counts_extra = {"relief_m": relief, "hilly": hilly, "photo": mat != null}
	status.call("Building the neighbourhood…")
	var counts := build(features, {"lat": at.lat, "lon": at.lon, "address": address, "terrain": terrain,
		"attribution": "; ".join(attribution), "photo": info_photo})
	counts.merge(counts_extra)
	counts["notes"] = notes
	# The sun follows the site: real position for this place, local time zone
	# approximated from longitude (the user can correct it for daylight saving).
	var GnEnvironment = load("res://addons/genesis/core/gn_environment.gd")
	if GnEnvironment.is_set_up():
		GnEnvironment.apply("latitude", at.lat)
		GnEnvironment.apply("longitude", at.lon)
		GnEnvironment.apply("utc_offset", float(roundi(at.lon / 15.0)))
		GnEnvironment.apply("real_sun", true)
	counts["name"] = at.name
	return counts


# ---------------------------------------------------------------------------
# Building the scene.
# ---------------------------------------------------------------------------
static func height_of(tags: Dictionary) -> float:
	if tags.has("height"):
		var h := str(tags.height).to_float()
		if h > 0.0:
			return h
	if tags.has("building:levels"):
		var lv := str(tags["building:levels"]).to_float()
		if lv > 0.0:
			return lv * 3.1 + 1.0
	match str(tags.get("building", "yes")):
		"garage", "garages", "shed", "hut", "kiosk", "roof", "carport":
			return 3.0
		"house", "terrace", "semidetached_house", "detached", "residential":
			return 9.0
		"apartments":
			return 15.0
		"commercial", "retail", "office":
			return 12.0
		"church", "cathedral":
			return 18.0
		"industrial", "warehouse":
			return 8.0
	return 8.0


# Builds the whole context under one "Site context" node and adds it as one
# undo step. Returns a short summary for the dock.
static func build(features: Array, info: Dictionary) -> Dictionary:
	var root := GnScene.root()
	var site := Node3D.new()
	site.name = "Site context"
	site.set_meta(GnScene.ROLE, "site")
	site.set_meta(&"gn_site", {"lat": info.lat, "lon": info.lon, "address": info.get("address", ""),
		"attribution": info.get("attribution", ATTRIBUTION)})
	# On real ground everything sits on it: buildings on their lowest corner,
	# roads, paths and water laid over its shape.
	var terrain: Node3D = info.get("terrain")
	var photo: Dictionary = info.get("photo", {})
	var h := func(x: float, z: float) -> float: return _ground(terrain, x, z)
	# A sharp photograph shows the parks, beaches and roads better than we can
	# draw them; a coarse one still wants the roads.
	var draw_areas := photo.is_empty()
	var draw_roads := photo.is_empty() or float(photo.get("metres_per_pixel", 10.0)) > 2.0
	var massing := StandardMaterial3D.new()
	massing.albedo_color = Color(0.86, 0.85, 0.82)
	massing.roughness = 0.9
	var plot_mat := massing.duplicate() as StandardMaterial3D
	plot_mat.albedo_color = Color(0.95, 0.72, 0.45)
	var road_mat := _preset_or("res://genesis_data/materials/asphalt.tres", Color(0.18, 0.18, 0.19))
	var path_mat := _preset_or("res://genesis_data/materials/paving.tres", Color(0.55, 0.53, 0.5))
	var green_mat := _preset_or("res://genesis_data/materials/grass.tres", Color(0.3, 0.42, 0.2))
	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.86, 0.8, 0.66)
	sand_mat.roughness = 0.95
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.1, 0.16, 0.18)
	water_mat.roughness = 0.05
	water_mat.metallic_specular = 1.0

	var roads := SurfaceTool.new()
	roads.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paths := SurfaceTool.new()
	paths.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := SurfaceTool.new()
	green.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sand := SurfaceTool.new()
	sand.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var counts := {"buildings": 0, "roads": 0, "green": 0, "water": 0, "beach": 0}
	# The plot: the building whose footprint contains the address, or the
	# nearest to it.
	var plot_id := ""
	var plot_d := INF
	for f in features:
		if f.tags.has("building") and f.points.size() >= 3:
			if Geometry2D.is_point_in_polygon(Vector2.ZERO, f.points):
				plot_id = f.id
				plot_d = 0.0
				break
			var c := Vector2.ZERO
			for pt in f.points:
				c += pt
			c /= f.points.size()
			if c.length() < plot_d:
				plot_d = c.length()
				plot_id = f.id
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	site.add_child(buildings)
	for f in features:
		var t: Dictionary = f.tags
		if t.has("building") and f.points.size() >= 4:
			var mi := _building(f, height_of(t), plot_mat if f.id == plot_id else massing)
			if mi and terrain:
				var low := INF
				for q in f.points:
					low = minf(low, h.call(q.x, q.y))
				mi.position.y = low
			if mi:
				mi.name = "Plot" if f.id == plot_id else ("Building %s" % t.get("addr:housenumber", f.id))
				if f.id == plot_id:
					mi.set_meta(&"gn_plot", true)
				buildings.add_child(mi)
				counts.buildings += 1
		elif t.has("highway") and str(t.highway) not in ROAD_SKIP and draw_roads:
			var w: float = ROAD_WIDTH.get(str(t.highway), 4.0)
			var foot := str(t.highway) in ["footway", "path", "cycleway", "steps", "pedestrian"]
			_ribbon(paths if foot else roads, f.points, w, 0.03 if foot else 0.02)
			counts.roads += 1
		elif t.get("natural", "") in ["beach", "sand"] and draw_areas:
			if _area(sand, f.points, 0.012):
				counts.beach += 1
		elif _is_water(t):
			if _area(water, f.points, 0.015):
				counts.water += 1
		elif draw_areas and (t.get("leisure", "") in ["park", "garden", "pitch", "playground", "recreation_ground"] \
				or t.get("landuse", "") in ["grass", "meadow", "village_green", "recreation_ground"]):
			if _area(green, f.points, 0.01):
				counts.green += 1
	for pair in [[roads, road_mat, "Roads"], [paths, path_mat, "Footpaths"], [green, green_mat, "Green"],
			[sand, sand_mat, "Beach"], [water, water_mat, "Water"]]:
		var st: SurfaceTool = pair[0]
		var arrays := st.commit_to_arrays()
		# A layer with nothing in it (no parks nearby, say) commits empty.
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		if terrain:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i].y += h.call(verts[i].x, verts[i].z) + 0.05
			arrays[Mesh.ARRAY_VERTEX] = verts
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = pair[2]
		mi.mesh = mesh
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		site.add_child(mi)
	if terrain:
		site.add_child(terrain)
		site.move_child(terrain, 0)
		# The flat world ground goes below the site's lowest point, so hills
		# rise out of it and valleys are not flooded by it.
		var flat := GnScene.find_role("ground") as Node3D
		if flat:
			var low := 0.0
			for v in (terrain.get("heights") as PackedFloat32Array):
				low = minf(low, v)
			flat.position.y = low - 0.05
	GnScene.add_node(site, root, "Genesis: site context")
	return counts


# The ground's height at a point of the site (0 where there is no terrain).
static func _ground(terrain: Node3D, x: float, z: float) -> float:
	if terrain == null:
		return 0.0
	var size: float = terrain.get("size")
	var cells: int = terrain.get("cells")
	var heights: PackedFloat32Array = terrain.get("heights")
	var step := size / cells
	var fx := clampf((x + size * 0.5) / step, 0.0, cells - 0.001)
	var fz := clampf((z + size * 0.5) / step, 0.0, cells - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var a := heights[iz * (cells + 1) + ix]
	var b := heights[iz * (cells + 1) + ix + 1]
	var c := heights[(iz + 1) * (cells + 1) + ix]
	var d := heights[(iz + 1) * (cells + 1) + ix + 1]
	return lerpf(lerpf(a, b, fx - ix), lerpf(c, d, fx - ix), fz - iz)


static func _is_water(t: Dictionary) -> bool:
	return t.get("natural", "") == "water" or t.has("water") or t.get("waterway", "") == "riverbank"


# Godot treats clockwise triangles as front-facing. Emits a triangle wound
# so that its front faces along `n`, whatever order the points came in.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x, v.z) * 0.5)
		st.add_vertex(v)


static func _preset_or(path: String, fallback: Color) -> Material:
	if ResourceLoader.exists(path):
		return load(path)
	var m := StandardMaterial3D.new()
	m.albedo_color = fallback
	m.roughness = 0.9
	return m


# An extruded footprint: walls plus a flat roof, as one mesh.
static func _building(f: Feature, height: float, mat: Material) -> MeshInstance3D:
	var ring := f.points
	if ring[0].distance_to(ring[-1]) < 0.01:
		ring = ring.slice(0, ring.size() - 1)
	if ring.size() < 3:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(ring)
	if tris.is_empty():
		return null
	for i in range(0, tris.size(), 3):
		var p := [ring[tris[i]], ring[tris[i + 1]], ring[tris[i + 2]]]
		_tri(st, Vector3(p[0].x, height, p[0].y), Vector3(p[1].x, height, p[1].y), Vector3(p[2].x, height, p[2].y), Vector3.UP)
	# Walls face away from the footprint's middle.
	var mid := Vector2.ZERO
	for q in ring:
		mid += q
	mid /= ring.size()
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var n := Vector3(b.y - a.y, 0, -(b.x - a.x)).normalized()
		var edge_mid := (a + b) * 0.5
		if Vector2(n.x, n.z).dot(edge_mid - mid) < 0.0:
			n = -n
		var a0 := Vector3(a.x, 0, a.y)
		var b0 := Vector3(b.x, 0, b.y)
		var a1 := Vector3(a.x, height, a.y)
		var b1 := Vector3(b.x, height, b.y)
		_tri(st, a0, b0, b1, n)
		_tri(st, a0, b1, a1, n)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	# Double-sided: footprints wind either way and a wall must never vanish.
	(mi.material_override as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	return mi


# A road: the centreline widened to a flat strip.
static func _ribbon(st: SurfaceTool, pts: PackedVector2Array, width: float, y: float) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		var side := Vector2(-d.y, d.x) * width * 0.5
		var v := [a - side, b - side, b + side, a + side]
		var p := v.map(func(q): return Vector3(q.x, y, q.y))
		_tri(st, p[0], p[1], p[2], Vector3.UP)
		_tri(st, p[0], p[2], p[3], Vector3.UP)


# A flat area (park, water) from a closed ring. False if it would not triangulate.
static func _area(st: SurfaceTool, pts: PackedVector2Array, y: float) -> bool:
	var ring := pts
	if ring.size() > 2 and ring[0].distance_to(ring[-1]) < 0.01:
		ring = ring.slice(0, ring.size() - 1)
	if ring.size() < 3:
		return false
	var tris := Geometry2D.triangulate_polygon(ring)
	if tris.is_empty():
		return false
	for i in range(0, tris.size(), 3):
		var p := [ring[tris[i]], ring[tris[i + 1]], ring[tris[i + 2]]]
		_tri(st, Vector3(p[0].x, y, p[0].y), Vector3(p[1].x, y, p[1].y), Vector3(p[2].x, y, p[2].y), Vector3.UP)
	return true
