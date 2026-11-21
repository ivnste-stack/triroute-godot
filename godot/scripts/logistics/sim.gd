class_name Sim
extends SimCore
## Incidents on the road, border trouble, closures, weather, road closures, pirates and bandits:
## a port of legacy/src/08f-incidents.js on top of the core (sim_core.gd). Names follow the original.
##
## The HTML version draws a few things (road closures, the pirate zones) from Math.random; here they come
## from RX, a second RNG seeded from the world seed, so a game is reproducible (the reference run seeds
## Math.random the same way, legacy/tests/simref.js).

const INC_RED := {"acc": 1, "brk": 1, "fuel": 1, "cl": 1, "cxl": 1, "theft": 1, "pir": 1}   # red blinking; the rest is an amber delay
const D8 := [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]

var RX: Mulberry                # Math.random of the HTML version
var blk_v := -1                 # BLK_V: CO.clV the blocks were built for
var jam: Array = []             # JAM: road closures (points on roads)
var jamn := {}                  # JAMN: node → severity of the closures that are on
var inc_f := 0                  # INC_F: frame counter (trips are checked every other frame)
var _maxp := 0.0                # CO_MAXP


func setup(gen_: Object, seed_: int, states_: Array, board_: Dictionary, world: Dictionary = {}) -> void:
	super.setup(gen_, seed_, states_, board_, world)
	RX = Mulberry.new((seed_ ^ 0x51ed) & 0xFFFFFFFF)


# ---------- helpers ----------
func inc_init() -> void:
	for k in ["cls", "wx", "band", "imk", "pir"]:
		if CO.get(k) == null:
			CO[k] = []
	if CO.get("clV") == null:
		CO.clV = 1


func inc_changed() -> void:
	CO.clV = CO.get("clV", 0) + 1


func cnm(id: int) -> String:
	return states[id].name if id >= 0 and id < states.size() else "—"


func brk_k() -> float:
	var k := 1.0
	for u in D.UPG:
		if has_u(u.id) and u.get("brk", 0):
			k *= 1 - u.brk
	return k


func gps_k() -> float:
	var k := 1.0
	for u in D.UPG:
		if has_u(u.id) and u.get("gps", 0):
			k *= 1 - u.gps
	return k


func b_xy(n: int) -> Array:
	return [-board.wx / 2 + (n % board.nx) * board.st, -board.wz / 2 + (n / board.nx) * board.st]


static func pl_len(p: PackedFloat32Array) -> float:
	var L := 0.0
	for i in range(2, p.size(), 2):
		L += JS.hypot(p[i] - p[i - 2], p[i + 1] - p[i - 1])
	return L


func co_rad(p: Dictionary) -> float:
	if not _maxp:
		_maxp = .01
		for q in PL:
			if q.type != "vil":
				_maxp = maxf(_maxp, q.pop)
	if p.type == "vil":
		return .026 + .006 * minf(1, p.pop / .05)
	return .045 + .105 * sqrt(minf(1, p.pop / _maxp))


func _usd(x: float) -> String:
	return "$" + str(int(JS.round_js(x)))


func _days(x: float) -> String:
	return "%.1f дн." % x


# ---------- route blocking: closed borders, closed countries, closed checkpoints, roads shut by weather (incBlk) ----------
func inc_blk() -> void:
	inc_init()
	blk_v = CO.clV
	routes.clear()
	sky = {}
	for c in CO.cls:
		if c.get("conf"):
			sky[c.a] = true
			sky[c.b] = true
	var states_c := PackedInt32Array()
	var pairs := PackedInt32Array()
	var cps := PackedFloat32Array()
	for c in CO.cls:
		if c.kind == "pair":
			pairs.append_array([c.a, c.b])
		elif c.kind == "cty":
			states_c.append(c.a)
		else:
			cps.append_array([c.x, c.z])
	var zones := PackedFloat64Array()
	for w in CO.wx:
		var K: Dictionary = D.WXK[w.k]
		if not K.get("road", 0) and not K.get("rail", 0) or w.t0 > co_now():
			continue
		zones.append_array([w.x, w.z, w.r, (1 if K.get("road", 0) else 0) | (2 if K.get("rail", 0) else 0)])
	blk = not (pairs.is_empty() and states_c.is_empty() and cps.is_empty() and zones.is_empty())
	gen.set_blocks({"closed_states": states_c, "closed_pairs": pairs, "closed_cps": cps, "wx_zones": zones, "sky": PackedInt32Array(sky.keys())})


func inc_cross_cl(a: int, b: int, x: float, z: float) -> Variant:
	for c in CO.cls:
		if c.kind == "cty" and (c.a == a or c.a == b):
			return c
		if c.kind == "pair" and (c.a == a and c.b == b or c.a == b and c.b == a):
			return c
		if c.kind == "cp" and JS.hypot(x - c.x, z - c.z) < board.st * 1.8:
			return c
	return null


## when the closure of a port/airport ends: the latest of the reasons keeping it shut
func inc_port_until(p: Dictionary, mode: String) -> Variant:
	if CO.get("cls") == null:
		return null
	var u: Variant = null
	var adds := []
	if mode == "air" and sky.has(p.cid):
		for c in CO.cls:
			if c.get("conf") and (c.a == p.cid or c.b == p.cid):
				adds.append(["Закрите небо: воєнний стан", c.until])
	for c in CO.cls:
		if c.kind == "cty" and c.a == p.cid:
			adds.append([c.why, c.until])
	for w in CO.get("wx", []):
		var K: Dictionary = D.WXK[w.k]
		if w.t0 > co_now():
			continue
		if (K.get("sea", 0) if mode == "sea" else K.get("air", 0)) and JS.hypot(p.x - w.x, p.z - w.z) < w.r:
			adds.append([w.n, w.until])
	for a in adds:
		if u == null or a[1] > u.until:
			u = {"why": a[0], "until": a[1]}
	return u


# ---------- closed sky: planes fly around countries at war ----------
func co_alt(j: Dictionary, st: Dictionary) -> float:
	if j.mode != "air" or st.seg < 0:
		return 0.0
	var L: float = j.lead if st.seg == 0 else j.len
	var f := JS.clamp_js(st.get("f", 0.0), 0, 1)
	var same: bool = j.get("airS") == st.seg
	var arc := JS.clamp_js((maxf(L, j.get("airH", 0)) if same else L) / CO_DU * .22, .05, .9)
	return sin(PI * (.5 + .5 * f if same else f)) * arc


