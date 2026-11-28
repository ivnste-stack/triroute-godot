class_name TrailerStory
extends Node
## --story: the game's trailer as one scripted take, recorded by Movie Maker (tools/trailer_story.sh): the camera,
## the trips, the windows and the clicks of a cursor follow a script shot by shot at a steady 60 fps; the money
## in the top bar climbs from $3 thousand to $1 billion, slowly and then ever faster. Every shot prints its
## second (STORY …), for the subtitles laid on afterwards (tools/subtitles.py).
##   1 the world from afar (the logistics layer) → down to the headquarters in a central state, turning right;
##     a truck leaves and the camera follows it to the delivery, then draws back
##   2 a train in another state, followed for a few seconds while the camera circles it
##   3 the exchange: scrolled down through the orders, «Прокласти маршрут» on one
##   4 the route planner: the shortest road (a toll motorway, a closure), «Без платних», back, «Відправити»
##   5 a ship at sea: the camera circles it, then follows it towards a pirates' zone, then glides over the map
##     while the hubs open town after town
##   6 the whole map: trips of every kind, «Рейси в дорозі» with loading, on the road, unloading
##   7 the fleet: a truck, a tanker, a freight train and a plane bought; the staff: two hired
##   8 the company: the licences from grey to obtainable, then all of them obtained
##   9 the map's centre close up, a vehicle for every hub, turned right; back to the standard view
## --storypeek=t1,t2… --storyout=DIR: PNGs at those seconds (a check without a video); --storyfrom=N: from shot N.

const FPS := 60.0
const TOTAL := 96.0          # the length the money counter is spread over
const WARM := 40             # frames before the story starts: the map and the trips settle
const D = preload("res://scripts/logistics/game_data.gd")

var main: Node
var sim: Sim
var cam: MapCamera
var T := 0.0                 # the story's seconds
var _f := 0
var _started := false
var _peeks: Array = []
var _out := ""
var _cursor: Node2D
var _ring := 0.0             # the cursor's click ring (seconds left)
var _shot := 0
var _from := 1
var _keep := false   # a window being clicked through: it does not build itself again under the cursor


func _init(main_: Node) -> void:
	main = main_


func _ready() -> void:
	process_priority = 100
	sim = main.session.sim
	cam = main.map.camera
	var a: Dictionary = main._args
	for p in String(a.get("storypeek", "")).split(",", false):
		_peeks.append(float(p))
	_peeks.sort()
	_out = String(a.get("storyout", "user://story"))
	_from = int(a.get("storyfrom", "1"))
	DirAccess.make_dir_recursive_absolute(_out)
	# the picture: the logistics layer, no dialogs or notifications, no legend, the decisions answer themselves
	sim.auto_choice = 0
	sim.modals = []
	main.toasts.visible = false
	main.map_ui.no_hover = true
	main.legend.modulate.a = 0
	main.hud.mode_dd.value = "grid"
	main.hud.mode_dd._show_value()
	main.map.set_mode("grid")
	Settings._values.daynight = false
	sim.CO.auto = false
	main.session.set_speed(2)
	main.hud.studio = {"cash": 3000.0, "lic": 1.0, "rating": 3.0, "del": 0.0}
	_cursor_make()


func _process(_delta: float) -> void:
	_f += 1
	if _f == WARM:
		print("STORY START %d" % Engine.get_process_frames())
		_started = true
		_run()
	if not _started:
		return
	T = (_f - WARM) / FPS
	# the money: $3 thousand to $1 billion over the whole take, slowly and then ever faster
	var p := clampf(T / TOTAL, 0, 1)
	var k := pow(p, 1.35)
	main.hud.studio.cash = 3000.0 * pow(1e9 / 3000.0, k)
	main.hud.studio.rating = lerpf(3.0, 4.85, _ss(p))          # the rating up with it
	main.hud.studio.del = roundf(4200.0 * (pow(1.0 + 99.0, k) - 1.0) / 99.0)   # the deliveries too, ever faster
	if _shot >= 8:   # the company's window shows the cash of the top bar
		sim.CO.cash = maxf(main.hud.studio.cash, 4e7)
	if main.modals.is_open():
		main.modals.clear()
	sim.modals = []
	if _ring > 0:
		_ring -= 1.0 / FPS
		_cursor.queue_redraw()
	while _peeks.size() and T >= _peeks[0]:
		var t: float = _peeks.pop_front()
		get_viewport().get_texture().get_image().save_png("%s/peek_%05.1f.png" % [_out, t])
		print("STORY PEEK %.1f" % t)


