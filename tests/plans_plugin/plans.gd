@tool
extends EditorPlugin

# Plans and CAD, against drawings whose right answers are known: a DXF with
# walls, an arc drawn by a polyline bulge, a circle, text, a layer switched
# off, and a chair block inserted turned, arrayed and mirrored; the same
# drawing again half a million metres from its origin, which must keep its
# millimetres; a floor-plan image scaled with two clicks; the tape measure
# snapping to the drawing's corners.

const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnMeasure := preload("res://addons/genesis/core/gn_measure.gd")
const GnDxf := preload("res://addons/genesis/cad/gn_dxf.gd")
const GnCadImport := preload("res://addons/genesis/cad/gn_cad_import.gd")
const Drawing := preload("res://addons/genesis/cad/gn_drawing.gd")
const Underlay := preload("res://addons/genesis/cad/gn_underlay.gd")

var _ok := true


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(400.0).timeout.connect(func(): print("GN_PLANS FAIL watchdog"); get_tree().quit(1))
	await _frames(20)
	DirAccess.make_dir_recursive_absolute("res://scenes")
	var r0 := Node3D.new()
	r0.name = "Plans"
	var packed := PackedScene.new()
	packed.pack(r0)
	ResourceSaver.save(packed, "res://scenes/plans_test.tscn")
	r0.free()
	EditorInterface.open_scene_from_path("res://scenes/plans_test.tscn")
	await _frames(10)
	GnEnvironment.set_up()
	GnEnvironment.apply("time_of_day", 13.0)
	var host := get_editor_interface().get_base_control()
	var dir := OS.get_user_data_dir()

	# 1. The reader, on its own.
	var path := dir.path_join("venue.dxf")
	_write(path, _venue(0.0))
	var d := GnDxf.read(path)
	_check("the drawing reads (%s)" % (d.error if d.error != "" else "ok"), d.error == "", d.error)
	_check("its units are millimetres", d.units == 4, str(d.units))
	_check("the FURN layer is switched off in the file", d.layers.has("FURN") and not d.layers.FURN.on, "")
	_check("walls are red, as their layer says", d.layers.WALLS.colour.is_equal_approx(Color(1, 0, 0)), str(d.layers.WALLS.colour))
	var w := d.hi_x - d.lo_x
	var h := d.hi_y - d.lo_y
	print("GN_PLANS extents %.3f x %.3f mm, %d segments, counts %s" % [w, h, d.segment_count(), d.counts])
	_check("10 m wide", absf(w - 10000.0) < 0.001, str(w))
	# The bulge arc swings 1 m below the wall line: 6 m of room plus 1 m of arc.
	_check("7 m deep, arc included (the bulge is drawn as its arc)", absf(h - 7000.0) < 1.0, str(h))
	var chairs := _points(d, "CHAIRS")
	_check("8 chairs of 4 sides", chairs.size() == 8 * 4 * 2, str(chairs.size()))
	_check("the turned chair: its corner is at (550, 1000)", _has(chairs, 550.0, 1000.0), "")
	_check("the arrayed chairs: the last one's far corner is at (4650, 5050)", _has(chairs, 4650.0, 5050.0), "")
	_check("the mirrored chair runs back from its insert point to x 7550", _has(chairs, 7550.0, 1000.0), "")
	_check("block linework takes the insert's layer", not (d.segments.get("0", PackedFloat64Array()) as PackedFloat64Array).size() > 0, "")
	_check("the text comes through", d.texts.size() == 1 and d.texts[0].text == "STAGE", str(d.texts))

	# 2. Far from its origin, millimetres survive (64-bit until placed).
	var far := dir.path_join("far.dxf")
	_write(far, _venue(512000000.0))
	var fd := GnDxf.read(far)
	_check("a drawing 512 km from its origin reads the same size", absf((fd.hi_x - fd.lo_x) - 10000.0) < 0.001, "")

	# 3. Into the scene through the importer, as the Plans page does it.
	var added := GnCadImport.add_drawing(far)
	_check("the importer brings the drawing in (%s)" % added.get("error", "ok"), added.has("node"), str(added))
	if not added.has("node"):
		_finish()
		return
	var node: Node3D = added.node
	node.position = Vector3.ZERO
	await _frames(3)
	var size: Vector2 = node.size_m()
	_check("it lies 10.000 × 7.000 m (%.4f × %.4f)" % [size.x, size.y], absf(size.x - 10.0) < 0.0005 and absf(size.y - 7.0) < 0.001, "")
	var layer_meshes := node.find_children("Layer *", "MeshInstance3D", true, false)
	_check("one mesh per layer, the one off in the file left out (%d)" % layer_meshes.size(), layer_meshes.size() == 3
		and node.hidden_layers == PackedStringArray(["FURN"]), str(node.hidden_layers))
	# The wall line runs 10 m along x: its two ends in the scene are 10.000 m apart.
	var a := _local(node, 0.0, 0.0)
	var b := _local(node, 10000.0, 0.0)
	_check("a 10 m wall is 10.000 m in the scene (%.5f), far from the origin" % a.distance_to(b), absf(a.distance_to(b) - 10.0) < 0.0005, "")
	# Snapping: a point 7 cm off the wall's corner lands on it exactly.
	var corner := node.global_transform * a
	var near := corner + Vector3(0.05, 0.0, 0.05)
	var snapped: Vector3 = node.snap(near, 0.2)
	_check("the tape measure snaps to the corner (%.4f m off)" % snapped.distance_to(Vector3(corner.x, 0, corner.z)),
		snapped.distance_to(Vector3(corner.x, 0, corner.z)) < 0.0005, "")
	# Walls, text and hiding.
	node.wall_layers = PackedStringArray(["WALLS"])
	node.hidden_layers = PackedStringArray(["FURN"])
	await _frames(3)
	var walls := node.find_children("Walls *", "MeshInstance3D", true, false)
	var wall_aabb: AABB = (walls[0] as MeshInstance3D).get_aabb() if walls.size() > 0 else AABB()
	_check("the wall layer stands up %.1f m tall" % wall_aabb.size.y, walls.size() == 1 and absf(wall_aabb.size.y - 3.0) < 0.01, "")
	_check("the hidden layer is gone", node.find_children("Layer FURN", "MeshInstance3D", true, false).is_empty(), "")
	var labels := node.find_children("*", "Label3D", true, false)
	_check("the text lies on the plan", labels.size() == 1, str(labels.size()))
	_check("its report reads", node.report_text().contains("10.000 × 7.000 m") and node.report_text().contains("millimetres"), node.report_text())

	# 4. The tape measure, clicking on the drawing from above.
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	cam.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 14, 0))
	await _frames(3)
	var tape := GnMeasure.new()
	tape.active = true
	var made: Array = []
	tape.measured.connect(func(dim): made.append(dim))
	var wall_start := node.global_transform * _local(node, 0.0, 0.0)
	var wall_end := node.global_transform * _local(node, 10000.0, 0.0)
	for p in [wall_start + Vector3(0.04, 0, -0.03), wall_end + Vector3(-0.03, 0, 0.04)]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = cam.unproject_position(p)
		tape.handle(cam, click)
	_check("clicking near both ends measures exactly 10.000 m (%s)" % (made[0].text() if made.size() == 1 else "none"),
		made.size() == 1 and absf(made[0].length() - 10.0) < 0.0005, "")
	tape.active = false

	# 5. A floor-plan image, scaled with two points.
	var png := dir.path_join("plan.png")
	var img := Image.create(1000, 500, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for x in 1000:
		img.set_pixel(x, 250, Color.BLACK)
	img.save_png(png)
	var p_added := GnCadImport.add_plan(png, 20.0)
	_check("the plan comes in (%s)" % p_added.get("error", "ok"), p_added.has("node"), str(p_added))
	if p_added.has("node"):
		var plan: Node3D = p_added.node
		plan.position = Vector3(40, 0, 0)
		_check("at the width asked for (%.2f m)" % plan.size_m().x, absf(plan.size_m().x - 20.0) < 0.001, "")
		# Two points 400 px apart are 8 m on the plan as it stands; they are really 10 m.
		var pa := plan.global_position + Vector3(-4, 0, 0)
		var pb := plan.global_position + Vector3(4, 0, 0)
		var k: float = plan.calibrate(pa, pb, 10.0)
		print("GN_PLANS plan scaled by %.4f to %s m" % [k, plan.size_m()])
		_check("two clicks and a distance set its scale (25 × 12.5 m)", absf(plan.size_m().x - 25.0) < 0.001 and absf(plan.size_m().y - 12.5) < 0.001, str(plan.size_m()))
		# Scaling about its middle, the plan moved so the first point (x 36) stays put.
		_check("and the first point stays put", absf(plan.global_position.x - 41.0) < 0.001, str(plan.global_position))

	# 6. A PDF, if this machine can draw one.
	if GnCadImport.find_tool(["pdftoppm", "mutool"]) == "":
		print("GN_PLANS (no PDF tool on this machine: PDF plans not tried)")
	_check("without the ODA converter, a DWG says what it needs", GnCadImport.find_oda() != "" or
		GnCadImport.add_drawing(dir.path_join("x.dwg")).get("error", "").contains("ODA File Converter"), "")

	# 6b. A PDF plotted from CAD, read as linework: a 10 x 5 m room drawn
	# with a heavy pen at 1:100, a grid of thin grey lines inside it, the
	# page compressed as real plots are.
	var k := 72.0 / 0.0254 / 100.0   # points per metre at 1:100
	var content := "q 0.7 w 0 G 100 100 %.4f %.4f re S Q\n" % [10.0 * k, 5.0 * k]
	for g in 60:
		content += "q 0.1 w 0.5 G %.3f 110 m %.3f 200 l S Q\n" % [110.0 + g * 2.0, 110.0 + g * 2.0]
	var vec_pdf := dir.path_join("plotted_plan.pdf")
	_write_pdf(vec_pdf, content, true)
	var pdf_added := GnCadImport.add_drawing(vec_pdf, 1, 100.0)
	_check("a CAD PDF comes in as a drawing (%s)" % pdf_added.get("error", "ok"), pdf_added.has("node"), str(pdf_added))
	if pdf_added.has("node"):
		var pn: Node3D = pdf_added.node
		await _frames(3)
		var psize: Vector2 = pn.size_m()
		_check("its room is 10.000 × 5.000 m (%.4f × %.4f)" % [psize.x, psize.y],
			absf(psize.x - 10.0) < 0.001 and absf(psize.y - 5.0) < 0.001, "")
		var pens: Dictionary = pn.layer_list()
		_check("each pen is a layer (%s)" % ", ".join(pens.keys()),
			pens.has("Lines 0.70 pt, black") and pens.has("Lines 0.10 pt, grey 50%") and int(pens["Lines 0.10 pt, grey 50%"].count) == 60, str(pens.keys()))
		pn.wall_layers = PackedStringArray(["Lines 0.70 pt, black"])
		await _frames(3)
		_check("the heavy pen stands up as walls", pn.find_children("Walls *", "MeshInstance3D", true, false).size() == 1, "")
		_check("its report says the scale", pn.report_text().contains("1:100"), pn.report_text())
		pn.queue_free()
	var pic_pdf := dir.path_join("picture_plan.pdf")
	_write_pdf(pic_pdf, "q 0.5 w 0 0 m 100 0 l S Q\n", false)
	var refused := GnCadImport.add_drawing(pic_pdf, 1, 100.0)
	_check("a page with no linework is sent to the image route", str(refused.get("error", "")).contains("picture"), str(refused))

	# 7. What it looks like: the drawing from above, walls up.
	var shot := Camera3D.new()
	GnScene.root().add_child(shot)
	shot.global_position = Vector3(-6, 9, 9)
	shot.look_at(Vector3(0, 0, 0))
	var out: String = await GnRender.render(shot, Vector2i(1280, 800), host)
	_check("it renders", out != "", "")
	if out != "":
		DirAccess.copy_absolute(ProjectSettings.globalize_path(out), ProjectSettings.globalize_path("res://renders/plans_drawing.png"))
	shot.free()
	EditorInterface.save_scene()
	_finish()


# A small venue in millimetres, everything shifted by `off` in x and y.
func _venue(off: float) -> String:
	var o := func(v: float) -> String: return str(snappedf(v + off, 0.001))
	var e: Array = []
	e += ["0", "SECTION", "2", "HEADER", "9", "$INSUNITS", "70", "4", "0", "ENDSEC"]
	e += ["0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", "4"]
	for l in [["WALLS", "1"], ["FURN", "-3"], ["CHAIRS", "5"], ["ARCS", "2"]]:
		e += ["0", "LAYER", "2", l[0], "70", "0", "62", l[1]]
	e += ["0", "ENDTAB", "0", "ENDSEC"]
	e += ["0", "SECTION", "2", "BLOCKS", "0", "BLOCK", "8", "0", "2", "CHAIR", "70", "0", "10", "0", "20", "0", "30", "0",
		"0", "LWPOLYLINE", "8", "0", "90", "4", "70", "1", "10", "0", "20", "0", "10", "450", "20", "0", "10", "450", "20", "450",
		"10", "0", "20", "450", "0", "ENDBLK", "8", "0", "0", "ENDSEC"]
	e += ["0", "SECTION", "2", "ENTITIES"]
	e += ["0", "LINE", "8", "WALLS", "10", o.call(0), "20", o.call(0), "30", "0", "11", o.call(10000), "21", o.call(0), "31", "0"]
	e += ["0", "LWPOLYLINE", "8", "WALLS", "90", "4", "70", "1", "10", o.call(0), "20", o.call(0), "10", o.call(10000), "20", o.call(0),
		"10", o.call(10000), "20", o.call(6000), "10", o.call(0), "20", o.call(6000)]
	# A semicircle from (2000,0) to (4000,0), bulge 1: its arc dips 1 m below.
	e += ["0", "LWPOLYLINE", "8", "ARCS", "90", "2", "70", "0", "10", o.call(2000), "20", o.call(0), "42", "1",
		"10", o.call(4000), "20", o.call(0)]
	e += ["0", "CIRCLE", "8", "FURN", "10", o.call(5000), "20", o.call(3000), "30", "0", "40", "500"]
	e += ["0", "INSERT", "8", "CHAIRS", "2", "CHAIR", "10", o.call(1000), "20", o.call(1000), "30", "0", "50", "90"]
	e += ["0", "INSERT", "8", "CHAIRS", "2", "CHAIR", "10", o.call(3000), "20", o.call(4000), "30", "0", "70", "3", "71", "2",
		"44", "600", "45", "600"]
	e += ["0", "INSERT", "8", "CHAIRS", "2", "CHAIR", "10", o.call(8000), "20", o.call(1000), "30", "0", "41", "-1"]
	e += ["0", "TEXT", "8", "WALLS", "10", o.call(5000), "20", o.call(5000), "30", "0", "40", "250", "1", "STAGE"]
	e += ["0", "ENDSEC", "0", "EOF"]
	return "\n".join(e) + "\n"


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# A layer's segment ends as (x, y) pairs, drawing units, relative to the
# drawing's own first wall corner (so the far copy compares the same).
func _points(d: GnDxf.Drawing, layer: String) -> Array:
	var out: Array = []
	var segs: PackedFloat64Array = d.segments.get(layer, PackedFloat64Array())
	for q in segs.size() / 3:
		out.append(Vector2(segs[q * 3] - d.lo_x, segs[q * 3 + 1] - (d.lo_y + 1000.0)))
	return out


func _has(points: Array, x: float, y: float) -> bool:
	for p in points:
		if absf(p.x - x) < 0.01 and absf(p.y - y) < 0.01:
			return true
	return false


# A drawing point (relative to its first wall corner, drawing units) in the node's space.
func _local(node: Node3D, x: float, y: float) -> Vector3:
	var dr: GnDxf.Drawing = node.drawing
	return node._to_local(dr.lo_x + x, dr.lo_y + 1000.0 + y, 0.0) - Vector3(0, node.lift, 0)


func _finish() -> void:
	print("GN_PLANS RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


# A one-page PDF with a classic cross-reference table around `content`.
func _write_pdf(path: String, content: String, compress: bool) -> void:
	var stream := content.to_ascii_buffer()
	var filter := ""
	if compress:
		stream = stream.compress(FileAccess.COMPRESSION_DEFLATE)
		filter = " /Filter /FlateDecode"
	var objs: Array = [
		"<< /Type /Catalog /Pages 2 0 R >>".to_ascii_buffer(),
		"<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_ascii_buffer(),
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 842 595] /Contents 4 0 R /Resources << >> >>".to_ascii_buffer(),
	]
	var four := ("<< /Length %d%s >>\nstream\n" % [stream.size(), filter]).to_ascii_buffer()
	four.append_array(stream)
	four.append_array("\nendstream".to_ascii_buffer())
	objs.append(four)
	var out := "%PDF-1.4\n".to_ascii_buffer()
	var offsets: Array = []
	for i in objs.size():
		offsets.append(out.size())
		out.append_array(("%d 0 obj\n" % (i + 1)).to_ascii_buffer())
		out.append_array(objs[i])
		out.append_array("\nendobj\n".to_ascii_buffer())
	var xref := out.size()
	var table := "xref\n0 %d\n0000000000 65535 f \n" % (objs.size() + 1)
	for o in offsets:
		table += "%010d 00000 n \n" % o
	table += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [objs.size() + 1, xref]
	out.append_array(table.to_ascii_buffer())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(out)
	f.close()


func _check(what: String, good: bool, detail: String) -> void:
	print("GN_PLANS %s %s%s" % ["ok  " if good else "FAIL", what, "" if good else ": " + detail])
	_ok = _ok and good


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
