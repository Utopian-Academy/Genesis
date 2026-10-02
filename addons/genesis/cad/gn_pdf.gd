@tool
extends RefCounted

# CAD drawings saved as PDF, read as drawings: the page's own lines, at the
# drawing's scale, instead of a picture of them. Architects plot to PDF far
# more often than they send DXF, and a plotted PDF keeps every wall, door
# and grid line as exact vectors.
#
# A PDF has no layers, but a CAD plot draws each layer with its own pen, so
# lines are grouped by pen (weight and shade) into layers: the heavy pen is
# usually the walls. Filled shapes (hatching, and text the plotter turned
# into outlines) go on layers of their own.
#
# Reads PDF 1.0-2.0 structure: classic and compressed cross-reference
# tables, object streams, Flate compression with PNG predictors. Pictures
# on the page are skipped (bring a scanned plan in as an image instead).

const GnDxf := preload("res://addons/genesis/cad/gn_dxf.gd")

## Points per inch on a PDF page.
const PT_INCH := 72.0
const CURVE_STEPS := 8
const MAX_FORM_DEPTH := 12

var _b := PackedByteArray()
var _xref := {}         # object number -> {"off": int} or {"stm": int, "idx": int}
var _cache := {}        # object number -> parsed value
var _stm_cache := {}    # object stream number -> {"data": bytes, "offsets": {num: off}}
var _trailer := {}
var error := ""


## Reads one page of a PDF as a drawing: `page` from 1, `ratio` the
## drawing's scale (48 for 1/4" = 1'-0", 100 for 1:100). Check .error.
static func read(path: String, page := 1, ratio := 100.0) -> GnDxf.Drawing:
	var out := GnDxf.Drawing.new()
	out.units = 6
	var pdf = (load("res://addons/genesis/cad/gn_pdf.gd") as GDScript).new()
	pdf._open(path)
	if pdf.error != "":
		out.error = pdf.error
		return out
	var pages: Array = pdf.pages()
	if pages.is_empty():
		out.error = "No pages found in %s." % path.get_file()
		return out
	if page < 1 or page > pages.size():
		out.error = "%s has %d pages; there's no page %d." % [path.get_file(), pages.size(), page]
		return out
	var k := 0.0254 / PT_INCH * ratio
	var ctx := {"out": out, "pdf": pdf, "k": k}
	pdf._run(pages[page - 1], [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], ctx, 0)
	# A picture page can still carry a footer rule or two.
	if out.segment_count() < 50:
		out.error = "Page %d of %s has no linework: it is a picture, not a drawing. Bring it in as a plan instead." % [page, path.get_file()]
	return out


## How many pages a PDF has, or 0 if it can't be read.
static func page_count(path: String) -> int:
	var pdf = (load("res://addons/genesis/cad/gn_pdf.gd") as GDScript).new()
	pdf._open(path)
	return 0 if pdf.error != "" else pdf.pages().size()


# ---------------------------------------------------------------------------
# File structure
# ---------------------------------------------------------------------------

