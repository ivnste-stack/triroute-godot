class_name Course
extends Control
## Changing the course of a trip under way (the panel and the map part of SR in legacy/src/08r-multi.js):
## ships through points at sea, trucks through road points and checkpoints, planes through any point; with
## «Оминати небезпеку» the course goes around pirates, bandits, bad weather and closures by itself. The panel
## compares the new course with the current one: arrival, distance, checkpoints, extra fuel and risk.
## The calculations are Sim.sr_calc / sr_go. Time stands still while the panel is open.

signal acted(res: Dictionary)
signal closed

const D = preload("res://scripts/logistics/game_data.gd")
const W = preload("res://scripts/ui/windows.gd")
const SR_N := {"sea": {"w": "Судно", "where": "по морю", "pt": "точка в морі", "bad": "Через ці точки судно не пройде: суходіл."},
	"road": {"w": "Вантажівка", "where": "по дорогах або значках КПП", "pt": "точка на дорозі", "bad": "Через ці точки немає проїзду: дорогу перекрито."},
	"air": {"w": "Літак", "where": "будь-де на мапі", "pt": "точка курсу", "bad": "Курс не прокласти: закрите небо."}}

var map: MapView
var session: GameSession
var sim: Sim
var planner: Planner             # the map helpers (pick_w, the tags) and the canvas
var on := false
var j: Dictionary = {}
var m := "road"
var pts: Array = []
var avoid := false
var _prev_speed := 0
var _panel: PanelContainer
var _body: VBoxContainer
var _draw_node: Control
var _hk := ""
var _hq: Variant = null
var _hp: Variant = null
var _calc: Dictionary = {}
var _calc_k := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
	visible = false
	_panel = Ui.glass()
	add_child(_panel)
	_body = Ui.vbox(0)
	_panel.add_child(Ui.margin(_body, 14))


func attach(s: GameSession, mv: MapView, pl: Planner) -> void:
	session = s
	sim = s.sim
	map = mv
	planner = pl
	if _draw_node == null:
		_draw_node = Control.new()
		_draw_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_draw_node.draw.connect(_draw_course)
		map.vehicles.get_parent().add_child(_draw_node)


## srOpen: "" when opened, or why not
func open(job: Dictionary) -> String:
	if not sim.sr_ok(job):
		return "%s не в дорозі або затриманий" % SR_N.get(job.mode, {"w": "Транспорт"}).w
	j = job
	m = job.mode
	pts = []
	avoid = false
	on = true
	_prev_speed = session.speed
	session.set_speed(0)
	session.lock_speed = "Поки змінюєш курс, час стоїть: зміни курс або закрий панель"
	var q: Array = sim.sr_now(j).pos
	var B: Dictionary = sim.PL[j.k.to]
	map.camera.ttx = (q[0] + B.x) / 2
	map.camera.ttz = (q[1] + B.z) / 2 + .3
	map.camera.tdist = clampf(Vector2(q[0] - B.x, q[1] - B.z).length() * 1.5 + 3, 3, map.camera.world_size.x * 1.1)
	visible = true
	_build()
	return ""


func close() -> void:
	if not on:
		return
	on = false
	visible = false
	session.lock_speed = ""
	if _prev_speed:
		session.set_speed(_prev_speed)
	_draw_node.queue_redraw()
	closed.emit()


func undo() -> void:
	if pts.size():
		pts.pop_back()
		_build()


func _c() -> Dictionary:
	var key := ";".join(pts.map(func(q): return "%f,%f" % [q.x, q.z])) + str(avoid) + str(j.t0) + ":%.3f" % sim.co_now()
	if key != _calc_k:
		_calc_k = key
		_calc = sim.sr_calc(j, pts, avoid)
	return _calc


