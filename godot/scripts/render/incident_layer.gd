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
var lines: Array = []:         # TRWorldGen.lines() (borders between states: a, b = state id + 1)
	set(v):
		lines = v
		_border_cache = {}   # closures of another world (or of the same one edited) had other borders
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
	# the markers are small textures (DotTex): filtered through their mipmaps, smooth at any zoom
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	Perf.begin("incident_layer._process")
	_process_t(_delta)
	Perf.end("incident_layer._process")


func _process_t(_delta: float) -> void:
	if session == null or session.sim == null or camera == null:
		if _anim != null and _anim_on:   # the game is gone: its pulsing markers go with it
			_anim.queue_redraw()
			_anim_on = false
		if _cl_layer != null:
			_cl_layer.queue_free()
			_cl_layer = null
			_cl_key = ""
		hits = []
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
	# as many points as its size on screen needs (a small zone far away: a dozen, not forty projections)
	var c0: Variant = _P(x, z)
	var c1: Variant = _P(x + r, z)
	if c0 != null and c1 != null:
		n = clampi(int((c0 as Vector2).distance_to(c1) / 3.0), 32, maxi(n, 64))   # round at any zoom
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
	var t := Clock.now()
	var W := size.x
	var H := size.y
	# pirate and bandit zones
	for e in [["pir", "240,98,95"], ["band", "255,140,60"]]:
		for z in (CO.get(e[0], []) if MapVis.vis(e[0]) else []):
			var pts := _circle(z.x, z.z, z.r, 36)
			if pts.size() < 8:
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
		if pts.size() < 8:
			continue
		var col := _c(K.col)
		draw_colored_polygon(pts, Color(col, .1))
		draw_polyline(pts, Color(col, .75), 1.5 * dpr, true)
		var c: Variant = _P(w.x, w.z)
		if c != null and camera.dist < 26:
			_badge(c, K.ic, Color(col, .55) if w.t0 > sim.co_now() else col)   # a forecast: the same colour, faded
	# closed borders: red lines along the border — a GPU line layer (_closed_lines), not drawn here: a closed
	# country's whole border projected point by point and stroked on the CPU at every camera move cost 15–25 ms
	_closed_lines()


## the pulsing road closures (redrawn every frame while there are any)
const JAM_PLAN := Color(150 / 255.0, 160 / 255.0, 172 / 255.0)
const JAM_BAD := Color(240 / 255.0, 68 / 255.0, 60 / 255.0)
const JAM_WARN := Color(1.0, 138 / 255.0, 42 / 255.0)


func _anim_base(n: Node2D) -> void:
	Perf.begin("incident_layer.anim")
	_anim_base_t(n)
	Perf.end("incident_layer.anim")


func _anim_base_t(n: Node2D) -> void:
	_hits_anim = []
	if session == null or session.sim == null:
		return
	var sim := session.sim
	var t := Clock.now()
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
			var col: Color = JAM_PLAN if pl else (JAM_BAD if J.sev > 1 else JAM_WARN)
			var f: float = .3 if pl else .5 + .5 * sin(t * 4 + J.id)
			# textured markers: all the closures batch into a few draw calls (antialiased circles for each
			# one every frame were the costliest thing on the CPU)
			DotTex.draw(n, DotTex.soft(), q, r * (1.9 + .4 * f), Color(col, .18 + .14 * f))
			DotTex.draw(n, DotTex.dot(), q, r, col)
			_hits_anim.append({"x": q.x, "y": q.y, "r": r / dpr + 5, "kind": "jam", "data": J})
	hits = _hits_static + _hits_anim


var _cl_layer: LineLayer = null
var _cl_key := ""


