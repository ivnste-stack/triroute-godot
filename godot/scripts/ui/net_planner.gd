class_name NetPlanner
extends Planner
## «Створити маршрут» of the alternative balance (SimNet): the panel on the left like the route planner, the
## route on the map. The run starts at a terminal; the player clicks the towns one after another — where to
## deliver, where to pick up — and last the hub (or terminal) everything else goes to. The panel: the kind of
## transport, which vehicle (or a partner), the stops (↑ ↓ ✕, «Додати зупинку», «Попутні»), the consignments
## the run takes (each on or off), the load, the time, the costs and the pay, «Відправити» once, or a line
## that repeats the run every few days. Time stands still while it is open, as in the planner.

const MODE_N := {"road": "Авто", "rail": "Залізниця", "sea": "Море", "air": "Авіа"}

var st := {}
var _spec := {}
var _C := {}


## opens at a terminal; args: m (the kind of transport), way (stops already chosen)
func open_net(a: int, args: Dictionary = {}) -> void:
	st = {"a": a, "m": args.get("m", "road"), "vid": -2, "way": args.get("way", []).duplicate(), "skip": {}, "every": 0, "fill": .5, "back": false}
	LP = {"k": {}, "pts": [a], "modes": []}   # what the planner's own parts read
	on = true
	_prev_speed = session.speed
	session.set_speed(0)
	session.lock_speed = "Поки створюєш маршрут, час стоїть: відправ рейс або закрий панель"
	var A: Dictionary = sim.PL[a]
	map.camera.ttx = A.x
	map.camera.ttz = A.z + .3
	map.camera.tdist = clampf(map.camera.tdist, 4, 9)
	visible = true
	_panel_build()


func cancel() -> void:
	close("coNet")


func undo() -> void:
	if st.way.size():
		st.way.pop_back()
		_panel_build()


func clear_route() -> void:
	st.way = []
	st.skip = {}
	_panel_build()


func click(mp: Vector2) -> void:
	var pid := city_at(mp, 18)
	if pid < 0:
		return
	var last: int = st.way.back() if st.way.size() else st.a
	if pid == last:
		return
	if not sim.node_ok(st.m, sim.PL[pid]):
		acted.emit({"tone": "warn", "t": "%s: немає %s" % [MODE_N[st.m], {"rail": "станції", "sea": "порту", "air": "аеропорту"}.get(st.m, "дороги")], "d": sim.PL[pid].name})
		return
	if sim.co_route(st.m, last, pid) == null:
		acted.emit({"tone": "warn", "t": "Маршрут недоступний", "d": "%s не пройде між %s і %s" % [MODE_N[st.m], sim.PL[last].name, sim.PL[pid].name]})
		return
	st.way.append(pid)
	_panel_build()


func _unhandled_key_input(e: InputEvent) -> void:
	if not on or not (e is InputEventKey) or not e.pressed:
		return
	if e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancel()
	elif e.keycode == KEY_Z and (e.ctrl_pressed or e.meta_pressed):
		get_viewport().set_input_as_handled()
		undo()


func _sect(t: String) -> Control:
	return Ui.margin(Ui.lbl(t), 0, 12, 0, 6)


