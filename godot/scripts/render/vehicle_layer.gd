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


## what moves on its own between two pictures of the map (the pulse of the selected trip, incident waves and
## blinking, a GPS blackout, attack marks) is drawn by this child every frame; the trips, trails and the route
## only when the game's clock, the camera or the trips change
var _fx: Control
var _fx_items: Array = []   # [{j, sp, r, rgb, inc, red, amb, tp, tc, w, sel}] from the last picture


func _ready() -> void:
	# the markers are small textures (DotTex): filtered through their mipmaps, smooth at any zoom
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx = Control.new()
	_fx.texture_filter = texture_filter
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


func _process(_delta: float) -> void:
	Perf.begin("vehicle_layer._process")
	_process_t(_delta)
	Perf.end("vehicle_layer._process")


func _process_t(_delta: float) -> void:
	if session == null or session.sim == null:
		return
	# redrawn when something on it moves: the game's clock, the camera, the legend, or a blinking marker
	# (paused with a still camera a fleet of hundreds cost 2+ ms a frame for the same picture)
	var k := "%.6f|%s|%s|%d|%d|%d" % [session.sim.co_now(), camera.global_transform, size, MapVis.ver, session.sim.CO.get("jobs", []).size(),
		selected.id if selected != null else -1]
	if k != _key:
		_key = k
		queue_redraw()
	if _anim:
		_fx.queue_redraw()


var _key := ""
var _anim := false   # the last picture has blinking or pulsing markers: they need every frame


func _P(x: float, y: float, z: float) -> Variant:
	var w := Vector3(x, y, z)
	if camera.is_position_behind(w):
		return null
	return camera.unproject_position(w)


func _ms() -> float:
	return Clock.now()


func _draw() -> void:
	Perf.begin("vehicle_layer._draw")
	_draw_t()
	Perf.end("vehicle_layer._draw")


func _draw_t() -> void:
	_fx_items = []
	_fx.queue_redraw()   # the effects follow this picture (a new world: the old game's markers go too)
	if Perf.off("veh"):
		return
	hits = []
	if camera == null or session == null or session.sim == null:
		return
	var sim := session.sim
	var CO := sim.CO
	if CO.is_empty() or not CO.has("hubs"):
		return
	var anim := false
	var zf := clampf(11.0 / camera.dist, 1, 1.8)
	var T0 := sim.co_now()
	var vw := size
	# the remaining route of the selected trip
	if selected != null and CO.jobs.any(func(x): return is_same(x, selected)):
		_route(selected, T0)
	# trips
	for j in CO.jobs:
		if not MapVis.vis("v_" + String(j.mode)) and not is_same(selected, j):
			continue
		var e: float = T0 - j.t0
		var st := sim.co_job_state(j, minf(e, j.tl + j.hs + j.tm * .5) if j.get("hold", 0) > 0 else e)
		var pos := sim.co_pos_at(j, st.s)
		var alt := sim.co_alt(j, st)
		var sp: Variant = _P(pos[0], alt, pos[1])
		if sp == null:
			continue
		# off the screen: nothing to draw or to point at (its trail could reach in, by at most a few dots)
		if sp.x < -60 or sp.y < -60 or sp.x > vw.x + 60 or sp.y > vw.y + 60:
			continue
		var gv := 1.0   # a GPS blackout fades it: the effects child draws it with its blink
		var inc: Variant = st.get("inc") if st.get("inc") != null and st.inc.k != "stop" else null
		var red: bool = j.get("hold", 0) > 0 or j.lost or (inc != null and INC_RED.has(inc.k))
		var amb: bool = inc != null and not red
		var rgb: Color = RED if red else MODE_RGB.get(j.mode, HUB_RGB)
		# a trip whose marker blinks or waves is drawn by the effects child (_draw_fx), every frame
		var live: bool = inc != null or j.get("gps") != null and T0 < j.gps.until
		var fx: Variant = null
		if live or is_same(selected, j):
			anim = true
			fx = {"j": j, "sp": sp, "r": 4.2 * dpr * zf, "rgb": rgb, "inc": inc, "red": red, "amb": amb, "live": live, "sel": is_same(selected, j), "tp": null, "tc": null, "w": 0.0}
			_fx_items.append(fx)
		# trail: full close up, shorter farther out, none at the far zoom (a dot or two of pixels there)
		# fewer trail points as the camera goes back, and none from far for road and rail (hundreds of them); planes
		# and ships keep theirs at any distance (few of them, and the trail shows where they head over open sea)
		var far_ok: bool = j.mode == "air" or j.mode == "sea"
		var tn := 6 if camera.dist < 9 else (3 if camera.dist < 17 or far_ok else 0)
		if trails and tn > 0 and st.seg >= 0 and inc == null:
			var step: float = {"road": .05, "rail": .06, "sea": .08, "air": .12}[j.mode] * minf(1, camera.dist / 6 + .25) * sim.CO_DU / 1.6
			# one polyline with fading colours instead of nine separate lines
			var tp := PackedVector2Array([sp])
			var tc := PackedColorArray([Color(rgb, .75 * gv)])
			var kk := 6.0 / tn
			if j.mode != "air":   # on the ground and at sea: along the route itself, through its every bend
				var trl := _trail_path(j, st.s, 9 * step, rgb, gv, tp, tc)
				tp = trl[0]
				tc = trl[1]
				tn = 0
			for k in range(1, tn + 1):   # 6 points 1.5 steps apart (the original's 9), or 3 points 3 steps apart
				var s2: float = st.s - k * step * 1.5 * kk
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
				tp.append(q)
				tc.append(Color(rgb, .75 * (1 - k * kk * 1.5 / 10.0) * gv))
			if tp.size() > 1:
				if fx != null and fx.live:   # a GPS blackout fades the trail too: drawn with it
					fx.tp = tp
					fx.tc = tc
					fx.w = maxf(2.0 * dpr, (2.4 if j.mode == "sea" else 1.8) * dpr * zf * .8)
				else:   # at least 2 px: a thinner antialiased line shimmers at its edges as it moves
					draw_polyline_colors(tp, tc, maxf(2.0 * dpr, (2.4 if j.mode == "sea" else 1.8) * dpr * zf * .8), true)
		if j.mode == "air" and alt > 0:
			var sh: Variant = _P(pos[0], 0, pos[1])
			if sh != null:
				_ellipse(sh, 3 * dpr * zf, 1.6 * dpr * zf, Color(0, 0, 0, .35 * gv))
		if fx == null or not fx.live:
			_marker(self, j, sp, 4.2 * dpr * zf, rgb, null, false, false, 1.0)
		var hit := {"j": j, "x": sp.x, "y": sp.y, "r": 14, "wx": pos[0], "wz": pos[1]}
		if is_same(selected, j) and st.seg >= 0:   # where it heads on the screen: its card stays clear of the route ahead
			var ds: float = .04 * sim.CO_DU
			var pa := sim.co_pos_at(j, maxf(0.0, st.s - ds))
			var pb := sim.co_pos_at(j, st.s + ds)
			var qa: Variant = _P(pa[0], alt, pa[1])
			var qb: Variant = _P(pb[0], alt, pb[1])
			if qa != null and qb != null:
				hit.dx = (qb - qa).normalized().x if qb != qa else 0.0
		hits.append(hit)
	_anim = anim or not session.sim.CO.get("imk", []).is_empty()
	_fx.queue_redraw()


