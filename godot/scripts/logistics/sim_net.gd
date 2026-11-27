class_name SimNet
extends SimActions
## The alternative balance, «Мережа терміналів» (a separate module: a new game chooses it, CO.alt). The cargo is
## a thing that is somewhere: waiting at the shipper's town, in a hub's warehouse or in a vehicle. An order taken
## from the board becomes a consignment (CO.net.cs) with its deadline; how it gets there is the player's network:
##   · a hub is a terminal: a warehouse (tons), a throughput (tons a day, a queue when more comes), modules for
##     the kinds of transport (a rail ramp, a pier, an air cargo terminal; the road terminal is always there) and
##     upgrades (cranes, a sorting line, a cold room, a bonded warehouse, a 24-hour shift);
##   · runs (CO.net.runs): one vehicle, or a partner carrier, along stops; at a stop it delivers what is for that
##     town, unloads what it leaves there into the warehouse and loads what was picked for it. A long haul of many
##     consignments in one train costs about as much as one: consolidation is the profit;
##   · lines (CO.net.lines): runs on a schedule, a round of a hub's area or a haul between two terminals;
##   · partners: their carriers between any terminals at their rates and departures, their terminals in towns
##     with a port, a station or an airport (fees for handling and storage); partner freight through your
##     terminals pays you and takes a share of their throughput;
##   · terminal events: strikes, broken cranes, a congested pier, customs checks, spoiled food, theft.
## In the classic game every hook below passes straight on: nothing there changes.

const NET_CAP := [0, 80, 300, 1200, 5000]        # warehouse, t, by hub level
const NET_THR := [0, 60, 220, 900, 3500]         # throughput, t a day, by hub level
const NET_MODS := [
	{"id": "rail", "n": "Залізнична рампа", "ic": "train", "cost": 45000, "d": "Потяги вантажаться й розвантажуються прямо у вашому терміналі — без збору партнерського терміналу й на пів дня швидше."},
	{"id": "sea", "n": "Причал", "ic": "anchor", "cost": 140000, "d": "Судна швартуються біля вашого складу: перевалка без партнерського порту, його зборів і черг."},
	{"id": "air", "n": "Авіавантажний термінал", "ic": "plane", "cost": 100000, "d": "Власна вантажна зона аеропорту: літаки завантажуються з вашого складу без зборів партнера."}]
const NET_UPS := [
	{"id": "crane", "n": "Крани й навантажувачі", "ic": "gear", "cost": [35000, 110000], "d": "Пропускна здатність ×1,5, з другим рівнем ×2,2."},
	{"id": "sort", "n": "Сортувальна лінія", "ic": "layers", "cost": [60000], "d": "Посилки, електроніку й ліки обробляє втричі швидше."},
	{"id": "cold", "n": "Холодильна камера", "ic": "snow", "cost": [50000], "d": "Продукти й ліки чекають на складі без псування."},
	{"id": "bond", "n": "Митний склад", "ic": "gavel", "cost": [80000], "d": "Митне оформлення в терміналі: рейси звідси стоять на кордонах утричі менше. Митниця іноді перевіряє вантажі на складі."},
	{"id": "shift", "n": "Цілодобова зміна", "ic": "sun", "cost": [15000], "mo": 3000, "d": "Пропускна здатність ×1,5. Зарплати нічної зміни — $3 тис./міс."}]
const NET_PERIOD := {"road": .25, "rail": 2.0, "sea": 4.0, "air": 1.0}   # partner departures, days
const NET_PFEE := {"road": 8, "rail": 10, "sea": 8, "air": 40}            # partner handling, $ for t^.85 (bulk is cheaper a ton)
const NET_PART := ["Закрито", "Частково", "Повністю"]                      # partner freight through a terminal
const NET_VT := {"road": "truck", "rail": "train", "sea": "ship", "air": "plane"}
const NET_EV := {"strike": ["Страйк вантажників", "users"], "crane": ["Зламався кран", "gear"], "congest": ["Затор біля причалу", "anchor"],
	"customs": ["Митна перевірка", "gavel"]}
const NET_AREA := 2.4          # a hub's area (world units): the towns its rounds go to
const NET_LATE_MAX := 10.0     # days late after which the shipper takes the cargo away


# ====================================================================== the start
func net_init() -> void:
	CO.alt = true
	CO.board = []
	CO.net = {"uid": 1, "cs": [], "term": {}, "runs": [], "lines": [], "flow": {}, "stat": {"done": 0, "fail": 0, "part_t": 0.0, "part_rev": 0.0}}
	_T(CO.hq)
	# a fuller board from the first day: consolidation needs freight
	var i := 0
	while i < 60 and CO.board.size() < co_board_max():
		var k: Variant = co_gen()
		if k != null:
			CO.board.append(k)
		i += 1


func alt() -> bool:
	return CO.get("alt", false)


## the terminal of a hub (created with the hub; gone with it)
func _T(pid: int) -> Dictionary:
	var key := str(pid)
	var t: Dictionary = CO.net.term.get(key, {})
	if t.is_empty():
		t = {"mods": {}, "up": {}, "q": 0.0, "part": 1, "ev": []}
		CO.net.term[key] = t
	return t


func net_term(pid: int) -> Variant:
	if hub_at(pid) == null:
		return null
	return _T(pid)


## what kind of place a consignment can wait at: "hub" (yours), "part" (a partner terminal: a port, a station or
## an airport) or "" (a town: only its own cargo waits there)
func n_kind(pid: int) -> String:
	if hub_at(pid) != null:
		return "hub"
	var p: Dictionary = PL[pid]
	return "part" if p.port != null or p.rail or p.air else ""


func n_mod(pid: int, m: String) -> bool:
	if m == "road":
		return true
	var t: Variant = net_term(pid)
	return t != null and t.mods.has(m)


func n_up(pid: int, id: String) -> int:
	var t: Variant = net_term(pid)
	return int(t.up.get(id, 0)) if t != null else 0


func n_ev(pid: int, k: String) -> Variant:
	var t: Variant = net_term(pid)
	if t == null:
		return null
	for e in t.ev:
		if e.k == k and e.until > co_now():
			return e
	return null


func n_cap(pid: int) -> float:
	var h: Variant = hub_at(pid)
	return float(NET_CAP[h.lvl]) if h != null else 1e9


## tons a day the terminal handles for the company: the level, cranes, the night shift, events, and the share
## partners take
func n_thr(pid: int) -> float:
	var h: Variant = hub_at(pid)
	if h == null:
		return 1e9
	var t: Dictionary = _T(pid)
	var x: float = NET_THR[h.lvl] * [1.0, 1.5, 2.2][mini(2, n_up(pid, "crane"))] * (1.5 if n_up(pid, "shift") else 1.0)
	x *= 1 - .18 * int(t.part)
	if n_ev(pid, "strike") != null:
		return 0.0
	if n_ev(pid, "crane") != null:
		x *= .5
	if n_ev(pid, "congest") != null:
		x *= .45
	return x


func n_stored(pid: int) -> float:
	var s := 0.0
	for c in CO.net.cs:
		if c.at == pid and (c.st == "ready" or c.st == "proc") and not c.k.get("sea"):   # shiploads wait at the quay
			s += c.k.tons
	return s


func n_inbound(pid: int) -> float:
	var s := 0.0
	for r in CO.net.runs:
		for c in _run_cs(r):
			if c.get("dst_pid", -1) == pid and c.k.to != pid:
				s += c.k.tons
	return s


## days of work waiting in a terminal's queue
func n_queue(pid: int) -> float:
	var t: Variant = net_term(pid)
	return maxf(0, t.q - co_now()) if t != null else 0.0


static func _small(cg: String) -> bool:
	return cg == "parcel" or cg == "elec" or cg == "med"


## handling a batch at a place from `t`: when it is done. A hub works through its queue at its throughput; a
## partner terminal takes a fixed time; a town loads and unloads a vehicle by hand
const NET_QUAY := {"sea": 2500.0, "rail": 1200.0}   # ships and trains load at the quay or the ramp, t a day


## tons a day a place loads this kind of transport: ships and trains at the quay or the ramp (own with the
## module, cranes on top; else the partner's next door, slower), everything else through the warehouse
func n_rate(pid: int, m: String) -> float:
	if NET_QUAY.has(m):
		if n_kind(pid) == "hub" and n_mod(pid, m):
			return NET_QUAY[m] * [1.0, 1.5, 2.2][mini(2, n_up(pid, "crane"))]
		return NET_QUAY[m] * .6
	return n_thr(pid)


func n_handle(pid: int, cs: Array, m: String, t: float) -> float:
	var tons := 0.0
	for c in cs:
		tons += c.k.tons * (.35 if _small(c.k.cg) and n_up(pid, "sort") else 1.0)
	var base: float = D.HAND[m] * hand_k() * .5
	match n_kind(pid):
		"hub":
			var T: Dictionary = _T(pid)
			var thr := n_rate(pid, m) if n_thr(pid) > 0 else 0.0
			var start := maxf(t, T.q)
			if thr <= 0:   # a strike: the work waits for its end
				var e: Variant = n_ev(pid, "strike")
				start = maxf(start, e.until if e != null else t + 1)
				thr = NET_THR[hub_at(pid).lvl]
			var over := maxf(0, n_stored(pid) - n_cap(pid))
			var end := start + maxf(base, tons / thr * (1.8 if over > 0 else 1.0))
			if not n_mod(pid, m):   # the partner's terminal in the same town loads this kind of transport
				end += .3
			T.q = end
			return end
		"part":
			return t + .4 + base + (tons / n_rate(pid, m) if NET_QUAY.has(m) else 0.0)
	return t + base + minf(.3, tons / 60.0)


## what handling there costs (a partner's terminal, or your hub without the module for this kind of transport)
func n_hfee(pid: int, cs: Array, m: String) -> float:
	var tons := 0.0
	for c in cs:
		tons += c.k.tons
	var k := n_kind(pid)
	if k == "part" or (k == "hub" and not n_mod(pid, m)):
		return JS.round_js((150 + NET_PFEE[m] * JS.pow(maxf(tons, .1), .85)) * price_k(PL[pid].cid))
	return 0.0


# ====================================================================== the board
func co_gen() -> Variant:
	if not alt():
		return super.co_gen()
	return _co_gen_perm()


func _co_gen() -> Variant:
	if not alt():
		return super._co_gen()
	return net_gen()


## the orders on the board still open (the ones taken stay shown, marked, but take no place)
func net_board_n() -> int:
	var n := 0
	for k in CO.board:
		if not k.get("taken"):
			n += 1
	return n


func co_board_max() -> int:
	if not alt():
		return super.co_board_max()
	if CO.tier < 1:
		return 0
	var s := 0
	var mods := 0
	for h in CO.hubs:
		s += h.lvl
		mods += _T(h.pid).mods.size()
	return 14 + CO.tier * 3 + s * 3 + mods * 2 + int(JS.round_js(msk("cco") * 6))


## the cheapest way partners would carry it on their own: what the shipper expects to pay (and how long)
func net_ref(A: Dictionary, B: Dictionary, tons: float) -> Variant:
	var box := {"best": null}
	var try := func(legs: Array) -> void:
		var c := 0.0
		var t := 0.0
		for L in legs:
			c += ch_cost(L.m, L.len, tons) + D.CH_BASE[L.m] * .25
			t += L.len / (D.CH_SPD[L.m] * spd_k()) + D.HAND[L.m] * hand_k() * 2 + NET_PERIOD[L.m] * .5
		if box.best == null or c < box.best.c:
			var ml: Dictionary = legs[0]
			for L in legs:
				if D.CH_RATE[L.m] * L.len > D.CH_RATE[ml.m] * ml.len:
					ml = L
			box.best = {"c": c, "t": t, "m": ml.m, "legs": legs}
	var road := func(a: Dictionary, b: Dictionary) -> Variant:
		if a.id == b.id:
			return []
		var r: Variant = co_route("road", a.id, b.id)
		return [{"a": a.id, "b": b.id, "m": "road", "len": r.len}] if r != null else null
	if A.land == B.land:
		var rd: Variant = road.call(A, B)
		if rd != null:
			try.call(rd)
	for m in ["rail", "sea", "air"]:
		if m == "rail" and A.land != B.land:
			continue
		if m == "air" and tons > 60:
			continue
		if m == "sea" and A.land == B.land and JS.hypot(A.x - B.x, A.z - B.z) < 4:
			continue
		var n1: Variant = _near_t(A, m)
		var n2: Variant = _near_t(B, m)
		if n1 == null or n2 == null or n1.id == n2.id:
			continue
		var r: Variant = co_route(m, n1.id, n2.id)
		if r == null:
			continue
		var pre: Variant = road.call(A, n1)
		var post: Variant = road.call(n2, B)
		if pre == null or post == null:
			continue
		try.call(pre + [{"a": n1.id, "b": n2.id, "m": m, "len": r.len}] + post)
	return box.best


