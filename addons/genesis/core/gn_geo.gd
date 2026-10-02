@tool
extends RefCounted

# The real ground under a site: its elevation, and a photograph of it from
# above, from open data anyone may use.
#
#   Elevation  Mapzen Terrain Tiles on AWS Open Data (SRTM, ETOPO1, GMTED,
#              EU-DEM, USGS 3DEP and others), global.
#   Imagery    USGS The National Map orthoimagery (public domain), about two
#              metres a pixel, where it exists (the United States); elsewhere
#              Sentinel-2 cloudless 2016 by EOX (CC BY 4.0), ten metres a
#              pixel, global.
#
# Everything is placed in the site's own frame (gn_site.gd): x east and z
# south in metres from the site's centre, heights above the centre's ground.

const TERRAIN_URL := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"   # z, x, y
const USGS_URL := "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/%d/%d/%d"   # z, y, x
const S2_URL := "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/g/%d/%d/%d.jpg"   # z, y, x
const ATTR_TERRAIN := "Elevation: Mapzen Terrain Tiles on AWS Open Data (SRTM, GMTED, ETOPO1, EU-DEM, USGS 3DEP and others)"
const ATTR_USGS := "Imagery: USGS The National Map (public domain)"
const ATTR_S2 := "Imagery: Sentinel-2 cloudless 2016 by EOX IT Services GmbH (contains modified Copernicus Sentinel data 2016), CC BY 4.0"
const UA := "Genesis site context (Utopian Academy)"
const METRES_PER_DEG_LAT := 110540.0
const METRES_PER_DEG_LON := 111320.0
const EARTH := 40075016.686
# Less relief than this across a site is the data's own noise (and in some
# sources, rooftops): the site is flat.
const FLAT_BELOW_M := 6.0
const IMAGERY_DIR := "res://genesis_data/sites"


## Elevation for a square `size` metres across centred on lat/lon, sampled on
## a (cells + 1)² grid, row by row from the north-west. Heights are relative
## to the centre's ground. {"heights", "relief", "flat", "attribution"} or
## {"error"}.
static func elevation(lat: float, lon: float, size: float, cells: int, host: Node) -> Dictionary:
	var target := size / cells
	var z := clampi(roundi(log(EARTH * cos(deg_to_rad(lat)) / (256.0 * target)) / log(2.0)), 8, 15)
	var mosaic: Dictionary = await _mosaic(TERRAIN_URL, false, lat, lon, size * 0.5 + target * 2.0, z, host)
	if mosaic.has("error"):
		return mosaic
	var img: Image = mosaic.image
	# Terrarium: height = R * 256 + G + B / 256 - 32768 metres.
	var w := img.get_width()
	var h := img.get_height()
	var metres := PackedFloat32Array()
	metres.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			metres[y * w + x] = c.r8 * 256.0 + c.g8 + c.b8 / 256.0 - 32768.0
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	var half := size * 0.5
	var step := size / cells
	var lo := INF
	var hi := -INF
	for iz in cells + 1:
		for ix in cells + 1:
			var px := _local_to_mosaic(Vector2(ix * step - half, iz * step - half), lat, lon, z, mosaic.origin)
			var v := _bilinear(metres, w, h, px)
			heights[iz * (cells + 1) + ix] = v
			lo = minf(lo, v)
			hi = maxf(hi, v)
	var centre := _bilinear(metres, w, h, _local_to_mosaic(Vector2.ZERO, lat, lon, z, mosaic.origin))
	for i in heights.size():
		heights[i] -= centre
	return {"heights": heights, "relief": hi - lo, "flat": hi - lo < FLAT_BELOW_M, "centre_m": centre,
		"attribution": ATTR_TERRAIN}


## A photograph from above of the same square, as a texture saved in the
## project. {"texture", "path", "attribution", "metres_per_pixel"} or {"error"}.
static func imagery(lat: float, lon: float, size: float, name: String, host: Node) -> Dictionary:
	var half := size * 0.5
	var mosaic: Dictionary = {}
	var attribution := ATTR_USGS
	# The best there is: USGS, about two metres a pixel (its tiles stop at
	# zoom 16), inside the US.
	var z := clampi(roundi(log(EARTH * cos(deg_to_rad(lat)) / (256.0 * maxf(size / 4096.0, 0.6))) / log(2.0)), 10, 16)
	mosaic = await _mosaic(USGS_URL, true, lat, lon, half, z, host)
	if mosaic.has("error"):
		# Sentinel-2 has real detail only to zoom 14.
		z = mini(z, 14)
		attribution = ATTR_S2
		mosaic = await _mosaic(S2_URL, true, lat, lon, half, z, host)
		if mosaic.has("error"):
			return mosaic
	var img: Image = mosaic.image
	# Crop the stitched tiles to the square exactly.
	var a := _local_to_mosaic(Vector2(-half, -half), lat, lon, z, mosaic.origin)
	var b := _local_to_mosaic(Vector2(half, half), lat, lon, z, mosaic.origin)
	var rect := Rect2i(Vector2i(a.floor()), Vector2i((b - a).ceil())).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	img = img.get_region(rect)
	if img.get_width() > 4096 or img.get_height() > 4096:
		img.resize(mini(img.get_width(), 4096), mini(img.get_height(), 4096), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var tex := PortableCompressedTexture2D.new()
	tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, false, 0.85)
	DirAccess.make_dir_recursive_absolute(IMAGERY_DIR)
	var path := "%s/%s_imagery.res" % [IMAGERY_DIR, name.validate_filename().to_lower().replace(" ", "_").left(60)]
	ResourceSaver.save(tex, path)
	return {"texture": load(path), "path": path, "attribution": attribution,
		"metres_per_pixel": size / float(img.get_width())}


