class_name TrailerStudio
extends CanvasLayer
## «Студія трейлера» (the ` key, left of 1 — not F8: the Godot editor stops the running game on it): the player
## films the game. The panel on the right, on its own layer, never in the picture of a take.
## · Camera: slower, softer keys (W A S D, Q / E, Z / X zoom); «Запис» keeps the camera's way frame by frame and
##   every button pressed meanwhile (with its second and place); «Програти» plays it back, smoothed;
##   «До стандартного виду» turns the camera north up and draws it back a little, slowly.
## · Scene: trips all over the map (by kind of transport), which vehicles show, road closures and accidents, a
##   war, a closed border, bandits, a hurricane, pirates — where the camera looks.
## · Counters: the cash, the rating, the deliveries, the licences in the top bar count up or down to a number.
## · Take: «Зняти дубль» hides the panel (and as much of the interface as asked) and plays the way and the
##   buttons again — for a screen recorder; «Команда рендеру» copies a command that records the take by Godot's
##   Movie Maker at a steady 60 fps from the snapshot saved when the way was recorded (--load=… --take=…).
## · Subtitles: a line of text in the game's font, its colour and size, moving across the screen; the list is
##   copied as code (JSON) for tools/subtitles.py, which draws it over recorded frames the same way.
## Takes live in user://trailer/<name>.json; their snapshots in the save slot trailer_<name>.

const W = preload("res://scripts/ui/windows.gd")
const KEY := KEY_QUOTELEFT   # by its place: ` on the English layout, ' on the Ukrainian
const DIR := "user://trailer"
const KINDS := [["road", "Авто", "truck"], ["rail", "Залізниця", "train"], ["sea", "Море", "ship"], ["air", "Авіа", "plane"]]
const ANIMS := [["fade", "Поява", "Плавно проявляється й зникає"], ["up", "Знизу", "Виїжджає знизу вгору"],
	["side", "Збоку", "Виїжджає збоку (з того боку, звідки рух)"], ["pop", "Збільшення", "З’являється, трохи збільшуючись"],
	["wipe", "Шторка", "Відкривається зліва направо"], ["type", "Друк", "Літери з’являються одна за одною"]]
const WARM := 30   # frames before a rendered take starts: the map and the trips settle

var main: Node
var panel: PanelContainer
var _body: VBoxContainer
var _status: Label
var _sub_layer: CanvasLayer   # the subtitles' preview, over everything

var opts := {"spd": .45, "glide": .93, "smooth": .5, "ui": "top", "dens": 2, "ret": 5.0, "ret_d": 14.0, "hub_spd": 8.0, "snap": true, "reset_take": true,
	"kinds": {"road": true, "rail": true, "sea": true, "air": true}}
var take_name := "take1"

# the way being recorded or played: [t, x, z, dist, yaw] every frame; the buttons: [t, kind, args]
var rec := false
var _rec_t := 0.0
var path: Array = []
var acts: Array = []
var playing := false
var _play_t := 0.0
var _play_path: Array = []
var _play_acts: Array = []
var _fired := {}
var _take := ""               # "" | "live" | "render"
var _ui_hidden: Array = []    # [CanvasItem, was visible, its alpha]
var _ret := {}                # the glide back to the standard view
var _cnt := {}                # counter → {from, to, t, dur}
var _warm := 0
var _render_take := {}

# subtitles: the list and the one being edited
var subs: Array = []
var sub := {"title": "Будуйте логістичну імперію", "text": "Вантажівки, потяги, кораблі й літаки по всьому світу", "t0": 0.0, "dur": 5.0,
	"color": "#ffffff", "size": 44, "font": "display", "x": .5, "box": true, "drift": 1, "align": "left",
	"y": .8}


func _init(main_: Node) -> void:
	main = main_
	layer = 120


