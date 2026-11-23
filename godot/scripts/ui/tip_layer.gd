class_name TipLayer
extends Control
## The tooltip of the HTML version (#tip of 08-ui.js): it shows at once under the hovered element that has a
## tip and follows the pointer (14 px right, 16 px down, flipped near the screen edges). A glass card at most
## 300 px wide with 10×12 px padding and a line-hi border; the first line of the tip is the bold title
## (13 px, fg, 3 px below it), the rest is the text (12.5 px, fg-2, line height 1.45).
## It replaces Godot's own tooltips: a control's tooltip_text is read here (split at the first "\n"), and a
## control with a tip_builder (TipPanel) gives its own content.

const MAX_W := 300.0
const PAD := Vector4(12, 10, 12, 10)

var _target: Control = null
var _text := ""
var _card: PanelContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4000
	theme = Ui.theme()


func _process(_delta: float) -> void:
	var t := _tip_target()
	var txt := ""
	if t != null:
		if t is TipPanel and (t as TipPanel).tip_builder.is_valid():
			txt = "\u0001builder"
		else:
			txt = t.get_tooltip(t.get_local_mouse_position())
	if t != _target or txt != _text:
		_target = t
		_text = txt
		_rebuild()
	if _card != null:
		_place()


func _input(e: InputEvent) -> void:
	# a click or the wheel hides the tip until the pointer reaches another element (as the HTML hides it on scroll)
	if _card != null and (e is InputEventMouseButton and e.pressed):
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_card.queue_free()
			_card = null


## the hovered control or the nearest parent that has a tip
func _tip_target() -> Control:
	var c := get_viewport().gui_get_hovered_control()
	while c != null:
		if c is TipPanel and (c as TipPanel).tip_builder.is_valid():
			return c
		if c.tooltip_text != "":
			return c
		# as Godot looks for a tooltip: up the parents until one that stops the mouse
		if c.mouse_filter == Control.MOUSE_FILTER_STOP or c.top_level:
			return null
		c = c.get_parent() as Control
	return null


func _rebuild() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	if _target == null or _text == "":
		return
	var content: Control = null
	var g := Ui.glass(Ui.GLASS_HI, Ui.LINE_HI)
	if _text.begins_with("\u0001"):
		content = (_target as TipPanel).tip_builder.call()
		if content == null:
			g.free()
			return
	else:
		content = _text_ui(_text)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(Ui.margin(content, int(PAD.x), int(PAD.y), int(PAD.z), int(PAD.w)))
	for c in content.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(g)
	_card = g
	g.reset_size()
	_place()


## T(title, text): a bold title over the text, wrapped at 300 px
func _text_ui(s: String) -> Control:
	var i := s.find("\n")
	var title := s if i < 0 else s.substr(0, i)
	var body := "" if i < 0 else s.substr(i + 1).strip_edges()
	var inner := MAX_W - PAD.x - PAD.z - 2
	var v := Ui.vbox(3)
	var tf := Ui.font("body", 600)
	var tl := _wrapped(title, 13, Ui.FG, tf, inner)
	v.add_child(tl)
	if body != "":
		var bf: Font = Ui.font("body")
		var bl := _wrapped(body, 12, Ui.FG2, bf, inner)
		bl.add_theme_constant_override("line_spacing", 3)
		v.add_child(bl)
	return v


func _wrapped(s: String, fs: int, col: Color, f: Font, inner: float) -> Label:
	var l := Ui.label(s, fs, col, f)
	var w := 0.0
	for line in s.split("\n"):
		w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	if w > inner:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = inner
	return l


func _place() -> void:
	var m := get_local_mouse_position()
	var sz := _card.get_combined_minimum_size()
	_card.size = sz
	var x := m.x + 14
	var y := m.y + 16
	if x + sz.x > size.x - 8:
		x = m.x - sz.x - 14
	if y + sz.y > size.y - 8:
		y = m.y - sz.y - 12
	_card.position = Vector2(maxf(4, x), maxf(4, y)).round()
