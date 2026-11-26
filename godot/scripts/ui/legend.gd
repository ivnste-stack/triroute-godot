class_name Legend
extends PanelContainer
## The legend of the map layer (#legend, updateLegend of 08e-company.js): above the bottom bar, right of the
## rail; its own entries for each layer: the company network, logistic routes, risks, political, demand.
## The button in the corner folds it to its title (UI.lgc, kept in the settings).

const HUB := Color("#ffb347")
const DEM_COL := [Color(.78, .9, .97), Color(.47, .73, .9), Color(.22, .5, .78), Color(.1, .29, .55)]
const RISK_COL := [Color(.27, .62, .42), Color(.83, .71, .3), Color(.88, .47, .2), Color(.78, .2, .18)]

signal toggled   # a line was clicked: what it names is hidden or shown again (MapVis)

var sim: Sim
var mode := "co"
var _box: VBoxContainer
var _key := ""
var _scroll: ScrollContainer
var _pad: MarginContainer


func _ready() -> void:
	Ui.glass(Ui.GLASS, Ui.LINE, self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_top = 1
	anchor_bottom = 1
	offset_left = 14 + 64
	offset_bottom = -86
	_box = Ui.vbox(7)
	_scroll = SmoothScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pad = Ui.margin(_box, 14, 12, 14, 12)
	_scroll.add_child(_pad)
	add_child(_scroll)


func _process(_delta: float) -> void:
	if sim == null:
		return
	var folded: bool = Settings.get_value("legend_folded")
	var k := "%d|%s|%s|%d|%d|%d" % [MapVis.ver, mode, folded, sim.CO.get("hubs", []).size(), sim.CO.get("jobs", []).size(), int(get_viewport_rect().size.y)]
	if k != _key:
		_key = k
		_build(folded)


func _build(folded: bool) -> void:
	# out at once: rows waiting to be freed would still count in the size
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var title: String = {"co": "Мережа " + String(sim.CO.get("name", "")), "grid": "Логістичні шляхи", "risk": "Ризики перевезень",
		"pol": "Політична карта", "dem": "Світовий попит на доставку"}.get(mode, "")
	# folded: the title and the button side by side, nothing between; open: the button at the right edge
	var head := Ui.hbox(10, [Ui.lbl(title)] if folded else [Ui.lbl(title), Ui.spacer()])
	var fold := Button.new()
	fold.icon = Icons.tex("plus" if folded else "minus", Ui.FG2, 14)
	fold.flat = true
	fold.focus_mode = Control.FOCUS_NONE
	fold.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fold.tooltip_text = "Розгорнути легенду" if folded else "Згорнути легенду"
	fold.custom_minimum_size = Vector2(22, 16)
	fold.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	fold.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	fold.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	fold.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	fold.mouse_entered.connect(func(): fold.icon = Icons.tex("plus" if folded else "minus", Ui.ACCENT, 14))
	fold.mouse_exited.connect(func(): fold.icon = Icons.tex("plus" if folded else "minus", Ui.FG2, 14))
	fold.pressed.connect(func(): Settings.set_value("legend_folded", not folded))
	head.add_child(fold)
	_box.add_child(head)
	custom_minimum_size.x = 0 if folded else 258
	# a slim bar when folded
	_pad.add_theme_constant_override("margin_top", 6 if folded else 12)
	_pad.add_theme_constant_override("margin_bottom", 6 if folded else 12)
	_pad.add_theme_constant_override("margin_right", 8 if folded else 14)
	if folded:
		_fit.call_deferred()
		return
	for e in _entries():
		if e[0] is String:
			var n := Ui.note(e[1], Ui.MUTED)
			n.add_theme_font_size_override("font_size", 12)
			n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			n.custom_minimum_size.x = 230
			_box.add_child(Ui.margin(n, 0, 4, 0, 0))
		else:
			_box.add_child(_row(e[0], e[1]))
	_fit.call_deferred()


## max-height: calc(100% - 190px), the rest scrolls
func _fit() -> void:
	# wrapped notes know their height only after a layout pass
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_scroll.custom_minimum_size = Vector2.ZERO
	var inner := (_box.get_parent() as Control).get_combined_minimum_size()
	var h := minf(inner.y, get_viewport_rect().size.y - 190)
	_scroll.custom_minimum_size = Vector2(inner.x, h)
	var sz := get_combined_minimum_size()
	# anchored to the bottom left: the panel grows upwards from 86 px above the bottom
	offset_top = offset_bottom - sz.y
	offset_right = offset_left + sz.x
	size = sz


## a line of the legend: the mark and its name; on the network, logistics, political and demand layers a
## click hides what it names (struck through and faded while hidden) or shows it again
func _row(mark: Dictionary, text: String) -> Control:
	var m := Control.new()
	m.custom_minimum_size = Vector2(26, 16)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.draw.connect(func(): _mark(m, mark))
	var l := Ui.label(text, 12, Ui.FG2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := Ui.hbox(10, [m, l])
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key := MapVis.key_of(text) if mode in ["co", "grid", "pol", "dem"] else ""
	if key == "":
		return h
	var p := PanelContainer.new()
	var idle := Ui.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, Vector4(0, 1, 6, 1))
	var hov := Ui.box(Color(1, 1, 1, .05), Color.TRANSPARENT, 0, Vector4(0, 1, 6, 1))
	p.add_theme_stylebox_override("panel", idle)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.tooltip_text = ("Показати на мапі" if not MapVis.vis(key) else "Сховати з мапи")
	p.add_child(h)
	var off := not MapVis.vis(key)
	if off:
		h.modulate.a = .38
		l.draw.connect(func(): l.draw_line(Vector2(0, l.size.y / 2 + 1), Vector2(l.size.x, l.size.y / 2 + 1), Color(1, 1, 1, .35), 1.0))
	p.mouse_entered.connect(func(): p.add_theme_stylebox_override("panel", hov))
	p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", idle))
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click", -4.0)
			MapVis.toggle(key)
			toggled.emit())
	return p


