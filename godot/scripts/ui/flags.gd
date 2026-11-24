class_name Flags
extends RefCounted
## Country flags (genFlag in 03-core.js): the world generator rolls the pattern, colours and emblem (the
## state's "flag": {cols, type, emblem}); here they are drawn into a 240×160 image (the original's 120×80 at
## twice the size, drawn at 8× and filtered down for smooth edges) once per state and kept as a mipmapped texture.

const W := 240
const H := 160

static var _cache := {}   # flag dictionary's hash → Texture2D


static func texture(st: Dictionary) -> Texture2D:
	var f: Variant = st.get("flag")
	if not (f is Dictionary) or not (f.has("cols") or f.has("ops")):
		return null
	var key := hash(f.ops) if f.has("ops") else hash([f.cols, f.type, f.emblem])
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(_render_ops(f.ops) if f.has("ops") else _render(f))
	_cache[key] = tex
	return tex


## a flag for the UI: w×h with a thin border (plName: 18×12; the inspector's head: 30×20)
static func rect(st: Dictionary, w: float = 18, h: float = 12) -> Control:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(w, h)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture = texture(st)
	t.set_meta("st", st)
	t.draw.connect(func():
		if t.texture == null:   # no flag rolled: the country's colour
			t.draw_rect(Rect2(Vector2.ZERO, t.size), Color(st.get("color", "#7d8e9e")))
		t.draw_rect(Rect2(Vector2.ZERO, t.size), Ui.LINE_HI, false, 1))
	return t


## drawing on a canvas (the planner's tags): the flag and its border
static func draw(ci: CanvasItem, st: Dictionary, r: Rect2, border: Color = Color(1, 1, 1, .35)) -> void:
	var t := texture(st)
	if t != null:
		ci.draw_texture_rect(t, r, false)
	else:
		ci.draw_rect(r, Color(st.get("color", "#7d8e9e")))
	ci.draw_rect(r, border, false, 1)


# ====================================================================== drawing
## a polygon or a circle filled row by row (even-odd), the spans by Image.fill_rect: at 4× the size, then
## brought down with a good filter, which gives the smooth edges
static func _fill(img: Image, s: Array, c: Color, k: float) -> void:
	match s[0]:
		"r":
			var x0 := int(round(s[1] * k))
			var y0 := int(round(s[2] * k))
			img.fill_rect(Rect2i(x0, y0, int(round((s[1] + s[3]) * k)) - x0, int(round((s[2] + s[4]) * k)) - y0), c)
		"c":
			var cx: float = s[1] * k
			var cy: float = s[2] * k
			var r: float = s[3] * k
			for y in range(maxi(0, int(cy - r)), mini(img.get_height(), int(cy + r) + 1)):
				var dy := y + .5 - cy
				if absf(dy) > r:
					continue
				var w := sqrt(r * r - dy * dy)
				var x0 := int(round(cx - w))
				img.fill_rect(Rect2i(x0, y, int(round(cx + w)) - x0, 1), c)
		"p":
			var P: PackedVector2Array = s[1]
			var y0 := 1e9
			var y1 := -1e9
			for q in P:
				y0 = minf(y0, q.y * k)
				y1 = maxf(y1, q.y * k)
			for y in range(maxi(0, int(y0)), mini(img.get_height(), int(ceil(y1)) + 1)):
				var yc := y + .5
				var xs: Array = []
				for i in P.size():
					var A := P[i] * k
					var B := P[(i + 1) % P.size()] * k
					if (A.y <= yc) != (B.y <= yc):
						xs.append(A.x + (yc - A.y) / (B.y - A.y) * (B.x - A.x))
				xs.sort()
				for i in range(0, xs.size() - 1, 2):
					var x0 := int(round(xs[i]))
					img.fill_rect(Rect2i(x0, y, int(round(xs[i + 1])) - x0, 1), c)