## the nearest town with a station, a port or an airport on the same land
func _near_t(p: Dictionary, m: String) -> Variant:
	if node_ok(m, p):
		return p
	var best: Variant = null
	var bd := 1e9
	for q in PL:
		if q.land == p.land and node_ok(m, q) and not in_conf(q.cid):
			var d := JS.hypot(q.x - p.x, q.z - p.z)
			if d < bd:
				bd = d
				best = q
	return best


func _hub_d(p: Dictionary) -> float:
	var bd := 1e9
	for h in CO.hubs:
		var q: Dictionary = PL[h.pid]
		if q.land == p.land:
			bd = minf(bd, JS.hypot(q.x - p.x, q.z - p.z))
	return bd


## an order of the alternative balance: from a town of the licence to another, no kind of transport fixed;
## shippers near the company's hubs order more; small parcels, middle loads and some bulk for rail and sea
func net_gen() -> Variant:
	# special freight of the industries: a refinery's fuel by tanker trucks to the port (from the tankers'
	# licence), shiploads between continents that only a ship can take (from the sea licence)
	var sp := R.next()
	if CO.tier >= 2 and sp < .12:
		var kr: Variant = _gen_refinery()
		if kr != null:
			return kr
	elif CO.tier >= 5 and sp < .3:
		var ks: Variant = _gen_sea()
		if ks != null:
			return ks
	var pool := PL.filter(func(p): return co_scope(p) and not in_conf(p.cid))
	if pool.size() < 2:
		return null
	var tw := 0.0
	var ws := []
	for p in pool:
		var d := _hub_d(p)
		var w: float = (sqrt(p.pop) + .15) * (1 + 2.5 * exp(-d * d / 3.0)) * (2.2 if p.type == "cap" else 1.0)
		tw += w
		ws.append(w)
	var r0 := R.next() * tw
	var A: Dictionary = pool[0]
	for i in pool.size():
		r0 -= ws[i]
		if r0 <= 0:
			A = pool[i]
			break
	# where to: the licence opens longer hauls — another state on the land (trains pay there), another continent
	# (ships and planes); the classic shares at the start
	var far := R.next()
	var p_cty: float = .55 if CO.tier < 3 else .4
	var p_land: float = .85 if CO.tier < 5 else .68
	var cand := pool.filter(func(p): return p.id != A.id and (p.cid == A.cid if far < p_cty else (p.land == A.land and p.cid != A.cid if far < p_land else p.land != A.land)))
	if cand.is_empty():
		cand = pool.filter(func(p): return p.id != A.id)
	var t2 := 0.0
	var w2 := []
	for p in cand:
		var d := _hub_d(p)
		var w: float = (sqrt(p.pop) + .15) * (1 + 1.5 * exp(-d * d / 3.0))
		t2 += w
		w2.append(w)
	var r2 := R.next() * t2
	var B: Dictionary = cand[0]
	for i in cand.size():
		r2 -= w2[i]
		if r2 <= 0:
			B = cand[i]
			break
	# the size grows with the licence: parcels and small loads first, bulk for trains and ships later
	var sz := R.next()
	var lo := .2
	var hi := 4.0
	var mid: float = [5.0, 5.0, 20.0, 25.0, 25.0][mini(4, CO.tier)]
	var big: float = [0.0, 0.0, 0.0, 120.0, 400.0][mini(4, CO.tier)]
	if sz > .6:
		lo = 4.0
		hi = mid
	if sz > (.75 if CO.tier >= 4 else .88) and big > 0:   # bulk: for trains, more of it with the rail licence
		lo = 25.0
		hi = big if (_near_t(A, "rail") != null or A.land != B.land) else 40.0
	if A.land != B.land:   # across the sea: parcels for planes, middle loads, bulk for ships
		if sz < .4:
			lo = .2
			hi = 5.0
		elif sz < .7:
			lo = 5.0
			hi = 40.0
		else:
			lo = 40.0
			hi = 2000.0
	var tons := lo * JS.pow(hi / lo, JS.pow(R.next(), 1.5))
	tons = JS.fixed1(tons) if tons < 5 else JS.round_js(tons)
	var cgs := D.CARGO.filter(func(cg): return not cg.get("aid", false) and cg.t[1] >= tons * .5 and cg.t[0] <= tons * 1.5)
	if cgs.is_empty():
		return null
	var cg: Dictionary = pick(cgs)
	var ref: Variant = net_ref(A, B, tons)
	if ref == null:
		return null
	var urg := R.next()
	var risk := JS.clamp_js((co_risk(A.cid) + co_risk(B.cid)) / 2 * cg.get("theft", .7), 0, 2)
	var min_r := JS.clamp_js(JS.round_js((CO.rating + rnd(-.4, .5)) * 10) / 10, 2.5, 4.9) if chance(.18) else 0.0
	var gr := co_grade()
	var pk := (price_k(A.cid) + price_k(B.cid)) / 2
	var pay := JS.round_js(ref.c * 1.12 * cg.k * pk * (1 + urg * .45) * (1 + risk * .15) * (.8 + CO.rating * .07) * (1 + msk("cco") * .12) * (1.3 if min_r else 1.0) * rnd(.9, 1.1) * (1 + gr * .03))
	pay *= fast_k()
	var dl := maxf(1.5, ref.t * (2.6 - urg * .9) + 1.5)
	var k := {"id": CO.uid, "from": A.id, "to": B.id, "cg": cg.id, "tons": tons, "pay": pay, "dlDays": JS.fixed1(dl), "mode": ref.m, "risk": risk,
		"minR": min_r, "len": 0.0, "exp": day + rint(4, 10), "net": 1, "ref": ref.legs.map(func(L): return L.m)}
	for L in ref.legs:
		k.len += L.len
	CO.uid += 1
	return k


## «Взяти в роботу»: the order becomes a consignment waiting where it is
func net_accept(k: Dictionary) -> Dictionary:
	if not CO.board.has(k) or k.get("taken"):
		return {}
	if k.get("minR", 0) and CO.rating < k.minR:
		return _toast("warn", "Замовник хоче рейтинг %.1f+" % k.minR, "Ваш рейтинг %.2f" % CO.rating)
	var nd := perm_need(cargo_i.get(k.cg), "sea" if k.get("sea") else "road").filter(func(x): return not perm_ok(x))
	if nd.size():
		return _toast("warn", "Потрібен дозвіл", perm_i[nd[0]].n)
	k.taken = 1   # the card stays on the board, marked «Вантаж прийнято», until the offer would have expired
	_take(k)
	co_news("good", "box", "%s прийняла вантаж «%s»: %s → %s" % [CO.name, cargo_i[k.cg].n.to_lower(), PL[k.from].name, PL[k.to].name])
	return _toast("good", "Вантаж прийнято", "%s → %s · до %s" % [PL[k.from].name, PL[k.to].name, _days(k.dlDays)])


## a consignment of an order (or of a contract) waiting at the shipper's
func _take(k: Dictionary) -> Dictionary:
	var c := {"id": CO.net.uid, "k": k, "at": k.from, "st": "wait", "dl": day + k.dlDays, "t0": co_now(), "dmg": 0.0, "hops": 0, "run": -1, "since": co_now(), "auto": false}
	CO.net.uid += 1
	CO.net.cs.append(c)
	if n_kind(k.from) == "hub":   # the shipper brings it to the terminal in town
		c.st = "proc"
		c.rdy = n_handle(k.from, [c], "sea" if k.get("sea") else "road", co_now())   # a shipload comes straight to the quay
	return c


# ====================================================================== the way through the network
## a suggested way for cargo from a place: own hubs and the partners' terminals near the ends, every kind of
## transport between them; the cheapest that still makes the deadline (time weighed against the money)
var _np := {}        # ways found today: the board shows the same orders on every rebuild of its window
var _np_k := ""


func net_path(from: int, to: int, tons: float, left: float, pay: float) -> Variant:
	if from == to:
		return {"legs": [], "t": 0.0, "c": 0.0}
	var dk := "%d|%d|%d|%d|%d" % [int(day), CO.hubs.size(), CO.veh.size(), blk_v, CO.tier]
	if dk != _np_k:
		_np_k = dk
		_np = {}
	var key := "%d:%d:%.2f:%.1f:%d" % [from, to, tons, left, int(pay)]
	if _np.has(key):
		return _np[key]
	var res: Variant = _net_path(from, to, tons, left, pay)
	_np[key] = res
	return res


func _net_path(from: int, to: int, tons: float, left: float, pay: float) -> Variant:
	var A: Dictionary = PL[from]
	var B: Dictionary = PL[to]
	var nodes := {from: true, to: true}
	for h in CO.hubs:
		nodes[h.pid] = true
	for p in [A, B]:
		for m in ["rail", "sea", "air"]:
			var q: Variant = _near_t(p, m)
			if q != null:
				nodes[q.id] = true
	for h in CO.hubs:
		for m in ["rail", "sea", "air"]:
			var q: Variant = _near_t(PL[h.pid], m)
			if q != null:
				nodes[q.id] = true
	var N: Array = nodes.keys()
	var own := _own_types()
	own["_ppl"] = pay / maxf(.05, JS.hypot(A.x - B.x, A.z - B.z) * CO_DU * 1.3)   # what the cargo pays a unit of its way
	var lam := pay / maxf(1.0, left) * .35
	var dist := {}
	var tim := {}
	var prev := {}
	for n in N:
		dist[n] = 1e18
	dist[from] = 0.0
	tim[from] = 0.0
	var done := {}
	while true:
		var u := -1
		var bu := 1e18
		for n in N:
			if not done.has(n) and dist[n] < bu:
				bu = dist[n]
				u = n
		if u < 0 or u == to:
			break
		done[u] = true
		var U: Dictionary = PL[u]
		for v in N:
			if done.has(v) or v == u:
				continue
			var V: Dictionary = PL[v]
			for m in ["road", "rail", "sea", "air"]:
				if not node_ok(m, U) or not node_ok(m, V):
					continue
				if (m == "road" or m == "rail") and U.land != V.land:
					continue
				var e := _edge(m, U, V, tons, own)
				if e.is_empty():
					continue
				var t: float = tim[u] + e.t
				var w: float = dist[u] + e.c + e.t * lam + (1e6 if t > left else 0.0)
				if w < dist[v]:
					dist[v] = w
					tim[v] = t
					prev[v] = {"a": u, "m": m}
	if not prev.has(to):
		return null
	var legs := []
	var c: int = to
	var cost := 0.0
	while c != from:
		var pv: Dictionary = prev[c]
		legs.push_front({"a": pv.a, "b": c, "m": pv.m})
		c = pv.a
	for L in legs:
		cost += _edge(L.m, PL[L.a], PL[L.b], tons, own).c
	return {"legs": legs, "t": tim[to], "c": cost}


## a step of a way: an estimate from the straight distance (exact routes are found when a run is planned):
## own transport of that kind at its cost per ton, otherwise a partner's price; handling at the ends
## the largest own vehicle type of every kind of transport (once per way: a big fleet is scanned once)
func _own_types() -> Dictionary:
	var own := {}
	for v in CO.veh:
		var m: String = D.VT[v.t].mode
		if not own.has(m) or D.VT[v.t].cap > D.VT[own[m]].cap:
			own[m] = v.t
	return own