func _mark(n: Control, k: Dictionary) -> void:
	var c := n.size / 2
	var col: Color = k.get("c", Color.WHITE)
	var bc: Color = k.get("b", Color("#071420"))
	match k.t:
		"sq", "dia":   # .sq: 8×8 with a dark border; .sqc: the accent, turned 45°
			var s: Vector2 = k.get("s", Vector2(8, 8))
			var pts := PackedVector2Array([c + Vector2(-s.x, -s.y) / 2, c + Vector2(s.x, -s.y) / 2, c + Vector2(s.x, s.y) / 2, c + Vector2(-s.x, s.y) / 2])
			if k.t == "dia":
				pts = PackedVector2Array([c + Vector2(0, -s.y * .7), c + Vector2(s.x * .7, 0), c + Vector2(0, s.y * .7), c + Vector2(-s.x * .7, 0)])
			if col.a > 0:
				n.draw_colored_polygon(pts, col)
			var bw: float = k.get("bw", 1.5)
			if bw > 0:
				pts.append(pts[0])
				if k.get("dash", false):
					for i in 4:
						n.draw_dashed_line(pts[i], pts[i + 1], bc, bw, 2.0)
				else:
					n.draw_polyline(pts, bc, bw, true)
		"dot":   # a round mark, with a ring or a dashed edge
			var r: float = k.get("r", 4.5)
			if col.a > 0:
				n.draw_circle(c, r, col, true, -1.0, true)
			if k.has("b"):
				if k.get("dash", false):
					for i in 8:
						n.draw_arc(c, r, i * TAU / 8, i * TAU / 8 + TAU / 16, 4, bc, 1.0, true)
				else:
					n.draw_arc(c, r, 0, TAU, 24, bc, k.get("bw", 1.0), true)
		"line":   # .lg i: a 26 px stripe
			var h: float = k.get("h", 2.0)
			if k.has("b"):
				n.draw_rect(Rect2(0, c.y - h / 2 - 1, n.size.x, h + 2), bc)
			if k.get("dash", false):
				n.draw_dashed_line(Vector2(0, c.y), Vector2(n.size.x, c.y), col, h, 4.0)
			else:
				n.draw_rect(Rect2(0, c.y - h / 2, n.size.x, h), col)
		"cp":   # a border checkpoint: red and white stripes
			var o := c - Vector2(5, 5)
			n.draw_rect(Rect2(o, Vector2(10, 10)), Color.WHITE)
			for seg in [[Vector2(0, 4), Vector2(4, 0)], [Vector2(0, 10), Vector2(10, 0)], [Vector2(6, 10), Vector2(10, 6)]]:
				n.draw_line(o + seg[0], o + seg[1], Color("#f0625f"), 2.0, true)
			n.draw_rect(Rect2(o, Vector2(10, 10)), Color("#e8edf2"), false, 1.0)
		"jam":   # two dots: planned and active closures
			n.draw_circle(c + Vector2(-6, 0), 4.5, Color("#ff8a2a"), true, -1.0, true)
			n.draw_arc(c + Vector2(-6, 0), 6, 0, TAU, 20, Color(1, .54, .16, .25), 3, true)
			n.draw_circle(c + Vector2(6, 0), 4.5, Color("#f0443c"), true, -1.0, true)
			n.draw_arc(c + Vector2(6, 0), 6, 0, TAU, 20, Color(.94, .27, .24, .25), 3, true)
		"ico":
			var tex := Icons.tex(k.i, Color("#9fb4c6"), 14)
			n.draw_texture_rect(tex, Rect2(c - Vector2(7, 7), Vector2(14, 14)), false)


