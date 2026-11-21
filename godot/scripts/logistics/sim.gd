class_name Sim
extends SimIncidents
## The route planner's calculations (legacy/src/08q-planner.js without its panel and map drawing): the player
## puts points on the map (cities, or road/rail nodes to steer through) and a mode for every step; this works
## out the legs, who carries each (own vehicles or a partner carrier), the time, the cost, the risks and
## whether the plan may be sent. The interface (stage 6) keeps the points and shows the result.
##
## A plan point is a place id (int) or a road/rail node {v, x, z, cp?, cn?} (lpPickW).
## lp_calc(k, pts, modes, veh0) ↔ lpCalc() with LP = {k, pts, modes, veh0}.

var _lp_rc := {}                # LP_RC: ordinary routes, valid while the blocks stay the same
var _lp_rc_v := -2


static func lp_is_w(q: Variant) -> bool:
	return q is Dictionary


func lp_node(q: Variant) -> int:
	return q.v if lp_is_w(q) else PL[q].node


func lp_name(q: Variant) -> String:
	if not lp_is_w(q):
		return PL[q].name
	var c: int = gen.state_at(q.x, q.z)
	if q.get("cp"):
		return "КПП" + (" " + q.cn if q.get("cn") else "")
	return "дорога" + (" (" + states[c].name + ")" if c >= 0 else "")


func lp_mode_ok(m: String, p: Dictionary) -> bool:
	match m:
		"road": return true
		"rail": return p.rail
		"sea": return p.port != null
		"air": return p.air == true
	return false


func _path_len(p: PackedFloat32Array) -> float:
	var L := 0.0
	for i in range(2, p.size(), 2):
		L += JS.hypot(p[i] - p[i - 2], p[i + 1] - p[i - 1])
	return L


## the ordinary route between two places: the planner does not steer around the weather — that is the
## dispatcher's job (lpPlain)
func lp_plain(m: String, a: int, b: int) -> Variant:
	if (m != "road" and m != "rail") or a == b:
		return co_route(m, a, b)
	if m == "rail" and not (PL[a].rail and PL[b].rail):
		return null
	if _lp_rc_v != blk_v:
		_lp_rc_v = blk_v
		_lp_rc.clear()
	var key := m + str(a) + ":" + str(b)
	if _lp_rc.has(key):
		return _lp_rc[key]
	var p: PackedFloat32Array = gen.node_path(PL[a].node, PL[b].node, m == "rail", true)
	var res: Variant = null
	if p.size() >= 4:
		res = {"p": p, "len": _path_len(p) * CO_DU}
	_lp_rc[key] = res
	return res


## a path between two plan points of one mode (lpSeg)
func lp_seg(m: String, a: Variant, b: Variant) -> Variant:
	if not lp_is_w(a) and not lp_is_w(b):
		return lp_plain(m, a, b)
	if m != "road" and m != "rail":
		return null
	var p: PackedFloat32Array = gen.node_path(lp_node(a), lp_node(b), m == "rail", true)
	if p.is_empty():
		return null
	return {"p": p, "len": _path_len(p) * CO_DU}


static func lp_join(rs: Array) -> Dictionary:
	var f := PackedFloat32Array()
	var len_ := 0.0
	for i in rs.size():
		var r: Dictionary = rs[i]
		f.append_array(r.p.slice(0 if i == 0 else 2))
		len_ += r.len
	return {"p": f, "len": len_}


# ---------- what can go wrong along a path (lpRisk) ----------
func lp_risk(r: Dictionary, m: String) -> Dictionary:
	var p: PackedFloat32Array = r.p
	var o := {"jam": 0, "wx": 0, "band": 0, "pir": 0, "border": 0, "cl": 0}
	var seen := {}
	for i in range(2, p.size(), 2):
		var L := JS.hypot(p[i] - p[i - 2], p[i + 1] - p[i - 1])
		var n := maxi(1, int(ceil(L / (board.st * .5))))
		for s in n + 1:
			var x: float = p[i - 2] + (p[i] - p[i - 2]) * s / n
			var z: float = p[i - 1] + (p[i + 1] - p[i - 1]) * s / n
			for w in CO.get("wx", []):
				var K: Dictionary = D.WXK[w.k]
				if K.get(m, 0) and JS.hypot(x - w.x, z - w.z) < w.r and not seen.has("w" + str(w.id)):
					seen["w" + str(w.id)] = true
					o.wx += 1
			if m == "road" or m == "rail":
				for zb in CO.get("band", []):
					if JS.hypot(x - zb.x, z - zb.z) < zb.r and not seen.has("b" + str(zb.id)):
						seen["b" + str(zb.id)] = true
						o.band += 1
			if m == "sea":
				for zp in CO.get("pir", []):
					var key := "p" + str(zp.id if zp.get("id") else zp.x)
					if JS.hypot(x - zp.x, z - zp.z) < zp.r and not seen.has(key):
						seen[key] = true
						o.pir += 1
	if m == "road" and jam.size():
		for i in range(2, p.size(), 2):
			var J: Variant = jam_on(p[i - 2], p[i - 1], p[i], p[i + 1])
			if J != null and not seen.has("j" + str(J.id)):
				seen["j" + str(J.id)] = true
				o.jam += 1
	if m == "road" or m == "rail":
		var cr: Array = gen.crossings(p, CO_DU)
		o.border = cr.size()
		for c in cr:
			if inc_cross_cl(c.a, c.b, c.x, c.z) != null:
				o.cl += 1
	o.p = 1 - JS.pow(.9, o.wx) * JS.pow(.88, o.band) * JS.pow(.8, o.pir)   # damage: bad weather, bandits, pirates
	return o