func _panel_build() -> void:
	var vs := get_viewport_rect().size
	_panel.position = Vector2(14, 84)
	_panel.size = Vector2(minf(380, vs.x - 32), minf(vs.y - 84 - 86, maxf(_panel.size.y, 200)))
	_scroll.custom_minimum_size = _panel.size
	var keep := _scroll.scroll_vertical
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var B := _body
	var CO := sim.CO
	var A: Dictionary = sim.PL[st.a]
	LP.pts = [st.a] + st.way
	# head
	B.add_child(_row(Ui.hbox(8, [Ui.icon("road", 18, Ui.FG), W._b("Новий маршрут", 15)]), MapUi._xbtn(cancel)))
	B.add_child(Ui.margin(W._note("Старт — %s. Клікайте на мапі міста по черзі: куди доставити й де забрати вантаж. Останнім — хаб чи термінал, куди машина повезе решту." % A.name), 0, 4, 0, 0))
	# the kind of transport
	B.add_child(_sect("Вид транспорту"))
	var ms := ["road", "rail", "sea", "air"].filter(func(m): return sim.node_ok(m, A))
	if not ms.has(st.m):
		st.m = "road"
	B.add_child(Ui.seg(ms.map(func(m): return [m, MODE_N[m]]), st.m, func(x):
		st.m = x
		st.way = []
		st.vid = -2
		_panel_build()))
	# who drives
	B.add_child(_sect("Хто їде"))
	var cars := []
	for v in sim.net_idle_at(st.a, st.m):
		var T: Dictionary = D.VT[v.t]
		cars.append([v.id, "%s #%d · %s т%s" % [T.n, v.id, Ui.loc(T.cap), (" · стан %.0f%%" % v.cond) if v.cond < 60 else ""], T.ic])
	cars.append([-1, "Партнер-перевізник", "handshake"])
	if st.vid == -2 or not cars.any(func(x): return x[0] == st.vid):
		st.vid = cars[0][0]
	var dd := Dropdown.make(cars, st.vid, func(x):
		st.vid = x
		_panel_build())
	dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	B.add_child(dd)
	if cars.size() == 1:
		B.add_child(Ui.margin(W._icl("info", "Вільної власної техніки цього виду тут немає: везе партнер за свій тариф.", Ui.FG2, 12), 0, 4, 0, 0))
	# the stops
	B.add_child(_sect("Зупинки"))
	B.add_child(NetWin.new(_wins()).way_editor(st, _panel_build))
	if st.way.is_empty():
		B.add_child(Ui.margin(W._note("Клікніть на мапі перше місто маршруту.", Ui.MUTED), 0, 6, 0, 0))
		_spec = {}
		_C = {}
		_end(B, keep)
		return
	_spec = sim.net_auto_multi(st.a, st.way, st.m, st.vid, false, st.skip)
	_C = sim.net_calc(_spec)
	var C: Dictionary = _C
	# the cargo
	var listed := []
	for row in C.rows:
		listed.append(row.c)
	for id in st.skip:
		var c: Variant = sim._cs(id)
		if c != null:
			listed.append(c)
	B.add_child(_sect("Вантажі в рейсі"))
	if listed.is_empty():
		B.add_child(W._note("Для цих зупинок вантажів зараз немає: додайте міста, куди їдуть вантажі зі старту, або де вони чекають.", Ui.MUTED))
	var rows := {}
	for row in C.rows:
		rows[row.c.id] = row
	for c in listed:
		var row: Variant = rows.get(c.id)
		var cid: int = c.id
		var tail := "[color=#8a96a3]не їде[/color]"
		if row != null:
			var off: String = sim.PL[_spec.stops[row.off]].name
			if not row.dest:
				tail = "на склад у %s" % off
			elif row.late <= 0:
				tail = "до %s вчасно" % off
			else:
				tail = "до %s [color=#f0625f]із запізненням %s[/color]" % [off, Ui.days(row.late)]
			if row.on > 0:   # picked up on the way
				tail = "забрати в %s · %s" % [sim.PL[_spec.stops[row.on]].name, tail]
		var r := Ui.rich("[b]%s → %s[/b] · %s т · %s" % [sim.PL[c.k.from].name, sim.PL[c.k.to].name, Ui.loc(c.k.tons), tail], 12)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		B.add_child(Ui.margin(Ui.hbox(8, [W._toggle(row != null, func():
			if st.skip.has(cid):
				st.skip.erase(cid)
			else:
				st.skip[cid] = true
			_panel_build()), r]), 0, 2, 0, 2))
	# the sums
	B.add_child(_sect("Рейс"))
	var own: bool = st.vid >= 0
	var g := W._grid(2, [
		W._stat("Заповнення", ("%d%%" % int(C.fill * 100)) if own else "%s т" % Ui.loc(C.tons), "%s т" % Ui.loc(C.tons) if own else "партнер бере будь-яку вагу", "", "bad" if C.get("over") else ""),
		W._stat("Час", Ui.days(C.t), "з обробкою на складах"),
		W._stat("Витрати", Ui.usd(C.c), "пальне, екіпаж, збори" if own else "тариф і збори партнера"),
		W._stat("Оплата в рейсі", Ui.usd(C.rev), "за доставлені цим рейсом", "", "good" if C.rev > C.c else "")], 8)
	B.add_child(g)
	if own:
		B.add_child(Ui.margin(W._meter(C.fill, Ui.BAD if C.fill > 1 else Ui.ACCENT), 0, 8, 0, 0))
	if not C.ok:
		B.add_child(Ui.margin(W._icl("alert", C.why, Ui.WARN, 12), 0, 8, 0, 0))
	# how often
	B.add_child(_sect("Повторювати"))
	B.add_child(Ui.seg([[0, "раз"], [1, "щодня"], [2, "2 дн."], [3, "3 дн."], [5, "5 дн."], [7, "тиждень"]], st.every, func(x):
		st.every = x
		_panel_build()))
	if st.every > 0:
		B.add_child(Ui.margin(Ui.hbox(8, [Ui.lbl("рушати, коли заповнено від"), Ui.seg([[0.0, "будь-яке"], [.3, "30%"], [.6, "60%"], [.9, "90%"]], st.fill, func(x): st.fill = x)]), 0, 8, 0, 0))
		B.add_child(Ui.margin(W._note("Рейс повторюватиметься сам — щоразу з тим, що на той момент чекає на цих зупинках. Термінові вантажі не чекають заповнення.", Ui.MUTED, 12), 0, 6, 0, 0))
	# the buttons
	var bs := Ui.hbox(8)
	bs.add_child(W._btn("", "sm", "trash", clear_route, true, "Очистити маршрут"))
	bs.add_child(Ui.spacer())
	if st.every > 0:
		bs.add_child(W._btn("Створити лінію", "pri", "refresh", _make_line, C.ok or C.rows.is_empty(), W._tip("Лінія за розкладом", "Перший рейс — зараз, якщо вантаж уже є, далі кожні %d дн." % st.every)))
	else:
		bs.add_child(W._btn("Відправити", "pri", "send", _go, C.ok))
	B.add_child(Ui.margin(bs, 0, 14, 0, 0))
	_end(B, keep)


