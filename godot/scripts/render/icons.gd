class_name Icons
extends RefCounted
## The line icons of the HTML version (ICONS in 03-core.js, exported to assets/icons.json by
## legacy/tools/dump_tables.js): SVG fragments in a 24×24 box drawn as strokes. Rasterised on demand
## at twice the size they are shown, cached by name, colour and size.

static var _src := {}
static var _cache := {}


static func _load() -> void:
	if _src.is_empty():
		_src = JSON.parse_string(FileAccess.get_file_as_string("res://assets/icons.json"))


static func has(name: String) -> bool:
	_load()
	return _src.has(name)


## a texture of the icon; size_px is the size it is drawn at (the texture is twice that)
static func tex(name: String, color: Color, size_px: float, stroke: float = 1.8) -> Texture2D:
	_load()
	var key := "%s|%s|%d|%.2f" % [name, color.to_html(), int(size_px * 2), stroke]
	if _cache.has(key):
		return _cache[key]
	var frag: String = _src.get(name, "")
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" width=\"24\" height=\"24\" fill=\"none\" stroke=\"#%s\" stroke-opacity=\"%.3f\" stroke-width=\"%.2f\" stroke-linecap=\"round\" stroke-linejoin=\"round\">%s</svg>" % [color.to_html(false), color.a, stroke, frag]
	var img := Image.new()
	img.load_svg_from_string(svg, size_px * 2 / 24.0)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## draws the icon centred vertically on y, its left edge at x (drawIcons)
static func draw(ci: CanvasItem, name: String, x: float, y: float, size_px: float, color: Color, stroke: float = 1.8) -> void:
	ci.draw_texture_rect(tex(name, color, size_px, stroke), Rect2(x, y - size_px / 2, size_px, size_px), false)
