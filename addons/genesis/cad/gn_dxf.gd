@tool
extends RefCounted

# Reads an AutoCAD DXF drawing (the ASCII kind every CAD program writes) into
# linework per layer: lines, polylines with their arcs, circles, arcs,
# ellipses, splines, 3D faces, text, and blocks inserted any number of times,
# scaled, turned, mirrored and arrayed, nested as deep as the drawing goes.
# Dimensions come through as the geometry their blocks carry.
#
# Coordinates stay in 64-bit floats, in the drawing's own units, until the
# drawing is placed: a site plan drawn in millimetres half a million units
# from its origin would lose the millimetres in Godot's 32-bit vectors.
#
# The result is plain data (see read()); GnDrawing turns it into a node.

# $INSUNITS codes to metres (0, unitless, is left to the reader to decide).
const UNIT_METRES := {1: 0.0254, 2: 0.3048, 3: 1609.344, 4: 0.001, 5: 0.01, 6: 1.0, 7: 1000.0, 8: 0.0000000254,
	9: 0.0000254, 10: 0.9144, 14: 0.1}
const UNIT_NAMES := {0: "unitless", 1: "inches", 2: "feet", 3: "miles", 4: "millimetres", 5: "centimetres", 6: "metres",
	7: "kilometres", 10: "yards", 14: "decimetres"}
# How finely curves are drawn: one straight piece per this many degrees.
const ARC_STEP_DEG := 5.0
const MAX_DEPTH := 16


class Drawing:
	var units := 0
	## layer name -> {"colour": Color, "on": bool}
	var layers := {}
	## layer name -> PackedFloat64Array of segment ends: x0 y0 z0 x1 y1 z1 ...
	var segments := {}
	## layer name -> PackedColorArray, one colour per segment
	var colours := {}
	## {"layer", "text", "x", "y", "z", "height", "angle"} (angle in radians)
	var texts: Array = []
	## entity type -> how many were drawn / how many were skipped
	var counts := {}
	var skipped := {}
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	# 64-bit extents, for recentring without losing precision
	var lo_x := INF
	var lo_y := INF
	var hi_x := -INF
	var hi_y := -INF
	var error := ""

	func segment_count() -> int:
		var n := 0
		for l in segments:
			n += (segments[l] as PackedFloat64Array).size() / 6
		return n


# An entity: its type and every group code it carried, in order.
class Entity:
	var type := ""
	var codes: Array = []   # [int, String] pairs
	var vertices: Array = []   # POLYLINE's VERTEX entities

	func s(code: int, default := "") -> String:
		for c in codes:
			if c[0] == code:
				return c[1]
		return default

	func f(code: int, default := 0.0) -> float:
		for c in codes:
			if c[0] == code:
				return float(c[1])
		return default

	func i(code: int, default := 0) -> int:
		for c in codes:
			if c[0] == code:
				return int(c[1])
		return default

	func all(code: int) -> Array:
		var out: Array = []
		for c in codes:
			if c[0] == code:
				out.append(float(c[1]))
		return out


# A 2D affine transform (a b c / d e f) with a z scale and offset, in 64 bits.
class Xf:
	var a := 1.0
	var b := 0.0
	var c := 0.0
	var d := 0.0
	var e := 1.0
	var f := 0.0
	var sz := 1.0
	var tz := 0.0

	func apply(x: float, y: float, z: float) -> Array:
		return [a * x + b * y + c, d * x + e * y + f, sz * z + tz]

	func then(o: Xf) -> Xf:
		# self applied after o: self * o
		var r := Xf.new()
		r.a = a * o.a + b * o.d
		r.b = a * o.b + b * o.e
		r.c = a * o.c + b * o.f + c
		r.d = d * o.a + e * o.d
		r.e = d * o.b + e * o.e
		r.f = d * o.c + e * o.f + f
		r.sz = sz * o.sz
		r.tz = sz * o.tz + tz
		return r

	func scale_factor() -> float:
		return sqrt(absf(a * e - b * d))

	func mirrored() -> bool:
		return a * e - b * d < 0.0