func inc_air_reroute(j: Dictionary, st: Dictionary) -> bool:
	var T: Dictionary = D.VT[j.t]
	var sp: float = T.spd * spd_k()
	var cur := co_pos_at(j, st.s)
	var A: Dictionary = PL[j.k.from]
	var B: Dictionary = PL[j.k.to]
	var H := co_alt(j, st)
	if st.seg == 0 and not j.get("ret"):
		var a: PackedFloat32Array = gen.air_path(cur[0], cur[1], A.x, A.z)
		var b: PackedFloat32Array = gen.air_path(A.x, A.z, B.x, B.z)
		if a.is_empty() or b.is_empty():
			return false
		var pts := PackedFloat32Array(a)
		pts.append_array(b.slice(2))
		var la := pl_len(a) * CO_DU
		var lb := pl_len(b) * CO_DU
		j.merge({"p": pts, "lead": la, "len": lb, "tl": la / sp, "tm": lb / sp, "t0": co_now(), "pz": [], "airS": 0, "airH": H / .22 * CO_DU}, true)
		j.tot = j.tl + j.hs + j.tm + j.hs + j.get("cust", 0)
	else:
		var b: PackedFloat32Array = gen.air_path(cur[0], cur[1], B.x, B.z)
		if b.is_empty():
			return false
		var lb := pl_len(b) * CO_DU
		j.merge({"p": b, "lead": 0.0, "tl": 0.0, "len": lb, "tm": lb / sp, "t0": co_now(), "pz": [], "cont": true, "airS": 1, "airH": H / .22 * CO_DU}, true)
		j.tot = j.tm + (0.0 if j.get("ret") else j.hs + j.get("cust", 0))
	j.erase("_c")
	j.ev.append("Закрите небо: літак змінив курс в обхід зони бойових дій")
	return true


func inc_sky_check(j: Dictionary, st: Dictionary) -> void:
	if j.get("skyV") == CO.clV:
		return
	if st.seg < 0:
		return
	j.skyV = CO.clV
	if sky.is_empty():
		return
	var s: float = st.s / CO_DU
	var c := co_cum(j)
	var n := c.size()
	var p: PackedFloat32Array = j.p
	var hit := false
	for i in range(1, n):
		if hit:
			break
		if c[i] < s:
			continue
		var a: Array = co_pos_at(j, st.s) if (i == 1 or c[i - 1] < s) else [p[i * 2 - 2], p[i * 2 - 1]]
		hit = gen.sky_hit(a[0], a[1], p[i * 2], p[i * 2 + 1])
	if hit:
		inc_air_reroute(j, st)


# ---------- pauses: the vehicle stops where it is (accident, queue, weather) ----------
func co_pause(j: Dictionary, w: float, ph: String, k: String, extra: Dictionary = {}) -> Dictionary:
	if j.get("pz") == null:
		j.pz = []
	var at: float = co_now() - j.t0
	for p in j.pz:
		if at >= p.e and at < p.e + p.w:
			at = p.e + p.w
	var p := {"e": at, "w": maxf(.01, w), "ph": ph, "k": k}
	p.merge(extra, true)
	j.pz.append(p)
	_stable_sort(j.pz, func(a, b): return a.e - b.e)
	j.tot += p.w
	return p


func co_pause_cut(j: Dictionary, p: Dictionary) -> void:
	var e: float = co_now() - j.t0
	if e >= p.e + p.w:
		return
	var nw := maxf(0, e - p.e)
	var d: float = p.w - nw
	p.w = nw
	j.tot -= d
	for q in j.pz:
		if not is_same(q, p) and q.e > p.e:
			q.e -= d


func pz_len(j: Dictionary) -> float:
	var a := 0.0
	for p in j.get("pz", []):
		a += p.w
	return a


func co_pause_to(j: Dictionary, p: Dictionary, d: float) -> void:
	var e: float = co_now() - j.t0
	var nw := maxf(0, e - p.e) + d
	var dl: float = nw - p.w
	p.w = nw
	j.tot += dl
	for q in j.pz:
		if not is_same(q, p) and q.e > p.e:
			q.e += dl


func inc_mark(j: Dictionary, st: Dictionary, k: String, days: float) -> void:
	var q := co_pos_at(j, st.s)
	CO.imk.append({"x": q[0], "z": q[1], "k": k, "jid": j.id, "until": co_now() + days, "t": Time.get_ticks_msec()})


# ---------- reroute a road/rail trip from where it stands (incDetour) ----------
func inc_detour(j: Dictionary, st: Dictionary, to_pid: int) -> bool:
	if j.mode != "road" and j.mode != "rail":
		return false
	var pos := co_pos_at(j, st.s)
	var lo: int = pos[2]
	var p: PackedFloat32Array = j.p
	var vx: float = p[lo * 2]
	var vz: float = p[lo * 2 + 1]
	var path: PackedFloat32Array = gen.node_path(node_at(vx, vz), PL[to_pid].node, j.mode == "rail")
	if path.is_empty():
		return false
	var pts: Array = [pos[0], pos[1], vx, vz]
	for i in range(2, path.size(), 2):
		pts.append(path[i])
		pts.append(path[i + 1])
	var wl := 0.0
	for i in range(2, pts.size(), 2):
		wl += JS.hypot(pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1])
	var T: Dictionary = D.VT[j.t]
	var len_ := wl * CO_DU
	var tm: float = len_ / (T.spd * spd_k())
	j.merge({"p": PackedFloat32Array(pts), "lead": 0.0, "tl": 0.0, "len": len_, "tm": tm, "cont": true, "pz": [], "t0": co_now(), "cust": 0.0}, true)
	j.erase("_c")
	var stops := []
	for c in gen.crossings(j.p, CO_DU):
		if c.s > .03:
			stops.append({"s": c.s, "a": c.a, "b": c.b, "x": c.x, "z": c.z, "w": cp_wait(c.b, j.mode)})
	j.stops = stops
	var W := 0.0
	for q in stops:
		W += q.w
	j.tot = tm + (0.0 if j.get("ret") else j.hs + W)
	return true


func inc_cross_names(j: Dictionary) -> String:
	var s := {}
	for q in j.get("stops", []):
		s[q.a] = true
		s[q.b] = true
	return ", ".join(s.keys().map(func(id): return cnm(id)))


## cargo goes back to the loading point
func inc_return(j: Dictionary, st: Dictionary, why: String, comp: float = 0) -> bool:
	if not inc_detour(j, st, j.k.from):
		return false
	j.back = true
	j.comp = comp
	if comp:
		CO.cash += comp
		CO.m.contract += comp
	j.ev.append(why)
	return true


