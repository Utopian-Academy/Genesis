@tool
extends Control

# A live picture of what a saved camera will render: its lens, exposure,
# depth of field and finishing look, following the camera as it is moved.
# With photo match on, the site photo sits behind the design, so the camera
# can be lined up by eye. Used by the Cameras, Look and Movie sections.

const GnLook := preload("res://addons/genesis/core/gn_look.gd")
const GnPhotomatch := preload("res://addons/genesis/core/gn_photomatch.gd")

var camera: Camera3D

var _photo: TextureRect
var _box: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _post: ShaderMaterial
var _shown := {}
var _shown_photo := ""


func _init() -> void:
	custom_minimum_size = Vector2(260, 146)
	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_photo)
	_box = SubViewportContainer.new()
	_box.stretch = true
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_box)
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_box.add_child(_vp)
	_post = GnLook.post_material(GnLook.DEFAULTS)
	_box.material = _post


func _process(_delta: float) -> void:
	visible = is_instance_valid(camera)
	if not visible:
		return
	if _vp.world_3d == null:
		var editor_vp := EditorInterface.get_editor_viewport_3d(0)
		if editor_vp:
			_vp.world_3d = editor_vp.find_world_3d()
	var look := GnLook.get_look(camera)
	GnLook.apply_lens(_cam, camera, look)
	if look != _shown:
		# Rebuilt only when the look changes, not every frame.
		GnLook.apply_camera(_cam, look, 10.0)
		GnLook.update_post(_post, look)
		_shown = look
	if float(look.get("flare", 0.0)) > 0.0:
		_post.set_shader_parameter("sun_uv", GnLook.sun_uv(_cam, Vector2(_vp.size)))
	var photo := GnPhotomatch.photo(camera)
	if photo != _shown_photo:
		var img := GnPhotomatch.load_photo(camera)
		_photo.texture = ImageTexture.create_from_image(img) if img else null
		# The preview shows the design half over the photo: enough to line up
		# edges against. The final render composites properly.
		_box.modulate.a = 0.75 if img else 1.0
		_shown_photo = photo
	_cam.make_current()
