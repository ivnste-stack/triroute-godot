class_name Ui
extends RefCounted
## The look of the HTML version's interface (the CSS of legacy/src/01-head.html): colours, fonts, the Godot
## theme, small builders for its elements (glass panels, buttons, labels, icons, pills) and the number formats
## (fmtUSD, daysS, kmS, dateStr…).

# ---------- colours (:root) ----------
const BG := Color("#05090e")
const GLASS := Color(11 / 255.0, 17 / 255.0, 25 / 255.0, .66)
const GLASS_HI := Color(20 / 255.0, 29 / 255.0, 40 / 255.0, .78)
const GLASS_LO := Color(8 / 255.0, 12 / 255.0, 18 / 255.0, .5)
const LINE := Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .16)
const LINE_HI := Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .32)
const FG := Color("#e7eef4")
const FG2 := Color("#b3c2cf")
const MUTED := Color("#7d8e9e")
const ACCENT := Color("#5cc8f2")
const ACCENT_INK := Color("#04131c")
const ACCENT_SOFT := Color(92 / 255.0, 200 / 255.0, 242 / 255.0, .14)
const WARM := Color("#f0a347")
const GOOD := Color("#5bd492")
const WARN := Color("#f1c453")
const BAD := Color("#f0625f")

const F_ONEST := preload("res://assets/fonts/Onest.ttf")
const F_UNBOUNDED := preload("res://assets/fonts/Unbounded.ttf")
const F_MONO := preload("res://assets/fonts/JetBrainsMono-Medium.ttf")
const F_MONO_B := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")

static var _fonts := {}
static var _theme: Theme
static var _glass: Shader
static var blur := true
static var _glass_rects: Array = []   # weak refs to the backgrounds, to switch the blur off and on


## the blur of every glass panel on or off (off: a flat tint, no copy of the screen)
static func set_blur(on: bool) -> void:
	blur = on
	var keep := []
	for w in _glass_rects:
		var r: Variant = w.get_ref()
		if r == null:
			continue
		keep.append(w)
		_glass_style(r)
	_glass_rects = keep


static func _glass_style(bg: ColorRect) -> void:
	var m: ShaderMaterial = bg.get_meta("glass")
	bg.material = m if blur else null
	var t: Color = m.get_shader_parameter("tint")
	bg.color = Color(t.r, t.g, t.b, minf(1.0, t.a + .22))


## a variable font at a weight, optionally letter-spaced (px)
static func font(family: String, weight: int = 400, spacing: float = 0.0) -> Font:
	var key := "%s|%d|%.2f" % [family, weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var f := FontVariation.new()
	match family:
		"display":
			f.base_font = F_UNBOUNDED
		"mono":
			f.base_font = F_MONO_B if weight >= 650 else F_MONO
		_:
			f.base_font = F_ONEST
	if family != "mono":
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	if spacing:
		f.spacing_glyph = int(round(spacing))
	_fonts[key] = f
	return f


static func box(bg: Color, border: Color = Color.TRANSPARENT, bw: int = 1, pad: Vector4 = Vector4.ZERO) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	return s


## the theme of every control (body: 14px Onest, buttons .btn)
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font("body", 400)
	t.default_font_size = 14
	t.set_color("font_color", "Label", FG)
	# .btn
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, .04), LINE_HI, 1, Vector4(13, 0, 13, 0)))
	t.set_stylebox("hover", "Button", box(ACCENT_SOFT, ACCENT, 1, Vector4(13, 0, 13, 0)))
	t.set_stylebox("pressed", "Button", box(ACCENT_SOFT, ACCENT, 1, Vector4(13, 0, 13, 0)))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, .02), LINE, 1, Vector4(13, 0, 13, 0)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", font("body", 500))
	t.set_font_size("font_size", "Button", 13)
	t.set_color("font_color", "Button", FG)
	t.set_color("font_hover_color", "Button", FG)
	t.set_color("font_pressed_color", "Button", FG)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_color("icon_normal_color", "Button", FG)
	t.set_constant("h_separation", "Button", 7)
	t.set_constant("icon_max_width", "Button", 16)   # icon textures are rendered at twice their size
	# scroll bars: thin, like the original
	var sb := box(Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .25))
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .4)))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT))
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, Vector4(3, 0, 3, 0)))
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	t.set_stylebox("normal", "LineEdit", box(Color(1, 1, 1, .04), LINE_HI, 1, Vector4(10, 6, 10, 6)))
	t.set_stylebox("focus", "LineEdit", box(Color(1, 1, 1, .06), ACCENT, 1, Vector4(10, 6, 10, 6)))
	t.set_stylebox("panel", "TooltipPanel", box(Color(12 / 255.0, 19 / 255.0, 28 / 255.0, .96), LINE_HI, 1, Vector4(12, 10, 12, 10)))
	t.set_color("font_color", "TooltipLabel", FG2)
	t.set_font_size("font_size", "TooltipLabel", 12)
	_theme = t
	return t


