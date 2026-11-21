extends Node
## Entry scene. Stage 1: an empty shell that proves the project, autoloads and settings load.
## Next stages add the world generator, the map renderer and the interface here.

func _ready() -> void:
	var label := Label.new()
	label.text = "TriRoute · Godot %s\nЕтап 1: каркас проєкту. Генерація світу, мапа й інтерфейс переносяться далі." % Engine.get_version_info().string
	label.position = Vector2(40, 40)
	add_child(label)
	print("TriRoute started, settings wfx=", Settings.get_value("wfx"))
