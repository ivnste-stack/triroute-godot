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
## border crossings along a path of float32 (routes) or of doubles (a course drawn by hand)
func _cross(p: Variant, eco: float) -> Array:
	if p is PackedFloat32Array:
		return gen.crossings(p, eco)
	return gen.crossings64(PackedFloat64Array(p), eco)


func lp_risk(r: Dictionary, m: String) -> Dictionary:
	var p: Variant = r.p
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
		var cr: Array = _cross(p, CO_DU)
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
	if LP.k.get("cons"):
		return lp_calc_cons(LP)
	var M: Variant = LP.k.get("multi")
	var legs := []
	var gr := lp_groups(LP.pts, LP.modes)
	var got := {}
	for i in gr.G.size():
		var g: Dictionary = gr.G[i]
		if M != null:   # the plane carries what is still on board
			var rest := 0.0
			for d in M:
				if not got.has(d.to):
					rest += d.tons
			LP.tn = maxf(.1, JS.fixed1(rest))
		var L: Variant = lp_leg(LP, g.a, g.b, g.m, i, g.r, g.via)
		if L != null:
			legs.append(L)
		if M != null and M.any(func(d): return d.to == g.b):
			got[g.b] = true
	LP.tn = null
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
	var late := maxf(0, t - LP.k.dlDays) if M == null else 0.0
	var pay: float = LP.k.pay * (maxf(.35, 1 - late * .12) if late > 0 else 1.0)
	var drops: Variant = null
	if M != null:   # every drop has its own deadline; unloading at each drop takes a while
		drops = []
		var off := 0.0
		var last_new := -1
		var g2 := {}
		var ul: float = D.HAND.air * hand_k() * .5
		for i in legs.size():
			var L: Dictionary = legs[i]
			var d: Variant = null
			for x in M:
				if x.to == L.b:
					d = x
					break
			if d != null and not g2.has(d.to):
				g2[d.to] = true
				var eta: float = L.tEnd + off
				drops.append({"d": d, "eta": eta, "late": maxf(0, eta - d.dl)})
				off += ul
				last_new = i
		t += off
		done = gr.tail == null and g2.size() == M.size() and last_new == legs.size() - 1
		late = 0.0
		pay = 0.0
		for x in drops:
			late = maxf(late, x.late)
			pay += x.d.pay * (maxf(.35, 1 - x.late * .12) if x.late > 0 else 1.0)
	return {"legs": legs, "t": t, "c": c, "risk": 1 - risk, "len": len_, "tr": tr, "ht": ht, "done": done, "late": late, "net": pay - c, "tail": gr.tail, "drops": drops,
		"groups": gr.G.size(), "bad": gr.get("bad")}


## the order of landings for a multi-drop flight (ACT.lpOrder): "urg" — the most urgent first, "near" — the
## nearest next; returns the plan points
func lp_order(k: Dictionary, kind: String) -> Array:
	var left: Array = k.multi.map(func(d): return PL[d.to])
	var cur: Dictionary = PL[k.from]
	var ord := []
	var dl_of := func(p): return k.multi.filter(func(d): return d.to == p.id)[0].dl
	if kind == "urg":
		_stable_sort(left, func(a, b): return dl_of.call(a) - dl_of.call(b))
		ord = left
	else:
		while left.size():
			var c0: Dictionary = cur
			_stable_sort(left, func(a, b): return JS.hypot(a.x - c0.x, a.z - c0.z) - JS.hypot(b.x - c0.x, b.z - c0.z))
			cur = left.pop_front()
			ord.append(cur)
	return [k.from] + ord.map(func(p): return p.id)


