extends RefCounted
## World generator (native TRWorldGen) against its references (tests/ref.gd): the same seed must give the
## same world — the maps, the towns and roads, the states, routes between towns, coastlines and borders.
## world_fingerprints.json and lines_fingerprints.json are recorded from the game by tests/record_refs.gd.

const Ref = preload("res://tests/ref.gd")
const SEEDS := [777, 303, 123456]


static func _gen(seed_value: int) -> Object:
	var gen: Object = ClassDB.instantiate("TRWorldGen")
	gen.generate(seed_value)
	return gen


## the maps of a world: states, heights, the lattice, the land threshold, the first state
static func world_fp(seed_value: int) -> Dictionary:
	var gen: Object = ClassDB.instantiate("TRWorldGen")
	var w: Dictionary = gen.generate(seed_value)
	var c0: Dictionary = w.countries[0]
	return Ref.norm({"own": Ref.md5(w.own), "height": Ref.md5(w.height.to_byte_array()), "sqd": Ref.md5(w.sqd), "T": Ref.h(w.T),
		"land": w.land_count, "countries": w.countries.size(), "first_country": {"lx": c0.lx, "ly": c0.ly, "neighbors": Array(c0.neighbors)}})


## the towns, roads, railways and checkpoints
static func board_fp(gen: Object) -> Dictionary:
	var b: Dictionary = gen.generate_board()   # uses the states' own populations (generate_states)
	var parts := PackedStringArray()
	var pops := PackedStringArray()
	for tw in b.towns:
		parts.append("%s:%s:%d:%d:%s%s" % [tw.name, tw.type, tw.cid, tw.node, "P" if tw.port else "", "A" if tw.air_ov else ""])
		pops.append(Ref.h(tw.pop))
	return Ref.norm({"towns": b.towns.size(), "towns_md5": Ref.md5("|".join(parts).to_utf8_buffer()), "pops_md5": Ref.md5(" ".join(pops).to_utf8_buffer()),
		"bits": Ref.md5(b.bits), "rbits": Ref.md5(b.rbits), "roads": b.roads.size(), "railways": b.railways.size(), "checkpoints": b.checkpoints.size()})


static func states_fp(gen: Object) -> Dictionary:
	var st: Array = gen.generate_states()
	var parts := PackedStringArray()
	for c in st:
		parts.append("%s:%s:%s:%s:%s:%d:%s:%s:%s" % [c.name, c.color, c.ideol, c.trait, c.leader, c.leader_age, Ref.h(c.pop), Ref.h(c.dev), Ref.h(c.stability)])
	return Ref.norm({"n": st.size(), "md5": Ref.md5("|".join(parts).to_utf8_buffer()), "first": st[0].name if st.size() else ""})


## road, rail and sea paths between sample town pairs
static func routes_fp(gen: Object) -> Dictionary:
	var b: Dictionary = gen.generate_board()
	var n: int = b.towns.size()
	var c := HashingContext.new()
	c.start(HashingContext.HASH_MD5)
	var cnt := 0
	for i in range(0, n, 3):
		var j := (i * 13 + 5) % n
		if i == j:
			continue
		cnt += 1
		var rail_ok: bool = b.rbits[b.towns[i].node] != 0 and b.rbits[b.towns[j].node] != 0
		var sea_ok: bool = b.towns[i].wc_i >= 0 and b.towns[j].wc_i >= 0
		for r in [gen.route("road", i, j), gen.route("rail", i, j) if rail_ok else PackedFloat32Array(), gen.route("sea", i, j) if sea_ok else PackedFloat32Array()]:
			c.update("-".to_utf8_buffer() if r.is_empty() else r.to_byte_array())
			c.update("|".to_utf8_buffer())
	return Ref.norm({"n": cnt, "md5": c.finish().hex_encode()})


## coastlines and state borders: the number of lines and points, the pairs of the first lines in order and
## every coordinate
static func lines_fp(gen: Object) -> Dictionary:
	var L: Array = gen.lines()
	var n := 0
	var coast := 0
	var ab := []
	var c := HashingContext.new()
	c.start(HashingContext.HASH_MD5)
	for l in L:
		n += l.p.size() / 2
		if l.a == 0:
			coast += 1
		if ab.size() < 50:
			ab.append(l.a * 256 + l.b)
		c.update(l.p.to_byte_array())
	return Ref.norm({"lines": L.size(), "pts": n, "coast": coast, "ab": ab, "md5": c.finish().hex_encode()})


## every reference of one seed, in the layout of world_fingerprints.json
static func all_fp(seed_value: int) -> Dictionary:
	var o := {"world": world_fp(seed_value), "states": states_fp(_gen(seed_value))}
	for part in ["board", "routes"]:
		var gen := _gen(seed_value)
		gen.generate_states()
		o[part] = board_fp(gen) if part == "board" else routes_fp(gen)
	return o


func _check(part: String, what: String) -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp: Dictionary = Ref.read("world_fingerprints.json")
	for seed_str in fp:
		var t := Time.get_ticks_msec()
		var got: Dictionary
		if part == "world":
			got = world_fp(int(seed_str))
		else:
			var gen := _gen(int(seed_str))
			if part != "states":
				gen.generate_states()
			got = {"states": states_fp, "board": board_fp, "routes": routes_fp}[part].call(gen)
		var d := Ref.diff(got, fp[seed_str][part], "seed %s %s" % [seed_str, part])
		if d != "":
			return d
		print("       seed %s: %s as recorded (%d ms)" % [seed_str, what, Time.get_ticks_msec() - t])
	return ""


func test_native_module_loaded() -> String:
	return "" if ClassDB.class_exists("TRWorldGen") else "TRWorldGen is not registered (bin/triroute.gdextension not loaded)"


func test_worlds_match_reference() -> String:
	return _check("world", "maps")


func test_states_match_reference() -> String:
	return _check("states", "states")


func test_boards_match_reference() -> String:
	return _check("board", "towns, roads, railways, checkpoints")


func test_routes_match_reference() -> String:
	return _check("routes", "road/rail/sea routes")


func test_lines_match_reference() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var fp: Dictionary = Ref.read("lines_fingerprints.json")
	for seed_str in fp:
		var d := Ref.diff(lines_fp(_gen(int(seed_str))), fp[seed_str], "seed %s lines" % seed_str)
		if d != "":
			return d
		print("       seed %s: %d lines, %d points — as recorded" % [seed_str, fp[seed_str].lines, fp[seed_str].pts])
	return ""
