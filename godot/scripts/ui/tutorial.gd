class_name Tutorial
extends Control
## The tutorial of the «Навчальна» difficulty (beta): the operations manager — an avatar drawn from an SVG — speaks
## from a glass card in the corner; the block to press next is lit up on the screen (the rest dimmed a little, a
## pulsing frame and a «Сюди» chip), and a step goes on by itself once the player has done it. A short guide: the
## company, the board, one route laid on the map, the dispatch, the time running, the delivery. The step is kept in
## CO.tut (a saved game goes on from it; −1 when done or skipped). The classic game and the alternative balance
## (the network of terminals) have their own steps where they differ.

const NAME := "Аліна Корса"
const ROLE := "операційний менеджер"
const AVATAR := """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#18293a"/><stop offset="1" stop-color="#08121b"/></linearGradient>
<linearGradient id="jk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5cc8f2"/><stop offset="1" stop-color="#2b6d9b"/></linearGradient>
<clipPath id="c"><circle cx="48" cy="48" r="45"/></clipPath>
</defs>
<circle cx="48" cy="48" r="46" fill="url(#bg)"/>
<g clip-path="url(#c)">
<path d="M14 98 C16 72 32 63 48 63 C64 63 80 72 82 98 Z" fill="url(#jk)"/>
<path d="M39 64 L48 76 L57 64" fill="none" stroke="#e7eef4" stroke-width="3" stroke-linejoin="round"/>
<rect x="43" y="52" width="10" height="13" rx="4" fill="#e2b998"/>
<circle cx="48" cy="40" r="15.5" fill="#f1cfb2"/>
<path d="M32 42 C30 25 41 19 49 19 C59 19 67 26 64 42 C62 34 56 29.5 48 29.5 C41 29.5 35 34 32 42 Z" fill="#2a2f3b"/>
<path d="M33 42 C32 50 33 56 36 60 C34 52 34 47 35 43 Z" fill="#2a2f3b"/>
<path d="M30.5 42 C30.5 28 38.5 21 48 21 C57.5 21 65.5 28 65.5 42" fill="none" stroke="#5cc8f2" stroke-width="3" stroke-linecap="round"/>
<rect x="27.5" y="38" width="6.5" height="11" rx="3.2" fill="#5cc8f2"/>
<rect x="62" y="38" width="6.5" height="11" rx="3.2" fill="#5cc8f2"/>
<path d="M30.5 48 C31.5 55 37 57.5 43.5 56.5" fill="none" stroke="#5cc8f2" stroke-width="2.2" stroke-linecap="round"/>
<circle cx="44.5" cy="56.3" r="2.4" fill="#5cc8f2"/>
<circle cx="42.6" cy="41" r="1.7" fill="#18293a"/><circle cx="53.4" cy="41" r="1.7" fill="#18293a"/>
<path d="M43.8 47.2 Q48 50.6 52.2 47.2" fill="none" stroke="#18293a" stroke-width="1.7" stroke-linecap="round"/>
</g>
<circle cx="48" cy="48" r="46" fill="none" stroke="#5cc8f2" stroke-width="2"/>
<circle cx="80" cy="80" r="8" fill="#5bd492" stroke="#08121b" stroke-width="3"/>
</svg>"""