## why the plan cannot be sent, or null (lpBlock)
func lp_block(LP: Dictionary, C: Dictionary) -> Variant:
	var k: Dictionary = LP.k
	if C.get("consBlock") != null:
		return C.consBlock
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
	# the HTML version counted a plan as done even when a leg had no route at all, and then failed to send it
	if C.get("bad") != null or C.legs.is_empty() or C.legs.size() != C.get("groups", C.legs.size()):
		return "Ділянку маршруту не прокласти"
	var b: Variant = lp_block(LP, C)
	if b != null:
		return b
	var k: Dictionary = LP.k
	if k.get("cons"):
		cons_go_plan(LP, C, by_mgr)
		return ""
	k.how = "mgr" if by_mgr else "hand"
	var legs := []
	for L in C.legs:
		legs.append({"a": L.a, "b": L.b, "m": L.m, "r": L.r if L.via.size() else null})
	var plan := {"legs": legs, "ctry": PL[LP.pts[0]].cid}
	var P0: Variant = C.legs[0].get("P") if C.legs.size() else null
	plan.veh0 = LP.veh0 if LP.get("veh0") != null else (P0.vids[0] if P0 != null and P0.ok and P0.n == 1 else null)
	if k.get("multi"):   # every leg carries what is still on board; a leg ending at a drop pays it there
		var got := {}
		var rem := 0.0
		for d in k.multi:
			rem += d.tons
		for L in legs:
			L.tons = JS.fixed1(maxf(.1, rem))
			L.pay = 0
			for d in k.multi:
				if d.to == L.b and not got.has(d.to):
					got[d.to] = true
					var dd: Dictionary = d.duplicate()
					dd.dlA = day + d.dl
					L.drop = dd
					rem -= d.tons
					break
		var z: Dictionary = legs.back()
		z.pay = z.drop.pay
		z.dl = z.drop.dlA
	_drop(CO.board, k)
	var dl: float = day + k.dlDays
	hub_tax_pay(C.ht)
	lp_run_leg(k, plan, 0, dl)
	return ""


# =====================================================================================================
# Changing the course of a trip under way: ships, trucks, planes (08r-multi.js, SR)
# A course point is {x, z} (a road point also has v, a lattice node; it may be a checkpoint: cp, cn).
# =====================================================================================================

## what can hurt this kind of transport: pirates & storms at sea, bandits & bad weather on roads, bad weather in the air
func sr_danger(m: String) -> Array:
	var out := []
	if m == "sea":
		for z in CO.get("pir", []):
			out.append({"x": z.x, "z": z.z, "r": z.r, "k": "pir", "n": "Пірати: " + z.get("name", "")})
	elif m == "road":
		for z in CO.get("band", []):
			out.append({"x": z.x, "z": z.z, "r": z.r, "k": "band", "n": "Бандити: " + z.get("name", "")})
	for w in CO.get("wx", []):
		if D.WXK[w.k].get(m, 0):
			out.append({"x": w.x, "z": w.z, "r": w.r, "k": "wx", "n": w.n})
	return out


static func _zones(D_: Array) -> PackedFloat64Array:
	var z := PackedFloat64Array()
	for q in D_:
		z.append_array([q.x, q.z, q.r])
	return z


## roads: the road graph; with avoid, nodes inside bandit zones, bad weather and closures are closed for this search
func sr_road(a: Dictionary, b: Dictionary, avoid: bool) -> Variant:
	var na: int = a.v if a.get("v") != null else node_at(a.x, a.z)
	var nb: int = b.v if b.get("v") != null else node_at(b.x, b.z)
	var p := PackedFloat32Array()
	if avoid:
		p = gen.node_path_avoid(na, nb, PackedInt32Array(jamn.keys()), _zones(sr_danger("road")))
	if p.is_empty():
		p = gen.node_path(na, nb, false)
	if p.is_empty():
		return null
	var out: Array = Array(p)
	if a.get("v") == null or a.get("start"):
		out = [a.x, a.z] + out
	return out


func sr_seg(m: String, a: Dictionary, b: Dictionary, avoid: bool) -> Variant:
	if m == "road":
		return sr_road(a, b, avoid)
	if m == "air" and not avoid:
		var p: PackedFloat32Array = gen.air_path(a.x, a.z, b.x, b.z)
		return Array(p) if p.size() else null
	var g: PackedFloat64Array = gen.sr_grid(m, a.x, a.z, b.x, b.z, _zones(sr_danger(m)) if avoid else PackedFloat64Array())
	return Array(g) if g.size() else null