## the fading trails behind moving vehicles (settings «Сліди техніки»)
static var trails := true


func _dot(c: Vector2, r: float, fill: Color, stroke: Color, w: float) -> void:
	_dot_on(self, c, r, fill, stroke, w)


func _dot_on(ci: CanvasItem, c: Vector2, r: float, fill: Color, stroke: Color, w: float) -> void:
	ci.draw_circle(c, r, fill, true, -1.0, true)
	ci.draw_arc(c, r, 0, TAU, 24, stroke, w, true)


## a trip's marker on ci: the dot with its glow, incident waves and blink, "!", the count, "GPS?" (gv: GPS fade)
func _marker(ci: CanvasItem, j: Dictionary, sp: Vector2, r: float, rgb: Color, inc: Variant, red: bool, amb: bool, gv: float) -> void:
	var t := _ms()
	var bl := .5 + .5 * sin(t * (9.0 if red else 5.0)) if inc != null else 1.0
	if inc != null:
		var wc := AMBER if amb else rgb
		for w in (2 if amb else 1):
			var f := fmod(t / .9 + w * .5, 1.0)
			ci.draw_arc(sp, r + 2 * dpr + f * 14 * dpr, 0, TAU, 32, Color(wc, .9 * (1 - f) * gv), 1.8 * dpr, true)
	DotTex.draw(ci, DotTex.dot(), sp, r, Color(rgb, ((.35 + .65 * bl) if red and inc != null else 1.0) * gv))
	if inc != null and red and camera.dist < 16:
		_text_on(ci, "!", Vector2(sp.x - 2.5 * dpr, sp.y), int(round(9 * dpr)), Color(Color("#06121b"), gv))
	if j.n > 1 and camera.dist < 12:
		_text_on(ci, "×%d" % j.n, Vector2(sp.x + r + 3 * dpr, sp.y - r - 3 * dpr), int(round(9 * dpr)), Color(rgb, gv))
	if gv < 1 and camera.dist < 18:
		_text_on(ci, "GPS?", Vector2(sp.x + r + 3 * dpr, sp.y + r + 3 * dpr), int(round(8.5 * dpr)), Color(Color("#c9d4de"), gv))


