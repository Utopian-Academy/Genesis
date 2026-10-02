@tool
extends Node3D

# An LED video wall built from real cabinet specifications: the right number
# of the right-sized cabinets, straight or curved, flown or ground-stacked,
# showing content (or a pixel map) at the wall's true native resolution.
#
# A node with exported properties rather than a mesh, so Godot's own
# Inspector edits it and its own undo covers every change, and the scene
# remembers it as a wall, not as geometry.
#
# Panel figures are typical values for each class of product, not any one
# manufacturer's. Enter a real product's numbers with "Custom" for a real show.

const GnLiveVideo := preload("res://addons/genesis/core/gn_live_video.gd")
const VIDEO_EXTENSIONS := ["mp4", "mov", "m4v", "webm", "mkv", "avi", "mxf"]

const PANELS := {
	"1.9 mm fine pitch (500 × 500)": {"w": 0.5, "h": 0.5, "px": Vector2i(256, 256), "kg": 7.5, "watts": 180},
	"2.6 mm indoor (500 × 500)": {"w": 0.5, "h": 0.5, "px": Vector2i(192, 192), "kg": 7.0, "watts": 170},
	"2.9 mm indoor (500 × 500)": {"w": 0.5, "h": 0.5, "px": Vector2i(168, 168), "kg": 7.0, "watts": 160},
	"3.9 mm indoor/outdoor (500 × 1000)": {"w": 0.5, "h": 1.0, "px": Vector2i(128, 256), "kg": 13.0, "watts": 360},
	"5.9 mm outdoor (500 × 1000)": {"w": 0.5, "h": 1.0, "px": Vector2i(84, 168), "kg": 14.5, "watts": 420},
	"Custom": {"w": 0.5, "h": 0.5, "px": Vector2i(192, 192), "kg": 7.0, "watts": 170},
}
# Pixels one 1 Gb processor port carries at 60 Hz, 8-bit: the usual planning figure.
const PIXELS_PER_PORT := 655360

@export_enum("1.9 mm fine pitch (500 × 500)", "2.6 mm indoor (500 × 500)", "2.9 mm indoor (500 × 500)",
	"3.9 mm indoor/outdoor (500 × 1000)", "5.9 mm outdoor (500 × 1000)", "Custom")
var panel: String = "2.6 mm indoor (500 × 500)":
	set(v): panel = v; _queue()
@export_range(1, 200) var columns: int = 12:
	set(v): columns = v; _queue()
@export_range(1, 100) var rows: int = 7:
	set(v): rows = v; _queue()
## Total bend across the wall. 0 is flat; positive curves toward the audience.
@export_range(-180.0, 180.0, 1.0) var curve_degrees: float = 0.0:
	set(v): curve_degrees = v; _queue()
## Height of the wall's bottom edge above the floor.
@export_range(0.0, 30.0, 0.05) var bottom: float = 0.6:
	set(v): bottom = v; _queue()
## An image or a video to show (a video loops). Empty shows the pixel map.
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.mp4", "*.mov", "*.m4v", "*.webm", "*.mkv", "*.avi", "*.mxf")
var content: String = "":
	set(v): content = v; _queue()
## Live video instead: what a playback app, media server or camera is
## sending (see the Show page), e.g. "srt:9710" for Deckboy's Stream output.
@export var live_source: String = "":
	set(v): live_source = v; _queue()
## Screen brightness relative to a typical indoor setting.
@export_range(0.0, 4.0, 0.05) var brightness: float = 1.0:
	set(v):
		brightness = v
		# A fade changes the screen's material in place, not the whole wall.
		if _screen_mat and not _pending:
			_screen_mat.albedo_color = Color(brightness, brightness, brightness)
			_screen_mat.emission_energy_multiplier = brightness * 1.5
		else:
			_queue()
@export_group("Custom panel")
@export var custom_size_m := Vector2(0.5, 0.5):
	set(v): custom_size_m = v; _queue()
@export var custom_pixels := Vector2i(192, 192):
	set(v): custom_pixels = v; _queue()
@export var custom_kg := 7.0:
	set(v): custom_kg = v; _queue()
@export var custom_watts := 170.0:
	set(v): custom_watts = v; _queue()

var _pending := false


# The live source this wall holds open, so a rebuild does not restart it.
var _live := ""
var _live_texture: ImageTexture
var _screen_mat: StandardMaterial3D


func _exit_tree() -> void:
	_hold("")


