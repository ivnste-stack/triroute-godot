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
var walls: WallMesh
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
var night_lights: NightLights
## the test day and night: -1 follows the game's clock, 0…24 holds this hour (tests)
var night_hour := -1.0
var _tw_vp: SubViewport
var towns: TownLayer
var sea_labels: SeaLabels
var inc_base: IncidentLayer
var inc_top: IncidentLayer
var vehicles: VehicleLayer


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = BG
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# the distance haze is the map's and the walls' own (map.gdshader, wall.gdshader): no engine fog
	add_child(env)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/map.gdshader")
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(120, 120)   # ±60 like the original quad; the shader fades the far field into the background
	walls = WallMesh.new()
	add_child(walls)
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
	night_lights = NightLights.new()
	night_lights.camera = camera
	cl.add_child(night_lights)
	inc_base = IncidentLayer.new()
	inc_base.camera = camera
	cl.add_child(inc_base)
	sea_labels = SeaLabels.new()   # the names of the oceans and seas, flat on the board
	sea_labels.camera = camera
	add_child(sea_labels)
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
## fine_roads: the test road net (TRWorldGen.set_fine_roads)
func generate(seed_value: int, size_key: String = "m", fine_roads: bool = false, edit: Dictionary = {}) -> void:
	if _task >= 0:
		return
	_seed = seed_value
	_edit = edit
	_keep_cam = false
	var sec: Vector2i = {"s": Vector2i(2, 1), "m": Vector2i(3, 2), "l": Vector2i(4, 3), "earth": Vector2i(4, 3)}.get(size_key, Vector2i(3, 2))
	_mw = sec.x * 600
	_mh = sec.y * 600
	# G.genN: the number of states grows with the area
	_n_states = maxi(12, int(JS.round_js(30.0 * (_mw / 80.0) * (_mh / 80.0) / 384.0)))
	_gen = ClassDB.instantiate("TRWorldGen")
	if size_key == "earth":   # the real world: its countries, coasts and borders (tools/make_earth.py)
		var E := MapView.earth_data()
		_n_states = E.names.size()
		_gen.set_earth(E.w, E.h, E.labels, E.seeds, E.names, E.pop, E.dev)
	_is_earth = size_key == "earth"
	_gen.set_fine_roads(fine_roads)
	_task = WorkerThreadPool.add_task(_generate_in_thread, true, "world generation")


static var _earth := {}
var _is_earth := false


## assets/maps/earth.json: the label grid (run-length coded), a seed, a name, the population and the
## development of every state
static func earth_data() -> Dictionary:
	if not _earth.is_empty():
		return _earth
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/earth.json"))
	var rle := Marshalls.base64_to_raw(d.near)
	var lab := PackedByteArray()
	var run := PackedByteArray()
	for i in range(0, rle.size(), 2):
		run.resize(rle[i + 1])
		run.fill(rle[i])
		lab.append_array(run)
	var seeds := PackedInt32Array()
	for s in d.seeds:
		seeds.append(int(s[0]))
		seeds.append(int(s[1]))
	_earth = {"w": int(d.w), "h": int(d.h), "labels": lab, "seeds": seeds, "names": PackedStringArray(d.names),
		"pop": PackedFloat64Array(d.pop), "dev": PackedFloat64Array(d.dev), "cities": d.get("cities", []), "flags": d.get("flags", [])}
	return _earth


## the Earth: the states' simplified real flags, and real names for the towns. The capital takes the real
## capital; every other town (the largest first) the real city of its state that is near it and of a like size
## (the map is a real projection, so a town in the north-west of a country gets a city of the north-west);
## a town with no real city of its state within reach keeps its invented name.
static func earth_apply(w: Dictionary, mw: int, mh: int) -> void:
	var E := earth_data()
	for i in w.states.size():
		if i < E.flags.size() and E.flags[i] != null:
			w.states[i]["flag"] = {"ops": E.flags[i]}
	var RANK := {"cap": 0, "big": 1, "city": 2, "town": 3, "vil": 4}
	var by_state := {}
	for t in w.board.towns:
		if not by_state.has(t.cid):
			by_state[t.cid] = []
		by_state[t.cid].append(t)
	var WX := mw / 80.0
	var WZ := mh / 80.0
	for cid in by_state:
		if cid < 0 or cid >= E.cities.size():
			continue
		var real: Array = E.cities[cid]
		if real.is_empty():
			continue
		var used := {}
		var T: Array = by_state[cid]
		T.sort_custom(func(a, b): return RANK.get(a.type, 5) < RANK.get(b.type, 5) or (RANK.get(a.type, 5) == RANK.get(b.type, 5) and a.pop > b.pop))
		const S := 50.0     # texture pixels a tenfold difference in size is worth
		const MAXD := 130.0  # texture pixels (≈ 1.6 lattice cells): no real city nearer, the invented name stays
		for t in T:
			var px: float = (float(t.x) + WX / 2) * 80
			var py: float = (float(t.z) + WZ / 2) * 80
			var best := -1
			var bc := INF
			for k in real.size():
				if used.has(k):
					continue
				var r: Array = real[k]
				if t.type == "cap":   # the capital: the real one (the largest when a country has several)
					if int(r[4]) == 1:
						best = k
						break
					continue
				var dl := Vector2(px - float(r[1]), py - float(r[2])).length()
				if dl > (MAXD if t.type == "town" or t.type == "vil" else MAXD * 1.6):   # too far from where the city really is
					continue
				var d := dl / S
				var c := d + absf(log(maxf(float(t.pop), .001) / maxf(float(r[3]), .001)) / log(10.0)) * .6
				if c < bc:
					bc = c
					best = k
			if best < 0 and t.type == "cap":
				best = 0 if not used.has(0) else -1
			if best < 0:
				continue
			used[best] = true
			t["name"] = String(real[best][0])


