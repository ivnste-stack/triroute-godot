extends RefCounted
## Game logic (scripts/logistics/sim.gd) against its references (tests/ref.gd, recorded from the game by
## tests/record_refs.gd). A new game is deterministic: places' continents, the company name, the headquarters,
## competitors, manager candidates and every field of every order on the starting board
## (company_fingerprints.json); then the simulation itself, day by day for 150 days in six scenarios
## (sim_fingerprints.json): trips, border checkpoints, deliveries, returns, the city, the board, the
## dispatcher, prices, incidents, the planner, the month.

const Ref = preload("res://tests/ref.gd")
const COMPANY_SEEDS := [777, 303, 123456]
const SIM_SEEDS := [777, 303]
const SCENARIOS := ["start", "fleet", "abroad", "staff", "ocean", "air"]
const SIM_DAYS := 150


static func _new_game(seed_value: int) -> Sim:
	var gen: Object = ClassDB.instantiate("TRWorldGen")
	var world: Dictionary = gen.generate(seed_value)
	var states: Array = gen.generate_states()
	var board: Dictionary = gen.generate_board()
	var sim := Sim.new()
	sim.setup(gen, seed_value, states, board, world)
	var choices := sim.start_choices()
	sim.co_init(choices[0].id)
	sim.co_set_hq(choices[0].id)
	return sim


## the start of a new game, as it is stored
static func company_fp(seed_value: int) -> Dictionary:
	var sim := _new_game(seed_value)
	var cand := {}
	for id in sim.CO.cand:
		cand[id] = sim.CO.cand[id].map(func(m): return [m.name, m.age, m.skill, m.sal, m.trait, m.honest, m.loyal])
	return Ref.norm({"name": sim.CO.name, "hq": sim.CO.hq, "lands": sim.PL.map(func(p): return p.land),
		"comp": sim.CO.comp.map(func(c): return [c.n, Ref.h(c.rev), Ref.h(c.g)]),
		"board": Ref.enc(sim.CO.board), "cand": cand})


func test_company_start_matches_reference() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp: Dictionary = Ref.read("company_fingerprints.json")
	for seed_str in fp:
		var t := Time.get_ticks_msec()
		var d := Ref.diff(company_fp(int(seed_str)), fp[seed_str], "seed " + seed_str)
		if d != "":
			return d
		print("       seed %s: «%s», %d orders on the board — as recorded (%d ms)" % [seed_str, fp[seed_str].name, fp[seed_str].board.size(), Time.get_ticks_msec() - t])
	return ""


static func _h(x: float) -> String:
	return Ref.h(x)