static func sr_len(p: Variant) -> float:
	var L := 0.0
	for i in range(2, p.size(), 2):
		L += JS.hypot(p[i] - p[i - 2], p[i + 1] - p[i - 1])
	return L


## can the course of this trip be changed now (srOK)
func sr_ok(j: Dictionary) -> bool:
	if j.get("cons") or not (j.mode in ["sea", "road", "air"]) or j.get("ret") or j.get("back") or j.lost or j.get("hold", 0) > 0:
		return false
	if not CO.jobs.any(func(x): return is_same(x, j)):
		return false
	var st := co_job_state(j, co_now() - j.t0)
	var inc_ok: bool = st.get("inc") != null and (st.inc.k in ["wx", "jam"])
	if j.mode == "road" and j.lead > .002 and st.s < j.lead * .97 and (st.seg == 0 or st.get("w") != null or inc_ok):
		return true   # the empty run to the loading city
	return st.s >= j.lead - 1e-6 and st.s < j.lead + j.len * .97 and (st.seg == 1 or st.get("w") != null or inc_ok)


## during the empty run the new course leads to the loading city; the loaded part of the trip stays as planned
func sr_lead_now(j: Dictionary) -> bool:
	var st := co_job_state(j, co_now() - j.t0)
	return j.mode == "road" and j.lead > .002 and st.s < j.lead - 1e-6


func sr_lead_idx(j: Dictionary) -> int:
	var A: Dictionary = PL[j.k.from]
	var p: PackedFloat32Array = j.p
	var bi := -1
	var bd := 1e9
	var L := 0.0
	for i in p.size() / 2:
		if i:
			L += JS.hypot(p[i * 2] - p[i * 2 - 2], p[i * 2 + 1] - p[i * 2 - 1]) * CO_DU
		var d := JS.hypot(p[i * 2] - A.x, p[i * 2 + 1] - A.z) + absf(L - j.lead) * .5
		if d < bd:
			bd = d
			bi = i
	return bi


func sr_now(j: Dictionary) -> Dictionary:
	var st := co_job_state(j, co_now() - j.t0)
	var pos := co_pos_at(j, st.s)
	var rem: Array = [pos[0], pos[1]]
	var li := sr_lead_idx(j) if sr_lead_now(j) else 1000000000
	var p: PackedFloat32Array = j.p
	var i: int = pos[2] + 1
	while i <= li and i < p.size() / 2:
		rem.append(p[i * 2])
		rem.append(p[i * 2 + 1])
		i += 1
	return {"st": st, "pos": pos, "rem": rem, "left": maxf(0, j.tot - (co_now() - j.t0))}


## the nearest road point: the truck may turn back
func sr_start(j: Dictionary, N: Dictionary) -> Dictionary:
	if j.mode != "road":
		return {"x": N.pos[0], "z": N.pos[1]}
	return {"x": N.pos[0], "z": N.pos[1], "v": node_at(N.pos[0], N.pos[1]), "start": 1}


func sr_dest(j: Dictionary) -> Dictionary:
	var B: Dictionary = PL[j.k.from if sr_lead_now(j) else j.k.to]
	return {"x": B.x, "z": B.z, "v": B.node} if j.mode == "road" else {"x": B.x, "z": B.z}


func sr_build(j: Dictionary, pts: Array, avoid: bool) -> Variant:
	var N := sr_now(j)
	var way: Array = [sr_start(j, N)] + pts + [sr_dest(j)]
	var out := []
	for i in range(1, way.size()):
		var p: Variant = sr_seg(j.mode, way[i - 1], way[i], avoid)
		if p == null:
			return null
		out.append_array(p.slice(2) if out.size() else p)
	return out


