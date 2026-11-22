class_name TownLayer
extends Control
## Settlements on the map, as the HTML version draws them: border checkpoints, town markers and their
## labels (drawBoardTowns in 08e-company.js, a label is skipped when it would cover a more important one)
## and the country chips at the capitals (buildCityLabels / updateCities in logcities.js and their CSS).
##
## Every marker, label, chip and checkpoint is a node that draws itself once and again only when what it shows
## changes (a hub, the zoom level of a chip); when the camera moves only their positions, visibility and the
## overlap of the labels are worked out — no drawing commands are made again.

const F_INTER_B := preload("res://assets/fonts/Inter-Bold.otf")
const F_INTER_SB := preload("res://assets/fonts/Inter-SemiBold.otf")
const F_MONO_B := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const F_ONEST := preload("res://assets/fonts/Onest.ttf")
const ORDER := {"cap": 0, "big": 1, "city": 2, "town": 3, "vil": 4}
const FG := Color("#e7eef4")
const FG2 := Color("#b3c2cf")
const CP_SZ := 7.0               # checkpoints are drawn at the largest size and scaled down


## a piece of the layer that draws itself with a function (called again only on queue_redraw)
class Piece extends Node2D:
	var fn: Callable

	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)


var camera: MapCamera
var towns: Array = []          # board towns: {x, z, type, name, port, air_ov, cid, node…}
var rail_nodes := {}           # lattice nodes on the railway graph (a town with a station)
var states: Array = []
var countries: Array = []      # world countries (capital position in texture pixels)
var cps: Array = []            # border checkpoints
var mwh := Vector2(1800, 1200)
var sim: Sim = null            # the company (hubs on the labels), optional
var dpr := 1.0
var host: SubViewport          # the buffer this is drawn into, refreshed only when it changes
var lbl: Array = []            # {pid, r}: the labels and country chips on screen (BOARD.lbl, CITY_EL)

var _order: Array = []         # town indices, the most important first
var _wc := {}                  # widths of the names, measured once
var _key := ""
var _onest_600: FontVariation
var _onest_500: FontVariation
var _cp_nodes: Array = []
var _mk: Array = []            # per town: the marker
var _lb: Array = []            # per town: the label
var _info: Array = []          # per town: {key, s, w, h}
var _chips: Array = []         # per country: {node, key, pid, x, z, w, h, half}
var _cap_pid := {}
var _cp_sc := 0.0               # the scale the checkpoints were last drawn for (their border keeps 1.2 px)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_onest_600 = _onest(600)
	_onest_500 = _onest(500)