func _edge(m: String, U: Dictionary, V: Dictionary, tons: float, owns: Dictionary) -> Dictionary:
	var big: String = owns.get(m, "")
	if tons > PART_CAP[m] and (big == "" or D.VT[big].cap < tons):   # too much for partners and own vehicles of this kind
		return {}
	var d := JS.hypot(U.x - V.x, U.z - V.z) * CO_DU
	var ln: float = d * {"road": 1.3, "rail": 1.2, "sea": 1.35, "air": 1.0}[m]
	if m == "air" and d < .3:
		return {}
	if m == "sea" and U.land == V.land and d < .5:
		return {}
	var own: String = owns.get(m, "")
	var c := 0.0
	var t := 0.0
	if own != "":
		var T: Dictionary = D.VT[own]
		t = ln / (T.spd * spd_k())
		var run: float = ln * T.fuel * CO.fuel * fuel_k(m) + (T.up + D.ROLE[T.role].w * wage_k(me) / 30 * T.get("crew", 1)) * t
		c = run * minf(1.0, tons / (T.cap * .6))
	else:
		t = ln / (D.CH_SPD[m] * spd_k()) + NET_PERIOD[m] * .5
		c = maxf(owns.get("_ppl", 0.0) * ln * PART_SHARE, ch_cost(m, ln, tons)) + D.CH_BASE[m] * .25
	t += D.HAND[m] * hand_k()
	var hu := hub_at(V.id) != null
	if not hu or not n_mod(V.id, m):
		c += (150 + NET_PFEE[m] * JS.pow(maxf(tons, .1), .85)) * price_k(V.cid) * (0.0 if n_kind(V.id) == "" else 1.0)
	return {"c": c, "t": t}


## where a consignment should go next (cached for a day at the same place)
func net_next(c: Dictionary) -> Variant:
	if c.at == c.k.to:
		return null
	var nh: Variant = c.get("nh")
	if nh != null and nh.at == c.at and nh.day == int(day):
		return nh.L
	var P: Variant = net_path(c.at, c.k.to, c.k.tons, maxf(.5, c.dl - co_now()), c.k.pay)
	var L: Variant = P.legs[0] if P != null and P.legs.size() else null
	c.nh = {"at": c.at, "day": int(day), "L": L, "P": P}
	return L


# ====================================================================== runs
## a run: {vid (−1 a partner), m, stops: [place…], picks: {stop index: [consignment id…]}}. A consignment rides to
## its own town if the run passes it, otherwise to the last stop (a hub or a partner terminal)
func _cs(id: int) -> Variant:
	for c in CO.net.cs:
		if c.id == id:
			return c
	return null


func _run_cs(r: Dictionary) -> Array:
	var out := []
	for c in CO.net.cs:
		if c.run == r.id:
			out.append(c)
	return out


## runs that are loading (at the start or at a stop on the way) or waiting for a partner's departure: shown
## among the trips under way from the moment they are sent
func net_loading() -> Array:
	return CO.net.runs.filter(func(r): return r.st == "load") if alt() else []


## what the cargo booked on a run pays at its towns
func net_run_pay(rid: int) -> float:
	var x := 0.0
	for c in CO.net.cs:
		if c.run == rid:
			x += c.k.pay
	return x


func _veh(id: int) -> Variant:
	for v in CO.veh:
		if v.id == id:
			return v
	return null


## the stop where a consignment loaded at stop i gets off
static func _drop_at(stops: Array, i: int, to: int) -> int:
	for j in range(i + 1, stops.size()):
		if stops[j] == to:
			return j
	return stops.size() - 1


## what a run would do: legs, times, costs, the load on every leg, when each consignment arrives
## a leg's route: through the road or rail points the player put on it (via), or the usual one; on the road,
## around the toll motorways and/or the heavy-vehicle bans when the player asked (av: "toll", "ban", "toll,ban")
func net_leg_route(m: String, a: int, b: int, via: Array, av: String = "") -> Variant:
	if via.is_empty():
		if m != "road" or av == "" or not road_rules:
			return co_route(m, a, b)
		var av0 := road_av
		road_av = av
		var r: Variant = co_route(m, a, b)
		road_av = av0
		return r
	var f := PackedFloat32Array()
	var len_ := 0.0
	var pts: Array = [a] + via + [b]
	for k in range(1, pts.size()):
		var r: Variant = call("lp_seg", m, pts[k - 1], pts[k])   # Sim's (the planner's own path between points)
		if r == null:
			return null
		f.append_array(r.p.slice(0 if k == 1 else 2))
		len_ += r.len
	return {"p": f, "len": len_}


func net_calc(spec: Dictionary) -> Dictionary:
	var stops: Array = spec.stops
	var res := {"ok": false, "why": "", "legs": [], "rows": [], "t": 0.0, "c": 0.0, "rev": 0.0, "fill": 0.0, "tons": 0.0}
	if stops.size() < 2:
		res.why = "Додайте зупинку"
		return res
	var own: bool = spec.get("vid", -1) >= 0
	var v: Variant = _veh(spec.vid) if own else null
	if own and v == null:
		res.why = "Техніки немає"
		return res
	var m: String = D.VT[v.t].mode if own else spec.m
	var T: Dictionary = D.VT[v.t] if own else D.VT[NET_VT[m]]
	if own:
		if v.st != "idle" or (v.get("resv") and v.resv != "net:%d" % spec.get("rid", -9)) or v.loc != stops[0]:
			res.why = "%s зайнята або стоїть деінде" % T.n
			return res
	for i in stops.size():
		if not node_ok(m, PL[stops[i]]):
			res.why = "%s: немає %s" % [PL[stops[i]].name, {"rail": "станції", "sea": "порту", "air": "аеропорту", "road": "дороги"}[m]]
			return res
	if own and CO.strike > day:
		res.why = "Страйк: екіпажі не виходять на рейси"
		return res
	if own and co_crew_free().get(T.role, 0) < T.get("crew", 1):
		res.why = "Бракує персоналу: " + D.ROLE[T.role].n.to_lower()
		return res
	var picks: Dictionary = spec.get("picks", {})
	var board := {}   # consignment id → [on, off]
	var sea_only := ""
	var ids := []
	for i in stops.size() - 1:
		for id in picks.get(i, []):
			var c: Variant = _cs(id)
			if c == null:
				continue
			if c.at != stops[i] or not (c.st == "ready" or c.st == "wait" or (c.st == "proc" and c.get("rdy", 0) - co_now() < 2)) or (c.run >= 0 and c.run != spec.get("rid", -9)):
				continue
			if c.k.get("sea") and m != "sea":   # a shipload: only a ship takes it
				sea_only = cargo_i[c.k.cg].n
				continue
			var off: int = int(spec.get("offs", {}).get(id, _drop_at(stops, i, c.k.to)))
			if off <= i or off >= stops.size():
				off = _drop_at(stops, i, c.k.to)
			board[id] = [i, off]
			ids.append(c)
	if ids.is_empty() and sea_only != "":
		res.why = "%s: такого обсягу везуть лише морем" % sea_only
		return res
	for c in ids:   # cargo is left only at a terminal, or at its own town
		var q: int = stops[board[c.id][1]]
		if q != c.k.to and n_kind(q) == "":
			res.why = "%s — не термінал: вантажі туди можна лише доставляти" % PL[q].name
			return res
	# the load on every leg
	var mx := 0.0
	var mv := 0.0
	var loads := []
	for i in stops.size() - 1:
		var t := 0.0
		var vo := 0.0
		for c in ids:
			if board[c.id][0] <= i and board[c.id][1] > i:
				t += c.k.tons
				vo += _kv(c.k)
		loads.append(t)
		mx = maxf(mx, t)
		mv = maxf(mv, vo)
	res.tons = mx
	if not own and mx > PART_CAP[m]:
		res.why = "Партнер (%s) бере до %s т за рейс" % [{"road": "авто", "rail": "залізниця", "air": "авіа", "sea": "море"}[m], Ui.grp(PART_CAP[m])]
		res.over = true
	if own:
		res.fill = mx / T.cap
		if mx > T.cap + 1e-6 or (T.get("vol", 0) and mv > T.vol + 1e-6):
			res.why = "Не вміщує: %s т і %s м³ при %s т і %s м³" % [JS.fixed1(mx), JS.fixed1(mv), T.cap, T.vol]
			res.over = true
	# legs: routes, time, money; handling at the stops
	var t := co_now()
	var cost := 0.0
	var at_stop := {}
	for i in stops.size():
		var on := []
		var offl := []
		for c in ids:
			if board[c.id][0] == i:
				on.append(c)
			if board[c.id][1] == i:
				offl.append(c)
		if i > 0:
			var a: int = stops[i - 1]
			var b: int = stops[i]
			var r: Variant = net_leg_route(m, a, b, spec.get("via", {}).get(i - 1, []), spec.get("av", ""))
			if r == null:
				res.why = "Немає маршруту %s → %s" % [PL[a].name, PL[b].name]
				return res
			var tm: float
			var lc: float
			if own:
				tm = r.len / (T.spd * spd_k())
				lc = r.len * T.fuel * CO.fuel * fuel_k(m) + (T.up * rep_k() + D.ROLE[T.role].w * wage_k(me) * CO.wageLv / 30 * T.get("crew", 1)) * tm
			else:
				var dep := _part_dep(t, a, b, m)
				tm = dep - t + r.len / (D.CH_SPD[m] * spd_k())
				var aboard := ids.filter(func(c): return board[c.id][0] <= i - 1 and board[c.id][1] > i - 1)
				lc = net_part_fee(m, r.len, aboard, PL[a].cid != PL[b].cid)
			var cust := 0.0
			if PL[a].cid != PL[b].cid and (m == "sea" or m == "air"):
				cust = .3 * (.4 if n_up(a, "bond") else 1.0)
			elif PL[a].cid != PL[b].cid:
				cust = cp_wait(PL[b].cid, m) * (.3 if n_up(a, "bond") else 1.0)
			t += tm + cust
			cost += lc
			res.legs.append({"a": a, "b": b, "len": r.len, "t": tm + cust, "c": lc, "tons": loads[i - 1]})
		# handling at the stop: what gets off, then what gets on (an estimate: the queue as it is now)
		var hcs: Array = offl + on
		if hcs.size():
			var hf := n_hfee(stops[i], hcs, m)
			cost += hf
			var wait: float = n_queue(stops[i]) if n_kind(stops[i]) == "hub" else 0.0
			var tons := 0.0
			for c in hcs:
				tons += c.k.tons
			var dur: float = D.HAND[m] * hand_k() * .5 + (tons / maxf(1.0, n_rate(stops[i], m)) if n_kind(stops[i]) == "hub" else \
				((.4 + (tons / n_rate(stops[i], m) if NET_QUAY.has(m) else 0.0)) if n_kind(stops[i]) == "part" else minf(.3, tons / 60.0)))
			if i == 0 and n_kind(stops[i]) == "hub":
				t += wait
			t += dur
		at_stop[i] = t
	res.t = t - co_now()
	res.c = cost
	var rev := 0.0
	for c in ids:
		var off: int = board[c.id][1]
		var eta: float = at_stop[off]
		var to_dest: bool = stops[off] == c.k.to
		var late := maxf(0, eta - c.dl)
		if to_dest:
			rev += c.k.pay * (maxf(.35, 1 - late * .12) if late > 0 else 1.0) * (1 - minf(.8, c.dmg))
		res.rows.append({"c": c, "on": board[c.id][0], "off": off, "eta": eta, "late": late, "dest": to_dest})
	res.rev = rev
	if ids.is_empty() and res.why == "":
		res.why = "Нічого не завантажено"
	if res.why == "":
		res.ok = true
	return res


const PART_SHARE := .85
const PART_CAP := {"road": 400.0, "rail": 6000.0, "air": 250.0, "sea": 2000.0}   # what one booking (or run) can take, t   # a partner's cut of what a consignment pays, for the part of its way it carries


