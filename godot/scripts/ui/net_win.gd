class_name NetWin
extends RefCounted
## The windows of the alternative balance («Мережа терміналів», SimNet): the board of orders taken into the
## network, «Вантажі» (where every consignment is and where it should go next), «Термінали» (warehouses,
## queues, modules, upgrades, partner freight, lines) and the run dialog (a round of a hub's area, a haul
## between terminals, a pick-up). Built by Windows like its own windows, with its small elements.

const D = preload("res://scripts/logistics/game_data.gd")
const MODE_IC := {"road": "truck", "rail": "train", "sea": "ship", "air": "plane"}
const MODE_N := {"road": "Авто", "rail": "Залізниця", "sea": "Море", "air": "Авіа"}

var w: Windows
var sim: Sim


func _init(w_: Windows) -> void:
	w = w_
	sim = w_.sim


func _pl(pid: int) -> String:
	return sim.PL[pid].name


static func _left_s(d: float) -> String:
	if d < 0:
		return "запізнення %s" % Ui.days(-d)
	return "до дедлайну %s" % Ui.days(d)


static func _left_col(d: float) -> Color:
	return Ui.BAD if d < 0 else (Ui.WARN if d < 1.5 else Ui.FG2)


## the steps of a way as a row: a town, the icon of how it goes on, the next town…
func _way(legs: Array, size: int = 13) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 5)
	h.add_theme_constant_override("v_separation", 4)
	for i in legs.size():
		var L: Dictionary = legs[i]
		if i == 0:
			h.add_child(Ui.label(_pl(L.a), size, Ui.FG2))
		var ic := Ui.icon(MODE_IC[L.m], size + 1, Ui.ACCENT)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.tooltip_text = MODE_N[L.m]
		h.add_child(Ui.label("→", size, Ui.MUTED))
		h.add_child(ic)
		h.add_child(Ui.label("→", size, Ui.MUTED))
		h.add_child(Ui.label(_pl(L.b), size, Ui.FG2))
	return h


# ====================================================================== the board
func board(body: VBoxContainer) -> void:
	var CO := sim.CO
	var st := {}
	for c in CO.net.cs:
		st[c.st] = st.get(c.st, 0) + 1
	body.add_child(Windows._grid(3, [
		Windows._stat("На біржі", str(sim.net_board_n()), "до %d одночасно" % sim.co_board_max(), Windows._tip("Біржа", "Відправники ближче до ваших хабів замовляють більше. Кожен рівень хабу, модуль терміналу й комерційний директор додають місць на біржі.")),
		Windows._stat("Вантажів у мережі", str(CO.net.cs.size()), "чекають %d · на складах %d · у дорозі %d" % [st.get("wait", 0), st.get("ready", 0) + st.get("proc", 0), st.get("move", 0)]),
		Windows._stat("Рейсів", str(CO.net.runs.size()), "ліній за розкладом: %d" % CO.net.lines.size())]))
	body.add_child(Ui.hint("[b]Альтернативний баланс: мережа терміналів.[/b] «Взяти в роботу» — і вантаж чекає у відправника. Забирайте його кільцевими рейсами з хабів, збирайте на складах, везіть магістралями (своєю технікою або партнерами) і розвозьте по містах. Чим більше вантажів в одному рейсі, тим дешевше кожен: це і є прибуток. Вікна «Прийняті вантажі» й «Термінали» — ваші склади, рейси й лінії.", "layers"))
	contracts(body)
	body.add_child(Windows._sect("Біржа вантажів"))
	if CO.board.is_empty():
		body.add_child(Windows._note("Нових замовлень поки немає — вони з'являються щодня."))
		return
	var bd: Array = CO.board.duplicate()
	bd.sort_custom(func(a, b): return a.id > b.id)
	var n: int = maxi(w.st.bmore, 15)
	var v := Ui.vbox(8)
	for k in bd.slice(0, n):
		await w._pause()
		v.add_child(card(k))
	body.add_child(v)
	if bd.size() > n:
		body.add_child(w._more(bd.size() - n, "bmore"))


