extends RefCounted
## The windows of the company (scripts/ui/windows.gd): every window is built from a running game, then every
## button, switch, dropdown and slider in it is used once, and every window is built again. Checks that nothing
## stops with a script error and that the actions change the game.


func _game() -> Sim:
	var gen: Object = ClassDB.instantiate("TRWorldGen")
	var world: Dictionary = gen.generate(777)
	var sim := Sim.new()
	sim.setup(gen, 777, gen.generate_states(), gen.generate_board(), world)
	sim.auto_choice = 0
	var ch := sim.start_choices()
	sim.co_init(ch[0].id)
	sim.co_set_hq(ch[0].id)
	var CO := sim.CO
	CO.cash = 2e6
	CO.tier = 4
	CO.staff.merge({"driver": 12, "rail": 6}, true)
	for vt in ["truck", "truck", "rtrain", "reefer", "ltruck", "van", "van", "train"]:
		CO.veh.append({"id": CO.uid, "t": vt, "loc": CO.hq, "st": "idle", "cond": 80.0, "km": 0.0})
		CO.uid += 1
	CO.mgr.cto = CO.cand.cto[0].duplicate()
	CO.cand.erase("cto")
	CO.auto = true
	for d in 35:
		for f in 8:
			sim.co_frame(f / 8.0)
		sim.co_day()
	return sim