func _generate_in_thread() -> void:
	var w: Dictionary = _gen.generate(_seed, _n_states, _mw, _mh)
	w["seed"] = _seed
	if not _edit.is_empty():   # a world of the map editor (a loaded game): the edit on the world of its seed
		_result = MapEditor.build_world(_gen, w, _edit)
		_result["seed"] = _seed
		return
	w["states"] = _gen.generate_states()
	w["board"] = _gen.generate_board()
	if _is_earth:
		MapView.earth_apply(w, _mw, _mh)
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


## the map is rendered at this share of the window's pixels (settings: the render resolution); the 3D map
## through Viewport.scaling_3d_scale, the lines and the towns through the size of their buffers
var render_k := 1.0


## 0 by day … 1 at night: dusk 18:00–20:30, dawn 5:00–7:30
static func night_at(h: float) -> float:
	return clampf(1.0 - smoothstep(5.0, 7.5, h) + smoothstep(18.0, 20.5, h), 0.0, 1.0)


func _day_night() -> void:
	var n := 0.0
	if Settings.get_value("daynight") and _session != null and _session.sim != null:
		var h := night_hour if night_hour >= 0 else fposmod(_session.sim.co_now(), 1.0) * 24.0
		n = night_at(h) * .9
	_mat.set_shader_parameter("night", n)
	if walls != null and walls._mat != null:
		walls._mat.set_shader_parameter("night", n)
	_ov_rect.modulate = Color.WHITE.lerp(Color(.6, .64, .78), n)
	night_lights.sim = _session.sim if _session != null else null
	night_lights.night = n


func _process_t(_delta: float) -> void:
	_day_night()
	if _plane.visible:
		_mat.set_shader_parameter("wall_h", walls.update(camera))

	# the overlay buffer: the size of the screen in real pixels
	# the line and town buffers at the map's resolution: the lines smooth their own edges in their shader
	# (overlay_line.gdshader); a supersampled buffer cost 7–8 ms of GPU at every camera move on 1440p
	var phys := Vector2i(get_viewport().get_visible_rect().size * get_window().content_scale_factor * render_k) if get_window() != null else Vector2i(1600, 900)
	if _ov_vp.size != phys and phys.x > 0:
		_ov_vp.size = phys
		overlay.dpr = phys.x / maxf(1.0, get_viewport().get_visible_rect().size.x)
		overlay.dirty()
	if _tw_vp.size != phys and phys.x > 0:
		_tw_vp.size = phys
		towns.dpr = phys.x / maxf(1.0, get_viewport().get_visible_rect().size.x)
		towns._key = ""
	if Perf.off("map"):
		_plane.visible = false
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _ed_img != null:
			edit_end()
		_show(_result, _keep_cam)
		_result = {}


var _edit := {}
var _keep_cam := false


## the world of the map editor's edit, on the generator that holds its base world (in a worker thread);
## world_ready fires when it is on the map
func build_edit(edit: Dictionary) -> void:
	if _task >= 0:
		return
	var b := world.duplicate()
	_keep_cam = true
	_is_earth = false
	_task = WorkerThreadPool.add_task(func():
		_result = MapEditor.build_world(_gen, b, edit)
		_result["seed"] = _seed, true, "edited world")


