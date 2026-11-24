class_name NightLights
extends Node2D
## The test day and night (settings: «День і ніч (тест)»): after dusk the towns light up — a warm glow under
## every settlement, bigger for the bigger ones, added onto the darkened map. Drawn only when the view or the
## darkness changes.

var camera: MapCamera
var sim: Sim = null
var night := 0.0          # 0 day … 1 deep night (MapView sets it)
var _key := ""

const R := {"cap": 26.0, "big": 21.0, "city": 16.0, "town": 10.0, "vil": 6.0}

## one soft glow drawn into a texture once: every town is a single textured quad, all of them batch into a
## few draw calls (seven circles a town made thousands of them)
static var _glow: Texture2D = null


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, .16, .22, .55, 1.0])
		g.colors = PackedColorArray([Color(1, .9, .68, 1), Color(1, .86, .6, .9), Color(1, .72, .38, .42), Color(1, .66, .32, .16), Color(1, .6, .3, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(.5, .5)
		t.fill_to = Vector2(1, .5)
		t.width = 64
		t.height = 64
		_glow = t


func _process(_delta: float) -> void:
	# redrawn when the view moves or the darkness changes by a visible step, not every frame of the dusk
	var k := "%s|%.2f|%s" % [camera.global_transform if camera != null else "", snappedf(night, .04), get_viewport_rect().size] if night > .01 else "off"
	if k != _key:
		_key = k
		queue_redraw()


func _draw() -> void:
	if night <= .01 or sim == null or camera == null:
		return
	var vs := get_viewport_rect().size
	var zoom := clampf(10.0 / camera.dist, .45, 2.2)
	for p in sim.PL:
		var w := Vector3(p.x, 0, p.z)
		if camera.is_position_behind(w):
			continue
		var c := camera.unproject_position(w)
		var r: float = R.get(p.type, 8.0) * zoom
		if c.x < -r or c.y < -r or c.x > vs.x + r or c.y > vs.y + r:
			continue
		draw_texture_rect(_glow, Rect2(c - Vector2(r, r), Vector2(r, r) * 2), false, Color(1, 1, 1, night))
