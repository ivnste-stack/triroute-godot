class_name ModalLayer
extends Control
## Dialogs (queueModal of the HTML version): one at a time over a dimmed map, a head with an icon, an eyebrow
## and a title, a body and the choices; the game stands still while one is open.
## spec: {icon, tone ("", "bad", "warn", "good"), eyebrow, title, body (BBCode), hint, choices: [{t, d, f: Callable, hl}],
##        close: bool (a ✕ in the head)}

signal opened
signal closed

var _queue: Array = []
var _box: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func is_open() -> bool:
	return visible


func push(spec: Dictionary) -> void:
	_queue.append(spec)
	if not visible:
		_next()


func clear() -> void:
	_queue.clear()
	_hide()


func _hide() -> void:
	if _box != null:
		_box.queue_free()
		_box = null
	if visible:
		visible = false
		closed.emit()


func _next() -> void:
	if _box != null:
		_box.queue_free()
		_box = null
	if _queue.is_empty():
		_hide()
		return
	var spec: Dictionary = _queue.pop_front()
	var was := visible
	visible = true
	if not was:
		opened.emit()
	_box = _build(spec)
	add_child(_box)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(2 / 255.0, 5 / 255.0, 9 / 255.0, .55))


func _build(spec: Dictionary) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Ui.glass()
	g.custom_minimum_size.x = spec.get("width", 560)
	center.add_child(g)
	var col := Ui.vbox(0)
	g.add_child(col)
	# head
	var tone: String = spec.get("tone", "")
	var tcol: Color = {"bad": Ui.BAD, "warn": Ui.WARN, "good": Ui.GOOD}.get(tone, Ui.ACCENT)
	var mic := PanelContainer.new()
	mic.custom_minimum_size = Vector2(44, 44)
	mic.add_theme_stylebox_override("panel", Ui.box(Color.TRANSPARENT, Color(tcol, .5) if tone != "" else Ui.LINE_HI))
	var ic := Ui.icon(spec.get("icon", "info"), 20, tcol)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mic.add_child(ic)
	var tt := Ui.vbox(6, [Ui.lbl(spec.get("eyebrow", "")), Ui.heading(spec.get("title", ""), 18)])
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Ui.hbox(14, [mic, tt])
	if spec.get("close", false):
		var x := Ui.xbtn(func(): _next())
		x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(x)
	var hp := PanelContainer.new()
	hp.add_theme_stylebox_override("panel", Ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector4(18, 16, 18, 16)))
	hp.add_child(head)
	col.add_child(hp)
	var sep := ColorRect.new()
	sep.color = Ui.LINE
	sep.custom_minimum_size.y = 1
	col.add_child(sep)
	# body and choices
	var body := Ui.vbox(10)
	if spec.get("body", "") != "":
		body.add_child(Ui.rich(spec.body, 14, Ui.FG2))
	if spec.get("hint", "") != "":
		body.add_child(Ui.hint(spec.hint, spec.get("hint_icon", "bulb")))
	if spec.has("content"):
		body.add_child(spec.content)
	for c in spec.get("choices", []):
		body.add_child(_choice(c))
	var scroll := SmoothScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = mini(int(get_viewport_rect().size.y) - 220, 640)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var m := Ui.margin(body, 18)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(m)
	col.add_child(scroll)
	# the scroll area shrinks to its content
	m.minimum_size_changed.connect(func(): scroll.custom_minimum_size.y = mini(int(m.get_combined_minimum_size().y), int(get_viewport_rect().size.y) - 220))
	scroll.custom_minimum_size.y = 0
	scroll.call_deferred("set", "custom_minimum_size", Vector2(0, mini(int(m.get_combined_minimum_size().y), int(get_viewport_rect().size.y) - 220)))
	return center


## .choice: a title and a note; highlighted (hl) like the hovered one
func _choice(c: Dictionary) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := Ui.box(ACCENT_SOFT_HL if c.get("hl") else Color(1, 1, 1, .035), Ui.ACCENT if c.get("hl") else Ui.LINE_HI, 1, Vector4(13, 11, 13, 11))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", Ui.box(Ui.ACCENT_SOFT, Ui.ACCENT, 1, Vector4(13, 11, 13, 11)))
	b.add_theme_stylebox_override("pressed", Ui.box(Ui.ACCENT_SOFT, Ui.ACCENT, 1, Vector4(13, 11, 13, 11)))
	b.disabled = c.get("disabled", false)
	var v := Ui.vbox(4, [Ui.label(c.get("t", ""), 14, Ui.FG, Ui.font("body", 600))])
	if c.get("d", "") != "":
		var d := Ui.note(c.d, Ui.FG2)
		d.add_theme_font_size_override("font_size", 12)
		v.add_child(d)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in v.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := Ui.margin(v, 13, 11)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.minimum_size_changed.connect(func(): b.custom_minimum_size.y = m.get_combined_minimum_size().y)
	b.custom_minimum_size.y = 52
	b.pressed.connect(func():
		var f: Variant = c.get("f")
		_next()
		if f is Callable and f.is_valid():
			f.call())
	return b


const ACCENT_SOFT_HL := Color(92 / 255.0, 200 / 255.0, 242 / 255.0, .1)
