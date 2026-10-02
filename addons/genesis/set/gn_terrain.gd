@tool
extends Node3D

# Sculptable terrain: a square heightfield, centred on the node, shaped with
# the Landscape brush (raise, lower, smooth, flatten). The heights are an
# exported array, so they save with the scene and Godot's undo covers a
# stroke as one property change.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

@export_range(20.0, 2000.0, 10.0) var size: float = 200.0:
	set(v): size = v; _queue()
## Grid cells along each side. 128 is smooth enough for landscape at a few
## metres per cell and still rebuilds instantly while sculpting.
@export_range(16, 256, 1) var cells: int = 128:
	set(v):
		cells = v
		_resize_heights()
		_queue()
@export var heights: PackedFloat32Array = PackedFloat32Array():
	set(v): heights = v; _queue()
@export var material: Material:
	set(v): material = v; _queue()
## Up to four ground materials (presets by name) painted over the surface:
## "gravel", "earth", "sand", "rock", "forest_floor", "snow", "mud"...
@export var layers: PackedStringArray = PackedStringArray():
	set(v): layers = v; _queue()
## How much of each layer every point shows, four bytes a point.
@export var splat: PackedByteArray = PackedByteArray():
	set(v): splat = v; _queue()

## Ground presets that can be painted.
const GROUNDS := ["grass", "earth", "gravel", "sand", "rock", "forest_floor", "mud", "snow", "fallen_leaves", "paving",
	"asphalt", "concrete", "stone"]

var _pending := false
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	_resize_heights()
	_rebuild()


func _resize_heights() -> void:
	var n := (cells + 1) * (cells + 1)
	if heights.size() != n:
		var h := PackedFloat32Array()
		h.resize(n)
		heights = h
	if splat.size() != n * 4:
		var s := PackedByteArray()
		s.resize(n * 4)
		splat = s


## One dab of paint: layer 1-4 laid on, or 0 to wipe back to the surface.
## Strength 0-1 at the centre. Like sculpt(), the brush records the stroke
## for undo with the splat before and after.
func paint(world: Vector3, radius: float, strength: float, layer: int) -> void:
	var local := to_local(world)
	var step := size / cells
	var s := splat.duplicate()
	var r_cells := int(ceil(radius / step))
	var cx := int(round((local.x + size * 0.5) / step))
	var cz := int(round((local.z + size * 0.5) / step))
	for iz in range(maxi(cz - r_cells, 0), mini(cz + r_cells, cells) + 1):
		for ix in range(maxi(cx - r_cells, 0), mini(cx + r_cells, cells) + 1):
			var d := Vector2(ix * step - size * 0.5 - local.x, iz * step - size * 0.5 - local.z).length()
			if d > radius:
				continue
			var w := (0.5 + 0.5 * cos(PI * d / radius)) * strength
			var i := (iz * (cells + 1) + ix) * 4
			if layer <= 0:
				for k in 4:
					s[i + k] = int(s[i + k] * (1.0 - w))
				continue
			var k0 := clampi(layer - 1, 0, 3)
			s[i + k0] = mini(255, s[i + k0] + int(ceil(255.0 * w)))
			# The other layers give way, so the four never add up past full.
			var others := 0
			for k in 4:
				if k != k0:
					others += s[i + k]
			var room := 255 - s[i + k0]
			if others > room:
				for k in 4:
					if k != k0:
						s[i + k] = int(s[i + k] * float(room) / others)
	splat = s


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


func height_at_index(ix: int, iz: int) -> float:
	return heights[iz * (cells + 1) + ix]


