extends Node
## The game: the main menu, a new game (size, difficulty, seed), the world generation, the choice of the
## headquarters, then the map with the interface (HUD, windows, dialogs). F9 — the checks (all tests, green/red).
## Command line (automatic screenshots): godot --path godot -- [--seed=777] [--shot=path.png] [--cam=x,z,dist]
##   [--company [--demo: a fleet with a dispatcher] [--hq=place id]] [--days=N] [--speed=0…3] [--select]
##   [--win=coJobs] [--pick: stop at the choice of the headquarters] [--menu: the main menu]
##   [--plan[=auto]: the planner for the first order] [--place=pid | --country=cid: the card on the right] [--mouse=x,y: hover] [--click=x,y]

const DIFF_N := [[0, "Навчальна"], [1, "Звичайна"], [2, "Жорстка"]]
const SIZE_N := [["s", "Мала · 2×1"], ["m", "Середня · 3×2"], ["l", "Велика · 4×3"]]
const DEC_ICON := {"acc": ["alert", "bad"], "brk": ["gear", "warn"], "theft": ["skull", "bad"], "pir": ["skull", "bad"], "cxl": ["doc", "warn"],
	"strike": ["fist", "bad"], "thief": ["coins", "bad"], "raise": ["briefcase", "warn"]}

var map: MapView
var session: GameSession
var hud: Hud
var modals: ModalLayer
var win: WindowPanel
var wins: Windows
var toasts: Toasts
var map_ui: MapUi
var tips: TipLayer
var perf_panel: PerfPanel
var _bb: BackBufferCopy
var planner: Planner
var course: Course
var menu: StartMenu
var _args := {}
var _ng := {"size": "m", "diff": 1, "seed": 0}
var _loading: Control
var _checks: PanelContainer
var _ui: CanvasLayer
var _size_key := "m"
var _pending: Variant = null     # a saved game waiting for its world


## the interface in CSS pixels, like the browser: the system scale (Windows display scaling), or the setting
## the frame limit: the monitor's rate by default (VSync), or a number, or none; quieter when nothing happens
## the window: maximised, a window of the chosen size (centred), borderless or exclusive full screen
func apply_window() -> void:
	if _args.has("shot") or DisplayServer.get_name() == "headless":
		return
	var w := get_window()
	match String(Settings.get_value("window")):
		"window":
			w.mode = Window.MODE_WINDOWED
			var p := String(Settings.get_value("win_size")).split("x")
			var sz := Vector2i(int(p[0]), int(p[1])) if p.size() == 2 else Vector2i(1600, 900)
			var scr := DisplayServer.screen_get_usable_rect(w.current_screen)
			sz = sz.min(scr.size)
			w.size = sz
			w.position = scr.position + (scr.size - sz) / 2
		"borderless":
			w.mode = Window.MODE_FULLSCREEN
		"exclusive":
			w.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:
			w.mode = Window.MODE_MAXIMIZED


## VSync, the frame limit, anti-aliasing, anisotropic filtering and the render resolution of the map
func apply_video() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if Settings.get_value("vsync") else DisplayServer.VSYNC_DISABLED)
	var f := int(Settings.get_value("fps"))
	_fps_cap = f if f > 0 else 0
	Engine.max_fps = _fps_cap
	var vp := get_viewport()
	# the map is one flat plane whose coasts, borders and water triangles are drawn by its shader: MSAA, which
	# smooths only the edges of geometry, cannot see them. FXAA smooths the finished picture; SSAA renders the
	# map larger and shrinks it (supersampling), which smooths everything the shader draws.
	var aa := _aa_mode()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" or aa == "fxaa_ssaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	if map != null:
		map.set_glint(bool(Settings.get_value("glint")))
	vp.anisotropic_filtering_level = clampi(int(Settings.get_value("aniso")), 0, 4) as Viewport.AnisotropicFiltering
	apply_render_scale()


## the map's render resolution (RES_OPTS): the width it is drawn at against the window's real pixels
func apply_render_scale() -> void:
	var vp := get_viewport()
	var res := int(Settings.get_value("res"))
	var phys_w := float(get_window().size.x) if get_window() != null else 1600.0
	var k := clampf(res / maxf(320.0, phys_w), .5, 2.0) if res > 0 else 1.0
	# supersampling: the map's 3D render this many times larger on each side (at most 2, Godot's limit)
	var ss: float = {"ssaa2": 1.5, "ssaa4": 2.0, "fxaa_ssaa": 1.5}.get(_aa_mode(), 1.0)
	var k3 := minf(k * ss, 2.0)
	vp.scaling_3d_scale = k3
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if String(Settings.get_value("upscale")) == "fsr" and k3 < 1 else Viewport.SCALING_3D_MODE_BILINEAR
	_map_k3 = k3
	if map != null:
		map.render_k = k


var _map_k3 := 1.0


## the anti-aliasing mode; the MSAA modes of earlier versions became supersampling
func _aa_mode() -> String:
	var aa := String(Settings.get_value("aa"))
	return {"msaa2": "ssaa2", "msaa4": "ssaa4", "msaa8": "ssaa4"}.get(aa, aa)


