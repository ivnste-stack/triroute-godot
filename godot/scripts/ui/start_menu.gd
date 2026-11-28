class_name StartMenu
extends Control
## The main menu (#start of the HTML version): the logo and the buttons over the floating pictures of a
## logistics map (MenuBackdrop, shared with the loading screen).

signal new_game
signal settings
signal load_game
signal quit

const GLEAM := preload("res://shaders/menu_gleam.gdshader")
const GLEAM_EVERY := 4.5   # seconds between two gleams over the name
const GLEAM_TIME := 1.1    # how long one takes to cross it
static var gleam_at := -1.0   # test: the gleam held at this part of its way (0..1)


var _name: RichTextLabel
var _gleam_t := 0.0
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
	# the name in the game's display font, TRY white and ROUTE in the accent, a gleam running over it now and then
	var logo := RichTextLabel.new()
	logo.bbcode_enabled = true
	logo.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	logo.text = "[center]TRY[color=#%s]ROUTE[/color][/center]" % Ui.ACCENT.to_html(false)
	logo.fit_content = true
	logo.autowrap_mode = TextServer.AUTOWRAP_OFF
	logo.scroll_active = false
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_theme_font_override("normal_font", Ui.font("display", 800))
	logo.add_theme_font_size_override("normal_font_size", 50)
	logo.add_theme_color_override("default_color", Color.WHITE)
	logo.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var mat := ShaderMaterial.new()
	mat.shader = GLEAM
	logo.material = mat
	_name = logo
	# the line under the logo
	var sub := Ui.label("ГЛОБАЛЬНА ЛОГІСТИЧНА СТРАТЕГІЯ", 11, Ui.FG2, Ui.font("mono", 600, 3.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lg.add_child(Ui.margin(Ui.vbox(0, [logo, sub]), 32, 24, 32, 22))
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


## the gleam: every few seconds a band of light crosses the name, left to right, easing out
func _process(delta: float) -> void:
	if _name == null or not is_visible_in_tree():
		return
	_gleam_t += delta
	var p := gleam_at if gleam_at >= 0 else fmod(_gleam_t, GLEAM_EVERY) / GLEAM_TIME
	var w := _name.size.x
	var band := -10000.0
	if p < 1.0:
		var e := 1.0 - pow(1.0 - p, 2.0)
		band = lerpf(-w * .25, w * 1.15, e)
	(_name.material as ShaderMaterial).set_shader_parameter("band", band)
