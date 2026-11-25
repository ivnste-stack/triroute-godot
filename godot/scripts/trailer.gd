class_name Trailer
extends Node
## --trailer=<scene>: one scene of the game's trailer, played by itself and recorded by Movie Maker
## (godot --write-movie scene.avi --fixed-fps 60 --resolution 1920x1080 -- --company --stress … --trailer=…).
## The game's interface is hidden; over the map an English overlay: the company's cash (it ticks up with every
## delivery and drops with every mishap), callouts at the events on the map, captions. The camera follows a
## path of keys; events are fired at their second. The scene prints the frames it starts and ends at, so the
## recording can be cut to it (tools/trailer.sh).

const FPS := 60.0
const WARM := 45   # frames before the scene starts: the map, the trips and the lines settle

var main: Node
var scene := ""
var sim: Sim
var cam: MapCamera
var dur := 8.0
var keys := []        # [t, x, z, dist, yaw]
var follow: Callable  # → Vector2: the camera's point, when it follows something moving
var caps := []        # [t0, t1, text, kind: "cap" | "title"]
var events := []      # [t, Callable]
var show_cash := true
var night_from := -1.0
var night_to := -1.0

var _f := 0
var _t := 0.0
var _fired := {}
var _ov: CanvasLayer
var _cash: Label
var _cash_cap: Label
var _cash_box: Control
var _cash_shown := 0.0
var _cash_last := 0.0
var _cash_acc := 0.0
var _cash_acc_t := 0.0
var _flash := 0.0
var _flash_col := Color.WHITE
var _cap: Label
var _title: VBoxContainer
var _dim: ColorRect
var _floats := []     # [Label, age]
var _drop_ok := -1.0  # until this second a big drop of the money is shown as it is (an event's)
var _calls := []      # [Control, world Vector2, t0]

const GREEN := Color("#5bd68c")
const RED := Color("#f0625f")
const AMBER := Color("#f1c453")
const ICE := Color("#8fe3ff")


func _init(main_: Node, scene_: String) -> void:
	main = main_
	scene = scene_


func _ready() -> void:
	process_priority = 100
	sim = main.session.sim
	cam = main.map.camera
	main._ui.visible = false
	sim.auto_choice = 0   # the game's decisions answer themselves
	sim.CO.sandbox = false
	Settings._values.daynight = false
	# trips at every stage: filled, a day played, filled again…
	for i in 3:
		_fill(TRIPS)
		main.session.run_days(1)
	_fill(TRIPS)
	print("TRAILER trips %d" % sim.CO.jobs.size())
	# the money of the scene from here; the month does not turn while it plays (its wages only where staged)
	sim.CO.cash = 24_850_000.0
	sim.date.d = mini(int(sim.date.d), 10)
	main.session.day_passed.connect(func(_d): _fill(TRIPS))
	main.session.set_speed(3)
	_overlay()
	match scene:
		"intro": _intro()
		"network": _network()
		"pirates": _pirates()
		"border": _border()
		"storm": _storm()
		"money": _money()
		"night": _night()
		"end": _end()
	_cash_shown = sim.CO.cash
	_cash_last = sim.CO.cash
	_cash_box.visible = show_cash
	_place(0.0)


## many trips at once: the board filled and every order that can go sent, over and over until the company has
## this many trips on the way
const TRIPS := 520


func _fill(want: int) -> void:
	for i in 220:
		if sim.CO.jobs.size() >= want:
			break
		sim.co_board_day()
		for k in sim.CO.board.duplicate():
			var P: Dictionary = sim.co_plan(k)
			if P.ok:
				sim.co_dispatch(k, P, true)
			else:
				sim.CO.board.erase(k)   # it would hold a place on the board: a new order comes instead


func _process(_delta: float) -> void:
	_f += 1
	if _f == WARM:
		print("TRAILER START %d" % Engine.get_process_frames())
	if _f < WARM:
		_place(0.0)
		return
	_t = (_f - WARM) / FPS
	_place(_t)
	for i in events.size():
		if not _fired.has(i) and _t >= events[i][0]:
			_fired[i] = true
			events[i][1].call()
	if night_from >= 0:
		main.map.night_hour = lerpf(night_from, night_to, clampf(_t / dur, 0, 1))
	_tick_overlay(1.0 / FPS)
	if _t >= dur:
		print("TRAILER END %d" % Engine.get_process_frames())
		get_tree().quit()