func _ready() -> void:
	panel = Ui.glass()
	panel.theme = Ui.theme()
	panel.anchor_left = 1
	panel.anchor_right = 1
	panel.anchor_bottom = 1
	panel.offset_left = -404
	panel.offset_right = -14
	panel.offset_top = 70
	panel.offset_bottom = -14
	add_child(panel)
	var sc := SmoothScroll.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	_body = Ui.vbox(6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := Ui.margin(_body, 14)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	_sub_layer = CanvasLayer.new()
	_sub_layer.layer = 125
	add_child(_sub_layer)
	_build()
	_cam_opts(true)
	_snap0 = _snapshot()   # «Скинути все» brings the world back to this


func sim() -> Sim:
	return main.session.sim if main.session != null else null


func cam() -> MapCamera:
	return main.map.camera


## the studio's camera: slower keys, a softer glide, Z / X zoom (on) — the game's own (off)
func _cam_opts(on: bool) -> void:
	var c := cam()
	c.key_k = opts.spd if on else 1.0
	c.glide = opts.glide if on else .85
	c.zoom_keys = on


func open_panel(on: bool) -> void:
	panel.visible = on
	_cam_opts(on or playing)


func close_studio() -> void:
	_cam_opts(false)
	if main.hud != null:
		main.hud.studio = {}
	queue_free()


# ====================================================================== the panel
func _build() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var B := _body
	B.add_child(_row(Ui.hbox(8, [Ui.icon("video" if Icons.has("video") else "eye", 18, Ui.ACCENT), W._b("Студія трейлера", 15)]), MapUi._xbtn(close_studio)))
	B.add_child(W._note("` (ліворуч від 1) — сховати / показати панель. Панель не потрапляє в кадр дубля.", Ui.MUTED, 12))
	_status = Ui.label("", 12, Ui.ACCENT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	B.add_child(_status)
	_show_status()

	# ---- the camera
	B.add_child(W._sect("Камера"))
	B.add_child(W._note("W A S D — рух · Q / E — поворот · Z / X — наближення · колесо миші", Ui.FG2, 12))
	B.add_child(_slider("Швидкість клавіш", opts.spd, .1, 1.0, func(v):
		opts.spd = v
		_cam_opts(true)))
	B.add_child(_slider("Плавність руху", opts.glide, .85, .98, func(v):
		opts.glide = v
		_cam_opts(true)))
	B.add_child(_slider("Згладжування дубля", opts.smooth, 0.0, 1.5, func(v): opts.smooth = v, "с"))
	var name_e := LineEdit.new()
	name_e.text = take_name
	name_e.placeholder_text = "назва дубля"
	name_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_e.text_changed.connect(func(t): take_name = t.strip_edges().replace(" ", "_"))
	B.add_child(Ui.hbox(8, [Ui.lbl("Дубль"), name_e]))
	var rb := W._btn("■ Зупинити запис" if rec else "● Запис", "pri sm" if not rec else "sm", "", toggle_rec)
	var pb := W._btn("▶ Програти", "sm", "", func(): play(false), path.size() > 1 and not rec)
	B.add_child(_fill([rb, pb]))
	B.add_child(_fill([W._btn("До стандартного виду", "sm", "refresh", return_view, true,
		"Плавно й повільно повертає камеру на північ і наближає чи віддаляє до обраного зуму. Під час запису теж записується."),
		_slider_small(opts.ret, 2.0, 12.0, func(v): opts.ret = v, "с")]))
	var mx: float = cam().world_size.x * 1.2
	B.add_child(Ui.hbox(8, [_slider("Зум повернення", opts.ret_d, cam().min_dist, mx, func(v): opts.ret_d = v, "", 1),
		W._btn("Поточний", "sm", "", func():
			opts.ret_d = cam().dist
			_build(), true, "Узяти зум, який зараз")]))
	B.add_child(_fill([W._btn("Зберегти", "sm", "doc", save_take, path.size() > 1), W._btn("Відкрити", "sm", "folder" if Icons.has("folder") else "doc", func(): load_take(take_name))]))
	var tk := _takes()
	if tk.size():
		B.add_child(W._note("Збережені: %s" % ", ".join(PackedStringArray(tk)), Ui.MUTED, 12))
	B.add_child(Ui.hbox(8, [W._toggle(opts.snap, func():
		opts.snap = not opts.snap
		_build()), _wrap("Знімок світу на початку запису (для рендеру)")]))

	# ---- the take
	B.add_child(W._sect("Дубль"))
	B.add_child(Ui.seg([["all", "Увесь інтерфейс"], ["top", "Лише верхня панель"], ["none", "Без інтерфейсу"]], opts.ui, func(x):
		opts.ui = x
		_build()))
	B.add_child(_fill([W._btn("▶ Зняти дубль", "pri sm", "", func(): play(true), path.size() > 1 and not rec,
		"Ховає панель (і інтерфейс, як обрано вище) та програє шлях камери й усі натиснуті під час запису кнопки. Записуйте екран у цей час. ` — зупинити."),
		W._btn("Команда рендеру", "sm", "doc", copy_render, path.size() > 1,
		"Копіює команду: Godot сам запише дубль у відео 1920×1080, рівно 60 кадрів/с, зі знімка світу на початку запису.")]))
	B.add_child(Ui.hbox(8, [W._toggle(opts.reset_take, func():
		opts.reset_take = not opts.reset_take
		_build()), _wrap("Перед дублем повертати світ, яким він був на початку запису")]))

	# ---- the scene
	B.add_child(W._sect("Сцена"))
	B.add_child(_fill([W._btn("Скинути все", "sm", "refresh", reset_all, true,
		"Повертає світ, яким він був, коли відкрили студію (або з «Новий початок»): хаби, рейси, події, гроші, лічильники, видимість транспорту — усі дії сцени скасовано"),
		W._btn("Новий початок", "sm", "", func():
			_snap0 = _snapshot()
			main.toasts.push("good", "Новий початок", "«Скинути все» повертатиме світ до цього стану"), true,
		"Запам'ятати світ, як він зараз, як той, до якого повертає «Скинути все»")]))
	var kr := HFlowContainer.new()
	kr.add_theme_constant_override("h_separation", 6)
	kr.add_theme_constant_override("v_separation", 6)
	for K in KINDS:
		var k_: String = K[0]
		var on: bool = opts.kinds[k_]
		var b := W._btn(K[1], "pri sm" if on else "sm", K[2], func():
			opts.kinds[k_] = not opts.kinds[k_]
			act("kinds", {"kinds": opts.kinds.duplicate()})
			_build())
		b.tooltip_text = "Показувати й створювати рейси: %s" % K[1]
		kr.add_child(b)
	B.add_child(kr)
	B.add_child(Ui.hbox(8, [Ui.label("Рейсів з кожного міста", 12, Ui.FG2), Ui.seg([[1, "×1"], [2, "×2"], [3, "×3"], [4, "×4"], [8, "×8"], [16, "×16"]], opts.dens, func(x):
		opts.dens = x
		_build())]))
	B.add_child(_fill([W._btn("Рейси по всьому світу", "pri sm", "road", func(): act("trips", {"dens": opts.dens, "kinds": opts.kinds.duplicate(), "seed": randi()}), true,
		"Рівномірно по всьому світу: з кожного міста стільки рейсів обраними видами транспорту до сусідніх міст, уже в дорозі. Гроші компанії не змінюються."),
		W._btn("Прибрати рейси", "sm", "close", func(): act("clear_trips", {}), true, "Прибирає з мапи всі рейси")]))
	B.add_child(_slider("Хабів за секунду", opts.hub_spd, 1.0, 40.0, func(v): opts.hub_spd = v, "", 0))
	B.add_child(W._btn("Відкрити всі хаби", "sm", "building", func():
		var h := _here()
		h.spd = opts.hub_spd
		act("hubs", h), true, "Міста одне за одним стають хабами компанії (помаранчеві квадрати), хвилею від місця, куди дивиться камера"))
	B.add_child(W._note("Події — там, куди дивиться камера:", Ui.FG2, 12))
	var ev := GridContainer.new()
	ev.columns = 2
	ev.add_theme_constant_override("h_separation", 6)
	ev.add_theme_constant_override("v_separation", 6)
	for e in [["jam", "Затори й ремонти", "alert"], ["acc", "Аварії на дорогах", "alert"], ["war", "Війна", "skull" if Icons.has("skull") else "alert"],
			["border", "Закрити кордон", "close"], ["band", "Бандити", "skull" if Icons.has("skull") else "alert"], ["storm", "Ураган", "alert"],
			["pir", "Пірати", "ship"], ["clear", "Прибрати події", "close"]]:
		var k_: String = e[0]
		var b := W._btn(e[1], "sm", e[2], func(): act(k_, _here()))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ev.add_child(b)
	B.add_child(ev)

	# ---- the counters
	B.add_child(W._sect("Лічильники у верхній панелі"))
	var CO: Dictionary = sim().CO
	for c in [["cash", "Гроші", CO.cash], ["rating", "Рейтинг", CO.rating], ["del", "Доставлено", float(CO.get("cdel", 0))], ["lic", "Ліцензії", float(CO.tier)]]:
		B.add_child(_counter_row(c[0], c[1], c[2]))
	B.add_child(W._btn("Показувати справжні числа", "sm", "close", func(): act("cnt_reset", {})))

	# ---- the subtitles
	B.add_child(W._sect("Субтитри"))
	B.add_child(_sub_editor())


## a note beside a switch: as wide as there is room, wrapped
func _wrap(t: String) -> Label:
	var l := Ui.label(t, 12, Ui.FG2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 200
	return l


func _row(a: Control, b: Control) -> HBoxContainer:
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return Ui.hbox(8, [a, b])


func _fill(cs: Array) -> HBoxContainer:
	for c in cs:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return Ui.hbox(8, cs)


func _slider(label: String, v: float, a: float, b: float, cb: Callable, unit: String = "", dec: int = 2) -> Control:
	var s := HSlider.new()
	s.min_value = a
	s.max_value = b
	s.step = (b - a) / 100.0 if dec > 0 else 1.0
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Ui.label(("%." + str(dec) + "f%s") % [v, unit], 12, Ui.FG2, Ui.font("mono", 500))
	val.custom_minimum_size.x = 52
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x):
		val.text = ("%." + str(dec) + "f%s") % [x, unit]
		cb.call(x))
	var l := Ui.label(label, 12, Ui.FG2)
	l.custom_minimum_size.x = 130
	return Ui.hbox(8, [l, s, val])


func _slider_small(v: float, a: float, b: float, cb: Callable, unit: String) -> Control:
	var s := HSlider.new()
	s.min_value = a
	s.max_value = b
	s.step = .5
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Ui.label("%.1f %s" % [v, unit], 12, Ui.FG2, Ui.font("mono", 500))
	s.value_changed.connect(func(x):
		val.text = "%.1f %s" % [x, unit]
		cb.call(x))
	s.tooltip_text = "Скільки триває повернення"
	return Ui.hbox(6, [s, val])


func _num_edit(v: float, w: float = 96) -> LineEdit:
	var e := LineEdit.new()
	e.text = str(v) if absf(v - roundf(v)) > 1e-6 else str(int(v))
	e.custom_minimum_size.x = w
	return e


## a counter: to which number, in how many seconds, ▶
func _counter_row(key: String, name: String, cur: float) -> Control:
	var to := _num_edit(cur)
	var dur := _num_edit(3.0, 52)
	var l := Ui.label(name, 12, Ui.FG2)
	l.custom_minimum_size.x = 84
	var go := W._btn("▶", "sm", "", func(): act("cnt", {"k": key, "to": to.text.to_float(), "dur": maxf(.1, dur.text.to_float())}))
	go.tooltip_text = "Плавно змінити число в панелі (вниз теж: наприклад, гроші в мінус)"
	return Ui.hbox(6, [l, to, Ui.label("за", 12, Ui.MUTED), dur, Ui.label("с", 12, Ui.MUTED), go])


func _status_set(t: String) -> void:
	if _status != null:
		_status.text = t


func _show_status() -> void:
	if rec:
		_status_set("● Запис: %.1f с · кнопок %d" % [_rec_t, acts.size()])
	elif playing:
		_status_set("▶ %.1f / %.1f с" % [_play_t, _play_path.back()[0] if _play_path.size() else 0.0])
	elif path.size() > 1:
		_status_set("Шлях «%s»: %.1f с · кнопок %d" % [take_name, path.back()[0], acts.size()])
	else:
		_status_set("Шляху ще немає: «● Запис», рухайте камеру, тисніть кнопки сцени, «■ Зупинити».")


# ====================================================================== recording and playing
func toggle_rec() -> void:
	if rec:
		rec = false
		_show_status()
		_build()
		return
	if opts.snap:   # the world as the way starts: the render replays the take from it
		var sd: Dictionary = main._save_data()
		SaveSystem.write("trailer_" + take_name, sd.data, sd.meta)
	_snap_rec = _snapshot()   # a take starts again from here («Перед дублем повертати світ…»)
	rec = true
	_rec_t = 0.0
	path = []
	acts = []
	_meta = {"speed": main.session.speed, "mode": main.map.mode, "hid": MapVis.hid.duplicate(), "kinds": opts.kinds.duplicate()}
	_build()


var _meta := {}
var _snap0 := {}      # the world when the studio opened (or «Новий початок»)
var _snap_rec := {}   # the world when the way's recording started


## the world as it is: the simulation's whole state, the time of day, what the map shows
func _snapshot() -> Dictionary:
	var S := sim()
	if S == null:
		return {}
	return {"sim": S.save_state(), "acc": main.session.acc, "pfr": main.session.paused_fr, "hid": MapVis.hid.duplicate(), "kinds": opts.kinds.duplicate()}


func _restore(sn: Dictionary) -> void:
	var S := sim()
	if sn.is_empty() or S == null:
		return
	S.load_state(sn.sim)
	main.session.acc = sn.acc
	main.session.paused_fr = sn.pfr
	MapVis.hid = sn.hid.duplicate()
	MapVis.ver += 1
	opts.kinds = sn.kinds.duplicate()
	_cnt = {}
	_hubq = []
	_ret = {}
	main.hud.studio = {}
	main.map.vehicles.selected = null
	main.map_ui.close_card()
	S.inc_changed()
	main.map.apply_vis()
	main.map.company_colors()


## «Скинути все»: every action of the scene undone — the world as it was
func reset_all() -> void:
	if playing:
		_play_t = INF
		_stop_play()
	_restore(_snap0)
	_build()
	main.toasts.push("good", "Усе скинуто", "Світ — як на початку")


## a button of the scene: done now and, while recording, kept with its second
func act(kind: String, a: Dictionary) -> void:
	if rec:
		acts.append([_rec_t, kind, a.duplicate(true)])
	_do(kind, a)
	_show_status()


func play(take: bool) -> void:
	if path.size() < 2:
		return
	_play_path = _smoothed(path, opts.smooth)
	_play_acts = acts.duplicate(true)
	_fired = {}
	_play_t = 0.0
	playing = true
	_cnt = {}
	if take:
		if opts.reset_take and not _snap_rec.is_empty():
			_restore(_snap_rec)
		_take = "live"
		_hide_ui(true)
	_cam_opts(true)


func _stop_play() -> void:
	playing = false
	if _take == "render":
		print("TAKE END %d" % Engine.get_process_frames())
		get_tree().quit()
		return
	if _take == "live":
		_hide_ui(false)
	_take = ""
	_show_status()


## the way smoothed: each sample the weighted mean of its neighbours within w seconds (a gaussian)
static func _smoothed(p: Array, w: float) -> Array:
	if w <= .01 or p.size() < 3:
		return p
	var out := []
	var n := p.size()
	var j0 := 0
	for i in n:
		var t: float = p[i][0]
		while j0 < n and p[j0][0] < t - w:
			j0 += 1
		var s := [0.0, 0.0, 0.0, 0.0]
		var ws := 0.0
		var j := j0
		while j < n and p[j][0] <= t + w:
			var d: float = (p[j][0] - t) / maxf(w * .5, 1e-3)
			var g := exp(-d * d)
			for c in 4:
				s[c] += p[j][c + 1] * g
			ws += g
			j += 1
		out.append([t, s[0] / ws, s[1] / ws, s[2] / ws, s[3] / ws])
	return out


func _sample(t: float) -> Array:
	var P := _play_path
	if t <= P[0][0]:
		return P[0]
	if t >= P.back()[0]:
		return P.back()
	var lo := 0
	var hi := P.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if P[mid][0] <= t:
			lo = mid
		else:
			hi = mid
	var a: Array = P[lo]
	var b: Array = P[hi]
	var f: float = (t - a[0]) / maxf(1e-6, b[0] - a[0])
	return [t, lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f), lerpf(a[4], b[4], f)]