# ---------- daily: roll what can go wrong on each trip (coJobsDay) ----------
func _jobs_day() -> void:
	for j in CO.jobs.duplicate():
		if j.get("hold", 0) > 0:
			j.hold -= 1
			j.t0 += 1
			if j.hold == 0 and j.get("seized"):
				j.seized = false
			continue
		var e: float = day - j.t0
		var st := co_job_state(j, e)
		var cg: Dictionary = cargo_i[j.k.cg]
		if not j.get("ret") and not j.get("back") and not j.get("cx0") and not j.get("sch") and st.get("inc") == null:
			var cc: Dictionary = states[PL[j.k.to if st.s > j.lead + j.len / 2 else j.k.from].cid]
			var k: Variant = inc_roll(j, st, cc, cg)
			if k != null:
				j.sch = {"k": k, "at": day + R.next() * .95}
		if e >= j.tot and CO.jobs.any(func(x): return is_same(x, j)):
			co_complete(j)


func inc_band_k(j: Dictionary, st: Dictionary) -> float:
	var q := co_pos_at(j, st.s)
	for z in CO.get("band", []):
		if JS.hypot(q[0] - z.x, q[1] - z.z) < z.r:
			return 5.0
	return .6


func inc_roll(j: Dictionary, st: Dictionary, cc: Dictionary, cg: Dictionary) -> Variant:
	var m: String = j.mode
	var dk := dfk()
	var mt: float = [1.4, 1.0, .65][CO.maint]
	var mor: float = 1.35 - CO.morale / 100
	var dev: float = 1.4 - cc.dev * .6
	var saf := 1 - .45 * msk("coo")
	var frg: float = cg.fr * 4 + .3
	var theft_k: float = cg.get("theft", .6) if cg.get("theft", 0) else .6
	var P := []
	if m == "road":
		P.append_array([["acc", .006 * dk * sqrt(j.n) * saf * mor * dev * mt], ["brk", (.008 * j.n * mt) * brk_k()], ["pdr", .011 * mor * saf],
			["fuel", .004 * dev * CO.fuel], ["dmg", .005 * frg * dev * mt], ["cxl", .0025]])
		if st.seg == 1 and not j.lost:
			P.append(["theft", .0016 * dk * theft_k * (bur(cc.id) / 40) * (1.6 - cc.stability / 100) * (2.5 if in_conf(cc.id) else 1.0) * (1 - .65 * msk("cso")) * inc_band_k(j, st)])
	elif m == "rail":
		P.append_array([["acc", .0015 * dk * saf], ["brk", (.004 * mt) * brk_k()], ["dmg", .003 * frg], ["cxl", .002]])
		if st.seg == 1 and not j.lost:
			P.append(["theft", .0006 * dk * theft_k * (bur(cc.id) / 40) * inc_band_k(j, st)])
	elif m == "sea":
		P.append_array([["brk", (.004 * mt) * brk_k()], ["dmg", .003 * frg], ["cxl", .0015]])
		if st.seg == 1 and not j.lost:
			var q := co_pos_at(j, st.s)
			if CO.pir.any(func(z): return JS.hypot(q[0] - z.x, q[1] - z.z) < z.r):
				P.append(["pir", dfk() * .08 * (1 - .6 * msk("cso"))])
	elif m == "air":
		P.append_array([["brk", (.003 * mt) * brk_k()], ["dmg", .002 * frg], ["cxl", .0015]])
	P.append(["gps", (.002 if m == "air" else .004) * gps_k()])
	for kp in P:
		if chance(kp[1]):
			return kp[0]
	return null


# ---------- one incident (coIncident) ----------
func _pay(c: float, cat: String = "other") -> float:
	c = JS.round_js(c)
	CO.cash -= c
	CO.m[cat] += c
	return c