## the camera at time t: its keys eased one into the next (a smootherstep between each two)
func _place(t: float) -> void:
	if keys.is_empty():
		return
	var a: Array = keys[0]
	var b: Array = keys[0]
	for i in keys.size():
		if keys[i][0] <= t:
			a = keys[i]
			b = keys[mini(i + 1, keys.size() - 1)]
	var f := 0.0 if b[0] <= a[0] else clampf((t - a[0]) / (b[0] - a[0]), 0, 1)
	f = f * f * f * (f * (f * 6 - 15) + 10)
	var x: float = lerpf(a[1], b[1], f)
	var z: float = lerpf(a[2], b[2], f)
	if follow.is_valid():
		var p: Vector2 = follow.call()
		x += p.x
		z += p.y
	var d: float = lerpf(a[3], b[3], f)
	var y: float = lerpf(a[4], b[4], f)
	cam.tx = x
	cam.ttx = x
	cam.tz = z
	cam.ttz = z
	cam.dist = d
	cam.tdist = d
	cam.yaw = y
	cam.tyaw = y


# ---------------------------------------------------------------- the scenes
func _intro() -> void:   # the Earth: from the whole world down to the busy Atlantic
	dur = 8.0
	show_cash = false
	keys = [[0.0, 0.0, 0.6, 33.0, 0.0], [8.0, -1.6, -1.4, 15.0, 0.18]]
	caps = [[1.0, 7.4, "BUILD A GLOBAL LOGISTICS EMPIRE", "cap"]]


func _network() -> void:   # low over a busy region: trucks, trains, ships and planes everywhere
	dur = 10.0
	var c := _densest()
	keys = [[0.0, c.x - 2.2, c.y + .6, 7.5, -.25], [10.0, c.x + 1.8, c.y - .4, 5.2, .3]]
	caps = [[1.2, 4.8, "TRUCKS · TRAINS · SHIPS · PLANES", "cap"], [5.6, 9.6, "THOUSANDS OF THEM. ALL YOURS.", "cap"]]


func _pirates() -> void:   # a ship of the company, pirates close in, the ship is seized
	dur = 8.0
	var js: Array = sim.CO.jobs.filter(func(j): return j.mode == "sea" and not j.get("ret"))
	if js.is_empty():
		_network()
		return
	js.sort_custom(func(a, b): return a.tot - (sim.co_now() - a.t0) > b.tot - (sim.co_now() - b.t0))   # the most way left
	var j: Dictionary = js[0]
	var at := func() -> Vector2:
		var q := sim.co_pos_at(j, sim.co_job_state(j, sim.co_now() - j.t0).s)
		return Vector2(q[0], q[1])
	var p0: Vector2 = at.call()
	sim.CO.pir.append({"id": sim.CO.uid, "x": p0.x + .35, "z": p0.y - .2, "r": .8, "cid": 0, "name": "open sea"})
	sim.CO.uid += 1
	sim.inc_changed()
	follow = at
	keys = [[0.0, .0, .25, 6.5, .1], [8.0, .0, .2, 4.2, -.05]]
	caps = [[.6, 3.6, "EVERY ROUTE IS A GAMBLE", "cap"]]
	events = [[2.4, func():
		sim.co_incident(j, "pir")
		_callout(at.call(), "PIRATE ATTACK", RED)]]


func _border() -> void:   # two states close the border between them, trips stop at it
	dur = 7.0
	var pair := _busy_border()
	var a: int = pair[0]
	var b: int = pair[1]
	var m: Vector2 = pair[2]
	keys = [[0.0, m.x - .8, m.y + .5, 7.8, .12], [7.0, m.x + .4, m.y + .1, 5.6, -.08]]
	caps = [[.5, 3.4, "BORDERS CLOSE OVERNIGHT", "cap"]]
	events = [[1.6, func():
		sim.CO.cls.append({"id": sim.CO.uid, "kind": "pair", "a": a, "b": b, "why": "Political crisis", "until": sim.co_now() + 30})
		sim.CO.uid += 1
		sim.inc_changed()
		sim.inc_blk()
		_callout(m, "BORDER CLOSED", RED)]]


