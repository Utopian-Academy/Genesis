@tool
extends Node3D

# A flown line array: a flying frame at the node, and boxes hung below it,
# each one splayed down from the one above about their shared front rigging
# point, the way the real ones pin together. Splay grows from the top box to
# the bottom one (a "J"), so the top throws to the back of the room and the
# bottom covers the front. The node's position is the frame's trim height;
# its forward (-Z) is where the array faces.

const GnAssets := preload("res://addons/genesis/core/gn_assets.gd")

## The box, from the library's line array elements.
@export var element: String = "":
	set(v): element = v; _queue()
@export_range(1, 24, 1) var boxes: int = 12:
	set(v): boxes = v; _queue()
## Downward tilt of the whole array at the frame, degrees.
@export_range(-10.0, 20.0, 0.5) var frame_tilt: float = 2.0:
	set(v): frame_tilt = v; _queue()
## Splay between the top two boxes, degrees.
@export_range(0.0, 10.0, 0.25) var top_splay: float = 0.5:
	set(v): top_splay = v; _queue()
## Splay between the bottom two boxes, degrees.
@export_range(0.0, 10.0, 0.25) var bottom_splay: float = 8.0:
	set(v): bottom_splay = v; _queue()

var _pending := false


func _ready() -> void:
	if element == "":
		var kinds := elements()
		if not kinds.is_empty():
			element = kinds[0]
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


func _validate_property(property: Dictionary) -> void:
	# The element list is whatever the library holds.
	if property.name == "element":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(elements())


static func elements() -> Array:
	return GnAssets.of_kind("audio", ["line_array_element"]).map(func(a): return a.path)


## Splay between box i and the one below it: a J, flat at the top.
func splay(i: int) -> float:
	var t := float(i) / maxf(boxes - 2, 1)
	return lerpf(top_splay, bottom_splay, t * t)


## Lowest point of the array above the node, metres (negative: below).
func bottom_height() -> float:
	var lowest := 0.0
	for c in get_children():
		if c.has_meta(&"gn_box"):
			lowest = minf(lowest, (c.transform * Vector3(0, 0, 0)).y)
	return lowest


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	if element == "" or not ResourceLoader.exists(element):
		return
	var info := GnAssets.info(element)
	var hf := float(info.get("front_height_m", 0.36))
	var d := float(info.get("depth_m", 0.5))
	var packed := load(element) as PackedScene
	var frame_path := GnAssets.find("audio", "bumper_%s" % ("large" if d >= 0.49 and hf >= 0.3 else "compact"))
	if frame_path != "":
		var frame := (load(frame_path) as PackedScene).instantiate() as Node3D
		frame.name = "Frame"
		frame.set_meta(&"gn_generated", true)
		add_child(frame)
	# Box coordinates: the front face is at z = -d/2, the top at y = hf. Each
	# box hangs from the one above by its top-front point, at the other's
	# bottom-front point, turned down by the splay.
	var top_front := Vector3(0, hf, -d * 0.5)
	var bottom_front := Vector3(0, 0, -d * 0.5)
	var t := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-frame_tilt)), Vector3.ZERO)
	# The first box hangs just under the frame, fronts flush.
	t = t * Transform3D(Basis(), Vector3(0, -0.02 - hf, 0))
	for i in boxes:
		if i > 0:
			t = t * Transform3D(Basis(), bottom_front) * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-splay(i - 1))), Vector3.ZERO) \
				* Transform3D(Basis(), -top_front)
		var box := packed.instantiate() as Node3D
		box.name = "Box %d" % (i + 1)
		box.transform = t
		box.set_meta(&"gn_generated", true)
		box.set_meta(&"gn_box", true)
		add_child(box)


## "12 x Kora, 4.1 m tall, bottom 3.9 m below the frame, splays 0.5°-8°".
func report_text() -> String:
	var info := GnAssets.info(element)
	var name_of := str(info.get("label", element.get_file().get_basename()))
	return "%d × %s\nBottom of the array %.1f m below the frame\nSplay %.1f° at the top, %.1f° at the bottom" % [
		boxes, name_of, -bottom_height(), top_splay, bottom_splay]
