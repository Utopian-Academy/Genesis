@tool
extends RefCounted

# Temporary changes to the scene for a special render (clay, object ID,
# mask, depth), recorded so they can be put back exactly afterwards. Shared
# by render passes and by the Clay look.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

const DEPTH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, skip_vertex_transform;
uniform sampler2D depth_tex : hint_depth_texture;
uniform float far_m = 150.0;
void vertex() { POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0); }
void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float dist = length(v.xyz / v.w);
	ALBEDO = vec3(1.0 - clamp(dist / far_m, 0.0, 1.0));
}
"""


# The section cut fill ("poche"): drawn over every surface, it shows only
# the inside faces, in solid colour. Normally the outside hides them; where a
# camera's cut slices a wall open, the inside shows through, and the cut
# reads as solid, the way it does on an architect's section.
const CUT_FILL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 fill : source_color = vec3(0.07, 0.07, 0.08);
void fragment() {
	if (FRONT_FACING) {
		discard;
	}
	ALBEDO = fill;
}
"""


# What each pass changes, recorded so it can be put back exactly.
static func stage(pass_name: String) -> Array:
	var undo: Array = []
	var root := GnScene.root()
	match pass_name:
		"cut":
			var sh := Shader.new()
			sh.code = CUT_FILL_SHADER
			var fill := ShaderMaterial.new()
			fill.shader = sh
			for gi in root.find_children("*", "GeometryInstance3D", true, false):
				if _role_of(gi) in ["ground", "site"] or gi is GPUParticles3D:
					continue
				undo.append(["prop", gi, "material_overlay", gi.material_overlay])
				gi.material_overlay = fill
		"depth":
			var quad := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(2, 2)
			var mat := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = DEPTH_SHADER
			mat.shader = sh
			qm.material = mat
			quad.mesh = qm
			quad.extra_cull_margin = 16384.0
			root.add_child(quad)
			undo.append(["free", quad])
		"id", "clay", "mask":
			var world := GnScene.find_role("environment") as WorldEnvironment
			for gi in root.find_children("*", "GeometryInstance3D", true, false):
				var role := _role_of(gi)
				if pass_name == "mask" and role in ["ground", "site"]:
					undo.append(["prop", gi, "visible", gi.visible])
					gi.visible = false
					continue
				var m := StandardMaterial3D.new()
				if pass_name == "clay":
					m.albedo_color = Color(0.74, 0.735, 0.72)
					m.roughness = 0.9
				else:
					m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					m.albedo_color = Color.WHITE if pass_name == "mask" else _id_colour(gi)
				undo.append(["prop", gi, "material_override", gi.material_override])
				gi.material_override = m
			if pass_name in ["id", "mask"] and world and world.environment:
				var env := world.environment
				undo.append(["prop", env, "background_mode", env.background_mode])
				undo.append(["prop", env, "background_color", env.background_color])
				undo.append(["prop", env, "fog_enabled", env.fog_enabled])
				undo.append(["prop", env, "tonemap_mode", env.tonemap_mode])
				env.background_mode = Environment.BG_COLOR
				env.background_color = Color(0, 0, 0, 0)
				env.fog_enabled = false
				# Flat IDs must come out exactly as painted.
				env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return undo


static func unstage(undo: Array) -> void:
	undo.reverse()
	for u in undo:
		if u[0] == "free":
			u[1].queue_free()
		else:
			u[1].set(u[2], u[3])


# The scene-root child an object belongs to, and that child's role.
static func _role_of(n: Node) -> String:
	var root := GnScene.root()
	while n and n.get_parent() != root:
		n = n.get_parent()
	return str(n.get_meta(GnScene.ROLE, "")) if n else ""


# A stable, well-separated colour per top-level object: the same object gets
# the same colour in every render.
static func _id_colour(n: Node) -> Color:
	var root := GnScene.root()
	while n and n.get_parent() != root:
		n = n.get_parent()
	var h := float(hash(str(n.name)) % 997) / 997.0
	return Color.from_hsv(h, 0.75, 0.95)