## Reads a DXF file. Check .error on the result.
static func read(path: String) -> Drawing:
	var out := Drawing.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		out.error = "Can't open %s" % path
		return out
	var head := file.get_buffer(22)
	if head.get_string_from_ascii().begins_with("AutoCAD Binary DXF"):
		out.error = "This is a binary DXF; save it from your CAD program as ASCII DXF."
		return out
	file.seek(0)
	var lines := file.get_as_text().replace("\r\n", "\n").replace("\r", "\n").split("\n")
	return parse(lines, out)


## Parses DXF text already split into lines.
static func parse(lines: PackedStringArray, out: Drawing = null) -> Drawing:
	if out == null:
		out = Drawing.new()
	var pairs: Array = []
	var n := lines.size() - 1
	var k := 0
	while k < n:
		var code_text := lines[k].strip_edges()
		if not code_text.is_valid_int():
			out.error = "Not a DXF file (line %d is not a group code)." % (k + 1)
			return out
		pairs.append([int(code_text), lines[k + 1].strip_edges()])
		k += 2
	if pairs.is_empty():
		out.error = "The file is empty."
		return out

	var blocks := {}   # name -> {"x", "y", "z", "entities": Array}
	var entities: Array = []
	var section := ""
	var table := ""
	var p := 0
	var block_name := ""
	var block: Dictionary = {}
	while p < pairs.size():
		var code: int = pairs[p][0]
		var value: String = pairs[p][1]
		if code == 0 and value == "SECTION":
			section = pairs[p + 1][1] if p + 1 < pairs.size() else ""
			p += 2
			continue
		if code == 0 and value == "ENDSEC":
			section = ""
			p += 1
			continue
		if section == "HEADER":
			if code == 9 and value == "$INSUNITS" and p + 1 < pairs.size():
				out.units = int(pairs[p + 1][1])
			p += 1
			continue
		if section == "TABLES":
			if code == 0 and value == "TABLE":
				table = pairs[p + 1][1] if p + 1 < pairs.size() else ""
				p += 2
				continue
			if code == 0 and value == "LAYER" and table == "LAYER":
				var e := _entity_at(pairs, p)
				var colour := e.i(62, 7)
				var name := e.s(2, "0")
				out.layers[name] = {"colour": aci(absi(colour)), "on": colour >= 0 and (e.i(70) & 1) == 0}
				if e.codes.any(func(cv): return cv[0] == 420):
					out.layers[name].colour = _true_colour(e.i(420))
				p = e.codes.size() + p + 1
				continue
			p += 1
			continue
		if section == "BLOCKS":
			if code == 0 and value == "BLOCK":
				var e := _entity_at(pairs, p)
				block_name = e.s(2)
				block = {"x": e.f(10), "y": e.f(20), "z": e.f(30), "entities": []}
				p += e.codes.size() + 1
				continue
			if code == 0 and value == "ENDBLK":
				if block_name != "":
					blocks[block_name] = block
				block_name = ""
				p += _entity_at(pairs, p).codes.size() + 1
				continue
			if code == 0 and block_name != "":
				p = _read_entity(pairs, p, block.entities)
				continue
			p += 1
			continue
		if section == "ENTITIES":
			if code == 0 and value != "ENDSEC":
				p = _read_entity(pairs, p, entities)
				continue
		p += 1

	for name in out.layers:
		out.segments[name] = PackedFloat64Array()
		out.colours[name] = PackedColorArray()
	var ctx := {"out": out, "blocks": blocks}
	for e in entities:
		_draw(e, Xf.new(), "", Color(), ctx, 0)
	return out


# The entity starting at pairs[p] (a 0 code), without its leading 0 pair.
static func _entity_at(pairs: Array, p: int) -> Entity:
	var e := Entity.new()
	e.type = pairs[p][1]
	var q := p + 1
	while q < pairs.size() and pairs[q][0] != 0:
		e.codes.append(pairs[q])
		q += 1
	return e