func _storm() -> void:   # a hurricane over a port
	dur = 7.0
	var ports: Array = sim.PL.filter(func(p): return p.port != null and sim.hub_at(p.id) != null)
	if ports.is_empty():
		ports = sim.PL.filter(func(p): return p.port != null)
	var P: Dictionary = ports[0]
	var best := -1
	for p in ports:   # the port with the most trips around it
		var n := 0
		for j in sim.CO.jobs:
			if JS.hypot(sim.PL[j.k.from].x - p.x, sim.PL[j.k.from].z - p.z) < 2 or JS.hypot(sim.PL[j.k.to].x - p.x, sim.PL[j.k.to].z - p.z) < 2:
				n += 1
		if n > best:
			best = n
			P = p
	var at := Vector2(P.x + .3, P.z - .2)
	keys = [[0.0, at.x + .9, at.y + .7, 7.5, -.15], [7.0, at.x, at.y + .2, 5.0, .1]]
	caps = [[.5, 3.4, "STORMS SHUT DOWN PORTS", "cap"]]
	events = [[1.2, func():
		var T := sim.co_now()
		sim.CO.wx.append({"id": sim.CO.uid, "k": "hur", "n": "Ураган", "x": at.x, "z": at.y, "r": 1.0, "t0": T, "until": T + 5, "on": 1, "near": P.name, "mine": true})
		sim.CO.uid += 1
		sim.inc_changed()
		sim.inc_blk()
		_callout(at, "HURRICANE", AMBER)]]


func _money() -> void:   # the whole company from above at full speed: money in, money out
	dur = 9.0
	var c := _busiest()
	keys = [[0.0, c.x, c.y + .5, 15.0, 0.0], [9.0, c.x + .6, c.y, 11.5, .15]]
	caps = [[.6, 4.4, "PROFIT...", "cap"], [4.8, 8.6, "...OR RUIN", "cap"]]
	var hit := func(type: String, text: String) -> void:
		var js: Array = sim.CO.jobs.filter(func(j): return j.mode == "road" and not j.get("ret") and j.get("hold", 0) <= 0)
		if js.is_empty():
			return
		var j: Dictionary = js[int(floor(randf() * js.size()))]
		var q := sim.co_pos_at(j, sim.co_job_state(j, sim.co_now() - j.t0).s)
		sim.co_incident(j, type)
		_callout(Vector2(q[0], q[1]), text, RED)
	events = [[4.9, func(): hit.call("theft", "CARGO STOLEN")], [6.2, func(): hit.call("acc", "ACCIDENT")],
		[7.3, func():
			_drop_ok = _t + 1.0
			sim.CO.cash -= 1_250_000.0   # the month's wages
			_callout(Vector2(c.x - 2, c.y + 1.2), "PAYDAY: WAGES", AMBER)]]


func _night() -> void:   # night falls, the cities light up, the trips go on
	dur = 6.0
	show_cash = false
	Settings._values.daynight = true
	night_from = 18.6
	night_to = 22.5
	var c := _densest()
	keys = [[0.0, c.x + 1.2, c.y + .4, 9.0, .25], [6.0, c.x - .8, c.y, 7.0, -.1]]
	caps = [[.8, 5.4, "THE WORLD NEVER SLEEPS", "cap"]]


func _end() -> void:   # the title over the world
	dur = 6.0
	show_cash = false
	keys = [[0.0, 0.0, .6, 30.0, -.06], [6.0, 0.0, .5, 26.0, .04]]
	caps = [[.8, 6.0, "TRIROUTE", "title"]]


## the densest spot of the trips: the square of the map (2 × 2 world units) with the most vehicles now
func _densest() -> Vector2:
	var cnt := {}
	var sum := {}
	for j in sim.CO.jobs:
		var q := sim.co_pos_at(j, sim.co_job_state(j, sim.co_now() - j.t0).s)
		var k := Vector2i(int(floor(q[0] / 2.0)), int(floor(q[1] / 2.0)))
		cnt[k] = cnt.get(k, 0) + 1
		sum[k] = sum.get(k, Vector2.ZERO) + Vector2(q[0], q[1])
	var best: Variant = null
	for k in cnt:
		if best == null or cnt[k] > cnt[best]:
			best = k
	return sum[best] / cnt[best] if best != null else Vector2.ZERO


## the centre of the trips: where most of them are now
func _busiest() -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for j in sim.CO.jobs:
		var q := sim.co_pos_at(j, sim.co_job_state(j, sim.co_now() - j.t0).s)
		s += Vector2(q[0], q[1])
		n += 1
	return s / maxf(1, n) if n else Vector2.ZERO


