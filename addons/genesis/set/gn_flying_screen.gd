@tool
extends Node3D

# A flying screen: an LED wall hung under a helicopter on a long line, the
# way it is done for festival openings and stadium fly-ins. The helicopter
# hovers at the node (its wheels at the node's origin, so raise the node to
# the altitude wanted); from its cargo hook a long line drops to a ring, a
# bridle spreads to a bar across the top of the wall, and the wall hangs
# from the bar. The wall is a real LED wall, built from cabinet specs, so it
# reports its size, pixels and weight, and the payload is checked against
# the helicopter's hook limit.
#
# In a movie the load swings gently at the true period of a pendulum that
# long. Put the whole thing on a moving-objects path and it flies the route.

const GnAssets := preload("res://addons/genesis/core/gn_assets.gd")
const LedWall := preload("res://addons/genesis/set/gn_led_wall.gd")

## Things that follow the movie's clock without riding a path.
const GROUP := &"gn_timed"
const GRAVITY := 9.81
# Spreader bar weight per metre, and the shackles, ring and slings.
const BAR_KG_PER_M := 12.0
const RIGGING_KG := 45.0

## The helicopter, from the library's heavy lifters (those with a cargo hook).
@export var helicopter: String = "":
	set(v): helicopter = v; _queue()
## Hook to the bridle ring, metres.
@export_range(3.0, 60.0, 0.5) var long_line: float = 15.0:
	set(v): long_line = v; _queue()
## Which way the helicopter points, degrees. 90 flies it side-on to the wall.
@export_range(-180.0, 180.0, 1.0) var heading_degrees: float = 90.0:
	set(v): heading_degrees = v; _queue()
## How far the load swings either side in a movie, degrees. 0 hangs still.
@export_range(0.0, 15.0, 0.5) var swing_degrees: float = 2.0:
	set(v): swing_degrees = v; at_time(_shown)
@export_group("Screen")
## Cabinet type, as on an LED wall.
@export var panel: String = "5.9 mm outdoor (500 × 1000)":
	set(v): panel = v; _queue()
@export_range(1, 60) var columns: int = 16:
	set(v): columns = v; _queue()
@export_range(1, 30) var rows: int = 5:
	set(v): rows = v; _queue()
## An image or a video to show (a video loops). Empty shows the pixel map.
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp", "*.mp4", "*.mov", "*.m4v", "*.webm", "*.mkv", "*.avi", "*.mxf")
var content: String = "":
	set(v): content = v; _queue()
## Live video instead, as on an LED wall ("srt:9710" for Deckboy's Stream output).
@export var live_source: String = "":
	set(v): live_source = v; _queue()
@export_range(0.0, 4.0, 0.05) var brightness: float = 1.5:
	set(v): brightness = v; _queue()

var _pending := false
var _shown := 0.0
var _load: Node3D
var _wall: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	if helicopter == "":
		var lifters := lifters()
		if not lifters.is_empty():
			helicopter = lifters[0]
	_rebuild()


func _queue() -> void:
	if not _pending and is_inside_tree():
		_pending = true
		_rebuild.call_deferred()


func _validate_property(property: Dictionary) -> void:
	if property.name == "helicopter":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(lifters())
	elif property.name == "panel":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(LedWall.PANELS.keys().filter(func(k): return k != "Custom"))


## Library helicopters that carry a cargo hook.
static func lifters() -> Array:
	return GnAssets.of_kind("aircraft", ["helicopter"]).filter(func(a): return a.license.has("hook")).map(
		func(a): return a.path)


## The hook, in the node's space.
func hook_point() -> Vector3:
	var hook := Vector3(0, 0.4, 0)
	if helicopter != "":
		var h: Array = GnAssets.info(helicopter).get("hook", [])
		if h.size() == 3:
			hook = Vector3(h[0], h[1], h[2])
	return Basis(Vector3.UP, deg_to_rad(heading_degrees)) * hook


## The wall node hanging below (an LED wall), or null before it is built.
func wall() -> Node3D:
	return _wall


func report() -> Dictionary:
	var r: Dictionary = _wall.report() if _wall else {}
	var size: Vector2 = r.get("size_m", Vector2.ZERO)
	var payload := float(r.get("weight_kg", 0.0)) + size.x * BAR_KG_PER_M + RIGGING_KG
	var limit := float(GnAssets.info(helicopter).get("hook_limit_kg", 0.0)) if helicopter != "" else 0.0
	return {
		"payload_kg": payload,
		"hook_limit_kg": limit,
		"drop_m": _drop() + size.y,
		"period_s": TAU * sqrt(_pendulum() / GRAVITY),
	}


