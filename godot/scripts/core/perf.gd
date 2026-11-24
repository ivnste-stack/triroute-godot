class_name Perf
extends RefCounted
## Frame-time counters: Perf.begin("name") … Perf.end("name") around the parts of the game's own code.
## Two readers: report() (F3 panel and --perf, averages since its last call) and take_frame() (PerfRecorder,
## what each single frame spent). Sections may nest (co_day runs inside game_session._process): a reader
## sees both, the outer one includes the inner.

static var acc := {}       # µs since the last report()
static var frame := {}     # µs in the frame going on
static var _t := {}


static func begin(k: String) -> void:
	_t[k] = Time.get_ticks_usec()


static func end(k: String) -> void:
	var d: int = Time.get_ticks_usec() - _t.get(k, Time.get_ticks_usec())
	acc[k] = acc.get(k, 0) + d
	frame[k] = frame.get(k, 0) + d


## what the frame that just ended spent, section by section (µs); starts the next one
static func take_frame() -> Dictionary:
	var f := frame
	frame = {}
	return f


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


## --perf on the command line: a line per game day with what the day cost
static var verbose: bool = "--perf" in OS.get_cmdline_user_args()


static func off(k: String) -> bool:
	if _off == null:
		_off = []
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--off="):
				_off = a.substr(6).split(",")
	return _off.has(k)
