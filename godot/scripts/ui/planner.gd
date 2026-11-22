class_name Planner
extends Control
## The route planner (the panel and the map part of legacy/src/08q-planner.js, the landings of 08r-multi.js):
## the player clicks cities, road or rail points and checkpoints; every click adds a leg of the chosen kind
## of transport. The panel shows who carries the first leg, the legs, the transshipments and hub taxes, the
## time against the deadline, the cost, the profit and the risk, next to the dispatcher's own route.
## The calculations are Sim.lp_calc / lp_block / lp_go. Time stands still while the planner is open.

signal acted(res: Dictionary)
signal closed(reopen: String)    # the window to open after closing ("" — none)

const D = preload("res://scripts/logistics/game_data.gd")
const W = preload("res://scripts/ui/windows.gd")
const LP_C := {"road": Color8(52, 199, 89), "rail": Color8(236, 150, 92), "sea": Color8(110, 190, 255), "air": Color8(214, 150, 255)}
const LP_T := {"road": "truck", "rail": "train", "sea": "ship", "air": "plane"}
const LP_N := {"road": "Авто", "rail": "Залізниця", "sea": "Море", "air": "Авіа"}
const DEP := Color8(92, 200, 242)
const ARR := Color8(255, 214, 90)
const CRIT := Color8(240, 98, 95)