func report_text() -> String:
	var r := report()
	var lines: Array = [_wall.report_text()] if _wall else []
	if r.hook_limit_kg > 0.0:
		lines.append("Payload %.0f kg of the helicopter's %.0f kg hook limit%s" % [
			r.payload_kg, r.hook_limit_kg, "" if r.payload_kg <= r.hook_limit_kg else ": TOO HEAVY"])
	else:
		lines.append("Payload %.0f kg" % r.payload_kg)
	lines.append("Bottom of the screen %.1f m below the hook; it swings once every %.1f s" % [r.drop_m, r.period_s])
	return "\n".join(lines)


# Hook to the top of the wall: the long line, then the bridle down to the bar.
func _drop() -> float:
	return long_line + _bridle_drop() + 0.15


func _bridle_drop() -> float:
	var width: float = _wall.report().size_m.x if _wall else 8.0
	# Legs at about 60° to the bar, the usual bridle angle.
	return width * 0.5 * tan(deg_to_rad(60.0))


# Hook to the wall's middle: the length of the pendulum.
func _pendulum() -> float:
	var h: float = _wall.report().size_m.y if _wall else 5.0
	return _drop() + h * 0.5


## Sets the swing as it is `t` seconds into the movie.
func at_time(t: float) -> void:
	_shown = t
	if _load == null:
		return
	var w := sqrt(GRAVITY / maxf(_pendulum(), 0.1))
	# Mostly toward and away from the audience, a little sideways, out of step.
	var a := deg_to_rad(swing_degrees)
	_load.rotation = Vector3(a * sin(w * t), 0.0, a * 0.3 * sin(w * t * 1.07 + 1.3))


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta(&"gn_generated"):
			remove_child(c)
			c.queue_free()
	_load = null
	_wall = null
	if helicopter != "" and ResourceLoader.exists(helicopter):
		var heli := (load(helicopter) as PackedScene).instantiate() as Node3D
		heli.name = "Helicopter"
		heli.rotation.y = deg_to_rad(heading_degrees)
		heli.set_meta(&"gn_generated", true)
		add_child(heli)

	# Everything below the hook hangs from one pivot, so it swings as one.
	_load = Node3D.new()
	_load.name = "Load"
	_load.position = hook_point()
	_load.set_meta(&"gn_generated", true)
	add_child(_load)

	var w := LedWall.new()
	w.name = "Screen"
	w.panel = panel
	w.columns = columns
	w.rows = rows
	w.content = content
	w.live_source = live_source
	w.brightness = brightness
	w.bottom = 0.0
	_wall = w
	var size: Vector2 = w.report().size_m
	var bar_y := -(long_line + _bridle_drop())
	w.position = Vector3(0, bar_y - 0.15 - size.y, 0)
	_load.add_child(w)

	var rope := _material(Color(0.12, 0.12, 0.1), 0.7, 0.0)
	var steel := _material(Color(0.55, 0.56, 0.58), 0.35, 0.8)
	var ring := Vector3(0, -long_line, -0.04)
	_rope(Vector3(0, 0, -0.04), ring, 0.012, rope)
	var half := size.x * 0.5 - 0.1
	for x in [-half, half]:
		_rope(ring, Vector3(x, bar_y, -0.04), 0.01, rope)
		_rope(Vector3(x, bar_y, -0.04), Vector3(x, bar_y - 0.15, -0.04), 0.012, steel)
	_rope(Vector3(-size.x * 0.5, bar_y, -0.04), Vector3(size.x * 0.5, bar_y, -0.04), 0.05, steel)
	var shackle := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.05
	torus.outer_radius = 0.08
	shackle.mesh = torus
	shackle.material_override = steel
	shackle.position = ring
	shackle.rotation.x = PI * 0.5
	_load.add_child(shackle)
	at_time(_shown)


# A straight round bar from a to b under the load: a rope, a sling, the bar.
func _rope(a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 8
	cyl.rings = 1
	m.mesh = cyl
	m.material_override = mat
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD) if absf(up.dot(Vector3.FORWARD)) < 0.99 else up.cross(Vector3.RIGHT)
	side = side.normalized()
	m.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	_load.add_child(m)


static func _material(colour: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = metallic
	return m
