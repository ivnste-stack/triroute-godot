class_name TownLayer
extends Control
## Settlements on the map, as the HTML version draws them: border checkpoints, town markers and their
## labels (drawBoardTowns in 08e-company.js, a label is skipped when it would cover a more important one)
## and the country chips at the capitals (buildCityLabels / updateCities in logcities.js and their CSS).
## Redrawn when the camera moves.

const F_INTER_B := preload("res://assets/fonts/Inter-Bold.otf")
const F_INTER_SB := preload("res://assets/fonts/Inter-SemiBold.otf")
const F_MONO_B := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const F_ONEST := preload("res://assets/fonts/Onest.ttf")
const ORDER := {"cap": 0, "big": 1, "city": 2, "town": 3, "vil": 4}
const FG := Color("#e7eef4")
const FG2 := Color("#b3c2cf")

var camera: MapCamera
var towns: Array = []          # board towns: {x, z, type, name, port, air_ov, cid, node…}
var rail_nodes := {}           # lattice nodes on the railway graph (a town with a station)
var states: Array = []
var countries: Array = []      # world countries (capital position in texture pixels)
var cps: Array = []            # border checkpoints
var mwh := Vector2(1800, 1200)
var sim: Sim = null            # the company (hubs on the labels), optional
var dpr := 1.0
var lbl: Array = []             # {pid, r}: the labels and country chips on screen (BOARD.lbl, CITY_EL)

var _order: Array = []
var _key := ""
var _onest_600: FontVariation
var _onest_500: FontVariation


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
	_order = towns.duplicate()
	SimCore._stable_sort(_order, func(a, b): return ORDER[a.type] - ORDER[b.type])
	_key = ""
	queue_redraw()


func _process(_delta: float) -> void:
	if camera == null or towns.is_empty():
		return
	var k := "%.4f|%.4f|%.4f|%s" % [camera.tx, camera.tz, camera.dist, size]
	if sim != null:
		k += "|%d" % sim.CO.get("hubs", []).size()
	if k != _key:
		_key = k
		queue_redraw()


func _P(x: float, z: float) -> Variant:
	var w := Vector3(x, 0, z)
	if camera.is_position_behind(w):
		return null
	return camera.unproject_position(w)


func _hub(pid: int) -> Variant:
	return sim.hub_at(pid) if sim != null and not sim.CO.is_empty() else null


