@tool
extends Node3D

# Special effects as one object each: the landscape ones Lumion has (fire,
# smoke, a fountain jet, falling leaves) and the ones shows use (confetti,
# CO2 jets, cold sparks, flame projectors). Each is GPU particles, warmed up
# before it is seen, so a still shows a full plume rather than the first
# frame. Size scales the whole effect; amount scales how dense it is.

const KINDS := ["Fire", "Smoke", "Fountain", "Falling leaves", "Confetti", "CO2 jet", "Cold sparks", "Flame projector"]

@export_enum("Fire", "Smoke", "Fountain", "Falling leaves", "Confetti", "CO2 jet", "Cold sparks", "Flame projector")
var kind: String = "Fire":
	set(v): kind = v; _queue()
## 1 is the natural size: a campfire, a 3 m fountain, a 4 m CO2 jet.
@export_range(0.1, 10.0, 0.05) var size: float = 1.0:
	set(v): size = v; _queue()
@export_range(0.1, 4.0, 0.05) var amount: float = 1.0:
	set(v): amount = v; _queue()
## Confetti colours, water tint, spark colour; ignored by fire and smoke.
@export var colour: Color = Color(1, 1, 1):
	set(v): colour = v; _queue()

var _pending := false


func _ready() -> void:
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


func particles() -> GPUParticles3D:
	for c in get_children():
		if c is GPUParticles3D:
			return c
	return null


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	var s := size
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_texture = _soft_dot()
	var quad := QuadMesh.new()
	m.direction = Vector3.UP
	var count := 100
	var life := 1.0
	match kind:
		"Fire", "Flame projector":
			var tall := kind == "Flame projector"
			count = 260 if tall else 200
			life = 0.8 if tall else 1.0
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = (0.12 if tall else 0.28) * s
			m.spread = 8.0 if tall else 14.0
			m.initial_velocity_min = (5.0 if tall else 1.0) * s
			m.initial_velocity_max = (6.5 if tall else 1.8) * s
			m.gravity = Vector3(0, 1.5 * s, 0)
			m.scale_curve = _curve([1.0, 0.8, 0.0])
			# Each lick faint and orange: hundreds overlap, and only the heart
			# should burn out to yellow-white.
			m.color_ramp = _ramp([Color(1, 0.7, 0.3, 0.5), Color(1, 0.38, 0.06, 0.45), Color(0.3, 0.05, 0.0, 0)])
			look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			quad.size = Vector2.ONE * (0.8 if tall else 0.6) * s
			var glow := OmniLight3D.new()
			glow.light_color = Color(1.0, 0.55, 0.2)
			glow.light_energy = (6.0 if tall else 3.0) * amount
			glow.omni_range = (10.0 if tall else 6.0) * s
			glow.position = Vector3(0, (1.5 if tall else 0.4) * s, 0)
			glow.set_meta(&"gn_generated", true)
			add_child(glow)
		"Smoke":
			count = 120
			life = 6.0
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			m.emission_sphere_radius = 0.3 * s
			m.spread = 20.0
			m.initial_velocity_min = 0.4 * s
			m.initial_velocity_max = 0.8 * s
			m.gravity = Vector3(0.15, 0.3, 0) * s
			m.turbulence_enabled = true
			m.turbulence_noise_strength = 0.6
			m.scale_curve = _curve([0.5, 1.6, 3.0])
			m.color_ramp = _ramp([Color(0.5, 0.5, 0.52, 0.0), Color(0.45, 0.45, 0.47, 0.35), Color(0.6, 0.6, 0.62, 0.0)])
			quad.size = Vector2.ONE * 1.2 * s
		"Fountain":
			# Speed for the height asked: v = sqrt(2 g h).
			count = 700
			life = 1.7 * sqrt(s)
			var v := sqrt(2.0 * 9.8 * 3.0 * s)
			m.spread = 5.0
			m.initial_velocity_min = v * 0.9
			m.initial_velocity_max = v
			m.gravity = Vector3(0, -9.8, 0)
			var water := Color(0.72, 0.84, 1.0) if colour == Color(1, 1, 1) else colour
			m.color_ramp = _ramp([Color(water, 0.8), Color(water, 0.35)])
			quad.size = Vector2.ONE * 0.07 * sqrt(s)
		"Falling leaves":
			count = 160
			life = 9.0
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			m.emission_box_extents = Vector3(5.0, 0.5, 5.0) * s
			m.direction = Vector3.DOWN
			m.initial_velocity_min = 0.2
			m.initial_velocity_max = 0.5
			m.gravity = Vector3(0.2, -0.7, 0)
			m.turbulence_enabled = true
			m.turbulence_noise_strength = 1.2
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -120.0
			m.angular_velocity_max = 120.0
			m.color_initial_ramp = _ramp([Color(0.75, 0.45, 0.1), Color(0.6, 0.2, 0.05), Color(0.8, 0.65, 0.2), Color(0.45, 0.3, 0.1)])
			look.albedo_texture = null
			look.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			look.cull_mode = BaseMaterial3D.CULL_DISABLED
			look.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			quad.size = Vector2(0.07, 0.05)
		"Confetti":
			count = 900
			life = 7.0
			m.spread = 28.0
			m.initial_velocity_min = 9.0 * sqrt(s)
			m.initial_velocity_max = 13.0 * sqrt(s)
			m.gravity = Vector3(0, -2.5, 0)
			m.damping_min = 2.5
			m.damping_max = 3.5
			m.turbulence_enabled = true
			m.turbulence_noise_strength = 0.8
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -400.0
			m.angular_velocity_max = 400.0
			m.color_initial_ramp = _ramp([Color(1, 0.2, 0.4), Color(1, 0.85, 0.2), Color(0.2, 0.7, 1), Color(0.3, 1, 0.5),
				Color(1, 1, 1), colour])
			look.albedo_texture = null
			look.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			look.cull_mode = BaseMaterial3D.CULL_DISABLED
			quad.size = Vector2(0.03, 0.05)
		"CO2 jet":
			count = 320
			life = 0.9
			m.spread = 5.0
			m.initial_velocity_min = 9.0 * sqrt(s)
			m.initial_velocity_max = 11.0 * sqrt(s)
			m.damping_min = 7.0
			m.damping_max = 9.0
			m.scale_curve = _curve([0.4, 1.5, 3.0])
			m.color_ramp = _ramp([Color(1, 1, 1, 0.7), Color(0.95, 0.97, 1, 0.45), Color(0.9, 0.93, 1, 0.0)])
			quad.size = Vector2.ONE * 0.7 * s
		"Cold sparks":
			count = 450
			life = 1.3 * sqrt(s)
			m.spread = 4.0
			var up := sqrt(2.0 * 9.8 * 3.5 * s)
			m.initial_velocity_min = up * 0.85
			m.initial_velocity_max = up
			m.gravity = Vector3(0, -9.8, 0)
			var spark := colour if colour != Color(1, 1, 1) else Color(1.0, 0.8, 0.45)
			m.color_ramp = _ramp([Color(1, 1, 0.9, 1), spark, Color(spark.r, spark.g * 0.6, 0.1, 0)])
			look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			quad.size = Vector2.ONE * 0.035
			# The machine the sparks come out of.
			var unit := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.36, 0.28, 0.36)
			unit.mesh = box
			unit.position = Vector3(0, -0.14, 0)
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.04, 0.04, 0.045)
			unit.material_override = dark
			unit.set_meta(&"gn_generated", true)
			add_child(unit)
	quad.material = look
	p.draw_pass_1 = quad
	p.process_material = m
	p.amount = maxi(int(count * amount), 1)
	p.lifetime = life
	# Warm up, so a still (or the first frame of a movie) shows a full plume.
	p.preprocess = life
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-12, -12, -12) * s, Vector3(24, 30, 24) * s)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.name = kind
	p.set_meta(&"gn_generated", true)
	add_child(p)


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	# The range first: points above it would be clipped as they are added.
	c.max_value = 4.0
	for i in points.size():
		c.add_point(Vector2(float(i) / (points.size() - 1), points[i]))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _ramp(colours: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colours.size():
		offsets.append(float(i) / maxf(colours.size() - 1, 1))
	g.offsets = offsets
	g.colors = PackedColorArray(colours)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static var _dot: Texture2D

# A soft round blob: the shape of every flame lick, puff and droplet.
static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_dot = t
	return t
