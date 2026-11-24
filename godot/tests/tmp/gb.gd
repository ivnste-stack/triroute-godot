extends SceneTree
func _init():
	var gen = ClassDB.instantiate("TRWorldGen")
	var world: Dictionary = gen.generate(777, 26, 1800, 1200)
	var sim := Sim.new()
	sim.setup(gen, 777, gen.generate_states(), gen.generate_board(), world)
	var ch := sim.start_choices()
	sim.co_init(ch[0].id)
	sim.co_set_hq(ch[0].id)
	sim.act_sandbox()
	for d in 4:
		sim._gen_pre = {"wait": sim._gen_wait(), "own": 0.0, "ov": 0.0, "rlim": sim.road_lim()}
		for i in 12:
			var t0 := Time.get_ticks_usec()
			var k: Variant = sim.co_gen()
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			if ms > 30:
				print("day ", d, " gen ", ms, " ms ", (k.mode + " " + str(k.get("legs", null) != null) + " " + sim.PL[k.from].name + "→" + sim.PL[k.to].name) if k != null else "null")
		sim.co_day()
	print("done")
	quit()
