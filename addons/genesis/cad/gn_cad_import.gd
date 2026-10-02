@tool
extends RefCounted

# Bringing plans and drawings into the project: images and PDF pages become
# floor-plan underlays, DXF drawings become GnDrawing nodes. Everything is
# copied into the project (genesis_data/plans, genesis_data/cad) so a
# scene travels with what it was built on.
#
# Two formats need a free outside tool, found if installed:
#   PDF: Poppler's pdftoppm, or MuPDF's mutool, draws the page as an image.
#   DWG: the ODA File Converter (opendesign.com, free) saves it as DXF.
#        DWG is AutoCAD's closed format; nothing else reads it reliably.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const Underlay := preload("res://addons/genesis/cad/gn_underlay.gd")
const Drawing := preload("res://addons/genesis/cad/gn_drawing.gd")
const GnDxf := preload("res://addons/genesis/cad/gn_dxf.gd")
const GnPdf := preload("res://addons/genesis/cad/gn_pdf.gd")

const PLAN_DIR := "res://genesis_data/plans"
const CAD_DIR := "res://genesis_data/cad"
const PLAN_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "pdf"]
const CAD_EXTENSIONS := ["dxf", "dwg", "pdf"]
## Drawing scales as sheets state them, and their ratios.
const SCALES := {"1:50": 50.0, "1:100": 100.0, "1:200": 200.0, "1:500": 500.0,
	"1/4\" = 1'-0\" (1:48)": 48.0, "1/8\" = 1'-0\" (1:96)": 96.0, "3/16\" = 1'-0\" (1:64)": 64.0,
	"3/32\" = 1'-0\" (1:128)": 128.0, "1/16\" = 1'-0\" (1:192)": 192.0, "1\" = 20' (1:240)": 240.0}
# PDF pages are drawn at this resolution: 1:100 at A1 comes out about 5,000
# pixels wide, fine enough for millimetre-thin lines.
const PDF_DPI := 200
const ODA_URL := "https://www.opendesign.com/guestfiles/oda_file_converter"
const POPPLER_URL := "https://poppler.freedesktop.org"


## Adds a floor plan. For a PDF, `ratio` is the drawing's scale (100 for
## 1:100) and sets its size exactly; for an image, `width_m` is a first guess
## at how wide the plan is (set it exactly with two clicks afterwards).
## Returns {"node": Node3D} or {"error": String}.
static func add_plan(path: String, width_m := 30.0, ratio := 100.0, page := 1) -> Dictionary:
	if GnScene.root() == null:
		return {"error": "Open or make a scene first."}
	var ext := path.get_extension().to_lower()
	if ext not in PLAN_EXTENSIONS:
		return {"error": "Plans can be PNG, JPG, WebP or PDF."}
	DirAccess.make_dir_recursive_absolute(PLAN_DIR)
	var stem := _unique(PLAN_DIR, path.get_file().get_basename().validate_filename(), "png" if ext == "pdf" else ext)
	var target := "%s/%s" % [PLAN_DIR, stem]
	var mpp := 0.0
	if ext == "pdf":
		var err := pdf_page(path, ProjectSettings.globalize_path(target), page, PDF_DPI)
		if err != "":
			return {"error": err}
		# A PDF knows its paper size: a pixel is 25.4 mm / dpi on paper,
		# `ratio` times that on the ground.
		mpp = 0.0254 / PDF_DPI * ratio
	else:
		var copy_err := DirAccess.copy_absolute(path, ProjectSettings.globalize_path(target))
		if copy_err != OK:
			return {"error": "Couldn't copy %s into the project." % path.get_file()}
	var img := Image.load_from_file(ProjectSettings.globalize_path(target))
	if img == null or img.get_width() == 0:
		return {"error": "Couldn't read %s as an image." % path.get_file()}
	if mpp == 0.0:
		mpp = width_m / img.get_width()
	var u := Underlay.new()
	u.name = "Plan %s" % path.get_file().get_basename()
	u.image = target
	u.metres_per_pixel = mpp
	u.position = GnPlacement.drop_point() * Vector3(1, 0, 1)
	GnScene.add_node(u, GnScene.root(), "Genesis: add plan", "plan")
	GnScene.select(u)
	return {"node": u}


## Adds a CAD drawing (DXF, DWG through the ODA File Converter, or a PDF
## plotted from CAD, read at `ratio` from `page`).
## Returns {"node": Node3D} or {"error": String}.
static func add_drawing(path: String, page := 1, ratio := 100.0) -> Dictionary:
	if GnScene.root() == null:
		return {"error": "Open or make a scene first."}
	var ext := path.get_extension().to_lower()
	if ext not in CAD_EXTENSIONS:
		return {"error": "Drawings can be DXF, DWG or PDF."}
	DirAccess.make_dir_recursive_absolute(CAD_DIR)
	if ext == "pdf":
		var copy := "%s/%s" % [CAD_DIR, _unique(CAD_DIR, path.get_file().get_basename().validate_filename(), "pdf")]
		var read := GnPdf.read(path, page, ratio)
		if read.error != "":
			return {"error": read.error}
		if DirAccess.copy_absolute(path, ProjectSettings.globalize_path(copy)) != OK:
			return {"error": "Couldn't copy %s into the project." % path.get_file()}
		var pd := Drawing.new()
		pd.name = "Drawing %s" % path.get_file().get_basename()
		pd.pdf_page = page
		pd.pdf_scale = ratio
		pd.source = copy
		# Plotted text and hatching are outlines; they start hidden so the
		# linework reads, one tick away.
		var fills := PackedStringArray()
		for layer in read.layers:
			if str(layer).begins_with("Filled shapes"):
				fills.append(layer)
		pd.hidden_layers = fills
		pd.position = GnPlacement.drop_point() * Vector3(1, 0, 1)
		GnScene.add_node(pd, GnScene.root(), "Genesis: add drawing", "drawing")
		GnScene.select(pd)
		return {"node": pd}
	var target := "%s/%s" % [CAD_DIR, _unique(CAD_DIR, path.get_file().get_basename().validate_filename(), "dxf")]
	if ext == "dwg":
		var err := dwg_to_dxf(path, ProjectSettings.globalize_path(target))
		if err != "":
			return {"error": err}
	elif DirAccess.copy_absolute(path, ProjectSettings.globalize_path(target)) != OK:
		return {"error": "Couldn't copy %s into the project." % path.get_file()}
	var check := GnDxf.read(ProjectSettings.globalize_path(target))
	if check.error != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
		return {"error": check.error}
	var d := Drawing.new()
	d.name = "Drawing %s" % path.get_file().get_basename()
	d.source = target
	# Layers switched off or frozen in the drawing start hidden, as in CAD.
	var off := PackedStringArray()
	for layer in check.layers:
		if not check.layers[layer].on:
			off.append(layer)
	d.hidden_layers = off
	d.position = GnPlacement.drop_point() * Vector3(1, 0, 1)
	GnScene.add_node(d, GnScene.root(), "Genesis: add drawing", "drawing")
	GnScene.select(d)
	return {"node": d}


