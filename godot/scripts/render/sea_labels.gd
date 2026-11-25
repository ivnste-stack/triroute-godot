class_name SeaLabels
extends Node3D
## The names of the oceans, seas and lakes, lying on the map itself (Label3D flat on the board, under the
## roads and the towns, which are drawn over the 3D map in 2D).
##   · a generated world: the water is split into bodies (squares of the lattice joined by a side) and every
##     water square gets its distance to the land; the names go where the water is widest, the widest first,
##     each one keeping the others away: the open expanses of the biggest body are oceans (named by the side
##     of the world they lie on), the rest seas, a small body closed by land a lake. Names come from the lists
##     below in an order of the world's seed, so a world keeps its names
##   · the Earth: the real names at their real places (the Miller projection of tools/make_earth.py)
## The text grows with the room around it, and fades out close up, where it would cover the screen.

const OCEAN_SIDE := {"w": "Західний океан", "e": "Східний океан", "n": "Північний океан", "s": "Південний океан"}
const OCEANS := ["Великий океан", "Тихий океан", "Туманний океан", "Безкраїй океан", "Вітряний океан"]
const SEAS := ["Бурштинове море", "Срібне море", "Тихе море", "Вітряне море", "Лазурове море", "Холодне море", "Тепле море",
	"Коралове море", "Перлинне море", "Штормове море", "Зелене море", "Глибоке море", "Мілке море", "Сонячне море", "Місячне море",
	"Туманне море", "Скляне море", "Сапфірове море", "Чайкове море", "Бризове море", "Кам'яне море", "Солоне море", "Синє море",
	"Золоте море", "Острівне море", "Вербове море", "Північне море", "Південне море"]
const LAKES := ["Ясне озеро", "Глибоке озеро", "Дзеркальне озеро", "Тихе озеро", "Лебедине озеро", "Синє озеро", "Біле озеро",
	"Чисте озеро", "Світле озеро", "Срібне озеро"]

## the Earth: [name, longitude, latitude, size (the height of the letters in world units)]
const EARTH := [["Тихий океан", -140.0, 2.0, .55], ["Тихий океан", 172.0, 22.0, .42], ["Атлантичний океан", -45.0, 34.0, .34],
	["Атлантичний океан", -9.0, -30.0, .3], ["Індійський океан", 77.0, -28.0, .38], ["Північний Льодовитий океан", 100.0, 81.5, .2],
	["Південний океан", 70.0, -51.0, .3], ["Середземне море", 18.0, 34.5, .14], ["Чорне море", 34.0, 43.3, .1],
	["Каспійське море", 51.0, 42.0, .08], ["Червоне море", 38.5, 20.0, .07], ["Аравійське море", 64.0, 14.0, .18],
	["Бенгальська затока", 88.0, 14.0, .15], ["Південнокитайське море", 114.0, 13.0, .14], ["Східнокитайське море", 125.0, 29.0, .1],
	["Японське море", 135.0, 40.0, .1], ["Охотське море", 150.0, 54.0, .13], ["Берингове море", 182.0, 58.0, .14],
	["Філіппінське море", 132.0, 18.0, .16], ["Коралове море", 155.0, -16.0, .15], ["Тасманове море", 160.0, -40.0, .15],
	["Карибське море", -75.0, 15.0, .15], ["Мексиканська затока", -90.0, 25.0, .12], ["Гудзонова затока", -85.0, 59.0, .13],
	["Балтійське море", 19.5, 57.0, .08], ["Північне море", 3.0, 56.0, .09], ["Норвезьке море", 2.0, 68.0, .13],
	["Баренцове море", 40.0, 73.0, .14], ["Карське море", 70.0, 75.0, .12], ["Море Лаптєвих", 125.0, 76.0, .12],
	["Перська затока", 51.5, 27.0, .06], ["Гвінейська затока", 3.0, 2.0, .14]]

const COL := Color(.68, .86, 1.0)
const FS := 64   # the font size the letters are rendered at (their size on the map is pixel_size × FS)

