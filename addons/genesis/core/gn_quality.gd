@tool
extends RefCounted

# Final-render quality, switched on only for the moment a still is captured.
# The editor stays fast for moving around and painting; the image gets bounce
# light, soft sun shadows and ultra filtering. Everything changed is recorded
# and put back afterwards, and none of it touches the undo history.

const GnScene := preload("res://addons/genesis/core/gn_scene.gd")

# Frames to wait before capturing, for the screen-space effects to settle.
const SETTLE_DRAFT := 8
const SETTLE_HIGH := 24


class State:
	var props: Array = []  # [object, property, old value]


static func begin_high() -> State:
	var st := State.new()
	var world := GnScene.find_role("environment") as WorldEnvironment
	var sun := GnScene.find_role("sun") as DirectionalLight3D
	if world and world.environment:
		var env := world.environment
		# Bounce light between nearby surfaces. SDFGI (Godot's full real-time
		# GI) is deliberately NOT used: tested on the demo, it adds the photo
		# sky's light to an open field a second time and washes the whole image
		# out, killing the sun's shadows. Screen-space GI keeps the contrast.
		_change(st, env, "ssil_enabled", true)
		_change(st, env, "ssil_intensity", 1.2)
		_change(st, env, "ssao_enabled", true)
	if sun:
		# The real sun is half a degree across; a point sun gives razor
		# shadows that read as CG.
		_change(st, sun, "light_angular_distance", 0.6)
		_change(st, sun, "directional_shadow_max_distance", maxf(sun.directional_shadow_max_distance, 250.0))
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_ULTRA, true, 0.5, 2, 50, 300)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_ULTRA, true, 0.5, 4, 50, 300)
	# A finer haze grid, so narrow stage beams stay crisp instead of smearing.
	RenderingServer.environment_set_volumetric_fog_volume_size(160, 128)
	return st


static func end(st: State) -> void:
	for p in st.props:
		p[0].set(p[1], p[2])
	# Back to the project's own settings for the editor view.
	RenderingServer.directional_soft_shadow_filter_set_quality(
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2))
	RenderingServer.positional_soft_shadow_filter_set_quality(
		ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2))
	RenderingServer.environment_set_ssao_quality(
		ProjectSettings.get_setting("rendering/environment/ssao/quality", 2), true, 0.5, 2, 50, 300)
	RenderingServer.environment_set_ssil_quality(
		ProjectSettings.get_setting("rendering/environment/ssil/quality", 2), true, 0.5, 4, 50, 300)
	RenderingServer.environment_set_volumetric_fog_volume_size(
		ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_size", 64),
		ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_depth", 64))


static func _change(st: State, obj: Object, prop: String, value: Variant) -> void:
	st.props.append([obj, prop, obj.get(prop)])
	obj.set(prop, value)