# World-space height under a point, for dropping plants and cameras onto it.
func height_at(world: Vector3) -> float:
	var local := to_local(world)
	var step := size / cells
	var fx := clampf((local.x + size * 0.5) / step, 0.0, cells - 0.001)
	var fz := clampf((local.z + size * 0.5) / step, 0.0, cells - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h := lerpf(lerpf(height_at_index(ix, iz), height_at_index(ix + 1, iz), tx),
		lerpf(height_at_index(ix, iz + 1), height_at_index(ix + 1, iz + 1), tx), tz)
	return global_position.y + h


# One dab of the brush. `mode` is raise, lower, smooth or flatten; strength
# is metres per dab at the centre. Returns nothing; call commit() at the end
# of a stroke to record it for undo.
func sculpt(world: Vector3, radius: float, strength: float, mode: String, flatten_to := 0.0) -> void:
	var local := to_local(world)
	var step := size / cells
	var h := heights.duplicate()
	var r_cells := int(ceil(radius / step))
	var cx := int(round((local.x + size * 0.5) / step))
	var cz := int(round((local.z + size * 0.5) / step))
	for iz in range(maxi(cz - r_cells, 0), mini(cz + r_cells, cells) + 1):
		for ix in range(maxi(cx - r_cells, 0), mini(cx + r_cells, cells) + 1):
			var px := ix * step - size * 0.5
			var pz := iz * step - size * 0.5
			var d := Vector2(px - local.x, pz - local.z).length()
			if d > radius:
				continue
			# Smooth falloff: full at the centre, nothing at the rim.
			var w := 0.5 + 0.5 * cos(PI * d / radius)
			var i := iz * (cells + 1) + ix
			match mode:
				"raise":
					h[i] += strength * w
				"lower":
					h[i] -= strength * w
				"flatten":
					h[i] = lerpf(h[i], flatten_to - global_position.y, w * 0.5)
				"smooth":
					var sum := 0.0
					var n := 0
					for oz in range(-1, 2):
						for ox in range(-1, 2):
							var jx := clampi(ix + ox, 0, cells)
							var jz := clampi(iz + oz, 0, cells)
							sum += heights[jz * (cells + 1) + jx]
							n += 1
					h[i] = lerpf(h[i], sum / n, w * 0.6)
	heights = h


func _rebuild() -> void:
	_pending = false
	_resize_heights()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / cells
	var half := size * 0.5
	for iz in cells + 1:
		for ix in cells + 1:
			var hx0 := height_at_index(maxi(ix - 1, 0), iz)
			var hx1 := height_at_index(mini(ix + 1, cells), iz)
			var hz0 := height_at_index(ix, maxi(iz - 1, 0))
			var hz1 := height_at_index(ix, mini(iz + 1, cells))
			st.set_normal(Vector3(hx0 - hx1, 2.0 * step, hz0 - hz1).normalized())
			st.set_uv(Vector2(ix, iz) * step * 0.5)
			st.set_uv2(Vector2(ix, iz) / cells)
			var si := (iz * (cells + 1) + ix) * 4
			st.set_color(Color(splat[si] / 255.0, splat[si + 1] / 255.0, splat[si + 2] / 255.0, splat[si + 3] / 255.0))
			st.add_vertex(Vector3(ix * step - half, height_at_index(ix, iz), iz * step - half))
	for iz in cells:
		for ix in cells:
			var a := iz * (cells + 1) + ix
			var b := a + 1
			var c := a + cells + 1
			var d := c + 1
			# Clockwise seen from above: Godot's front face.
			for k in [a, b, c, b, d, c]:
				st.add_index(k)
	st.generate_tangents()
	if _mesh_instance == null or not is_instance_valid(_mesh_instance):
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Surface"
		_mesh_instance.set_meta(&"gn_generated", true)
		add_child(_mesh_instance)
	_mesh_instance.mesh = st.commit()
	_mesh_instance.material_override = _painted_material() if not layers.is_empty() else (material if material else _default_material())


# The surface with its painted layers: each layer blended in where it was
# painted, the change set by the textures' own light and dark (stones
# first, then the soil between them) rather than a soft smear.
func _painted_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PAINT_SHADER
	m.shader = sh
	var base := material if material else _default_material()
	if base is ShaderMaterial and (base as ShaderMaterial).get_shader_parameter("imagery"):
		m.set_shader_parameter("base_photo", true)
		m.set_shader_parameter("base_albedo", (base as ShaderMaterial).get_shader_parameter("imagery"))
	else:
		_layer_params(m, "base", base as BaseMaterial3D)
	for k in 4:
		var name := layers[k] if k < layers.size() else ""
		var p := "res://genesis_data/materials/%s.tres" % name
		var lm: BaseMaterial3D = load(p) if name != "" and ResourceLoader.exists(p) else null
		_layer_params(m, "l%d" % k, lm)
	return m


func _layer_params(m: ShaderMaterial, prefix: String, src: BaseMaterial3D) -> void:
	if src == null:
		m.set_shader_parameter(prefix + "_scale", 0.0)
		return
	m.set_shader_parameter(prefix + "_albedo", src.albedo_texture)
	m.set_shader_parameter(prefix + "_tint", src.albedo_color)
	m.set_shader_parameter(prefix + "_rough", src.roughness_texture)
	m.set_shader_parameter(prefix + "_rough_value", src.roughness)
	m.set_shader_parameter(prefix + "_normal", src.normal_texture)
	# Presets tile in world space: one repeat every this many metres.
	m.set_shader_parameter(prefix + "_scale", 1.0 / src.uv1_scale.x if src.uv1_scale.x > 0.0 else 2.0)


const PAINT_SHADER := """
shader_type spatial;
uniform bool base_photo = false;
uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform sampler2D base_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float base_rough_value = 0.95;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float base_scale = 3.0;
uniform sampler2D l0_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 l0_tint : source_color = vec4(1.0);
uniform sampler2D l0_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float l0_rough_value = 1.0;
uniform sampler2D l0_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float l0_scale = 0.0;
uniform sampler2D l1_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 l1_tint : source_color = vec4(1.0);
uniform sampler2D l1_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float l1_rough_value = 1.0;
uniform sampler2D l1_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float l1_scale = 0.0;
uniform sampler2D l2_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 l2_tint : source_color = vec4(1.0);
uniform sampler2D l2_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float l2_rough_value = 1.0;
uniform sampler2D l2_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float l2_scale = 0.0;
uniform sampler2D l3_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 l3_tint : source_color = vec4(1.0);
uniform sampler2D l3_rough : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float l3_rough_value = 1.0;
uniform sampler2D l3_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float l3_scale = 0.0;

varying vec4 weights;
varying vec3 wpos;

void vertex() {
	weights = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Lays one layer over what is there, where its weight says, the change led
// by the layer's own light and dark so it reads as stones and soil meeting.
void lay(sampler2D alb, vec4 tint, sampler2D rgh, float rv, sampler2D nrm, float scale, float w,
		inout vec3 col, inout float rough, inout vec3 nmap) {
	if (scale <= 0.0 || w <= 0.001) {
		return;
	}
	vec2 uv = wpos.xz / scale;
	vec3 a = texture(alb, uv).rgb * tint.rgb;
	float h = dot(a, vec3(0.333));
	float k = clamp((w - 0.5) * 3.0 + 0.5 + (h - 0.4) * 0.8, 0.0, 1.0);
	k = min(k, smoothstep(0.02, 0.25, w));
	col = mix(col, a, k);
	rough = mix(rough, texture(rgh, uv).r * rv, k);
	nmap = mix(nmap, texture(nrm, uv).rgb, k);
}

void fragment() {
	vec3 col;
	float rough;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	if (base_photo) {
		col = texture(base_albedo, UV2).rgb;
		rough = 0.95;
	} else {
		vec2 uv = wpos.xz / base_scale;
		col = texture(base_albedo, uv).rgb * base_tint.rgb;
		rough = texture(base_rough, uv).r * base_rough_value;
		nmap = texture(base_normal, uv).rgb;
	}
	lay(l0_albedo, l0_tint, l0_rough, l0_rough_value, l0_normal, l0_scale, weights.r, col, rough, nmap);
	lay(l1_albedo, l1_tint, l1_rough, l1_rough_value, l1_normal, l1_scale, weights.g, col, rough, nmap);
	lay(l2_albedo, l2_tint, l2_rough, l2_rough_value, l2_normal, l2_scale, weights.b, col, rough, nmap);
	lay(l3_albedo, l3_tint, l3_rough, l3_rough_value, l3_normal, l3_scale, weights.a, col, rough, nmap);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	NORMAL_MAP = nmap;
}
"""


static func _default_material() -> Material:
	if ResourceLoader.exists("res://genesis_data/materials/grass.tres"):
		return load("res://genesis_data/materials/grass.tres")
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.42, 0.22)
	m.roughness = 0.95
	return m
