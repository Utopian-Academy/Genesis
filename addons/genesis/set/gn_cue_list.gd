@tool
extends Node

# The show's cue list: a rough click-through of the running order, the way a
# lighting desk runs it. Each cue is a look: every light's colour, level,
# position and zoom, what each screen shows and how bright, which effects
# run, the time of day and the haze, the camera to watch it from. GO fades
# from where things are to the next cue over its fade time.
#
# A cue can also tell other show software to go: Deckboy (its plain-text
# commands over TCP, "GO" or "TAKE" or anything its HELP lists), anything
# that takes OSC, or plain text over UDP. So one GO runs the preview and
# the playback together, with the playback's output on the screens (see
# live video on the Show page).
#
# Running cues changes the scene, as running a desk changes the stage; the
# cues are what is saved. Playback is not undoable.

const Fixture := preload("res://addons/genesis/set/gn_light_fixture.gd")
const LedWall := preload("res://addons/genesis/set/gn_led_wall.gd")
const FlyingScreen := preload("res://addons/genesis/set/gn_flying_screen.gd")
const Effect := preload("res://addons/genesis/set/gn_effect.gd")
const Crowd := preload("res://addons/genesis/set/gn_crowd.gd")
const AreaLight := preload("res://addons/genesis/set/gn_area_light.gd")
const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")

signal went(index: int)
signal sent(result: String)

const GROUP := &"gn_cue_lists"
# What a cue remembers of each kind of show object.
const RECORDED := {
	"fixture": ["visible", "colour", "dimmer", "pan", "tilt", "beam_degrees"],
	"screen": ["visible", "brightness", "content", "live_source"],
	"effect": ["visible", "amount"],
	"crowd": ["visible"],
	"area": ["visible", "colour", "kelvin", "dimmer"],
}
const ENV_KEYS := ["time_of_day", "haze"]
const TARGETS := ["Deckboy (TCP)", "OSC (UDP)", "Text (UDP)"]
const DECKBOY_PORT := 5510

## The cues, in running order. Each is a Dictionary:
## {"name", "fade", "camera", "env": {}, "state": {path: {property: value}},
##  "send": {"on", "target", "host", "port", "message"}}
@export var cues: Array = []

## The cue last gone to (-1: none yet).
var current := -1
var _tween: Tween


func _ready() -> void:
	add_to_group(GROUP)


