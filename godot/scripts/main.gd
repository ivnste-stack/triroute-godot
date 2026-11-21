extends Node
## Entry scene while the game is being ported: the board map of a generated world (stage 3),
## a small panel with the seed, «Новий світ» and «Перевірки» (all checks, green/red).
## Command line (for automatic screenshots): godot --path godot -- --seed=777 --shot=res://shot.png [--cam=x,z,dist]

var map: MapView
var _info: Label
var _checks: PanelContainer
var _args := {}


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
