class_name VehicleDiagram
extends Control
## The load of a trip as a container that fills up, the same for every kind of transport: an outline with
## corrugated walls and corner fittings, filled from the left by the share of the load (fill 0…1) with the
## percentage written in it.

var fill := 0.0
var label := ""
var line_col := Ui.FG2
var fill_col := Ui.ACCENT


## t: the vehicle type (kept for the callers; every type shows the same container)
static func make(_t: String, f: float, text: String = "") -> VehicleDiagram:
	var d := VehicleDiagram.new()
	d.fill = clampf(f, 0, 1)
	d.label = text
	d.custom_minimum_size = Vector2(0, 56)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _draw() -> void:
	var h := minf(size.y - 4, 52.0)
	var w := minf(size.x - 4, h * 4.2)
	var r := Rect2((size.x - w) / 2, (size.y - h) / 2, w, h)
	# the load
	if fill > 0:
		var fr := Rect2(r.position, Vector2(r.size.x * fill, r.size.y)).grow(-3)
		if fr.size.x > 0:
			draw_rect(fr, Color(fill_col, .78))
	# the corrugated walls
	var n := int(w / 9)
	for i in range(1, n):
		var x := r.position.x + w * i / n
		draw_line(Vector2(x, r.position.y + 5), Vector2(x, r.end.y - 5), Color(line_col, .28), 1.0, true)
	# the frame and the corner fittings
	draw_rect(r, line_col, false, 2.0, true)
	for c in [r.position, Vector2(r.end.x - 6, r.position.y), Vector2(r.position.x, r.end.y - 6), r.end - Vector2(6, 6)]:
		draw_rect(Rect2(c, Vector2(6, 6)), line_col)
	# the share
	var txt := label if label != "" else "%d%%" % int(round(fill * 100))
	var f: Font = Ui.font("mono", 600)
	var fs := 14
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(r.get_center().x - tw / 2, r.get_center().y + fs * .36)
	draw_string_outline(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(Ui.BG, .85))
	draw_string(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Ui.FG)