## two neighbouring states with the most trips between them, and a point on their border
func _busy_border() -> Array:
	var cnt := {}
	for j in sim.CO.jobs:
		var a: int = sim.PL[j.k.from].cid
		var b: int = sim.PL[j.k.to].cid
		# only states that border each other: their border is drawn closed
		if a != b and a < sim.neighbors.size() and Array(sim.neighbors[a]).has(b):
			var k := "%d:%d" % [mini(a, b), maxi(a, b)]
			cnt[k] = cnt.get(k, 0) + 1
	var best := ""
	for k in cnt:
		if best == "" or cnt[k] > cnt[best]:
			best = k
	var a := 0
	var b := 1
	if best != "":
		var p := best.split(":")
		a = int(p[0])
		b = int(p[1])
	# the closest pair of their towns: the border lies between them
	var m := Vector2.ZERO
	var bd := 1e9
	for p in sim.PL:
		if p.cid != a:
			continue
		for q in sim.PL:
			if q.cid == b:
				var d := JS.hypot(p.x - q.x, p.z - q.z)
				if d < bd:
					bd = d
					m = Vector2((p.x + q.x) / 2, (p.z + q.z) / 2)
	return [a, b, m]


# ---------------------------------------------------------------- the overlay
func _overlay() -> void:
	_ov = CanvasLayer.new()
	_ov.layer = 60
	add_child(_ov)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.add_child(root)
	# a cinematic vignette
	var vg := ColorRect.new()
	vg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ vec2 d = UV - .5; float v = smoothstep(.35, .85, length(d * vec2(1.2, 1.))); COLOR = vec4(0., .01, .02, v * .6); }"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vg.material = mat
	root.add_child(vg)
	# the cash
	_cash_box = VBoxContainer.new()
	_cash_box.add_theme_constant_override("separation", -6)
	_cash_box.position = Vector2(64, 52)
	_cash_cap = Label.new()
	_cash_cap.text = "COMPANY CASH"
	_cash_cap.add_theme_font_override("font", Ui.font("body", 700, 6))
	_cash_cap.add_theme_font_size_override("font_size", 22)
	_cash_cap.add_theme_color_override("font_color", Color(ICE, .85))
	_cash = Label.new()
	_cash.add_theme_font_override("font", Ui.font("display", 700))
	_cash.add_theme_font_size_override("font_size", 64)
	_cash.add_theme_color_override("font_outline_color", Color(0, 0, 0, .55))
	_cash.add_theme_constant_override("outline_size", 10)
	_cash_box.add_child(_cash_cap)
	_cash_box.add_child(_cash)
	root.add_child(_cash_box)
	# the caption
	_cap = Label.new()
	_cap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap.add_theme_font_override("font", Ui.font("display", 700, 10))
	_cap.add_theme_font_size_override("font_size", 58)
	_cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, .6))
	_cap.add_theme_constant_override("outline_size", 14)
	_cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .5))
	_cap.add_theme_constant_override("shadow_offset_y", 4)
	root.add_child(_cap)
	# the title card, over the map darkened
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.color = Color(0, .01, .02, 0)
	root.add_child(_dim)
	_title = VBoxContainer.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # the whole screen, its lines centred
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.alignment = BoxContainer.ALIGNMENT_CENTER
	_title.visible = false
	for spec in [["TRIROUTE", "display", 150, 34, Color.WHITE], ["LOGISTICS STRATEGY", "body", 34, 18, ICE], ["COMING SOON", "body", 26, 14, Color(1, 1, 1, .7)]]:
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", Ui.font(spec[1], 700, spec[3]))
		l.add_theme_font_size_override("font_size", spec[2])
		l.add_theme_color_override("font_color", spec[4])
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, .5))
		l.add_theme_constant_override("outline_size", 12)
		_title.add_child(l)
	root.add_child(_title)


func _money_s(x: float) -> String:
	var s := str(int(round(absf(x))))
	var o := ""
	while s.length() > 3:
		o = "," + s.substr(s.length() - 3) + o
		s = s.substr(0, s.length() - 3)
	return ("-$" if x < 0 else "$") + s + o


