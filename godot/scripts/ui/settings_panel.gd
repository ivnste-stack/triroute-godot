class_name SettingsPanel
extends VBoxContainer
## The settings (the «Налаштування» view of the pause menu, 08d-settings.js), in four sections: graphics,
## interface, sound and game. Every row is a title with a note on the left and its control on the right;
## a change is saved and applied at once.

const TABS := [["gfx", "Графіка", "eye"], ["ui", "Інтерфейс", "layers"], ["snd", "Звук", "mega"], ["keys", "Керування", "target"], ["game", "Гра", "gear"]]
const RES_OPTS := [[0, "Як вікно"], [1280, "HD · 1280×720"], [1600, "HD+ · 1600×900"], [1920, "Full HD · 1920×1080"],
	[2560, "2K · 2560×1440"], [3840, "4K · 3840×2160"]]

const WIN_SIZES := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]

static var tab := "gfx"

var host: Node              # main: apply_window, apply_video, apply_ui_scale, render_size, set_blur_mode, checks
var _tabs: Array = []
var _page: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	custom_minimum_size.x = 680
	var row := Ui.hbox(0)
	for t in TABS:
		var b := _tab_btn(t)
		row.add_child(b)
		_tabs.append(b)
	var line := ColorRect.new()
	line.color = Ui.LINE
	line.custom_minimum_size.y = 1
	add_child(Ui.vbox(0, [row, line]))
	_page = Ui.vbox(4)
	_page.custom_minimum_size.y = 500   # the dialog keeps its height between the sections
	add_child(_page)
	_show(tab)


## a section tab: the icon and the name, the open one with an accent underline
func _tab_btn(t: Array) -> Button:
	var b := Button.new()
	b.set_meta("silent", true)   # moving between the sections makes no sound
	b.text = t[1]
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_override("font", Ui.font("body", 600))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_constant_override("h_separation", 8)
	b.add_theme_constant_override("icon_max_width", 16)
	b.set_meta("id", t[0])
	b.set_meta("ic", t[2])
	b.pressed.connect(func(): _show(t[0]))
	return b


func _paint_tabs() -> void:
	for b in _tabs:
		var on: bool = b.get_meta("id") == tab
		var st := Ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector4(16, 0, 16, 0))
		st.border_color = Ui.ACCENT
		st.border_width_bottom = 2 if on else 0
		var hv: StyleBoxFlat = st.duplicate()
		hv.bg_color = Ui.ACCENT_SOFT
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var col := Ui.FG if on else Ui.FG2
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, Ui.FG if k != "font_color" else col)
		b.icon = Icons.tex(b.get_meta("ic"), Ui.ACCENT if on else Ui.FG2, 16)


func _show(id: String) -> void:
	tab = id
	_wait = ""
	_paint_tabs()
	for c in _page.get_children():
		c.queue_free()
	match id:
		"gfx": _gfx()
		"ui": _ui()
		"snd": _snd()
		"keys": _keys()
		"game": _game()


func _refresh() -> void:
	_show.call_deferred(tab)


# ---------- rows ----------
## a setting: the title and the note on the left, the control on the right; a line under it
func _row(title: String, note: String, ctl: Control) -> void:
	var l := Ui.vbox(3, [Ui.label(title, 14, Ui.FG, Ui.font("body", 500))])
	if note != "":
		var n := Ui.note(note, Ui.MUTED)
		n.add_theme_font_size_override("font_size", 12)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_child(n)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 280
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var p := PanelContainer.new()
	var st := Ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector4(2, 10, 2, 10))
	st.border_color = Ui.LINE
	st.border_width_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.add_child(Ui.hbox(18, [l, ctl]))
	_page.add_child(p)


func _head(text: String) -> void:
	var l := Ui.lbl(text)
	_page.add_child(Ui.margin(l, 2, 14, 2, 2))


func _put(key: String, v: Variant, apply: Callable = Callable(), refresh := false) -> void:
	Settings.set_value(key, v)
	if apply.is_valid():
		apply.call()
	if refresh:
		_refresh()


func _seg(key: String, opts: Array, apply: Callable = Callable(), refresh := false) -> Control:
	return Ui.seg(opts, Settings.get_value(key), func(v): _put(key, v, apply, refresh))