func card(k: Dictionary) -> PanelContainer:
	var CO := sim.CO
	var A: Dictionary = sim.PL[k.from]
	var B: Dictionary = sim.PL[k.to]
	var cg: Dictionary = sim.cargo_i[k.cg]
	var info := Ui.vbox(3)
	info.add_child(Ui.hbox(6, [w._place(k.from), Ui.label("→", 14), w._place(k.to)]))
	info.add_child(Windows._icl(cg.ic, "%s · %s т · %s м³%s" % [cg.n, Ui.loc(k.tons), Ui.loc(k.tons * cg.get("v", 3), 1), " · кордон" if A.cid != B.cid else ""]))
	if k.get("fs"):
		info.add_child(Windows._icl("building", "%s → %s" % [k.fs, k.ft]))
	var P: Variant = sim.net_path(k.from, k.to, k.tons, k.dlDays, k.pay)
	if k.get("sea"):   # a shipload: port to port by an own ship (bought or to buy)
		P = {"legs": [{"a": k.from, "b": k.to, "m": "sea"}], "t": 0.0, "c": 0.0}
		var wy := _way(P.legs)
		var has_ship: bool = sim.CO.veh.any(func(v): return D.VT[v.t].mode == "sea" and D.VT[v.t].cap >= k.tons)
		wy.add_child(Ui.label("· власним судном" if has_ship else "· потрібне власне судно на %s т" % Ui.grp(k.tons), 13, Ui.GOOD if has_ship else Ui.WARN))
		info.add_child(wy)
	elif P != null and P.legs.size():
		var wy := _way(P.legs)
		var ok: bool = P.t <= k.dlDays
		wy.add_child(Ui.label("· ≈ %s · витрати ≈ %s" % [Ui.days(P.t), Ui.usd(P.c)], 13, Ui.GOOD if ok and P.c < k.pay * .7 else (Ui.WARN if ok else Ui.BAD)))
		wy.tooltip_text = Windows._tip("Шлях через вашу мережу", "Найдешевший шлях, що встигає в дедлайн, з вашими хабами й терміналами партнерів: оцінка для одного цього вантажу. Разом з іншими в одному рейсі він обійдеться дешевше. Ви не зобов'язані їхати саме так.")
		info.add_child(wy)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pay := Ui.num(Ui.usd(k.pay), 16)
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var dl := Ui.label("термін " + Ui.days(k.dlDays), 13, Ui.FG2)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var mi := Ui.icon("box", 18, Ui.ACCENT)
	mi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pills := HFlowContainer.new()
	pills.add_theme_constant_override("h_separation", 6)
	pills.add_theme_constant_override("v_separation", 6)
	var rw := Windows._risk_w(k.risk)
	pills.add_child(Ui.pill("Ризик: " + rw[0].to_lower(), rw[1], "shield"))
	if k.get("minR", 0):
		pills.add_child(Ui.pill("Вимога %.1f★" % k.minR, "acc" if CO.rating >= k.minR else "bad", "star"))
	if cg.get("reefer"):
		var cp := Ui.pill("Холодний ланцюг", "", "snow")
		cp.tooltip_text = Windows._tip("Холодний ланцюг", "Продукти, ліки, рефконтейнери. На складі вашого хабу без холодильної камери псуються: після півтора дня — щодня −5% стану (менша оплата й претензії за пошкодження). Холодильна камера в «Керуванні терміналом» це знімає. Привезене рефрижератором оплачується на 20% більше.")
		pills.add_child(cp)
	if k.get("sea"):
		var sp := Ui.pill("Лише власним судном", "acc", "ship")
		sp.tooltip_text = Windows._tip("Морська партія", "Тисячі тонн — більше, ніж беруть партнери (до 2 000 т): тільки ваш контейнеровоз (до 6 000 т) або балкер (до 28 000 т). Платять щедро: судно окупається такими рейсами.")
		pills.add_child(sp)
	elif k.get("refy"):
		var tp := Ui.pill("Автоцистерна +20%", "acc", "truck")
		tp.tooltip_text = Windows._tip("Пальне з НПЗ", "Нафтопереробний завод відправляє пальне в порт. Привезене вашою автоцистерною оплачується на 20% більше. Потрібен дозвіл ADR.")
		pills.add_child(tp)
	elif k.tons >= 25:
		pills.add_child(Ui.pill("Масовий вантаж", "acc", "layers"))
	for id in sim.perm_need(cg, "sea" if k.get("sea") else "road"):
		pills.add_child(Ui.pill(sim.perm_i[id].n.split(":")[0], "good" if sim.perm_ok(id) else "bad", sim.perm_i[id].ic))
	if P == null:
		pills.add_child(Ui.pill("Шляху немає", "bad", "alert"))
	pills.add_child(Ui.pill("%d дн. на біржі" % maxi(0, int(k.exp - sim.day)), "", "info"))
	if k.get("taken"):   # taken: the card stays, the button greyed, «Вантаж прийнято»
		var tb := Windows._btn("Вантаж прийнято", "sm", "check", func(): pass, false)
		var card := Windows._blk(Ui.vbox(8, [Ui.hbox(10, [mi, info, Ui.vbox(2, [pay, dl])]), pills, Windows._card_rule(), Ui.hbox(8, [w._show_btn(k), tb])]))
		card.modulate.a = .7
		return card
	var bs := Ui.hbox(8, [w._show_btn(k), Windows._btn("Взяти в роботу", "pri sm", "box", func(): w._do(sim.net_accept(k)), P != null,
		Windows._tip("Взяти в роботу", "Замовник чекає, що ви заберете вантаж у місті %s і доставите в %s за %s. Далі — у вікні «Прийняті вантажі»." % [A.name, B.name, Ui.days(k.dlDays)]))])
	return Windows._blk(Ui.vbox(8, [Ui.hbox(10, [mi, info, Ui.vbox(2, [pay, dl])]), pills, Windows._card_rule(), bs]))


# ====================================================================== contracts
## «Контракти» on the board: the offers of businesses, the contracts under way (with a route made for one), the
## regular clients and how far each is from a contract
func contracts(body: VBoxContainer) -> void:
	var N: Dictionary = sim._nets()
	body.add_child(Windows._sect("Контракти"))
	if N.coff.is_empty() and N.ctr.is_empty() and N.firms.is_empty():
		body.add_child(Windows._note("Доставляйте вчасно вантажі одних і тих самих підприємств — і вони запропонують контракт: поставки за графіком, без біржі, за сталу ціну. З %d вчасних доставок контракт можна запропонувати й самому." % SimNet.CTR_ASK, Ui.MUTED))
		return
	for O in N.coff:
		body.add_child(_ctr_card(O, true))
	for C in N.ctr:
		body.add_child(_ctr_card(C, false))
	# the regular clients
	var fs: Array = N.firms.keys().filter(func(key): return not sim.ctr_has(key))
	fs.sort_custom(func(a, b): return N.firms[a].ok > N.firms[b].ok)
	if fs.size():
		var rows := Ui.vbox(4, [Ui.lbl("Постійні клієнти")])
		for key in fs.slice(0, 5):
			var F: Dictionary = N.firms[key]
			var k_: String = key
			var can: bool = F.ok >= SimNet.CTR_ASK
			var sub := "%s · вчасно %d · із запізненням %d" % [_pl(F.at), F.ok, F.late]
			if F.ok < SimNet.CTR_MIN:
				sub = "%s · вчасно %d · із запізненням %d · до пропозиції ще %d вчасних" % [_pl(F.at), F.ok, F.late, SimNet.CTR_MIN - F.ok]
			var nm := Ui.vbox(1, [Windows._b(F.n, 13), Windows._note(sub, Ui.FG2, 12)])
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows.add_child(Ui.hbox(10, [Ui.icon("building", 16, Ui.FG2), nm, Windows._btn("Запропонувати контракт", "sm", "handshake", func(): w._do(sim.act_ctr_ask(k_)), can,
				Windows._tip("Запропонувати контракт", "Підприємство погодиться, якщо з ним було щонайменше %d вчасних доставок і мало запізнень. Ціна трохи нижча, ніж коли контракт пропонує воно саме." % SimNet.CTR_ASK))]))
		body.add_child(Windows._blk(rows))


