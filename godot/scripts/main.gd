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
var perf_rec: PerfRecorder
var perf_panel: PerfPanel
var _bb: BackBufferCopy
var planner: Planner
var netp: NetPlanner
var studio: TrailerStudio   # «Студія трейлера» (the ` key, left of 1)
var tutorial: Tutorial
var course: Course
var menu: StartMenu
var _args := {}
var _ng := {"size": "m", "diff": 1, "seed": 0, "map": "gen", "roads": "fine", "base": "gen", "mode": "classic"}
var editor: MapEditor = null   # the map editor, while it is open
var _edit := {}                # the map editor's edit of the world in play (saved with the game)
var _pending_edit := {}
var _loading: Control
var backdrop: MenuBackdrop
var legend: Legend
var _checks: PanelContainer
var _ui: CanvasLayer
var _size_key := "m"
var _pending: Variant = null     # a saved game waiting for its world


## the interface in CSS pixels, like the browser: the system scale (Windows display scaling), or the setting
## the frame limit: the monitor's rate by default (VSync), or a number, or none; quieter when nothing happens
## the window: maximised, a window of the chosen size (centred), borderless or exclusive full screen
func apply_window() -> void:
	if _args.has("shot") or DisplayServer.get_name() == "headless" or Clock.movie():
		return   # a screenshot, a test, or a recording (Movie Maker keeps the size it was given)
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


## VSync, the frame limit and the render resolution of the map
func apply_video() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if Settings.get_value("vsync") else DisplayServer.VSYNC_DISABLED)
	var f := int(Settings.get_value("fps"))
	_fps_cap = _paced_cap(f, bool(Settings.get_value("vsync")))
	Engine.max_fps = _fps_cap
	var vp := get_viewport()
	# no anti-aliasing of the picture: the map's shader smooths the edges of its own triangles, coasts and
	# borders (map.gdshader), the lines, towns and labels theirs
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if map != null:
		map.set_glint(bool(Settings.get_value("glint")))
	# the map reads its textures at a fixed level of detail: anisotropic filtering changes nothing on it
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_4X
	VehicleLayer.trails = bool(Settings.get_value("trails"))
	apply_render_scale()


## the map's render resolution: a share of the window's real pixels (high 100 %, medium 85 %, low 75 %)
func apply_render_scale() -> void:
	var vp := get_viewport()
	var res := int(Settings.get_value("res"))
	var k := clampf(-res / 100.0, .5, 1.0) if res < 0 else 1.0
	vp.scaling_3d_scale = k
	# a smaller render is stretched by AMD FSR 1.0: sharper than plain bilinear
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if k < 1 else Viewport.SCALING_3D_MODE_BILINEAR
	_map_k = k
	if map != null:
		map.render_k = k



var _map_k := 1.0


## the frame limit that is actually set. With VSync a limit that does not divide the monitor's refresh rate
## shows every picture for one or two refreshes in turn (120 on a 144 Hz monitor: 7 and 14 ms by turns) —
## the motion of the map judders as if it were at 60. So with VSync the limit snaps to a whole part of the
## refresh rate (144, 72, 48…), the nearest to the chosen one; at the refresh rate itself VSync alone paces
## the frames (no limiter on top, it only adds unevenness)
func _paced_cap(f: int, vsync: bool) -> int:
	if f <= 0:
		return 0
	var hz := int(round(DisplayServer.screen_get_refresh_rate()))
	if not vsync or hz <= 0:
		return f
	var d := maxi(1, int(round(float(hz) / f)))
	return 0 if d == 1 else int(round(float(hz) / d))


## the map's resolution now (for the settings): the window's size × the render scale, without supersampling
func render_size() -> Vector2i:
	return Vector2i((Vector2(get_window().size) * _map_k).round())


var _fps_cap := 0
var _last_input := 0.0
var _focused := true


func _input(e: InputEvent) -> void:
	if e is InputEventMouse or e is InputEventKey:
		_last_input = Time.get_ticks_msec() / 1000.0
	if e is InputEventMouseButton and e.pressed:
		_focused = true   # a click in the window: it has the focus whatever the system said


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


## a 2D map does not need hundreds of frames when nothing moves: 15 in the background, 30 when the game is
## paused and the player has not touched anything for a few seconds, the chosen limit otherwise
func _pace_frames() -> void:
	# frames at the chosen limit always: on pause, with a still camera, in the background
	if Engine.max_fps != _fps_cap:
		Engine.max_fps = _fps_cap


func apply_ui_scale() -> void:
	Ui.set_blur(int(Settings.get_value("blur")))
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
	I18n.setup(String(_args.get("lang", Settings.get_value("lang"))))   # the interface's language (test: --lang=en)
	if _args.has("preset"):   # test: a graphics preset for this run only
		for k in Settings.PRESETS[_args.preset]:
			Settings._values[k] = Settings.PRESETS[_args.preset][k]
	if _args.has("set"):   # test: settings for this run only, --set=res:-85,glint:false
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
	# the legend of the map layer, over the bottom left corner
	legend = Legend.new()
	hud.add_child(legend)
	hud.mode_changed.connect(func(m): legend.mode = m)
	legend.toggled.connect(func(): map.apply_vis())
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
	netp = NetPlanner.new()   # the alternative balance: «Створити маршрут» on the map
	netp.acted.connect(_on_act)
	netp.closed.connect(_planner_closed)
	_ui.add_child(netp)
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
	backdrop = MenuBackdrop.new()
	backdrop.visible = false
	_ui.add_child(backdrop)
	_ui.move_child(backdrop, 0)
	perf_panel = PerfPanel.new()
	_ui.add_child(perf_panel)
	tips = TipLayer.new()
	_ui.add_child(tips)
	tutorial = Tutorial.new()   # the «Навчальна» difficulty: the manager's guide over everything
	tutorial.main = self
	_ui.add_child(tutorial)
	# F4: the performance record (user://perf/), read back to find what loads the game
	perf_rec = PerfRecorder.new()
	perf_rec.context = _perf_context
	perf_rec.viewports = func(): return {"lines": map._ov_vp, "towns": map._tw_vp} if map != null and map._ov_vp != null else {}
	perf_rec.state_changed.connect(func(on, p):
		toasts.push("good" if on else "", "Запис продуктивності" + (" почато" if on else " збережено"), ("F4 — зупинити. Файл: " if on else "Надішліть цей файл: ") + p))
	add_child(perf_rec)
	if _args.has("perf-rec"):
		perf_rec.start.call_deferred()
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
	if _args.has("menugleam"):   # test: the menu's gleam held at a part of its way
		StartMenu.gleam_at = float(_args.menugleam)
	if _args.has("load"):
		_load_slot(_args.load)
	elif _args.has("editor"):   # test: the map editor at once (--editor=blank: on an empty ocean)
		_ng.map = "edit"
		_ng.base = "blank" if _args.editor == "blank" else "gen"
		_ng.size = String(_args.get("size", _ng.size))
		_create_world()
	elif _args.has("company") or _args.has("pick") or (_args.has("shot") and not _args.has("menu")):
		_create_world()
	else:
		_show_menu()
		if _args.has("newgame"):   # test: the new game dialog (--newgame=earth: the Earth chosen)
			_ng.map = _args.newgame if _args.newgame in ["earth", "edit"] else "gen"
			_new_game_dialog()
		if _args.has("shot"):
			for i in 12:
				await get_tree().process_frame
			if _args.has("wait"):
				await get_tree().create_timer(float(_args.wait)).timeout
			if _args.has("loadscr"):   # test: the loading screen alone (the world is not made), some seconds in
				menu.visible = false
				_loading.visible = true
				_load_t = float(_args.loadscr)
				for i in 4:
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
		_ui.move_child(backdrop, 0)
	menu.visible = true
	Music.menu()
	hud.visible = false
	win.visible = false


## the flags are drawn ahead, one a frame, so no window waits for them
func _warm_flags(sim: Sim) -> void:
	for st in sim.states:
		if session == null or session.sim != sim:
			return
		Flags.texture(st)
		await get_tree().process_frame


