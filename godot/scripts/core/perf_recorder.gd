class_name PerfRecorder
extends Node
## The performance recorder (F4, or Settings → Гра): while it runs, a plain-text report grows in
## user://perf/, made to be read back and acted on:
##   · the computer and the settings (video card, driver, CPU, window, scale, VSync, frame limit, quality);
##   · every second: FPS, frame times (average, 95th percentile, worst), the CPU and GPU time of rendering
##     (the screen and the cached layers), draw calls, objects, memory, and the state of the game (speed,
##     zoom, open window, trips, vehicles, orders, map layer);
##   · every slow frame ("spike"): how long it took and what the game's code spent in it, part by part;
##   · at the end: a summary — frame-time percentiles, the costliest parts over the whole run, what the
##     spikes were made of.
## Times of the game's code come from Perf sections; sections nest (game_session._process holds co_day and
## sim.frame), so a part may be counted inside a bigger one.

signal state_changed(on: bool, path: String)

## sections that run inside another one (their time is already in the outer section)
const NESTED := ["co_day", "sim.frame", "town_layer.layout", "window.build"]

var context: Callable              # → Dictionary: the state of the game for the per-second line
var viewports: Callable            # → {name: SubViewport}: cached layers whose rendering is measured too
var recording := false
var path := ""

var _f: FileAccess
var _t0 := 0.0
var _sec_t := 0.0
var _sec_dts: PackedFloat32Array = PackedFloat32Array()
var _sec_parts := {}
var _all_dts: PackedFloat32Array = PackedFloat32Array()
var _all_parts := {}
var _all_frames := 0
var _spikes := 0
var _spike_parts := {}
var _skip := 2                     # the first frames after a start carry the start itself


func _ready() -> void:
	process_priority = -1000   # first in a frame: it closes the frame before, whose sections are complete
	process_mode = Node.PROCESS_MODE_ALWAYS


func toggle() -> void:
	if recording:
		stop()
	else:
		start()


func start() -> void:
	if recording:
		return
	DirAccess.make_dir_recursive_absolute("user://perf")
	path = "user://perf/perf-%s.txt" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		push_warning("PerfRecorder: cannot write " + path)
		return
	recording = true
	_t0 = Time.get_ticks_msec() / 1000.0
	_sec_t = 0.0
	_sec_dts = PackedFloat32Array()
	_sec_parts = {}
	_all_dts = PackedFloat32Array()
	_all_parts = {}
	_all_frames = 0
	_spikes = 0
	_spike_parts = {}
	_skip = 2
	Perf.take_frame()
	_measure(true)
	_header()
	state_changed.emit(true, ProjectSettings.globalize_path(path))


func stop() -> void:
	if not recording:
		return
	recording = false
	_summary()
	_f.close()
	_f = null
	_measure(false)
	state_changed.emit(false, ProjectSettings.globalize_path(path))


func _exit_tree() -> void:
	stop()


func _measure(on: bool) -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), on)
	for vp in _vps().values():
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), on)


func _vps() -> Dictionary:
	return viewports.call() if viewports.is_valid() else {}


func _w(line: String) -> void:
	_f.store_line(line)


