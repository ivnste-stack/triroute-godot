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