## A terrain material showing the imagery (its UV2 runs 0-1 across the terrain).
static func imagery_material(tex: Texture2D) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D imagery : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
void fragment() {
	ALBEDO = texture(imagery, UV2).rgb;
	ROUGHNESS = 0.95;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("imagery", tex)
	return m


# ---------------------------------------------------------------------------
# Web Mercator tiles
# ---------------------------------------------------------------------------

# A point in the site's frame to a pixel of a mosaic at zoom z whose top-left
# tile pixel is `origin` (global pixel coordinates).
static func _local_to_mosaic(p: Vector2, lat0: float, lon0: float, z: int, origin: Vector2) -> Vector2:
	var lat := lat0 - p.y / METRES_PER_DEG_LAT
	var lon := lon0 + p.x / (METRES_PER_DEG_LON * cos(deg_to_rad(lat0)))
	return _global_px(lat, lon, z) - origin


static func _global_px(lat: float, lon: float, z: int) -> Vector2:
	var n := 256.0 * pow(2.0, z)
	var x := (lon + 180.0) / 360.0 * n
	var s := sin(deg_to_rad(clampf(lat, -85.05, 85.05)))
	var y := (0.5 - log((1.0 + s) / (1.0 - s)) / (4.0 * PI)) * n
	return Vector2(x, y)


# Downloads and stitches the tiles covering `half` metres round the centre.
static func _mosaic(url: String, zyx: bool, lat: float, lon: float, half: float, z: int, host: Node) -> Dictionary:
	var a := _global_px(lat + half / METRES_PER_DEG_LAT, lon - half / (METRES_PER_DEG_LON * cos(deg_to_rad(lat))), z)
	var b := _global_px(lat - half / METRES_PER_DEG_LAT, lon + half / (METRES_PER_DEG_LON * cos(deg_to_rad(lat))), z)
	var t0 := Vector2i(floori(a.x / 256.0), floori(a.y / 256.0))
	var t1 := Vector2i(floori(b.x / 256.0), floori(b.y / 256.0))
	var nx := t1.x - t0.x + 1
	var ny := t1.y - t0.y + 1
	if nx * ny > 400:
		return {"error": "That area is too big to download at this detail."}
	var img := Image.create(nx * 256, ny * 256, false, Image.FORMAT_RGB8)
	var got := 0
	var jobs: Array = []
	for ty in range(t0.y, t1.y + 1):
		for tx in range(t0.x, t1.x + 1):
			jobs.append(Vector2i(tx, ty))
	# A few at a time: quick, and polite to the servers.
	var i := 0
	while i < jobs.size():
		var batch := jobs.slice(i, i + 6)
		var waits: Array = []
		for t in batch:
			var u := url % ([z, t.y, t.x] if zyx else [z, t.x, t.y])
			waits.append(_get_bytes(u, host))
		for k in batch.size():
			var fetch: Fetch = waits[k]
			if not fetch.finished:
				await fetch.done
			var bytes := fetch.bytes
			var t: Vector2i = batch[k]
			if bytes.is_empty():
				continue
			var tile := Image.new()
			var err := tile.load_png_from_buffer(bytes) if bytes.slice(1, 4).get_string_from_ascii() == "PNG" else tile.load_jpg_from_buffer(bytes)
			if err != OK:
				continue
			tile.convert(Image.FORMAT_RGB8)
			img.blit_rect(tile, Rect2i(0, 0, 256, 256), Vector2i((t.x - t0.x) * 256, (t.y - t0.y) * 256))
			got += 1
		i += 6
	if got < jobs.size():
		return {"error": "Only %d of %d map tiles arrived." % [got, jobs.size()]}
	return {"image": img, "origin": Vector2(t0.x * 256, t0.y * 256)}


# One download on its own thread. When `finished`, `bytes` holds the body
# (empty if it failed); until then, await `done`.
class Fetch:
	extends RefCounted
	signal done
	var bytes := PackedByteArray()
	var finished := false

	func finish(b: PackedByteArray) -> void:
		bytes = b
		finished = true
		done.emit()


static func _get_bytes(url: String, host: Node) -> Fetch:
	var f := Fetch.new()
	var req := HTTPRequest.new()
	req.timeout = 60.0
	req.use_threads = true
	host.add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		f.finish(body if result == HTTPRequest.RESULT_SUCCESS and code == 200 else PackedByteArray()))
	if req.request(url, PackedStringArray(["User-Agent: " + UA])) != OK:
		req.queue_free()
		f.finish(PackedByteArray())
	return f


static func _bilinear(v: PackedFloat32Array, w: int, h: int, p: Vector2) -> float:
	var x := clampf(p.x, 0.0, w - 1.001)
	var y := clampf(p.y, 0.0, h - 1.001)
	var ix := int(x)
	var iy := int(y)
	var tx := x - ix
	var ty := y - iy
	var a := v[iy * w + ix]
	var b := v[iy * w + ix + 1]
	var c := v[(iy + 1) * w + ix]
	var d := v[(iy + 1) * w + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)