## the size the map is rendered at now (for the settings)
func render_size() -> Vector2i:
	return Vector2i((Vector2(get_window().size) * _map_k3).round())


var _fps_cap := 0
var _last_input := 0.0
var _focused := true


func _input(e: InputEvent) -> void:
	if e is InputEventMouse or e is InputEventKey:
		_last_input = Time.get_ticks_msec() / 1000.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


## a 2D map does not need hundreds of frames when nothing moves: 15 in the background, 30 when the game is
## paused and the player has not touched anything for a few seconds, the chosen limit otherwise
func _pace_frames() -> void:
	var cap := _fps_cap
	if not _focused and Settings.get_value("idle_fps"):
		cap = 15
	elif not Settings.get_value("idle_fps"):
		pass
	elif menu != null and menu.visible:
		pass   # the main menu's backgrounds float: every frame counts
	elif (session == null or session.speed == 0) and Time.get_ticks_msec() / 1000.0 - _last_input > 3.0 and not modals.is_open():
		var c := map.camera
		if absf(c.tx - c.ttx) + absf(c.tz - c.ttz) + absf(c.dist - c.tdist) < 1e-4:
			cap = 30
	if Engine.max_fps != cap:
		Engine.max_fps = cap


func apply_ui_scale() -> void:
	Ui.set_blur(bool(Settings.get_value("blur")))
	var sc := float(Settings.get_value("ui_scale"))
	if sc <= 0:
		sc = DisplayServer.screen_get_scale()
		if OS.get_name() == "Windows":
			sc = DisplayServer.screen_get_dpi() / 96.0
		sc = clampf(snappedf(sc, .25), 1.0, 3.0)
	if _args.has("scale"):
		sc = float(_args.scale)
	get_window().content_scale_factor = sc


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if _args.has("set"):   # test: settings for this run only, --set=res:1280,aa:msaa4
		for kv in String(_args.set).split(","):
			var p := kv.split(":")
			var d: Variant = Settings.DEFAULTS.get(p[0])
			Settings._values[p[0]] = int(p[1]) if d is int else (float(p[1]) if d is float else (p[1] == "true" if d is bool else p[1]))
	apply_ui_scale()
	map = MapView.new()
	add_child(map)
	apply_window()
	apply_video()
	get_window().size_changed.connect(apply_render_scale)
	map.world_ready.connect(_on_world)
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	# the glass panels blur what is under them: copy the screen (map and overlays) before the interface
	_bb = BackBufferCopy.new()
	_bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if Ui.blur else BackBufferCopy.COPY_MODE_DISABLED
	_ui.add_child(_bb)
	map_ui = MapUi.new()
	map_ui.visible = false
	map_ui.acted.connect(_on_act)
	map_ui.open_window.connect(func(id): if hud.open_window != id: _toggle_window(id))
	map_ui.ask.connect(func(spec): modals.push(spec))
	_ui.add_child(map_ui)
	hud = Hud.new()
	hud.visible = false
	hud.window_requested.connect(_toggle_window)
	hud.menu_requested.connect(_game_menu)
	hud.mode_changed.connect(func(m): map.set_mode(m))
	_ui.add_child(hud)
	# the compass over the bottom right corner: back to the standard view after Q / E
	var cmp := CompassButton.new()
	cmp.camera = map.camera
	cmp.anchor_left = 1
	cmp.anchor_right = 1
	cmp.anchor_top = 1
	cmp.anchor_bottom = 1
	cmp.offset_left = -14 - 44
	cmp.offset_right = -14
	cmp.offset_top = -84 - 44
	cmp.offset_bottom = -84
	hud.add_child(cmp)
	win = WindowPanel.new()
	win.visible = false
	win.theme = Ui.theme()
	win.close_requested.connect(func(): _toggle_window(hud.open_window))
	_ui.add_child(win)
	toasts = Toasts.new()
	_ui.add_child(toasts)
	planner = Planner.new()
	planner.acted.connect(_on_act)
	planner.closed.connect(_planner_closed)
	_ui.add_child(planner)
	course = Course.new()
	course.acted.connect(_on_act)
	course.closed.connect(func(): hud.set_planning(false))
	_ui.add_child(course)
	SaveSystem.provider = _autosave
	modals = ModalLayer.new()
	modals.theme = Ui.theme()
	modals.opened.connect(func(): if session != null: session.hold = true)
	modals.closed.connect(func(): if session != null: session.hold = false)
	_ui.add_child(modals)
	var ddl := Control.new()   # dropdown lists open here, over the windows and the dialogs
	ddl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ddl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ddl.theme = Ui.theme()
	_ui.add_child(ddl)
	Dropdown.layer = ddl
	_loading = _build_loading()
	_ui.add_child(_loading)
	perf_panel = PerfPanel.new()
	_ui.add_child(perf_panel)
	tips = TipLayer.new()
	_ui.add_child(tips)
	if _args.has("f3"):
		perf_panel.toggle.call_deferred()
	_checks = PanelContainer.new()
	_checks.position = Vector2(80, 80)
	_checks.visible = false
	_ui.add_child(_checks)
	if not ClassDB.class_exists("TRWorldGen"):
		modals.push({"icon": "alert", "tone": "bad", "eyebrow": "Помилка", "title": "Нативний модуль не завантажився",
			"body": "Бібліотека [b]godot/bin/libtriroute[/b] не знайдена або не підходить до цієї системи. Натисни F9, щоб побачити перевірки.", "choices": []})
		return
	_ng.seed = int(_args.get("seed", str(randi() % 1000000000)))
	if _args.has("load"):
		_load_slot(_args.load)
	elif _args.has("company") or _args.has("pick") or (_args.has("shot") and not _args.has("menu")):
		_create_world()
	else:
		_show_menu()
		if _args.has("shot"):
			for i in 12:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_args.shot)
			get_tree().quit()