# Keeps exactly one hold on the source this wall shows.
func _hold(spec: String) -> ImageTexture:
	if spec != _live:
		if _live != "":
			GnLiveVideo.release(_live)
		_live = spec
		_live_texture = GnLiveVideo.acquire(spec) if spec != "" else null
	return _live_texture


## The live source showing, if any: a live_source, or a video file as content.
func live_spec() -> String:
	if live_source.strip_edges() != "":
		return live_source.strip_edges()
	if content != "" and content.get_extension().to_lower() in VIDEO_EXTENSIONS:
		return "file:%s" % content
	return ""


func _ready() -> void:
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


func spec() -> Dictionary:
	if panel == "Custom":
		return {"w": custom_size_m.x, "h": custom_size_m.y, "px": custom_pixels, "kg": custom_kg, "watts": custom_watts}
	return PANELS.get(panel, PANELS["2.6 mm indoor (500 × 500)"])


# Everything a production manager asks about a wall.
func report() -> Dictionary:
	var s := spec()
	var px: Vector2i = s.px
	var res := Vector2i(px.x * columns, px.y * rows)
	var count := columns * rows
	var pitch_mm := float(s.w) * 1000.0 / px.x
	var max_w := float(s.watts) * count
	return {
		"size_m": Vector2(float(s.w) * columns, float(s.h) * rows),
		"resolution": res,
		"aspect": float(res.x) / res.y,
		"cabinets": count,
		"pitch_mm": pitch_mm,
		"weight_kg": float(s.kg) * count,
		"power_max_w": max_w,
		# Typical content draws about a third of the panel's maximum.
		"power_typical_w": max_w * 0.33,
		"amps_230v": max_w / 230.0,
		"amps_120v": max_w / 120.0,
		"data_ports": int(ceil(float(res.x * res.y) / PIXELS_PER_PORT)),
		# The common rule: about a metre of viewing distance per millimetre of pitch.
		"min_view_m": pitch_mm,
	}


func report_text() -> String:
	var r := report()
	return "\n".join([
		"%.2f × %.2f m, %d × %d px (%.2f:1)" % [r.size_m.x, r.size_m.y, r.resolution.x, r.resolution.y, r.aspect],
		"%d cabinets, %.2f mm pitch, %.0f kg" % [r.cabinets, r.pitch_mm, r.weight_kg],
		"Power %.1f kW max, %.1f kW typical: %.0f A at 230 V, %.0f A at 120 V" % [
			r.power_max_w / 1000.0, r.power_typical_w / 1000.0, r.amps_230v, r.amps_120v],
		"%d data port%s, best viewed from %.0f m" % [r.data_ports, "" if r.data_ports == 1 else "s", r.min_view_m],
	])


# ---------------------------------------------------------------------------
# Geometry: cabinets as a MultiMesh of thin boxes following the curve, and one
# screen surface over their faces carrying the content across the whole wall.
# ---------------------------------------------------------------------------
func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	var s := spec()
	var cw := float(s.w)
	var ch := float(s.h)
	var depth := 0.08
	var total_angle := deg_to_rad(curve_degrees)
	var width := cw * columns
	# A curved wall is an arc whose length is the wall's width.
	var radius := width / absf(total_angle) if absf(total_angle) > 0.001 else 0.0

	var cab := BoxMesh.new()
	cab.size = Vector3(cw * 0.995, ch * 0.995, depth)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.05, 0.05, 0.055)
	frame_mat.roughness = 0.6
	frame_mat.metallic = 0.4
	cab.material = frame_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cab
	mm.instance_count = columns * rows
	for c in columns:
		var col_xf := _column(c + 0.5, cw, radius, total_angle)
		for r in rows:
			var y := bottom + ch * (r + 0.5)
			mm.set_instance_transform(c * rows + r, col_xf.translated_local(Vector3(0, y, -depth * 0.5 - 0.004)))
	var cabinets := MultiMeshInstance3D.new()
	cabinets.name = "Cabinets"
	cabinets.multimesh = mm
	cabinets.set_meta(&"gn_generated", true)
	add_child(cabinets)

	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = _screen_mesh(cw, ch, radius, total_angle)
	_screen_mat = _screen_material()
	screen.material_override = _screen_mat
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.set_meta(&"gn_generated", true)
	add_child(screen)


