@tool
extends VBoxContainer

# One beautiful still.

const GnUi := preload("res://addons/genesis/ui/gn_ui.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const GnPanorama := preload("res://addons/genesis/core/gn_panorama.gd")
const GnPasses := preload("res://addons/genesis/core/gn_passes.gd")
const GnTour := preload("res://addons/genesis/core/gn_tour.gd")
const GnUpscale := preload("res://addons/genesis/core/gn_upscale.gd")
const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

var _camera: OptionButton
var _size: OptionButton
var _quality: OptionButton
var _button: Button
var _all_button: Button
var _study_button: Button
var _pano_button: Button
var _stereo: CheckBox
var _passes_button: Button
var _tour_button: Button
var _upscale_factor: OptionButton
var _upscale_button: Button
var _result: Label
var _last_path := ""

const QUALITY := {"Standard": 0, "Photoreal (16 samples)": 16, "Photoreal (64 samples)": 64}


func _init() -> void:
	name = "Render"
	_camera = GnUi.option(self, "Camera", [], func(_t): pass)
	_size = GnUi.option(self, "Size", GnRender.SIZES.keys(), func(_t): pass)
	# Photoreal averages many renders: true lens blur, soft sun shadows and
	# clean edges, for about twice the time at 16 samples.
	_quality = GnUi.option(self, "Quality", QUALITY.keys(), func(_t): pass)
	GnUi.select_text(_quality, "Photoreal (16 samples)")
	_button = GnUi.button(self, "Render still", _render)
	_all_button = GnUi.button(self, "Render every camera", _render_all)
	_study_button = GnUi.button(self, "Sun study: 9:00, 12:00, 15:00", _sun_study)
	_pano_button = GnUi.button(self, "360° panorama from this camera", _panorama)
	_stereo = CheckBox.new()
	_stereo.text = "Stereo, for VR headsets (3D 360, top-bottom)"
	add_child(_stereo)
	_tour_button = GnUi.button(self, "Virtual tour of every camera (one web page)", _tour)
	_passes_button = GnUi.button(self, "Render passes (depth, normals, ID, mask, clay)", _passes)
	# AI upscaling: a 4K still to 8K in seconds rather than rendering 8K.
	_upscale_factor = GnUi.option(self, "AI upscale", ["×2", "×4"], func(_t): pass)
	_upscale_button = GnUi.button(self, "AI upscale the last render", _upscale)
	if GnUpscale.available() and not GnUpscale.installed():
		_upscale_button.tooltip_text = "The first time, this downloads the free Real-ESRGAN upscaler (%d MB)." % GnUpscale.download_mb()
	_upscale_factor.get_parent().visible = GnUpscale.available()
	_upscale_button.visible = GnUpscale.available()
	_result = GnUi.note(self, "")
	GnUi.button(self, "Show renders folder", func():
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(
			_last_path if _last_path != "" else GnRender.OUTPUT_DIR)))


func refresh() -> void:
	var keep := _camera.get_item_text(_camera.selected) if _camera.selected >= 0 else ""
	_camera.clear()
	for cam in GnCameras.cameras():
		_camera.add_item(cam.name)
	GnUi.select_text(_camera, keep)
	_button.disabled = _camera.item_count == 0
	_all_button.disabled = _camera.item_count < 2
	_study_button.disabled = _camera.item_count == 0
	_pano_button.disabled = _camera.item_count == 0
	_tour_button.disabled = _camera.item_count == 0
	_passes_button.disabled = _camera.item_count == 0
	if _camera.item_count == 0:
		_result.text = "Save a view on the Cameras tab first."


# A 360 image from where the camera stands: 8192 wide for a full-size
# output, 4096 otherwise. Viewable in any 360 viewer or social site.
func _panorama() -> void:
	var cams := GnCameras.cameras()
	var cam := cams[_camera.selected] if _camera.selected >= 0 and _camera.selected < cams.size() else null
	if cam == null:
		return
	var size: Vector2i = GnRender.SIZES[_size.get_item_text(_size.selected)]
	_pano_button.disabled = true
	var path := ""
	if _stereo.button_pressed:
		_result.text = "Rendering both eyes all the way round…"
		path = await GnPanorama.render_stereo(cam, 8192 if size.x >= 3840 else 4096, self)
	else:
		_result.text = "Rendering the six directions…"
		path = await GnPanorama.render(cam, 8192 if size.x >= 3840 else 4096, self)
	_pano_button.disabled = false
	if path != "":
		_last_path = path
	_result.text = "Saved %s" % path if path != "" else "The panorama failed. See the Output panel."


# A 360 from every camera, walkable from one to the next, in a single web
# page. Opens in the browser when done.
func _tour() -> void:
	var cams := GnCameras.cameras()
	if cams.is_empty():
		return
	var size: Vector2i = GnRender.SIZES[_size.get_item_text(_size.selected)]
	var root := GnScene.root()
	var title := root.name if root else "Virtual tour"
	_tour_button.disabled = true
	_result.text = "Rendering the tour: 0 of %d views…" % cams.size()
	var path: String = await GnTour.export_tour(cams, title, _stereo.button_pressed, 8192 if size.x >= 3840 else 4096, self,
		func(done, total): _result.text = "Rendering the tour: %d of %d views…" % [done, total])
	_tour_button.disabled = false
	if path == "":
		_result.text = "The tour failed. See the Output panel."
		return
	_last_path = path
	_result.text = "Saved %s. It opens in any browser; send the file itself to share it. For VR, put it on any https web host and open it in the headset's browser." % path.get_file()
	OS.shell_open(ProjectSettings.globalize_path(path))