## the company's new name (the pencil in the Company window)
func _rename_dialog() -> void:
	var sim := session.sim
	var e := LineEdit.new()
	e.text = sim.CO.name
	e.max_length = 40
	e.custom_minimum_size = Vector2(360, 38)
	e.add_theme_font_size_override("font_size", 15)
	e.select_all_on_focus = true
	var ok := func() -> void:
		var n := e.text.strip_edges()
		if n == "":
			return
		modals.clear()
		if n != sim.CO.name:
			sim.CO.name = n
			toasts.push("good", "Компанію перейменовано", n)
		_win_tick(true)
	e.text_submitted.connect(func(_t): ok.call())
	var save := Ui.btn("Зберегти", "pri", "check", ok)
	var no := Ui.btn("Скасувати", "", "", func(): modals.clear())
	e.text_changed.connect(func(t): save.disabled = t.strip_edges() == "")
	var c := Ui.vbox(14, [Ui.note("Назву видно в шапці вікон, у збереженнях і новинах."), e, Ui.hbox(10, [Ui.spacer(), no, save])])
	modals.push({"icon": "edit", "eyebrow": "Компанія", "title": "Назва компанії", "content": c, "close": true, "width": 460})
	e.call_deferred("grab_focus")
	e.call_deferred("select_all")


func _new_game_dialog() -> void:
	var c := Ui.vbox(12)
	c.add_child(Ui.note("Ви — засновник логістичної компанії. Від однієї вантажної машини до потягів, кораблів і літаків на всіх континентах."))
	var field := func(name: String, ctl: Control) -> Control:
		var l := Ui.lbl(name)
		l.custom_minimum_size.x = 130
		return Ui.hbox(12, [l, ctl])
	var size_row: Control = field.call("Розмір мапи", Ui.seg(SIZE_N, _ng.size, func(v): _ng.size = v))
	var size_note := Ui.note("Розмір у секторах. Сектор — 3×3 великі клітинки сітки.", Ui.MUTED)
	var earth_note := Ui.note("Справжня карта світу: 119 найбільших держав з реальними назвами, населенням і рівнем розвитку, мапа 4×3. Карликові країни приєднано до сусідів.", Ui.MUTED)
	var base_row: Control = field.call("Основа", Ui.seg([["gen", "Згенерований світ"], ["blank", "Порожній океан"]], _ng.base, func(v): _ng.base = v))
	var edit_note := Ui.note("Редактор: малюй сушу й кордони держав пензлем, став міста, прокладай дороги й залізниці. «Почати гру» — і компанія стартує на твоїй мапі.", Ui.MUTED)
	var map_vis := func() -> void:
		var e: bool = _ng.map == "earth"
		size_row.visible = not e
		size_note.visible = not e
		earth_note.visible = e
		base_row.visible = _ng.map == "edit"
		edit_note.visible = _ng.map == "edit"
	c.add_child(field.call("Світ", Ui.seg([["gen", "Згенерований"], ["earth", "Земля"], ["edit", "Редактор мапи"]], _ng.map, func(v):
		_ng.map = v
		map_vis.call())))
	c.add_child(earth_note)
	c.add_child(edit_note)
	c.add_child(base_row)
	c.add_child(size_row)
	c.add_child(size_note)
	map_vis.call()
	c.add_child(field.call("Складність", Ui.seg(DIFF_N, _ng.diff, func(v): _ng.diff = v)))
	var mode_note := Ui.note("", Ui.MUTED)
	var mode_txt := func() -> void:
		mode_note.text = {"classic": "Класичний: замовлення з біржі — окремі рейси від міста до міста.",
			"mm": "Мультимодальний: на біржі немає поділу на авто, потяги, кораблі й літаки — кожне замовлення ви берете й самі будуєте маршрут з ділянок, обираючи для кожної вид транспорту й конкретну техніку.",
			"alt": "Альтернативний баланс — мережа терміналів: вантаж чекає у відправника, ви забираєте його кільцевими рейсами, збираєте на складах хабів і везете магістралями (своєю технікою чи партнерами), консолідуючи багато вантажів в одному рейсі. Хаби мають склад, пропускну здатність, модулі для потягів, суден і літаків; рейси можна поставити на розклад."}.get(_ng.mode, "")
	c.add_child(field.call("Режим", Ui.seg([["classic", "Класичний"], ["mm", "Мультимодальний (тест)"], ["alt", "Альтернативний баланс"]], _ng.mode, func(v):
		_ng.mode = v
		mode_txt.call())))
	mode_txt.call()
	c.add_child(mode_note)
	var seed_l := Ui.num(str(_ng.seed), 14, Ui.MUTED)
	c.add_child(field.call("Зерно світу", Ui.hbox(12, [seed_l, Ui.btn("Інше", "sm", "dice", func():
		_ng.seed = randi() % 1000000000
		seed_l.text = str(_ng.seed))])))
	var go := Ui.btn("Створити світ", "pri", "globe", func():
		modals.clear()
		_ng.roads = "fine"   # every new world has the dense road net (a loaded game keeps its own)
		_edit = {}
		_create_world())
	go.custom_minimum_size.y = 44
	c.add_child(go)
	modals.push({"icon": "globe", "eyebrow": "Нова гра", "title": "Створити гру", "content": c, "close": true})


func _settings() -> void:
	var c := SettingsPanel.new()
	c.host = self
	modals.push({"icon": "gear", "eyebrow": "Гра", "title": "Налаштування", "content": c, "close": true, "width": 760})


func in_game() -> bool:
	return session != null and session.sim != null and hud.visible


## the language changed: what is drawn by hand is drawn again (the Labels and Buttons translate themselves)
func retranslate() -> void:
	if map != null:
		map.towns._content = ""
		map.towns._wc = {}
		map.overlay.dirty()
	if win.visible:
		_win_tick(true)
	if hud != null:
		hud.queue_redraw()


## the fast progress of the settings (Sim.act_fast)
func fast_mode() -> void:
	if not in_game():
		return
	_on_act(session.sim.act_fast())
	_win_tick(true)


## the test sandbox (Sim.act_sandbox): the command-line tests only
func sandbox() -> void:
	if not in_game():
		return
	_on_act(session.sim.act_sandbox())
	map.company_colors()


func apply_blur() -> void:
	Ui.set_blur(int(Settings.get_value("blur")))
	_bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if Ui.blur else BackBufferCopy.COPY_MODE_DISABLED


## a graphics preset: every setting it covers at once, applied
func apply_preset(name: String) -> void:
	Settings.apply_preset(name)
	apply_video()
	apply_blur()


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


## the stages the loading screen names while the world is made (the generation is one native call: the bar
## eases towards its end and the stages follow it)
## the stages named while a saved game's world is made again
const LOAD_STEPS_SAVE := ["Читання збереження", "Відтворення рельєфу й узбережжя", "Відновлення кордонів держав", "Відновлення міст і портів",
	"Відновлення доріг і залізниць", "Відновлення компанії й автопарку", "Запікання текстур мапи", "Компіляція шейдерів"]
const LOAD_STEPS := ["Ініціалізація генератора", "Генерація рельєфу й узбережжя", "Розподіл суші та моря", "Тріангуляція сітки клітинок",
	"Векторизація кордонів держав", "Розрахунок висот і гірських хребтів", "Прокладання автомагістралей", "Трасування залізничної мережі",
	"Розміщення портів і аеропортів", "Заснування міст і сіл", "Економіка держав і ресурси", "Побудова біржі вантажів",
	"Запікання текстур мапи", "Компіляція шейдерів"]
var _load_t := 0.0


## the loading screen: the floating pictures of the menu behind (MenuBackdrop), a thin bar without a frame,
## the stage of the generation under it
func _build_loading() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	# a veil over the pictures: the light land would swallow the thin text
	var veil := ColorRect.new()
	veil.color = Color(3 / 255.0, 6 / 255.0, 10 / 255.0, .45)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(veil)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(460, 4)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.add_theme_stylebox_override("background", Ui.box(Color(1, 1, 1, .14)))
	bar.add_theme_stylebox_override("fill", Ui.box(Ui.ACCENT))
	bar.name = "bar"
	var title := Ui.label("ГЕНЕРАЦІЯ СВІТУ", 11, Ui.FG, Ui.font("mono", 600, 2.5))
	title.name = "title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var step := Ui.label("", 12, Ui.FG, Ui.font("mono", 500))
	step.name = "step"
	step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(Ui.vbox(12, [title, bar, step]))
	return root


