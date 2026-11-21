class_name Sim
extends RefCounted
## The logistics game state and rules: a port of the company mode of the HTML version (legacy/src/08e-company.js
## and the modules that wrap it). Names follow the original (CO, PL, coGen…) so every function can be checked
## against its JS source. The order of RNG calls is kept, so a new game starts exactly like the HTML version.
##
## Part 1 (this file so far): places, company start, the order board (coGen with permits and firms).

const D = preload("res://scripts/logistics/game_data.gd")

var gen: Object                 # TRWorldGen: world, board, routes
var seed_value := 0
var states: Array = []          # G.C
var board: Dictionary = {}      # BOARD
var PL: Array = []              # places (towns)
var CO: Dictionary = {}         # the company
var R: Mulberry                 # the game RNG (R in the HTML version)
var day := 0.0                  # G.day
var date := {"d": 1, "m": 0, "y": 2026}
var diff := 1                   # G.diff
var CO_DU := .16
var routes := {}                # CO_ROUTES
var firms := {}                 # FIRMS
var nspec := {}                 # NSPEC
var cargo_i := {}               # CARGO_I
var perm_i := {}                # PERM_I


## A new game on the world made by gen.generate(seed) (states, board and textures already built there).
func setup(gen_: Object, seed_: int, states_: Array, board_: Dictionary) -> void:
	gen = gen_
	seed_value = seed_
	states = states_
	board = board_
	for c in D.CARGO:
		cargo_i[c.id] = c
	for p in D.PERM:
		perm_i[p.id] = p
	# the RNG continues after the states (makeCountry + colours), then initRelations and calibrateResources
	R = Mulberry.new(0)
	R._a = int(gen.states_rng_state())
	var n := states.size()
	for i in n * (n - 1):            # initRelations: rnd(-20,20) for every ordered pair
		R.next()
	for k in D.RES.size():           # calibrateResources: rnd(.98,1.06) per resource, rnd(1,3) per state
		R.next()
		for i in n:
			R.next()
	_places()


# ---------- RNG helpers (rnd, rint, pick, chance of 03-core.js) ----------
func rnd(a: float, b = null) -> float:
	return R.next() * a if b == null else a + R.next() * (float(b) - a)


func rint(a: int, b: int) -> int:
	return int(floor(rnd(a, b + 1)))


func pick(a: Array) -> Variant:
	return a[int(floor(R.next() * a.size()))]


func chance(p: float) -> bool:
	return R.next() < p


# ---------- places (coPlaces) ----------
func _places() -> void:
	var land: PackedInt32Array = gen.continents()
	var rnodes := {}
	for t in board.towns:
		if board.rbits[t.node] != 0:
			rnodes[t.node] = true
	PL = []
	var i := 0
	for t in board.towns:
		PL.append({"id": i, "cid": t.cid, "name": t.name, "type": t.type, "x": t.x, "z": t.z, "pop": t.pop,
			"air": t.air_ov if t.air_ov else (t.type == "cap" or t.type == "big"),
			"port": 1 if t.port else null, "rail": rnodes.has(t.node), "land": land[t.cid], "node": t.node,
			"wc_i": t.wc_i, "wc_j": t.wc_j})
		i += 1


# ---------- helpers (08e-company.js) ----------
func msk(id: String) -> float:
	return CO.mgr[id].skill / 10.0 if CO.has("mgr") and CO.mgr.has(id) else 0.0


func price_k(cid: int) -> float:
	return .45 + states[cid].dev * 1.35


func wage_k(cid: int) -> float:
	return .4 + states[cid].dev * 1.5


func bur(cid: int) -> float:
	return 10 + (1 - JS.clamp_js(states[cid].dev, 0, 1)) * 60 if cid >= 0 and cid < states.size() else 35.0


func co_risk(cid: int) -> float:
	var c: Dictionary = states[cid]
	var r: float = bur(cid) / 80 * .55 + (100 - c.stability) / 100 * .45
	for x in CO.get("conf", []):
		if x.a == cid or x.b == cid:
			r += .6
			break
	return JS.clamp_js(r, 0, 1.2)


