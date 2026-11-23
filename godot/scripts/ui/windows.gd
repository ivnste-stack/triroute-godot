class_name Windows
extends RefCounted
## The windows of the company (WINS.co* of the HTML version: 08e-company.js, 08g-business.js): the order
## board, trips on the way, the fleet, the hub network, staff and managers, finances and the company card.
## Every window is built from the current state of the game; an action calls SimActions and reports its result
## through `acted` (a toast, then the window is built again).

signal acted(res: Dictionary)
signal goto_place(pid: int)
signal select_job(j: Dictionary)
signal plan_order(k: Dictionary)    # ACT.lpPlan: open the route planner
signal move_vehicle(v: Dictionary)  # ACT.coMove: pick a new home hub on the map

const D = preload("res://scripts/logistics/game_data.gd")
const MODE_IC := {"local": "van", "road": "truck", "rail": "train", "sea": "ship", "air": "plane"}
const MODES := [["all", "Усі", ""], ["road", "Авто", "truck"], ["rail", "Залізниця", "train"], ["sea", "Море", "ship"], ["air", "Авіа", "plane"]]
const TYPE_N := {"cap": "столиця", "big": "велике місто", "city": "місто", "town": "містечко"}
const CO_MS := [["d100", "Перша сотня", "100 доставок"], ["f5", "Маленький автопарк", "5 одиниць техніки"], ["van", "На колесах", "Перший фургон"],
	["hub2", "Друга точка", "Другий хаб"], ["c1", "Перший контракт", "Виконати замовлення між містами"], ["abroad", "За кордон", "Хаб в іншій країні"],
	["d10k", "Десять тисяч", "10 000 доставок"], ["rail", "Сталеві колії", "Перший потяг"], ["ocean", "Через океан", "Рейс між материками"],
	["air", "У небі", "Перший вантажний літак"], ["m1", "Мільйон на місяць", "Виручка $1 млн за місяць"], ["c3", "Три материки", "Хаби на трьох материках"],
	["r45", "Бездоганна репутація", "Рейтинг 4.5"], ["top3", "Призер", "Топ-3 логістичних компаній світу"], ["top1", "Лідер ринку", "№1 серед логістичних компаній світу"]]
const CO_MYTH := [
	["Найшвидший транспорт — найвигідніший.", "Літак перевозить тонну в 10–20 разів дорожче за корабель. Авіацією везуть лише те, що дороге або термінове: ліки, електроніку, запчастини."],
	["Повна машина завжди вигідніша.", "Якщо заради повного завантаження машина три дні чекає вантаж, втрачені дні коштують дорожче. Важливий баланс завантаження і швидкості."],
	["Головні витрати перевізника — пальне.", "У міських доставках найбільша стаття — люди. На дальніх маршрутах пальне, але зарплати, ремонт і простої разом часто більші."],
	["Страхування — викинуті гроші.", "Одна викрадена фура з електронікою може коштувати як рік страхових внесків."],
	["Дешевша робоча сила завжди краща.", "Низькі зарплати — це плинність кадрів, аварії й страйки. Мотивований водій береже техніку і вантаж."],
	["Залізниця застаріла.", "На відстанях понад 500–800 км потяг везе тонну вантажу в 3–4 рази дешевше за вантажівку і з меншими викидами."],
	["Порожній зворотний рейс — дрібниця.", "Порожній пробіг — одна з головних втрат галузі. Диспетчери шукають попутні вантажі, щоб машина не їхала назад порожньою."],
	["Велика компанія не може збанкрутувати.", "У логістиці маржа тонка: 3–8%. Кредити на техніку, падіння попиту і дорожнеча пального швидко з'їдають запас."]]

var sim: Sim
## the state of the interface (UI.jfl, UI.ffl, UI.bmore… of the HTML version)
var st := {"jfl": "all", "ffl": "all", "bmore": 15, "jmore": 15, "fmore": 120, "cons": []}
const GR_FEAT := {"cons": 1, "move": 1, "reroute": 2, "cto": 2}
const CONS_TIP := "Збірний рейс\nПозначте кілька замовлень одного виду транспорту цією кнопкою — одна машина, потяг, судно чи літак забере й розвезе їх за маршрутом, який ви прокладете. Головне — щоб вага й об'єм усіх вантажів разом вмістилися в кузов і встигнути в дедлайни."


func _init(sim_: Sim) -> void:
	sim = sim_


func build(id: String, body: VBoxContainer) -> void:
	Perf.acc.erase("co_plan")
	match id:
		"coHome": _home(body)
		"coJobs": _jobs(body)
		"coTrips": _trips(body)
		"coFleet": _fleet(body)
		"coNet": _net(body)
		"coStaff": _staff(body)
		"coFin": _fin(body)


func _do(res: Variant) -> void:
	acted.emit(res if res is Dictionary else {})


# ====================================================================== small elements
static func _tone_col(cls: String) -> Color:
	return {"good": Ui.GOOD, "bad": Ui.BAD, "warn": Ui.WARN, "acc": Ui.ACCENT, "mut": Ui.MUTED}.get(cls, Ui.FG)


static func _tip(t: String, d: String) -> String:
	return t + ("\n" + d if d != "" else "")


## .stat: a label, a big number, a small line under it
static func _stat(l: String, v: String, s: String = "", tip: String = "", cls: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(12, 10, 12, 10)))
	var c := Ui.vbox(0)
	c.add_child(Ui.lbl(l))
	var n := Ui.num(v, 19, _tone_col(cls))
	n.custom_minimum_size.y = 29
	n.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	c.add_child(n)
	if s != "":
		var sl := Ui.label(s, 12, Ui.MUTED)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(sl)
	p.add_child(c)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tip != "":
		p.tooltip_text = tip
	return p


## .sect h4: an upper-case heading between the parts of a window
static func _sect(t: String) -> Control:
	var l := Ui.label(t.to_upper(), 13, Ui.FG, Ui.font("display", 600, 0.8))
	var line := ColorRect.new()
	line.color = Ui.LINE
	line.custom_minimum_size.y = 1
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return Ui.margin(Ui.hbox(10, [l, line]), 0, 8, 0, 0)


## .grid2/.grid3/.grid4: equal columns
static func _grid(n: int, items: Array, gap: int = 10) -> GridContainer:
	var g := GridContainer.new()
	g.columns = n
	g.add_theme_constant_override("h_separation", gap)
	g.add_theme_constant_override("v_separation", gap)
	for it in items:
		it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(it)
	return g


## an icon with a coloured label next to it
static func _icl(ic: String, text: String, col: Color = Ui.FG2, size: int = 13) -> HBoxContainer:
	var h := Ui.hbox(5)
	if ic != "":
		var i := Ui.icon(ic, size + 1, col)
		i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(i)
	h.add_child(Ui.label(text, size, col))
	return h


static func _note(text: String, col: Color = Ui.FG2, size: int = 13) -> Label:
	var l := Ui.note(text, col)
	l.add_theme_font_size_override("font_size", size)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _b(text: String, size: int = 14, col: Color = Ui.FG) -> Label:
	return Ui.label(text, size, col, Ui.font("body", 600))


## a block with a title and a note under it
static func _tt(title: String, sub: String = "", ic: String = "", ic_col: Color = Ui.ACCENT) -> HBoxContainer:
	var h := Ui.hbox(10)
	if ic != "":
		var i := Ui.icon(ic, 18, ic_col)
		i.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(i)
	var v := Ui.vbox(2, [_b(title)])
	if sub != "":
		v.add_child(_note(sub))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


## .meter: a thin bar, frac 0..1
static func _meter(frac: float, col: Color = Ui.ACCENT, w: float = 0) -> Control:
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, .07)
	bg.custom_minimum_size = Vector2(w, 6)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fg := ColorRect.new()
	fg.color = col
	fg.anchor_bottom = 1
	fg.anchor_right = clampf(frac, 0, 1)
	bg.add_child(fg)
	return bg


## .tg: an on/off switch
static func _toggle(on: bool, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(38, 20)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var s := Ui.box(Ui.ACCENT_SOFT if on else Color(1, 1, 1, .08), Ui.ACCENT if on else Ui.LINE_HI)
	for k in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(k, s)
	var knob := ColorRect.new()
	knob.color = Ui.ACCENT if on else Ui.MUTED
	knob.size = Vector2(14, 14)
	knob.position = Vector2(21 if on else 3, 3)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(knob)
	b.pressed.connect(cb)
	b.tooltip_text = tip
	return b


## a row with a title and a switch (the auto-dispatch and insurance rows)
static func _tg_row(title: String, sub: String, on: bool, cb: Callable) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(12, 10, 12, 10)))
	p.add_child(Ui.hbox(12, [_tt(title, sub), _toggle(on, cb)]))
	return p


## .blk with an optional border colour and opacity
static func _blk(child: Control, border: Color = Ui.LINE, alpha: float = 1.0) -> PanelContainer:
	var p := Ui.blk(child, border)
	p.modulate.a = alpha
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


## .seg of the mode filters: [key, text, icon] with a counter
func _mode_seg(key: String, count: Callable) -> Control:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 0)
	h.add_theme_constant_override("v_separation", 0)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Color.TRANSPARENT, Ui.LINE_HI))
	var row := Ui.hbox(0)
	p.add_child(row)
	for i in MODES.size():
		var m: Array = MODES[i]
		var on: bool = st[key] == m[0]
		var b := Button.new()
		b.text = "%s · %d" % [m[1], count.call(m[0])]
		if m[2] != "":
			b.icon = Icons.tex(m[2], Ui.ACCENT_INK if on else Ui.FG2, 14, 1.8)
		b.add_theme_constant_override("icon_max_width", 14)
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size.y = 30
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var s := Ui.box(Ui.ACCENT if on else Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector4(10, 0, 10, 0))
		s.border_color = Ui.LINE
		s.border_width_right = 0 if i == MODES.size() - 1 else 1
		var hv := s.duplicate()
		if not on:
			hv.bg_color = Ui.ACCENT_SOFT
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, Ui.ACCENT_INK if on else Ui.FG2)
		var v: String = m[0]
		b.pressed.connect(func():
			st[key] = v
			_do({}))
		row.add_child(b)
	h.add_child(p)
	return h


## a dropdown (dd() of the HTML version): options [[value, text, icon]]
func _dd(options: Array, sel: Variant, cb: Callable) -> Dropdown:
	return Dropdown.make(options, sel, cb)


