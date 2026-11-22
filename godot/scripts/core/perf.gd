class_name Perf
extends RefCounted
## Frame-time counters for --perf: Perf.begin("name") … Perf.end("name"); main prints the averages each second.

static var acc := {}
static var _t := {}


static func begin(k: String) -> void:
	_t[k] = Time.get_ticks_usec()


static func end(k: String) -> void:
	acc[k] = acc.get(k, 0) + Time.get_ticks_usec() - _t.get(k, Time.get_ticks_usec())


static func report(frames: int) -> String:
	var ks := acc.keys()
	ks.sort_custom(func(a, b): return acc[a] > acc[b])
	var out := []
	for k in ks:
		out.append("%s %.2f" % [k, acc[k] / 1000.0 / maxi(1, frames)])
	acc = {}
	return ", ".join(out)


## --off=a,b: parts switched off to see what a frame costs (glass, inc, veh, town, overlay, hud, map)
static var _off: Variant = null


static func off(k: String) -> bool:
	if _off == null:
		_off = []
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--off="):
				_off = a.substr(6).split(",")
	return _off.has(k)