## what a day leaves: money, the board, the trips, the fleet, incidents, managers…
static func _record(sim: Sim, sent: int) -> Dictionary:
	var CO: Dictionary = sim.CO
	var m := PackedStringArray()
	for k in CO.m:
		m.append("%s=%s" % [k, _h(CO.m[k])])
	var bd := PackedStringArray()
	for k in CO.board:
		bd.append("%d:%s" % [k.id, _h(k.pay)])
	var jb := PackedStringArray()
	for j in CO.jobs:
		var fl: String = ("r" if j.get("ret") else "") + ("b" if j.get("back") else "") + ("x" if j.get("cx0") else "") + ("l" if j.get("lost") else "")
		var pk: float = j.payK if j.get("payK") else 1.0
		jb.append("%d:%s%s:%s:%s:%d:%s:%d:%s" % [j.id, fl, _h(j.tot), _h(j.t0), "/".join(j.vids.map(func(x): return str(x))), j.get("stops", []).size(),
			_h(j.dmg), j.get("pz", []).size() if j.get("pz") != null else 0, _h(pk)])
	var vh := PackedStringArray()
	for v in CO.veh:
		vh.append("%d:%d:%s:%s:%s" % [v.id, v.loc, v.st, _h(v.cond), _h(v.km)])
	var hb := PackedStringArray()
	for h in CO.hubs:
		hb.append(_h(h.share))
	var cf := PackedStringArray()
	for c in CO.conf:
		cf.append("%d-%d@%d" % [c.a, c.b, int(c.until)])
	var cp := PackedStringArray()
	for c in CO.comp:
		cp.append(_h(c.rev))
	var pl := PackedStringArray()
	for k in CO.pool:
		pl.append("%s=%d" % [k, int(CO.pool[k])])
	var cl := PackedStringArray()
	for c in CO.get("cls", []):
		cl.append("%d%s%d-%s@%s" % [c.id, c.kind, c.a, str(c.b) if c.get("b") != null else "", _h(c.until)])
	var wx := PackedStringArray()
	for w in CO.get("wx", []):
		wx.append("%d%s@%s" % [w.id, w.k, _h(w.until)])
	var bn := PackedStringArray()
	for z in CO.get("band", []):
		bn.append("%d@%s" % [z.id, _h(z.x)])
	var pr := PackedStringArray()
	for z in CO.get("pir", []):
		pr.append("%d@%s" % [z.id, _h(z.x)])
	var jm := PackedStringArray()
	for J in sim.jam:
		jm.append("%d:%d@%s" % [J.id, J.n, _h(J.until)])
	var td := PackedStringArray()
	for t in CO.tenders:
		td.append("%s:%d:%d:%d" % [t.t, t.n, t.left, int(t.pay)])
	var tf := PackedStringArray()
	for o in CO.get("toff", []):
		tf.append("%d:%s:%d:%d" % [o.id, o.t, o.n, int(o.pay)])
	var mg := PackedStringArray()
	for k in CO.mgr:
		mg.append("%s:%d:%d:%s" % [k, CO.mgr[k].sal, CO.mgr[k].loyal, "true" if CO.mgr[k].honest else "false"])
	var sf := PackedStringArray()
	for k in CO.staff:
		sf.append(str(int(CO.staff[k])))
	return {"td": " ".join(td) + "|" + " ".join(tf), "mgr": " ".join(mg) + "|" + str(int(CO.strike)) + "|" + _h(CO.wageLv) + "|" + ",".join(sf),
		"cls": " ".join(cl), "wx": " ".join(wx), "band": " ".join(bn), "pir": " ".join(pr), "jam": " ".join(jm), "mcd": CO.get("mcd", 0),
		"day": sim.day, "sent": sent, "cash": _h(CO.cash), "rating": _h(CO.rating), "morale": _h(CO.morale), "fuel": _h(CO.fuel),
		"parts": _h(CO.get("parts", 1.0)), "uid": CO.uid, "deliv": _h(CO.deliv), "cdel": CO.cdel, "xp": CO.get("xp", 0), "m": " ".join(m),
		"board": " ".join(bd), "jobs": " ".join(jb), "veh": " ".join(vh), "hubs": " ".join(hb), "conf": " ".join(cf), "comp": " ".join(cp), "pool": " ".join(pl)}


