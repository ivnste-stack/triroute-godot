class_name MapUi
extends Control
## What the map answers to the pointer (08e-company.js, 08f-incidents.js, 08g-business.js of the HTML version):
##  · a hover card (#coTip): a settlement (placeTip), the city couriers of a hub, a group of vehicles, a road
##    closure, a closed border or port, a weather / bandit / pirate zone (zoneTip);
##  · the card of a country or a settlement on the right (#insp, coInsp): facts, risk, firms, your hubs there,
##    the towns with «open a hub» / «upgrade»;
##  · the card of a trip next to its vehicle (#ucard, coCard), the camera follows the vehicle.
## Clicks: a vehicle → its trip card; a label or a town → the settlement card; elsewhere → the country card.

signal acted(res: Dictionary)
signal open_window(id: String)
signal ask(spec: Dictionary)      # a dialog of ModalLayer
signal reroute(j: Dictionary)     # «Змінити курс» in the trip card

const D = preload("res://scripts/logistics/game_data.gd")
const W = preload("res://scripts/ui/windows.gd")
const TYPE_N := {"cap": "Столиця", "big": "Велике місто", "city": "Середнє місто", "town": "Мале місто", "vil": "Мале місто"}
const RISK_N := [["Низький", "good"], ["Помірний", "warn"], ["Високий", "bad"], ["Дуже високий", "bad"]]
const LP_N := {"road": "авто", "rail": "залізниця", "sea": "море", "air": "авіа"}

var map: MapView
var planner: Planner   # while it is open, the clicks place the points of the route
var course: Course     # the same for a new course of a trip under way
var session: GameSession
var sim: Sim
var follow := false             # CO.follow: the camera follows the selected vehicle
var sel_c := -1                 # UI.sel: the country of the card
var sel_p := -1                 # UI.selP: the settlement of the card

