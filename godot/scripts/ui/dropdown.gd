class_name Dropdown
extends Button
## The dropdown of the HTML version (dd() / openDD() of 08-ui.js and .dd, .ddlist of its CSS): a button with an
## icon, the value and a small chevron; a click opens a glass list under it (at least 200 px wide, items of
## 8×10 px padding, the chosen one and the one under the pointer on the accent tint, the chosen one with a 2 px
## accent bar on the left). A click outside closes it.

signal chosen(value: Variant)

## where the lists open: a full-screen layer above the interface (set by main)
static var layer: Control

var options: Array = []       # [[value, label, icon]]
var value: Variant
var placeholder := ""         # shown (with a plus) while no option is the value: a list of actions, not a choice
var _lbl: Label
var _ic: TextureRect
var _list: Control = null


static func make(opts: Array, sel: Variant, cb: Callable, h: float = 34) -> Dropdown:
	var d := Dropdown.new()
	d.options = opts
	d.value = sel
	d.custom_minimum_size = Vector2(160, h)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.chosen.connect(cb)
	return d


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("normal", Ui.box(Color(1, 1, 1, .04), Ui.LINE_HI))
	add_theme_stylebox_override("disabled", Ui.box(Color(1, 1, 1, .04), Ui.LINE_HI))
	add_theme_stylebox_override("hover", Ui.box(Color(1, 1, 1, .04), Ui.ACCENT))
	add_theme_stylebox_override("pressed", Ui.box(Color(1, 1, 1, .04), Ui.ACCENT))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var h := Ui.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -10
	_ic = Ui.icon("spark", 16, Ui.FG)
	_lbl = Ui.label("", 13, Ui.FG, Ui.font("body", 500))
	_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl.clip_text = true
	_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_ic)
	h.add_child(_lbl)
	h.add_child(Ui.icon("chev", 14, Ui.MUTED))
	for c in h.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	# as wide as the longest option (the HTML button grows with its value; this one does not jump)
	var f: Font = _lbl.get_theme_font("font")
	var w := 0.0
	for o in options:
		w = maxf(w, f.get_string_size(String(o[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	custom_minimum_size.x = maxf(custom_minimum_size.x, ceilf(w) + 20 + 24 + 22 + 2)
	_show_value()
	pressed.connect(_toggle)
	tree_exiting.connect(close)


func _show_value() -> void:
	if placeholder != "" and not options.any(func(x): return x[0] == value):
		_lbl.text = placeholder
		_ic.visible = true
		_ic.texture = Icons.tex("plus", Ui.FG, 16)
		return
	var o: Array = options[0] if options.size() else [null, "", ""]
	for x in options:
		if x[0] == value:
			o = x
	_lbl.text = o[1]
	_ic.visible = o.size() > 2 and o[2] != ""
	if _ic.visible:
		_ic.texture = Icons.tex(o[2], Ui.FG, 16)


func _toggle() -> void:
	if _list != null:
		close()
	else:
		_open()


func close() -> void:
	if _list != null and is_instance_valid(_list):
		_list.queue_free()
	_list = null


func _open() -> void:
	if layer == null:
		return
	var r := get_global_rect()
	# a full-screen catcher: a click outside the list closes it
	var catcher := Control.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	layer.add_child(catcher)
	_list = catcher
	var g := Ui.glass(Ui.GLASS_HI, Ui.LINE_HI)
	var a: Node = get_parent()
	while a != null:   # in a dialog: the list lies over its veil too
		if a is ModalLayer:
			Ui.glass_dim(g)
			break
		a = a.get_parent()
	g.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := Ui.vbox(0)
	g.add_child(Ui.margin(v, 4))
	for x in options:
		v.add_child(_item(x))
	catcher.add_child(g)
	var w := maxf(r.size.x, 200)
	g.custom_minimum_size.x = w
	g.reset_size()
	var hgt := minf(300, g.get_combined_minimum_size().y)
	var top := r.end.y + 4
	if top + hgt > layer.size.y - 10:
		top = r.position.y - hgt - 4
	g.position = Vector2(r.position.x, top)


## .ddlist div: icon and label; hover and the chosen one on the accent tint, the chosen one with a bar
func _item(x: Array) -> Control:
	var on: bool = x[0] == value
	var p := PanelContainer.new()
	p.custom_minimum_size.y = 34
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var idle := Ui.box(Ui.ACCENT_SOFT if on else Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector4(10, 8, 10, 8))
	var hov := Ui.box(Ui.ACCENT_SOFT, Color.TRANSPARENT, 0, Vector4(10, 8, 10, 8))
	p.add_theme_stylebox_override("panel", idle)
	var h := Ui.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Ui.FG if on else Ui.FG2
	var ic: TextureRect = null
	if x.size() > 2 and x[2] != "":
		ic = Ui.icon(x[2], 16, col)
		h.add_child(ic)
	var l := Ui.label(x[1], 13, col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	p.add_child(h)
	if on:   # box-shadow: inset 2px 0 0 var(--accent)
		p.draw.connect(func(): p.draw_rect(Rect2(0, 0, 2, p.size.y), Ui.ACCENT))
	p.mouse_entered.connect(func():
		p.add_theme_stylebox_override("panel", hov)
		l.add_theme_color_override("font_color", Ui.FG)
		if ic != null:
			ic.texture = Icons.tex(x[2], Ui.FG, 16))
	p.mouse_exited.connect(func():
		p.add_theme_stylebox_override("panel", idle)
		l.add_theme_color_override("font_color", col)
		if ic != null:
			ic.texture = Icons.tex(x[2], col, 16))
	var v: Variant = x[0]
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			value = v
			_show_value()
			close()
			chosen.emit(v))
	return p