# ---------- the main menu and a new game ----------
func _show_menu() -> void:
	if menu == null:
		menu = StartMenu.new()
		menu.new_game.connect(_new_game_dialog)
		menu.settings.connect(_settings)
		menu.load_game.connect(func(): _slots(false))
		menu.quit.connect(func(): get_tree().quit())
		_ui.add_child(menu)
		_ui.move_child(menu, 0)
	menu.visible = true
	Music.menu()
	hud.visible = false
	win.visible = false


func _new_game_dialog() -> void:
	var c := Ui.vbox(12)
	c.add_child(Ui.note("Ви — засновник логістичної компанії. Від однієї вантажної машини до потягів, кораблів і літаків на всіх континентах."))
	var field := func(name: String, ctl: Control) -> Control:
		var l := Ui.lbl(name)
		l.custom_minimum_size.x = 130
		return Ui.hbox(12, [l, ctl])
	c.add_child(field.call("Розмір мапи", Ui.seg(SIZE_N, _ng.size, func(v): _ng.size = v)))
	c.add_child(Ui.note("Розмір у секторах. Сектор — 3×3 великі клітинки сітки.", Ui.MUTED))
	c.add_child(field.call("Складність", Ui.seg(DIFF_N, _ng.diff, func(v): _ng.diff = v)))
	var seed_l := Ui.num(str(_ng.seed), 14, Ui.MUTED)
	c.add_child(field.call("Зерно світу", Ui.hbox(12, [seed_l, Ui.btn("Інше", "sm", "dice", func():
		_ng.seed = randi() % 1000000000
		seed_l.text = str(_ng.seed))])))
	var go := Ui.btn("Створити світ", "pri", "globe", func():
		modals.clear()
		_create_world())
	go.custom_minimum_size.y = 44
	c.add_child(go)
	modals.push({"icon": "globe", "eyebrow": "Нова гра", "title": "Створити гру", "content": c, "close": true})


func _settings() -> void:
	var c := SettingsPanel.new()
	c.host = self
	modals.push({"icon": "gear", "eyebrow": "Гра", "title": "Налаштування", "content": c, "close": true, "width": 760})


func apply_blur() -> void:
	var v: bool = Settings.get_value("blur")
	Ui.set_blur(v)
	_bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if v else BackBufferCopy.COPY_MODE_DISABLED


func open_checks() -> void:
	modals.clear()
	_toggle_checks()


func _game_menu() -> void:
	modals.push({"icon": "shield", "eyebrow": "Пауза", "title": "Меню гри", "close": true, "width": 420, "choices": [
		{"t": "Продовжити", "center": true, "f": func(): pass},
		{"t": "Зберегти гру", "center": true, "f": func(): _slots(true)},
		{"t": "Завантажити гру", "center": true, "disabled": not SaveSystem.any(), "f": func(): _slots(false)},
		{"t": "Налаштування", "center": true, "f": _settings},
		{"t": "Головне меню", "center": true, "f": func():
			_end_game()
			_show_menu()},
		{"t": "Вихід", "center": true, "f": func(): get_tree().quit()}]})


func _build_loading() -> Control:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var g := Ui.glass()
	g.custom_minimum_size.x = 360
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 6
	bar.add_theme_stylebox_override("background", Ui.box(Color(1, 1, 1, .07)))
	bar.add_theme_stylebox_override("fill", Ui.box(Ui.ACCENT))
	bar.name = "bar"
	g.add_child(Ui.margin(Ui.vbox(12, [Ui.lbl("Генерація світу…"), bar]), 18))
	c.add_child(g)
	return c


func _create_world() -> void:
	if menu != null:
		menu.visible = false
	_loading.visible = true
	GameState.reset(_ng.seed)
	_size_key = _args.get("size", _ng.size)
	map.generate(_ng.seed, _size_key)


var _perf_t := 0.0
var _perf_n := 0


var _live_n := 0


func _process(delta: float) -> void:
	if _args.has("perf"):
		_perf_n += 1
		_perf_t += delta
		if _perf_t >= 2.0:
			RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
			print("PERF fps %.0f · gpu %.1f ms · process %.2f ms · draw calls %d · %s" % [_perf_n / _perf_t, RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Perf.report(_perf_n)])
			_perf_t = 0
			_perf_n = 0
	_live_n += 1
	if map != null and map.camera != null:
		var fo := get_viewport().gui_get_focus_owner()
		map.camera.keys_on = hud != null and hud.visible and not modals.is_open() and not (fo is LineEdit or fo is TextEdit)
	if _live_n % 6 == 0 and win.visible and session != null and session.sim != null:
		Windows.tick_trips(session.sim, get_tree())
	Perf.begin("main._process")
	_process_t(delta)
	Perf.end("main._process")