var _tip: PanelContainer
var _tip_key := ""
var _insp: PanelContainer
var _insp_body: VBoxContainer
var _insp_title: Label
var _insp_sub: Label
var _insp_ic: Control
var _insp_scroll: ScrollContainer
var _card: PanelContainer
var _card_t := 0.0
var _land_n := {}
var _risk_q := []
var _risk_k := ""
var _rng := RandomNumberGenerator.new()
var _day := -1.0
var mv_v: Variant = null         # MV: the vehicle being re-based
var mv_ts: Array = []
var _mv_node: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
	# the hover card
	_tip = Ui.glass(Ui.GLASS_HI, Ui.LINE_HI)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	add_child(_tip)
	# the card of a country / settlement
	_insp = Ui.glass()
	_insp.visible = false
	add_child(_insp)
	var col := Ui.vbox(0)
	_insp.add_child(col)
	_insp_title = Ui.label("", 19, Ui.FG, Ui.font("display", 600, .6))
	_insp_title.clip_text = true
	_insp_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_insp_sub = Ui.label("", 13, Ui.FG2)
	_insp_sub.clip_text = true
	_insp_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_insp_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	_insp_sub.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_insp_sub.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: show_country(sel_c))
	_insp_ic = Control.new()
	_insp_ic.custom_minimum_size = Vector2(30, 20)
	_insp_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_insp_ic.draw.connect(_draw_insp_icon)
	var tt := Ui.vbox(2, [_insp_title, _insp_sub])
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Ui.hbox(10, [_insp_ic, tt, _xbtn(close_insp)])
	col.add_child(Ui.margin(head, 14, 14, 4, 10))
	var sep := ColorRect.new()
	sep.color = Ui.LINE
	sep.custom_minimum_size.y = 1
	col.add_child(sep)
	_insp_scroll = SmoothScroll.new()
	# no sideways scrolling: the card is as wide as what it shows (at least 330) and stands at the right edge,
	# so nothing is cut off on the right
	_insp_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_insp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_insp_scroll)
	_insp_body = Ui.vbox(10)
	_insp_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := Ui.margin(_insp_body, 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_scroll.add_child(m)
	# the trip card
	_card = Ui.glass()
	_card.visible = false
	_card.custom_minimum_size.x = 290
	add_child(_card)


func attach(s: GameSession, m: MapView) -> void:
	session = s
	sim = s.sim
	map = m
	_land_names()
	if not map.camera.clicked.is_connected(_on_click):
		map.camera.clicked.connect(_on_click)
		map.camera.dragged.connect(_on_drag)


static func _xbtn(cb: Callable) -> Button:
	return Ui.xbtn(cb)


## CO_LN: names of the continents and islands, the biggest first
func _land_names() -> void:
	_land_n = {}
	var cnt := {}
	var st := {}
	for p in sim.PL:
		cnt[p.land] = cnt.get(p.land, 0) + 1
		if not st.has(p.land):
			st[p.land] = {}
		st[p.land][p.cid] = 1
	var LN := ["Аркадія", "Борея", "Велесія", "Гелона", "Дарінія", "Етерра", "Зоряна", "Ілірія", "Корана", "Лютея", "Мірія", "Норвія"]
	var IS := ["Вітрів", "Чайок", "Скель", "Мусонів", "Рифів", "Туманів"]
	var R_ := func(n: int) -> String: return "" if n < 1 else " " + ["II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][mini(8, n - 1)]
	var keys: Array = cnt.keys()
	keys.sort_custom(func(a, b): return cnt[a] > cnt[b] or (cnt[a] == cnt[b] and a < b))
	var k := 0
	var ki := 0
	for l in keys:
		if cnt[l] >= 8 or st[l].size() >= 2:
			_land_n[l] = LN[k % LN.size()] + R_.call(k / LN.size())
			k += 1
		else:
			_land_n[l] = "Острів " + IS[ki % 6] + R_.call(ki / 6)
			ki += 1


## riskLvl: the quartiles of coRisk over all countries, kept for a month
func _risk_lvl(cid: int) -> int:
	var key := "%d:%d" % [int(sim.day / 30), sim.CO.get("conf", []).size()]
	if _risk_k != key:
		var v := []
		for i in sim.states.size():
			v.append(sim.co_risk(i))
		v.sort()
		var q := func(f: float) -> float: return v[mini(v.size() - 1, int(floor(f * v.size())))]
		_risk_q = [q.call(.3), q.call(.65), q.call(.88)]
		_risk_k = key
	var r := sim.co_risk(cid)
	return 3 if r > _risk_q[2] else (2 if r > _risk_q[1] else (1 if r > _risk_q[0] else 0))


static func _fmt_pop(m: float) -> String:
	return ("%.2f млрд" % (m / 1000)) if m >= 1000 else (("%.0f млн" % m) if m >= 10 else ("%.1f млн" % m))


## dayDate: the date and hour of a moment of the game
func _day_date(t: float) -> String:
	var d: Dictionary = sim.date.duplicate()
	var n := int(floor(t) - sim.day)
	var dim := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	while n > 0:
		d.d += 1
		if d.d > dim[d.m]:
			d.d = 1
			d.m += 1
			if d.m > 11:
				d.m = 0
				d.y += 1
		n -= 1
	var h := int(floor(fposmod(t, 1.0) * 24))
	return "%d %s, %02d:00" % [d.d, Ui.MONTHS_FULL[d.m], h]


func _flag(cid: int, w: float = 18, h: float = 12) -> Control:
	return Flags.rect(sim.states[cid], w, h)


# ====================================================================== frame
func _process(_delta: float) -> void:
	Perf.begin("map_ui._process")
	_process_t(_delta)
	Perf.end("map_ui._process")


func _process_t(_delta: float) -> void:
	if sim == null:
		return
	if mv_v != null:
		_mv_node.queue_redraw()
	if prev_k != null:
		_pv_node.queue_redraw()
	_follow()
	_place_card()
	if _card.visible and Time.get_ticks_msec() - _card_t > 700:
		_build_card()
	if _insp.visible and sim.day != _day:
		_day = sim.day
		_build_insp(true)
	_hover()


func _over_ui() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null


# ====================================================================== hover card
func _hover() -> void:
	var mp := get_viewport().get_mouse_position()
	if _over_ui() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not visible:
		_show_tip("", null, mp)
		return
	# incidents on the map
	var best: Variant = null
	var bd := 1e9
	for L in [map.inc_base, map.inc_top]:
		for h in L.hits:
			var d := Vector2(h.x, h.y).distance_to(mp)
			if d < h.r and d < bd:
				bd = d
				best = h
	if best != null:
		_show_tip("inc:%s:%d" % [best.kind, int(best.x * 7 + best.y)], func(): return _inc_tip(best), mp, 340)
		return
	if (planner != null and planner.on) or (course != null and course.on) or mv_v != null:
		_show_tip("", null, mp)
		return
	var pid := map.towns.place_at(mp)
	if pid >= 0:
		_show_tip("pl:%d" % pid, func(): return _place_tip(sim.PL[pid]), mp)
		return
	var w: Variant = map.camera.pick_plane(mp)
	if w != null:
		var z: Variant = _zone_tip(w)
		if z != null:
			_show_tip("zone:" + z[0], func(): return z[1], mp, 340)
			return
	_show_tip("", null, mp)


var _tip_settle := 0


func _show_tip(key: String, build: Variant, mp: Vector2, width: float = 0) -> void:
	if key == "":
		_tip.visible = false
		_tip_key = ""
		return
	if key != _tip_key:
		_tip_key = key
		for c in _tip.get_children():
			if not (c is ColorRect):
				_tip.remove_child(c)
				c.queue_free()
		var content: Control = build.call()
		var m := Ui.margin(content, 12, 10)
		_tip.add_child(m)
		_tip.custom_minimum_size.x = width if width > 0 else 280
		# wrapped text knows its height only after a layout pass: show the card once its size has settled
		_tip.modulate.a = 0
		_tip_settle = 2
	_tip.visible = true
	if _tip_settle > 0:
		_tip_settle -= 1
		if _tip_settle == 0:
			_tip.modulate.a = 1
	_tip.size = _tip.get_combined_minimum_size()
	var w := _tip.size.x
	var h := _tip.size.y
	var x := mp.x + 18
	var y := mp.y - h / 2
	if x + w > size.x - 10:
		x = mp.x - w - 18
	y = clampf(y, 70, size.y - h - 10)
	_tip.position = Vector2(x, y)


static func _row_sp(a: Control, b: Control, gap: int = 14) -> HBoxContainer:
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return Ui.hbox(gap, [a, b])


static func _sep_top(c: Control, pad: int = 7) -> MarginContainer:
	var v := Ui.vbox(pad)
	var l := ColorRect.new()
	l.color = Ui.LINE
	l.custom_minimum_size.y = 1
	v.add_child(l)
	v.add_child(c)
	return Ui.margin(v, 0, pad - 2, 0, 0)


## placeTip: a settlement under the pointer
func _place_tip(p: Dictionary) -> Control:
	var h: Variant = sim.hub_at(p.id)
	var F: Array = sim.firms_of(p.id)
	var s: Dictionary = sim.node_spec(p)
	var v := Ui.vbox(2)
	v.add_child(_row_sp(W._b(p.name, 13), Ui.label("%s · %s" % [TYPE_N.get(p.type, "Поселення"), sim.states[p.cid].name], 12, Ui.FG2)))
	var pop := "Населення " + Ui.people(p.pop)
	if h != null:
		pop += " · [color=#f1c453]%s%s[/color]" % [D.HUB_LV[h.lvl], " · штаб" if p.id == sim.CO.hq else ""]
	v.add_child(Ui.rich(pop, 12))
	if p.get("rail") or p.get("port") != null or p.get("air"):
		var iv := Ui.vbox(3)
		if p.get("rail"):
			iv.add_child(W._icl("check", "залізнична станція", Ui.GOOD, 12))
		if p.get("port") != null:
			iv.add_child(W._icl("check", "порт%s%s" % [", рефконтейнери" if s.get("reefer") else "", ", балкери" if s.get("deep") else ""], Ui.GOOD, 12))
		if p.get("air"):
			iv.add_child(W._icl("check", "аеропорт%s" % (", важкі літаки" if s.get("heavy") else ""), Ui.GOOD, 12))
		v.add_child(_sep_top(iv))
	if F.size():
		var fv := Ui.vbox(4, [Ui.lbl("Підприємства · %d" % F.size())])
		for f in F.slice(0, 3):
			fv.add_child(Ui.hbox(6, [Ui.icon(D.IND[f.ind].ic, 14, Ui.MUTED), Ui.label(f.n, 13), Ui.label(String(D.IND[f.ind].n).to_lower(), 12, Ui.FG2)]))
		if F.size() > 3:
			fv.add_child(Ui.label("і ще %d · клік — подробиці" % (F.size() - 3), 12, Ui.FG2))
		v.add_child(_sep_top(fv))
	return v


## the city couriers of a hub, or a group of vehicles on the streets
## the hover text of a road closure, a closed border or checkpoint, a closed port or airport
func _inc_tip(h: Dictionary) -> Control:
	var v := Ui.vbox(4)
	var T_ := sim.co_now()
	match h.kind:
		"jam":
			var J: Dictionary = h.data
			var K: Dictionary = D.RCK[0]
			for x in D.RCK:
				if x.k == J.kind:
					K = x
			var pl: bool = J.t0 > T_
			v.add_child(W._icl(K.ic, "Плановий ремонт дороги" if J.kind == "repair" else K.n, Ui.FG, 13))
			v.get_child(0).get_child(0).modulate = Ui.MUTED if pl else (Ui.BAD if J.sev > 1 else Ui.WARN)
			v.get_child(0).get_child(1).add_theme_font_override("font", Ui.font("body", 600))
			if not pl:
				v.add_child(W._note(K.d, Ui.FG2, 12))
			if pl:
				v.add_child(Ui.rich("[b]Заплановано:[/b] з %s до %s (почнеться через %s). Поки що рух вільний." % [_day_date(J.t0), _day_date(J.until), Ui.days(J.t0 - T_)], 12))
			else:
				v.add_child(W._note("Дорогу перекрито%s · відкриють через %s. Техніка стоятиме тут до відкриття — прокладіть маршрут в об'їзд." % [(" до " + _day_date(J.until)) if J.kind == "repair" else "", Ui.days(maxf(0, J.until - T_))], Ui.FG2, 12))
		"cl":
			var cl: Dictionary = h.data
			var c: Dictionary = h.get("cp", cl)
			var ttl: String = "Пункт пропуску закрито" if cl.kind == "cp" else ("Кордон закрито" if cl.kind == "pair" else "%s закрила кордони" % sim.cnm(cl.a))
			v.add_child(W._icl("lock", ttl, Ui.BAD, 13))
			v.add_child(W._note("%s · %s → %s" % ["Залізничний перехід" if c.get("rail") else "Автомобільний пункт пропуску", sim.cnm(c.a), sim.cnm(c.b)], Ui.FG2, 12))
			v.add_child(_sep_top(Ui.rich("Причина: [b]%s[/b]" % cl.why, 13, Ui.FG)))
			v.add_child(W._note("Машини їдуть через сусідні пункти пропуску." if cl.kind == "cp" else ("Закриті всі переходи між цими країнами: лише об'їзд через інші держави." if cl.kind == "pair" else "Не можна в'їхати чи виїхати; порти й аеропорти теж закрито."), Ui.FG2, 12))
			v.add_child(_row_sp(Ui.label("Відкриття через", 12, Ui.FG2), Ui.num("≈ " + Ui.days(maxf(0, cl.until - T_)), 13, Ui.WARN)))
		"port":
			var d: Dictionary = h.data
			var sea: bool = d.what == "anchor"
			v.add_child(W._icl(d.what, "%s %s закрито" % ["Порт" if sea else "Аеропорт", d.place.name], Ui.BAD, 13))
			v.add_child(_sep_top(Ui.rich("Причина: [b]%s[/b]" % d.why, 13, Ui.FG)))
			v.add_child(W._note("Судна чекають на рейді, нові морські рейси звідси й сюди не відправляються." if sea else "Вильоти й посадки скасовано, нові авіарейси недоступні.", Ui.FG2, 12))
	return v


static func _wx_cl(K: Dictionary) -> String:
	var a := []
	var slow: Dictionary = K.get("slow", {})
	if K.get("road"):
		a.append("закрито дороги")
	elif slow.get("road"):
		a.append("сповільнено рух дорогами")
	if K.get("rail"):
		a.append("закрито залізницю")
	elif slow.get("rail"):
		a.append("сповільнено потяги")
	if K.get("sea"):
		a.append("закрито порти")
	if K.get("air"):
		a.append("закрито аеропорти")
	return ", ".join(a)


## zoneTip: weather, bandits, pirates under the pointer → [key, card] or null
func _zone_tip(w: Vector3) -> Variant:
	var CO := sim.CO
	var T := sim.co_now()
	for i in CO.get("wx", []).size():
		var z: Dictionary = CO.wx[i]
		if Vector2(w.x - z.x, w.z - z.z).length() < z.r:
			var K: Dictionary = D.WXK[z.k]
			var pl: bool = z.t0 > T
			var c: Array = String(K.col).split(",")
			var col := Color8(150, 160, 172) if pl else Color8(int(c[0]), int(c[1]), int(c[2]))
			var v := Ui.vbox(6, [Ui.hbox(8, [Ui.icon(K.ic, 16, col), W._b(K.n, 13), Ui.label(("біля " + z.near) if z.get("near") else "", 12, Ui.FG2)])])
			v.add_child(W._note("%s%s." % ["Прогноз синоптиків: негода ще не почалась, рух поки вільний. Коли почнеться: " if pl else "Зараз: ", _wx_cl(K)], Ui.FG2, 12))
			v.add_child(Ui.hbox(8, [Ui.label("Почнеться через" if pl else "Закінчиться через", 12, Ui.FG2), Ui.num("≈ " + Ui.days(maxf(0, (z.t0 if pl else z.until) - T)), 13, Ui.WARN)]))
			if pl:
				v.add_child(Ui.hbox(8, [Ui.label("Триватиме", 12, Ui.FG2), Ui.num("≈ " + Ui.days(z.until - z.t0), 13)]))
			return ["wx%d%s" % [i, pl], v]
	for i in CO.get("band", []).size():
		var z: Dictionary = CO.band[i]
		if Vector2(w.x - z.x, w.z - z.z).length() < z.r:
			var v := Ui.vbox(6, [Ui.hbox(8, [Ui.icon("skull", 16, Color("#ff8c3c")), W._b("Зона бандитів", 13), Ui.label(z.get("name", ""), 12, Ui.FG2)]),
				W._note("На дорогах діє банда: ризик пограбування вантажівок і потягів уп'ятеро вищий. Директор з безпеки знижує ризик.", Ui.FG2, 12),
				Ui.hbox(8, [Ui.label("Банду знешкодять через", 12, Ui.FG2), Ui.num("≈ " + Ui.days(maxf(0, z.until - T)), 13, Ui.WARN)])])
			return ["band%d" % i, v]
	for i in CO.get("pir", []).size():
		var z: Dictionary = CO.pir[i]
		if Vector2(w.x - z.x, w.z - z.z).length() < z.r:
			var v := Ui.vbox(6, [Ui.hbox(8, [Ui.icon("skull", 16, Ui.BAD), W._b("Зона піратства", 13), Ui.label(z.get("name", ""), 12, Ui.FG2)]),
				W._note("Судна в цих водах можуть захопити заради викупу. Директор з безпеки знижує ризик.", Ui.FG2, 12)])
			return ["pir%d" % i, v]
	return null


# ====================================================================== clicks
func _on_click(mp: Vector2) -> void:
	if sim == null or _over_ui():
		return
	if mv_v != null:
		_mv_click(mp)
		return
	if planner != null and planner.on:
		planner.click(mp)
		return
	if course != null and course.on:
		course.click(mp)
		return
	# a vehicle
	# where the vehicles are now, not where they were drawn the frame before: at a high speed a moving
	# one is a few pixels further on and the click would miss it
	var jh: Variant = null
	var bd := 16.0
	var T := sim.co_now()
	for h in map.vehicles.hits:
		if h.has("j"):
			var j: Dictionary = h.j
			var e: float = T - j.t0
			var st := sim.co_job_state(j, minf(e, j.tl + j.hs + j.tm * .5) if j.get("hold", 0) > 0 else e)
			var pos := sim.co_pos_at(j, st.s)
			var w := Vector3(pos[0], sim.co_alt(j, st), pos[1])
			var sp := Vector2(h.x, h.y) if map.camera.is_position_behind(w) else map.camera.unproject_position(w)
			var d := minf(sp.distance_to(mp), Vector2(h.x, h.y).distance_to(mp))
			if d < bd:
				bd = d
				jh = h
	if jh != null:
		select_job(jh.j)
		return
	var pid := map.towns.place_at(mp)
	if pid >= 0:
		show_place(pid)
		return
	# the nearest settlement within 16 px
	var best := -1
	var bdd := 16.0
	for p in sim.PL:
		var q: Variant = _screen(p.x, p.z)
		if q == null:
			continue
		var d: float = q.distance_to(mp)
		if d < bdd:
			bdd = d
			best = p.id
	if best >= 0:
		show_place(best)
		return
	var w: Variant = map.camera.pick_plane(mp)
	var k: int = map.state_at(w) if w != null else -1
	if k < 0:
		close_insp()
	else:
		show_country(k)


func _on_drag() -> void:
	if follow and map.vehicles.selected != null:
		follow = false
		acted.emit({"tone": "", "t": "Камера більше не стежить", "d": "Клікніть на транспорт ще раз, щоб стежити"})


func _screen(x: float, z: float) -> Variant:
	var cam: Camera3D = map.camera
	var p := Vector3(x, 0, z)
	if cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)


# ====================================================================== an order on the map (coShow, CO_PREV)
var prev_k: Variant = null       # the board order whose A and B pulse on the map
var _pv_node: Control
signal prev_gone


func show_order(k: Variant) -> void:
	prev_k = k
	if _pv_node == null:
		_pv_node = Control.new()
		_pv_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pv_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pv_node.draw.connect(_pv_draw)
		map.vehicles.get_parent().add_child(_pv_node)
	_pv_node.queue_redraw()
	if k == null:
		return
	var A: Dictionary = sim.PL[k.from]
	var B: Dictionary = sim.PL[k.to]
	var cam := map.camera
	cam.ttx = (A.x + B.x) / 2
	cam.ttz = (A.z + B.z) / 2 + .3
	cam.tdist = clampf(Vector2(A.x - B.x, A.z - B.z).length() * 1.5 + 3, 3, cam.world_size.x * 1.1)


func _pv_draw() -> void:
	if prev_k == null:
		return
	if not sim.CO.board.any(func(x): return is_same(x, prev_k)):
		prev_k = null
		prev_gone.emit()
		return
	planner._wave(_pv_node, sim.PL[prev_k.from], Planner.DEP)
	planner._wave(_pv_node, sim.PL[prev_k.to], Planner.ARR)


# ====================================================================== re-basing a vehicle (08w-move.js)
func move_start(v: Dictionary) -> void:
	mv_v = v
	mv_ts = sim.mv_targets(v)
	if _mv_node == null:
		_mv_node = Control.new()
		_mv_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_mv_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mv_node.draw.connect(_mv_draw)
		map.vehicles.get_parent().add_child(_mv_node)
	acted.emit({"tone": "", "t": "%s: оберіть новий хаб" % D.VT[v.t].n, "d": "Клікніть на підсвічене місто. Esc — скасувати."})


func move_cancel(say: bool = true) -> void:
	if mv_v == null:
		return
	mv_v = null
	mv_ts = []
	_mv_node.queue_redraw()
	if say:
		acted.emit({"tone": "", "t": "Переміщення скасовано", "d": ""})


func _mv_click(mp: Vector2) -> void:
	if not sim.CO.veh.any(func(x): return is_same(x, mv_v)):
		move_cancel(false)
		return
	var best: Variant = null
	var bd := 26.0
	for t in mv_ts:
		var p: Dictionary = sim.PL[t.pid]
		var q: Variant = _screen(p.x, p.z)
		if q == null:
			continue
		var d: float = q.distance_to(mp)
		if d < bd:
			bd = d
			best = t
	if best == null:
		acted.emit({"tone": "warn", "t": "Оберіть хаб", "d": "Клікніть на підсвічене місто з хабом. Esc — скасувати."})
		return
	if best.why != "":
		acted.emit({"tone": "warn", "t": sim.PL[best.pid].name, "d": best.why})
		return
	var v: Dictionary = mv_v
	move_cancel(false)
	acted.emit(sim.act_move(v, best.pid))


func _unhandled_key_input(e: InputEvent) -> void:
	if mv_v != null and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		move_cancel()


func _mv_draw() -> void:
	if mv_v == null:
		return
	var n := _mv_node
	var f := fmod(Time.get_ticks_msec() / 1000.0 * .8, 1.0)
	var font := Ui.font("mono", 700)
	for t in mv_ts:
		var p: Dictionary = sim.PL[t.pid]
		var q: Variant = _screen(p.x, p.z)
		if q == null:
			continue
		var ok: bool = t.why == ""
		var col := Color8(92, 200, 242) if ok else Color8(150, 160, 172)
		if ok:
			n.draw_arc(q, 10 + f * 22, 0, TAU, 40, Color(col, 1 - f), 2, true)
		n.draw_circle(q, 8.75, Color("#0b1520"), true, -1.0, true)
		n.draw_circle(q, 8, col, true, -1.0, true)
		Icons.draw(n, "updown", q.x - 5, q.y, 10, Color("#0b1520"))
		var txt: String = p.name if ok else "%s · %s" % [p.name, t.why]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 12
		var r := Rect2(q.x - tw / 2, q.y + 12, tw, 17)
		n.draw_rect(r, Color(8 / 255.0, 18 / 255.0, 28 / 255.0, .9))
		n.draw_rect(r, Color(col, .9), false, 1)
		n.draw_string(font, Vector2(q.x - tw / 2 + 6, q.y + 24.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	var vp: Dictionary = sim.PL[sim.mv_from(mv_v)]
	var s: Variant = _screen(vp.x, vp.z)
	if s != null:
		n.draw_circle(s, 5.75, Color("#0b1520"), true, -1.0, true)
		n.draw_circle(s, 5, Color("#ffb347"), true, -1.0, true)


# ====================================================================== the trip card
func select_job(j: Dictionary, fly: bool = false) -> void:
	map.vehicles.selected = j
	follow = true
	if fly:
		var st := sim.co_job_state(j, sim.day - j.t0)
		var q := sim.co_pos_at(j, st.s)
		map.camera.ttx = q[0]
		map.camera.ttz = q[1] + .3
		map.camera.tdist = minf(map.camera.tdist, 6)
	_build_card()


func ask_cancel(j: Dictionary) -> void:
	var c := sim.cancel_info(j)
	ask.emit({"icon": "alert", "tone": "warn", "eyebrow": "Скасування рейсу", "title": "Скасувати рейс №%d?" % j.id,
		"body": "Замовлення у вас уже %s. Замовник виставить штраф [b]%s[/b], рейтинг знизиться на [b]%.2f[/b]. Що довше вантаж у вас, то дорожче скасування." % [Ui.days(c.held), Ui.usd(c.fine), c.rat],
		"hint": "Техніка розвернеться й поїде до найближчого хабу.",
		"choices": [{"t": "Скасувати рейс", "d": "Штраф %s · рейтинг −%.2f" % [Ui.usd(c.fine), c.rat], "f": func():
			if is_same(map.vehicles.selected, j):
				close_card()
			acted.emit(sim.act_cancel(j))},
			{"t": "Продовжити рейс", "d": "Нічого не змінювати", "hl": 1, "f": func(): pass}]})


func close_card() -> void:
	map.vehicles.selected = null
	follow = false
	_card.visible = false


func _follow() -> void:
	var j: Variant = map.vehicles.selected
	if j == null:
		if _card.visible:
			_card.visible = false
		return
	if not sim.CO.jobs.any(func(x): return is_same(x, j)):
		close_card()
		return
	if follow:
		var T := sim.co_now()
		var st := sim.co_job_state(j, minf(T - j.t0, j.tl + j.hs + j.tm * .5) if j.get("hold", 0) > 0 else T - j.t0)
		var q := sim.co_pos_at(j, st.s)
		if q.size() >= 2 and is_finite(q[0]) and is_finite(q[1]):
			map.camera.ttx = q[0]
			map.camera.ttz = q[1]
		else:
			follow = false


## placeUnitCard: next to its vehicle, on the side away from the screen edge
func _place_card() -> void:
	if not _card.visible:
		return
	var j: Variant = map.vehicles.selected
	var ms := _card.get_combined_minimum_size()
	_card.size = ms
	for h in map.vehicles.hits:
		if h.has("j") and is_same(h.j, j):
			var w := _card.size.x
			var hh := _card.size.y
			var lx: float = h.x + 22
			if lx + w > size.x - 12:
				lx = h.x - w - 22
			_card.position = Vector2(lx, clampf(h.y - hh / 2, 70, size.y - hh - 90))
			return


func _build_card() -> void:
	var j: Variant = map.vehicles.selected
	if j == null:
		return
	build_card_for(j)


## the card of a trip into _card (also used by the tests for every trip)
func build_card_for(j: Dictionary) -> void:
	_card_t = Time.get_ticks_msec()
	for c in _card.get_children():
		if not (c is ColorRect):
			_card.remove_child(c)
			c.queue_free()
	var T: Dictionary = D.VT[j.t]
	var ret: bool = j.get("ret", false)
	var cg: Dictionary = {"n": "Повернення в хаб", "val": 0} if ret else sim.cargo_i[j.k.cg]
	var back: bool = j.get("back", false)
	var A: Dictionary = sim.PL[j.k.to if back else j.k.from]
	var B: Dictionary = sim.PL[j.k.from if back else j.k.to]
	var e: float = sim.co_now() - j.t0
	var st := sim.co_job_state(j, e)
	var left := maxf(0, j.tot - e)
	var prog := clampf(e / j.tot, 0, 1)
	var late_by: float = sim.co_now() + left - j.dl
	var rows := []
	if ret:
		rows = [["Техніка", T.n], ["Рейс", "Порожній, повернення в хаб"], ["Відстань", Ui.km(j.len)], ["Етап", st.ph]]
	else:
		rows.append(["Техніка", T.n + ((" ×%d" % j.n) if j.get("n", 1) > 1 else "")])
		rows.append(["Вантаж", "%s, %s т" % [cg.n, Ui.loc(j.k.tons)]])
		if j.get("lp") and j.lp.plan.legs.size() > 1:
			var legs: Array = j.lp.plan.legs
			rows.append(["Маршрут", "ділянка %d з %d: %s" % [j.lp.i + 1, legs.size(), " → ".join(PackedStringArray(legs.map(func(L): return LP_N[L.m])))]])
		if j.k.get("fs"):
			rows.append(["Відправник", j.k.fs])
			rows.append(["Отримувач", j.k.ft])
		rows.append(["Вартість вантажу", Ui.usd(j.k.tons * cg.val)])
		rows.append(["Оплата", Ui.usd(j.k.pay)])
		rows.append(["Відстань", Ui.km(j.lead + j.len)])
		if j.get("hold", 0) > 0:
			rows.append(["Етап", "Захоплено піратами" if j.get("seized") else "Затримано", Ui.BAD])
		elif st.get("inc") != null:
			rows.append(["Етап", st.ph, Ui.BAD if SimIncidents.INC_RED.has(st.inc.k) else Ui.WARN])
		else:
			rows.append(["Етап", st.ph])
		rows.append(["Термін", "запізнення %.1f дн." % late_by, Ui.BAD] if late_by > .05 else ["Термін", "встигаємо", Ui.GOOD])
	if j.get("dmg", 0) > .02:
		rows.append(["Пошкодження", "%.0f%%" % (j.dmg * 100), Ui.WARN])
	if j.get("lost"):
		rows.append(["Вантаж", "втрачено", Ui.BAD])
	rows.append(["Прибуття через", Ui.days(left)])
	# head
	var ic := PanelContainer.new()
	ic.custom_minimum_size = Vector2(40, 40)
	ic.add_theme_stylebox_override("panel", Ui.box(Ui.ACCENT))
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ic.add_child(Ui.icon(T.ic, 22, Ui.ACCENT_INK))
	var tt := Ui.vbox(3, [Ui.lbl("%s · %s" % [sim.CO.name, D.MODE_N[j.mode]]), Ui.label("Рейс №%d" % j.id, 14, Ui.FG, Ui.font("display", 600)), Ui.label(cg.n, 13, Ui.FG2)])
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Ui.hbox(12, [ic, tt, _xbtn(close_card)])
	var col := Ui.vbox(0, [Ui.margin(head, 12, 12, 12, 10)])
	var sep := ColorRect.new()
	sep.color = Ui.LINE
	sep.custom_minimum_size.y = 1
	col.add_child(sep)
	var body := Ui.vbox(12)
	# the route
	var rt := PanelContainer.new()
	rt.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(10, 10, 10, 10)))
	rt.add_child(Ui.vbox(2, [Ui.hbox(8, [_flag(A.cid, 24, 16), Ui.label(A.name, 14)]), _left(Ui.margin(Ui.icon("down", 14, Ui.MUTED), 4, 0, 0, 0)), Ui.hbox(8, [_flag(B.cid, 24, 16), Ui.label(B.name, 14)])]))
	body.add_child(rt)
	# the vehicle and its hold: empty on the way to the cargo, filling while it loads, full on the road,
	# emptying while it unloads
	var nv: int = j.get("n", 1)
	var load := 0.0
	var ltxt := ""
	if not ret:
		var lw: float = j.k.tons / maxf(.01, T.cap * nv)
		var lv: float = sim.k_vol(j.k) / maxf(.01, T.get("vol", 1e9) * nv) if T.get("vol", 0) else 0.0
		load = clampf(maxf(lw, lv), 0, 1)
		ltxt = "%s т з %s т%s" % [Ui.loc(j.k.tons), Ui.loc(T.cap * nv), (" · %s м³ з %s м³" % [Ui.loc(sim.k_vol(j.k)), Ui.loc(T.vol * nv)]) if T.get("vol", 0) else ""]
	var ph := 0.0
	var hs: float = j.get("hs", 0.0)
	var tl: float = j.get("tl", 0.0)
	if ret or e < tl:
		ph = 0.0
	elif hs > 0 and e < tl + hs:
		ph = (e - tl) / hs
	elif hs > 0 and e > j.tot - hs:
		ph = clampf((j.tot - e) / hs, 0, 1)
	else:
		ph = 1.0
	var vd := VehicleDiagram.make(j.t, load * ph)
	var vbox := Ui.vbox(4, [vd])
	if ltxt != "":
		var cap := Ui.label("Завантаження %d%% · %s%s" % [int(round(load * 100)), ltxt, (" · ×%d" % nv) if nv > 1 else ""], 12, Ui.FG2)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap.custom_minimum_size.x = 240   # a wrapped label without a width is one letter wide for a frame
		vbox.add_child(cap)
	var vp := PanelContainer.new()
	vp.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(10, 8, 10, 8)))
	vp.add_child(vbox)
	body.add_child(vp)
	var kv := GridContainer.new()
	kv.columns = 2
	kv.add_theme_constant_override("h_separation", 12)
	kv.add_theme_constant_override("v_separation", 6)
	for r in rows:
		var k := Ui.label(r[0], 13, Ui.FG2)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kv.add_child(k)
		var vv := Ui.label(r[1], 12, r[2] if r.size() > 2 else Ui.FG, Ui.font("mono", 500))
		vv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vv.custom_minimum_size.x = 150
		kv.add_child(vv)
	body.add_child(kv)
	var pr := Ui.vbox(6, [_row_sp(Ui.lbl("Маршрут" if ret else "Маршрут · відкрити замовлення ›"), Ui.num("%d%%" % int(prog * 100), 12, Ui.MUTED)), W._meter(prog, Ui.ACCENT, 0, j.get("hold", 0) <= 0 and (st.seg < 0 or st.get("inc") != null))])
	if not ret:
		var op := PanelContainer.new()
		op.add_theme_stylebox_override("panel", Ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 1, Vector4(8, 8, 8, 8)))
		op.add_child(pr)
		op.mouse_filter = Control.MOUSE_FILTER_STOP
		op.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		op.tooltip_text = "Відкрити в «Рейси в дорозі»"
		op.mouse_entered.connect(func(): op.add_theme_stylebox_override("panel", Ui.box(Color(4 / 255.0, 9 / 255.0, 14 / 255.0, .55), Ui.LINE, 1, Vector4(8, 8, 8, 8))))
		op.mouse_exited.connect(func(): op.add_theme_stylebox_override("panel", Ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 1, Vector4(8, 8, 8, 8))))
		op.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: open_window.emit("coTrips"))
		body.add_child(Ui.margin(op, -8, 2, -8, 0))
	else:
		body.add_child(pr)
	if j.get("ev", []).size():
		var evn := W._note("\n".join(j.ev.slice(-3)), Ui.FG2, 12)
		evn.custom_minimum_size.x = 260   # a width from the start: no one-letter column for a frame
		evn.custom_minimum_size.x = 266
		body.add_child(evn)
	# a new course (08r-multi.js): highlighted when danger lies ahead
	if sim.sr_ok(j):
		var hz: Variant = sim.sr_hit(j)
		var rb := W._btn("Змінити курс" + (" — небезпека на шляху" if hz != null else ""), "pri sm" if hz != null else "sm", Planner.LP_T[j.mode], func(): reroute.emit(j))
		rb.size_flags_horizontal = Control.SIZE_FILL
		body.add_child(rb)
	# cancel the trip (08v-cons.js coCancel): a dialog first
	if not ret:
		var ci := sim.cancel_info(j)
		var b := W._btn("Скасувати рейс · штраф " + Ui.usd(ci.fine), "sm", "close", func(): ask_cancel(j))
		b.size_flags_horizontal = Control.SIZE_FILL
		body.add_child(b)
	col.add_child(Ui.margin(body, 12))
	_card.add_child(col)
	_card.visible = true
	if is_inside_tree():
		get_viewport().update_mouse_cursor_state.call_deferred()
	_card.reset_size()