func _ctr_card(C: Dictionary, offer: bool) -> PanelContainer:
	var cg: Dictionary = sim.cargo_i[C.cg]
	var head := Ui.hbox(8, [Ui.icon("handshake", 18, Ui.ACCENT), Windows._b(C.firm, 14), Ui.spacer(), Ui.num("%s за поставку" % Ui.usd(C.pay), 14)])
	var lane := Ui.hbox(6, [w._place(C.from, 13), Ui.label("→", 13), w._place(C.to, 13)])
	var facts := "%s · %s т · кожні %d дн. · дедлайн %s" % [cg.n, Ui.loc(C.tons), C.every, Ui.days(C.dl)]
	var v := Ui.vbox(6, [head, lane, Windows._note(facts, Ui.FG2, 12)])
	var bs := Ui.hbox(8)
	if offer:
		v.add_child(Windows._note("Пропозиція на %d міс. · діє ще %s · разом ≈ %s" % [C.months, Ui.days(maxf(0, C.exp - sim.day)), Ui.usd(C.pay * C.months * 30 / C.every)], Ui.MUTED, 12))
		var oid: int = C.id
		bs.add_child(Windows._btn("Укласти контракт", "pri sm", "handshake", func(): w._do(sim.act_ctr_take(oid))))
		bs.add_child(Windows._btn("Відхилити", "sm", "close", func():
			sim.act_ctr_decline(oid)
			w._do({})))
	else:
		v.add_child(Windows._note("Наступна поставка за %s · до кінця %s · доставлено %d · зривів %d з 3" % [Ui.days(maxf(0, C.next - sim.day)), Ui.days(maxf(0, C.until - sim.day)), C.ok, C.miss],
			Ui.BAD if C.miss >= 2 else Ui.MUTED, 12))
		var cid: int = C.id
		# a route for it: from the nearest hub on its land to the shipper, the consignee and back
		var A: Dictionary = sim.PL[C.from]
		var hb := -1
		var bd := 1e9
		for h in sim.CO.hubs:
			var q: Dictionary = sim.PL[h.pid]
			if q.land == A.land and JS.hypot(q.x - A.x, q.z - A.z) < bd:
				bd = JS.hypot(q.x - A.x, q.z - A.z)
				hb = h.pid
		if hb >= 0:
			var way: Array = ([C.from] if C.from != hb else []) + [C.to] + ([hb] if C.to != hb else [])
			var ev: int = C.every
			bs.add_child(Windows._btn("Маршрут під контракт", "pri sm", "road", func(): w.net_dialog.emit("route", {"a": hb, "way": way, "every": ev}), true,
				Windows._tip("Маршрут під контракт", "Відкриє створення маршруту з хабу %s: забрати в %s, доставити в %s і повернутися, з повтором кожні %d дн. Лінія сама братиме кожну поставку контракту." % [_pl(hb), _pl(C.from), _pl(C.to), ev])))
		bs.add_child(Windows._btn("Розірвати", "sm", "close", func(): w._do(sim.act_ctr_end(cid)), true, "Розірвати контракт: рейтинг −0.1"))
	v.add_child(Windows._card_rule())
	v.add_child(bs)
	return Windows._blk(v, Ui.ACCENT if offer else Ui.LINE)


# ====================================================================== «Вантажі»
func cargo(body: VBoxContainer) -> void:
	var CO := sim.CO
	var cs: Array = CO.net.cs.duplicate()
	if cs.is_empty():
		body.add_child(Ui.hint("Прийнятих вантажів поки немає. Беріть замовлення на «Біржі вантажів» кнопкою «Взяти в роботу».", "box"))
		return
	cs.sort_custom(func(a, b): return a.dl < b.dl)
	# the countries: where the cargo is, comes from or goes to
	var by := {}
	for c in cs:
		for pid in [c.at, c.k.from, c.k.to]:
			var cid: int = sim.PL[pid].cid
			if not by.has(cid):
				by[cid] = {}
			by[cid][c.id] = true
	var cur: int = w.st.get("ccty", -1)
	if not by.has(cur):
		cur = -1
		w.st.ccty = -1
	if by.size():
		var opts := [[-1, "Усі країни · %d" % cs.size(), "globe"]]
		var ks: Array = by.keys()
		ks.sort_custom(func(x, y): return by[x].size() > by[y].size())
		for cid in ks:
			opts.append([cid, "%s · %d" % [sim.states[cid].name, by[cid].size()], "flag"])
		var dd := Dropdown.make(opts, cur, func(x):
			w.st.ccty = x
			w._do({}))
		body.add_child(Ui.hbox(10, [Ui.lbl("Країна"), dd]))
	if cur >= 0:
		cs = cs.filter(func(c): return by[cur].has(c.id))
	var groups := [["wait", "Чекають у відправників", "pin"], ["store", "На складах", "building"], ["move", "У рейсах", "road"]]
	for g in groups:
		var L: Array = cs.filter(func(c): return (c.st == "wait" and c.run < 0) if g[0] == "wait" else ((c.st == "ready" or c.st == "proc") and c.run < 0 if g[0] == "store" else (c.st == "move" or c.run >= 0)))
		if L.is_empty():
			continue
		var tons := 0.0
		for c in L:
			tons += c.k.tons
		body.add_child(Windows._sect("%s · %d · %s т" % [g[1], L.size(), Ui.loc(tons)]))
		var v := Ui.vbox(6)
		for c in L.slice(0, 60):
			v.add_child(cs_row(c))
		body.add_child(v)
		if L.size() > 60:
			body.add_child(Windows._note("…і ще %d" % (L.size() - 60), Ui.MUTED))


## the hub a pick-up starts from: the nearest with a free road vehicle, else the nearest on the land
func _pick_hub(c: Dictionary) -> int:
	var hs := sim.net_pick_from(c)
	if hs.size():
		return hs[0]
	var P: Dictionary = sim.PL[c.at]
	var best := -1
	var bd := 1e9
	for h in sim.CO.hubs:
		var q: Dictionary = sim.PL[h.pid]
		var d := JS.hypot(q.x - P.x, q.z - P.z)
		if q.land == P.land and d < bd:
			bd = d
			best = h.pid
	return best


func _run_of(c: Dictionary) -> Variant:
	for r in sim.CO.net.runs:
		if r.id == c.run:
			return r
	return null