func _dd(key: String, opts: Array, ic: String, apply: Callable = Callable(), refresh := false) -> Dropdown:
	var o := []
	for x in opts:
		o.append([x[0], x[1], ic])
	var d := Dropdown.make(o, Settings.get_value(key), func(v): _put(key, v, apply, refresh))
	d.custom_minimum_size.x = 230
	return d


func _toggle(key: String, inverted := false, apply: Callable = Callable()) -> Control:
	var on: bool = bool(Settings.get_value(key)) != inverted
	return Ui.seg([[true, "Увімкнено"], [false, "Вимкнено"]], on, func(v): _put(key, v != inverted, apply))


## .rng: a slider 0…100 % with the value beside it
func _slider(key: String, apply: Callable = Callable()) -> Control:
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.value = roundf(float(Settings.get_value(key)) * 100)
	s.custom_minimum_size = Vector2(200, 22)
	s.focus_mode = Control.FOCUS_NONE
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var track := Ui.box(Color(1, 1, 1, .1))
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := Ui.box(Ui.ACCENT)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob(Ui.FG)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", _knob(Ui.ACCENT))
	var v := Ui.num("%d%%" % int(s.value), 13, Ui.FG2)
	v.custom_minimum_size.x = 44
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x):
		v.text = "%d%%" % int(x)
		Settings.set_value(key, x / 100.0)
		if apply.is_valid():
			apply.call())
	return Ui.hbox(10, [s, v])


static var _knobs := {}


static func _knob(col: Color) -> Texture2D:
	var k := col.to_html()
	if _knobs.has(k):
		return _knobs[k]
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	for y in 28:
		for x in 28:
			var d := Vector2(x + .5 - 14, y + .5 - 14).length()
			var a := clampf(13.0 - d, 0, 1)
			var c := col if d < 10.5 else Color(.04, .07, .1)
			img.set_pixel(x, y, Color(c, a))
	img.resize(14, 14, Image.INTERPOLATE_LANCZOS)
	_knobs[k] = ImageTexture.create_from_image(img)
	return _knobs[k]


# ---------- sections ----------
func _gfx() -> void:
	_head("Екран")
	_row("Режим вікна", "«На весь екран» — без рамки, швидко перемикається між програмами. «Ексклюзивний» — найменша затримка, але Alt+Tab повільніший.",
		_dd("window", [["max", "Розгорнуте вікно"], ["window", "Вікно"], ["borderless", "На весь екран"], ["exclusive", "Ексклюзивний повноекранний"]], "layers", host.apply_window, true))
	var scr := DisplayServer.screen_get_size(get_window().current_screen) if get_window() != null else Vector2i(3840, 2160)
	var sizes := []
	for s in WIN_SIZES:
		var p: PackedStringArray = s.split("x")
		if int(p[0]) <= scr.x and int(p[1]) <= scr.y:
			sizes.append([s, s.replace("x", "×") + {"1920x1080": " · Full HD", "2560x1440": " · 2K", "3840x2160": " · 4K", "1280x720": " · HD"}.get(s, "")])
	if sizes.is_empty():
		sizes.append(["1280x720", "1280×720 · HD"])
	var wd := _dd("win_size", sizes, "layers", host.apply_window)
	wd.disabled = Settings.get_value("window") != "window"
	if wd.disabled:
		wd.modulate.a = .4
		wd.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_row("Розмір вікна", "Для режиму «Вікно». Розміри, більші за екран (%d×%d), не показано." % [scr.x, scr.y], wd)
	_row("Вертикальна синхронізація", "Кадри йдуть у такт з монітором: без розривів зображення і з найменшим навантаженням.", _toggle("vsync", false, host.apply_video))
	_row("Обмеження кадрів", "Найбільша частота кадрів. Для 2D-мапи 60–144 більш ніж досить.",
		_seg("fps", [[30, "30"], [60, "60"], [120, "120"], [144, "144"], [240, "240"], [0, "Без меж"]], host.apply_video))
	_row("Економія на паузі", "На паузі без дій гра сама знижує частоту до 30 кадрів, у фоні — до 15.", _toggle("idle_fps"))
	_head("Мапа")
	var rs: Vector2i = host.render_size()
	_row("Роздільна здатність рендеру мапи", "Зараз мапа рендериться у %d×%d пікселів. 2K і 4K — максимальна чіткість кордонів і тексту на великих екранах, але більше навантаження на відеокарту." % [rs.x, rs.y],
		_dd("res", RES_OPTS, "mapIc", host.apply_video, true))
	_row("Масштабування", "Як розтягувати мапу, коли вона рендериться менше за вікно. FSR 1.0 — чіткіше за звичайне.",
		_seg("upscale", [["bilinear", "Звичайне"], ["fsr", "FSR 1.0"]], host.apply_video))
	var aa: String = host._aa_mode()
	if aa != Settings.get_value("aa"):
		Settings.set_value("aa", aa)
	_row("Згладжування", "Прибирає «драбинки» на берегах, кордонах і трикутниках води. SSAA рендерить мапу більшою і стискає — найчистіше, але важче для відеокарти (4× — удвічі більше пікселів по кожній стороні). FXAA — легке розмиття країв.",
		_dd("aa", [["off", "Вимкнено"], ["fxaa", "FXAA"], ["ssaa2", "SSAA 2×"], ["ssaa4", "SSAA 4×"], ["fxaa_ssaa", "FXAA + SSAA 2×"]], "spark", host.apply_video, true))
	_row("Анізотропна фільтрація", "Чіткість рельєфу мапи під кутом, коли камера нахилена.",
		_seg("aniso", [[0, "Вимк"], [1, "2×"], [2, "4×"], [3, "8×"], [4, "16×"]], host.apply_video))
	_row("Відблиски на воді", "Час від часу окремі трикутники води повільно світлішають або темнішають і так само повільно повертаються.",
		_toggle("glint", false, host.apply_video))
	_row("Розмиття під панелями", "Скляні панелі розмивають мапу під собою. Без розмиття вони просто напівпрозорі — легше для слабкої відеокарти.",
		_toggle("blur", false, host.apply_blur))
	var f3 := Ui.note("F3 — панель продуктивності: кадри, час CPU і GPU, відеокарта.", Ui.MUTED)
	f3.add_theme_font_size_override("font_size", 12)
	_page.add_child(Ui.margin(f3, 2, 10, 2, 0))