func _sq(c: Color, b := Color("#071420"), s := Vector2(8, 8), bw := 1.5) -> Dictionary:
	return {"t": "sq", "c": c, "b": b, "s": s, "bw": bw}


## LG_SET: the two kinds of settlement marks
func _lg_set() -> Array:
	return [[{"t": "dia", "c": Ui.ACCENT, "bw": 0}, "Столиці, великі й середні міста"], [{"t": "dia", "c": Color.WHITE}, "Малі міста"]]


## LG_INC: the situation on the map
func _inc() -> Array:
	return [[{"t": "jam"}, "Перекриті дороги"], [{"t": "line", "c": Color("#f0443c"), "h": 2.0}, "Закриті кордони"],
		[{"t": "dot", "c": Color(160 / 255.0, 190 / 255.0, 1, .22), "b": Color("#a8c4ff"), "dash": true}, "Негода"],
		[{"t": "dot", "c": Color("#f0625f")}, "Закриті порти й аеропорти"],
		[{"t": "line", "c": Color("#d696ff"), "h": 2.0, "dash": true}, "Закрите небо (війна)"],
		[{"t": "dot", "c": Color(240 / 255.0, 98 / 255.0, 95 / 255.0, .18), "b": Color("#f0625f"), "dash": true}, "Зона піратства"],
		[{"t": "dot", "c": Color(1, 140 / 255.0, 60 / 255.0, .18), "b": Color("#ff8c3c"), "dash": true}, "Зона бандитів на дорогах"],
		[{"t": "dot", "c": Color("#0b1520"), "b": Color("#f0625f"), "bw": 2.0}, "Напад: пограбування, захоплення"],
		[{"t": "dot", "c": Color.TRANSPARENT, "b": Color("#c9d4de"), "dash": true}, "Збій GPS: техніка зникає з карти"]]


func _ways() -> Array:
	return [[{"t": "line", "c": Color("#8fe3ff"), "h": 2.0, "b": Color("#f6b94f")}, "Платні швидкісні траси"],
		[{"t": "line", "c": Color("#f0625f"), "h": 3.0}, "Заборона для важкого транспорту"],
		[{"t": "line", "c": Color("#6b3b1a"), "h": 4.0}, "Залізниця"], [{"t": "cp"}, "Пропускний пункт на кордоні"],
		[{"t": "ico", "i": "anchor"}, "Морський порт"], [{"t": "ico", "i": "plane"}, "Аеропорт"], [{"t": "ico", "i": "train"}, "Залізнична станція"]]