## the new course against the current one (srCalc0): eta, extra fuel, risk, checkpoints
func sr_calc(j: Dictionary, pts: Array, avoid: bool) -> Dictionary:
	var m: String = j.mode
	var T: Dictionary = D.VT[j.t]
	var N := sr_now(j)
	var np: Variant = sr_build(j, pts, avoid)
	var sp: float = T.spd * spd_k()
	var old_len := sr_len(N.rem) * CO_DU
	var old_risk := lp_risk({"p": N.rem}, m)
	var unl: float = 0.0 if N.st.s >= j.lead + j.len else j.hs
	var cur_eta: float = N.left
	if np == null:
		return {"N": N, "oldLen": old_len, "oldRisk": old_risk, "curEta": cur_eta, "bad": true}
	var len_ := sr_len(np) * CO_DU
	var cps := []
	if m == "road":
		for c in _cross(np, CO_DU):
			if c.s > .03:
				cps.append({"s": c.s, "a": c.a, "b": c.b, "x": c.x, "z": c.z, "w": cp_wait(c.b, m)})
	var wait := 0.0
	for q in cps:
		wait += q.w
	var lead_tail := 0.0
	if sr_lead_now(j):
		var sw := 0.0
		for q in j.get("stops", []):
			if q.s > j.lead:
				sw += q.get("w", 0)
		lead_tail = j.tm + sw
	var eta: float = len_ / sp + unl + wait + (j.get("cust", 0) if m == "air" else 0.0) + lead_tail
	var extra := maxf(0, (len_ - old_len) * T.fuel * CO.fuel * fuel_k(m) * j.n)
	return {"N": N, "np": np, "len": len_, "eta": eta, "extra": extra, "risk": lp_risk({"p": np}, m), "oldLen": old_len, "oldRisk": old_risk,
		"curEta": cur_eta, "unl": unl, "cps": cps, "wait": wait, "dl": j.dl - co_now(), "bad": false}


## change the course (ACT.srGo): "" when done, or why not
func sr_go(j: Dictionary, pts: Array, avoid: bool) -> String:
	if not sr_ok(j):
		return "Курс змінити не можна: транспорт не в дорозі або затриманий"
	var C := sr_calc(j, pts, avoid)
	if C.bad:
		return "Курс не прокласти"
	var m: String = j.mode
	var T: Dictionary = D.VT[j.t]
	var tm: float = C.len / (T.spd * spd_k())
	if C.extra > 0:
		CO.cash -= C.extra
		CO.m.fuel += C.extra
	if sr_lead_now(j):
		var li := sr_lead_idx(j)
		var np: Array = C.np + Array(j.p.slice(li * 2)).slice(2)
		var P := PackedFloat32Array(np)
		var cps := []
		var wait := 0.0
		for c in gen.crossings(P, CO_DU):
			if c.s > .03:
				var w := cp_wait(c.b, m)
				cps.append({"s": c.s, "a": c.a, "b": c.b, "x": c.x, "z": c.z, "w": w})
				wait += w
		j.merge({"p": P, "lead": C.len, "tl": tm, "cont": false, "pz": [], "drag": [], "t0": co_now(), "wxd": null, "wxCool": 0, "srWarn": {}, "jn": null, "stops": cps}, true)
		j.erase("_c")
		j.tot = tm + j.get("hs", 0) + j.tm + wait
		j.ev.append("Перегін змінено" + (" через %d точк." % pts.size() if pts.size() else ""))
		return ""
	var H := co_alt(j, C.N.st) if m == "air" else 0.0
	j.merge({"p": PackedFloat32Array(C.np), "lead": 0.0, "tl": 0.0, "len": C.len, "tm": tm, "cont": true, "pz": [], "t0": co_now(),
		"cust": j.get("cust", 0) if m == "air" else 0.0, "wxd": null, "wxCool": 0, "srWarn": {}, "jn": null}, true)
	j.erase("_c")
	if m == "road":
		j.stops = C.cps
		j.tot = tm + C.unl + C.wait
	else:
		j.stops = []
		j.tot = tm + C.unl + j.get("cust", 0)
	if m == "air":
		j.airS = 1
		j.airH = H / .22 * CO_DU
	j.ev.append("Курс змінено" + (" через %d точк." % pts.size() if pts.size() else "") + (" в обхід небезпечних зон" if avoid else ""))
	return ""


# =====================================================================================================
# Consolidated road trips («Збірний рейс», 08v-cons.js): several orders in one vehicle; the player sets the
# order of pick-ups and drops in the planner; each order is paid at its own drop against its own deadline.
# =====================================================================================================

