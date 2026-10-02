@tool
extends RefCounted

# Weather and seasons, Lumion-style: rain, snow, wet ground, and leaves that
# change with the season. State lives as metadata on a "Weather" node, so it
# saves with the scene; the particles are children of it.
#
# Rain and snow are GPU particles over a box around the site. Pre-simulated,
# so a still captures falling rain rather than the first drops leaving the sky.
# Wet ground darkens the ground and makes it glossy so it mirrors the sky.
# Seasons tint the shared foliage materials; winter drops the leaves.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

const META := &"gn_weather"
const DEFAULTS := {"kind": "Clear", "amount": 0.6, "wet": 0.0, "puddles": 0.0, "season": "Summer", "area": 120.0}
const KINDS := ["Clear", "Rain", "Snow"]
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]

# Leaf tints by season, multiplied onto each foliage material's own colour.
const SEASON_TINT := {
	"Spring": Color(1.05, 1.15, 0.85), "Summer": Color(1, 1, 1),
	"Autumn": Color(1.45, 0.78, 0.35), "Winter": Color(0.85, 0.75, 0.6),
}
const FOLIAGE := ["res://genesis_data/plants/leaves_broad.tres", "res://genesis_data/plants/leaves_small.tres",
	"res://genesis_data/plants/grass_blades.tres"]


static func node() -> Node3D:
	return GnScene.find_role("weather") as Node3D


static func state() -> Dictionary:
	var out := DEFAULTS.duplicate()
	var n := node()
	if n:
		out.merge(n.get_meta(META, {}), true)
	return out


# Changes one setting (undoable) and rebuilds what it drives.
static func set_value(key: String, value: Variant) -> void:
	var n := node()
	if n == null:
		n = Node3D.new()
		n.name = "Weather"
		n.set_meta(META, {})
		GnScene.add_node(n, GnScene.root(), "Genesis: weather", "weather")
	var s: Dictionary = n.get_meta(META, {}).duplicate()
	s[key] = value
	GnScene.set_props("Genesis: %s" % key.capitalize(), [[n, "metadata/" + META, s]])
	apply()


# Makes the scene match the stored weather. Called after every change and
# when a scene opens, because foliage tints and particles are not saved.
static func apply() -> void:
	var s := state()
	var n := node()
	if n == null:
		_season(s)
		return
	for c in n.get_children():
		if c.has_meta(&"gn_generated"):
			n.remove_child(c)
			c.queue_free()
	if s.kind == "Rain":
		n.add_child(_particles(s, true))
	elif s.kind == "Snow":
		n.add_child(_particles(s, false))
	_ground(float(s.wet) if s.kind != "Snow" else 0.0, s.kind == "Snow" and float(s.amount) > 0.3, str(s.season))
	if s.kind != "Snow" and float(s.puddles) > 0.0:
		n.add_child(_puddles(float(s.puddles), float(s.area)))
	_season(s)


