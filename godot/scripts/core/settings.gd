extends Node
## Player settings (legacy: SET in 08d-settings.js, stored in localStorage "pon_settings").
## Here: ConfigFile at user://settings.cfg.

const PATH := "user://settings.cfg"

## Defaults mirror the legacy keys that the logistics game still uses.
const DEFAULTS := {
	# graphics
	"window": "max",      # "max" a maximised window, "window" a window of win_size, "borderless" full screen, "exclusive" exclusive full screen
	"win_size": "1600x900",
	"res": 0,             # the width the map is rendered at (0 = the window's): 1280…3840 (RES_OPTS)
	"upscale": "bilinear",  # how a smaller map render is stretched: "bilinear" or "fsr" (AMD FSR 1.0)
	"aa": "off",          # anti-aliasing of the map: "off", "fxaa", "ssaa2", "ssaa4", "fxaa_ssaa"
	"aniso": 2,           # anisotropic filtering of the map textures: 0…4 = 1×, 2×, 4×, 8×, 16×
	"vsync": true,        # wait for the monitor's refresh
	"fps": 0,             # the frame limit: 0 none, else 30…240
	"idle_fps": true,     # fewer frames when nothing happens (paused without input, in the background)
	"glint": true,        # slow glints on the water
	"blur": true,         # the glass of the panels blurs the map behind (heavier for the video card)
	# interface
	"ui_scale": 0.0,      # 0 = the system scale (Windows display scaling), else 1…2
	"no_tips": false,
	"no_ticker": false,
	"legend_folded": false,   # the map legend folded to its title
	# sound
	"master_vol": 0.8,    # general volume 0..1
	"mus_vol": 0.6,       # music volume 0..1
	"no_music": false,    # menu music off
	"no_game_music": false,
	# controls
	"keys": {},           # key bindings changed by the player (Keys): {action: keycode}
	# game
	"autosave": true,
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
