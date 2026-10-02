@tool
extends RefCounted

# A virtual tour: a 360 panorama from every saved camera, in one HTML file
# that opens in any browser. Drag to look round; rings mark the other views
# and walk you there, keeping the way you face. In a headset (the file
# served over https) "Enter VR" puts you inside it, in 3D if the tour was
# rendered in stereo. One file, so it can be emailed or put anywhere.

const GnPanorama := preload("res://addons/genesis/core/gn_panorama.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")

const VIEWER := "res://addons/genesis/core/gn_tour_viewer.html"
## Views further apart than this get no ring between them (they are still
## in the menu): across a site, a ring 200 m away is only clutter.
const REACH_M := 60.0
const JPEG_QUALITY := 0.86


## Renders the tour and saves it; returns the file's path, or "". `progress`
## is called with (done, total) as each view finishes.
static func export_tour(cams: Array, title: String, stereo: bool, width: int, host: Node,
		progress := Callable()) -> String:
	if cams.is_empty():
		return ""
	var stops: Array = []
	for i in cams.size():
		var cam: Camera3D = cams[i]
		var path := ""
		if stereo:
			path = await GnPanorama.render_stereo(cam, width, host)
		else:
			path = await GnPanorama.render(cam, width, host)
		if path == "":
			return ""
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		img.convert(Image.FORMAT_RGB8)
		stops.append({
			"name": str(cam.name),
			"yaw": heading(cam),
			"image": "data:image/jpeg;base64," + Marshalls.raw_to_base64(img.save_jpg_to_buffer(JPEG_QUALITY)),
			"spots": spots(cams, i),
		})
		if progress.is_valid():
			progress.call(i + 1, cams.size())
	var tour := {"title": title, "stereo": stereo, "stops": stops}
	var html := FileAccess.get_file_as_string(VIEWER).replace("/*TOUR_JSON*/null", JSON.stringify(tour))
	var file := "%s/%s_tour.html" % [GnRender.OUTPUT_DIR, title.validate_filename().replace(" ", "_")]
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(html)
	f.close()
	return file


## The way a camera faces, as the panorama's centre longitude.
static func heading(cam: Camera3D) -> float:
	var fwd := -cam.global_transform.basis.z
	return atan2(fwd.x, -fwd.z)


## Rings from view `i` to the others in reach: where each stands, as a
## longitude and latitude in view i's panorama, nearest first.
static func spots(cams: Array, i: int) -> Array:
	var here: Vector3 = (cams[i] as Camera3D).global_position
	var yaw := heading(cams[i])
	var out: Array = []
	for j in cams.size():
		var d: Vector3 = (cams[j] as Camera3D).global_position - here
		if j == i or d.length() > REACH_M or d.length() < 0.2:
			continue
		out.append({"to": j, "dist": d.length(),
			"lon": wrapf(atan2(d.x, -d.z) - yaw, -PI, PI), "lat": asin(clampf(d.y / d.length(), -1.0, 1.0))})
	out.sort_custom(func(a, b): return a.dist < b.dist)
	return out