## ACT.srGo
func go() -> void:
	var C := _c()
	if C.get("bad"):
		return
	var T: Dictionary = D.VT[j.t]
	var lead := sim.sr_lead_now(j)
	var extra: float = C.extra
	var eta: float = C.eta
	var why := sim.sr_go(j, pts, avoid)
	if why != "":
		acted.emit({"tone": "warn", "t": "Курс змінити не можна", "d": why})
		return
	close()
	var fuel := (" · пальне +" + Ui.usd(extra)) if extra > 0 else ""
	if lead:
		acted.emit({"tone": "good", "t": "Перегін змінено", "d": "%s: до %s через %s%s" % [T.n, sim.PL[j.k.from].name, Ui.days(j.tl), fuel]})
	else:
		acted.emit({"tone": "good", "t": "Курс змінено", "d": "%s: прибуття через %s%s" % [T.n, Ui.days(eta), fuel]})


## srPick: a water cell for ships, a road node (or checkpoint) for trucks, any point for planes
func pick(mp: Vector2) -> Variant:
	if m == "road":
		return planner.pick_w(mp, "road")
	var g: Variant = map.camera.pick_plane(mp)
	if g == null:
		return null
	if m == "sea":
		var B: Dictionary = sim.board
		var st: float = B.st
		var Wn: int = B.nx - 1
		var Hn: int = B.nz - 1
		var i := int(floor((g.x + B.wx / 2) / st))
		var k := int(floor((g.z + B.wz / 2) / st))
		if i < 0 or k < 0 or i >= Wn or k >= Hn:
			return null
		var x0: float = -B.wx / 2 + i * st
		var z0: float = -B.wz / 2 + k * st
		for uv in [[.25, .25], [.75, .25], [.25, .75], [.75, .75], [.5, .5]]:
			if sim.gen.state_at(x0 + uv[0] * st, z0 + uv[1] * st) >= 0:
				return null
		return {"x": x0 + .5 * st, "z": z0 + .5 * st, "c": k * Wn + i}
	return {"x": g.x, "z": g.z}


func click(mp: Vector2) -> void:
	var q: Variant = pick(mp)
	if q == null:
		acted.emit({"tone": "warn", "t": "Тут суходіл" if m == "sea" else "Тут немає дороги", "d": "Точка курсу має бути в морі" if m == "sea" else "Клікніть по дорозі або значку КПП"})
		return
	pts.append(q)
	_build()


func _unhandled_key_input(e: InputEvent) -> void:
	if not on or not (e is InputEventKey) or not e.pressed:
		return
	if e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
	elif e.keycode == KEY_Z and (e.ctrl_pressed or e.meta_pressed):
		get_viewport().set_input_as_handled()
		undo()


static func _risk_txt(r: Dictionary) -> String:
	var a := []
	if r.get("pir"):
		a.append("пірати %d" % r.pir)
	if r.get("band"):
		a.append("бандити %d" % r.band)
	if r.get("wx"):
		a.append("негода %d" % r.wx)
	if r.get("jam"):
		a.append("перекриття %d" % r.jam)
	if r.get("cl"):
		a.append("закриті кордони %d" % r.cl)
	return ", ".join(a) if a.size() else "чисто"


func _cmp(a: float, b: float) -> Color:
	return Ui.GOOD if a < b - .005 else (Ui.BAD if a > b + .005 else Ui.FG)


func _row(l: String, v: String, col: Color, now: String = "") -> HBoxContainer:
	var a := Ui.label(l, 14)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r := Ui.hbox(6, [Ui.num(v, 13, col)])
	if now != "":
		r.add_child(Ui.label("зараз " + now, 12, Ui.FG2))
	return Ui.hbox(8, [a, r])


