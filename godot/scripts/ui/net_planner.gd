class_name NetPlanner
extends Planner
## «Створити маршрут» of the alternative balance (SimNet): the panel on the left like the route planner, the
## route on the map. The run starts at a terminal; the player clicks the towns one after another — where to
## deliver, where to pick up — and last the hub (or terminal) everything else goes to. The panel: the kind of
## transport, which vehicle (or a partner), the stops (↑ ↓ ✕, «Додати зупинку», «Попутні»), the consignments
## the run takes (each on or off), the load, the time, the costs and the pay, «Відправити» once, or a line
## that repeats the run every few days. Time stands still while it is open, as in the planner.

const MODE_N := {"road": "Авто", "rail": "Залізниця", "sea": "Корабель", "air": "Авіа"}

var st := {}
var _spec := {}
var _C := {}


## opens at a terminal; args: m (the kind of transport), way (stops already chosen)
func open_net(a: int, args: Dictionary = {}) -> void:
	st = {"a": a, "m": args.get("m", "road"), "vid": -2, "way": args.get("way", []).duplicate(), "every": int(args.get("every", 0)), "fill": 0.0, "back": false,
		"focus": int(args.get("focus", -1)), "foci": []}
	if st.focus >= 0:
		st.foci.append(st.focus)
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


## the route, the cargo switched on or off and the orders marked since: all gone; the order the panel was opened
## for stays marked
func clear_route() -> void:
	st.way = []
	st.foci = [st.focus] if st.focus >= 0 and sim._cs(st.focus) != null else []
	_panel_build()


## what the route does not load: everything but the orders marked and the cargo switched on by hand (no cargo
## joins on its own because it happens to wait on the way), and what was switched off
func _skip_eff() -> Dictionary:
	var sk := {}
	for c in sim.CO.net.cs:
		if c.run < 0 and not st.foci.has(c.id) and c.st != "move" and c.st != "done":
			sk[c.id] = true
	return sk