# ====================================================================== the card of a country / settlement
func show_country(k: int) -> void:
	sel_c = k
	sel_p = -1
	_build_insp()


func show_place(pid: int) -> void:
	sel_p = pid
	sel_c = sim.PL[pid].cid
	_build_insp()


func close_insp() -> void:
	sel_c = -1
	sel_p = -1
	_insp.visible = false
	map._mat.set_shader_parameter("sel", -1)


func insp_open() -> bool:
	return _insp.visible


func refresh() -> void:
	if _insp.visible:
		_build_insp(true)
	if _card.visible:
		_build_card()


func _draw_insp_icon() -> void:
	if sel_p >= 0:
		return
	Flags.draw(_insp_ic, sim.states[sel_c], Rect2(Vector2.ZERO, _insp_ic.size), Ui.LINE_HI)


func _build_insp(keep: bool = false) -> void:
	if sel_c < 0:
		return
	_day = sim.day
	var scroll := _insp_scroll.scroll_vertical
	var CO := sim.CO
	var k := sel_c
	var c: Dictionary = sim.states[k]
	var sp: Variant = sim.PL[sel_p] if sel_p >= 0 and sim.PL[sel_p].cid == k else null
	map._mat.set_shader_parameter("sel", k)
	var vs := get_viewport_rect().size
	_insp.position = Vector2(vs.x - 14 - 330, 84)
	_insp.size = Vector2(330, vs.y - 170)
	_insp.custom_minimum_size = _insp.size
	_insp_title.text = String(sp.name if sp != null else c.name).to_upper()
	_insp_sub.visible = sp != null
	if sp != null:
		_insp_sub.text = "%s · %s ›" % [TYPE_N.get(sp.type, ""), c.name]
	# the icon of the head: the flag (a swatch of the country colour) or a building
	for ch in _insp_ic.get_children():
		ch.queue_free()
	if sp != null:
		var ic := Ui.icon("house" if sp.type == "vil" else ("pin" if sp.type == "town" else "building"), 20, Ui.ACCENT)
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_insp_ic.add_child(ic)
	_insp_ic.queue_redraw()
	for ch in _insp_body.get_children():
		_insp_body.remove_child(ch)
		ch.queue_free()
	var B := _insp_body
	# conflicts, pirates
	var conf: Array = CO.get("conf", []).filter(func(x): return x.a == k or x.b == k)
	if conf.size():
		B.add_child(_red_hint("swords", "[b]Прикордонний конфлікт[/b] з %s. Перевезення ризиковані, але гуманітарні вантажі оплачуються щедро." % ", ".join(conf.map(func(x): return sim.states[x.b if x.a == k else x.a].name))))
	if CO.get("pir", []).any(func(z): return z.get("cid", -1) == k):
		B.add_child(_red_hint("skull", "Біля узбережжя діють [b]пірати[/b]. Директор з безпеки знижує ризик."))
	# the facts
	var pls: Array
	if sp != null:
		pls = sim.PL.duplicate()
		pls.sort_custom(func(a, b): return Vector2(a.x - sp.x, a.z - sp.z).length() < Vector2(b.x - sp.x, b.z - sp.z).length())
		pls = pls.slice(0, 10)
	else:
		var O := {"cap": 0, "big": 1, "city": 2, "town": 3}
		pls = sim.PL.filter(func(p): return p.cid == k)
		pls.sort_custom(func(a, b): return O.get(a.type, 4) < O.get(b.type, 4) or (O.get(a.type, 4) == O.get(b.type, 4) and a.pop > b.pop))
	var rw: Array = RISK_N[_risk_lvl(k)]
	var kv := GridContainer.new()
	kv.columns = 2
	kv.add_theme_constant_override("h_separation", 12)
	kv.add_theme_constant_override("v_separation", 6)
	var facts := [["Материк", _land_n.get(pls[0].land, "—") if pls.size() else "—", Ui.FG, ""],
		["Населення", _fmt_pop(c.pop), Ui.FG, ""],
		["Ризик перевезень", rw[0], W._tone_col(rw[1]), W._tip("Ризик", "Ймовірність крадіжок і затримок на кордонах.")]]
	for f in facts:
		var l := Ui.label(f[0], 13, Ui.FG2)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if f[3] != "":
			l.tooltip_text = f[3]
			l.mouse_filter = Control.MOUSE_FILTER_STOP
		kv.add_child(l)
		var v := Ui.num(f[1], 13, f[2]) if f[0] != "Материк" and f[0] != "Ризик перевезень" else W._b(f[1], 13, f[2])
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kv.add_child(v)
	B.add_child(W._blk(kv))
	if sp != null:
		_biz_insp(B, sp)
	# your hubs here
	var hs: Array = CO.hubs.filter(func(h): return sim.PL[h.pid].cid == k)
	if hs.size():
		B.add_child(W._sect("Ваша мережа тут"))
		for h in hs:
			var q: Dictionary = sim.PL[h.pid]
			var hq: bool = h.pid == CO.hq
			var pid: int = q.id
			var nveh: int = CO.veh.filter(func(v): return v.loc == pid).size()
			var row := W._lrow("star" if hq else "building", Ui.vbox(2, [W._b(("Штаб · " if hq else "") + D.HUB_LV[h.lvl], 14), W._note("%s · %d од. техніки" % [q.name, nveh])]), Ui.pill("На мапі", "warn", "pin"))
			row.add_theme_stylebox_override("panel", Ui.box(Color(1, 179 / 255.0, 71 / 255.0, .07), Color(1, 179 / 255.0, 71 / 255.0, .45), 1, Vector4(12, 10, 12, 10)))
			row.get_child(0).get_child(0).texture = Icons.tex("star" if hq else "building", Ui.WARN, 18)
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: fly(pid))
			B.add_child(row)
	# the settlements
	B.add_child(W._sect("Поруч" if sp != null else "Міста й села"))
	for p in pls:
		B.add_child(_place_row(p))
	_clip_labels(B)
	if keep:
		_restore(scroll)
	_insp.visible = true
	_fit_insp.call_deferred()
	get_tree().process_frame.connect(_fit_insp, CONNECT_ONE_SHOT)   # again once wrapped text has its size
	get_viewport().update_mouse_cursor_state()