func _ui() -> void:
	_row("Масштаб інтерфейсу", "«Авто» — як масштаб у налаштуваннях екрана Windows.",
		_seg("ui_scale", [[0.0, "Авто"], [1.0, "100%"], [1.25, "125%"], [1.5, "150%"], [1.75, "175%"], [2.0, "200%"]], host.apply_ui_scale))
	_row("Підказки", "Картки з поясненням при наведенні на елементи інтерфейсу.", _toggle("no_tips", true))
	_row("Стрічка новин", "Остання новина, що біжить у нижній панелі.", _toggle("no_ticker", true))


func _snd() -> void:
	_row("Загальна гучність", "Уся гра. 0% — тиша.", _slider("master_vol"))
	_row("Гучність музики", "Для музики в меню і в грі.", _slider("mus_vol"))
	_row("Звуки інтерфейсу", "Кнопки, вікна, відправлення й доставка рейсів, інциденти, новий грейд.", _slider("sfx_vol", func(): Sfx.play("coin")))
	_row("Музика в меню", "Трек головного меню й екрана генерації світу.", _toggle("no_music", true))
	_row("Музика в грі", "Добірка треків, кожен раз за коло, у випадковому порядку.", _toggle("no_game_music", true))
	_row("Що грає в грі", "«Спокійний фон» — тиха мелодія без ударних по колу. «Фокус» — три бадьоріші мелодії з м'якою пульсацією для зосередження. «Добірка» — треки у випадковому порядку. «Разом» — усе це впереміш.",
		_seg("game_music", [["ambient", "Спокійний фон"], ["focus", "Фокус"], ["tracks", "Добірка"], ["mix", "Разом"]]))


