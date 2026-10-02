@tool
extends RefCounted

# Finds and adds the nodes Genesis manages in the edited scene. They are
# ordinary nodes tagged with `genesis_role` metadata, so a scene still opens
# and renders with the plugin disabled; the tag is only how we find them again.

const ROLE := &"genesis_role"


static func root() -> Node:
	return EditorInterface.get_edited_scene_root()


static func find_role(role: String) -> Node:
	var r := root()
	if r == null:
		return null
	if r.get_meta(ROLE, "") == role:
		return r
	for node in r.find_children("*", "", true, false):
		if node.get_meta(ROLE, "") == role:
			return node
	return null


# Adds `node` under `parent` as one undoable step. The node is kept alive by the
# undo history while it is out of the tree, which is what add_do_reference is for.
static func add_node(node: Node, parent: Node, action: String, role := "") -> void:
	if role != "":
		node.set_meta(ROLE, role)
	add_nodes([node], parent, action)


# Several nodes as a single undo step.
static func add_nodes(nodes: Array, parent: Node, action: String) -> void:
	var owner := root()
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action(action, UndoRedo.MERGE_DISABLE, owner)
	for node in nodes:
		ur.add_do_method(parent, "add_child", node, true)
		for n in _saved_nodes(node):
			ur.add_do_property(n, "owner", owner)
		ur.add_do_reference(node)
		ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()


# Every node under an added one needs the scene root as owner or it is not
# saved. Instanced scenes are the exception: their insides belong to them.
static func _saved_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	if node.scene_file_path == "":
		for child in node.get_children():
			out.append_array(_saved_nodes(child))
	return out


# A property change that merges with the previous one of the same name, so
# dragging a slider is one undo step rather than a hundred.
static func set_props(action: String, changes: Array) -> void:
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action(action, UndoRedo.MERGE_ENDS, root())
	for c in changes:
		var obj: Object = c[0]
		ur.add_do_property(obj, c[1], c[2])
		ur.add_undo_property(obj, c[1], obj.get(c[1]))
	ur.commit_action()


static func select(node: Node) -> void:
	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)
	EditorInterface.edit_node(node)