# ====================================================================== helpers
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await _frames(int(round(sec * FPS)))


static func _ss(f: float) -> float:   # smootherstep
	f = clampf(f, 0, 1)
	return f * f * f * (f * (f * 6 - 15) + 10)


func _put(x: float, z: float, d: float, y: float) -> void:
	cam.tx = x
	cam.ttx = x
	cam.tz = z
	cam.ttz = z
	cam.dist = d
	cam.tdist = d
	cam.yaw = y
	cam.tyaw = y


func _cam() -> Array:
	return [cam.tx, cam.tz, cam.dist, cam.yaw]


## the camera over `sec` seconds: f(p) → [x, z, dist, yaw] for p from 0 to 1 every frame
func _track(sec: float, f: Callable) -> void:
	var n := int(round(sec * FPS))
	for i in n + 1:
		var c: Array = f.call(float(i) / maxf(1, n))
		_put(c[0], c[1], c[2], c[3])
		if i < n:
			await get_tree().process_frame


func _shot_start(n: int, name: String) -> bool:
	_shot = n
	if n < _from:
		return false
	print("STORY SHOT %d %.2f %s" % [n, T, name])
	return true


func _cut() -> void:   # a cut between shots: windows and cards away
	if main.win.visible:
		main._toggle_window("")
	main.map_ui.close_card()
	main.map_ui.close_insp()
	_cursor.visible = false


## a trip without the company's vehicles, `secs` long at the story's speed (speed 2: a day is 30 s), already
## `done` of the way; hs — the loading and unloading (days)
func _trip(a: int, b: int, m: String, secs: float, done: float = 0.0, hs: float = .02) -> Variant:
	var rr: Variant = sim.co_route(m, a, b)
	if rr == null:
		return null
	var t := ""
	for x in D.VT:
		if D.VT[x].mode == m and not D.VT[x].get("loc", 0) and (t == "" or (m == "road" and x == "ltruck")):
			t = x
	var tm := secs / 30.0 - hs * 2
	var k := {"id": sim.CO.uid, "from": a, "to": b, "cg": "parcel", "tons": 4.0, "pay": 0, "dlDays": 99.0, "mode": m, "risk": .1, "minR": 0,
		"len": rr.len, "_demo": 1}
	sim.CO.uid += 1
	var A: Dictionary = sim.PL[a]
	var P := {"ok": true, "fuel": 0.0, "leadR": {"p": PackedFloat32Array([A.x, A.z]), "len": 0.0}, "main": rr, "t": t, "n": 1, "vids": [],
		"lead": 0.0, "tl": 0.0, "tm": maxf(.01, tm), "hs": hs, "cust": 0.0, "tot": maxf(.01, tm) + hs * 2}
	sim.co_dispatch(k, P, true)
	var j: Dictionary = sim.CO.jobs.back()
	j.t0 = sim.co_now() - done * j.tot
	return j


func _pos(j: Dictionary) -> Vector2:
	var q := sim.co_pos_at(j, sim.co_job_state(j, sim.co_now() - j.t0).s)
	return Vector2(q[0], q[1])


## towns of a kind of transport within a distance of a point (on its land for road and rail)
func _towns(m: String, at: Dictionary, dmin: float, dmax: float) -> Array:
	return sim.PL.filter(func(p):
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		return p.id != at.id and d >= dmin and d <= dmax and sim.node_ok(m, p) and ((m != "road" and m != "rail") or p.land == at.land))


