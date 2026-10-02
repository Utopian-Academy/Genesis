@tool
extends RefCounted

# Live link: a building brought in from outside the project remembers the
# file it came from. When that file changes (re-exported from SketchUp,
# Revit, Rhino or Blender), the new version is copied over the project's copy
# and reimported, and the building in the scene updates where it stands,
# keeping its position, materials and everything placed around it.
#
# plugin.gd calls poll() every couple of seconds; it only reads file times.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

const SOURCE := &"gn_source"
const SOURCE_TIME := &"gn_source_time"

static var enabled := true
static var last_update := ""  # "house.glb at 14:05", for the Scene page


## Remembers where a placed building came from.
static func link(node: Node, source: String) -> void:
	node.set_meta(SOURCE, source)
	node.set_meta(SOURCE_TIME, FileAccess.get_modified_time(source))


## Every linked building in the edited scene.
static func linked() -> Array:
	var root := GnScene.root()
	if root == null:
		return []
	var out: Array = root.find_children("*", "Node3D", true, false).filter(func(n): return n.has_meta(SOURCE))
	if root.has_meta(SOURCE):
		out.push_front(root)
	return out


## Checks the sources; brings in any that changed. Returns how many did.
static func poll() -> int:
	if not enabled:
		return 0
	var efs := EditorInterface.get_resource_filesystem()
	if efs.is_scanning() or efs.is_importing():
		return 0
	var changed := PackedStringArray()
	for node in linked():
		var source := str(node.get_meta(SOURCE))
		if not FileAccess.file_exists(source):
			continue
		var t := FileAccess.get_modified_time(source)
		if t <= int(node.get_meta(SOURCE_TIME, 0)):
			continue
		var dest: String = node.scene_file_path
		if dest == "" or DirAccess.copy_absolute(source, ProjectSettings.globalize_path(dest)) != OK:
			continue
		node.set_meta(SOURCE_TIME, t)
		if not dest in changed:
			changed.append(dest)
		last_update = "%s at %s" % [source.get_file(), Time.get_time_string_from_system().left(5)]
	if not changed.is_empty():
		# A scan finds the project's copy changed and reimports it the way it
		# would a file overwritten by hand, which updates every instance.
		# (Calling reimport_files directly on a scene the editor has open
		# could take the editor down.)
		efs.scan()
	return changed.size()