func _process_t(delta: float) -> void:
	_pace_frames()
	if _loading.visible:
		var bar: ProgressBar = _loading.find_child("bar", true, false)
		bar.value = fmod(bar.value + delta * 40, 100)
	if session != null and session.sim != null:
		# decisions of the game wait for the player
		var sim := session.sim
		if sim.auto_choice < 0 and sim.modals.size() and not modals.is_open():
			modals.push(_decision(sim.modals.pop_front()))
		if win.visible:
			_win_tick()
		while sim.toasts.size():
			var t: Dictionary = sim.toasts.pop_front()
			toasts.push(t.tone, t.t, t.d)
		# #toasts moves left of the card on the right
		toasts.offset_right = -358 if map_ui.insp_open() else -14
		toasts.offset_left = toasts.offset_right - 320


# ---------- the world is ready: the headquarters ----------
func _on_world(w: Dictionary) -> void:
	_loading.visible = false
	if _args.has("colors"):   # test: the state colours of the HTML version, one #rrggbb per line
		var cols := []
		for l in FileAccess.get_file_as_string(_args.colors).split("\n", false):
			cols.append(Color(l.strip_edges()))
		map.set_colors(cols)
	if session != null:
		session.queue_free()
	session = GameSession.new()
	add_child(session)
	session.begin(map.generator(), GameState.world_seed, w.states, w.board, w, _ng.diff)
	hud.session = session
	var loaded := _pending != null
	if loaded:
		var d: Dictionary = _pending
		_pending = null
		session.sim.load_state(d.sim)
		session.sim.auto_choice = -1
		_play(session.sim.CO.hq, false, true)
		var hp: Dictionary = session.sim.PL[session.sim.CO.hq]
		map.camera.look_at_point(Vector2(hp.x, hp.z + .3), 6.0)
		map.company_colors()
		toasts.push("good", "Гру завантажено", "%s · %s" % [session.sim.CO.name, Ui.date_str(session.sim.date)])
	if loaded:
		if _args.has("win"):
			_toggle_window(_args.win)
	elif _args.has("company"):
		var hq := int(_args.get("hq", str(session.choices[0].id)))
		_play(hq, true)
		if _args.has("demo"):
			session.demo_fleet()
			map.company_colors()
		if _args.has("days"):
			session.run_days(int(_args.days))
		session.set_speed(int(_args.get("speed", "0")))
		if _args.has("select") and session.sim.CO.jobs.size():
			var js: Array = session.sim.CO.jobs.filter(func(x): return not x.get("ret"))
			map_ui.select_job(js[0] if js.size() else session.sim.CO.jobs[0], true)
		if _args.has("plan"):
			var ks: Array = session.sim.CO.board.filter(func(x): return session.sim.co_plan(x).ok)
			if ks.size():
				_plan(ks[0])
				if _args.plan == "auto":
					planner.auto_use()
		if _args.has("reroute"):
			session.sim.CO.xp = 1e6
			var js: Array = session.sim.CO.jobs.filter(func(x): return session.sim.sr_ok(x) and x.mode == _args.reroute)
			if js.size():
				_reroute(js[0])
		if _args.has("place"):
			map_ui.show_place(int(_args.place))
		if _args.has("country"):
			map_ui.show_country(int(_args.country))
		if _args.has("win"):
			_toggle_window(_args.win)
		if _args.has("save"):   # test: save into a slot
			var sd := _save_data()
			SaveSystem.write(_args.save, sd.data, sd.meta)
		map.camera.tx = map.camera.ttx   # no glide for a screenshot
		map.camera.tz = map.camera.ttz
		map.camera.dist = map.camera.tdist
	elif not (_args.has("shot") and not _args.has("pick")):
		_pick_hq()
	if _args.has("cam"):
		var c: PackedStringArray = String(_args.cam).split(",")
		map.camera.look_at_point(Vector2(float(c[0]), float(c[1])), float(c[2]))
		map.camera.tx = map.camera.ttx
		map.camera.tz = map.camera.ttz
		map.camera.dist = map.camera.tdist
	if _args.has("yaw"):   # test: the camera turned
		map.camera.yaw = float(_args.yaw)
		map.camera.tyaw = map.camera.yaw
	if _args.has("noui"):   # test: the map alone (the main menu's backgrounds)
		_ui.visible = false
	if _args.has("mode"):   # test: a map layer
		hud.mode_dd.value = String(_args.mode)
		hud.mode_dd._show_value()
		map.set_mode(String(_args.mode))
	if _args.has("shot"):
		for i in 12:
			await get_tree().process_frame
		if _args.has("wait"):   # test: seconds of play before the shot
			await get_tree().create_timer(float(_args.wait)).timeout
		if _args.has("settings"):   # test: the settings on a tab
			SettingsPanel.tab = String(_args.settings) if _args.settings != "" else "gfx"
			_settings()
			for i in 6:
				await get_tree().process_frame
		if _args.has("gmenu"):   # test: the game menu
			_game_menu()
			for i in 6:
				await get_tree().process_frame
		if _args.has("showk"):   # test: the first order of the board on the map
			var ks: Array = session.sim.CO.board
			if ks.size():
				wins.st.prev = ks[0].id
				map_ui.show_order(ks[0])
				_win_tick(true)
			for i in 40:
				await get_tree().process_frame
		if _args.has("hdd"):   # test: the map layer list, opened
			hud.mode_dd.pressed.emit()
		if _args.has("mouse"):   # test: the hover card at a point of the screen
			var c: PackedStringArray = String(_args.mouse).split(",")
			get_viewport().warp_mouse(Vector2(float(c[0]), float(c[1])))
			for i in 4:
				await get_tree().process_frame
		if _args.has("toast"):   # test: a toast
			toasts.push("warn", "Немає ліцензії", "Залізниця: цей вид транспорту ще недоступний")
			toasts.push("good", "Рейс відправлено", "Вантажна машина: Річар → Сенвіль")
			for i in 20:
				await get_tree().process_frame
		if _args.has("dd"):   # test: the first dropdown of the open window, opened
			var ob: Array = win.body.find_children("*", "Dropdown", true, false)
			if ob.size():
				ob[0].pressed.emit()
				await get_tree().process_frame
				get_viewport().warp_mouse(ob[0].get_global_rect().position + Vector2(40, 56))
			for i in 6:
				await get_tree().process_frame
		if _args.has("alljobs"):   # test: select every trip in turn and time the frames
			for j in session.sim.CO.jobs.duplicate():
				var t1 := Time.get_ticks_usec()
				map_ui.select_job(j)
				var t2 := Time.get_ticks_usec()
				for i in 3:
					await get_tree().process_frame
				print("job %d %s ret=%s sel %.1f ms, 3 frames %.1f ms" % [j.id, j.mode, j.get("ret", false), (t2 - t1) / 1000.0, (Time.get_ticks_usec() - t2) / 1000.0])
		if _args.has("clickveh"):   # test: a click on the first vehicle on screen, then a few seconds of play
			for h in map.vehicles.hits:
				if h.has("j") and session.sim.co_job_state(h.j, session.sim.co_now() - h.j.t0).seg >= 0:
					print("click vehicle at ", h.x, ",", h.y)
					if _args.has("real"):
						get_viewport().warp_mouse(Vector2(h.x, h.y))
						await get_tree().process_frame
						var hp := Vector2(h.x, h.y)
						for h2 in map.vehicles.hits:
							if h2.has("j") and is_same(h2.j, h.j):
								hp = Vector2(h2.x, h2.y)
						get_viewport().warp_mouse(hp)
						for pr in [true, false]:
							var ev := InputEventMouseButton.new()
							ev.button_index = MOUSE_BUTTON_LEFT
							ev.pressed = pr
							ev.position = hp
							ev.global_position = ev.position
							Input.parse_input_event(ev)
							await get_tree().process_frame
					elif not _args.has("noclick"):
						map.camera.clicked.emit(Vector2(h.x, h.y))
					if _args.has("nofollow"):
						map_ui.follow = false
					break
			var t0 := Time.get_ticks_msec()
			for i in 120:
				await get_tree().process_frame
			print("120 frames in %d ms, card %s, follow %s" % [Time.get_ticks_msec() - t0, map_ui._card.visible, map_ui.follow])
			print(Perf.report(120))
		if _args.has("click"):   # test: a click on the map
			var c: PackedStringArray = String(_args.click).split(",")
			map.camera.clicked.emit(Vector2(float(c[0]), float(c[1])))
			for i in 4:
				await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args.shot)
		get_tree().quit()