func _draw() -> void:
	lbl = []
	if camera == null or towns.is_empty():
		return
	var W := size.x
	var H := size.y
	var a: Variant = _P(camera.tx, camera.tz)
	var b: Variant = _P(camera.tx + 1, camera.tz)
	var ppu: float = a.distance_to(b) if a != null and b != null else 40.0
	# border checkpoints: a dark square with a red-white barrier band
	if ppu > 45:
		var sz := clampf(ppu / 40, 3.5, 7) * dpr
		for c in cps:
			var q: Variant = _P(c.x, c.z)
			if q == null or q.x < -20 or q.y < -20 or q.x > W + 20 or q.y > H + 20:
				continue
			var r := Rect2(q.x - sz, q.y - sz, sz * 2, sz * 2)
			draw_rect(r, Color("#0b1520"))
			var band := PackedVector2Array([Vector2(q.x - sz, q.y - sz * .35), Vector2(q.x + sz, q.y - sz * .35), Vector2(q.x + sz, q.y + sz * .35), Vector2(q.x - sz, q.y + sz * .35)])
			for k in range(-3, 4):
				var st := PackedVector2Array([Vector2(q.x + k * sz * .5, q.y - sz), Vector2(q.x + k * sz * .5 + sz * .5, q.y - sz), Vector2(q.x + k * sz * .5, q.y + sz), Vector2(q.x + k * sz * .5 - sz * .5, q.y + sz)])
				for poly in Geometry2D.intersect_polygons(st, band):
					draw_colored_polygon(poly, Color("#f0625f") if k % 2 else Color.WHITE)
			draw_rect(r, Color("#e8edf2"), false, 1.2 * dpr)
	# settlements
	var boxes := []
	for p in _order:
		var shown: bool = ppu > 150 if p.type == "vil" else (ppu > 60 if p.type == "town" else true)
		if not shown:
			continue
		var c: Variant = _P(p.x, p.z)
		if c == null or c.x < -60 or c.y < -60 or c.x > W + 60 or c.y > H + 60:
			continue
		var pid: int = towns.find(p)
		var hb: Variant = _hub(pid)
		if hb != null and p.type != "cap":
			var hs: float = {"cap": 7, "big": 6, "city": 5, "town": 4, "vil": 3}.get(p.type, 4) * dpr
			var hr := Rect2(c.x - hs, c.y - hs, hs * 2, hs * 2)
			draw_rect(hr, Color("#a9b4be") if hb.get("rent") else Color("#ffb347"))
			draw_rect(hr, Color("#06121b"), false, 1.4 * dpr)
		if p.type == "cap":
			continue   # capitals use the country chip
		var s: float = ({"big": 6, "city": 5, "town": 4, "vil": 3}.get(p.type, 4) if hb != null else (4.0 if p.type == "big" or p.type == "city" else (3.0 if p.type == "town" else 2.2))) * dpr
		if hb == null:
			var d := s * .86 * sqrt(2.0)
			var dia := PackedVector2Array([Vector2(c.x, c.y - d), Vector2(c.x + d, c.y), Vector2(c.x, c.y + d), Vector2(c.x - d, c.y)])
			draw_colored_polygon(dia, Color.WHITE if p.type == "vil" or p.type == "town" else Color("#5cc8f2"))
			dia.append(dia[0])
			draw_polyline(dia, Color("#071420"), 1.3 * dpr, true)
		# label
		var big: bool = p.type == "big" or p.type == "city"
		var fs := (12.0 if big else (10.5 if p.type == "town" else 9.5)) * dpr
		var font: Font = F_INTER_B if big else F_INTER_SB
		var tag := ""
		if hb != null:
			tag = ("★ ШТАБ · " if pid == sim.CO.hq else "") + ("ОРЕНДА · " if hb.get("rent") else "") + String(GameData.HUB_LV[hb.lvl]).to_upper()
		var tgw := F_MONO_B.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(9 * dpr))).x if tag else 0.0
		var icl := []
		if p.port:
			icl.append("anchor")
		if p.air_ov or p.type == "big":
			icl.append("plane")
		if rail_nodes.has(p.node):
			icl.append("train")
		var isz := 11 * dpr
		var name_w := font.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs))).x
		var nmw := name_w + (icl.size() * (isz + 2 * dpr) + 4 * dpr if icl.size() else 0.0)
		var tw := maxf(nmw, tgw) + 12 * dpr
		var th := fs + 8 * dpr + (12 * dpr if tag else 0.0)
		var lx: float = c.x + s + 5 * dpr
		var ly: float = c.y - th / 2
		var hit := false
		for bx in boxes:
			if lx < bx[2] and lx + tw > bx[0] and ly < bx[3] and ly + th > bx[1]:
				hit = true
				break
		if hit:
			continue
		boxes.append([lx, ly, lx + tw, ly + th])
		lbl.append({"pid": pid, "r": Rect2(lx, ly, tw, th)})
		draw_rect(Rect2(lx, ly, tw, th), Color(8 / 255.0, 18 / 255.0, 28 / 255.0, .86))
		var bc := (Color(170 / 255.0, 182 / 255.0, 194 / 255.0, .85) if hb.get("rent") else Color(1, 179 / 255.0, 71 / 255.0, .8)) if tag else Color(160 / 255.0, 180 / 255.0, 198 / 255.0, .28)
		draw_rect(Rect2(lx + .5 * dpr, ly + .5 * dpr, tw - dpr, th - dpr), bc, false, 1 * dpr)
		var mid := ly + (fs + 8 * dpr) / 2 + .5 * dpr
		_text(font, p.name, Vector2(lx + 6 * dpr, mid), int(round(fs)), Color("#c9d4de"))
		var ix := lx + 6 * dpr + name_w + 5 * dpr
		for n in icl:
			Icons.draw(self, n, ix, ly + (fs + 8 * dpr) / 2, isz, Color("#9fb4c6"))
			ix += isz + 2 * dpr
		if tag:
			_text(F_MONO_B, tag, Vector2(lx + 6 * dpr, ly + fs + 8 * dpr + 3 * dpr), int(round(9 * dpr)), Color("#b8c2cc") if hb.get("rent") else Color("#ffb347"))
	_draw_chips()


