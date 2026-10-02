@tool
extends Node3D

# A stage built from standard 2 m × 1 m deck modules on legs, with an optional
# skirt. The seams between modules show, as they do on a real stage. Width
# runs along local X, depth along Z, the front edge faces +Z.

@export_range(1.0, 40.0, 1.0) var width: float = 8.0:
	set(v): width = v; _queue()
@export_range(1.0, 20.0, 1.0) var depth: float = 4.0:
	set(v): depth = v; _queue()
@export_range(0.2, 2.0, 0.1) var height: float = 0.8:
	set(v): height = v; _queue()
@export var skirt: bool = true:
	set(v): skirt = v; _queue()
@export var skirt_colour: Color = Color(0.03, 0.03, 0.035):
	set(v): skirt_colour = v; _queue()

const DECK := Vector2(2.0, 1.0)
const THICK := 0.12

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
	var top := StandardMaterial3D.new()
	top.albedo_color = Color(0.08, 0.08, 0.085)
	top.roughness = 0.75
	var leg := StandardMaterial3D.new()
	leg.albedo_color = Color(0.5, 0.5, 0.52)
	leg.metallic = 0.8
	leg.roughness = 0.4
	var cols := int(ceil(width / DECK.x))
	var rows := int(ceil(depth / DECK.y))
	var deck := BoxMesh.new()
	deck.size = Vector3(DECK.x - 0.008, THICK, DECK.y - 0.008)
	deck.material = top
	var post := BoxMesh.new()
	post.size = Vector3(0.05, height - THICK, 0.05)
	post.material = leg
	var decks := MultiMesh.new()
	decks.transform_format = MultiMesh.TRANSFORM_3D
	decks.mesh = deck
	decks.instance_count = cols * rows
	var posts := MultiMesh.new()
	posts.transform_format = MultiMesh.TRANSFORM_3D
	posts.mesh = post
	posts.instance_count = cols * rows * 4
	var x0 := -cols * DECK.x * 0.5
	var z0 := -rows * DECK.y * 0.5
	var i := 0
	for c in cols:
		for r in rows:
			var centre := Vector3(x0 + (c + 0.5) * DECK.x, height - THICK * 0.5, z0 + (r + 0.5) * DECK.y)
			decks.set_instance_transform(c * rows + r, Transform3D(Basis(), centre))
			for dx in [-1, 1]:
				for dz in [-1, 1]:
					posts.set_instance_transform(i, Transform3D(Basis(), Vector3(
						centre.x + dx * (DECK.x * 0.5 - 0.1), (height - THICK) * 0.5, centre.z + dz * (DECK.y * 0.5 - 0.1))))
					i += 1
	for mm in [decks, posts]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.set_meta(&"gn_generated", true)
		add_child(mmi)
	if skirt:
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = skirt_colour
		cloth.roughness = 0.95
		var w := cols * DECK.x
		var d := rows * DECK.y
		var h := height - THICK
		for side in [[Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, 0.01)], [Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.01, h, d)],
				[Vector3(w * 0.5, h * 0.5, 0), Vector3(0.01, h, d)]]:
			var panel := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = side[1]
			bm.material = cloth
			panel.mesh = bm
			panel.position = side[0]
			panel.set_meta(&"gn_generated", true)
			add_child(panel)
