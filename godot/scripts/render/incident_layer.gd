class_name IncidentLayer
extends Control
## The situation on the map (08f-incidents.js). Two passes, as in the HTML version:
## base (drawIncBase, under the settlements): pirate and bandit zones, weather zones with hatching, road
## closures, closed borders; top (drawIncTop, over the settlements): a closed sky, closed checkpoints, closed
## ports and airports.

const F_MONO_B := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const RED := Color(240 / 255.0, 98 / 255.0, 95 / 255.0)

var camera: MapCamera
var session: GameSession
var lines: Array = []          # TRWorldGen.lines() (borders between states: a, b = state id + 1)
var top := false
var mode := "co"             # the map layer (MapView.mode): road closures only on "co" and "grid"
var dpr := 1.0
var hits: Array = []           # {x, y, r, kind, data}: hover targets (INC_HIT / JAM_HIT)
var _border_cache := {}
var _key := ""
var _anim: Piece
var _anim_on := false
var _hits_static: Array = []
var _hits_anim: Array = []


class Piece extends Node2D:
	var fn: Callable

	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	Perf.begin("incident_layer._process")
	_process_t(_delta)
	Perf.end("incident_layer._process")


func _process_t(_delta: float) -> void:
	if session == null or session.sim == null or camera == null:
		return
	var sim := session.sim
	var CO := sim.CO
	# the situation changes with the camera and with the game (a few times a game day), not every frame
	var k := "%d|%s|%s|%s|%.2f|%d|%d|%d|%d|%d|%d|%d|%s" % [MapVis.ver, mode, camera.global_transform, size, dpr, int(sim.co_now() * 8),
		CO.get("clV", 0), CO.get("wx", []).size(), CO.get("pir", []).size(), CO.get("band", []).size(), sim.jam.size(), sim.sky.size(), camera.dist < 26]
	if k != _key:
		_key = k
		queue_redraw()
	# the moving parts: pulsing road closures (base), the running dashes of a closed sky (top)
	if _anim == null:
		_anim = Piece.new()
		_anim.fn = _anim_top if top else _anim_base
		add_child(_anim)
	if (top and sim.sky.size()) or (not top and _jams_on()):
		_anim.queue_redraw()
		_anim_on = true
	elif _anim_on:
		_anim.queue_redraw()
		_anim_on = false


func _P(x: float, z: float) -> Variant:
	var w := Vector3(x, 0, z)
	if camera.is_position_behind(w):
		return null
	return camera.unproject_position(w)


func _c(s: String, a: float = 1.0) -> Color:
	var p := s.split(",")
	return Color(float(p[0]) / 255.0, float(p[1]) / 255.0, float(p[2]) / 255.0, a)


