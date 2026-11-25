extends Node
## Player settings (legacy: SET in 08d-settings.js, stored in localStorage "pon_settings").
## Here: ConfigFile at user://settings.cfg.

const PATH := "user://settings.cfg"

## Defaults mirror the legacy keys that the logistics game still uses.
const DEFAULTS := {
	# graphics
	"window": "max",      # "max" a maximised window, "window" a window of win_size, "borderless" full screen, "exclusive" exclusive full screen
	"win_size": "1600x900",
	"res": 0,             # the map's render: 0 high (the window's), -85 medium (85 %), -75 low (75 %)
	"aa": "ssaa2",        # anti-aliasing of the map (supersampling): "off", "ssaa2", "ssaa4"
	"vsync": true,        # wait for the monitor's refresh
	"fps": 0,             # the frame limit: 0 none, else 30…240
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
	# older settings: a render share or width of their own → the nearest of the three; FXAA (no visible effect
	# in this renderer) → off, FXAA + SSAA → SSAA 2×
	var r := int(_values.res)
	if not r in [0, -85, -75]:
		var pct := -r if r < 0 else 100   # a width of its own: the window's
		_values.res = 0 if pct >= 93 else (-85 if pct >= 80 else -75)
	_values.aa = {"fxaa": "off", "fxaa_ssaa": "ssaa2", "msaa2": "ssaa2", "msaa4": "ssaa4", "msaa8": "ssaa4"}.get(_values.aa, _values.aa)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in _values.keys():
		cfg.set_value("settings", k, _values[k])
	cfg.save(PATH)


## the graphics presets: what each one sets (everything else stays the player's)
const PRESETS := {
	"low": {"res": -75, "aa": "off", "glint": false, "blur": 0, "trails": false},
	"medium": {"res": -85, "aa": "off", "glint": true, "blur": 1, "trails": true},
	"high": {"res": 0, "aa": "ssaa2", "glint": true, "blur": 2, "trails": true},
	"ultra": {"res": 0, "aa": "ssaa4", "glint": true, "blur": 2, "trails": true},
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
