class_name CompassButton
extends Button
## A round glass button that shows where north is while the camera is turned (Q / E); a click turns the
## camera back to the standard view. Hidden while the camera looks north.

var camera: MapCamera


func _ready() -> void:
	custom_minimum_size = Vector2(44, 44)
	size = custom_minimum_size
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Стандартний вигляд\nПовернути камеру північчю догори. Q / E — повернути камеру."
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(k, StyleBoxEmpty.new())
	visible = false
	modulate.a = 0
	pressed.connect(func(): if camera != null: camera.reset_turn())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _process(_delta: float) -> void:
	if camera == null:
		return
	var turned := absf(wrapf(camera.yaw, -PI, PI)) > .01 or absf(wrapf(camera.tyaw, -PI, PI)) > .01
	if turned and not visible:
		visible = true
	var a := move_toward(modulate.a, 1.0 if turned else 0.0, _delta * 5)
	if a != modulate.a:
		modulate.a = a
	if a <= 0 and visible:
		visible = false
	if visible:
		queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var c := size / 2
	var r := size.x / 2 - 1
	var hov := is_hovered()
	draw_circle(c, r, Color(11 / 255.0, 17 / 255.0, 25 / 255.0, .82), true, -1.0, true)
	draw_arc(c, r, 0, TAU, 48, Ui.ACCENT if hov else Ui.LINE_HI, 1.0, true)
	# the needle: north (red) points where the board's north is on the screen
	var a := camera.yaw
	var dir := Vector2(sin(a), -cos(a))
	var side := Vector2(-dir.y, dir.x)
	var L := r - 9
	draw_colored_polygon(PackedVector2Array([c + dir * L, c + side * 4.5, c - side * 4.5]), Color("#f0625f"))
	draw_colored_polygon(PackedVector2Array([c - dir * L, c + side * 4.5, c - side * 4.5]), Ui.FG2)
	draw_circle(c, 2, Color("#06121b"), true, -1.0, true)
