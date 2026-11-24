class_name DotTex
extends RefCounted
## Markers drawn as small textures instead of antialiased circles: a canvas batches textured quads, so a
## hundred markers cost a few draw calls instead of thousands of triangles built every frame. White, tinted by
## the modulate colour of draw_texture_rect.
##   soft — a disc with a soft edge (halos and glows)
##   dot  — a filled disc with a dark rim (vehicles, road closures)

const N := 64
static var _soft: Texture2D = null
static var _dot: Texture2D = null


static func soft() -> Texture2D:
	if _soft == null:
		_soft = _make(false)
	return _soft


static func dot() -> Texture2D:
	if _dot == null:
		_dot = _make(true)
	return _dot


static func _make(rim: bool) -> Texture2D:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := (N - 1) / 2.0
	var R := N / 2.0 - 1.0
	var rimc := Color(.04, .08, .12)
	for y in N:
		for x in N:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(R - d + .5, 0, 1)   # 1 px antialiased edge at this size
			var col := Color(1, 1, 1, a)
			if rim:
				var rw := N * .085   # the rim: ~1.4 px on a 16 px dot
				var k := clampf(d - (R - rw) + .5, 0, 1)
				col = Color(1, 1, 1).lerp(rimc, k)
				col.a = a
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## draw a marker centred on c with radius r (the visible disc), tinted col
static func draw(ci: CanvasItem, tex: Texture2D, c: Vector2, r: float, col: Color) -> void:
	var R := r * N / (N - 2.0)
	ci.draw_texture_rect(tex, Rect2(c.x - R, c.y - R, R * 2, R * 2), false, col)
