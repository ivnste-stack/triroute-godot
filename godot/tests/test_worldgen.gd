extends RefCounted
## World generator (native TRWorldGen): the same seed must give the same world as the HTML version.
## world_fingerprints.json holds MD5 hashes of the HTML generator's arrays (made by legacy/tests/worldref.js).

func _fp() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/world_fingerprints.json"))


## a double stored as 16 hex digits (little-endian IEEE-754)
func _f64(hex: String) -> float:
	return hex.hex_decode().decode_double(0)


func _md5(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(bytes)
	return h.finish().hex_encode()


func test_native_module_loaded() -> String:
	return "" if ClassDB.class_exists("TRWorldGen") else "TRWorldGen is not registered (bin/triroute.gdextension not loaded)"


func test_worlds_match_html() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp := _fp()
	for seed_str in fp.keys():
		var want: Dictionary = fp[seed_str]
		var gen: Object = ClassDB.instantiate("TRWorldGen")
		var t := Time.get_ticks_msec()
		var w: Dictionary = gen.generate(int(seed_str))
		var ms := Time.get_ticks_msec() - t
		if _md5(w.own) != want.own:
			return "seed %s: state map differs" % seed_str
		if _md5(w.height.to_byte_array()) != want.height:
			return "seed %s: height map differs" % seed_str
		if _md5(w.sqd) != want.sqd:
			return "seed %s: lattice differs" % seed_str
		if w.T != float(want.T) or w.land_count != int(want.land):
			return "seed %s: land threshold %s / %s, want %s / %s" % [seed_str, w.T, w.land_count, want.T, want.land]
		if w.countries.size() != int(want.countries):
			return "seed %s: %d states, want %d" % [seed_str, w.countries.size(), want.countries]
		var c0: Dictionary = w.countries[0]
		if c0.lx != int(want.first_country.lx) or c0.ly != int(want.first_country.ly) or Array(c0.neighbors) != want.first_country.neighbors.map(func(v): return int(v)):
			return "seed %s: first state %s" % [seed_str, c0]
		print("       seed %s: identical to HTML, %d ms" % [seed_str, ms])
	return ""


func test_boards_match_html() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp := _fp()
	for seed_str in fp.keys():
		var want: Dictionary = fp[seed_str].board
		var gen: Object = ClassDB.instantiate("TRWorldGen")
		gen.generate(int(seed_str))
		var t := Time.get_ticks_msec()
		var b: Dictionary = gen.generate_board()   # uses the states' own populations (generate_states)
		var ms := Time.get_ticks_msec() - t
		var parts := PackedStringArray()
		for tw in b.towns:
			parts.append("%s:%s:%d:%d:%s%s" % [tw.name, tw.type, tw.cid, tw.node, "P" if tw.port else "", "A" if tw.air_ov else ""])
		if b.towns.size() != int(want.towns) or _md5("|".join(parts).to_utf8_buffer()) != want.towns_md5:
			return "seed %s: towns differ (%d, want %d; first %s)" % [seed_str, b.towns.size(), want.towns, b.towns[0] if b.towns.size() else {}]
		if b.towns[0].pop != _f64(want.first_town.pop):
			return "seed %s: first town population %s, want %s" % [seed_str, b.towns[0].pop, _f64(want.first_town.pop)]
		if _md5(b.bits) != want.bits or _md5(b.rbits) != want.rbits:
			return "seed %s: road or rail graph differs" % seed_str
		if b.roads.size() != int(want.roads) or b.railways.size() != int(want.railways) or b.checkpoints.size() != int(want.checkpoints):
			return "seed %s: %d roads / %d railways / %d checkpoints, want %s / %s / %s" % [seed_str, b.roads.size(), b.railways.size(), b.checkpoints.size(), want.roads, want.railways, want.checkpoints]
		print("       seed %s: %d towns, %d roads, %d railways, %d checkpoints — identical to HTML, %d ms" % [seed_str, b.towns.size(), b.roads.size(), b.railways.size(), b.checkpoints.size(), ms])
	return ""


func test_states_match_html() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp := _fp()
	for seed_str in fp.keys():
		var want: Dictionary = fp[seed_str].states
		var gen: Object = ClassDB.instantiate("TRWorldGen")
		gen.generate(int(seed_str))
		var st: Array = gen.generate_states()
		var parts := PackedStringArray()
		for c in st:
			parts.append("%s:%s:%s:%s:%s:%d" % [c.name, c.color, c.ideol, c.trait, c.leader, c.leader_age])
		if st.size() != int(want.n) or _md5("|".join(parts).to_utf8_buffer()) != want.md5:
			return "seed %s: states differ (first: %s)" % [seed_str, st[0].name if st.size() else "-"]
		if st[0].pop != _f64(want.pop0) or st[0].dev != _f64(want.dev0) or st[0].stability != _f64(want.stab0):
			return "seed %s: first state numbers differ" % seed_str
		print("       seed %s: %d states (%s, %s…) — identical to HTML" % [seed_str, st.size(), st[0].name, st[1].name])
	return ""


## Route search (boardPath / boardSea): road, rail and sea paths between sample town pairs, like the HTML version
func test_routes_match_html() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp := _fp()
	var checked := 0
	for seed_str in fp.keys():
		if not fp[seed_str].has("routes"):
			continue
		var want: Dictionary = fp[seed_str].routes
		var gen: Object = ClassDB.instantiate("TRWorldGen")
		gen.generate(int(seed_str))
		var b: Dictionary = gen.generate_board()
		var n: int = b.towns.size()
		var h := HashingContext.new()
		h.start(HashingContext.HASH_MD5)
		var cnt := 0
		var t := Time.get_ticks_usec()
		for i in range(0, n, 3):
			var j := (i * 13 + 5) % n
			if i == j:
				continue
			cnt += 1
			var rail_ok: bool = b.rbits[b.towns[i].node] != 0 and b.rbits[b.towns[j].node] != 0
			var sea_ok: bool = b.towns[i].wc_i >= 0 and b.towns[j].wc_i >= 0
			for r in [gen.route("road", i, j), gen.route("rail", i, j) if rail_ok else PackedFloat32Array(), gen.route("sea", i, j) if sea_ok else PackedFloat32Array()]:
				h.update("-".to_utf8_buffer() if r.is_empty() else r.to_byte_array())
				h.update("|".to_utf8_buffer())
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		if cnt != int(want.n) or h.finish().hex_encode() != want.md5:
			return "seed %s: routes differ from the HTML version" % seed_str
		checked += 1
		print("       seed %s: %d road/rail/sea routes identical to HTML, %.0f ms" % [seed_str, cnt * 3, ms])
	return "" if checked else "no reference routes"


## coastlines and state borders (TRWorldGen.lines, extractSqLines) against the HTML version: the number of lines
## and points, the pairs of the first lines in order and a weighted sum of every coordinate
func test_lines_match_html() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/lines_fingerprints.json"))
	for seed_str in fp.keys():
		var want: Dictionary = fp[seed_str]
		var gen: Object = ClassDB.instantiate("TRWorldGen")
		gen.generate(int(seed_str))
		var L: Array = gen.lines()
		var n := 0
		var s := 0.0
		var coast := 0
		for l in L:
			n += l.p.size() / 2
			if l.a == 0:
				coast += 1
			for i in l.p.size():
				s += l.p[i] * ((i % 7) + 1)
		if L.size() != int(want.lines) or n != int(want.pts) or coast != int(want.coast):
			return "seed %s: %d lines (%d coast), %d points; want %d (%d), %d" % [seed_str, L.size(), coast, n, want.lines, want.coast, want.pts]
		for i in want.ab.size():
			if L[i].a * 256 + L[i].b != int(want.ab[i]):
				return "seed %s: line %d is %d-%d" % [seed_str, i, L[i].a, L[i].b]
		if absf(s - float(want.sum)) > 1e-6 * absf(float(want.sum)):
			return "seed %s: coordinates differ (sum %f, want %f)" % [seed_str, s, want.sum]
		print("       seed %s: %d lines, %d points — identical to HTML" % [seed_str, L.size(), n])
	return ""

