extends RefCounted
## Saving and loading (Sim.save_state / load_state, SaveSystem): a game saved in the middle, written to a slot
## and read back into a fresh simulation of the same world goes on exactly like the one that kept running.


func _sim(gen: Object, world: Dictionary, seed_value: int) -> Sim:
	var sim := Sim.new()
	sim.setup(gen, seed_value, gen.generate_states(), gen.generate_board(), world)
	sim.auto_choice = 0
	return sim


func _days(sim: Sim, n: int) -> void:
	for d in n:
		for f in 8:
			sim.co_frame(f / 8.0)
		sim.co_day()


func test_saved_game_goes_on_like_the_original() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var gen: Object = ClassDB.instantiate("TRWorldGen")
	var world: Dictionary = gen.generate(303)
	var a := _sim(gen, world, 303)
	var ch := a.start_choices()
	a.co_init(ch[0].id)
	a.co_set_hq(ch[0].id)
	var CO := a.CO
	CO.cash = 2e6
	CO.tier = 4
	CO.staff.merge({"driver": 12, "rail": 6}, true)
	for vt in ["truck", "truck", "rtrain", "reefer", "ltruck", "van", "van", "train"]:
		CO.veh.append({"id": CO.uid, "t": vt, "loc": CO.hq, "st": "idle", "cond": 100.0, "km": 0.0})
		CO.uid += 1
	CO.mgr.cto = CO.cand.cto[0].duplicate()
	CO.cand.erase("cto")
	CO.auto = true
	_days(a, 40)
	# through a real slot
	if not SaveSystem.write("test", {"sim": a.save_state()}, {"name": CO.name}):
		return "the slot was not written"
	var d: Variant = SaveSystem.read("test")
	var m := SaveSystem.meta("test")
	SaveSystem.remove("test")
	if d == null or m.get("name") != CO.name:
		return "the slot did not come back"
	var b := _sim(gen, world, 303)
	b.load_state(d.sim)
	if var_to_bytes(b.save_state()) != var_to_bytes(a.save_state()):
		return "the loaded game differs from the saved one"
	_days(a, 60)
	_days(b, 60)
	if b.CO.cash != a.CO.cash or b.CO.jobs.size() != a.CO.jobs.size() or b.day != a.day or b.R._a != a.R._a:
		return "after 60 more days: cash %s vs %s, trips %d vs %d" % [b.CO.cash, a.CO.cash, b.CO.jobs.size(), a.CO.jobs.size()]
	var sa := a.save_state()
	var sb := b.save_state()
	for k in sa:
		if var_to_bytes(sa[k]) != var_to_bytes(sb[k]):
			var diff: String = k
			if sa[k] is Dictionary:
				for k2 in sa[k]:
					if not sb[k].has(k2) or var_to_bytes(sa[k][k2]) != var_to_bytes(sb[k][k2]):
						diff += "." + str(k2) + _deep(sa[k][k2], sb[k].get(k2))
						break
			return "after 60 more days the games differ: " + diff
	return ""


func _deep(a: Variant, b: Variant) -> String:
	if typeof(a) != typeof(b):
		return " types %s/%s" % [type_string(typeof(a)), type_string(typeof(b))]
	if a is Array:
		if a.size() != b.size():
			return " sizes"
		for i in a.size():
			if var_to_bytes(a[i]) != var_to_bytes(b[i]):
				return "[%d]" % i + _deep(a[i], b[i])
	if a is Dictionary:
		if a.keys().size() != b.keys().size():
			return " keys %s / %s" % [a.keys(), b.keys()]
		for k in a:
			if not b.has(k):
				return " missing " + str(k)
			if var_to_bytes(a[k]) != var_to_bytes(b[k]):
				return "." + str(k) + _deep(a[k], b[k])
		return " key order/type %s / %s" % [a.keys().map(func(x): return type_string(typeof(x))), b.keys().map(func(x): return type_string(typeof(x)))]
	return " = %s / %s" % [str(a).left(200), str(b).left(200)]