static func _onest(w: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = F_ONEST
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
	return f


func setup(board: Dictionary, states_: Array, countries_: Array, mwh_: Vector2) -> void:
	towns = board.towns
	cps = board.get("checkpoints", [])
	states = states_
	countries = countries_
	mwh = mwh_
	rail_nodes = {}
	var rb: PackedByteArray = board.rbits
	for t in towns:
		if rb[t.node] != 0:
			rail_nodes[t.node] = true
	_order = range(towns.size())
	SimCore._stable_sort(_order, func(a, b): return ORDER[towns[a].type] - ORDER[towns[b].type])
	_wc = {}
	for c in get_children():
		c.queue_free()
	# drawing order as before: checkpoints, then every town (marker, label) by importance, then the chips
	_cp_nodes = []
	for c in cps:
		var n := Piece.new()
		n.fn = _draw_cp
		n.visible = false
		add_child(n)
		_cp_nodes.append(n)
	_mk = []
	_lb = []
	_info = []
	_mk.resize(towns.size())
	_lb.resize(towns.size())
	_info.resize(towns.size())
	for pid in _order:
		for arr in [_mk, _lb]:
			var n := Piece.new()
			n.visible = false
			add_child(n)
			arr[pid] = n
		_info[pid] = {"key": ""}
	_cap_pid = {}
	var cap_name := {}
	for i in towns.size():
		if towns[i].type == "cap":
			cap_name[towns[i].cid] = towns[i].name
			_cap_pid[towns[i].cid] = i
	_chips = []
	for c in countries:
		if c.idx >= states.size():
			continue
		# the chip stands at the capital town of the board (the board moves geo.cap there)
		var x: float = c.cap_x / mwh.x * (mwh.x / 80.0) - mwh.x / 160.0
		var z: float = c.cap_y / mwh.y * (mwh.y / 80.0) - mwh.y / 160.0
		if _cap_pid.has(c.idx):
			x = towns[_cap_pid[c.idx]].x
			z = towns[_cap_pid[c.idx]].z
		var n := Piece.new()
		n.visible = false
		add_child(n)
		_chips.append({"node": n, "key": "", "cid": c.idx, "pid": _cap_pid.get(c.idx, -1), "x": x, "z": z, "sub": cap_name.get(c.idx, "")})
	_key = ""


func _process(_delta: float) -> void:
	Perf.begin("town_layer._process")
	_process_t(_delta)
	Perf.end("town_layer._process")


func _process_t(_delta: float) -> void:
	if camera == null or towns.is_empty():
		return
	var k := "%.4f|%.4f|%.4f|%s|%.2f" % [camera.tx, camera.tz, camera.dist, size, dpr]
	if sim != null:
		k += "|%d|%s" % [sim.CO.get("hq", -1), sim.CO.get("hubs", []).map(func(h): return [h.pid, h.lvl, h.get("rent", false)])]
	if k != _key:
		_key = k
		Perf.begin("town_layer.layout")
		_layout()
		Perf.end("town_layer.layout")
		if host != null:
			host.render_target_update_mode = SubViewport.UPDATE_ONCE


func _P(x: float, z: float) -> Variant:
	var w := Vector3(x, 0, z)
	if camera.is_position_behind(w):
		return null
	return camera.unproject_position(w) * dpr


func _hub(pid: int) -> Variant:
	return sim.hub_at(pid) if sim != null and pid >= 0 and not sim.CO.is_empty() else null


## where everything goes for this view of the camera
func _layout() -> void:
	lbl = []
	var W := size.x
	var H := size.y
	var a: Variant = _P(camera.tx, camera.tz)
	var b: Variant = _P(camera.tx + 1, camera.tz)
	var ppu: float = a.distance_to(b) / dpr if a != null and b != null else 40.0
	# border checkpoints: a dark square with a red-white barrier band
	var cp_on := ppu > 45
	var cp_sc := clampf(ppu / 40, 3.5, 7) * dpr / (CP_SZ * dpr)
	var redraw_cp := cp_on and absf(cp_sc - _cp_sc) > .02
	if redraw_cp:
		_cp_sc = cp_sc
	for i in cps.size():
		var n: Piece = _cp_nodes[i]
		var q: Variant = _P(cps[i].x, cps[i].z) if cp_on else null
		var on: bool = q != null and q.x >= -20 and q.y >= -20 and q.x <= W + 20 and q.y <= H + 20
		if n.visible != on:
			n.visible = on
		if on:
			n.position = q
			n.scale = Vector2(cp_sc, cp_sc)
		if redraw_cp:
			n.queue_redraw()
	# settlements
	var boxes := []
	for pid in _order:
		var p: Dictionary = towns[pid]
		var mk: Piece = _mk[pid]
		var lb: Piece = _lb[pid]
		var shown: bool = ppu > 150 if p.type == "vil" else (ppu > 60 if p.type == "town" else true)
		var c: Variant = _P(p.x, p.z) if shown else null
		if c == null or c.x < -60 or c.y < -60 or c.x > W + 60 or c.y > H + 60:
			if mk.visible:
				mk.visible = false
			if lb.visible:
				lb.visible = false
			continue
		var I: Dictionary = _town_info(pid)
		var has_mk: bool = I.mk
		if mk.visible != has_mk:
			mk.visible = has_mk
		mk.position = c
		if p.type == "cap":
			if lb.visible:
				lb.visible = false
			continue   # capitals use the country chip
		var lx: float = c.x + I.s + 5 * dpr
		var ly: float = c.y - I.h / 2
		var hit := false
		for bx in boxes:
			if lx < bx[2] and lx + I.w > bx[0] and ly < bx[3] and ly + I.h > bx[1]:
				hit = true
				break
		if hit:
			if lb.visible:
				lb.visible = false
			continue
		boxes.append([lx, ly, lx + I.w, ly + I.h])
		lbl.append({"pid": pid, "r": Rect2(lx, ly, I.w, I.h)})
		if not lb.visible:
			lb.visible = true
		lb.position = Vector2(lx, ly)
	_layout_chips()


## what a town shows: built again (and drawn again) only when its hub changes
func _town_info(pid: int) -> Dictionary:
	var p: Dictionary = towns[pid]
	var hb: Variant = _hub(pid)
	var hq: bool = sim != null and pid == sim.CO.get("hq", -1)
	var key := "%s|%s|%s|%.2f" % [hb.lvl if hb != null else -1, hb.get("rent", false) if hb != null else false, hq, dpr]
	var I: Dictionary = _info[pid]
	if I.key == key:
		return I
	I.key = key
	var mk: Piece = _mk[pid]
	var lb: Piece = _lb[pid]
	var d := dpr
	# the marker: an orange square for a hub, a diamond for a town without one
	I.mk = hb != null and p.type != "cap" or (hb == null and p.type != "cap")
	var s: float = ({"big": 6, "city": 5, "town": 4, "vil": 3}.get(p.type, 4) if hb != null else (4.0 if p.type == "big" or p.type == "city" else (3.0 if p.type == "town" else 2.2))) * d
	I.s = s
	if hb != null:
		var hs: float = {"cap": 7, "big": 6, "city": 5, "town": 4, "vil": 3}.get(p.type, 4) * d
		var rent: bool = hb.get("rent", false)
		mk.fn = func(n: Node2D) -> void:
			var hr := Rect2(-hs, -hs, hs * 2, hs * 2)
			n.draw_rect(hr, Color("#a9b4be") if rent else Color("#ffb347"))
			n.draw_rect(hr, Color("#06121b"), false, 1.4 * d)
	else:
		var dd := s * .86 * sqrt(2.0)
		var col := Color.WHITE if p.type == "vil" or p.type == "town" else Color("#5cc8f2")
		mk.fn = func(n: Node2D) -> void:
			var dia := PackedVector2Array([Vector2(0, -dd), Vector2(dd, 0), Vector2(0, dd), Vector2(-dd, 0)])
			n.draw_colored_polygon(dia, col)
			dia.append(dia[0])
			n.draw_polyline(dia, Color("#071420"), 1.3 * d, true)
	mk.queue_redraw()
	# the label
	var big: bool = p.type == "big" or p.type == "city"
	var fs := (12.0 if big else (10.5 if p.type == "town" else 9.5)) * d
	var font: Font = F_INTER_B if big else F_INTER_SB
	var tag := ""
	if hb != null:
		tag = ("★ ШТАБ · " if hq else "") + ("ОРЕНДА · " if hb.get("rent") else "") + String(GameData.HUB_LV[hb.lvl]).to_upper()
	var tgw := _tw(F_MONO_B, tag, int(round(9 * d))) if tag else 0.0
	var icl := []
	if p.port:
		icl.append("anchor")
	if p.air_ov or p.type == "big":
		icl.append("plane")
	if rail_nodes.has(p.node):
		icl.append("train")
	var isz := 11 * d
	var name_w := _tw(font, p.name, int(round(fs)))
	var nmw := name_w + (icl.size() * (isz + 2 * d) + 4 * d if icl.size() else 0.0)
	var tw := maxf(nmw, tgw) + 12 * d
	var th := fs + 8 * d + (12 * d if tag else 0.0)
	I.w = tw
	I.h = th
	var rent2: bool = hb != null and hb.get("rent", false)
	var nm: String = p.name
	lb.fn = func(n: Node2D) -> void:
		n.draw_rect(Rect2(0, 0, tw, th), Color(8 / 255.0, 18 / 255.0, 28 / 255.0, .86))
		var bc := (Color(170 / 255.0, 182 / 255.0, 194 / 255.0, .85) if rent2 else Color(1, 179 / 255.0, 71 / 255.0, .8)) if tag else Color(160 / 255.0, 180 / 255.0, 198 / 255.0, .28)
		n.draw_rect(Rect2(.5 * d, .5 * d, tw - d, th - d), bc, false, 1 * d)
		var mid := (fs + 8 * d) / 2 + .5 * d
		_text(n, font, nm, Vector2(6 * d, mid), int(round(fs)), Color("#c9d4de"))
		var ix := 6 * d + name_w + 5 * d
		for ic in icl:
			Icons.draw(n, ic, ix, (fs + 8 * d) / 2, isz, Color("#9fb4c6"))
			ix += isz + 2 * d
		if tag:
			_text(n, F_MONO_B, tag, Vector2(6 * d, fs + 8 * d + 3 * d), int(round(9 * d)), Color("#b8c2cc") if rent2 else Color("#ffb347"))
	lb.queue_redraw()
	return I


## a checkpoint at CP_SZ, scaled to the zoom by its node
func _draw_cp(n: Node2D) -> void:
	var sz := CP_SZ * dpr
	var r := Rect2(-sz, -sz, sz * 2, sz * 2)
	n.draw_rect(r, Color("#0b1520"))
	var band := PackedVector2Array([Vector2(-sz, -sz * .35), Vector2(sz, -sz * .35), Vector2(sz, sz * .35), Vector2(-sz, sz * .35)])
	for k in range(-3, 4):
		var st := PackedVector2Array([Vector2(k * sz * .5, -sz), Vector2(k * sz * .5 + sz * .5, -sz), Vector2(k * sz * .5, sz), Vector2(k * sz * .5 - sz * .5, sz)])
		for poly in Geometry2D.intersect_polygons(st, band):
			n.draw_colored_polygon(poly, Color("#f0625f") if k % 2 else Color.WHITE)
	n.draw_rect(r, Color("#e8edf2"), false, 1.2 * dpr / maxf(_cp_sc, .1))


## text with its vertical middle at pos.y (textBaseline = "middle")
static func _text(n: CanvasItem, font: Font, s: String, pos: Vector2, fsize: int, col: Color) -> void:
	var asc := font.get_ascent(fsize)
	var desc := font.get_descent(fsize)
	n.draw_string(font, Vector2(pos.x, pos.y + (asc - desc) / 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## the settlement under a point of the screen (coPlaceAt): a label, a country chip
func place_at(pos: Vector2) -> int:
	for i in range(lbl.size() - 1, -1, -1):
		var r: Rect2 = lbl[i].r
		if r.grow_side(SIDE_LEFT, 4).has_point(pos * dpr):
			return lbl[i].pid
	return -1


# ---------- country chips at the capitals (logcities.js and its CSS, company mode) ----------
func _layout_chips() -> void:
	var far := camera.dist > 11
	var W := size.x
	var H := size.y
	for ch in _chips:
		var n: Piece = ch.node
		var q: Variant = _P(ch.x, ch.z)
		if q == null or q.x < -80 or q.x > W + 80 or q.y < -40 or q.y > H + 40:
			if n.visible:
				n.visible = false
			continue
		_chip_info(ch, far)
		if not n.visible:
			n.visible = true
		n.position = q
		if ch.pid >= 0:
			var ly: float = q.y - ch.h / 2
			lbl.append({"pid": ch.pid, "r": Rect2(q.x - 10 * dpr, ly, ch.lx + ch.w + 10 * dpr, ch.h), "cap": true})


## what a chip shows: drawn again only when its hub, the zoom step or the headquarters change
func _chip_info(ch: Dictionary, far: bool) -> void:
	var hb: Variant = _hub(ch.pid)
	var hq: bool = sim != null and ch.pid == sim.CO.get("hq", -1)
	var mine: bool = sim != null and ch.cid == sim.me
	var key := "%s|%s|%s|%s|%s|%.2f" % [far, hb.lvl if hb != null else -1, hb.get("rent", false) if hb != null else false, hq, mine, dpr]
	if ch.key == key:
		return
	ch.key = key
	var d := dpr
	var st: Dictionary = states[ch.cid]
	var title: String = String(st.name).to_upper()
	var sub: String = ch.sub
	var tag := ""
	if hb != null:
		tag = (("★ Штаб · " if hq else "") + ("Оренда · " if hb.get("rent") else "") + String(GameData.HUB_LV[hb.lvl])).to_upper()
	var f1 := 11.0 * d
	var tw := _spaced_w(_onest_600, title, int(round(f1)), .08 * f1)
	var sw := 0.0 if far else 11 * d + 4 * d + _tw(_onest_500, sub, int(round(11 * d)))
	var tgw := 0.0 if tag == "" else _tw(F_MONO_B, tag, int(round(10 * d)))
	var w := maxf(tw, maxf(sw, tgw)) + 15 * d
	var rows := 1 + (0 if far else 1) + (1 if tag else 0)
	var h := (rows * 11.0 + (rows - 1) * 4.0 + 10.0) * d
	var half := (11.0 if hb != null else 9.0) / 2   # box-sizing: border-box
	var lx: float = -5.5 * d + (half * 2 + 6) * d
	ch.w = w
	ch.h = h
	ch.lx = lx
	var rent: bool = hb != null and hb.get("rent", false)
	var has_hb := hb != null
	var border := Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .32)
	if has_hb:
		border = Color("#a9b4be") if rent else Color("#ffb347")
	elif mine:
		border = Color("#5cc8f2")
	var self_ := self
	ch.node.fn = func(n: Node2D) -> void:
		# the capital marker: a 9 px square with a 1.5 px border turned 45°, a faint ring around it
		var mc := Vector2(.5 * d, 0)
		var ring := Color("#ffb347") if has_hb else Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .35)
		var fill := (Color("#a9b4be") if rent else Color("#ffb347")) if has_hb else Color("#5cc8f2")
		if not has_hb:
			n.draw_colored_polygon(_dia(mc, (half + 1) * d), ring)
		n.draw_colored_polygon(_dia(mc, half * d), Color("#06121b") if has_hb else Color("#04131c"))
		n.draw_colored_polygon(_dia(mc, (half - 1.5) * d), fill)
		var ly := -h / 2
		var r := Rect2(lx, ly, w, h)
		for k in 4:   # box-shadow: 0 3px 10px rgba(0,0,0,.35)
			n.draw_rect(Rect2(r.position + Vector2(0, 3 * d), r.size).grow((1.5 + k * 2.0) * d), Color(0, 0, 0, .07))
		n.draw_rect(r, Color(10 / 255.0, 16 / 255.0, 24 / 255.0, .86))
		n.draw_rect(Rect2(lx + .5 * d, ly + .5 * d, w - d, h - d), border, false, 1 * d)
		var y := ly + 5 * d + 5.5 * d
		self_._spaced(n, self_._onest_600, title, Vector2(lx + 7 * d, y), int(round(f1)), .08 * f1, FG)
		if not far:
			y += 15 * d
			Icons.draw(n, "crown", lx + 7 * d, y, 11 * d, Color("#5cc8f2"), 1.7)
			_text(n, self_._onest_500, sub, Vector2(lx + 7 * d + 15 * d, y), int(round(11 * d)), FG2)
		if tag:
			y += 15 * d
			_text(n, F_MONO_B, tag, Vector2(lx + 7 * d, y), int(round(10 * d)), Color("#b8c2cc") if rent else Color("#ffb347"))
	ch.node.queue_redraw()


## the width of a text, measured once (the names do not change)
func _tw(font: Font, s: String, fsize: int) -> float:
	var k := "%d|%d|%s" % [font.get_instance_id(), fsize, s]
	if not _wc.has(k):
		_wc[k] = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	return _wc[k]


## letter-spaced text (letter-spacing: .08em): the advance of every letter plus the spacing, measured once
func _spaced_w(font: Font, s: String, fsize: int, sp: float) -> float:
	var k := "sp%d|%d|%.2f|%s" % [font.get_instance_id(), fsize, sp, s]
	if not _wc.has(k):
		var w := 0.0
		var xs := PackedFloat32Array()
		for ch in s:
			xs.append(w)
			w += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + sp
		_wc[k] = w - sp
		_wc[k + "#"] = xs
	return _wc[k]


func _spaced(n: CanvasItem, font: Font, s: String, pos: Vector2, fsize: int, sp: float, col: Color) -> void:
	var base := pos.y + (font.get_ascent(fsize) - font.get_descent(fsize)) / 2
	_spaced_w(font, s, fsize, sp)
	var xs: PackedFloat32Array = _wc["sp%d|%d|%.2f|%s" % [font.get_instance_id(), fsize, sp, s] + "#"]
	var i := 0
	for ch in s:
		n.draw_char(font, Vector2(pos.x + xs[i], base), ch, fsize, col)
		i += 1


## a square of half-side r turned 45° around c
static func _dia(c: Vector2, r: float) -> PackedVector2Array:
	var d := r * sqrt(2.0)
	return PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
