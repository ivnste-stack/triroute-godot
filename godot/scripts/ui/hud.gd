class_name Hud
extends Control
## The always-visible interface of the HTML version in company mode (02-body.html + coHUD / buildHUD):
## top — the menu button, the company card (logo, name, licence, headquarters), the KPIs; left — the rail of
## windows; bottom — the time controls, date and clock, trips, fuel and parts prices, this month's revenue,
## the news ticker.

signal window_requested(id: String)
signal menu_requested

const RAIL := [["coHome", "briefcase", "Компанія", "Огляд, рейтинг, ліцензії, досягнення і поради."],
	["coJobs", "box", "Біржа вантажів", "Замовлення від підприємств, прокладання маршрутів, автодиспетчеризація, тендери."],
	["coTrips", "road", "Рейси в дорозі", "Техніка в рейсах, ділянки маршрутів, повернення в хаби, останні доставки."],
	["coFleet", "truck", "Автопарк", "Купівля, продаж і ремонт техніки."],
	["coNet", "globe", "Мережа хабів", "Хаби в містах, місцевий ринок доставок, реклама, склади."],
	["coStaff", "users", "Персонал і менеджмент", "Найм, зарплати, моральний дух, менеджери."],
	["coFin", "coins", "Фінанси", "Прибутки й витрати, кредити, страхування, рейтинг компаній світу."],
	["|"],
	["news", "news", "Стрічка новин", "Що відбувається у світі."]]
const SPEED := [["pause", "Пауза (пробіл)"], ["play", "Звичайна швидкість"], ["ff", "Швидко"], ["fff", "Дуже швидко"]]

var session: GameSession
var open_window := ""

var _name: Label
var _sub: Label
var _logo: Control
var _kpis: HBoxContainer
var _kpi_vals: Array = []
var _rail_btns := {}
var _rail: Control
var _badges := {}
var _speed_btns: Array = []
var _cells := {}
var _ticker: Label
var _ticker_dot: ColorRect
var _ticker_clip: Control
var _ticker_x := 0.0
var _ticker_text := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
	_build_top()
	_build_rail()
	_build_bar()


# ---------- top ----------
func _build_top() -> void:
	var top := Ui.hbox(8)
	top.position = Vector2(14, 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var menu := Ui.glass()
	menu.custom_minimum_size = Vector2(62, 62)
	var mb := Button.new()
	mb.flat = true
	mb.icon = Icons.tex("shield", Ui.FG2, 22)
	mb.add_theme_constant_override("icon_max_width", 22)
	mb.focus_mode = Control.FOCUS_NONE
	mb.tooltip_text = "Меню гри"
	mb.pressed.connect(func(): menu_requested.emit())
	menu.add_child(mb)
	top.add_child(menu)
	# the company card
	var who := Ui.glass()
	_logo = Control.new()
	_logo.custom_minimum_size = Vector2(46, 30)
	_logo.draw.connect(_draw_logo)
	_name = Ui.label("—", 14, Ui.FG, Ui.font("display", 600, .6))
	_sub = Ui.label("—", 12, Ui.MUTED)
	who.add_child(Ui.margin(Ui.hbox(12, [_logo, Ui.vbox(3, [_name, _sub])]), 8, 8, 14, 8))
	top.add_child(who)
	# KPIs
	var kp := Ui.glass()
	_kpis = Ui.hbox(0)
	kp.add_child(_kpis)
	top.add_child(kp)
	for k in ["Гроші", "Прибуток / міс", "Рейтинг", "Доставки / день", "Техніка", "Персонал", "Ліцензія"]:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", _cell_box(k != "Ліцензія"))
		cell.custom_minimum_size.x = 84
		var v := Ui.hbox(4, [Ui.num("—", 15)])
		cell.add_child(Ui.vbox(5, [Ui.lbl(k), v]))
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		_kpis.add_child(cell)
		_kpi_vals.append(v)


## the right border of a cell (border-right: 1px solid var(--line))
func _cell_box(right: bool, pad: Vector4 = Vector4(12, 8, 12, 8)) -> StyleBoxFlat:
	var s := Ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, pad)
	if right:
		s.border_color = Ui.LINE
		s.border_width_right = 1
	return s