## The show objects in the scene, by kind.
static func show_objects(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for n in root.find_children("*", "Node3D", true, false):
		var k := kind_of(n)
		# A flying screen's own wall is recorded through the flying screen.
		if k != "" and not (k == "screen" and n.get_parent() and n.get_parent().name == "Load"):
			out.append(n)
	return out


static func kind_of(n: Node) -> String:
	var s: Script = n.get_script()
	if s == Fixture:
		return "fixture"
	if s == LedWall or s == FlyingScreen:
		return "screen"
	if s == Effect:
		return "effect"
	if s == Crowd:
		return "crowd"
	if s == AreaLight:
		return "area"
	return ""


## Everything a cue would remember, as things stand now.
func snapshot(root: Node) -> Dictionary:
	var state := {}
	for n in show_objects(root):
		var props := {}
		for p in RECORDED[kind_of(n)]:
			props[p] = n.get(p)
		state[str(root.get_path_to(n))] = props
	var env := {}
	for k in ENV_KEYS:
		env[k] = GnEnvironment.value(k)
	return {"state": state, "env": env}


## A new cue from the scene as it is. `at` < 0 adds it at the end.
func record(root: Node, name: String, fade: float, camera: String, send: Dictionary, at := -1) -> int:
	var cue := snapshot(root)
	cue.name = name
	cue.fade = fade
	cue.camera = camera
	cue.send = send
	if at < 0 or at >= cues.size():
		cues.append(cue)
		return cues.size() - 1
	cues.insert(at, cue)
	return at


## Re-records a cue's look, keeping its name, fade, camera and message.
func update(index: int, root: Node) -> void:
	if index < 0 or index >= cues.size():
		return
	var snap := snapshot(root)
	cues[index].state = snap.state
	cues[index].env = snap.env


## The next cue. At the end of the list, GO does nothing.
func go() -> void:
	if current < cues.size() - 1:
		go_to(current + 1)


func back() -> void:
	if current > 0:
		go_to(current - 1, 0.0)


## Runs cue `index`, fading over its own time (or `fade` if given).
func go_to(index: int, fade := -1.0) -> void:
	if index < 0 or index >= cues.size():
		return
	var root: Node = owner if owner else get_tree().edited_scene_root
	var cue: Dictionary = cues[index]
	var time := float(cue.get("fade", 0.0)) if fade < 0.0 else fade
	current = index
	if _tween and _tween.is_valid():
		_tween.kill()
	# Everything that fades: from where it is now to where the cue has it.
	var fades: Array = []
	var ends: Array = []
	for path in cue.get("state", {}):
		var n: Node = root.get_node_or_null(NodePath(path)) if root else null
		if n == null:
			continue
		var props: Dictionary = cue.state[path]
		for p in props:
			var to: Variant = props[p]
			var from: Variant = n.get(p)
			if from == to:
				continue
			if time > 0.0 and (to is float or to is Color):
				fades.append([n, p, from, to])
			elif p == "visible" and to == false and time > 0.0:
				# Out at the end of the fade, once its level has gone.
				ends.append([n, p, to])
			else:
				n.set(p, to)
	var env_from := {}
	for k in cue.get("env", {}):
		env_from[k] = GnEnvironment.value(k)
	if time <= 0.0:
		for k in cue.get("env", {}):
			GnEnvironment.apply(k, cue.env[k], false)
	else:
		var step := func(t: float) -> void:
			for f in fades:
				if is_instance_valid(f[0]):
					f[0].set(f[1], _mix(f[2], f[3], t))
			for k in env_from:
				var a: Variant = env_from[k]
				var b: Variant = cue.env[k]
				if a is float and b is float and not is_equal_approx(a, b):
					GnEnvironment.apply(k, lerpf(a, b, t), false)
		var finish := func() -> void:
			for e in ends:
				if is_instance_valid(e[0]):
					e[0].set(e[1], e[2])
			for k in cue.get("env", {}):
				GnEnvironment.apply(k, cue.env[k], false)
		_tween = get_tree().create_tween()
		_tween.tween_method(step, 0.0, 1.0, time)
		_tween.tween_callback(finish)
	went.emit(index)
	var send: Dictionary = cue.get("send", {})
	if send.get("on", false) and str(send.get("message", "")).strip_edges() != "":
		_send(send)


static func _mix(a: Variant, b: Variant, t: float) -> Variant:
	if a is Color and b is Color:
		return (a as Color).lerp(b, t)
	if (a is float or a is int) and (b is float or b is int):
		return lerpf(float(a), float(b), t)
	return b if t >= 1.0 else a


## The camera a cue watches from, or null.
func camera_of(index: int) -> Camera3D:
	if index < 0 or index >= cues.size():
		return null
	var root: Node = owner if owner else get_tree().edited_scene_root
	var path := str(cues[index].get("camera", ""))
	return root.get_node_or_null(NodePath(path)) as Camera3D if root and path != "" else null


# --- telling other show software to go -----------------------------------------

func _send(send: Dictionary) -> void:
	var target := str(send.get("target", TARGETS[0]))
	var host := str(send.get("host", "127.0.0.1"))
	var port := int(send.get("port", DECKBOY_PORT))
	var message := str(send.get("message", "")).strip_edges()
	match target:
		"OSC (UDP)":
			var udp := PacketPeerUDP.new()
			udp.set_dest_address(host, port)
			var err := udp.put_packet(osc_packet(message))
			sent.emit("OSC %s → %s:%d %s" % [message, host, port, "sent" if err == OK else "failed"])
		"Text (UDP)":
			var udp := PacketPeerUDP.new()
			udp.set_dest_address(host, port)
			var err := udp.put_packet((message + "\n").to_utf8_buffer())
			sent.emit("\"%s\" → %s:%d %s" % [message, host, port, "sent" if err == OK else "failed"])
		_:
			var answer: String = await tcp_command(get_tree(), host, port, message)
			sent.emit("Deckboy: %s" % answer)


## Sends one line over TCP and returns the first line of the answer (Deckboy
## answers every command: "OK <VERB>" or "ERR ..."), or what went wrong.
static func tcp_command(tree: SceneTree, host: String, port: int, line: String, timeout_s := 2.0) -> String:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host(host, port) != OK:
		return "can't reach %s:%d" % [host, port]
	var until := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < until:
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		if tcp.get_status() == StreamPeerTCP.STATUS_ERROR:
			return "nothing listening at %s:%d (is its remote control on?)" % [host, port]
		await tree.process_frame
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return "no answer from %s:%d" % [host, port]
	tcp.put_data((line + "\n").to_utf8_buffer())
	var reply := ""
	until = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < until and not reply.contains("\n"):
		tcp.poll()
		var n := tcp.get_available_bytes()
		if n > 0:
			reply += tcp.get_utf8_string(n)
		else:
			await tree.process_frame
	tcp.disconnect_from_host()
	reply = reply.strip_edges().get_slice("\n", 0)
	return reply if reply != "" else "sent \"%s\" (no answer)" % line


## An OSC message from text: "/address arg arg…"; numbers go as int or
## float, anything else as a string.
static func osc_packet(text: String) -> PackedByteArray:
	var parts := text.strip_edges().split(" ", false)
	var address := parts[0] if parts.size() > 0 else "/"
	var tags := ","
	var args := PackedByteArray()
	for i in range(1, parts.size()):
		var a := parts[i]
		var b := StreamPeerBuffer.new()
		b.big_endian = true
		if a.is_valid_int():
			tags += "i"
			b.put_32(int(a))
			args.append_array(b.data_array)
		elif a.is_valid_float():
			tags += "f"
			b.put_float(float(a))
			args.append_array(b.data_array)
		else:
			tags += "s"
			args.append_array(_osc_string(a))
	var out := _osc_string(address)
	out.append_array(_osc_string(tags))
	out.append_array(args)
	return out


static func _osc_string(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	b.append(0)
	while b.size() % 4 != 0:
		b.append(0)
	return b
