extends Node
## Entry scene while the game is being ported: the board map of a generated world, a small panel with the
## seed, «Новий світ», «Нова компанія» (the company at the first suggested capital; time: pause, 1, 2, 3 or
## the keys Space, 1, 2, 3) and «Перевірки» (all checks, green/red). The full interface is stage 6.
## Command line (for automatic screenshots): godot --path godot -- --seed=777 --shot=res://shot.png
##   [--cam=x,z,dist] [--company [--demo: a fleet with a dispatcher]] [--days=N: run N days at once] [--speed=0…3]
##   [--select: the first trip]

var map: MapView
var _info: Label
var _checks: PanelContainer
var _args := {}
var session: GameSession
var _clock: Label
var _speed_box: HBoxContainer


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	map = MapView.new()
	add_child(map)
	map.world_ready.connect(_on_world)
	_build_ui()
	if not ClassDB.class_exists("TRWorldGen"):
		_info.text = "Нативний модуль не завантажився (godot/bin). Натисни «Перевірки»."
		return
	_new_world(int(_args.get("seed", "777")))


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	ui.add_child(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_info = Label.new()
	_info.text = "Генерація світу…"
	box.add_child(_info)
	var b_new := Button.new()
	b_new.text = "Новий світ"
	b_new.pressed.connect(func(): _new_world(randi() % 1000000000))
	box.add_child(b_new)
	var b_co := Button.new()
	b_co.text = "Нова компанія"
	b_co.pressed.connect(_start_company.bind(true))
	box.add_child(b_co)
	_speed_box = HBoxContainer.new()
	_speed_box.visible = false
	box.add_child(_speed_box)
	for i in 4:
		var b := Button.new()
		b.text = ["‖", "1", "2", "3"][i]
		b.toggle_mode = true
		b.pressed.connect(_set_speed.bind(i))
		_speed_box.add_child(b)
	_clock = Label.new()
	_speed_box.add_child(_clock)
	var b_chk := Button.new()
	b_chk.text = "Перевірки"
	b_chk.pressed.connect(_toggle_checks)
	box.add_child(b_chk)
	_checks = PanelContainer.new()
	_checks.position = Vector2(16, 70)
	_checks.visible = false
	ui.add_child(_checks)


func _new_world(seed_value: int) -> void:
	GameState.reset(seed_value)
	_info.text = "Генерація світу #%d…" % seed_value
	map.generate(seed_value)


func _on_world(w: Dictionary) -> void:
	_info.text = "TriRoute · Godot %s · світ #%d · %d держав · колесо — зум, перетягування — рух" % [Engine.get_version_info().string, GameState.world_seed, w.countries.size()]
	if _args.has("colors"):   # test: the state colours of the HTML version, one #rrggbb per line
		var cols := []
		for l in FileAccess.get_file_as_string(_args.colors).split("\n", false):
			cols.append(Color(l.strip_edges()))
		map.set_colors(cols)
	if _args.has("wfx"):
		Settings.set_value("wfx", float(_args.wfx))
	if _args.has("company"):
		_start_company(_args.has("demo"))
		if _args.has("days"):
			session.run_days(int(_args.days))
		_set_speed(int(_args.get("speed", "0")))
		if _args.has("select") and session.sim.CO.jobs.size():
			map.vehicles.selected = session.sim.CO.jobs[0]
		map.camera.tx = map.camera.ttx   # no glide for a screenshot
		map.camera.tz = map.camera.ttz
		map.camera.dist = map.camera.tdist
	if _args.has("cam"):
		var c: PackedStringArray = String(_args.cam).split(",")
		map.camera.look_at_point(Vector2(float(c[0]), float(c[1])), float(c[2]))
		map.camera.tx = map.camera.ttx
		map.camera.tz = map.camera.ttz
		map.camera.dist = map.camera.tdist
	if _args.has("shot"):
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args.shot)
		get_tree().quit()


## demo: a fleet of tier 4 with a dispatcher, so trips run on their own until the interface can send them
func _start_company(demo: bool = false) -> void:
	if map.world.is_empty():
		return
	if session != null:
		session.queue_free()
	session = GameSession.new()
	add_child(session)
	var w := map.world
	session.start(map.generator(), GameState.world_seed, w.states, w.board, w)
	if demo:
		session.demo_fleet()
	map.attach_session(session)
	var hq: Dictionary = session.sim.PL[session.sim.CO.hq]
	map.camera.look_at_point(Vector2(hq.x, hq.z + .3), 6.0)
	_speed_box.visible = true
	_set_speed(1)


func _set_speed(i: int) -> void:
	if session == null:
		return
	session.set_speed(i)
	for k in _speed_box.get_child_count() - 1:
		(_speed_box.get_child(k) as Button).button_pressed = k == i


func _unhandled_key_input(e: InputEvent) -> void:
	if session == null or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match e.keycode:
		KEY_SPACE:
			_set_speed(0 if session.speed else 1)
		KEY_1, KEY_2, KEY_3:
			_set_speed(e.keycode - KEY_0)


func _process(_delta: float) -> void:
	if session == null or session.sim == null:
		return
	var sim := session.sim
	var fr := session.fraction()
	var h := int(fr * 24)
	_clock.text = "%02d.%02d.%d %02d:%02d · %s · $%s · рейсів %d · рейтинг %.2f" % [sim.date.d, sim.date.m + 1, sim.date.y, h, int((fr * 24 - h) * 6) * 10,
		sim.CO.name, String.num_int64(int(sim.CO.cash)), sim.CO.jobs.size(), sim.CO.rating]


func _toggle_checks() -> void:
	_checks.visible = not _checks.visible
	if not _checks.visible:
		return
	for c in _checks.get_children():
		c.queue_free()
	var out := RichTextLabel.new()
	out.bbcode_enabled = true
	out.fit_content = true
	out.custom_minimum_size = Vector2(760, 0)
	_checks.add_child(out)
	out.append_text("[color=#ffb347]Перевіряю… (генерація кількох світів займає кілька секунд)[/color]")
	await get_tree().process_frame
	await get_tree().process_frame
	var r := TestRunner.run_all()
	out.clear()
	for l in r.lines:
		var col := "#5fd08a" if l.begins_with("ok") else "#f0625f" if l.begins_with("FAIL") else "#ffb347"
		out.append_text("[color=%s]%s[/color]\n" % [col, l])
