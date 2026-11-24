extends Node
## Player settings (legacy: SET in 08d-settings.js, stored in localStorage "pon_settings").
## Here: ConfigFile at user://settings.cfg.

const PATH := "user://settings.cfg"

## Defaults mirror the legacy keys that the logistics game still uses.
const DEFAULTS := {
	# graphics
	"window": "max",      # "max" a maximised window, "window" a window of win_size, "borderless" full screen, "exclusive" exclusive full screen
	"win_size": "1600x900",
	"res": 0,             # the map's render: 0 the window's, < 0 a share of it (-75 = 75 %), > 0 a width 1280…3840
	"upscale": "bilinear",  # how a smaller map render is stretched: "bilinear" or "fsr" (AMD FSR 1.0)
	"aa": "ssaa2",        # anti-aliasing of the map: "off", "fxaa", "ssaa2", "ssaa4", "fxaa_ssaa"
	"aniso": 2,           # anisotropic filtering of the map textures: 0…4 = 1×, 2×, 4×, 8×, 16×
	"vsync": true,        # wait for the monitor's refresh
	"fps": 0,             # the frame limit: 0 none, else 30…240
	"idle_fps": true,     # fewer frames when nothing happens (paused without input, in the background)
	"glint": true,        # slow glints on the water
	"daynight": false,    # the test day and night (MapView._day_night)
	"blur": 2,            # the glass of the panels blurs the map behind: 0 off, 1 light (4 taps), 2 full (9 taps)
	"trails": true,       # the fading trails behind moving vehicles
	"preset": "high",     # the graphics preset last chosen ("custom" once a setting is changed by hand)
	# interface
	"ui_scale": 0.0,      # 0 = the system scale (Windows display scaling), else 1…2
	"no_tips": false,
	"no_ticker": false,
	"legend_folded": false,   # the map legend folded to its title
	# sound
	"master_vol": 0.8,    # general volume 0..1
	"mus_vol": 0.6,       # music volume 0..1
	"sfx_vol": 0.7,       # interface sounds 0..1
	"no_music": false,    # menu music off
	"no_game_music": false,
	"game_music": "mix",  # in the game: "mix" the tracks and the calm background, "tracks", "ambient"
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
	if _values.blur is bool:   # older settings: the blur was on or off
		_values.blur = 2 if _values.blur else 0


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in _values.keys():
		cfg.set_value("settings", k, _values[k])
	cfg.save(PATH)


## the graphics presets: what each one sets (everything else stays the player's)
const PRESETS := {
	"low": {"res": -67, "aa": "off", "aniso": 0, "glint": false, "blur": 0, "trails": false, "upscale": "fsr"},
	"medium": {"res": -85, "aa": "fxaa", "aniso": 1, "glint": true, "blur": 1, "trails": true, "upscale": "fsr"},
	"high": {"res": 0, "aa": "ssaa2", "aniso": 2, "glint": true, "blur": 2, "trails": true, "upscale": "bilinear"},
	"ultra": {"res": 0, "aa": "ssaa4", "aniso": 4, "glint": true, "blur": 2, "trails": true, "upscale": "bilinear"},
}


func apply_preset(name: String) -> void:
	for k in PRESETS[name]:
		_values[k] = PRESETS[name][k]
	_values.preset = name
	save_settings()
	for k in PRESETS[name]:
		EventBus.settings_changed.emit(k, _values[k])


## the preset the current values match, or "custom"
func preset_now() -> String:
	for n in PRESETS:
		var ok := true
		for k in PRESETS[n]:
			if _values.get(k) != PRESETS[n][k]:
				ok = false
				break
		if ok:
			return n
	return "custom"


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	save_settings()
	EventBus.settings_changed.emit(key, value)
