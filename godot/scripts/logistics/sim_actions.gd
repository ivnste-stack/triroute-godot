class_name SimActions
extends SimIncidents
## What the player does (the ACT.co* handlers of the HTML version, 08e-company.js, 08g-business.js,
## 08v-cons.js, 08w-move.js): buy, sell and repair vehicles, hire staff and managers, wages, hubs, advertising,
## licences, permits, upgrades, loans, insurance, maintenance, sending an order, cancelling a trip, moving a
## vehicle to another hub. Every action returns what the interface shows: {} or {tone, t (title), d (text)}.

const HUB_STAFF := [0, 12, 40, 150, 400]


static func _toast(tone: String, t: String, d: String = "") -> Dictionary:
	return {"tone": tone, "t": t, "d": d}


static func usd_s(v: float, sign: bool = false) -> String:
	var s := "+" if sign and v > 0 else ""
	var n := "−" if v < 0 else ""
	var a := absf(v)
	var t: String
	if a >= 1e9:
		t = "%.2f млрд" % (a / 1e9)
	elif a >= 1e6:
		t = ("%." + str(0 if a >= 1e8 else (1 if a >= 1e7 else 2)) + "f млн") % (a / 1e6)
	elif a >= 1e4:
		t = "%.0f тис." % (a / 1e3)
	elif a >= 1e3:
		t = "%.1f тис." % (a / 1e3)
	else:
		t = "%.0f" % a
	return s + n + "$" + t


func staff_cap() -> int:
	var n := 6
	for h in CO.hubs:
		n += HUB_STAFF[h.lvl]
	return n


func staff_total() -> int:
	var n := 0
	for r in CO.staff:
		n += CO.staff[r]
	return n


func hub_abroad(p: Dictionary) -> bool:
	return CO.hq != null and p.cid != PL[CO.hq].cid


func hub_open_cost(p: Dictionary) -> float:
	return JS.round_js(hub_cost(p) * .1) if hub_abroad(p) else hub_cost(p)


func co_rate() -> float:
	return JS.clamp_js(.07 + (5 - CO.rating) * .022 - msk("cfo") * .025, .03, .2)


func loans_left() -> float:
	var a := 0.0
	for l in CO.loans:
		a += l.left
	return a


# ---------- vehicles ----------
func act_buy(t: String) -> Dictionary:
	var T: Dictionary = D.VT[t]
	if CO.tier < T.tier:
		return {}
	if CO.cash < T.cost:
		return _toast("warn", "Бракує грошей", "%s коштує %s" % [T.n, usd_s(T.cost)])
	var hubs: Array = CO.hubs.filter(func(h): return mode_ok(T.mode, PL[h.pid]))
	if T.mode == "local":
		hubs = CO.hubs
	if hubs.is_empty():
		return _toast("warn", "Немає відповідного хабу", "Потрібен хаб у портовому місті" if T.mode == "sea" else ("Потрібен хаб у місті з аеропортом" if T.mode == "air" else "Потрібен хаб біля залізничної станції"))
	var h: Variant = null
	for x in hubs:
		if x.pid == CO.get("buyAt"):
			h = x
	if h == null:
		for x in hubs:
			if x.pid == CO.hq:
				h = x
	if h == null:
		h = hubs[0]
	var note := ""
	if hub_veh_n(h.pid) >= hub_veh_cap(h):
		var o: Variant = null
		for x in hubs:
			if hub_veh_n(x.pid) < hub_veh_cap(x):
				o = x
				break
		if o == null:
			return _toast("warn", "Хаби заповнені", "%s у місті %s вміщує %d од. техніки. Покращіть хаб або відкрийте новий." % [D.HUB_LV[h.lvl], PL[h.pid].name, hub_veh_cap(h)])
		note = "%s: місця немає, техніку поставлено в хаб %s" % [PL[h.pid].name, PL[o.pid].name]
		h = o
	CO.cash -= T.cost
	CO.veh.append({"id": CO.uid, "t": t, "loc": h.pid, "st": "idle", "cond": 100.0, "km": 0.0})
	CO.uid += 1
	return _toast("good", "Куплено: " + T.n, note if note else "%s · %s" % [PL[h.pid].name, usd_s(T.cost)])


