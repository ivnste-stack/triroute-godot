extends RefCounted
## Core tests: the RNG and noise must match the HTML version bit for bit (vectors in rng_vectors.json
## were produced by the legacy JS code; RNG values are stored as raw 32-bit integers), plus the calendar.

func _vectors() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/rng_vectors.json"))


func test_mulberry_matches_legacy() -> String:
	var v := _vectors()
	for seed_str in ["0", "1", "777", "123456789", "-5", "4294967295"]:
		var r := Mulberry.new(int(seed_str))
		var want: Array = v[seed_str]
		for i in want.size():
			var got := int(r.next() * 4294967296.0)   # the raw 32-bit output, compared exactly
			if got != int(want[i]):
				return "seed %s #%d: got %d, want %d" % [seed_str, i, got, int(want[i])]
	return ""


func test_perlin_matches_legacy() -> String:
	var v := _vectors()
	var p := Perlin.new(Mulberry.new((777 ^ 0x77) & 0xFFFFFFFF))
	for row in v["perlin"]:
		var got := p.noise(row[0], row[1])
		if absf(got - float(row[2])) > 1e-12:
			return "perlin(%s,%s): got %.17f, want %.17f" % [row[0], row[1], got, row[2]]
	return ""


func test_calendar() -> String:
	var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")
	if gs == null:
		return "GameState autoload is missing"
	gs.reset(1)
	gs.date = {"d": 31, "m": 11, "y": 2026}
	gs.advance_days(1)
	var d: Dictionary = gs.date
	if d.d != 1 or d.m != 0 or d.y != 2027:
		return "31 Dec + 1 day = %s" % [d]
	gs.advance_days(59)   # 2027 is not a leap year: 1 Jan + 59 days = 1 Mar
	if gs.date.d != 1 or gs.date.m != 2:
		return "1 Jan + 59 days = %s" % [gs.date]
	return ""