func _button(root: Node, text: String, last: bool = false) -> Button:
	var found: Button = null
	for b in root.find_children("*", "Button", true, false):
		if b is Button and b.visible and b.is_visible_in_tree() and String(b.text).begins_with(text):
			if found == null or (last and b.get_global_rect().position.y > found.get_global_rect().position.y):
				found = b
			if not last:
				return found
	return found


# ====================================================================== the cursor
func _cursor_make() -> void:
	var L := CanvasLayer.new()
	L.layer = 128
	add_child(L)
	_cursor = Node2D.new()
	_cursor.visible = false
	_cursor.draw.connect(func():
		var s := 1.4
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 17), Vector2(4.5, 13), Vector2(7.5, 20), Vector2(10, 19), Vector2(7, 12), Vector2(12.5, 12)])
		for i in pts.size():
			pts[i] *= s
		if _ring > 0:
			var f := 1.0 - _ring / .35
			_cursor.draw_arc(Vector2.ZERO, 8 + f * 22, 0, TAU, 32, Color(1, 1, 1, .8 * (1 - f)), 2.5, true)
		_cursor.draw_colored_polygon(pts, Color.WHITE)
		pts.append(pts[0])
		_cursor.draw_polyline(pts, Color(0.02, 0.05, 0.08), 1.6, true))
	L.add_child(_cursor)


func _cursor_to(p: Vector2, sec: float = .6) -> void:
	if not _cursor.visible:
		_cursor.position = p + Vector2(120, 80)
		_cursor.visible = true
	var a := _cursor.position
	var n := int(round(sec * FPS))
	for i in n + 1:
		_cursor.position = a.lerp(p, _ss(float(i) / maxf(1, n)))
		await get_tree().process_frame


## the cursor to a button, a click: the ring and the button's own action
func _click(b: Variant, sec: float = .6) -> void:
	if b == null or not is_instance_valid(b):
		return
	var text: String = b.text
	var at: Vector2 = b.get_global_rect().get_center()
	await _cursor_to(at, sec)
	_ring = .35
	await _wait(.12)
	if not is_instance_valid(b):   # the window was built again meanwhile: the same button in it, nearest the cursor
		b = _near_button(text, at)
	if b != null and not b.disabled:
		b.pressed.emit()
		main._win_tick(true)   # the window shows what the click did (it does not build itself again meanwhile)
	await _wait(.2)


func _near_button(text: String, at: Vector2) -> Button:
	var best: Button = null
	var bd := 1e9
	for root in [main.win, main.planner, main.hud]:
		for x in root.find_children("*", "Button", true, false):
			if x is Button and x.is_visible_in_tree() and x.text == text:
				var d: float = x.get_global_rect().get_center().distance_to(at)
				if d < bd:
					bd = d
					best = x
	return best


## a window's list scrolled to show a control (its top a third down the window), smoothly
func _scroll_to(c: Variant, sec: float) -> void:
	if not is_instance_valid(c):
		return
	var sc: ScrollContainer = main.win.scroll
	var bar := sc.get_v_scroll_bar()
	var top := maxf(0, bar.max_value - bar.page)
	var to := clampf(sc.scroll_vertical + c.get_global_rect().position.y - sc.get_global_rect().position.y - sc.size.y * .3, 0, top)
	await _scroll(to, sec)


func _scroll(to: float, sec: float) -> void:
	var sc: ScrollContainer = main.win.scroll
	sc.hold = true
	var a := float(sc.scroll_vertical)
	var n := int(round(sec * FPS))
	for i in n + 1:
		sc.scroll_vertical = int(round(lerpf(a, to, _ss(float(i) / maxf(1, n)))))
		await get_tree().process_frame
	sc.hold = _keep


