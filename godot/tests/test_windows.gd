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
	var ks: Array = sim.CO.board.filter(func(k): return sim.cons_ok(k) and k.mode == "road" and sim.co_plan(k).ok and k.tons < 4)
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
	return ""
