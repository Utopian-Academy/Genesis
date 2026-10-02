@tool
extends Node3D

# A light as the thing a lighting designer or an architect would specify:
# a moving-head beam, a wash, a recessed downlight or a bare bulb, with its
# colour, output and beam angle. Pan and tilt aim the head. With haze on
# (Environment section) spot beams show in the air, as they do on a show.
#
# Output is in lumens-ish "brightness" rather than Godot light energy, and
# converted here, so a 17,000 lm beam and a 700 lm downlight feel right next
# to each other.

const GnAssets := preload("res://addons/genesis/core/gn_assets.gd")
const GnIes := preload("res://addons/genesis/core/gn_ies.gd")

@export_enum("Beam (moving head)", "Wash", "Downlight", "Bulb") var kind: String = "Beam (moving head)":
	set(v): kind = v; _queue()
@export var colour: Color = Color(1.0, 0.95, 0.85):
	set(v): colour = v; _tune()
## Luminous output in lumens.
@export_range(50.0, 50000.0, 50.0, "exp") var lumens: float = 12000.0:
	set(v): lumens = v; _tune()
## How far up it is, 0 (out) to 1 (full): what a show's cues fade.
@export_range(0.0, 1.0, 0.01) var dimmer: float = 1.0:
	set(v): dimmer = v; _tune()
@export_range(2.0, 120.0, 0.5) var beam_degrees: float = 8.0:
	set(v): beam_degrees = v; _tune()
@export_range(-270.0, 270.0, 1.0) var pan: float = 0.0:
	set(v): pan = v; _tune()
@export_range(-135.0, 135.0, 1.0) var tilt: float = -60.0:
	set(v): tilt = v; _tune()
## How strongly the beam shows in haze.
@export_range(0.0, 4.0, 0.05) var beam_in_haze: float = 1.0:
	set(v): beam_in_haze = v; _tune()
@export var casts_shadows: bool = true:
	set(v): casts_shadows = v; _queue()
## A fixture model from the library to show instead of the simple shape.
## Moving heads pan and tilt their yoke and head to aim.
@export var model: String = "":
	set(v): model = v; _queue()
## Hung from truss (base up) rather than standing on the deck.
@export var hung: bool = true:
	set(v): hung = v; _queue()
## A manufacturer's IES photometry file: its beam shape, cone and lumens
## replace the settings above (spot kinds only).
@export_file("*.ies") var ies: String = "":
	set(v): ies = v; _queue()

var _pending := false
# What a quick change (colour, dimmer, pan, tilt, zoom) touches, kept from
# the last rebuild so a fading cue never rebuilds the fixture.
var _light: Light3D
var _lens_mat: StandardMaterial3D
var _yoke: Node3D
var _head: Node3D
var _model_yoke: Node3D
var _model_head: Node3D
var _model_holder: Node3D
var _ies_lumens := 0.0


func _ready() -> void:
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


# Colour, output, aim and zoom change in place when the fixture is built.
func _tune() -> void:
	if _pending or not is_instance_valid(_light):
		_queue()
		return
	_light.light_color = colour
	var out := _ies_lumens if _ies_lumens > 0.0 else lumens
	_light.light_energy = out / 1500.0 * dimmer
	_light.visible = dimmer > 0.001
	_light.light_volumetric_fog_energy = beam_in_haze * 30.0
	if _light is SpotLight3D and _ies_lumens <= 0.0:
		(_light as SpotLight3D).spot_angle = beam_degrees * 0.5
		(_light as SpotLight3D).spot_range = sqrt(lumens) * (0.9 if kind == "Beam (moving head)" else 0.5)
	elif _light is OmniLight3D:
		(_light as OmniLight3D).omni_range = sqrt(lumens) * 0.35
	if _lens_mat:
		_lens_mat.albedo_color = colour.lightened(0.3) * lerpf(0.15, 1.0, dimmer)
		_lens_mat.emission = colour
		_lens_mat.emission_energy_multiplier = 4.0 * dimmer
	_yoke.rotation_degrees = Vector3(0, pan, 0)
	_head.rotation_degrees = Vector3(tilt, 0, 0)
	if _model_yoke and _model_head:
		_aim_model()


# A moving-head model's own yoke and head, turned so its beam points where ours does.
func _aim_model() -> void:
	var want := (_yoke.basis * _head.basis) * Vector3.FORWARD
	var local := _model_holder.basis.inverse() * want
	var t := acos(clampf(local.y, -1.0, 1.0))
	_model_yoke.rotation = Vector3(0, atan2(local.x, local.z), 0)
	_model_head.rotation = Vector3(t, 0, 0)