func cs_row(c: Dictionary) -> PanelContainer:
	var k: Dictionary = c.k
	var cg: Dictionary = sim.cargo_i[k.cg]
	var left: float = c.dl - sim.co_now()
	var head := Ui.hbox(6, [w._place(k.from, 14), Ui.label("→", 14), w._place(k.to, 14), Ui.spacer(), Ui.num(Ui.usd(k.pay), 14)])
	var where := ""
	match c.st:
		"wait":
			where = "чекає у відправника в місті %s" % _pl(c.at) if c.at == k.from else "чекає в місті %s" % _pl(c.at)
		"proc":
			where = "обробка на складі %s · ще %s" % [_pl(c.at), Ui.days(maxf(0, c.rdy - sim.co_now()))]
		"ready":
			where = ("на складі %s" if sim.n_kind(c.at) == "hub" else "у терміналі партнера в %s") % _pl(c.at)
		"move":
			var r: Variant = _run_of(c)
			where = "у рейсі %s → %s" % [_pl(r.stops[r.i]), _pl(r.stops[mini(r.i + 1, r.stops.size() - 1)])] if r != null and r.st == "go" else "завантажується в %s" % _pl(c.at)
	if c.st != "move" and c.run >= 0:
		var r: Variant = _run_of(c)
		where += " · заброньовано на рейс" + ((" з %s" % _pl(r.stops[0])) if r != null else "")
	var line := Ui.rich(("[color=#5cc8f2]Контракт[/color] · " if k.get("ctr") != null else "") + "%s · %s т · %s · [color=#%s]%s[/color]%s" % [cg.n, Ui.loc(k.tons), where, _left_col(left).to_html(false), _left_s(left),
		(" · [color=#f1c453]пошкоджено %d%%[/color]" % int(c.dmg * 100)) if c.dmg > .02 else ""], 13)
	var mid := Ui.vbox(4, [head, line])
	if c.st != "move" and c.run < 0:
		var nx: Variant = sim.net_next(c)
		var acts := Ui.hbox(6)
		if nx != null:
			var wy := _way([nx], 12)
			var pth: Variant = c.nh.P if c.get("nh") != null else null
			wy.add_child(Ui.label("далі" + ((" · увесь шлях ≈ %s" % Ui.days(pth.t)) if pth != null else ""), 12, Ui.MUTED))
			wy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			acts.add_child(wy)
		else:
			acts.add_child(Ui.spacer())
		var cid: int = c.id
		# «На мапі»: waves where it is now and where it goes, as on the board
		var pk := {"id": -1000000 - cid, "from": c.at, "to": k.to, "cs": cid}
		var shown: bool = w.st.prev == pk.id
		acts.add_child(Windows._btn("Сховати" if shown else "На мапі", "sm", "mapIc", func():
			w.st.prev = -1 if shown else pk.id
			w.show_order.emit(null if shown else pk)))
		if c.st == "wait":
			# the same route panel as «Відправити»: from a hub with a free truck (or the nearest one) to the shipper,
			# on to the consignee, back to the hub; more towns can be added on the way
			var hb := _pick_hub(c)
			if hb >= 0:
				acts.add_child(Windows._btn("Забрати", "pri sm", "truck", func(): w.net_dialog.emit("route", {"a": hb, "focus": cid}), true,
					Windows._tip("Забрати", "Маршрут на мапі з хабу %s: клікайте міста по черзі — %s, щоб забрати вантаж, далі куди везти." % [_pl(hb), _pl(c.at)])))
			else:
				acts.add_child(Windows._btn("Забрати", "sm", "truck", func(): pass, false, "Немає хабу на цьому материку"))
		else:
			var b: int = nx.b if nx != null else k.to
			var m: String = nx.m if nx != null else "road"
			acts.add_child(Windows._btn("Відправити", "pri sm", "send", func(): w.net_dialog.emit("route", {"a": c.at, "m": m, "focus": cid}), c.st == "ready" or c.st == "proc",
				Windows._tip("Відправити", "Маршрут на мапі від міста %s: клікайте міста по черзі. Далі вантажу — %s." % [_pl(c.at), _pl(b)])))
		mid.add_child(acts)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Color(Ui.BAD, .5) if left < 0 else Ui.LINE, 1, Vector4(12, 8, 12, 8)))
	p.add_child(Ui.hbox(10, [Ui.icon(cg.ic, 18, Ui.ACCENT), mid]))
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


# ====================================================================== «Термінали» (the hub window of this mode)
## below the hubs in «Термінали»: the partners' terminals the company keeps cargo in, the lines
func sections(body: VBoxContainer) -> void:
	var CO := sim.CO
	var part := {}
	for c in CO.net.cs:
		if sim.n_kind(c.at) == "part" and (c.st == "ready" or c.st == "proc"):
			part[c.at] = part.get(c.at, 0) + 1
	if part.size():
		body.add_child(Windows._sect("Термінали партнерів"))
		for pid in part:
			var p_: int = pid
			body.add_child(Windows._lrow("handshake", Ui.vbox(2, [w._place(pid), Windows._note("Ваших вантажів: %d · зберігання дорожче, ніж у своєму хабі" % part[pid])]),
				Windows._btn("Створити маршрут", "sm", "road", func(): w.net_dialog.emit("route", {"a": p_}))))
	body.add_child(Windows._sect("Лінії за розкладом"))
	if CO.net.lines.is_empty():
		body.add_child(Windows._note("Ліній ще немає. «Керування терміналом» → «Створити маршрут», обрати, як часто повторювати, — і рейс ходитиме сам."))
	for L in CO.net.lines:
		body.add_child(_line_row(L))


## the facts of a terminal under a hub's name in «Термінали»
func term_facts(pid: int) -> Control:
	var stored := sim.n_stored(pid)
	var cap := sim.n_cap(pid)
	var q := sim.n_queue(pid)
	var fill := stored / cap if cap > 0 else 0.0
	var mt := Windows._meter(fill, Ui.BAD if fill > 1 else (Ui.WARN if fill > .85 else Ui.ACCENT))
	var v := Ui.vbox(6, [Ui.hbox(10, [Ui.label("Склад %s / %s т · %s т/добу · черга %s" % [Ui.loc(stored), Ui.grp(cap), Ui.grp(sim.n_thr(pid)), Ui.days(q) if q > .05 else "немає"], 13, Ui.BAD if fill > 1 else Ui.FG2), mt])])
	var T: Dictionary = sim._T(pid)
	var pills := HFlowContainer.new()
	pills.add_theme_constant_override("h_separation", 6)
	pills.add_theme_constant_override("v_separation", 6)
	for M in SimNet.NET_MODS:
		if T.mods.has(M.id):
			pills.add_child(Ui.pill(M.n, "good", M.ic))
	for U in SimNet.NET_UPS:
		var lv := sim.n_up(pid, U.id)
		if lv:
			pills.add_child(Ui.pill(U.n + (" %d" % lv if U.cost.size() > 1 else ""), "good", U.ic))
	for e in T.ev:
		if e.until > sim.co_now():
			pills.add_child(Ui.pill("%s · ще %s" % [SimNet.NET_EV[e.k][0], Ui.days(e.until - sim.co_now())], "bad", SimNet.NET_EV[e.k][1]))
	if pills.get_child_count():
		v.add_child(pills)
	return v


