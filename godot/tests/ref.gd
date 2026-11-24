extends RefCounted
## Reference data of the tests: what the game produced when the references were last recorded
## (tests/record_refs.gd). The tests compare the game with it, so a change in the generator or the
## simulation shows up; a change made on purpose is recorded again:
##   godot --headless --path godot -s res://tests/record_refs.gd
## Doubles are kept as 16 hex digits (IEEE-754, little-endian), so the comparison is exact.

const DIR := "res://tests/"


static func h(x: float) -> String:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, x)
	return b.hex_encode()


static func f64(hex: String) -> float:
	return hex.hex_decode().decode_double(0)


static func md5(bytes: PackedByteArray) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_MD5)
	c.update(bytes)
	return c.finish().hex_encode()


## a value as it is stored: doubles as hex, everything else as is (dictionaries and arrays inside too)
static func enc(v: Variant) -> Variant:
	if v is float:
		return h(v)
	if v is Dictionary:
		var o := {}
		for k in v:
			o[str(k)] = enc(v[k])
		return o
	if v is Array:
		return v.map(func(x): return enc(x))
	if v is PackedInt32Array or v is PackedInt64Array:
		return Array(v)
	if v is PackedFloat32Array or v is PackedFloat64Array:
		return Array(v).map(func(x): return h(x))
	return v


## through JSON and back: the computed value in the same shape as the one read from a file
static func norm(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v, "", false, true))


static func read(name: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + name))


static func write(name: String, data: Variant, indent := "") -> void:
	var f := FileAccess.open(DIR + name, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, indent, false, true))
	f.close()


static func _show(v: Variant) -> String:
	if v is String and v.length() == 16 and v.is_valid_hex_number():
		return str(f64(v))
	return str(v).left(300)


## "" when got is the same as want, else where they first differ
static func diff(got: Variant, want: Variant, path := "") -> String:
	if want is Dictionary:
		if not got is Dictionary:
			return "%s: %s, want a dictionary" % [path, _show(got)]
		for k in want:
			if not got.has(k):
				return "%s.%s is missing" % [path, k]
			var d := diff(got[k], want[k], "%s.%s" % [path, k])
			if d != "":
				return d
		for k in got:
			if not want.has(k):
				return "%s.%s is new" % [path, k]
		return ""
	if want is Array:
		if not got is Array:
			return "%s: %s, want a list" % [path, _show(got)]
		for i in mini(got.size(), want.size()):
			var d := diff(got[i], want[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		if got.size() != want.size():
			return "%s: %d items, want %d" % [path, got.size(), want.size()]
		return ""
	if want is float or want is int:
		if (got is float or got is int) and float(got) == float(want):
			return ""
		return "%s: %s, want %s" % [path, _show(got), _show(want)]
	if str(got) == str(want):
		return ""
	if got is String and want is String and " " in want:   # a list written as one line: the first item that differs
		var gs: PackedStringArray = got.split(" ")
		var ws: PackedStringArray = want.split(" ")
		for i in maxi(gs.size(), ws.size()):
			var a: String = gs[i] if i < gs.size() else "—"
			var b: String = ws[i] if i < ws.size() else "—"
			if a != b:
				return "%s #%d: %s, want %s" % [path, i, a, b]
	return "%s: %s, want %s" % [path, _show(got), _show(want)]