func co_incident(j: Dictionary, type: String, st: Variant = null) -> void:
	var T: Dictionary = D.VT[j.t]
	var cg: Dictionary = cargo_i[j.k.cg]
	var A: Dictionary = PL[j.k.from]
	var B: Dictionary = PL[j.k.to]
	var vs: Array = CO.veh.filter(func(v): return j.vids.has(v.id))
	if st == null:
		st = co_job_state(j, co_now() - j.t0)
	var here := co_pos_at(j, st.s)
	var cid := maxi(0, gen.state_at(here[0], here[1]))
	var pk := price_k(cid if cid < states.size() else me)
	var where: String = states[cid].name if cid < states.size() else A.name
	var rt := "%s → %s" % [A.name, B.name]
	var val: float = j.k.tons * cg.val
	match type:
		"acc":
			var sev := 2 if chance(.35) else 1
			var fault := chance(JS.clamp_js(.45 + .25 * (1.35 - CO.morale / 100) - .2 * msk("coo"), .15, .85))
			var d: float = (rnd(.15, .5) if sev == 2 else rnd(.03, .15)) * (cg.fr * 6 + .4)
			j.dmg = minf(1, j.dmg + d)
			var v: Variant = _pick_or_null(vs)
			if v != null:
				v.cond = maxf(0, v.cond - (rnd(30, 55) if sev == 2 else rnd(10, 25)))
			var fine := JS.round_js(rnd(200, 900) * pk) if fault else 0.0
			var third := JS.round_js((rnd(12000, 60000) if sev == 2 else rnd(1500, 8000)) * pk * (2.5 if cg.get("dg") else 1.0)) if fault else 0.0
			var dl := rnd(1, 2.5) if sev == 2 else rnd(.3, .8)
			var rh := (.25 if sev == 2 else .08) if fault else .03
			var ph := "ДТП: на місці аварійні служби" if sev == 2 else "ДТП: оформлення з поліцією"
			var apply := func(o: int) -> void:
				var t: float = third * (.3 if CO.ins else 1.0)
				var w := dl
				if o == 1:
					_pay(900 * pk, "claims")
					w *= .6
					t *= .75
				_pay(fine + t, "claims")
				CO.rating = JS.clamp_js(CO.rating - rh, 1, 5)
				co_pause(j, w, ph, "acc")
				j.ev.append("ДТП%s: пошкоджено %d%% вантажу, затримка %s" % [" з вини водія" if fault else "", int(JS.round_js(d * 100)), _days(w)])
			co_news("bad", "alert", "%s за участі техніки %s (%s): %s, маршрут %s" % ["Серйозна ДТП" if sev == 2 else "ДТП", CO.name, where, T.n.to_lower(), rt])
			if sev == 2 and co_modal_ok() and j.mode == "road":
				co_modal({"kind": "acc", "title": "Серйозна аварія з вини вашого водія" if fault else "Серйозна аварія на трасі", "job": j.id,
					"choices": [{"t": "Чекати поліцію", "f": apply.bind(0)}, {"t": "Викликати аварійних комісарів", "f": apply.bind(1)}]})
			else:
				apply.call(0)
		"brk":
			var ev: float = {"road": 300 + T.cost * .004, "rail": 2500 + T.cost * .002, "sea": 15000 + T.cost * .002, "air": 8000 + T.cost * .001}[j.mode] * pk * rep_k()
			var rep: float = T.cost * rnd(.004, .012) * rep_k()
			var dls := {"road": rnd(.3, 1), "rail": rnd(.4, 1.2), "sea": rnd(1, 2.5), "air": rnd(.2, .6)}   # all four are drawn, as in the original
			var dl: float = dls[j.mode]
			var nm: String = {"road": "Поломка в дорозі", "rail": "Несправність локомотива", "sea": "Поломка двигуна судна", "air": "Технічна несправність літака"}[j.mode]
			var sv: String = {"road": "евакуатор", "rail": "резервний тягач", "sea": "буксир", "air": "технічна бригада"}[j.mode]
			for v in vs:
				v.cond = maxf(0, v.cond - rnd(5, 12))
			var apply := func(o: int) -> void:
				var w := dl
				var c := ev + rep
				if o == 1:
					if chance(.55):
						c = rep * .3
						w = dl * .6
					else:
						c = rep * .3 + ev + rep
						w = dl * 1.8
				if o == 2:
					c = rep * 1.6
					w = dl * .5
				_pay(c, "upkeep")
				co_pause(j, w, "%s: %s" % [nm, sv if o == 0 else "ремонт"], "brk")
				j.ev.append("%s: %s, затримка %s" % [nm, _usd(c), _days(w)])
			if j.mode == "road" and co_modal_ok() and chance(.4):
				co_modal({"kind": "brk", "title": "%s зламався на трасі" % T.n, "job": j.id,
					"choices": [{"t": "Викликати евакуатор і сервіс", "f": apply.bind(0)}, {"t": "Ремонт силами водія", "f": apply.bind(1)}, {"t": "Мобільна ремонтна бригада", "f": apply.bind(2)}]})
			else:
				apply.call(0)
		"pdr":
			var V := [["перевищення швидкості", 1, 0], ["перевантаження на вагах", 2.2, .2], ["порушення режиму праці й відпочинку (тахограф)", 1.6, .25],
				["неправильна стоянка", .6, 0], ["рух смугою громадського транспорту", .8, 0], ["несправні фари", .5, .05]]
			var v: Array = pick(V)
			var f := _pay(rnd(60, 450) * v[1] * pk, "claims")
			if v[2]:
				co_pause(j, v[2] * rnd(.5, 1.2), "Поліція: " + v[0], "pdr")
			else:
				co_pause(j, rnd(.03, .08), "Зупинка поліцією", "pdr")
			j.ev.append("Штраф ПДР: %s, %s" % [v[0], _usd(f)])
			co_news("warn", "gavel", "Водія %s оштрафовано (%s): %s, %s" % [CO.name, where, v[0], _usd(f)])
		"fuel":
			var c := _pay((150 + j.k.tons * .4) * CO.fuel * pk * rnd(1.2, 2.2), "fuel")
			var w := rnd(.2, .6)
			var why: String = pick(["на найближчих АЗС немає пального", "водій не розрахував запас пального", "паливна картка заблокована"])
			co_pause(j, w, "Нестача пального: чекає на паливозаправник", "fuel")
			j.ev.append("Нестача пального: %s, дозаправка %s" % [why, _usd(c)])
		"dmg":
			var d: float = rnd(.05, .25) * (cg.fr * 3 + .3) * 2
			var L: Array = (["вантаж зсунувся під час різкого гальмування", "розбита дорога", "протікає тент", "порушено температурний режим"] if j.mode == "road"
				else (["жорстке зчеплення вагонів", "порушено температурний режим"] if j.mode == "rail"
				else (["хитавиця: контейнери зсунулися", "волога в трюмі"] if j.mode == "sea" else ["груба обробка в аеропорту"])))
			var why: String = pick(L)
			j.dmg = minf(1, j.dmg + d)
			co_pause(j, rnd(.08, .25), "Пошкодження вантажу: перекладання", "dmg")
			j.ev.append("Пошкоджено %d%% вантажу: %s" % [int(JS.round_js(d * 100)), why])
		"cxl":
			inc_cancel(j, st)
		"theft":
			var big := val > 150000 and co_modal_ok()
			j.lost = true
			CO.rating = JS.clamp_js(CO.rating - .12, 1, 5)
			j.ev.append("Бандити пограбували потяг" if j.mode == "rail" else "Напад бандитів: вантаж викрадено")
			co_pause(j, rnd(.3, .8), "Напад бандитів: поліція на місці", "theft")
			inc_mark(j, st, "theft", 3)
			co_news("bad", "skull", "Викрадено вантаж %s: «%s» на %s (%s)" % [CO.name, cg.n, _usd(val), where])
			if big:
				var stab: float = states[cid].stability if cid < states.size() else 50.0
				var detect := func() -> void:
					_pay(val * .05 + 8000)
					if chance(.3 + msk("cso") * .4):
						j.lost = false
						j.ev.append("Вантаж повернули детективи")
				var police := func() -> void:
					if chance(stab / 400):
						j.lost = false
						j.ev.append("Поліція повернула вантаж")
				co_modal({"kind": "theft", "title": "Вантаж захопили на трасі", "job": j.id,
					"choices": [{"t": "Найняти приватних детективів", "f": detect}, {"t": "Заява в поліцію", "f": police}, {"t": "Списати", "f": func() -> void: pass}]})
		"pir":
			j.seized = true
			var p := co_pause(j, rint(6, 12), "Захоплено піратами: переговори про викуп", "pir", {"end": "free"})
			inc_mark(j, st, "pir", 0)
			var ransom := JS.round_js(val * .08 + T.cost * .03)
			co_news("bad", "skull", "Пірати захопили судно %s з вантажем «%s»" % [CO.name, cg.n])
			var pay_r := func() -> void:
				_pay(ransom)
				co_pause_to(j, p, 7)
				p.ph = "Захоплено піратами: викуп сплачено, чекаємо звільнення"
				j.ev.append("Сплачено викуп")
			var navy := func() -> void:
				if chance(.35 + msk("cso") * .3):
					co_pause_to(j, p, 4)
					p.ph = "Військовий флот звільняє судно"
				else:
					j.lost = true
					co_pause_to(j, p, 18)
					for v in vs:
						v.cond = maxf(0, v.cond - 40)
					CO.rating = JS.clamp_js(CO.rating - .15, 1, 5)
					j.ev.append("Штурм провалився: вантаж втрачено")
			var give := func() -> void:
				j.lost = true
				co_pause_to(j, p, 20)
				CO.rating = JS.clamp_js(CO.rating - .12, 1, 5)
			co_modal({"kind": "pir", "title": "Пірати захопили ваше судно", "job": j.id,
				"choices": [{"t": "Заплатити викуп " + _usd(ransom), "f": pay_r}, {"t": "Чекати на військовий флот", "f": navy}, {"t": "Відмовитися від вантажу", "f": give}]})
		"gps":
			j.gps = {"until": co_now() + rnd(.6, 2)}
			var nm := "AIS-транспондера" if j.mode == "sea" else "GPS-навігації"
			j.ev.append("Збій %s: техніка зникла з карти" % nm)
			if j.mode == "road" and chance(.45):
				co_pause(j, rnd(.08, .25), "Збій GPS: водій заблукав і повертається на маршрут", "gps")
				j.ev.append("Водій заблукав без навігації")
			co_news("warn", "target", "Збій %s: %s %s зникає з радарів (%s)" % [nm, T.n.to_lower(), CO.name, where])