## «Керування терміналом»: the hub's level, the warehouse, modules and upgrades, partner freight, the events,
## this terminal's lines; «Кільцевий рейс» and «Створити маршрут» (the route on the map). Built again after
## every purchase; done closes it
func manage(pid: int, done: Callable) -> Control:
	var box := Ui.vbox(12)
	box.custom_minimum_size.x = 700
	var redraw := func(): pass
	redraw = func():
		for ch in box.get_children():
			ch.queue_free()
		_manage_fill(box, pid, done, redraw)
	redraw.call()
	return box


func _manage_fill(box: VBoxContainer, pid: int, done: Callable, redraw: Callable) -> void:
	var CO := sim.CO
	var h: Variant = sim.hub_at(pid)
	if h == null:
		box.add_child(Windows._note("Хабу тут більше немає."))
		return
	var p: Dictionary = sim.PL[pid]
	var T: Dictionary = sim._T(pid)
	var act := func(res: Dictionary) -> void:
		w._do(res)
		redraw.call()
	# the terminal now
	var stored := sim.n_stored(pid)
	var cap := sim.n_cap(pid)
	var q := sim.n_queue(pid)
	box.add_child(Windows._grid(4, [
		Windows._stat("Рівень хабу", "%d з 4" % h.lvl, "техніки до %d" % D.HUB_VEH[h.lvl]),
		Windows._stat("Склад", "%s / %s т" % [Ui.loc(stored), Ui.grp(cap)], "переповнений" if stored > cap else "вантажів: %d" % CO.net.cs.filter(func(c): return c.at == pid and (c.st == "ready" or c.st == "proc")).size(), "", "bad" if stored > cap else ""),
		Windows._stat("Пропускна здатність", "%s т/добу" % Ui.grp(sim.n_thr(pid)), "черга " + (Ui.days(q) if q > .05 else "порожня")),
		Windows._stat("Техніка тут", str(sim.net_idle_at(pid).size()), "вільної зараз")], 8))
	for e in T.ev:
		if e.until > sim.co_now():
			box.add_child(Windows._icl(SimNet.NET_EV[e.k][1], "%s · ще %s" % [SimNet.NET_EV[e.k][0], Ui.days(e.until - sim.co_now())], Ui.BAD))
	# the hub's level
	box.add_child(Windows._sect("Рівень хабу"))
	if h.lvl < 4:
		var up: float = sim.hub_cost(p) * D.HUB_UP[h.lvl]
		var n2: int = h.lvl + 1
		var tip := Windows._tip(sim.hub_lv(n2), "Склад %s → %s т, пропускна здатність %s → %s т/добу. Техніки в хабі: %d → %d. Робочих місць: +%d. Більше замовлень поблизу й +3 місця на біржі. Оренда %s/міс." % [
			Ui.grp(SimNet.NET_CAP[h.lvl]), Ui.grp(SimNet.NET_CAP[n2]), Ui.grp(SimNet.NET_THR[h.lvl]), Ui.grp(SimNet.NET_THR[n2]), D.HUB_VEH[h.lvl], D.HUB_VEH[n2],
			D.HUB_STAFF[n2] - D.HUB_STAFF[h.lvl], Ui.usd(D.HUB_RENT[n2] * sim.price_k(p.cid))])
		var b := Windows._btn("%s · %s" % [sim.hub_lv(n2), Ui.usd(up)], "sm", "up", func(): act.call(sim.act_hub_up(pid)), CO.cash >= up, tip)
		box.add_child(Ui.hbox(10, [Windows._note("Склад %s → %s т · пропускна здатність %s → %s т/добу · техніки %d → %d" % [Ui.grp(SimNet.NET_CAP[h.lvl]), Ui.grp(SimNet.NET_CAP[n2]),
			Ui.grp(SimNet.NET_THR[h.lvl]), Ui.grp(SimNet.NET_THR[n2]), D.HUB_VEH[h.lvl], D.HUB_VEH[n2]]), b]))
	else:
		box.add_child(Ui.pill(sim.hub_lv(4) + " — найвищий рівень", "good", "star"))
	# modules and upgrades
	box.add_child(Windows._sect("Модулі й покращення"))
	var mods := HFlowContainer.new()
	mods.add_theme_constant_override("h_separation", 6)
	mods.add_theme_constant_override("v_separation", 6)
	for M in SimNet.NET_MODS:
		if not sim.mode_ok(M.id, p):
			continue
		var mid: String = M.id
		if T.mods.has(mid):
			var pl := Ui.pill(M.n, "good", M.ic)
			pl.tooltip_text = Windows._tip(M.n, M.d)
			mods.add_child(pl)
		else:
			var c := sim.net_mod_cost(pid, mid)
			mods.add_child(Windows._btn("%s · %s" % [M.n, Ui.usd(c)], "sm", M.ic, func(): act.call(sim.act_net_mod(pid, mid)), CO.cash >= c, Windows._tip(M.n, M.d + " Утримання 1% вартості на місяць.")))
	for U in SimNet.NET_UPS:
		var uid: String = U.id
		var lv := sim.n_up(pid, uid)
		var c := sim.net_up_cost(pid, uid)
		if c < 0:
			var pl := Ui.pill(U.n + (" %d" % lv if U.cost.size() > 1 else ""), "good", U.ic)
			pl.tooltip_text = Windows._tip(U.n, U.d)
			mods.add_child(pl)
		else:
			mods.add_child(Windows._btn("%s%s · %s" % [U.n, (" %d" % (lv + 1)) if U.cost.size() > 1 else "", Ui.usd(c)], "sm", U.ic, func(): act.call(sim.act_net_up(pid, uid)), CO.cash >= c, Windows._tip(U.n, U.d)))
	box.add_child(mods)
	# partner freight
	var est: float = 3.0 * h.lvl * (1 + T.mods.size() * 1.2) * sqrt(maxf(.2, p.pop)) * (5 + 9 * T.mods.size()) * sim.price_k(p.cid)
	var seg := Ui.seg([[0, "Закрито"], [1, "Частково"], [2, "Повністю"]], int(T.part), func(x):
		sim.act_net_part(pid, x)
		act.call({}))
	var pn := Windows._note("Транзит партнерів: ≈ %s/день, −%d%% пропускної здатності" % [Ui.usd(est * (0.0 if T.part == 0 else (.5 if T.part == 1 else 1.0))), 18 * int(T.part)], Ui.FG2, 12)
	pn.tooltip_text = Windows._tip("Транзит партнерів", "Інші перевізники платять за перевалку своїх вантажів у вашому терміналі. Що вищий рівень хабу й більше модулів, то більше вони везуть — і то більше пропускної здатності забирають у ваших вантажів.")
	box.add_child(Ui.hbox(10, [Ui.icon("handshake", 16, Ui.FG2), pn, seg]))
	# this terminal's lines
	var mine: Array = CO.net.lines.filter(func(L): return L.a == pid)
	if mine.size():
		box.add_child(Windows._sect("Лінії звідси"))
		for L in mine:
			box.add_child(_line_row(L, redraw))
	# the runs
	box.add_child(Windows._card_rule())
	var idle_r := sim.net_idle_at(pid, "road").size()
	box.add_child(Ui.hbox(10, [Ui.spacer(),
		Windows._btn("Кільцевий рейс", "sm", "refresh", func():
			done.call()
			w.net_dialog.emit("round", {"a": pid}), idle_r > 0, Windows._tip("Кільцевий рейс", "Машина з цього хабу сама розвезе вантажі зі складу по містах округи й забере те, що там чекає, — і повернеться.") if idle_r else "Немає вільної авто-техніки в цьому хабі"),
		Windows._btn("Створити маршрут", "pri", "road", func():
			done.call()
			w.net_dialog.emit("route", {"a": pid}), true, Windows._tip("Створити маршрут", "Маршрут на мапі: клікайте міста по черзі — де доставити й де забрати вантаж, — останнім хаб, куди машина повезе решту. Обираєте техніку й як часто повторювати."))]))


