class_name VehicleLayer
extends Control
## The company on the map, as the HTML version draws it on its vehicle canvas (drawCompany in 08e-company.js,
## drawIncMarks in 08f-incidents.js): couriers on the streets of hub cities (single dots or one marker when
## several overlap), trips with their trail, colour by mode, the state of the trip (incident waves, red when
## something serious happened, GPS blackout), attack marks, the remaining route of the selected trip.

const F_MONO_B := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const HUB_RGB := Color(1, 179 / 255.0, 71 / 255.0)
const MODE_RGB := {"road": Color(52 / 255.0, 199 / 255.0, 89 / 255.0), "rail": Color(236 / 255.0, 150 / 255.0, 92 / 255.0),
	"sea": Color(110 / 255.0, 190 / 255.0, 1.0), "air": Color(214 / 255.0, 150 / 255.0, 1.0)}
const RED := Color(240 / 255.0, 98 / 255.0, 95 / 255.0)
const AMBER := Color(241 / 255.0, 196 / 255.0, 83 / 255.0)
const INC_RED := {"acc": 1, "brk": 1, "fuel": 1, "cl": 1, "cxl": 1, "theft": 1, "pir": 1}
const BRAD := {"cap": .08, "big": .064, "city": .052, "town": .032, "vil": .016}

var camera: MapCamera
var session: GameSession
var selected: Variant = null      # the selected trip (CO_SEL)
var dpr := 1.0
var hits: Array = []              # {j | ids, x, y, r}: what is under the pointer (CO_HITS / CO_CL)
var _paths := {}                  # coCityPaths per place


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if session != null and session.sim != null:
		queue_redraw()


func _P(x: float, y: float, z: float) -> Variant:
	var w := Vector3(x, y, z)
	if camera.is_position_behind(w):
		return null
	return camera.unproject_position(w)


func _ms() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------- the streets couriers drive along in a hub city (coCityPaths, board version) ----------
func _city_paths(p: Dictionary) -> Array:
	if _paths.has(p.id):
		return _paths[p.id]
	var r := []
	var R_: float = BRAD.get(p.type, .04) * .92
	var rr := Mulberry.new(((p.id * 9973 + 7)) & 0xFFFFFFFF)
	var push := func(pts: PackedVector2Array) -> void:
		var c := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			c.append(c[c.size() - 1] + pts[i].distance_to(pts[i - 1]))
		r.append({"p": pts, "c": c, "L": c[c.size() - 1]})
	var ring := PackedVector2Array()
	for k in 33:
		var a := k / 32.0 * 6.2832
		ring.append(Vector2(p.x + cos(a) * R_ * .62, p.z + sin(a) * R_ * .62))
	push.call(ring)
	for k in 5:
		var a := rr.next() * 3.1416
		var o := (rr.next() - .5) * R_ * .8
		var nx := -sin(a)
		var nz := cos(a)
		var h := sqrt(maxf(0, R_ * R_ - o * o))
		var q := PackedVector2Array()
		for t in 9:
			var s := -h + 2 * h * t / 8.0
			q.append(Vector2(p.x + cos(a) * s + nx * o, p.z + sin(a) * s + nz * o))
		push.call(q)
	_paths[p.id] = r
	return r


static func _at(pp: Dictionary, s: float) -> Vector2:
	s = clampf(s, 0, pp.L)
	var c: PackedFloat32Array = pp.c
	var k := 1
	while k < c.size() - 1 and c[k] < s:
		k += 1
	var d := c[k] - c[k - 1]
	var t := (s - c[k - 1]) / (d if d else 1.0)
	return pp.p[k - 1].lerp(pp.p[k], t)