## «Де відкриємо перший хаб?»: five capitals from the poorest to the richest
func _pick_hq() -> void:
	var sim := session.sim
	var ch := []
	for p in session.choices:
		var c: Dictionary = sim.states[p.cid]
		var pid: int = p.id
		ch.append({"t": "%s, %s" % [p.name, c.name], "d": "Населення міста %s · рівень цін ×%.2f · зарплати ×%.2f · ризики: %s" % [Ui.people(p.pop), sim.price_k(p.cid), sim.wage_k(p.cid), _risk_word(sim.co_risk(p.cid))],
			"f": func(): _play(pid, false)})
	modals.push({"icon": "truck", "eyebrow": "Логістична компанія", "title": "Де відкриємо перший хаб?",
		"body": "У вас [b]%s[/b], одна вантажна машина і бажання доставляти. Оберіть столицю для штаб-квартири. Від неї залежать ціни, зарплати й те, куди ви зможете розширитися першими." % Ui.usd(sim.CO.cash),
		"hint": "У [b]багатих[/b] країнах доставки дорожчі, але дорожчі й люди. У [b]бідних[/b] праця дешева, проте посилки коштують копійки, а ризики вищі.",
		"choices": ch})


## riskW
static func _risk_word(r: float) -> String:
	return "дуже високий" if r > .75 else ("високий" if r > .5 else ("середній" if r > .3 else "низький"))


