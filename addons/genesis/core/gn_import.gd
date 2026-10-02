@tool
extends RefCounted

# "Drop your building in": copy a model from anywhere on disk into the
# project, let Godot's importer do the actual importing, then place it at the
# origin. Genesis does not parse a single byte of the model itself.

const GnPlacement := preload("res://addons/genesis/core/gn_placement.gd")
const GnLiveLink := preload("res://addons/genesis/core/gn_live_link.gd")

const DEST := "res://assets"
const EXTENSIONS := ["glb", "gltf", "blend", "fbx", "obj"]


# Returns an error message, or "" once the model is in the scene.
static func import_building(source: String) -> String:
	var ext := source.get_extension().to_lower()
	if ext not in EXTENSIONS:
		return "Genesis can bring in %s files." % ", ".join(EXTENSIONS)
	if ext == "blend":
		var settings := EditorInterface.get_editor_settings()
		if str(settings.get_setting("filesystem/import/blender/blender_path")) == "":
			return "To use .blend files directly, tell Godot where Blender is: Editor Settings → FileSystem → Import → Blender → Blender Path."
	if ext == "gltf":
		# A .gltf usually has a .bin and textures beside it; copying only the
		# .gltf would import an empty model.
		return "Export as .glb (one file) and bring that in instead."
	# The editor may still be importing (a project just opened, textures just
	# added). Starting our own scan then makes Godot refuse a second, nested
	# import, so wait for it to settle first.
	var efs := EditorInterface.get_resource_filesystem()
	if not await _idle(efs):
		return "The editor is still busy importing. Try again in a moment."
	DirAccess.make_dir_recursive_absolute(DEST)
	var dest := "%s/%s" % [DEST, source.get_file()]
	if DirAccess.copy_absolute(source, ProjectSettings.globalize_path(dest)) != OK:
		return "Could not copy %s into the project." % source
	# Wait for the imported model to exist, not for the scan to stop: on a
	# first import the scan has not started yet, so "not scanning" is true
	# before anything is imported. (update_file cannot do this either; it only
	# knows folders the editor has already scanned, and res://assets may be new.)
	efs.scan()
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await Engine.get_main_loop().process_frame
		if ResourceLoader.exists(dest) and not efs.is_scanning() and not efs.is_importing():
			break
	var node := GnPlacement.place(dest, "architecture", Vector3.ZERO)
	if node == null:
		return "Godot could not import %s." % source.get_file()
	# Re-exports of the source come in by themselves from now on.
	GnLiveLink.link(node, source)
	return ""


static func _idle(efs: EditorFileSystem) -> bool:
	var deadline := Time.get_ticks_msec() + 120000
	while efs.is_scanning() or efs.is_importing():
		if Time.get_ticks_msec() > deadline:
			return false
		await Engine.get_main_loop().process_frame
	return true