## a partner carrier's price for one booking: partners know the market — for every consignment they take most of
## what the shipper pays, in proportion to the part of its way this leg covers — plus a booking fee. Partners
## keep the network going where it has no vehicles of its own; the profit is in own vehicles, full ones
func net_part_fee(m: String, len_: float, cs: Array, border: bool) -> float:
	var x: float = D.CH_BASE[m] * .25
	var tons := 0.0
	for c in cs:
		x += c.k.pay * PART_SHARE * clampf(len_ / maxf(.05, c.k.get("len", len_)), .15, 1.2)
		tons += c.k.tons
	return JS.round_js(maxf(x, ch_cost(m, len_, maxf(.5, tons)) + D.CH_BASE[m] * .25) * (1.1 if border else 1.0))


func _part_dep(t: float, a: int, b: int, m: String) -> float:
	var per: float = NET_PERIOD[m]
	var ph: float = float((a * 31 + b * 17) % 97) / 97.0 * per
	return ph + ceil((t - ph) / per) * per


## «Відправити»: the consignments are booked on the run, the vehicle kept for it; loading starts at the first stop
func net_go(spec: Dictionary, by_line: bool = false) -> Dictionary:
	var C := net_calc(spec)
	if not C.ok:
		return _toast("warn", "Рейс не відправлено", C.why)
	var rid: int = CO.net.uid
	CO.net.uid += 1
	var stops: Array = spec.stops.duplicate()
	var own: bool = spec.get("vid", -1) >= 0
	var m: String = D.VT[_veh(spec.vid).t].mode if own else spec.m
	var r := {"id": rid, "vid": spec.get("vid", -1), "m": m, "stops": stops, "picks": {}, "i": 0, "st": "load", "t_dep": 0.0, "line": spec.get("line", -1), "cost": 0.0, "rev": 0.0, "job": -1,
		"offn": {}, "via": spec.get("via", {}).duplicate(true), "av": spec.get("av", "")}
	for row in C.rows:   # what each stop unloads (kept for the trip card, the cargo itself leaves the run there)
		r.offn[row.off] = r.offn.get(row.off, 0) + 1
	for row in C.rows:
		var c: Dictionary = row.c
		c.run = rid
		c.dst_pid = stops[row.off]
		c.on_i = row.on
		c.off_i = row.off
		c.auto = c.auto or by_line
		if not r.picks.has(row.on):
			r.picks[row.on] = []
		r.picks[row.on].append(c.id)
	if own:
		var v: Dictionary = _veh(spec.vid)
		v.resv = "net:%d" % rid
		v.nres = rid
	CO.net.runs.append(r)
	_load_at(r, 0, co_now())
	var n := 0
	for x in r.picks.values():
		n += x.size()
	if not by_line:
		co_news("", D.VT[NET_VT[m]].ic if not own else D.VT[_veh(spec.vid).t].ic, "%s: рейс %s → %s, вантажів: %d" % [CO.name, PL[stops[0]].name, PL[stops.back()].name, n])
	return _toast("good", "Рейс відправлено", "%s → %s · вантажів %d · завантаження %s" % [PL[stops[0]].name, PL[stops.back()].name, n, _days(maxf(0, r.t_dep - co_now()))])


## loading at a stop: what gets on there is handled; the run leaves when it is done (a partner at its departure)
func _load_at(r: Dictionary, i: int, t: float) -> void:
	var on := []
	for id in r.picks.get(i, []):
		var c: Variant = _cs(id)
		if c != null and c.at == r.stops[i] and c.run == r.id and c.st != "done":
			on.append(c)
	var end := t
	if on.size():
		for c in on:
			if c.st == "proc":   # still being unloaded from an earlier run: it can only go after that
				end = maxf(end, c.rdy)
		end = maxf(end, n_handle(r.stops[i], on, r.m, t))
		var f := n_hfee(r.stops[i], on, r.m)
		if f > 0:
			_npay(f, "hand")
			r.cost += f
		for c in on:
			c.st = "move"
	if r.vid < 0 and i + 1 < r.stops.size():
		end = _part_dep(end, r.stops[i], r.stops[i + 1], r.m)
	r.t_dep = end
	r.st = "load"


func _npay(x: float, key: String) -> void:
	CO.cash -= x
	CO.m[key] = CO.m.get(key, 0.0) + x


## a leg leaves: an own vehicle through the ordinary trip (border checkpoints, incidents, the map), a partner
## carrier as a trip without own vehicles
func _run_leg(r: Dictionary) -> bool:
	var i: int = r.i
	var a: int = r.stops[i]
	var b: int = r.stops[i + 1]
	var cs := []
	for c in _run_cs(r):
		if c.st == "move":
			cs.append(c)
	var tons := 0.0
	var vol := 0.0
	var risk := 0.0
	for c in cs:
		tons += c.k.tons
		vol += _kv(c.k)
		risk = maxf(risk, c.k.risk)
	var kk := {"id": CO.uid, "from": a, "to": b, "cg": "parcel", "tons": maxf(.1, tons), "_vol": maxf(.1, vol), "pay": 0, "dlDays": 1e3, "mode": r.m, "risk": risk,
		"minR": 0, "len": 0.0, "net": r.id, "_one": true}
	CO.uid += 1
	var P: Variant
	if r.vid >= 0:
		var v: Variant = _veh(r.vid)
		if v == null:
			return false
		v.idle0 = co_now()
		kk._veh = [r.vid]   # the kept vehicle itself: the plan takes it
		var rv: Variant = net_leg_route(r.m, a, b, r.get("via", {}).get(i, []), r.get("av", ""))
		if rv == null:
			r.why = "Маршрут перекрито"
			return false
		P = lp_with(r.m + str(a) + ":" + str(b), rv, func(): return co_plan1(kk))   # the roads the player chose
		if not P.ok:
			r.why = P.why
			return false
	else:
		var rr: Variant = net_leg_route(r.m, a, b, r.get("via", {}).get(i, []), r.get("av", ""))
		if rr == null:
			r.why = "Маршрут перекрито"
			return false
		var tm: float = rr.len / (D.CH_SPD[r.m] * spd_k())
		var fee := net_part_fee(r.m, rr.len, cs, PL[a].cid != PL[b].cid)
		_npay(fee, "part")
		r.cost += fee
		P = {"ok": true, "t": NET_VT[r.m], "n": 1, "vids": [], "lead": 0.0, "leadR": {"p": PackedFloat32Array([rr.p[0], rr.p[1]]), "len": 0.0}, "main": rr,
			"tl": 0.0, "tm": tm, "hs": .02, "cust": 0.0, "tot": tm + .04, "fuel": 0.0, "profit": 0.0, "late": false}
	var c0: float = CO.m.fuel + CO.m.get("toll", 0.0)
	co_dispatch(kk, P, true)
	r.cost += CO.m.fuel + CO.m.get("toll", 0.0) - c0
	var j: Variant = null
	for x in CO.jobs:
		if is_same(x.k, kk):
			j = x
	if j == null:
		return false
	# handling is the terminal's work (done before and after): the trip itself only drives
	j.hs = .02
	if r.m == "sea" or r.m == "air":
		j.cust = (.3 if PL[a].cid != PL[b].cid else 0.0) * (.4 if n_up(a, "bond") else 1.0)
	var W := 0.0
	if j.get("stops"):
		for q in j.stops:
			if n_up(a, "bond"):
				q.w *= .3
			W += q.w
	j.tot = j.tl + j.tm + j.cust + .04 + W
	j.net = {"run": r.id, "leg": i, "n": cs.size()}
	r.st = "go"
	r.job = j.id
	r.why = ""
	var key := "%d:%d:%s" % [mini(a, b), maxi(a, b), r.m]
	CO.net.flow[key] = CO.net.flow.get(key, 0.0) + tons
	return true


## a leg of a run has arrived (or turned back, or the cargo is lost): the trip hook of co_complete
func net_job_done(j: Dictionary) -> void:
	_drop(CO.jobs, j)
	var r: Variant = null
	for x in CO.net.runs:
		if x.id == j.net.run:
			r = x
	var wear: float = {"road": 1.6, "rail": .5, "sea": .25, "air": .12}[j.mode] * [1.4, 1.0, .65][CO.maint]
	var back: bool = j.get("back", false) or j.get("cx0", false)
	var at: int = j.k.from if back else j.k.to
	for v in CO.veh:
		if j.vids.has(v.id):
			v.st = "idle"
			v.job = null
			v.loc = at
			v.idle0 = co_now()
			v.km += (j.lead + j.len) * D.KM
			v.cond = maxf(0, v.cond - (j.lead + j.len) * wear)
	if r == null:
		return
	var cs := []
	for c in _run_cs(r):
		if c.st == "move":
			cs.append(c)
	for c in cs:
		c.dmg = maxf(c.dmg, j.get("dmg", 0.0))
		c.hops += 1
	if j.lost:
		for c in cs:
			_fail(c, "втрачено в дорозі", true)
		_run_end(r, at)
		return
	if back:   # turned back: the cargo is unloaded where the leg began
		for c in cs:
			c.at = at
			c.run = -1
			if n_kind(at) != "" :
				c.st = "proc"
				c.rdy = n_handle(at, [c], r.m, co_now())
			else:
				c.st = "wait"
		co_news("warn", "", "%s: рейс повернувся в %s, вантажі чекають там" % [CO.name, PL[at].name])
		_run_end(r, at)
		return
	r.i += 1
	_arrive(r, co_now())


## at a stop: deliveries to this town, the cargo left here goes into the warehouse, then loading for the next leg
func _arrive(r: Dictionary, t: float) -> void:
	var i: int = r.i
	var pid: int = r.stops[i]
	var offl := []
	for c in _run_cs(r):
		if c.st == "move" and c.get("off_i", -1) == i:
			offl.append(c)
	var end := t
	if offl.size():
		var f := n_hfee(pid, offl, r.m)
		if f > 0:
			_npay(f, "hand")
			r.cost += f
		end = n_handle(pid, offl, r.m, t)
	for c in offl:
		c.at = pid
		c.run = -1
		c.since = co_now()
		if pid == c.k.to:
			_deliver(c, r)
		else:
			c.st = "proc"
			c.rdy = end
			c.erase("nh")
	if i >= r.stops.size() - 1:
		_run_end(r, pid)
		return
	# whatever was booked to be picked here and is no longer here is left out
	_load_at(r, i, end)


func _run_end(r: Dictionary, at: int) -> void:
	_drop(CO.net.runs, r)
	for c in CO.net.cs:
		if c.run == r.id:   # booked for a stop the run never reached
			c.run = -1
			if c.st == "move":
				c.st = "ready" if n_kind(c.at) != "" else "wait"
	if r.vid >= 0:
		var v: Variant = _veh(r.vid)
		if v != null:
			v.resv = null
			v.erase("nres")
			if v.st == "idle":
				v.loc = at
				v.idle0 = null if hub_at(at) != null else co_now()
	if r.get("line", -1) >= 0:
		for L in CO.net.lines:
			if L.id == r.line:
				L.last = {"d": day, "rev": r.rev, "cost": r.cost}


