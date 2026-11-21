extends Node
## Entry scene. While the game is being ported it shows the port status and runs the checks:
## open the project in Godot and press F5 (▶) — the results appear on screen.

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	panel.add_child(margin)
	margin.add_child(box)

	var title := Label.new()
	title.text = "TriRoute · перенос на Godot %s" % Engine.get_version_info().string
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var status := Label.new()
	status.text = "Перевіряю… (генерація 3 світів займає кілька секунд)"
	box.add_child(status)

	var out := RichTextLabel.new()
	out.bbcode_enabled = true
	out.fit_content = true
	out.add_theme_font_size_override("normal_font_size", 18)
	box.add_child(out)

	# let the window appear before the heavy checks run
	await get_tree().process_frame
	await get_tree().process_frame
	var r := TestRunner.run_all()
	for l in r.lines:
		print(l)
		var col := "#5fd08a" if l.begins_with("ok") else "#f0625f" if l.begins_with("FAIL") else "#ffb347"
		out.append_text("[color=%s]%s[/color]\n" % [col, l])
	if r.failed == 0:
		status.text = "Усі перевірки пройдено: світи в Godot ідентичні HTML-версії."
		status.add_theme_color_override("font_color", Color("#5fd08a"))
	else:
		status.text = "Є розбіжності — зроби скріншот цього вікна й надішли."
		status.add_theme_color_override("font_color", Color("#f0625f"))