## sell one idle vehicle of a type at a place
func act_sell(t: String, loc: int) -> Dictionary:
	for v in CO.veh:
		if v.t == t and v.st == "idle" and v.loc == loc:
			var T: Dictionary = D.VT[t]
			var p := JS.round_js(T.cost * (.25 + .35 * v.cond / 100))
			CO.cash += p
			_drop(CO.veh, v)
			return _toast("", "Продано: " + T.n, usd_s(p, true))
	return {}


func repair_cost(t: String, loc: int) -> float:
	var s := 0.0
	for v in CO.veh:
		if v.t == t and v.st == "idle" and v.loc == loc and v.cond < 99:
			s += D.VT[t].cost * (100 - v.cond) / 100 * .22
	return JS.round_js(s * rep_k())


func act_repair(t: String, loc: int) -> Dictionary:
	var vs: Array = CO.veh.filter(func(v): return v.t == t and v.st == "idle" and v.loc == loc and v.cond < 99)
	if vs.is_empty():
		return {}
	var c := repair_cost(t, loc)
	if CO.cash < c:
		return _toast("warn", "Бракує грошей", "Ремонт " + usd_s(c))
	CO.cash -= c
	CO.m.upkeep += c
	for v in vs:
		v.cond = 100.0
	return _toast("good", "Техніку відремонтовано", usd_s(c))


func act_maint(v: int) -> void:
	CO.maint = v


func act_buy_at(pid: int) -> void:
	CO.buyAt = pid


# ---------- staff and managers ----------
func hire_fee(r: String, k: int) -> float:
	return JS.round_js(D.ROLE[r].w * wage_k(me) * .5 * absi(k) * (1 - msk("hro") * .3))


## k > 0 hires, k < 0 lays off
func act_hire(r: String, k: int) -> Dictionary:
	if k > 0:
		k = mini(k, int(floor(CO.pool.get(r, 0))))
		if k <= 0:
			return _toast("warn", "Ринок праці вичерпано", "%s: нові кандидати з'являться наступного місяця. Підвищення зарплат і HR-директор приводять більше людей." % D.ROLE[r].n)
	var fee := hire_fee(r, k)
	if k > 0:
		var room := staff_cap() - staff_total()
		if room <= 0:
			return _toast("warn", "Немає робочих місць", "Хаби вміщують %d працівників. Покращіть хаби або відкрийте нові." % staff_cap())
		if k > room:
			k = room
		if CO.cash < fee:
			return _toast("warn", "Бракує грошей", "Найм коштує " + usd_s(fee))
		CO.cash -= fee
		CO.m.wage += fee
		CO.staff[r] += k
		CO.pool[r] -= k
	else:
		var q := mini(CO.staff[r], -k)
		if not q:
			return {}
		var sev := JS.round_js(D.ROLE[r].w * wage_k(me) * CO.wageLv * q)
		CO.cash -= sev
		CO.m.wage += sev
		CO.staff[r] -= q
		CO.morale -= q * .6
	return {}


func act_wage(level: float) -> void:
	CO.wageLv = level


func act_hire_mgr(id: String, i: int) -> Dictionary:
	var g: Dictionary = CO.cand[id][i]
	if CO.cash < g.sal:
		return _toast("warn", "Бракує грошей", "Підписний бонус — місячна зарплата")
	CO.cash -= g.sal
	CO.m.mgmt += g.sal
	CO.mgr[id] = g.duplicate()
	CO.cand.erase(id)
	var n := ""
	for s in D.MG:
		if s.id == id:
			n = s.n
	return _toast("good", "Менеджера найнято", "%s · %s" % [g.name, n])


func act_fire_mgr(id: String) -> Dictionary:
	var g: Dictionary = CO.mgr[id]
	CO.cash -= g.sal
	CO.m.mgmt += g.sal
	CO.mgr.erase(id)
	co_mgr_cand(id)
	if id == "cto":
		CO.auto = false
	return {}


func act_recand(id: String) -> Dictionary:
	var c := JS.round_js(1500 * price_k(me))
	if CO.cash < c:
		return {}
	CO.cash -= c
	CO.m.other += c
	co_mgr_cand(id)
	return {}