## the cargo is at its town: paid by its deadline and its state
func _deliver(c: Dictionary, r: Variant) -> void:
	var k: Dictionary = c.k
	var cg: Dictionary = cargo_i[k.cg]
	var late := maxf(0, co_now() - c.dl)
	var pay: float = k.pay * (maxf(.35, 1 - late * .12) if late > 0 else 1.0)
	if r != null and r.vid >= 0:   # brought by a vehicle made for it (a tanker for fuel, a reefer for food…): +20%
		var v: Variant = _veh(r.vid)
		if v != null and D.VT[v.t].get("fit", []).has(k.cg):
			pay *= 1.2
	var value: float = k.tons * cg.val
	var claim := 0.0
	if c.dmg > 0:
		claim = minf(value * minf(1, c.dmg) * .8, k.pay * 3 + 1500)
		pay *= 1 - minf(.8, c.dmg)
		if c.dmg > .08:
			CO.rating = JS.clamp_js(CO.rating - minf(.3, c.dmg * .6), 1, 5)
	pay = JS.round_js(pay)
	var covered := claim * .8 if CO.ins else 0.0
	CO.cash += pay - claim + covered
	CO.m[rev_key(k)] += pay
	CO.m.claims += claim - covered
	if r != null:
		r.rev += pay
	var s := 2.0 if late > 2 else (3.2 if late > 0 else (3.8 if c.dmg > .05 else 5.0))
	var w := minf(.05, .01 + JS.log10(1 + k.pay) * .005)
	CO.rating = JS.clamp_js(CO.rating + (s - CO.rating) * w, 1, 5)
	CO.cdel += 1
	CO.deliv += 1
	CO.tons += k.tons
	var xp := (10 + 5 * maxi(0, c.hops - 1) + 4 * JS.log2(1 + k.pay / 2000)) * (.5 if late > 0 else 1.0) * (.6 if c.dmg > .05 else 1.0) * (.6 if c.auto else 1.0)
	CO.xp = CO.get("xp", 0) + maxf(1, JS.round_js(xp)) * (5.0 if CO.get("fast") else 1.0)
	c.st = "done"
	_drop(CO.net.cs, c)
	_drop(CO.board, k)   # its card «Вантаж прийнято» leaves the board: the order is done
	CO.net.stat.done += 1
	_firm_note(c, late <= .25, pay)   # a few hours late still counts as on time for the business
	var tone := "warn" if late > 0 or c.dmg > .05 else "good"
	if late > 0:
		co_news(tone, "box", "%s: «%s» доставлено в %s із запізненням %.1f дн." % [CO.name, cg.n.to_lower(), PL[k.to].name, late])
	else:
		co_news(tone, "box", "%s: «%s» доставлено в %s" % [CO.name, cg.n.to_lower(), PL[k.to].name])
	_last({"d": date.duplicate(), "from": k.from, "to": k.to, "cg": k.cg, "pay": pay - claim + covered, "tone": tone, "mode": k.mode})


func _fail(c: Dictionary, why: String, lost: bool) -> void:
	var k: Dictionary = c.k
	var cg: Dictionary = cargo_i[k.cg]
	var pen := JS.round_js(k.pay * .3)
	var claim: float = minf(k.tons * cg.val * .6, k.pay * 4 + 3000) if lost else 0.0   # the shipper's own insurance pays the rest
	var covered: float = claim * .8 if CO.ins else 0.0
	CO.cash -= pen + claim - covered
	CO.m.claims += pen + claim - covered
	CO.rating = JS.clamp_js(CO.rating - (.2 if lost else .12), 1, 5)
	c.st = "fail"
	c.why = why
	_drop(CO.net.cs, c)
	_drop(CO.board, k)
	_firm_note(c, false, 0.0)
	CO.net.stat.fail += 1
	co_news("bad", "alert", "%s: «%s» %s → %s — %s, штраф %s" % [CO.name, cg.n.to_lower(), PL[k.from].name, PL[k.to].name, why, _usd(pen + claim - covered)])
	_nt({"tone": "bad", "t": "Вантаж втрачено" if lost else "Замовник забрав вантаж", "d": "%s → %s: %s" % [PL[k.from].name, PL[k.to].name, why]})


# ====================================================================== ready-made runs
## the cargo of a hub's area: towns nearer to this hub than to any other on the same land, not too far
func net_area(hub: int) -> Array:
	var H: Dictionary = PL[hub]
	var out := []
	for p in PL:
		if p.land != H.land or p.id == hub:
			continue
		var d := JS.hypot(p.x - H.x, p.z - H.z)
		if d > NET_AREA:
			continue
		var mine := true
		for h in CO.hubs:
			if h.pid != hub:
				var q: Dictionary = PL[h.pid]
				if q.land == p.land and JS.hypot(p.x - q.x, p.z - q.z) < d - 1e-6:
					mine = false
					break
		if mine:
			out.append(p.id)
	return out


## «Кільцевий рейс»: from the hub to the towns of its area — first the deliveries waiting in the warehouse
## (by deadline), on the way the pick-ups of cargo waiting in those towns, back to the hub. Nearest next; the
## load never over the vehicle
func net_auto_round(hub: int, vid: int, skip: Dictionary = {}) -> Dictionary:
	var v: Variant = _veh(vid)
	var spec := {"vid": vid, "stops": [hub], "picks": {}}
	if v == null:
		return spec
	var T: Dictionary = D.VT[v.t]
	var area := {}
	for p in net_area(hub):
		area[p] = true
	var dels: Array = CO.net.cs.filter(func(c): return c.at == hub and c.run < 0 and (c.st == "ready" or (c.st == "proc" and c.rdy - co_now() < .5)) and area.has(c.k.to) and not skip.has(c.id))
	_stable_sort(dels, func(a, b): return a.dl - b.dl)
	var load := 0.0
	var vol := 0.0
	var on0 := []
	for c in dels:
		if load + c.k.tons <= T.cap and vol + _kv(c.k) <= T.get("vol", 1e9):
			load += c.k.tons
			vol += _kv(c.k)
			on0.append(c)
	var pks: Array = CO.net.cs.filter(func(c): return c.st == "wait" and c.run < 0 and area.has(c.at) and not skip.has(c.id))
	_stable_sort(pks, func(a, b): return a.dl - b.dl)
	var todo := {}   # town → what to do there
	for c in on0:
		todo[c.k.to] = true
	for c in pks:
		todo[c.at] = true
	var cur: Dictionary = PL[hub]
	var stops := [hub]
	var picks := {0: on0.map(func(c): return c.id)}
	var onb: Array = on0.duplicate()
	var left: Dictionary = todo.duplicate()
	while left.size() and stops.size() < 9:
		var best := -1
		var bd := 1e9
		for pid in left:
			var d := JS.hypot(PL[pid].x - cur.x, PL[pid].z - cur.z)
			if d < bd:
				bd = d
				best = pid
		left.erase(best)
		stops.append(best)
		var si := stops.size() - 1
		onb = onb.filter(func(c): return c.k.to != best)
		load = 0.0
		vol = 0.0
		for c in onb:
			load += c.k.tons
			vol += _kv(c.k)
		var here := []
		for c in pks:
			if c.at == best and load + c.k.tons <= T.cap and vol + _kv(c.k) <= T.get("vol", 1e9):
				load += c.k.tons
				vol += _kv(c.k)
				here.append(c.id)
				onb.append(c)
		if here.size():
			picks[si] = here
		cur = PL[best]
	stops.append(hub)
	# a stop with nothing to do (its pick-up did not fit) is left out
	var keep := [0]
	for i in range(1, stops.size() - 1):
		var used: bool = picks.has(i)
		for j in picks:
			if j < i:
				for id in picks[j]:
					var c: Variant = _cs(id)
					if c != null and c.k.to == stops[i]:
						used = true
		if used:
			keep.append(i)
	keep.append(stops.size() - 1)
	var st2 := []
	var pk2 := {}
	for n in keep.size():
		st2.append(stops[keep[n]])
		if picks.has(keep[n]) and picks[keep[n]].size():
			pk2[n] = picks[keep[n]]
	spec.stops = st2
	spec.picks = pk2
	return spec


## «Магістральний рейс»: from a terminal to another by one kind of transport, with what should go that way, the
## nearest deadline first; back: the return leg brings what waits there for this terminal
func net_auto_trunk(a: int, b: int, m: String, vid: int, back: bool = false, skip: Dictionary = {}) -> Dictionary:
	return net_auto_multi(a, [b], m, vid, back, skip)


## a haul along several stops (way: the places after the start, in order; back: the run ends where it began).
## At every stop it takes what waits there for a later stop — its own town, its next step, or (at the last
## stop) a terminal that brings it nearer — the nearest deadline first, as long as every leg stays within the
## vehicle; each consignment gets off at the stop it is for
func net_auto_multi(a: int, way: Array, m: String, vid: int, back: bool = false, skip: Dictionary = {}) -> Dictionary:
	var stops: Array = [a] + way + ([a] if back and way.size() else [])
	var spec := {"vid": vid, "m": m, "stops": stops, "picks": {}, "offs": {}}
	# a route that ends at a town where the cargo picked up on the way is not for: the run goes on to the
	# nearest hub and leaves it there (the player may put a hub last instead)
	if way.size() and not back and n_kind(stops.back()) == "":
		var last: int = stops.back()
		var lose: bool = CO.net.cs.any(func(c): return c.run < 0 and c.st == "wait" and way.has(c.at) and not skip.has(c.id) \
			and not way.slice(way.find(c.at) + 1).has(c.k.to))
		if lose:
			var hb := net_near_hub(last, m)
			if hb >= 0 and hb != last:
				stops.append(hb)
				spec.auto_end = hb
	var cap := 1e9
	var cv := 1e9
	if vid >= 0:
		var v: Variant = _veh(vid)
		if v == null:
			return spec
		cap = D.VT[v.t].cap
		cv = D.VT[v.t].get("vol", 1e9)
	var n := stops.size()
	if n < 2:
		return spec
	var lt := []
	var lv := []
	for i in n - 1:
		lt.append(0.0)
		lv.append(0.0)
	var taken := {}
	for i in n - 1:
		var here: int = stops[i]
		var L: Array = CO.net.cs.filter(func(c): return c.at == here and c.run < 0 and not taken.has(c.id) and not skip.has(c.id) and (c.st == "ready" or c.st == "wait" or (c.st == "proc" and c.rdy - co_now() < 1)))
		_stable_sort(L, func(x, y): return x.dl - y.dl)
		for c in L:
			var off := -1
			for j in range(i + 1, n):
				if stops[j] == c.k.to:
					off = j
					break
			if off < 0:
				var nx: Variant = net_next(c)
				if nx != null:
					for j in range(i + 1, n):
						if stops[j] == nx.b and n_kind(stops[j]) != "":
							off = j
							break
			# the run ends at a hub or a terminal: cargo picked up at a shipper's on the way is taken there whatever
			# its way (that is where the player chose to bring it); cargo already in a warehouse only if it gets nearer
			if off < 0 and stops[n - 1] != here and n_kind(stops[n - 1]) != "" and (c.st == "wait" or _goes(c, stops[n - 1], m)):
				off = n - 1
			if off < 0:
				continue
			var fits := true
			for q in range(i, off):
				if lt[q] + c.k.tons > cap + 1e-6 or lv[q] + _kv(c.k) > cv + 1e-6:
					fits = false
					break
			if not fits:
				continue
			for q in range(i, off):
				lt[q] += c.k.tons
				lv[q] += _kv(c.k)
			taken[c.id] = true
			if not spec.picks.has(i):
				spec.picks[i] = []
			spec.picks[i].append(c.id)
			spec.offs[c.id] = off
	return spec


## the own hub nearest to a place that this kind of transport reaches from it
func net_near_hub(pid: int, m: String) -> int:
	var P: Dictionary = PL[pid]
	var best := -1
	var bd := 1e9
	for h in CO.hubs:
		var q: Dictionary = PL[h.pid]
		if not node_ok(m, q) or ((m == "road" or m == "rail") and q.land != P.land):
			continue
		var d := JS.hypot(q.x - P.x, q.z - P.z)
		if d < bd and (h.pid == pid or co_route(m, pid, h.pid) != null):
			bd = d
			best = h.pid
	return best