func _loading_step(delta: float) -> void:
	_load_t += delta
	# eases towards 96 % in about ten seconds; the world being ready hides the screen
	var p := 0.96 * (1.0 - exp(-_load_t / 3.2))
	var bar: ProgressBar = _loading.find_child("bar", true, false)
	bar.value = p
	var steps: Array = LOAD_STEPS_SAVE if _pending != null else LOAD_STEPS
	var i := mini(int(p / 0.96 * steps.size()), steps.size() - 1)
	var nd := 1 + int(_load_t * 3) % 3
	var dots := ".".repeat(nd) + " ".repeat(3 - nd)   # a steady width: the centred line does not wobble
	(_loading.find_child("step", true, false) as Label).text = steps[i] + dots


func _create_world() -> void:
	map.detach_session()
	if menu != null:
		menu.visible = false
	_loading.visible = true
	_load_t = 0.0
	# a new world is generated; a saved game's world is loaded (made again from its seed and edit)
	(_loading.find_child("title", true, false) as Label).text = "ЗАВАНТАЖЕННЯ СВІТУ" if _pending != null else "ГЕНЕРАЦІЯ СВІТУ"
	MapVis.clear()   # a new world: everything shown
	GameState.reset(_ng.seed)
	_size_key = _args.get("size", "earth" if _ng.map == "earth" else _ng.size)
	if _args.has("roads"):   # test: --roads=fine
		_ng.roads = String(_args.roads)
	map.generate(_ng.seed, _size_key, _ng.roads == "fine", _pending_edit)
	_pending_edit = {}


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
		if editor == null:
			map.camera.left_locked = false   # the left button drags the map everywhere but in the editor's brushes
		map.camera.keys_on = ((hud != null and hud.visible) or editor != null) and not modals.is_open() and not (fo is LineEdit or fo is TextEdit)
	if _live_n % 6 == 0 and win.visible and session != null and session.sim != null:
		Windows.tick_trips(session.sim, get_tree())
	_pick_process()
	Perf.begin("main._process")
	_process_t(delta)
	Perf.end("main._process")


func _process_t(delta: float) -> void:
	_pace_frames()
	if _loading.visible:
		_loading_step(delta)
	if legend != null:
		legend.sim = session.sim if session != null else null
		legend.visible = legend.sim != null
		legend.mode = map.mode
	if backdrop != null:
		backdrop.visible = (menu != null and menu.visible) or _loading.visible
	if session != null and session.sim != null:
		# decisions of the game wait for the player
		var sim := session.sim
		if sim.CO.get("sandbox", false) and sim.CO.cash < 1e11:   # the test sandbox: money without a limit
			sim.CO.cash = 1e12
		if sim.auto_choice < 0 and sim.modals.size() and not modals.is_open():
			modals.push(_decision(sim.modals.pop_front()))
		if win.visible and _live_n % 10 == 0:
			# a trip ended or began between days: the windows that list trips are built again at once
			# (and the board as soon as a vehicle comes back free: its orders can be planned again)
			var idle := 0
			for v in sim.CO.veh:
				if v.st == "idle":
					idle += 1
			var sig := [sim.CO.jobs.size(), sim.CO.get("cdel", 0), sim.CO.veh.size(), idle, sim.CO.board.size()]
			# at most every 1.5 s: with dozens of trips something changes several times a second, and building
			# the exchange (a plan per order) or a fleet of hundreds each time cost 40–150 ms
			var now_ms := Time.get_ticks_msec()
			if sig != _win_sig and hud.open_window in ["coTrips", "coFleet", "coHome", "coJobs"] and now_ms - _win_sig_t >= 1500:
				_win_dirty = true   # built again in the background, like a new day (not cleared first)
				_win_sig = sig
				_win_sig_t = now_ms
			_win_tick()
		while sim.toasts.size():
			var t: Dictionary = sim.toasts.pop_front()
			toasts.push(t.tone, t.t, t.d)
		# #toasts moves left of the card on the right
		toasts.offset_right = -(map_ui.insp_width() + 28) if map_ui.insp_open() else -14
		toasts.offset_left = toasts.offset_right - 320


