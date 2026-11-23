class_name StartMenu
extends Control
## The main menu (#start of the HTML version): the picture of a logistics map behind, the logo, the buttons.

signal new_game
signal settings
signal load_game
signal quit

## the backgrounds: the logistics layer of a world, shot from a few places and turns; they float slowly and
## take turns, one fading into the next
const BGS := ["res://assets/img/menu_bg_1.webp", "res://assets/img/menu_bg_2.webp", "res://assets/img/menu_bg_3.webp", "res://assets/img/menu_bg_4.webp"]
const SHOW := 16.0    # seconds a picture stays
const FADE := 3.0     # seconds of the cross-fade
const LOGO := preload("res://assets/img/logo.webp")


var _bgs: Array = []
var _t := 0.0


## the backgrounds float: each drifts and grows a little over its time on screen (a slow pan and zoom),
## the next one fades in over the last seconds
func _process(delta: float) -> void:
	if not visible or _bgs.is_empty():
		return
	_t += delta
	var n := _bgs.size()
	var per := SHOW
	var cur := int(_t / per) % n
	var f := fmod(_t, per) / per
	for i in n:
		var bg: ColorRect = _bgs[i]
		var on := i == cur
		var nxt := i == (cur + 1) % n and n > 1
		var fade_in := clampf((fmod(_t, per) - (per - FADE)) / FADE, 0, 1)
		fade_in = fade_in * fade_in * (3 - 2 * fade_in)
		var a := 1.0 if on else (fade_in if nxt else 0.0)
		bg.visible = a > 0
		bg.modulate.a = a
		if not bg.visible:
			continue
		# the time of this picture on screen: the next one starts its drift while fading in
		var lt := f if on else (fmod(_t, per) - per) / per
		var u := lt + FADE / per   # 0 … 1 + FADE / per over the life of the picture
		var dir := Vector2(cos(i * 2.1 + .6), sin(i * 2.1 + .6))
		var m: ShaderMaterial = bg.material
		m.set_shader_parameter("rect_size", size)
		m.set_shader_parameter("zoom", 1.06 + .05 * u)
		m.set_shader_parameter("pan", dir * .018 * (u - .55))
	# the one fading in lies above the current one
	var top: ColorRect = _bgs[(cur + 1) % n]
	if n > 1 and top.get_index() < _bgs[cur].get_index():
		move_child(top, _bgs[cur].get_index())


var _load_btn: Button
var _load_box: Control


## #sLoad: no saves, nothing to load (checked each time the menu shows)
func _refresh_load() -> void:
	if _load_btn == null or not visible:
		return
	var has := SaveSystem.any()
	_load_btn.disabled = not has
	_load_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if has else Control.CURSOR_ARROW
	_load_box.modulate.a = 1.0 if has else .45


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.theme()
	# #bgSnap: the pictures blurred by a shader (filter: blur(6px)), darker than the game so the buttons stand
	# out on the light land; mipmapped 4K pictures: sharp on large screens, smooth when they drift
	var paths: Array = BGS.filter(func(x): return ResourceLoader.exists(x))
	if paths.is_empty():
		paths = ["res://assets/img/menu_bg.webp"]
	var sh: Shader = load("res://shaders/menu_bg.gdshader")
	for path in paths:
		var tex: Texture2D = load(path)
		var bg := ColorRect.new()
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("pic", tex)
		m.set_shader_parameter("pic_size", Vector2(tex.get_width(), tex.get_height()))
		m.set_shader_parameter("shade", Vector3(.7, .72, .76))
		bg.material = m
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.modulate.a = 0
		add_child(bg)
		_bgs.append(bg)
	if _bgs.size():
		_bgs[0].modulate.a = 1
	# #start: linear-gradient(90deg, rgba(3,6,10,.5), rgba(3,6,10,.12) 45%, rgba(3,6,10,.05))
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0, .45, 1])
	gr.colors = PackedColorArray([Color(3 / 255.0, 6 / 255.0, 10 / 255.0, .5), Color(3 / 255.0, 6 / 255.0, 10 / 255.0, .12), Color(3 / 255.0, 6 / 255.0, 10 / 255.0, .05)])
	var gt := GradientTexture2D.new()
	gt.gradient = gr
	gt.width = 256
	gt.height = 4
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# the glass of the logo and the buttons blurs this
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(bb)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := Ui.vbox(10)
	col.custom_minimum_size.x = 420
	center.add_child(col)
	var lg := Ui.glass(Ui.GLASS, Ui.LINE_HI)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(400, 108)
	lg.add_child(Ui.margin(logo, 24, 24, 24, 22))
	col.add_child(lg)
	for b in [["Створити гру", "pri", func(): new_game.emit()], ["Завантажити гру", "", func(): load_game.emit()], ["Налаштування", "", func(): settings.emit()], ["Вихід", "", func(): quit.emit()]]:
		var bt := Ui.btn(b[0], b[1], "", b[2])
		bt.custom_minimum_size.y = 46
		bt.add_theme_font_override("font", Ui.font("body", 600))
		bt.add_theme_font_size_override("font_size", 14)
		if b[0] == "Завантажити гру":
			_load_btn = bt
		if b[1] == "":
			# .snav: glass under a transparent button
			var g := Ui.glass(Ui.GLASS, Ui.LINE_HI)
			for st in ["normal", "disabled"]:
				bt.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			bt.add_theme_stylebox_override("hover", Ui.box(Ui.ACCENT_SOFT, Ui.BAD if b[0] == "Вихід" else Ui.ACCENT))
			g.add_child(bt)
			col.add_child(g)
			if bt == _load_btn:
				_load_box = g
		else:
			col.add_child(bt)
	visibility_changed.connect(_refresh_load)
	_refresh_load()
