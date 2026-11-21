extends RefCounted
## Game logic (scripts/logistics/sim.gd) against the HTML version. A new game is deterministic up to the first
## order board, so these compare exactly: places' continents, the company name, the headquarters, competitors,
## manager candidates and every field of every order on the starting board (company_fingerprints.json, made
## from legacy/tests/companyref.js).

func _fp() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/company_fingerprints.json"))


func _f64(hex: String) -> float:
	return hex.hex_decode().decode_double(0)


func _same(got: Variant, want: Variant) -> bool:
	if want is String and want.length() == 16 and want.is_valid_hex_number():
		return got is float and got == _f64(want) or (got is int and float(got) == _f64(want))
	if want is float or want is int:
		return (got is int or got is float) and float(got) == float(want)
	return got == want


func _new_game(seed_value: int) -> Sim:
	var gen: Object = ClassDB.instantiate("TRWorldGen")
	gen.generate(seed_value)
	var states: Array = gen.generate_states()
	var board: Dictionary = gen.generate_board()
	var sim := Sim.new()
	sim.setup(gen, seed_value, states, board)
	var choices := sim.start_choices()
	sim.co_init(choices[0].id)
	sim.co_set_hq(choices[0].id)
	return sim


func test_company_start_matches_html() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp := _fp()
	for seed_str in fp.keys():
		var want: Dictionary = fp[seed_str]
		var t := Time.get_ticks_msec()
		var sim := _new_game(int(seed_str))
		var ms := Time.get_ticks_msec() - t
		for i in sim.PL.size():
			if sim.PL[i].land != int(want.lands[i]):
				return "seed %s: continent of place %d: %d, want %d" % [seed_str, i, sim.PL[i].land, want.lands[i]]
		if sim.CO.name != want.name or sim.CO.hq != int(want.hq):
			return "seed %s: company %s at %d, want %s at %d" % [seed_str, sim.CO.name, sim.CO.hq, want.name, want.hq]
		for i in want.comp.size():
			var c: Dictionary = sim.CO.comp[i]
			if c.n != want.comp[i][0] or c.rev != _f64(want.comp[i][1]) or c.g != _f64(want.comp[i][2]):
				return "seed %s: competitor %d differs" % [seed_str, i]
		if sim.CO.board.size() != want.board.size():
			return "seed %s: %d orders on the board, want %d" % [seed_str, sim.CO.board.size(), want.board.size()]
		for i in want.board.size():
			var w: Dictionary = want.board[i]
			var g: Dictionary = sim.CO.board[i]
			for key in w.keys():
				if not g.has(key) or not _same(g[key], w[key]):
					return "seed %s: order %d, %s = %s, want %s" % [seed_str, i, key, g.get(key), (_f64(w[key]) if w[key] is String and w[key].length() == 16 else w[key])]
			for key in g.keys():
				if not w.has(key):
					return "seed %s: order %d has an extra field %s" % [seed_str, i, key]
		for id in want.cand.keys():
			for i in 3:
				var m: Dictionary = sim.CO.cand[id][i]
				var e: Array = want.cand[id][i]
				if m.name != e[0] or m.age != int(e[1]) or m.skill != int(e[2]) or m.sal != int(e[3]) or m.trait != e[4] or m.honest != e[5] or m.loyal != int(e[6]):
					return "seed %s: manager candidate %s #%d: %s, want %s" % [seed_str, id, i, m, e]
		print("       seed %s: «%s», %d orders on the board, %d manager candidates — identical to HTML (%d ms)" % [seed_str, sim.CO.name, sim.CO.board.size(), sim.CO.cand.size() * 3, ms])
	return ""
