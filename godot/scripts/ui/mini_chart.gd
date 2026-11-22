class_name MiniChart
extends Control
## A small line chart (chart()/drawChart() of the HTML version): four grid lines with values on the left, a
## gradient under the line, a dot on the last point; under the mouse a guide line and the value of that point.

var data: Array = []
var col := Ui.ACCENT
var zero := false
var _hi := -1
var _L := 44.0


static func make(d: Array, c: Color, z: bool = false, h: float = 120) -> MiniChart:
	var m := MiniChart.new()
	m.data = d
	m.col = c
	m.zero = z
	m.custom_minimum_size.y = h
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_exited.connect(func():
		m._hi = -1
		m.queue_redraw())
	return m


func _range() -> Vector2:
	var mn: float = data.min()
	var mx: float = data.max()
	if zero:
		mn = minf(0, mn)
	if mx - mn < 1e-9:
		mx += 1
		mn -= 1
	var pad := (mx - mn) * .12
	mx += pad
	if not zero:
		mn -= pad
	return Vector2(mn, mx)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and data.size() > 1:
		var n := data.size()
		_hi = clampi(int(round((e.position.x - _L) / (size.x - _L - 12) * (n - 1))), 0, n - 1)
		queue_redraw()


func _draw() -> void:
	if data.size() < 2:
		return
	var f := Ui.font("mono", 500)
	var r := _range()
	var mn := r.x
	var mx := r.y
	var lw := 0.0
	for k in 4:
		lw = maxf(lw, f.get_string_size(Ui.usd(mn + (mx - mn) * k / 3.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x)
	var w := size.x
	var h := size.y
	_L = ceilf(lw) + 12
	var Rr := 12.0
	var Tp := 8.0
	var B := 18.0
	var X := func(i: int) -> float: return _L + float(i) / (data.size() - 1) * (w - _L - Rr)
	var Y := func(v: float) -> float: return Tp + (1 - (v - mn) / (mx - mn)) * (h - Tp - B)
	for k in 4:
		var v := mn + (mx - mn) * k / 3.0
		var y: float = Y.call(v)
		draw_line(Vector2(_L, y), Vector2(w - Rr, y), Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .1), 1)
		var t := Ui.usd(v)
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(f, Vector2(_L - 6 - tw, y + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.MUTED)
	var pts := PackedVector2Array()
	for i in data.size():
		pts.append(Vector2(X.call(i), Y.call(data[i])))
	# the gradient under the line: a polygon with alpha .33 at the top and 0 at the bottom
	var poly := PackedVector2Array(pts)
	poly.append(Vector2(X.call(data.size() - 1), h - B))
	poly.append(Vector2(X.call(0), h - B))
	var cols := PackedColorArray()
	for p in poly:
		cols.append(Color(col, .33 * (1 - (p.y - Tp) / (h - B - Tp))))
	draw_polygon(poly, cols)
	draw_polyline(pts, col, 2, true)
	var e := _hi if _hi >= 0 else data.size() - 1
	if _hi >= 0:
		draw_line(Vector2(pts[e].x, Tp), Vector2(pts[e].x, h - B), Color(231 / 255.0, 238 / 255.0, 244 / 255.0, .35), 1)
	draw_circle(pts[e], 5.5, Color("#0b1119"))
	draw_circle(pts[e], 4.5, col)
	if _hi >= 0:
		var t := Ui.usd(data[_hi])
		var fs := Ui.font("body", 500)
		var sz := fs.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var bx := Rect2(pts[e] + Vector2(-sz.x / 2 - 7, -sz.y - 16), sz + Vector2(14, 8))
		bx.position.x = clampf(bx.position.x, 0, w - bx.size.x)
		bx.position.y = maxf(0, bx.position.y)
		draw_rect(bx, Ui.GLASS_HI)
		draw_rect(bx, Ui.LINE_HI, false, 1)
		draw_string(fs, bx.position + Vector2(7, sz.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.FG)
