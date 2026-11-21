class_name SimCore
extends RefCounted
## The logistics game state and rules: a port of the company mode of the HTML version (legacy/src/08e-company.js
## and the modules that wrap it). Names follow the original (CO, PL, coGen…) so every function can be checked
## against its JS source. The order of RNG calls is kept, so a new game starts exactly like the HTML version.
##
## Part 1: places, company start, the order board (coGen with permits and firms).
## Part 2: planning a trip (coPlan1/coPlan), dispatch with border checkpoints, the trip state machine, delivery,
## returns to the hub, the day (coLocal, the board, the dispatcher, prices, permits) and the month.
## Part 3: chains of legs (lpRunLeg of 08q-planner.js): every leg is a trip of its own, the next one starts
## where the last one unloads; a leg without own vehicles goes to a partner carrier.
## Incidents (08f-incidents.js) are in sim_incidents.gd (SimIncidents extends this class) and plug in through
## _inc_frame() and _jobs_day(); the route planner's calculations are in sim.gd (Sim extends SimIncidents).
## Not ported yet: multi-drop flights and consolidated trips, the postal service.

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
var me := -1                    # G.me: the state of the headquarters
var sky := {}                   # SKY: states with a closed sky
var blk := false                # BLK: routes are blocked (closed borders, weather)
var over := false               # G.over: bankrupt
var neighbors: Array = []       # G.C[i].geo.neighbors
var news: Array = []            # coNews: [tone, icon, text], newest last


## A new game on the world made by gen.generate(seed) (states, board and textures already built there).
func setup(gen_: Object, seed_: int, states_: Array, board_: Dictionary, world: Dictionary = {}) -> void:
	gen = gen_
	neighbors = []
	for c in world.get("countries", []):
		neighbors.append(c.neighbors)
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
var lp_ovr: Variant = null      # LP_OVR: a route the player drew, used for one key while planning


## LP_OVR / lpWith: plan with a given route for one leg
func lp_with(key: String, r: Variant, f: Callable) -> Variant:
	var s: Variant = lp_ovr
	lp_ovr = {"key": key, "r": r} if r != null else null
	var res: Variant = f.call()
	lp_ovr = s
	return res


func co_route(mode: String, a: int, b: int) -> Variant:
	if lp_ovr != null and lp_ovr.key == mode + str(a) + ":" + str(b):
		return lp_ovr.r
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
	me = PL[pid].cid
	CO.hubs = [{"pid": pid, "lvl": 1, "share": .05, "mk": 0}]
	CO.veh = [{"id": CO.uid, "t": "ltruck", "loc": pid, "st": "idle", "cond": 100.0, "km": 0.0}]
	CO.uid += 1
	var R2 := Mulberry.new((seed_value ^ 0x7f4a) & 0xFFFFFFFF)
	CO.comp = []
	var cn: Array = D.COMP_N
	for i in cn.size():
		var rev := JS.exp(JS.log(1.5e6) + (float(i) / (cn.size() - 1) * .8 + R2.next() * .2) * JS.log(60))
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
	return int(JS.round_js((1200 + skill * 380) * (1 + JS.log10(1 + rev / 150000) * .8) * (.6 + .4 * price_k(hq_p().cid)) / 10) * 10)


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
	return D.CH_RATE[m] * len_ * JS.pow(t, .85) + D.CH_BASE[m] * .15


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
		var w: float = JS.pow(firms_of(p.id).size(), 1.25) * (sqrt(p.pop) + .15) * D.HUB_ORD[lv] / (1 + (d / Dref) * (d / Dref)) * (3.0 if waitAt.has(p.id) else 1.0) / (1 + 1.5 * onB.get(str(p.id), 0)) * (1.0 if ownC.has(p.cid) else .3)
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
	var tons := lo * JS.pow(hi / lo, JS.pow(R.next(), 1.6))
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
		base += D.CH_BASE[L.m] * (1.0 if is_same(L, ml) else .25) + D.CH_RATE[L.m] * L.len * JS.pow(tons, .85)
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


# =====================================================================================================
# Part 2: trips, the day and the month
# =====================================================================================================

# ---------- hooks for the incidents (sim.gd) ----------
## coJobsDay: what goes wrong on each trip today, and trips that end on the day tick
func _jobs_day() -> void:
	pass


## incFrame: incidents, checkpoints, weather and traffic, every frame
func _inc_frame(_T: float) -> void:
	pass


# ---------- decisions (coModal): the player chooses; tests and the headless run take a fixed choice ----------
## >= 0: every decision is taken at once with this choice (tests, headless). -1: decisions wait in `modals`
## for the interface, which calls the chosen choice's "f".
var auto_choice := 0
var modals: Array = []


func co_modal_ok() -> bool:
	return day >= CO.get("mcd", 0)


## spec: {title, body, choices: [{t, d, f: Callable}]}
func co_modal(spec: Dictionary) -> void:
	CO.mcd = day + rint(9, 18)
	if auto_choice >= 0:
		spec.choices[mini(auto_choice, spec.choices.size() - 1)].f.call()
	else:
		modals.append(spec)


# ---------- small helpers (08e-company.js, 08g-business.js) ----------
func co_now() -> float:
	return day + CO.get("lastFr", 0.0)


func dfk() -> float:
	return [.6, 1.0, 1.45][diff]


func co_news(tone: String, icon: String, text: String) -> void:
	news.append([tone, icon, text])
	if news.size() > 200:
		news.pop_front()


## Array.filter(x => x !== o) for one object: dictionaries compare by value in GDScript, so by identity here.
static func _drop(a: Array, o: Variant) -> void:
	for i in a.size():
		if is_same(a[i], o):
			a.remove_at(i)
			return


func hub_veh_n(pid: int) -> int:
	var n := 0
	for v in CO.veh:
		if v.loc == pid and v.st != "trip":
			n += 1
	return n


func hub_veh_cap(h: Dictionary) -> int:
	return D.HUB_VEH[h.lvl]


func hand_f(pid: int) -> float:
	var h: Variant = hub_at(pid)
	return D.HUB_HAND[h.lvl if h != null else 0]


func hub_cost(p: Dictionary) -> float:
	return JS.round_js({"cap": 60000, "big": 35000, "city": 20000, "town": 8000, "vil": 4000}.get(p.type, 8000) * price_k(p.cid))


func hub_rent_m(h: Dictionary) -> float:
	var p: Dictionary = PL[h.pid]
	return D.HUB_RENT[h.lvl] * price_k(p.cid) * (2.5 if h.get("rent") else 1.0) + (hub_cost(p) * .05 if h.get("rent") else 0.0)


func co_rev(m: Variant) -> float:
	return m.local + m.contract + m.tender if m != null else 0.0


func co_cost(m: Variant) -> float:
	if m == null:
		return 0.0
	return m.get("office", 0) + m.wage + m.mgmt + m.fuel + m.upkeep + m.rent + m.ins + m.interest + m.claims + m.other + m.mk + m.get("hubtax", 0)


func co_value() -> float:
	var v: float = CO.cash
	for x in CO.veh:
		v += D.VT[x.t].cost * (.35 + .4 * x.cond / 100)
	for h in CO.hubs:
		v += hub_cost(PL[h.pid]) * h.lvl * .8
	for l in CO.loans:
		v -= l.left
	return v


func co_credit() -> float:
	return maxf(15000, JS.round_js(co_value() * .45 + co_rev(CO.lm) * 2))


func co_year_rev() -> float:
	var h: Array = CO.hist.rev.slice(-12)
	var s := 0.0
	for x in h:
		s += x
	return s / maxf(1, h.size()) * 12 if h.size() < 12 else s


func co_rank() -> int:
	var my := co_year_rev()
	var n := 1
	for c in CO.comp:
		if c.rev > my:
			n += 1
	return n


func co_crew_free() -> Dictionary:
	var f := {}
	for r in D.ROLE:
		f[r] = CO.staff.get(r, 0) + (CO.founder if r == "driver" else 0)
	for v in CO.veh:
		if v.st == "trip" or v.st == "tender":
			var T: Dictionary = D.VT[v.t]
			f[T.role] -= T.get("crew", 1)
	return f


func has_u(id: String) -> bool:
	return CO.has("upg") and CO.upg.has(id)


