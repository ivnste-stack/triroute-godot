class_name MapView
extends Node3D
## The board map: generates the world with the native TRWorldGen in a background thread, uploads the
## terrain / border / state textures and draws the board plane with shaders/map.gdshader; on top of it the
## vector layers (MapOverlay: coastlines, borders, grid, railways, roads) and the settlements with their
## labels (TownLayer).

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
var _mw := 1800
var _mh := 1200
var _n_states := 26
var overlay: MapOverlay
var _ov_vp: SubViewport
var _ov_rect: TextureRect
var _tw_vp: SubViewport
var towns: TownLayer
var inc_base: IncidentLayer
var inc_top: IncidentLayer
var vehicles: VehicleLayer


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
	var cl := CanvasLayer.new()
	cl.layer = 0
	add_child(cl)
	# the vector layers are drawn into their own buffer, and only when the view changes (the HTML version also
	# redraws its canvas only then): a still map costs one texture per frame instead of ~16 offscreen passes
	_ov_vp = SubViewport.new()
	_ov_vp.transparent_bg = true
	_ov_vp.disable_3d = true
	_ov_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_ov_vp)
	overlay = MapOverlay.new()
	overlay.camera = camera
	overlay.host = _ov_vp
	_ov_vp.add_child(overlay)
	_ov_rect = TextureRect.new()
	_ov_rect.texture = _ov_vp.get_texture()
	_ov_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ov_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ov_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA   # the buffer holds premultiplied colour
	_ov_rect.material = pm
	cl.add_child(_ov_rect)
	inc_base = IncidentLayer.new()
	inc_base.camera = camera
	cl.add_child(inc_base)
	towns = TownLayer.new()
	towns.camera = camera
	_tw_vp = _cached(towns, cl)
	towns.host = _tw_vp
	inc_top = IncidentLayer.new()
	inc_top.camera = camera
	inc_top.top = true
	cl.add_child(inc_top)
	vehicles = VehicleLayer.new()
	vehicles.camera = camera
	cl.add_child(vehicles)


## Starts generating a world; world_ready fires when the map is on screen.
## size: "s" 2×1, "m" 3×2, "l" 4×3 sectors (a sector is 7.5 world units, 600 texture pixels)
func generate(seed_value: int, size_key: String = "m") -> void:
	if _task >= 0:
		return
	_seed = seed_value
	var sec: Vector2i = {"s": Vector2i(2, 1), "m": Vector2i(3, 2), "l": Vector2i(4, 3)}.get(size_key, Vector2i(3, 2))
	_mw = sec.x * 600
	_mh = sec.y * 600
	# G.genN: the number of states grows with the area
	_n_states = maxi(12, int(JS.round_js(30.0 * (_mw / 80.0) * (_mh / 80.0) / 384.0)))
	_gen = ClassDB.instantiate("TRWorldGen")
	_task = WorkerThreadPool.add_task(_generate_in_thread, true, "world generation")


func _generate_in_thread() -> void:
	var w: Dictionary = _gen.generate(_seed, _n_states, _mw, _mh)
	w["states"] = _gen.generate_states()
	w["board"] = _gen.generate_board()
	w["textures"] = _gen.build_textures()
	w["lines"] = _gen.lines()
	_result = w


func _process(_delta: float) -> void:
	Perf.begin("map_view._process")
	_process_t(_delta)
	Perf.end("map_view._process")


## a layer drawn into its own buffer, shown as one texture; the layer refreshes it when it changes
func _cached(layer: Node, parent: Node) -> SubViewport:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	vp.add_child(layer)
	var r := TextureRect.new()
	r.texture = vp.get_texture()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	r.material = pm
	parent.add_child(r)
	return vp


func _process_t(_delta: float) -> void:
	# the overlay buffer: the size of the screen in real pixels
	var phys := Vector2i(get_viewport().get_visible_rect().size * get_window().content_scale_factor) if get_window() != null else Vector2i(1600, 900)
	if _ov_vp.size != phys and phys.x > 0:
		_ov_vp.size = phys
		overlay.dpr = phys.x / maxf(1.0, get_viewport().get_visible_rect().size.x)
		overlay.dirty()
	if _tw_vp.size != phys and phys.x > 0:
		_tw_vp.size = phys
		towns.dpr = phys.x / maxf(1.0, get_viewport().get_visible_rect().size.x)
		towns._key = ""
	if Perf.off("msaa"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if Perf.off("map"):
		_plane.visible = false
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
	set_colors(w.states.map(func(st): return Color(st.color)))
	camera.set_world(size)
	_plane.visible = true
	overlay.build(w.lines, w.board, size, w.own, Vector2i(mw, mh))
	overlay.walls.set_terrain(terrain, float(w.tri_s), Vector2(mw, mh))   # land per lattice triangle, like the map
	towns.setup(w.board, w.states, w.countries, Vector2(mw, mh))
	inc_base.lines = w.lines
	inc_top.lines = w.lines
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


## the generator of the world on screen (routes, blocks for the simulation)
func generator() -> Object:
	return _gen


## shows a running game on the map
func attach_session(session: GameSession) -> void:
	towns.sim = session.sim
	for L in [inc_base, inc_top]:
		L.session = session
	vehicles.session = session
	_session = session
	session.day_passed.connect(func(_d): company_colors())
	company_colors()


var _session: GameSession


## the map colours of the company mode (coColors + the closed-country tint of 08f): states with a hub are tinted
## orange, states within the licence are muted, the rest darkened, closed countries reddened
func company_colors() -> void:
	if _session == null or _session.sim == null:
		return
	var sim := _session.sim
	var hub_c := {}
	for h in sim.CO.hubs:
		hub_c[sim.PL[h.pid].cid] = true
	var mix := func(a: Color, b: Color, t: float) -> Color: return a.lerp(b, t)
	var cols := []
	for c in world.states:
		var col := Color(c.color)
		var cap: Variant = null
		for p in sim.PL:
			if p.cid == c.id and p.type == "cap":
				cap = p
				break
		if hub_c.has(c.id):
			col = mix.call(col, Color(1, .7, .28), .35)
		elif cap != null and sim.co_scope(cap):
			col = mix.call(col, Color(.3, .34, .38), .35)
		else:
			col = mix.call(col, Color(.17, .2, .24), .78)
		cols.append(col)
	for cl in sim.CO.get("cls", []):
		if cl.kind == "cty" and cl.a < cols.size():
			cols[cl.a] = mix.call(cols[cl.a], Color(.86, .22, .2), .55)
	set_colors(cols)