# Reads one entity (and a POLYLINE's vertices) into list; returns the next index.
static func _read_entity(pairs: Array, p: int, list: Array) -> int:
	var e := _entity_at(pairs, p)
	var q := p + 1 + e.codes.size()
	if e.type == "POLYLINE":
		while q < pairs.size() and pairs[q][1] == "VERTEX" and pairs[q][0] == 0:
			var v := _entity_at(pairs, q)
			e.vertices.append(v)
			q += 1 + v.codes.size()
		if q < pairs.size() and pairs[q][1] == "SEQEND":
			q += 1 + _entity_at(pairs, q).codes.size()
	list.append(e)
	return q


# Draws an entity through xf. Blocks' layer "0" and BYBLOCK colours take the
# insert's layer and colour, as CAD does.
static func _draw(e: Entity, xf: Xf, parent_layer: String, parent_colour: Color, ctx: Dictionary, depth: int) -> void:
	var out: Drawing = ctx.out
	var layer := e.s(8, "0")
	if layer == "0" and parent_layer != "":
		layer = parent_layer
	if not out.layers.has(layer):
		out.layers[layer] = {"colour": aci(7), "on": true}
		out.segments[layer] = PackedFloat64Array()
		out.colours[layer] = PackedColorArray()
	var colour: Color = out.layers[layer].colour
	var ci := e.i(62, 256)
	if e.codes.any(func(cv): return cv[0] == 420):
		colour = _true_colour(e.i(420))
	elif ci == 0 and parent_colour != Color():
		colour = parent_colour
	elif ci > 0 and ci < 256:
		colour = aci(ci)
	# An entity whose extrusion points down is drawn mirrored (OCS -Z).
	var ocs := xf
	if e.f(230, 1.0) < 0.0:
		var flip := Xf.new()
		flip.a = -1.0
		ocs = xf.then(flip)
	var pts: Array = []   # polylines of [x, y, z]
	match e.type:
		"LINE":
			pts.append([[e.f(10), e.f(20), e.f(30)], [e.f(11), e.f(21), e.f(31)]])
			ocs = xf   # LINE is in world coordinates
		"LWPOLYLINE":
			var xs := e.all(10)
			var ys := e.all(20)
			var bulges := _lw_bulges(e)
			var z := e.f(38)
			var closed := (e.i(70) & 1) == 1
			pts.append(_bulged(xs, ys, bulges, closed, z))
		"POLYLINE":
			var flags := e.i(70)
			if flags & 16 or flags & 64:
				# Polygon meshes and polyface meshes: draw their vertices' outline.
				out.skipped[e.type + " mesh"] = int(out.skipped.get(e.type + " mesh", 0)) + 1
				return
			var xs: Array = []
			var ys: Array = []
			var bulges: Array = []
			var zs: Array = []
			for v in e.vertices:
				xs.append(v.f(10))
				ys.append(v.f(20))
				zs.append(v.f(30))
				bulges.append(v.f(42))
			var closed := (flags & 1) == 1
			if flags & 8:
				# A 3D polyline is in world coordinates, straight segments.
				ocs = xf
				var line: Array = []
				for q in xs.size():
					line.append([xs[q], ys[q], zs[q]])
				if closed and xs.size() > 2:
					line.append(line[0])
				pts.append(line)
			else:
				pts.append(_bulged(xs, ys, bulges, closed, e.f(30)))
		"CIRCLE":
			pts.append(_arc(e.f(10), e.f(20), e.f(30), e.f(40), 0.0, TAU))
		"ARC":
			var a0 := deg_to_rad(e.f(50))
			var a1 := deg_to_rad(e.f(51))
			while a1 <= a0:
				a1 += TAU
			pts.append(_arc(e.f(10), e.f(20), e.f(30), e.f(40), a0, a1))
		"ELLIPSE":
			ocs = xf
			pts.append(_ellipse(e))
		"SPLINE":
			ocs = xf
			pts.append(_spline(e))
		"3DFACE", "SOLID", "TRACE":
			var c := [[e.f(10), e.f(20), e.f(30)], [e.f(11), e.f(21), e.f(31)], [e.f(12), e.f(22), e.f(32)], [e.f(13), e.f(23), e.f(33)]]
			if e.type != "3DFACE":
				# SOLID's third and fourth corners go the other way round.
				c = [c[0], c[1], c[3], c[2]]
			else:
				ocs = xf
			pts.append(c + [c[0]])
		"TEXT", "MTEXT", "ATTRIB":
			if e.type == "ATTRIB" and (e.i(70) & 1):
				return   # invisible attribute
			var text := e.s(1)
			if e.type == "MTEXT":
				var chunks := ""
				for cv in e.codes:
					if cv[0] == 3:
						chunks += cv[1]
				text = _plain(chunks + text)
			if text.strip_edges() == "":
				return
			var ang := deg_to_rad(e.f(50))
			if e.type == "MTEXT" and e.codes.any(func(cv): return cv[0] == 11):
				ang = atan2(e.f(21), e.f(11))
			# Justified TEXT is placed at its second alignment point.
			var at := [e.f(10), e.f(20), e.f(30)]
			if e.type != "MTEXT" and (e.i(72) != 0 or e.i(73) != 0) and e.codes.any(func(cv): return cv[0] == 11):
				at = [e.f(11), e.f(21), e.f(31)]
			var w := ocs.apply(at[0], at[1], at[2])
			var dir := ocs.apply(cos(ang), sin(ang), 0.0)
			var o := ocs.apply(0.0, 0.0, 0.0)
			out.texts.append({"layer": layer, "text": text, "x": w[0], "y": w[1], "z": w[2],
				"height": e.f(40, 1.0) * ocs.scale_factor(), "angle": atan2(dir[1] - o[1], dir[0] - o[0]), "colour": colour})
			_extend(out, w[0], w[1], w[2])
			out.counts[e.type] = int(out.counts.get(e.type, 0)) + 1
			return
		"INSERT", "DIMENSION":
			if depth >= MAX_DEPTH:
				return
			var name := e.s(2)
			if not ctx.blocks.has(name):
				return
			var blk: Dictionary = ctx.blocks[name]
			var inner := Xf.new()
			if e.type == "INSERT":
				var sx := e.f(41, 1.0)
				var sy := e.f(42, 1.0)
				var r := deg_to_rad(e.f(50))
				var n_cols := maxi(e.i(70, 1), 1)
				var n_rows := maxi(e.i(71, 1), 1)
				for row in n_rows:
					for col in n_cols:
						# Array spacing runs along the insert's own turned axes.
						var ox := col * e.f(44)
						var oy := row * e.f(45)
						var t := Xf.new()
						t.a = cos(r) * sx
						t.b = -sin(r) * sy
						t.d = sin(r) * sx
						t.e = cos(r) * sy
						t.c = e.f(10) + cos(r) * ox - sin(r) * oy - (t.a * blk.x + t.b * blk.y)
						t.f = e.f(20) + sin(r) * ox + cos(r) * oy - (t.d * blk.x + t.e * blk.y)
						t.sz = e.f(43, 1.0)
						t.tz = e.f(30) - t.sz * blk.z
						var through := ocs.then(t)
						for child in blk.entities:
							_draw(child, through, layer, colour, ctx, depth + 1)
			else:
				inner.c = -blk.x
				inner.f = -blk.y
				for child in blk.entities:
					_draw(child, xf.then(inner), layer, colour, ctx, depth + 1)
			out.counts[e.type] = int(out.counts.get(e.type, 0)) + 1
			return
		_:
			out.skipped[e.type] = int(out.skipped.get(e.type, 0)) + 1
			return
	var segs: PackedFloat64Array = out.segments[layer]
	var cols: PackedColorArray = out.colours[layer]
	for line in pts:
		for q in range(line.size() - 1):
			var p0 := ocs.apply(line[q][0], line[q][1], line[q][2])
			var p1 := ocs.apply(line[q + 1][0], line[q + 1][1], line[q + 1][2])
			segs.append_array(PackedFloat64Array([p0[0], p0[1], p0[2], p1[0], p1[1], p1[2]]))
			cols.append(colour)
			_extend(out, p0[0], p0[1], p0[2])
			_extend(out, p1[0], p1[1], p1[2])
	out.segments[layer] = segs
	out.colours[layer] = cols
	out.counts[e.type] = int(out.counts.get(e.type, 0)) + 1