func fuel_k(mode: String) -> float:
	var k := 1.0
	for u in D.UPG:
		if has_u(u.id) and u.has("fx") and u.fx.get(mode, 0):
			k *= 1 - u.fx[mode]
	return k


func rep_k() -> float:
	var k: float = CO.get("parts", 1) if CO.get("parts", 0) else 1.0
	for u in D.UPG:
		if has_u(u.id) and u.get("rep", 0):
			k *= 1 - u.rep
	return k


func rev_key(k: Dictionary) -> String:
	return "local" if PL[k.from].cid == PL[k.to].cid else "contract"


# ---------- node specialisation (nodeSpec, specWhy of 08g) ----------
func node_spec(p: Dictionary) -> Dictionary:
	if nspec.has(p.id):
		return nspec[p.id]
	var sd := seed_value if seed_value else 1
	var h: int = (((p.id + 1) * 2654435761) & 0xFFFFFFFF) ^ ((sd * 40503) & 0xFFFFFFFF)
	var a := h % 100
	var b := (h >> 8) % 100
	var c := (h >> 16) % 100
	var port: bool = p.port != null
	var s := {"reefer": port and (p.type == "cap" or p.type == "big" or (p.type == "city" and a < 60) or (p.type == "town" and a < 25)),
		"deep": port and (p.type == "cap" or (p.type == "big" and b < 70) or (p.type == "city" and b < 30)),
		"heavy": p.air == true and (p.type == "cap" or (p.type == "big" and c < 65) or (p.type == "city" and c < 20))}
	nspec[p.id] = s
	return s


func spec_why(k: Dictionary, t: Variant) -> Variant:
	var A: Dictionary = PL[k.from]
	var B: Dictionary = PL[k.to]
	var cg: Variant = cargo_i.get(k.cg)
	if k.mode == "sea" and cg != null and cg.get("reefer"):
		for p in [A, B]:
			if not node_spec(p).reefer:
				return "Порт %s не приймає рефрижераторні контейнери" % p.name
	if t == "bulk":
		for p in [A, B]:
			if not node_spec(p).deep:
				return "Порт %s мілководний: балкер не зайде" % p.name
	if t == "jumbo" or t == "mega":
		for p in [A, B]:
			if not node_spec(p).heavy:
				return "Аеропорт %s: коротка смуга для важкого літака" % p.name
	return null


## incPortCl (08f): why a port or an airport is closed now, or null
func inc_port_cl(p: Dictionary, mode: String) -> Variant:
	if CO.get("cls") == null:
		return null
	if mode == "air" and sky.has(p.cid):
		return "Закрите небо: воєнний стан"
	for c in CO.cls:
		if c.kind == "cty" and c.a == p.cid:
			return c.why
	for w in CO.get("wx", []):
		var K: Dictionary = D.WXK[w.k]
		if w.t0 > co_now():
			continue
		if (K.get("sea") if mode == "sea" else K.get("air")) and JS.hypot(p.x - w.x, p.z - w.z) < w.r:
			return w.n
	return null


# ---------- positions along a trip (coCum, coPosAt, retPos, retLead, vCid) ----------
func co_cum(j: Dictionary) -> PackedFloat32Array:
	var n: int = j.p.size() / 2
	if j.has("_c") and j._c.size() == n:
		return j._c
	var c := PackedFloat32Array()
	c.resize(n)
	for i in range(1, n):
		c[i] = c[i - 1] + JS.hypot(j.p[i * 2] - j.p[i * 2 - 2], j.p[i * 2 + 1] - j.p[i * 2 - 1])
	j._c = c
	return c


func co_pos_at(j: Dictionary, s: float) -> Array:
	s /= CO_DU
	var c := co_cum(j)
	var n := c.size()
	var p: PackedFloat32Array = j.p
	if s <= 0:
		return [p[0], p[1], 0]
	if s >= c[n - 1]:
		return [p[n * 2 - 2], p[n * 2 - 1], 0]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var m := (lo + hi) >> 1
		if c[m] <= s:
			lo = m
		else:
			hi = m
	var d: float = c[hi] - c[lo]
	var t: float = (s - c[lo]) / (d if d else 1.0)
	return [p[lo * 2] + (p[hi * 2] - p[lo * 2]) * t, p[lo * 2 + 1] + (p[hi * 2 + 1] - p[lo * 2 + 1]) * t, lo]


func _ret_job(v: Dictionary) -> Variant:
	for x in CO.jobs:
		if x.get("ret") and x.vids.has(v.id):
			return x
	return null


func is_ret_v(v: Dictionary) -> bool:
	return v.st == "trip" and D.VT[v.t].mode == "road" and _ret_job(v) != null


func ret_pos(v: Dictionary) -> Variant:
	var j: Variant = _ret_job(v)
	if j == null:
		return null
	return co_pos_at(j, co_job_state(j, co_now() - j.t0).s)


func node_at(x: float, z: float) -> int:
	var i := int(JS.clamp_js(JS.round_js((x + board.wx / 2) / board.st), 0, board.nx - 1))
	var k := int(JS.clamp_js(JS.round_js((z + board.wz / 2) / board.st), 0, board.nz - 1))
	return k * board.nx + i


func ret_lead(v: Dictionary, dest: int) -> Variant:
	var q: Variant = ret_pos(v)
	if q == null:
		return null
	var p: PackedFloat32Array = gen.node_path(node_at(q[0], q[1]), PL[dest].node, false)
	if p.is_empty():
		return null
	var a: Array = [q[0], q[1]]
	a.append_array(Array(p))
	var L := 0.0
	for i in range(2, a.size(), 2):
		L += JS.hypot(a[i] - a[i - 2], a[i + 1] - a[i - 1])
	return {"p": PackedFloat32Array(a), "len": L * CO_DU}


func v_cid(v: Dictionary) -> int:
	if v.st == "trip":
		var q: Variant = ret_pos(v)
		if q != null:
			var o: int = gen.state_at(q[0], q[1])
			if o >= 0:
				return o
	return PL[v.loc].cid if v.loc != null and v.loc >= 0 and v.loc < PL.size() else -1


# ---------- planning one leg (coPlan1) ----------
func cp_wait(cid: int, mode: String) -> float:
	return ((.25 if mode == "rail" else .35) + bur(cid) / 110) * (1 - .6 * msk("clo")) * .45