var camera: MapCamera
var _base := []   # [Label3D, alpha]


func clear() -> void:
	for c in get_children():
		c.queue_free()
	_base = []


## own: the owner of every texture pixel (int8 as bytes, < 0 the sea); mw × mh: the texture
func build(own: PackedByteArray, mw: int, mh: int, tri_s: int, earth: bool, seed_value: int) -> void:
	clear()
	if earth:
		for e in EARTH:
			var p := _earth_px(e[1], e[2], mw, mh)
			_add(e[0], p.x / 80.0 - mw / 160.0, p.y / 80.0 - mh / 160.0, e[3], String(e[0]).contains("океан"))
		return
	_generated(own, mw, mh, tri_s, seed_value)


## make_earth.py: proj(lon, lat) on its 2400 × 1800 texture, scaled to this one
static func _earth_px(lon: float, lat: float, mw: int, mh: int) -> Vector2:
	const W := 2400.0
	const H := 1800.0
	const LON0 := -169.0
	const MX := 24.0
	var K := (W - 2 * MX) / TAU
	var miller := func(la: float) -> float:
		var f := deg_to_rad(clampf(la, -89, 89))
		return 1.25 * log(tan(PI / 4 + .4 * f))
	var OY: float = (H - (miller.call(84.0) - miller.call(-56.0)) * K) / 2
	if lon < LON0:
		lon += 360
	var x := MX + deg_to_rad(lon - LON0) * K
	var y: float = OY + (miller.call(84.0) - miller.call(lat)) * K
	return Vector2(x * mw / W, y * mh / H)


func _generated(own: PackedByteArray, mw: int, mh: int, S: int, seed_value: int) -> void:
	var W := mw / S
	var H := mh / S
	var N := W * H
	var wat := PackedByteArray()
	wat.resize(N)
	for j in H:
		for i in W:
			wat[j * W + i] = 1 if own[(j * S + S / 2) * mw + i * S + S / 2] > 127 else 0   # int8 < 0: sea
	# the bodies of water, their size and whether they reach the edge of the board
	var comp := PackedInt32Array()
	comp.resize(N)
	comp.fill(-1)
	var size := []
	var edge := []
	var q := PackedInt32Array()
	for c0 in N:
		if not wat[c0] or comp[c0] >= 0:
			continue
		var id := size.size()
		size.append(0)
		edge.append(false)
		comp[c0] = id
		q.resize(0)
		q.append(c0)
		var h := 0
		while h < q.size():
			var c: int = q[h]
			h += 1
			size[id] += 1
			var x := c % W
			var y := c / W
			if x == 0 or y == 0 or x == W - 1 or y == H - 1:
				edge[id] = true
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var m := ny * W + nx
				if wat[m] and comp[m] < 0:
					comp[m] = id
					q.append(m)
	if size.is_empty():
		return
	var big := 0
	for i in size.size():
		if size[i] > size[big]:
			big = i
	# the distance of every water square to the land (8 neighbours), and to the edge of the board
	var dist := PackedInt32Array()
	dist.resize(N)
	dist.fill(1 << 20)
	q.resize(0)
	for c in N:
		if not wat[c]:
			dist[c] = 0
			q.append(c)
	var h2 := 0
	while h2 < q.size():
		var c: int = q[h2]
		h2 += 1
		var x := c % W
		var y := c / W
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var nx: int = x + dx
				var ny: int = y + dy
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var m := ny * W + nx
				if dist[m] > dist[c] + 1:
					dist[m] = dist[c] + 1
					q.append(m)
	# the squares by their room (the distance to land and to the edge), the widest first
	var buckets := {}
	var dmax := 0
	for c in N:
		if not wat[c]:
			continue
		var x := c % W
		var y := c / W
		# the room: to the land, and to the board's edge (across it the text would be cut; above and below a name
		# needs only its height)
		var d: int = mini(dist[c], mini(mini(x, W - 1 - x), mini(y, H - 1 - y) * 2 + 1))
		if d < 2:
			continue
		if not buckets.has(d):
			buckets[d] = PackedInt32Array()
		buckets[d].append(c)
		dmax = maxi(dmax, d)
	var r := Mulberry.new((seed_value * 7919 + 17) & 0xFFFFFFFF)
	var seas := _shuffled(SEAS, r)
	var lakes := _shuffled(LAKES, r)
	var oceans := _shuffled(OCEANS, r)
	var used_side := {}
	var placed := []   # [x, y, keep-away radius]
	var n_oc := 0
	var n_sea := 0
	var n_lake := 0
	var cell := S / 80.0   # a square in world units
	for d in range(dmax, 1, -1):
		if not buckets.has(d):
			continue
		for c: int in buckets[d]:
			var x: int = c % W
			var y: int = c / W
			var ok := true
			for p in placed:
				if Vector2(x - p[0], y - p[1]).length() < p[2]:
					ok = false
					break
			if not ok:
				continue
			var id: int = comp[c]
			var lake: bool = not edge[id] and size[id] < N * .03
			var kind := "lake" if lake else ("ocean" if id == big and d >= maxi(6, int(dmax * .55)) else "sea")
			if kind == "sea" and d < 3 or kind == "lake" and d < 2:
				continue
			var name := ""
			match kind:
				"ocean":
					if n_oc >= 4:
						continue
					var side := _side(x, y, W, H)
					if not used_side.has(side):
						used_side[side] = true
						name = OCEAN_SIDE[side]
					else:
						name = oceans[n_oc % oceans.size()]
					n_oc += 1
				"sea":
					if n_sea >= 14:
						continue
					name = seas[n_sea % seas.size()]
					n_sea += 1
				_:
					if n_lake >= 5:
						continue
					name = lakes[n_lake % lakes.size()]
					n_lake += 1
			placed.append([x, y, d * (3.2 if kind == "ocean" else (2.6 if kind == "sea" else 1.5)) + 4])
			# the letters: as tall as about a third of the room, the whole name within its width
			var room := d * cell
			var hgt := room * (.42 if kind == "ocean" else .34)
			hgt = minf(hgt, room * 1.9 / maxf(1.0, name.length() * (.9 if kind == "ocean" else .62)))
			hgt = clampf(hgt, .07, .9)
			_add(name, (x + .5) * cell - mw / 160.0, (y + .5) * cell - mh / 160.0, hgt, kind == "ocean")