## coLogo: the company colour, a darker wedge, an arrow and the initials
func _draw_logo() -> void:
	paint_logo(_logo, session.sim if session != null else null)


static func paint_logo(c: Control, sim: Variant) -> void:
	var w := c.size.x
	var h := c.size.y
	var col := Color(sim.CO.get("col", "#ffb347")) if sim != null else Ui.WARM
	var k := Vector2(w / 96.0, h / 64.0)
	c.draw_rect(Rect2(0, 0, w, h), col)
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 64) * k, Vector2(96, 14) * k, Vector2(96, 64) * k]), Color(0, 0, 0, .18))
	c.draw_polyline(PackedVector2Array([Vector2(18, 44) * k, Vector2(46, 20) * k, Vector2(46, 32) * k, Vector2(78, 32) * k]), Color("#0b1520"), 5 * k.x, true)
	if sim != null:
		var ini := ""
		for part in String(sim.CO.name).split(" ", false):
			ini += part.left(1)
		var f := Ui.font("body", 700)
		c.draw_string(f, Vector2(58, 56) * k, ini.left(2).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k.y), Color("#0b1520"))
	c.draw_rect(Rect2(0, 0, w, h), Ui.LINE_HI, false, 1)


# ---------- the rail of windows ----------
## body.lplan: the rail of windows steps aside while the route planner is open
func set_planning(on: bool) -> void:
	_rail.visible = not on


func _build_rail() -> void:
	var g := Ui.glass()
	g.position = Vector2(14, 84)
	_rail = g
	var v := Ui.vbox(0)
	g.add_child(Ui.margin(v, 4))
	add_child(g)
	for r in RAIL:
		if r[0] == "|":
			var sep := ColorRect.new()
			sep.color = Ui.LINE
			sep.custom_minimum_size = Vector2(32, 1)
			v.add_child(Ui.margin(sep, 6, 4))
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 40)
		b.icon = Icons.tex(r[1], Ui.FG2, 20)
		b.add_theme_constant_override("icon_max_width", 20)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s\n%s" % [r[2], r[3]]
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", Ui.box(Ui.ACCENT_SOFT))
		b.add_theme_stylebox_override("pressed", Ui.box(Ui.ACCENT))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var id: String = r[0]
		b.pressed.connect(func(): window_requested.emit(id))
		v.add_child(b)
		_rail_btns[id] = [b, r[1]]
		# a red badge (the orders on the board, the trips under way)
		var bd := Label.new()
		bd.add_theme_font_override("font", Ui.font("mono", 600))
		bd.add_theme_font_size_override("font_size", 10)
		bd.add_theme_color_override("font_color", Color.WHITE)
		bd.add_theme_stylebox_override("normal", Ui.box(Ui.BAD, Color.TRANSPARENT, 0, Vector4(4, 0, 4, 0)))
		bd.position = Vector2(26, 5)
		bd.visible = false
		b.add_child(bd)
		_badges[id] = bd