func _open(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		error = "Couldn't open %s." % path.get_file()
		return
	_b = f.get_buffer(f.get_length())
	f.close()
	if _b.size() < 8 or _b.slice(0, 5).get_string_from_ascii() != "%PDF-":
		error = "%s isn't a PDF." % path.get_file()
		return
	# The tail is binary (stream data), so look for the keyword as bytes.
	var key := "startxref".to_ascii_buffer()
	var at := -1
	for i in range(_b.size() - key.size(), maxi(0, _b.size() - 4096) - 1, -1):
		if _b[i] == key[0] and _b.slice(i, i + key.size()) == key:
			at = i
			break
	if at < 0:
		error = "%s is damaged (no cross-reference)." % path.get_file()
		return
	var off := int(_value([at + key.size()]))
	var seen := {}
	while off > 0 and not seen.has(off):
		seen[off] = true
		off = _read_xref(off)
	if _xref.is_empty():
		error = "%s's cross-reference couldn't be read." % path.get_file()


# Reads the cross-reference section at `off` (table or stream); returns the
# previous section's offset, or 0.
func _read_xref(off: int) -> int:
	var p := [_skip_ws(off)]
	if _word_at(p[0]) == "xref":
		p[0] += 4
		while true:
			p[0] = _skip_ws(p[0])
			if _word_at(p[0]) == "trailer":
				p[0] += 7
				var t: Dictionary = _value(p)
				_merge_trailer(t)
				if t.has("XRefStm"):
					_read_xref(int(t.XRefStm))
				return int(t.get("Prev", 0))
			var first := int(_value(p))
			var count := int(_value(p))
			for i in count:
				p[0] = _skip_ws(p[0])
				var line := _b.slice(p[0], p[0] + 18).get_string_from_ascii()
				p[0] += 18
				var n := first + i
				if line.length() >= 17 and line[17] == "n" and not _xref.has(n):
					_xref[n] = {"off": line.substr(0, 10).to_int()}
		return 0
	# A cross-reference stream: "n g obj << /Type /XRef ... >> stream".
	var obj = _object_at(off)
	if not (obj is Dictionary) or not obj.has("__data"):
		return 0
	_merge_trailer(obj)
	var data := _decode(obj)
	var w: Array = obj.get("W", [1, 2, 1])
	var index: Array = obj.get("Index", [0, int(obj.get("Size", 0))])
	var row := int(w[0]) + int(w[1]) + int(w[2])
	var pos := 0
	for s in range(0, index.size(), 2):
		for i in int(index[s + 1]):
			if pos + row > data.size():
				break
			var t := _field(data, pos, int(w[0]), 1)
			var f2 := _field(data, pos + int(w[0]), int(w[1]), 0)
			var f3 := _field(data, pos + int(w[0]) + int(w[1]), int(w[2]), 0)
			pos += row
			var n := int(index[s]) + i
			if _xref.has(n):
				continue
			if t == 1:
				_xref[n] = {"off": f2}
			elif t == 2:
				_xref[n] = {"stm": f2, "idx": f3}
	return int(obj.get("Prev", 0))


func _field(data: PackedByteArray, at: int, width: int, default: int) -> int:
	if width == 0:
		return default
	var v := 0
	for i in width:
		v = (v << 8) | data[at + i]
	return v


func _merge_trailer(t: Dictionary) -> void:
	for key in ["Root", "Info", "Size"]:
		if t.has(key) and not _trailer.has(key):
			_trailer[key] = t[key]


## An object by number (references resolved one level).
func obj(n: int) -> Variant:
	if _cache.has(n):
		return _cache[n]
	var e: Dictionary = _xref.get(n, {})
	var v: Variant = null
	if e.has("off"):
		v = _object_at(e.off)
	elif e.has("stm"):
		v = _from_stream(int(e.stm), n)
	_cache[n] = v
	return v


## Follows a reference, if it is one.
func res(v: Variant) -> Variant:
	var guard := 0
	while v is Vector2i and guard < 32:
		v = obj(v.x)
		guard += 1
	return v


func _object_at(off: int) -> Variant:
	var p := [off]
	_value(p)          # object number
	_value(p)          # generation
	p[0] = _skip_ws(p[0])
	if _word_at(p[0]) != "obj":
		return null
	p[0] += 3
	var v: Variant = _value(p)
	if v is Dictionary:
		var q := _skip_ws(p[0])
		if _word_at(q) == "stream":
			q += 6
			if q < _b.size() and _b[q] == 13:
				q += 1
			if q < _b.size() and _b[q] == 10:
				q += 1
			var length: int = int(res(v.get("Length", 0)))
			var end := q + length
			# A wrong /Length (it happens): fall back to finding "endstream".
			if length <= 0 or end > _b.size() or _b.slice(end, mini(end + 12, _b.size())).get_string_from_ascii().strip_edges().begins_with("endstream") == false:
				end = _find(q, "endstream")
				while end > q and (_b[end - 1] == 10 or _b[end - 1] == 13):
					end -= 1
			v["__data"] = _b.slice(q, end)
	return v


func _from_stream(stm: int, n: int) -> Variant:
	if not _stm_cache.has(stm):
		var s = obj(stm)
		if not (s is Dictionary) or not s.has("__data"):
			return null
		var data := _decode(s)
		var first := int(s.get("First", 0))
		var head := data.slice(0, first).get_string_from_ascii().split(" ", false)
		var offsets := {}
		var nums: Array = []
		for t in head:
			for part in t.split("\n", false):
				for q in part.split("\r", false):
					nums.append(q.to_int())
		for i in range(0, nums.size() - 1, 2):
			offsets[nums[i]] = first + nums[i + 1]
		_stm_cache[stm] = {"data": data, "offsets": offsets}
	var entry: Dictionary = _stm_cache[stm]
	if not entry.offsets.has(n):
		return null
	var saved := _b
	_b = entry.data
	var v: Variant = _value([int(entry.offsets[n])])
	_b = saved
	return v


## A stream's data, decompressed.
func _decode(s: Dictionary) -> PackedByteArray:
	var data: PackedByteArray = s.get("__data", PackedByteArray())
	var filters: Variant = res(s.get("Filter", null))
	var parms: Variant = res(s.get("DecodeParms", null))
	var list: Array = filters if filters is Array else ([filters] if filters != null else [])
	var plist: Array = parms if parms is Array else [parms]
	for i in list.size():
		var name := str(list[i])
		if name == "FlateDecode" or name == "Fl":
			var out := data.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
			if out.is_empty() and not data.is_empty():
				return PackedByteArray()
			data = out
			var p: Variant = res(plist[i]) if i < plist.size() else null
			if p is Dictionary and int(p.get("Predictor", 1)) >= 10:
				data = _unpredict(data, int(p.get("Columns", 1)) * int(p.get("Colors", 1)) * int(p.get("BitsPerComponent", 8)) / 8)
		else:
			# Pictures (DCT, JBIG2, CCITT) aren't drawn; nothing else is common.
			return PackedByteArray()
	return data


# PNG row filters, as used on cross-reference streams.
func _unpredict(data: PackedByteArray, cols: int) -> PackedByteArray:
	var out := PackedByteArray()
	var prev := PackedByteArray()
	prev.resize(cols)
	var i := 0
	while i + cols < data.size() + 1 and i < data.size():
		var kind := data[i]
		var row := data.slice(i + 1, i + 1 + cols)
		row.resize(cols)
		for c in cols:
			var left := row[c - 1] if c > 0 else 0
			var up := prev[c]
			var ul := prev[c - 1] if c > 0 else 0
			match kind:
				1: row[c] = (row[c] + left) & 255
				2: row[c] = (row[c] + up) & 255
				3: row[c] = (row[c] + (left + up) / 2) & 255
				4:
					var pp := left + up - ul
					var pa := absi(pp - left)
					var pb := absi(pp - up)
					var pc := absi(pp - ul)
					row[c] = (row[c] + (left if pa <= pb and pa <= pc else (up if pb <= pc else ul))) & 255
		out.append_array(row)
		prev = row
		i += cols + 1
	return out


## The document's pages, in order: each {"dict", "resources", "box"}.
func pages() -> Array:
	var out: Array = []
	var root = res(_trailer.get("Root", null))
	if not (root is Dictionary):
		return out
	_collect(res(root.get("Pages", null)), {}, out, 0)
	return out


func _collect(node: Variant, inherited: Dictionary, out: Array, depth: int) -> void:
	if not (node is Dictionary) or depth > 64:
		return
	var here := inherited.duplicate()
	for key in ["Resources", "MediaBox", "Rotate"]:
		if node.has(key):
			here[key] = node[key]
	if str(node.get("Type", "")) == "Pages" or node.has("Kids"):
		for kid in res(node.get("Kids", [])):
			_collect(res(kid), here, out, depth + 1)
	else:
		out.append({"dict": node, "resources": res(here.get("Resources", {})), "rotate": int(res(here.get("Rotate", 0)))})


# ---------------------------------------------------------------------------
# Object syntax
# ---------------------------------------------------------------------------

func _skip_ws(p: int) -> int:
	var n := _b.size()
	while p < n:
		var c := _b[p]
		if c == 32 or c == 10 or c == 13 or c == 9 or c == 12 or c == 0:
			p += 1
		elif c == 37:   # % comment
			while p < n and _b[p] != 10 and _b[p] != 13:
				p += 1
		else:
			break
	return p


func _word_at(p: int) -> String:
	var e := p
	while e < _b.size() and e - p < 12 and _is_regular(_b[e]):
		e += 1
	return _b.slice(p, e).get_string_from_ascii()


func _is_regular(c: int) -> bool:
	return not (c == 32 or c == 10 or c == 13 or c == 9 or c == 12 or c == 0 or c == 40 or c == 41 or c == 60 or c == 62 \
		or c == 91 or c == 93 or c == 123 or c == 125 or c == 47 or c == 37)


func _find(from: int, text: String) -> int:
	var needle := text.to_ascii_buffer()
	var first := needle[0]
	var i := from
	var n := _b.size() - needle.size()
	while i <= n:
		if _b[i] == first and _b.slice(i, i + needle.size()) == needle:
			return i
		i += 1
	return _b.size()


# Parses one value at p[0] (advancing it). Names are Strings, strings are
# PackedByteArrays, references Vector2i(number, generation).
func _value(p: Array) -> Variant:
	var i := _skip_ws(p[0])
	if i >= _b.size():
		p[0] = i
		return null
	var c := _b[i]
	if c == 60 and i + 1 < _b.size() and _b[i + 1] == 60:     # <<
		p[0] = i + 2
		var d := {}
		while true:
			var q := _skip_ws(p[0])
			if q >= _b.size():
				break
			if _b[q] == 62 and q + 1 < _b.size() and _b[q + 1] == 62:
				p[0] = q + 2
				break
			var key: Variant = _value(p)
			if key == null:
				break
			d[str(key)] = _value(p)
		return d
	if c == 91:     # [
		p[0] = i + 1
		var a: Array = []
		while true:
			var q := _skip_ws(p[0])
			if q >= _b.size():
				break
			if _b[q] == 93:
				p[0] = q + 1
				break
			a.append(_value(p))
		return a
	if c == 47:     # /Name
		var e := i + 1
		while e < _b.size() and _is_regular(_b[e]):
			e += 1
		p[0] = e
		return _b.slice(i + 1, e).get_string_from_ascii()
	if c == 40:     # (string)
		var depth := 1
		var e := i + 1
		while e < _b.size() and depth > 0:
			if _b[e] == 92:
				e += 1
			elif _b[e] == 40:
				depth += 1
			elif _b[e] == 41:
				depth -= 1
			e += 1
		p[0] = e
		return _b.slice(i + 1, e - 1)
	if c == 60:     # <hex>
		var e := i + 1
		while e < _b.size() and _b[e] != 62:
			e += 1
		p[0] = e + 1
		return _b.slice(i + 1, e)
	# A number, perhaps the start of "n g R", or a keyword.
	var e := i
	while e < _b.size() and _is_regular(_b[e]):
		e += 1
	var word := _b.slice(i, e).get_string_from_ascii()
	p[0] = e
	if word.is_valid_int():
		# "n g R" is a reference.
		var q := [e]
		var save: int = p[0]
		var g_start := _skip_ws(q[0])
		var g_end := g_start
		while g_end < _b.size() and _b[g_end] >= 48 and _b[g_end] <= 57:
			g_end += 1
		if g_end > g_start:
			var r := _skip_ws(g_end)
			if r < _b.size() and _b[r] == 82 and (r + 1 >= _b.size() or not _is_regular(_b[r + 1])):
				p[0] = r + 1
				return Vector2i(word.to_int(), _b.slice(g_start, g_end).get_string_from_ascii().to_int())
		p[0] = save
		return word.to_int()
	if word.is_valid_float():
		return word.to_float()
	match word:
		"true": return true
		"false": return false
		"null": return null
	return word


# ---------------------------------------------------------------------------
# Page content: the drawing operators
# ---------------------------------------------------------------------------

# Interprets a page's or form's content stream into drawing segments.
func _run(src: Dictionary, ctm: Array, ctx: Dictionary, depth: int) -> void:
	if depth > MAX_FORM_DEPTH:
		return
	var data := PackedByteArray()
	var resources: Dictionary = {}
	if src.has("dict"):
		resources = src.resources if src.resources is Dictionary else {}
		var contents: Variant = res(src.dict.get("Contents", null))
		for part in (contents if contents is Array else [contents]):
			var s: Variant = res(part)
			if s is Dictionary:
				data.append_array(_decode(s))
				data.append(10)
	else:
		resources = res(src.get("Resources", {})) if src.get("Resources", null) != null else {}
		data = _decode(src)
	var xobjects: Dictionary = {}
	if resources is Dictionary and resources.has("XObject"):
		var x: Variant = res(resources.XObject)
		if x is Dictionary:
			xobjects = x
	_interpret(data, ctm, xobjects, ctx, depth)


func _interpret(b: PackedByteArray, ctm0: Array, xobjects: Dictionary, ctx: Dictionary, depth: int) -> void:
	var out: GnDxf.Drawing = ctx.out
	var k: float = ctx.k
	var nums := PackedFloat64Array()
	var name := ""
	var ctm: Array = ctm0.duplicate()
	var width := 1.0
	var stroke := Color.BLACK
	var fill := Color.BLACK
	var stack: Array = []
	# The path being built, in page space: a list of subpaths, each a
	# PackedFloat64Array of x y pairs.
	var path: Array = []
	var cur := PackedFloat64Array()
	var n := b.size()
	var i := 0
	while i < n:
		var c := b[i]
		if c == 32 or c == 10 or c == 13 or c == 9 or c == 12 or c == 0:
			i += 1
			continue
		if (c >= 48 and c <= 57) or c == 45 or c == 43 or c == 46:
			# A number, parsed by hand (this runs millions of times).
			var neg := c == 45
			if c == 45 or c == 43:
				i += 1
			var v := 0.0
			while i < n and b[i] >= 48 and b[i] <= 57:
				v = v * 10.0 + (b[i] - 48)
				i += 1
			if i < n and b[i] == 46:
				i += 1
				var scale := 0.1
				while i < n and b[i] >= 48 and b[i] <= 57:
					v += (b[i] - 48) * scale
					scale *= 0.1
					i += 1
			nums.append(-v if neg else v)
			continue
		if c == 47:     # /Name
			var e := i + 1
			while e < n and _is_regular(b[e]):
				e += 1
			name = b.slice(i + 1, e).get_string_from_ascii()
			i = e
			continue
		if c == 40:     # (string): skipped
			var d := 1
			i += 1
			while i < n and d > 0:
				if b[i] == 92:
					i += 1
				elif b[i] == 40:
					d += 1
				elif b[i] == 41:
					d -= 1
				i += 1
			continue
		if c == 60:     # <hex> or << dict >> (inline image parameters)
			if i + 1 < n and b[i + 1] == 60:
				i += 2
				continue
			while i < n and b[i] != 62:
				i += 1
			i += 1
			continue
		if c == 62 or c == 91 or c == 93 or c == 123 or c == 125:
			i += 1
			continue
		if c == 37:
			while i < n and b[i] != 10 and b[i] != 13:
				i += 1
			continue
		# An operator.
		var e := i
		while e < n and _is_regular(b[e]):
			e += 1
		var op := b.slice(i, e).get_string_from_ascii()
		i = e
		var m := nums.size()
		match op:
			"q":
				stack.append([ctm.duplicate(), width, stroke, fill])
			"Q":
				if not stack.is_empty():
					var s: Array = stack.pop_back()
					ctm = s[0]
					width = s[1]
					stroke = s[2]
					fill = s[3]
			"cm":
				if m >= 6:
					ctm = _mul([nums[m - 6], nums[m - 5], nums[m - 4], nums[m - 3], nums[m - 2], nums[m - 1]], ctm)
			"w":
				if m >= 1:
					width = nums[m - 1]
			"G", "RG", "K", "SC", "SCN":
				var col := _colour(nums)
				if col.a > 0.0:
					stroke = col
			"g", "rg", "k", "sc", "scn":
				var col := _colour(nums)
				if col.a > 0.0:
					fill = col
			"m":
				if m >= 2:
					cur = PackedFloat64Array()
					var p := _at(ctm, nums[m - 2], nums[m - 1])
					cur.append(p.x)
					cur.append(p.y)
					path.append(cur)
			"l":
				if m >= 2 and not path.is_empty():
					var p := _at(ctm, nums[m - 2], nums[m - 1])
					cur.append(p.x)
					cur.append(p.y)
					path[path.size() - 1] = cur
			"c", "v", "y":
				var need := 6 if op == "c" else 4
				if m >= need and not path.is_empty() and cur.size() >= 2:
					var p0 := Vector2(cur[cur.size() - 2], cur[cur.size() - 1])
					var p1: Vector2
					var p2: Vector2
					var p3: Vector2
					if op == "c":
						p1 = _at(ctm, nums[m - 6], nums[m - 5])
						p2 = _at(ctm, nums[m - 4], nums[m - 3])
						p3 = _at(ctm, nums[m - 2], nums[m - 1])
					elif op == "v":
						p1 = p0
						p2 = _at(ctm, nums[m - 4], nums[m - 3])
						p3 = _at(ctm, nums[m - 2], nums[m - 1])
					else:
						p1 = _at(ctm, nums[m - 4], nums[m - 3])
						p2 = _at(ctm, nums[m - 2], nums[m - 1])
						p3 = p2
					for s in range(1, CURVE_STEPS + 1):
						var t := float(s) / CURVE_STEPS
						var q := p0.bezier_interpolate(p1, p2, p3, t)
						cur.append(q.x)
						cur.append(q.y)
					path[path.size() - 1] = cur
			"re":
				if m >= 4:
					var x := nums[m - 4]
					var y := nums[m - 3]
					var w := nums[m - 2]
					var h := nums[m - 1]
					cur = PackedFloat64Array()
					for corner in [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h), Vector2(x, y)]:
						var p := _at(ctm, corner.x, corner.y)
						cur.append(p.x)
						cur.append(p.y)
					path.append(cur)
			"h":
				if cur.size() >= 4:
					cur.append(cur[0])
					cur.append(cur[1])
					path[path.size() - 1] = cur
			"S", "s", "B", "B*", "b", "b*":
				if op == "s" or op == "b" or op == "b*":
					if cur.size() >= 4:
						cur.append(cur[0])
						cur.append(cur[1])
						path[path.size() - 1] = cur
				var pen := width * sqrt(absf(float(ctm[0]) * float(ctm[3]) - float(ctm[1]) * float(ctm[2])))
				_emit(out, path, k, "Lines %.2f pt, %s" % [maxf(pen, 0.0), _shade(stroke)], stroke)
				path = []
				cur = PackedFloat64Array()
			"f", "F", "f*":
				_emit(out, path, k, "Filled shapes, %s" % _shade(fill), fill)
				path = []
				cur = PackedFloat64Array()
			"n":
				path = []
				cur = PackedFloat64Array()
			"Do":
				if xobjects.has(name):
					var x: Variant = res(xobjects[name])
					if x is Dictionary and str(x.get("Subtype", "")) == "Form":
						var fm: Array = res(x.get("Matrix", [1, 0, 0, 1, 0, 0]))
						var fmf: Array = []
						for v in fm:
							fmf.append(float(v))
						_run(x, _mul(fmf, ctm), ctx, depth + 1)
					elif x is Dictionary:
						out.skipped["PICTURE"] = int(out.skipped.get("PICTURE", 0)) + 1
			"BI":
				# An inline picture: skip its data, up to "EI".
				var q := i
				while q + 2 < n and not (b[q] == 69 and b[q + 1] == 73 and (b[q + 2] == 32 or b[q + 2] == 10 or b[q + 2] == 13) \
						and (b[q - 1] == 32 or b[q - 1] == 10 or b[q - 1] == 13)):
					q += 1
				i = q + 2
				out.skipped["PICTURE"] = int(out.skipped.get("PICTURE", 0)) + 1
		nums.clear()