## a table (.tb): heads [[text, min width, align right]], rows of controls
static func _table(heads: Array, rows: Array, empty: String = "") -> VBoxContainer:
	var v := Ui.vbox(0)
	if heads.size():
		v.add_child(_tr(heads.map(func(h): return Ui.label(h[0].to_upper(), 10, Ui.MUTED, Ui.font("mono", 600, 1.0))), heads, 8))
	for r in rows:
		v.add_child(_tr(r, heads, 8))
	if rows.is_empty() and empty != "":
		v.add_child(_tr([_note(empty)], [["", 0, false]], 8))
	return v


static func _tr(cells: Array, heads: Array, pad: int, bg: Color = Color.TRANSPARENT) -> PanelContainer:
	var p := PanelContainer.new()
	var s := Ui.box(bg, Color.TRANSPARENT, 0, Vector4(0, pad, 0, pad))
	s.border_color = Ui.LINE
	s.border_width_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	var h := Ui.hbox(12)
	for i in cells.size():
		var c: Control = cells[i]
		var hd: Array = heads[i] if i < heads.size() else ["", 0, false]
		if hd[1] > 0:
			c.custom_minimum_size.x = hd[1]
			c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		else:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if hd[2]:
			if c is Label:
				c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			elif c is BoxContainer:
				c.alignment = BoxContainer.ALIGNMENT_END
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(c)
	p.add_child(Ui.margin(h, 8, 0, 8, 0))
	return p


## .lrow: icon | text | right
static func _lrow(ic: String, mid: Control, right: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(12, 10, 12, 10)))
	var i := Ui.icon(ic, 18, Ui.ACCENT)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(Ui.hbox(12, [i, mid, right]))
	return p


## .hint coloured by tone (advHint)
static func _adv(tone: String, text: String) -> PanelContainer:
	var h := Ui.hint(text, {"bad": "alert", "good": "check"}.get(tone, "bulb"))
	var col: Color = {"bad": Ui.BAD, "warn": Ui.WARN, "good": Ui.GOOD}.get(tone, Ui.ACCENT)
	if tone != "":
		h.add_theme_stylebox_override("panel", Ui.box(Color(col, .07), Color(col, .4), 1, Vector4(12, 10, 12, 10)))
	return h


static func _btn(text: String, kind: String, ic: String, cb: Callable, enabled: bool = true, tip: String = "") -> Button:
	var b := Ui.btn(text, kind, ic, cb)
	b.disabled = not enabled
	b.tooltip_text = tip
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


static func _dng(text: String, cb: Callable) -> Button:
	var b := Ui.btn(text, "sm", "", cb)
	b.add_theme_stylebox_override("normal", Ui.box(Color(1, 1, 1, .04), Color(Ui.BAD, .5), 1, Vector4(10, 0, 10, 0)))
	b.add_theme_stylebox_override("hover", Ui.box(Color(Ui.BAD, .15), Ui.BAD, 1, Vector4(10, 0, 10, 0)))
	b.add_theme_color_override("font_color", Color("#ffb3b1"))
	b.add_theme_color_override("font_hover_color", Color("#ffb3b1"))
	return b


static func _right(c: Array) -> HBoxContainer:
	var h := Ui.hbox(4, c)
	h.alignment = BoxContainer.ALIGNMENT_END
	return h


static func _stars(skill: float) -> String:
	var n := int(JS.round_js(skill / 2))
	return "★".repeat(n) + "☆".repeat(5 - n)


func _pl(pid: int) -> String:
	return sim.PL[pid].name


func _cn(cid: int) -> String:
	return sim.states[cid].name


## plName with the flag: the flag is a swatch of the country's colour until the flags are ported
func _place(pid: int, size: int = 14, bold: bool = true, flag: bool = true) -> HBoxContainer:
	var p: Dictionary = sim.PL[pid]
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(18, 12)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c: Variant = sim.states[p.cid].get("color")
	sw.color = Color(c) if c is String else (c if c is Color else Ui.MUTED)
	sw.visible = flag
	var h := Ui.hbox(5, [sw, _b(p.name, size) if bold else Ui.label(p.name, size)])
	return h


# ====================================================================== helpers of the windows
func _crew_need() -> Dictionary:
	var f := {}
	for r in D.ROLE:
		f[r] = 0
	for v in sim.CO.veh:
		var T: Dictionary = D.VT[v.t]
		f[T.role] += T.get("crew", 1)
	return f


func _crew_have(r: String) -> int:
	return int(sim.CO.staff.get(r, 0)) + (int(sim.CO.founder) if r == "driver" else 0)


static func _risk_w(r: float) -> Array:
	return ["Дуже високий", "bad"] if r > .75 else (["Високий", "bad"] if r > .5 else (["Середній", "warn"] if r > .3 else ["Низький", "good"]))


## coMonthPlan: what the end of the month will charge
func month_plan() -> Dictionary:
	var CO := sim.CO
	var wk: float = sim.wage_k(sim.me) * CO.wageLv * (1 - sim.msk("hro") * .08)
	var wage := 0.0
	for r in D.ROLE:
		wage += CO.staff.get(r, 0) * D.ROLE[r].w * wk
	var N := sim.staff_total()
	var office: float = JS.round_js(45 * JS.pow(N, 1.12) * sim.price_k(sim.me) * (1 - sim.msk("cfo") * .1))
	var mgmt := 0.0
	for id in CO.mgr:
		mgmt += CO.mgr[id].sal
	var rent := 0.0
	var mk := 0.0
	for h in CO.hubs:
		rent += sim.hub_rent_m(h)
		mk += h.get("mk", 0)
	var ins := 0.0
	if CO.ins:
		var c := 0.0
		for v in CO.veh:
			c += D.VT[v.t].cost
		ins = JS.round_js(500 + c * .0035)
	var interest := 0.0
	for l in CO.loans:
		interest += l.left * l.rate / 12
	if CO.cash < 0:
		interest += -CO.cash * .025
	return {"wage": wage, "office": office, "mgmt": mgmt, "rent": rent, "mk": mk, "ins": ins, "interest": interest}


## coAdvice: up to five lines of advice
func advice() -> Array:
	var CO := sim.CO
	var A := []
	var need := _crew_need()
	for r in D.ROLE:
		var lack: int = need[r] - _crew_have(r)
		if lack > 0:
			A.append(["bad", "Бракує персоналу: [b]%s[/b] — %d. Частина техніки стоїть без екіпажу. Наймайте у вікні «Персонал»." % [D.ROLE[r].n.to_lower(), lack]])
	if CO.cash < 0:
		A.append(["bad", "Рахунок у мінусі — овердрафт коштує 2,5% на місяць. Візьміть кредит, продайте зайву техніку або скоротіть витрати."])
	var lo: int = CO.veh.filter(func(v): return v.cond < 45).size()
	if lo:
		A.append(["warn", "%d од. техніки зношені (стан нижче 45%%): більше аварій і поломок. Ремонт — у вікні «Автопарк»." % lo])
	if CO.morale < 40:
		A.append(["warn", "Моральний дух %.0f/100 — ризик страйку й аварій. Підніміть зарплати або найміть HR-директора." % CO.morale])
	if sim.lic_ok().ok:
		A.append(["good", "Можна отримати ліцензію [b]«%s»[/b]!" % D.LIC[CO.tier + 1].n])
	if CO.tier >= 1 and not CO.veh.any(func(v): return D.VT[v.t].mode == "road"):
		A.append(["warn", "Ліцензія дозволяє міжміські рейси, але у вас немає фургона чи вантажівки."])
	if CO.tier >= 1 and CO.hubs.size() < 2:
		A.append(["", "Відкрийте хаб в іншому місті своєї країни: клацніть на країну на мапі й оберіть місто."])
	if CO.lm != null and CO.lm.get("stolen", 0) > 0 and not CO.mgr.has("cfo"):
		A.append(["warn", "Нез'ясовані втрати %s минулого місяця. Без фінансового директора ніхто не перевірить менеджерів." % Ui.usd(CO.lm.stolen)])
	if not CO.ins and CO.tier >= 2:
		A.append(["", "Без страховки кожна крадіжка чи аварія з вантажем лягає на вас. Увімкніть у вікні «Фінанси»."])
	if A.is_empty():
		A.append(["good", "Усе під контролем. Розширюйтеся: нові хаби, техніка, ліцензії."])
	return A.slice(0, 5)