# ---------- the head of the report ----------
func _header() -> void:
	var win := get_window()
	_w("# TriRoute — запис продуктивності · TriRoute performance record")
	_w("started   %s" % Time.get_datetime_string_from_system(false, true))
	_w("build     %s · Godot %s" % ["debug (editor / debug export)" if OS.is_debug_build() else "release", Engine.get_version_info().string])
	_w("os        %s %s" % [OS.get_name(), OS.get_version()])
	_w("cpu       %s · %d threads" % [OS.get_processor_name(), OS.get_processor_count()])
	_w("gpu       %s · %s · %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version()])
	_w("renderer  %s · %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method()])
	_w("screen    %s · window %dx%d · mode %d · ui scale %.2f · refresh %.0f Hz" % [DisplayServer.screen_get_size(win.current_screen), win.size.x, win.size.y, win.mode, win.content_scale_factor, DisplayServer.screen_get_refresh_rate(win.current_screen)])
	var keys := ["preset", "vsync", "fps", "idle_fps", "res", "upscale", "aa", "aniso", "blur", "glint", "trails", "daynight", "ui_scale", "window"]
	_w("settings  " + " · ".join(keys.map(func(k): return "%s=%s" % [k, Settings.get_value(k)])))
	_w("limits    Engine.max_fps=%d · vsync mode=%d" % [Engine.max_fps, DisplayServer.window_get_vsync_mode()])
	_w("")
	_w("Every second:  t  fps  frame avg/p95/max ms | render cpu/gpu ms (+ layers gpu) | draws objs | mem MB vram MB | game")
	_w("Spikes:        SPIKE t  frame ms  = the game's code parts in that frame (ms, nested parts included in outer ones)")
	_w("")
	_f.flush()


# ---------- every frame ----------
func _process(delta: float) -> void:
	var parts := Perf.take_frame()   # the frame that just ended
	if not recording:
		return
	if _skip > 0:
		_skip -= 1
		return
	var ms := delta * 1000.0
	_sec_dts.append(ms)
	_all_dts.append(ms)
	_all_frames += 1
	for k in parts:
		var v: float = parts[k] / 1000.0
		_sec_parts[k] = _sec_parts.get(k, 0.0) + v
		_all_parts[k] = _all_parts.get(k, 0.0) + v
	# a slow frame: twice the frame time of the target rate (or of 60 FPS), at least 12 ms
	var target := 1000.0 / float(Engine.max_fps if Engine.max_fps > 0 else 60)
	if ms > maxf(12.0, target * 2.0):
		_spikes += 1
		var ks := parts.keys()
		ks.sort_custom(func(a, b): return parts[a] > parts[b])
		var top: Array = ks.slice(0, 8).map(func(k): return "%s %.2f" % [k, parts[k] / 1000.0])
		# the game's code is the outer sections only (nested ones are inside them); the rest of the frame went
		# to the engine: rendering, waiting for the video card or VSync, the OS
		var outer := 0.0
		for k in ks:
			if not (k in NESTED):
				outer += parts[k] / 1000.0
		var vp := get_viewport().get_viewport_rid()
		var rc := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		var rg := RenderingServer.viewport_get_measured_render_time_gpu(vp)
		# the frame is put down to the game's costliest part when the code took a good share of it, else to the engine
		var cause: String = ks[0] if ks.size() and outer >= ms * .4 else "engine: rendering / GPU / VSync / OS"
		_spike_parts[cause] = _spike_parts.get(cause, 0) + 1
		_w("SPIKE %7.2f  %6.1f ms  code %.1f ms · render cpu %.1f gpu %.1f  = %s" % [_now(), ms, outer, rc, rg, ", ".join(top) if top.size() else "nothing in the game's code"])
	_sec_t += delta
	if _sec_t >= 1.0:
		_second()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0 - _t0


func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[mini(b.size() - 1, int(floor(p * b.size())))]


func _second() -> void:
	var n := _sec_dts.size()
	var sum := 0.0
	var mx := 0.0
	for d in _sec_dts:
		sum += d
		mx = maxf(mx, d)
	var vp := get_viewport().get_viewport_rid()
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var lay := []
	for nm in _vps():
		var v: SubViewport = _vps()[nm]
		lay.append("%s %.2f" % [nm, RenderingServer.viewport_get_measured_render_time_gpu(v.get_viewport_rid())])
	var game := ""
	if context.is_valid():
		var c: Dictionary = context.call()
		game = " ".join(c.keys().map(func(k): return "%s=%s" % [k, c[k]]))
	_w("%7.2f  %4d fps  %5.1f/%5.1f/%5.1f | %5.2f/%5.2f (%s) | %d %d | %.0f %.0f | %s" % [_now(), roundi(n / _sec_t), sum / maxi(1, n), _pct(_sec_dts, .95), mx,
		cpu, gpu, ", ".join(lay), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, game])
	# the code of this second, ms a frame (the costliest parts)
	var ks := _sec_parts.keys()
	ks.sort_custom(func(a, b): return _sec_parts[a] > _sec_parts[b])
	if ks.size():
		_w("         code ms/frame: " + ", ".join(ks.slice(0, 8).map(func(k): return "%s %.2f" % [k, _sec_parts[k] / maxi(1, n)])))
	_f.flush()
	_sec_t = 0.0
	_sec_dts = PackedFloat32Array()
	_sec_parts = {}


# ---------- the end ----------
func _summary() -> void:
	_w("")
	_w("# Summary")
	var n := _all_frames
	var sum := 0.0
	for d in _all_dts:
		sum += d
	_w("recorded  %.1f s · %d frames · %.0f fps on average" % [_now(), n, n / maxf(.001, sum / 1000.0)])
	_w("frame ms  avg %.2f · p50 %.2f · p90 %.2f · p95 %.2f · p99 %.2f · max %.2f" % [sum / maxi(1, n), _pct(_all_dts, .5), _pct(_all_dts, .9), _pct(_all_dts, .95), _pct(_all_dts, .99), _pct(_all_dts, 1.0)])
	var over := func(lim: float) -> int:
		var c := 0
		for d in _all_dts:
			if d > lim:
				c += 1
		return c
	_w("slow      >8.3 ms (120 fps): %d · >16.7 ms (60 fps): %d · >33 ms: %d · spikes recorded: %d" % [over.call(8.34), over.call(16.7), over.call(33.4), _spikes])
	_w("")
	_w("The game's code over the whole run (ms a frame on average · share of the frame time):")
	var ks := _all_parts.keys()
	ks.sort_custom(func(a, b): return _all_parts[a] > _all_parts[b])
	for k in ks.slice(0, 20):
		_w("  %-32s %7.3f ms  %5.1f%%" % [k, _all_parts[k] / maxi(1, n), 100.0 * _all_parts[k] / maxf(.001, sum)])
	if _spike_parts.size():
		_w("")
		_w("What the spikes were made of (the costliest part of each slow frame):")
		var sk := _spike_parts.keys()
		sk.sort_custom(func(a, b): return _spike_parts[a] > _spike_parts[b])
		for k in sk:
			_w("  %-40s %d" % [k, _spike_parts[k]])
	_w("")
	_w("ended     %s" % Time.get_datetime_string_from_system(false, true))