# ---------- the world is ready: the headquarters ----------
func _on_world(w: Dictionary) -> void:
	_loading.visible = false
	if editor == null and _ng.map == "edit" and not w.has("edit") and _pending == null:
		_open_editor(w)
		return
	_edit = w.get("edit", {})
	if not _edit.is_empty() and _args.has("shot"):   # test: the edited world as the game got it
		print("TEST edited world: %d states, %d towns, %d roads, %d railways, %d checkpoints, own %s" % [w.states.size(), w.board.towns.size(), w.board.roads.size(),
			w.board.railways.size(), w.board.checkpoints.size(), PackedByteArray(w.own).hex_encode().md5_text()])
	if _args.has("colors"):   # test: the state colours of the HTML version, one #rrggbb per line
		var cols := []
		for l in FileAccess.get_file_as_string(_args.colors).split("\n", false):
			cols.append(Color(l.strip_edges()))
		map.set_colors(cols)
	if session != null:
		session.queue_free()
	session = GameSession.new()
	add_child(session)
	if _args.has("diff"):   # test: the difficulty (0 — «Навчальна», with the tutorial)
		_ng.diff = int(_args.diff)
	session.begin(map.generator(), GameState.world_seed, w.states, w.board, w, _ng.diff)
	if _ng.mode == "mm" or _args.get("gmode", "") == "mm":   # the multimodal mode (test): every order is built by hand
		session.sim.CO.mm = true
	if _ng.mode == "alt" or _args.get("gmode", "") == "alt":   # the alternative balance: the network of terminals (SimNet)
		session.alt = true
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
		var hq := int(_args.get("hq", str(session.choices[0].id))) if _args.get("hq", "") != "center" else _central_choice()
		_play(hq, true)
		if _args.has("demo"):
			session.demo_fleet()
			map.company_colors()
		if _args.has("stress"):   # test: a big company — every vehicle, the dispatcher sends what it can
			sandbox()
			var CO: Dictionary = session.sim.CO
			if not CO.mgr.has("cto") and CO.cand.has("cto"):
				CO.mgr.cto = CO.cand.cto[0].duplicate()
			CO.auto = true
			if _args.has("hubs"):   # --hubs=N: a hub network of N cities (the biggest ones it may open)
				var sm := session.sim
				var ps: Array = sm.PL.filter(func(p): return sm.hub_at(p.id) == null and sm.co_scope(p))
				ps.sort_custom(func(a, b): return a.pop > b.pop)
				for p in ps.slice(0, maxi(0, int(_args.hubs) - CO.hubs.size())):
					CO.cash = maxf(CO.cash, sm.hub_cost(p) * 2)
					sm.act_hub(p.id, false)
		if _args.has("closecty"):   # test: the headquarters' country closes its borders (the red lines)
			var sm := session.sim
			sm.CO.cls.append({"id": sm.CO.uid, "kind": "cty", "a": sm.PL[sm.CO.hq].cid, "why": "Test", "until": sm.co_now() + 30})
			sm.CO.uid += 1
			sm.inc_changed()
			sm.inc_blk()
		if _args.has("fast"):   # test: the fast progress of the settings
			fast_mode()
		if _args.get("plan", "") == "mm":   # test: the orders stay on the board for the player
			session.sim.CO.auto = false
		if _args.has("days") and _args.has("netbot") and session.sim.alt():   # test: the network played by NetBot
			var sm := session.sim
			for d in int(_args.days):
				NetBot.policy(sm)
				for f in 8:
					sm.co_frame(f / 8.0)
				sm.co_day()
			if _args.netbot != "true":   # --netbot=N: a few more orders taken, the trips of today under way
				for i in int(_args.netbot):
					NetBot.policy(sm, false)
			map.company_colors()
		elif _args.has("days"):
			session.run_days(int(_args.days))
		session.set_speed(int(_args.get("speed", "0")))
		if _args.get("select", "") == "net" and session.sim.alt():   # test: the day goes on until a run of the network is on the road
			var sm := session.sim
			for f in 16:
				if sm.CO.jobs.any(func(x): return x.get("net") != null and x.vids.size()):
					break
				sm.co_frame(minf(.99, sm.co_now() - sm.day + 1 / 16.0))
		if _args.has("select") and session.sim.CO.jobs.size():
			var js: Array = session.sim.CO.jobs.filter(func(x): return not x.get("ret") and (String(_args.select) in ["", "true"] or x.mode == _args.select or (_args.select == "net" and x.get("net") != null and x.vids.size())))
			map_ui.select_job(js[0] if js.size() else session.sim.CO.jobs[0], true)
		if _args.has("plan"):
			if _args.plan == "road" and _args.has("sandbox"):   # test: plenty of vehicles and every licence first
				sandbox()
				for i in 3:
					session.sim.co_board_day()
			var ks: Array = session.sim.CO.board.filter(func(x): return session.sim.co_plan(x).ok)
			if _args.plan == "multi":   # test: a multi-drop flight, landings in the most urgent order
				ks = session.sim.CO.board.filter(func(x): return x.get("multi") != null)
				print("TEST multi orders on the board: %d of %d" % [ks.size(), session.sim.CO.board.size()])
			if _args.plan == "road":   # test: an order whose road crosses a toll motorway or a ban, its leg laid
				var sm := session.sim
				ks = ks.filter(func(x):
					if x.mode != "road" or x.get("legs"):
						return false
					var ri := sm.road_info(sm.co_route("road", x.from, x.to))
					return ri.toll > 0 or ri.ban > 0)
			if _args.plan == "mm":   # test: the multimodal mode, a road leg straight to the end, its vehicle list open
				ks = session.sim.CO.board.filter(func(x): return not x.get("multi"))
				var sm0 := session.sim
				var hc: int = sm0.board.comp[sm0.PL[sm0.CO.hq].node]
				ks = ks.filter(func(x): return sm0.board.comp[sm0.PL[x.from].node] == hc and sm0.board.comp[sm0.PL[x.to].node] == hc)
				ks.sort_custom(func(a, b): return a.tons < b.tons)   # the lightest on the home land: a single truck takes it
			if ks.size():
				_plan(ks[0])
				if _args.plan == "mm":
					planner.mode = "road"
					planner.add(ks[0].to)
					planner._pick_leg = 0
					if _args.has("plango"):   # test: the first vehicle that holds the load carries the leg
						var c0: Dictionary = planner.sim.lp_calc(planner.LP).legs[0]
						for v in planner._leg_cands(c0):   # the first one that can really take it
							planner.LP.vehs[0] = v.id
							var C1: Dictionary = planner.sim.lp_calc(planner.LP)
							if planner.sim.lp_block(planner.LP, C1) == null:
								print("TEST mm: leg 0 by vehicle %d (%s at %s, %s), lead %.2f" % [v.id, v.t, session.sim.PL[v.loc].name, v.st, C1.legs[0].P.lead])
								break
							planner.LP.vehs.erase(0)
					planner._panel_build()
				if _args.plan == "auto":
					planner.auto_use()
				elif _args.plan == "dest":   # test: a click on the destination, as a player would
					planner.add(planner.LP.k.to)
				elif _args.plan == "multi":
					planner.order("urg")
				if _args.has("plango"):   # test: press «Відправити» a moment later
					get_tree().create_timer(1.0).timeout.connect(func():
						var t := Time.get_ticks_usec()
						planner.go()
						print("PERF plan go %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
						for j in session.sim.CO.jobs:
							if j.get("lp") and j.lp.plan.get("vehs") != null:
								print("TEST mm: job %s → %s by %s, lead %.2f" % [session.sim.PL[j.k.from].name, session.sim.PL[j.k.to].name, j.vids, j.lead]))
				elif _args.plan == "road":
					planner.LP.pts = [ks[0].from, ks[0].to]
					planner.LP.modes = ["road"]
					if _args.has("av"):
						planner.LP.av = String(_args.av).replace("+", ",")
					planner._panel_build()
		if _args.has("reroute"):
			session.sim.CO.xp = 1e6
			var js: Array = session.sim.CO.jobs.filter(func(x): return session.sim.sr_ok(x) and x.mode == _args.reroute)
			if js.size():
				_reroute(js[0])
		if _args.has("place"):
			map_ui.show_place(session.sim.CO.hq if _args.place == "hq" else int(_args.place))
		if _args.has("country"):
			map_ui.show_country(int(_args.country))
		if _args.has("win"):
			_toggle_window(_args.win)
			if _args.has("countryhubs"):   # test: the cities of a country, from «Відкрити хаб у країні»
				wins.country_hubs.emit(session.sim.PL[session.sim.CO.hq].cid)
		if _args.has("netwait"):   # test: orders taken, their cargo waiting at the shippers' (the boxes on the map)
			var nb: Array = session.sim.CO.board.duplicate()
			nb.sort_custom(func(a, b): return a.id > b.id)   # the newest: the top of the board
			for k in nb.slice(0, int(_args.netwait)):
				session.sim.net_accept(k)
			if win.visible:
				_win_tick(true)
		if _args.has("netind"):   # test: the sea licence and permits, a board with refineries and shiploads
			var sm := session.sim
			sm.CO.tier = 6
			sm.CO.perm = {"adr": {"until": 1e9}, "imdg": {"until": 1e9}}
			sm.CO.board = []
			for i in 60:
				var k: Variant = sm.co_gen()
				if k != null and (k.get("sea") or k.get("refy")) and sm.CO.board.size() < 8:
					sm.CO.board.append(k)
			if win.visible:
				_win_tick(true)
		if _args.has("ctrdemo"):   # test: two good clients — one offers a contract, one has signed
			var sm := session.sim
			var ks: Array = sm.CO.board.filter(func(x): return x.get("fs"))
			for i in mini(2, ks.size()):
				var k: Dictionary = ks[i]
				var key := SimNet.firm_key(k.from, k.fs)
				sm._nets().firms[key] = {"n": k.fs, "at": k.from, "ok": 15, "late": 0, "off": -999.0, "lanes": {str(k.to): {"n": 15, "pay": k.pay * 15, "tons": k.tons * 15, "cg": {k.cg: 15}}},
					"need": 7, "rmin": 1.0, "good": 15, "dmg": 0}
				if i == 0:
					sm._offer(sm.ctr_terms(key))
				else:
					sm.act_ctr_ask(k.from, k.fs)
			if win.visible:
				_win_tick(true)
		if _args.has("netdlg"):   # test: a run dialog of the network (round / trunk / pick)
			var sm := session.sim
			if _args.has("netacc"):   # --netacc=N: N orders taken into the network first, some brought to the hub
				for k in sm.CO.board.slice(0, int(_args.netacc)):
					sm.net_accept(k)
				for c in sm.CO.net.cs.slice(0, 3 if _args.netdlg != "trunk" else 99):
					c.at = sm.CO.hq
					c.st = "ready"
			match String(_args.netdlg):
				"pick":
					var wt: Array = sm.CO.net.cs.filter(func(c): return c.st == "wait" and c.run < 0)
					if wt.size():   # as «Забрати» does: the route panel from the headquarters
						var c0: Dictionary = wt[0]
						_net_dialog("route", {"a": sm.CO.hq, "focus": c0.id})
				"manage":
					_net_dialog("manage", {"a": sm.CO.hq})
				"trunk", "route":
					var ta := {"a": sm.CO.hq}
					if _args.has("netempty"):   # test: a route from the headquarters that only picks up on the way
						for c in sm.CO.net.cs:
							c.at = c.k.from
							c.st = "wait"
						sm.CO.net.cs = sm.CO.net.cs.filter(func(c): return c.at != sm.CO.hq)
						var wt: Array = sm.CO.net.cs.filter(func(c): return c.st == "wait")
						if wt.size():   # --netempty=pick: only where it is picked up
							ta.way = [wt[0].at] if String(_args.netempty) == "pick" else [wt[0].at, wt[0].k.to]
					if _args.has("netway"):   # --netway=N: a truck and N stops the player put in
						sm.CO.veh.push_front({"id": sm.CO.uid, "t": "truck", "loc": sm.CO.hq, "st": "idle", "cond": 100.0, "km": 0.0})
						sm.CO.uid += 1
						sm.CO.staff.driver += 1
						var way := sm.net_way_auto(sm.CO.hq, [], "road", false)
						while way.size() < int(_args.netway):
							var cs: Array = sm.net_way_cands(sm.CO.hq, way, "road", false).filter(func(x): return x.to > 0)
							if cs.is_empty():
								break
							way = cs[0].way
						ta.way = way
						if _args.has("netvia") and way.size():   # --netvia: a road point aside of the first leg
							var A_: Dictionary = sm.PL[sm.CO.hq]
							var B_: Dictionary = sm.PL[way[0]]
							var k_ := float(_args.netvia) if _args.netvia != "true" else .35
							var mx: float = (A_.x + B_.x) / 2 + (B_.z - A_.z) * k_
							var mz: float = (A_.z + B_.z) / 2 - (B_.x - A_.x) * k_
							var Bd: Dictionary = sm.board
							var best := -1
							var bd := 1e9
							for v in Bd.bits.size():
								if Bd.bits[v] != 0:
									var px: float = -Bd.wx / 2 + (v % Bd.nx) * Bd.st
									var pz: float = -Bd.wz / 2 + (v / Bd.nx) * Bd.st
									var d := Vector2(px - mx, pz - mz).length()
									if d < bd:
										bd = d
										best = v
							ta.way = [{"v": best, "x": -Bd.wx / 2 + (best % Bd.nx) * Bd.st, "z": -Bd.wz / 2 + (best / Bd.nx) * Bd.st}] + way
						for c in sm.CO.net.cs:   # the order the panel was opened for, as from «Прийняті вантажі»
							if c.at == sm.CO.hq and c.run < 0 and way.has(c.k.to):
								ta.focus = c.id
								break
					_net_dialog(String(_args.netdlg), ta)
				_:
					_net_dialog("round", {"a": sm.CO.hq})
		if _args.has("thenedit"):   # test: from a running game back to a new world in the editor
			await get_tree().create_timer(1.0).timeout
			_end_game()
			_args.erase("company")
			_ng.map = "edit"
			_create_world()
			return
		if _args.has("save"):   # test: save into a slot
			var sd := _save_data()
			SaveSystem.write(_args.save, sd.data, sd.meta)
		map.camera.tx = map.camera.ttx   # no glide for a screenshot
		map.camera.tz = map.camera.ttz
		map.camera.dist = map.camera.tdist
	elif not (_args.has("shot") and not _args.has("pick")):
		_pick_hq()
		if _args.has("pickat") or _args.has("pickclick"):   # test: the world, then a state hovered or clicked
			modals.clear()
			map.camera.look_at_point(Vector2(0, .55), map.camera.world_size.x * 1.03)
			map.camera.tx = map.camera.ttx
			map.camera.tz = map.camera.ttz
			map.camera.dist = map.camera.tdist
			for i in 4:
				await get_tree().process_frame
			var c: PackedStringArray = String(_args.get("pickat", _args.get("pickclick"))).split(",")
			var at := Vector2(float(c[0]), float(c[1]))
			if _args.has("pickclick"):   # a real click: the press and the release go through the input, like a player's
				for pr in [true, false]:
					var ev := InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = pr
					ev.position = at
					ev.global_position = at
					Input.parse_input_event(ev)
					await get_tree().process_frame
			else:
				Input.warp_mouse(at)
			for i in 6:
				await get_tree().process_frame
	if _args.has("winscroll") and win.visible:   # test: the open window scrolled down by so many pixels
		for i in 30:
			await get_tree().process_frame
		win.scroll.scroll_vertical = int(_args.winscroll)
		for i in 4:
			await get_tree().process_frame
	if _args.has("roadstyle"):   # test: the look of the roads (MapOverlay.road_style)
		MapOverlay.road_style = int(_args.roadstyle)
		map.overlay.road_colors()
	if _args.has("cam"):
		var c: PackedStringArray = String(_args.cam).split(",")
		if c[0] == "hq" and session != null:   # --cam=hq,dist: the headquarters
			var hp: Dictionary = session.sim.PL[session.sim.CO.hq]
			c = PackedStringArray([str(hp.x), str(hp.z), c[1]])
		map.camera.look_at_point(Vector2(float(c[0]), float(c[1])), float(c[2]))
		map.camera.tx = map.camera.ttx
		map.camera.tz = map.camera.ttz
		map.camera.dist = map.camera.tdist
	if _args.has("camwx") and session != null and session.sim.CO.get("wx", []).size():   # test: close up on a weather zone
		var wz: Dictionary = session.sim.CO.wx[0]
		if _args.has("wxk"):   # test: the zone of this kind (--wxk=fog)
			wz.k = String(_args.wxk)
		map.camera.look_at_point(Vector2(wz.x, wz.z), float(_args.camwx))
		map.camera.tx = map.camera.ttx
		map.camera.tz = map.camera.ttz
		map.camera.dist = map.camera.tdist
	if _args.has("decide") and session != null:   # test: an incident on the first trip of its mode until it asks a decision (--decide=brk|acc)
		var sim_ := session.sim
		sim_.auto_choice = -1
		var js: Array = sim_.CO.jobs.filter(func(x): return x.mode == "road" and not x.get("ret"))
		if js.size():
			for i in 60:
				if sim_.modals.size():
					break
				sim_.CO.mcd = 0
				sim_.co_incident(js[0], String(_args.decide))
		if sim_.modals.size():
			modals.push(_decision(sim_.modals.pop_front()))
		for i in 6:
			await get_tree().process_frame
	if _args.has("closecp") and session != null:   # test: the first border checkpoint closed, the camera on it (--closecp=dist)
		var sim_ := session.sim
		var c: Dictionary = sim_.board.checkpoints.filter(func(q): return not q.rail)[0]
		sim_.CO.cls.append({"id": sim_.CO.uid, "kind": "cp", "a": c.a, "b": c.b, "x": c.x, "z": c.z, "why": "тест", "until": sim_.day + 30})
		sim_.CO.uid += 1
		sim_.CO.clV = sim_.CO.get("clV", 0) + 1
		map.camera.look_at_point(Vector2(c.x, c.z), float(_args.closecp))
		map.camera.tx = map.camera.ttx
		map.camera.tz = map.camera.ttz
		map.camera.dist = map.camera.tdist
	if _args.has("sandbox") and session != null:   # test: the sandbox of the settings
		sandbox()
	if _args.has("hide"):   # test: kinds hidden from the legend, --hide=roads,rail
		for k in String(_args.hide).split(","):
			MapVis.toggle(k)
		map.apply_vis()
	if _args.has("yaw"):   # test: the camera turned
		map.camera.yaw = float(_args.yaw)
		map.camera.tyaw = map.camera.yaw
	if _args.has("hour"):   # test: the day and night at this hour (--hour=22)
		map.night_hour = float(_args.hour)
	if _args.has("trailer"):   # a scene of the trailer (scripts/trailer.gd, tools/trailer.sh)
		add_child(Trailer.new(self, String(_args.trailer)))
	if _args.has("story"):   # the scripted trailer (scripts/trailer_story.gd, tools/trailer_story.sh)
		add_child(TrailerStory.new(self))
	if _args.has("take"):   # a take of the trailer studio recorded by Movie Maker (with --load=trailer_<name>)
		studio = TrailerStudio.new(self)
		add_child(studio)
		studio.render_take(String(_args.take))
	if _args.has("studiokey"):   # test: the key left of 1 pressed as a player presses it
		for pr in [true, false]:
			var ev := InputEventKey.new()
			ev.physical_keycode = TrailerStudio.KEY
			ev.keycode = KEY_APOSTROPHE   # what the Ukrainian layout gives there
			ev.pressed = pr
			Input.parse_input_event(ev)
			await get_tree().process_frame
		for i in 3:
			await get_tree().process_frame
		print("TEST studio by its key: %s" % is_instance_valid(studio))
	if _args.has("studio"):   # test: the trailer studio open
		studio = TrailerStudio.new(self)
		add_child(studio)
		if _args.has("studioret"):   # test: the camera turned and close, then back to the standard view
			for c in [["yaw", 1.3], ["tyaw", 1.3], ["dist", 3.0], ["tdist", 3.0]]:
				map.camera.set(c[0], c[1])
			for i in 3:
				await get_tree().process_frame
			studio.opts.ret = 1.0
			var d0 := map.camera.dist
			studio.return_view()
			var t0 := Time.get_ticks_msec()
			while not studio._ret.is_empty() and Time.get_ticks_msec() - t0 < 20000:
				await get_tree().process_frame
			print("TEST studio return: yaw %.3f, dist %.2f → %.2f, at %.2f, %.2f" % [map.camera.yaw, d0, map.camera.dist, map.camera.tx, map.camera.tz])
		if _args.has("studioscroll"):   # test: the exchange open and scrolled slowly for a while
			studio.act("win", {"id": "coJobs"})
			for i in 20:
				await get_tree().process_frame
			studio.act("scroll", {"dir": 1, "spd": 300.0})
			var v0: int = win.scroll.scroll_vertical
			for i in int(_args.studioscroll):
				await get_tree().process_frame
			print("TEST studio scroll: %d → %d px, window %s, quiet: decisions answer themselves %s, toasts shown %s" % [v0, win.scroll.scroll_vertical, hud.open_window, session.sim.auto_choice == 0, toasts.visible])
		if _args.has("studiokeys"):   # test: two camera points, the glide between them; the interface hidden by its key
			var c := map.camera
			studio._put_cam(-3.0, 1.0, 9.0, 0.0)
			studio.add_key()
			studio._put_cam(2.0, -.5, 4.0, .9)
			studio.add_key()
			studio.opts.key_dur = 30.0
			studio.run_keys()
			var seen := []
			for f in 60:
				await get_tree().process_frame
				if f % 12 == 11:
					seen.append("t%.1f %.2f,%.2f d%.1f y%.2f" % [studio._play_t, c.tx, c.tz, c.dist, c.yaw])
			print("TEST studio keys: %d samples · %s" % [studio.path.size(), " → ".join(PackedStringArray(seen))])
			_key_action("hide_ui")
			var hidden := not _ui.visible
			_key_action("hide_ui")
			print("TEST hide ui: hidden %s, back %s" % [hidden, _ui.visible])
		if _args.has("subdemo"):   # test: subtitles' previews — a card drifting right, bare text still
			studio.sub.align = String(_args.get("subalign", "left"))   # --subalign=left|center|right
			studio.sub.anim = String(_args.get("subanim", "fade"))   # --subanim=fade|up|side|pop|wipe|type
			studio.preview_sub(studio.sub.duplicate())
			var it2: Dictionary = studio.sub.duplicate()
			it2.title = "ВАНТАЖІВКИ · ПОТЯГИ · КОРАБЛІ"
			it2.text = ""
			it2.box = false
			it2.drift = 0
			it2.color = "#f1c453"
			it2.size = 56
			it2.y = .18
			studio.preview_sub(it2)
			if _args.has("trips"):   # and trips all over the world, ×N per town
				var t0 := Time.get_ticks_msec()
				studio.act("trips", {"dens": int(_args.trips), "kinds": studio.opts.kinds.duplicate(), "seed": 7})
				print("TEST studio trips ×%s: %d trips in %d ms, %d towns" % [_args.trips, session.sim.CO.jobs.size(), Time.get_ticks_msec() - t0, session.sim.PL.size()])
				if _args.has("cleartrips"):
					studio.act("clear_trips", {})
					print("TEST studio trips cleared: %d left" % session.sim.CO.jobs.size())
			if _args.has("hubwave"):
				var h := studio._here()
				h.spd = 200.0
				studio.act("hubs", h)
			if _args.has("studioreset"):   # test: everything undone — the hubs, the trips, the events, the counters
				for i in 40:
					await get_tree().process_frame
				studio.act("storm", studio._here())
				studio.act("cnt", {"k": "cash", "to": -5.0, "dur": .1})
				for i in 5:
					await get_tree().process_frame
				var CO: Dictionary = session.sim.CO
				print("TEST studio before reset: hubs %d, trips %d, weather %d, counters %d" % [CO.hubs.size(), CO.jobs.size(), CO.wx.size(), hud.studio.size()])
				studio.reset_all()
				CO = session.sim.CO
				print("TEST studio after reset: hubs %d, trips %d, weather %d, counters %d" % [CO.hubs.size(), CO.jobs.size(), CO.wx.size(), hud.studio.size()])
		if _args.has("studiodemo"):   # test: a way recorded with some buttons, saved, played as a take
			for i in 5:
				await get_tree().process_frame
			studio.take_name = "demo"
			studio.toggle_rec()
			for f in 120:
				map.camera.ttx += .015
				map.camera.tdist *= .997
				map.camera.tyaw += .004
				if f == 20:
					studio.act("trips", {"n": 40, "kinds": studio.opts.kinds.duplicate()})
				if f == 40:
					studio.act("cnt", {"k": "cash", "to": -250000.0, "dur": 1.0})
				if f == 60:
					studio.act("storm", studio._here())
				await get_tree().process_frame
			studio.toggle_rec()
			studio.save_take()
			print("TEST studio: %d samples, %d buttons, %.2f s" % [studio.path.size(), studio.acts.size(), studio.path.back()[0]])
			studio.play(true)
			for i in int(_args.studiodemo):
				await get_tree().process_frame
			print("TEST studio take: panel %s, windows %s, hud cash %s" % [studio.panel.visible, map_ui.visible, str(hud.studio.get("cash"))])
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
		if _args.has("rename"):   # test: the company's name dialog
			_rename_dialog()
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
## the start (08l-start.js): on every difficulty the player picks a state on the map; the headquarters
## opens in its capital. Hovering a state shows what starting there means, a click asks to confirm.
var _picking := false
var _pick_bar: Control = null
var _pick_tip: PanelContainer = null
var _pick_cid := -2
var _demand := {}


func _pick_hq() -> void:
	var sim := session.sim
	_picking = true
	_demand = {}
	if not map.camera.clicked.is_connected(_pick_click):
		map.camera.clicked.connect(_pick_click)
	var D_ := ["Навчальна складність", "Звичайна складність", "Жорстка складність"]
	modals.push({"icon": "globe", "eyebrow": D_[clampi(sim.diff, 0, 2)], "title": "Оберіть країну старту",
		"body": "У вас [b]%s[/b] і одна вантажна машина. Клікніть на мапі на будь-яку державу: штаб відкриється в її столиці. Наведіть на державу — покажемо, скільки в ній міст, який попит на перевезення й ризики." % Ui.usd(sim.CO.cash),
		"hint": "У [b]малій[/b] державі на 3–4 міста біржа на старті скромна: замовлень менше, поки компанія не вийде за кордон. У [b]великій[/b] — більше міст, довші рейси й більше пропозицій.",
		"choices": [{"t": "Обрати на мапі", "d": "Камера покаже весь світ", "f": func():
			var ws: Vector2 = map.camera.world_size
			map.camera.look_at_point(Vector2(0, .55), ws.x * 1.03)}]})
	_pick_bar = Ui.glass(Ui.GLASS_HI, Ui.LINE_HI)
	_pick_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pick_bar.add_child(Ui.margin(Ui.hbox(10, [Ui.icon("pin", 16, Ui.ACCENT), Ui.label("Клікніть на державу, щоб відкрити в ній штаб", 13)]), 16, 10))
	_ui.add_child(_pick_bar)
	_pick_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pick_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	_pick_tip = Ui.glass(Ui.GLASS_HI, Ui.LINE_HI)
	_pick_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pick_tip.visible = false
	_pick_tip.custom_minimum_size.x = 300
	_ui.add_child(_pick_tip)


## the capital of a state (or its largest town)
func _pick_cap(cid: int) -> Variant:
	var best: Variant = null
	for p in session.sim.PL:
		if p.cid != cid:
			continue
		if p.type == "cap":
			return p
		if best == null or p.pop > best.pop:
			best = p
	return best


## coDemand: the freight demand of a state against the others (firms of its towns, their size, the wealth)
func _pick_demand(cid: int) -> Array:
	var sim := session.sim
	if _demand.is_empty():
		var v := []
		v.resize(sim.states.size())
		v.fill(0.0)
		for p in sim.PL:
			v[p.cid] += sim.firms_of(p.id).size() * sqrt(p.pop + .05)
		for c in v.size():
			v[c] *= .5 + sim.states[c].dev
		var srt := v.duplicate()
		srt.sort()
		_demand = {"v": v, "q": [srt[int(srt.size() / 3.0)], srt[int(srt.size() * 2 / 3.0)]]}
	var x: float = _demand.v[cid]
	return ["Високий", Ui.GOOD] if x >= _demand.q[1] else (["Середній", Ui.WARN] if x >= _demand.q[0] else ["Низький", Ui.BAD])


## how many orders the board holds at the start in a state (co_board_max with one hub there)
func _pick_offers(cid: int) -> int:
	var sim := session.sim
	var n := 0
	for p in sim.PL:
		if p.cid == cid:
			n += 1
	return maxi(3, int(JS.round_js((8 + 2) * JS.clamp_js(n / 12.0, .35, 1.4))))


func _pick_info(cid: int, p: Dictionary) -> Control:
	var sim := session.sim
	var n := 0
	for q in sim.PL:
		if q.cid == cid:
			n += 1
	var v := Ui.vbox(8)
	v.add_child(Ui.hbox(10, [Flags.rect(sim.states[cid], 24, 16), MapUi._left(Ui.label(sim.states[cid].name, 15, Ui.FG, Ui.font("body", 700))), Ui.spacer(), Ui.label("%d міст" % n, 12, Ui.MUTED)]))
	var kv := GridContainer.new()
	kv.columns = 2
	kv.add_theme_constant_override("h_separation", 14)
	kv.add_theme_constant_override("v_separation", 4)
	var dm := _pick_demand(cid)
	var rw := Windows._risk_w(sim.co_risk(cid))
	for r in [["Штаб у столиці", p.name, Ui.FG], ["Населення столиці", Ui.people(p.pop), Ui.FG], ["Біржа на старті", "до %d замовлень" % _pick_offers(cid), Ui.FG],
			["Попит на перевезення", dm[0], dm[1]], ["Ризик перевезень", rw[0], Windows._tone_col(rw[1])]]:
		var l := Ui.label(r[0], 13, Ui.FG2)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kv.add_child(l)
		var b := Ui.label(r[1], 13, r[2], Ui.font("body", 600))
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kv.add_child(b)
	v.add_child(kv)
	return v


func _pick_process() -> void:
	if not _picking or _pick_tip == null:
		return
	var mp := get_viewport().get_mouse_position()
	var cid := -1
	if not modals.is_open() and get_viewport().gui_get_hovered_control() == null:
		var w: Variant = map.camera.pick_plane(mp)
		cid = map.state_at(w) if w != null else -1
	var p: Variant = _pick_cap(cid) if cid >= 0 else null
	if p == null:
		_pick_tip.visible = false
		_pick_cid = -2
		return
	if cid != _pick_cid:
		_pick_cid = cid
		for c in _pick_tip.get_children():
			if not (c is ColorRect):   # the glass background stays
				_pick_tip.remove_child(c)
				c.queue_free()
		var v := _pick_info(cid, p)
		v.add_child(Ui.label("Клік — відкрити штаб тут", 12, Ui.MUTED))
		_pick_tip.add_child(Ui.margin(v, 12, 10))
		_pick_tip.reset_size()
	_pick_tip.visible = true
	var vs := get_viewport().get_visible_rect().size
	var sz := _pick_tip.get_combined_minimum_size()
	var x := mp.x + 18 if mp.x + 18 + sz.x < vs.x - 10 else mp.x - sz.x - 18
	_pick_tip.position = Vector2(x, clampf(mp.y - sz.y / 2, 70, vs.y - sz.y - 10))


func _pick_click(mp: Vector2) -> void:
	if not _picking or modals.is_open():
		return
	var w: Variant = map.camera.pick_plane(mp)
	var cid: int = map.state_at(w) if w != null else -1
	if cid < 0:
		toasts.push("warn", "Тут немає держави", "Клікніть на сушу")
		return
	var p: Variant = _pick_cap(cid)
	if p == null:
		toasts.push("warn", "У цій державі немає міст", "Оберіть іншу")
		return
	var pid: int = p.id
	modals.push({"icon": "building", "eyebrow": "Країна старту", "title": "%s, %s" % [p.name, session.sim.states[cid].name],
		"choices": [{"t": "Відкрити штаб тут", "d": "Компанія стартує в цій столиці", "hl": true, "f": func(): _pick_done(pid)},
			{"t": "Обрати іншу країну", "d": "Повернутися до мапи", "f": func(): pass}]})


func _pick_done(pid: int) -> void:
	_picking = false
	for n in [_pick_bar, _pick_tip]:
		if n != null:
			n.queue_free()
	_pick_bar = null
	_pick_tip = null
	_play(pid, false)
	var hp: Dictionary = session.sim.PL[pid]
	# the company's first frames are heavy (its board, the layers): the camera sets off after them, so the
	# glide to the headquarters starts smooth instead of with a jump
	for i in 3:
		await get_tree().process_frame
	map.camera.look_at_point(Vector2(hp.x, hp.z + .3), 6.0)


func _play(hq: int, auto_decisions: bool, loaded: bool = false) -> void:
	if not loaded:
		session.choose_hq(hq, auto_decisions)
	else:   # the hour the game was saved at
		session.paused_fr = clampf(float(session.sim.CO.get("lastFr", 0.0)), 0, .999)
	session.set_speed(0)
	map.attach_session(session)
	map.overlay.set_marks(session.sim.road_mark_segs() if session.sim.road_rules else [])   # toll motorways, bans
	map.apply_vis()
	wins = Windows.new(session.sim)
	wins.acted.connect(_on_act)
	wins.goto_place.connect(_goto_place)
	wins.select_job.connect(func(j): map_ui.select_job(j, true))
	map_ui.attach(session, map)
	map_ui.planner = planner
	planner.attach(session, map)
	netp.attach(session, map)
	map_ui.netp = netp
	course.attach(session, map, planner)
	map_ui.course = course
	if not map_ui.reroute.is_connected(_reroute):
		map_ui.reroute.connect(_reroute)
	wins.plan_order.connect(_plan)
	wins.rename_requested.connect(_rename_dialog)
	wins.net_dialog.connect(_net_dialog)
	wins.country_hubs.connect(func(cid):   # «Відкрити хаб у країні»: its cities, to buy or rent a hub
		var sm := session.sim
		modals.push({"icon": "building", "eyebrow": "Відкрити хаб", "title": sm.states[cid].name, "close": true, "width": 760,
			"content": wins.country_hub_list(cid, func(): modals.clear())}))
	_warm_flags(session.sim)
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
	# the tutorial: a new game on «Навчальна», or a saved one in the middle of it
	var CO: Dictionary = session.sim.CO
	if not loaded and session.sim.diff == 0 and not _args.has("notut"):
		CO.tut = int(_args.get("tut", "0"))
	if int(CO.get("tut", -1)) >= 0:
		tutorial.start(int(CO.tut))
	else:
		tutorial.visible = false
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
	"coNet": ["globe", "Мережа хабів"], "coStaff": ["users", "Персонал і менеджмент"], "coFin": ["coins", "Фінанси"], "news": ["news", "Стрічка новин"],
	"coCargo": ["check", "Прийняті вантажі"]}


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
var _win_sig: Array = []
var _win_sig_t := 0
var _win_building := false
var _win_dirty := false