## #insp: 330 wide at the right edge, never past the screen
## the card keeps its width: a line of text in a column gives way (… at its end) instead of pushing the
## card off the screen (long names, a row with a button)
static func _clip_labels(n: Node) -> void:
	for c in n.get_children():
		if c is Label and n is VBoxContainer and c.autowrap_mode == TextServer.AUTOWRAP_OFF:
			c.clip_text = true
			c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		elif c is Control:
			_clip_labels(c)


func _fit_insp() -> void:
	var vs := get_viewport_rect().size
	_insp.custom_minimum_size = Vector2(330, vs.y - 170)
	_insp.size = Vector2(maxf(330, _insp.get_combined_minimum_size().x), vs.y - 170)
	_insp.position = Vector2(vs.x - 14 - _insp.size.x, 84)


## how much of the right side the card takes (the toasts move left of it)
func insp_width() -> float:
	return _insp.size.x if _insp.visible else 0.0


func _restore(v: int) -> void:
	await get_tree().process_frame
	_insp_scroll.scroll_vertical = v


static func _left(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return c


static func _red_hint(ic: String, text: String) -> PanelContainer:
	var h := Ui.hint(text, ic)
	h.add_theme_stylebox_override("panel", Ui.box(Color(Ui.BAD, .07), Color(Ui.BAD, .4), 1, Vector4(12, 10, 12, 10)))
	return h


## bizInsp: the infrastructure and the firms of a settlement
func _biz_insp(B: VBoxContainer, p: Dictionary) -> void:
	var s: Dictionary = sim.node_spec(p)
	var rows := []
	var y := func(ok: bool, t: String) -> Control: return W._icl("check" if ok else "close", t, Ui.GOOD if ok else Ui.MUTED, 13)
	if p.get("port") != null:
		rows.append(_flow([W._icl("anchor", "Порт", Ui.FG, 13), y.call(s.get("reefer", false), "рефконтейнери"), y.call(s.get("deep", false), "глибоководний причал (балкери)")]))
	if p.get("air"):
		rows.append(_flow([W._icl("plane", "Аеропорт", Ui.FG, 13), y.call(true, "вантажні літаки"), y.call(s.get("heavy", false), "важкі авіавантажники")]))
	if p.get("rail"):
		rows.append(_flow([W._icl("train", "Залізнична станція", Ui.FG, 13)]))
	if rows.size():
		B.add_child(W._sect("Інфраструктура"))
		B.add_child(W._blk(Ui.vbox(6, rows)))
	B.add_child(W._sect("Підприємства"))
	var fv := Ui.vbox(6)
	for f in sim.firms_of(p.id).slice(0, 9):
		fv.add_child(W._tt(f.n, D.IND[f.ind].n, D.IND[f.ind].ic, Ui.MUTED))
	B.add_child(fv)


static func _flow(items: Array) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 12)
	f.add_theme_constant_override("v_separation", 4)
	for i in items:
		f.add_child(i)
	return f