## «Прийняті вантажі»: every order taken that waits in the start's country, local ones (to a town of the same
## country) or international ones (to another), each with its switch: on — it goes on this run (and is marked on
## the map), and a tag for how it ends on the route laid
func _cargo_list(B: VBoxContainer) -> void:
	var A: Dictionary = sim.PL[st.a]
	var rows := {}
	for row in _C.get("rows", []):
		rows[row.c.id] = row
	var stops: Array = _spec.get("stops", [])
	var loc := []
	var intl := []
	for c in sim.CO.net.cs:
		if c.run >= 0 or not (c.st == "ready" or c.st == "wait" or c.st == "proc") or sim.PL[c.at].cid != A.cid:
			continue
		(loc if sim.PL[c.k.to].cid == A.cid else intl).append(c)
	var cf: String = st.get("cf", "loc")
	B.add_child(_sect("Прийняті вантажі"))
	B.add_child(_seg_eq([["loc", "Локальні · %d" % loc.size()], ["intl", "Міжнародні · %d" % intl.size()]], cf, func(x):
		st.cf = x
		_panel_build()))
	var L: Array = loc if cf == "loc" else intl
	L.sort_custom(func(x, y): return st.foci.has(x.id) and not st.foci.has(y.id) or (st.foci.has(x.id) == st.foci.has(y.id) and x.dl < y.dl))
	if L.is_empty():
		B.add_child(Ui.margin(W._note("Локальних прийнятих вантажів у цій країні зараз немає: візьміть замовлення на біржі." if cf == "loc" else "Міжнародних прийнятих вантажів у цій країні зараз немає: візьміть замовлення на біржі.", Ui.MUTED, 12), 0, 6, 0, 0))
		return
	var lv := Ui.vbox(0)
	for c in L:
		var row: Variant = rows.get(c.id)
		var cid: int = c.id
		var on: bool = st.foci.has(cid)
		# how it ends on the route: on time, late by…, to a warehouse, no room, the route misses it
		var tag: Control = null
		if row != null:
			if not row.dest:
				tag = Ui.pill("на склад · %s" % sim.PL[stops[row.off]].name, "acc", "building")
			elif row.late <= 0:
				tag = Ui.pill("вчасно", "good", "check")
			else:
				tag = Ui.pill("затримка %s" % Ui.days(row.late), "bad", "alert")
		elif on and stops.size():
			var i0: int = stops.find(c.at)
			if i0 >= 0 and i0 < stops.size() - 1:
				tag = Ui.pill("не вміщується", "bad", "alert")
				tag.tooltip_text = W._tip("Не вміщується", "%s т не влазять у машину разом з іншими: оберіть більшу техніку або вимкніть інший вантаж." % Ui.loc(c.k.tons))
			else:
				tag = Ui.pill("поза маршрутом", "warn")
				tag.tooltip_text = W._tip("Поза маршрутом", "Маршрут не проходить через %s, де чекає вантаж: клікніть це місто на мапі." % sim.PL[c.at].name)
		var nm := Ui.rich("[b]%s → %s[/b] · %s т" % [sim.PL[c.at].name, sim.PL[c.k.to].name, Ui.loc(c.k.tons)], 12)   # from where it is now
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.tooltip_text = "%s · до дедлайну %s" % [sim.cargo_i[c.k.cg].n, Ui.days(maxf(0, c.dl - sim.co_now()))]
		var tg := W._toggle(on, func():
			if st.foci.has(cid):
				st.foci.erase(cid)
			else:
				st.foci.append(cid)
			_panel_build())
		var h := Ui.hbox(8, [tg, nm])
		if tag != null:
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(tag)
		lv.add_child(Ui.margin(h, 0, 3, 0, 3))
	B.add_child(Ui.margin(lv, 0, 6, 0, 0))


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
	_panel.size.x = minf(380, vs.x - 32)   # the height follows the content (_size_to_body)
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
	B.add_child(Ui.margin(W._note("Старт — %s. Клікайте на мапі міста по черзі: куди доставити й де забрати вантаж. Останнім — хаб чи термінал, куди машина повезе решту. Ctrl+Z прибирає останню зупинку." % A.name), 0, 4, 0, 0))
	# the kind of transport
	B.add_child(_sect("Вид транспорту"))
	var ms := ["road", "rail", "sea", "air"]
	if not sim.node_ok(st.m, A):
		st.m = "road"
	var mseg := _seg_eq(ms.map(func(m): return [m, MODE_N[m]]), st.m, func(x):
		st.m = x
		st.way = []
		st.vid = -2
		_panel_build())
	var mb: Array = mseg.get_child(0).get_children()
	for k in ms.size():   # no station, port or airport at the start: the kind shown, not chosen
		if not sim.node_ok(ms[k], A):
			mb[k].disabled = true
			mb[k].tooltip_text = "У %s немає %s" % [A.name, {"rail": "залізничної станції", "sea": "порту", "air": "аеропорту"}.get(ms[k], "дороги")]
	B.add_child(mseg)
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
	if st.vid < 0:   # partners know the market: they keep most of the pay for their part of the way
		B.add_child(Ui.margin(W._note(("Вільної власної техніки цього виду тут немає. " if cars.size() == 1 else "") + "Партнер забирає ≈85% оплати вантажів за свою ділянку і бере плату за бронювання: це вихід, щоб не зірвати дедлайн, а заробіток — на власній техніці.", Ui.WARN, 12), 0, 4, 0, 0))
	# the plan of the route as it is now (what each stop loads and unloads goes into the route's rows)
	_spec = {}
	_C = {}
	st.cnt = {}
	st.planned = st.way.size() > 0
	if st.way.size():
		_spec = sim.net_auto_multi(st.a, st.way, st.m, st.vid, false, _skip_eff())
		st.auto_end = _spec.get("auto_end", -1)
		_C = sim.net_calc(_spec)
		for row in _C.rows:
			for e in [[row.on, 0], [row.off, 1]]:
				if not st.cnt.has(e[0]):
					st.cnt[e[0]] = [0, 0]
				st.cnt[e[0]][e[1]] += 1
	B.add_child(_sect("Маршрут"))
	B.add_child(NetWin.new(_wins()).way_editor(st, _panel_build))
	if st.way.is_empty():
		B.add_child(Ui.margin(W._note("Клікніть на мапі перше місто маршруту.", Ui.MUTED), 0, 6, 0, 0))
		_cargo_list(B)
		_end(B, keep)
		return
	var C: Dictionary = _C
	_cargo_list(B)
	# the sums
	B.add_child(_sect("Рейс"))
	var own: bool = st.vid >= 0
	var fs := W._stat("Заповнення", ("%d%%" % int(C.fill * 100)) if own else "%s т" % Ui.loc(C.tons), "%s т" % Ui.loc(C.tons) if own else "партнер бере будь-яку вагу", "", "bad" if C.get("over") else "")
	if own:   # the whole width of the tile a bar, filled from the left, the percent in its middle
		var txt: VBoxContainer = fs.get_child(0)
		var num: Label = txt.get_child(1)
		txt.remove_child(num)
		var bar := FillBar.new()
		bar.f = C.fill
		bar.col = Ui.BAD if C.fill > 1 else Ui.ACCENT
		num.custom_minimum_size = Vector2.ZERO
		num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bar.add_child(num)
		txt.add_child(Ui.margin(bar, 0, 4, 0, 4))
		txt.move_child(txt.get_child(txt.get_child_count() - 1), 1)
	var g := W._grid(2, [
		fs,
		W._stat("Час", Ui.days(C.t), "з обробкою на складах"),
		W._stat("Витрати", Ui.usd(C.c), "пальне, екіпаж, збори" if own else "тариф і збори партнера"),
		W._stat("Оплата в рейсі", Ui.usd(C.rev), "за доставлені цим рейсом", "", "good" if C.rev > C.c else "")], 8)
	B.add_child(g)
	if not C.ok:
		B.add_child(Ui.margin(W._icl("alert", C.why, Ui.WARN, 12), 0, 8, 0, 0))
	# how often
	B.add_child(_sect("Повторювати"))
	B.add_child(_seg_eq([[0, "раз"], [1, "щодня"], [2, "2 дн."], [3, "3 дн."], [5, "5 дн."], [7, "тиждень"]], st.every, func(x):
		st.every = x
		_panel_build()))
	# how full the vehicle must be to leave
	var own_fill: float = C.fill if own else C.tons / 40.0
	B.add_child(_sect("Рушати, коли заповнено від"))
	B.add_child(_seg_eq([[0.0, "одразу"], [.3, "30%"], [.5, "50%"], [.7, "70%"], [.9, "90%"]], st.fill, func(x):
		st.fill = x
		_panel_build()))
	var wait: bool = st.fill > 0 and own_fill + 1e-6 < st.fill
	var now_s := ("%d%%" % int(own_fill * 100)) if own else ("%s т" % Ui.loc(C.tons))
	var ft: String
	if wait:
		ft = "Зараз %s — рейс чекатиме в %s, поки назбирається вантаж (не довше %d дн.; термінові вантажі не чекають)." % [now_s, sim.PL[st.a].name, maxi(st.every, 5)]
	elif st.fill > 0:
		ft = "Зараз %s — достатньо, рейс може рушати." % now_s
	else:
		ft = "Зараз %s." % now_s
	if not own:
		ft += " Для партнера 100% — це 40 т."
	B.add_child(Ui.margin(W._note(ft, Ui.WARN if wait else Ui.MUTED, 12), 0, 6, 0, 0))
	if st.every > 0:
		B.add_child(Ui.margin(W._note("Рейс повторюватиметься сам — щоразу з тим, що на той момент чекає на цих зупинках.", Ui.MUTED, 12), 0, 4, 0, 0))
	# the buttons
	var bs := Ui.hbox(8)
	bs.add_child(W._btn("Очистити маршрут", "", "trash", clear_route, true))
	bs.add_child(Ui.spacer())
	if st.every > 0:
		bs.add_child(W._btn("Створити лінію", "pri", "refresh", _make_line, C.ok or C.rows.is_empty(), W._tip("Лінія за розкладом", "Перший рейс — зараз, якщо вантаж уже є й заповнення досягнуто, далі кожні %d дн." % st.every)))
	elif wait:
		bs.add_child(W._btn("Чекати заповнення", "pri", "clock" if Icons.has("clock") else "refresh", _make_line, C.ok or C.rows.is_empty(), W._tip("Чекати заповнення", "Машина стоїть у хабі й рушить цим маршрутом, щойно заповнення досягне %d%%." % int(st.fill * 100))))
	else:
		bs.add_child(W._btn("Відправити", "pri", "send", _go, C.ok))
	B.add_child(Ui.margin(bs, 0, 14, 0, 0))
	_end(B, keep)