func cons_ok(k: Variant) -> bool:
	return k != null and k.get("legs") == null and k.get("multi") == null


func k_vol(k: Dictionary) -> float:
	var cg: Variant = cargo_i.get(k.cg)
	return JS.fixed1(k.tons * (cg.v if cg != null and cg.get("v", 0) else 3))


## the planner order for the chosen orders (ACT.consRoute): one order made of them all
func cons_make(ks: Array) -> Dictionary:
	var tons := 0.0
	var vol := 0.0
	var pay := 0.0
	var dl := -1e18
	var len_ := 0.0
	var O := []
	for k in ks:
		tons += k.tons
		vol += k_vol(k)
		pay += k.pay
		dl = maxf(dl, k.dlDays)
		len_ += k.len
		O.append({"id": k.id, "from": k.from, "to": k.to, "cg": k.cg, "tons": k.tons, "vol": k_vol(k), "pay": k.pay, "dl": k.dlDays})
	var kC := {"id": CO.uid, "from": ks[0].from, "to": ks.back().to, "cg": ks[0].cg, "tons": JS.fixed1(tons), "_vol": JS.fixed1(vol), "pay": pay, "dlDays": dl,
		"mode": ks[0].mode, "risk": 0, "minR": 0, "len": len_, "cons": O}
	CO.uid += 1
	return kC


## the dispatcher's sequence: all pick-ups nearest first, then drops by deadline (consAutoSeq)
func cons_auto_seq(k: Dictionary) -> Array:
	var O: Array = k.cons
	var seq: Array = [O[0].from]
	var left := {}
	for o in O:
		left[o.from] = true
	left.erase(O[0].from)
	var cur: Dictionary = PL[O[0].from]
	while left.size():
		var best: Variant = null
		var bd := 1e9
		for pid in left:
			var d := JS.hypot(PL[pid].x - cur.x, PL[pid].z - cur.z)
			if d < bd:
				bd = d
				best = pid
		left.erase(best)
		seq.append(best)
		cur = PL[best]
	var by_dl: Array = O.duplicate()
	_stable_sort(by_dl, func(a, b): return a.dl - b.dl)
	for o in by_dl:
		if seq.back() != o.to:
			seq.append(o.to)
	return seq