var map: MapView
var session: GameSession
var sim: Sim
var on := false
var LP := {}
var mode := "road"
var _prev_speed := 0
var _panel: PanelContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _draw_node: Control         # on the map's canvas, above the vehicles: the route
var _hover_w: Variant = null
var _hover_k := ""
var _tags: Array = []           # {pid, tag, col, extra}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
	visible = false
	_panel = Ui.glass()
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	_body = Ui.vbox(0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := Ui.margin(_body, 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(m)


func attach(s: GameSession, m: MapView) -> void:
	session = s
	sim = s.sim
	map = m
	if _draw_node == null:
		_draw_node = Control.new()
		_draw_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_draw_node.draw.connect(_draw_route)
		map.vehicles.get_parent().add_child(_draw_node)


# ====================================================================== open / close
## ACT.lpPlan: "" when opened, or why not
func open(k: Dictionary) -> String:
	if not k.get("multi"):
		var P := sim.co_plan(k)
		if not P.ok:
			return P.why
	LP = {"k": k, "pts": [k.from], "modes": [], "veh0": null, "byMgr": false}
	mode = k.mode
	on = true
	_prev_speed = session.speed
	session.set_speed(0)
	session.lock_speed = "Поки прокладаєш маршрут, час стоїть: відправ рейс за маршрутом або закрий планувальник"
	var A: Dictionary = sim.PL[k.from]
	var B: Dictionary = sim.PL[k.to]
	map.camera.ttx = (A.x + B.x) / 2
	map.camera.ttz = (A.z + B.z) / 2 + .3
	map.camera.tdist = clampf(Vector2(A.x - B.x, A.z - B.z).length() * 1.6 + 3, 3, map.camera.world_size.x * 1.1)
	visible = true
	_panel_build()
	return ""


func close(reopen: String = "") -> void:
	if not on:
		return
	on = false
	visible = false
	_tags = []
	session.lock_speed = ""
	if _prev_speed:
		session.set_speed(_prev_speed)
	_draw_node.queue_redraw()
	closed.emit(reopen)


func cancel() -> void:
	close("coJobs")


func undo() -> void:
	if LP.pts.size() > 1:
		LP.pts.pop_back()
		LP.modes.pop_back()
		_panel_build()


## ACT.lpAutoUse: the dispatcher's route as the plan
func auto_use() -> void:
	if not sim.CO.mgr.has("cto"):
		return
	var k: Dictionary = LP.k
	if k.get("cons"):
		LP.pts = sim.cons_auto_seq(k)
		LP.modes = LP.pts.slice(1).map(func(_x): return k.mode)
	elif k.get("legs"):
		LP.pts = [k.legs[0].a] + k.legs.map(func(L): return L.b)
		LP.modes = k.legs.map(func(L): return L.m)
	else:
		LP.pts = [k.from, k.to]
		LP.modes = [k.mode]
	LP.byMgr = true
	_panel_build()


func order(kind: String) -> void:
	LP.pts = sim.lp_order(LP.k, kind)
	LP.modes = LP.pts.slice(1).map(func(_x): return "air")
	LP.byMgr = false
	_panel_build()


## ACT.lpGo
func go() -> void:
	var C := sim.lp_calc(LP)
	if not C.done:
		return
	var b: Variant = sim.lp_block(LP, C)
	if b != null:
		acted.emit({"tone": "warn", "t": "Відправити не можна", "d": b})
		return
	var n: int = C.legs.size()
	var modes: String = " → ".join(C.legs.map(func(L): return LP_N[L.m]))
	var cons: bool = LP.k.get("cons") != null
	var why := sim.lp_go(LP, LP.byMgr)
	if why != "":
		acted.emit({"tone": "warn", "t": "Відправити не можна", "d": why})
		return
	close("coJobs")
	if cons:
		acted.emit({"tone": "good", "t": "Збірний рейс відправлено", "d": "%d %s · %d %s" % [LP.k.cons.size(), "замовлення", n, "ділянка" if n == 1 else "ділянки"]})
	else:
		acted.emit({"tone": "good", "t": "Рейс за вашим маршрутом", "d": "%d %s · %s" % [n, "ділянка" if n == 1 else "ділянки", modes]})


# ====================================================================== points
func _lock() -> Variant:
	var l: Variant = LP.pts.back()
	return LP.modes.back() if Sim.lp_is_w(l) else null


func _pt_ok(m: String, q: Variant) -> bool:
	if Sim.lp_is_w(q):
		return m == "road" or (m == "rail" and sim.board.rbits[q.v] != 0)
	return sim.lp_mode_ok(m, sim.PL[q])


## lpAdd
func add(q: Variant) -> void:
	var last: Variant = LP.pts.back()
	var lk: Variant = _lock()
	var m: String = lk if lk != null else mode
	if not sim.lp_unlocked(m):
		acted.emit({"tone": "warn", "t": "Немає ліцензії", "d": "%s: цей вид транспорту ще недоступний" % LP_N[m]})
		return
	if (not Sim.lp_is_w(q) and not Sim.lp_is_w(last) and q == last) or (Sim.lp_is_w(q) and Sim.lp_is_w(last) and q.v == last.v):
		return
	mode = m
	if not _pt_ok(m, last) or not _pt_ok(m, q):
		var bad: Variant = last if not _pt_ok(m, last) else q
		acted.emit({"tone": "warn", "t": "%s: немає %s" % [LP_N[m], "станції" if m == "rail" else ("порту" if m == "sea" else "аеропорту")], "d": sim.lp_name(bad)})
		return
	var r: Variant = sim.lp_seg(m, last, q)
	if r == null:
		acted.emit({"tone": "warn", "t": "Маршрут недоступний", "d": "%s не пройде між %s і %s: море, закритий кордон або негода" % [LP_N[m], sim.lp_name(last), sim.lp_name(q)]})
		return
	LP.pts.append(q)
	LP.modes.append(m)
	LP.byMgr = false
	_panel_build()


## lpCityAt: a label, or the nearest town within R px
func city_at(mp: Vector2, R: float) -> int:
	var lab := map.towns.place_at(mp)
	if lab >= 0:
		return lab
	var best := -1
	var bd := R
	for p in sim.PL:
		var q: Variant = _scr(p.x, 0, p.z)
		if q == null:
			continue
		var d: float = q.distance_to(mp)
		if d < bd:
			bd = d
			best = p.id
	return best


## lpPickW: the road (or rail) node under the pointer, a checkpoint when one is near
func pick_w(mp: Vector2, m: String) -> Variant:
	if m != "road" and m != "rail":
		return null
	var g: Variant = map.camera.pick_plane(mp)
	var g2: Variant = map.camera.pick_plane(mp + Vector2(16, 0))
	if g == null or g2 == null:
		return null
	var B: Dictionary = sim.board
	var st: float = B.st
	var R := maxf(st * .8, Vector2(g2.x - g.x, g2.z - g.z).length())
	var bits: PackedByteArray = B.rbits if m == "rail" else B.bits
	var cp: Variant = null
	var cd := R * 1.2
	for c in B.get("checkpoints", []):
		if bool(c.get("rail", false)) != (m == "rail"):
			continue
		var d := Vector2(c.x - g.x, c.z - g.z).length()
		if d < cd:
			cd = d
			cp = c
	var cx: float = cp.x if cp != null else g.x
	var cz: float = cp.z if cp != null else g.z
	var nx: int = B.nx
	var nz: int = B.nz
	var i0 := int(round((cx + B.wx / 2) / st))
	var j0 := int(round((cz + B.wz / 2) / st))
	var n := int(ceil(R / st)) + 1
	var best := -1
	var bd := 1e9
	for j in range(j0 - n, j0 + n + 1):
		for i in range(i0 - n, i0 + n + 1):
			if i < 0 or j < 0 or i >= nx or j >= nz:
				continue
			var v := j * nx + i
			if bits[v] == 0:
				continue
			var px: float = -B.wx / 2 + i * st
			var pz: float = -B.wz / 2 + j * st
			var d := Vector2(px - cx, pz - cz).length()
			if d < bd and d < R * 1.3:
				bd = d
				best = v
	if best < 0:
		return null
	var o := {"v": best, "x": -B.wx / 2 + (best % nx) * st, "z": -B.wz / 2 + (best / nx) * st}
	if cp != null:
		o.cp = 1
		if cp.a < sim.states.size() and cp.b < sim.states.size():
			o.cn = sim.states[cp.a].name + " – " + sim.states[cp.b].name
	return o


## a click on the map while planning
func click(mp: Vector2) -> void:
	var pid := city_at(mp, 18)
	if pid >= 0:
		add(pid)
		return
	var lk: Variant = _lock()
	var w: Variant = pick_w(mp, lk if lk != null else mode)
	if w != null:
		add(w)
	elif mode != "road" and mode != "rail" and lk == null:
		acted.emit({"tone": "", "t": "Проміжні точки — лише для авто і потяга", "d": "%s їде від міста до міста" % LP_N[mode]})


func _unhandled_key_input(e: InputEvent) -> void:
	if not on or not (e is InputEventKey) or not e.pressed:
		return
	if e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancel()
	elif e.keycode == KEY_Z and (e.ctrl_pressed or e.meta_pressed):
		get_viewport().set_input_as_handled()
		undo()


# ====================================================================== the panel
## lpVehList: who can start the route — idle in a hub, waiting after a delivery, or driving home — in the
## country of the first point
func _veh_list() -> Array:
	var k: Dictionary = LP.k
	if Sim.lp_is_w(LP.pts[0]):
		return []
	var m: String = k.mode if k.get("cons") else (LP.modes[0] if LP.modes.size() else mode)
	var cid: int = sim.PL[LP.pts[0]].cid
	var T := sim.co_now()
	return sim.CO.veh.filter(func(v): return D.VT[v.t].mode == m and not v.get("resv") \
		and ((v.st == "idle" and (sim.hub_at(v.loc) != null or (v.get("idle0") != null and T - v.idle0 < 1))) or sim.is_ret_v(v)) and sim.v_cid(v) == cid)


func _bar(v: float, mx: float, col: Color) -> Control:
	var m := W._meter(clampf(v / mx, .02, 1), col)
	return Ui.margin(m, 0, 4, 0, 0)


func _row(a: Control, b: Control) -> HBoxContainer:
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return Ui.hbox(8, [a, b])


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


func _panel_build() -> void:
	var vs := get_viewport_rect().size
	_panel.position = Vector2(14, 84)
	_panel.size = Vector2(minf(360, vs.x - 32), vs.y - 84 - 86)
	_scroll.custom_minimum_size = _panel.size
	var keep := _scroll.scroll_vertical
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_hover_k = ""
	var B := _body
	var CO := sim.CO
	var k: Dictionary = LP.k
	var C := sim.lp_calc(LP)
	var A: Variant = _auto() if CO.mgr.has("cto") else null
	var last_q: Variant = LP.pts.back()
	var lock: Variant = _lock()
	var dest: Dictionary = sim.PL[k.to]
	var risk_c: Color = Ui.BAD if C.risk > .35 else (Ui.WARN if C.risk > .15 else Ui.GOOD)
	var dl: Variant = null if k.get("multi") or k.get("cons") else k.dlDays
	var aT: Variant = A.P.tot if A != null and A.P != null and A.P.ok else null
	var aNet: Variant = A.P.profit if A != null and A.P != null and A.P.ok else null
	var aRisk: Variant = sim.lp_risk(A.r, k.mode).p if A != null and A.r != null else null
	# head
	var x := MapUi._xbtn(cancel)
	B.add_child(_row(Ui.hbox(8, [Ui.icon("road", 18, Ui.FG), W._b("Прокладання маршруту", 15)]), x))
	var sub: String
	if k.get("cons"):
		sub = "Збірний рейс · %d замовлення · %s т · %s м³ · %s · оплата до %s" % [k.cons.size(), Ui.loc(k.tons), Ui.loc(k.get("_vol", 0)), LP_N[k.mode].to_lower(), Ui.usd(k.pay)]
	else:
		sub = "%s, %s т · %s → %s · оплата %s" % [sim.cargo_i[k.cg].n, Ui.loc(k.tons), sim.PL[k.from].name, ("%d країни (збірний авіарейс)" % k.multi.size()) if k.get("multi") else dest.name, Ui.usd(k.pay)]
	B.add_child(Ui.margin(W._note(sub), 0, 4, 0, 0))
	# who starts
	var L := _veh_list()
	var m0: String = k.mode if k.get("cons") else (LP.modes[0] if LP.modes.size() else mode)
	if L.is_empty():
		B.add_child(Ui.margin(W._icl("alert", "У країні %s немає вільної техніки: %s" % [sim.states[sim.PL[LP.pts[0]].cid].name if not Sim.lp_is_w(LP.pts[0]) else "", String(D.MODE_N[m0]).to_lower()], Ui.WARN), 0, 10, 0, 0))
	else:
		B.add_child(Ui.margin(Ui.lbl("Хто їде · " + sim.states[sim.PL[LP.pts[0]].cid].name), 0, 10, 0, 6))
		var vl := Ui.vbox(4)
		var vb := W._btn("Найближча, що вміщує вантаж", "pri sm" if LP.veh0 == null else "sm", "cpu", func():
			LP.veh0 = null
			_panel_build())
		vb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vl.add_child(vb)
		for v in L.slice(0, 12):
			var T: Dictionary = D.VT[v.t]
			var stt: String = "повертається в хаб" if v.st == "trip" else ("у хабі" if sim.hub_at(v.loc) != null else "чекає після доставки")
			var vid: int = v.id
			var b := W._btn("%s · %s · %s · %s т / %s м³%s" % [T.n, sim.PL[v.loc].name, stt, Ui.loc(T.cap), Ui.loc(T.get("vol", 0)), (" · стан %.0f%%" % v.cond) if v.cond < 60 else ""], "pri sm" if LP.veh0 == vid else "sm", T.ic, func():
				LP.veh0 = vid
				_panel_build())
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			vl.add_child(b)
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size.y = minf(150, (L.slice(0, 12).size() + 1) * 32)
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(vl)
		B.add_child(sc)
	# the mode of the next leg
	B.add_child(Ui.margin(Ui.lbl("Транспорт наступної ділянки"), 0, 10, 0, 6))
	var segp := PanelContainer.new()
	segp.add_theme_stylebox_override("panel", Ui.box(Color.TRANSPARENT, Ui.LINE_HI))
	var seg := Ui.hbox(0)
	segp.add_child(seg)
	var ms := ["road", "rail", "sea", "air"]
	for i in ms.size():
		var m: String = ms[i]
		var ok: bool = sim.lp_unlocked(m) and (not k.get("cons") or m == k.mode) and ((m == lock) if lock != null else _pt_ok(m, last_q))
		var sel := mode == m
		var b := Button.new()
		b.text = LP_N[m]
		b.icon = Icons.tex(LP_T[m], Ui.ACCENT_INK if sel else Ui.FG2, 14, 1.8)
		b.add_theme_constant_override("icon_max_width", 14)
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size.y = 30
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not ok
		b.modulate.a = 1.0 if ok else .4
		var s := Ui.box(Ui.ACCENT if sel else Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector4(8, 0, 8, 0))
		s.border_color = Ui.LINE
		s.border_width_right = 0 if i == 3 else 1
		var hv := s.duplicate()
		if not sel:
			hv.bg_color = Ui.ACCENT_SOFT
		for st in ["normal", "disabled"]:
			b.add_theme_stylebox_override(st, s)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		for ck in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			b.add_theme_color_override(ck, Ui.ACCENT_INK if sel else Ui.FG2)
		b.pressed.connect(func():
			mode = m
			_panel_build())
		seg.add_child(b)
	B.add_child(segp)
	# what to do
	var goal: String
	if C.done:
		goal = "[color=#5bd492]✓ %s[/color]" % ("Маршрут охоплює всі замовлення" if k.get("cons") else ("Усі пункти охоплено" if k.get("multi") else "Маршрут доходить до " + dest.name))
	else:
		goal = "Клікніть місто, будь-яку ділянку дороги чи значок КПП — наступна точка. Ціль: [b]%s[/b]" % ("забрати й доставити всі замовлення — доставити можна лише те, що вже в кузові" if k.get("cons") else ("усі пункти збірного рейсу, останнім — пункт посадки" if k.get("multi") else dest.name))
		if lock != null:
			goal += "\nВи на дорозі: ділянка закінчується в місті, транспорт — %s." % LP_N[lock].to_lower()
	B.add_child(Ui.margin(Ui.rich(goal, 13), 0, 6, 0, 0))
	# the legs
	var lg := Ui.vbox(5)
	for Lg in C.legs:
		var bits := []
		if Lg.via.size():
			bits.append("через: " + ", ".join(Lg.via.map(func(v): return sim.lp_name(v))))
		bits.append(Ui.km(Lg.r.len))
		bits.append(Ui.days(Lg.time))
		bits.append(Ui.usd(Lg.cost))
		bits.append(Lg.get("veh") if Lg.get("veh") else ("власна техніка" if Lg.own else "партнер"))
		if Lg.risk.jam:
			bits.append("[color=#f0625f]перекриття %d[/color]" % Lg.risk.jam)
		if Lg.risk.wx:
			bits.append("негода")
		if Lg.risk.band:
			bits.append("бандити")
		if Lg.risk.pir:
			bits.append("пірати")
		if Lg.risk.cl:
			bits.append("[color=#f0625f]закритий кордон[/color]")
		lg.add_child(_leg_row(Lg.m, "%s → %s" % [sim.PL[Lg.a].name, sim.PL[Lg.b].name], " · ".join(bits)))
	if C.legs.is_empty() and C.tail == null:
		lg.add_child(W._note("Ще немає ділянок."))
	if C.tail != null:
		var tl: Dictionary = C.tail
		var r := _leg_row(tl.m, "%s → …" % sim.lp_name(LP.pts[LP.pts.size() - 1 - tl.via.size()]), "через: %s · %s · доведіть до міста" % [", ".join(tl.via.map(func(v): return sim.lp_name(v))), Ui.km(tl.r.len)])
		r.modulate.a = .8
		lg.add_child(r)
	if C.tr.size():
		var s := 0.0
		for f in C.tr:
			s += f
		lg.add_child(W._note("Перевантаження між видами транспорту: %d · %s" % [C.tr.size(), Ui.usd(s)]))
	if C.ht.size():
		var s := 0.0
		for h in C.ht:
			s += h.f
		var n := W._note("Податок за чужі хаби: %s · %s" % [", ".join(C.ht.map(func(h): return sim.PL[h.pid].name)), Ui.usd(s)], Ui.WARN)
		n.tooltip_text = W._tip("Податок за чужий хаб", "Перевантаження в місті, де у вас немає власного хаба: власник хаба бере податок — 4% від оплати замовлення плюс збір за вид транспорту. Відкрийте свій хаб у цьому місті, щоб не платити.")
		n.mouse_filter = Control.MOUSE_FILTER_STOP
		lg.add_child(n)
	B.add_child(Ui.margin(lg, 0, 10, 0, 0))
	if k.get("multi"):
		_drops(B, C)
	if k.get("cons"):
		_cons_plan(B, C)
	# the totals
	var tv := Ui.vbox(0)
	var cmp := func(v: float, a: Variant, lower_better: bool, txt: String) -> Control:
		var n := Ui.num(txt, 13)
		if a == null or C.legs.is_empty():
			return n
		var good: bool = v < a if lower_better else v > a
		return Ui.hbox(6, [n, Ui.label("диспетчер " + (Ui.days(a) if txt.ends_with("дн.") or txt.ends_with("год") or txt.ends_with("хв") else (("%d%%" % int(JS.round_js(a * 100))) if txt.ends_with("%") else Ui.usd(a, true))), 12, Ui.GOOD if good else Ui.BAD)])
	var t_txt: String = Ui.days(C.t) if C.legs.size() else "—"
	var tlbl: Control = cmp.call(C.t, aT, true, t_txt)
	if dl != null and C.t > dl and tlbl is Label:
		tlbl.add_theme_color_override("font_color", Ui.BAD)
	tv.add_child(_row(Ui.label("Орієнтовне прибуття", 14), tlbl))
	if dl != null:
		tv.add_child(_bar(C.t, dl * 1.3, Ui.BAD if C.t > dl else Ui.GOOD))
		var dn := "дедлайн " + Ui.days(dl)
		if C.legs.size():
			dn += (" · запас " + Ui.days(dl - C.t)) if C.t <= dl else (" · [color=#f0625f]запізнення %s[/color]" % Ui.days(C.t - dl))
		tv.add_child(Ui.rich(dn, 13))
	tv.add_child(_gap(8))
	tv.add_child(_row(Ui.label("Пальне, фрахт і збори", 14), Ui.num(Ui.usd(C.c), 13)))
	tv.add_child(_gap(8))
	var net: Control = cmp.call(C.net, aNet, false, Ui.usd(C.net, true) if C.legs.size() else "—")
	if net is Label:
		net.add_theme_color_override("font_color", Ui.GOOD if C.net >= 0 else Ui.BAD)
	elif net.get_child_count():
		net.get_child(0).add_theme_color_override("font_color", Ui.GOOD if C.net >= 0 else Ui.BAD)
	tv.add_child(_row(Ui.label("Чистий прибуток", 14), net))
	tv.add_child(_gap(8))
	var rk: Control = cmp.call(C.risk, aRisk, true, ("%d%%" % int(JS.round_js(C.risk * 100))) if C.legs.size() else "—")
	(rk if rk is Label else rk.get_child(0)).add_theme_color_override("font_color", risk_c)
	tv.add_child(_row(Ui.label("Ризик пошкодження", 14), rk))
	tv.add_child(_bar(C.risk, .6, risk_c))
	B.add_child(Ui.margin(W._blk(tv), 0, 10, 0, 0))
	if A != null:
		var dash := Control.new()
		dash.custom_minimum_size = Vector2(18, 10)
		dash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dash.draw.connect(func():
			for i in 3:
				dash.draw_line(Vector2(i * 7, 5), Vector2(i * 7 + 4, 5), Color(220 / 255.0, 230 / 255.0, 240 / 255.0, .55), 2))
		var at: String = ("%s · %s" % [Ui.days(aT), Ui.usd(aNet, true)]) if aT != null else (A.P.why if A.P != null else "недоступний")
		var al := W._note("Маршрут диспетчера-логіста: " + at)
		B.add_child(Ui.margin(Ui.hbox(6, [dash, al]), 0, 8, 0, 0))
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	acts.add_child(W._btn("Прибрати ділянку", "sm", "refresh", undo, LP.pts.size() > 1))
	if A != null:
		acts.add_child(W._btn("Маршрут від диспетчера", "sm", "cpu", auto_use))
	if k.get("multi"):
		acts.add_child(W._btn("Спершу ближчі", "sm", "mapIc", func(): order("near")))
		acts.add_child(W._btn("Спершу термінові", "sm", "alert", func(): order("urg")))
	B.add_child(Ui.margin(acts, 0, 10, 0, 0))
	var blk: Variant = sim.lp_block(LP, C)
	if blk != null:
		B.add_child(Ui.margin(W._icl("lock", blk, Ui.BAD), 0, 10, 0, 0))
	var gb := W._btn("Відправити за маршрутом", "pri", "send", go, C.done and blk == null)
	gb.size_flags_horizontal = Control.SIZE_FILL
	B.add_child(Ui.margin(gb, 0, 10, 0, 0))
	_restore(keep)
	# the blocks over the map: departure and arrival
	_tags = []
	if k.get("multi"):
		for d in k.multi:
			_tags.append({"pid": d.to, "tag": "ПОСАДКА · КРИТИЧНО" if d.get("crit") else "ПОСАДКА", "col": CRIT if d.get("crit") else ARR, "extra": "≤ " + Ui.days(d.dl)})
	elif not k.get("cons"):
		_tags.append({"pid": k.to, "tag": "ПРИБУТТЯ", "col": ARR})
	if not k.get("cons"):
		_tags.append({"pid": k.from if Sim.lp_is_w(LP.pts[0]) else LP.pts[0], "tag": "ВІДПРАВЛЕННЯ", "col": DEP})


func _restore(v: int) -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = v


func _leg_row(m: String, title: String, sub: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(8, 6, 8, 6)))
	var i := Ui.icon(LP_T[m], 18, LP_C[m])
	var v := Ui.vbox(2, [W._b(title, 13), Ui.rich(sub, 12)])
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(Ui.hbox(10, [i, v]))
	return p


## lpDropsHTML: the landings of a multi-drop flight in the order of the route
func _drops(B: VBoxContainer, C: Dictionary) -> void:
	var k: Dictionary = LP.k
	var by := {}
	var drops: Array = C.get("drops", []) if C.get("drops") != null else []
	for i in drops.size():
		by[drops[i].d.to] = i
	var L: Array = k.multi.duplicate()
	L.sort_custom(func(a, b):
		var ia: int = by.get(a.to, 99)
		var ib: int = by.get(b.to, 99)
		return ia < ib or (ia == ib and a.dl < b.dl))
	B.add_child(Ui.margin(Ui.lbl("Пункти посадки"), 0, 10, 0, 6))
	var v := Ui.vbox(4)
	for d in L:
		var p: Dictionary = sim.PL[d.to]
		var x: Variant = drops[by[d.to]] if by.has(d.to) else null
		var n := Ui.num(str(by[d.to] + 1) if x != null else "·", 13, LP_C.air if x != null else Ui.MUTED)
		n.custom_minimum_size.x = 18
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var t := "%s т · термін %s · %s" % [Ui.loc(d.tons), Ui.days(d.dl), Ui.usd(d.pay)]
		if x != null:
			t += " · прибуття %s %s" % [Ui.days(x.eta), ("[color=#f0625f]запізнення %s[/color]" % Ui.days(x.late)) if x.late > 0 else "[color=#5bd492]вчасно[/color]"]
		else:
			t += " · ще не в маршруті"
		var head := Ui.hbox(6, [MapUi._left(_flag(p.cid)), W._b(p.name, 13)])
		if d.get("crit"):
			head.add_child(Ui.label("критично", 12, Ui.BAD))
		var c := Ui.vbox(2, [head, Ui.rich(t, 12)])
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(8, 5, 8, 5)))
		row.add_child(Ui.hbox(10, [n, c]))
		v.add_child(row)
	B.add_child(v)