## the customer cancels: before loading the truck just stops at the loading point; after loading — a long
## wait, then maybe back to the sender
func inc_cancel(j: Dictionary, st: Dictionary) -> void:
	if st.seg == 0 and not j.get("cont"):
		var fee := JS.round_js(j.k.pay * rnd(.1, .2))
		CO.cash += fee
		CO.m.contract += fee
		j.cx0 = true
		j.tot = j.tl + seg_w(j, 0, j.lead) + pz_len(j)
		j.ev.append("Замовник скасував рейс до завантаження: компенсація " + _usd(fee))
		co_news("warn", "doc", "Замовник скасував рейс %s %s → %s" % [CO.name, PL[j.k.from].name, PL[j.k.to].name])
		return
	co_pause(j, rnd(1, 2.5), "Замовник призупинив рейс: чекаємо рішення", "cxw", {"end": "cxl"})
	j.ev.append("Замовник призупинив рейс")


func inc_cancel_end(j: Dictionary) -> void:
	var A: Dictionary = PL[j.k.from]
	var st := co_job_state(j, co_now() - j.t0)
	if chance(.5):
		j.ev.append("Замовник підтвердив рейс")
		return
	var comp := JS.round_js(j.k.pay * .35)
	var road: bool = j.mode == "road" or j.mode == "rail"
	var do_back := func() -> void:
		if road and inc_return(j, st, "Замовник скасував рейс: вантаж повертається в %s, компенсація %s" % [A.name, _usd(comp)], comp):
			co_news("warn", "doc", "Замовник скасував рейс %s: «%s» повертається в %s" % [CO.name, cargo_i[j.k.cg].n, A.name])
		else:
			j.payK = .4
			j.ev.append("Замовник скасував рейс: вантаж залишать на складі в пункті призначення, оплата 40%")
	if co_modal_ok() and j.k.pay > 3000:
		var ch: Array = [{"t": "Повернути вантаж відправнику" if road else "Здати вантаж на склад", "f": do_back}]
		if CO.mgr.has("clo"):
			var lawyer := func() -> void:
				var fee := JS.round_js(j.k.pay * .08 + 500)
				CO.cash -= fee
				CO.m.other += fee
				if chance(.45 + msk("clo") * .4):
					var x := JS.round_js(j.k.pay * .8)
					CO.cash += x
					CO.m.contract += x
					j.payK = 0
					j.ev.append("Суд: замовник сплатив " + _usd(x))
					if road:
						inc_return(j, st, "Вантаж повертається відправнику", 0)
				else:
					do_back.call()
			ch.append({"t": "Подати претензію через юриста", "f": lawyer})
		co_modal({"kind": "cxl", "title": "Замовник відмовився від вантажу", "job": j.id, "choices": ch})
	else:
		do_back.call()


# ---------- border checkpoint: queue, papers, inspection; a closed border → detour or back ----------
func cp_arrive(j: Dictionary, q: Dictionary, st: Dictionary) -> void:
	var a: int = q.a
	var b: int = q.b
	var x: float = q.x if q.get("x") != null else co_pos_at(j, st.s)[0]
	var z: float = q.z if q.get("z") != null else co_pos_at(j, st.s)[1]
	var cl: Variant = inc_cross_cl(a, b, x, z)
	if cl != null:
		inc_border_hit(j, q, st, cl)
		return
	if j.get("ret"):
		return
	var C: Dictionary = states[b]
	if not chance(.24 * (.5 + bur(b) / 60) * (1 - .5 * msk("clo"))):
		return
	var K: String = pick(["queue", "queue", "docs", "insp"])
	var w0s := {"queue": rnd(.3, 1.2), "docs": rnd(.5, 1.8), "insp": rnd(.3, 1.2)}   # all three are drawn
	var w0: float = w0s[K] * (1 + bur(b) / 100)
	var ph: String = {"queue": "Черга на кордоні", "docs": "Виправлення документів", "insp": "Митний огляд"}[K] + " · " + C.name
	if CO.mgr.has("clo"):
		var f := JS.clamp_js(.55 - .35 * msk("clo"), .15, .55)
		co_pause(j, w0 * f, ph, "cus")
		j.ev.append("%s: юрист і митний брокер — оформлення пришвидшено, затримка %s" % [ph, _days(w0 * f)])
		return
	co_pause(j, w0, ph, "cus")
	j.ev.append("%s: затримка %s" % [ph, _days(w0)])
	if K == "insp" and chance(.25):
		j.dmg = minf(1, j.dmg + rnd(.02, .06))
		j.ev.append("Під час огляду пошкоджено упаковку")


func inc_border_hit(j: Dictionary, q: Dictionary, _st: Dictionary, cl: Dictionary) -> void:
	var to: int = j.k.from if j.get("back") else j.k.to
	var left: float = cl.until - co_now()
	var why: String = cl.why
	var nm: String
	if cl.kind == "cty":
		nm = "%s закрила кордони" % cnm(cl.a)
	elif cl.kind == "pair":
		nm = "Кордон %s — %s закрито" % [cnm(cl.a), cnm(cl.b)]
	else:
		nm = "Пункт пропуску %s → %s закрито" % [cnm(q.a), cnm(q.b)]
	if inc_detour(j, co_job_state(j, co_now() - j.t0), to):
		var via := inc_cross_names(j)
		j.ev.append("%s: об'їзд%s" % [nm, " через " + via if via else ""])
		return
	if left < 4:
		co_pause(j, left + .02, nm + ": чекає відкриття", "cl")
		q.h = 0
		j.ev.append("%s (%s): чекаємо відкриття" % [nm, why.to_lower()])
		return
	if not j.get("ret") and not j.get("back") and inc_return(j, co_job_state(j, co_now() - j.t0), "%s (%s): вантаж повертається відправнику" % [nm, why.to_lower()], JS.round_js(j.k.pay * .25)):
		return
	co_pause(j, 1, nm + ": чекає відкриття", "cl")
	q.h = 0