func _put_cam(x: float, z: float, d: float, y: float) -> void:
	var c := cam()
	c.tx = x
	c.ttx = x
	c.tz = z
	c.ttz = z
	c.dist = d
	c.tdist = d
	c.yaw = y
	c.tyaw = y


## «До стандартного виду»: north up (the nearest whole turn), the same point, at the zoom chosen — slowly
func return_view() -> void:
	var c := cam()
	var y0 := c.yaw
	var y1 := roundf(y0 / TAU) * TAU
	_ret = {"t": 0.0, "dur": opts.ret, "from": [c.tx, c.tz, c.dist, y0], "to": [c.tx, c.tz, clampf(opts.ret_d, c.min_dist, c.world_size.x * 1.2), y1]}


func _process(delta: float) -> void:
	if main.session == null or main.session.sim == null:
		return
	if _take == "render" and _warm < WARM:   # the map settles before the rendered take starts
		_warm += 1
		if _warm == WARM:
			print("TAKE START %d" % Engine.get_process_frames())
			play(false)
			_take = "render"
		return
	var dt := delta
	if not _ret.is_empty():
		_ret.t += dt
		var f := clampf(_ret.t / _ret.dur, 0, 1)
		f = f * f * f * (f * (f * 6 - 15) + 10)
		var A: Array = _ret.from
		var Bv: Array = _ret.to
		_put_cam(lerpf(A[0], Bv[0], f), lerpf(A[1], Bv[1], f), lerpf(A[2], Bv[2], f), lerpf(A[3], Bv[3], f))
		if _ret.t >= _ret.dur:
			_ret = {}
	if playing:
		_play_t += dt
		var s := _sample(_play_t)
		_put_cam(s[1], s[2], s[3], s[4])
		for i in _play_acts.size():
			if not _fired.has(i) and _play_t >= _play_acts[i][0]:
				_fired[i] = true
				_do(_play_acts[i][1], _play_acts[i][2])
		if _play_t >= _play_path.back()[0]:
			_stop_play()
	if rec:
		_rec_t += dt
		var c := cam()
		path.append([_rec_t, c.tx, c.tz, c.dist, c.yaw])
	_tick_counters(dt)
	_tick_hubs(dt)
	_tick_sub(dt)
	if rec or playing:
		_show_status()