## text with its vertical middle at pos.y (textBaseline = "middle")
func _text(font: Font, s: String, pos: Vector2, fsize: int, col: Color) -> void:
	var asc := font.get_ascent(fsize)
	var desc := font.get_descent(fsize)
	draw_string(font, Vector2(pos.x, pos.y + (asc - desc) / 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## the settlement under a point of the screen (coPlaceAt): a label, a country chip
func place_at(pos: Vector2) -> int:
	for i in range(lbl.size() - 1, -1, -1):
		var r: Rect2 = lbl[i].r
		if r.grow_side(SIDE_LEFT, 4).has_point(pos * dpr):
			return lbl[i].pid
	return -1


# ---------- country chips at the capitals (logcities.js and its CSS, company mode) ----------
func _draw_chips() -> void:
	var far := camera.dist > 11
	var W := size.x
	var H := size.y
	var cap_name := {}
	var cap_pid := {}
	for i in towns.size():
		if towns[i].type == "cap":
			cap_name[towns[i].cid] = towns[i].name
			cap_pid[towns[i].cid] = i
	for c in countries:
		if c.idx >= states.size():
			continue
		# the chip stands at the capital town of the board (the board moves geo.cap there)
		var x: float = c.cap_x / mwh.x * (mwh.x / 80.0) - mwh.x / 160.0
		var z: float = c.cap_y / mwh.y * (mwh.y / 80.0) - mwh.y / 160.0
		if cap_pid.has(c.idx):
			x = towns[cap_pid[c.idx]].x
			z = towns[cap_pid[c.idx]].z
		var q: Variant = _P(x, z)
		if q == null or q.x < -80 or q.x > W + 80 or q.y < -40 or q.y > H + 40:
			continue
		var st: Dictionary = states[c.idx]
		var hb: Variant = _hub(cap_pid.get(c.idx, -1))
		var title: String = String(st.name).to_upper()
		var sub: String = cap_name.get(c.idx, "")
		var tag := ""
		if hb != null:
			tag = ("★ Штаб · " if cap_pid[c.idx] == sim.CO.hq else "") + ("Оренда · " if hb.get("rent") else "") + String(GameData.HUB_LV[hb.lvl])
			tag = tag.to_upper()
		var f1 := 11.0 * dpr
		var tw := _spaced_w(_onest_600, title, int(round(f1)), .08 * f1)
		var sw := 0.0 if far else 11 * dpr + 4 * dpr + _onest_500.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(11 * dpr))).x
		var tgw := 0.0 if tag == "" else F_MONO_B.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(10 * dpr))).x
		var w := maxf(tw, maxf(sw, tgw)) + 15 * dpr
		var rows := 1 + (0 if far else 1) + (1 if tag else 0)
		var h := (rows * 11.0 + (rows - 1) * 4.0 + 10.0) * dpr
		# the capital marker: a 9 px square with a 1.5 px border turned 45°, a faint ring around it
		var mc: Vector2 = q + Vector2(.5 * dpr, 0)
		var ring := Color("#ffb347") if hb != null else Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .35)
		var fill := (Color("#a9b4be") if hb.get("rent") else Color("#ffb347")) if hb != null else Color("#5cc8f2")
		var half := (11.0 if hb != null else 9.0) / 2   # box-sizing: border-box
		if hb == null:
			draw_colored_polygon(_dia(mc, (half + 1) * dpr), ring)
		draw_colored_polygon(_dia(mc, half * dpr), Color("#06121b") if hb != null else Color("#04131c"))
		draw_colored_polygon(_dia(mc, (half - 1.5) * dpr), fill)
		var lx: float = q.x - 5.5 * dpr + (half * 2 + 6) * dpr
		var ly: float = q.y - h / 2
		var r := Rect2(lx, ly, w, h)
		if cap_pid.has(c.idx):
			lbl.append({"pid": cap_pid[c.idx], "r": Rect2(q.x - 10 * dpr, ly, lx + w - q.x + 10 * dpr, h), "cap": true})
		for k in 4:   # box-shadow: 0 3px 10px rgba(0,0,0,.35)
			draw_rect(Rect2(r.position + Vector2(0, 3 * dpr), r.size).grow((1.5 + k * 2.0) * dpr), Color(0, 0, 0, .07))
		draw_rect(r, Color(10 / 255.0, 16 / 255.0, 24 / 255.0, .86))
		var border := Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .32)
		if hb != null:
			border = Color("#a9b4be") if hb.get("rent") else Color("#ffb347")
		elif sim != null and c.idx == sim.me:
			border = Color("#5cc8f2")
		draw_rect(Rect2(lx + .5 * dpr, ly + .5 * dpr, w - dpr, h - dpr), border, false, 1 * dpr)
		var y := ly + 5 * dpr + 5.5 * dpr
		_spaced(_onest_600, title, Vector2(lx + 7 * dpr, y), int(round(f1)), .08 * f1, FG)
		if not far:
			y += 15 * dpr
			Icons.draw(self, "crown", lx + 7 * dpr, y, 11 * dpr, Color("#5cc8f2"), 1.7)
			_text(_onest_500, sub, Vector2(lx + 7 * dpr + 15 * dpr, y), int(round(11 * dpr)), FG2)
		if tag:
			y += 15 * dpr
			_text(F_MONO_B, tag, Vector2(lx + 7 * dpr, y), int(round(10 * dpr)), Color("#b8c2cc") if hb.get("rent") else Color("#ffb347"))


func _spaced_w(font: Font, s: String, fsize: int, sp: float) -> float:
	var w := 0.0
	for ch in s:
		w += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + sp
	return w - sp


## letter-spaced text (letter-spacing: .08em)
func _spaced(font: Font, s: String, pos: Vector2, fsize: int, sp: float, col: Color) -> void:
	var x := pos.x
	var base := pos.y + (font.get_ascent(fsize) - font.get_descent(fsize)) / 2
	for ch in s:
		draw_string(font, Vector2(x, base), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + sp


## a square of half-side r turned 45° around c
static func _dia(c: Vector2, r: float) -> PackedVector2Array:
	var d := r * sqrt(2.0)
	return PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
