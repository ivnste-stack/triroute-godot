class_name PerfPanel
extends PanelContainer
## F3: what a frame costs on this computer. FPS, the CPU and GPU time of a frame (measured by the rendering
## server), the video card and the renderer in use, the screen and interface scale, draw calls, and the parts
## of the game's own code that take the most time. A screenshot of it says where the frames go.

var _l: Label
var _n := 0
var _t := 0.0
var _worst := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", Ui.box(Color(0.03, 0.05, 0.08, .92), Ui.LINE_HI, 1, Vector4(12, 10, 12, 10)))
	_l = Ui.label("", 12, Ui.FG, Ui.font("mono", 500))
	add_child(_l)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(get_viewport_rect().size.x - 440, 84)


func toggle() -> void:
	visible = not visible
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), visible)
	_n = 0
	_t = 0.0
	_worst = 0.0
	Perf.acc = {}


func _process(delta: float) -> void:
	if not visible:
		return
	_n += 1
	_t += delta
	_worst = maxf(_worst, delta)
	if _t < 1.0:
		return
	var vp := get_viewport().get_viewport_rid()
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var win := get_window()
	var lines := [
		"FPS %d · найдовший кадр %.1f мс" % [roundi(_n / _t), _worst * 1000],
		"Цикл process %.1f мс · фізика %.1f мс" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000],
		"Рендер: CPU %.1f мс · GPU %.1f мс" % [cpu, gpu],
		"Draw calls %d · об'єктів %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)],
		"Відеокарта: %s" % RenderingServer.get_video_adapter_name(),
		"Драйвер: %s · %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method()],
		"Вікно %dx%d · масштаб %.2f · VSync %s" % [win.size.x, win.size.y, win.content_scale_factor, ["вимк", "увімк", "adaptive", "mailbox"][DisplayServer.window_get_vsync_mode()]],
		"Збірка: %s" % ("debug (з редактора)" if OS.is_debug_build() else "release"),
		"",
		"Найдорожче в коді, мс/кадр:"]
	var parts: String = Perf.report(_n)
	for p in parts.split(", ").slice(0, 7):
		lines.append("  " + p)
	_l.text = "\n".join(lines)
	position = Vector2(get_viewport_rect().size.x - size.x - 14, 84)
	_n = 0
	_t = 0.0
	_worst = 0.0