func in_conf(cid: int) -> bool:
	for x in CO.conf:
		if x.a == cid or x.b == cid:
			return true
	return false


func hq_p() -> Dictionary:
	return PL[CO.hq]


func co_scope(p: Dictionary) -> bool:
	var H := hq_p()
	if CO.tier >= 5:
		return true
	if CO.tier >= 3:
		return p.land == H.land
	if CO.tier >= 1:
		return p.cid == H.cid
	return p.id == H.id


func hub_at(pid: int) -> Variant:
	for h in CO.get("hubs", []):
		if h.pid == pid:
			return h
	return null


func co_grade() -> int:
	var x: float = CO.get("xp", 0)
	var g := 0
	for i in D.GRADES.size():
		if x >= D.GRADES[i].xp:
			g = i
	return g


func spd_k() -> float:
	return .15


func hand_k() -> float:
	return .4


func co_board_max() -> int:
	if CO.tier < 1:
		return 0
	var s := 0
	for h in CO.hubs:
		s += h.lvl - 1
	return 8 + CO.tier * 2 + int(JS.round_js(msk("cco") * 4)) + s


# ---------- routes (coRoute, cached) ----------
func co_route(mode: String, a: int, b: int) -> Variant:
	var A: Dictionary = PL[a]
	if a == b:
		return {"p": PackedFloat32Array([A.x, A.z, A.x, A.z]), "len": 0.0}
	var key := mode + str(a) + ":" + str(b)
	if routes.has(key):
		return routes[key]
	var B: Dictionary = PL[b]
	var p := PackedFloat32Array()
	if mode == "road":
		p = gen.route("road", a, b)
	elif mode == "sea" and A.port != null and B.port != null:
		p = gen.route("sea", a, b)
	elif mode == "rail" and A.rail and B.rail:
		p = gen.route("rail", a, b)
	elif mode == "air" and A.air and B.air:
		p = gen.air_path(A.x, A.z, B.x, B.z)
	var res: Variant = null
	if p.size() >= 4:
		var L := 0.0
		for i in range(2, p.size(), 2):
			L += JS.hypot(p[i] - p[i - 2], p[i + 1] - p[i - 1])
		res = {"p": p, "len": L * CO_DU}
	routes[key] = res
	return res


func mode_ok(mode: String, p: Dictionary) -> bool:
	return p.port != null if mode == "sea" else (p.air if mode == "air" else (p.rail if mode == "rail" else true))


# ---------- company start (coInit, coSetHQ) ----------
## Suggested capitals for the first hub (startBoard), in the order the HTML version offers them.
func start_choices() -> Array:
	var comp: PackedInt32Array = board.comp
	var csz: PackedInt32Array = board.comp_size
	var tiny := func(p): return comp[p.node] < 0 or csz[comp[p.node]] < D.TINY_ISL
	var mates := func(p):
		var n := 0
		for q in PL:
			if q != p and q.cid == p.cid and comp[q.node] == comp[p.node]:
				n += 1
		return n
	var caps := PL.filter(func(p): return p.type == "cap" and not tiny.call(p))
	var ok := caps.filter(func(p): return mates.call(p) >= 2)
	if ok.size() >= 3:
		caps = ok
	caps.sort_custom(func(a, b): return states[a.cid].dev - states[b.cid].dev < 0)
	# Array.sort_custom is not stable; ties of dev never happen with random devs, but keep it explicit
	var out := []
	for f in [.08, .3, .5, .72, .94]:
		var p: Dictionary = caps[mini(caps.size() - 1, int(floor(f * caps.size())))]
		if not out.has(p):
			out.append(p)
	return out