# ====================================================================== the interface in the take
func _hide_ui(on: bool) -> void:
	if not on:
		for e in _ui_hidden:
			if is_instance_valid(e[0]):
				e[0].visible = e[1]
				e[0].modulate.a = e[2]
		_ui_hidden = []
		panel.visible = _take != "render"
		return
	panel.visible = false
	var mode: String = opts.ui
	if mode == "all":
		return
	var keep: Control = null   # the top bar: the cash, the rating, the deliveries, the licences
	if mode == "top" and main.hud != null:
		var n: Node = main.hud._kpis
		while n != null and n.get_parent() != main.hud:
			n = n.get_parent()
		keep = n
	for c in main._ui.get_children():
		if not (c is CanvasItem):
			continue
		if c == main.hud and mode == "top":
			for h in main.hud.get_children():
				if h is CanvasItem and h != keep:
					_hide(h)
			continue
		_hide(c)


## out of the picture: hidden and transparent (the legend and the compass show themselves again on their own)
func _hide(c: CanvasItem) -> void:
	_ui_hidden.append([c, c.visible, c.modulate.a])
	c.visible = false
	c.modulate.a = 0.0


# ====================================================================== takes on disk
func _takes() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	return out


func save_take() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open("%s/%s.json" % [DIR, take_name], FileAccess.WRITE)
	f.store_string(JSON.stringify({"v": 1, "name": take_name, "path": path, "acts": acts, "meta": _meta, "ui": opts.ui, "smooth": opts.smooth,
		"subs": subs}))
	f.close()
	main.toasts.push("good", "Дубль збережено", "%s/%s.json" % [ProjectSettings.globalize_path(DIR), take_name])
	_build()