func _validate_property(property: Dictionary) -> void:
	# The model list is whatever fixtures the library holds.
	if property.name == "model":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(GnAssets.of_kind("lighting", []).map(func(a): return a.path))


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.06, 0.06, 0.065)
	body_mat.roughness = 0.5
	body_mat.metallic = 0.3
	_model_yoke = null
	_model_head = null
	_model_holder = null
	_ies_lumens = 0.0
	var lens_mat := StandardMaterial3D.new()
	lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lens_mat.albedo_color = colour.lightened(0.3)
	lens_mat.emission_enabled = true
	lens_mat.emission = colour
	lens_mat.emission_energy_multiplier = 4.0

	# The head: pans about Y, tilts about its own X. The light points down
	# its -Z, like every Godot light.
	var yoke := Node3D.new()
	yoke.rotation_degrees = Vector3(0, pan, 0)
	yoke.set_meta(&"gn_generated", true)
	add_child(yoke)
	var head := Node3D.new()
	head.rotation_degrees = Vector3(tilt, 0, 0)
	yoke.add_child(head)

	var light: Light3D
	var shown := _show_model(yoke, head)
	match kind:
		"Bulb":
			var omni := OmniLight3D.new()
			omni.omni_range = sqrt(lumens) * 0.35
			light = omni
			if shown == null:
				_part(head, _sphere(0.06), lens_mat, Vector3.ZERO)
		_:
			var spot := SpotLight3D.new()
			spot.spot_angle = beam_degrees * 0.5
			spot.spot_angle_attenuation = 0.4 if kind == "Beam (moving head)" else 1.2
			spot.spot_range = sqrt(lumens) * (0.9 if kind == "Beam (moving head)" else 0.5)
			light = spot
			match "" if shown != null else kind:
				"Beam (moving head)":
					_part(yoke, _box(Vector3(0.36, 0.14, 0.28)), body_mat, Vector3(0, -0.07, 0))
					_part(head, _cyl(0.13, 0.42), body_mat, Vector3(0, 0, 0.05), Vector3(90, 0, 0))
					_part(head, _cyl(0.1, 0.01), lens_mat, Vector3(0, 0, -0.17), Vector3(90, 0, 0))
				"Wash":
					_part(head, _cyl(0.2, 0.3), body_mat, Vector3(0, 0, 0.05), Vector3(90, 0, 0))
					_part(head, _cyl(0.18, 0.01), lens_mat, Vector3(0, 0, -0.1), Vector3(90, 0, 0))
				"Downlight":
					_part(head, _cyl(0.05, 0.01), lens_mat, Vector3(0, 0, -0.005), Vector3(90, 0, 0))
	# Lumens to Godot energy: tuned by eye so a 700 lm downlight lights a
	# room and a 17,000 lm beam reads across a stage at night.
	light.light_energy = lumens / 1500.0 * dimmer
	if ies != "" and light is SpotLight3D and FileAccess.file_exists(ies):
		var profile := GnIes.load_file(ies)
		if profile:
			GnIes.apply(light, profile)
			light.light_energy = profile.lumens / 1500.0 * dimmer
			light.spot_range = sqrt(profile.lumens) * 0.5
			_ies_lumens = profile.lumens
	light.visible = dimmer > 0.001
	lens_mat.albedo_color = colour.lightened(0.3) * lerpf(0.15, 1.0, dimmer)
	lens_mat.emission_energy_multiplier = 4.0 * dimmer
	_light = light
	_lens_mat = lens_mat
	_yoke = yoke
	_head = head
	light.light_color = colour
	light.shadow_enabled = casts_shadows
	# Godot's volumetric fog needs a strong push to show a narrow beam: 30
	# was the value where an 8-degree beam read clearly in tests.
	light.light_volumetric_fog_energy = beam_in_haze * 30.0
	light.set_meta(&"gn_generated", true)
	if shown != null:
		# From the model's lens, along its beam (the head's +Y).
		light.rotation_degrees = Vector3(90, 0, 0)
		light.position = Vector3(0, 0.2, 0)
		shown.add_child(light)
	else:
		head.add_child(light)


# Puts the library model in, aimed where pan and tilt say. Returns the node
# the light should hang from (the model's head), or null for the simple shape.
func _show_model(yoke: Node3D, head: Node3D) -> Node3D:
	if model == "" or not ResourceLoader.exists(model):
		return null
	var inst := (load(model) as PackedScene).instantiate() as Node3D
	var m_yoke := inst.find_child("Yoke", true, false) as Node3D
	var m_head := inst.find_child("Head", true, false) as Node3D
	if m_yoke and m_head:
		# A moving head: its own yoke pans and its head tilts. Its beam is its
		# head's +Y; find the pan and tilt that point it where ours points.
		var holder := Node3D.new()
		holder.set_meta(&"gn_generated", true)
		if hung:
			holder.rotation_degrees = Vector3(180, 0, 0)
		add_child(holder)
		holder.add_child(inst)
		_yoke = yoke
		_head = head
		_model_yoke = m_yoke
		_model_head = m_head
		_model_holder = holder
		_aim_model()
		return m_head
	# A fixed fixture: the whole thing turns, beam (+Y) along our -Z.
	var turned := Node3D.new()
	turned.rotation_degrees = Vector3(-90, 0, 0)
	turned.position = Vector3(0, 0, 0.15)
	head.add_child(turned)
	turned.add_child(inst)
	return turned


func _part(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 20
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2
	return m