## consPlanHTML: the orders of a consolidated trip, picked up, on board or delivered along the route
func _cons_plan(B: VBoxContainer, C: Dictionary) -> void:
	var v := Ui.vbox(5, [Ui.lbl("Замовлення збірного рейсу")])
	var veh: Variant = null
	for x in sim.CO.veh:
		if x.id == LP.get("consVeh", -1):
			veh = x
	if veh != null:
		var T: Dictionary = D.VT[veh.t]
		v.add_child(W._icl(T.ic, "%s · кузов %s т / %s м³ · найбільше завантаження %s т / %s м³" % [T.n, Ui.loc(T.cap), Ui.loc(T.get("vol", 0)), Ui.loc(C.maxT, 1), Ui.loc(C.maxV, 1)], Ui.FG2, 12))
	var blk: bool = C.get("consBlock") != null
	if blk:
		v.add_child(W._icl("alert", "Вантаж не вміщується — маршрут не можна відправити", Ui.BAD, 12))
	for r in C.get("rows", []):
		var o: Dictionary = r.o
		var ic: String = "pin" if blk else ("check" if r.dropped else ("box" if r.picked else "pin"))
		var left := W._icl(ic, "%s → %s · %s т" % [sim.PL[o.from].name, sim.PL[o.to].name, Ui.loc(o.tons)], Ui.FG2, 12)
		left.get_child(0).modulate = Ui.GOOD if r.dropped and not blk else Color.WHITE
		var st: String
		var col := Ui.FG2
		if blk:
			st = "не вміщується"
			col = Ui.BAD
		elif r.dropped:
			if r.late > 0:
				st = "запізнення " + Ui.days(r.late)
				col = Ui.BAD
			else:
				st = Ui.days(r.eta) + " · вчасно"
				col = Ui.GOOD
		else:
			st = "у кузові" if r.picked else "ще не забрано"
		var right := Ui.hbox(0, [Ui.label(st, 12, col), Ui.label(" · ≤ " + Ui.days(o.dl), 12, Ui.FG2)])
		v.add_child(_row(left, right))
	B.add_child(Ui.margin(W._blk(v), 0, 10, 0, 0))