func co_plan1(k: Dictionary) -> Dictionary:
	var mode: String = k.mode
	var A: Dictionary = PL[k.from]
	if k.get("minR", 0) and CO.rating < k.minR:
		return {"ok": false, "why": "Замовник хоче рейтинг %.1f+" % k.minR}
	if CO.strike > day:
		return {"ok": false, "why": "Страйк: водії не виходять на рейси"}
	var nd := perm_need(cargo_i.get(k.cg), mode).filter(func(x): return not perm_ok(x))
	if nd.size():
		return {"ok": false, "why": "Потрібна ліцензія «%s»" % perm_i[nd[0]].n, "perm": nd[0]}
	var w0: Variant = spec_why(k, null)
	if w0 != null:
		return {"ok": false, "why": w0}
	if mode == "sea" or mode == "air":
		for pid in [k.from, k.to]:
			var w: Variant = inc_port_cl(PL[pid], mode)
			if w != null:
				return {"ok": false, "why": "%s %s закрито: %s" % ["Порт" if mode == "sea" else "Аеропорт", PL[pid].name, w.to_lower()]}
	var main: Variant = co_route(mode, k.from, k.to)
	if main == null:
		return {"ok": false, "why": "Маршрут перекрито: закритий кордон або негода" if blk else "Маршрут недоступний"}
	var free := co_crew_free()
	var best: Variant = null
	var why: String = "Немає вільної техніки: " + D.MODE_N[mode].to_lower()
	var ex: Dictionary = k.get("_ex", {})
	for t in D.VT:
		var T: Dictionary = D.VT[t]
		if T.mode != mode:
			continue
		var sw: Variant = spec_why(k, t)
		if sw != null:
			why = sw
			continue
		var idle := []
		for v in CO.veh:
			if v.t != t:
				continue
			var ok_st: bool = (v.st == "idle" and (hub_at(v.loc) != null or (v.get("idle0") != null and co_now() - v.idle0 < 1))) or is_ret_v(v)
			if not ok_st:
				continue
			if k.get("_ctry") != null and v_cid(v) != k._ctry:
				continue
			if ex.has(v.id):
				continue
			if k.get("_veh") != null and v.id != k._veh:
				continue
			if v.get("resv") and v.id != k.get("_veh"):
				continue
			idle.append(v)
		if idle.is_empty():
			continue
		var crew: int = T.get("crew", 1)
		var vol_n := 1
		if T.get("vol", 0):
			var cv: Variant = cargo_i.get(k.cg)
			var vol: float = k._vol if k.get("_vol") != null else k.tons * (cv.v if cv != null and cv.get("v", 0) else 3)
			vol_n = int(ceil(vol / T.vol))
		var n := maxi(int(ceil(k.tons / T.cap)), vol_n)
		if k.get("_one") and n > 1:
			why = "Не вміщує: %s бере %s т і %s м³" % [T.n.to_lower(), T.cap, T.vol]
			continue
		if n > 14:
			why = "Замало місткості: потрібно %d × %s" % [n, T.n.to_lower()]
			continue
		if idle.size() < n:
			why = "Потрібно %d × %s, вільних %d" % [n, T.n.to_lower(), idle.size()]
			continue
		var ret_n := 0
		for v in idle:
			if is_ret_v(v):
				ret_n += 1
		if free[T.role] + mini(n, ret_n) * crew < crew * n:
			why = "Бракує персоналу: " + D.ROLE[T.role].n.to_lower()
			continue
		_stable_sort(idle, func(a, b): return JS.hypot(PL[a.loc].x - A.x, PL[a.loc].z - A.z) - JS.hypot(PL[b.loc].x - A.x, PL[b.loc].z - A.z))
		var sel := []
		var lead := 0.0
		var lead_r: Variant = null
		for v in idle:
			var r: Variant = ret_lead(v, k.from) if v.st == "trip" else co_route(mode, v.loc, k.from)
			if r == null:
				continue
			sel.append(v)
			if lead_r == null or r.len >= lead:
				lead = r.len
				lead_r = r
			if sel.size() == n:
				break
		if sel.size() < n:
			why = "Техніку відрізано: закритий кордон або негода" if blk else "Техніка на іншому материку"
			continue
		var border: bool = PL[k.from].cid != PL[k.to].cid
		var cust := 0.0
		if border:
			if mode == "road" or mode == "rail":
				cust = cp_wait(PL[k.to].cid, mode) * maxf(1, JS.round_js(JS.hypot(PL[k.to].x - A.x, PL[k.to].z - A.z) / 5))
			else:
				cust = .3
		var tl: float = lead / (T.spd * spd_k())
		var tm: float = main.len / (T.spd * spd_k())
		var hs: float = D.HAND[mode] * hand_k() * (hand_f(k.from) + hand_f(k.to)) / 2
		var tot: float = tl + hs + tm + cust + hs
		var fuel: float = (lead + main.len) * T.fuel * CO.fuel * fuel_k(mode) * n * (1 - .06 * msk("cto")) * 1
		var runc: float = (T.up * rep_k() * [.8, 1.0, 1.35][CO.maint] + D.ROLE[T.role].w * wage_k(me) * CO.wageLv / 30 * crew) * tot * n
		var pk_ := 1.2 if T.has("fit") and T.fit.has(k.cg) else 1.0
		var c := {"ok": true, "t": t, "n": n, "vids": sel.map(func(v): return v.id), "lead": lead, "leadR": lead_r, "main": main, "tl": tl, "tm": tm,
			"hs": hs, "cust": cust, "tot": tot, "fuel": fuel, "payK": pk_, "profit": k.pay * pk_ - fuel - runc, "late": tot > k.dlDays}
		if best == null or (not c.late and best.late) or (c.late == best.late and c.profit > best.profit):
			best = c
	return best if best != null else {"ok": false, "why": why}


# ---------- planning an order (coPlan: chains of legs, the multi-drop wrapper of 08r) ----------
func hub_tax(k: Variant, pid: int, m: String) -> float:
	if hub_at(pid) != null:
		return 0.0
	return JS.round_js((k.pay if k != null else 0.0) * .04 + {"road": 120, "rail": 450, "sea": 1500, "air": 1100}[m] * price_k(PL[pid].cid))


func hub_tax_pay(ht: Array) -> float:
	var x := 0.0
	for h in ht:
		x += h.f
	if x:
		CO.cash -= x
		CO.m.hubtax = CO.m.get("hubtax", 0) + x
	return x


func co_plan(k: Dictionary) -> Dictionary:
	if k.get("multi"):
		return {"ok": false, "why": "Збірний рейс: порядок посадок прокладається вручну"}
	var legs: Array = k.get("legs", []) if k.get("legs") != null else []
	if legs.size() < 2:
		return co_plan1(k)
	if k.get("minR", 0) and CO.rating < k.minR:
		return {"ok": false, "why": "Замовник хоче рейтинг %.1f+" % k.minR}
	var ex := {}
	var sub := []
	var ht := []
	var tot := 0.0
	var fuel := 0.0
	var cost := 0.0
	var pay_k := 1.0
	for i in legs.size():
		var L: Dictionary = legs[i]
		var kk := k.duplicate()
		var r: Variant = co_route(L.m, L.a, L.b)
		kk.legs = null
		kk.from = L.a
		kk.to = L.b
		kk.mode = L.m
		kk.minR = 0
		kk.pay = 0
		kk._ex = ex
		kk.len = r.len if r != null and r.len else k.len
		var P := co_plan1(kk)
		if not P.ok:
			return {"ok": false, "why": "Ділянка %d (%s %s → %s): %s" % [i + 1, D.MODE_N[L.m].to_lower(), PL[L.a].name, PL[L.b].name, P.why]}
		for id in P.vids:
			ex[id] = true
		sub.append(P)
		tot += P.tot
		fuel += P.fuel
		cost += -P.profit + ((250 + k.tons * 1.5) * price_k(PL[L.a].cid) if i else 0.0)
		if i and legs[i - 1].m != L.m:
			var x := hub_tax(k, L.a, L.m)
			if x:
				cost += x
				ht.append({"pid": L.a, "f": x})
		if L.m == k.mode:
			pay_k = P.payK if P.payK else 1.0
	var mi := -1
	for i in legs.size():
		if legs[i].m == k.mode:
			mi = i
			break
	var M: Dictionary = sub[mi] if mi >= 0 else sub[0]
	return {"ok": true, "chain": sub, "ht": ht, "t": M.t, "n": M.n, "lead": sub[0].lead, "tot": tot, "fuel": fuel, "payK": pay_k,
		"profit": k.pay * pay_k - cost, "late": tot > k.dlDays}


# ---------- dispatch (coDispatch) ----------
func co_dispatch(k: Dictionary, P: Dictionary, _silent: bool = false) -> bool:
	if not P.get("ok"):
		return false
	if P.has("chain"):
		_drop(CO.board, k)
		hub_tax_pay(P.ht)
		var plan := {"legs": k.legs.map(func(L): return {"a": L.a, "b": L.b, "m": L.m, "r": null})}
		lp_run_leg(k, plan, 0, day + k.dlDays)
		return true
	CO.cash -= P.fuel
	CO.m.fuel += P.fuel
	var lp: PackedFloat32Array = P.leadR.p
	var mp: PackedFloat32Array = P.main.p
	var path := PackedFloat32Array(lp)
	path.append_array(mp.slice(2))
	var j := {"id": k.id, "k": k, "mode": k.mode, "t": P.t, "n": P.n, "vids": P.vids, "payK": P.payK if P.get("payK") else 1.0, "p": path, "lead": P.lead,
		"len": P.main.len, "tl": P.tl, "tm": P.tm, "hs": P.hs, "cust": P.cust, "tot": P.tot, "t0": co_now(), "dl": day + k.dlDays, "dmg": 0.0,
		"lost": false, "hold": 0.0, "ev": []}
	if k.mode == "road" or k.mode == "rail":
		var tot: float = j.lead + j.len
		var wl := 0.0
		for i in range(2, path.size(), 2):
			wl += JS.hypot(path[i] - path[i - 2], path[i + 1] - path[i - 1])
		var eco: float = tot / wl if wl > 0 else CO_DU
		var stops := []
		for c in gen.crossings(path, eco):
			stops.append({"s": c.s, "a": c.a, "b": c.b, "x": c.x, "z": c.z, "w": cp_wait(c.b, k.mode)})
		j.stops = stops
		if stops.size():
			var W := 0.0
			for q in stops:
				W += q.w
			j.tot = j.tl + j.hs + j.tm + j.hs + W
			j.cust = 0.0
	for v in CO.veh:
		if P.vids.has(v.id) and v.st == "trip":
			var rj: Variant = _ret_job(v)
			if rj != null:
				_drop(CO.jobs, rj)   # a truck on its way home turns to the new order
	for v in CO.veh:
		if P.vids.has(v.id):
			v.st = "trip"
			v.job = j.id
			v.idle0 = null
	CO.jobs.append(j)
	_drop(CO.board, k)
	if k.mode == "sea" and PL[k.from].land != PL[k.to].land:
		CO.flags.ocean = 1
	return true