## Draws one page of a PDF to a PNG. Returns "" or what went wrong.
static func pdf_page(pdf: String, png: String, page: int, dpi: int) -> String:
	var tool := find_tool(["pdftoppm", "mutool"])
	if tool == "":
		return "Reading a PDF needs Poppler (pdftoppm) or MuPDF (mutool), both free: %s. Or save the page as a PNG and bring that in." % POPPLER_URL
	var out: Array = []
	var code := -1
	if tool.get_file().get_basename().to_lower() == "pdftoppm":
		# -singlefile writes <base>.png
		code = OS.execute(tool, PackedStringArray(["-png", "-r", str(dpi), "-f", str(page), "-l", str(page), "-singlefile",
			pdf, png.get_basename()]), out, true)
	else:
		code = OS.execute(tool, PackedStringArray(["draw", "-r", str(dpi), "-o", png, pdf, str(page)]), out, true)
	if code != 0 or not FileAccess.file_exists(png):
		return "Couldn't draw page %d of %s: %s" % [page, pdf.get_file(), "\n".join(out).strip_edges().left(300)]
	return ""


## Converts a DWG to DXF with the ODA File Converter. Returns "" or what went wrong.
static func dwg_to_dxf(dwg: String, dxf: String) -> String:
	var oda := find_oda()
	if oda == "":
		return "DWG needs the free ODA File Converter (%s). Install it, or save the drawing as DXF from your CAD program." % ODA_URL
	# It converts folders: give it one holding just this file.
	var work := OS.get_user_data_dir().path_join("dwg_%d" % Time.get_ticks_usec())
	var into := work.path_join("in")
	var outof := work.path_join("out")
	DirAccess.make_dir_recursive_absolute(into)
	DirAccess.make_dir_recursive_absolute(outof)
	DirAccess.copy_absolute(dwg, into.path_join(dwg.get_file()))
	var said: Array = []
	var code := OS.execute(oda, PackedStringArray([into, outof, "ACAD2018", "DXF", "0", "1", "*.DWG"]), said, true)
	var made := outof.path_join(dwg.get_file().get_basename() + ".dxf")
	if not FileAccess.file_exists(made):
		# Some versions keep the extension's case.
		made = outof.path_join(dwg.get_file().get_basename() + ".DXF")
	var err := ""
	if code != 0 or not FileAccess.file_exists(made):
		err = "The ODA File Converter couldn't convert %s: %s" % [dwg.get_file(), "\n".join(said).strip_edges().left(300)]
	else:
		DirAccess.copy_absolute(made, dxf)
	_remove_tree(work)
	return err


## The ODA File Converter, wherever it installs on this system, or "".
static func find_oda() -> String:
	var candidates: Array = []
	match OS.get_name():
		"Windows":
			for root in [OS.get_environment("ProgramFiles"), OS.get_environment("ProgramFiles(x86)")]:
				if root == "":
					continue
				var oda_dir: String = root.path_join("ODA")
				if DirAccess.dir_exists_absolute(oda_dir):
					var names := Array(DirAccess.get_directories_at(oda_dir))
					names.sort()
					names.reverse()   # the newest version first
					for d in names:
						candidates.append(oda_dir.path_join(d).path_join("ODAFileConverter.exe"))
		"macOS":
			candidates.append("/Applications/ODAFileConverter.app/Contents/MacOS/ODAFileConverter")
		_:
			candidates.append_array(["/usr/bin/ODAFileConverter", "/usr/local/bin/ODAFileConverter",
				"/opt/ODAFileConverter/ODAFileConverter"])
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return find_tool(["ODAFileConverter"])


## The first of these programs that is on the PATH, as a full path, or "".
static func find_tool(names: Array) -> String:
	var sep := ";" if OS.get_name() == "Windows" else ":"
	var exts := [".exe", ""] if OS.get_name() == "Windows" else [""]
	for name in names:
		for dir in OS.get_environment("PATH").split(sep, false):
			for ext in exts:
				var p: String = dir.path_join(name + ext)
				if FileAccess.file_exists(p):
					return p
	return ""


static func _unique(dir: String, stem: String, ext: String) -> String:
	var name := "%s.%s" % [stem, ext]
	var n := 2
	while FileAccess.file_exists("%s/%s" % [dir, name]):
		name = "%s_%d.%s" % [stem, n, ext]
		n += 1
	return name


static func _remove_tree(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)
