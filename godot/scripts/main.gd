extends Node
## The game: the main menu, a new game (size, difficulty, seed), the world generation, the choice of the
## headquarters, then the map with the interface (HUD, windows, dialogs). F9 — the checks (all tests, green/red).
## Command line (automatic screenshots): godot --path godot -- [--seed=777] [--shot=path.png] [--cam=x,z,dist]
##   [--company [--demo: a fleet with a dispatcher] [--hq=place id]] [--days=N] [--speed=0…3] [--select]
##   [--win=coJobs] [--pick: stop at the choice of the headquarters] [--menu: the main menu]
##   [--place=pid | --country=cid: the card on the right] [--mouse=x,y: hover] [--click=x,y]

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
var menu: StartMenu
var _args := {}
var _ng := {"size": "m", "diff": 1, "seed": 0}
var _loading: Control
var _checks: PanelContainer
var _ui: CanvasLayer


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	map = MapView.new()
	add_child(map)
	map.world_ready.connect(_on_world)
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	# the glass panels blur what is under them: copy the screen (map and overlays) before the interface
	var bb := BackBufferCopy.new()
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_ui.add_child(bb)
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
	_ui.add_child(hud)
	win = WindowPanel.new()
	win.visible = false
	win.theme = Ui.theme()
	win.close_requested.connect(func(): _toggle_window(hud.open_window))
	_ui.add_child(win)
	toasts = Toasts.new()
	_ui.add_child(toasts)
	modals = ModalLayer.new()
	modals.theme = Ui.theme()
	modals.opened.connect(func(): if session != null: session.hold = true)
	modals.closed.connect(func(): if session != null: session.hold = false)
	_ui.add_child(modals)
	_loading = _build_loading()
	_ui.add_child(_loading)
	_checks = PanelContainer.new()
	_checks.position = Vector2(80, 80)
	_checks.visible = false
	_ui.add_child(_checks)
	if not ClassDB.class_exists("TRWorldGen"):
		modals.push({"icon": "alert", "tone": "bad", "eyebrow": "Помилка", "title": "Нативний модуль не завантажився",
			"body": "Бібліотека [b]godot/bin/libtriroute[/b] не знайдена або не підходить до цієї системи. Натисни F9, щоб побачити перевірки.", "choices": []})
		return
	_ng.seed = int(_args.get("seed", str(randi() % 1000000000)))
	if _args.has("company") or _args.has("pick") or (_args.has("shot") and not _args.has("menu")):
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
		menu.quit.connect(func(): get_tree().quit())
		_ui.add_child(menu)
		_ui.move_child(menu, 0)
	menu.visible = true
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
	var c := Ui.vbox(12)
	var wfx_on: bool = float(Settings.get_value("wfx")) > 0
	c.add_child(Ui.hbox(12, [Ui.note("Відблиски й хвилі на воді"), Ui.spacer(), Ui.seg([[true, "Увімкнено"], [false, "Вимкнено"]], wfx_on, func(v): Settings.set_value("wfx", 1.0 if v else 0.0))]))
	c.add_child(Ui.btn("Перевірки (F9)", "", "check", func():
		modals.clear()
		_toggle_checks()))
	modals.push({"icon": "gear", "eyebrow": "Гра", "title": "Налаштування", "content": c, "close": true})


func _game_menu() -> void:
	modals.push({"icon": "shield", "eyebrow": "Пауза", "title": "Меню гри", "close": true, "choices": [
		{"t": "Продовжити", "d": "Повернутися до гри", "f": func(): pass},
		{"t": "Налаштування", "d": "Вода, перевірки", "f": _settings},
		{"t": "Головне меню", "d": "Поточна гра не зберігається (збереження — у наступних частинах переносу)", "f": func():
			if session != null:
				session.queue_free()
				session = null
			_show_menu()},
		{"t": "Вихід", "d": "Закрити гру", "f": func(): get_tree().quit()}]})


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
	map.generate(_ng.seed, _args.get("size", _ng.size))


func _process(delta: float) -> void:
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
	if _args.has("wfx"):
		Settings.set_value("wfx", float(_args.wfx))
	if session != null:
		session.queue_free()
	session = GameSession.new()
	add_child(session)
	session.begin(map.generator(), GameState.world_seed, w.states, w.board, w, _ng.diff)
	hud.session = session
	if _args.has("company"):
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
		if _args.has("place"):
			map_ui.show_place(int(_args.place))
		if _args.has("country"):
			map_ui.show_country(int(_args.country))
		if _args.has("win"):
			_toggle_window(_args.win)
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
	if _args.has("shot"):
		for i in 12:
			await get_tree().process_frame
		if _args.has("mouse"):   # test: the hover card at a point of the screen
			var c: PackedStringArray = String(_args.mouse).split(",")
			get_viewport().warp_mouse(Vector2(float(c[0]), float(c[1])))
			for i in 4:
				await get_tree().process_frame
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


func _play(hq: int, auto_decisions: bool) -> void:
	session.choose_hq(hq, auto_decisions)
	session.set_speed(0)
	map.attach_session(session)
	wins = Windows.new(session.sim)
	wins.acted.connect(_on_act)
	wins.goto_place.connect(_goto_place)
	wins.select_job.connect(func(j): map_ui.select_job(j, true))
	map_ui.attach(session, map)
	map_ui.visible = true
	hud.visible = true
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
	_win_day = sim.day
	var id := hud.open_window
	var h: Array = WIN_HEAD.get(id, ["info", id])
	win.set_head(h[0], "%s · %s" % [sim.CO.name, Ui.date_str(sim.date)], h[1])
	var keep := win.scroll.scroll_vertical
	win.clear_body()
	if id == "news":
		for i in range(sim.news.size() - 1, maxi(-1, sim.news.size() - 60), -1):
			var n: Array = sim.news[i]
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(7, 7)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.color = {"good": Ui.GOOD, "bad": Ui.BAD, "warn": Ui.WARN}.get(n[0], Ui.ACCENT)
			var t := Ui.note(n[2])
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			win.body.add_child(Ui.hbox(10, [dot, t]))
		if sim.news.is_empty():
			win.body.add_child(Ui.note("Поки що новин немає.", Ui.MUTED))
	else:
		wins.build(id, win.body)
	# the same place in the window after a rebuild
	if not force:
		_restore_scroll(keep)


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


func _goto_place(pid: int) -> void:
	map_ui.fly(pid)


# ---------- checks ----------
func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match e.keycode:
		KEY_F9:
			_toggle_checks()
		KEY_SPACE:
			if session != null and session.sim != null and hud.visible:
				session.set_speed(0 if session.speed else 1)
		KEY_1, KEY_2, KEY_3:
			if session != null and session.sim != null and hud.visible:
				session.set_speed(e.keycode - KEY_0)
		KEY_ESCAPE:
			if win.visible:
				_toggle_window("")


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