func _play(hq: int, auto_decisions: bool, loaded: bool = false) -> void:
	if not loaded:
		session.choose_hq(hq, auto_decisions)
	session.set_speed(0)
	map.attach_session(session)
	wins = Windows.new(session.sim)
	wins.acted.connect(_on_act)
	wins.goto_place.connect(_goto_place)
	wins.select_job.connect(func(j): map_ui.select_job(j, true))
	map_ui.attach(session, map)
	map_ui.planner = planner
	planner.attach(session, map)
	course.attach(session, map, planner)
	map_ui.course = course
	if not map_ui.reroute.is_connected(_reroute):
		map_ui.reroute.connect(_reroute)
	wins.plan_order.connect(_plan)
	wins.show_order.connect(func(k):
		map_ui.show_order(k)
		_win_tick(true))
	map_ui.prev_gone.connect(func(): wins.st.prev = -1)
	wins.move_vehicle.connect(func(v):
		if win.visible:
			_toggle_window("")
		map_ui.move_start(v))
	session.day_passed.connect(func(_d): _grade_check())
	_grade_check()
	if not session.speed_refused.is_connected(_speed_refused):
		session.speed_refused.connect(_speed_refused)
	map_ui.visible = true
	hud.visible = true
	Music.game()
	var p: Dictionary = session.sim.PL[hq]
	map.camera.look_at_point(Vector2(p.x, p.z + .3), 6.0)


## a decision of the game (Sim.co_modal) as a dialog
func _decision(spec: Dictionary) -> Dictionary:
	var ic: Array = DEC_ICON.get(spec.get("kind", ""), ["alert", "warn"])
	var ch := []
	for c in spec.choices:
		ch.append({"t": c.t, "d": c.get("d", ""), "f": c.f})
	return {"icon": ic[0], "tone": ic[1], "eyebrow": session.sim.CO.name, "title": spec.get("title", ""), "body": spec.get("body", ""), "choices": ch}


# ---------- windows ----------
const WIN_HEAD := {"coHome": ["briefcase", "Компанія"], "coJobs": ["box", "Біржа вантажів"], "coTrips": ["road", "Рейси в дорозі"], "coFleet": ["truck", "Автопарк"],
	"coNet": ["globe", "Мережа хабів"], "coStaff": ["users", "Персонал і менеджмент"], "coFin": ["coins", "Фінанси"], "news": ["news", "Стрічка новин"]}


func _toggle_window(id: String) -> void:
	if hud.open_window == id or id == "":
		hud.open_window = ""
		win.visible = false
		return
	hud.open_window = id
	var vs := get_viewport().get_visible_rect().size
	win.position = Vector2(78, 84)
	win.size = Vector2(minf(760, vs.x - 460), vs.y - 170)
	win.custom_minimum_size = win.size
	win.visible = true
	_win_tick(true)


var _win_day := -1.0


## the content of the open window, built again every game day and after every action
func _win_tick(force: bool = false) -> void:
	var sim := session.sim
	if not force and sim.day == _win_day:
		return
	if not force and _win_day >= 0 and (win.scroll as SmoothScroll).busy():
		return   # later: the content does not change under the reader's hand
	# a new day: the window changes in small steps over a few frames; opening it or an action: at once
	var smooth := not force and _win_day >= 0 and hud.open_window == _win_id
	_win_day = sim.day
	var id := hud.open_window
	_win_id = id
	if smooth and _args.has("perf"):
		print("PERF day %.1f ms" % (Perf.acc.get("co_day", 0) / 1000.0))
	var h: Array = WIN_HEAD.get(id, ["info", id])
	win.set_head(h[0], "%s · %s" % [sim.CO.name, Ui.date_str(sim.date)], h[1])
	if smooth:
		await get_tree().process_frame   # not in the frame the day was computed in
		if hud.open_window != id:
			return
	var keep := win.scroll.scroll_vertical
	var t0 := Time.get_ticks_usec()
	var off := VBoxContainer.new()
	if id == "news":
		for i in range(sim.news.size() - 1, maxi(-1, sim.news.size() - 60), -1):
			var n: Array = sim.news[i]
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(7, 7)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.color = {"good": Ui.GOOD, "bad": Ui.BAD, "warn": Ui.WARN}.get(n[0], Ui.ACCENT)
			var t := Ui.note(n[2])
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			off.add_child(Ui.hbox(10, [dot, t]))
		if sim.news.is_empty():
			off.add_child(Ui.note("Поки що новин немає.", Ui.MUTED))
	else:
		wins.build(id, off)
	_swap_gen += 1
	if smooth:
		var gen := _swap_gen
		await get_tree().process_frame   # the build and the swap in different frames too
		if gen != _swap_gen:
			off.free()
			return
		_swap_t = Time.get_ticks_usec()
		await _swap(win.body, off, gen)
	else:
		win.clear_body()
		for ch in off.get_children():
			off.remove_child(ch)
			win.body.add_child(ch)
		if not force:
			_restore_scroll(keep)
	off.free()
	get_viewport().update_mouse_cursor_state()   # the button under the pointer lights up again
	if _args.has("perf"):
		print("PERF window %s %s in %.1f ms" % [id, "swapped" if smooth else "built", (Time.get_ticks_usec() - t0) / 1000.0])


var _win_id := ""
var _swap_gen := 0
var _swap_t := 0