# ---------- chains: legs run one after another (lpRunLeg, lpFee, lpUnlocked) ----------
func lp_unlocked(m: String) -> bool:
	for t in D.VT:
		if D.VT[t].mode == m and D.VT[t].tier <= CO.tier:
			return true
	return false


## a partner carrier's price: market rate for a hand-made multi-drop leg, a share of the order otherwise
func lp_fee(k: Dictionary, r: Dictionary, m: String, tons: float, cid: int) -> float:
	if k.get("multi"):
		return JS.round_js(({"road": 600, "rail": 5000, "sea": 20000, "air": 15000}[m] * .25 + {"road": 150, "rail": 22, "sea": 9, "air": 260}[m] * r.len * JS.pow(tons, .85)) * cargo_i[k.cg].k * price_k(cid) * .5)
	var kl: float = k.len if k.get("len") else r.len
	return JS.round_js(k.pay * .55 * minf(1.4, r.len / maxf(.05, kl)) + {"road": 150, "rail": 900, "sea": 4000, "air": 3000}[m] * price_k(cid))


## plan: {legs: [{a, b, m, r (a drawn route or null), tons?, pay?, dl?}], veh0?, ctry?}
func lp_run_leg(k: Dictionary, plan: Dictionary, i: int, dl: float) -> void:
	var L: Dictionary = plan.legs[i]
	var kk := k.duplicate()
	kk.multi = null
	kk.legs = null
	kk.cons = null
	if i == 0 and plan.get("veh0") != null:
		kk._veh = plan.veh0
	kk.from = L.a
	kk.to = L.b
	kk.mode = L.m
	kk.minR = 0
	kk.id = k.id
	kk.tons = L.tons if L.get("tons") else k.tons
	kk.pay = L.pay if L.get("pay") != null else k.pay
	var P: Variant = null
	if lp_unlocked(L.m):
		P = lp_with(L.m + str(L.a) + ":" + str(L.b), L.get("r"), func(): return co_plan(kk))
	if P == null or not P.ok:
		var r: Variant = L.get("r") if L.get("r") != null else co_route(L.m, L.a, L.b)
		if r == null:
			co_news("bad", "", "Ділянку не пройти: %s → %s" % [PL[L.a].name, PL[L.b].name])
			return
		var t := "truck"
		for x in D.VT:
			if D.VT[x].mode == L.m and not D.VT[x].get("loc", 0):
				t = x
				break
		var T: Dictionary = D.VT[t]
		var tm: float = r.len / (T.spd * spd_k())
		var hs: float = D.HAND[L.m] * hand_k()
		var fee := lp_fee(k, r, L.m, L.tons if L.get("tons") else k.tons, PL[L.a].cid)
		P = {"ok": true, "t": t, "n": 1, "vids": [], "lead": 0.0, "leadR": {"p": PackedFloat32Array([r.p[0], r.p[1]]), "len": 0.0}, "main": r, "tl": 0.0, "tm": tm,
			"hs": hs, "cust": 0.0, "tot": hs + tm + hs, "fuel": fee, "profit": 0.0, "late": false}
	if i > 0:
		var f := JS.round_js((250 + k.tons * 1.5) * price_k(PL[L.a].cid))
		CO.cash -= f
		CO.m.other += f
	co_dispatch(kk, P, true)
	for j in CO.jobs:
		if is_same(j.k, kk):
			j.lp = {"plan": plan, "i": i, "k0": k}
			j.dl = L.dl if L.get("dl") else dl
			if i > 0:
				j.cont = false
			return


# ---------- the dispatcher (coAuto) ----------
func co_auto() -> void:
	if not CO.auto or not CO.mgr.has("cto") or CO.strike > day:
		return
	var n := 0
	var lim := 4
	var sk := msk("cto")
	var L: Array = CO.board.duplicate()
	_stable_sort(L, func(a, b): return b.pay - a.pay)
	for k in L:
		if n >= lim:
			break
		var P := co_plan(k)
		var guess: float = P.get("profit", NAN) * (1 + (R.next() - .5) * (1 - sk) * .9)   # a weak dispatcher misjudges orders
		if P.ok and (not P.late and guess > k.pay * .15):
			var extra := JS.round_js(P.fuel * (1 - sk) * .45)   # and plans longer, costlier routes
			CO.cash -= extra
			CO.m.fuel += extra
			k.how = "mgr"
			co_dispatch(k, P, true)
			n += 1
	if n:
		co_news("", "cpu", "Диспетчерська %s відправила %d %s" % [CO.name, n, "рейс" if n == 1 else "рейси"])


# ---------- trip state (driveAt, segW, coJobState, coJobState0) ----------
func drive_at(j: Dictionary, e: float, s0: float, s1: float, T: float) -> Dictionary:
	var st := []
	for q in j.get("stops", []):
		if q.s >= s0 and q.s < s1:
			st.append(q)
	if st.is_empty():
		return {"s": s0 + (e / T if T > 0 else 1.0) * (s1 - s0)}
	var v := (s1 - s0) / T if T > 0 else 1e9
	var pos := s0
	for q in st:
		var t: float = (q.s - pos) / v
		if e < t:
			return {"s": pos + e * v}
		e -= t
		pos = q.s
		if e < q.w:
			return {"s": pos, "wait": q}
		e -= q.w
	return {"s": minf(s1, pos + e * v)}


func seg_w(j: Dictionary, s0: float, s1: float) -> float:
	var a := 0.0
	for q in j.get("stops", []):
		if q.s >= s0 and q.s < s1:
			a += q.w
	return a


func co_job_state(j: Dictionary, e: float) -> Dictionary:
	var inc: Variant = null
	if j.get("pz"):
		var sub := 0.0
		for p in j.pz:
			if e >= p.e + p.w:
				sub += p.w
			elif e >= p.e:
				inc = p
				sub += e - p.e
				break
			else:
				break
		e -= sub
	var drg: Variant = null
	if j.get("drag"):
		for d in j.drag:
			if e > d.e0:
				if e < d.e1:
					drg = d
				e -= (minf(e, d.e1) - d.e0) * (1 - d.f)
	var st := co_job_state0(j, e)
	if inc != null:
		st.ph = inc.ph
		st.inc = inc
	elif drg != null and st.seg >= 0:
		st.ph = drg.ph
	elif j.get("gps") and co_now() < j.gps.until:
		st.ph = "Втрачено сигнал GPS: остання відома позиція"
	elif j.get("back") and st.seg >= 0:
		st.ph = "Везе вантаж назад відправнику"
	return st


func _cp_ph(q: Dictionary) -> String:
	return "Пропускний пункт %s → %s: очікування" % [states[q.a].name, states[q.b].name]