## where a haul from `a` could also stop on the way: the towns and next steps of the cargo waiting at the start
## and at the stops already chosen, the towns near the way where cargo waits for a pick-up, the hubs. Each with
## what it is for, the tons and how much longer the way gets with it (inserted where it costs the least)
func net_way_cands(a: int, way: Array, m: String, back: bool) -> Array:
	var A: Dictionary = PL[a]
	var at := {a: true}
	for p in way:
		at[p] = true
	var c2 := {}   # place → {to: tons for that town, nx: tons that go on from there, pick: tons waiting there}
	var add := func(pid: int, key: String, t: float) -> void:
		if pid == a or not node_ok(m, PL[pid]) or ((m == "road" or m == "rail") and PL[pid].land != A.land):
			return
		if not c2.has(pid):
			c2[pid] = {"to": 0.0, "nx": 0.0, "pick": 0.0, "n": 0}
		c2[pid][key] += t
		c2[pid].n += 1
	for c in CO.net.cs:
		if c.run >= 0 or c.st == "move":
			continue
		if at.has(c.at):
			add.call(c.k.to, "to", c.k.tons)
			var nx: Variant = net_next(c)
			if nx != null and nx.m == m and nx.b != c.k.to and n_kind(nx.b) != "":
				add.call(nx.b, "nx", c.k.tons)
		elif c.st == "wait" and m == "road":
			var P: Dictionary = PL[c.at]
			for q in at:
				if JS.hypot(PL[q].x - P.x, PL[q].z - P.z) < 1.6:
					add.call(c.at, "pick", c.k.tons)
					break
	for h in CO.hubs:
		if not c2.has(h.pid) and h.pid != a and node_ok(m, PL[h.pid]) and ((m != "road" and m != "rail") or PL[h.pid].land == A.land):
			c2[h.pid] = {"to": 0.0, "nx": 0.0, "pick": 0.0, "n": 0}
	var out := []
	for pid in c2:
		if at.has(pid):
			continue
		var ins := net_way_insert(a, way, pid, back)
		out.append({"pid": pid, "to": c2[pid].to, "nx": c2[pid].nx, "pick": c2[pid].pick, "n": c2[pid].n, "det": ins.det, "way": ins.way})
	out.sort_custom(func(x, y): return (x.to + x.nx + x.pick) / (1 + x.det * 4) > (y.to + y.nx + y.pick) / (1 + y.det * 4))
	return out


## the way with a place put where it lengthens it the least; det: the extra length against the way (0.1 = 10%)
func net_way_insert(a: int, way: Array, pid: int, back: bool) -> Dictionary:
	var pts: Array = [a] + way + ([a] if back else [])
	var d := func(x: int, y: int) -> float: return JS.hypot(PL[x].x - PL[y].x, PL[x].z - PL[y].z)
	var tot := 0.0
	for i in range(1, pts.size()):
		tot += d.call(pts[i - 1], pts[i])
	var best := -1
	var bd := 1e18
	for i in range(1, pts.size()):
		var e: float = d.call(pts[i - 1], pid) + d.call(pid, pts[i]) - d.call(pts[i - 1], pts[i])
		if e < bd:
			bd = e
			best = i
	if not back:   # or at the end
		var e: float = d.call(pts.back(), pid)
		if e < bd:
			bd = e
			best = pts.size()
	var w2: Array = way.duplicate()
	w2.insert(clampi(best - 1, 0, w2.size()), pid)
	return {"way": w2, "det": bd / maxf(.5, tot)}


## «Попутні зупинки»: the stops the cargo is for, added one by one while they are worth the detour (up to six)
func net_way_auto(a: int, way: Array, m: String, back: bool) -> Array:
	var w: Array = way.duplicate()
	while w.size() < 6:
		var cs := net_way_cands(a, w, m, back)
		var best: Variant = null
		for x in cs:
			var t: float = x.to + x.nx + x.pick
			if t <= 0:
				continue
			if w.is_empty() or x.det < .35:
				best = x
				break
		if best == null:
			break
		w = best.way
	return w


## does a consignment want to go from where it is to `b` (by `m`)? Its next step there, or its own town, or
## a step that brings it nearer to its town than it is now
func _goes(c: Dictionary, b: int, m: String) -> bool:
	if c.k.to == b:
		return true
	var L: Variant = net_next(c)
	if L != null and L.b == b:
		return true
	var A: Dictionary = PL[c.at]
	var B: Dictionary = PL[b]
	var Z: Dictionary = PL[c.k.to]
	return L == null and JS.hypot(Z.x - B.x, Z.z - B.z) < JS.hypot(Z.x - A.x, Z.z - A.z) * .6


## the vehicles that can start a run at a place now
func net_idle_at(pid: int, m: String = "") -> Array:
	return CO.veh.filter(func(v): return v.st == "idle" and v.loc == pid and not v.get("resv") and (m == "" or D.VT[v.t].mode == m) and D.VT[v.t].mode != "local")


## for a consignment waiting in a town: the hubs on its land with a free road vehicle, the nearest first
func net_pick_from(c: Dictionary) -> Array:
	var P: Dictionary = PL[c.at]
	var hs: Array = CO.hubs.filter(func(h): return PL[h.pid].land == P.land and net_idle_at(h.pid, "road").size())
	_stable_sort(hs, func(a, b): return JS.hypot(PL[a.pid].x - P.x, PL[a.pid].z - P.z) - JS.hypot(PL[b.pid].x - P.x, PL[b.pid].z - P.z))
	return hs.map(func(h): return h.pid)


# ====================================================================== lines
## a line: a run made again on a schedule. kind "round" (a hub's area) or "trunk" (a → b by m, back optional);
## every: days; fill: the least share of the vehicle to go (a consignment that would be late goes anyway)
func net_line_add(L: Dictionary) -> Dictionary:
	L.id = CO.net.uid
	CO.net.uid += 1
	L.next = day + 1 if not L.has("next") else L.next
	L.on = true
	L.last = {}
	CO.net.lines.append(L)
	return _toast("good", "Лінію створено", "%s · кожні %d дн." % [net_line_name(L), L.every])


func net_line_name(L: Dictionary) -> String:
	if L.kind == "round":
		return "Кільце %s" % PL[L.a].name
	if L.get("every", 1) == 0:
		return "Чекає заповнення: %s → %s" % [PL[L.a].name, " → ".join(L.get("way", [L.b]).map(func(p): return PL[p].name))]
	var way: Array = L.get("way", [L.b])
	return "%s → %s%s" % [PL[L.a].name, " → ".join(way.map(func(p): return PL[p].name)), " → " + PL[L.a].name if L.get("back") else ""]


func net_line_del(id: int) -> void:
	CO.net.lines = CO.net.lines.filter(func(L): return L.id != id)


func _lines_day() -> void:
	CO.net.lines = CO.net.lines.filter(func(L): return not L.get("done", false))
	for L in CO.net.lines:
		if not L.on or day < L.next:
			continue
		var vid: int = L.get("vid", -1)
		if vid >= 0:
			var v: Variant = _veh(vid)
			if v == null:
				L.on = false
				co_news("warn", "", "Лінію «%s» зупинено: техніки більше немає" % net_line_name(L))
				continue
			if v.st != "idle" or v.get("resv") or v.loc != L.a:
				L.why = "техніка ще в рейсі" if v.st != "idle" else ("стоїть у місті %s" % PL[v.loc].name)
				if v.st == "idle" and not v.get("resv") and v.loc != L.a and hub_at(v.loc) != null:   # bring it to the line's start
					var r: Variant = co_route(D.VT[v.t].mode, v.loc, L.a)
					if r != null:
						_ret_trip(v, L.a, r)
				L.next = day + 1
				continue
		var spec: Dictionary = net_auto_round(L.a, vid) if L.kind == "round" else net_auto_multi(L.a, L.get("way", [L.b]), L.m, vid, L.get("back", false))
		spec.line = L.id
		spec.via = L.get("via", {})
		spec.av = L.get("av", "")
		var C := net_calc(spec)
		var urgent := false
		for row in C.rows:
			if row.c.dl - co_now() < C.t + 1.5:
				urgent = true
		var fill: float = C.fill if vid >= 0 else C.tons / 40.0
		if L.every == 0 and not C.ok and L.get("waited", 0) >= 5:   # a run waiting for a load that never came
			L.done = true
			co_news("warn", "", "Рейс %s скасовано: вантажу так і не назбиралося" % net_line_name(L).trim_prefix("Чекає заповнення: "))
			continue
		if not C.ok or (fill < L.fill and not urgent and L.get("waited", 0) < maxi(L.every, 5)):
			L.why = C.why if not C.ok else "чекає вантажу: заповнення %d%%" % int(fill * 100)
			L.waited = L.get("waited", 0) + 1
			L.next = day + 1
			continue
		L.waited = 0
		L.why = ""
		net_go(spec, true)
		L.next = day + L.every
		if L.every == 0:   # a run waiting for its load: once, then gone
			L.on = false
			L.done = true


# ====================================================================== the day, the frame, the month
## a leg of a run with nothing on board (on its way to where it loads) is an empty run, not «з вантажем»
func co_job_state(j: Dictionary, e: float) -> Dictionary:
	var st := super(j, e)
	if j.get("net") != null and int(j.net.get("n", 1)) == 0 and not j.get("ret", false) and st.get("inc") == null \
			and (st.ph == "У дорозі з вантажем" or st.ph == "Завантаження" or st.ph == "Розвантаження"):
		st.ph = "Порожній перегін до %s" % PL[j.k.to].name
	return st


func co_frame(fr: float) -> void:
	super.co_frame(fr)
	if alt():
		net_frame(day + fr)


func net_frame(T: float) -> void:
	for c in CO.net.cs:
		if c.st == "proc" and T >= c.rdy:
			c.st = "ready"
	for r in CO.net.runs.duplicate():
		if r.st == "load" and T >= r.t_dep:
			var cs := _run_cs(r).filter(func(c): return c.st == "move")
			if cs.is_empty() and r.i >= r.stops.size() - 2:   # nothing on board and nothing to pick on the way
				_run_end(r, r.stops[r.i])
				continue
			if not _run_leg(r):
				r.t_dep = T + .25
				if not r.get("warned"):
					r.warned = true
					co_news("warn", "", "Рейс із %s чекає: %s" % [PL[r.stops[r.i]].name, r.get("why", "")])


## a vehicle kept for a run, standing at a stop, is not sent home
func co_returns() -> void:
	if alt():
		for v in CO.veh:
			if v.get("nres") != null and v.st == "idle":
				v.idle0 = co_now()
	super.co_returns()


func co_complete(j: Dictionary) -> void:
	if j.get("net") != null and alt():
		net_job_done(j)
		return
	super.co_complete(j)


func _auto0(st: Dictionary) -> void:
	if alt():   # the network has lines, not the dispatcher of the board
		st.stage = "returns"
		return
	super._auto0(st)


func co_day_begin() -> Dictionary:
	var st := super.co_day_begin()
	if alt() and not over:
		net_day()
	return st


func co_rev(m: Variant) -> float:
	return super.co_rev(m) + (m.get("transit", 0.0) if m != null else 0.0)


func co_cost(m: Variant) -> float:
	if m == null:
		return 0.0
	return super.co_cost(m) + m.get("store", 0.0) + m.get("hand", 0.0) + m.get("part", 0.0)