## a settlement without a hub: buy one (the full price) or rent one (a deposit, then a monthly rent, up to
## level 2), one under the other
func _hub_btns(p: Dictionary) -> Control:
	var CO := sim.CO
	var pid: int = p.id
	var buy := sim.hub_cost(p)
	var dep := sim.hub_rent_deposit(p)
	var rent_m := sim.hub_rent_m({"pid": pid, "lvl": 1, "rent": 1})
	var b1 := W._btn("Купити " + Ui.usd(buy), "pri sm" if CO.cash >= buy else "sm", "plus", func(): acted.emit(sim.act_hub(pid, false)), CO.cash >= buy,
		W._tip("Купити хаб", "Власний хаб 1 рівня в цьому місті за %s. Без щомісячної оренди, розширюється до «Логістичного хабу»." % Ui.usd(buy)))
	var b2 := W._btn("Оренда " + Ui.usd(dep), "sm", "doc", func(): acted.emit(sim.act_hub(pid, true)), CO.cash >= dep,
		W._tip("Орендувати хаб", "Застава %s, далі ≈ %s/міс. Дешевий старт без великої покупки, але оренда дорожча за утримання власного. Розширити можна лише до 2 рівня." % [Ui.usd(dep), Ui.usd(rent_m)]))
	for b in [b1, b2]:
		b.size_flags_horizontal = Control.SIZE_FILL
	return Ui.vbox(4, [b1, b2])