# ---------- builders ----------
## a glass panel (.glass): the blurred map behind, a tint, a thin border
## the glass of a panel over a dialog's veil: what it blurs is darkened like the screen under the veil
static func glass_dim(p: PanelContainer, dim: float = .55) -> void:
	for c in p.get_children():
		if c is ColorRect and c.has_meta("glass"):
			(c.get_meta("glass") as ShaderMaterial).set_shader_parameter("dim", dim)
			var t: Color = (c.get_meta("glass") as ShaderMaterial).get_shader_parameter("tint")
			if not blur:
				c.color = Color(t.r, t.g, t.b, minf(1.0, t.a + .22)).lerp(Color(.0078, .0196, .0353), dim * .5)


static func glass(tint: Color = GLASS, border: Color = LINE, into: PanelContainer = null) -> PanelContainer:
	if _glass == null:
		_glass = load("res://shaders/glass.gdshader")
	var p := into if into != null else PanelContainer.new()
	var bg := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = _glass
	m.set_shader_parameter("tint", tint)
	bg.set_meta("glass", m)
	_glass_style(bg)
	_glass_rects.append(weakref(bg))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true
	p.add_child(bg)
	p.add_theme_stylebox_override("panel", box(Color.TRANSPARENT, border))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func margin(c: Control, l: int, t: int = -1, r: int = -1, b: int = -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", l if t < 0 else t)
	m.add_theme_constant_override("margin_right", l if r < 0 else r)
	m.add_theme_constant_override("margin_bottom", (l if t < 0 else t) if b < 0 else b)
	if c != null:
		m.add_child(c)
	return m


static func label(text: String, size: int = 14, col: Color = FG, f: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if f != null:
		l.add_theme_font_override("font", f)
	return l


## .lbl: 600 10px mono, letter-spacing .14em, upper case, muted
static func lbl(text: String, col: Color = MUTED) -> Label:
	return label(text.to_upper(), 10, col, font("mono", 600, 1.4))


## .note: 13px, fg-2
static func note(text: String, col: Color = FG2) -> Label:
	var l := label(text, 13, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## h3 / headings: 600 Unbounded
static func heading(text: String, size: int = 18) -> Label:
	return label(text, size, FG, font("display", 600))


static func num(text: String, size: int = 15, col: Color = FG) -> Label:
	return label(text, size, col, font("mono", 600))


static func icon(name: String, size: float = 18, col: Color = FG, stroke: float = 1.7) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.tex(name, col, size, stroke)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the icon keeps its size: a container must not stretch it (the textures are drawn at twice the size)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## .btn (kind: "", "pri", "sm", "pri sm")
static func btn(text: String, kind: String = "", ic: String = "", cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	var sm := kind.contains("sm")
	b.custom_minimum_size.y = 28 if sm else 34
	if sm:
		b.add_theme_font_size_override("font_size", 12)
		for st in ["normal", "hover", "pressed", "disabled"]:
			var s: StyleBoxFlat = theme().get_stylebox(st, "Button").duplicate()
			s.content_margin_left = 10
			s.content_margin_right = 10
			b.add_theme_stylebox_override(st, s)
	if kind.contains("pri"):
		for st in ["normal", "hover", "pressed"]:
			var s := box(ACCENT if st == "normal" else ACCENT.lightened(.12), ACCENT, 1, Vector4(10 if sm else 13, 0, 10 if sm else 13, 0))
			b.add_theme_stylebox_override(st, s)
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, ACCENT_INK)
		b.add_theme_font_override("font", font("body", 600))
	if ic != "":
		b.icon = Icons.tex(ic, ACCENT_INK if kind.contains("pri") else FG, 16, 1.8)
		b.expand_icon = false
	if cb.is_valid():
		b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # .btn: 34 / 28 px high, not the height of the row
	return b


## .xbtn: 30×30, transparent; under the pointer a thin border and the icon in fg
static func xbtn(cb: Callable) -> Button:
	var x := Button.new()
	x.set_meta("silent", true)   # closing makes no sound
	x.icon = Icons.tex("close", MUTED, 18)
	x.add_theme_constant_override("icon_max_width", 18)
	x.custom_minimum_size = Vector2(30, 30)
	x.focus_mode = Control.FOCUS_NONE
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	x.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	x.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	x.add_theme_stylebox_override("hover", box(Color.TRANSPARENT, LINE_HI))
	x.add_theme_stylebox_override("pressed", box(Color(1, 1, 1, .05), LINE_HI))
	x.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	x.mouse_entered.connect(func(): x.icon = Icons.tex("close", FG, 18))
	x.mouse_exited.connect(func(): x.icon = Icons.tex("close", MUTED, 18))
	x.pressed.connect(cb)
	return x


## the list of a dropdown (OptionButton) styled like .ddlist: no radio marks, small icons, accent on hover
static func style_popup(pm: PopupMenu) -> void:
	pm.add_theme_stylebox_override("panel", box(Color(12 / 255.0, 19 / 255.0, 28 / 255.0, .97), LINE_HI, 1, Vector4(4, 4, 4, 4)))
	pm.add_theme_stylebox_override("hover", box(ACCENT_SOFT))
	pm.add_theme_color_override("font_color", FG2)
	pm.add_theme_color_override("font_hover_color", FG)
	pm.add_theme_font_size_override("font_size", 13)
	pm.add_theme_constant_override("icon_max_width", 14)
	pm.add_theme_constant_override("v_separation", 8)
	pm.add_theme_constant_override("h_separation", 8)
	pm.add_theme_constant_override("item_start_padding", 8)
	var none := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for k in ["radio_checked", "radio_unchecked", "radio_checked_disabled", "radio_unchecked_disabled", "checked", "unchecked"]:
		pm.add_theme_icon_override(k, none)


## .pill (tone: "", "good", "warn", "bad", "acc")
static func pill(text: String, tone: String = "", ic: String = "") -> PanelContainer:
	var col: Color = {"good": GOOD, "warn": WARN, "bad": BAD, "acc": ACCENT}.get(tone, FG2)
	var brd: Color = Color(col, .45) if tone != "" else LINE_HI
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color.TRANSPARENT, brd, 1, Vector4(7, 3, 7, 3)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	if ic != "":
		h.add_child(icon(ic, 12, col))
	if text != "":
		h.add_child(label(text, 11, col, font("body", 500)))
	else:
		h.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(h)
	# .pill: as tall as its text (3 px around), never stretched by the row it sits in
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return p


static func hbox(sep: int = 8, children: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


static func vbox(sep: int = 8, children: Array = []) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	for c in children:
		v.add_child(c)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## .blk: a block inside a window
static func blk(child: Control, border: Color = LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(GLASS_LO, border, 1, Vector4(12, 12, 12, 12)))
	p.add_child(child)
	return p


## .hint: an info line with an icon
static func hint(text: String, ic: String = "info") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(92 / 255.0, 200 / 255.0, 242 / 255.0, .07), Color(92 / 255.0, 200 / 255.0, 242 / 255.0, .22), 1, Vector4(12, 10, 12, 10)))
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.text = text
	l.add_theme_font_size_override("normal_font_size", 13)
	l.add_theme_font_size_override("bold_font_size", 13)
	l.add_theme_font_override("bold_font", font("body", 600))
	l.add_theme_color_override("default_color", FG2)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(hbox(10, [icon(ic, 18, ACCENT), l]))
	return p


## rich text in the body style ([b] bold in fg)
static func rich(text: String, size: int = 14, col: Color = FG2) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.text = text
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_font_size_override("bold_font_size", size)
	l.add_theme_font_override("bold_font", font("body", 600))
	l.add_theme_color_override("default_color", col)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# ---------- formats ----------
## x.toFixed(d)
static func _f(x: float, d: int) -> String:
	return ("%." + str(d) + "f") % x


## fmtUSD: "$3.5 тис.", "−$12 тис.", "+$1.20 млн"
static func usd(v: float, sign: bool = false) -> String:
	var s := "+" if sign and v > 0 else ""
	var n := "−" if v < 0 else ""
	var a := absf(v)
	var t: String
	if a >= 1e9:
		t = _f(a / 1e9, 2) + " млрд"
	elif a >= 1e6:
		t = _f(a / 1e6, 0 if a >= 1e8 else (1 if a >= 1e7 else 2)) + " млн"
	elif a >= 1e4:
		t = _f(a / 1e3, 0) + " тис."
	elif a >= 1e3:
		t = _f(a / 1e3, 1) + " тис."
	else:
		t = _f(a, 0)
	return s + n + "$" + t


## daysS: "35 хв", "6 год", "2.4 дн."
static func days(d: float) -> String:
	if d < 1 / 24.0:
		return "%d хв" % maxi(1, int(JS.round_js(d * 1440)))
	if d < 1:
		return "%d год" % int(JS.round_js(d * 24))
	return _f(d, 1) + " дн."


## a number with spaces between thousands (toLocaleString("uk-UA"))
static func grp(n: float) -> String:
	var s := str(int(JS.round_js(absf(n))))
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("−" if n < 0 else "") + s + out


## toLocaleString("uk-UA") of any number: spaces between thousands, up to `dec` decimals, no trailing zeros
static func loc(x: float, dec: int = 3) -> String:
	var r := snappedf(absf(x), pow(10.0, -dec))
	var ip := floorf(r)
	var fr := String.num(r - ip, dec).trim_prefix("0")
	if fr == "." or fr == "0":
		fr = ""
	return ("−" if x < 0 else "") + grp(ip).trim_prefix("−") + fr.replace(".", ",")


## a number as JS prints it (String(x)): 19, 1.1, 0.25
static func js_num(x: float) -> String:
	return String.num(x)


static func km(len_: float) -> String:
	return grp(len_ * GameData.KM) + " км"


const MONTHS_FULL := ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"]
const MONTHS := ["січ", "лют", "бер", "кві", "тра", "чер", "лип", "сер", "вер", "жов", "лис", "гру"]


static func date_str(d: Dictionary) -> String:
	return "%d %s %d" % [d.d, MONTHS_FULL[d.m], d.y]


## fmtSP: population in millions → "2.07 млн" / "752 тис."
static func people(p: float) -> String:
	if p >= 1:
		return _f(p, 2) + " млн"
	if p * 1000 >= 10:
		return _f(p * 1000, 0) + " тис."
	return _f(p * 1000, 1) + " тис."


## .seg: a row of options, one selected; cb(value)
static func seg(options: Array, selected: Variant, cb: Callable) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color.TRANSPARENT, LINE_HI))
	var h := hbox(0)
	p.add_child(h)
	var btns := []
	for o in options:   # [value, text]
		var b := Button.new()
		b.text = o[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 30
		b.add_theme_font_size_override("font_size", 12)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btns.append(b)
		h.add_child(b)
	var paint := func(sel: Variant) -> void:
		for i in btns.size():
			var on: bool = options[i][0] == sel
			var st := box(ACCENT if on else Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector4(10, 0, 10, 0))
			st.border_color = LINE
			st.border_width_right = 0 if i == btns.size() - 1 else 1
			for k in ["normal", "hover", "pressed"]:
				btns[i].add_theme_stylebox_override(k, st if on or k == "normal" else box(ACCENT_SOFT, Color.TRANSPARENT, 0, Vector4(10, 0, 10, 0)))
			for k in ["font_color", "font_hover_color", "font_pressed_color"]:
				btns[i].add_theme_color_override(k, ACCENT_INK if on else FG2)
	paint.call(selected)
	for i in btns.size():
		var v: Variant = options[i][0]
		btns[i].pressed.connect(func():
			paint.call(v)
			cb.call(v))
	return p