var main: Node                 # the game (main.gd): the HUD, the windows, the planner, the map, the session
var steps: Array = []
var i := -1
var _card: PanelContainer
var _body: RichTextLabel
var _title: Label
var _prog: Label
var _dots: HBoxContainer
var _next: Button
var _t := 0.0
var _rect: Variant = null      # the lit block (screen rect) or null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
	visible = false
	_card = Ui.glass(Ui.GLASS_HI, Ui.LINE_HI)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.custom_minimum_size.x = 470
	add_child(_card)
	var av := TextureRect.new()
	av.texture = _avatar(84)
	av.custom_minimum_size = Vector2(84, 84)
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var who := Ui.vbox(0, [Ui.label(NAME, 14, Ui.FG, Ui.font("display", 600, .4)), Ui.label(ROLE, 12, Ui.MUTED)])
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var beta := Ui.pill("Бета · навчання", "acc", "bulb")
	beta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title = Ui.label("", 16, Ui.FG, Ui.font("body", 700))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body = Ui.rich("", 14, Ui.FG2)
	_body.fit_content = true
	_prog = Ui.label("", 11, Ui.MUTED, Ui.font("body", 600))
	_dots = Ui.hbox(4)
	var skip := Ui.btn("Пропустити", "sm", "", func(): finish(true))
	skip.tooltip_text = "Закрити навчання. Його можна пройти знову в новій грі на складності «Навчальна»."
	_next = Ui.btn("Далі", "pri sm", "", func(): advance())
	var foot := Ui.hbox(10, [Ui.vbox(4, [_prog, _dots]), Ui.spacer(), skip, _next])
	var text := Ui.vbox(8, [Ui.hbox(10, [who, beta]), _title, _body, foot])
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.add_child(Ui.margin(Ui.hbox(16, [av, text]), 16, 14, 16, 14))


static func _avatar(px: int) -> Texture2D:
	var img := Image.new()
	img.load_svg_from_string(AVATAR, px * 2 / 96.0)
	return ImageTexture.create_from_image(img)


# ====================================================================== steps
func _sim() -> Sim:
	return main.session.sim


## the steps of this game: the welcome, the company, then the classic way or the network's
func _build() -> void:
	var sim := _sim()
	var hq: String = sim.PL[sim.CO.hq].name
	var alt: bool = sim.alt()
	steps = [
		{"t": "Вітаємо з відкриттям першого хабу в місті %s!" % hq,
			"b": "Я — %s, ваш операційний менеджер. Хаб — це база компанії: звідси виїжджає техніка й сюди повертається. Покажу, як виконати перше замовлення від початку до кінця — це кілька хвилин." % NAME,
			"to": _hq_rect, "next": true},
		{"t": "Ваша компанія з одного погляду",
			"b": "Угорі — [b]гроші[/b], [b]прибуток[/b] за місяць, [b]рейтинг[/b] (від нього залежать дорожчі замовлення й ліцензії), кількість доставок, [b]техніка[/b] й [b]персонал[/b]. Слідкуйте, щоб гроші не пішли в мінус.",
			"to": func(): return _ctl_rect(main.hud._kpis), "next": true},
		{"t": "Відкрийте «Біржу вантажів»",
			"b": "Підприємства щодня публікують замовлення: звідки, куди, вага, оплата й термін. Натисніть на підсвічену кнопку зліва.",
			"to": func(): return _rail("coJobs"), "done": func(): return main.hud.open_window == "coJobs"}]
	if not alt:
		steps.append_array([
			{"t": "Оберіть замовлення",
				"b": "У картці видно маршрут, вантаж, оплату й термін. Натисніть [b]«Прокласти маршрут»[/b] — відкриється планувальник на мапі.",
				"to": func(): return _btn_in(main.win, "Прокласти маршрут"), "done": func(): return main.planner.on},
			{"t": "Прокладіть маршрут",
				"b": "Блакитна хвиля — звідки забрати вантаж, жовта — куди доставити. [b]Клікніть на місто призначення[/b] на мапі: машина поїде дорогами. Можна додавати проміжні точки, щоб об'їхати платні траси чи небезпеку.",
				"to": _dest_rect, "done": func(): return main.planner.on and sim.lp_calc(main.planner.LP).done},
			{"t": "Відправте рейс",
				"b": "Ліворуч — час дороги проти дедлайну, витрати на пальне, прибуток і ризик. Якщо все зелене — натисніть [b]«Відправити за маршрутом»[/b].",
				"to": func(): return _btn_in(main.planner, "Відправити за маршрутом"), "done": func(): return _on_trip()}])
	else:
		steps.append_array([
			{"t": "Візьміть замовлення в роботу",
				"b": "У цьому режимі вантаж спершу треба забрати у відправника. Натисніть [b]«Взяти в роботу»[/b] — він з'явиться серед прийнятих вантажів.",
				"to": func(): return _btn_in(main.win, "Взяти в роботу"), "done": func(): return sim.CO.net.cs.size() > 0},
			{"t": "Відкрийте «Прийняті вантажі»",
				"b": "Тут видно, де зараз кожен вантаж, куди йому далі й скільки лишилося до дедлайну.",
				"to": func(): return _rail("coCargo"), "done": func(): return main.hud.open_window == "coCargo"},
			{"t": "Заберіть вантаж",
				"b": "Натисніть [b]«Забрати»[/b]. У вікні рейсу оберіть машину, а в полі «Куди» — [b]«одразу до одержувача»[/b], щоб доставити за один рейс.",
				"to": func(): return _btn_in(main.win, "Забрати"), "done": func(): return main.modals.is_open() or sim.CO.net.runs.size() > 0},
			{"t": "Відправте рейс",
				"b": "Перевірте заповнення машини, час і оплату — і натисніть [b]«Відправити»[/b].",
				"to": func(): return _btn_in(main.modals, "Відправити"), "done": func(): return sim.CO.net.runs.size() > 0}])
	steps.append_array([
		{"t": "Запустіть час",
			"b": "Поки гра на паузі, машина стоїть. Увімкніть швидкість унизу: ▶ — звичайна, ▶▶ і ▶▶▶ — швидше. Пробіл ставить на паузу.",
			"to": _speed_rect, "done": func(): return main.session.speed > 0},
		{"t": "Рейс у дорозі",
			"b": "Машину видно на мапі — клікніть на неї, щоб стежити. Усі рейси — у вікні [b]«Рейси в дорозі»[/b]. Дорогою бувають затори, кордони й пригоди: менеджер повідомить. Чекаємо доставки…",
			"to": func(): return _rail("coTrips"), "done": func(): return (sim.CO.net.stat.done if alt else sim.CO.cdel) > 0},
		{"t": "Перша доставка!",
			"b": "Гроші вже на рахунку, рейтинг росте. Далі: беріть вигідні замовлення, купуйте техніку в [b]«Автопарку»[/b], наймайте водіїв у [b]«Персоналі»[/b], відкривайте нові хаби. За доставки ростуть досвід і грейд — вони відкривають ліцензії на вантажівки, міжнародні рейси, потяги, судна й літаки. Успіхів!",
			"to": func(): return null, "next": true, "last": true}])


