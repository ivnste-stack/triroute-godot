extends Node
## Save slots (saveWrite / ACT.doSave / loadGame of legacy/src/08d-settings.js): "auto" and "1".."3".
## A slot is two files in user://saves: slot_N.sav — the game (Godot binary variants: floats and packed
## arrays come back bit for bit, so a loaded game goes on exactly like the saved one) — and slot_N.json, the
## line shown in the list (company, date, when saved). The world itself is made again from its seed.
## Autosave: every 15 minutes of play, through `provider` (returns {data, meta} or {} when it should not save).

const DIR := "user://saves"
const SLOTS := ["auto", "1", "2", "3"]
const AUTOSAVE_SEC := 15 * 60

var provider: Callable = Callable()
var _timer: Timer


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_timer = Timer.new()
	_timer.wait_time = AUTOSAVE_SEC
	_timer.timeout.connect(_on_autosave)
	add_child(_timer)
	_timer.start()


func _path(slot: String, ext: String) -> String:
	return "%s/slot_%s.%s" % [DIR, slot, ext]


func write(slot: String, data: Dictionary, meta: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(_path(slot, "sav"), FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data)
	f.close()
	var m := FileAccess.open(_path(slot, "json"), FileAccess.WRITE)
	if m == null:
		return false
	m.store_string(JSON.stringify(meta))
	m.close()
	EventBus.game_saved.emit(slot)
	return true


## the saved game, or null when the slot is empty or broken
func read(slot: String) -> Variant:
	if not FileAccess.file_exists(_path(slot, "sav")):
		return null
	var f := FileAccess.open(_path(slot, "sav"), FileAccess.READ)
	if f == null:
		return null
	var d: Variant = f.get_var()
	return d if d is Dictionary else null


func meta(slot: String) -> Dictionary:
	if not FileAccess.file_exists(_path(slot, "json")) or not FileAccess.file_exists(_path(slot, "sav")):
		return {}
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(slot, "json")))
	return p if p is Dictionary else {}


func remove(slot: String) -> void:
	for e in ["sav", "json"]:
		if FileAccess.file_exists(_path(slot, e)):
			DirAccess.remove_absolute(_path(slot, e))


func any() -> bool:
	return SLOTS.any(func(s): return not meta(s).is_empty())


func _on_autosave() -> void:
	if not provider.is_valid():
		return
	var s: Variant = provider.call()
	if s is Dictionary and s.has("data"):
		write("auto", s.data, s.meta)