# Adds a path's subpaths as segments on a layer, in metres.
func _emit(out: GnDxf.Drawing, path: Array, k: float, layer: String, colour: Color) -> void:
	if path.is_empty():
		return
	if not out.layers.has(layer):
		out.layers[layer] = {"colour": colour, "on": true}
		out.segments[layer] = PackedFloat64Array()
		out.colours[layer] = PackedColorArray()
	var segs: PackedFloat64Array = out.segments[layer]
	var cols: PackedColorArray = out.colours[layer]
	for sp in path:
		var pts: PackedFloat64Array = sp
		for j in range(0, pts.size() - 2, 2):
			var x0 := pts[j] * k
			var y0 := pts[j + 1] * k
			var x1 := pts[j + 2] * k
			var y1 := pts[j + 3] * k
			if x0 == x1 and y0 == y1:
				continue
			segs.append_array([x0, y0, 0.0, x1, y1, 0.0])
			cols.append(colour)
			GnDxf._extend(out, x0, y0, 0.0)
			GnDxf._extend(out, x1, y1, 0.0)
	out.segments[layer] = segs
	out.colours[layer] = cols
	out.counts["LINE"] = int(out.counts.get("LINE", 0)) + 1


func _colour(nums: PackedFloat64Array) -> Color:
	match nums.size():
		1: return Color(nums[0], nums[0], nums[0])
		3: return Color(nums[0], nums[1], nums[2])
		4:
			var kk := nums[3]
			return Color((1.0 - nums[0]) * (1.0 - kk), (1.0 - nums[1]) * (1.0 - kk), (1.0 - nums[2]) * (1.0 - kk))
	return Color(0, 0, 0, 0)


func _shade(c: Color) -> String:
	if absf(c.r - c.g) < 0.02 and absf(c.g - c.b) < 0.02:
		if c.r < 0.02:
			return "black"
		if c.r > 0.98:
			return "white"
		return "grey %d%%" % roundi(c.r * 100.0)
	return "#" + c.to_html(false)


# 2D affine [a b c d e f], PDF's order: a point goes through `m` then `n`.
static func _mul(m: Array, n: Array) -> Array:
	return [m[0] * n[0] + m[1] * n[2], m[0] * n[1] + m[1] * n[3],
		m[2] * n[0] + m[3] * n[2], m[2] * n[1] + m[3] * n[3],
		m[4] * n[0] + m[5] * n[2] + n[4], m[4] * n[1] + m[5] * n[3] + n[5]]


static func _at(m: Array, x: float, y: float) -> Vector2:
	return Vector2(x * m[0] + y * m[2] + m[4], x * m[1] + y * m[3] + m[5])