func co_init(hq: int) -> void:
	var nm: String = pick(D.CO_NAMES_A) + pick(D.CO_NAMES_B)
	CO = {"name": nm, "col": "#ffb347", "hq": hq, "cash": [8000, 3500, 2000][diff], "rating": 3.0, "tier": 1, "veh": [], "jobs": [], "board": [], "hubs": [],
		"staff": {"driver": 1, "rail": 0, "sailor": 0, "pilot": 0}, "founder": 0, "wageLv": 1, "morale": 66.0, "mgr": {}, "cand": {}, "loans": [], "ins": false,
		"fuel": 1.0, "maint": 1, "pir": [], "conf": [], "comp": [], "hist": {"cash": [], "rev": [], "rat": [], "prof": []}, "m": co_zero(), "lm": null, "uid": 1,
		"auto": false, "ms": [], "deliv": 0.0, "cdel": 0, "xp": 0.0, "tons": 0.0, "mcd": 0, "tenders": [], "flags": {}, "neg": 0, "cls": [], "wx": [], "clV": 1,
		"pool": {"driver": 3, "rail": 0, "sailor": 0, "pilot": 0}, "strike": 0, "dayLocal": 0, "buyAt": null, "last": []}


func co_zero() -> Dictionary:
	return {"office": 0.0, "local": 0.0, "contract": 0.0, "tender": 0.0, "wage": 0.0, "mgmt": 0.0, "fuel": 0.0, "upkeep": 0.0, "rent": 0.0, "ins": 0.0,
		"interest": 0.0, "claims": 0.0, "other": 0.0, "mk": 0.0, "stolen": 0.0, "hubtax": 0.0}


func co_set_hq(pid: int) -> void:
	CO.hq = pid
	CO.hubs = [{"pid": pid, "lvl": 1, "share": .05, "mk": 0}]
	CO.veh = [{"id": CO.uid, "t": "ltruck", "loc": pid, "st": "idle", "cond": 100.0, "km": 0.0}]
	CO.uid += 1
	var R2 := Mulberry.new((seed_value ^ 0x7f4a) & 0xFFFFFFFF)
	CO.comp = []
	var cn: Array = D.COMP_N
	for i in cn.size():
		var rev := exp(log(1.5e6) + (float(i) / (cn.size() - 1) * .8 + R2.next() * .2) * log(60))
		CO.comp.append({"n": cn[i], "rev": rev, "g": .004 + R2.next() * .01})
	var i := 0
	while i < 40 and CO.board.size() < mini(co_board_max(), 10):
		var k: Variant = co_gen()
		if k != null:
			CO.board.append(k)
		i += 1
	for t in 6:
		co_mgr_cand("")


func co_mgr_sal(skill: int) -> int:
	var rev := 0.0
	if CO.lm != null:
		rev = CO.lm.local + CO.lm.contract + CO.lm.tender
	return int(JS.round_js((1200 + skill * 380) * (1 + log(1 + rev / 150000) / log(10) * .8) * (.6 + .4 * price_k(hq_p().cid)) / 10) * 10)


func co_mgr_cand(id: String) -> void:
	if id == "":
		for s in D.MG:
			if not CO.cand.has(s.id):
				co_mgr_cand(s.id)
		return
	var L := []
	for i in 3:
		var sk := int(JS.clamp_js(JS.round_js(rnd(2, 9.5)), 1, 10))
		var nm: String = pick(D.FIRST) + " " + pick(D.LAST)
		var age := rint(28, 63)
		L.append({"name": nm, "age": age, "skill": sk, "sal": co_mgr_sal(sk), "trait": pick(D.MG_TR), "honest": chance(.78), "loyal": rint(45, 85)})
	CO.cand[id] = L


# ---------- firms (08g-business.js) ----------
func _firm_name(ind: String, r: Mulberry) -> String:
	var I: Dictionary = D.IND[ind]
	if I.has("fixed"):
		return I.fixed[int(floor(r.next() * I.fixed.size()))]
	var nm: String = I.a[int(floor(r.next() * I.a.size()))] + I.b[int(floor(r.next() * I.b.size()))]
	var f := int(floor(r.next() * 5))
	if ind == "bank":
		return "АТ «%s»" % nm
	return ["ТОВ «%s»", "ПрАТ «%s»", "Група «%s»"][f] % nm if f < 3 else "«%s»" % nm