func net_day() -> void:
	var now := co_now()
	# closed hubs: their terminals go, the cargo there waits for a pick-up
	for key in CO.net.term.keys():
		if hub_at(int(key)) == null:
			CO.net.term.erase(key)
	for h in CO.hubs:
		_T(h.pid)
	# storage: by the ton and day, partners dearer, over the capacity dearer still; food spoils without cold
	var store := 0.0
	var near := []   # deadlines close for cargo still not on its way: one toast for all of them
	var ovr := {}
	for h in CO.hubs:
		ovr[h.pid] = n_stored(h.pid) > n_cap(h.pid)
	for c in CO.net.cs.duplicate():
		if (c.st == "ready" or c.st == "proc") and not c.k.get("sea"):   # a shipload waits at the quay, free
			var k := n_kind(c.at)
			if k == "hub":
				store += c.k.tons * 2 * price_k(PL[c.at].cid) * (3.0 if ovr.get(c.at, false) else 1.0)
				if cargo_i[c.k.cg].get("reefer") and not n_up(c.at, "cold") and now - c.since > 1.5:
					c.dmg = minf(1, c.dmg + .05)
					if not c.get("spoilW"):
						c.spoilW = true
						co_news("warn", "leaf", "%s: «%s» псується на складі без холодильної камери" % [PL[c.at].name, cargo_i[c.k.cg].n.to_lower()])
			elif k == "part":
				store += c.k.tons * 6 * price_k(PL[c.at].cid)
			else:
				c.st = "wait"
		# the shipper's patience
		if c.run < 0 and c.st != "move" and day > c.dl + NET_LATE_MAX:
			_fail(c, "запізнення понад %d дн." % int(NET_LATE_MAX), false)
		elif c.run < 0 and day > c.dl - 1.5 and not c.get("lateW"):
			c.lateW = true
			near.append(c)
	if near.size():
		var c: Dictionary = near[0]
		if near.size() > 1:
			_nt({"tone": "warn", "t": "Дедлайн близько: %d вантажів" % near.size(), "d": "Перший — %s → %s, ще в місті %s. Решта — у вікні «Прийняті вантажі»." % [PL[c.k.from].name, PL[c.k.to].name, PL[c.at].name]})
		else:
			_nt({"tone": "warn", "t": "Дедлайн близько", "d": "%s → %s: вантаж ще в місті %s" % [PL[c.k.from].name, PL[c.k.to].name, PL[c.at].name]})
	if store > 0:
		_npay(JS.round_js(store), "store")
	# the terminals: events, partner freight
	for h in CO.hubs:
		var T: Dictionary = _T(h.pid)
		T.ev = T.ev.filter(func(e): return e.until > now)
		_term_events(h, T)
		var part: int = int(T.part)
		if part > 0:
			var p: Dictionary = PL[h.pid]
			var tons: float = 3.0 * h.lvl * (1 + T.mods.size() * 1.2) * (.5 if part == 1 else 1.0) * sqrt(maxf(.2, p.pop)) * (0.0 if n_ev(h.pid, "strike") != null else 1.0)
			var inc: float = JS.round_js(tons * (5 + 9 * T.mods.size()) * price_k(p.cid))
			CO.cash += inc
			CO.m.transit = CO.m.get("transit", 0.0) + inc
			CO.net.stat.part_t += tons
			CO.net.stat.part_rev += inc
	for key in CO.net.flow.keys():
		CO.net.flow[key] *= .93
		if CO.net.flow[key] < .2:
			CO.net.flow.erase(key)
	_contracts_day()
	_lines_day()


func _term_events(h: Dictionary, T: Dictionary) -> void:
	var p: Dictionary = PL[h.pid]
	var now := co_now()
	var busy: bool = n_stored(h.pid) > 0 or T.q > now
	var add := func(k: String, d: float, txt: String) -> void:
		T.ev.append({"k": k, "until": now + d})
		co_news("bad", NET_EV[k][1], "%s, %s: %s" % [NET_EV[k][0], p.name, txt])
		_nt({"tone": "warn", "t": NET_EV[k][0], "d": "%s: %s" % [p.name, txt]})
	if n_ev(h.pid, "strike") == null and busy and RX.next() < .0025 * (3.0 if CO.morale < 45 else 1.0) * (1 - .6 * msk("hro")):
		var d := 2 + RX.next() * 3
		add.call("strike", d, "термінал стоїть %.0f дн." % d)
	if n_up(h.pid, "crane") and n_ev(h.pid, "crane") == null and busy and RX.next() < .006 * (.6 if has_u("pred") else 1.0):
		var d := 2 + RX.next() * 2
		add.call("crane", d, "пропускна здатність удвічі менша %.0f дн." % d)
	if T.mods.has("sea") and n_ev(h.pid, "congest") == null and RX.next() < .005:
		var d := 3 + RX.next() * 3
		add.call("congest", d, "перевалка повільніша %.0f дн." % d)
	if n_up(h.pid, "bond") and RX.next() < .012:
		var L: Array = CO.net.cs.filter(func(c): return c.at == h.pid and (c.st == "ready" or c.st == "proc") and PL[c.k.from].cid != PL[c.k.to].cid)
		if L.size():
			var c: Dictionary = L[int(RX.next() * L.size())]
			var d := 1 + RX.next() * 2
			c.st = "proc"
			c.rdy = maxf(c.get("rdy", now), now) + d
			co_news("warn", "gavel", "Митна перевірка в %s: «%s» затримано на %.0f дн." % [p.name, cargo_i[c.k.cg].n.to_lower(), d])
	# theft from the warehouse: the more is stored there and the riskier the country, the likelier
	var val := 0.0
	var L2: Array = CO.net.cs.filter(func(c): return c.at == h.pid and (c.st == "ready" or c.st == "proc"))
	for c in L2:
		val += c.k.tons * cargo_i[c.k.cg].val
	if L2.size() and RX.next() < minf(.005, val / 2e7 * co_risk(p.cid)) * (1 - .7 * msk("cso")):
		var c: Dictionary = L2[int(RX.next() * L2.size())]
		_fail(c, "викрадено зі складу в місті %s" % p.name, true)


func co_month() -> void:
	super.co_month()
	if not alt():
		return
	var x := 0.0
	for h in CO.hubs:
		var T: Dictionary = _T(h.pid)
		if n_up(h.pid, "shift"):
			x += 3000 * price_k(PL[h.pid].cid)
		for m in T.mods:
			for M in NET_MODS:
				if M.id == m:
					x += M.cost * .01 * price_k(PL[h.pid].cid)
	if x > 0:
		_npay(JS.round_js(x), "rent")


# ====================================================================== terminal actions
func net_mod_cost(pid: int, id: String) -> float:
	for M in NET_MODS:
		if M.id == id:
			return JS.round_js(M.cost * price_k(PL[pid].cid))
	return 0.0


func net_up_cost(pid: int, id: String) -> float:
	for U in NET_UPS:
		if U.id == id:
			var lv := n_up(pid, id)
			return JS.round_js(U.cost[lv] * price_k(PL[pid].cid)) if lv < U.cost.size() else -1.0
	return -1.0


func act_net_mod(pid: int, id: String) -> Dictionary:
	var T: Variant = net_term(pid)
	if T == null or T.mods.has(id):
		return {}
	if not mode_ok(id, PL[pid]):
		return _toast("warn", "Немає інфраструктури", "У місті %s немає %s" % [PL[pid].name, {"rail": "залізничної станції", "sea": "порту", "air": "аеропорту"}[id]])
	var c := net_mod_cost(pid, id)
	if CO.cash < c:
		return _toast("warn", "Бракує грошей", usd_s(c))
	CO.cash -= c
	T.mods[id] = 1
	var n := ""
	for M in NET_MODS:
		if M.id == id:
			n = M.n
	co_news("good", "building", "%s: %s у місті %s" % [CO.name, n.to_lower(), PL[pid].name])
	return _toast("good", n, PL[pid].name)


func act_net_up(pid: int, id: String) -> Dictionary:
	var T: Variant = net_term(pid)
	if T == null:
		return {}
	var c := net_up_cost(pid, id)
	if c < 0:
		return {}
	if CO.cash < c:
		return _toast("warn", "Бракує грошей", usd_s(c))
	CO.cash -= c
	T.up[id] = n_up(pid, id) + 1
	var n := ""
	for U in NET_UPS:
		if U.id == id:
			n = U.n
	return _toast("good", n, PL[pid].name)


func act_net_part(pid: int, lv: int) -> void:
	var T: Variant = net_term(pid)
	if T != null:
		T.part = clampi(lv, 0, 2)


# ====================================================================== small helpers
func _nt(d: Dictionary) -> void:
	var t: Array = get("toasts")
	t.append(d)


func _kv(k: Dictionary) -> float:
	var cg: Variant = cargo_i.get(k.cg)
	return JS.fixed1(k.tons * (cg.v if cg != null and cg.get("v", 0) else 3))


## a step of the board in the alternative balance: more attempts a day (consolidation needs freight)
func _board1(st: Dictionary) -> bool:
	if not alt():
		return super._board1(st)
	if st.a < 0:
		var mx: int = st.mx
		if not (st.i < maxi(4, int(ceil(mx / 3.0))) and net_board_n() < mx):
			_gen_pre = {}
			return false
		st.i += 1
		if not chance(.8):
			return true
		st.a = 0
	var k: Variant = co_gen()
	st.a += 1
	if k != null:
		CO.board.append(k)
		st.a = -1
	elif st.a >= 5:
		st.a = -1
	return true



# ====================================================================== contracts with shippers
## Every consignment delivered for a business is remembered (CO.net.firms: by its town and name, its lanes —
## where to, how many, tons, pay, cargo). Each business has its own terms, hidden from the player: so many good
## deliveries (on time, undamaged — 7 to 15, drawn once), none damaged, and the company's rating above its own bar
## (3 to 5). The player may propose a contract from the first day — the business accepts once its terms are met
## and refuses otherwise, saying no more; a business whose terms are met may offer one itself now and then.
## A contract: for a few months it ships on a schedule — every few days a
## consignment appears at its town on its own, at a fixed pay, a little above the board's. Lines whose stops it
## lies on carry it like any other cargo. A missed or late shipment counts against the contract; three and the
## business ends it. A clean contract is offered again when it ends.

const CTR_NEED := [7, 15]   # the good deliveries a business wants before a contract (its own number in between)
const CTR_RATE := [3.0, 5.0]   # the company's rating it wants (its own bar in between)


static func firm_key(pid: int, name: String) -> String:
	return "%d|%s" % [pid, name]


func _nets() -> Dictionary:
	for k in ["firms", "ctr", "coff"]:
		if not CO.net.has(k):
			CO.net[k] = {} if k == "firms" else []
	return CO.net


func _firm_note(c: Dictionary, ok: bool, pay: float) -> void:
	var k: Dictionary = c.k
	var N := _nets()
	if k.get("ctr") != null:   # a shipment of a contract
		for C in N.ctr:
			if C.id == k.ctr:
				if ok:
					C.ok += 1
				else:
					C.miss += 1
					if C.miss >= 3:
						_ctr_end(C, "три зриви поставок")
		return
	if not k.get("fs"):
		return
	var F := _firm(k.from, k.fs)
	if ok:
		F.ok += 1
	else:
		F.late += 1
	if pay > 0 and c.get("dmg", 0.0) > .05:
		F.dmg = F.get("dmg", 0) + 1
	elif ok:
		F.good = F.get("good", 0) + 1
	var lk := str(k.to)
	var L: Dictionary = F.lanes.get(lk, {"n": 0, "pay": 0.0, "tons": 0.0, "cg": {}})
	L.n += 1
	L.pay += k.pay
	L.tons += k.tons
	L.cg[k.cg] = L.cg.get(k.cg, 0) + 1
	F.lanes[lk] = L


## a business's record (made on its first delivery or proposal), with its own hidden terms for a contract
func _firm(pid: int, name: String) -> Dictionary:
	var N := _nets()
	var key := firm_key(pid, name)
	var F: Dictionary = N.firms.get(key, {})
	if F.is_empty():
		F = {"n": name, "at": pid, "ok": 0, "late": 0, "lanes": {}, "off": -999.0}
		N.firms[key] = F
	if not F.has("need"):   # drawn once (a record from an older save gets its terms now)
		F.need = CTR_NEED[0] + int(RX.next() * (CTR_NEED[1] - CTR_NEED[0] + 1))
		F.rmin = JS.fixed1(CTR_RATE[0] + RX.next() * (CTR_RATE[1] - CTR_RATE[0]))
		F.good = F.get("good", F.ok)
		F.dmg = F.get("dmg", 0)
	return F


## whether a business would sign: its good deliveries, none damaged, the company's rating (its hidden terms)
func ctr_ready(key: String) -> bool:
	var F: Variant = _nets().firms.get(key)
	if F == null or not F.has("need"):
		return false
	return F.good >= F.need and F.dmg == 0 and CO.rating >= F.rmin


## the terms a business would sign: its busiest lane, its usual cargo and load, every few days (the more it
## ships with you, the oftener), a pay per shipment a little above its average on the board
func ctr_terms(key: String, premium: float = 1.08) -> Variant:
	var F: Variant = _nets().firms.get(key)
	if F == null or F.lanes.is_empty():
		return null
	var best := ""
	for lk in F.lanes:
		if best == "" or F.lanes[lk].n > F.lanes[best].n:
			best = lk
	var L: Dictionary = F.lanes[best]
	var cg := ""
	for x in L.cg:
		if cg == "" or L.cg[x] > L.cg[cg]:
			cg = x
	var to := int(best)
	var tons: float = JS.fixed1(L.tons / L.n)
	var ref: Variant = net_ref(PL[F.at], PL[to], tons)
	if ref == null:
		return null
	var ln := 0.0
	for x in ref.legs:
		ln += x.len
	return {"key": key, "firm": F.n, "from": F.at, "to": to, "cg": cg, "tons": tons, "pay": JS.round_js(L.pay / L.n * premium),
		"every": clampi(7 - int(F.ok / 4), 3, 7), "months": 3, "dl": JS.fixed1(maxf(2.0, ref.t * 2.2 + 1.5)), "len": ln, "mode": ref.m}


