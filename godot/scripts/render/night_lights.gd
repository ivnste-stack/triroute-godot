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


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func _process(_delta: float) -> void:
	var k := "%s|%.3f|%s" % [camera.global_transform if camera != null else "", night, get_viewport_rect().size] if night > .01 else "off"
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
		# a soft glow: rings fading outwards, a bright core
		for i in 6:
			var f := 1.0 - i / 6.0
			draw_circle(c, r * (1.0 - i * .14), Color(1.0, .72, .38, .09 * night * (1.2 - f * .4)))
		draw_circle(c, r * .18, Color(1.0, .86, .6, .75 * night))
