@tool
extends Node3D

# A body of water: pond, pool, river stretch or sea, as one parametric node.
# Width along local X, length along Z, the surface at the node's height.
# "Ocean" is the same surface made enormous with bigger, slower waves.

const WATER := preload("res://addons/genesis/set/gn_water.gdshader")

@export_enum("Pond", "Pool", "River", "Ocean") var kind: String = "Pond":
	set(v): kind = v; _queue()
@export_range(1.0, 2000.0, 0.5) var width: float = 20.0:
	set(v): width = v; _queue()
@export_range(1.0, 2000.0, 0.5) var length: float = 12.0:
	set(v): length = v; _queue()
@export_range(0.0, 2.0, 0.05) var waves: float = 0.6:
	set(v): waves = v; _queue()

const LOOKS := {
	"Pond": {"shallow": Color(0.2, 0.3, 0.2), "deep": Color(0.03, 0.07, 0.05), "scale": 0.35, "clarity": 1.5},
	"Pool": {"shallow": Color(0.35, 0.75, 0.85), "deep": Color(0.05, 0.35, 0.55), "scale": 0.6, "clarity": 6.0},
	"River": {"shallow": Color(0.22, 0.3, 0.28), "deep": Color(0.05, 0.09, 0.1), "scale": 0.25, "clarity": 1.2},
	"Ocean": {"shallow": Color(0.12, 0.35, 0.42), "deep": Color(0.01, 0.06, 0.12), "scale": 0.08, "clarity": 8.0},
}

var _pending := false


func _ready() -> void:
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	var l: Dictionary = LOOKS.get(kind, LOOKS["Pond"])
	var plane := PlaneMesh.new()
	var ocean := kind == "Ocean"
	plane.size = Vector2(maxf(width, 4000.0), maxf(length, 4000.0)) if ocean else Vector2(width, length)
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	mat.set_shader_parameter("shallow", l.shallow)
	mat.set_shader_parameter("deep", l.deep)
	mat.set_shader_parameter("wave_scale", l.scale)
	mat.set_shader_parameter("wave_strength", waves * (2.0 if ocean else 1.0))
	mat.set_shader_parameter("clarity_m", l.clarity)
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(&"gn_generated", true)
	add_child(mi)