# ====================================================================== coHome
func _home(body: VBoxContainer) -> void:
	var CO := sim.CO
	var lm: Variant = CO.lm
	var pr: float = sim.co_rev(lm) - sim.co_cost(lm) if lm != null else 0.0
	var hq: Dictionary = sim.PL[CO.hq]
	var cids := {}
	for h in CO.hubs:
		cids[sim.PL[h.pid].cid] = 1
	var where := Ui.hbox(4, [Ui.icon("pin", 14, Ui.FG2), Ui.label("Штаб: %s" % hq.name, 13, Ui.FG2)])
	where.mouse_filter = Control.MOUSE_FILTER_STOP
	where.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	where.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: goto_place.emit(CO.hq))
	var nh: int = CO.hubs.size()
	var sub := Ui.hbox(0, [where, Ui.label(", %s · %d %s · %d країн" % [_cn(hq.cid), nh, "хаб" if nh == 1 else "хаби", cids.size()], 13, Ui.FG2)])
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(48, 32)
	logo.draw.connect(func(): Hud.paint_logo(logo, sim))
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(Ui.hbox(10, [logo, Ui.vbox(2, [_b(CO.name, 16), sub])]))
	var rat: float = CO.rating
	body.add_child(_grid(4, [
		_stat("Гроші", Ui.usd(CO.cash), "вартість компанії " + Ui.usd(sim.co_value()), _tip("Гроші", "Готівка. Вартість компанії — гроші плюс техніка і хаби мінус кредити."), "bad" if CO.cash < 0 else ""),
		_stat("Рейтинг", "%.2f ★" % rat, _stars(rat * 2), _tip("Рейтинг", "Середня оцінка клієнтів. Вчасні й цілі доставки його піднімають, аварії, запізнення й крадіжки — опускають."), "good" if rat >= 4 else ("bad" if rat < 2.6 else "")),
		_stat("Досвід", Ui.grp(floor(CO.get("xp", 0))), "%s доставок · %d контрактів" % [Ui.grp(CO.deliv), CO.cdel], _tip("Досвід компанії", "Росте за кожну успішну доставку з біржі: більше за великі й багатоділянкові рейси, удвічі менше за запізнення. Маршрут, прокладений вручну, дає повний досвід, маршрут диспетчера-логіста — лише 8%. Потрібен для ліцензій.")),
		_stat("Прибуток / міс", Ui.usd(pr, true) if lm != null else "—", ("виручка " + Ui.usd(sim.co_rev(lm))) if lm != null else "перший місяць ще триває", _tip("Прибуток", "За минулий місяць."), "good" if pr >= 0 else "bad")]))
	body.add_child(_sect("Порадник"))
	for a in advice():
		body.add_child(_adv(a[0], a[1]))
	body.add_child(_sect("Ліцензії"))
	var lic := sim.lic_ok()
	var lv := Ui.vbox(6)
	for i in D.LIC.size():
		var l: Dictionary = D.LIC[i]
		if l.get("hide"):
			continue
		var got: bool = i <= CO.tier
		var cur: bool = i == CO.tier
		var nx: bool = i == CO.tier + 1
		var pill_t: String = "Поточна" if cur else ("Отримано" if got else ("Наступна" if nx else "%.1f★ · %s" % [l.rat, Ui.usd(l.cost)]))
		var head := Ui.hbox(10, [_tt("%d. %s" % [i, l.n], l.d, "check" if got else "lock", Ui.GOOD if got else (Ui.WARN if nx else Ui.MUTED)),
			Ui.pill(pill_t, "acc" if cur else ("good" if got else ("warn" if nx else "")))])
		var v := Ui.vbox(10, [head])
		if nx:
			var kv := GridContainer.new()
			kv.columns = 2
			kv.add_theme_constant_override("h_separation", 12)
			kv.add_theme_constant_override("v_separation", 6)
			for x in lic.r:
				var a := _icl("check" if x[0] else "lock", x[1], Ui.GOOD if x[0] else Ui.MUTED)
				a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				kv.add_child(a)
				var n := Ui.num(x[2], 13, Ui.GOOD if x[0] else Ui.FG)
				n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				kv.add_child(n)
			v.add_child(kv)
			var b := _btn("Отримати ліцензію · " + Ui.usd(l.cost), "pri sm" if lic.ok else "sm", "doc", func(): _do(sim.act_lic()), lic.ok)
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			v.add_child(b)
		lv.add_child(_blk(v, Ui.ACCENT if cur else (Color(241 / 255.0, 196 / 255.0, 83 / 255.0, .45) if nx else Ui.LINE), 1.0 if got or nx else .55))
	body.add_child(lv)
	_perm_sect(body)
	var ch := []
	for g in [["coins", "Гроші на кінець місяця", CO.hist.cash, Ui.WARM, true], ["chart", "Виручка за місяць", CO.hist.rev, Ui.ACCENT, false]]:
		var v := Ui.vbox(8, [_icl(g[0], g[1].to_upper(), Ui.MUTED, 10)])
		if g[2].size() > 1:
			v.add_child(MiniChart.make(g[2], g[3], g[4]))
		else:
			v.add_child(_note("Графік з'явиться через пару місяців."))
		ch.append(_blk(v))
	body.add_child(_grid(2, ch))
	body.add_child(_sect("Досягнення"))
	var ms := []
	for m in CO_MS:
		var ok: bool = CO.ms.has(m[0])
		var it := _tt(m[1], m[2], "star" if ok else "lock", Ui.GOOD if ok else Ui.MUTED)
		it.modulate.a = 1.0 if ok else .45
		ms.append(it)
	body.add_child(_grid(2, ms))
	body.add_child(_sect("Логістичний лікбез"))
	var my: Array = CO_MYTH[(sim.date.m + sim.date.y) % CO_MYTH.size()]
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 4)
	g.add_child(Ui.label("МІФ", 10, Ui.BAD, Ui.font("mono", 600, 1)))
	var mt := Ui.rich("[s]%s[/s]" % my[0], 13)
	g.add_child(mt)
	g.add_child(Ui.label("ФАКТ", 10, Ui.GOOD, Ui.font("mono", 600, 1)))
	g.add_child(Ui.rich(my[1], 13, Ui.FG))
	var mp := PanelContainer.new()
	mp.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(12, 10, 12, 10)))
	mp.add_child(g)
	body.add_child(mp)


## permSect: permits for special cargo
func _perm_sect(body: VBoxContainer) -> void:
	var CO := sim.CO
	body.add_child(_sect("Дозволи на спецвантажі"))
	body.add_child(Ui.hint("Небезпечні, цінні й фармацевтичні вантажі платять більше, але потрібна [b]ліцензія на рік[/b]. Без неї такі замовлення на біржі заблоковані. Продовження автоматичне, якщо вистачає грошей. Ціна залежить від країни штабу й ситуації у світі."))
	var v := Ui.vbox(6)
	for p in D.PERM:
		var P: Variant = CO.get("perm", {}).get(p.id)
		var ok := sim.perm_ok(p.id)
		var lock: bool = CO.tier < p.tier
		var f := sim.perm_fee(p.id)
		var left: int = int(JS.round_js(P.until - sim.day)) if P != null else 0
		var right: Control = Control.new()
		if ok:
			right = Ui.pill("діє ще %d дн." % left, "warn" if left < 31 else "good")
		elif lock:
			right = Ui.pill("Ліцензія «%s»" % D.LIC[p.tier].n, "", "lock")
		elif P != null:
			right = Ui.pill("сплила", "bad")
		var c := Ui.vbox(8, [Ui.hbox(10, [_tt(p.n, p.d, p.ic, Ui.GOOD if ok else (Ui.MUTED if lock else Ui.ACCENT)), right])])
		if not lock:
			var id: String = p.id
			var row := Ui.hbox(8, [_note("%s на рік" % Ui.usd(f))])
			if P != null:
				row.add_child(_toggle(P.get("auto", false), func():
					sim.act_perm_auto(id)
					_do({}), _tip("Автопродовження", "Списати оплату автоматично, коли ліцензія спливе.")))
			row.add_child(_btn("Продовжити на рік" if ok else "Купити на рік", "sm" if ok else "pri sm", "doc", func(): _do(sim.act_perm(id)), CO.cash >= f))
			c.add_child(row)
		v.add_child(_blk(c, Color(91 / 255.0, 214 / 255.0, 140 / 255.0, .45) if ok else Ui.LINE, .55 if lock else 1.0))
	body.add_child(v)


## ACT.coMove: the fleet window closes and the map shows the hubs to pick from
func move(v: Dictionary) -> void:
	var T: Dictionary = D.VT[v.t]
	if T.mode != "road" and T.mode != "rail":
		_do({"tone": "warn", "t": "Лише наземна техніка", "d": "Переміщувати між хабами можна машини й потяги"})
		return
	if not gr_ok("move"):
		return
	var ts := sim.mv_targets(v)
	if not ts.any(func(t): return t.why == ""):
		_do({"tone": "warn", "t": "Немає куди перемістити", "d": "Відкрийте ще один хаб — тоді техніку можна буде перевести туди" if sim.CO.hubs.size() < 2 else "Усі інші хаби недоступні: інший континент, немає сполучення або вони заповнені"})
		return
	move_vehicle.emit(v)


## grOK: some features open with a grade of experience; a toast says how far it is
func gr_ok(f: String) -> bool:
	var need: int = GR_FEAT.get(f, 0)
	if sim.co_grade() >= need:
		return true
	var G: Dictionary = D.GRADES[need]
	_do({"tone": "warn", "t": "Потрібен грейд «%s»" % G.n, "d": "Ще %s досвіду. Досвід дають успішні доставки, особливо з маршрутом, прокладеним вручну." % Ui.grp(maxf(0, G.xp - floor(sim.CO.get("xp", 0))))})
	return false


## consOrders: the chosen orders still on the board
func cons_orders() -> Array:
	var out := []
	for id in st.cons:
		for k in sim.CO.board:
			if k.id == id:
				out.append(k)
	st.cons = out.map(func(k): return k.id)
	return out


## ACT.consAdd: an order in or out of the consolidated trip
func cons_add(id: int) -> void:
	var k: Variant = null
	for x in sim.CO.board:
		if x.id == id:
			k = x
	if not sim.cons_ok(k):
		return
	if st.cons.has(id):
		st.cons.erase(id)
		_do({})
		return
	if not gr_ok("cons"):
		return
	var ks := cons_orders()
	if ks.size() and ks[0].mode != k.mode:
		_do({"tone": "warn", "t": "Інший вид транспорту", "d": "У збірному рейсі — лише %s: одна техніка везе всі замовлення" % String(Planner.LP_N[ks[0].mode]).to_lower()})
		return
	if st.cons.size() >= 6:
		_do({"tone": "warn", "t": "Забагато замовлень", "d": "У збірний рейс — до 6 замовлень"})
		return
	st.cons.append(id)
	_do({})


func _cons_btn(k: Dictionary, no_veh: bool, why: String) -> Button:
	var inn: bool = st.cons.has(k.id)
	var id: int = k.id
	if no_veh and not inn:
		var b := _btn("До збірного рейсу", "sm", "plus", func(): pass, true, "Збірний рейс недоступний\n%s. Дочекайтеся, поки техніка звільниться, або купіть ще в «Автопарку»." % why)
		b.modulate.a = .45
		b.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
		return b
	return _btn("У збірному" if inn else "До збірного рейсу", "pri sm" if inn else "sm", "check" if inn else "plus", func(): cons_add(id), true, CONS_TIP)