## the player of the test: the best-paying single-leg orders that can be done on time, chains, multi-drop
## flights, consolidated trips and reroutes depending on the scenario
static func _policy(sim: Sim, scenario: String = "") -> int:
	var n := 0
	if scenario == "fleet" and sim.CO.tenders.is_empty() and sim.CO.get("toff", []).size():
		sim.co_tender_take(sim.CO.toff[0].id)
	var L: Array = sim.CO.board.duplicate()
	Sim._stable_sort(L, func(a, b): return b.pay - a.pay)
	for k in L:
		var P: Dictionary = sim.co_plan(k)
		if P.ok and not P.late:
			sim.co_dispatch(k, P, true)
			n += 1
	# the route planner: the best-paying chain order left is sent along its legs when that pays
	if scenario == "abroad" or scenario == "ocean":
		var ks: Array = sim.CO.board.filter(func(x): return x.get("legs") != null)
		Sim._stable_sort(ks, func(a, b): return b.pay - a.pay)
		if ks.size():
			var k: Dictionary = ks[0]
			var LP := {"k": k, "pts": [k.from] + k.legs.map(func(L): return L.b), "modes": k.legs.map(func(L): return L.m), "veh0": null}
			var C: Dictionary = sim.lp_calc(LP)
			if C.done and C.get("bad") == null and C.legs.size() and C.legs.size() == C.get("groups", C.legs.size()) and sim.lp_block(LP, C) == null and C.net > 0:
				sim.lp_go(LP)
				n += 100
	# multi-drop flights: the most urgent landing first
	if scenario == "air":
		var ms: Array = sim.CO.board.filter(func(x): return x.get("multi") != null)
		Sim._stable_sort(ms, func(a, b): return b.pay - a.pay)
		if ms.size():
			var k: Dictionary = ms[0]
			var pts: Array = sim.lp_order(k, "urg")
			var LP := {"k": k, "pts": pts, "modes": pts.slice(1).map(func(_p): return "air"), "veh0": null}
			var C: Dictionary = sim.lp_calc(LP)
			if C.done and C.get("bad") == null and C.legs.size() and C.legs.size() == C.get("groups", C.legs.size()) and sim.lp_block(LP, C) == null and C.net > 0:
				sim.lp_go(LP)
				n += 1000
	# a consolidated road trip of the three best-paying small road orders (up to 6 t, no special permits)
	if scenario == "fleet":
		var ks: Array = sim.CO.board.filter(func(x): return sim.cons_ok(x) and x.mode == "road" and x.tons <= 6 and sim.perm_need(sim.cargo_i[x.cg], "road").all(func(id): return sim.perm_ok(id)))
		Sim._stable_sort(ks, func(a, b): return b.pay - a.pay)
		ks = ks.slice(0, 3)
		if ks.size() >= 2:
			var kC: Dictionary = sim.cons_make(ks)
			var pts: Array = sim.cons_auto_seq(kC)
			var LP := {"k": kC, "pts": pts, "modes": pts.slice(1).map(func(_p): return "road"), "veh0": null}
			var C: Dictionary = sim.lp_calc(LP)
			if C.done and C.get("bad") == null and C.legs.size() and C.legs.size() == C.get("groups", C.legs.size()) and sim.lp_block(LP, C) == null and C.net > 0:
				sim.lp_go(LP)
				n += 10000
	# once a week the first trip that can turns its course around danger
	if (scenario == "fleet" or scenario == "ocean" or scenario == "air") and int(sim.day) % 7 == 3:
		for j in sim.CO.jobs:
			if sim.sr_ok(j):
				if not sim.sr_calc(j, [], true).bad:
					sim.sr_go(j, [], true)
					n += 100000
				break
	return n


## the planner's estimates for the first orders on the board
static func _lp_rec(sim: Sim) -> String:
	var out := PackedStringArray()
	for k in sim.CO.board.slice(0, 4):
		var legs: bool = k.get("legs") != null
		var LP := {"k": k, "pts": ([k.from] + k.legs.map(func(L): return L.b)) if legs else [k.from, k.to], "modes": k.legs.map(func(L): return L.m) if legs else [k.mode], "veh0": null}
		var C: Dictionary = sim.lp_calc(LP)
		var b: Variant = sim.lp_block(LP, C)
		out.append("%d:%s:%s:%s:%s:%d:%s:%d" % [k.id, _h(C.t), _h(C.c), _h(C.risk), _h(C.net), 1 if C.done else 0, "".join(C.legs.map(func(L): return "o" if L.own else "p")), 1 if b != null else 0])
	return " ".join(out)