static func _side(x: int, y: int, W: int, H: int) -> String:
	var fx := (x + .5) / W - .5
	var fy := (y + .5) / H - .5
	if absf(fx) * H > absf(fy) * W:
		return "e" if fx > 0 else "w"
	return "s" if fy > 0 else "n"


static func _shuffled(a: Array, r: Mulberry) -> Array:
	var o := a.duplicate()
	for i in range(o.size() - 1, 0, -1):
		var j := int(floor(r.next() * (i + 1)))
		var t: Variant = o[i]
		o[i] = o[j]
		o[j] = t
	return o


func _add(text: String, x: float, z: float, hgt: float, ocean: bool) -> void:
	var l := Label3D.new()
	l.text = text.to_upper() if ocean else text
	l.font = Ui.font("body", 600 if ocean else 500, 8.0 if ocean else 2.0)   # oceans in spaced capitals
	l.font_size = FS
	l.pixel_size = hgt / FS
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.rotation_degrees = Vector3(-90, 0, 0)   # flat on the board, read from the south
	l.position = Vector3(x, .004, z)
	var a := .5 if ocean else .58
	l.modulate = Color(COL, a)
	l.render_priority = 1
	add_child(l)
	_base.append([l, a])


func _process(_delta: float) -> void:
	if camera == null or _base.is_empty():
		return
	visible = MapVis.vis("seas")
	# close up a name would cover the screen: it fades out
	var k := smoothstep(2.2, 4.5, camera.dist)
	for b in _base:
		var l: Label3D = b[0]
		l.modulate.a = b[1] * k
		l.visible = k > .01