## consPanel: the chosen orders on top of the board
func _cons_panel() -> Control:
	var ks := cons_orders()
	if ks.is_empty():
		return null
	var m: String = ks[0].mode
	var tons := 0.0
	var vol := 0.0
	for k in ks:
		tons += k.tons
		vol += sim.k_vol(k)
	var why := ""
	for k in ks:
		if k.get("minR", 0) and sim.CO.rating < k.minR:
			why = "Замовник хоче рейтинг %.1f+" % k.minR
			break
		var nd: Array = sim.perm_need(sim.cargo_i[k.cg], m).filter(func(x): return not sim.perm_ok(x))
		if nd.size():
			why = "Потрібна ліцензія «%s»" % sim.perm_i[nd[0]].n
			break
	var own: Array = sim.CO.veh.filter(func(v): return D.VT[v.t].mode == m and (v.st == "idle" or sim.is_ret_v(v)) and not v.get("resv"))
	if why == "" and own.is_empty():
		why = "Немає вільної техніки: " + String(D.MODE_N[m]).to_lower()
	var by_city := {}
	for k in ks:
		var c: Array = by_city.get(k.from, [0.0, 0.0])
		by_city[k.from] = [c[0] + k.tons, c[1] + sim.k_vol(k)]
	var need_t := 0.0
	var need_v := 0.0
	for c in by_city.values():
		need_t = maxf(need_t, c[0])
		need_v = maxf(need_v, c[1])
	if why == "" and own.size() and not own.any(func(v): return D.VT[v.t].cap >= need_t and D.VT[v.t].get("vol", 1e9) >= need_v):
		why = "Немає вільної техніки, що вмістить %s т і %s м³ разом — %s" % [Ui.loc(need_t, 1), Ui.loc(need_v, 1), "усі замовлення завантажуються в одному місті" if by_city.size() == 1 else "стільки забирається в одному місті"]
	var big := {"cap": 0, "vol": 0, "n": ""}
	for v in own:
		if D.VT[v.t].cap > big.cap:
			big = D.VT[v.t]
	var t := Ui.hbox(6, [Ui.icon(MODE_IC[m], 16), _b("Збірний рейс · %s · %d замовлення" % [Planner.LP_N[m], ks.size()])])
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := Ui.vbox(8, [Ui.hbox(8, [t, _btn("Скасувати", "sm", "close", func():
		st.cons = []
		_do({}))])])
	for k in ks:
		var cg: Dictionary = sim.cargo_i[k.cg]
		var id: int = k.id
		var row := _lrow(cg.ic, Ui.vbox(2, [_b("%s → %s" % [_pl(k.from), _pl(k.to)], 13), _note("%s · %s т · %s м³ · дедлайн %s · %s" % [cg.n, Ui.loc(k.tons), Ui.loc(sim.k_vol(k), 1), Ui.days(k.dlDays), Ui.usd(k.pay)], Ui.FG2, 12)]),
			_btn("", "sm", "close", func(): cons_add(id), true, "Прибрати"))
		row.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(8, 5, 8, 5)))
		v.add_child(row)
	var tx := "Разом %s т · %s м³" % [Ui.loc(tons, 1), Ui.loc(vol, 1)]
	if big.cap:
		tx += " · найбільша вільна: %s (%s т, %s м³)" % [big.n, Ui.loc(big.cap), Ui.loc(big.get("vol", 0))]
	v.add_child(_note(tx + ". Порядок зупинок і дорогу ви прокладаєте самі: забрати можна в будь-якому порядку, але доставити — лише те, що вже в кузові."))
	if why != "":
		v.add_child(_icl("alert", why, Ui.BAD))
	var go := _btn("Додайте ще замовлення" if ks.size() < 2 else "Прокласти маршрут збірного рейсу", "pri", "road", func(): plan_order.emit(sim.cons_make(cons_orders())), why == "" and ks.size() >= 2)
	go.size_flags_horizontal = Control.SIZE_FILL
	v.add_child(go)
	return _blk(v, Color(Ui.ACCENT, .55))


# ====================================================================== coJobs
func _plan_line(k: Dictionary, P: Dictionary) -> RichTextLabel:
	var what: String
	if P.get("chain"):
		what = " → ".join(P.chain.map(func(q): return D.VT[q.t].n + (" ×%d" % q.n if q.n > 1 else "")))
	else:
		what = D.VT[P.t].n + (" ×%d" % P.n if P.n > 1 else "")
	var s := what + " · "
	if P.lead > .05:
		s += "перегін " + Ui.km(P.lead) + " · "
	s += "доставка за " + Ui.days(P.tot) + " "
	s += "[color=#f0625f]— запізнення![/color]" if P.late else "[color=#5bd492]— вчасно[/color]"
	s += " · пальне " + Ui.usd(P.fuel) + " · прибуток ≈ [b][color=%s]%s[/color][/b]" % ["#5bd492" if P.profit > 0 else "#f0625f", Ui.usd(P.profit, true)]
	return Ui.rich(s, 13)


func _board_card(k: Dictionary) -> PanelContainer:
	var CO := sim.CO
	var A: Dictionary = sim.PL[k.from]
	var B: Dictionary = sim.PL[k.to]
	var cg: Dictionary = sim.cargo_i[k.cg]
	Perf.begin("co_plan")
	var P: Dictionary = sim.co_plan(k)
	Perf.end("co_plan")
	var info := Ui.vbox(2)
	info.add_child(Ui.hbox(6, [_place(k.from), Ui.label("→", 14), _place(k.to)]))
	var vol: float = k.tons * cg.get("v", 3)
	info.add_child(_icl(cg.ic, "%s · %s т · %s м³ · %s%s" % [cg.n, Ui.loc(k.tons), Ui.loc(vol, 1), Ui.km(k.len), " · кордон" if A.cid != B.cid else ""]))
	if k.get("fs"):
		info.add_child(_icl("building", "%s → %s" % [k.fs, k.ft]))
	if k.get("pIn") != null:
		info.add_child(_icl("handshake", "Відправник сам довезе вантаж із міста %s до міста %s" % [_pl(k.src), _pl(k.pIn)]))
	if k.get("legs"):
		var parts := []
		for L in k.legs:
			parts.append(_pl(L.a))
		var lh := Ui.hbox(4)
		for i in k.legs.size():
			lh.add_child(_icl(MODE_IC[k.legs[i].m], parts[i] + " ›"))
		lh.add_child(Ui.label(_pl(k.to), 13, Ui.FG2))
		info.add_child(lh)
	if k.get("pOut") != null:
		info.add_child(_icl("handshake", "Одержувач сам забере вантаж у місті %s і довезе до %s" % [_pl(k.pOut), _pl(k.dst)]))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pay := Ui.num(Ui.usd(k.pay), 16)
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var dl := Ui.label("термін " + Ui.days(k.dlDays), 13, Ui.FG2)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var mi := Ui.icon(MODE_IC[k.mode], 18, Ui.ACCENT)
	mi.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var top := Ui.hbox(10, [mi, info, Ui.vbox(2, [pay, dl])])
	# pills
	var pills := HFlowContainer.new()
	pills.add_theme_constant_override("h_separation", 6)
	pills.add_theme_constant_override("v_separation", 6)
	var add_p := func(t: String, tone: String, ic: String, tip: String = ""):
		var p := Ui.pill(t, tone, ic)
		p.tooltip_text = tip
		pills.add_child(p)
	if k.get("prem"):
		add_p.call("Терміново", "warn", "bolt", _tip("Термінове замовлення", "Відкривається з грейду «Диспетчер». Дедлайн на третину тісніший, зате оплата +40–60%. На біржі висить лише 2–4 дні."))
	if k.get("vip"):
		add_p.call("Ключовий клієнт", "acc", "crown", _tip("Ключовий клієнт", "Відкривається з грейду «Логіст». Великий постійний відправник: оплата +35%."))
	var rw := _risk_w(k.risk)
	add_p.call("Ризик: " + rw[0].to_lower(), rw[1], "shield", _tip("Ризик крадіжки чи нападу", "Залежить від країн відправки й призначення (бюрократія, стабільність, війна), від того, наскільки вантаж привабливий для крадіїв (електроніка, ліки, авто — вище), і від піратських вод на морському плечі. Чим вищий ризик — тим дорожче платять. Директор з безпеки знижує шанс інциденту."))
	if k.get("minR", 0):
		add_p.call("Вимога %.1f★" % k.minR, "acc" if CO.rating >= k.minR else "bad", "star")
	if cg.get("aid"):
		add_p.call("Зона конфлікту", "warn", "heart")
	for id in sim.perm_need(cg, k.mode):
		var pn: Dictionary = sim.perm_i[id]
		var t: String = "Небезпечний вантаж" if id in ["adr", "imdg", "dgr"] else {"gdp": "Фарма", "valu": "Цінності", "expl": "Вибухівка"}.get(id, "Радіоактивний")
		add_p.call(t, "good" if sim.perm_ok(id) else "bad", pn.ic, _tip(pn.n, pn.d))
	if cg.get("reefer") and k.mode == "sea":
		add_p.call("Рефконтейнер", "", "leaf")
	add_p.call("%d дн. на біржі" % maxi(0, int(k.exp - sim.day)), "", "info", _tip("Термін пропозиції", "Скільки днів замовлення ще висітиме на біржі. Потім замовник віддасть його іншому перевізнику і воно зникне. Це не дедлайн доставки — дедлайн рахується з моменту, коли ви приймете замовлення."))
	var v := Ui.vbox(8, [top, pills])
	var id: int = k.id
	if P.ok:
		var pl := _plan_line(k, P)
		v.add_child(pl)
		var bs := Ui.hbox(8)
		if sim.cons_ok(k):
			bs.add_child(_cons_btn(k, false, ""))
		bs.add_child(_btn("Прокласти маршрут", "pri sm", "road", func(): plan_order.emit(k)))
		v.add_child(bs)
	else:
		var why: String = P.why
		var quiet: bool = why.begins_with("Замовник хоче рейтинг") or why.begins_with("Немає вільної техніки") \
			or (sim.perm_need(cg, k.mode).any(func(x): return not sim.perm_ok(x)) and why.begins_with("Потрібна ліцензія «"))
		if not quiet:
			v.add_child(_icl("alert", why, Ui.WARN))
		var bs := Ui.hbox(8)
		if sim.cons_ok(k):
			bs.add_child(_cons_btn(k, why.begins_with("Немає вільної техніки"), why))
		bs.add_child(_btn("Прокласти маршрут", "sm", "road", func(): pass, false, _tip("Маршрут не прокласти", why + ".")))
		v.add_child(bs)
	return _blk(v)