# ---------- one leg: own vehicles if they can do it, else a partner carrier (lpLeg) ----------
func lp_leg(LP: Dictionary, a: int, b: int, m: String, i: int, rr: Variant, via: Array) -> Variant:
	var k: Dictionary = LP.k
	var r: Variant = rr if rr != null else lp_plain(m, a, b)
	if r == null:
		return null
	var A: Dictionary = PL[a]
	var kk := k.duplicate()
	kk.multi = null
	kk.legs = null
	kk.from = a
	kk.to = b
	kk.mode = m
	kk.minR = 0
	kk.tons = LP.tn if LP.get("tn") != null else k.tons
	if i == 0:
		kk._veh = LP.get("veh0")
		kk._ctry = PL[LP.pts[0]].cid if not lp_is_w(LP.pts[0]) else null
	var P: Variant = null
	if lp_unlocked(m):
		P = lp_with(m + str(a) + ":" + str(b), r if via.size() else null, func(): return co_plan(kk))
	var risk := lp_risk(r, m)
	if P != null and P.ok:
		return {"a": a, "b": b, "m": m, "r": r, "own": true, "P": P, "time": P.tot - (D.HAND[m] * hand_k() if i > 0 else 0.0), "cost": k.pay - P.profit,
			"run": k.pay - P.profit - P.fuel, "risk": risk, "via": via, "veh": D.VT[P.t].n + (" ×%d" % P.n if P.n > 1 else "")}
	var t := "truck"
	for x in D.VT:
		if D.VT[x].mode == m and D.VT[x].tier <= 7 and not D.VT[x].get("loc", 0):
			t = x
			break
	var T: Dictionary = D.VT[t]
	var tm: float = r.len / (T.spd * spd_k())
	var fee := lp_fee(k, r, m, LP.tn if LP.get("tn") != null else k.tons, A.cid)
	return {"a": a, "b": b, "m": m, "r": r, "via": via, "own": false, "why": P.why if P != null else null, "time": tm + D.HAND[m] * hand_k() * 2,
		"cost": fee, "risk": risk, "veh": "партнер · " + T.n.to_lower()}


# ---------- the whole plan (lpGroups, lpCalc, lpBlock) ----------
## consecutive points of one mode through road/rail nodes form one leg between two places
func lp_groups(pts: Array, modes: Array) -> Dictionary:
	var G_ := []
	var a: Variant = pts[0]
	var via := []
	var rs := []
	var m := ""
	for i in range(1, pts.size()):
		var q: Variant = pts[i]
		m = modes[i - 1]
		var r: Variant = lp_seg(m, pts[i - 1], q)
		if r == null:
			return {"G": G_, "bad": i, "tail": null}
		rs.append(r)
		if lp_is_w(q):
			via.append(q)
		else:
			G_.append({"a": a, "b": q, "m": m, "via": via, "r": lp_join(rs) if via.size() else r})
			a = q
			via = []
			rs = []
	return {"G": G_, "tail": {"via": via, "m": m, "r": lp_join(rs)} if via.size() else null}