# Puddles: dark, glassy patches of standing water on whatever lies below
# them (paving, road, lawn), as decals, so they sit on any ground's shape.
static func _puddles(amount: float, area: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Puddles"
	holder.set_meta(&"gn_generated", true)
	var textures := _puddle_textures()
	var r := RandomNumberGenerator.new()
	r.seed = 1919
	var reach := minf(area * 0.35, 60.0)
	for i in int(amount * 60.0) + 1:
		var d := Decal.new()
		d.texture_albedo = textures[0]
		d.texture_orm = textures[1]
		d.texture_normal = textures[2]
		var s := r.randf_range(0.8, 3.5) * lerpf(0.7, 1.3, amount)
		d.size = Vector3(s * r.randf_range(1.0, 2.2), 1.0, s)
		d.position = Vector3(r.randf_range(-reach, reach), 0.0, r.randf_range(-reach, reach))
		d.rotation.y = r.randf() * TAU
		d.albedo_mix = 1.0
		d.normal_fade = 0.6
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		holder.add_child(d)
	return holder


static var _puddle_tex: Array = []


# The puddle's shape (soft, blotchy), its glassy roughness, and the faint
# ripple normal, drawn once.
static func _puddle_textures() -> Array:
	if not _puddle_tex.is_empty():
		return _puddle_tex
	var size := 256
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var albedo := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var orm := Image.create(size, size, false, Image.FORMAT_RGB8)
	var normal := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var p := Vector2(x, y) / size - Vector2(0.5, 0.5)
			var edge := p.length() * 2.0 + noise.get_noise_2d(x, y) * 0.55
			var water := clampf((0.9 - edge) * 6.0, 0.0, 1.0)
			albedo.set_pixel(x, y, Color(0.035, 0.04, 0.045, water * 0.85))
			# Occlusion, roughness, metal: wet and glassy.
			orm.set_pixel(x, y, Color(1.0, lerpf(0.6, 0.02, water), 0.0))
			var rip := noise.get_noise_2d(x * 6.0, y * 6.0) * 0.05
			normal.set_pixel(x, y, Color(0.5 + rip, 0.5 - rip, 1.0))
	_puddle_tex = [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(orm), ImageTexture.create_from_image(normal)]
	return _puddle_tex


static func _particles(s: Dictionary, rain: bool) -> GPUParticles3D:
	var area := float(s.area)
	var amount := float(s.amount)
	var p := GPUParticles3D.new()
	p.name = "Rain" if rain else "Snow"
	p.set_meta(&"gn_generated", true)
	p.amount = int((70000 if rain else 40000) * amount) + 100
	p.lifetime = 1.6 if rain else 12.0
	# Start mid-storm: a still must not catch the first drops leaving the sky.
	p.preprocess = p.lifetime * 2.0
	p.visibility_aabb = AABB(Vector3(-area, -5, -area), Vector3(area * 2, 45, area * 2))
	p.position = Vector3(0, 30, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area, 2, area)
	pm.direction = Vector3(0.08, -1, 0.05) if rain else Vector3(0, -1, 0)
	pm.spread = 2.0 if rain else 20.0
	pm.initial_velocity_min = 16.0 if rain else 0.8
	pm.initial_velocity_max = 20.0 if rain else 1.6
	pm.gravity = Vector3(0, -9.8, 0) if rain else Vector3(0, -0.4, 0)
	if not rain:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_scale = 4.0
	p.process_material = pm
	var quad := QuadMesh.new()
	# Big enough to register at 1080p from a few metres away; real drops and
	# flakes are smaller, but a render must show that it is raining.
	quad.size = Vector2(0.025, 0.9) if rain else Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.88, 0.92, 0.55) if rain else Color(1, 1, 1, 0.95)
	# Rain streaks stay upright and face the camera round the vertical axis;
	# snowflakes just face the camera.
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if rain else BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


# Ground tint by season: summer's own colour, browner in autumn, straw in winter.
const GROUND_TINT := {"Spring": Color(1.0, 1.05, 0.95), "Summer": Color(1, 1, 1),
	"Autumn": Color(1.1, 0.95, 0.7), "Winter": Color(1.05, 0.92, 0.72)}


# The ground's material, remembered as it was the first time, then changed
# for the conditions: snow replaces the lawn with white; wet ground darkens
# and goes nearly mirror-smooth so it reflects the sky and the buildings.
static func _ground(wet: float, snow: bool, season: String) -> void:
	var ground := GnScene.find_role("ground") as MeshInstance3D
	if ground == null or ground.mesh == null:
		return
	var mat := ground.mesh.surface_get_material(0) as BaseMaterial3D
	if mat == null:
		return
	if not mat.has_meta(&"gn_dry"):
		mat.set_meta(&"gn_dry", {"roughness": mat.roughness, "albedo": mat.albedo_color,
			"texture": mat.albedo_texture, "detail": mat.detail_enabled})
	var dry: Dictionary = mat.get_meta(&"gn_dry")
	if snow:
		# Snow covers the lawn: the grass texture goes, not tinted white.
		mat.albedo_texture = null
		mat.detail_enabled = false
		mat.albedo_color = Color(0.92, 0.93, 0.96)
		mat.roughness = 0.85
		return
	mat.albedo_texture = dry.texture
	mat.detail_enabled = dry.detail
	var tint: Color = GROUND_TINT.get(season, Color.WHITE)
	mat.roughness = lerpf(float(dry.roughness), 0.08, wet)
	mat.albedo_color = ((dry.albedo as Color) * tint).darkened(0.45 * wet)


static func _season(s: Dictionary) -> void:
	var tint: Color = SEASON_TINT.get(s.season, Color.WHITE)
	for path in FOLIAGE:
		if not ResourceLoader.exists(path):
			continue
		var m := load(path) as BaseMaterial3D
		if not m.has_meta(&"gn_base"):
			m.set_meta(&"gn_base", {"albedo": m.albedo_color, "scissor": m.alpha_scissor_threshold})
		var base: Dictionary = m.get_meta(&"gn_base")
		var is_grass: bool = path.ends_with("grass_blades.tres")
		var c: Color = (base.albedo as Color) * tint
		# Winter: the trees are bare. Zero alpha cuts every leaf card away (a
		# higher scissor threshold does not, with alpha-to-coverage on).
		# Grass stays, browned.
		c.a = 0.0 if s.season == "Winter" and not is_grass else (base.albedo as Color).a
		m.albedo_color = c