## a multi-drop flight on the board (08r-multi.js)
func _multi_card(k: Dictionary) -> PanelContainer:
	var cg: Dictionary = sim.cargo_i[k.cg]
	var air := Color8(214, 150, 255)
	var mi := Ui.icon("plane", 18, air)
	mi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var info := Ui.vbox(2, [Ui.hbox(6, [_b("Збірний авіарейс з"), _place(k.from)]), _icl(cg.ic, "%s · %s т · %d країни · один літак" % [cg.n, Ui.loc(k.tons), k.multi.size()])])
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pay := Ui.num(Ui.usd(k.pay), 16)
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ex := Ui.label("%d дн. на біржі" % maxi(0, int(k.exp - sim.day)), 13, Ui.FG2)
	ex.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var v := Ui.vbox(8, [Ui.hbox(10, [mi, info, Ui.vbox(2, [pay, ex])])])
	var dv := Ui.vbox(4)
	for d in k.multi:
		var l := Ui.hbox(6, [_place(d.to, 14, false), Ui.label(Ui.loc(d.tons) + " т", 13, Ui.FG2)])
		var r := Ui.rich(("[color=#f0625f]критично[/color] · " if d.get("crit") else "") + "до %s · %s" % [Ui.days(d.dl), Ui.usd(d.pay)], 13)
		r.size_flags_horizontal = Control.SIZE_SHRINK_END
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dv.add_child(Ui.hbox(8, [l, r]))
	v.add_child(dv)
	var id: int = k.id
	var n := _note("У кожної країни свій термін — порядок посадок обираєте ви.")
	v.add_child(Ui.hbox(8, [n, _btn("Прокласти маршрут", "pri sm", "road", func(): plan_order.emit(k)), _btn("", "sm", "trash", func():
		sim.act_decline(id)
		_do({}), true, "Прибрати")]))
	var b := _blk(v, Color(air, .45))
	return b


func _jobs(body: VBoxContainer) -> void:
	var CO := sim.CO
	if CO.tier < 1:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE_HI, 1, Vector4(28, 28, 28, 28)))
		var c := Ui.vbox(8, [Ui.icon("lock", 40, Ui.MUTED), Ui.heading("Біржа вантажів закрита"), _note("Потрібна ліцензія «%s»." % D.LIC[1].n)])
		c.alignment = BoxContainer.ALIGNMENT_CENTER
		for x in c.get_children():
			x.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		p.add_child(c)
		body.add_child(p)
		return
	var jf: String = st.jfl
	var m_ok := func(m): return jf == "all" or m == jf
	var bd: Array = CO.board.filter(func(k): return m_ok.call(k.mode))
	var tds: Array = CO.tenders.filter(func(t): return m_ok.call(D.VT[t.t].mode))
	var tof: Array = CO.get("toff", []).filter(func(o): return o.exp > sim.day and m_ok.call(D.VT[o.t].mode))
	var nveh := 0
	for t in CO.tenders:
		nveh += t.n
	body.add_child(_grid(3, [
		_stat("Досвід", Ui.grp(floor(CO.get("xp", 0))), "за маршрути, прокладені вручну", _tip("Досвід", "Ручне прокладання дає повний досвід, диспетчер-логіст — лише 8%.")),
		_stat("На біржі", str(CO.board.size()), "до %d одночасно" % sim.co_board_max(), _tip("Біржа", "Замовлення з'являються в містах, де у вас є хаби. Більше хабів і складів, комерційний директор — більше замовлень.")),
		_stat("Тендери", str(CO.tenders.size()), "%d од. техніки зайнято" % nveh, _tip("Тендери", "Довгострокові контракти: стабільний дохід щомісяця."))]))
	body.add_child(_mode_seg("jfl", func(m): return CO.jobs.size() + CO.board.size() if m == "all" else CO.jobs.filter(func(j): return j.mode == m).size() + CO.board.filter(func(k): return k.mode == m).size()))
	body.add_child(_sect("Біржа вантажів"))
	body.add_child(_tg_row("Автодиспетчеризація", "Диспетчер-логіст сам бере замовлення й прокладає маршрути. Досвіду компанії за такі рейси майже немає." if CO.mgr.has("cto") else "Потрібен диспетчер-логіст (вікно «Персонал»).", CO.auto, func(): _do(sim.act_auto())))
	var cp := _cons_panel()
	if cp != null:
		body.add_child(cp)
	if bd.size():
		bd.sort_custom(func(a, b): return a.id > b.id)
		var n: int = maxi(st.bmore, 15)
		var v := Ui.vbox(8)
		for k in bd.slice(0, n):
			v.add_child(_multi_card(k) if k.get("multi") else _board_card(k))
		body.add_child(v)
		if bd.size() > n:
			body.add_child(_more(bd.size() - n, "bmore"))
	else:
		body.add_child(_note("Нових замовлень%s поки немає — вони з'являються щодня." % (" цього типу" if jf != "all" else "")))
	body.add_child(_sect("Тендери"))
	body.add_child(Ui.hint("[b]Як працюють тендери.[/b] Компанія-замовник наймає вашу техніку з екіпажами на кілька місяців. Поки діє контракт, ці машини не беруть інших рейсів, а ви щомісяця отримуєте фіксовану оплату за кожну одиницю. Нові пропозиції з'являються на початку місяця з ліцензією «Вантажні перевезення» і діють 3–6 тижнів. Щоб підписати тендер, потрібна вільна техніка потрібного типу.", "info"))
	if CO.tier < 2:
		body.add_child(_icl("lock", "Тендери відкриються з ліцензією «Вантажні перевезення».", Ui.FG2))
	if tds.size():
		body.add_child(Ui.lbl("Діючі контракти"))
		for t in tds:
			var T: Dictionary = D.VT[t.t]
			body.add_child(_lrow(T.ic, Ui.vbox(2, [_b("Контракт " + t.n_), _note("%d × %s · ще %d міс." % [t.n, T.n.to_lower(), t.left])]), Ui.num(Ui.usd(t.pay * t.n) + "/міс", 14, Ui.GOOD)))
	if CO.tier >= 2:
		if tof.size():
			body.add_child(Ui.lbl("Пропозиції"))
			for o in tof:
				body.add_child(_tender_card(o))
		else:
			body.add_child(_note("Нових пропозицій%s зараз немає — наступні з'являться на початку місяця." % (" цього типу" if jf != "all" else "")))


func _tender_card(o: Dictionary) -> PanelContainer:
	var T: Dictionary = D.VT[o.t]
	var idle: int = sim.CO.veh.filter(func(v): return v.t == o.t and v.st == "idle").size()
	var ok: bool = idle >= o.n
	var pay := Ui.num(Ui.usd(o.pay * o.n) + "/міс", 16)
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var tot := Ui.label("разом " + Ui.usd(o.pay * o.n * o.months), 13, Ui.FG2)
	tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var top := Ui.hbox(10, [_tt("Контракт " + o.n_, "%d × %s з екіпажами · %d міс. · пропозиція діє ще %d дн." % [o.n, T.n.to_lower(), o.months, maxi(1, int(JS.round_js(o.exp - sim.day)))], T.ic), Ui.vbox(2, [pay, tot])])
	var id: int = o.id
	var st_l := _icl("check" if ok else "alert", ("Вільно %d з %d потрібних" % [idle, o.n]) if ok else ("Потрібно %d, вільно %d: купіть техніку в «Автопарку»" % [o.n, idle]), Ui.GOOD if ok else Ui.WARN)
	st_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := Ui.hbox(8, [st_l, _btn("", "sm", "trash", func():
		sim.CO.toff = sim.CO.toff.filter(func(x): return x.id != id)
		_do({}), true, "Відхилити"), _btn("Підписати", "pri sm" if ok else "sm", "doc", func():
		var why := sim.co_tender_take(id)
		_do(SimActions._toast("warn", "Тендер не підписано", why) if why != "" else {}), ok)])
	return _blk(Ui.vbox(8, [top, row]))


func _more(left: int, key: String) -> Button:
	var b := _btn("Показати ще %d з %d" % [mini(15 if key != "fmore" else 120, left), left], "sm", "", func():
		st[key] = maxi(st[key], 15 if key != "fmore" else 120) + (15 if key != "fmore" else 120)
		_do({}))
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return b


# ====================================================================== coTrips
func _job_row(j: Dictionary) -> PanelContainer:
	var e: float = sim.co_now() - j.t0
	var stt := sim.co_job_state(j, e)
	var T: Dictionary = D.VT[j.t]
	var cg_n: String = "повернення в хаб" if j.get("ret") else sim.cargo_i[j.k.cg].n
	var prog := clampf(e / j.tot, 0, 1)
	var left := maxf(0, j.tot - e)
	var late_by: float = sim.day + left - j.dl
	var head := Ui.hbox(8, [_place(j.k.from, 14, true, false), Ui.label("→", 14), _place(j.k.to, 14, true, false), Ui.spacer(),
		Ui.label("%s%s · %s · %s т" % [T.n, (" ×%d" % j.n) if j.get("n", 1) > 1 else "", cg_n, j.k.tons], 13, Ui.FG2)])
	var bad: bool = j.get("hold", 0) > 0 or j.get("lost", false)
	var mt := _meter(prog, Ui.BAD if bad else Ui.ACCENT)
	var parts := []
	if j.get("hold", 0) > 0:
		parts.append("[color=#f0625f]%s · ще %d дн.[/color]" % ["Захоплено піратами" if j.get("seized") else "Затримано", j.hold])
	else:
		var col := ""
		if stt.get("inc") != null:
			col = "#f0625f" if SimIncidents.INC_RED.has(stt.inc.k) else "#f1c453"
		var t: String = "%s · залишилось %s" % [stt.ph, Ui.days(left)]
		parts.append(("[color=%s]%s[/color]" % [col, t]) if col != "" else t)
	if late_by > .05:
		parts.append("[color=#f0625f]запізнення %.1f дн.[/color]" % late_by)
	if j.get("lost"):
		parts.append("[color=#f0625f]вантаж втрачено[/color]")
	elif j.get("dmg", 0) > .02:
		parts.append("[color=#f1c453]пошкоджено %.0f%%[/color]" % (j.dmg * 100))
	var mid := Ui.vbox(5, [head, mt, Ui.rich(" · ".join(parts), 13)])
	var row := _lrow(T.ic, mid, Ui.num(Ui.usd(j.k.pay), 14))
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: select_job.emit(j))
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE_HI, 1, Vector4(12, 10, 12, 10))))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(12, 10, 12, 10))))
	return row


