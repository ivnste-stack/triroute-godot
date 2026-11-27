class_name MapOverlay
extends Node2D
## Vector layers on the map, as the HTML version strokes them on its 2D canvas (drawBorders, drawBoard,
## drawLogistics in 08-ui.js / 08e-company.js / 086-logistics.js): the board frame, coastlines, state
## borders, the board grid, railways, roads and motorways. Widths are in screen pixels and follow the zoom
## like the original; the geometry is built once and drawn by the GPU (LineLayer).

const SECTOR := 7.5
# grid levels (drawBoard): step, width, colour
const GRID := [[SECTOR, 3.2, Color(28 / 255.0, 40 / 255.0, 52 / 255.0, .95)], [SECTOR / 3, 1.7, Color(40 / 255.0, 54 / 255.0, 68 / 255.0, .8)],
	[.5, 1.0, Color(60 / 255.0, 74 / 255.0, 88 / 255.0, .55)], [.125, .7, Color(80 / 255.0, 94 / 255.0, 108 / 255.0, .4)]]

var camera: MapCamera
var _layers := {}       # name → LineLayer
var _grid: Array = []   # LineLayer per grid level
var _built := false
var dpr := 1.0
var host: SubViewport          # the buffer this is drawn into, refreshed only when the view changes
var _key := ""


static func _c(r: int, g: int, b: int, a: float = 1.0) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)


func _layer(name: String, _order: int, geometry: Dictionary, color: Color, w: float) -> LineLayer:
	var L := LineLayer.new(geometry, color, w)
	L.name = name
	add_child(L)
	_layers[name] = L
	return L


## lines: TRWorldGen.lines(); board: TRWorldGen.generate_board(); size: the world size (WX, WZ);
## own: the owner per texture pixel, mwh: the texture size (for the coastal walls)
func build(lines: Array, board: Dictionary, size: Vector2, own: PackedByteArray, mwh: Vector2i) -> void:
	for c in get_children():
		c.queue_free()
	_layers.clear()
	_grid.clear()
	var hx := size.x / 2
	var hz := size.y / 2
	# the board frame
	var fr := PackedVector2Array([Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz), Vector2(-hx, -hz)])
	var fm := LineLayer.build_geometry([fr])
	_layer("frame_glow", 10, fm, _c(92, 200, 242, .16), 6)
	_layer("frame", 11, fm, _c(120, 214, 248, .9), 1.4)
	# coastlines, then state borders
	var coast := []
	var borders := []
	for l in lines:
		(coast if l.a == 0 else borders).append(l.p)
	var cm := LineLayer.build_geometry(coast)
	_layer("coast_glow", 20, cm, _c(150, 220, 245, .22), 3.2)
	_layer("coast", 21, cm, _c(5, 12, 20, .92), 1.3)
	_layer("borders", 22, LineLayer.build_geometry(borders), _c(6, 10, 14, .9), 1.25)
	# the grid: finer levels first, a line of the next coarser level is not drawn again
	for k in [3, 2, 1, 0]:
		var st: float = GRID[k][0]
		var segs := []
		var nx := int(floor(size.x / st + 1e-6))
		var nz := int(floor(size.y / st + 1e-6))
		var skip := func(v: float) -> bool:
			if k == 0:
				return false
			var cs: float = GRID[k - 1][0]
			return absf(roundf(v / cs) * cs - v) < 1e-6
		for i in nx + 1:
			if not skip.call(i * st):
				segs.append(PackedVector2Array([Vector2(-hx + i * st, -hz), Vector2(-hx + i * st, hz)]))
		for i in nz + 1:
			if not skip.call(i * st):
				segs.append(PackedVector2Array([Vector2(-hx, -hz + i * st), Vector2(hx, -hz + i * st)]))
		var L := _layer("grid%d" % k, 30 + (3 - k), LineLayer.build_geometry(segs, false), GRID[k][2], GRID[k][1])
		_grid.append([k, L])
	# railways, roads, motorways (drawLogistics)
	var rails: Array = board.get("railways", [])
	var rm := LineLayer.build_geometry(rails)
	_layer("rail_case", 40, rm, _c(20, 10, 4, .55), 3)
	_layer("rail", 41, rm, Color("#6b3b1a"), 2)
	var roads := []
	var mways := []
	for h in board.get("roads", []):
		(mways if h.lv >= 3 else roads).append(h.p)
	var road_m := LineLayer.build_geometry(roads)
	_layer("road_case", 50, road_m, _c(6, 12, 18, .7), 3)   # the outline of a planned route: 1 px each side
	_layer("road", 51, road_m, Color("#f4b453"), 1.5)
	var mw_m := LineLayer.build_geometry(mways)
	_layer("mway_case", 52, mw_m, _c(6, 12, 18, .7), 3)
	_layer("mway", 53, mw_m, Color("#f6b94f"), 2)
	_built = true
	_key = ""