func ctr_has(key: String) -> bool:
	var N := _nets()
	return N.ctr.any(func(C): return C.key == key) or N.coff.any(func(O): return O.key == key)


## «Запропонувати контракт» (on a board card, from the first day): the business accepts once its hidden terms are
## met, at a pay a little lower than its own offer would be, and refuses otherwise — without saying why
func act_ctr_ask(pid: int, name: String) -> Dictionary:
	var key := firm_key(pid, name)
	if name == "" or ctr_has(key):
		return {}
	var F := _firm(pid, name)
	var T: Variant = ctr_terms(key, 1.0) if ctr_ready(key) else null
	if T == null:
		return _toast("warn", "Партнер відхилив вашу пропозицію контракту", F.n)
	return _ctr_start(T, "Партнер прийняв вашу пропозицію")


func act_ctr_take(oid: int) -> Dictionary:
	var N := _nets()
	for O in N.coff:
		if O.id == oid:
			N.coff.erase(O)
			return _ctr_start(O)
	return {}


func act_ctr_decline(oid: int) -> void:
	var N := _nets()
	N.coff = N.coff.filter(func(O): return O.id != oid)


func act_ctr_end(cid: int) -> Dictionary:
	for C in _nets().ctr:
		if C.id == cid:
			_ctr_end(C, "розірвано вами")
			CO.rating = JS.clamp_js(CO.rating - .1, 1, 5)
			return _toast("warn", "Контракт розірвано", "%s · рейтинг −0.1" % C.firm)
	return {}


func _ctr_start(T: Dictionary, title: String = "Контракт укладено") -> Dictionary:
	var C := T.duplicate()
	C.id = CO.net.uid
	CO.net.uid += 1
	C.next = day + 1
	C.until = day + T.months * 30
	C.ok = 0
	C.miss = 0
	C.sent = 0
	_nets().ctr.append(C)
	co_news("good", "handshake", "%s уклала контракт із %s: %s → %s, кожні %d дн." % [CO.name, C.firm, PL[C.from].name, PL[C.to].name, C.every])
	return _toast("good", title, "%s: %s → %s · кожні %d дн. · %s за поставку" % [C.firm, PL[C.from].name, PL[C.to].name, C.every, usd_s(C.pay)])


func _ctr_end(C: Dictionary, why: String) -> void:
	var N := _nets()
	N.ctr.erase(C)
	if N.firms.has(C.key):
		N.firms[C.key].off = day   # some time before the next offer
	co_news("warn" if why != "строк завершився" else "good", "handshake", "Контракт із %s завершено: %s" % [C.firm, why])
	_nt({"tone": "warn" if why != "строк завершився" else "good", "t": "Контракт завершено", "d": "%s: %s" % [C.firm, why]})


func _contracts_day() -> void:
	var N := _nets()
	N.coff = N.coff.filter(func(O): return O.exp > day)
	for C in N.ctr.duplicate():
		if day >= C.until:
			var clean: bool = C.miss == 0 and C.ok > 0
			_ctr_end(C, "строк завершився")
			if clean:   # served well: offered again
				var T: Variant = ctr_terms(C.key)
				if T != null:
					_offer(T)
			continue
		if day >= C.next:   # a shipment on the schedule
			var k := {"id": CO.uid, "from": C.from, "to": C.to, "cg": C.cg, "tons": C.tons, "pay": C.pay, "dlDays": C.dl, "mode": C.mode, "risk": 0.3,
				"minR": 0, "len": C.len, "net": 1, "fs": C.firm, "ft": "", "ctr": C.id, "exp": day}
			CO.uid += 1
			_take(k)
			C.sent += 1
			C.next = day + C.every
	# a business whose terms are met offers a contract itself (now and then, not twice at once)
	for key in N.firms:
		var F: Dictionary = N.firms[key]
		if day - F.off > 30 and not ctr_has(key) and ctr_ready(key) and RX.next() < .2:
			var T: Variant = ctr_terms(key)
			if T != null:
				_offer(T)


func _offer(T: Dictionary) -> void:
	var O := T.duplicate()
	O.id = CO.net.uid
	CO.net.uid += 1
	O.exp = day + 7
	_nets().coff.append(O)
	co_news("good", "handshake", "%s пропонує контракт: %s → %s, кожні %d дн." % [O.firm, PL[O.from].name, PL[O.to].name, O.every])
	_nt({"tone": "good", "t": "Пропозиція контракту", "d": "%s: %s → %s · кожні %d дн. · %s за поставку. Прийняті вантажі → Контракти" % [O.firm, PL[O.from].name, PL[O.to].name, O.every, usd_s(O.pay)]})



# ====================================================================== industries: refineries, shiploads
## crude oil: no truck takes a tanker's worth of it — a cargo of its own, shipped between ports
const NET_CARGO := [{"id": "crude", "n": "Сира нафта", "ic": "barrel", "t": [2000, 40000], "k": .7, "fr": .01, "val": 450, "v": 1.2, "dg": 1}]
const SEA_LOTS := ["crude", "fuel", "grain", "cars", "cont", "metal", "gas", "rcont"]
const SEA_RATE := 45.0   # what a shipload pays, $ for a ton over a unit of the way: enough for an own ship to pay off


func setup(gen_: Object, seed_: int, states_: Array, board_: Dictionary, world: Dictionary = {}) -> void:
	super.setup(gen_, seed_, states_, board_, world)
	for c in NET_CARGO:
		cargo_i[c.id] = c


## the towns with a refinery: a few large inland towns on lands that have a port (fixed for the world)
func net_refineries() -> Array:
	var ports := {}
	for p in PL:
		if p.port != null:
			ports[p.land] = true
	var out := []
	for p in PL:
		if p.port == null and ports.has(p.land) and (p.type == "cap" or p.type == "big" or p.type == "city") \
			and ((p.id * 2654435761 + seed_value * 97) & 0xFFFF) % 5 == 0:
			out.append(p.id)
	return out


func refinery_name(pid: int) -> String:
	var r := Mulberry.new((seed_value * 131 + pid * 977 + 12345) & 0xFFFFFFFF)
	var nm := _firm_name("energy", r)
	var q := nm.find("«")
	if q >= 0:   # the name without its legal form and quotes
		nm = nm.substr(q + 1)
	return "НПЗ «%s»" % nm.trim_suffix("»")


## a refinery's fuel: a tanker load to the nearest port on its land (the consignee: the port's terminal)
func _gen_refinery() -> Variant:
	var refs := net_refineries().filter(func(pid): return co_scope(PL[pid]) and not in_conf(PL[pid].cid))
	if refs.is_empty():
		return null
	var A: Dictionary = PL[refs[int(R.next() * refs.size())]]
	var B: Variant = _near_t(A, "sea")
	if B == null or B.id == A.id or not co_scope(B):
		return null
	var tons: float = JS.round_js(rnd(8, 25))
	var ref: Variant = net_ref(A, B, tons)
	if ref == null:
		return null
	var k: Dictionary = _net_order(A, B, cargo_i["fuel"], tons, ref, rnd(1.1, 1.25))
	k.fs = refinery_name(A.id)
	k.ft = "Нафтотермінал порту %s" % B.name
	k.refy = 1
	return k


## a shipload between continents (from the sea licence): grain, oil and fuel, metal, cars, containers —
## thousands of tons from a port to a port that only a ship can take
func _gen_sea() -> Variant:
	var ports := PL.filter(func(p): return p.port != null and co_scope(p) and not in_conf(p.cid))
	if ports.size() < 2:
		return null
	var A: Dictionary = ports[int(R.next() * ports.size())]
	var far := ports.filter(func(p): return p.land != A.land)
	if far.is_empty():
		return null
	var B: Dictionary = far[int(R.next() * far.size())]
	var r: Variant = co_route("sea", A.id, B.id)
	if r == null:
		return null
	var ids: Array = SEA_LOTS
	# a refinery's port ships fuel and oil more often
	var near_ref := net_refineries().any(func(pid): return PL[pid].land == A.land)
	var cid: String = ("crude" if R.next() < .5 else "fuel") if near_ref and R.next() < .45 else ids[int(R.next() * ids.size())]
	# more than partners' ships take: a container ship's load, a bulk carrier's with the global licence
	var hi: float = 28000.0 if CO.tier >= 7 else 6000.0
	var tons: float = JS.round_js(2500.0 * JS.pow(hi / 2500.0, JS.pow(R.next(), 1.4)) / 10) * 10
	var t: float = r.len / (D.CH_SPD.sea * spd_k()) + D.HAND.sea * hand_k() * 2 + NET_PERIOD.sea * .5
	var ref := {"c": ch_cost("sea", r.len, tons) + D.CH_BASE.sea * .25, "t": t, "m": "sea", "legs": [{"a": A.id, "b": B.id, "m": "sea", "len": r.len}]}
	var k: Dictionary = _net_order(A, B, cargo_i[cid], tons, ref, rnd(1.0, 1.15))
	var cg: Dictionary = cargo_i[cid]
	k.pay = JS.round_js(tons * r.len * SEA_RATE * maxf(.6, cg.k) * (price_k(A.cid) + price_k(B.cid)) / 2 * rnd(.9, 1.25)) * fast_k()
	k.sea = 1
	var r2 := Mulberry.new((seed_value * 7 + A.id * 131 + k.id) & 0xFFFFFFFF)
	var refs := net_refineries().filter(func(pid): return PL[pid].land == A.land)
	refs.sort_custom(func(x, y): return JS.hypot(PL[x].x - A.x, PL[x].z - A.z) < JS.hypot(PL[y].x - A.x, PL[y].z - A.z))
	k.fs = refinery_name(refs[0]) if (cid == "crude" or cid == "fuel") and refs.size() else _firm_name("port", r2)
	k.ft = _firm_name("port", r2)
	return k


## an order of the network from a reference way (the pay and the deadline as for the board)
func _net_order(A: Dictionary, B: Dictionary, cg: Dictionary, tons: float, ref: Dictionary, extra: float) -> Dictionary:
	var urg := R.next()
	var risk := JS.clamp_js((co_risk(A.cid) + co_risk(B.cid)) / 2 * cg.get("theft", .7), 0, 2)
	var pk := (price_k(A.cid) + price_k(B.cid)) / 2
	var pay := JS.round_js(ref.c * 1.12 * cg.k * pk * (1 + urg * .45) * (1 + risk * .15) * (.8 + CO.rating * .07) * (1 + msk("cco") * .12) * extra * (1 + co_grade() * .03)) * fast_k()
	var k := {"id": CO.uid, "from": A.id, "to": B.id, "cg": cg.id, "tons": tons, "pay": pay, "dlDays": JS.fixed1(maxf(1.5, ref.t * (2.6 - urg * .9) + 1.5)), "mode": ref.m,
		"risk": risk, "minR": 0.0, "len": 0.0, "exp": day + rint(5, 12), "net": 1, "ref": ref.legs.map(func(L): return L.m)}
	for L in ref.legs:
		k.len += L.len
	CO.uid += 1
	return k


## the businesses of an order: a refinery's or a port's already named are kept
func biz_firms_k(k: Dictionary) -> void:
	if k.get("fs") and (k.get("refy") or k.get("sea")):
		return
	super.biz_firms_k(k)


## a refinery among the businesses of its town (the tooltips, the regular clients)
func firms_of(pid: int) -> Array:
	var L: Array = super.firms_of(pid)
	if alt() and net_refineries().has(pid) and not L.any(func(f): return f.get("refy")):
		L.append({"n": refinery_name(pid), "ind": "energy", "refy": 1})
	return L