# The frame of a point `u` columns along the wall: flat, or on the arc.
func _column(u: float, cw: float, radius: float, total_angle: float) -> Transform3D:
	var width := cw * columns
	if radius == 0.0:
		return Transform3D(Basis(), Vector3(u * cw - width * 0.5, 0, 0))
	# t: angle along the arc from the wall's centre. Bending toward the
	# audience (+Z) brings the edges forward and turns each cabinet in toward
	# the circle's centre; bending away does the opposite.
	var bend := signf(total_angle)
	var t := (u * cw - width * 0.5) / radius
	var pos := Vector3(sin(t) * radius, 0, (1.0 - cos(t)) * radius * bend)
	return Transform3D(Basis(Vector3.UP, -t * bend), pos)


func _screen_mesh(cw: float, ch: float, radius: float, total_angle: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := columns * (4 if radius != 0.0 else 1)
	var h0 := bottom
	var h1 := bottom + ch * rows
	for i in steps:
		var u0 := float(i) / steps
		var u1 := float(i + 1) / steps
		var x0 := _column(u0 * columns, cw, radius, total_angle)
		var x1 := _column(u1 * columns, cw, radius, total_angle)
		var n := x0.basis.z
		var quad := [[x0.origin + Vector3(0, h0, 0), Vector2(u0, 1)], [x1.origin + Vector3(0, h0, 0), Vector2(u1, 1)],
			[x1.origin + Vector3(0, h1, 0), Vector2(u1, 0)], [x0.origin + Vector3(0, h0, 0), Vector2(u0, 1)],
			[x1.origin + Vector3(0, h1, 0), Vector2(u1, 0)], [x0.origin + Vector3(0, h1, 0), Vector2(u0, 0)]]
		for v in quad:
			st.set_normal(n)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


func _screen_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex: Texture2D = _hold(live_spec()) if is_inside_tree() else null
	if tex == null and content != "" and FileAccess.file_exists(content) and live_spec() == "":
		var img := Image.load_from_file(ProjectSettings.globalize_path(content))
		if img:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		tex = ImageTexture.create_from_image(pixel_map())
	# An LED wall is a light source: its picture is emission, not paint.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Seen from behind it is the cabinets' backs anyway; double-sided saves
	# caring which way the strip was wound.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex
	m.albedo_color = Color(brightness, brightness, brightness)
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = brightness * 1.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# The wall's pixel map at its native resolution: every cabinet outlined and
# numbered (column.row), with a centre cross and the resolution written on
# it. What an LED tech loads into the processor to check the mapping; here it
# is also what an empty wall shows. Scaled down for the preview if enormous.
func pixel_map() -> Image:
	var s := spec()
	var px: Vector2i = s.px
	var res := Vector2i(px.x * columns, px.y * rows)
	var scale := minf(1.0, 4096.0 / maxf(res.x, res.y))
	var size := Vector2i(maxi(int(res.x * scale), 8), maxi(int(res.y * scale), 8))
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var cw := float(size.x) / columns
	var ch := float(size.y) / rows
	for c in columns:
		for r in rows:
			var hue := fposmod((c * 0.13 + r * 0.29), 1.0)
			var fill := Color.from_hsv(hue, 0.55, 0.35)
			img.fill_rect(Rect2i(int(c * cw), int(r * ch), ceili(cw), ceili(ch)), fill)
			img.fill_rect(Rect2i(int(c * cw), int(r * ch), ceili(cw), maxi(int(ch * 0.02), 1)), Color.WHITE)
			img.fill_rect(Rect2i(int(c * cw), int(r * ch), maxi(int(cw * 0.02), 1), ceili(ch)), Color.WHITE)
			# Sized so the longest label ("12.10") fits inside its cabinet.
			var label := "%d.%d" % [c + 1, r + 1]
			var cell := maxi(mini(int(ch * 0.07), int(cw * 0.76 / (label.length() * 4))), 1)
			_digits(img, label, Vector2i(int(c * cw + cw * 0.12), int(r * ch + ch * 0.15)), cell)
	# Centre cross.
	img.fill_rect(Rect2i(size.x / 2 - 1, 0, 3, size.y), Color(1, 0.2, 0.2))
	img.fill_rect(Rect2i(0, size.y / 2 - 1, size.x, 3), Color(1, 0.2, 0.2))
	return img


# A tiny 3x5 bitmap font for digits and '.', drawn with rectangles.
const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
	".": ["000", "000", "000", "000", "010"],
}


func _digits(img: Image, text: String, at: Vector2i, cell: int) -> void:
	var x := at.x
	for ch in text:
		var g: Array = GLYPHS.get(ch, GLYPHS["."])
		for row in 5:
			for col in 3:
				if g[row][col] == "1":
					img.fill_rect(Rect2i(x + col * cell, at.y + row * cell, cell, cell), Color.WHITE)
		x += cell * 4