func co_job_state0(j: Dictionary, e: float) -> Dictionary:
	var h0: float = 0.0 if j.get("cont") else j.hs
	if j.get("stops") and not j.get("ret"):
		var tl: float = j.tl + seg_w(j, 0, j.lead)
		var tm: float = j.tm + seg_w(j, j.lead, j.lead + j.len + 1e-9)
		if e < tl:
			var d := drive_at(j, e, 0, j.lead, j.tl)
			var wt: Variant = d.get("wait")
			return {"s": d.s, "w": wt, "seg": -1 if wt != null else 0, "f": d.s / j.lead if j.lead > 0 else 1.0,
				"ph": _cp_ph(wt) if wt != null else "Порожній перегін до відвантаження"}
		e -= tl
		if e < h0:
			return {"s": j.lead, "seg": -1, "ph": "Завантаження"}
		e -= h0
		if e < tm:
			var d := drive_at(j, e, j.lead, j.lead + j.len + 1e-9, j.tm)
			var wt: Variant = d.get("wait")
			return {"s": d.s, "w": wt, "seg": -1 if wt != null else 1, "f": (d.s - j.lead) / (j.len if j.len else 1.0),
				"ph": _cp_ph(wt) if wt != null else ("Захоплено" if j.hold > 0 else "У дорозі з вантажем")}
		return {"s": j.lead + j.len, "seg": -1, "ph": "Розвантаження"}
	if j.get("ret"):
		var f := JS.clamp_js(e / j.tm, 0, 1)
		return {"s": f * j.len, "seg": 1, "f": f, "ph": "Повертається в хаб без вантажу"}
	if e < j.tl:
		return {"s": e / j.tl * j.lead if j.tl > 0 else 0.0, "seg": 0, "f": e / j.tl if j.tl > 0 else 1.0, "ph": "Порожній перегін до відвантаження"}
	e -= j.tl
	if e < h0:
		return {"s": j.lead, "seg": -1, "ph": "Завантаження"}
	e -= h0
	if e < j.tm:
		return {"s": j.lead + e / j.tm * j.len, "seg": 1, "f": e / j.tm, "ph": "Захоплено" if j.hold > 0 else "У дорозі з вантажем"}
	e -= j.tm
	if e < j.cust:
		return {"s": j.lead + j.len, "seg": -1, "ph": "Митне оформлення"}
	return {"s": j.lead + j.len, "seg": -1, "ph": "Розвантаження"}


# ---------- delivery (coComplete, coXP) ----------
func co_xp(j: Dictionary, k: Dictionary, late: float) -> int:
	var nl: int = j.lp.plan.legs.size() if j.get("lp") else 1
	var mgr: bool = k.get("how") == "mgr"
	var x := (10 + 6 * (nl - 1) + 4 * JS.log2(1 + k.pay / 2000)) * (.5 if late > 0 else 1.0) * (.6 if j.dmg > .05 else 1.0)
	if mgr:
		x *= .08
	return int(maxf(0 if mgr else 1, JS.round_js(x)))


func _last(e: Dictionary) -> void:
	CO.last.push_front(e)
	if CO.last.size() > 30:
		CO.last.pop_back()


func co_complete(j: Dictionary) -> void:
	if j.get("cons") or (j.get("lp") and j.lp.plan.get("cons")):
		push_error("Sim: consolidated trips are not ported yet")
	# a leg of a chain: the cargo is handed over and the next leg starts (the wrapper of 08q-planner.js)
	if j.get("lp") and j.lp.i < j.lp.plan.legs.size() - 1 and not j.get("back") and not j.get("cx0"):
		_drop(CO.jobs, j)
		var L: Dictionary = j.lp.plan.legs[j.lp.i]
		if (L.get("drop") or L.get("drops")) and not L.get("paid"):
			push_error("Sim: multi-drop legs are not ported yet")
		for v in CO.veh:
			if j.vids.has(v.id):
				v.st = "idle"
				v.job = null
				v.loc = L.b
				v.idle0 = null if hub_at(L.b) != null else co_now()
		co_news("", "", "Перевантаження в %s: «%s» їде далі" % [PL[L.b].name, cargo_i[j.k.cg].n.to_lower()])
		var d: float = j.dmg
		var lost: bool = j.lost
		var ev: Array = j.ev
		lp_run_leg(j.lp.k0, j.lp.plan, j.lp.i + 1, j.dl)
		for n in CO.jobs:
			if n.get("lp") and is_same(n.lp.k0, j.lp.k0):
				n.dmg = d
				n.lost = lost
				n.ev = ev + n.ev
				break
		return
	if j.get("ret"):
		_drop(CO.jobs, j)
		for v in CO.veh:
			if j.vids.has(v.id):
				v.st = "idle"
				v.job = null
				v.loc = j.k.to
				v.km += j.len * D.KM
				v.idle0 = null
		return
	if j.get("back") or j.get("cx0"):
		_drop(CO.jobs, j)
		var at: int = j.k.from
		for v in CO.veh:
			if j.vids.has(v.id):
				v.st = "idle"
				v.job = null
				v.loc = at
				v.idle0 = null if hub_at(at) != null else co_now()
				v.km += j.get("len", 0) * D.KM
		if j.get("back"):
			co_news("warn", "", "%s: вантаж «%s» повернено відправнику в %s" % [CO.name, cargo_i[j.k.cg].n.to_lower(), PL[at].name])
			_last({"d": date.duplicate(), "from": j.k.from, "to": j.k.to, "cg": j.k.cg, "pay": j.get("comp", 0), "tone": "warn", "mode": j.mode})
		return
	_drop(CO.jobs, j)
	var k: Dictionary = j.k
	var cg: Dictionary = cargo_i[k.cg]
	var late := maxf(0, day - j.dl)
	var pay: float = k.pay * (j.payK if j.get("payK") else 1.0)
	if late > 0:
		pay *= maxf(.35, 1 - late * .12)
	var value: float = k.tons * cg.val
	var claim := 0.0
	if j.lost:
		pay = 0
		claim = value * .6
	elif j.dmg > 0:
		claim = minf(value * minf(1, j.dmg) * .8, k.pay * 3 + 1500)
		pay *= 1 - minf(.8, j.dmg)
		if j.dmg > .08:
			CO.rating = JS.clamp_js(CO.rating - minf(.3, j.dmg * .6), 1, 5)
	var covered := claim * .8 if CO.ins else 0.0
	CO.cash += pay - claim + covered
	CO.m[rev_key(k)] += pay
	CO.m.claims += claim - covered
	var s := 1.0 if j.lost else (1.6 if j.dmg > .3 else (2.0 if late > 2 else (3.2 if late > 0 else (3.8 if j.dmg > 0 else 5.0))))
	var w := minf(.05, .01 + JS.log10(1 + k.pay) * .005)
	CO.rating = JS.clamp_js(CO.rating + (s - CO.rating) * w, 1, 5)
	var wear: float = {"road": 1.6, "rail": .5, "sea": .25, "air": .12}[j.mode] * [1.4, 1.0, .65][CO.maint]
	for v in CO.veh:
		if j.vids.has(v.id):
			v.st = "idle"
			v.job = null
			v.loc = k.to
			v.idle0 = null if hub_at(k.to) != null else co_now()
			v.km += (j.lead + j.len) * D.KM
			v.cond = maxf(0, v.cond - (j.lead + j.len) * wear)
	if not j.lost:
		CO.cdel += 1
		CO.deliv += 1
		CO.tons += k.tons
		var xp := co_xp(j, k, late)
		CO.xp = CO.get("xp", 0) + xp
		j.xp = xp
	var tone := "bad" if j.lost else ("warn" if late > 0 or j.dmg > .05 else "good")
	co_news(tone, "", "%s: %s доставлено в %s" % [CO.name, cg.n.to_lower(), PL[k.to].name])
	_last({"d": date.duplicate(), "from": k.from, "to": k.to, "cg": k.cg, "pay": pay - claim + covered, "tone": tone, "mode": j.mode})


# ---------- returns to a hub (coReturns + the home-hub wrapper of 08w) ----------
func _ret_trip(v: Dictionary, to: int, r: Dictionary) -> void:
	var T: Dictionary = D.VT[v.t]
	var fuel: float = r.len * T.fuel * CO.fuel * fuel_k(T.mode)
	CO.cash -= fuel
	CO.m.fuel += fuel
	var tm: float = r.len / (T.spd * spd_k())
	var j := {"id": CO.uid, "ret": true, "k": {"id": 0, "from": v.loc, "to": to, "cg": "parcel", "tons": 0, "pay": 0, "dlDays": 1e3, "mode": T.mode, "risk": 0},
		"mode": T.mode, "t": v.t, "n": 1, "vids": [v.id], "p": r.p, "lead": 0.0, "len": r.len, "tl": 0.0, "tm": tm, "hs": 0.0, "cust": 0.0, "tot": tm,
		"t0": co_now(), "dl": day + 1e3, "dmg": 0.0, "lost": false, "hold": 0.0, "ev": []}
	CO.uid += 1
	v.st = "trip"
	v.job = j.id
	v.idle0 = null
	CO.jobs.append(j)