func _flag(cid: int) -> ColorRect:
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(14, 10)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.color = Color(sim.states[cid].color)
	return sw


## lpAuto: the dispatcher's plan and route
func _auto() -> Variant:
	var k: Dictionary = LP.k
	if k.get("multi"):
		return null
	if k.get("cons"):
		return {"P": null, "r": null}
	return {"P": sim.co_plan(k), "r": sim.co_route(k.mode, k.from, k.to)}


# ====================================================================== drawing
func _process(_delta: float) -> void:
	if not on:
		return
	_draw_node.queue_redraw()
	queue_redraw()


func _scr(x: float, y: float, z: float) -> Variant:
	var cam: Camera3D = map.camera
	var p := Vector3(x, y, z)
	if cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)


func _path(r: Dictionary, m: String) -> Array:
	var pts := []
	var p: PackedFloat32Array = r.p
	if m == "air":
		var H := clampf(r.len / sim.CO_DU * .22, .05, .9)
		for i in 41:
			var t := i / 40.0
			pts.append(Vector3(lerpf(p[0], p[p.size() - 2], t), sin(PI * t) * H, lerpf(p[1], p[p.size() - 1], t)))
	else:
		for i in range(0, p.size(), 2):
			pts.append(Vector3(p[i], 0, p[i + 1]))
	return pts