## pixels per world unit at the view centre (ppu of the original)
func ppu() -> float:
	if camera == null:
		return 40.0
	var a := camera.unproject_position(Vector3(camera.tx, 0, camera.tz))
	var b := camera.unproject_position(Vector3(camera.tx + 1, 0, camera.tz))
	return a.distance_to(b)


## road rules (SimCore.road_mark_segs): toll motorways (a light stripe along the motorway) and the stretches
## closed to heavy vehicles (red); segs: [x1, z1, x2, z2, flags]
func set_marks(segs: Array) -> void:
	for nm in ["toll", "hban"]:
		if _layers.has(nm):
			_layers[nm].queue_free()
			_layers.erase(nm)
	var toll := []
	var ban := []
	for q in segs:
		var pl := PackedFloat32Array([q[0], q[1], q[2], q[3]])
		if int(q[4]) & 1:
			toll.append(pl)
		if int(q[4]) & 2:
			ban.append(pl)
	if toll.size():
		_layer("toll", 54, LineLayer.build_geometry(toll), Color("#8fe3ff"), 1)
	if ban.size():
		_layer("hban", 55, LineLayer.build_geometry(ban), Color("#f0625f"), 2)
	dirty()


func dirty() -> void:
	_key = ""


func _process(_delta: float) -> void:
	Perf.begin("map_overlay._process")
	_process_t(_delta)
	Perf.end("map_overlay._process")


func _process_t(_delta: float) -> void:
	if not _built or camera == null:
		return
	if Perf.off("overlay"):
		visible = false
	var vp := camera.get_camera_projection() * Projection(camera.get_camera_transform().affine_inverse())
	var scr := get_viewport_rect().size
	var key := "%s|%s|%s|%.3f" % [vp.x, vp.y, vp.w, scr.x * 7 + scr.y + dpr]
	key += "%s" % [vp.z]
	if key == _key:
		return
	_key = key
	if host != null:
		host.render_target_update_mode = SubViewport.UPDATE_ONCE
	for L in _layers.values():
		L.set_camera(vp, scr)
	var d := camera.dist
	var zw := clampf(13.0 / d, 1.0, 3.2)          # drawBorders
	_layers.coast_glow.set_width(3.2 * zw * dpr)
	_layers.coast.set_width(1.3 * zw * dpr)
	_layers.borders.set_width(1.25 * zw * dpr)
	var p := ppu()
	for e in _grid:
		var k: int = e[0]
		var L: LineLayer = e[1]
		var px: float = GRID[k][0] * p
		if px < 7:
			L.visible = false
			continue
		L.set_alpha(clampf((px - 7) / 18, 0, 1))
		L.set_width(GRID[k][1] * dpr * (1.0 if k == 0 else clampf(.7 + p / 400, .7, 1.4)))
	var zl := clampf(pow(12.0 / d, .6), .8, 3.6) * dpr   # drawLogistics
	var rw := 1.15 * zl
	_layers.rail_case.set_width(rw * 2.6)
	_layers.rail.set_width(rw * 1.85)
	_layers.road_case.set_width(rw + 2 * dpr)
	_layers.road.set_width(maxf(rw, 1.4 * dpr))   # never thinner than a crisp line: thinner ones fade out
	_layers.mway_case.set_width(rw * 1.85 + 2 * dpr)
	_layers.mway.set_width(maxf(rw * 1.85, 2 * dpr))
	if _layers.has("toll"):
		_layers.toll.set_width(rw * .7)
	if _layers.has("hban"):
		_layers.hban.set_width(rw * 1.5)