## shows a world: its textures, layers and camera (keep_cam: the editor's world goes on where the view is)
func _show(w: Dictionary, keep_cam: bool = false) -> void:
	world = w
	var tx: Dictionary = w.textures
	var mw: int = tx.width
	var mh: int = tx.height
	set_textures(tx)
	w.erase("textures")
	var size := Vector2(mw / 80.0, mh / 80.0)
	_mat.set_shader_parameter("MWH", Vector2(mw, mh))
	_mat.set_shader_parameter("WSZ", size)
	_mat.set_shader_parameter("triS", float(w.tri_s))
	set_colors(w.states.map(func(st): return Color(st.color)))
	if not keep_cam:
		camera.set_world(size)
	_plane.visible = true
	show_layers(w.lines, w.board, w.states, w.countries, w.own, Vector2i(mw, mh))
	sea_labels.build(w.own, mw, mh, int(w.tri_s), _is_earth, _seed)
	sea_labels.hold = false
	world_ready.emit(w)


## the map shader's textures (TRWorldGen.build_textures)
func set_textures(tx: Dictionary) -> void:
	var mw: int = tx.width
	var mh: int = tx.height
	_mat.set_shader_parameter("t0", ImageTexture.create_from_image(Image.create_from_data(mw, mh, tx.get("terrain_mips", true), Image.FORMAT_RGBAH, tx.terrain)))
	_mat.set_shader_parameter("tb", ImageTexture.create_from_image(Image.create_from_data(mw * 2, mh * 2, true, Image.FORMAT_RH, tx.border)))
	_mat.set_shader_parameter("t1", ImageTexture.create_from_image(Image.create_from_data(mw * 2, mh * 2, false, Image.FORMAT_R8, tx.states)))


## the vector layers, the coastal walls and the settlements of a world (or of the editor's world as it is now)
func show_layers(lines: Array, board: Dictionary, states: Array, countries: Array, own: PackedByteArray, mwh: Vector2i) -> void:
	var size := Vector2(mwh.x / 80.0, mwh.y / 80.0)
	overlay.build(lines, board, size, own, mwh)
	walls.build(lines, own, mwh)   # coastal side walls: a static 3D mesh
	walls._mat.set_shader_parameter("haze", _haze_k)
	towns.setup(board, states, countries, Vector2(mwh))
	inc_base.lines = lines
	inc_top.lines = lines
	apply_vis()


# ---------- the map editor ----------
var _ed_img: Image
var _ed_tex: ImageTexture


## the editor's lattice drawn by the shader (one RGBA8 texel a square: owner of h0, of h1, the diagonal)
func edit_begin(sqw: int, sqh: int, data: PackedByteArray) -> void:
	_ed_img = Image.create_from_data(sqw, sqh, false, Image.FORMAT_RGBA8, data)
	_ed_tex = ImageTexture.create_from_image(_ed_img)
	_mat.set_shader_parameter("tE", _ed_tex)
	_mat.set_shader_parameter("SQWH", Vector2(sqw, sqh))
	_mat.set_shader_parameter("edit_on", true)
	set_haze(0.0)
	sea_labels.hold = true   # the names of the seas come back with the finished world


func edit_update(data: PackedByteArray) -> void:
	if _ed_img == null:
		return
	_ed_img.set_data(_ed_img.get_width(), _ed_img.get_height(), false, Image.FORMAT_RGBA8, data)
	_ed_tex.update(_ed_img)


## the sea of the editor's lattice drawn deep, whatever the old world's terrain says (an empty ocean until
## its own textures are built)
func set_edit_deep(on: bool) -> void:
	_mat.set_shader_parameter("ed_deep", on)


func edit_end() -> void:
	_mat.set_shader_parameter("edit_on", false)
	_mat.set_shader_parameter("ed_deep", false)
	set_haze(1.0)
	sea_labels.hold = false
	_ed_img = null
	_ed_tex = null


func set_haze(k: float) -> void:
	_mat.set_shader_parameter("haze", k)
	if walls._mat != null:
		walls._mat.set_shader_parameter("haze", k)
	_haze_k = k


var _haze_k := 1.0


func set_sel(cid: int) -> void:
	_mat.set_shader_parameter("sel", cid)


## Colours by state, sRGB (the shader works in sRGB like the original).
func set_colors(cols: Array) -> void:
	var arr := PackedVector3Array()
	arr.resize(120)
	for i in mini(cols.size(), 120):
		var c: Color = cols[i]
		arr[i] = Vector3(c.r, c.g, c.b)
	_mat.set_shader_parameter("col", arr)


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


## a new world: the layers forget the old game (its zones, trips and headquarters) until the new one starts
func detach_session() -> void:
	towns.sim = null
	towns._key = ""
	for L in [inc_base, inc_top]:
		L.session = null
		L.queue_redraw()
	vehicles.session = null
	vehicles.queue_redraw()
	_session = null


