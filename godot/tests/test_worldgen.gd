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
		var pops := PackedFloat64Array()
		for p in want.pops:
			pops.append(_f64(p))   # stored as raw IEEE-754 bytes: JSON and to_float() both round the last bit
		var b: Dictionary = gen.generate_board(pops)
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
