extends RefCounted

const D = preload("res://scripts/logistics/game_data.gd")
## The alternative balance, «Мережа терміналів» (scripts/logistics/sim_net.gd): consignments taken from the board
## travel through the network — picked up by rounds, handled in the hubs' terminals, hauled, delivered and paid;
## the terminals' queues, modules and upgrades work; lines run on their own; a saved game of the network goes on
## exactly like the one that kept running. The classic game is the other tests' business: they must not move.


static func _game(seed_value: int) -> Sim:
	var gen: Object = ClassDB.instantiate("TRWorldGen")
	var world: Dictionary = gen.generate(seed_value)
	var sim := Sim.new()
	sim.setup(gen, seed_value, gen.generate_states(), gen.generate_board(), world)
	var ch := sim.start_choices()
	sim.co_init(ch[0].id)
	sim.co_set_hq(ch[0].id)
	sim.net_init()
	return sim


static func _days(sim: Sim, n: int, bot: bool = true) -> void:
	for d in n:
		if bot:
			NetBot.policy(sim)
		for f in 8:
			sim.co_frame(f / 8.0)
		sim.co_day()


## nothing is lost between the states: every consignment is somewhere, every kept vehicle belongs to a run
static func _consistent(sim: Sim) -> String:
	var runs := {}
	for r in sim.CO.net.runs:
		runs[r.id] = r
	for c in sim.CO.net.cs:
		if not ["wait", "proc", "ready", "move"].has(c.st):
			return "a consignment in state %s is still listed" % c.st
		if c.st == "move" and not runs.has(c.run):
			return "a consignment rides a run that is gone"
		if c.run >= 0 and not runs.has(c.run):
			return "a consignment is booked on a run that is gone"
	for v in sim.CO.veh:
		if v.get("nres") != null and not runs.has(v.nres):
			return "a vehicle is kept for a run that is gone"
	return ""


func test_network_carries_and_pays() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(777)
	if sim.CO.board.is_empty() or not sim.CO.board.all(func(k): return k.get("net")):
		return "the board of the network is empty or classic"
	var cash0: float = sim.CO.cash
	_days(sim, 90)
	var st: Dictionary = sim.CO.net.stat
	if st.done < 80:
		return "only %d consignments delivered in 90 days" % st.done
	if st.fail > st.done * .08:
		return "%d failed against %d delivered" % [st.fail, st.done]
	if sim.over or sim.CO.cash < cash0 - 40000:   # a simple player leaning on partners about breaks even (one theft swings it)
		return "the network does not pay: cash %d" % int(sim.CO.cash)
	var w := _consistent(sim)
	if w != "":
		return w
	if sim.CO.net.flow.is_empty():
		return "no flows recorded"
	for k in sim.CO.board:   # a card «Вантаж прийнято» stays only while its cargo is in the network
		if k.get("taken") and not sim.CO.net.cs.any(func(c): return is_same(c.k, k)):
			return "a delivered order still on the board"
	print("       90 days: %d delivered, %d failed, cash %d, %d in the network, %d runs under way" % [st.done, st.fail, int(sim.CO.cash), sim.CO.net.cs.size(), sim.CO.net.runs.size()])
	return ""


## a round takes the warehouse's cargo out and brings the waiting cargo in; a haul consolidates; partners
## carry what own vehicles cannot
func test_runs_round_haul_partner() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(303)
	var hq: int = sim.CO.hq
	for k in sim.CO.board.duplicate():
		sim.net_accept(k)
	var n0: int = sim.CO.net.cs.size()
	if n0 < 5:
		return "only %d consignments taken" % n0
	var v: Dictionary = sim.CO.veh[0]
	var sp := sim.net_auto_round(hq, v.id)
	var C := sim.net_calc(sp)
	if not C.ok or C.rows.is_empty():
		return "the round of the headquarters: %s" % C.why
	if C.fill > 1.0 + 1e-6:
		return "the round overloads the vehicle: %.2f" % C.fill
	if sim.net_go(sp).get("tone") != "good":
		return "the round did not leave"
	if v.get("resv") == null:
		return "the vehicle is not kept for its run"
	# a partner haul of what is in the warehouse to the farthest destination
	var L: Array = sim.CO.net.cs.filter(func(c): return c.at == hq and c.run < 0)
	if L.size():
		var c: Dictionary = L[0]
		var ps := {"vid": -1, "m": "road", "stops": [hq, c.k.to], "picks": {0: [c.id]}}
		var P := sim.net_calc(ps)
		if not P.ok:
			return "a partner haul: %s" % P.why
		sim.net_go(ps)
	_days(sim, 25, false)
	if sim.CO.net.stat.done == 0:
		return "nothing delivered by the runs"
	if v.get("resv") != null and sim.CO.net.runs.is_empty():
		return "the vehicle stayed kept after its run"
	var w := _consistent(sim)
	if w != "":
		return w
	print("       a round and a partner haul: %d delivered in 25 days" % sim.CO.net.stat.done)
	return ""