# ---------- licences, permits, upgrades ----------
## coLicOK: the conditions of the next licence: {ok, r: [[met, what, have]…]}
func lic_ok() -> Dictionary:
	if CO.tier + 1 >= D.LIC.size():
		return {"ok": false, "r": []}
	var n: Dictionary = D.LIC[CO.tier + 1]
	var r := []
	r.append([CO.rating >= n.rat, "Рейтинг %.1f" % n.rat, "%.2f" % CO.rating])
	r.append([CO.cdel >= n.del, "Доставок %d" % n.del, str(int(CO.cdel))])
	if n.con > 0:
		r.append([CO.cdel >= n.con, "Контрактів %d" % n.con, str(int(CO.cdel))])
	if n.get("xp", 0) > 0:
		r.append([CO.get("xp", 0) >= n.xp, ("Грейд «%s»" % D.GRADES[n.gr].n) if n.get("gr") != null else "Досвід %d" % n.xp, D.GRADES[co_grade()].n])
	r.append([CO.cash >= n.cost, "Внесок " + usd_s(n.cost), usd_s(CO.cash)])
	return {"ok": r.all(func(x): return x[0]), "r": r}


func act_lic() -> Dictionary:
	if CO.tier + 1 >= D.LIC.size() or not lic_ok().ok:
		return {}
	var n: Dictionary = D.LIC[CO.tier + 1]
	CO.cash -= n.cost
	CO.tier += 1
	if CO.tier == 2:
		co_tender_offers()
	co_news("good", "doc", "%s отримала ліцензію «%s»" % [CO.name, n.n])
	return {"tone": "good", "t": n.n, "d": n.d, "lic": true}


func act_perm(id: String) -> Dictionary:
	var p: Dictionary = perm_i[id]
	if CO.tier < p.tier:
		return {}
	if p.get("need") and not perm_ok(p.need):
		return _toast("warn", "Спершу потрібна інша ліцензія", perm_i[p.need].n)
	var f := perm_fee(id)
	if CO.cash < f:
		return _toast("warn", "Бракує грошей", usd_s(f))
	if not CO.has("perm"):
		CO.perm = {}
	var cur: Variant = CO.perm.get(id)
	CO.cash -= f
	CO.m.other += f
	var renew: bool = cur != null and cur.until > day
	CO.perm[id] = {"until": maxf(day, cur.until if cur != null else 0.0) + 365, "auto": cur.auto if cur != null else true}
	return _toast("good", "Ліцензію продовжено" if renew else "Ліцензію отримано", "%s · %s на рік" % [p.n, usd_s(f)])


func act_perm_auto(id: String) -> void:
	if CO.has("perm") and CO.perm.has(id):
		CO.perm[id].auto = not CO.perm[id].auto


func upg_cost(u: Dictionary) -> float:
	return JS.round_js(u.cost * (.6 + .4 * CO.get("parts", 1.0)))


func act_upg(id: String) -> Dictionary:
	var u: Variant = null
	for x in D.UPG:
		if x.id == id:
			u = x
	if u == null or has_u(id) or CO.tier < u.tier:
		return {}
	var c := upg_cost(u)
	if CO.cash < c:
		return _toast("warn", "Бракує грошей", usd_s(c))
	CO.cash -= c
	CO.m.other += c
	if not CO.has("upg"):
		CO.upg = {}
	CO.upg[id] = {"d": day}
	return _toast("good", "Модернізацію впроваджено", u.n)


# ---------- hubs ----------
func act_hub(pid: int) -> Dictionary:
	var p: Dictionary = PL[pid]
	if hub_at(pid) != null or not co_scope(p):
		return {}
	var ab := hub_abroad(p)
	var c := hub_open_cost(p)
	if CO.cash < c:
		return _toast("warn", "Бракує грошей", ("Застава за оренду хаба " if ab else "Хаб коштує ") + usd_s(c))
	CO.cash -= c
	var h := {"pid": pid, "lvl": 1, "share": .01, "mk": 0}
	if ab:
		h.rent = 1
	CO.hubs.append(h)
	co_news("good", "building", "%s %s хаб у місті %s (%s)" % [CO.name, "орендувала" if ab else "відкрила", p.name, states[p.cid].name])
	if p.cid != me:
		CO.flags.abroad = 1
	return _toast("good", "Хаб в оренді" if ab else "Новий хаб", ("%s: оренда %s/міс." % [p.name, usd_s(hub_rent_m(h))]) if ab else p.name)


