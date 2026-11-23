extends Node
## Music (08j-music.js): one track for the main menu and the loading screen, faded in and out; in the game a
## shuffled bag of tracks, each once per round and none of the last two heard first in the next round, with
## a pause of a few seconds between them. The volume comes from the settings: the general one (the Master
## bus) and the music one (the Music bus).

const MENU := "res://assets/music/menu.mp3"
const TRACKS := ["res://assets/music/game-1.mp3", "res://assets/music/game-2.mp3", "res://assets/music/game-3.mp3",
	"res://assets/music/game-4.mp3", "res://assets/music/game-5.mp3"]
const MENU_K := .55   # MUS.vol = .55 × the music volume
const GAME_K := .5    # gmVol = .5 × the music volume

var _menu: AudioStreamPlayer
var _game: AudioStreamPlayer
var _want := ""          # "menu", "game" or ""
var _bag: Array = []
var _last: Array = []
var _next_t: SceneTreeTimer = null
var _tw := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Music")
		AudioServer.set_bus_send(i, "Master")
	_menu = _player()
	_game = _player()
	_game.finished.connect(_track_done)
	apply_volume()
	EventBus.settings_changed.connect(func(k, _v):
		if k in ["master_vol", "mus_vol"]:
			apply_volume()
		elif k == "no_music" and _want == "menu":
			menu()
		elif k == "no_game_music" and _want == "game":
			game())


func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_linear = 0.0
	add_child(p)
	return p


static func _db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))


func apply_volume() -> void:
	var m := clampf(float(Settings.get_value("master_vol")), 0, 1)
	var mu := clampf(float(Settings.get_value("mus_vol")), 0, 1)
	AudioServer.set_bus_volume_db(0, _db(m))
	AudioServer.set_bus_mute(0, m <= 0.001)
	var i := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(i, _db(mu))
	AudioServer.set_bus_mute(i, mu <= 0.001)


func _ramp(p: AudioStreamPlayer, to: float, sec: float, done: Callable = Callable()) -> void:
	if _tw.has(p) and _tw[p].is_valid():
		_tw[p].kill()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(p, "volume_linear", to, sec)
	if done.is_valid():
		tw.tween_callback(done)
	_tw[p] = tw


## the main menu and the loading screen
func menu() -> void:
	_want = "menu"
	_stop_game(1.5)
	if Settings.get_value("no_music") or not ResourceLoader.exists(MENU):
		_ramp(_menu, 0, .6, func(): if _want != "menu" or Settings.get_value("no_music"): _menu.stop())
		return
	if _menu.stream == null:
		var s: AudioStream = load(MENU)
		if s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = true
		_menu.stream = s
	if not _menu.playing:
		_menu.play()
	_ramp(_menu, MENU_K, 1.8)


## in the game: the menu music fades out, then the game tracks start
func game() -> void:
	_want = "game"
	if _menu.playing:
		_ramp(_menu, 0, 3.5, func(): if _want != "menu": _menu.stop())
	if Settings.get_value("no_game_music"):
		_stop_game(.6)
		return
	if _game.playing:
		_ramp(_game, GAME_K, 1.5)
		return
	if _next_t == null:
		_next_t = get_tree().create_timer(3.6 if _menu.playing else .2)
		_next_t.timeout.connect(func():
			_next_t = null
			if _want == "game" and not Settings.get_value("no_game_music") and not _game.playing:
				_track())


## no music (e.g. the game is closing)
func stop() -> void:
	_want = ""
	_stop_game(1.0)
	_ramp(_menu, 0, 1.0, func(): _menu.stop())


func _stop_game(sec: float) -> void:
	if _game.playing:
		_ramp(_game, 0, sec, func(): if _want != "game" or Settings.get_value("no_game_music"): _game.stop())


func _pick() -> String:
	if _bag.is_empty():
		var b: Array = []
		for t in 60:
			b = TRACKS.duplicate()
			b.shuffle()
			if not (b[0] in _last) and not (b[1] in _last):
				break
		_bag = b
	var t: String = _bag.pop_front()
	_last.append(t)
	if _last.size() > 2:
		_last.pop_front()
	return t


func _track() -> void:
	var path := _pick()
	if not ResourceLoader.exists(path):
		return
	_game.stream = load(path)
	_game.volume_linear = 0
	_game.play()
	_ramp(_game, GAME_K, 2.5)


func _track_done() -> void:
	if _want != "game" or Settings.get_value("no_game_music"):
		return
	_next_t = get_tree().create_timer(randf_range(2.5, 6.0))
	_next_t.timeout.connect(func():
		_next_t = null
		if _want == "game" and not _game.playing:
			_track())