## the terminal: the queue grows with what is handled, cranes and modules change it; costs and refusals
func test_terminal_queue_modules_upgrades() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(777)
	var hq: int = sim.CO.hq
	sim.CO.cash = 1e7
	var thr0 := sim.n_thr(hq)
	var fake := func(t: float) -> Dictionary: return {"k": {"tons": t, "cg": "build"}}
	var t := sim.co_now()
	var e1 := sim.n_handle(hq, [fake.call(30.0)], "road", t)
	var e2 := sim.n_handle(hq, [fake.call(30.0)], "road", t)
	if not (e2 > e1 and e1 > t):
		return "the queue does not grow: %.3f, %.3f" % [e1, e2]
	if absf((e2 - e1) - 30.0 / thr0) > 1e-6:
		return "a batch takes %.3f days, not tons / throughput" % (e2 - e1)
	sim.act_net_up(hq, "crane")
	if sim.n_thr(hq) <= thr0:
		return "cranes do not raise the throughput"
	var p: Dictionary = sim.PL[hq]
	for m in ["rail", "sea", "air"]:
		var r := sim.act_net_mod(hq, m)
		if sim.mode_ok(m, p) != sim.n_mod(hq, m):
			return "module %s: infrastructure %s, built %s (%s)" % [m, sim.mode_ok(m, p), sim.n_mod(hq, m), r.get("d", "")]
	sim.act_net_part(hq, 0)
	var t0 := sim.n_thr(hq)
	sim.act_net_part(hq, 2)
	if sim.n_thr(hq) >= t0:
		return "partner freight takes no throughput"
	return ""


## a line of rounds runs on its own
func test_line_runs_on_schedule() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(777)
	var hq: int = sim.CO.hq
	sim.net_line_add({"kind": "round", "a": hq, "b": -1, "m": "road", "vid": sim.CO.veh[0].id, "back": false, "every": 1, "fill": 0.0, "next": sim.day})
	for i in 30:
		for k in sim.CO.board.duplicate():
			if sim.CO.net.cs.size() < 14:
				sim.net_accept(k)
		_days(sim, 1, false)
	var L: Dictionary = sim.CO.net.lines[0]
	if L.get("last", {}).is_empty() and sim.CO.net.runs.is_empty():
		return "the line never ran: %s" % L.get("why", "")
	if sim.CO.net.stat.done == 0:
		return "the line delivered nothing"
	return _consistent(sim)


func test_saved_network_goes_on() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var a := _game(303)
	_days(a, 30)
	var d: Dictionary = a.save_state()
	var gen: Object = ClassDB.instantiate("TRWorldGen")
	var world: Dictionary = gen.generate(303)
	var b := Sim.new()
	b.setup(gen, 303, gen.generate_states(), gen.generate_board(), world)
	b.load_state(d)
	if not b.alt():
		return "the loaded game lost the alternative balance"
	_days(a, 30)
	_days(b, 30)
	if var_to_bytes(a.save_state()) != var_to_bytes(b.save_state()):
		return "after 30 more days: cash %d vs %d, delivered %d vs %d" % [int(a.CO.cash), int(b.CO.cash), a.CO.net.stat.done, b.CO.net.stat.done]
	return ""