## replaces the children of dst by those of src a few at a time (≈4 ms a frame); a big column of the same
## kind is swapped inside, so a long list never lands in one frame. A newer build (gen) stops an older one.
func _swap(dst: Container, src: Container, gen: int) -> void:
	var i := 0
	while src.get_child_count() > 0:
		if gen != _swap_gen or not is_instance_valid(dst):
			return
		var n: Node = src.get_child(0)
		src.remove_child(n)
		if i < dst.get_child_count():
			var o: Node = dst.get_child(i)
			if o is VBoxContainer and n is VBoxContainer and o.get_script() == null and n.get_script() == null and n.get_child_count() > 3:
				await _swap(o, n, gen)
				n.free()
				i += 1
				continue
			dst.remove_child(o)
			o.queue_free()
			dst.add_child(n)
			dst.move_child(n, i)
		else:
			dst.add_child(n)
		i += 1
		if Time.get_ticks_usec() - _swap_t > 4000:
			await get_tree().process_frame
			_swap_t = Time.get_ticks_usec()
	if gen != _swap_gen or not is_instance_valid(dst):
		return
	while dst.get_child_count() > i:
		var o: Node = dst.get_child(i)
		dst.remove_child(o)
		o.queue_free()


func _restore_scroll(v: int) -> void:
	await get_tree().process_frame
	win.scroll.scroll_vertical = v


## the result of an action in a window: a toast (a dialog for a new licence), then the window again
func _on_act(res: Dictionary) -> void:
	if res.get("lic"):
		modals.push({"icon": "doc", "tone": "good", "eyebrow": "Нова ліцензія", "title": res.t, "body": res.d, "close": true,
			"choices": [{"t": "Чудово", "f": func(): pass}]})
	elif res.get("t", "") != "":
		toasts.push(res.get("tone", ""), res.t, res.get("d", ""))
	_win_day = -1
	if win.visible:
		_win_tick()
	map_ui.refresh()


## ACT.lpPlan: the route planner over the map; the windows, the rail and the cards step aside
func _plan(k: Dictionary) -> void:
	map_ui.show_order(null)
	wins.st.prev = -1
	var why := planner.open(k)
	if why != "":
		toasts.push("warn", "Маршрут не прокласти", why)
		return
	if win.visible:
		_toggle_window("")
	map_ui.close_insp()
	map_ui.close_card()
	hud.set_planning(true)


## grBox: a new grade of experience — news and a toast (CO.grd remembers the last one)
func _grade_check() -> void:
	var sim := session.sim
	var g := sim.co_grade()
	if sim.CO.get("grd") == null:
		sim.CO.grd = g
	elif g > sim.CO.grd:
		sim.CO.grd = g
		var q: Dictionary = GameData.GRADES[g]
		sim.co_news("good", "star", "%s отримала грейд «%s»" % [sim.CO.name, q.n])
		toasts.push("good", "Новий грейд: " + q.n, " · ".join(q.u))


## srOpen: a new course for a trip under way
func _reroute(j: Dictionary) -> void:
	if wins.gr_ok("reroute"):
		var why := course.open(j)
		if why != "":
			toasts.push("warn", "Курс змінити не можна", why)
			return
		if win.visible:
			_toggle_window("")
		map_ui.close_insp()
		map_ui.close_card()
		hud.set_planning(true)


func _planner_closed(reopen: String) -> void:
	hud.set_planning(false)
	if reopen != "" and hud.open_window != reopen:
		_toggle_window(reopen)


func _speed_refused(why: String) -> void:
	toasts.push("warn", "Час на паузі", why)


func _goto_place(pid: int) -> void:
	map_ui.fly(pid)


# ---------- saving ----------
## the game as a save: the world comes back from the seed and the size
func _save_data() -> Dictionary:
	var sim := session.sim
	return {"data": {"v": 1, "seed": GameState.world_seed, "size": _size_key, "diff": sim.diff, "sim": sim.save_state()},
		"meta": {"name": sim.CO.name, "col": sim.CO.get("col", "#ffb347"), "date": Ui.date_str(sim.date), "mode": "Логістична компанія",
			"when": Time.get_datetime_string_from_system(false, true).substr(5, 11).replace("T", " ")}}


## autosave: not while planning, in a dialog or before the headquarters
func _autosave() -> Variant:
	if not Settings.get_value("autosave"):
		return {}
	if session == null or session.sim == null or not hud.visible or planner.on or course.on or modals.is_open():
		return {}
	var s := _save_data()
	toasts.push("", "Автозбереження", s.meta.date)
	return s