func _end(_B: VBoxContainer, keep: int) -> void:
	_restore(keep)
	_fit()


func _wins() -> Windows:
	var w := Windows.new(sim)
	return w


func _go() -> void:
	var res := sim.net_go(_spec)
	close("")
	acted.emit(res)


func _make_line() -> void:
	var L := {"kind": "trunk", "a": st.a, "b": st.way.back(), "way": st.way.duplicate(), "m": st.m, "vid": st.vid, "back": false, "every": st.every, "fill": st.fill, "next": sim.day}
	var res := sim.net_line_add(L)
	if _C.get("ok", false):   # the first run now
		sim.net_go(_spec, true)
		L.next = sim.day + st.every
	close("")
	acted.emit(res)


## the route in the colour of its transport, the preview to the town under the pointer, the stops numbered,
## waves where the run picks cargo up (blue) and where it delivers (yellow)
func _draw_route() -> void:
	if not on:
		return
	var n := _draw_node
	var m: String = st.m
	var pts: Array = [st.a] + st.way
	for i in range(1, pts.size()):
		var r: Variant = sim.co_route(m, pts[i - 1], pts[i])
		if r != null:
			var pp := _path(r, m)
			_poly(n, pp, Color(6 / 255.0, 12 / 255.0, 18 / 255.0, .7), 5)
			_poly(n, pp, LP_C[m], 3)
	var mp := get_viewport().get_mouse_position()
	if get_viewport().gui_get_hovered_control() == null:
		var t := city_at(mp, 22)
		var last: int = pts.back()
		if t >= 0 and t != last and sim.node_ok(m, sim.PL[t]):
			var r: Variant = sim.co_route(m, last, t)
			if r != null:
				map.vehicles._wdash_on(n, _path(r, m), Color(LP_C[m], .85), 2.4)
	if not _C.is_empty():
		var ons := {}
		var offs := {}
		for row in _C.rows:
			ons[_spec.stops[row.on]] = true
			offs[_spec.stops[row.off]] = true
		for pid in ons:
			if pid != st.a:
				_wave(n, sim.PL[pid], DEP)
		for pid in offs:
			_wave(n, sim.PL[pid], ARR)
	var f := Ui.font("mono", 700)
	for i in pts.size():
		var p: Dictionary = sim.PL[pts[i]]
		var q: Variant = _scr(p.x, 0, p.z)
		if q == null:
			continue
		n.draw_circle(q, 9, Color("#06121b"), true, -1.0, true)
		n.draw_circle(q, 7.5, LP_C[m] if i else Color(Ui.ACCENT), true, -1.0, true)
		var s := "★" if i == 0 else str(i)
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		n.draw_string(f, Vector2(q.x - w / 2, q.y + 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#06121b"))