# ====================================================================== the story
func _run() -> void:
	var CO: Dictionary = sim.CO
	var HQ: Dictionary = sim.PL[CO.hq]
	var W: Vector2 = cam.world_size
	if _from >= 6:   # started past shot 5: the hubs it opens, open already
		for p in sim.PL:
			if sim.hub_at(p.id) == null:
				CO.hubs.append({"pid": p.id, "lvl": 1, "share": .01, "mk": 0})
		main.map.company_colors()

	# ---- 1: from afar down to the headquarters, turning right; a truck leaves, followed to the delivery
	if _shot_start(1, "the world → the headquarters, a truck"):
		var far := W.x * 1.15
		var tos: Array = _towns("road", HQ, 1.6, 2.6).filter(func(p): return sim.co_route("road", HQ.id, p.id) != null)
		var dest: Dictionary = tos[0] if tos.size() else HQ
		var start := [0.0, .6, far, 0.0]
		var close := [HQ.x, HQ.z, 4.2, .75]
		var truck: Variant = null
		await _track(7.0, func(p):
			var e := _ss(p)
			var dz := 1.0 - pow(1.0 - p, 2.2)   # the zoom leads, the turn and the move ease in with it
			return [lerpf(start[0], close[0], e), lerpf(start[1], close[1], e), lerpf(start[2], close[2], dz), lerpf(start[3], close[3], e)])
		truck = _trip(HQ.id, dest.id, "road", 7.5, 0.0, .01)
		if truck != null:
			var c0 := _cam()
			await _track(7.4, func(p):   # follows the truck: the point eases onto it, then stays on it
				var q := _pos(truck)
				var e := _ss(minf(1.0, p * 3))
				return [lerpf(c0[0], q.x, e), lerpf(c0[1], q.y, e), lerpf(c0[2], 3.6, _ss(p)), c0[3] + .25 * p])
			var c1 := _cam()
			await _track(1.6, func(p): return [c1[0], c1[1], lerpf(c1[2], 5.8, _ss(p)), c1[3]])   # a little back

	# ---- 2: a train in another state, circled
	if _shot_start(2, "a train in another state"):
		var tr: Variant = null
		var rails: Array = sim.PL.filter(func(p): return p.rail and p.cid != HQ.cid)
		rails.sort_custom(func(x, y): return Vector2(x.x - HQ.x, x.z - HQ.z).length() < Vector2(y.x - HQ.x, y.z - HQ.z).length())
		for A in rails.slice(0, 30):
			for B in _towns("rail", A, 2.0, 5.0).slice(0, 6):
				tr = _trip(A.id, B.id, "rail", 16.0, .25)
				if tr != null:
					break
			if tr != null:
				break
		if tr != null:
			_cut()
			var y0 := cam.yaw
			await _track(4.6, func(p):
				var q := _pos(tr)
				return [q.x, q.y, lerpf(2.6, 2.2, p), y0 + 1.5 * _ss(p)])

	# ---- 3: the exchange, scrolled through, «Прокласти маршрут» on an order whose road has a toll motorway
	var order: Variant = null
	if _shot_start(3, "the exchange"):
		_cut()
		CO.veh.append({"id": CO.uid, "t": "ltruck", "loc": CO.hq, "st": "idle", "cond": 100.0, "km": 0.0})   # who would drive it
		CO.uid += 1
		CO.staff.driver += 1
		# a full exchange: orders of the larger licences too (their cards say which), the newest first
		var t0: int = CO.tier
		CO.tier = 3
		for i in 60:
			if CO.board.size() >= 22:
				break
			var k: Variant = sim.co_gen()
			if k != null:
				if not k.has("exp"):
					k.exp = sim.day + 3 + (i % 8)
				CO.board.append(k)
		CO.tier = t0
		order = _toll_order(HQ)
		_put(HQ.x + 1.5, HQ.z + .8, 7.0, .2)
		main._toggle_window("coJobs")
		await _wait(.8)
		var sc: ScrollContainer = main.win.scroll
		var bar := sc.get_v_scroll_bar()
		await _scroll(maxf(0, bar.max_value - bar.page), 5.5)   # the many orders
		await _wait(.4)
		var pb := _button(main.win, "Прокласти маршрут", true)   # the last card: the order of the story
		await _click(pb, .8)
		await _wait(.3)

	# ---- 4: the planner: the shortest road (a toll motorway and a closure on it), «Без платних», back, «Відправити»
	if _shot_start(4, "the route planner"):
		if not main.planner.on and order != null:
			main._toggle_window("")
			main.planner.open(order)
		if main.planner.on:   # the order the planner opened on (the clicked card's)
			order = main.planner.LP.get("k", order)
		await _wait(.8)
		if order != null:
			var B: Dictionary = sim.PL[order.to]
			await _cursor_to(cam.unproject_position(Vector3(B.x, 0, B.z)), .9)
			_ring = .35
			await _wait(.12)
			main.planner.add(order.to)
			await _wait(2.6)
			await _click(_button(main.planner, "Без платних"), .7)
			await _wait(2.2)
			await _click(_button(main.planner, "Найкоротші"), .6)
			await _wait(1.4)
			await _click(_button(main.planner, "Відправити"), .8)
			await _wait(1.0)
		_cursor.visible = false

	# ---- 5: a ship circled, followed towards the pirates, then over the map while the hubs open
	if _shot_start(5, "a ship, the pirates, the hubs"):
		_cut()
		if main.planner.on:
			main.planner.close("")
		var ship: Variant = null
		var ports: Array = sim.PL.filter(func(p): return p.port != null)
		for A in ports:
			for B in _towns("sea", A, 5.0, 11.0).slice(0, 5):
				ship = _trip(A.id, B.id, "sea", 40.0, .3)
				if ship != null:
					break
			if ship != null:
				break
		if ship != null:
			var j: Dictionary = ship
			var s_ahead: float = sim.co_job_state(j, sim.co_now() - j.t0).s + j.len * .18   # the pirates ahead on its course
			var pa := sim.co_pos_at(j, s_ahead)
			CO.pir.append({"id": CO.uid, "x": pa[0], "z": pa[1], "r": .75, "cid": 0, "name": "відкрите море"})
			CO.uid += 1
			sim.inc_changed()
			var y0 := cam.yaw
			await _track(4.2, func(p):   # circling it
				var q := _pos(j)
				return [q.x, q.y, 2.3, y0 + 2.2 * _ss(p)])
			var y1 := cam.yaw
			await _track(3.4, func(p):   # following it, the zone ahead in the picture
				var q := _pos(j)
				return [q.x, q.y, lerpf(2.3, 4.0, _ss(p)), y1])
			# leaving it: over the map, the hubs opening town after town
			var c0 := _cam()
			var to := Vector2(HQ.x, HQ.z)
			var q: Array = sim.PL.filter(func(p): return sim.hub_at(p.id) == null)
			q.sort_custom(func(a, b): return Vector2(a.x - to.x, a.z - to.y).length() < Vector2(b.x - to.x, b.z - to.y).length())
			var opened := 0
			var n := int(5.5 * FPS)
			for i in n + 1:
				var p := float(i) / n
				var e := _ss(p)
				_put(lerpf(c0[0], to.x, e), lerpf(c0[1], to.y, e), lerpf(c0[2], 9.5, e), lerpf(c0[3], c0[3] + .4, e))
				var want := int(q.size() * clampf((p - .1) / .85, 0, 1))
				var added := false
				while opened < want:
					CO.hubs.append({"pid": q[opened].id, "lvl": 1, "share": .01, "mk": 0})
					opened += 1
					added = true
				if added and i % 6 == 0:
					main.map.company_colors()
				await get_tree().process_frame
			main.map.company_colors()

	# ---- 6: the whole map, trips of every kind; «Рейси в дорозі»: loading, on the road, unloading
	if _shot_start(6, "the whole map, the trips"):
		_cut()
		_clear_trips()
		_put(0.0, .6, W.x * .66, 0.0)
		_trips_mix(30)
		await _wait(2.4)
		# the list: loading (0), on the road, unloading (.76) — of every kind; made as the window opens, so the
		# phases are those on the screen (a trip is 24 s, loading and unloading 6 s each)
		_clear_trips()
		_trips_mix(30)
		main._toggle_window("coTrips")
		await _wait(.6)
		var sc: ScrollContainer = main.win.scroll
		var bar := sc.get_v_scroll_bar()
		await _scroll(minf(maxf(0, bar.max_value - bar.page), 900.0), 4.2)
		await _wait(1.0)

	# ---- 7: the fleet: a truck, a tanker, a freight train, a plane; the staff: two hired
	if _shot_start(7, "buying vehicles, hiring"):
		_keep = true
		main.win.scroll.hold = true
		CO.tier = D.LIC.size() - 1   # every vehicle buyable (the top bar keeps showing the first licence)
		CO.cash = 1e12
		main._toggle_window("coFleet")
		await _wait(.8)
		for name in ["Вантажна машина", "Автоцистерна", "Вантажний потяг", "Вантажний літак"]:
			var b: Variant = _buy_button(name)
			if b != null:
				await _scroll_to(b, .7)
				await _click(b, .5)
				await _wait(.35)
		main._toggle_window("coStaff")
		await _wait(.9)
		for i in 2:
			var h: Variant = _button(main.win, "Найняти")
			if h != null:
				await _scroll_to(h, .5)
				await _click(h, .5)
				await _wait(.4)
		_cursor.visible = false

	# ---- 8: the company: the licences from grey to obtainable, then all obtained
	if _shot_start(8, "the licences"):
		CO.tier = 1
		CO.rating = 3.0
		CO.cdel = 0
		CO.cash = maxf(main.hud.studio.cash, 4e7)   # the window opens on the top bar's money
		main._toggle_window("coHome")
		await _wait(.6)
		var head: Control = null
		for l in main.win.find_children("*", "Label", true, false):
			if String(l.text).to_upper() == "ЛІЦЕНЗІЇ":
				head = l
				break
		if head != null:
			await _scroll_to(head, 1.2)
		await _wait(.6)
		# the terms met one by one: the grey turns into what can be obtained
		for step in [["rating", 4.6], ["cdel", 4200], ["xp", 31000.0]]:
			CO[step[0]] = step[1]
			main._win_tick(true)
			await _wait(.45)
		for i in D.LIC.size():
			var b := _button(main.win, "Отримати ліцензію")
			if b == null:
				break
			await _click(b, .45)
			main.hud.studio.lic = float(CO.tier)
			main._win_tick(true)
			await _wait(.3)
		_cursor.visible = false
		_keep = false
		main.win.scroll.hold = false
		await _wait(.8)

	# ---- 9: the centre close up, a vehicle for every hub, turned right; back to the standard view
	if _shot_start(9, "the final pull-back"):
		_cut()
		_clear_trips()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var ms := ["road", "road", "rail", "sea", "air"]
		for A in sim.PL.filter(func(p): return sim.hub_at(p.id) != null):
			var m: String = ms[rng.randi() % ms.size()]
			if not sim.node_ok(m, A):
				m = "road"
			var far := Vector2(1.0, 4.0) if m == "road" or m == "rail" else Vector2(3.0, 9.0)
			var bs := _towns(m, A, far.x, far.y)
			if bs.size():
				_trip(A.id, bs[rng.randi() % bs.size()].id, m, rng.randf_range(16.0, 40.0), rng.randf(), .02)
		var d0 := lerpf(cam.min_dist, W.x * 1.25, .2)
		var d1 := W.x * 1.05
		await _track(10.0, func(p):
			var e := _ss(p)
			return [lerpf(0.0, 0.0, e), lerpf(.6, .6, e), lerpf(d0, d1, e), lerpf(.85, 0.0, e)])
		await _wait(1.5)
	print("STORY END %d %.2f" % [Engine.get_process_frames(), T])
	get_tree().quit()


