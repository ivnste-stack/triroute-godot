extends Node
## Interface sounds (assets/sfx, made by tools/make_sfx.py): only what the player does — a button pressed, a
## window opened. Events of the game (a trip sent, a delivery, a hub bought, warnings, a new grade) are silent.
## A few players on the "Sfx" bus (its volume: the settings); the same sound again within a moment is skipped.

const NAMES := ["click"]
const GAP := {"click": .04}   # seconds before the same sound again

var _streams := {}
var _players: Array = []
var _next := 0
var _last := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Sfx") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Sfx")
		AudioServer.set_bus_send(i, "Master")
	for n in NAMES:
		var p := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(p):
			_streams[n] = load(p)
	for i in 6:
		var pl := AudioStreamPlayer.new()
		pl.bus = "Sfx"
		add_child(pl)
		_players.append(pl)
	apply_volume()
	EventBus.settings_changed.connect(func(k, _v): if k == "sfx_vol": apply_volume())
	# every button of the interface clicks
	get_tree().node_added.connect(_on_node)


func apply_volume() -> void:
	var v := clampf(float(Settings.get_value("sfx_vol")), 0, 1)
	var i := AudioServer.get_bus_index("Sfx")
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, .0001)))
	AudioServer.set_bus_mute(i, v <= .001)


func play(n: String, vol_db: float = 0.0, pitch_jitter: float = .03) -> void:
	if not _streams.has(n):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last.get(n, -10.0) < GAP.get(n, .08):
		return
	_last[n] = now
	var pl: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	pl.stream = _streams[n]
	pl.volume_db = vol_db
	pl.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	pl.play()


func _on_node(n: Node) -> void:
	if n is BaseButton and not n.has_meta("silent"):
		(n as BaseButton).pressed.connect(func(): play("click", -4.0))