func _trips(body: VBoxContainer) -> void:
	var CO := sim.CO
	var jf: String = st.jfl
	var m_ok := func(m): return jf == "all" or m == jf
	var jobs: Array = CO.jobs.filter(func(j): return m_ok.call(j.mode))
	var last: Array = CO.last.filter(func(l): return m_ok.call(l.mode))
	var nret: int = CO.jobs.filter(func(j): return j.get("ret")).size()
	body.add_child(_grid(3, [
		_stat("У дорозі", str(CO.jobs.size() - nret), "%d од. техніки" % CO.veh.filter(func(v): return v.st == "trip").size(), _tip("Рейси", "Техніка, що зараз везе вантаж або їде по нього.")),
		_stat("Повертаються в хаб", str(nret), "порожні пробіги додому"),
		_stat("Доставлено", Ui.grp(CO.cdel), Ui.grp(CO.tons) + " т")]))
	body.add_child(_mode_seg("jfl", func(m): return CO.jobs.size() if m == "all" else CO.jobs.filter(func(j): return j.mode == m).size()))
	body.add_child(_sect("У дорозі · %d" % CO.jobs.size()))
	jobs.sort_custom(func(a, b): return a.t0 > b.t0)
	var n: int = maxi(st.jmore, 15)
	if jobs.size():
		var v := Ui.vbox(6)
		for j in jobs.slice(0, n):
			v.add_child(_job_row(j))
		body.add_child(v)
		if jobs.size() > n:
			body.add_child(_more(jobs.size() - n, "jmore"))
	else:
		body.add_child(_note("Немає активних рейсів%s." % (" цього типу" if jf != "all" else "")))
	if last.size():
		body.add_child(_sect("Останні доставки"))
		var rows := []
		for l in last.slice(0, 10):
			rows.append([Ui.label(Ui.date_str(l.d), 13, Ui.FG2), _icl(MODE_IC[l.mode], "%s → %s" % [_pl(l.from), _pl(l.to)], Ui.FG),
				Ui.label(sim.cargo_i[l.cg].n, 13, Ui.FG2), Ui.num(Ui.usd(l.pay, true), 13, _tone_col(l.get("tone", "")))])
		body.add_child(_table_rows(rows, [["", 120, false], ["", 0, false], ["", 150, false], ["", 90, true]]))


static func _table_rows(rows: Array, cols: Array) -> VBoxContainer:
	var v := Ui.vbox(0)
	for r in rows:
		v.add_child(_tr(r, cols, 8))
	return v


# ====================================================================== coFleet
func _fleet(body: VBoxContainer) -> void:
	var CO := sim.CO
	var ff: String = st.ffl
	var f_ok := func(t): return ff == "all" or D.VT[t].mode == ff
	var groups := {}
	var order := []
	for v in CO.veh:
		if not f_ok.call(v.t):
			continue
		var k := "%s:%s:%s" % [v.t, v.loc, v.st]
		if not groups.has(k):
			groups[k] = []
			order.append(k)
		groups[k].append(v)
	var rows: Array = order.map(func(k): return groups[k])
	rows.sort_custom(func(a, b): return D.VT[b[0].t].cost < D.VT[a[0].t].cost)
	var val := 0.0
	var cs := 0.0
	for v in CO.veh:
		val += D.VT[v.t].cost * (.35 + .4 * v.cond / 100)
		cs += v.cond
	body.add_child(_grid(3, [
		_stat("Техніка", str(CO.veh.size()), "%d вільні" % CO.veh.filter(func(v): return v.st == "idle").size()),
		_stat("Вартість парку", Ui.usd(val), "за ринковою оцінкою"),
		_stat("Середній стан", "%.0f%%" % (cs / CO.veh.size() if CO.veh.size() else 100.0), "зношена техніка частіше ламається", _tip("Стан техніки", "Знижується з кожним кілометром. Нижче 45% — більше аварій і поломок, ризик штрафу на техогляді."))]))
	var hubs := []
	for h in CO.hubs:
		hubs.append([h.pid, _pl(h.pid), "building"])
	var buy_at: int = CO.get("buyAt", CO.hq) if CO.get("buyAt") != null else CO.hq
	var mseg := Ui.seg([[0, "Економне"], [1, "Стандартне"], [2, "Преміальне"]], CO.maint, func(i):
		sim.act_maint(i)
		_do({}))
	var dd := _dd(hubs, buy_at, func(pid):
		sim.act_buy_at(pid)
		_do({}))
	dd.custom_minimum_size.x = 200
	var left := Ui.vbox(6, [Ui.lbl("Обслуговування"), mseg])
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(Ui.hbox(12, [left, Ui.vbox(6, [Ui.lbl("Нова техніка прибуває в"), dd])]))
	body.add_child(_note("Економне: дешевше утримання, але техніка зношується швидше й частіше ламається. Преміальне — навпаки."))
	body.add_child(_mode_seg("ffl", func(m): return CO.veh.size() if m == "all" else CO.veh.filter(func(v): return D.VT[v.t].mode == m).size()))
	body.add_child(_sect("Ваша техніка"))
	var ST := {"idle": ["Вільна", "good"], "trip": ["У рейсі", "acc"], "tender": ["Тендер", "warn"]}
	var trs := []
	var nmax: int = st.fmore
	for g in rows.slice(0, nmax):
		var v: Dictionary = g[0]
		var Ty: Dictionary = D.VT[v.t]
		var cond := 0.0
		for x in g:
			cond += x.cond
		cond /= g.size()
		var name_c := Ui.hbox(6, [Ui.icon(Ty.ic, 16, Ui.FG), _b(Ty.n, 13)])
		if g.size() > 1:
			name_c.add_child(Ui.pill("×%d" % g.size()))
		if Ty.mode == "road" or Ty.mode == "rail":
			var home: Variant = v.get("home")
			var mtip := _tip("Перемістити в інший хаб", "Покаже на мапі всі ваші хаби — клікніть, щоб приписати техніку туди. Лише по дорозі%s: на інший континент не перемістити.%s" % [" (залізниці)" if Ty.mode == "rail" else "", (" Зараз приписана: %s." % _pl(home)) if home != null else ""])
			var mb := _btn("", "sm", "updown", func(): move(v), true, mtip)
			mb.custom_minimum_size = Vector2(0, 22)   # .btn.sm.icon: padding 3px 5px
			for k in ["normal", "hover", "pressed"]:
				var sb: StyleBoxFlat = mb.get_theme_stylebox(k).duplicate()
				sb.content_margin_left = 5
				sb.content_margin_right = 5
				mb.add_theme_stylebox_override(k, sb)
			mb.add_theme_constant_override("icon_max_width", 14)
			name_c.add_child(mb)
		var acts := _right([])
		if v.st == "idle":
			var t: String = v.t
			var loc: int = v.loc
			if cond < 99:
				acts.add_child(_btn("Ремонт", "sm", "gear", func(): _do(sim.act_repair(t, loc)), true, "≈ " + Ui.usd(sim.repair_cost(t, loc))))
			acts.add_child(_btn("Продати", "sm", "coins", func(): _do(sim.act_sell(t, loc)), true, _tip("Продати одну", "≈ " + Ui.usd(Ty.cost * (.25 + .35 * v.cond / 100)))))
		var stv: Array = ST.get(v.st, ["—", ""])
		var pc := Ui.hbox(0, [Ui.pill(stv[0], stv[1])])
		trs.append([name_c, Ui.label("в дорозі" if v.st == "trip" else _pl(v.loc), 13, Ui.FG2), _meter(cond / 100, Ui.GOOD if cond > 65 else (Ui.WARN if cond > 40 else Ui.BAD)), pc, acts])
	body.add_child(_table([["Тип", 0, false], ["Де", 100, false], ["Стан", 100, false], ["Статус", 76, false], ["Дії", 180, true]], trs, "Техніки немає."))
	if rows.size() > nmax:
		body.add_child(_more(rows.size() - nmax, "fmore"))
	body.add_child(_sect("Купити"))
	var types: Array = D.VT.keys().filter(func(t): return f_ok.call(t))
	types.sort_custom(func(a, b): return D.VT[a].tier < D.VT[b].tier or (D.VT[a].tier == D.VT[b].tier and D.VT[a].cost < D.VT[b].cost))
	var cards := []
	for t in types:
		var T: Dictionary = D.VT[t]
		var lock: bool = CO.tier < T.tier
		var sub: String = D.MODE_N[T.mode]
		if T.get("cap"):
			sub += " · до %s т" % Ui.loc(T.cap)
		if T.get("vol"):
			sub += " · %s м³" % Ui.grp(T.vol)
		if T.get("loc"):
			sub += " · доставка по місту"
		var price := Ui.num(Ui.usd(T.cost), 14)
		price.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var c := Ui.vbox(6, [Ui.hbox(10, [_tt(T.n, sub, T.ic), price]),
			_note("%s Екіпаж: %d (%s). Утримання %s/міс." % [T.d, T.get("crew", 1), D.ROLE[T.role].n.to_lower(), Ui.usd(T.up * 30)])])
		if lock:
			c.add_child(Ui.hbox(0, [Ui.pill("Ліцензія «%s»" % D.LIC[T.tier].n, "", "lock")]))
		else:
			var tt: String = t
			c.add_child(Ui.hbox(0, [_btn("Купити", "pri sm" if CO.cash >= T.cost else "sm", "plus", func(): _do(sim.act_buy(tt)), CO.cash >= T.cost)]))
		cards.append(_blk(c, Ui.LINE, .5 if lock else 1.0))
	body.add_child(_grid(2, cards))
	_upg_sect(body, ff)


## upgSect: upgrades of the company
func _upg_sect(body: VBoxContainer, ff: String) -> void:
	var CO := sim.CO
	var m: Variant = ff if ff != "all" else null
	body.add_child(_sect("Модернізація"))
	var cards := []
	for u in D.UPG:
		if m != null and u.get("fx") != null and not u.fx.has(m) and not u.get("rep") and not u.get("brk"):
			continue
		var got := sim.has_u(u.id)
		var lock: bool = CO.tier < u.tier
		var c := sim.upg_cost(u)
		var head := Ui.hbox(8, [Ui.icon(u.ic, 18, Ui.GOOD if got else Ui.ACCENT), _b(u.n), Ui.spacer()])
		if got:
			head.add_child(Ui.pill("Є", "good", "check"))
		var v := Ui.vbox(6, [head, _note(u.d)])
		if not got:
			if lock:
				v.add_child(Ui.hbox(0, [Ui.pill("Ліцензія «%s»" % D.LIC[u.tier].n, "", "lock")]))
			else:
				var id: String = u.id
				v.add_child(Ui.hbox(0, [_btn("Впровадити · " + Ui.usd(c), "pri sm" if CO.cash >= c else "sm", "plus", func(): _do(sim.act_upg(id)), CO.cash >= c)]))
		cards.append(_blk(v, Color(91 / 255.0, 214 / 255.0, 140 / 255.0, .45) if got else Ui.LINE, .5 if lock else 1.0))
	body.add_child(_grid(2, cards))