static func _extend(out: Drawing, x: float, y: float, z: float) -> void:
	out.lo_x = minf(out.lo_x, x)
	out.lo_y = minf(out.lo_y, y)
	out.hi_x = maxf(out.hi_x, x)
	out.hi_y = maxf(out.hi_y, y)
	out.lo.z = minf(out.lo.z, z)
	out.hi.z = maxf(out.hi.z, z)


# LWPOLYLINE bulges belong to the vertex they follow; a vertex without one is 0.
static func _lw_bulges(e: Entity) -> Array:
	var out: Array = []
	var seen := false
	for c in e.codes:
		if c[0] == 10:
			if seen:
				out.append(0.0)
			seen = true
		elif c[0] == 42 and seen:
			out.append(float(c[1]))
			seen = false
	if seen:
		out.append(0.0)
	return out


# A polyline's points, each bulged segment drawn as its arc.
static func _bulged(xs: Array, ys: Array, bulges: Array, closed: bool, z: float) -> Array:
	var line: Array = []
	var n := xs.size()
	if n == 0:
		return line
	var last := n if closed else n - 1
	line.append([xs[0], ys[0], z])
	for q in last:
		var r := (q + 1) % n
		var bulge: float = bulges[q] if q < bulges.size() else 0.0
		if absf(bulge) > 1e-9:
			var x0: float = xs[q]
			var y0: float = ys[q]
			var x1: float = xs[r]
			var y1: float = ys[r]
			var cx := x1 - x0
			var cy := y1 - y0
			var chord := sqrt(cx * cx + cy * cy)
			if chord > 0.0:
				var theta := 4.0 * atan(bulge)
				var h := chord * 0.5 / tan(theta * 0.5)
				var mx := (x0 + x1) * 0.5 - cy / chord * h
				var my := (y0 + y1) * 0.5 + cx / chord * h
				var rad := sqrt((x0 - mx) * (x0 - mx) + (y0 - my) * (y0 - my))
				var a0 := atan2(y0 - my, x0 - mx)
				var steps := maxi(2, int(ceil(absf(rad_to_deg(theta)) / ARC_STEP_DEG)))
				for s in range(1, steps):
					var a := a0 + theta * s / steps
					line.append([mx + rad * cos(a), my + rad * sin(a), z])
		line.append([xs[r], ys[r], z])
	return line


