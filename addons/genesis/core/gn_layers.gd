@tool
extends RefCounted

# Layers: named sets of objects that can be shown or hidden together, the
# way Lumion's layers work (landscaping on one, furniture on another,
# options A and B on two more). A node's layer is metadata, so it survives
# with the scene and costs nothing when the plugin is off; showing and hiding
# is the node's own visible flag, undoable.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

const META := &"gn_layer"


## {layer name: [nodes]} for the edited scene, sorted by name.
static func layers() -> Dictionary:
	var out := {}
	var root := GnScene.root()
	if root == null:
		return out
	for n in root.find_children("*", "Node3D", true, false):
		var name := str(n.get_meta(META, ""))
		if name == "":
			continue
		if not out.has(name):
			out[name] = []
		out[name].append(n)
	var sorted := {}
	var keys := out.keys()
	keys.sort()
	for k in keys:
		sorted[k] = out[k]
	return sorted


## Puts nodes on a layer ("" takes them off), as one undo step.
static func assign(nodes: Array, layer: String) -> void:
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Genesis: put on layer %s" % layer, UndoRedo.MERGE_DISABLE, GnScene.root())
	for n in nodes:
		if not n is Node3D:
			continue
		var before = n.get_meta(META, "")
		if layer == "":
			ur.add_do_method(n, "remove_meta", META)
		else:
			ur.add_do_method(n, "set_meta", META, layer)
		if before == "":
			ur.add_undo_method(n, "remove_meta", META)
		else:
			ur.add_undo_method(n, "set_meta", META, before)
	ur.commit_action()


static func is_shown(layer: String) -> bool:
	for n in layers().get(layer, []):
		if (n as Node3D).visible:
			return true
	return false


static func show(layer: String, on: bool) -> void:
	var changes: Array = []
	for n in layers().get(layer, []):
		changes.append([n, "visible", on])
	if not changes.is_empty():
		GnScene.set_props("Genesis: %s layer %s" % ["show" if on else "hide", layer], changes)
