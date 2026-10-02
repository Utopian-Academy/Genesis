@tool
extends RefCounted

# Fly-throughs. A movie is a list of shots; each shot is either
#   a path   - the camera glides through saved cameras in order, or
#   an orbit - the camera circles a point at a height and distance.
# Stored as metadata on a "Movie" node in the scene, so it saves with it.
#
# Motion is what separates a fly-through from a slideshow: positions follow a
# Catmull-Rom curve through the waypoints (no corners), rotations are slerped,
# and the whole shot eases in and out rather than starting and stopping dead.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")
const GnCameras := preload("res://addons/genesis/core/gn_cameras.gd")
const GnRender := preload("res://addons/genesis/core/gn_render.gd")
const GnLook := preload("res://addons/genesis/core/gn_look.gd")
const GnSurface := preload("res://addons/genesis/core/gn_surface.gd")
const GnEnvironment := preload("res://addons/genesis/core/gn_environment.gd")
const Mover := preload("res://addons/genesis/set/gn_mover.gd")
const FlyingScreen := preload("res://addons/genesis/set/gn_flying_screen.gd")
const GnPhasing := preload("res://addons/genesis/core/gn_phasing.gd")
const GnFfmpeg := preload("res://addons/genesis/core/gn_ffmpeg.gd")

const META := &"gn_shots"
# {"from": hour, "to": hour} when the sun moves through the film, else absent.
const TIMELAPSE := &"gn_timelapse"
const FPS := 30


static func movie() -> Node3D:
	return GnScene.find_role("movie") as Node3D


static func ensure_movie() -> Node3D:
	var m := movie()
	if m == null and GnScene.root():
		m = Node3D.new()
		m.name = "Movie"
		m.set_meta(META, [])
		GnScene.add_node(m, GnScene.root(), "Genesis: new movie", "movie")
	return m


static func shots() -> Array:
	var m := movie()
	return (m.get_meta(META, []) as Array).duplicate(true) if m else []


static func set_shots(list: Array, action: String) -> void:
	var m := ensure_movie()
	GnScene.set_props(action, [[m, "metadata/" + META, list]])


# A path through the named saved cameras, `seconds` long.
static func timelapse() -> Dictionary:
	var m := movie()
	return m.get_meta(TIMELAPSE, {}) if m else {}


static func set_timelapse(from_hour: float, to_hour: float, on: bool) -> void:
	var m := ensure_movie()
	GnScene.set_props("Genesis: time-lapse", [[m, "metadata/" + TIMELAPSE,
		{"from": from_hour, "to": to_hour} if on else {}]])


## Sets the world as it is `t` seconds into the film: the sun, if it moves,
## and everything on a moving-objects path. Not undoable: it is playback.
## Returns the hour shown, or -1 if the sun is not animated.
static func show_time(t: float, list: Array) -> float:
	var hour := -1.0
	var lapse := timelapse()
	var total := duration(list)
	if not lapse.is_empty() and total > 0.0:
		hour = lerpf(float(lapse.from), float(lapse.to), clampf(t / total, 0.0, 1.0))
		GnEnvironment.apply("time_of_day", hour, false)
	var root := GnScene.root()
	if root:
		for m in root.get_tree().get_nodes_in_group(Mover.GROUP):
			m.at_time(t)
		# Things that move in place: a flying screen's swing.
		for m in root.get_tree().get_nodes_in_group(FlyingScreen.GROUP):
			m.at_time(t)
		# The build going up.
		GnPhasing.show(root, t)
	return hour


static func path_shot(camera_names: Array, seconds: float) -> Dictionary:
	return {"type": "path", "cameras": camera_names, "seconds": seconds}


static func orbit_shot(centre: Vector3, radius: float, height: float, degrees: float, seconds: float) -> Dictionary:
	return {"type": "orbit", "centre": centre, "radius": radius, "height": height,
		"degrees": degrees, "seconds": seconds}


static func duration(list: Array) -> float:
	var t := 0.0
	for s in list:
		t += float(s.seconds)
	return t


# The camera at time t (seconds) as {transform, fov, look}, or {} if none.
static func sample(list: Array, t: float) -> Dictionary:
	var start := 0.0
	for s in list:
		var d := float(s.seconds)
		if t <= start + d or s == list[-1]:
			var u := clampf((t - start) / maxf(d, 0.001), 0.0, 1.0)
			return _sample_shot(s, _ease(u))
		start += d
	return {}


static func _ease(u: float) -> float:
	# Smootherstep: zero velocity and acceleration at both ends.
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


