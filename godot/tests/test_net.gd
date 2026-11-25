extends RefCounted
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
	if st.done < 150:
		return "only %d consignments delivered in 90 days" % st.done
	if st.fail > st.done * .08:
		return "%d failed against %d delivered" % [st.fail, st.done]
	if sim.over or sim.CO.cash <= cash0:
		return "the network does not pay: cash %d" % int(sim.CO.cash)
	var w := _consistent(sim)
	if w != "":
		return w
	if sim.CO.net.flow.is_empty():
		return "no flows recorded"
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