## a haul along several towns: each consignment gets off at its own stop, the load never over the vehicle
func test_haul_along_several_stops() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(777)
	var hq: int = sim.CO.hq
	sim.CO.veh.append({"id": sim.CO.uid, "t": "truck", "loc": hq, "st": "idle", "cond": 100.0, "km": 0.0})
	var vid: int = sim.CO.uid
	sim.CO.uid += 1
	sim.CO.staff.driver += 1
	for i in 3:
		sim.co_board_day()
	for k in sim.CO.board.duplicate():
		sim.net_accept(k)
	for c in sim.CO.net.cs:   # all of it in the headquarters' warehouse
		c.at = hq
		c.st = "ready"
	var way := sim.net_way_auto(hq, [], "road", false)
	if way.is_empty():
		return "no stops on the way"
	while way.size() < 3:   # the player adds the other towns, each where it lengthens the way the least
		var cands := sim.net_way_cands(hq, way, "road", false).filter(func(x): return x.to > 0)
		if cands.is_empty():
			break
		if cands[0].det < -1e-6:
			return "a negative detour"
		way = cands[0].way
	if way.size() < 2:
		return "the stops on the way: %s" % str(way)
	var sp := sim.net_auto_multi(hq, way, "road", vid)
	var C := sim.net_calc(sp)
	if not C.ok:
		return "the haul: %s" % C.why
	if C.fill > 1.0 + 1e-6:
		return "the haul overloads the truck: %.2f" % C.fill
	var offs := {}
	for row in C.rows:
		if not row.dest:
			return "a consignment rides past its town"
		offs[row.off] = true
	if offs.size() < 2:
		return "everything gets off at one stop: %s" % str(offs.keys())
	var n: int = C.rows.size()
	var d0: int = sim.CO.net.stat.done
	sim.net_go(sp)
	_days(sim, 15, false)
	if sim.CO.net.stat.done - d0 < n:
		return "%d of %d delivered" % [sim.CO.net.stat.done - d0, n]
	print("       a haul of %d stops: %d consignments, each at its own town" % [way.size(), n])
	return _consistent(sim)


## a run that waits in its hub for a load: it leaves once (when full enough, or after a few days), then it is gone
func test_run_waits_for_its_load() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(777)
	var hq: int = sim.CO.hq
	var v: Dictionary = sim.CO.veh[0]
	var way := [sim.PL.filter(func(p): return p.cid == sim.PL[hq].cid and p.id != hq)[0].id]
	sim.net_line_add({"kind": "trunk", "a": hq, "b": way[0], "way": way, "m": "road", "vid": v.id, "back": false, "every": 0, "fill": .99, "next": sim.day})
	var ran := false
	for i in 8:
		_days(sim, 1, false)
		if v.get("resv") != null or v.st == "trip":
			ran = true
	if sim.CO.net.lines.size():
		return "the waiting run is still listed after 8 days: %s" % sim.CO.net.lines[0].get("why", "")
	if not ran and sim.net_calc(sim.net_auto_multi(hq, way, "road", v.id)).ok:
		return "the run never left"
	return _consistent(sim)


## businesses served on time offer contracts (or accept one proposed); a contract ships on its schedule,
## its consignments wait at the shipper's like any other and are carried by the network
func test_contracts_with_shippers() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(777)
	_days(sim, 20)
	var N: Dictionary = sim._nets()
	if N.firms.is_empty():
		return "no business remembered after 20 days of deliveries"
	# a business served on time four times (as a punctual player would have)
	var k: Dictionary = sim.CO.board.filter(func(x): return x.get("fs"))[0]
	var key := SimNet.firm_key(k.from, k.fs)
	N.firms[key] = {"n": k.fs, "at": k.from, "ok": 4, "late": 0, "off": -999.0,
		"lanes": {str(k.to): {"n": 4, "pay": k.pay * 4, "tons": k.tons * 4, "cg": {k.cg: 4}}}}
	if sim.act_ctr_ask("0|nobody").get("tone", "") == "good":
		return "a stranger signed a contract"
	var r := sim.act_ctr_ask(key)
	if r.get("tone", "") != "good" and not sim.ctr_has(key):
		return "the proposal was refused: %s" % r.get("d", "")
	if N.ctr.is_empty():
		return "no contract under way"
	var C: Dictionary = N.ctr[0]
	var sent0: int = C.sent
	_days(sim, C.every * 3 + 2)
	if not N.ctr.has(C) and C.miss < 3:
		return "the contract vanished"
	if C.sent - sent0 < 2:
		return "only %d shipments in %d days of a contract every %d days" % [C.sent - sent0, C.every * 3 + 2, C.every]
	if C.ok + C.miss == 0 and not sim.CO.net.cs.any(func(c): return c.k.get("ctr") == C.id):
		return "the shipments went nowhere"
	print("       contract with «%s» %s → %s every %d d: %d shipments, %d delivered, %d missed; %d businesses known" % [C.firm, sim.PL[C.from].name, sim.PL[C.to].name, C.every, C.sent, C.ok, C.miss, N.firms.size()])
	return _consistent(sim)