# The compositing passes for the chosen camera, at the chosen size.
# Enlarges the last still with Real-ESRGAN, fetching it the first time.
func _upscale() -> void:
	if _last_path == "" or not _last_path.ends_with(".png"):
		_result.text = "Render a still first; the upscale works on the last one."
		return
	_upscale_button.disabled = true
	if not GnUpscale.installed():
		var err: String = await GnUpscale.install(self, func(got, total):
			_result.text = "Downloading the free Real-ESRGAN upscaler: %d of %d MB…" % [roundi(got / 1e6), roundi(total / 1e6)])
		if err != "":
			_result.text = err
			_upscale_button.disabled = false
			return
		_upscale_button.tooltip_text = ""
	var factor := 4 if _upscale_factor.selected == 1 else 2
	_result.text = "Upscaling %s ×%d…" % [_last_path.get_file(), factor]
	var out: Dictionary = await GnUpscale.upscale(_last_path, factor, self)
	_upscale_button.disabled = false
	if out.error != "":
		_result.text = out.error
		return
	_last_path = out.path
	var size := Image.load_from_file(ProjectSettings.globalize_path(out.path)).get_size()
	_result.text = "Saved %s (%d × %d). AI upscaling sharpens edges; check very fine patterns, which it can invent." % [
		out.path.get_file(), size.x, size.y]


func _passes() -> void:
	var cams := GnCameras.cameras()
	var cam := cams[_camera.selected] if _camera.selected >= 0 and _camera.selected < cams.size() else null
	if cam == null:
		return
	var size: Vector2i = GnRender.SIZES[_size.get_item_text(_size.selected)]
	_passes_button.disabled = true
	_result.text = "Rendering passes…"
	var out: Dictionary = await GnPasses.render(cam, size, self)
	_passes_button.disabled = false
	_result.text = "Saved %s passes in %s: %s." % [out.size(), GnRender.OUTPUT_DIR, ", ".join(out.keys())]


# The same view at three times of day: the shadow study planning
# applications ask for. The user's own time of day is put back afterwards.
func _sun_study() -> void:
	var cams := GnCameras.cameras()
	var cam := cams[_camera.selected] if _camera.selected >= 0 and _camera.selected < cams.size() else null
	if cam == null or not GnEnvironment.is_set_up():
		return
	var size: Vector2i = GnRender.SIZES[_size.get_item_text(_size.selected)]
	var keep: float = GnEnvironment.value("time_of_day")
	_study_button.disabled = true
	for hour in [9.0, 12.0, 15.0]:
		_result.text = "Sun study: rendering %d:00…" % int(hour)
		GnEnvironment.apply("time_of_day", hour, false)
		var path: String = await GnRender.render(cam, size, self, true, Viewport.DEBUG_DRAW_DISABLED, false, _samples())
		if path != "":
			var named := "%s/%s_sun_study_%02d00.png" % [GnRender.OUTPUT_DIR, str(cam.name).replace(" ", ""), int(hour)]
			DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(named))
			_last_path = named
	GnEnvironment.apply("time_of_day", keep, false)
	_study_button.disabled = false
	_result.text = "Sun study saved: 9:00, 12:00 and 15:00 in %s." % GnRender.OUTPUT_DIR


# Every saved view in order: the presentation set, in one click.
func _render_all() -> void:
	var cams := GnCameras.cameras()
	var size: Vector2i = GnRender.SIZES[_size.get_item_text(_size.selected)]
	_button.disabled = true
	_all_button.disabled = true
	var done := 0
	for cam in cams:
		_result.text = "Rendering %s (%d of %d)…" % [cam.name, done + 1, cams.size()]
		var path: String = await GnRender.render(cam, size, self, true, Viewport.DEBUG_DRAW_DISABLED, false, _samples())
		if path != "":
			_last_path = path
			done += 1
	_button.disabled = false
	_all_button.disabled = false
	_result.text = "Rendered %d of %d cameras into %s." % [done, cams.size(), GnRender.OUTPUT_DIR]


func _render() -> void:
	var cams := GnCameras.cameras()
	var cam := cams[_camera.selected] if _camera.selected >= 0 and _camera.selected < cams.size() else null
	if cam == null:
		return
	_button.disabled = true
	_result.text = "Rendering…"
	var size: Vector2i = GnRender.SIZES[_size.get_item_text(_size.selected)]
	var path: String = await GnRender.render(cam, size, self, true, Viewport.DEBUG_DRAW_DISABLED, false, _samples())
	_button.disabled = false
	if path == "":
		_result.text = "The render failed. See the Output panel."
		return
	_last_path = path
	_result.text = "Saved %s" % path


func _samples() -> int:
	return QUALITY.get(_quality.get_item_text(maxi(_quality.selected, 0)), 0)