func _place_row(p: Dictionary) -> PanelContainer:
	var CO := sim.CO
	var h: Variant = sim.hub_at(p.id)
	var can := sim.co_scope(p)
	var cost := sim.hub_cost(p)   # the upgrade is priced on the full price, as act_hub_up
	var pid: int = p.id
	var ic: String = ("star" if pid == CO.hq else "building") if h != null else ("crown" if p.type == "cap" else "pin")
	var nm := W._b(p.name, 14)
	nm.mouse_filter = Control.MOUSE_FILTER_STOP
	nm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	nm.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: fly(pid))
	var sub := Ui.hbox(4, [Ui.label(Ui.people(p.pop), 13, Ui.FG2)])
	for x in [["air", "plane"], ["port", "anchor"], ["rail", "train"]]:
		if (p.get(x[0]) != null and x[0] == "port") or (x[0] != "port" and p.get(x[0])):
			sub.add_child(Ui.icon(x[1], 13, Ui.FG2))
	if h != null:
		sub.add_child(Ui.label(" · ", 13, Ui.FG2))
		sub.add_child(Ui.label(D.HUB_LV[h.lvl], 13, Ui.WARN))
	var right: Control
	if h != null:
		if h.lvl < 4:
			right = W._btn(Ui.usd(cost * D.HUB_UP[h.lvl]), "sm", "up", func(): acted.emit(sim.act_hub_up(pid)))
		else:
			right = Ui.pill("Логістичний хаб", "good")
	elif can:
		right = _hub_btns(p)
	else:
		right = Ui.pill("", "", "lock")
		right.tooltip_text = W._tip("Недоступно", "Потрібна ліцензія «Міжміська доставка»." if CO.tier < 1 else ("Хаби за кордоном — з ліцензією «Міжнародні перевезення»." if CO.tier < 3 else "Інші материки — з ліцензією «Морський перевізник»."))
		right.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := W._lrow(ic, Ui.vbox(2, [nm, sub]), right)
	row.get_child(0).get_child(0).texture = Icons.tex(ic, Ui.WARN if h != null else Ui.MUTED, 18)
	return row


## coFly: the camera to a settlement
func fly(pid: int) -> void:
	var p: Dictionary = sim.PL[pid]
	follow = false
	map.camera.ttx = p.x
	map.camera.ttz = p.z + .12
	map.camera.tdist = minf(map.camera.tdist, 2.4)