static func _arc(cx: float, cy: float, cz: float, r: float, a0: float, a1: float) -> Array:
	var steps := maxi(8, int(ceil(rad_to_deg(a1 - a0) / ARC_STEP_DEG)))
	var line: Array = []
	for s in steps + 1:
		var a := a0 + (a1 - a0) * s / steps
		line.append([cx + r * cos(a), cy + r * sin(a), cz])
	return line


static func _ellipse(e: Entity) -> Array:
	var cx := e.f(10)
	var cy := e.f(20)
	var mx := e.f(11)
	var my := e.f(21)
	var ratio := e.f(40, 1.0)
	var t0 := e.f(41, 0.0)
	var t1 := e.f(42, TAU)
	while t1 <= t0:
		t1 += TAU
	var nx := -my * ratio
	var ny := mx * ratio
	if e.f(230, 1.0) < 0.0:
		nx = -nx
		ny = -ny
	var steps := maxi(8, int(ceil(rad_to_deg(t1 - t0) / ARC_STEP_DEG)))
	var line: Array = []
	for s in steps + 1:
		var t := t0 + (t1 - t0) * s / steps
		line.append([cx + mx * cos(t) + nx * sin(t), cy + my * cos(t) + ny * sin(t), e.f(30)])
	return line


# A B-spline evaluated from its control points and knots (de Boor), weighted
# if it is rational; fit points only, if that is all the file gives.
static func _spline(e: Entity) -> Array:
	var cx := e.all(10)
	var cy := e.all(20)
	var cz := e.all(30)
	var knots := e.all(40)
	var weights := e.all(41)
	var degree := e.i(71, 3)
	var n := cx.size()
	var line: Array = []
	if n < 2 or knots.size() != n + degree + 1:
		var fx := e.all(11)
		var fy := e.all(21)
		for q in fx.size():
			line.append([fx[q], fy[q], 0.0])
		if line.is_empty():
			for q in n:
				line.append([cx[q], cy[q], cz[q] if q < cz.size() else 0.0])
		return line
	var lo: float = knots[degree]
	var hi: float = knots[n]
	var steps := maxi(16, n * 8)
	for s in steps + 1:
		var t := lerpf(lo, hi, float(s) / steps)
		line.append(_de_boor(t, degree, knots, cx, cy, cz, weights))
	return line