## a scenario played for `days` days: the record of every day
static func sim_run(seed_value: int, scenario: String, days: int) -> Dictionary:
	var sim := _new_game(seed_value)
	var SC: Dictionary = {"fleet": {"cash": 250000.0, "tier": 2, "staff": {"driver": 8}, "veh": ["ltruck", "ltruck", "van", "van", "van", "truck", "truck"]},
		"abroad": {"cash": 2e6, "tier": 4, "staff": {"driver": 12, "rail": 6}, "veh": ["truck", "truck", "truck", "rtrain", "reefer", "ltruck", "van", "train", "train"]},
		"staff": {"cash": 250000.0, "tier": 2, "staff": {"driver": 8}, "veh": ["ltruck", "ltruck", "van", "van", "van", "truck", "truck"]},
		"ocean": {"cash": 5e7, "tier": 5, "staff": {"driver": 16, "rail": 8, "sailor": 40}, "veh": ["truck", "truck", "truck", "truck", "train", "train"]},
		"air": {"cash": 2e8, "tier": 6, "staff": {"driver": 16, "pilot": 30}, "veh": ["plane", "plane", "turbo", "truck", "truck", "truck"]}}.get(scenario, {})
	if SC:
		sim.CO.cash = SC.cash
		sim.CO.tier = SC.tier
		sim.CO.staff.merge(SC.staff, true)
		for vt in SC.veh:
			sim.CO.veh.append({"id": sim.CO.uid, "t": vt, "loc": sim.CO.hq, "st": "idle", "cond": 100.0, "km": 0.0})
			sim.CO.uid += 1
		sim.CO.mgr.cto = sim.CO.cand.cto[0].duplicate()
		sim.CO.cand.erase("cto")
		sim.CO.auto = true
	if scenario == "ocean":
		var H: Dictionary = sim.PL[sim.CO.hq]
		var P: Variant = H if H.port != null else null
		if P == null:
			var L: Array = sim.PL.filter(func(p): return p.port != null and p.land == H.land)
			Sim._stable_sort(L, func(a, b): return JS.hypot(a.x - H.x, a.z - H.z) - JS.hypot(b.x - H.x, b.z - H.z))
			P = L[0] if L.size() else null
		if P != null:
			if P.id != sim.CO.hq:
				sim.CO.hubs.append({"pid": P.id, "lvl": 1, "share": .04, "mk": 0})
			for vt in ["feeder", "ship", "feeder"]:
				sim.CO.veh.append({"id": sim.CO.uid, "t": vt, "loc": P.id, "st": "idle", "cond": 100.0, "km": 0.0})
				sim.CO.uid += 1
	if scenario == "staff":
		sim.auto_choice = 1
		sim.CO.wageLv = .7
		sim.CO.mgr.cfo = sim.CO.cand.cfo[0].duplicate()
		sim.CO.mgr.cfo.honest = true
		sim.CO.cand.erase("cfo")
		sim.CO.mgr.coo = sim.CO.cand.coo[0].duplicate()
		sim.CO.mgr.coo.honest = false
		sim.CO.mgr.coo.sal = 500
		sim.CO.cand.erase("coo")
	var rec := []
	for n in days:
		if sim.over:
			break
		var sent := _policy(sim, scenario)
		for f in 8:
			sim.co_frame(f / 8.0)
		sim.co_day()
		var got := _record(sim, sent)
		got.lp = _lp_rec(sim) if n % 10 == 9 else ""
		rec.append(got)
	return Ref.norm({"seed": seed_value, "scenario": scenario, "name": sim.CO.name, "hq": sim.CO.hq, "over": sim.over,
		"cdel": sim.CO.cdel, "cash": int(sim.CO.cash), "rec": rec})


func test_simulation_days_match_reference() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp: Dictionary = Ref.read("sim_fingerprints.json")
	for want in fp.runs:
		var t := Time.get_ticks_msec()
		var got := sim_run(int(want.seed), want.scenario, want.rec.size())
		var where := "seed %d %s" % [int(want.seed), want.scenario]
		for i in mini(got.rec.size(), want.rec.size()):
			var d := Ref.diff(got.rec[i], want.rec[i], "%s, day %d" % [where, int(want.rec[i].day)])
			if d != "":
				return d
		var d := Ref.diff(got, want, where)
		if d != "":
			return d
		print("       %s «%s»: %d days, %d deliveries, cash %d — as recorded (%d ms)" % [where, want.name, want.rec.size(), int(want.cdel), int(want.cash), Time.get_ticks_msec() - t])
	return ""