func act_hub_up(pid: int) -> Dictionary:
	var h: Variant = hub_at(pid)
	if h == null or h.lvl >= 4:
		return {}
	if h.get("rent") and h.lvl >= 2:
		return _toast("warn", "Орендований хаб", "Орендодавець дозволяє розширити його лише до 2 рівня")
	var c: float = hub_cost(PL[h.pid]) * D.HUB_UP[h.lvl]
	if CO.cash < c:
		return _toast("warn", "Бракує грошей", usd_s(c))
	CO.cash -= c
	h.lvl += 1
	return _toast("good", D.HUB_LV[h.lvl], PL[h.pid].name)


func act_hub_close(pid: int) -> Dictionary:
	if pid == CO.hq:
		return {}
	var h: Variant = hub_at(pid)
	if h == null:
		return {}
	_drop(CO.hubs, h)
	if not h.get("rent"):
		CO.cash += hub_cost(PL[pid]) * h.lvl * .3
	return _toast("", "Оренду хаба припинено" if h.get("rent") else "Хаб закрито", PL[pid].name)


func act_mk(pid: int, v: float) -> void:
	var h: Variant = hub_at(pid)
	if h != null:
		h.mk = v


# ---------- finance ----------
func act_ins() -> void:
	CO.ins = not CO.ins


func act_auto() -> Dictionary:
	if not CO.mgr.has("cto"):
		return _toast("warn", "Потрібен директор диспетчерської", "Найміть його у вікні «Персонал»")
	CO.auto = not CO.auto
	return {}


## a loan of a share f of the credit left
func act_loan(f: float) -> Dictionary:
	var lim := co_credit() - loans_left()
	var a := JS.round_js(maxf(0, lim) * f)
	if a < 1000:
		return _toast("warn", "Кредитний ліміт вичерпано")
	var r := co_rate()
	CO.loans.append({"amt": a, "left": a, "rate": r})
	CO.cash += a
	return _toast("good", "Кредит отримано", "%s під %.1f%%" % [usd_s(a), r * 100])


func act_repay() -> void:
	var pay := minf(CO.cash * .8, loans_left())
	if pay < 100:
		return
	CO.cash -= pay
	for l in CO.loans:
		var x := minf(l.left, pay)
		l.left -= x
		pay -= x
	CO.loans = CO.loans.filter(func(l): return l.left > 1)


# ---------- orders and trips ----------
func act_send(id: int) -> Dictionary:
	for k in CO.board:
		if k.id == id:
			var P := co_plan(k)
			if not P.ok:
				return _toast("warn", "Неможливо відправити", P.why)
			k.how = "hand"
			co_dispatch(k, P)
			var A: Dictionary = PL[k.from]
			var B: Dictionary = PL[k.to]
			return _toast("good", "Рейс відправлено", "%s%s: %s → %s" % [D.VT[P.t].n if P.has("t") and D.VT.has(P.t) else "", (" ×%d" % P.n) if P.get("n", 1) > 1 else "", A.name, B.name])
	return {}


func act_decline(id: int) -> void:
	CO.board = CO.board.filter(func(k): return k.id != id)


## the cost of cancelling a trip (coCancelInfo)
func cancel_info(j: Dictionary) -> Dictionary:
	var pl: Variant = j.lp.plan if j.get("lp") else null
	var k0: Dictionary = j.lp.k0 if j.get("lp") else j.k
	var pay: float = k0.pay
	if pl != null and pl.get("cons"):
		pay = 0.0
		for L in pl.legs.slice(j.lp.i):
			for d in L.get("drops", []):
				if not d.get("done"):
					pay += d.pay
	var t00: Variant = pl.get("t00") if pl != null else null
	var held := maxf(0, co_now() - (t00 if t00 != null else j.t0))
	var f := JS.clamp_js(held / maxf(.5, k0.dlDays if k0.dlDays else 1.0), 0, 1)
	return {"pay": pay, "held": held, "fine": JS.round_js(pay * (.1 + .6 * f) + 150 * price_k(me)), "rat": JS.fixed2(.05 + .15 * f)}