static func _de_boor(t: float, p: int, knots: Array, cx: Array, cy: Array, cz: Array, w: Array) -> Array:
	var n := cx.size()
	var k := p
	while k < n - 1 and t >= knots[k + 1]:
		k += 1
	var d: Array = []
	for j in p + 1:
		var idx := k - p + j
		var wt: float = w[idx] if idx < w.size() else 1.0
		d.append([cx[idx] * wt, cy[idx] * wt, (cz[idx] if idx < cz.size() else 0.0) * wt, wt])
	for r in range(1, p + 1):
		for j in range(p, r - 1, -1):
			var i := k - p + j
			var den: float = knots[i + p - r + 1] - knots[i]
			var alpha: float = 0.0 if den == 0.0 else (t - knots[i]) / den
			for c in 4:
				d[j][c] = (1.0 - alpha) * d[j - 1][c] + alpha * d[j][c]
	var h: Array = d[p]
	var wt: float = h[3] if h[3] != 0.0 else 1.0
	return [h[0] / wt, h[1] / wt, h[2] / wt]


# MTEXT's formatting codes stripped: paragraph breaks become new lines.
static func _plain(text: String) -> String:
	var re := RegEx.new()
	text = text.replace("\\P", "\n").replace("\\~", " ")
	re.compile("\\\\[ACcFfHhQqTtWw][^;]*;")
	text = re.sub(text, "", true)
	re.compile("\\\\[LlOoKk]")
	text = re.sub(text, "", true)
	return text.replace("{", "").replace("}", "").replace("%%c", "Ø").replace("%%d", "°").replace("%%p", "±")


static func _true_colour(v: int) -> Color:
	return Color8((v >> 16) & 255, (v >> 8) & 255, v & 255)


## An AutoCAD colour index as a colour. 7 (white on screen, black on paper)
## is drawn dark, as on a printed plan lying on the floor.
static func aci(i: int) -> Color:
	var fixed := {1: Color(1, 0, 0), 2: Color(1, 1, 0), 3: Color(0, 1, 0), 4: Color(0, 1, 1), 5: Color(0, 0, 1),
		6: Color(1, 0, 1), 7: Color(0.08, 0.08, 0.08), 8: Color(0.5, 0.5, 0.5), 9: Color(0.75, 0.75, 0.75)}
	if fixed.has(i):
		return fixed[i]
	if i >= 250 and i <= 255:
		var g := [0.2, 0.31, 0.41, 0.51, 0.68, 1.0][i - 250] as float
		return Color(g, g, g)
	if i >= 10 and i <= 249:
		var hue := float((i / 10) - 1) * 15.0 / 360.0
		var sub := i % 10
		var value := [1.0, 1.0, 0.65, 0.65, 0.5, 0.5, 0.3, 0.3, 0.15, 0.15][sub] as float
		var sat := 1.0 if sub % 2 == 0 else 0.5
		return Color.from_hsv(hue, sat, value)
	return Color(0.08, 0.08, 0.08)