## the trail of a trip on the ground or at sea: from the vehicle back along its route by len, through the
## route's own corners (points sampled at fixed steps cut the corners, and the cut slid along as the vehicle
## moved: the trail crawled like a worm), fading out towards its end
func _trail_path(j: Dictionary, s: float, len_: float, rgb: Color, gv: float, tp: PackedVector2Array, tc: PackedColorArray) -> Array:
	var sim := session.sim
	var c := sim.co_cum(j)
	var p: PackedFloat32Array = j.p
	var du: float = sim.CO_DU
	var s0 := maxf(0.0, s - len_)
	if s - s0 < 1e-6:
		return [tp, tc]
	var a := func(sv: float) -> Color: return Color(rgb, .75 * (1.0 - .9 * (s - sv) / len_) * gv)
	var here: int = sim.co_pos_at(j, s)[2]
	var n := 0
	for i in range(here, -1, -1):   # the corners behind the vehicle, newest first
		var si: float = c[i] * du
		if si >= s:
			continue
		if si <= s0 or n >= 48:
			break
		var q: Variant = _P(p[i * 2], 0, p[i * 2 + 1])
		if q == null:
			return [tp, tc]
		tp.append(q)
		tc.append(a.call(si))
		n += 1
	var e := sim.co_pos_at(j, s0)
	var q: Variant = _P(e[0], 0, e[1])
	if q != null:
		tp.append(q)
		tc.append(a.call(s0))
	return [tp, tc]


## every frame: what blinks and pulses (the trips of the last picture whose marker moves on its own, the
## selected trip's ring, attack marks)
func _draw_fx() -> void:
	if session == null or session.sim == null or camera == null:
		return
	var T0 := session.sim.co_now()
	var now := session.anim_t
	for it in _fx_items:
		var j: Dictionary = it.j
		var gv := _gps_vis(j, T0) if it.live else 1.0
		if gv <= 0:
			continue
		if it.tp != null:
			var tc: PackedColorArray = it.tc.duplicate()
			for i in tc.size():
				tc[i].a *= gv
			_fx.draw_polyline_colors(it.tp, tc, it.w, true)
		if it.sel:
			var f := fmod(now * 1.2, 1.0)
			_fx.draw_arc(it.sp, it.r + 3 * dpr + f * 10 * dpr, 0, TAU, 32, Color(it.rgb, (.9 - f * .9) * gv), 1.5 * dpr, true)
		if it.live:
			_marker(_fx, j, it.sp, it.r, it.rgb, it.inc, it.red, it.amb, gv)
	_marks()


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := i / 20.0 * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _text(s: String, pos: Vector2, fs: int, col: Color) -> void:
	_text_on(self, s, pos, fs, col)


func _text_on(ci: CanvasItem, s: String, pos: Vector2, fs: int, col: Color) -> void:
	var asc := F_MONO_B.get_ascent(fs)
	var desc := F_MONO_B.get_descent(fs)
	ci.draw_string(F_MONO_B, Vector2(pos.x, pos.y + (asc - desc) / 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


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
			draw_circle(e, 4 * dpr, Color(rgb, .25), true, -1.0, true)
			draw_arc(e, 4 * dpr, 0, TAU, 24, rgb, 2 * dpr, true)


## a dashed line anchored to the world: the pattern does not crawl when the camera moves (wdash)
func _wdash(pts: Array, col: Color, w: float) -> void:
	_wdash_on(self, pts, col, w)


func _wdash_on(n: CanvasItem, pts: Array, col: Color, w: float) -> void:
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
					n.draw_line(pa, pb, col, w, true)
				acc += e - s
				s = e
			else:
				var e := minf(L, s + maxf(per - ph, per * 1e-4))
				acc += e - s
				s = e


## attacks: a skull badge with a ring, bandits or pirates closing in for the first seconds (drawIncMarks)
func _marks() -> void:
	if not MapVis.vis("mark"):
		return
	var sim := session.sim
	var now := Clock.ms()
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
					_fx.draw_colored_polygon(boat, Color("#1a0808"))
					boat.append(boat[0])
					_fx.draw_polyline(boat, col, 1.4 * dpr, true)
				else:
					_dot_on(_fx, p, 3 * dpr, Color("#1a0808"), col, 1.4 * dpr)
		var f := fmod(now / 1000.0, 1.4) / 1.4
		_fx.draw_arc(c, (10 + f * 22) * dpr, 0, TAU, 40, Color(col, .9 * (1 - f)), 2 * dpr, true)
		var y: float = c.y - 20 * dpr
		var txt := I18n.t("ПІРАТИ" if m.k == "pir" else "НАПАД")
		var fs := int(round(9 * dpr))
		var tw := F_MONO_B.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 24 * dpr
		var r := Rect2(c.x - tw / 2, y - 9 * dpr, tw, 18 * dpr)
		_fx.draw_rect(r, Color(26 / 255.0, 6 / 255.0, 6 / 255.0, .92))
		_fx.draw_rect(r, col, false, 1.2 * dpr)
		Icons.draw(_fx, "skull", c.x - tw / 2 + 4 * dpr, y, 12 * dpr, col)
		_text_on(_fx, txt, Vector2(c.x - tw / 2 + 19 * dpr, y + .5 * dpr), fs, col)