func _build() -> void:
	if not on:
		return
	var vs := get_viewport_rect().size
	_panel.position = Vector2(14, 84)
	_panel.custom_minimum_size = Vector2(minf(360, vs.x - 32), 0)
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var B := _body
	var T: Dictionary = D.VT[j.t]
	var C := _c()
	var dest: Dictionary = sim.PL[j.k.to]
	var cg: Dictionary = sim.cargo_i[j.k.cg]
	var N: Dictionary = SR_N[m]
	var t := Ui.hbox(8, [Ui.icon(Planner.LP_T[m], 18), W._b("Зміна курсу", 15)])
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	B.add_child(Ui.hbox(8, [t, MapUi._xbtn(close)]))
	B.add_child(Ui.margin(W._note("%s%s · %s, %s т · до %s" % [T.n, (" ×%d" % j.n) if j.get("n", 1) > 1 else "", cg.n, Ui.loc(j.k.tons), dest.name]), 0, 4, 0, 0))
	var legend: String = "червоні кола — пірати, сині — шторми" if m == "sea" else ("червоні кола — бандити, сині — негода; з «Оминати небезпеку» маршрут обходить і перекриті дороги" if m == "road" else "сині кола — негода; закрите небо літак обходить сам")
	B.add_child(Ui.margin(W._note("Клікайте %s — точки нового курсу. Пунктир — поточний курс; %s." % [N.where, legend]), 0, 8, 0, 0))
	var pv := Ui.vbox(4)
	for i in pts.size():
		var q: Dictionary = pts[i]
		var tx: String = sim.lp_name(q) if q.get("cp") else N.pt
		if not q.get("cp"):
			var c: int = sim.gen.state_at(q.x, q.z)
			if c >= 0:
				tx += " · " + sim.cnm(c)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(8, 5, 8, 5)))
		row.add_child(Ui.hbox(10, [Ui.num(str(i + 1), 13, Planner.LP_C[m]), W._note(tx)]))
		pv.add_child(row)
	if pts.is_empty():
		pv.add_child(W._note("Курс прокладено автоматично в обхід небезпеки." if avoid else "Точок ще немає — новий курс іде прямо до %s." % dest.name))
	B.add_child(Ui.margin(pv, 0, 8, 0, 0))
	if C.get("bad"):
		B.add_child(Ui.margin(W._icl("alert", N.bad, Ui.BAD), 0, 8, 0, 0))
	else:
		var v := Ui.vbox(0)
		v.add_child(_row("Прибуття", Ui.days(C.eta), _cmp(C.eta, C.curEta), Ui.days(C.curEta)))
		v.add_child(Ui.margin(W._meter(clampf(C.eta / (maxf(maxf(C.dl, C.eta), .1) * 1.2), .02, 1), Ui.BAD if C.eta > C.dl else Ui.GOOD), 0, 4, 0, 0))
		v.add_child(Ui.rich("дедлайн через %s%s" % [Ui.days(maxf(0, C.dl)), (" · [color=#f0625f]запізнення %s[/color]" % Ui.days(C.eta - C.dl)) if C.eta > C.dl else ""], 13))
		v.add_child(Ui.margin(_row("Відстань", Ui.km(C.len), Ui.FG, Ui.km(C.oldLen)), 0, 8, 0, 0))
		if m == "road" and C.get("cps", []).size():
			v.add_child(Ui.margin(_row("Пункти пропуску", "%d · %s" % [C.cps.size(), Ui.days(C.wait)], Ui.FG), 0, 8, 0, 0))
		v.add_child(Ui.margin(_row("Додаткове пальне", Ui.usd(C.extra) if C.extra > 0 else "—", Ui.FG), 0, 8, 0, 0))
		v.add_child(Ui.margin(_row("Ризик", "%d%%" % int(JS.round_js(C.risk.p * 100)), _cmp(C.risk.p, C.oldRisk.p), "%d%%" % int(JS.round_js(C.oldRisk.p * 100))), 0, 8, 0, 0))
		v.add_child(W._note("на новому курсі: %s · на поточному: %s" % [_risk_txt(C.risk), _risk_txt(C.oldRisk)]))
		B.add_child(Ui.margin(W._blk(v), 0, 10, 0, 0))
	var acts := Ui.hbox(6, [W._btn("Прибрати точку", "sm", "refresh", undo, pts.size() > 0), W._btn("Оминати небезпеку", "pri sm" if avoid else "sm", "shield", func():
		avoid = not avoid
		_build())])
	B.add_child(Ui.margin(acts, 0, 10, 0, 0))
	var gb := W._btn("Змінити курс", "pri", Planner.LP_T[m], go, not C.get("bad", false))
	gb.size_flags_horizontal = Control.SIZE_FILL
	B.add_child(Ui.margin(gb, 0, 10, 0, 0))
	_panel.size = Vector2.ZERO
	_panel.reset_size()