func load_take(name: String) -> bool:
	var p := "%s/%s.json" % [DIR, name]
	if not FileAccess.file_exists(p):
		if main.toasts != null:
			main.toasts.push("warn", "Дубль не знайдено", p)
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (d is Dictionary):
		return false
	take_name = name
	path = d.get("path", [])
	acts = d.get("acts", [])
	_meta = d.get("meta", {})
	opts.ui = d.get("ui", opts.ui)
	opts.smooth = d.get("smooth", opts.smooth)
	subs = d.get("subs", [])
	for a in acts:   # JSON numbers are floats: the counts back to ints where an int is wanted
		if a[2].has("n"):
			a[2].n = int(a[2].n)
	if panel != null:
		_build()
	return true


## the command that records the take by Godot's Movie Maker: from the snapshot, at 60 fps, 1920×1080
func copy_render() -> void:
	save_take()
	var exe := OS.get_executable_path()
	var out := ProjectSettings.globalize_path("%s/%s.avi" % [DIR, take_name])
	var proj := "" if OS.has_feature("template") else " --path \"%s\"" % ProjectSettings.globalize_path("res://")
	# Movie Maker records at the window's size: 1920×1080 by an override.cfg the render removes once it runs
	var ov := (OS.get_executable_path().get_base_dir() + "/override.cfg") if OS.has_feature("template") else ProjectSettings.globalize_path("res://override.cfg")
	if not FileAccess.file_exists(ov):
		var f := FileAccess.open(ov, FileAccess.WRITE)
		if f != null:
			f.store_string("; the trailer studio's render (removed by it)\n[display]\n\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/size/mode=0\n")
			f.close()
	var cmd := "\"%s\"%s --write-movie \"%s\" --fixed-fps 60 --resolution 1920x1080 -- --load=trailer_%s --take=%s" % [exe, proj, out, take_name, take_name]
	DisplayServer.clipboard_set(cmd)
	main.toasts.push("good", "Команду скопійовано", "Вставте її в термінал: відео буде в %s" % out)


## --take=<name>: the take recorded by Movie Maker (the world loaded from its snapshot by --load)
func render_take(name: String) -> void:
	if not load_take(name):
		get_tree().quit()
		return
	panel.visible = false
	var ov := (OS.get_executable_path().get_base_dir() + "/override.cfg") if OS.has_feature("template") else ProjectSettings.globalize_path("res://override.cfg")
	if FileAccess.file_exists(ov) and FileAccess.get_file_as_string(ov).begins_with("; the trailer studio's render"):
		DirAccess.remove_absolute(ov)   # read at the start already: the game's own window size next time
	var M: Dictionary = _meta
	main.session.set_speed(int(M.get("speed", 1)))
	if M.has("mode"):
		main.hud.mode_dd.value = String(M.mode)
		main.hud.mode_dd._show_value()
		main.map.set_mode(String(M.mode))
	if M.has("hid"):
		MapVis.hid = M.hid.duplicate()
		MapVis.ver += 1
		main.map.apply_vis()
	_take = "render"
	_warm = 0
	_hide_ui(true)
	panel.visible = false
	if path.size():
		_put_cam(path[0][1], path[0][2], path[0][3], path[0][4])


# ====================================================================== the scene's buttons
## the point the camera looks at (where the events go)
func _here() -> Dictionary:
	var c := cam()
	return {"x": c.tx, "z": c.tz}


func _do(kind: String, a: Dictionary) -> void:
	var S := sim()
	var CO: Dictionary = S.CO
	var T := S.co_now()
	match kind:
		"kinds":
			for K in KINDS:
				var on: bool = a.kinds.get(K[0], true)
				opts.kinds[K[0]] = on
				var key: String = "v_" + K[0]
				if on == MapVis.hid.has(key):
					MapVis.toggle(key)
			main.map.apply_vis()
		"trips":
			_trips(int(a.get("dens", 2)), a.kinds, int(a.get("seed", 1)))
		"clear_trips":
			_clear_trips()
		"hubs":
			var q: Array = S.PL.filter(func(p): return S.hub_at(p.id) == null)
			q.sort_custom(func(p1, p2): return Vector2(p1.x - a.x, p1.z - a.z).length() < Vector2(p2.x - a.x, p2.z - a.z).length())
			_hubq = q.map(func(p): return p.id)
			_hub_spd = float(a.get("spd", 8.0))
			_hub_acc = 0.0
		"jam":
			var n0 := _road_node(a.x, a.z)
			var put := 0
			for i in 24:
				if put >= 5:
					break
				var n := _road_node(a.x + randf_range(-1.2, 1.2), a.z + randf_range(-.9, .9)) if i else n0
				if n >= 0 and S._jam_put(T, n, randf_range(.8, 2.5)):
					put += 1
			for J in S.jam:   # on at once, for a while
				if not J.on:
					J.t0 = T
					J.on = 1
					S.jamn[J.n] = J.sev
			S.inc_changed()
			S.inc_blk()
		"acc":
			var js: Array = CO.jobs.filter(func(j): return j.mode == "road" and not j.get("ret") and j.get("hold", 0) <= 0)
			js.sort_custom(func(x, y): return _dist_to(S, x, a) < _dist_to(S, y, a))
			for j in js.slice(0, 3):
				S.co_incident(j, "acc")
		"war", "border":
			var pr := _pair_at(S, a.x, a.z)
			if pr.size():
				if kind == "war":
					if not CO.has("conf"):
						CO.conf = []
					CO.conf.append({"a": pr[0], "b": pr[1], "until": T + 40})
				CO.cls.append({"id": CO.uid, "kind": "pair", "a": pr[0], "b": pr[1], "why": "Воєнний конфлікт" if kind == "war" else "Дипломатичний конфлікт",
					"until": T + 40, "conf": 1 if kind == "war" else 0})
				CO.uid += 1
				S.inc_changed()
				S.inc_blk()
		"band":
			var cid: int = S.gen.state_at(a.x, a.z)
			CO.band.append({"id": CO.uid, "x": a.x, "z": a.z, "r": .65, "cid": maxi(0, cid), "until": T + 40, "name": S.states[cid].name if cid >= 0 else ""})
			CO.uid += 1
			S.inc_changed()
		"storm":
			CO.wx.append({"id": CO.uid, "k": "hur", "n": "Ураган", "x": a.x, "z": a.z, "r": 1.0, "t0": T, "until": T + 6, "on": 1, "near": "", "mine": true})
			CO.uid += 1
			S.inc_changed()
			S.inc_blk()
		"pir":
			CO.pir.append({"id": CO.uid, "x": a.x, "z": a.z, "r": .8, "cid": 0, "name": "відкрите море"})
			CO.uid += 1
			S.inc_changed()
		"clear":
			CO.cls = []
			CO.conf = []
			CO.band = []
			CO.wx = []
			CO.pir = []
			S.jam = []
			S.jamn = {}
			S.inc_changed()
			S.inc_blk()
		"cnt":
			var from: float = main.hud.studio.get(a.k, _real(a.k))
			_cnt[a.k] = {"from": from, "to": float(a.to), "t": 0.0, "dur": float(a.dur)}
		"cnt_reset":
			_cnt = {}
			main.hud.studio = {}