func _end(_B: VBoxContainer, keep: int) -> void:
	_restore(keep)
	_fit()


## the options of a segmented control in equal parts across the panel, the text centred
func _seg_eq(options: Array, sel: Variant, cb: Callable) -> Control:
	var p := Ui.seg(options, sel, cb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h: HBoxContainer = p.get_child(0)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for b in h.get_children():
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.0
		b.custom_minimum_size.x = 1
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return p


## the panel as tall as its content (to «Відправити»), never more than the screen: set whenever the content's
## height changes — at once, without waiting a frame (no growing for a moment and shrinking back)
func _fit() -> void:
	if not _body.minimum_size_changed.is_connected(_size_to_body):
		_body.minimum_size_changed.connect(_size_to_body)
	_size_to_body()


func _size_to_body() -> void:
	if not on or not is_inside_tree():
		return
	var vs := get_viewport_rect().size
	var w := minf(380, vs.x - 32)
	var h := minf(vs.y - 84 - 86, _body.get_combined_minimum_size().y + 28)
	_scroll.custom_minimum_size = Vector2(w, h)
	_panel.custom_minimum_size = Vector2(w, h)
	_panel.size = Vector2(w, h)
	_panel.reset_size()


class FillBar extends Control:
	var f := 0.0
	var col := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(40, 28)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(1, 1, 1, .04))
		var w := (size.x - 4) * clampf(f, 0, 1)
		if w > 0:
			draw_rect(Rect2(2, 2, w, size.y - 4), Color(col, .45))
			draw_rect(Rect2(2 + w - minf(2, w), 2, minf(2, w), size.y - 4), col)
		draw_rect(r.grow(-.5), Ui.LINE_HI, false, 1.0)


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
	var full: bool = (_C.fill if st.vid >= 0 else _C.tons / 40.0) + 1e-6 >= st.fill
	if _C.get("ok", false) and full:   # the first run now
		sim.net_go(_spec, true)
		L.next = sim.day + st.every
		if st.every == 0:   # once: done
			sim.net_line_del(L.id)
	elif st.every == 0:
		res = {"tone": "good", "t": "Рейс чекає заповнення", "d": "%s: рушить, коли заповнення досягне %d%%" % [sim.PL[st.a].name, int(st.fill * 100)]}
	close("")
	acted.emit(res)


## the route in the colour of its transport, the preview to the town under the pointer, the stops numbered,
## waves where the run picks cargo up (blue) and where it delivers (yellow)
func _draw_route() -> void:
	if not on:
		return
	var n := _draw_node
	var m: String = st.m
	var pts: Array = [st.a] + st.way + ([st.auto_end] if st.get("auto_end", -1) >= 0 and st.way.size() else [])
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
	for fid in st.get("foci", []):
		var fc: Variant = sim._cs(fid)
		if fc != null:
			_wave(n, sim.PL[fc.at], DEP)
			_wave(n, sim.PL[fc.k.to], ARR)
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
