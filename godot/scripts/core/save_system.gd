extends Node
## Save slots (legacy: saveWrite / ACT.doLoad in 08d-settings.js, localStorage "pon_save_N").
## Slots: "auto" plus "1".."3", stored as JSON in user://saves/. Autosave every 15 minutes of play.

const DIR := "user://saves"
const SLOTS := ["auto", "1", "2", "3"]
const AUTOSAVE_SEC := 15 * 60

## Modules register what they save: name -> {"save": Callable() -> Variant, "load": Callable(Variant)}
var _parts := {}
var _timer: Timer


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_timer = Timer.new()
	_timer.wait_time = AUTOSAVE_SEC
	_timer.timeout.connect(_on_autosave)
	add_child(_timer)
	_timer.start()
	register("game", GameState.to_dict, GameState.from_dict)


func register(part: String, save_fn: Callable, load_fn: Callable) -> void:
	_parts[part] = {"save": save_fn, "load": load_fn}


func save(slot: String, meta := {}) -> bool:
	var data := {"v": 3, "meta": meta, "parts": {}}
	for k in _parts.keys():
		data.parts[k] = _parts[k].save.call()
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	EventBus.game_saved.emit(slot)
	return true


func load_slot(slot: String) -> bool:
	if not FileAccess.file_exists(_path(slot)):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(slot)))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var parts: Dictionary = parsed.get("parts", {})
	for k in parts.keys():
		if _parts.has(k):
			_parts[k].load.call(parts[k])
	EventBus.game_loaded.emit(slot)
	return true


func meta(slot: String) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(slot)))
	return parsed.get("meta", {}) if typeof(parsed) == TYPE_DICTIONARY else {}


func _path(slot: String) -> String:
	return "%s/slot_%s.json" % [DIR, slot]


func _on_autosave() -> void:
	# only while a game is running (a world exists)
	if GameState.world_seed != 0:
		save("auto", {"auto": true})