func _draw() -> void:
	hits = []
	if camera == null or session == null or session.sim == null:
		return
	var sim := session.sim
	var CO := sim.CO
	if CO.is_empty() or not CO.has("hubs"):
		return
	var now := session.anim_t
	var zf := clampf(11.0 / camera.dist, 1, 1.8)
	var T0 := sim.co_now()
	# couriers: idle city vehicles of a hub drive around its streets
	var cour := []
	for h in CO.hubs:
		var p: Dictionary = sim.PL[h.pid]
		if camera.dist >= 13 or not h.has("ids") or h.ids.is_empty():
			continue
		var paths := _city_paths(p)
		var ids := []
		for id in h.ids:
			for v in CO.veh:
				if v.id == id and v.st == "idle" and v.loc == h.pid:
					ids.append(id)
					break
		for i in mini(ids.size(), 240):
			var id: int = ids[i]
			var pp: Dictionary = paths[(i * 7 + 3) % paths.size()]
			var L: float = pp.L
			var sp := (.018 + ((id * 37) % 11) * .0022) / 40.0
			var d := fmod((now + id * 5.3) * sp, 2 * L)
			var fwd := d < L
			var s0 := d if fwd else 2 * L - d
			var q := _at(pp, s0)
			var qs: Variant = _P(q.x, 0, q.y)
			if qs == null:
				continue
			var tr := []
			for k in range(1, 5):
				var xk := _at(pp, s0 + (-1 if fwd else 1) * k * .012 / 20.0)
				var t2: Variant = _P(xk.x, 0, xk.y)
				if t2 != null:
					tr.append(t2)
			cour.append({"id": id, "x": qs.x, "y": qs.y, "tr": tr, "pid": p.id})
	# one marker when several couriers overlap (in a small city: all of its couriers)
	var cell := 22 * dpr
	var groups := {}
	var order := []
	var small := {}
	for c in cour:
		if not small.has(c.pid):
			var q: Dictionary = sim.PL[c.pid]
			var a: Variant = _P(q.x, 0, q.z)
			var b: Variant = _P(q.x + BRAD.get(q.type, .04), 0, q.z)
			small[c.pid] = a == null or b == null or a.distance_to(b) < 70 * dpr
		var key: String = ("p%d" % c.pid) if small[c.pid] else "%d:%d" % [floor(c.x / cell), floor(c.y / cell)]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(c)
	for key in order:
		var L: Array = groups[key]
		if L.size() >= 2:
			var c: Dictionary = L[0]
			var x: float = c.x
			var y: float = c.y
			var hs := 8 * dpr
			_trail(Vector2(x, y), c.tr, HUB_RGB)
			draw_rect(Rect2(x - hs, y - hs, hs * 2, hs * 2), Color(11 / 255.0, 21 / 255.0, 32 / 255.0, .55))
			draw_rect(Rect2(x - hs, y - hs, hs * 2, hs * 2), HUB_RGB, false, 1.4 * dpr)
			_dot(Vector2(x, y), 2.8 * dpr, HUB_RGB, Color(6 / 255.0, 18 / 255.0, 27 / 255.0, .85), .9 * dpr)
			var txt := "×%d" % L.size()
			var fs := int(round(9.5 * dpr))
			var tw := F_MONO_B.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6 * dpr
			var br := Rect2(x + hs - 1 * dpr, y - hs - 11 * dpr, tw, 12 * dpr)
			draw_rect(br, Color("#0b1520"))
			draw_rect(br, HUB_RGB, false, 1 * dpr)
			_text(txt, Vector2(x + hs + 2 * dpr, y - hs - 5 * dpr), fs, HUB_RGB)
			hits.append({"x": x, "y": y, "r": 14, "ids": L.map(func(o): return o.id), "pid": c.pid})
		else:
			for c in L:
				_trail(Vector2(c.x, c.y), c.tr, HUB_RGB)
				_dot(Vector2(c.x, c.y), 2.6 * dpr * minf(zf, 1.3), HUB_RGB, Color(6 / 255.0, 18 / 255.0, 27 / 255.0, .85), .9 * dpr)
				hits.append({"x": c.x, "y": c.y, "r": 8, "ids": [c.id], "pid": c.pid})
	# the remaining route of the selected trip
	if selected != null and CO.jobs.any(func(x): return is_same(x, selected)):
		_route(selected, T0)
	# trips
	for j in CO.jobs:
		var e: float = T0 - j.t0
		var st := sim.co_job_state(j, minf(e, j.tl + j.hs + j.tm * .5) if j.get("hold", 0) > 0 else e)
		var pos := sim.co_pos_at(j, st.s)
		var alt := sim.co_alt(j, st)
		var sp: Variant = _P(pos[0], alt, pos[1])
		if sp == null:
			continue
		var gv := _gps_vis(j, T0)
		if gv <= 0:
			continue
		var inc: Variant = st.get("inc") if st.get("inc") != null and st.inc.k != "stop" else null
		var red: bool = j.get("hold", 0) > 0 or j.lost or (inc != null and INC_RED.has(inc.k))
		var amb: bool = inc != null and not red
		var rgb: Color = RED if red else MODE_RGB.get(j.mode, HUB_RGB)
		# trail
		if st.seg >= 0 and inc == null:
			var step: float = {"road": .05, "rail": .06, "sea": .08, "air": .12}[j.mode] * minf(1, camera.dist / 6 + .25) * sim.CO_DU / 1.6
			var prev: Vector2 = sp
			for k in range(1, 10):
				var s2: float = st.s - k * step
				if s2 < 0:
					break
				var pp := sim.co_pos_at(j, s2)
				var a2 := 0.0
				if j.mode == "air":
					var L: float = j.lead if st.seg == 0 else j.len
					var base: float = 0.0 if st.seg == 0 else j.lead
					var f: float = (s2 - base) / (L if L else 1.0)
					a2 = sin(PI * clampf(f, 0, 1)) * clampf(L / sim.CO_DU * .22, .05, .9) if f >= 0 else 0.0
				var q: Variant = _P(pp[0], a2, pp[1])
				if q == null:
					break
				draw_line(prev, q, Color(rgb, .75 * (1 - k / 10.0) * gv), (2.4 if j.mode == "sea" else 1.8) * dpr * zf * (1 - k / 12.0), true)
				prev = q
		if j.mode == "air" and alt > 0:
			var sh: Variant = _P(pos[0], 0, pos[1])
			if sh != null:
				_ellipse(sh, 3 * dpr * zf, 1.6 * dpr * zf, Color(0, 0, 0, .35 * gv))
		var r := 4.2 * dpr * zf
		var t := _ms()
		if is_same(selected, j):
			var f := fmod(now * 1.2, 1.0)
			draw_arc(sp, r + 3 * dpr + f * 10 * dpr, 0, TAU, 32, Color(rgb, (.9 - f * .9) * gv), 1.5 * dpr, true)
		var bl := .5 + .5 * sin(t * (9.0 if red else 5.0)) if inc != null else 1.0
		if inc != null:
			var wc := AMBER if amb else rgb
			for w in (2 if amb else 1):
				var f := fmod(t / .9 + w * .5, 1.0)
				draw_arc(sp, r + 2 * dpr + f * 14 * dpr, 0, TAU, 32, Color(wc, .9 * (1 - f) * gv), 1.8 * dpr, true)
		draw_circle(sp, r * 2.1, Color(rgb, (.22 * bl + .06) * gv))
		_dot(sp, r, Color(rgb, ((.35 + .65 * bl) if red and inc != null else 1.0) * gv), Color(Color("#06121b"), gv), 1.4 * dpr)
		if inc != null and red and camera.dist < 16:
			_text("!", Vector2(sp.x - 2.5 * dpr, sp.y), int(round(9 * dpr)), Color(Color("#06121b"), gv))
		if j.n > 1 and camera.dist < 12:
			_text("×%d" % j.n, Vector2(sp.x + r + 3 * dpr, sp.y - r - 3 * dpr), int(round(9 * dpr)), Color(rgb, gv))
		if gv < 1 and camera.dist < 18:
			_text("GPS?", Vector2(sp.x + r + 3 * dpr, sp.y + r + 3 * dpr), int(round(8.5 * dpr)), Color(Color("#c9d4de"), gv))
		hits.append({"j": j, "x": sp.x, "y": sp.y, "r": 14})
	_marks()