# ---------- per frame: fire scheduled incidents, checkpoints, weather and traffic (incFrame) ----------
func _inc_frame(T: float) -> void:
	inc_init()
	if blk_v != CO.clV:
		inc_blk()
	var dt := JS.clamp_js(T - (CO.incT if CO.get("incT") != null else T), 0, 1)
	CO.incT = T
	if dt > 0:
		inc_world(T, dt)
		inc_jams(T, dt)
	elif jam.is_empty():
		inc_jams(T, 0)
	inc_f += 1
	if (inc_f - 1) % 2:
		return
	for j in CO.jobs.duplicate():
		if j.get("hold", 0) > 0:
			continue
		var e: float = T - j.t0
		var st := co_job_state(j, e)
		# a pause that waits for a decision
		if j.get("pz"):
			for p in j.pz:
				if p.get("end") and not p.get("done") and e >= p.e + p.w:
					p.done = 1
					if p.end == "cxl":
						inc_cancel_end(j)
					if p.end == "free":
						j.seized = false
		if j.get("gps") and T >= j.gps.until:
			j.erase("gps")
			j.ev.append("Сигнал GPS відновлено")
		if not CO.jobs.any(func(x): return is_same(x, j)):
			continue
		if j.get("sch") and T >= j.sch.at:
			var k: String = j.sch.k
			j.sch = null
			if st.get("inc") == null and (st.seg >= 0 or k == "cxl"):
				co_incident(j, k, st)
			continue
		if st.get("inc") != null:
			continue
		var wq: Variant = st.get("w")
		if wq != null and not wq.get("h"):
			wq.h = 1
			cp_arrive(j, wq, st)
			continue
		if j.mode == "air":
			inc_sky_check(j, st)
		var pos := co_pos_at(j, st.s)
		# weather: vehicles inside a storm stop; planes only on the ground; ships wait at anchor near a closed port
		var stopped := false
		if not (T < j.get("wxCool", 0)):
			for w in CO.wx:
				var K: Dictionary = D.WXK[w.k]
				if not K.get(j.mode, 0) or j.get("wxd") == w.id or w.t0 > T:
					continue
				if j.mode == "air" and st.seg >= 0:
					continue
				if JS.hypot(pos[0] - w.x, pos[1] - w.z) < w.r:
					j.wxd = w.id
					var d := maxf(.05, w.until - T)
					j.wxCool = w.until + .5
					co_pause(j, d, "%s: %s" % [w.n, {"road": "дорогу перекрито", "rail": "рух поїздів зупинено", "sea": "судно перечікує в укритті", "air": "вильоти скасовано"}[j.mode]], "wx")
					stopped = true
					break
		if stopped:
			continue
		if st.seg >= 0:
			for w in CO.wx:
				var K: Dictionary = D.WXK[w.k]
				if not K.has("slow") or not K.slow.get(j.mode, 0) or w.t0 > T or j.get("drag", []).any(func(dd): return dd.w == w.id):
					continue
				if JS.hypot(pos[0] - w.x, pos[1] - w.z) < w.r:
					var f: float = K.slow[j.mode]
					var Lc: float = w.r * 1.6 * ((j.lead + j.len) / maxf(1e-6, pl_len(j.p)) if j.p.size() > 4 else CO_DU)
					var sp: float = D.VT[j.t].spd * spd_k()
					var e0: float = T - j.t0
					var d := Lc / (sp * f)
					if j.get("drag") == null:
						j.drag = []
					j.drag.append({"w": w.id, "e0": e0, "e1": e0 + d, "f": f, "ph": w.n + ": рух сповільнено"})
					j.tot += d * (1 - f)
					j.ev.append(w.n + ": рух сповільнено")   # slowed, not stopped
		if (j.mode == "sea" or j.mode == "air") and st.seg == 1 and st.f > .88 and not (T < j.get("wxCool", 0)):
			var u: Variant = inc_port_until(PL[j.k.to], j.mode)
			if u != null:
				var d := JS.clamp_js(u.until - T, .05, 3)
				j.wxCool = T + d + .5
				co_pause(j, d, "%s закрито (%s): %s" % ["Порт" if j.mode == "sea" else "Аеропорт", u.why.to_lower(), "очікування на рейді" if j.mode == "sea" else "зона очікування"], "wx")
				continue
		# road closure: the vehicle stops before it
		if j.mode == "road" and st.seg >= 0:
			var lp: Array = j.jp if j.get("jp") != null else pos
			var eN: float = T - j.t0
			var eP: float = j.je if j.get("je") != null else eN
			j.jp = [pos[0], pos[1]]
			j.je = eN
			if jam.size():
				var J: Variant = jam_on(lp[0], lp[1], pos[0], pos[1])
				if J != null and j.get("jn") != J.id:
					j.jn = J.id
					var dx: float = pos[0] - lp[0]
					var dz: float = pos[1] - lp[1]
					var L2 := dx * dx + dz * dz
					var t := JS.clamp_js(((J.x - lp[0]) * dx + (J.z - lp[1]) * dz) / L2, 0, 1) if L2 > 0 else 1.0   # back to the closure point itself
					var K: Dictionary = _rck(J.kind)
					var pz := co_pause(j, maxf(.05, J.until - T), K.n + ": дорогу перекрито, чекає відкриття", "jam")
					pz.e = maxf(0, pz.e - (1 - t) * maxf(0, eN - eP))
		else:
			j.jp = null
			j.je = null


# ---------- the world: closures and weather appear and fade (incWorld) ----------
func wx_season() -> Array:
	var m: int = date.m
	if m == 11 or m <= 1:
		return ["snow", "snow", "hsnow", "hsnow", "ice", "ice", "fog", "storm"]
	if m <= 4:
		return ["rain", "rain", "tstorm", "flood", "flood", "fog", "storm", "storm"]
	if m <= 7:
		return ["rain", "tstorm", "tstorm", "hur", "fog", "storm", "storm", "flood"]
	if m <= 9:
		return ["rain", "rain", "tstorm", "hur", "fog", "fog", "storm", "flood"]
	return ["rain", "hsnow", "ice", "fog", "fog", "storm", "storm", "tstorm"]


func _near_hub(p: Variant, r: float) -> bool:
	for h in CO.hubs:
		if JS.hypot(PL[h.pid].x - p.x, PL[h.pid].z - p.z) < r:
			return true
	return false


