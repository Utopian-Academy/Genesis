@tool
extends RefCounted

# The asset library: every model under res://genesis_assets/<category>/
# that has a licence sidecar next to it. An asset without one is skipped and
# reported rather than listed, so nothing of unknown provenance can end up in
# somebody's render.

const ROOT := "res://genesis_assets"
const CATEGORIES := ["trees", "plants", "grass", "people", "animals", "vehicles", "furniture", "architecture", "props",
	"boats", "aircraft", "audio", "lighting", "control", "av"]
const MODEL_EXTENSIONS := ["glb", "gltf", "blend", "fbx", "obj", "tscn"]


class Asset:
	var path: String
	var name: String
	var category: String
	var license: Dictionary

	func label() -> String:
		# Generated kit carries a proper name in its sidecar ("Kora compact
		# line array element"); anything else is named after its file.
		if license.has("label"):
			return str(license.label)
		return name.replace("_", " ").capitalize()


# Returns {assets: Array[Asset], unlicensed: Array[String]}.
static func scan() -> Dictionary:
	var assets: Array = []
	var unlicensed: Array = []
	for category in CATEGORIES:
		var dir := "%s/%s" % [ROOT, category]
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			if file.get_extension().to_lower() not in MODEL_EXTENSIONS:
				continue
			var path := "%s/%s" % [dir, file]
			var license := _read_license(path)
			if license.is_empty():
				unlicensed.append(path)
				continue
			var a := Asset.new()
			a.path = path
			a.name = file.get_basename()
			a.category = category
			a.license = license
			assets.append(a)
	return {"assets": assets, "unlicensed": unlicensed}


static func _read_license(model_path: String) -> Dictionary:
	var sidecar := model_path.get_basename() + ".license.json"
	if not FileAccess.file_exists(sidecar):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(sidecar))
	if parsed is Dictionary and parsed.has("license"):
		return parsed
	return {}


# The licence sidecar of one model, or {} if it has none.
static func info(model_path: String) -> Dictionary:
	return _read_license(model_path)


# Every asset in a category whose sidecar says it is of this kind
# ("line_array_element", "moving_head"...), sorted by path.
static func of_kind(category: String, kinds: Array) -> Array:
	var out: Array = []
	for a in scan().assets:
		if a.category == category and (kinds.is_empty() or str(a.license.get("kind", "")) in kinds):
			out.append(a)
	out.sort_custom(func(x, y): return x.path < y.path)
	return out


## A library model by category and name, whatever it was saved as
## ("lighting", "wash_aurora" -> .../wash_aurora.gltf), or "".
static func find(category: String, name: String) -> String:
	for ext in ["gltf", "glb", "tscn"]:
		var p := "%s/%s/%s.%s" % [ROOT, category, name, ext]
		if ResourceLoader.exists(p):
			return p
	return ""