## the content of the open window, built again every game day and after every action
func _win_tick(force: bool = false) -> void:
	var sim := session.sim
	if not force and ((sim.day == _win_day and not _win_dirty) or session.day_busy()):
		return   # nothing new, or the new day is still being worked out
	if not force and _win_day >= 0 and (win.scroll as SmoothScroll).busy():
		return   # later: the content does not change under the reader's hand
	# a new day: the window changes in small steps over a few frames; opening it or an action: at once
	var smooth := not force and _win_day >= 0 and hud.open_window == _win_id
	if smooth and _win_building:
		return   # the update before is still being built: this one comes after it
	_win_day = sim.day
	_win_dirty = false
	var id := hud.open_window
	var opened := id != _win_id   # another window: what the last one showed goes at once
	_win_id = id
	if smooth and _args.has("perf"):
		print("PERF day %.1f ms" % (Perf.acc.get("co_day", 0) / 1000.0))
	var h: Array = WIN_HEAD.get(id, ["info", id])
	if id == "coNet" and sim.alt():   # the alternative balance: the hubs are terminals
		h = ["globe", "Термінали"]
	win.set_head(h[0], "%s · %s" % [sim.CO.name, Ui.date_str(sim.date)], h[1])
	if smooth:
		await get_tree().process_frame   # not in the frame the day was computed in
		if hud.open_window != id:
			return
	var keep := win.scroll.scroll_vertical
	var t0 := Time.get_ticks_usec()
	Perf.begin("window.build")
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
		# every build goes over as many frames as it needs (a few ms each): the content shown stays until the new
		# one is ready; of builds that overlap, the latest is the one shown
		if opened:
			win.clear_body()
		_build_gen += 1
		var bg := _build_gen
		_win_building = smooth
		await wins.build(id, off, true)
		if bg == _build_gen:
			_win_building = false
		if bg != _build_gen or hud.open_window != id:   # a newer build, or the window closed or switched meanwhile
			Perf.end("window.build")
			off.free()
			return
	Perf.end("window.build")
	var t_build := Time.get_ticks_usec() - t0
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
		print("PERF window %s %s: build %.1f ms%s (plans %.1f) · until shown %.1f ms" % [id, "swapped" if smooth else "built", t_build / 1000.0,
			(" in %d frames, the longest %.1f ms" % [wins.slices, wins.slice_max / 1000.0]) if wins.slices > 1 else "", Perf.acc.get("co_plan", 0) / 1000.0, (Time.get_ticks_usec() - t0) / 1000.0])