func firms_of(pid: int) -> Array:
	if firms.has(pid):
		return firms[pid]
	var p: Dictionary = PL[pid]
	var r := Mulberry.new((seed_value * 31 + pid * 7919) & 0xFFFFFFFF)
	var L := []
	var base: int = {"cap": 9, "big": 7, "city": 4, "town": 2, "vil": 1}.get(p.type, 2)
	var mult := 1.0 if p.type == "vil" else JS.clamp_js(.75 + sqrt(p.pop if p.pop else .1) * .35, .75, 1.6)
	var n := maxi(1, int(JS.round_js(base * mult)))
	var pool := ["retail", "food", "build", "tech", "furn", "agro", "pharma", "auto", "metal", "energy"]
	if p.type == "vil" or p.type == "town":
		pool.append_array(["agro", "agro", "food"])
	var want := ["retail"]
	if p.port != null:
		want.append("port")
	if p.air and p.type != "town":
		want.append("aero")
	if p.type == "cap":
		want.append_array(["bank", "pharma"])
	while want.size() < n:
		want.append(pool[int(floor(r.next() * pool.size()))])
	var seen := {}
	for ind in want.slice(0, n):
		var nm := _firm_name(ind, r)
		var k := 0
		while seen.has(nm) and k < 5:
			k += 1
			nm = _firm_name(ind, r)
		seen[nm] = true
		L.append({"n": nm, "ind": ind})
	firms[pid] = L
	return L


func firm_for(pid: int, inds: Array, salt: int) -> Dictionary:
	var L := firms_of(pid)
	var m := L.filter(func(f): return inds.has(f.ind))
	if m.size():
		return m[absi(salt) % m.size()]
	var r := Mulberry.new((seed_value * 131 + pid * 31 + String(inds[0]).length() * 977 + salt) & 0xFFFFFFFF)
	var f := {"n": _firm_name(inds[0], r), "ind": inds[0], "extra": 1}
	L.append(f)
	return f


func biz_firms_k(k: Dictionary) -> void:
	var ii: Array = D.CG_IND.get(k.cg, [["retail"], ["retail"]])
	k.fs = firm_for(k.get("src", k.from), ii[0], k.id).n
	k.ft = firm_for(k.get("dst", k.to), ii[1], k.id * 7 + 3).n


# ---------- permits (08g-business.js) ----------
func perm_need(cg: Variant, mode: String) -> Array:
	var r := []
	if cg == null:
		return r
	if cg.get("dg"):
		r.append("imdg" if mode == "sea" else ("dgr" if mode == "air" else "adr"))
	if cg.get("cls"):
		r.append(cg.cls)
	if cg.id == "med":
		r.append("gdp")
	if cg.id == "gold":
		r.append("valu")
	return r


func perm_ok(id: String) -> bool:
	return CO.has("perm") and CO.perm.has(id) and CO.perm[id].until > day


# ---------- chains (chNear, chLand, roadLim) ----------
func road_lim() -> float:
	var own := []
	for v in CO.veh:
		if D.VT[v.t].mode == "road":
			own.append(D.VT[v.t].cap)
	var c := own
	if c.is_empty():
		for t in D.VT:
			if D.VT[t].mode == "road" and D.VT[t].tier <= CO.tier:
				c.append(D.VT[t].cap)
	return c.max() * 8 if c.size() else 0.0


func node_ok(m: String, p: Dictionary) -> bool:
	return true if m == "road" else (p.rail if m == "rail" else (p.port != null if m == "sea" else p.air))


func ch_near(p: Dictionary, m: String, n: int = 2) -> Array:
	var L := []
	for q in PL:
		if q.land == p.land and node_ok(m, q) and not in_conf(q.cid) and (CO.tier >= 3 or q.cid == p.cid):
			L.append({"q": q, "d": JS.hypot(q.x - p.x, q.z - p.z)})
	_stable_sort(L, func(a, b): return a.d - b.d)
	return L.slice(0, n).map(func(o): return o.q)