## the game started (or was loaded) with the tutorial on: from this step
func start(from: int = 0) -> void:
	_build()
	i = clampi(from, 0, steps.size() - 1)
	visible = true
	_show_step()


func finish(skipped: bool = false) -> void:
	visible = false
	i = -1
	if main.session != null and main.session.sim != null:
		_sim().CO.tut = -1
	if skipped:
		main.toasts.push("", "Навчання закрито", "Підказки на кнопках і у вікнах лишаються — наведіть курсор, щоб прочитати.")


func advance() -> void:
	if i < 0:
		return
	if steps[i].get("last", false):
		finish()
		return
	i += 1
	_sim().CO.tut = i
	_show_step()


func _show_step() -> void:
	var s: Dictionary = steps[i]
	_title.text = s.t
	_body.text = s.b
	_prog.text = "Крок %d / %d" % [i + 1, steps.size()]
	for c in _dots.get_children():
		c.queue_free()
	for k in steps.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(14 if k == i else 6, 4)
		d.color = Ui.ACCENT if k <= i else Color(1, 1, 1, .15)
		_dots.add_child(d)
	_next.visible = s.get("next", false)
	_next.text = "Завершити" if s.get("last", false) else "Далі"
	# a soft entrance: the card fades in
	_card.modulate.a = 0.0
	create_tween().tween_property(_card, "modulate:a", 1.0, .3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Sfx.play("click", -10.0)


func _process(delta: float) -> void:
	if not visible or i < 0 or main.session == null or main.session.sim == null:
		return
	_t += delta
	var vs := get_viewport_rect().size
	_card.reset_size()
	var cs := _card.get_combined_minimum_size()
	_card.size = cs
	_card.position = Vector2(vs.x - cs.x - 18, vs.y - cs.y - 96)
	var s: Dictionary = steps[i]
	_rect = s.to.call() if s.has("to") else null
	if s.has("done") and s.done.call():
		advance()
		return
	queue_redraw()


# ====================================================================== what is lit
func _ctl_rect(c: Variant) -> Variant:
	if c == null or not is_instance_valid(c) or not (c as Control).is_visible_in_tree():
		return null
	return (c as Control).get_global_rect()


func _rail(id: String) -> Variant:
	var b: Variant = main.hud._rail_btns.get(id)
	return _ctl_rect(b[0]) if b != null else null


## the first visible, enabled button with this text inside a part of the interface
func _btn_in(root: Variant, text: String) -> Variant:
	if root == null or not is_instance_valid(root) or not (root as Control).is_visible_in_tree():
		return null
	var b: Variant = _find(root, text)
	return _ctl_rect(b)


func _find(n: Node, text: String) -> Variant:
	for c in n.get_children():
		if c is Button and c.text == text and not c.disabled and c.is_visible_in_tree():
			return c
		var r: Variant = _find(c, text)
		if r != null:
			return r
	return null


func _map_rect(x: float, z: float, r: float = 34) -> Variant:
	var cam: Camera3D = main.map.camera
	var p := Vector3(x, 0, z)
	if cam.is_position_behind(p):
		return null
	var q := cam.unproject_position(p)
	return Rect2(q - Vector2(r, r), Vector2(r, r) * 2)


func _hq_rect() -> Variant:
	var p: Dictionary = _sim().PL[_sim().CO.hq]
	return _map_rect(p.x, p.z)


func _dest_rect() -> Variant:
	if not main.planner.on:
		return null
	var p: Dictionary = _sim().PL[main.planner.LP.k.to]
	return _map_rect(p.x, p.z, 30)


func _speed_rect() -> Variant:
	var r: Variant = null
	for b in main.hud._speed_btns.slice(1):
		var q: Variant = _ctl_rect(b)
		if q != null:
			r = q if r == null else (r as Rect2).merge(q)
	return r


func _on_trip() -> bool:
	return not main.planner.on and _sim().CO.jobs.any(func(j): return not j.get("ret"))


# ====================================================================== drawing
func _draw() -> void:
	if _rect == null:
		return
	var r: Rect2 = (_rect as Rect2).grow(6)
	var vs := size
	var dim := Color(2 / 255.0, 6 / 255.0, 10 / 255.0, .38)
	draw_rect(Rect2(0, 0, vs.x, r.position.y), dim)
	draw_rect(Rect2(0, r.end.y, vs.x, vs.y - r.end.y), dim)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dim)
	draw_rect(Rect2(r.end.x, r.position.y, vs.x - r.end.x, r.size.y), dim)
	var f := fmod(_t * .8, 1.0)
	var pulse := StyleBoxFlat.new()
	pulse.draw_center = false
	pulse.set_corner_radius_all(12)
	pulse.set_border_width_all(2)
	pulse.border_color = Color(Ui.ACCENT, .55 * (1 - f))
	pulse.draw(get_canvas_item(), r.grow(3 + f * 12))
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_corner_radius_all(10)
	frame.set_border_width_all(2)
	frame.border_color = Ui.ACCENT
	frame.shadow_color = Color(Ui.ACCENT, .35)
	frame.shadow_size = 8
	frame.draw(get_canvas_item(), r)
	# the «Сюди» chip above the block (below it when there is no room)
	if not steps[i].get("next", false):
		var font := Ui.font("body", 700)
		var t := I18n.t("Сюди")
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18
		var y := r.position.y - 26 - sin(_t * 4) * 3
		if y < 70:
			y = r.end.y + 6 + sin(_t * 4) * 3
		var chip := Rect2(r.get_center().x - w / 2, y, w, 22)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Ui.ACCENT
		sb.set_corner_radius_all(11)
		sb.draw(get_canvas_item(), chip)
		draw_string(font, Vector2(chip.position.x + 9, chip.position.y + 15.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.ACCENT_INK)