func _line_row(L: Dictionary, after: Callable = Callable()) -> PanelContainer:
	var who := "партнер"
	if L.get("vid", -1) >= 0:
		var v: Variant = sim._veh(L.vid)
		who = D.VT[v.t].n if v != null else "техніки немає"
	var sub := "%s · кожні %d дн. · %s" % [who, L.every, ("рушить за %s" % Ui.days(maxf(0, L.next - sim.day))) if L.on else "на паузі"]
	if L.get("every", 1) == 0:
		sub = "%s · один рейс, коли заповнення досягне %d%%" % [who, int(L.fill * 100)]
	if L.get("why", "") != "":
		sub += " · " + L.why
	if L.get("last", {}).size():
		sub += " · останній: +%s / −%s" % [Ui.usd(L.last.rev), Ui.usd(L.last.cost)]
	var id: int = L.id
	var right := Windows._right([Windows._toggle(L.on, func():
		L.on = not L.on
		w._do({})
		if after.is_valid():
			after.call(), "Пауза / запуск"), Windows._btn("", "sm", "trash", func():
		sim.net_line_del(id)
		w._do({})
		if after.is_valid():
			after.call(), true, "Видалити лінію")])
	return Windows._lrow("refresh" if L.kind == "round" else MODE_IC.get(L.get("m", "road"), "truck"), Ui.vbox(2, [Windows._b(sim.net_line_name(L)), Windows._note(sub)]), right)


# ====================================================================== the run dialog
## kind "round" {a}, "trunk" {a, b?, m?}, "pick" {cs}; done: closes the dialog
func dialog(kind: String, args: Dictionary, done: Callable) -> Control:
	var st := {"kind": kind, "a": args.get("a", -1), "b": args.get("b", -1), "m": args.get("m", "road"), "vid": -2, "back": false, "skip": {}, "every": 3, "fill": .5,
		"cs": args.get("cs", -1), "to": -1, "from": -1}
	if args.has("way"):
		st.way = args.way.duplicate()
	var box := Ui.vbox(12)
	box.custom_minimum_size.x = 700
	var redraw := func(): pass
	redraw = func():
		for ch in box.get_children():
			ch.queue_free()
		_dialog_fill(box, st, done, redraw)
	redraw.call()
	return box


## the stops of a haul: the start, then every stop with what it is for and ↑ ↓ ✕; «Додати зупинку» lists the
## places on the way (the cargo's towns and next steps, pick-ups nearby, hubs) with the detour each costs, and
## puts the chosen one where it lengthens the way the least; «Попутні» adds the ones worth it
func way_editor(st: Dictionary, redraw: Callable) -> Control:
	var v := Ui.vbox(6)
	var way: Array = st.way
	var cnt: Dictionary = st.get("cnt", {})   # stop index (0 — the start) → [loaded, unloaded] on this run
	# a stop: ↓ where cargo is loaded, ↑ where it is unloaded (a count when several), the town's name
	var planned: bool = st.get("planned", false)   # the route panel: what the plan does, no guesses
	var arrow := func(t: String, tip: String) -> Label:
		var l := Ui.label(t, 15, Ui.FG2, Ui.font("body", 700))
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		return l
	var row := func(i: int, pid: int, note: String) -> Control:
		var h := Ui.hbox(6)
		var on := 0
		var off := 0
		if cnt.has(i):
			on = cnt[i][0]
			off = cnt[i][1]
		elif i > 0 and not planned:   # no plan yet: what could happen there
			for c in sim.CO.net.cs:
				if c.run < 0 and c.st != "move":
					if c.k.to == pid and (c.at == st.a or way.slice(0, i - 1).has(c.at)):
						off += 1
					if c.at == pid:
						on += 1
		# ↓ loading, ↑ unloading, ← the start of an empty run; a tooltip on each
		var marks := Ui.hbox(2)
		marks.custom_minimum_size.x = 30
		if i == 0 and on == 0 and way.size():
			marks.add_child(arrow.call("←", "Перегін: машина їде з %s порожньою до першої зупинки" % _pl(pid)))
		if on > 0:
			marks.add_child(arrow.call("↓", "Завантаження" + ((" · %d" % on) if on > 1 else "")))
		if off > 0:
			marks.add_child(arrow.call("↑", "Вивантаження" + ((" · %d" % off) if off > 1 else "")))
		if marks.get_child_count() == 0:
			marks.add_child(Ui.icon(MODE_IC[st.m] if i > 0 else ("building" if sim.hub_at(pid) != null else "pin"), 14, Ui.MUTED))
		h.add_child(marks)
		h.add_child(Windows._b(_pl(pid), 13))
		for e in [on, off]:
			if e > 1:   # several in one town: a count, like a fleet's ×N
				h.add_child(Ui.pill("×%d" % e))
		if note != "":
			h.add_child(Ui.label(note, 12, Ui.MUTED))
		return h
	v.add_child(row.call(0, st.a, ""))
	for i in way.size():
		v.add_child(row.call(i + 1, way[i], ""))
	if st.get("auto_end", -1) >= 0 and way.size():   # the nearest hub, added for the cargo picked up on the way
		var r: Control = row.call(way.size() + 1, st.auto_end, "")
		r.tooltip_text = "Маршрут закінчується містом, де вантаж не вивантажується: машина відвезе його в найближчий хаб і залишить на складі. Клікніть інший хаб останнім, щоб везти туди."
		r.modulate.a = .75
		v.add_child(r)
	if st.get("back", false) and way.size():
		v.add_child(Ui.hbox(8, [Ui.icon(MODE_IC[st.m], 14, Ui.ACCENT), Windows._b(_pl(st.a), 13), Ui.label("назад", 12, Ui.MUTED)]))
	# a town picked from the list goes to the end of the route, as a click on the map does
	var cands := sim.net_way_cands(st.a, way, st.m, st.get("back", false))
	var opts := []
	for x in cands.slice(0, 14):
		var why := []
		if x.to > 0:
			why.append("%s т туди" % Ui.loc(x.to))
		if x.nx > 0:
			why.append("%s т далі звідти" % Ui.loc(x.nx))
		if x.pick > 0:
			why.append("забрати %s т" % Ui.loc(x.pick))
		if why.is_empty():
			why.append("хаб")
		opts.append([x.pid, "%s · %s" % [_pl(x.pid), ", ".join(why)], "building" if sim.hub_at(x.pid) != null else "pin"])
	if opts.size():
		var dd := Dropdown.make(opts, null, func(pid):
			way.append(pid)
			redraw.call())
		dd.placeholder = "Додати замовлення"
		dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Ui.margin(dd, 0, 4, 0, 0))
	return v