func _controls(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is BaseButton or c is Range:
			out.append(c)
		_controls(c, out)


func test_windows_build_and_act() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game()
	var w := Windows.new(sim)
	var acts := [0]
	w.acted.connect(func(_r): acts[0] += 1)
	var cash0: float = sim.CO.cash
	var veh0: int = sim.CO.veh.size()
	for id in ["coHome", "coJobs", "coTrips", "coFleet", "coNet", "coStaff", "coFin"]:
		var body := VBoxContainer.new()
		w.build(id, body)
		if body.get_child_count() < 3:
			body.free()
			return "%s: only %d parts" % [id, body.get_child_count()]
		var cs := []
		_controls(body, cs)
		for c in cs:
			if c is OptionButton:
				if c.item_count > 1:
					c.item_selected.emit(c.item_count - 1)
			elif c is Slider:
				c.value = 120
				c.drag_ended.emit(true)
			elif c is BaseButton and not c.disabled:
				c.pressed.emit()
		body.free()
		var again := VBoxContainer.new()
		w.build(id, again)
		again.free()
	if acts[0] < 20:
		return "only %d actions" % acts[0]
	if sim.CO.cash == cash0 and sim.CO.veh.size() == veh0:
		return "the actions changed nothing"
	return ""


func test_consolidated_trip_from_the_board() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game()
	sim.CO.xp = 1e6
	sim.CO.auto = false
	sim.CO.rating = 5.0
	sim.CO.perm = {}
	for p in Sim.D.PERM:
		sim.CO.perm[p.id] = {"until": 1e9, "auto": false}
	sim.CO.staff.driver += 4
	sim.CO.tier = maxi(sim.CO.tier, 3)   # beyond the home market: a full board (market_k)
	for vt in ["truck", "truck"]:
		sim.CO.veh.append({"id": sim.CO.uid, "t": vt, "loc": sim.CO.hq, "st": "idle", "cond": 100.0, "km": 0.0})
		sim.CO.uid += 1
	for i in 6:
		sim.co_board_day()
	for v in sim.CO.veh:
		if v.st == "idle":
			v.cond = 100.0
	var w := Windows.new(sim)
	var planned := []
	w.plan_order.connect(func(k): planned.append(k))
	# the two lightest road orders, together within one truck (20 t, 82 m³)
	var ks: Array = sim.CO.board.filter(func(k): return sim.cons_ok(k) and k.mode == "road" and sim.co_plan(k).ok)
	ks.sort_custom(func(a, b): return a.tons < b.tons)
	if ks.size() >= 2 and (ks[0].tons + ks[1].tons > 20 or sim.k_vol(ks[0]) + sim.k_vol(ks[1]) > 82):
		ks = []
	if ks.size() < 2:
		return "fewer than two road orders on the board: %s" % [sim.CO.board.map(func(k): return [k.mode, k.tons, sim.cons_ok(k), sim.co_plan(k).get("why", "ok")])]
	w.cons_add(ks[0].id)
	w.cons_add(ks[1].id)
	if w.st.cons.size() != 2:
		return "orders not chosen: %s" % [w.st.cons]
	var body := VBoxContainer.new()
	w.build("coJobs", body)
	var found := false
	var cs := []
	_controls(body, cs)
	for c in cs:
		if c is Button and c.text == "Прокласти маршрут збірного рейсу":
			found = true
			if not c.disabled:
				c.pressed.emit()
	body.free()
	if not found:
		return "no consolidated trip panel"
	var kC: Dictionary = planned[0] if planned.size() else sim.cons_make(w.cons_orders())
	var LP := {"k": kC, "pts": sim.cons_auto_seq(kC), "modes": [], "veh0": null}
	LP.modes = LP.pts.slice(1).map(func(_x): return "road")
	var C := sim.lp_calc(LP)
	if not C.done:
		return "the dispatcher's sequence does not cover the orders: %s" % C.get("consBlock")
	var n0: int = sim.CO.board.size()
	var why := sim.lp_go(LP)
	if why != "":
		return "not sent: " + why
	if sim.CO.board.size() != n0 - 2:
		return "the orders stayed on the board"
	if not w.cons_orders().is_empty():
		return "the panel keeps sent orders"
	# the trip card on the map for every trip, the legs of a route among them
	var mu := MapUi.new()
	mu.sim = sim
	mu._card = Ui.glass()
	var legs := 0
	for j in sim.CO.jobs:
		if j.get("lp") and j.lp.plan.legs.size() > 1:
			legs += 1
		mu.build_card_for(j)
		# a script error inside stops the card before its content is added
		if not mu._card.get_children().any(func(c): return c is VBoxContainer and not c.is_queued_for_deletion()):
			mu._card.free()
			mu.free()
			return "the card of trip %d was not built" % j.id
	mu._card.free()
	mu.free()
	if legs == 0:
		return "no trip of several legs to show on a card"
	return ""


func test_move_vehicle_to_another_hub() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game()
	sim.CO.xp = 1e6
	var w := Windows.new(sim)
	var asked := []
	w.move_vehicle.connect(func(v): asked.append(v))
	var hq: Dictionary = sim.PL[sim.CO.hq]
	var near: Array = sim.PL.filter(func(p): return p.cid == hq.cid and p.id != hq.id)
	near.sort_custom(func(a, b): return Vector2(a.x - hq.x, a.z - hq.z).length() < Vector2(b.x - hq.x, b.z - hq.z).length())
	sim.CO.cash = 1e7
	var r := sim.act_hub(near[0].id)
	if sim.hub_at(near[0].id) == null:
		return "no second hub: %s" % [r]
	var v: Variant = null
	for x in sim.CO.veh:
		if x.st == "idle" and Sim.D.VT[x.t].mode == "road" and x.loc == sim.CO.hq:
			v = x
	if v == null:
		return "no idle truck at the headquarters"
	w.move(v)
	if asked.is_empty():
		return "the map was not asked to pick a hub"
	var ts: Array = sim.mv_targets(v).filter(func(t): return t.why == "")
	if ts.is_empty():
		return "no target hub"
	var res := sim.act_move(v, ts[0].pid)
	if v.st != "trip" or v.home != ts[0].pid:
		return "the vehicle did not set off: %s" % [res]
	return ""


## the test sandbox of the settings: everything open, 100 of every vehicle; the game goes on and the windows
## are built with it
func test_sandbox() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var sim := _game()
	sim.act_sandbox()
	var CO := sim.CO
	if CO.tier != Sim.D.LIC.size() - 1 or CO.cash < 1e11:
		return "not everything open: tier %d, cash %s" % [CO.tier, CO.cash]
	var types := {}
	for v in CO.veh:
		types[v.t] = types.get(v.t, 0) + 1
	for t in Sim.D.VT:
		if types.get(t, 0) < 100:
			return "%s: %d vehicles (no hub for its transport?)" % [t, types.get(t, 0)]
	for m in ["sea", "air", "rail"]:
		if not CO.hubs.any(func(h): return sim.mode_ok(m, sim.PL[h.pid])):
			return "no hub for " + m
	var t0 := Time.get_ticks_msec()
	for d in 5:
		for f in 8:
			sim.co_frame(f / 8.0)
		sim.co_day()
	var ms := Time.get_ticks_msec() - t0
	if ms > 20000:
		return "5 days with the sandbox fleet took %d ms" % ms
	var w := Windows.new(sim)
	for id in ["coHome", "coJobs", "coTrips", "coFleet", "coNet", "coStaff", "coFin"]:
		var body := VBoxContainer.new()
		w.build(id, body)
		var n := body.get_child_count()
		body.free()
		if n < 3:
			return "%s: only %d parts" % [id, n]
	return ""