func _real(k: String) -> float:
	var CO: Dictionary = sim().CO
	match k:
		"cash":
			return CO.cash
		"rating":
			return CO.rating
		"del":
			return float(CO.get("cdel", 0))
	return float(CO.tier)


func _tick_counters(dt: float) -> void:
	for k in _cnt.keys():
		var C: Dictionary = _cnt[k]
		C.t += dt
		var f := clampf(C.t / C.dur, 0, 1)
		f = f * f * (3 - 2 * f)
		var v: float = lerpf(C.from, C.to, f)
		if k == "rating":
			v = clampf(v, 1, 5)
		elif k == "del" or k == "lic":
			v = roundf(v)
		main.hud.studio[k] = v
		if f >= 1:
			_cnt.erase(k)


static func _dist_to(S: Sim, j: Dictionary, a: Dictionary) -> float:
	var q := S.co_pos_at(j, S.co_job_state(j, S.co_now() - j.t0).s)
	return Vector2(q[0] - a.x, q[1] - a.z).length()


## the road node nearest to a point, -1 when none is near
func _road_node(x: float, z: float) -> int:
	var Bd: Dictionary = sim().board
	var i0 := int(round((x + Bd.wx / 2) / Bd.st))
	var j0 := int(round((z + Bd.wz / 2) / Bd.st))
	var best := -1
	var bd := 1e9
	for j in range(j0 - 4, j0 + 5):
		for i in range(i0 - 4, i0 + 5):
			if i < 0 or j < 0 or i >= Bd.nx or j >= Bd.nz:
				continue
			var v: int = j * Bd.nx + i
			if Bd.bits[v] == 0:
				continue
			var d := Vector2(-Bd.wx / 2 + i * Bd.st - x, -Bd.wz / 2 + j * Bd.st - z).length()
			if d < bd:
				bd = d
				best = v
	return best


## two neighbouring states at a point: the one under it and the neighbour whose capital is nearest
static func _pair_at(S: Sim, x: float, z: float) -> Array:
	var a: int = S.gen.state_at(x, z)
	if a < 0 or a >= S.neighbors.size():
		return []
	var best := -1
	var bd := 1e9
	for b in S.neighbors[a]:
		if b < 0 or b >= S.states.size() or b == a:
			continue
		for p in S.PL:
			if p.cid == b:
				var d := Vector2(p.x - x, p.z - z).length()
				if d < bd:
					bd = d
					best = b
	return [a, best] if best >= 0 else []


## trips evenly over the whole world: from every town `dens` trips by the kinds chosen to towns around it
## (road and rail on its land, sea and air farther), already on their way — no vehicles of the company, no lead
## from a hub, no pay: the picture of a busy world, the company's money untouched
func _trips(dens: int, kinds: Dictionary, seed_: int) -> void:
	var S := sim()
	var CO: Dictionary = S.CO
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var ms: Array = KINDS.map(func(K): return K[0]).filter(func(m): return kinds.get(m, false))
	if ms.is_empty():
		return
	var by_m := {}
	for m in ms:
		by_m[m] = S.PL.filter(func(p): return S.node_ok(m, p))
	var vt := {}
	for t in D_VT():
		var T: Dictionary = D_VT()[t]
		if not vt.has(T.mode) and not T.get("loc", 0) and T.tier <= 7:
			vt[T.mode] = t
	var now := S.co_now()
	for A in S.PL:
		for n in dens:
			var cand: Array = ms.filter(func(m): return S.node_ok(m, A) and vt.has(m))
			if cand.is_empty():
				break
			var m: String = cand[rng.randi() % cand.size()]
			var far: Vector2 = Vector2(.6, 5.0) if m == "road" or m == "rail" else Vector2(2.5, 12.0)
			var pool: Array = by_m[m]
			for tries in 14:
				var B: Dictionary = pool[rng.randi() % pool.size()]
				var d := Vector2(B.x - A.x, B.z - A.z).length()
				if B.id == A.id or d < far.x or d > far.y or ((m == "road" or m == "rail") and B.land != A.land):
					continue
				var rr: Variant = S.co_route(m, A.id, B.id)
				if rr == null:
					continue
				var T: Dictionary = D_VT()[vt[m]]
				var tm: float = rr.len / (T.spd * S.spd_k())
				var k := {"id": CO.uid, "from": A.id, "to": B.id, "cg": "parcel", "tons": 4.0, "pay": 0, "dlDays": 99.0, "mode": m, "risk": .2,
					"minR": 0, "len": rr.len, "_demo": 1}
				CO.uid += 1
				var P := {"ok": true, "fuel": 0.0, "leadR": {"p": PackedFloat32Array([A.x, A.z]), "len": 0.0}, "main": rr, "t": vt[m], "n": 1, "vids": [],
					"lead": 0.0, "tl": 0.0, "tm": tm, "hs": .03, "cust": 0.0, "tot": tm + .06}
				S.co_dispatch(k, P, true)
				var j: Dictionary = CO.jobs.back()
				j.t0 = now - rng.randf() * j.tot * .9   # already on their way, each at its own point
				break
	main.map.company_colors()