## an order from the headquarters whose shortest road takes a toll motorway and has a way round it; a road
## closure put on the shortest road; the order last on the board (the oldest: the board lists the newest first)
func _toll_order(HQ: Dictionary) -> Variant:
	var CO: Dictionary = sim.CO
	if CO.board.is_empty():
		return null
	var best: Variant = null
	for B in _towns("road", HQ, 1.5, 7.0):
		if B.cid != HQ.cid:   # at home: the first licence sends it, no border on the way
			continue
		var r: Variant = sim.co_route("road", HQ.id, B.id)
		if r == null or sim.road_info(r).toll <= 0 or sim._cross(r.p, sim.CO_DU).size():
			continue
		var av0 := sim.road_av
		sim.road_av = "toll"
		var r2: Variant = sim.co_route("road", HQ.id, B.id)
		sim.road_av = av0
		if r2 != null and r2.len > r.len * 1.04 and sim._cross(r2.p, sim.CO_DU).is_empty():
			best = [B, r]
			break
	if best == null:   # no toll motorway with a way round at home: any town at home without a border on the way
		for B in _towns("road", HQ, 1.5, 6.0):
			var r: Variant = sim.co_route("road", HQ.id, B.id)
			if B.cid == HQ.cid and r != null and sim._cross(r.p, sim.CO_DU).is_empty():
				best = [B, r]
				break
	if best == null:
		return null
	var k: Dictionary = CO.board[0].duplicate(true)
	var lo := 1 << 30
	for x in CO.board:
		lo = mini(lo, int(x.id))
	k.id = lo - 1
	k.from = HQ.id
	k.to = best[0].id
	k.mode = "road"
	k.cg = "elec"
	k.tons = 3.5
	k.minR = 0
	k.dlDays = 8.0   # in time by either road
	k.exp = sim.day + 9
	k.erase("legs")
	k.erase("multi")
	CO.board.append(k)
	# a closure in the middle of the shortest road
	var p: PackedFloat32Array = best[1].p
	var mid := (p.size() / 4) * 2
	var n := sim.node_at(p[mid], p[mid + 1])
	if sim._jam_put(sim.co_now(), n, 1.2):
		for J in sim.jam:
			J.on = 1
			J.t0 = sim.co_now() - .01
			J.until = sim.co_now() + 5
			sim.jamn[J.n] = J.sev
		sim.inc_changed()
		sim.inc_blk()
	return k


