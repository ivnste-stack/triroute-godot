class_name Toasts
extends VBoxContainer
## Short messages at the top right (#toasts / toast() of the HTML version): a glass card with a coloured left
## edge, an icon, a title and a line of text; it fades away after a few seconds.

const LIFE := 5.0


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 320
	anchor_left = 1
	anchor_right = 1
	offset_left = -334
	offset_right = -14
	offset_top = 84


func push(tone: String, title: String, text: String = "") -> void:
	var g := Ui.glass()
	var col: Color = {"bad": Ui.BAD, "good": Ui.GOOD, "warn": Ui.WARN}.get(tone, Ui.ACCENT)
	var sb := Ui.box(Color.TRANSPARENT, Ui.LINE, 1, Vector4(12, 10, 12, 10))
	sb.border_color = Ui.LINE
	sb.border_width_left = 3
	sb.content_margin_left = 12
	g.add_theme_stylebox_override("panel", sb)
	# the coloured left edge (border-left: 3px), drawn by the panel under its content
	g.draw.connect(func(): g.draw_rect(Rect2(0, 0, 3, g.size.y), col))
	var ic := Ui.icon({"bad": "alert", "good": "check"}.get(tone, "info"), 16, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# .toast b: the title in the colour of the tone; span: 12 px in fg-2 with the browser's line height
	var tt := Ui.vbox(3, [Ui.label(title, 13, col if tone != "" else Ui.FG, Ui.font("body", 600))])
	if text != "":
		var d := Ui.label(text, 12, Ui.FG2)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_constant_override("line_spacing", 4)
		tt.add_child(d)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(Ui.hbox(10, [ic, tt]))
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	g.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: g.queue_free())
	add_child(g)
	move_child(g, 0)   # the newest on top
	while get_child_count() > 4:
		get_child(get_child_count() - 1).free()
	g.modulate.a = 0
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 1.0, .25)
	tw.tween_interval(LIFE)
	tw.tween_property(g, "modulate:a", 0.0, .4)
	tw.tween_callback(g.queue_free)