static func D_VT() -> Dictionary:
	return preload("res://scripts/logistics/game_data.gd").VT


## «Прибрати рейси»: every trip off the map; the vehicles back home, the network's runs undone
func _clear_trips() -> void:
	var S := sim()
	var CO: Dictionary = S.CO
	for v in CO.veh:
		if v.st != "idle":
			v.st = "idle"
			v.loc = CO.hq
		v.erase("resv")
		v.erase("nres")
	CO.jobs.clear()
	if S.alt():
		for c in CO.net.cs:
			if c.st == "move":
				c.st = "ready"
			c.run = -1
		CO.net.runs.clear()
	main.map.company_colors()


var _hubq: Array = []
var _hub_spd := 8.0
var _hub_acc := 0.0
var _hub_paint := 0.0


## «Відкрити всі хаби»: town by town, from the nearest to the camera outwards, a hub of the company
func _tick_hubs(dt: float) -> void:
	if _hubq.is_empty():
		return
	var S := sim()
	_hub_acc += dt * _hub_spd
	var added := false
	while _hub_acc >= 1.0 and _hubq.size():
		_hub_acc -= 1.0
		var pid: int = _hubq.pop_front()
		if S.hub_at(pid) == null:
			S.CO.hubs.append({"pid": pid, "lvl": 1, "share": .01, "mk": 0})
			added = true
	_hub_paint -= dt
	if added and (_hub_paint <= 0 or _hubq.is_empty()):   # the map's colours a few times a second
		_hub_paint = .2
		main.map.company_colors()


# ====================================================================== subtitles
## A subtitle is a card (or bare text): a title and a line under it, in the game's fonts, at a place on the
## screen (its centre: x, y as parts of the width and the height), drifting a little to one side over its time
## (2% of the width each way) or still, fading in and out over 0.4 s. The sizes are pixels at 1080p.
## tools/subtitles.py draws the same from the copied code.
func _sub_editor() -> Control:
	var v := Ui.vbox(6)
	var te := LineEdit.new()
	te.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	te.text = sub.title
	te.placeholder_text = "Заголовок"
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.text_changed.connect(func(t): sub.title = t)
	v.add_child(te)
	var tx := LineEdit.new()
	tx.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tx.text = sub.text
	tx.placeholder_text = "Текст під заголовком (можна порожній)"
	tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tx.text_changed.connect(func(t): sub.text = t)
	v.add_child(tx)
	var cp := ColorPickerButton.new()
	cp.color = Color(sub.color)
	cp.custom_minimum_size = Vector2(40, 28)
	cp.color_changed.connect(func(c): sub.color = "#" + c.to_html(false))
	v.add_child(Ui.hbox(8, [Ui.lbl("Заголовок"), cp, Ui.spacer(), W._toggle(sub.box, func():
		sub.box = not sub.box
		_build(), "Картка: темне скло й тонка рамка"), Ui.label("Картка", 12, Ui.FG2)]))
	v.add_child(Ui.hbox(8, [Ui.lbl("Шрифт"), Ui.seg([["display", "Широкий"], ["body", "Звичайний"]], sub.font, func(x):
		sub.font = x
		_build())]))
	v.add_child(Ui.hbox(8, [Ui.lbl("Текст на картці"), Ui.seg([["left", "Ліворуч"], ["center", "По центру"], ["right", "Праворуч"]], String(sub.get("align", "left")), func(x):
		sub.align = x
		_build())]))
	var an := GridContainer.new()
	an.columns = 3
	an.add_theme_constant_override("h_separation", 6)
	an.add_theme_constant_override("v_separation", 6)
	for A in ANIMS:
		var a_: String = A[0]
		var b := W._btn(A[1], "pri sm" if String(sub.get("anim", "fade")) == a_ else "sm", "", func():
			sub.anim = a_
			_build()
			preview_sub(sub.duplicate()))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = A[2]
		an.add_child(b)
	v.add_child(Ui.lbl("Анімація появи"))
	v.add_child(an)
	v.add_child(Ui.hbox(8, [Ui.lbl("Рух"), Ui.seg([[-1, "← трохи вліво"], [0, "на місці"], [1, "трохи вправо →"]], int(sub.drift), func(x):
		sub.drift = x
		_build())]))
	v.add_child(_slider("Розмір заголовка", float(sub.size), 20.0, 120.0, func(x): sub.size = int(x), "", 0))
	v.add_child(_slider("Де по горизонталі", float(sub.x), .1, .9, func(x): sub.x = x))
	v.add_child(_slider("Де по вертикалі", float(sub.y), .08, .92, func(x): sub.y = x))
	v.add_child(_slider("Тривалість", float(sub.dur), 1.0, 20.0, func(x): sub.dur = x, " с", 1))
	v.add_child(_slider("Початок у відео", float(sub.t0), 0.0, 120.0, func(x): sub.t0 = x, " с", 1))
	v.add_child(_fill([W._btn("Показати", "sm", "eye" if Icons.has("eye") else "", func(): preview_sub(sub.duplicate())),
		W._btn("Додати до списку", "pri sm", "", func():
			subs.append(sub.duplicate())
			_build())]))
	if subs.size():
		var L := Ui.vbox(2)
		for i in subs.size():
			var it: Dictionary = subs[i]
			var i_: int = i
			var row := Ui.label("%.1f–%.1f с · %s" % [it.t0, it.t0 + it.dur, it.title], 12, Color(it.color))
			row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.clip_text = true
			L.add_child(Ui.hbox(6, [row, MapUi._xbtn(func():
				subs.remove_at(i_)
				_build())]))
		v.add_child(L)
		v.add_child(_fill([W._btn("Показати всі", "sm", "", func():
			for it in subs:
				preview_sub(it.duplicate(), it.t0 - subs[0].t0)), W._btn("Копіювати код", "sm", "doc", copy_subs, true,
			"Копіює список субтитрів як JSON: надішліть його разом із відео — tools/subtitles.py накладе текст так само, як у попередньому перегляді.")]))
	return v


func copy_subs() -> void:
	DisplayServer.clipboard_set(JSON.stringify({"subtitles": subs}, "  "))
	main.toasts.push("good", "Код субтитрів скопійовано", "%d рядків" % subs.size())


