class_name MeterFill
extends Control
## The filled part of a .meter bar. While a trip is loaded or unloaded (.meter i.hand of the HTML version):
## diagonal stripes at −45°, 5 px of the colour and 5 px of it faded, running to the right at 25 px a second,
## every bar in step.

var color := Ui.ACCENT:
	set(v):
		if v != color:
			color = v
			queue_redraw()
var hand := false:
	set(v):
		if v != hand:
			hand = v
			set_process(v)
			queue_redraw()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(hand)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if not hand:
		draw_rect(r, color)
		return
	draw_rect(r, Color(color, .32))
	const P := 14.14   # the period across the bar (10 px along the stripes' normal)
	const W := 7.07    # the width of a coloured stripe across the bar (5 px along the normal)
	var h := size.y
	var off := fmod(Time.get_ticks_msec() / 1000.0 * 25.0, P)
	var x := off - P - h
	while x < size.x + h:
		# a stripe leaning like "/": its bottom edge to the left of its top edge
		draw_colored_polygon(PackedVector2Array([Vector2(x, h), Vector2(x + W, h), Vector2(x + W + h, 0), Vector2(x + h, 0)]), color)
		x += P