func _entries() -> Array:
	var out := []
	match mode:
		"pol":
			out.append([{"t": "line", "c": Color("#0b1520"), "h": 2.0, "b": Color(1, 1, 1, .25)}, "Кордони держав"])
			out.append_array(_lg_set())
			out.append(["note", "%d держав" % sim.states.size()])
		"dem":
			var nm := ["Низький", "Середній", "Високий", "Дуже високий"]
			for i in 4:
				out.append([_sq(DEM_COL[i], Color.TRANSPARENT, Vector2(14, 10), 0), nm[i]])
			out.append_array(_lg_set())
			out.append(["note", "Попит: населення й багатство міст країни на одиницю площі"])
		"risk":
			var nm := ["Низький", "Помірний", "Високий", "Дуже високий"]
			for i in 4:
				out.append([_sq(RISK_COL[i]), nm[i]])
			out.append([{"t": "dot", "c": Color(240 / 255.0, 98 / 255.0, 95 / 255.0, .25), "b": Color("#f0625f"), "dash": true}, "Зона піратства"])
			out.append([{"t": "dot", "c": Color(1, 140 / 255.0, 60 / 255.0, .2), "b": Color("#ff8c3c"), "dash": true}, "Зона бандитів на дорогах"])
			out.append(["note", "Рівень відносно інших держав: повільна митниця, нестабільність, конфлікти"])
		"grid":
			var km := func(d: float) -> int: return int(round(d * sim.CO_DU * GameData.KM))
			out.append([_sq(Color("#b8bfc7")), "Суходіл (усі держави)"])
			out.append_array(_lg_set())
			out.append([_sq(Color.TRANSPARENT, Color("#e6edf3"), Vector2(8, 8), 2.0), "Сектор ≈ %d км" % km.call(MapOverlay.SECTOR)])
			out.append([_sq(Color.TRANSPARENT, Color("#aab6c2"), Vector2(8, 8), 1.0), "Квартал ≈ %d км" % km.call(MapOverlay.SECTOR / 3)])
			var cell := _sq(Color.TRANSPARENT, Color("#7d8894"), Vector2(8, 8), 1.0)
			cell.dash = true
			out.append([cell, "Клітинка ≈ %d км (трикутники суші й води)" % km.call(.125)])
			out.append([{"t": "line", "c": Color("#f4b453"), "h": 2.0}, "Автомагістралі й дороги"])
			out.append_array(_ways())
			out.append_array(_inc())
			out.append([_sq(HUB), "Хаби"])
			out.append([_sq(HUB, Color("#071420"), Vector2(6, 6)), "Хаб 1 рівня"])
			out.append([_sq(HUB), "Хаб 2 рівня"])
			out.append([_sq(HUB, Color("#071420"), Vector2(10, 10)), "Хаб 3 рівня"])
			out.append([_sq(HUB, Color("#071420"), Vector2(12, 12)), sim.hub_lv(4) if sim != null else "Логістичний хаб"])
		_:
			out.append([_sq(HUB), "Хаби"])
			for v in [["#34c759", "Фургони й вантажівки"], ["#ec965c", "Потяги"], ["#6ebeff", "Кораблі"], ["#d696ff", "Літаки"],
					["#f0625f", "Інцидент: ДТП, поломка, пальне"], ["#f1c453", "Затримка: кордон, негода, перекриття"]]:
				out.append([{"t": "dot", "c": Color(v[0])}, v[1]])
			out.append_array(_inc())
			out.append([_sq(Color("#7d8a96")), "Доступно за ліцензією"])
			out.append([_sq(Color("#2b333c")), "Поки недоступно"])
			out.append([{"t": "line", "c": Color("#f6b94f"), "h": 4.0, "b": Color(6 / 255.0, 12 / 255.0, 18 / 255.0, .6)}, "Автомагістралі"])
			out.append([{"t": "line", "c": Color("#f4b453"), "h": 2.0}, "Дороги"])
			out.append_array(_ways())
			out.append(["note", "Хабів: %d · рейсів у дорозі: %d" % [sim.CO.get("hubs", []).size(), sim.CO.get("jobs", []).size()]])
	return out