## the sizes of a subtitle at a screen height (pixels): title, text, paddings — as in
## tools/subtitles.py
static func sub_sizes(it: Dictionary, h: float) -> Dictionary:
	var k := h / 1080.0
	var ts := maxi(8, int(round(float(it.size) * k)))
	var box: bool = it.get("box", true)
	return {"ts": ts, "xs": maxi(int(round(14 * k)), int(round(ts * .5))), "pad": int(round(ts * .55)) if box else 0,
		"padv": int(round(ts * .4)) if box else 0, "gap": int(round(ts * .25)), "bar": 0}


## a subtitle over the game as tools/subtitles.py draws it on the frames
func preview_sub(it: Dictionary, delay: float = 0.0) -> void:
	var vs := get_viewport().get_visible_rect().size
	var z := sub_sizes(it, vs.y)
	var box: bool = it.get("box", true)
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(.03, .07, .11, .86) if box else Color.TRANSPARENT
	if box:
		st.set_border_width_all(1)
		st.border_color = Color(1, 1, 1, .14)
	card.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var col := Ui.vbox(z.gap)
	var al: int = {"center": HORIZONTAL_ALIGNMENT_CENTER, "right": HORIZONTAL_ALIGNMENT_RIGHT}.get(String(it.get("align", "left")), HORIZONTAL_ALIGNMENT_LEFT)
	var t := _sub_label(it.title, Ui.font("display", 600) if it.font == "display" else Ui.font("body", 600), z.ts, Color(it.color), not box)
	t.horizontal_alignment = al   # the lines on the card: left, centred or right
	col.add_child(t)
	if String(it.get("text", "")) != "":
		var x := _sub_label(it.text, Ui.font("body", 500), z.xs, Color("#c9d4de"), not box)
		x.horizontal_alignment = al
		col.add_child(x)
	h.add_child(Ui.margin(col, z.pad, z.padv, z.pad, z.padv))
	card.add_child(h)
	var root := Control.new()   # the card inside: clipped for the wipe, scaled for the pop
	root.clip_contents = true
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	root.modulate.a = 0
	_sub_layer.add_child(root)
	_subs_live.append({"lbl": root, "card": card, "t": -delay, "it": it, "labels": col.get_children()})


static func _sub_label(text: String, f: Font, size: int, c: Color, shadow: bool) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # the player's own words
	l.text = text
	l.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING   # typing: the card keeps its size
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .55))
		l.add_theme_constant_override("shadow_offset_x", maxi(1, size / 18))
		l.add_theme_constant_override("shadow_offset_y", maxi(1, size / 18))
	return l


var _subs_live: Array = []


func _tick_sub(dt: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	for e in _subs_live.duplicate():
		e.t += dt
		var c: Control = e.lbl
		var card: Control = e.card
		var it: Dictionary = e.it
		card.size = card.get_combined_minimum_size()
		var sz := card.size
		var st := sub_state(it, e.t, vs, sz)
		c.position = st.pos
		c.size = Vector2(sz.x * st.reveal, sz.y)
		c.pivot_offset = sz / 2
		c.scale = Vector2.ONE * st.scale
		c.modulate.a = st.a
		# typing: the title's letters first, then the line's
		var L: Array = e.labels
		var n0: int = L[0].text.length()
		var n1: int = L[1].text.length() if L.size() > 1 else 0
		var shown := int(floor(st.chars * (n0 + n1)))
		L[0].visible_characters = mini(n0, shown) if st.chars < 1 else -1
		if L.size() > 1:
			L[1].visible_characters = maxi(0, shown - n0) if st.chars < 1 else -1
		if e.t > float(it.dur):
			c.queue_free()
			_subs_live.erase(e)


## where a subtitle is and how it shows, t seconds into it (tools/subtitles.py does the same): centred on its
## place, drifting 2% of the width to one side and on over its time (or still), fading out over the last 0.4 s;
## it comes in by its animation over 0.6 s (eased out): fade — a fade; up — from 4% of the height below;
## side — from 6% of the width on the side it drifts from; pop — growing from 85%; wipe — opened left to right;
## type — its letters one after another (about 28 a second). → pos, a (alpha), scale, reveal (the part of the
## width shown), chars (the part of the letters shown)
static func sub_state(it: Dictionary, t: float, vs: Vector2, sz: Vector2) -> Dictionary:
	var dur := float(it.dur)
	var p := clampf(t / dur, 0, 1)
	var dr := float(it.get("drift", 0))
	var d := dr * vs.x * .02 * (p * 2 - 1)
	var e := clampf(t / .6, 0, 1)
	var ein := 1.0 - pow(1.0 - e, 3)
	var out := clampf((dur - t) / .4, 0, 1)
	var a := clampf(minf(t / .4, out), 0, 1)
	var pos := Vector2(float(it.get("x", .5)) * vs.x - sz.x / 2 + d, float(it.y) * vs.y - sz.y / 2)
	var sc := 1.0
	var rv := 1.0
	var ch := 1.0
	match String(it.get("anim", "fade")):
		"up":
			pos.y += (1 - ein) * vs.y * .04
			a = minf(clampf(t / .35, 0, 1), out)
		"side":
			pos.x -= (1 - ein) * vs.x * .06 * (1.0 if dr >= 0 else -1.0)
			a = minf(clampf(t / .35, 0, 1), out)
		"pop":
			sc = .85 + .15 * ein
			a = minf(clampf(t / .25, 0, 1), out)
		"wipe":
			rv = ein
			a = out
		"type":
			var n := String(it.get("title", "")).length() + String(it.get("text", "")).length()
			ch = clampf(t / maxf(.2, n / 28.0), 0, 1)
			a = minf(clampf(t / .15, 0, 1), out)
	if t < 0:
		a = 0.0
	return {"pos": pos, "a": a, "scale": sc, "reveal": rv, "chars": ch}


# ====================================================================== keys
func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo or e.physical_keycode != KEY:
		return
	get_viewport().set_input_as_handled()
	if _take == "live":   # the key in a take stops it
		_play_t = INF
		_stop_play()
		return
	open_panel(not panel.visible)