## industries: a refinery's fuel goes to its port by road; a shipload between continents goes only by sea
func test_refineries_and_shiploads() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(777)
	sim.CO.tier = 6
	sim.CO.perm = {"adr": {"until": 1e9}, "imdg": {"until": 1e9}}
	if sim.net_refineries().is_empty():
		return "no refinery in the world"
	var sea: Variant = null
	var refy: Variant = null
	for i in 300:
		var k: Variant = sim.co_gen()
		if k == null:
			continue
		if k.get("sea") and sea == null:
			sea = k
		if k.get("refy") and refy == null:
			refy = k
	if sea == null or refy == null:
		return "no shipload or no refinery order in 300 orders"
	if sim.PL[refy.to].port == null or sim.PL[refy.from].port != null or not String(refy.fs).begins_with("НПЗ"):
		return "a refinery order not from an inland refinery to a port: %s" % str([refy.fs, sim.PL[refy.from].name, sim.PL[refy.to].name])
	if sea.tons < 500 or sim.PL[sea.from].land == sim.PL[sea.to].land:
		return "a shipload of %s t on one land" % sea.tons
	sim.CO.board.append(sea)
	sim.net_accept(sea)
	var c: Dictionary = sim.CO.net.cs.back()
	c.at = sea.from
	c.st = "ready"
	var road := sim.net_calc({"vid": -1, "m": "road", "stops": [sea.from, sea.to], "picks": {0: [c.id]}})
	if road.ok:
		return "a shipload went by road"
	var ship := sim.net_calc({"vid": -1, "m": "sea", "stops": [sea.from, sea.to], "picks": {0: [c.id]}})
	if ship.ok:
		return "a partner took a shipload of %s t" % sea.tons
	# an own ship takes it
	var A: Dictionary = sim.PL[sea.from]
	sim.CO.cash = 1e8
	sim.CO.staff.sailor = 60
	sim.act_hub(A.id, false)
	sim.act_net_mod(A.id, "sea")
	sim.CO.buyAt = A.id
	sim.act_buy("ship" if sea.tons <= 6000 else "bulk")
	var v: Variant = null
	for x in sim.CO.veh:
		if D.VT[x.t].mode == "sea":
			v = x
	if v == null:
		return "no ship bought"
	var own := sim.net_calc(sim.net_auto_multi(A.id, [sea.to], "sea", v.id))
	if not own.ok:
		return "an own ship cannot take the shipload: %s" % own.why
	print("       %s: %s → %s, %s t, pay %d, own ship %.1f d for %d (road: «%s», partner: «%s»); %s %s → %s" % [sim.cargo_i[sea.cg].n, sim.PL[sea.from].name, sim.PL[sea.to].name, sea.tons, sea.pay, own.t, own.c,
		road.why, ship.why, refy.fs, sim.PL[refy.from].name, sim.PL[refy.to].name])
	return ""


## a route that only picks up: the cargo goes to the nearest hub and waits in its warehouse
func test_pickup_only_goes_to_a_hub() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(777)
	var hq: int = sim.CO.hq
	for k in sim.CO.board.duplicate():
		sim.net_accept(k)
	var wt: Array = sim.CO.net.cs.filter(func(c): return c.st == "wait" and c.at != hq and c.k.to != hq and sim.PL[c.at].land == sim.PL[hq].land)
	if wt.is_empty():
		return "no cargo waiting away from the headquarters"
	var c: Dictionary = wt[0]
	var only := {}   # this one consignment only: the first leg goes empty to pick it up
	for x in sim.CO.net.cs:
		if x.id != c.id:
			only[x.id] = true
	var sp := sim.net_auto_multi(hq, [c.at], "road", sim.CO.veh[0].id, false, only)
	if sp.get("auto_end", -1) < 0:
		return "no hub added after a pick-up-only route"
	var C := sim.net_calc(sp)
	if not C.ok or not C.rows.any(func(r): return r.c.id == c.id and sp.stops[r.off] == sp.auto_end):
		return "the cargo does not go to the hub: %s" % C.why
	sim.net_go(sp)
	var j: Variant = null   # the first leg goes to load: nothing on board, an empty run
	for f in 64:
		for x in sim.CO.jobs:
			if x.get("net") != null:
				j = x
		if j != null:
			break
		sim.co_frame(minf(.99, sim.co_now() - sim.day + 1 / 32.0))
		if f % 32 == 31:
			sim.co_day()
	if j == null:
		return "the run never left"
	var ph: String = sim.co_job_state(j, j.tot * .5).ph
	if not ph.begins_with("Порожній перегін"):
		return "the way to the load reads «%s» (%d on board)" % [ph, j.net.n]
	_days(sim, 12, false)
	if c.at != sp.auto_end or not (c.st == "ready" or c.st == "proc" or c.st == "done"):
		return "the cargo is at %s (%s), not in the hub" % [sim.PL[c.at].name, c.st]
	return _consistent(sim)


