class_name MapCamera
extends Camera3D
## Map camera, the same behaviour as the HTML version (Cam, camEye, camPitch, bindMapInput, renderFrame in 04-map.js):
## a target point on the board, a distance and a pitch that grows with the distance; the wheel zooms
## (×1.12 / ×0.89 per notch), dragging pans the board under the cursor; everything glides to its target
## at the same speed per second whatever the frame rate.

signal hover_changed(world_point: Vector3)
signal clicked(screen: Vector2)   # a left click that did not drag the map
signal dragged                    # the map was dragged

var tx := 0.0
var tz := 0.4
var dist := 13.0
var yaw := 0.0
var ttx := 0.0
var ttz := 0.4
var tdist := 13.0
var world_size := Vector2(22.5, 15.0)
var min_dist := 0.55

var _down := false
var _moved := false
var _down_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO


func _ready() -> void:
	fov = 38.0
	near = 0.1
	far = 100.0
	keep_aspect = Camera3D.KEEP_HEIGHT
	_apply()


func set_world(size: Vector2) -> void:
	world_size = size
	dist = size.x * 1.05
	tdist = dist
	tx = 0.0
	ttx = 0.0
	tz = 0.6
	ttz = 0.6


func look_at_point(p: Vector2, d: float = -1.0) -> void:
	ttx = p.x
	ttz = p.y
	if d > 0:
		tdist = clampf(d, min_dist, world_size.x * 1.25)


func pitch() -> float:
	return lerpf(.8, 1.1, clampf((dist - 3.0) / 15.0, 0.0, 1.0))


func eye() -> Vector3:
	var p := pitch()
	return Vector3(tx + sin(yaw) * cos(p) * dist, sin(p) * dist, tz + cos(yaw) * cos(p) * dist)


func _process(delta: float) -> void:
	Perf.begin("map_camera._process")
	_process_t(delta)
	Perf.end("map_camera._process")


func _process_t(delta: float) -> void:
	if Perf.off("still"):   # --off=still: the camera keeps gliding (to measure redraws while the map moves)
		ttx += sin(Time.get_ticks_msec() / 700.0) * .02
	var dt := clampf(delta * 1000.0, 1.0, 50.0)
	var k := 1.0 - pow(.85, dt / 16.7)
	dist += (tdist - dist) * k
	tx += (ttx - tx) * k
	tz += (ttz - tz) * k
	_apply()


func _apply() -> void:
	var e := eye()
	global_position = e
	look_at(Vector3(tx, 0, tz), Vector3.UP)


## The point on the board plane (y = 0) under a screen position, or null.
func pick_plane(screen: Vector2) -> Variant:
	var o := project_ray_origin(screen)
	var d := project_ray_normal(screen)
	if absf(d.y) < 1e-6:
		return null
	var t := -o.y / d.y
	if t < 0:
		return null
	return o + d * t


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and get_viewport().gui_get_hovered_control() == null:
			var f := 1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else .89
			tdist = clampf(tdist * f, min_dist, world_size.x * 1.25)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if not mb.pressed and _down and not _moved:
				clicked.emit(mb.position)
			_down = mb.pressed
			_moved = false
			_down_pos = mb.position
			_last_pos = mb.position
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _down:
			if mm.position.distance_to(_down_pos) > 4.0:
				if not _moved:
					dragged.emit()
				_moved = true
			if _moved:
				var p0: Variant = pick_plane(_last_pos)
				var p1: Variant = pick_plane(mm.position)
				_last_pos = mm.position
				if p0 != null and p1 != null:
					var dx: float = p0.x - p1.x
					var dz: float = p0.z - p1.z
					var l := Vector2(dx, dz).length()
					var mx := dist * .12
					if l > mx:
						dx *= mx / l
						dz *= mx / l
					var mxx := minf(world_size.x / 2 - .5, dist * .28)
					var mzz := minf(world_size.y / 2 - .4, dist * .2)
					tx = clampf(tx + dx, -world_size.x / 2 + mxx, world_size.x / 2 - mxx)
					tz = clampf(tz + dz, -world_size.y / 2 + mzz, world_size.y / 2 - mzz * .3)
					ttx = tx
					ttz = tz
		else:
			var p: Variant = pick_plane(mm.position)
			if p != null:
				hover_changed.emit(p)