func co_returns() -> void:
	# a vehicle with a home hub goes there, not to the nearest one
	for v in CO.veh:
		if v.get("home") == null or v.st != "idle" or v.loc == v.home or hub_at(v.loc) != null:
			continue
		var h: Variant = hub_at(v.home)
		if h == null:
			v.home = null
			continue
		if v.get("idle0") == null or co_now() - v.idle0 < 1:
			continue
		var r: Variant = co_route(D.VT[v.t].mode, v.loc, v.home)
		if r == null or hub_veh_n(v.home) >= hub_veh_cap(h):
			continue
		_ret_trip(v, v.home, r)
	for v in CO.veh:
		var T: Dictionary = D.VT[v.t]
		if v.st != "idle" or T.mode == "local":
			v.idle0 = null
			continue
		if hub_at(v.loc) != null:
			v.idle0 = null
			continue
		if v.get("idle0") == null:
			v.idle0 = co_now()
			continue
		if co_now() - v.idle0 < 1:
			continue   # a day in the unloading city waiting for a new order
		var best: Variant = null
		var bl := 1e9
		for h in CO.hubs:
			if not mode_ok(T.mode, PL[h.pid]) or hub_veh_n(h.pid) >= hub_veh_cap(h):
				continue
			var r: Variant = co_route(T.mode, v.loc, h.pid)
			if r != null and r.len < bl:
				bl = r.len
				best = {"h": h, "r": r}
		if best == null:
			v.idle0 = co_now() + 30
			continue
		_ret_trip(v, best.h.pid, best.r)


# ---------- per frame: trips finish mid-day (coFrame) ----------
## fr: the fraction of the current day that has passed (0…1)
func co_frame(fr: float) -> void:
	CO.lastFr = fr
	var T := day + fr
	_inc_frame(T)
	var done := 0
	for j in CO.jobs.duplicate():
		if j.hold <= 0 and T - j.t0 >= j.tot:
			co_complete(j)
			done += 1
	if done:
		co_returns()


# ---------- the city: local deliveries, upkeep, rating, morale (coLocal) ----------
func co_local() -> void:
	var free := co_crew_free()
	var drv: float = free.driver
	var rev := 0.0
	var tot := 0.0
	var strike: bool = CO.strike > day
	for h in CO.hubs:
		var p: Dictionary = PL[h.pid]
		var c: Dictionary = states[p.cid]
		var mk := JS.log10(1 + h.get("mk", 0) / 400.0) * .05
		var target := JS.clamp_js(.035 + (CO.rating - 3) * .035 + h.lvl * .015 + msk("cco") * .03 + mk, .01, .5)
		h.share += (target - h.share) * .015
		var market: float = (p.pop * 1000 + 400) * (.45 + c.dev)
		var w: float = market * h.share
		var cap := 0.0
		var n := 0
		h.ids = []
		for v in CO.veh:
			if v.loc != p.id or v.st != "idle":
				continue
			var T: Dictionary = D.VT[v.t]
			if not T.get("loc", 0):
				continue
			var crew: int = T.get("crew", 1)
			if drv < crew:
				continue
			drv -= crew
			v.today = JS.round_js(T.loc * sqrt(R.next()) * (1.0 if v.cond > 35 else .6))
			cap += v.today
			n += 1
			h.ids.append(v.id)
		var cm: float = (.72 + CO.morale / 220) * (1 + msk("coo") * .08) * (.1 if strike else 1.0)
		cap *= cm
		var served := minf(w, cap)
		var fr_ := served / cap if cap > 0 else 0.0
		for id in h.ids:
			for v in CO.veh:
				if v.id == id:
					v.done = JS.round_js(v.today * cm * fr_)
					break
		h.want = w
		h.cap = cap
		h.served = served
		h.nloc = n
		var price := 4.2 * price_k(p.cid) * (1 + msk("cco") * .06)
		rev += served * price
		tot += served
		h.earn = h.get("earn", 0) + served * price
	CO.cash += rev
	CO.m.local += rev
	CO.deliv += tot
	CO.dayLocal = tot
	# wear & upkeep
	var up := 0.0
	for v in CO.veh:
		var T: Dictionary = D.VT[v.t]
		up += T.up * [.8, 1.0, 1.35][CO.maint]
		if T.get("loc", 0) and v.st == "idle":
			v.cond = maxf(0, v.cond - .035 * [1.5, 1.0, .6][CO.maint])
	CO.cash -= up
	CO.m.upkeep += up
	# service quality → rating
	if tot > 0:
		var avg_c := 100.0
		if CO.veh.size():
			avg_c = 0.0
			for v in CO.veh:
				avg_c += v.cond
			avg_c /= CO.veh.size()
		var s := JS.clamp_js(2.7 + 1.4 * CO.morale / 100 + msk("coo") * .6 + (avg_c - 80) / 80 + (-1.5 if strike else 0.0), 1, 5)
		var w := minf(.012, tot * .00015)
		CO.rating = JS.clamp_js(CO.rating + (s - CO.rating) * w, 1, 5)
	# morale
	var over_n := 0
	for h in CO.hubs:
		if h.want > h.cap * 1.6:
			over_n += 1
	var mt := JS.clamp_js(52 + (CO.wageLv - 1) * 130 + msk("hro") * 16 - over_n * 3 - (12 if CO.cash < 0 else 0) + (6 if CO.founder else 0), 5, 98)
	CO.morale += (mt - CO.morale) * .04
	# local accidents
	for v in CO.veh:
		var T: Dictionary = D.VT[v.t]
		if not T.get("loc", 0) or v.loc == null or v.st != "idle":
			continue
		if chance(dfk() * .0009 * (1 - .45 * msk("coo")) * (1.35 - CO.morale / 100) * (1.2 - v.cond / 250)):
			var cost := JS.round_js(rnd(800, 4500) * price_k(PL[v.loc].cid))
			CO.cash -= cost
			CO.m.claims += cost
			v.cond = maxf(0, v.cond - rnd(15, 40))
			CO.rating = JS.clamp_js(CO.rating - .01, 1, 5)
			co_news("bad", "alert", "%s %s потрапив у ДТП у місті %s" % [T.n, CO.name, PL[v.loc].name])


# ---------- the order board (coBoardDay) ----------
func co_board_day() -> void:
	CO.board = CO.board.filter(func(k): return k.exp > day)
	var mx := co_board_max()
	var i := 0
	while i < maxi(3, int(ceil(mx / 5.0))) and CO.board.size() < mx:
		i += 1
		if not chance(.65):
			continue
		for a in 5:
			var k: Variant = co_gen()
			if k != null:
				CO.board.append(k)
				break


# ---------- world prices, permits (08g) ----------
func biz_prices() -> void:
	if not CO.get("parts", 0):
		CO.parts = 1.0
	var conf: int = CO.conf.size()
	var cls: Array = CO.get("cls", [])
	var sanc := 0
	var cty := 0
	for c in cls:
		var why: String = c.why.to_lower()
		if why.contains("санкц") or why.contains("торговельна"):
			sanc += 1
		if c.kind == "cty":
			cty += 1
	var hur := 0
	for w in CO.get("wx", []):
		if w.k == "hur":
			hur += 1
	var fT := 1 + .1 * conf + .04 * sanc + .03 * cty + .03 * hur
	var pT := 1 + .07 * conf + .08 * sanc + .03 * cty
	CO.fuel = JS.clamp_js(CO.fuel + (fT - CO.fuel) * .015 + CO.fuel * rnd(-.006, .006), .6, 2.2)
	CO.parts = JS.clamp_js(CO.parts + (pT - CO.parts) * .015 + CO.parts * rnd(-.004, .004), .7, 2)


func perm_fee(id: String) -> float:
	var p: Dictionary = perm_i[id]
	return JS.round_js(p.fee * (.55 + .45 * price_k(hq_p().cid)) * (1 + .05 * CO.conf.size()) / 100) * 100


