extends Node
## Player settings (legacy: SET in 08d-settings.js, stored in localStorage "pon_settings").
## Here: ConfigFile at user://settings.cfg.

const PATH := "user://settings.cfg"

## Defaults mirror the legacy keys that the logistics game still uses.
const DEFAULTS := {
	"res": 0,             # map render resolution (0 = by screen)
	"eco": false,         # power saving: fewer frames, lower resolution
	"fps": 0,             # the frame limit: 0 the monitor (VSync), 60…240, -1 none
	"mus_vol": 0.6,       # music volume 0..1
	"no_music": false,    # menu music off
	"no_game_music": false,
	"no_tips": false,
	"no_ticker": false,
	"fastprog": false,    # test switch: progress x5
	"road_gab": false,    # test road generator
	"ui_scale": 0.0,
	"blur": true,         # the glass of the panels blurs the map behind (heavier for the video card)      # interface scale: 0 = the system scale (Windows display scaling), else 1…2
}

var _values := {}


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in DEFAULTS.keys():
		_values[k] = cfg.get_value("settings", k, DEFAULTS[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in _values.keys():
		cfg.set_value("settings", k, _values[k])
	cfg.save(PATH)


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	save_settings()
	EventBus.settings_changed.emit(key, value)