func _scoped_states() -> Array:
	var hc: int = hq_p().cid
	var have := {}
	for p in PL:
		if co_scope(p):
			have[p.cid] = true
	return states.filter(func(c): return c.id != hc and have.has(c.id))


func _n_cls(k: String) -> int:
	var n := 0
	for c in CO.cls:
		if c.kind == k and not c.get("conf"):
			n += 1
	return n


func inc_world(T: float, dt: float) -> void:
	var ch := false
	inc_zones(T, dt)
	CO.imk = CO.imk.filter(func(m): return CO.jobs.any(func(j): return j.id == m.jid and j.get("seized")) if m.k == "pir" else m.until > T)
	# expire
	for c in CO.cls.duplicate():
		if c.until <= T:
			_drop(CO.cls, c)
			ch = true
			co_news("good", "handshake", "%s знову відкрила кордони" % cnm(c.a) if c.kind == "cty" else ("Кордон %s — %s знову відкрито" % [cnm(c.a), cnm(c.b)] if c.kind == "pair" else "Пункт пропуску %s → %s знову працює" % [cnm(c.a), cnm(c.b)]))
	for w in CO.wx.duplicate():
		if w.until <= T:
			_drop(CO.wx, w)
			ch = true
	# war conflicts close the border between the two states
	for f in CO.get("conf", []):
		if f.until > T and not CO.cls.any(func(c): return c.get("conf") and c.a == f.a and c.b == f.b):
			CO.cls.append({"id": CO.uid, "kind": "pair", "a": f.a, "b": f.b, "why": "Воєнний конфлікт", "until": f.until, "conf": 1})
			CO.uid += 1
			ch = true
	var cps: Array = board.checkpoints.filter(func(c): return not c.rail)
	var hc: int = hq_p().cid
	if CO.tier >= 1 and _n_cls("cp") < 4 and cps.size() and chance(.05 * dt):
		var L: Array = cps.filter(func(c): return _near_hub(c, 4))
		L.append_array(cps.slice(0, 3))
		var c: Variant = _pick_or_null(L)
		if c != null and not CO.cls.any(func(x): return x.kind == "cp" and JS.hypot(x.x - c.x, x.z - c.z) < .3):
			var cl := {"id": CO.uid, "kind": "cp", "a": c.a, "b": c.b, "x": c.x, "z": c.z}
			CO.uid += 1
			cl.why = pick(D.CL_WHY.cp)
			cl.until = T + rnd(2, 9)
			CO.cls.append(cl)
			ch = true
			inc_tell(cl)
	if CO.tier >= 2 and _n_cls("pair") < 2 and chance(.006 * dt):
		var scoped := _scoped_states()
		var a: Dictionary = pick(scoped if scoped.size() else states)
		var nb: Array = Array(neighbors[a.id]).filter(func(i): return i >= 0 and i < states.size() and i != hc) if a.id < neighbors.size() else []
		if nb.size():
			var b: int = pick(nb)
			if not CO.cls.any(func(c): return c.kind == "pair" and (c.a == a.id and c.b == b or c.a == b and c.b == a.id)):
				var cl := {"id": CO.uid, "kind": "pair", "a": a.id, "b": b}
				CO.uid += 1
				cl.why = pick(D.CL_WHY.pair)
				cl.until = T + rnd(12, 45)
				CO.cls.append(cl)
				ch = true
				inc_tell(cl)
	if CO.tier >= 2 and _n_cls("cty") < 1 and chance(.004 * dt):
		var scoped := _scoped_states()
		if scoped.size():
			var a: Dictionary = pick(scoped)
			var cl := {"id": CO.uid, "kind": "cty", "a": a.id}
			CO.uid += 1
			cl.why = pick(D.CL_WHY.cty)
			cl.until = T + rnd(8, 35)
			CO.cls.append(cl)
			ch = true
			inc_tell(cl)
	# weather
	if CO.wx.size() < 3 and chance(.4 * dt):
		var k: String = pick(wx_season())
		var K: Dictionary = D.WXK[k]
		var base: Variant = null
		var ports: Array = PL.filter(func(p): return p.port != null)
		if k == "storm" and ports.size():
			if chance(.6):
				var L: Array = ports.filter(func(p): return _near_hub(p, 4))
				L.append_array(ports.slice(0, 2))
				base = _pick_or_null(L)
			else:
				base = _pick_or_null(ports)
		if base == null:
			if chance(.6) and CO.hubs.size():
				base = _pick_or_null(PL.filter(func(p): return _near_hub(p, 3)))
			else:
				base = pick(PL)
		if base != null:
			var rs := {"snow": rnd(.35, .8), "storm": rnd(.5, 1), "hur": rnd(.6, 1.1), "fog": rnd(.25, .55), "flood": rnd(.22, .45), "hsnow": rnd(.4, .8),
				"ice": rnd(.35, .7), "rain": rnd(.3, .65), "tstorm": rnd(.35, .7)}   # all nine are drawn, as in the original
			var r: float = rs[k]
			var x: float = base.x + rnd(-.4, .4)
			var z: float = base.z + rnd(-.4, .4)
			var mine := _near_hub({"x": x, "z": z}, r + .6)
			if not mine:
				for j in CO.jobs:
					var q := co_pos_at(j, co_job_state(j, T - j.t0).s)
					if JS.hypot(q[0] - x, q[1] - z) < r + .3:
						mine = true
						break
			var t0 := T + rnd(.8, 2.5)
			var w := {"id": CO.uid, "k": k, "n": K.n, "x": x, "z": z, "r": r, "t0": t0}
			CO.uid += 1
			w.until = t0 + (rnd(1.5, 3.5) if k == "hur" else rnd(.4, 2.5))
			w.near = base.name
			w.mine = mine
			CO.wx.append(w)
			ch = true
			if mine:
				co_news("warn", K.ic, "Прогноз: %s в районі %s" % [K.n.to_lower(), base.name])
	for w in CO.wx:
		if not w.get("on") and not (w.t0 > T):
			w.on = 1
			ch = true
	if ch:
		inc_changed()
		inc_blk()