func perm_day() -> void:
	if not CO.has("perm"):
		return
	for id in CO.perm:
		var P: Dictionary = CO.perm[id]
		var p: Dictionary = perm_i[id]
		var left := JS.round_js(P.until - day)
		if left == 30 and not P.get("warn"):
			P.warn = 1
			co_news("warn", "doc", "Через 30 днів спливає ліцензія «%s»" % p.n)
		if P.until <= day and not P.get("gone"):
			var f := perm_fee(id)
			if P.auto and CO.cash >= f:
				CO.cash -= f
				CO.m.other += f
				P.until += 365
				P.warn = 0
				co_news("good", "doc", "Ліцензію «%s» продовжено ще на рік" % p.n)
			else:
				P.gone = 1
				co_news("bad", "doc", "Ліцензія «%s» сплила: такі вантажі більше не можна брати" % p.n)
		if P.until > day:
			P.gone = 0


func biz_month() -> void:
	if has_u("shop"):
		var c: float = D.UPG.filter(func(u): return u.id == "shop")[0].mo
		CO.cash -= c
		CO.m.upkeep += c
	if chance(.07):
		var E := [["Дефіцит мікрочипів: запчастини й електроніка для техніки подорожчали", rnd(1.12, 1.3)], ["Нові мита на імпортні запчастини", rnd(1.08, 1.15)],
			["Обвал цін на сталь: запчастини подешевшали", rnd(.85, .93)]]
		var e: Array = pick(E)
		CO.parts = JS.clamp_js(CO.get("parts", 1) * e[1], .7, 2)
		co_news("bad" if e[1] > 1 else "good", "gear", e[0])


# ---------- the day (coDay) ----------
func co_day() -> void:
	if over:
		return
	day += 1
	date.d += 1
	var dim: int = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][date.m]
	var nm := false
	if date.d > dim:
		date.d = 1
		date.m += 1
		nm = true
		if date.m > 11:
			date.m = 0
			date.y += 1
	for k in D.RES.size():   # updateMarketDaily: world commodity prices (not shown in logistics), one R() each
		R.next()
	co_local()
	_jobs_day()
	co_board_day()
	co_auto()
	co_returns()
	biz_prices()
	perm_day()
	if nm:
		co_month()


# ---------- the month (coMonth + bizMonth) ----------
const CO_MS := [["d100", "Перша сотня"], ["f5", "Маленький автопарк"], ["van", "На колесах"], ["hub2", "Друга точка"], ["c1", "Перший контракт"],
	["abroad", "За кордон"], ["d10k", "Десять тисяч"], ["rail", "Сталеві колії"], ["ocean", "Через океан"], ["air", "У небі"], ["m1", "Мільйон на місяць"],
	["c3", "Три материки"], ["r45", "Бездоганна репутація"], ["top3", "Призер"], ["top1", "Лідер ринку"]]


func _ms_done(id: String) -> bool:
	match id:
		"d100": return CO.deliv >= 100
		"f5": return CO.veh.size() >= 5
		"van": return CO.veh.any(func(v): return v.t == "van")
		"hub2": return CO.hubs.size() >= 2
		"c1": return CO.cdel >= 1
		"abroad": return CO.hubs.any(func(h): return PL[h.pid].cid != me)
		"d10k": return CO.deliv >= 1e4
		"rail": return CO.veh.any(func(v): return D.VT[v.t].mode == "rail")
		"ocean": return CO.flags.get("ocean", 0) != 0
		"air": return CO.veh.any(func(v): return D.VT[v.t].mode == "air")
		"m1": return co_rev(CO.lm) >= 1e6
		"c3":
			var s := {}
			for h in CO.hubs:
				s[PL[h.pid].land] = true
			return s.size() >= 3
		"r45": return CO.rating >= 4.5
		"top3": return co_rank() <= 3
		"top1": return co_rank() == 1
	return false


func co_month() -> void:
	var m: Dictionary = CO.m
	var wk: float = wage_k(me) * CO.wageLv * (1 - msk("hro") * .08)
	var wage := 0.0
	var mgmt := 0.0
	var rent := 0.0
	var mk := 0.0
	var ins := 0.0
	var interest := 0.0
	var stolen := 0.0
	for r in D.ROLE:
		wage += CO.staff.get(r, 0) * D.ROLE[r].w * wk
	var N := 0
	for r in CO.staff:
		N += CO.staff[r]
	var office := JS.round_js(45 * JS.pow(N, 1.12) * price_k(me) * (1 - msk("cfo") * .1))
	m.office = m.get("office", 0) + office
	CO.cash -= office
	# labour market refresh: depends on wages, HR director, network size
	var lk: float = JS.clamp_js(CO.wageLv, .8, 1.8) * (1 + msk("hro") * .8) * (1 + minf(3, CO.hubs.size() * .25))
	for r in D.ROLE:
		var open := false
		for t in D.VT:
			if D.VT[t].role == r and D.VT[t].tier <= CO.tier:
				open = true
		var pl: float = D.ROLE[r].pool
		CO.pool[r] = JS.round_js(minf(CO.pool.get(r, 0) * .5 + pl * lk, pl * lk * 2.5)) if open else 0.0
	for id in CO.mgr:
		mgmt += CO.mgr[id].sal
	for h in CO.hubs:
		rent += hub_rent_m(h)
		mk += h.get("mk", 0)
	if CO.ins:
		var vc := 0.0
		for v in CO.veh:
			vc += D.VT[v.t].cost
		ins = JS.round_js(500 + vc * .0035)
	for l in CO.loans:
		var it: float = l.left * l.rate / 12
		var pr: float = minf(l.left, l.amt / 24)
		interest += it
		l.left -= pr
		CO.cash -= pr
	CO.loans = CO.loans.filter(func(l): return l.left > 1)
	if CO.cash < 0:
		interest += -CO.cash * .025
	# tenders
	for t in CO.tenders:
		m.tender += t.pay * t.n
		t.left -= 1
	CO.cash += m.tender
	for t in CO.tenders:
		if t.left <= 0:
			var n: int = t.n
			for v in CO.veh:
				if n > 0 and v.st == "tender" and v.t == t.t:
					v.st = "idle"
					n -= 1
			co_news("good", "doc", "Завершено тендер «%s»: техніка повернулася в роботу" % t.n_)
	CO.tenders = CO.tenders.filter(func(t): return t.left > 0)
	# dishonest managers
	for id in CO.mgr:
		if not CO.mgr[id].honest:
			stolen += maxf(200, co_rev(m) * rnd(.008, .025))
	m.wage += wage
	m.mgmt += mgmt
	m.rent += rent
	m.mk += mk
	m.ins += ins
	m.interest += interest
	m.stolen += stolen
	m.other += stolen
	CO.cash -= wage + mgmt + rent + mk + ins + interest + stolen
	# history
	CO.hist.cash.append(CO.cash)
	CO.hist.rev.append(co_rev(m))
	CO.hist.rat.append(JS.fixed2(CO.rating))
	CO.hist.prof.append(co_rev(m) - co_cost(m))
	for key in CO.hist:
		if CO.hist[key].size() > 48:
			CO.hist[key].pop_front()
	CO.lm = m
	CO.m = co_zero()
	# competitors
	for c in CO.comp:
		c.rev *= 1 + c.g + rnd(-.02, .02)
	# world: border conflicts
	for x in CO.conf:
		if x.until <= day:
			co_news("good", "handshake", "Кордон %s — %s знову відкрито" % [states[x.a].name, states[x.b].name])
	CO.conf = CO.conf.filter(func(x): return x.until > day)
	if chance(.12) and CO.conf.size() < 3:
		var a: Dictionary = pick(states)
		var nb: Array = Array(neighbors[a.id]) if a.id < neighbors.size() else []
		nb = nb.filter(func(j): return j >= 0 and j < states.size())
		var bi: Variant = _pick_or_null(nb)
		if bi != null and not in_conf(a.id) and not in_conf(bi):
			var b: Dictionary = states[bi]
			CO.conf.append({"a": a.id, "b": b.id, "until": day + rint(90, 270)})
			co_news("bad", "swords", "Конфлікт на кордоні %s — %s: перевезення ускладнені, ризики зросли" % [a.name, b.name])
	if chance(.05):
		var k := rnd(1.15, 1.4)
		CO.fuel = minf(2.2, CO.fuel * k)
		co_news("bad", "barrel", "Пальне подорожчало на %d%%: світові ціни на нафту стрибнули" % int(JS.round_js((k - 1) * 100)))
	# events (one optional decision per month at most)
	co_month_events()
	# management candidates refresh
	for sd in D.MG:
		if not CO.mgr.has(sd.id) and (not CO.cand.has(sd.id) or chance(.25)):
			co_mgr_cand(sd.id)
	# achievements
	for ms in CO_MS:
		if not CO.ms.has(ms[0]) and _ms_done(ms[0]):
			CO.ms.append(ms[0])
			co_news("good", "star", "Досягнення %s: «%s»" % [CO.name, ms[1]])
	# bankruptcy
	if CO.cash < -co_credit() * .5:
		CO.neg += 1
	elif CO.cash > 0:
		CO.neg = 0
	if CO.neg >= 3:
		over = true
	biz_month()


