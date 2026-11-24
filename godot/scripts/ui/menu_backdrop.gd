class_name MenuBackdrop
extends Control
## The background of the main menu and of the loading screen: pictures of the logistics layer of a world,
## blurred by a shader, that float slowly and take turns, one fading into the next. One node for both
## screens, so the picture goes on without a jump from the menu to the loading.

## the backgrounds: the logistics layer of a world, shot from a few places and turns; they float slowly and
## take turns, one fading into the next
const BGS := ["res://assets/img/menu_bg_1.webp", "res://assets/img/menu_bg_2.webp", "res://assets/img/menu_bg_3.webp", "res://assets/img/menu_bg_4.webp"]
const SHOW := 16.0    # seconds a picture stays
const FADE := 3.0     # seconds of the cross-fade

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



func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# #bgSnap: the pictures blurred by a shader (filter: blur(6px)), darker than the game so the buttons stand
	# out on the light land; mipmapped 4K pictures: sharp on large screens, smooth when they drift
	var paths: Array = BGS.filter(func(x): return ResourceLoader.exists(x))
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