# ====================================================================== drawing
func _process(_delta: float) -> void:
	if not on:
		return
	if not sim.CO.jobs.any(func(x): return is_same(x, j)):
		close()
		return
	_panel.size = _panel.get_combined_minimum_size()
	_draw_node.queue_redraw()
	queue_redraw()


func _line(n: Control, p: Array, col: Color, w: float, dash: bool = false) -> void:
	var cur := PackedVector2Array()
	var segs := []
	for i in range(0, p.size(), 2):
		var q: Variant = planner._scr(p[i], 0, p[i + 1])
		if q == null:
			if cur.size() > 1:
				segs.append(cur)
			cur = PackedVector2Array()
			continue
		cur.append(q)
	if cur.size() > 1:
		segs.append(cur)
	for s in segs:
		if dash:
			for k in range(1, s.size()):
				n.draw_dashed_line(s[k - 1], s[k], col, w, 6.0, true)
		else:
			n.draw_polyline(s, col, w, true)


func _draw_course() -> void:
	if not on:
		return
	var n := _draw_node
	for z in sim.sr_danger(m):
		var c: Variant = planner._scr(z.x, 0, z.z)
		var e: Variant = planner._scr(z.x + z.r, 0, z.z)
		if c == null or e == null:
			continue
		var r: float = c.distance_to(e)
		var red: bool = z.k != "wx"
		var col := Color8(240, 98, 95) if red else Color8(110, 170, 255)
		n.draw_circle(c, r, Color(col, .16), true, -1.0, true)
		n.draw_arc(c, r, 0, TAU, 64, Color(col, .8), 1.5, true)
	var C := _c()
	_line(n, C.N.rem, Color(220 / 255.0, 230 / 255.0, 240 / 255.0, .6), 2, true)
	if C.get("np") != null:
		_line(n, C.np, Color(6 / 255.0, 12 / 255.0, 18 / 255.0, .7), 5)
		_line(n, C.np, Planner.LP_C[m], 3)
	var mp := get_viewport().get_mouse_position()
	if get_viewport().gui_get_hovered_control() == null:
		var k := "%d:%d:%d%s" % [int(mp.x / 4), int(mp.y / 4), pts.size(), avoid]
		if _hk != k:
			_hk = k
			_hq = pick(mp)
			_hp = sim.sr_seg(m, pts.back() if pts.size() else sim.sr_start(j, C.N), _hq, avoid) if _hq != null else null
		if _hp != null:
			_line(n, _hp, Color(Planner.LP_C[m], .8), 2, true)
		if _hq != null:
			var s: Variant = planner._scr(_hq.x, 0, _hq.z)
			if s != null:
				n.draw_circle(s, 5.75, Planner.LP_C[m], true, -1.0, true)
				n.draw_circle(s, 3.25, Color.WHITE, true, -1.0, true)
	for q in pts:
		var s: Variant = planner._scr(q.x, 0, q.z)
		if s != null:
			n.draw_circle(s, 6.5, Color("#06121b"), true, -1.0, true)
			n.draw_circle(s, 5.5, Planner.LP_C[m], true, -1.0, true)
	var s0: Variant = planner._scr(C.N.pos[0], 0, C.N.pos[1])
	if s0 != null:
		n.draw_circle(s0, 8.5, Planner.LP_C[m], true, -1.0, true)
		n.draw_circle(s0, 5.5, Color.WHITE, true, -1.0, true)
	# departure and arrival: blinking waves, as in the planner
	planner._wave(n, sim.PL[j.k.from], Planner.DEP)
	planner._wave(n, sim.PL[j.k.to], Planner.ARR)


## the departure and arrival blocks (lpTags)
func _draw() -> void:
	if not on:
		return
	pass   # the waves on the map show departure and arrival