# ---------- monthly events: strike, embezzlement, pay rises, tenders, viral reviews, inspections (coMonthEvents) ----------
func co_month_events() -> void:
	var ok := co_modal_ok()
	# strike
	var staff_n := 0
	for r in CO.staff:
		staff_n += CO.staff[r]
	if ok and CO.morale < 34 and staff_n >= 5 and chance(.4 - msk("hro") * .25):
		var raise := func() -> void:
			CO.wageLv = minf(1.8, CO.wageLv + .15)
			CO.morale += 15
		var talk := func() -> void:
			if chance(.3 + msk("hro") * .6):
				CO.morale += 10
			else:
				CO.strike = day + 6
				co_news("bad", "fist", "Страйк у %s: техніка стоїть" % CO.name)
		var fire := func() -> void:
			for r in CO.staff:
				CO.staff[r] = int(floor(CO.staff[r] * .9))
			CO.rating = JS.clamp_js(CO.rating - .1, 1, 5)
			CO.morale -= 10
		co_modal({"kind": "strike", "title": "Працівники погрожують страйком",
			"choices": [{"t": "Підняти зарплати на 15%", "f": raise}, {"t": "Переговори", "f": talk}, {"t": "Звільнити заводіїв", "f": fire}]})
		return
	# embezzlement caught
	var thief: Variant = null
	for id in CO.mgr:
		if not CO.mgr[id].honest and id != "cfo":
			thief = id
			break
	if ok and thief != null and CO.mgr.has("cfo") and CO.mgr.cfo.honest and chance(.15 + msk("cfo") * .5):
		var id: String = thief
		var g: Dictionary = CO.mgr[id]
		g.honest = true
		var loss := JS.round_js(maxf(3000, co_rev(CO.lm) * rnd(.03, .08)))
		var sue := func() -> void:
			CO.mgr.erase(id)
			CO.cash += loss * .5
			co_mgr_cand(id)
		var warn := func() -> void:
			g.honest = chance(.6)
			g.loyal = mini(100, g.loyal + 20)
		co_modal({"kind": "thief", "title": "%s краде" % _mg_name(id), "choices": [{"t": "Звільнити і подати до суду", "f": sue}, {"t": "Залишити з попередженням", "f": warn}]})
		return
	# a manager asks for a raise
	for id in CO.mgr.keys():
		var g: Dictionary = CO.mgr[id]
		var want := co_mgr_sal(g.skill)
		if ok and want > g.sal * 1.25 and chance(.3):
			var ns := want
			var agree := func() -> void:
				g.sal = ns
				g.loyal = mini(100, g.loyal + 20)
			var half := func() -> void:
				if chance(.5):
					g.sal = int(JS.round_js((g.sal + ns) / 2.0))
				else:
					g.loyal -= 20
			var refuse := func() -> void:
				g.loyal -= 30
				if g.loyal < 25:
					CO.mgr.erase(id)
					co_mgr_cand(id)
					co_news("bad", "briefcase", "%s %s пішов до конкурентів" % [_mg_name(id), CO.name])
			co_modal({"kind": "raise", "title": "%s просить підвищення" % _mg_name(id),
				"choices": [{"t": "Погодитись", "f": agree}, {"t": "Компроміс", "f": half}, {"t": "Відмовити", "f": refuse}]})
			return
	# tenders
	co_tender_offers()
	if chance(.1):
		var up := chance(.55)
		CO.rating = JS.clamp_js(CO.rating + (.12 if up else -.12), 1, 5)
		co_news("good" if up else "bad", "star" if up else "alert", ("Вірусний відгук: клієнт розхвалив швидкість %s" if up else "Вірусне відео: водій %s кидає посилки через паркан") % CO.name)
	var avg_c := 100.0
	if CO.veh.size():
		avg_c = 0.0
		for v in CO.veh:
			avg_c += v.cond
		avg_c /= CO.veh.size()
	if avg_c < 50 and chance(.4):
		var fine := JS.round_js(800 + CO.veh.size() * 300 * price_k(me))
		CO.cash -= fine
		CO.lm.other += fine
		co_news("bad", "gavel", "Техогляд виявив зношену техніку %s: штраф %d" % [CO.name, int(fine)])


func _mg_name(id: String) -> String:
	for s in D.MG:
		if s.id == id:
			return s.n
	return id


# ---------- tenders: long contracts that keep vehicles busy for months (coTenderOffers, ACT.coTd) ----------
const TD_NM := {"air": ["фармацевтичного концерну", "виробника електроніки", "авіабудівного заводу", "міжнародного Червоного Хреста"],
	"sea": ["зернотрейдера", "металургійного комбінату", "автоконцерну", "нафтової компанії"],
	"rail": ["вугільної шахти", "металургійного комбінату", "зернового елеватора", "цементного заводу"],
	"road": ["мережі супермаркетів", "автозаводу", "фармацевтичної компанії", "інтернет-магазину", "будівельного холдингу", "виробника добрив"]}


func co_tender_offers() -> void:
	CO.toff = CO.get("toff", []).filter(func(o): return o.exp > day)
	if CO.tier < 2:
		return
	var types := []
	for t in D.VT:
		var T: Dictionary = D.VT[t]
		if T.tier >= 1 and T.tier <= CO.tier and T.mode != "local":
			types.append(t)
	var i := 0
	while i < 3 and CO.toff.size() < 5:
		i += 1
		if not chance(.45 if i > 1 else .85):
			continue
		var t: String = pick(types)
		var T: Dictionary = D.VT[t]
		var n := 1 if T.cost > 1e7 else (rint(1, 2) if T.cost > 1e6 else rint(2, 5))
		var months := rint(4, 9)
		var pay := JS.round_js(T.cost * (.036 if T.cost > 1e7 else (.06 if T.cost > 1e6 else .11)) * price_k(me) * (1 + msk("cco") * .1))
		var o := {"id": CO.uid, "t": t, "n": n, "months": months, "pay": pay}
		CO.uid += 1
		o.n_ = pick(TD_NM.get(T.mode, TD_NM.road))
		o.exp = day + rint(20, 40)
		CO.toff.append(o)


## take a tender offer (ACT.coTd): "" when done, or why not
func co_tender_take(id: int) -> String:
	var o: Variant = null
	for x in CO.get("toff", []):
		if x.id == id:
			o = x
	if o == null:
		return "Пропозицію не знайдено"
	var idle: Array = CO.veh.filter(func(v): return v.t == o.t and v.st == "idle")
	if idle.size() < o.n:
		return "Бракує техніки: потрібно %d, вільних %d" % [o.n, idle.size()]
	var T: Dictionary = D.VT[o.t]
	if co_crew_free()[T.role] < T.get("crew", 1) * o.n:
		return "Бракує екіпажів: " + D.ROLE[T.role].n
	for v in idle.slice(0, o.n):
		v.st = "tender"
	CO.tenders.append({"t": o.t, "n": o.n, "left": o.months, "pay": o.pay, "n_": o.n_})
	_drop(CO.toff, o)
	co_news("good", "doc", "%s виграла тендер %s" % [CO.name, o.n_])
	return ""


## pick() of an empty array: the HTML version still draws R() and gets undefined
func _pick_or_null(a: Array) -> Variant:
	var i := int(floor(R.next() * a.size()))
	return a[i] if i < a.size() else null
