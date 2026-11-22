class_name WindowPanel
extends PanelContainer
## A window of the company (#win of the HTML version): to the right of the rail, a head with an accent icon,
## an eyebrow (the company and the date) and a title, a close button and a scrolling body.

signal close_requested

var body: VBoxContainer
var scroll: ScrollContainer
var _eyebrow: Label
var _title: Label
var _icon: TextureRect


func _init() -> void:
	var g := Ui.glass()
	# the glass panel is the window itself
	for c in g.get_children():
		g.remove_child(c)
		add_child(c)
	add_theme_stylebox_override("panel", g.get_theme_stylebox("panel"))
	g.free()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := Ui.vbox(0)
	add_child(col)
	var head := Ui.hbox(0)
	var ic := PanelContainer.new()
	ic.custom_minimum_size = Vector2(54, 0)
	ic.add_theme_stylebox_override("panel", Ui.box(Ui.ACCENT))
	_icon = Ui.icon("box", 22, Ui.ACCENT_INK)
	ic.add_child(_icon)
	head.add_child(ic)
	_eyebrow = Ui.lbl("")
	_title = Ui.heading("", 18)
	var tt := Ui.vbox(6, [_eyebrow, _title])
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tm := Ui.margin(tt, 16, 14)
	tm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tm)
	var x := Button.new()
	x.flat = true
	x.icon = Icons.tex("close", Ui.MUTED, 18)
	x.add_theme_constant_override("icon_max_width", 18)
	x.focus_mode = Control.FOCUS_NONE
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.pressed.connect(func(): close_requested.emit())
	head.add_child(x)
	head.add_child(Ui.margin(null, 5))
	col.add_child(head)
	var sep := ColorRect.new()
	sep.color = Ui.LINE
	sep.custom_minimum_size.y = 1
	col.add_child(sep)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	body = Ui.vbox(12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := Ui.margin(body, 16)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(m)


func set_head(icon: String, eyebrow: String, title: String) -> void:
	_icon.texture = Icons.tex(icon, Ui.ACCENT_INK, 22)
	_eyebrow.text = eyebrow.to_upper()
	_title.text = title


func clear_body() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
