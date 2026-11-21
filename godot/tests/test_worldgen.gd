extends RefCounted
## World generator (native TRWorldGen): the same seed must give the same world as the HTML version.
## world_fingerprints.json holds MD5 hashes of the HTML generator's arrays (made by legacy/tests/worldref.js).

func _fp() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/world_fingerprints.json"))


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