func _tick_overlay(dt: float) -> void:
	var root: Control = _ov.get_child(0)
	var vw := root.size
	# the cash: shown ticking towards the real one; every change makes a floating sum and a flash
	# the day's running costs of a fleet this size come as one big drop at midnight: in the trailer the money
	# falls with the events only (they open a window for it), the rest is mostly given back
	var cash: float = sim.CO.cash
	if cash - _cash_last < -150000 and _t > _drop_ok:
		sim.CO.cash -= (cash - _cash_last) * .95
		cash = sim.CO.cash
	var d := cash - _cash_last
	_cash_last = cash
	_cash_acc += d
	_cash_acc_t += dt
	if _cash_acc_t > .5 and absf(_cash_acc) >= 4000 and show_cash:
		_float(_cash_acc)
		_flash = 1.0
		_flash_col = GREEN if _cash_acc > 0 else RED
		_cash_acc = 0
		_cash_acc_t = 0
	elif _cash_acc_t > .5:
		_cash_acc_t = 0
	_cash_shown += (cash - _cash_shown) * minf(1, dt * 7)
	_cash.text = _money_s(_cash_shown)
	_flash = maxf(0, _flash - dt * 2.2)
	_cash.add_theme_color_override("font_color", Color.WHITE.lerp(_flash_col, _flash))
	_cash_box.scale = Vector2.ONE * (1 + .05 * _flash)
	for f in _floats.duplicate():
		f[1] += dt
		var l: Label = f[0]
		l.position.y -= dt * 46
		l.modulate.a = clampf(1.6 - f[1], 0, 1)
		if f[1] > 1.6:
			l.queue_free()
			_floats.erase(f)
	# the caption
	var txt := ""
	var a := 0.0
	var kind := "cap"
	for c in caps:
		if _t >= c[0] and _t <= c[1]:
			txt = c[2]
			kind = c[3]
			a = minf(clampf((_t - c[0]) / .35, 0, 1), clampf((c[1] - _t) / .35, 0, 1))
	_title.visible = kind == "title" and a > 0
	_dim.color.a = .62 * a if kind == "title" else 0.0
	if kind == "title":
		_title.modulate.a = a
		_title.scale = Vector2.ONE * (1.0 + .04 * (1 - a))
		_title.pivot_offset = _title.size / 2
		_cap.visible = false
	else:
		_cap.visible = a > 0
		_cap.text = txt
		_cap.modulate.a = a
		_cap.size = Vector2(vw.x, 80)
		_cap.position = Vector2(0, vw.y - 170 + 18 * (1 - a))
	# the callouts follow their place on the map
	for c in _calls.duplicate():
		var n: Control = c[0]
		var age: float = _t - c[2]
		var p: Vector3 = Vector3(c[1].x, 0, c[1].y)
		if cam.is_position_behind(p) or age > 3.2:
			n.visible = false
			if age > 3.2:
				n.queue_free()
				_calls.erase(c)
			continue
		var s := cam.unproject_position(p)
		var k := clampf(age / .18, 0, 1)
		n.visible = true
		n.modulate.a = minf(k, clampf((3.2 - age) / .4, 0, 1))
		n.scale = Vector2.ONE * (.6 + .4 * k + .08 * sin(minf(age, .6) * 10) * (1 - minf(age / .6, 1)))
		n.pivot_offset = Vector2(n.size.x / 2, n.size.y)
		n.position = s - Vector2(n.size.x / 2, n.size.y + 34)


func _float(x: float) -> void:
	var l := Label.new()
	l.text = ("+" if x > 0 else "") + _money_s(x)
	l.add_theme_font_override("font", Ui.font("display", 700))
	l.add_theme_font_size_override("font_size", 34 if absf(x) < 100000 else 44)
	l.add_theme_color_override("font_color", GREEN if x > 0 else RED)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, .6))
	l.add_theme_constant_override("outline_size", 8)
	# a column beside the cash: a new sum below the ones still rising
	l.position = _cash_box.position + Vector2(_cash.size.x + 30, 30 + 46 * _floats.size())
	_ov.get_child(0).add_child(l)
	_floats.append([l, 0.0])


func _callout(at: Vector2, text: String, col: Color) -> void:
	_drop_ok = _t + 1.0
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Color(col.r * .25, col.g * .12, col.b * .12, .92), col, 3, Vector4(26, 12, 26, 12)))
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Ui.font("display", 700, 6))
	l.add_theme_font_size_override("font_size", 38)
	l.add_theme_color_override("font_color", col.lightened(.3))
	p.add_child(l)
	p.visible = false
	_ov.get_child(0).add_child(p)
	_calls.append([p, at, _t])
