class_name MapView
extends Node3D
## The board map: generates the world with the native TRWorldGen in a background thread, uploads the
## terrain / border / state textures and draws the board plane with shaders/map.gdshader.

signal world_ready(world: Dictionary)

## The same palette as the HTML version (COUNTRY_COLS in 06-sim.js).
const COUNTRY_COLS := ["#3f7f5a", "#c27a3a", "#3a6fa6", "#8b6bb0", "#4d9a8f", "#b5904a", "#6f8f3c", "#b2584f", "#4b8bbd",
	"#8a7a4e", "#5b6fb5", "#2f8f73", "#a8743a", "#7e5a8f", "#5f9a52", "#b16a6a", "#3d7d9a", "#9a8a3a"]
const BG := Color(.022, .038, .055)

var camera: MapCamera
var world: Dictionary = {}
var _mat: ShaderMaterial
var _plane: MeshInstance3D
var _gen: Object
var _task := -1
var _seed := 0
var _result: Dictionary = {}


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = BG
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(env)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/map.gdshader")
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(120, 120)   # ±60 like the original quad; the shader fades the far field into the background
	_plane = MeshInstance3D.new()
	_plane.mesh = mesh
	_plane.material_override = _mat
	_plane.visible = false
	add_child(_plane)
	camera = MapCamera.new()
	add_child(camera)
	camera.current = true
	camera.hover_changed.connect(_on_hover)
	EventBus.settings_changed.connect(func(k, v): if k == "wfx": _mat.set_shader_parameter("wfx", float(v)))


## Starts generating a world; world_ready fires when the map is on screen.
func generate(seed_value: int) -> void:
	if _task >= 0:
		return
	_seed = seed_value
	_gen = ClassDB.instantiate("TRWorldGen")
	_task = WorkerThreadPool.add_task(_generate_in_thread, true, "world generation")


func _generate_in_thread() -> void:
	var w: Dictionary = _gen.generate(_seed)
	w["states"] = _gen.generate_states()
	w["board"] = _gen.generate_board()
	w["textures"] = _gen.build_textures()
	_result = w


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_show(_result)
		_result = {}


func _show(w: Dictionary) -> void:
	world = w
	var tx: Dictionary = w.textures
	var mw: int = tx.width
	var mh: int = tx.height
	var terrain := ImageTexture.create_from_image(Image.create_from_data(mw, mh, true, Image.FORMAT_RGBAH, tx.terrain))
	var border := ImageTexture.create_from_image(Image.create_from_data(mw * 2, mh * 2, true, Image.FORMAT_RH, tx.border))
	var states := ImageTexture.create_from_image(Image.create_from_data(mw * 2, mh * 2, false, Image.FORMAT_R8, tx.states))
	w.erase("textures")
	var size := Vector2(mw / 80.0, mh / 80.0)
	_mat.set_shader_parameter("t0", terrain)
	_mat.set_shader_parameter("tb", border)
	_mat.set_shader_parameter("t1", states)
	_mat.set_shader_parameter("MWH", Vector2(mw, mh))
	_mat.set_shader_parameter("WSZ", size)
	_mat.set_shader_parameter("triS", float(w.tri_s))
	_mat.set_shader_parameter("wfx", float(Settings.get_value("wfx")))
	set_colors(w.states.map(func(st): return Color(st.color)))
	camera.set_world(size)
	_plane.visible = true
	world_ready.emit(w)


## Colours by state, sRGB (the shader works in sRGB like the original).
func set_colors(cols: Array) -> void:
	var arr := PackedVector3Array()
	arr.resize(120)
	for i in mini(cols.size(), 120):
		var c: Color = cols[i]
		arr[i] = Vector3(c.r, c.g, c.b)
	_mat.set_shader_parameter("col", arr)


## Fallback colouring (no state data): neighbours never share a colour, the least used colour first.
static func default_colors(countries: Array) -> Array:
	var used := {}
	var out := []
	out.resize(countries.size())
	for c in countries:
		var taken := {}
		for n in c.neighbors:
			if n < out.size() and out[n] != null:
				taken[out[n]] = true
		var best := ""
		for hex in COUNTRY_COLS:
			if taken.has(hex):
				continue
			if best == "" or used.get(hex, 0) < used.get(best, 0):
				best = hex
		if best == "":
			best = COUNTRY_COLS[c.idx % COUNTRY_COLS.size()]
		used[best] = used.get(best, 0) + 1
		out[c.idx] = best
	return out.map(func(h): return Color(h))


func state_at(p: Vector3) -> int:
	if world.is_empty():
		return -1
	var mw: int = world.mw
	var mh: int = world.mh
	var px := int(floor((p.x + mw / 160.0) / (mw / 80.0) * mw))
	var py := int(floor((p.z + mh / 160.0) / (mh / 80.0) * mh))
	if px < 0 or py < 0 or px >= mw or py >= mh:
		return -1
	var o: int = world.own[py * mw + px]
	if o > 127:
		o -= 256
	return o if o >= 0 and o < 120 else -1


func _on_hover(p: Vector3) -> void:
	_mat.set_shader_parameter("hov", state_at(p))