# ====================================================================== coNet
func _net(body: VBoxContainer) -> void:
	var CO := sim.CO
	body.add_child(Ui.hint("Хаб — база вашої техніки в місті: звідси машини виїздять на рейси й сюди повертаються. Він дає [b]місцевий ринок доставок[/b], а підприємства навколо частіше дають [b]замовлення[/b]. Рівні: 1, 2, 3, а хаб 3 рівня можна перетворити на [b]Логістичний хаб[/b]. Щоб відкрити хаб, клацніть на країну на мапі або оберіть місто зі списку нижче.", "bulb"))
	body.add_child(_sect("Ваші хаби"))
	var list := Ui.vbox(8)
	for h in CO.hubs:
		var p: Dictionary = sim.PL[h.pid]
		var pid: int = p.id
		var q: float = minf(1, h.get("cap", 0) / h.want) if h.get("want", 0) > 0 else 1.0
		var lvl: int = h.lvl
		var infra := []
		if p.get("air"):
			infra.append("аеропорт")
		if p.get("port") != null:
			infra.append("порт")
		if p.get("rail"):
			infra.append("залізниця")
		var name_c := _place(pid)
		name_c.mouse_filter = Control.MOUSE_FILTER_STOP
		name_c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		name_c.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: goto_place.emit(pid))
		var hi := Ui.icon("star" if pid == CO.hq else "building", 18, Ui.ACCENT)
		hi.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var info := Ui.vbox(2, [name_c, _note("%s · %s · %s · %s" % [D.HUB_LV[lvl], TYPE_N.get(p.type, ""), Ui.people(p.pop), ", ".join(infra) if infra.size() else "тільки автодороги"])])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var acts := _right([])
		if lvl < 4:
			var up: float = sim.hub_cost(p) * D.HUB_UP[lvl]
			var tip := _tip(D.HUB_LV[lvl + 1], "Техніки в хабі: %d → %d. Робочих місць: +%d. Завантаження й розвантаження %d%% швидше. Замовлень від підприємств поблизу ×%s. Більша частка міського ринку і +1 місце на біржі. Оренда %s/міс." % [
				D.HUB_VEH[lvl], D.HUB_VEH[lvl + 1], D.HUB_STAFF[lvl + 1] - D.HUB_STAFF[lvl], int(JS.round_js((1 - D.HUB_HAND[lvl + 1]) * 100)), str(D.HUB_ORD[lvl + 1]), Ui.usd(D.HUB_RENT[lvl + 1] * sim.price_k(p.cid))])
			acts.add_child(_btn("%s · %s" % [D.HUB_LV[lvl + 1], Ui.usd(up)], "sm", "up", func(): _do(sim.act_hub_up(pid)), true, tip))
		if pid != CO.hq:
			acts.add_child(_btn("", "sm", "trash", func(): _do(sim.act_hub_close(pid)), true, "Закрити хаб"))
		var stats := _grid(3, [
			_stat("Попит", "%d/день" % int(JS.round_js(h.get("want", 0))), "частка ринку %.1f%%" % (h.get("share", 0) * 100), _tip("Попит на ваші доставки", "Залежить від населення, багатства міста, вашого рейтингу, реклами і рівня хабу.")),
			_stat("Потужність", "%d/день" % int(JS.round_js(h.get("cap", 0))), "%d од. техніки" % h.get("nloc", 0), _tip("Потужність", "Скільки посилок встигають розвезти фургони й вантажні машини, що стоять у хабі цього міста."), "warn" if q < .6 else ""),
			_stat("Розвезено", "%d/день" % int(JS.round_js(h.get("served", 0))), Ui.usd(h.get("served", 0) * 4.2 * sim.price_k(p.cid)) + "/день")])
		var nveh := sim.hub_veh_n(pid)
		var facts := HFlowContainer.new()
		facts.add_theme_constant_override("h_separation", 14)
		facts.add_theme_constant_override("v_separation", 6)
		facts.add_child(_icl("truck", "Техніка %d / %d" % [nveh, D.HUB_VEH[lvl]], Ui.WARN if nveh >= sim.hub_veh_cap(h) else Ui.FG2))
		facts.add_child(_icl("users", "Робочих місць %d" % D.HUB_STAFF[lvl]))
		facts.add_child(_icl("box", "Завантаження " + (("−%d%%" % int(JS.round_js((1 - D.HUB_HAND[lvl]) * 100))) if lvl > 1 else "звичайне")))
		facts.add_child(_icl("doc", "Замовлень ×%s" % str(D.HUB_ORD[lvl])))
		var mk_opts := []
		for x in [0, 500, 2000, 8000, 30000]:
			mk_opts.append([x, (Ui.usd(x) + "/міс") if x else "Без реклами", "spark"])
		var mk := _dd(mk_opts, int(h.get("mk", 0)), func(x):
			sim.act_mk(pid, x)
			_do({}))
		var mkr := Ui.hbox(8, [_note("Реклама в місті"), mk])
		list.add_child(_blk(Ui.vbox(10, [Ui.hbox(10, [hi, info, acts]), stats, facts, mkr])))
	body.add_child(list)
	body.add_child(_sect("Де відкрити наступний хаб"))
	if CO.tier < 1:
		body.add_child(_icl("lock", "Нові хаби відкриваються з ліцензією «Міжміська доставка».", Ui.FG2))
	else:
		var recs: Array = sim.PL.filter(func(p): return sim.hub_at(p.id) == null and sim.co_scope(p))
		recs.sort_custom(func(a, b): return a.pop > b.pop)
		var rows := []
		for p in recs.slice(0, 8):
			var pid: int = p.id
			var nm := _place(pid)
			nm.mouse_filter = Control.MOUSE_FILTER_STOP
			nm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			nm.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: goto_place.emit(pid))
			var ics := Ui.hbox(4)
			if p.get("air"):
				ics.add_child(Ui.icon("plane", 14, Ui.FG2))
			if p.get("port") != null:
				ics.add_child(Ui.icon("anchor", 14, Ui.FG2))
			if p.get("rail"):
				ics.add_child(Ui.icon("train", 14, Ui.FG2))
			var c := sim.hub_open_cost(p)
			rows.append([Ui.vbox(2, [nm, _note("%s · %s" % [TYPE_N.get(p.type, "").capitalize(), Ui.people(p.pop)])]), ics,
				_right([_btn(("Оренда " if sim.hub_abroad(p) else "") + Ui.usd(c), "pri sm" if CO.cash >= c else "sm", "plus", func(): _do(sim.act_hub(pid)), CO.cash >= c)])])
		body.add_child(_table_rows(rows, [["", 0, false], ["", 70, false], ["", 150, true]]))
	body.add_child(_sect("Ліцензії"))
	for i in D.LIC.size():
		var l: Dictionary = D.LIC[i]
		if l.get("hide"):
			continue
		var got: bool = i <= CO.tier
		var r := _tt("%d. %s" % [i, l.n], l.d, "check" if got else "lock", Ui.GOOD if got else Ui.MUTED)
		r.modulate.a = 1.0 if got else .55
		body.add_child(_tr([r], [["", 0, false]], 6))