## cancel a trip: a fine, a lower rating, the vehicles turn back to the nearest hub (coCancelDo)
func act_cancel(j: Dictionary) -> Dictionary:
	if not CO.jobs.any(func(x): return is_same(x, j)) or j.get("ret"):
		return {}
	var c := cancel_info(j)
	CO.cash -= c.fine
	CO.m.claims += c.fine
	CO.rating = JS.clamp_js(CO.rating - c.rat, 1, 5)
	var st := co_job_state(j, co_now() - j.t0)
	var q := co_pos_at(j, st.s)
	var m: String = j.mode
	var T: Dictionary = D.VT[j.t]
	_drop(CO.jobs, j)
	for v in CO.veh:
		if v.get("resv") and j.get("lp") and v.resv == j.lp.k0.id:
			v.resv = null
	var k0: Dictionary = j.lp.k0 if j.get("lp") else j.k
	co_news("bad", "alert", "%s скасувала рейс %s → %s: штраф %s" % [CO.name, PL[k0.from].name, PL[k0.to].name, usd_s(c.fine)])
	var out := _toast("warn", "Рейс скасовано", "Штраф %s · рейтинг −%.2f" % [usd_s(c.fine), c.rat])
	var vs: Array = CO.veh.filter(func(v): return j.vids.has(v.id))
	if vs.is_empty():
		return out
	# home: the nearest hub that takes this kind of transport, from the exact point where the vehicle is
	var best: Variant = null
	var bd := 1e9
	for h in CO.hubs:
		var p: Dictionary = PL[h.pid]
		if not mode_ok(m, p):
			continue
		var d := JS.hypot(p.x - q[0], p.z - q[1])
		if d < bd:
			bd = d
			best = p
	var path: Variant = null
	if best != null:
		var a := {"x": q[0], "z": q[1]}
		var b := {"x": best.x, "z": best.z}
		if m == "road" or m == "rail":
			a.v = node_at(q[0], q[1])
			a.start = 1
			b.v = best.node
		path = call("sr_seg", m, a, b, false)
	if best == null or path == null or path.size() < 4:
		for v in vs:
			v.st = "idle"
			v.job = null
			v.loc = best.id if best != null else CO.hq
			v.idle0 = null
		return out
	var L := 0.0
	for i in range(2, path.size(), 2):
		L += JS.hypot(path[i] - path[i - 2], path[i + 1] - path[i - 1])
	var len_ := L * CO_DU
	var tm: float = len_ / (T.spd * spd_k())
	var r := {"id": CO.uid, "ret": true, "k": {"id": 0, "from": best.id, "to": best.id, "cg": "parcel", "tons": 0, "pay": 0, "dlDays": 1e3, "mode": m, "risk": 0},
		"mode": m, "t": j.t, "n": vs.size(), "vids": vs.map(func(v): return v.id), "p": PackedFloat32Array(path), "lead": 0.0, "len": len_, "tl": 0.0, "tm": tm,
		"hs": 0.0, "cust": 0.0, "tot": tm, "t0": co_now(), "dl": day + 1e3, "dmg": 0.0, "lost": false, "hold": 0.0, "ev": ["Рейс скасовано: повернення в хаб"]}
	CO.uid += 1
	for v in vs:
		v.st = "trip"
		v.job = r.id
		v.idle0 = null
	CO.jobs.append(r)
	return out


# ---------- moving a vehicle to another hub (08w-move.js) ----------
func mv_from(v: Dictionary) -> int:
	if v.st != "trip":
		return v.loc
	for j in CO.jobs:
		if j.vids.has(v.id):
			return j.k.to
	return v.loc


## the hubs a vehicle can be based at: [{pid, why}] (why: "" when it can)
func mv_targets(v: Dictionary) -> Array:
	var T: Dictionary = D.VT[v.t]
	var from := mv_from(v)
	var out := []
	for h in CO.hubs:
		var p: Dictionary = PL[h.pid]
		var why := ""
		if not mode_ok(T.mode, p):
			why = "Немає залізничної станції" if T.mode == "rail" else "Не підходить для цієї техніки"
		elif h.pid == v.get("home") or (v.get("home") == null and h.pid == v.loc and v.st != "trip"):
			why = "Техніка вже приписана сюди"
		elif h.pid != from and co_route(T.mode, from, h.pid) == null:
			why = "Немає залізничного сполучення" if T.mode == "rail" else "Інший континент — по дорозі не доїхати"
		elif hub_veh_n(h.pid) >= hub_veh_cap(h):
			why = "Хаб заповнений"
		out.append({"pid": h.pid, "why": why})
	return out