func _circle(x: float, z: float, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := i / float(n) * TAU
		var q: Variant = _P(x + cos(a) * r, z + sin(a) * r)
		if q != null:
			pts.append(q)
	return pts


func _badge(c: Vector2, icon: String, col: Color) -> void:
	var R := 10 * dpr
	draw_circle(c, R, Color(8 / 255.0, 18 / 255.0, 28 / 255.0, .9), true, -1.0, true)
	draw_arc(c, R, 0, TAU, 28, col, 1.4 * dpr, true)
	Icons.draw(self, icon, c.x - R * .62, c.y, R * 1.24, col)


func _text(s: String, pos: Vector2, fs: int, col: Color) -> void:
	draw_string(F_MONO_B, Vector2(pos.x, pos.y + (F_MONO_B.get_ascent(fs) - F_MONO_B.get_descent(fs)) / 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw() -> void:
	Perf.begin("incident_layer._draw")
	_draw_t()
	Perf.end("incident_layer._draw")


func _draw_t() -> void:
	if Perf.off("inc"):
		return
	hits = []
	if camera == null or session == null or session.sim == null or session.sim.CO.is_empty():
		return
	if top:
		_draw_top()
	else:
		_draw_base()
	_hits_static = hits
	hits = _hits_static + _hits_anim


func _jams_on() -> bool:
	return MapVis.vis("jam") and session.sim.jam.size() > 0 and camera.dist < 26 and (mode == "co" or mode == "grid")


func _draw_base() -> void:
	var sim := session.sim
	var CO := sim.CO
	var t := Time.get_ticks_msec() / 1000.0
	var W := size.x
	var H := size.y
	# pirate and bandit zones
	for e in [["pir", "240,98,95"], ["band", "255,140,60"]]:
		for z in (CO.get(e[0], []) if MapVis.vis(e[0]) else []):
			var pts := _circle(z.x, z.z, z.r, 36)
			if pts.size() < 10:
				continue
			draw_colored_polygon(pts, _c(e[1], .1))
			draw_polyline(pts, _c(e[1], .75), 1.5 * dpr, true)
			var c: Variant = _P(z.x, z.z)
			if c != null and camera.dist < 26:
				_badge(c, "skull", _c(e[1]))
	# weather zones: drawn like the bandit zones (a faint disc, a thin rim, the badge), in the colour of the weather
	for w in (CO.get("wx", []) if MapVis.vis("wx") else []):
		var K: Dictionary = GameData.WXK[w.k]
		var pts := _circle(w.x, w.z, w.r, 40)
		if pts.size() < 10:
			continue
		var col := _c(K.col)
		draw_colored_polygon(pts, Color(col, .1))
		draw_polyline(pts, Color(col, .75), 1.5 * dpr, true)
		var c: Variant = _P(w.x, w.z)
		if c != null and camera.dist < 26:
			_badge(c, K.ic, Color(col, .55) if w.t0 > sim.co_now() else col)   # a forecast: the same colour, faded
	# closed borders: red lines along the border
	var zw := clampf(13 / camera.dist, 1, 3.2)
	for cl in (CO.get("cls", []) if MapVis.vis("clb") else []):
		if cl.kind == "cp":
			continue   # a single closed checkpoint: only its square turns red
		for p in _border_pts(cl):
			var pts := PackedVector2Array()
			for i in range(0, p.size(), 2):
				var q: Variant = _P(p[i], p[i + 1])
				if q == null:
					if pts.size() > 1:
						draw_polyline(pts, Color("#f0443c"), 1.25 * zw * dpr, true)
					pts = PackedVector2Array()
					continue
				pts.append(q)
			if pts.size() > 1:
				draw_polyline(pts, Color("#f0443c"), 1.25 * zw * dpr, true)


## the pulsing road closures (redrawn every frame while there are any)
func _anim_base(n: Node2D) -> void:
	_hits_anim = []
	if session == null or session.sim == null:
		return
	var sim := session.sim
	var t := Time.get_ticks_msec() / 1000.0
	var W := size.x
	var H := size.y
	# road closures
	if _jams_on():
		var r := clampf(9 / sqrt(camera.dist), 2.2, 5) * dpr
		var T_ := sim.co_now()
		for J in sim.jam:
			var q: Variant = _P(J.x, J.z)
			if q == null or q.x < -20 or q.y < -20 or q.x > W + 20 or q.y > H + 20:
				continue
			var pl: bool = J.t0 > T_
			var col := _c("150,160,172") if pl else (_c("240,68,60") if J.sev > 1 else _c("255,138,42"))
			var f: float = .3 if pl else .5 + .5 * sin(t * 4 + J.id)
			n.draw_circle(q, r * (1.9 + .4 * f), Color(col, .18 + .14 * f), true, -1.0, true)
			n.draw_circle(q, r, col, true, -1.0, true)
			n.draw_arc(q, r, 0, TAU, 20, Color("#0b1520"), 1.2 * dpr, true)
			_hits_anim.append({"x": q.x, "y": q.y, "r": r / dpr + 5, "kind": "jam", "data": J})
	hits = _hits_static + _hits_anim


## the border lines a closure covers (incBorderPts)
func _border_pts(cl: Dictionary) -> Array:
	if _border_cache.has(cl.id):
		return _border_cache[cl.id]
	var out := []
	for l in lines:
		if not l.a or not l.b:
			continue
		var a: int = l.a - 1
		var b: int = l.b - 1
		var ok: bool = (a == cl.a or b == cl.a) if cl.kind == "cty" else (a == cl.a and b == cl.b or a == cl.b and b == cl.a)
		if ok:
			out.append(l.p)
	_border_cache[cl.id] = out
	return out


func _draw_top() -> void:
	var sim := session.sim
	var CO := sim.CO
	var W := size.x
	var H := size.y
	# a closed sky: a running dashed line along the borders of the states at war, a badge at the capital
	if sim.sky.size() and MapVis.vis("sky"):
		for cid in sim.sky:
			var cap: Variant = null
			for p in sim.PL:
				if p.cid == cid and (cap == null or p.type == "cap"):
					cap = p
					if p.type == "cap":
						break
			if cap == null:
				continue
			var q: Variant = _P(cap.x, cap.z + .35)
			if q == null:
				continue
			var txt := "ЗАКРИТЕ НЕБО"
			var fs := int(round(10 * dpr))
			var tw := F_MONO_B.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 28 * dpr
			var r := Rect2(q.x - tw / 2, q.y - 10 * dpr, tw, 20 * dpr)
			draw_rect(r, Color(40 / 255.0, 8 / 255.0, 20 / 255.0, .9))
			draw_rect(r, Color("#d696ff"), false, 1.2 * dpr)
			Icons.draw(self, "plane", q.x - tw / 2 + 5 * dpr, q.y, 13 * dpr, RED)
			draw_line(Vector2(q.x - tw / 2 + 5 * dpr, q.y + 6 * dpr), Vector2(q.x - tw / 2 + 18 * dpr, q.y - 6 * dpr), RED, 1.6 * dpr, true)
			_text(txt, Vector2(q.x - tw / 2 + 22 * dpr, q.y + .5 * dpr), fs, Color("#e9c8ff"))
	# closed checkpoints: a red square with a cross, the size of an open one
	if CO.get("cls", []).size() and MapVis.vis("clb"):
		var u0: Variant = _P(camera.tx, camera.tz)
		var u1: Variant = _P(camera.tx + 1, camera.tz)
		var pu: float = u0.distance_to(u1) / dpr if u0 != null and u1 != null else 40.0
		var cs := clampf(pu / 40, 3.5, 7) * dpr
		var pts := []
		for c in sim.board.get("checkpoints", []):
			var cl: Variant = sim.inc_cross_cl(c.a, c.b, c.x, c.z)
			if cl != null:
				pts.append([c, cl])
		for cl in CO.cls:
			if cl.kind == "cp" and not pts.any(func(o): return JS.hypot(o[0].x - cl.x, o[0].z - cl.z) < .05):
				pts.append([cl, cl])
		var seen := []
		for o in pts:
			var q: Variant = _P(o[0].x, o[0].z)
			if q == null or q.x < -20 or q.y < -20 or q.x > W + 20 or q.y > H + 20:
				continue
			if seen.any(func(s): return s.distance_to(q) < 4 * dpr):
				continue
			seen.append(q)
			var r := Rect2(q.x - cs, q.y - cs, cs * 2, cs * 2)
			draw_rect(r, RED)
			draw_rect(r, Color("#0b1520"), false, 1.4 * dpr)
			draw_line(q + Vector2(-cs, -cs) * .55, q + Vector2(cs, cs) * .55, Color.WHITE, 2 * dpr, true)
			draw_line(q + Vector2(cs, -cs) * .55, q + Vector2(-cs, cs) * .55, Color.WHITE, 2 * dpr, true)
			hits.append({"x": q.x, "y": q.y, "r": cs / dpr + 4, "kind": "cl", "data": o[1], "cp": o[0]})
	# closed ports and airports
	for p in (sim.PL if MapVis.vis("clp") else []):
		var sea: Variant = sim.inc_port_cl(p, "sea") if p.port != null else null
		var air: Variant = sim.inc_port_cl(p, "air") if p.air else null
		if sea == null and air == null:
			continue
		var q0: Variant = _P(p.x, p.z)
		if q0 == null:
			continue
		var ks := []
		if sea != null:
			ks.append(["anchor", sea])
		if air != null:
			ks.append(["plane", air])
		var R := 8.5 * dpr
		for i in ks.size():
			var q := Vector2(q0.x + (i - (ks.size() - 1) / 2.0) * (R * 2 + 3 * dpr), q0.y - R - 9 * dpr)
			draw_circle(q, R, Color("#f0443c"), true, -1.0, true)
			draw_arc(q, R, 0, TAU, 24, Color("#0b1520"), 1.4 * dpr, true)
			Icons.draw(self, ks[i][0], q.x - R * .6, q.y, R * 1.2, Color.WHITE)
			hits.append({"x": q.x, "y": q.y, "r": R / dpr + 3, "kind": "port", "data": {"place": p, "what": ks[i][0], "why": ks[i][1]}})


## the running dashes along the borders of the states at war (a closed sky)
func _anim_top(n: Node2D) -> void:
	if session == null or session.sim == null or session.sim.sky.is_empty() or not MapVis.vis("sky"):
		return
	var sim := session.sim
	var off := fmod(Time.get_ticks_msec() / 1000.0 * 14 * dpr, 13 * dpr)
	for l in lines:
		if not (sim.sky.has(l.a - 1) or sim.sky.has(l.b - 1)):
			continue
		var pts := PackedVector2Array()
		for i in range(0, l.p.size(), 2):
			var q: Variant = _P(l.p[i], l.p[i + 1])
			if q != null:
				pts.append(q)
		_dashed(n, pts, 7 * dpr, 6 * dpr, off, Color(214 / 255.0, 150 / 255.0, 1.0, .95), 2 * dpr)


## a dashed polyline with a moving offset (setLineDash + lineDashOffset)
func _dashed(n: CanvasItem, pts: PackedVector2Array, dash: float, gap: float, off: float, col: Color, w: float) -> void:
	var per := dash + gap
	var acc := per - fmod(off, per)
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var L := a.distance_to(b)
		var s := 0.0
		while s < L:
			var ph := fmod(acc, per)
			if ph < dash:
				var e := minf(L, s + dash - ph)
				n.draw_line(a.lerp(b, s / L), a.lerp(b, e / L), col, w, true)
				acc += e - s
				s = e
			else:
				var e := minf(L, s + per - ph)
				acc += e - s
				s = e