# ---------- the bottom bar ----------
func _build_bar() -> void:
	var g := Ui.glass()
	g.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	g.offset_left = 14
	g.offset_right = -14
	g.offset_top = -74
	g.offset_bottom = -14
	add_child(g)
	var row := Ui.hbox(0)
	g.add_child(row)
	var sp := Ui.hbox(2)
	var spc := PanelContainer.new()
	spc.add_theme_stylebox_override("panel", _cell_box(true, Vector4(10, 0, 10, 0)))
	spc.add_child(sp)
	row.add_child(spc)
	for i in SPEED.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = SPEED[i][1]
		b.add_theme_stylebox_override("normal", Ui.box(Color.TRANSPARENT, Color.TRANSPARENT))
		b.add_theme_stylebox_override("hover", Ui.box(Color.TRANSPARENT, Ui.LINE_HI))
		b.add_theme_stylebox_override("pressed", Ui.box(Ui.ACCENT))
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", 18)
		b.pressed.connect(func(): if session != null: session.set_speed(i))
		sp.add_child(b)
		_speed_btns.append(b)
	for c in [["date", "Дата", "1 день = 1 крок симуляції. Рейси рухаються щохвилини, економіка рахується щодня й щомісяця."],
			["trips", "Рейси в дорозі", "Техніка в рейсах і замовлення на біржі."],
			["fuel", "Пальне, барель", "Світова ціна барелю нафти. Від неї залежить вартість кожного рейсу. Стрибає при нафтових шоках, війнах і санкціях і поступово повертається до норми ≈ $80."],
			["parts", "ТО вантажівки", "Середня вартість планового техобслуговування вантажівки (норма ≈ $1 200). Так само дорожчають ремонт, евакуатори, утримання техніки й модернізація."],
			["rev", "Виручка за місяць", "Виручка з початку місяця і зміна проти того самого дня минулого місяця."]]:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", _cell_box(true, Vector4(16, 9, 16, 9)))
		cell.tooltip_text = "%s\n%s" % [c[1], c[2]]
		var v := Ui.hbox(6, [Ui.num("—", 16)])
		cell.add_child(Ui.vbox(4, [Ui.lbl(c[1]), v]))
		row.add_child(cell)
		_cells[c[0]] = v
	# the news ticker
	_ticker_clip = Control.new()
	_ticker_clip.clip_contents = true
	_ticker_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ticker_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_ticker_clip)
	_ticker_dot = ColorRect.new()
	_ticker_dot.custom_minimum_size = Vector2(7, 7)
	_ticker_dot.size = Vector2(7, 7)
	_ticker_clip.add_child(_ticker_dot)
	_ticker = Ui.label("", 13, Ui.FG2)
	_ticker_clip.add_child(_ticker)
	var mb := Button.new()
	mb.flat = true
	mb.icon = Icons.tex("menu", Ui.FG2, 20)
	mb.add_theme_constant_override("icon_max_width", 20)
	mb.custom_minimum_size = Vector2(48, 0)
	mb.focus_mode = Control.FOCUS_NONE
	mb.tooltip_text = "Шари мапи й легенда"
	row.add_child(mb)


# ---------- values (coHUD) ----------
func _put(box: HBoxContainer, parts: Array) -> void:
	# parts: [text, colour, size] …
	while box.get_child_count() < parts.size():
		box.add_child(Ui.num("", 15))
	for i in box.get_child_count():
		var l: Label = box.get_child(i)
		l.visible = i < parts.size()
		if i < parts.size():
			var p: Array = parts[i]
			l.text = p[0]
			l.add_theme_color_override("font_color", p[1] if p.size() > 1 else Ui.FG)
			l.add_theme_font_size_override("font_size", p[2] if p.size() > 2 else 15)
			l.size_flags_vertical = Control.SIZE_SHRINK_END


