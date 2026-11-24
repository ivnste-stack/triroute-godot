class_name Relief
extends RefCounted
## The test relief (settings: «Рельєф мапи (тест)»): the board's surface lifted by the height of the land.
## Heights live on the grid of the fine road net (a node every 0.0625: each lattice square in four) and are
## stepped into a few levels — pseudo heights, terraces rather than a real elevation model. One float texture
## holds them; the map shader lifts its vertices by it, the line shader its roads and borders, and h() gives
## the same height to everything drawn from GDScript (towns, vehicles, zones, the planner), so nothing floats.

const STEP := .0625
const K := .42        # world units at the highest land
const LEVELS := 9.0   # steps of height

static var on := false
static var gw := 0
static var gh := 0
static var wx := 0.0
static var wz := 0.0
static var grid := PackedFloat32Array()
static var tex: ImageTexture = null
static var ver := 0   # bumped when the relief changes (caches of drawn layers key on it)


## terrain: the map's terrain image (R = coast / height: > 0 land); world size wx × wz
static func build(terrain: Image, wx_: float, wz_: float) -> void:
	wx = wx_
	wz = wz_
	gw = int(round(wx / STEP)) + 1
	gh = int(round(wz / STEP)) + 1
	var img := terrain.duplicate() as Image
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.convert(Image.FORMAT_RF)
	# the grid's vertices sit on texture pixel corners every 5 pixels: a bilinear shrink averages around them
	img.resize(gw, gh, Image.INTERPOLATE_BILINEAR)
	var r := img.get_data().to_float32_array()
	grid.resize(gw * gh)
	for i in grid.size():
		var v: float = r[i]
		grid[i] = 0.0 if v <= 0.0 else round(sqrt(minf(v, 1.0)) * LEVELS) / LEVELS * K
	var hi := Image.create_from_data(gw, gh, false, Image.FORMAT_RF, grid.to_byte_array())
	tex = ImageTexture.create_from_image(hi)
	ver += 1


static func clear() -> void:
	grid = PackedFloat32Array()
	tex = null
	gw = 0
	gh = 0
	ver += 1


## the height of the surface at a world point (0 when the relief is off): bilinear between the grid's vertices
static func h(x: float, z: float) -> float:
	if not on or gw < 2:
		return 0.0
	var gx := clampf((x + wx / 2) / STEP, 0, gw - 1.001)
	var gz := clampf((z + wz / 2) / STEP, 0, gh - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var o := j * gw + i
	var a := lerpf(grid[o], grid[o + 1], fx)
	var b := lerpf(grid[o + gw], grid[o + gw + 1], fx)
	return lerpf(a, b, fz)