## the player's own roads: a point put on a road aside of the shortest way — the plan, the time and the
## truck itself go through it, and the cargo still gets there
func test_run_takes_the_players_roads() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game(777)
	var hq: int = sim.CO.hq
	sim.CO.veh.append({"id": sim.CO.uid, "t": "truck", "loc": hq, "st": "idle", "cond": 100.0, "km": 0.0})
	var vid: int = sim.CO.uid
	sim.CO.uid += 1
	sim.CO.staff.driver += 1
	for i in 3:
		sim.co_board_day()
	for k in sim.CO.board.duplicate():
		sim.net_accept(k)
	for c in sim.CO.net.cs:
		c.at = hq
		c.st = "ready"
	var way := sim.net_way_auto(hq, [], "road", false).filter(func(p): return p != hq)
	if way.is_empty():
		return "no stops on the way"
	way = [way[0]]
	var A: Dictionary = sim.PL[hq]
	var B: Dictionary = sim.PL[way[0]]
	var mx: float = (A.x + B.x) / 2 - (B.z - A.z) * .8
	var mz: float = (A.z + B.z) / 2 + (B.x - A.x) * .8
	var Bd: Dictionary = sim.board
	var best := -1
	var bd := 1e9
	for v in Bd.bits.size():
		if Bd.bits[v] != 0:
			var d := Vector2(-Bd.wx / 2 + (v % Bd.nx) * Bd.st - mx, -Bd.wz / 2 + (v / Bd.nx) * Bd.st - mz).length()
			if d < bd:
				bd = d
				best = v
	var w := {"v": best, "x": -Bd.wx / 2 + (best % Bd.nx) * Bd.st, "z": -Bd.wz / 2 + (best / Bd.nx) * Bd.st}
	var plain: Variant = sim.co_route("road", hq, way[0])
	var rv: Variant = sim.net_leg_route("road", hq, way[0], [w])
	if plain == null or rv == null:
		return "no route"
	if rv.len < plain.len * 1.1:
		return "the point does not lengthen the way: %.3f vs %.3f" % [rv.len, plain.len]
	var sp := sim.net_auto_multi(hq, way, "road", vid)
	var C0 := sim.net_calc(sp)
	sp.via = {0: [w]}
	var C := sim.net_calc(sp)
	if not (C.ok and C0.ok):
		return "the haul: %s" % C.why
	if C.legs[0].len < C0.legs[0].len * 1.1 or C.t <= C0.t:
		return "the plan ignores the point: %.3f, %.2f d vs %.3f, %.2f d" % [C.legs[0].len, C.t, C0.legs[0].len, C0.t]
	var n: int = C.rows.size()
	var d0: int = sim.CO.net.stat.done
	sim.net_go(sp)
	var j: Variant = null
	for f in 64:
		for x in sim.CO.jobs:
			if x.get("net") != null:
				j = x
		if j != null:
			break
		sim.co_frame(minf(.99, sim.co_now() - sim.day + 1 / 32.0))
		if f % 32 == 31:
			sim.co_day()
	if j == null:
		return "the run never left"
	if absf(j.len - rv.len) > rv.len * .01:
		return "the truck drives %.3f, the player's way is %.3f" % [j.len, rv.len]
	_days(sim, 10, false)
	if sim.CO.net.stat.done - d0 < n:
		return "%d of %d delivered" % [sim.CO.net.stat.done - d0, n]
	print("       through the player's point: %.0f%% longer than the shortest way" % ((rv.len / plain.len - 1) * 100))
	return _consistent(sim)