func ch_cost(m: String, len_: float, t: float) -> float:
	return D.CH_RATE[m] * len_ * pow(t, .85) + D.CH_BASE[m] * .15


func ch_land(X: Dictionary, Y: Dictionary, tons: float, no_rail: bool) -> Variant:
	if X.id == Y.id:
		return []
	var lim := road_lim()
	var best: Variant = null
	var bc := 1e18
	if tons <= lim:
		var r: Variant = co_route("road", X.id, Y.id)
		if r != null:
			bc = ch_cost("road", r.len, tons)
			best = [{"a": X.id, "b": Y.id, "m": "road", "len": r.len}]
	if not no_rail and CO.tier >= 4:
		for S1 in ch_near(X, "rail", 2):
			for S2 in ch_near(Y, "rail", 2):
				if S1.id == S2.id:
					continue
				var rr: Variant = co_route("rail", S1.id, S2.id)
				if rr == null:
					continue
				var L := []
				var c := ch_cost("rail", rr.len, tons)
				var ok := true
				for uv in [[X, S1], [S2, Y]]:
					if uv[0].id == uv[1].id:
						continue
					if tons > lim:
						ok = false
						break
					var r2: Variant = co_route("road", uv[0].id, uv[1].id)
					if r2 == null:
						ok = false
						break
					c += ch_cost("road", r2.len, tons)
					L.append({"a": uv[0].id, "b": uv[1].id, "m": "road", "len": r2.len})
				if not ok:
					continue
				var legs := []
				if X.id != S1.id:
					legs.append(L[0])
				legs.append({"a": S1.id, "b": S2.id, "m": "rail", "len": rr.len})
				if S2.id != Y.id:
					legs.append(L[L.size() - 1])
				if c < bc:
					bc = c
					best = legs
	return best


func co_pir_on(p: PackedFloat32Array) -> bool:
	if CO.pir.is_empty():
		return false
	for i in range(0, p.size(), 2):
		for z in CO.pir:
			if JS.hypot(p[i] - z.x, p[i + 1] - z.z) < z.r:
				return true
	return false


## Array.prototype.sort with a numeric comparator: stable (TimSort). GDScript's sort_custom is not stable,
## so this is a plain stable merge sort.
static func _stable_sort(a: Array, cmp: Callable) -> void:
	if a.size() < 2:
		return
	var tmp := a.duplicate()
	_msort(a, tmp, 0, a.size(), cmp)


static func _msort(a: Array, tmp: Array, lo: int, hi: int, cmp: Callable) -> void:
	if hi - lo < 2:
		return
	var mid := (lo + hi) >> 1
	_msort(a, tmp, lo, mid, cmp)
	_msort(a, tmp, mid, hi, cmp)
	var i := lo
	var j := mid
	var k := lo
	while i < mid and j < hi:
		if cmp.call(a[j], a[i]) < 0:
			tmp[k] = a[j]
			j += 1
		else:
			tmp[k] = a[i]
			i += 1
		k += 1
	while i < mid:
		tmp[k] = a[i]
		i += 1
		k += 1
	while j < hi:
		tmp[k] = a[j]
		j += 1
		k += 1
	for q in range(lo, hi):
		a[q] = tmp[q]


# ---------- the order board (coGen + the permit / firm wrapper of 08g) ----------
func co_gen() -> Variant:
	var k: Variant = _co_gen()
	if k == null:
		return null
	var nd := perm_need(cargo_i[k.cg], k.mode).filter(func(id): return not perm_ok(id))
	if nd.size():
		var above := nd.any(func(id): return perm_i[id].tier > CO.tier)
		if above or chance(.8):
			return null
	biz_firms_k(k)
	return k