func inc_zones(T: float, dt: float) -> void:
	var shaky := func() -> Array:
		var have := {}
		for p in PL:
			have[p.cid] = true
		var L: Array = states.filter(func(c): return have.has(c.id))
		_stable_sort(L, func(a, b): return (a.stability - bur(a.id)) - (b.stability - bur(b.id)))
		return L
	# pirates: water near ports of the shakiest coastal states
	if not CO.get("pirB"):
		CO.pirB = 1
		if CO.pir.is_empty():
			var S: Array = shaky.call().filter(func(c): return PL.any(func(p): return p.cid == c.id and p.port != null)).slice(0, 6)
			var i := 0
			while i < 3 and S.size():
				i += 1
				var c: Dictionary = S.pop_at(int(floor(RX.next() * S.size())))
				var pts: Array = PL.filter(func(p): return p.cid == c.id and p.port != null)
				var t: Variant = board.towns[pick(pts).id] if board.has("towns") else null
				if t == null or t.wc_i < 0:
					continue
				var zone := {"id": CO.uid}
				CO.uid += 1
				zone.x = -board.wx / 2 + (t.wc_i + .5) * board.st + rnd(-.25, .25)
				zone.z = -board.wz / 2 + (t.wc_j + .5) * board.st + rnd(-.25, .25)
				zone.r = rnd(.5, .85)
				zone.cid = c.id
				zone.name = "води біля " + c.name
				CO.pir.append(zone)
	# bandits: stretches of road in unstable states, they move around every few weeks
	var bef: int = CO.band.size()
	CO.band = CO.band.filter(func(z): return z.until > T)
	if CO.band.size() < 3 and (CO.band.size() < bef or (not bef and not CO.get("bandI")) or chance(.05 * dt)):
		CO.bandI = 1
		var S: Array = shaky.call().slice(0, 8)
		var c: Variant = _pick_or_null(S)
		if c != null:
			var ps: Array = PL.filter(func(p): return p.cid == c.id and p.type != "cap")
			if ps.size():
				var p: Dictionary = pick(ps)
				var zone := {"id": CO.uid}
				CO.uid += 1
				zone.x = p.x + rnd(-.3, .3)
				zone.z = p.z + rnd(-.3, .3)
				zone.r = rnd(.35, .7)
				zone.cid = c.id
				zone.until = T + rnd(30, 90)
				zone.name = c.name
				CO.band.append(zone)
				if _near_hub(p, 4):
					co_news("warn", "skull", "Поліція %s попереджає: на дорогах біля %s діє банда" % [c.name, p.name])


func inc_tell(cl: Dictionary) -> void:
	var t: String
	if cl.kind == "cty":
		t = "%s закрила кордони" % cnm(cl.a)
	elif cl.kind == "pair":
		t = "Кордон %s — %s закрито" % [cnm(cl.a), cnm(cl.b)]
	else:
		t = "Пункт пропуску %s → %s закрито" % [cnm(cl.a), cnm(cl.b)]
	co_news("bad", "lock" if cl.kind == "cp" else "swords", "%s: %s" % [t, cl.why.to_lower()])


# ---------- road closures: a point on a road shut for 2–3 days; a vehicle reaching it waits (incJams) ----------
func _rck(k: String) -> Dictionary:
	for r in D.RCK:
		if r.k == k:
			return r
	return D.RCK[0]


func jam_r() -> float:
	return board.st * .55


func rc_target() -> int:
	var n := 0
	for p in PL:
		if p.type == "cap" or p.type == "big" or p.type == "city":
			n += 1
	return int(JS.clamp_js(JS.round_js(n * .9), 10, 80))


func _jam_put(T: float, n0: int, steps_f: float) -> bool:
	var bits: PackedByteArray = board.bits
	var nx: int = board.nx
	var n := n0
	var steps := int(JS.round_js(steps_f))   # steps * CST / BL.st
	for s in steps:
		var o := []
		for d in 8:
			if bits[n] & (1 << d):
				o.append((n / nx + D8[d][1]) * nx + n % nx + D8[d][0])
		if o.is_empty():
			break
		n = o[int(floor(RX.next() * o.size()))]
	if not bits[n] or jamn.has(n):
		return false
	var xy := b_xy(n)
	for J in jam:
		if JS.hypot(J.x - xy[0], J.z - xy[1]) < board.st * .6:
			return false
	var tw := 0.0
	for r in D.RCK:
		tw += r.w
	var r_ := RX.next() * tw
	var K: Dictionary = D.RCK[0]
	for r in D.RCK:
		r_ -= r.w
		if r_ <= 0:
			K = r
			break
	for p in PL:   # never inside a city: it always has other ways in
		if JS.hypot(p.x - xy[0], p.z - xy[1]) < jam_r() * 1.6 + co_rad(p):
			return false
	var t0 := T + rnd(2, 5) if K.k == "repair" else T
	var J := {"id": CO.uid, "n": n, "x": xy[0], "z": xy[1], "sev": K.sev, "kind": K.k, "t0": t0}
	CO.uid += 1
	J.until = t0 + rnd(2, 3)
	J.on = 1 if t0 <= T else 0
	jam.append(J)
	if t0 <= T:
		jamn[n] = K.sev
	return true


func inc_jams(T: float, dt: float) -> void:
	if not board.has("bits"):
		return
	var ch := false
	var before := jam.size()
	jam = jam.filter(func(J): return J.until > T)
	if jam.size() != before:
		ch = true
	var src: Array = PL.filter(func(p): return p.node != null and p.type != "vil")
	var tgt := rc_target()
	# (a lambda cannot set the outer `ch`: GDScript captures locals by value, so spawn returns it)
	var spawn := func() -> bool:
		var p: Variant = _pick_or_null(src)
		return p != null and _jam_put(T, p.node, rnd(.6, 3.5))
	if jam.is_empty():
		var i := 0
		while i < tgt * 3 and jam.size() < tgt:   # the world starts with closures already in place, at different stages
			i += 1
			if spawn.call():
				ch = true
			var J: Variant = jam.back() if jam.size() else null
			if J != null and J.t0 == T:
				J.until = T + rnd(.4, 3)
			elif J != null and chance(.5):
				J.t0 = T - rnd(0, 1.5)
				J.until = T + rnd(.4, 3)
				J.on = 1
	elif jam.size() < tgt and RX.next() < dt * tgt / 2.5:
		if spawn.call():
			ch = true
	for J in jam:
		if not J.on and J.t0 <= T:
			J.on = 1
			ch = true
	if ch:
		jamn = {}
		for J in jam:
			if J.on:
				jamn[J.n] = maxi(jamn.get(J.n, 0), J.sev)


## the closure a vehicle drove into between two positions (a segment test: fast vehicles do not skip it)
func jam_on(x0: float, z0: float, x1: float, z1: float) -> Variant:
	if jam.is_empty():
		return null
	var Rr := jam_r()
	var dx := x1 - x0
	var dz := z1 - z0
	var L2 := dx * dx + dz * dz
	var now := co_now()
	for J in jam:
		if J.t0 > now:
			continue
		var t := JS.clamp_js(((J.x - x0) * dx + (J.z - z0) * dz) / L2, 0, 1) if L2 > 0 else 0.0
		if JS.hypot(x0 + dx * t - J.x, z0 + dz * t - J.z) < Rr:
			return J
	return null