func _game() -> void:
	_row("Автозбереження", "Кожні 15 хвилин гри в окремий слот — він перший у списку «Завантажити гру».", _toggle("autosave"))
	_row("Перевірки", "Самоперевірка симуляції і рендеру (F9).", Ui.btn("Відкрити", "sm", "check", func(): host.open_checks()))
	_head("Продуктивність")
	var rec: PerfRecorder = host.perf_rec
	var rb := Ui.btn("Зупинити й зберегти" if rec.recording else "Почати запис", "sm" if rec.recording else "pri sm", "chart", func():
		rec.toggle()
		_refresh())
	var ob := Ui.btn("Папка", "sm", "doc", func():
		DirAccess.make_dir_recursive_absolute("user://perf")
		OS.shell_open(ProjectSettings.globalize_path("user://perf")))
	_row("Запис продуктивності (F4)", "Пише звіт про те, що навантажує гру: частота й час кадрів, рендер, пам'ять, стан гри щосекунди, усі повільні кадри з розкладом по частинах коду, підсумок у кінці. Пограйте як зазвичай, зупиніть запис і надішліть файл з папки." + (" Зараз пишеться: " + ProjectSettings.globalize_path(rec.path) if rec.recording else ""), Ui.hbox(6, [rb, ob]))
	_head("Тестування")
	var on: bool = host.in_game() and host.session.sim.CO.get("sandbox", false)
	var b := Ui.btn("Увімкнено" if on else "Увімкнути", "sm" if on else "pri sm", "bolt", func():
		host.sandbox()
		_refresh())
	b.disabled = on or not host.in_game()
	_row("Тестовий режим", "Гроші без ліміту, найвищі грейд, ліцензія й рейтинг, усі дозволи, модернізації й менеджери, хаби в портовому, аеропортовому й залізничному місті, по 100 одиниць кожної техніки з екіпажами. Лише для поточної гри; зберігається разом із нею." if host.in_game() else "Доступно під час гри: відкрийте налаштування з меню гри (Esc).", b)


# ---------- controls (08k-keys.js) ----------
var _wait := ""      # the action waiting for its new key
var _key_note: Label


func _keys() -> void:
	_key_note = Ui.note("Клік по клавіші, потім натисніть нову. Backspace — зняти призначення, Esc — скасувати.", Ui.MUTED)
	_key_note.add_theme_font_size_override("font_size", 12)
	_key_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_key_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_child(Ui.margin(Ui.hbox(12, [_key_note, Ui.btn("Скинути", "sm", "refresh", func():
		Keys.reset()
		_refresh())]), 2, 6, 2, 0))
	for g in Keys.DEF:
		_head(g[0])
		for a in g[1]:
			_page.add_child(_key_row(a[0], a[1]))
	_head("Постійні клавіші")
	for f in Keys.FIXED:
		var pill := Ui.pill(f[1])
		_page.add_child(_line(Ui.label(f[0], 13, Ui.FG2), pill))


func _line(l: Control, r: Control) -> PanelContainer:
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var p := PanelContainer.new()
	var st := Ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector4(2, 5, 2, 5))
	st.border_color = Ui.LINE
	st.border_width_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.add_child(Ui.hbox(12, [l, r]))
	return p


func _key_row(id: String, n: String) -> Control:
	var waiting := _wait == id
	var k := Keys.key(id)
	var b := Ui.btn("Натисніть клавішу…" if waiting else Keys.name_of(k), "pri sm" if waiting else "sm", "", func():
		_wait = "" if _wait == id else id
		_refresh())
	b.custom_minimum_size.x = 150
	if k != Keys.default_key(id) and not waiting:
		b.tooltip_text = "Типово: " + Keys.name_of(Keys.default_key(id))
	return _line(Ui.label(n, 13, Ui.FG), b)


func _input(e: InputEvent) -> void:
	if _wait == "" or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	get_viewport().set_input_as_handled()
	var k := int(e.physical_keycode) if e.physical_keycode != KEY_NONE else int(e.keycode)
	var id := _wait
	_wait = ""
	if k == KEY_ESCAPE:
		_refresh()
		return
	if k == KEY_BACKSPACE or k == KEY_DELETE:
		Keys.set_key(id, 0)
		_refresh()
		return
	if k in Keys.BUSY or e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
		_refresh()
		_busy_note.call_deferred(Keys.name_of(k))
		return
	Keys.set_key(id, k)
	_refresh()


func _busy_note(k: String) -> void:
	if _key_note != null and is_instance_valid(_key_note):
		_key_note.text = "Клавіша %s зайнята: вона керує камерою, меню або панелями. Оберіть іншу." % k
		_key_note.add_theme_color_override("font_color", Ui.WARN)
