class_name VehicleDiagram
extends Control
## A schematic vehicle in the style of the line icons: outlines only, no detail. The cargo hold fills from the
## front by the share of the load (fill 0…1), with the percentage written in it. Kinds: van, truck, tanker,
## rtrain (a road train with a trailer), train, ship, plane. Drawn on a 200×70 canvas scaled to the control.

const W := 200.0
const H := 70.0

var kind := "truck"
var fill := 0.0
var label := ""
var line_col := Ui.FG2
var fill_col := Ui.ACCENT


## the kind of drawing for a vehicle type (GameData.VT)
static func kind_of(t: String) -> String:
	var T: Dictionary = GameData.VT.get(t, {})
	match String(T.get("mode", "road")):
		"rail":
			return "train"
		"sea":
			return "ship"
		"air":
			return "plane"
	if t == "van":
		return "van"
	if t == "rtrain":
		return "rtrain"
	if t == "tanker":
		return "tanker"
	return "truck"


static func make(t: String, f: float, text: String = "") -> VehicleDiagram:
	var d := VehicleDiagram.new()
	d.kind = kind_of(t)
	d.fill = clampf(f, 0, 1)
	d.label = text
	d.custom_minimum_size = Vector2(0, 74)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func set_fill(f: float) -> void:
	f = clampf(f, 0, 1)
	if absf(f - fill) > .001:
		fill = f
		queue_redraw()


# ---------------------------------------------------------------- drawing
var _k := 1.0
var _o := Vector2.ZERO


func _p(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _k


func _line(pts: Array, closed := false) -> void:
	var a := PackedVector2Array()
	for q in pts:
		a.append(_p(q[0], q[1]))
	if closed:
		a.append(a[0])
	draw_polyline(a, line_col, 1.6, true)


func _wheel(x: float, y: float, r := 6.5) -> void:
	draw_circle(_p(x, y), r * _k, Ui.BG, true, -1, true)
	draw_arc(_p(x, y), r * _k, 0, TAU, 24, line_col, 1.6, true)
	draw_circle(_p(x, y), 1.6 * _k, line_col, true, -1, true)


## a cargo hold: the rectangle, filled from its front (right) end by share f; rounded for a tank
func _hold(r: Rect2, f: float, round_ := 0.0) -> void:
	var rr := Rect2(_p(r.position.x, r.position.y), r.size * _k)
	if f > 0:
		var fr := Rect2(rr.end.x - rr.size.x * f, rr.position.y, rr.size.x * f, rr.size.y).grow(-2.5)
		if fr.size.x > 0:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(fill_col, .78)
			sb.set_corner_radius_all(int(maxf(0, round_ * _k - 2)))
			draw_style_box(sb, fr)
	var ob := StyleBoxFlat.new()
	ob.draw_center = false
	ob.border_color = line_col
	ob.set_border_width_all(2)
	ob.set_corner_radius_all(int(round_ * _k))
	ob.anti_aliasing = true
	draw_style_box(ob, rr)


## several holds filled one after another from the front (the last in the list is the front one)
func _holds(rs: Array, f: float, round_ := 0.0) -> Rect2:
	var total := 0.0
	for r in rs:
		total += r.size.x
	var left := f * total
	for i in range(rs.size() - 1, -1, -1):
		var r: Rect2 = rs[i]
		var take := clampf(left, 0, r.size.x)
		left -= take
		_hold(r, take / r.size.x, round_)
	var u := Rect2(rs[0].position, Vector2.ZERO)
	for r in rs:
		u = u.merge(r)
	return u


func _cab(x0: float) -> void:   # a truck's cab facing right, from x0
	_line([[x0, 58], [x0, 20], [x0 + 22, 20], [x0 + 38, 38], [x0 + 38, 58]])
	_line([[x0 + 6, 25], [x0 + 20, 25], [x0 + 30, 37], [x0 + 6, 37]], true)   # the window


func _draw() -> void:
	_k = minf(size.x / W, size.y / H)
	_o = Vector2((size.x - W * _k) / 2, (size.y - H * _k) / 2)
	var box := Rect2()
	match kind:
		"van":
			box = _holds([Rect2(18, 18, 112, 40)], fill, 6)
			_line([[130, 58], [130, 22], [150, 22], [174, 40], [174, 58]])
			_line([[136, 27], [150, 27], [164, 39], [136, 39]], true)
			_line([[12, 58], [180, 58]])
			for x in [42, 152]:
				_wheel(x, 60)
		"tanker":
			box = _holds([Rect2(10, 16, 132, 38)], fill, 19)
			_cab(148)
			_line([[8, 58], [188, 58]])
			for x in [34, 60, 168]:
				_wheel(x, 61)
		"rtrain":
			box = _holds([Rect2(6, 12, 70, 44), Rect2(84, 12, 60, 44)], fill)
			_line([[76, 50], [84, 50]])   # the coupling
			_cab(150)
			_line([[4, 58], [190, 58]])
			for x in [20, 44, 98, 122, 170]:
				_wheel(x, 61)
		"train":
			box = _holds([Rect2(4, 18, 44, 34), Rect2(52, 18, 44, 34), Rect2(100, 18, 44, 34)], fill, 3)
			_line([[148, 52], [148, 20], [172, 20], [192, 34], [192, 52], [148, 52]])   # the locomotive
			_line([[156, 25], [170, 25], [178, 33], [156, 33]], true)
			_line([[2, 58], [198, 58]])
			for x in [14, 38, 62, 86, 110, 134, 160, 182]:
				_wheel(x, 55, 4.5)
		"ship":
			box = _holds([Rect2(34, 14, 118, 32)], fill, 2)
			_line([[6, 46], [190, 46], [174, 64], [22, 64]], true)   # the hull
			_line([[156, 46], [156, 22], [176, 22], [176, 46]])      # the bridge
			_line([[160, 28], [172, 28]])
			_line([[0, 66], [200, 66]])
		"plane":
			box = _holds([Rect2(40, 24, 112, 22)], fill, 10)
			_line([[24, 22], [160, 22], [186, 30], [192, 36], [186, 42], [160, 48], [24, 48], [14, 40], [14, 14], [22, 14]], true)
			_line([[86, 48], [70, 66], [92, 66], [112, 48]])   # the wing
			_line([[18, 22], [10, 6], [24, 6], [40, 22]])      # the tail
		_:   # truck
			box = _holds([Rect2(8, 12, 136, 44)], fill)
			_cab(150)
			_line([[6, 58], [190, 58]])
			for x in [32, 56, 170]:
				_wheel(x, 61)
	# the share in the hold
	var txt := label if label != "" else "%d%%" % int(round(fill * 100))
	var f: Font = Ui.font("mono", 600)
	var fs := int(clampf(13 * _k, 10, 15))
	var c := _p(box.get_center().x, box.get_center().y)
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(c.x - tw / 2, c.y + fs * .36)
	draw_string_outline(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(Ui.BG, .85))
	draw_string(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Ui.FG)
