@tool
extends Node3D

# An area light: light from a surface, not a point. A softbox, an LED panel,
# a ceiling light, a skylight, a window's glow, a cove strip. Godot has no
# area lights, so this is the next best thing: the glowing panel itself, and
# behind it a small grid of wide spotlights sharing its output, each as big
# as its share of the panel, which is what makes their shadows soft the way
# an area light's are (Godot's light size gives soft, contact-hardening
# shadows).
#
# The panel faces down its -Z, like every Godot light: hang it from a ceiling
# and it lights the room below.

@export_enum("Rectangle", "Strip", "Disc") var shape: String = "Rectangle":
	set(v): shape = v; _queue()
## Width and height of the panel, metres (a disc uses the width).
@export var size: Vector2 = Vector2(1.2, 0.6):
	set(v): size = v; _queue()
@export var colour: Color = Color(1.0, 0.96, 0.9):
	set(v): colour = v; _tune()
## Colour temperature instead of a colour (0 uses the colour above).
@export_range(0.0, 10000.0, 100.0) var kelvin: float = 0.0:
	set(v): kelvin = v; _tune()
## Total output, lumens (a 60 x 60 cm office panel is about 3,600).
@export_range(10.0, 200000.0, 10.0, "exp") var lumens: float = 4000.0:
	set(v): lumens = v; _tune()
## 0-1, as a show's cues fade it.
@export_range(0.0, 1.0, 0.01) var dimmer: float = 1.0:
	set(v): dimmer = v; _tune()
## Light both ways (a hanging panel lit on both faces).
@export var two_sided: bool = false:
	set(v): two_sided = v; _queue()
@export var show_panel: bool = true:
	set(v): show_panel = v; _queue()
@export var casts_shadows: bool = true:
	set(v): casts_shadows = v; _queue()
## How far the light carries, metres.
@export_range(1.0, 200.0, 0.5) var reach: float = 12.0:
	set(v): reach = v; _tune()

var _pending := false
var _lights: Array = []
var _panel_mat: StandardMaterial3D


func _ready() -> void:
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


## The light's colour: the colour, or a black body at `kelvin`.
func light_colour() -> Color:
	return colour if kelvin <= 0.0 else kelvin_colour(kelvin)


## An approximation of a black body's colour (Tanner Helland's fit).
static func kelvin_colour(k: float) -> Color:
	var t := clampf(k, 1000.0, 40000.0) / 100.0
	var r := 255.0 if t <= 66.0 else 329.698727446 * pow(t - 60.0, -0.1332047592)
	var g := 99.4708025861 * log(t) - 161.1195681661 if t <= 66.0 else 288.1221695283 * pow(t - 60.0, -0.0755148492)
	var b := 255.0 if t >= 66.0 else (0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307)
	return Color(clampf(r, 0, 255) / 255.0, clampf(g, 0, 255) / 255.0, clampf(b, 0, 255) / 255.0)


# Where the lights sit on the panel: a grid that suits its shape.
func _points() -> Array:
	var out: Array = []
	var w := size.x
	var h := size.y if shape != "Disc" else size.x
	match shape:
		"Disc":
			out.append(Vector2.ZERO)
			if w > 0.5:
				for i in 6:
					out.append(Vector2(cos(TAU * i / 6.0), sin(TAU * i / 6.0)) * w * 0.3)
		_:
			var nx := clampi(int(ceil(w / 0.8)), 1, 5)
			var ny := clampi(int(ceil(h / 0.8)), 1, 5)
			for ix in nx:
				for iy in ny:
					out.append(Vector2((ix + 0.5) / nx - 0.5, (iy + 0.5) / ny - 0.5) * Vector2(w, h))
	return out


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	_lights.clear()
	var w := size.x
	var h := size.y if shape != "Disc" else size.x
	# The glowing panel.
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED if two_sided else BaseMaterial3D.CULL_BACK
	if show_panel:
		var mi := MeshInstance3D.new()
		mi.name = "Panel"
		if shape == "Disc":
			var disc := CylinderMesh.new()
			disc.top_radius = w * 0.5
			disc.bottom_radius = w * 0.5
			disc.height = 0.01
			disc.radial_segments = 32
			mi.mesh = disc
			mi.rotation_degrees = Vector3(90, 0, 0)
		else:
			var q := QuadMesh.new()
			q.size = Vector2(w, h)
			mi.mesh = q
			# A quad faces +Z; the light faces -Z.
			mi.rotation_degrees = Vector3(0, 180, 0)
		mi.material_override = _panel_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta(&"gn_generated", true)
		add_child(mi)
	# The lights: wide spots just in front of the panel, sharing the output.
	var pts := _points()
	var cell := sqrt(w * h / pts.size()) if shape != "Strip" else maxf(w / pts.size(), h)
	var sides := [1.0, -1.0] if two_sided else [1.0]
	var shadowed := 0
	for s in sides:
		for p in pts:
			var spot := SpotLight3D.new()
			spot.spot_angle = 80.0
			spot.spot_angle_attenuation = 0.6
			spot.position = Vector3(p.x, p.y, -0.02 * s)
			if s < 0.0:
				spot.rotation_degrees = Vector3(0, 180, 0)
			# Soft, contact-hardening shadows from a source this big.
			spot.light_size = clampf(cell, 0.05, 2.0)
			spot.shadow_enabled = casts_shadows and shadowed < 4
			if spot.shadow_enabled:
				shadowed += 1
			spot.set_meta(&"gn_generated", true)
			add_child(spot)
			_lights.append(spot)
	_tune()


func _tune() -> void:
	if _lights.is_empty():
		_queue()
		return
	var c := light_colour()
	# Lumens to Godot energy as the fixtures do (1,500 lm to 1.0), shared out.
	var each := lumens / 1500.0 * dimmer / _lights.size()
	for l in _lights:
		if not is_instance_valid(l):
			continue
		(l as SpotLight3D).light_color = c
		(l as SpotLight3D).light_energy = each
		(l as SpotLight3D).spot_range = reach
		(l as SpotLight3D).visible = dimmer > 0.001
	if _panel_mat:
		_panel_mat.albedo_color = c * lerpf(0.05, 1.0, dimmer)
		# Bright enough to bloom, as a real panel does to a camera.
		_panel_mat.emission_enabled = true
		_panel_mat.emission = c
		_panel_mat.emission_energy_multiplier = 2.0 * dimmer


func report_text() -> String:
	var area := size.x * size.y if shape != "Disc" else PI * size.x * size.x * 0.25
	return "%s, %.2f m², %.0f lm (%.0f lm/m²), %d light%s behind it" % [shape, area, lumens, lumens / maxf(area, 0.0001),
		_lights.size(), "" if _lights.size() == 1 else "s"]
