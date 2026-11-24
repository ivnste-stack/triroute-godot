extends SceneTree
## Records the references of the tests (tests/ref.gd) from the game as it is now:
##   godot --headless --path godot -s res://tests/record_refs.gd
## Run it after a change to the world generator or the game logic made on purpose, then the tests again.

const Ref = preload("res://tests/ref.gd")
const TSim = preload("res://tests/test_sim.gd")
const TWorld = preload("res://tests/test_worldgen.gd")
const TCore = preload("res://tests/test_core.gd")


func _initialize() -> void:
	var t := Time.get_ticks_msec()
	Ref.write("rng_vectors.json", TCore.rng_fp(), " ")
	var w := {}
	var l := {}
	for s in TWorld.SEEDS:
		w[str(s)] = TWorld.all_fp(s)
		l[str(s)] = TWorld.lines_fp(TWorld._gen(s))
	Ref.write("world_fingerprints.json", w, " ")
	Ref.write("lines_fingerprints.json", l)
	print("world: %d seeds" % w.size())
	var c := {}
	for s in TSim.COMPANY_SEEDS:
		c[str(s)] = TSim.company_fp(s)
	Ref.write("company_fingerprints.json", c)
	print("company start: %d seeds" % c.size())
	var runs := []
	for s in TSim.SIM_SEEDS:
		for sc in TSim.SCENARIOS:
			var r := TSim.sim_run(s, sc, TSim.SIM_DAYS)
			runs.append(r)
			print("seed %d %s: %d days, %d deliveries, cash %d%s" % [s, sc, r.rec.size(), int(r.cdel), int(r.cash), " (bankrupt)" if r.over else ""])
	Ref.write("sim_fingerprints.json", {"days": TSim.SIM_DAYS, "runs": runs})
	print("recorded in %.1f s" % ((Time.get_ticks_msec() - t) / 1000.0))
	quit()