## LP: {k: the order, pts: plan points, modes: a mode per step, veh0: the vehicle chosen for the first leg or null}
## Returns {legs, t (days), c (cost), risk, len, tr (transshipment fees), ht (hub taxes), done, late, net, tail}
func lp_calc(LP: Dictionary) -> Dictionary:
	if LP.k.get("multi") or LP.k.get("cons"):
		push_error("Sim: the planner for multi-drop flights and consolidated trips is not ported yet")
	var legs := []
	var gr := lp_groups(LP.pts, LP.modes)
	for i in gr.G.size():
		var g: Dictionary = gr.G[i]
		var L: Variant = lp_leg(LP, g.a, g.b, g.m, i, g.r, g.via)
		if L != null:
			legs.append(L)
	var t := 0.0
	var c := 0.0
	var risk := 1.0
	var len_ := 0.0
	var tr := []
	var ht := []
	for i in legs.size():
		var L: Dictionary = legs[i]
		t += L.time
		c += L.cost
		risk *= 1 - L.risk.p
		len_ += L.r.len
		if i and legs[i - 1].m != L.m:
			var f := JS.round_js((250 + LP.k.tons * 1.5) * price_k(PL[L.a].cid))
			c += f
			t += D.HAND[L.m] * hand_k() * .5
			tr.append(f)
			var x := hub_tax(LP.k, L.a, L.m)   # transshipment at a hub that is not yours: the owner charges a tax
			if x:
				c += x
				ht.append({"pid": L.a, "f": x})
		L.tEnd = t
	var last: Variant = LP.pts.back()
	var done: bool = gr.tail == null and LP.pts.size() > 1 and not lp_is_w(last) and last == LP.k.to
	var late := maxf(0, t - LP.k.dlDays)
	var pay: float = LP.k.pay * (maxf(.35, 1 - late * .12) if late > 0 else 1.0)
	return {"legs": legs, "t": t, "c": c, "risk": 1 - risk, "len": len_, "tr": tr, "ht": ht, "done": done, "late": late, "net": pay - c, "tail": gr.tail}


## why the plan cannot be sent, or null (lpBlock)
func lp_block(LP: Dictionary, C: Dictionary) -> Variant:
	var k: Dictionary = LP.k
	if LP.get("veh0") != null and C.legs.size() and not C.legs[0].own:
		var nm := "Обрана техніка"
		for v in CO.veh:
			if v.id == LP.veh0:
				nm = D.VT[v.t].n
		return "%s не підходить%s" % [nm, ": " + C.legs[0].why.to_lower() if C.legs[0].get("why") else ""]
	if k.get("minR", 0) and CO.rating < k.minR:
		return "Замовник хоче рейтинг %.1f+ (у вас %.2f)" % [k.minR, CO.rating]
	var cg: Dictionary = cargo_i[k.cg]
	for L in C.legs:
		if not lp_unlocked(L.m):
			var tmin := 99
			for t in D.VT:
				if D.VT[t].mode == L.m:
					tmin = mini(tmin, D.VT[t].tier)
			return "%s: потрібна ліцензія «%s»" % [D.MODE_N[L.m], D.LIC[tmin].n]
		var nd := perm_need(cg, L.m).filter(func(id): return not perm_ok(id))
		if nd.size():
			return "Потрібна ліцензія «%s»" % perm_i[nd[0]].n
		# without the international licence a route may not leave your country, not even in transit
		if CO.tier < 3 and (L.m == "road" or L.m == "rail"):
			var home: int = hq_p().cid
			var out: Variant = null
			for pid in [L.a, L.b]:
				if PL[pid].cid != home:
					out = PL[pid]
					break
			if out != null or gen.crossings(L.r.p, CO_DU).size():
				return "Маршрут виходить за межі країни%s: потрібна ліцензія «%s»" % [" (" + states[out.cid].name + ")" if out != null else "", D.LIC[3].n]
		if CO.tier < 5 and [L.a, L.b].any(func(pid): return not co_scope(PL[pid])):
			return "Пункт маршруту поза зоною вашої ліцензії: потрібна ліцензія «%s»" % D.LIC[5].n
	return null


## send the order along the plan (ACT.lpGo for an ordinary order): "" when sent, or why not
func lp_go(LP: Dictionary, by_mgr: bool = false) -> String:
	var C := lp_calc(LP)
	if not C.done:
		return "Маршрут не завершено"
	var b: Variant = lp_block(LP, C)
	if b != null:
		return b
	var k: Dictionary = LP.k
	k.how = "mgr" if by_mgr else "hand"
	var legs := []
	for L in C.legs:
		legs.append({"a": L.a, "b": L.b, "m": L.m, "r": L.r if L.via.size() else null})
	var plan := {"legs": legs, "ctry": PL[LP.pts[0]].cid}
	var P0: Variant = C.legs[0].get("P") if C.legs.size() else null
	plan.veh0 = LP.veh0 if LP.get("veh0") != null else (P0.vids[0] if P0 != null and P0.ok and P0.n == 1 else null)
	_drop(CO.board, k)
	var dl: float = day + k.dlDays
	hub_tax_pay(C.ht)
	lp_run_leg(k, plan, 0, dl)
	return ""