func _slots(save: bool) -> void:
	var c := Ui.vbox(8)
	var slots: Array = ["1", "2", "3"] if save else SaveSystem.SLOTS.filter(func(i): return i != "auto" or not SaveSystem.meta(i).is_empty())
	for i in slots:
		var m := SaveSystem.meta(i)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(30, 20)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = Color(m.get("col", "#ffb347")) if m.size() else Color(1, 1, 1, .06)
		var t: String = ("Автозбереження · " if i == "auto" else "") + (m.name if m.size() else "Порожній слот " + i)
		var info := Ui.vbox(2, [Ui.label(t, 14, Ui.FG, Ui.font("body", 600)), Ui.note(("%s · %s · збережено %s" % [m.get("mode", ""), m.get("date", ""), m.get("when", "")]) if m.size() else "Немає збереження")])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := Ui.hbox(10, [sw, info])
		var slot: String = i
		if save:
			row.add_child(Ui.btn("Перезаписати" if m.size() else "Зберегти", "pri sm", "", func():
				var s := _save_data()
				if SaveSystem.write(slot, s.data, s.meta):
					toasts.push("good", "Гру збережено", "Слот %s · %s" % [slot, s.meta.date])
				else:
					toasts.push("bad", "Не вдалося зберегти", "Немає доступу до папки збережень")
				modals.clear()))
		else:
			var b := Ui.btn("Завантажити", "pri sm", "", func():
				modals.clear()
				_load_slot(slot))
			b.disabled = m.is_empty()
			row.add_child(b)
		if m.size():
			row.add_child(Ui.btn("", "sm", "trash", func():
				SaveSystem.remove(slot)
				modals.clear()
				_slots(save)))
		c.add_child(Ui.blk(row))
	if save:
		c.add_child(Ui.note("Світ відтворюється із зерна, тому збереження компактні. Файли лежать у папці користувача гри."))
	elif session != null:
		c.add_child(Ui.note("Поточний незбережений прогрес буде втрачено."))
	if slots.is_empty():
		c.add_child(Ui.note("Збережених ігор ще немає."))
	modals.push({"icon": "doc" if save else "refresh", "eyebrow": "Збереження" if save else "Завантаження", "title": "Зберегти гру" if save else "Завантажити гру", "content": c, "close": true})


func _end_game() -> void:
	if planner.on:
		planner.close()
	if course.on:
		course.close()
	if map_ui.sim != null:
		map_ui.close_insp()
		map_ui.close_card()
		map_ui.move_cancel(false)
	map_ui.visible = false
	if win.visible:
		_toggle_window("")
	if session != null:
		session.queue_free()
		session = null


func _load_slot(slot: String) -> void:
	var d: Variant = SaveSystem.read(slot)
	if d == null or not d.has("sim"):
		toasts.push("bad", "Збереження не знайдено", "Слот порожній або пошкоджений")
		return
	_end_game()
	_pending = d
	_ng.seed = int(d.seed)
	_ng.size = d.get("size", "m")
	_ng.diff = int(d.get("diff", 1))
	_args.erase("size")
	hud.visible = false
	_create_world()


# ---------- checks ----------
func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var act := Keys.action_for(e)
	if act != "" and session != null and session.sim != null and hud.visible and not modals.is_open():
		get_viewport().set_input_as_handled()
		_key_action(act)
		return
	match e.keycode:
		KEY_F9:
			_toggle_checks()
		KEY_F3:
			perf_panel.toggle()
		KEY_ESCAPE:
			if planner.on or course.on or map_ui.mv_v != null:
				return
			if win.visible:
				_toggle_window("")
			elif map_ui.insp_open():
				map_ui.close_insp()
			elif session != null and hud.visible and not modals.is_open():
				_game_menu()


var _last_speed := 1


## a bound key (Keys): time, map layers, windows, a screenshot
func _key_action(act: String) -> void:
	if session.speed > 0:
		_last_speed = session.speed
	match act:
		"pause":
			session.set_speed(0 if session.speed else _last_speed)
		"speed1", "speed2", "speed3":
			session.set_speed(int(act.right(1)))
		"slower":
			session.set_speed(maxi(0, session.speed - 1))
		"faster":
			session.set_speed(mini(3, session.speed + 1))
		"shot":
			_screenshot()
		_:
			if act.begins_with("lay_"):
				var m := act.substr(4)
				hud.mode_dd.value = m
				hud.mode_dd._show_value()
				map.set_mode(m)
			elif act.begins_with("w_"):
				_toggle_window(act.substr(2))


## F2: the screen into the screenshots folder of the game's data
func _screenshot() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var f := "user://screenshots/triroute-%s.png" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var err := get_viewport().get_texture().get_image().save_png(f)
	if err == OK:
		toasts.push("good", "Скріншот збережено", ProjectSettings.globalize_path(f))
	else:
		toasts.push("bad", "Скріншот не збережено", "Помилка %d" % err)


func _toggle_checks() -> void:
	_checks.visible = not _checks.visible
	if not _checks.visible:
		return
	for c in _checks.get_children():
		c.queue_free()
	var g := Ui.glass()
	_checks.add_child(g)
	var out := RichTextLabel.new()
	out.bbcode_enabled = true
	out.fit_content = true
	out.custom_minimum_size = Vector2(760, 0)
	g.add_child(Ui.margin(out, 16))
	out.append_text("[color=#ffb347]Перевіряю… (генерація кількох світів займає кілька секунд)[/color]")
	await get_tree().process_frame
	await get_tree().process_frame
	var r := TestRunner.run_all()
	out.clear()
	for l in r.lines:
		var col := "#5fd08a" if l.begins_with("ok") else "#f0625f" if l.begins_with("FAIL") else "#ffb347"
		out.append_text("[color=%s]%s[/color]\n" % [col, l])
