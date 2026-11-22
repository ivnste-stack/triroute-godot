class_name StartMenu
extends Control
## The main menu (#start of the HTML version): the picture of a logistics map behind, the logo, the buttons.

signal new_game
signal settings
signal load_game
signal quit

const BG := preload("res://assets/img/menu_bg.webp")
const LOGO := preload("res://assets/img/logo.webp")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.theme()
	# #bgSnap: the picture blurred (filter: blur(6px) brightness(.9)): scaled down and stretched back
	var img: Image = BG.get_image()
	img.resize(img.get_width() / 6, img.get_height() / 6, Image.INTERPOLATE_LANCZOS)
	var bg := TextureRect.new()
	bg.texture = ImageTexture.create_from_image(img)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.modulate = Color(.9, .9, .9)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
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
		if not b[2].is_valid():
			bt.disabled = true
			bt.tooltip_text = "Збереження з'являться в наступних частинах переносу"
		if b[1] == "":
			# .snav: glass under a transparent button
			var g := Ui.glass(Ui.GLASS, Ui.LINE_HI)
			for st in ["normal", "disabled"]:
				bt.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			bt.add_theme_stylebox_override("hover", Ui.box(Ui.ACCENT_SOFT, Ui.BAD if b[0] == "Вихід" else Ui.ACCENT))
			g.add_child(bt)
			col.add_child(g)
		else:
			col.add_child(bt)