static func _sample_shot(s: Dictionary, u: float) -> Dictionary:
	if s.type == "orbit":
		var a := deg_to_rad(float(s.degrees)) * u
		var c: Vector3 = s.centre
		var pos := c + Vector3(sin(a) * float(s.radius), float(s.height), cos(a) * float(s.radius))
		return {"transform": Transform3D(Basis.looking_at(c - pos, Vector3.UP), pos), "fov": 50.0, "look": {}}
	var cams: Array[Camera3D] = []
	var by_name := {}
	for cam in GnCameras.cameras():
		by_name[str(cam.name)] = cam
	for n in s.cameras:
		if by_name.has(n):
			cams.append(by_name[n])
	if cams.is_empty():
		return {}
	if cams.size() == 1:
		return {"transform": cams[0].global_transform, "fov": cams[0].fov, "look": GnLook.get_look(cams[0])}
	var segs := cams.size() - 1
	var f := u * segs
	var i := mini(int(f), segs - 1)
	var lu := f - i
	var p0 := cams[maxi(i - 1, 0)].global_position
	var p1 := cams[i].global_position
	var p2 := cams[i + 1].global_position
	var p3 := cams[mini(i + 2, segs)].global_position
	var pos := _catmull(p0, p1, p2, p3, lu)
	var q := cams[i].global_transform.basis.get_rotation_quaternion().slerp(
		cams[i + 1].global_transform.basis.get_rotation_quaternion(), lu)
	var fov := lerpf(cams[i].fov, cams[i + 1].fov, lu)
	# The look belongs to whichever waypoint is nearer.
	var look := GnLook.get_look(cams[i] if lu < 0.5 else cams[i + 1])
	return {"transform": Transform3D(Basis(q), pos), "fov": fov, "look": look}


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# Where the camera would pass through something: a list of
# {from, to (seconds), what (node name)}. Checked every sixth of a second by
# casting short rays around the camera; a camera inside a tree or a wall
# ruins a shot and costs a full render to discover otherwise.
static func obstructions(list: Array, clearance := 0.6) -> Array:
	var probe := GnSurface.new(GnScene.root())
	# Foliage is open: a camera between leaf cards is inside the tree without
	# being near any one card, so for plants the whole crown counts.
	var plants: Array = []
	var root := GnScene.root()
	for n in root.find_children("*", "Node3D", true, false) if root else []:
		if n.get_meta(&"gn_category", "") in ["trees", "plants"]:
			var box := _world_aabb(n)
			if box.size != Vector3.ZERO:
				plants.append([box, str(n.name)])
	var out: Array = []
	var dirs := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var t := 0.0
	var total := duration(list)
	while t <= total:
		var at := sample(list, t)
		if not at.is_empty():
			var pos: Vector3 = (at.transform as Transform3D).origin
			var what := ""
			for p in plants:
				if (p[0] as AABB).has_point(pos):
					what = p[1]
					break
			for d in dirs if what == "" else []:
				var hit := probe.cast(pos, d)
				if not hit.is_empty() and pos.distance_to(hit.position) < clearance:
					what = str(hit.get("node", "something"))
					break
			if what != "":
				if not out.is_empty() and t - float(out[-1].to) < 0.34 and out[-1].what == what:
					out[-1].to = t
				else:
					out.append({"from": t, "to": t, "what": what})
		t += 1.0 / 6.0
	return out


static func _world_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var parts: Array = [n] if n is VisualInstance3D else []
	parts.append_array(n.find_children("*", "VisualInstance3D", true, false))
	for vi in parts:
		var b: AABB = vi.global_transform * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# Renders every frame to renders/<name>/ and, when ffmpeg is on the PATH,
# joins them into renders/<name>.mp4. `progress` is called with (frame, total).
# Returns the video path, the frame folder if there is no ffmpeg, or "".
static func render(list: Array, size: Vector2i, host: Node, movie_name: String,
		progress: Callable = Callable(), fps: int = FPS) -> String:
	var total := int(ceil(duration(list) * fps))
	if total <= 0:
		return ""
	var dir := "%s/%s" % [GnRender.OUTPUT_DIR, movie_name]
	DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(GnRender.OUTPUT_DIR + "/.gdignore"):
		FileAccess.open(GnRender.OUTPUT_DIR + "/.gdignore", FileAccess.WRITE).close()
	# A throwaway camera carries each frame's pose and look into the renderer.
	var cam := Camera3D.new()
	cam.name = "MovieFrame"
	host.add_child(cam)
	var hour_before = GnEnvironment.value("time_of_day")
	for f in total:
		var at := sample(list, float(f) / fps)
		if at.is_empty():
			continue
		show_time(float(f) / fps, list)
		cam.global_transform = at.transform
		cam.fov = at.fov
		cam.set_meta(GnLook.META, at.look)
		# Animation frames: no supersampling and a short settle, or a
		# one-minute film would take an hour. Motion hides what that costs.
		var img_path: String = await GnRender.render(cam, size, host, false)
		if img_path != "":
			DirAccess.rename_absolute(ProjectSettings.globalize_path(img_path),
				ProjectSettings.globalize_path("%s/frame_%05d.png" % [dir, f]))
		if progress.is_valid():
			progress.call(f + 1, total)
	cam.queue_free()
	# Back to the scene as it was set: movers to their start, then the sun
	# (after, since showing time 0 moves the sun too).
	show_time(0.0, list)
	GnPhasing.finish(GnScene.root())
	GnEnvironment.apply("time_of_day", hour_before, false)
	var out := ProjectSettings.globalize_path("%s/%s.mp4" % [GnRender.OUTPUT_DIR, movie_name])
	var args := ["-y", "-framerate", str(fps), "-i", ProjectSettings.globalize_path(dir) + "/frame_%05d.png",
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "17", "-preset", "slow", out]
	var ffmpeg := GnFfmpeg.find()
	var code := OS.execute(ffmpeg, PackedStringArray(args), [], true) if ffmpeg != "" else -1
	return out if code == 0 and FileAccess.file_exists(out) else ProjectSettings.globalize_path(dir)