## the Earth's flags (tools/earth_flags.py): rectangles, polygons and discs on 120×80, painted in order
static func _render_ops(ops: Array) -> Image:
	var K := 4.0 * W / 120.0
	var img := Image.create(int(120 * K), int(80 * K), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for o in ops:
		var c := Color(String(o[1]))
		match String(o[0]):
			"r":
				_fill(img, ["r", float(o[2]), float(o[3]), float(o[4]), float(o[5])], c, K)
			"c":
				_fill(img, ["c", float(o[2]), float(o[3]), float(o[4])], c, K)
			"p":
				var P := PackedVector2Array()
				var a: Array = o[2]
				for i in range(0, a.size() - 1, 2):
					P.append(Vector2(a[i], a[i + 1]))
				_fill(img, ["p", P], c, K)
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


static func _render(f: Dictionary) -> Image:
	var cols: Array = []
	for c in f.cols:
		cols.append(Color(c))
	var a: Color = cols[0]
	var b: Color = cols[1]
	var d: Color = cols[2]
	var e: Color = cols[3] if cols.size() > 3 else cols[0]
	var t := int(f.type)
	var S: Array = []   # [shape, colour] in the 120×80 units of the original, painted in order
	var R := func(x: float, y: float, w: float, h: float, c: Color) -> void: S.append([["r", x, y, w, h], c])
	match t:
		0:
			R.call(0, 0, 120, 27, a); R.call(0, 27, 120, 26, b); R.call(0, 53, 120, 27, d)
		1:
			R.call(0, 0, 40, 80, a); R.call(40, 0, 40, 80, b); R.call(80, 0, 40, 80, d)
		2:
			R.call(0, 0, 120, 40, a); R.call(0, 40, 120, 40, b)
		3:
			R.call(0, 0, 120, 80, a); R.call(30, 0, 14, 80, b); R.call(0, 33, 120, 14, b)
		4:
			for i in 7:
				R.call(0, i * 80 / 7.0, 120, 80 / 7.0 + 1, b if i % 2 else a)
			R.call(0, 0, 52, 46, d)
		5:
			R.call(0, 0, 120, 80, a)
			S.append([["p", PackedVector2Array([Vector2(0, 0), Vector2(120, 0), Vector2(0, 80)])], b])
			var n := Vector2(80, 120).normalized() * 5   # the 10-wide stroke from (120, 0) to (0, 80)
			S.append([["p", PackedVector2Array([Vector2(120, 0) + n, Vector2(0, 80) + n, Vector2(0, 80) - n, Vector2(120, 0) - n])], d])
		6:
			R.call(0, 0, 120, 27, a); R.call(0, 27, 120, 26, b); R.call(0, 53, 120, 27, a)
			S.append([["p", PackedVector2Array([Vector2(0, 0), Vector2(50, 40), Vector2(0, 80)])], d])
		7:
			R.call(0, 0, 120, 80, a)
			S.append([["c", 60.0, 40.0, 22.0], b])
		_:
			R.call(0, 0, 120, 80, a); R.call(0, 58, 120, 22, b); R.call(0, 52, 120, 6, d)
	var k := int(f.get("emblem", -1))
	if k >= 0:
		var ex := 26.0 if t == 4 else 18.0 if t == 6 else 37.0 if t == 3 else 60.0
		var ey := 23.0 if t == 4 else 40.0
		var ec := a if t == 7 else e
		if k == 0:
			var pts := PackedVector2Array()
			for i in 10:
				var rr := 5.0 if i % 2 else 12.0
				var an := i * PI / 5 - PI / 2
				pts.append(Vector2(ex + cos(an) * rr, ey + sin(an) * rr))
			S.append([["p", pts], ec])
		elif k == 1:
			S.append([["c", ex, ey, 9.0], ec])
			S.append([["c", ex + 4, ey - 2, 8.0], b if t == 7 else a])
		else:
			S.append([["p", PackedVector2Array([Vector2(ex, ey - 11), Vector2(ex + 10, ey), Vector2(ex, ey + 11), Vector2(ex - 10, ey)])], ec])
	var K := 4.0 * W / 120.0
	var img := Image.create(int(120 * K), int(80 * K), false, Image.FORMAT_RGBA8)
	img.fill(a)
	for sh in S:
		_fill(img, sh[0], sh[1], K)
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img