func _process(delta: float) -> void:
	if session == null or session.sim == null or session.sim.CO.is_empty() or not session.sim.CO.has("hubs"):
		return
	var sim := session.sim
	var CO := sim.CO
	_name.text = CO.name
	var hq: Dictionary = sim.PL[CO.hq]
	_sub.text = "%s · штаб: %s" % [GameData.LIC[CO.tier].n, hq.name]
	_logo.queue_redraw()
	var lm: Variant = CO.lm
	var pr: float = sim.co_rev(lm) - sim.co_cost(lm) if lm != null else 0.0
	var busy := 0
	for v in CO.veh:
		if v.st != "idle":
			busy += 1
	var staff := 0
	for r in CO.staff:
		staff += CO.staff[r]
	staff += CO.founder
	_put(_kpi_vals[0], [[Ui.usd(CO.cash)], ["▲" if CO.cash >= 0 else "▼", Ui.GOOD if CO.cash >= 0 else Ui.BAD, 11]])
	_put(_kpi_vals[1], [[Ui.usd(pr, true) if lm != null else "—", (Ui.GOOD if pr >= 0 else Ui.BAD) if lm != null else Ui.FG]])
	_put(_kpi_vals[2], [["%.2f ★" % CO.rating]])
	_put(_kpi_vals[3], [[Ui.grp(CO.dayLocal)]])
	_put(_kpi_vals[4], [[str(CO.veh.size())], ["%d у рейсі" % busy, Ui.MUTED, 11]])
	_put(_kpi_vals[5], [[str(staff)]])
	_put(_kpi_vals[6], [["%d/%d" % [CO.tier, GameData.LIC.size() - 1]]])
	# the bottom bar
	for i in _speed_btns.size():
		var on := i == session.speed
		var b: Button = _speed_btns[i]
		b.icon = Icons.tex(SPEED[i][0], Ui.ACCENT_INK if on else Ui.FG2, 18, 1.7, SPEED[i][0] != "pause")
		b.add_theme_stylebox_override("normal", Ui.box(Ui.ACCENT) if on else Ui.box(Color.TRANSPARENT, Color.TRANSPARENT))
	var fr := session.fraction()
	var h := int(fr * 24)
	var mm := int((fr * 24 - h) * 6) * 10
	_put(_cells.date, [[Ui.date_str(sim.date), Ui.FG, 16], ["%02d:%02d" % [h, mm], Ui.MUTED, 12]])
	_put(_cells.trips, [[str(CO.jobs.size()), Ui.FG, 16], [("%d на біржі" % CO.board.size()) if CO.tier >= 1 else "з ліцензією 2", Ui.MUTED, 11]])
	_put(_cells.fuel, [[Ui.usd(CO.fuel * 80), Ui.BAD if CO.fuel > 1.15 else (Ui.GOOD if CO.fuel < .9 else Ui.FG), 16]])
	var pk: float = CO.get("parts", 1.0)
	var rk := sim.rep_k()
	var parts := [[Ui.usd(1200 * pk * sim.price_k(sim.me)), Ui.BAD if pk > 1.12 else (Ui.GOOD if pk < .92 else Ui.FG), 16]]
	if absf(rk - pk) > .005:
		parts.append(["з СТО " + Ui.usd(1200 * rk * sim.price_k(sim.me)), Ui.MUTED, 11])
	_put(_cells.parts, parts)
	var rv := sim.co_rev(CO.m)
	var dm: int = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][sim.date.m]
	var prev: float = sim.co_rev(lm) * sim.date.d / dm if lm != null else 0.0
	var rparts := [[Ui.usd(rv), Ui.FG, 16]]
	if prev > 0:
		var dlt := (rv / prev - 1) * 100
		rparts.append(["%s%d%%" % ["+" if dlt >= 0 else "", int(JS.round_js(dlt))], Ui.GOOD if dlt >= 0 else Ui.BAD, 11])
	_put(_cells.rev, rparts)
	# rail: the open window, the badges
	for id in _rail_btns:
		var on: bool = id == open_window
		var b: Button = _rail_btns[id][0]
		b.icon = Icons.tex(_rail_btns[id][1], Ui.ACCENT_INK if on else Ui.FG2, 20)
		b.add_theme_stylebox_override("normal", Ui.box(Ui.ACCENT) if on else StyleBoxEmpty.new())
	_badge("coJobs", CO.board.size() if CO.tier >= 1 else 0)
	var trips := 0
	for j in CO.jobs:
		if not j.get("ret"):
			trips += 1
	_badge("coTrips", trips)
	# ticker: the latest news, scrolling
	var n: Variant = sim.news.back() if sim.news.size() else null
	var txt: String = n[2] if n != null else ""
	if txt != _ticker_text:
		_ticker_text = txt
		_ticker.text = txt
		_ticker_x = 0.0
		_ticker_dot.color = {"good": Ui.GOOD, "bad": Ui.BAD, "warn": Ui.WARN}.get(n[0] if n != null else "", Ui.ACCENT) if n != null else Color.TRANSPARENT
	var cw := _ticker_clip.size.x
	var tw := _ticker.get_combined_minimum_size().x
	if tw + 30 > cw:
		_ticker_x -= delta * 40
		if _ticker_x < -(tw + 30):
			_ticker_x = cw
	else:
		_ticker_x = 0
	_ticker_dot.position = Vector2(14 + _ticker_x, _ticker_clip.size.y / 2 - 3.5)
	_ticker.position = Vector2(28 + _ticker_x, (_ticker_clip.size.y - _ticker.get_combined_minimum_size().y) / 2)


func _badge(id: String, n: int) -> void:
	var b: Label = _badges[id]
	b.visible = n > 0
	b.text = str(n)