func _buy_button(name: String) -> Button:
	for b in main.win.find_children("*", "Button", true, false):
		if not (b is Button) or not String(b.text).begins_with("Купити"):
			continue
		var n: Node = b.get_parent()
		while n != null and not (n is PanelContainer):   # the row the button is on: it names the vehicle
			n = n.get_parent()
		if n != null:
			for l in n.find_children("*", "Label", true, false):
				if l.text == name:
					return b
	return null


## trips of every kind from the hubs, at every stage: loading, on the road, unloading
func _trips_mix(n: int) -> void:
	var kinds := ["road", "rail", "air", "sea", "road", "rail", "road", "air"]
	var phases := [0.0, .4, .76, .25, .55, 0.0, .76, .6]
	var made := 0
	var hubs: Array = sim.PL.filter(func(p): return sim.hub_at(p.id) != null)
	for pass_ in 3:
		for A in hubs:
			if made >= n:
				return
			var m: String = kinds[made % kinds.size()]
			if not sim.node_ok(m, A):
				continue
			var far := Vector2(1.5, 4.0) if m == "road" or m == "rail" else Vector2(4.0, 10.0)
			var bs := _towns(m, A, far.x, far.y)
			if bs.is_empty():
				continue
			if _trip(A.id, bs[made % bs.size()].id, m, 24.0, phases[made % phases.size()], .2) != null:
				made += 1


func _clear_trips() -> void:
	for v in sim.CO.veh:
		if v.st != "idle":
			v.st = "idle"
			v.loc = sim.CO.hq
	sim.CO.jobs.clear()