func _poly(n: Control, pts: Array, col: Color, w: float) -> void:
	var cur := PackedVector2Array()
	for q in pts:
		var s: Variant = _scr(q.x, q.y, q.z)
		if s == null:
			if cur.size() > 1:
				n.draw_polyline(cur, col, w, true)
			cur = PackedVector2Array()
			continue
		cur.append(s)
	if cur.size() > 1:
		n.draw_polyline(cur, col, w, true)


func _wave(n: Control, p: Dictionary, col: Color) -> void:
	var q: Variant = _scr(p.x, 0, p.z)
	if q == null:
		return
	var t := Time.get_ticks_msec() / 1100.0
	for w in 3:
		var f := fmod(t + w / 3.0, 1.0)
		n.draw_arc(q, 6 + f * 26, 0, TAU, 40, Color(col, .95 * (1 - f)), 2.4 * (1 - f * .5), true)
	n.draw_circle(q, 6.1, Color("#06121b"))
	n.draw_circle(q, 4.5, col)


## lpDraw: the legs in the colour of their transport, the preview to the point under the pointer, the points,
## the departure and arrival waves
func _draw_route() -> void:
	if not on:
		return
	var n := _draw_node
	for i in range(1, LP.pts.size()):
		var r: Variant = sim.lp_seg(LP.modes[i - 1], LP.pts[i - 1], LP.pts[i])
		if r != null:
			var pts := _path(r, LP.modes[i - 1])
			_poly(n, pts, Color(6 / 255.0, 12 / 255.0, 18 / 255.0, .7), 5)
			_poly(n, pts, LP_C[LP.modes[i - 1]], 3)
	# the preview to what is under the pointer
	var mp := get_viewport().get_mouse_position()
	if get_viewport().gui_get_hovered_control() == null:
		var lk: Variant = _lock()
		var m: String = lk if lk != null else mode
		var last: Variant = LP.pts.back()
		var t: Variant = city_at(mp, 22)
		if t == -1:
			var key := "%d,%d%s%d" % [mp.x, mp.y, m, LP.pts.size()]
			if _hover_k != key:
				_hover_k = key
				_hover_w = pick_w(mp, m)
			t = _hover_w
		if t != null and not (not Sim.lp_is_w(t) and not Sim.lp_is_w(last) and t == last) and _pt_ok(m, t) and _pt_ok(m, last):
			var r: Variant = sim.lp_seg(m, last, t)
			if r != null:
				var pts := _path(r, m)
				map.vehicles._wdash_on(n, pts, Color(LP_C[m], .85), 2.4)
				var e: Variant = _scr(pts.back().x, pts.back().y, pts.back().z)
				if e != null:
					n.draw_circle(e, 4, Color(LP_C[m], .25))
					n.draw_arc(e, 4, 0, TAU, 24, Color(LP_C[m], .85), 2, true)
			if Sim.lp_is_w(t):
				var q: Variant = _scr(t.x, 0, t.z)
				if q != null:
					n.draw_circle(q, 6.25, LP_C[m])
					n.draw_circle(q, 3.75, Color.WHITE)
					var s := sim.lp_name(t)
					var f := Ui.font("body", 600)
					var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
					n.draw_rect(Rect2(q.x + 9, q.y - 9, w + 10, 18), Color(6 / 255.0, 12 / 255.0, 18 / 255.0, .82))
					n.draw_string(f, Vector2(q.x + 14, q.y + 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	for i in LP.pts.size():
		var pid: Variant = LP.pts[i]
		var p: Dictionary = pid if Sim.lp_is_w(pid) else sim.PL[pid]
		var q: Variant = _scr(p.x, 0, p.z)
		if q == null:
			continue
		if Sim.lp_is_w(pid):
			n.draw_circle(q, 5.25, LP_C[LP.modes[i - 1]])
			n.draw_circle(q, 2.75, Color.WHITE)
			continue
		if i == 0:
			continue
		n.draw_circle(q, 6.5, Color("#06121b"))
		n.draw_circle(q, 5.5, LP_C[LP.modes[i - 1]])
	var k: Dictionary = LP.k
	if k.get("cons"):
		for o in k.cons:
			_wave(n, sim.PL[o.from], DEP)
			_wave(n, sim.PL[o.to], ARR)
		return
	for t in _tags:
		_wave(n, sim.PL[t.pid], t.col)


## lpTags: the departure and arrival blocks above the towns, with a leader and a ring
func _draw() -> void:
	if not on:
		return
	draw_tags(self, _tags)


func draw_tags(n: CanvasItem, tags: Array) -> void:
	var placed := []
	var f1 := Ui.font("mono", 700)
	var f2 := Ui.font("body", 700)
	for t in tags:
		var p: Dictionary = sim.PL[t.pid]
		var q: Variant = _scr(p.x, 0, p.z)
		if q == null:
			continue
		var top: String = ("%s · %s" % [t.tag, sim.states[p.cid].name]).to_upper()
		var ex: String = t.get("extra", "")
		var w1 := f1.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + top.length() * .54
		var w2 := 18 + 6 + f2.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + (f1.get_string_size(ex, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8 if ex != "" else 0.0)
		var w := maxf(w1, w2) + 20 + 3
		var h := 3 + 4 + 13 + 17 + 6.0
		var bx: float = q.x - w / 2
		var by: float = q.y - h - 20
		for _i in 6:
			if not placed.any(func(b): return bx < b[2] and bx + w > b[0] and by < b[3] and by + h > b[1]):
				break
			by -= h + 6
		placed.append([bx, by, bx + w, by + h])
		var col: Color = t.col
		n.draw_line(Vector2(q.x, by + h), Vector2(q.x, q.y - 9), Color(col, .9), 1.6, true)
		n.draw_circle(q, 9, Color(col, .22))
		n.draw_arc(q, 9, 0, TAU, 32, Color(col, .9), 2.4, true)
		for k in 3:
			n.draw_rect(Rect2(bx, by + 6, w, h).grow(3 + k * 4), Color(0, 0, 0, .1))
		n.draw_rect(Rect2(bx, by, w, h), Color(8 / 255.0, 18 / 255.0, 28 / 255.0, .95))
		n.draw_rect(Rect2(bx, by, w, 3), col)
		n.draw_rect(Rect2(bx + .75, by + .75, w - 1.5, h - 1.5), col, false, 1.5)
		var x := bx + 10
		n.draw_string(f1, Vector2(x, by + 3 + 4 + 9), top, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
		var y2 := by + 3 + 4 + 13 + 13
		n.draw_rect(Rect2(x, y2 - 10, 18, 12), Color(sim.states[p.cid].color))
		n.draw_rect(Rect2(x, y2 - 10, 18, 12), Color(1, 1, 1, .35), false, 1)
		n.draw_string(f2, Vector2(x + 24, y2), p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		if ex != "":
			n.draw_string(f1, Vector2(x + 24 + f2.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 8, y2), ex, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