## the vehicles that can do the run, and a partner
func _carriers(a: int, m: String, partner: bool) -> Array:
	var out := []
	for v in sim.net_idle_at(a, m):
		var T: Dictionary = D.VT[v.t]
		out.append([v.id, "%s #%d · %s т" % [T.n, v.id, Ui.loc(T.cap)], T.ic])
	if partner:
		out.append([-1, "Партнер-перевізник", "handshake"])
	return out


func _dialog_fill(box: VBoxContainer, st: Dictionary, done: Callable, redraw: Callable) -> void:
	var CO := sim.CO
	var spec := {}
	var field := func(name: String, ctl: Control) -> Control:
		var l := Ui.lbl(name)
		l.custom_minimum_size.x = 120
		return Ui.hbox(12, [l, ctl])
	match st.kind:
		"round":
			var cars := _carriers(st.a, "road", false)
			if cars.is_empty():
				box.add_child(Windows._note("У хабі %s немає вільної авто-техніки." % _pl(st.a)))
				return
			if st.vid == -2 or not cars.any(func(x): return x[0] == st.vid):
				st.vid = cars[0][0]
			box.add_child(field.call("Техніка", Dropdown.make(cars, st.vid, func(x):
				st.vid = x
				redraw.call())))
			spec = sim.net_auto_round(st.a, st.vid, st.skip)
		"trunk":
			var A: Dictionary = sim.PL[st.a]
			var ms := ["road", "rail", "sea", "air"].filter(func(m): return sim.node_ok(m, A))
			if not ms.has(st.m):
				st.m = "road"
			box.add_child(field.call("Вид транспорту", Ui.seg(ms.map(func(m): return [m, MODE_N[m]]), st.m, func(x):
				st.m = x
				st.way = []
				st.vid = -2
				redraw.call())))
			var cars := _carriers(st.a, st.m, true)
			if st.vid == -2 or not cars.any(func(x): return x[0] == st.vid):
				st.vid = cars[0][0]
			box.add_child(field.call("Хто везе", Ui.hbox(12, [Dropdown.make(cars, st.vid, func(x):
				st.vid = x
				redraw.call()), Windows._icl("refresh", "і назад з вантажем", Ui.FG2), Windows._toggle(st.back, func():
					st.back = not st.back
					redraw.call(), "Рейс повернеться сюди й забере на зворотному шляху вантажі, що чекають для цього терміналу")])))
			# the way: the stops after the start, in order; the first time — the destination asked for, or the stops
			# the cargo here is for
			if not st.has("way"):
				st.way = [st.b] if st.b >= 0 and st.b != st.a and sim.node_ok(st.m, sim.PL[st.b]) else []
			st.way = st.way.filter(func(p): return sim.node_ok(st.m, sim.PL[p]))
			if st.way.is_empty() and not st.get("way_auto", false):
				st.way_auto = true
				st.way = sim.net_way_auto(st.a, [], st.m, st.back)
			box.add_child(field.call("Зупинки", way_editor(st, redraw)))
			if st.way.is_empty():
				box.add_child(Windows._note("Додайте зупинку: місто, куди везете, або термінал, де вантаж поїде далі.", Ui.MUTED))
				return
			spec = sim.net_auto_multi(st.a, st.way, st.m, st.vid, st.back, st.skip)
		"pick":
			var c: Variant = sim._cs(st.cs)
			if c == null or c.st != "wait":
				box.add_child(Windows._note("Цей вантаж уже не чекає на забір."))
				return
			var hubs := sim.net_pick_from(c)
			var cars := []
			for pid in hubs:
				for v in sim.net_idle_at(pid, "road"):
					cars.append([v.id, "%s #%d · з хабу %s" % [D.VT[v.t].n, v.id, _pl(pid)], D.VT[v.t].ic])
			cars.append([-1, "Партнер-перевізник", "handshake"])
			if st.vid == -2 or not cars.any(func(x): return x[0] == st.vid):
				st.vid = cars[0][0]
			box.add_child(field.call("Хто забере", Dropdown.make(cars, st.vid, func(x):
				st.vid = x
				redraw.call())))
			var start: int = sim._veh(st.vid).loc if st.vid >= 0 else c.at
			var tos := []
			for h in CO.hubs:
				if sim.PL[h.pid].land == sim.PL[c.at].land:
					tos.append([h.pid, "у хаб %s" % _pl(h.pid), "building"])
			tos.append([c.k.to, "одразу до одержувача в %s" % _pl(c.k.to), "pin"])
			if st.to < 0 or not tos.any(func(x): return x[0] == st.to):
				st.to = start if st.vid >= 0 and sim.hub_at(start) != null else tos[0][0]
			box.add_child(field.call("Куди", Dropdown.make(tos, st.to, func(x):
				st.to = x
				redraw.call())))
			# what else waits in that town goes along
			var to_t: bool = sim.n_kind(st.to) == ""   # straight to a town: only what is for that town
			var here: Array = CO.net.cs.filter(func(x): return x.at == c.at and x.st == "wait" and x.run < 0 and not st.skip.has(x.id) and (not to_t or x.k.to == st.to))
			if st.vid >= 0:
				var T: Dictionary = D.VT[sim._veh(st.vid).t]
				var t := 0.0
				var ids := []
				for x in here:
					if t + x.k.tons <= T.cap:
						t += x.k.tons
						ids.append(x.id)
				var stops := [start, c.at]
				if st.to != c.at:
					stops.append(st.to)
				spec = {"vid": st.vid, "stops": stops, "picks": {1: ids}}
			else:
				spec = {"vid": -1, "m": "road", "stops": [c.at, st.to], "picks": {0: here.map(func(x): return x.id)}}
	if spec.is_empty():
		return
	var C := sim.net_calc(spec)
	# the course and what goes on it
	var chain := HFlowContainer.new()
	chain.add_theme_constant_override("h_separation", 6)
	for i in spec.stops.size():
		if i:
			chain.add_child(Ui.label("→", 13, Ui.MUTED))
			chain.add_child(Ui.icon(MODE_IC[D.VT[sim._veh(spec.vid).t].mode] if spec.vid >= 0 else MODE_IC[spec.get("m", "road")], 14, Ui.ACCENT))
			chain.add_child(Ui.label("→", 13, Ui.MUTED))
		chain.add_child(Windows._b(_pl(spec.stops[i]), 13))
	chain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if st.kind != "trunk":
		box.add_child(field.call("Маршрут", chain))
	var rows := Ui.vbox(4)
	var all := {}
	for row in C.rows:
		all[row.c.id] = row
	# the booked ones and the ones left out (to put back)
	var listed := []
	for row in C.rows:
		listed.append(row.c)
	for id in st.skip:
		var c: Variant = sim._cs(id)
		if c != null:
			listed.append(c)
	if listed.is_empty():
		rows.add_child(Windows._note("Вантажів для цього рейсу зараз немає.", Ui.MUTED))
	for c in listed:
		var row: Variant = all.get(c.id)
		var cid: int = c.id
		var on: bool = row != null
		var txt := "%s → %s · %s · %s т" % [_pl(c.k.from), _pl(c.k.to), sim.cargo_i[c.k.cg].n, Ui.loc(c.k.tons)]
		var tail := ""
		if on:
			tail = ("доставка %s" if row.dest else "до складу %s") % ("вчасно" if row.late <= 0 else "[color=#f0625f]із запізненням %s[/color]" % Ui.days(row.late)) if row.dest else "вивантаження в %s" % _pl(spec.stops[row.off])
			if row.on > 0:   # picked up on the way
				tail = "забрати в %s · %s" % [_pl(spec.stops[row.on]), tail]
		var r := Ui.rich("%s%s" % [txt, (" · " + tail) if tail != "" else " · [color=#8a96a3]не їде[/color]"], 13)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(Ui.hbox(10, [Windows._toggle(on, func():
			if st.skip.has(cid):
				st.skip.erase(cid)
			else:
				st.skip[cid] = true
			redraw.call()), r]))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = mini(300, 30 + listed.size() * 30)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(rows)
	box.add_child(sc)
	# the sums
	var facts := Windows._grid(4, [
		Windows._stat("Заповнення", ("%d%%" % int(C.fill * 100)) if spec.vid >= 0 else "%s т" % Ui.loc(C.tons), "%s т" % Ui.loc(C.tons) if spec.vid >= 0 else "партнер бере будь-яку вагу", "", "bad" if C.get("over") else ""),
		Windows._stat("Час", Ui.days(C.t), "з обробкою на складах"),
		Windows._stat("Витрати", Ui.usd(C.c), "пальне, екіпаж, збори" if spec.vid >= 0 else "тариф і збори партнера"),
		Windows._stat("Оплата в рейсі", Ui.usd(C.rev), "за доставлені цим рейсом", "", "good" if C.rev > C.c else "")])
	box.add_child(facts)
	if spec.vid >= 0:
		box.add_child(Windows._meter(C.fill, Ui.BAD if C.fill > 1 else Ui.ACCENT))
	if not C.ok:
		box.add_child(Windows._icl("alert", C.why, Ui.WARN))
	var go := Windows._btn("Відправити", "pri", "send", func():
		var res := sim.net_go(spec)
		done.call()
		w._do(res), C.ok)
	var bs := Ui.hbox(10, [Ui.spacer(), go])
	box.add_child(Windows._card_rule())
	if st.kind != "pick":
		var ev := Ui.seg([[1, "щодня"], [2, "2 дн."], [3, "3 дн."], [5, "5 дн."], [7, "тиждень"]], st.every, func(x): st.every = x)
		var fl := Ui.seg([[0.0, "будь-яке"], [.3, "30%"], [.6, "60%"], [.9, "90%"]], st.fill, func(x): st.fill = x)
		var mk := Windows._btn("Створити лінію", "sm", "refresh", func():
			var L := {"kind": st.kind, "a": st.a, "b": st.way.back() if st.kind == "trunk" else -1, "way": st.get("way", []).duplicate(), "m": st.m, "vid": spec.vid, "back": st.back,
				"every": st.every, "fill": st.fill, "next": sim.day}
			var res := sim.net_line_add(L)
			done.call()
			w._do(res), true, Windows._tip("Лінія за розкладом", "Такий рейс повторюватиметься сам: щоразу з тим, що на той момент чекає. Рушає, коли заповнення не менше обраного (або коли вантаж інакше запізниться). Досвіду за рейси ліній менше, ніж за сплановані вручну."))
		box.add_child(Ui.hbox(10, [Ui.lbl("Лінія"), ev, Ui.lbl("заповнення від"), fl, Ui.spacer(), mk]))
	box.add_child(bs)