func _trail(from: Vector2, tr: Array, col: Color) -> void:
	var prev := from
	for k in tr.size():
		draw_line(prev, tr[k], Color(col, .55 - k * .12), 1.4 * dpr, true)
		prev = tr[k]


func _dot(c: Vector2, r: float, fill: Color, stroke: Color, w: float) -> void:
	draw_circle(c, r, fill)
	draw_arc(c, r, 0, TAU, 24, stroke, w, true)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := i / 20.0 * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _text(s: String, pos: Vector2, fs: int, col: Color) -> void:
	var asc := F_MONO_B.get_ascent(fs)
	var desc := F_MONO_B.get_descent(fs)
	draw_string(F_MONO_B, Vector2(pos.x, pos.y + (asc - desc) / 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## GPS blackout: blink, vanish for a few seconds, flicker back, vanish again (incGpsVis)
func _gps_vis(j: Dictionary, T0: float) -> float:
	var gp: Variant = j.get("gps")
	if gp == null or T0 >= gp.until:
		return 1.0
	var t := fmod(_ms() + j.id * .73, 7.0)
	if t < 1.4:
		return 1.0 if sin(t * 22) > 0 else .12
	if t < 5:
		return 0.0
	return .5


## the selected trip: the rest of its route as a dashed line with a ring at the end (wroute)
func _route(j: Dictionary, T0: float) -> void:
	var sim := session.sim
	var st := sim.co_job_state(j, T0 - j.t0)
	var c := sim.co_cum(j)
	var n := c.size()
	var pts := []
	if j.mode == "air":
		for k in 49:
			var s_: float = st.s + (c[n - 1] * sim.CO_DU - st.s) * k / 48.0
			var pp := sim.co_pos_at(j, s_)
			var seg := 0 if s_ < j.lead else 1
			var L: float = j.lead if seg == 0 else j.len
			var f: float = (s_ - (j.lead if seg else 0.0)) / (L if L else 1.0)
			pts.append(Vector3(pp[0], sin(PI * clampf(f, 0, 1)) * clampf(L / sim.CO_DU * .22, .05, .9), pp[1]))
	else:
		var q0 := sim.co_pos_at(j, st.s)
		pts.append(Vector3(q0[0], 0, q0[1]))
		for i in n:
			if c[i] * sim.CO_DU <= st.s:
				continue
			pts.append(Vector3(j.p[i * 2], 0, j.p[i * 2 + 1]))
	var rgb: Color = MODE_RGB.get(j.mode, Color(1, 205 / 255.0, 130 / 255.0))
	_wdash(pts, rgb, 2.4 * dpr)
	if pts.size():
		var e: Variant = _P(pts.back().x, pts.back().y, pts.back().z)
		if e != null:
			draw_circle(e, 4 * dpr, Color(rgb, .25))
			draw_arc(e, 4 * dpr, 0, TAU, 24, rgb, 2 * dpr, true)


## a dashed line anchored to the world: the pattern does not crawl when the camera moves (wdash)
func _wdash(pts: Array, col: Color, w: float) -> void:
	if pts.size() < 2:
		return
	var q := pow(2.0, round(log(maxf(.25, camera.dist)) / log(2.0)))
	var Dl := .0075 * q
	var Gp := .0065 * q
	var per := Dl + Gp
	var acc := 0.0
	var budget := 24000
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var L := a.distance_to(b)
		if L <= 0:
			continue
		var s := 0.0
		var guard := 0
		while s < L and guard < 4000 and budget > 0:
			guard += 1
			budget -= 1
			var ph := fmod(acc, per)
			if ph < Dl - 1e-9:
				var e := minf(L, s + maxf(Dl - ph, per * 1e-4))
				var pa: Variant = _P(a.x + (b.x - a.x) * s / L, a.y + (b.y - a.y) * s / L, a.z + (b.z - a.z) * s / L)
				var pb: Variant = _P(a.x + (b.x - a.x) * e / L, a.y + (b.y - a.y) * e / L, a.z + (b.z - a.z) * e / L)
				if pa != null and pb != null:
					draw_line(pa, pb, col, w, true)
				acc += e - s
				s = e
			else:
				var e := minf(L, s + maxf(per - ph, per * 1e-4))
				acc += e - s
				s = e


## attacks: a skull badge with a ring, bandits or pirates closing in for the first seconds (drawIncMarks)
func _marks() -> void:
	var sim := session.sim
	var now := Time.get_ticks_msec()
	for m in sim.CO.get("imk", []):
		var x: float = m.x
		var z: float = m.z
		if m.k == "pir":
			for j in sim.CO.jobs:
				if j.id == m.jid:
					var q := sim.co_pos_at(j, sim.co_job_state(j, sim.co_now() - j.t0).s)
					x = q[0]
					z = q[1]
					break
		var c: Variant = _P(x, 0, z)
		if c == null:
			continue
		var a: float = (now - m.t) / 1000.0
		var col := RED if m.k == "pir" else Color(1, 140 / 255.0, 60 / 255.0)
		if a < 4:
			var k := clampf(a / 3, 0, 1)
			for i in (2 if m.k == "pir" else 3):
				var ang: float = i * 2.1 + fmod(m.t, 7)
				var R := (36 - 30 * k) * dpr
				var p := Vector2(c.x + cos(ang) * R, c.y + sin(ang) * R)
				if m.k == "pir":
					var boat := PackedVector2Array([p + Vector2(-5, -2) * dpr, p + Vector2(5, -2) * dpr, p + Vector2(3, 3) * dpr, p + Vector2(-3, 3) * dpr])
					draw_colored_polygon(boat, Color("#1a0808"))
					boat.append(boat[0])
					draw_polyline(boat, col, 1.4 * dpr, true)
				else:
					_dot(p, 3 * dpr, Color("#1a0808"), col, 1.4 * dpr)
		var f := fmod(now / 1000.0, 1.4) / 1.4
		draw_arc(c, (10 + f * 22) * dpr, 0, TAU, 40, Color(col, .9 * (1 - f)), 2 * dpr, true)
		var y: float = c.y - 20 * dpr
		var txt := "ПІРАТИ" if m.k == "pir" else "НАПАД"
		var fs := int(round(9 * dpr))
		var tw := F_MONO_B.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 24 * dpr
		var r := Rect2(c.x - tw / 2, y - 9 * dpr, tw, 18 * dpr)
		draw_rect(r, Color(26 / 255.0, 6 / 255.0, 6 / 255.0, .92))
		draw_rect(r, col, false, 1.2 * dpr)
		Icons.draw(self, "skull", c.x - tw / 2 + 4 * dpr, y, 12 * dpr, col)
		_text(txt, Vector2(c.x - tw / 2 + 19 * dpr, y + .5 * dpr), fs, col)
