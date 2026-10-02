@tool
extends RefCounted

# IES photometry (the LM-63 files lighting manufacturers publish for every
# fitting). Godot has no IES lights, but a spotlight can carry a projector
# image; the beam's shape, how bright it is at each angle off its axis, is
# drawn into one, and the spot's cone is opened to where the light runs out.
# The fitting's own lumens come from the file too.


class Profile:
	var vertical := PackedFloat32Array()   # degrees from straight down (nadir)
	var candela := PackedFloat32Array()    # averaged round the fitting
	var lumens := 0.0

	## Candela at an angle off the axis, interpolated.
	func at(angle: float) -> float:
		if vertical.is_empty():
			return 0.0
		if angle <= vertical[0]:
			return candela[0]
		for i in range(1, vertical.size()):
			if angle <= vertical[i]:
				var t := (angle - vertical[i - 1]) / maxf(vertical[i] - vertical[i - 1], 0.0001)
				return lerpf(candela[i - 1], candela[i], t)
		return candela[candela.size() - 1]

	## The half-angle where the light falls below `fraction` of its peak.
	func cutoff(fraction := 0.05) -> float:
		var peak := 0.0
		for c in candela:
			peak = maxf(peak, c)
		var last := vertical[0] if not vertical.is_empty() else 0.0
		for i in vertical.size():
			if candela[i] >= peak * fraction:
				last = vertical[i]
		return last


## Reads an LM-63 file; null if it isn't one.
static func load_file(path: String) -> Profile:
	var text := FileAccess.get_file_as_string(path)
	var at := text.find("TILT=")
	if at < 0:
		return null
	# Everything after the TILT line is whitespace-separated numbers.
	var rest := text.substr(text.find("\n", at) + 1)
	var nums := PackedFloat32Array()
	for tok in rest.replace("\r", " ").replace("\n", " ").replace("\t", " ").replace(",", " ").split(" ", false):
		if tok.is_valid_float():
			nums.append(tok.to_float())
	if nums.size() < 13:
		return null
	var lamps := nums[0]
	var lm_per_lamp := nums[1]
	var multiplier := nums[2]
	var n_v := int(nums[3])
	var n_h := int(nums[4])
	var i := 13  # 10 numbers, then ballast factor, future use, watts
	if nums.size() < i + n_v + n_h + n_v * n_h:
		return null
	var p := Profile.new()
	p.vertical = nums.slice(i, i + n_v)
	i += n_v + n_h
	p.candela.resize(n_v)
	for h in n_h:
		for v in n_v:
			p.candela[v] += nums[i + h * n_v + v] * multiplier / n_h
	# Absolute photometry files (LED) say -1 lumens per lamp: sum the beam.
	p.lumens = lamps * lm_per_lamp if lm_per_lamp > 0.0 else _integrate(p)
	return p


# Lumens from a symmetric candela distribution: the sum of candela times
# the solid angle of each ring.
static func _integrate(p: Profile) -> float:
	var total := 0.0
	for k in range(1, p.vertical.size()):
		var a0 := deg_to_rad(p.vertical[k - 1])
		var a1 := deg_to_rad(p.vertical[k])
		total += (p.candela[k - 1] + p.candela[k]) * 0.5 * TAU * (cos(a0) - cos(a1))
	return total


## The beam as a projector image for a spot opened to `half_angle` degrees:
## the centre is the axis, the edge of the circle is the cone's edge.
static func projector(p: Profile, half_angle: float, size := 256) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	var peak := 0.0
	for c in p.candela:
		peak = maxf(peak, c)
	var t_edge := tan(deg_to_rad(clampf(half_angle, 1.0, 89.0)))
	for y in size:
		for x in size:
			var r := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var angle := rad_to_deg(atan(r * t_edge))
			var v := p.at(angle) / maxf(peak, 0.0001) if r <= 1.0 else 0.0
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## Puts a profile on a spotlight: its cone, its beam shape, its output.
static func apply(spot: SpotLight3D, p: Profile) -> void:
	var half := clampf(p.cutoff(), 2.0, 89.0)
	spot.spot_angle = half
	# The projector already carries the fall-off; the light itself stays even.
	spot.spot_angle_attenuation = 0.1
	spot.light_projector = projector(p, half)