## the closed borders as one GPU line layer: built again when the closures change, re-projected by the GPU
## when the camera moves (like the map's own borders, MapOverlay)
func _closed_lines() -> void:
	var CO := session.sim.CO
	var cls: Array = CO.get("cls", []) if MapVis.vis("clb") else []
	var key := ""
	for cl in cls:
		if cl.kind != "cp":
			key += "%s," % cl.id
	key += "|%d" % lines.size()
	if key != _cl_key:
		_cl_key = key
		if _cl_layer != null:
			_cl_layer.queue_free()
			_cl_layer = null
		var pls := []
		for cl in cls:
			if cl.kind != "cp":
				pls.append_array(_border_pts(cl))
		if pls.size():
			_cl_layer = LineLayer.new(LineLayer.build_geometry(pls), Color("#f0443c"), 1.0)
			add_child(_cl_layer)
			move_child(_cl_layer, 0)   # under the pulsing road closures
	if _cl_layer != null:
		var vp := camera.get_camera_projection() * Projection(camera.get_camera_transform().affine_inverse())
		_cl_layer.set_camera(vp, size)
		_cl_layer.set_width(1.25 * clampf(13 / camera.dist, 1, 3.2) * dpr)


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
			var txt := I18n.t("ЗАКРИТЕ НЕБО")
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
		# the checkpoint icon under it (town layer) steps by 0.5 px and has a light rim: the red square is the
		# next step up plus the rim, so the rim never peeks out while zooming
		var cs := (ceilf(clampf(pu / 40, 3.5, 7) * 2) / 2 + 1.2) * dpr
		var pts: Array = _closed_state().cps
		var seen := []
		for o in pts:
			var q: Variant = _P(o[0].get("dx", o[0].x), o[0].get("dz", o[0].z))   # on the border line, like the icon
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
	for e in (_closed_state().ports if MapVis.vis("clp") else []):
		var p: Dictionary = e[0]
		var ks: Array = e[1]
		var q0: Variant = _P(p.x, p.z)
		if q0 == null:
			continue
		var R := 8.5 * dpr
		for i in ks.size():
			var q := Vector2(q0.x + (i - (ks.size() - 1) / 2.0) * (R * 2 + 3 * dpr), q0.y - R - 9 * dpr)
			draw_circle(q, R, Color("#f0443c"), true, -1.0, true)
			draw_arc(q, R, 0, TAU, 24, Color("#0b1520"), 1.4 * dpr, true)
			Icons.draw(self, ks[i][0], q.x - R * .6, q.y, R * 1.2, Color.WHITE)
			hits.append({"x": q.x, "y": q.y, "r": R / dpr + 3, "kind": "port", "data": {"place": p, "what": ks[i][0], "why": ks[i][1]}})


var _cs_key := ""
var _cs := {}


## what is closed now — the checkpoints and the ports and airports — worked out when the game changes, not at
## every camera move (every checkpoint and every town checked against every closure and weather zone each
## time the view moved cost ~2 ms a frame)
func _closed_state() -> Dictionary:
	var sim := session.sim
	var CO := sim.CO
	var key := "%d|%d|%d|%d|%d|%d" % [CO.get("clV", 0), CO.get("cls", []).size(), CO.get("wx", []).size(), sim.sky.size(), int(sim.co_now() * 8), sim.blk_v]
	if key == _cs_key:
		return _cs
	_cs_key = key
	var cps := []
	if CO.get("cls", []).size():
		for c in sim.board.get("checkpoints", []):
			var cl: Variant = sim.inc_cross_cl(c.a, c.b, c.x, c.z)
			if cl != null:
				cps.append([c, cl])
		for cl in CO.cls:
			if cl.kind == "cp" and not cps.any(func(o): return JS.hypot(o[0].x - cl.x, o[0].z - cl.z) < .05):
				cps.append([cl, cl])
	var ports := []
	for p in sim.PL:
		var sea: Variant = sim.inc_port_cl(p, "sea") if p.port != null else null
		var air: Variant = sim.inc_port_cl(p, "air") if p.air else null
		if sea == null and air == null:
			continue
		var ks := []
		if sea != null:
			ks.append(["anchor", sea])
		if air != null:
			ks.append(["plane", air])
		ports.append([p, ks])
	_cs = {"cps": cps, "ports": ports}
	return _cs


## the running dashes along the borders of the states at war (a closed sky)
func _anim_top(n: Node2D) -> void:
	if session == null or session.sim == null or session.sim.sky.is_empty() or not MapVis.vis("sky"):
		return
	var sim := session.sim
	var off := fmod(Clock.now() * 14 * dpr, 13 * dpr)
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
