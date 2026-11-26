class_name NetBot
extends RefCounted
## A simple player of the alternative balance (SimNet) for the tests and the command line (--netbot): takes the
## orders a way pays for, sends a round with every free road vehicle of a hub, hauls by the next step of what
## waits in the warehouses (own vehicles, else partners when there is enough or it is urgent), a partner for
## what waits too long; buys trucks, a licence and new hubs when it can.

const D = preload("res://scripts/logistics/game_data.gd")


static func policy(sim: Sim, grow: bool = true) -> Dictionary:
	var CO := sim.CO
	var n := {"acc": 0, "runs": 0, "part": 0}
	# take what a way exists for and that pays
	var open: int = CO.net.cs.size()
	var L: Array = CO.board.duplicate()
	L.sort_custom(func(a, b): return a.pay > b.pay)
	for k in L:
		if open > 2 + CO.veh.size() * 3:
			break
		var P: Variant = sim.net_path(k.from, k.to, k.tons, k.dlDays, k.pay)
		if P != null and P.c < k.pay * .6 and P.t < k.dlDays * .9:
			if sim.net_accept(k).get("tone", "") == "good":
				n.acc += 1
				open += 1
	for h in CO.hubs:
		# rounds with the idle road vehicles; one that has nothing in its area hauls along the towns the cargo
		# in the warehouse goes to (own vehicles first: partners take most of the pay)
		for v in sim.net_idle_at(h.pid, "road"):
			var sp: Dictionary = sim.net_auto_round(h.pid, v.id)
			var C: Dictionary = sim.net_calc(sp)
			if not (C.ok and C.rows.size()):
				var way: Array = sim.net_way_auto(h.pid, [], "road", true)
				if way.is_empty():
					continue
				sp = sim.net_auto_multi(h.pid, way, "road", v.id, true)
				C = sim.net_calc(sp)
			if C.ok and C.rows.size():
				sim.net_go(sp)
				n.runs += 1
		# hauls by own vehicles of other kinds, by the next step of what waits here
		var by := {}
		for c in CO.net.cs:
			if c.at == h.pid and c.run < 0 and c.st == "ready":
				var nx: Variant = sim.net_next(c)
				if nx != null and nx.m != "road" and nx.b != h.pid:
					var key := "%d|%s" % [nx.b, nx.m]
					by[key] = by.get(key, 0.0) + c.k.tons
		for key in by:
			var p: PackedStringArray = key.split("|")
			var vs: Array = sim.net_idle_at(h.pid, p[1])
			if vs.is_empty():
				continue
			var sp: Dictionary = sim.net_auto_trunk(h.pid, int(p[0]), p[1], vs[0].id, true)
			if sim.net_calc(sp).ok:
				sim.net_go(sp)
				n.runs += 1
	# a partner only for what would be late otherwise
	for c in CO.net.cs:
		if (c.st == "wait" or c.st == "ready") and c.run < 0 and c.dl - sim.co_now() < 2.5:
			var nx: Variant = sim.net_next(c)
			if nx != null:
				var sp: Dictionary = {"vid": -1, "m": nx.m, "stops": [c.at, nx.b], "picks": {0: [c.id]}}
				var C: Dictionary = sim.net_calc(sp)
				if C.ok:
					sim.net_go(sp)
					n.part += 1
	# grow
	if not grow:
		return n
	if sim.lic_ok().ok:
		sim.act_lic()
	if int(sim.day) % 5 == 0 and CO.cash > D.VT["truck" if CO.tier >= 2 else "ltruck"].cost * 1.3:
		var t := "truck" if CO.tier >= 2 else "ltruck"
		sim.act_buy(t)
		var need := 0
		for v in CO.veh:
			need += int(D.VT[v.t].get("crew", 1))
		if CO.staff.driver < need:
			sim.act_hire("driver", need - CO.staff.driver)
	if int(sim.day) % 30 == 15 and CO.cash > 60000 and CO.hubs.size() < 4 + int(sim.day / 120):
		var H: Dictionary = sim.PL[CO.hq]
		var c2: Array = sim.PL.filter(func(p): return p.cid == H.cid and sim.hub_at(p.id) == null and sim._hub_d(p) > 2.5)
		c2.sort_custom(func(a, b): return a.pop > b.pop)
		if c2.size():
			sim.act_hub(c2[0].id, false)
	return n