# ====================================================================== coStaff
func _staff(body: VBoxContainer) -> void:
	var CO := sim.CO
	var need := _crew_need()
	var wk: float = sim.wage_k(sim.me) * CO.wageLv
	var st_n := sim.staff_total()
	var cap := sim.staff_cap()
	var fund := 0.0
	for r in D.ROLE:
		fund += CO.staff.get(r, 0) * D.ROLE[r].w * wk
	var mor: float = CO.morale
	body.add_child(_grid(3, [
		_stat("Персонал", str(st_n + CO.founder), "робочих місць %d / %d" % [st_n, cap], _tip("Робочі місця", "Кожен хаб дає робочі місця: 1 рівень 12, 2 рівень 40, 3 рівень 150, логістичний хаб 400. Щоб наймати більше людей, покращуйте хаби або відкривайте нові."), "warn" if st_n >= cap else ""),
		_stat("Моральний дух", "%.0f/100" % mor, "ризик страйку" if mor < 35 else ("команда задоволена" if mor > 70 else "нормально"), _tip("Моральний дух", "Залежить від зарплат, перевантаження і HR-директора. Впливає на аварії, якість і страйки."), "bad" if mor < 35 else ("good" if mor > 65 else "warn")),
		_stat("Фонд оплати", Ui.usd(fund) + "/міс", "без менеджменту")]))
	# the wage slider: the value shows live, the level is set on release
	var wv := Ui.num("%d%%" % int(JS.round_js(CO.wageLv * 100)), 15)
	var sl := HSlider.new()
	sl.min_value = 80
	sl.max_value = 180
	sl.step = 5
	sl.value = JS.round_js(CO.wageLv * 100)
	sl.focus_mode = Control.FOCUS_NONE
	sl.add_theme_stylebox_override("slider", Ui.box(Color(1, 1, 1, .1), Color.TRANSPARENT, 0, Vector4(0, 2, 0, 2)))
	sl.add_theme_stylebox_override("grabber_area", Ui.box(Ui.ACCENT, Color.TRANSPARENT, 0, Vector4(0, 2, 0, 2)))
	sl.add_theme_stylebox_override("grabber_area_highlight", Ui.box(Ui.ACCENT, Color.TRANSPARENT, 0, Vector4(0, 2, 0, 2)))
	sl.add_theme_icon_override("grabber", _knob(Ui.ACCENT))
	sl.add_theme_icon_override("grabber_highlight", _knob(Ui.ACCENT.lightened(.2)))
	sl.value_changed.connect(func(x): wv.text = "%d%%" % int(x))
	sl.drag_ended.connect(func(_c):
		sim.act_wage(sl.value / 100)
		_do({}))
	var wl := Ui.lbl("Рівень зарплат відносно ринку")
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_blk(Ui.vbox(8, [Ui.hbox(8, [wl, wv]), sl, _note("Нижче 100% — економія, але падає дух і ростуть аварії. Вище — дорожче, зате надійно.")])))
	body.add_child(_sect("Працівники"))
	var rows := []
	for r in D.ROLE:
		var R_: Dictionary = D.ROLE[r]
		var have := _crew_have(r)
		var lack: int = need[r] - have
		var pool: int = int(CO.pool.get(r, 0))
		var rr: String = r
		var k5: int = maxi(5, lack)
		rows.append([Ui.hbox(6, [Ui.icon(R_.ic, 16), _b(R_.n, 13)]), Ui.num(str(have), 13), Ui.num(str(need[r]), 13, Ui.BAD if lack > 0 else Ui.FG),
			Ui.label(Ui.usd(R_.w * wk) + "/міс", 13, Ui.FG2), Ui.num(str(pool), 13, Ui.FG if pool > 0 else Ui.MUTED),
			_right([_btn("", "sm", "minus", func(): _do(sim.act_hire(rr, -1)), true, "Звільнити"), _btn("1", "sm", "plus", func(): _do(sim.act_hire(rr, 1))),
				_btn(str(k5), "pri sm" if lack > 0 else "sm", "plus", func(): _do(sim.act_hire(rr, k5)))])])
	var tb := _table([["Роль", 0, false], ["Є", 40, false], ["Потрібно", 64, false], ["Зарплата", 90, false], ["Кандидати", 74, false], ["Найм", 150, true]], rows)
	tb.get_child(0).get_child(0).get_child(0).get_child(4).tooltip_text = _tip("Ринок праці", "Скільки людей готові прийти до вас цього місяця. Поповнюється щомісяця: більше при вищих зарплатах, з HR-директором і великою мережею хабів.")
	tb.get_child(0).get_child(0).get_child(0).get_child(4).mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(tb)
	body.add_child(_note("Найм коштує пів місячної зарплати (оголошення, навчання). Звільнення — місячна компенсація. Що більше людей, то дорожчі офіс, бухгалтерія й диспетчери."))
	body.add_child(_sect("Топменеджмент"))
	var mv := Ui.vbox(10)
	for s in D.MG:
		var sid: String = s.id
		var g: Variant = CO.mgr.get(sid)
		if g != null:
			var av := PanelContainer.new()
			av.custom_minimum_size = Vector2(44, 44)
			av.add_theme_stylebox_override("panel", Ui.box(Ui.ACCENT))
			av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			var ini := Ui.label(_initials(g.name), 15, Ui.ACCENT_INK, Ui.font("display", 600))
			ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			av.add_child(ini)
			var info := Ui.vbox(2, [Ui.hbox(6, [Ui.icon(s.ic, 16, Ui.ACCENT), _b(s.n)]),
				_note("%s, %d · %s · навичка %s · лояльність %s" % [g.name, g.age, g.trait, _stars(g.skill), str(g.loyal)]), _note(s.d)])
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var rt := Ui.hbox(8, [Ui.num(Ui.usd(g.sal) + "/міс", 13), _dng("Звільнити", func(): _do(sim.act_fire_mgr(sid)))])
			rt.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", Ui.box(Ui.GLASS_LO, Ui.LINE, 1, Vector4(12, 12, 12, 12)))
			card.add_child(Ui.hbox(12, [av, info, rt]))
			mv.add_child(card)
			continue
		var cs: Array = CO.cand.get(sid, [])
		var t := Ui.hbox(6, [Ui.icon(s.ic, 16, Ui.MUTED), _b(s.n), Ui.pill("вакансія")])
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := Ui.vbox(6, [Ui.hbox(8, [t, _btn("Інші кандидати · " + Ui.usd(1500 * sim.price_k(sim.me)), "sm", "refresh", func(): _do(sim.act_recand(sid)))]), _note(s.d)])
		for i in cs.size():
			var c: Dictionary = cs[i]
			var ci: int = i
			var who := Ui.rich("[b]%s[/b], %d [color=#b3c2cf]· %s · навичка %s[/color]" % [c.name, c.age, c.trait, _stars(c.skill)], 13, Ui.FG)
			var row := _tr([who, Ui.hbox(8, [Ui.num(Ui.usd(c.sal) + "/міс", 13), _btn("Найняти", "pri sm" if CO.cash >= c.sal else "sm", "", func(): if sid != "cto" or gr_ok("cto"): _do(sim.act_hire_mgr(sid, ci)), CO.cash >= c.sal)])],
				[["", 0, false], ["", 0, true]], 6)
			var sb: StyleBoxFlat = row.get_theme_stylebox("panel").duplicate()
			sb.border_width_bottom = 0
			sb.border_width_top = 1
			row.add_theme_stylebox_override("panel", sb)
			row.get_child(0).add_theme_constant_override("margin_left", 0)
			row.get_child(0).add_theme_constant_override("margin_right", 0)
			v.add_child(row)
		mv.add_child(_blk(v))
	body.add_child(mv)
	body.add_child(_note("Чесність кандидата не видно в резюме. Нечесний менеджер потроху виводить гроші — ловить їх тільки фінансовий директор."))


static func _initials(n: String) -> String:
	var s := ""
	for w in n.split(" ", false):
		s += w.left(1)
	return s.left(2).to_upper()


static func _knob(col: Color) -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)


# ====================================================================== coFin
func _fin(body: VBoxContainer) -> void:
	var CO := sim.CO
	var m: Dictionary = CO.m
	var l: Variant = CO.lm
	var PLN := month_plan()
	var rows := [["Доставки по країні", "local", 1], ["Офіс, бухгалтерія, диспетчери", "office", -1], ["Міжнародні перевезення", "contract", 1], ["Тендери", "tender", 1],
		["Зарплати і найм", "wage", -1], ["Менеджмент", "mgmt", -1], ["Пальне", "fuel", -1], ["Утримання і ремонт", "upkeep", -1], ["Оренда хабів", "rent", -1],
		["Податок за чужі хаби", "hubtax", -1], ["Реклама", "mk", -1], ["Страхування", "ins", -1], ["Відсотки", "interest", -1], ["Претензії й збитки", "claims", -1],
		["Інше (штрафи, втрати)", "other", -1]]
	var debt := sim.loans_left()
	var lim := sim.co_credit()
	var rank := sim.co_rank()
	body.add_child(_grid(4, [
		_stat("Гроші", Ui.usd(CO.cash), "", "", "bad" if CO.cash < 0 else ""),
		_stat("Кредити", Ui.usd(debt), "ставка %.1f%%" % (sim.co_rate() * 100), _tip("Кредити", "Повертаються рівними частинами за 24 місяці. Ставка залежить від рейтингу і фінансового директора.")),
		_stat("Кредитний ліміт", Ui.usd(lim), "", _tip("Ліміт", "Залежить від вартості компанії і виручки.")),
		_stat("Місце у світі", "%d з %d" % [rank, CO.comp.size() + 1], "за річною виручкою", _tip("Рейтинг компаній", "Порівняння з найбільшими логістичними компаніями світу."), "good" if rank == 1 else "")]))
	body.add_child(_sect("Прибутки і витрати"))
	body.add_child(_note("Зарплати, офіс, менеджмент, оренда, реклама, страхування й відсотки списуються одним платежем в останній день місяця. До того в колонці «Цей місяць» видно очікувану суму. Одноразові витрати (найм, звільнення) списуються одразу."))
	var cols := [["Стаття", 0, false], ["Цей місяць", 170, true], ["Минулий", 110, true]]
	var trs := []
	for r in rows:
		var k: String = r[1]
		var s: int = r[2]
		var mv: float = m.get(k, 0)
		var cur := Ui.vbox(0)
		cur.alignment = BoxContainer.ALIGNMENT_END
		var main_t: String = Ui.usd(s * mv, true) if mv else ("" if PLN.get(k, 0) else "—")
		if main_t != "":
			var n := Ui.num(main_t, 13, Ui.GOOD if s > 0 and mv else Ui.FG)
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cur.add_child(n)
		if PLN.get(k, 0):
			var pn := Ui.label(("+ " if mv else "") + "≈ %s в кінці місяця" % Ui.usd(-PLN[k], true), 11, Ui.FG2)
			pn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cur.add_child(pn)
		var lv: float = l.get(k, 0) if l != null else 0.0
		trs.append([Ui.label(r[0], 13), cur, Ui.num(Ui.usd(s * lv, true) if lv else "—", 13)])
	trs.append([_b("Разом", 13), Ui.num(Ui.usd(sim.co_rev(m) - sim.co_cost(m), true), 13), Ui.num(Ui.usd(sim.co_rev(l) - sim.co_cost(l), true) if l != null else "—", 13)])
	body.add_child(_table(cols, trs))
	body.add_child(_note("Зарплати, оренда, реклама, страховка і кредити списуються на початку місяця."))
	body.add_child(_sect("Кредити і страхування"))
	var room := maxf(0, lim - debt)
	var lr := HFlowContainer.new()
	lr.add_theme_constant_override("h_separation", 8)
	lr.add_child(_btn("Кредит " + Ui.usd(room * .25), "sm", "plus", func(): _do(sim.act_loan(.25))))
	lr.add_child(_btn("Весь ліміт " + Ui.usd(room), "sm", "plus", func(): _do(sim.act_loan(1))))
	lr.add_child(_btn("Погасити достроково", "sm", "check", func():
		sim.act_repay()
		_do({}), debt > 0))
	body.add_child(lr)
	var vc := 0.0
	for v in CO.veh:
		vc += D.VT[v.t].cost
	body.add_child(_tg_row("Страхування вантажів", "Покриває 80%% претензій за викрадені й пошкоджені вантажі. ≈ %s/міс." % Ui.usd(500 + vc * .0035), CO.ins, func():
		sim.act_ins()
		_do({})))
	body.add_child(_sect("Найбільші логістичні компанії світу"))
	var lb := []
	for c in CO.comp:
		lb.append({"n": c.n, "rev": c.rev})
	lb.append({"n": CO.name, "rev": sim.co_year_rev(), "me": true})
	lb.sort_custom(func(a, b): return a.rev > b.rev)
	var lrows := []
	for i in lb.size():
		var c: Dictionary = lb[i]
		var me: bool = c.get("me", false)
		lrows.append([Ui.num(str(i + 1), 13), _b(c.n, 13, Ui.WARN) if me else Ui.label(c.n, 13), Ui.num(Ui.usd(c.rev) + "/рік", 13)])
	var t := Ui.vbox(0)
	var lcols := [["", 30, false], ["", 0, false], ["", 140, true]]
	for i in lrows.size():
		t.add_child(_tr(lrows[i], lcols, 8, Color(1, 179 / 255.0, 71 / 255.0, .08) if lb[i].get("me", false) else Color.TRANSPARENT))
	body.add_child(t)
