class_name StartMenu
extends Control
## The main menu (#start of the HTML version): the logo and the buttons over the floating pictures of a
## logistics map (MenuBackdrop, shared with the loading screen).

signal new_game
signal settings
signal load_game
signal quit

const LOGO := preload("res://assets/img/logo_tryroute.png")


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
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(380, 90)
	# the line under the logo
	var sub := Ui.label("ГЛОБАЛЬНА ЛОГІСТИЧНА СТРАТЕГІЯ", 11, Ui.FG2, Ui.font("mono", 600, 3.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lg.add_child(Ui.margin(Ui.vbox(12, [logo, sub]), 32, 26, 32, 22))
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