func _co_gen() -> Variant:
	var modes := []
	if CO.tier >= 1:
		modes.append_array(["road", "road", "road"])
	if CO.tier >= 4:
		modes.append_array(["rail", "rail"])
	if CO.tier >= 5:
		modes.append_array(["sea", "sea"])
	if CO.tier >= 6:
		modes.append_array(["air", "air"])
	var mode: String = pick(modes)
	var aid_ok: bool = CO.tier >= 3
	var HP: Array = CO.hubs.map(func(h): return PL[h.pid])
	var lands := {}
	for p in HP:
		lands[p.land] = true
	var Dref := 2.6
	var onB := {}
	for q in CO.board:
		onB[str(q.from)] = onB.get(str(q.from), 0) + 1
		var kk := str(q.from) + ":" + str(q.to)
		onB[kk] = onB.get(kk, 0) + 1
	var hubC := {}
	for p in HP:
		hubC[p.cid] = true
	var ownC := {}
	for h in CO.hubs:
		if not h.get("rent"):
			ownC[PL[h.pid].cid] = true
	var pool := PL.filter(func(p): return lands.has(p.land) and co_scope(p) and not in_conf(p.cid) and hubC.has(p.cid))
	if pool.is_empty():
		return null
	var tw := 0.0
	var waitAt := {}
	for v in CO.veh:
		if v.st == "idle" and v.get("idle0") != null and hub_at(v.loc) == null:
			waitAt[v.loc] = true
	var ws := []
	for p in pool:
		var d := 1e9
		var lv := 1
		for h in CO.hubs:
			var q: Dictionary = PL[h.pid]
			var dd := JS.hypot(q.x - p.x, q.z - p.z)
			if dd < d:
				d = dd
				lv = h.lvl
		var w: float = pow(firms_of(p.id).size(), 1.25) * (sqrt(p.pop) + .15) * D.HUB_ORD[lv] / (1 + (d / Dref) * (d / Dref)) * (3.0 if waitAt.has(p.id) else 1.0) / (1 + 1.5 * onB.get(str(p.id), 0)) * (1.0 if ownC.has(p.cid) else .3)
		tw += w
		ws.append(w)
	var chosen := -1
	# capitals ship about half of the freight, the other cities the rest
	var has_own := pool.any(func(p): return ownC.has(p.cid))
	var has_rent := pool.any(func(p): return not ownC.has(p.cid))
	var want_own := (not has_rent) or (has_own and chance(.78))
	var in_set := func(p): return ownC.has(p.cid) == want_own or not has_own
	var capI := []
	var oth := []
	for i in pool.size():
		if pool[i].type == "cap" and in_set.call(pool[i]):
			capI.append(i)
		elif pool[i].type != "cap" and in_set.call(pool[i]):
			oth.append(i)
	var use_cap: bool = capI.size() > 0 and (oth.is_empty() or chance(.5))
	var idx: Array = capI if use_cap else oth
	var t := 0.0
	var wl := []
	for i in idx:
		var x: float = ws[i] if use_cap else sqrt(ws[i]) * (1.0 if ownC.has(pool[i].cid) else .3)
		t += x
		wl.append(x)
	if t > 0:
		var r := R.next() * t
		for q in idx.size():
			r -= wl[q]
			if r <= 0:
				chosen = idx[q]
				break
	var r0 := R.next() * tw
	var A: Dictionary = pool[0]
	if chosen >= 0:
		A = pool[chosen]
	else:
		for i in pool.size():
			r0 -= ws[i]
			if r0 <= 0:
				A = pool[i]
				break
	# cargo and tonnage by the main mode
	var caps := []
	for tk in D.VT:
		if D.VT[tk].mode == mode and D.VT[tk].tier <= CO.tier:
			caps.append(D.VT[tk].cap)
	if caps.is_empty():
		return null
	var cap_max: float = caps.max()
	var own := 0.0
	for v in CO.veh:
		if D.VT[v.t].mode == "road":
			own += D.VT[v.t].cap
	var rng_: Array = {"road": [.3, maxf(1.5, minf(cap_max * 2.4, own * 1.15))], "rail": [80, 5000 if CO.tier >= 7 else 2400],
		"sea": [300, 40000 if CO.tier >= 7 else 16000], "air": [1, 400 if CO.tier >= 7 else 110]}[mode]
	var main: Variant = null
	var B: Dictionary
	var far := func(p, q, kk): return JS.hypot(p.x - q.x, p.z - q.z) * CO_DU > kk
	if mode == "road":
		var c := PL.filter(func(p): return p.id != A.id and p.land == A.land and co_scope(p) and (CO.tier >= 3 or p.cid == A.cid) and (not in_conf(p.cid) or aid_ok))
		if c.is_empty():
			return null
		var dom := c.filter(func(p): return p.cid == A.cid)
		if dom.size() and chance(.5):
			c = dom
		var gr_ := co_grade()
		var t2 := 0.0
		var w2 := []
		for p in c:
			var w: float = (sqrt(p.pop) + .1) / (1 + 3 * onB.get(str(A.id) + ":" + str(p.id), 0)) * (4.0 if p.cid == A.cid else 1.0)
			if gr_ < 2:
				var dd := JS.hypot(p.x - A.x, p.z - A.z)
				w /= 1 + dd * dd / 4
			t2 += w
			w2.append(w)
		var r2 := R.next() * t2
		B = c[0]
		for i in c.size():
			r2 -= w2[i]
			if r2 <= 0:
				B = c[i]
				break
	else:
		var n1 := ch_near(A, mode, 1)
		if n1.is_empty():
			return null
		var P1: Dictionary = n1[0]
		var c := PL.filter(func(p): return p.id != P1.id and node_ok(mode, p) and co_scope(p) and (not in_conf(p.cid) or aid_ok) and (
			(p.land == P1.land and (CO.tier >= 3 or p.cid == P1.cid) and far.call(p, P1, .5)) if mode == "rail" else (
			(p.land != P1.land or far.call(p, P1, .9)) if mode == "sea" else far.call(p, P1, .6))))
		if c.is_empty():
			return null
		var P2: Dictionary = pick(c)
		var rr: Variant = co_route(mode, P1.id, P2.id)
		if rr == null:
			return null
		main = {"a": P1.id, "b": P2.id, "m": mode, "len": rr.len}
		var nearL := PL.filter(func(p): return p.land == P2.land and co_scope(p) and (not in_conf(p.cid) or aid_ok) and JS.hypot(p.x - P2.x, p.z - P2.z) < 1.2)
		_stable_sort(nearL, func(a, b): return JS.hypot(a.x - P2.x, a.z - P2.z) - JS.hypot(b.x - P2.x, b.z - P2.z))
		nearL = nearL.slice(0, 6)
		B = P2 if chance(.35) else pick(nearL if nearL.size() else [P2])
	var aid := (in_conf(B.cid) or in_conf(A.cid)) and aid_ok
	var cgs := D.CARGO.filter(func(cg): return (cg.get("aid", false) if aid else not cg.get("aid", false)) and cg.t[1] >= rng_[0] and cg.t[0] <= rng_[1] and (mode != "air" or cg.val >= 2500 or cg.get("aid", false)))
	if cgs.is_empty():
		return null
	var cg: Dictionary = pick(cgs)
	var lo := maxf(cg.t[0], rng_[0])
	var hi := minf(cg.t[1], rng_[1])
	var tons := lo * pow(hi / lo, pow(R.next(), 1.6))
	if mode == "road":
		var ov := 0.0
		for v in CO.veh:
			if D.VT[v.t].mode == "road":
				ov += D.VT[v.t].get("vol", 0)
		if ov > 0:
			tons = maxf(.3, minf(tons, ov * 1.1 / (cg.get("v", 3) if cg.get("v", 0) else 3)))
	tons = JS.fixed1(tons) if tons < 5 else JS.round_js(tons)
	# legs: feeders by road (or rail) to the port / station / airport and from it; partners sometimes do a part
	var legs: Variant
	var p_in: Variant = null
	var p_out: Variant = null
	if mode == "road":
		legs = ch_land(A, B, tons, true)
		if legs == null or legs.is_empty():
			return null
		if legs[0].len < .03:
			return null
	else:
		var P1: Dictionary = PL[main.a]
		var P2: Dictionary = PL[main.b]
		var pre: Variant = ch_land(A, P1, tons, mode == "rail")
		var post: Variant = ch_land(P2, B, tons, mode == "rail")
		var hub_on := {}
		for p in HP:
			hub_on[p.land] = true
		if pre == null or (pre.size() and chance(.3)):
			if (pre != null and pre.size()) or A.id != P1.id:
				p_in = P1.id
			pre = []
		if post == null or (post.size() and (chance(.25) or not hub_on.has(P2.land))):
			if B.id != P2.id:
				p_out = P2.id
			post = []
		legs = pre + [main] + post
	var from: int = legs[0].a
	var to: int = legs[legs.size() - 1].b
	var F: Dictionary = PL[from]
	var T_: Dictionary = PL[to]
	var ml: Dictionary = legs[0]
	for L in legs:
		if D.CH_RATE[L.m] * L.len > D.CH_RATE[ml.m] * ml.len:
			ml = L
	var len_ := 0.0
	for L in legs:
		len_ += L.len
	var border: bool = F.cid != T_.cid
	var travel := 0.0
	for L in legs:
		travel += L.len / (D.CH_SPD[L.m] * spd_k()) + D.HAND[L.m] * hand_k() * 2
	travel += 1 * hand_k() if border else 0.0
	var urg := R.next()
	var has_sea: bool = legs.any(func(L): return L.m == "sea")
	var dl_days := maxf(.6, travel * (2.3 - urg * .9) + (3.0 if has_sea else .4))
	var sea_l: Variant = null
	for L in legs:
		if L.m == "sea":
			sea_l = L
			break
	var risk := JS.clamp_js((co_risk(F.cid) + co_risk(T_.cid)) / 2 * cg.get("theft", .7) + (.5 if sea_l != null and co_pir_on(co_route("sea", sea_l.a, sea_l.b).p) else 0.0), 0, 2)
	var min_r := JS.clamp_js(JS.round_js((CO.rating + rnd(-.4, .5)) * 10) / 10, 2.5, 4.9) if chance(.22) else 0.0
	var gr := co_grade()
	var prem := gr >= 2 and chance(.15)
	var vip := (not prem) and gr >= 3 and chance(.12)
	var pk := (price_k(F.cid) + price_k(T_.cid)) / 2
	var base := 0.0
	for L in legs:
		base += D.CH_BASE[L.m] * (1.0 if is_same(L, ml) else .25) + D.CH_RATE[L.m] * L.len * pow(tons, .85)
	var pay := JS.round_js(base * cg.k * pk * (1 + urg * .45) * (1 + risk * .18) * (.8 + CO.rating * .07) * (1 + msk("cco") * .12) * (1.3 if min_r else 1.0) * (1.4 if aid else 1.0) * rnd(.9, 1.1) * (1 + gr * .03) * (rnd(1.4, 1.6) if prem else 1.0) * (1.35 if vip else 1.0))
	var dl_k := .65 if prem else (1.25 if gr < 2 else 1.0)
	var k := {"id": CO.uid, "from": from, "to": to, "cg": cg.id, "tons": tons, "pay": pay, "dlDays": JS.fixed1(dl_days * dl_k), "mode": ml.m, "risk": risk,
		"minR": min_r, "len": len_, "exp": day + (rint(2, 4) if prem else rint(5, 12))}
	CO.uid += 1
	if prem:
		k.prem = 1
	if vip:
		k.vip = 1
	if legs.size() > 1:
		k.legs = legs.map(func(L): return {"a": L.a, "b": L.b, "m": L.m})
	if p_in != null:
		k.pIn = p_in
		k.src = A.id
	if p_out != null:
		k.pOut = p_out
		k.dst = B.id
	return k