## what is in the vehicle on each leg, when each order arrives (lpCalcCons)
func lp_calc_cons(LP: Dictionary) -> Dictionary:
	var k: Dictionary = LP.k
	var O: Array = k.cons
	var gr := lp_groups(LP.pts, LP.modes)
	var seq: Array = [LP.pts[0]] + gr.G.map(func(g): return g.b)
	var picked := {}
	var dropped := {}
	var ev_at := []
	var load := []
	var vols := []
	var t_ := 0.0
	var v_ := 0.0
	var max_t := 0.0
	var max_v := 0.0
	for pid in seq:
		var ev := []
		if not lp_is_w(pid):
			for o in O:
				if not picked.has(o.id) and o.from == pid:
					picked[o.id] = true
					ev.append({"o": o, "kind": "pick"})
					t_ += o.tons
					v_ += o.vol
			for o in O:
				if picked.has(o.id) and not dropped.has(o.id) and o.to == pid and not ev.any(func(e): return is_same(e.o, o)):
					dropped[o.id] = true
					ev.append({"o": o, "kind": "drop"})
					t_ -= o.tons
					v_ -= o.vol
		ev_at.append(ev)
		load.append(JS.fixed2(maxf(0, t_)))
		vols.append(JS.fixed2(maxf(0, v_)))
		max_t = maxf(max_t, t_)
		max_v = maxf(max_v, v_)
	var legs := []
	var cons_block: Variant = null
	for i in gr.G.size():
		if cons_block != null:
			break
		var g: Dictionary = gr.G[i]
		var r: Dictionary = g.r
		var kk := k.duplicate()
		kk.multi = null
		kk.legs = null
		kk.cons = null
		kk.from = g.a
		kk.to = g.b
		kk.mode = g.m
		kk.minR = 0
		kk.tons = maxf(.1, max_t) if i == 0 else maxf(.1, load[i])
		kk._vol = max_v if i == 0 else vols[i]
		kk._one = true
		kk._veh = LP.get("consVeh") if i else LP.get("veh0")
		if i == 0:
			kk._ctry = PL[LP.pts[0]].cid
		kk.pay = 0
		var P: Variant = null
		if lp_unlocked(g.m):
			P = lp_with(g.m + str(g.a) + ":" + str(g.b), r if g.via.size() else null, func(): return co_plan(kk))
		if P == null or not P.ok:
			var why: Variant = P.why if P != null else null
			cons_block = ("%s — потрібно %s т і %s м³ в одному кузові" % [why if why else "Немає вільної техніки", JS.fixed1(max_t), JS.fixed1(max_v)]) if i == 0 \
				else "Ділянка %d: %s" % [i + 1, why if why else "техніка недоступна"]
			break
		if i == 0:
			LP.consVeh = P.vids[0]
		legs.append({"a": g.a, "b": g.b, "m": g.m, "r": r, "own": true, "P": P, "time": P.tot - (D.HAND[g.m] * hand_k() if i > 0 else 0.0), "cost": -P.profit,
			"risk": lp_risk(r, g.m), "via": g.via, "veh": D.VT[P.t].n, "tons": load[i], "vol": vols[i]})
	var t := 0.0
	var c := 0.0
	var risk := 1.0
	var len_ := 0.0
	for L in legs:
		t += L.time
		c += L.cost
		risk *= 1 - L.risk.p
		len_ += L.r.len
		L.tEnd = t
	var rows := []
	var pay := 0.0
	var late := 0.0
	var all_dropped := true
	for o in O:
		var eta: Variant = null
		for i in range(1, mini(seq.size() - 1, legs.size()) + 1):
			if ev_at[i].any(func(e): return is_same(e.o, o) and e.kind == "drop"):
				eta = legs[i - 1].tEnd
		var lt: float = maxf(0, eta - o.dl) if eta != null else 0.0
		var dr: bool = dropped.has(o.id)
		rows.append({"o": o, "picked": picked.has(o.id), "dropped": dr, "eta": eta, "late": lt})
		if dr:
			pay += o.pay * (maxf(.35, 1 - lt * .12) if lt > 0 else 1.0)
		late = maxf(late, lt)
		all_dropped = all_dropped and dr
	var done: bool = gr.tail == null and cons_block == null and legs.size() == gr.G.size() and all_dropped and LP.pts.size() > 1 and not lp_is_w(LP.pts.back())
	return {"legs": legs, "t": t, "c": c, "risk": 1 - risk, "len": len_, "tr": [], "ht": [], "done": done, "late": late, "net": pay - c, "tail": gr.tail,
		"drops": null, "rows": rows, "evAt": ev_at, "consBlock": cons_block, "maxT": max_t, "maxV": max_v}


## go: the legs run one after another with the pinned vehicle; orders are paid where they are dropped (consGoPlan)
func cons_go_plan(LP: Dictionary, C: Dictionary, by_mgr: bool = false) -> void:
	var k: Dictionary = LP.k
	var how := "mgr" if by_mgr else "hand"
	var legs := []
	for i in C.legs.size():
		var L: Dictionary = C.legs[i]
		var drops := []
		var evs: Array = C.evAt[i + 1] if i + 1 < C.evAt.size() else []
		for e in evs:
			if e.kind == "drop":
				var o: Dictionary = e.o.duplicate()
				o.dlA = day + e.o.dl
				o.done = 0
				o.how = how
				drops.append(o)
		legs.append({"a": L.a, "b": L.b, "m": L.m, "r": L.r if L.via.size() else null, "tons": maxf(.1, L.tons), "vol": L.vol, "pay": 0, "drops": drops})
	var plan := {"legs": legs, "cons": true, "veh": LP.consVeh}
	for v in CO.veh:
		if v.id == plan.veh:
			v.resv = k.id
			break
	CO.board = CO.board.filter(func(x): return not k.cons.any(func(o): return o.id == x.id))
	lp_run_leg(k, plan, 0, day + k.dlDays)