func act_move(v: Dictionary, pid: int) -> Dictionary:
	var T: Dictionary = D.VT[v.t]
	v.home = pid
	if v.st == "idle":
		if v.loc == pid:
			return _toast("good", "Приписку змінено", "%s тепер належить хабу %s" % [T.n, PL[pid].name])
		var r: Variant = co_route(T.mode, v.loc, pid)
		if r == null:
			return {}
		var fuel: float = r.len * T.fuel * CO.fuel * fuel_k(T.mode)
		CO.cash -= fuel
		CO.m.fuel += fuel
		var tm: float = r.len / (T.spd * spd_k())
		var from: int = v.loc
		_ret_trip(v, pid, r)
		CO.cash += fuel   # _ret_trip pays the fuel itself
		CO.m.fuel -= fuel
		return _toast("good", "Техніка їде в новий хаб", "%s: %s → %s · %s · пальне %s" % [T.n, PL[from].name, PL[pid].name, "%.1f дн." % tm, usd_s(fuel)])
	return _toast("good", "Приписку змінено", "%s після поточного рейсу поїде в хаб %s" % [T.n, PL[pid].name])


# ---------- test sandbox ----------
## the test switch of the settings: endless money (topped up by the game), the highest grade, licence and
## rating, every permit, upgrade and manager, hubs of the highest level in the headquarters and in the
## nearest port, airport and railway cities, 100 vehicles of every type with their crews
func act_sandbox() -> Dictionary:
	CO.sandbox = true
	CO.cash = 1e12
	CO.xp = maxf(float(CO.get("xp", 0)), float(D.GRADES[D.GRADES.size() - 1].xp))
	CO.tier = D.LIC.size() - 1
	CO.rating = 5.0
	if not CO.has("perm") or not (CO.perm is Dictionary):
		CO.perm = {}
	for p in D.PERM:
		CO.perm[p.id] = {"until": 1e9, "auto": true}
	if not CO.has("upg"):
		CO.upg = {}
	for u in D.UPG:
		if not CO.upg.has(u.id):
			CO.upg[u.id] = {"d": day}
	for id in CO.get("cand", {}).keys().duplicate():
		if not CO.mgr.has(id) and CO.cand[id] is Array and CO.cand[id].size():
			act_hire_mgr(id, 0)
	# hubs: the headquarters and, for each kind of transport, the nearest city that can take it
	var hq: Dictionary = PL[CO.hq]
	for m in ["sea", "air", "rail"]:
		if CO.hubs.any(func(h): return mode_ok(m, PL[h.pid])):
			continue
		var best: Variant = null
		var bd := 1e9
		for p in PL:
			if mode_ok(m, p) and co_scope(p) and hub_at(p.id) == null:
				var d := Vector2(p.x - hq.x, p.z - hq.z).length() + (0.0 if p.cid == me else 3.0)
				if d < bd:
					bd = d
					best = p
		if best != null:
			act_hub(best.id)
	for h in CO.hubs:
		h.lvl = 2 if h.get("rent") else 4
	# 100 of every vehicle, each where its transport can start
	var need := {}
	for t in D.VT:
		var T: Dictionary = D.VT[t]
		var hubs: Array = CO.hubs.filter(func(h): return mode_ok(T.mode, PL[h.pid]))
		if hubs.is_empty():
			continue
		var at: int = CO.hq if hubs.any(func(h): return h.pid == CO.hq) else hubs[0].pid
		for i in 100:
			CO.veh.append({"id": CO.uid, "t": t, "loc": at, "st": "idle", "cond": 100.0, "km": 0.0})
			CO.uid += 1
		need[T.role] = need.get(T.role, 0) + 100 * int(T.get("crew", 1))
	for r in need:
		CO.staff[r] = maxi(int(CO.staff.get(r, 0)), need[r] + 20)
	CO.morale = 90.0
	CO.cash = 1e12
	return _toast("good", "Тестовий режим", "Гроші без ліміту, усе відкрито, по 100 одиниць кожної техніки")