## the map colours of the company mode (coColors + the closed-country tint of 08f): states with a hub are tinted
## orange, states within the licence are muted, the rest darkened, closed countries reddened
## the map layer (UI.mode): "co" the company's network, "grid" logistic routes, "risk" transport risks,
## "pol" political, "dem" world demand
var mode := "co"
const RISK_COL := [Color(.27, .62, .42), Color(.83, .71, .3), Color(.88, .47, .2), Color(.78, .2, .18)]
const DEM_COL := [Color(.78, .9, .97), Color(.47, .73, .9), Color(.22, .5, .78), Color(.1, .29, .55)]


## the legend's hidden kinds (MapVis): roads, motorways, railways and, on the political layer, borders
func apply_vis() -> void:
	if overlay != null and overlay._layers.size():
		var L: Dictionary = overlay._layers
		for k in ["road", "road_case"]:
			L[k].visible = MapVis.vis("r2")
		for k in ["mway", "mway_case"]:
			L[k].visible = MapVis.vis("r3")
		for k in ["rail", "rail_case"]:
			L[k].visible = MapVis.vis("rail")
		L.borders.visible = not (mode == "pol" and not MapVis.vis("pol_b"))
		if L.has("toll"):
			L.toll.visible = MapVis.vis("toll") and MapVis.vis("r3")
		if L.has("hban"):
			L.hban.visible = MapVis.vis("hban")
		overlay.dirty()
	company_colors()


func set_glint(on: bool) -> void:
	_mat.set_shader_parameter("glint", 1.0 if on else 0.0)


func set_mode(m: String) -> void:
	mode = m
	company_colors()
	inc_base.mode = m
	inc_top.mode = m
	apply_vis()


## coColors: the colours of the states for the layer
func company_colors() -> void:
	if _session == null or _session.sim == null:
		return
	var sim := _session.sim
	var cols := []
	match mode:
		"pol":
			for c in world.states:
				cols.append(Color(c.color))
			set_colors(cols)
			return
		"grid":
			for c in world.states:
				cols.append(Color(.72, .75, .78) if MapVis.vis("land") else Color(.3, .33, .36))
			set_colors(cols)
			return
		"risk":
			var v := []
			for i in world.states.size():
				v.append(sim.co_risk(i))
			var srt := v.duplicate()
			srt.sort()
			var q := func(f: float) -> float: return srt[mini(srt.size() - 1, int(floor(f * srt.size())))]
			var Q := [q.call(.3), q.call(.65), q.call(.88)]
			for r in v:
				cols.append(RISK_COL[3 if r > Q[2] else (2 if r > Q[1] else (1 if r > Q[0] else 0))])
			set_colors(cols)
			return
		"dem":
			var d := []
			d.resize(world.states.size())
			d.fill(0.0)
			for p in sim.PL:
				if p.cid < d.size():
					d[p.cid] += (p.pop * 1000 + 400) * (.45 + sim.states[p.cid].dev) * sim.price_k(p.cid)
			var v := []
			for i in d.size():
				v.append(d[i] / maxf(1, sqrt(float(world.countries[i].get("area", 1)) if i < world.countries.size() else 1.0)))
			var srt := v.duplicate()
			srt.sort()
			var q := func(f: float) -> float: return srt[int(floor(f * (srt.size() - 1)))]
			var T := [q.call(.35), q.call(.65), q.call(.88)]
			for x in v:
				cols.append(DEM_COL[0 if x < T[0] else (1 if x < T[1] else (2 if x < T[2] else 3))])
			set_colors(cols)
			return
	var hub_c := {}
	for h in sim.CO.hubs:
		hub_c[sim.PL[h.pid].cid] = true
	var mix := func(a: Color, b: Color, t: float) -> Color: return a.lerp(b, t)
	for c in world.states:
		var col := Color(c.color)
		var cap: Variant = null
		for p in sim.PL:
			if p.cid == c.id and p.type == "cap":
				cap = p
				break
		if hub_c.has(c.id) and MapVis.vis("hub"):
			col = mix.call(col, Color(1, .7, .28), .35)
		elif cap != null and sim.co_scope(cap):
			if MapVis.vis("avail"):
				col = mix.call(col, Color(.3, .34, .38), .35)
		elif MapVis.vis("unavail"):
			col = mix.call(col, Color(.17, .2, .24), .78)
		cols.append(col)
	for cl in (sim.CO.get("cls", []) if MapVis.vis("clb") else []):
		if cl.kind == "cty" and cl.a < cols.size():
			cols[cl.a] = mix.call(cols[cl.a], Color(.86, .22, .2), .55)
	set_colors(cols)