var _win_id := ""
var _build_gen := 0
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


## the alternative balance: a run of the network (a round of a hub's area, a haul, a pick-up) in a dialog
func _net_dialog(kind: String, args: Dictionary) -> void:
	var sim := session.sim
	if kind == "route":   # the route on the map: the windows and the cards step aside
		modals.clear()
		if win.visible:
			_toggle_window("")
		map_ui.close_insp()
		map_ui.close_card()
		hud.set_planning(true)
		netp.open_net(args.a, args)
		return
	if kind == "manage":
		modals.push({"icon": "gear", "eyebrow": "Термінали · " + sim.PL[args.a].name, "title": "Керування терміналом", "close": true, "width": 780,
			"content": NetWin.new(wins).manage(args.a, func(): modals.clear())})
		return
	var t: String = {"round": "Кільцевий рейс", "trunk": "Магістральний рейс", "pick": "Забрати вантаж"}.get(kind, "Рейс")
	var sub := ""
	if args.has("a"):
		sub = sim.PL[args.a].name
	elif args.has("cs"):
		var c: Variant = sim._cs(args.cs)
		if c != null:
			sub = sim.PL[c.at].name
	modals.push({"icon": {"round": "refresh", "trunk": "send", "pick": "truck"}.get(kind, "road"), "eyebrow": "Мережа терміналів · " + sub, "title": t, "close": true, "width": 780,
		"content": NetWin.new(wins).dialog(kind, args, func(): modals.clear())})


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
	session.finish_day()   # a day half done is not saved
	var sim := session.sim
	var data := {"v": 1, "seed": GameState.world_seed, "size": _size_key, "roads": _ng.roads, "diff": sim.diff, "sim": sim.save_state()}
	if not _edit.is_empty():   # a world of the map editor: made again from its edit
		data["edit"] = _edit
	return {"data": data,
		"meta": {"name": sim.CO.name, "col": sim.CO.get("col", "#ffb347"), "date": Ui.date_str(sim.date), "mode": "Логістична компанія",
			"when": Time.get_datetime_string_from_system(false, true).substr(5, 11).replace("T", " ")}}


## autosave: not while planning, in a dialog or before the headquarters
func _autosave() -> Variant:
	if not Settings.get_value("autosave"):
		return {}
	if session == null or session.sim == null or not hud.visible or planner.on or netp.on or course.on or modals.is_open():
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


# ---------- the map editor ----------
func _open_editor(w: Dictionary) -> void:
	backdrop.visible = false
	hud.visible = false   # nothing of a game over the editor
	map_ui.visible = false
	if win.visible:
		_toggle_window("")
	editor = MapEditor.new()
	editor.theme = Ui.theme()
	editor.toast = func(tone, t, d): toasts.push(tone, t, d)
	_ui.add_child(editor)
	_ui.move_child(editor, toasts.get_index())   # under the toasts and the dialogs
	editor.start(map, map.generator(), w, _ng.base == "blank")
	editor.finished.connect(_editor_done)
	editor.cancelled.connect(func():
		modals.push({"icon": "alert", "tone": "warn", "eyebrow": "Редактор мапи", "title": "Вийти без гри?", "body": "Зміни мапи не збережуться.", "close": true, "width": 420,
			"choices": [{"t": "Вийти в меню", "f": func():
				_close_editor()
				map.edit_end()
				_show_menu()}, {"t": "Лишитися", "f": func(): pass}]}))
	Music.menu()
	toasts.push("", "Редактор мапи", "Обери державу й малюй пензлем, або створи нову")
	if _args.has("edscript"):   # test: a scripted edit, then (--edscript=go) the game on it
		await get_tree().process_frame
		editor.test_script()
		if _args.edscript == "go":
			editor._finish()
		elif _args.edscript == "cancel":   # test: out of the editor with a brush in hand, then a generated world
			await get_tree().process_frame
			_close_editor()
			map.edit_end()
			_ng.map = "gen"
			_create_world()
			return
	if _args.has("shot") and editor != null and not _args.get("edscript", "") in ["go", "cancel"]:
		for i in 30:
			await get_tree().process_frame
		await get_tree().create_timer(float(_args.get("wait", "1.5"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args.shot)
		get_tree().quit()


func _close_editor() -> void:
	if editor != null:
		editor.stop()
		editor.queue_free()
		editor = null


## «Почати гру»: the edited world is made (states, board, textures) and the game starts on it
func _editor_done(e: Dictionary) -> void:
	_close_editor()
	_loading.visible = true
	_load_t = 0.0
	map.build_edit(e)


func _end_game() -> void:
	tutorial.visible = false
	tutorial.i = -1
	if planner.on:
		planner.close()
	if netp.on:
		netp.close()
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
	_ng.map = "earth" if _ng.size == "earth" else "gen"
	if _ng.size == "earth":
		_ng.size = "l"
	_ng.diff = int(d.get("diff", 1))
	_ng.roads = String(d.get("roads", "norm"))
	_pending_edit = d.get("edit", {})
	if not _pending_edit.is_empty():
		_ng.map = "edit"
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
	# the trailer studio (scripts/ui/trailer_studio.gd): the key left of 1, by its place (` on the English layout,
	# ' on the Ukrainian); not F8 — the Godot editor stops the running game on F8
	if e.physical_keycode == TrailerStudio.KEY:
		if session != null and session.sim != null and hud.visible and not is_instance_valid(studio):
			studio = TrailerStudio.new(self)
			add_child(studio)
		return
	match e.keycode:
		KEY_F9:
			_toggle_checks()
		KEY_F3:
			perf_panel.toggle()
		KEY_F4:
			perf_rec.toggle()
		KEY_ESCAPE:
			if planner.on or netp.on or course.on or map_ui.mv_v != null:
				return
			if win.visible:
				_toggle_window("")
			elif map_ui.insp_open():
				map_ui.close_insp()
			elif session != null and hud.visible and not modals.is_open():
				_game_menu()


var _last_speed := 1


## --hq=center: the start offered nearest to the map's centre (the trailer's story opens on it)
func _central_choice() -> int:
	var best: int = session.choices[0].id
	var bd := 1e9
	for c in session.choices:
		var p: Dictionary = session.sim.PL[c.id]
		var d := Vector2(p.x, p.z - .6).length()
		if d < bd:
			bd = d
			best = c.id
	return best


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
		"hide_ui":   # the whole interface away (and the windows closed) for a clean picture; the key again brings it back
			if _ui.visible:
				if win.visible:
					_toggle_window("")
				map_ui.close_card()
				map_ui.close_insp()
			_ui.visible = not _ui.visible
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


## the state of the game for the performance record, once a second
func _perf_context() -> Dictionary:
	var c := {"screen": "menu" if menu != null and menu.visible else ("loading" if _loading.visible else "game")}
	if session != null and session.sim != null and hud.visible:
		var CO := session.sim.CO
		c.speed = session.speed
		c.day = int(session.sim.day)
		c.zoom = snappedf(map.camera.dist, .01)
		c.yaw = snappedf(map.camera.yaw, .01)
		c.layer = map.mode
		c.map = "%d/%s/%s" % [GameState.world_seed, _size_key, _ng.roads]   # seed / size / road net: to make the world again
		c.win = hud.open_window if hud.open_window != "" else "-"
		c.dialog = modals.is_open()
		c.trips = CO.jobs.size()
		c.veh = CO.veh.size()
		c.hubs = CO.hubs.size()
		c.board = CO.board.size()
		c.wx = CO.get("wx", []).size()
		c.sandbox = CO.get("sandbox", false)
	return c


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
