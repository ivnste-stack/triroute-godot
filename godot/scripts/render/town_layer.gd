class_name TownLayer
extends Control
## Settlements on the map, as the HTML version draws them: border checkpoints, town markers and their
## labels (drawBoardTowns in 08e-company.js, a label is skipped when it would cover a more important one)
## and the country chips at the capitals (buildCityLabels / updateCities in logcities.js and their CSS).
##
## Engine side: every marker, label, chip and checkpoint picture is drawn once into an atlas texture (a
## SubViewport, drawn again only when a hub, the headquarters or the scale change) and the whole layer is one
## MultiMesh with an instance per piece — one draw call. While the camera moves, TRLabelLayout (C++) projects
## the anchors, drops what is off screen or covered and fills the MultiMesh buffer in one go.

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
var _key := ""

const CP_SIZES := [3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0]
const ATLAS_W := 2048

var _order: Array = []         # town indices, the most important first
var _wc := {}                  # widths of the names, measured once
var _onest_600: FontVariation
var _onest_500: FontVariation
var _chips: Array = []         # per country: {cid, pid, x, z, sub}
var _lay: Object = null        # TRLabelLayout (C++)
var _content := ""             # hubs, headquarters and scale the atlas was drawn for
var _lbl_r := PackedFloat32Array()
var _atlas: SubViewport
var _mm: MultiMeshInstance2D
var _n_inst := 0
var _i_mk := PackedInt32Array()
var _i_lb := PackedInt32Array()
var _cp_draw := 7.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_onest_600 = _onest(600)
	_onest_500 = _onest(500)
	_atlas = SubViewport.new()
	_atlas.transparent_bg = true
	_atlas.disable_3d = true
	_atlas.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_atlas.size = Vector2i(ATLAS_W, 64)
	add_child(_atlas)
	_mm = MultiMeshInstance2D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var q := ArrayMesh.new()
	q.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mm.mesh = q
	mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1), Vector3(2e5, 2e5, 2))
	_mm.multimesh = mm
	_mm.texture = _atlas.get_texture()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
render_mode blend_premul_alpha;
// a piece of the atlas: the rectangle of the instance in the custom data (u, v, w, h)
varying vec4 r;
void vertex() { r = INSTANCE_CUSTOM; }
void fragment() { COLOR = textureLod(TEXTURE, r.xy + UV * r.zw, 0.0); }
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_mm.material = m
	_mm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_mm)


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
	var cap_name := {}
	var cap_pid := {}
	for i in towns.size():
		if towns[i].type == "cap":
			cap_name[towns[i].cid] = towns[i].name
			cap_pid[towns[i].cid] = i
	_chips = []
	for c in countries:
		if c.idx >= states.size():
			continue
		# the chip stands at the capital town of the board (the board moves geo.cap there)
		var x: float = c.cap_x / mwh.x * (mwh.x / 80.0) - mwh.x / 160.0
		var z: float = c.cap_y / mwh.y * (mwh.y / 80.0) - mwh.y / 160.0
		if cap_pid.has(c.idx):
			x = towns[cap_pid[c.idx]].x
			z = towns[cap_pid[c.idx]].z
		_chips.append({"cid": c.idx, "pid": cap_pid.get(c.idx, -1), "x": x, "z": z, "sub": cap_name.get(c.idx, "")})
	# instances: the checkpoints, every town (marker, label) by importance, then the chips (near, far)
	_n_inst = cps.size()
	_i_mk = PackedInt32Array()
	_i_lb = PackedInt32Array()
	_i_mk.resize(towns.size())
	_i_lb.resize(towns.size())
	for pid in _order:
		_i_mk[pid] = _n_inst
		_i_lb[pid] = _n_inst + 1
		_n_inst += 2
	_lay = ClassDB.instantiate("TRLabelLayout")
	var xz := PackedFloat32Array()
	var mp := PackedFloat32Array()
	var caps := PackedInt32Array()
	for t in towns:
		xz.append_array([t.x, t.z])
		# villages: only close up; small towns: until 3/4 of the way out (_layout); cities and capitals: always
		mp.append(150.0 if t.type == "vil" else (0.0 if t.type == "town" else -1.0))
		caps.append(1 if t.type == "cap" else 0)
	_lay.set_towns(xz, PackedInt32Array(_order), mp, caps, _i_mk, _i_lb)
	var cxz := PackedFloat32Array()
	var ci := PackedInt32Array()
	for i in cps.size():
		cxz.append_array([cps[i].get("dx", cps[i].x), cps[i].get("dz", cps[i].z)])   # on the border line itself
		ci.append(i)
	_lay.set_points(cxz, ci)
	_n_inst += _chips.size() * 2
	_lay.set_instances(_n_inst)
	_mm.multimesh.instance_count = _n_inst
	_content = ""
	_key = ""


func _process(_delta: float) -> void:
	Perf.begin("town_layer._process")
	_process_t(_delta)
	Perf.end("town_layer._process")


func _process_t(_delta: float) -> void:
	if camera == null or towns.is_empty() or _lay == null:
		return
	var ck := "%.2f|%d" % [dpr, MapVis.ver]
	if sim != null:
		ck += "|%d|%d|%s" % [sim.CO.get("hq", -1), sim.me, sim.CO.get("hubs", []).map(func(h): return [h.pid, h.lvl, h.get("rent", false)])]
	if ck != _content:
		_content = ck
		_rebuild()
		_key = ""
	var k := "%s|%s" % [camera.global_transform, size]   # the camera as it is drawn this frame
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
	if not MapVis.vis("hub"):
		return null
	return sim.hub_at(pid) if sim != null and pid >= 0 and not sim.CO.is_empty() else null


## the atlas: every picture drawn once, packed in shelves; the instances learn their rectangles
func _rebuild() -> void:
	for c in _atlas.get_children():
		_atlas.remove_child(c)
		c.queue_free()
	var pics := []      # [instance or -1, fn, bounds, checkpoint size k]
	for k in CP_SIZES.size():
		var sz: float = CP_SIZES[k] * dpr
		var csz: float = CP_SIZES[k]
		pics.append([-1, func(n: Node2D) -> void: _draw_cp(n, csz), Rect2(-sz - 2, -sz - 2, sz * 2 + 4, sz * 2 + 4), k])
	for pid in _order:
		var I := _town_info(pid)
		_lay.set_town_size(pid, I.s, I.w, I.h, I.mk)
		if I.mk:
			pics.append([_i_mk[pid], I.fn, I.mk_b, -1])
		else:
			_lay.set_instance(_i_mk[pid], Rect2(), Rect2())
		if towns[pid].type != "cap":
			pics.append([_i_lb[pid], I.lb.fn, I.lb_b, -1])
	_lay.clear_chips()
	var base := cps.size() + towns.size() * 2
	for k in _chips.size():
		var ch: Dictionary = _chips[k]
		var nr := _chip_info(ch, false)
		var fr := _chip_info(ch, true)
		pics.append([base + k * 2, nr.fn, nr.b, -1])
		pics.append([base + k * 2 + 1, fr.fn, fr.b, -1])
		_lay.set_chip(k, ch.x, ch.z, ch.pid, base + k * 2, base + k * 2 + 1, nr.lx, nr.w, nr.h, fr.w, fr.h)
	# whole-pixel rectangles: the anchor stays on a whole pixel, so lines keep their sharpness
	for pc in pics:
		var b0: Rect2 = pc[2]
		var p0 := b0.position.floor()
		pc[2] = Rect2(p0, (b0.end - p0).ceil())
	# shelf packing, the tallest first
	var idx := range(pics.size())
	idx.sort_custom(func(a, b): return pics[a][2].size.y > pics[b][2].size.y)
	var x := 0.0
	var y := 0.0
	var row := 0.0
	var at := {}
	for i in idx:
		var b: Rect2 = pics[i][2]
		var w := ceilf(b.size.x)
		var h := ceilf(b.size.y)
		if x + w > ATLAS_W:
			x = 0
			y += row + 2
			row = 0
		at[i] = Vector2(x, y)
		x += w + 2
		row = maxf(row, h)
	var H := int(ceilf(y + row + 2))
	_atlas.size = Vector2i(ATLAS_W, H)
	for i in pics.size():
		var pc: Array = pics[i]
		var b: Rect2 = pc[2]
		var o: Vector2 = at[i]
		var n := Piece.new()
		n.fn = pc[1]
		n.position = o - b.position
		_atlas.add_child(n)
		var uv := Rect2(o.x / ATLAS_W, o.y / H, ceilf(b.size.x) / ATLAS_W, ceilf(b.size.y) / H)
		var bb := Rect2(b.position, Vector2(ceilf(b.size.x), ceilf(b.size.y)))
		if pc[3] >= 0:
			if MapVis.vis("cp"):
				_lay.set_point_picture(pc[3], CP_SIZES[pc[3]], bb, uv)
			else:
				_lay.set_point_picture(pc[3], CP_SIZES[pc[3]], Rect2(), Rect2())
		else:
			_lay.set_instance(pc[0], bb, uv)
	# hidden from the legend: small towns (and villages), cities, capitals with their chips
	for pid in _order:
		var t: String = towns[pid].type
		if not MapVis.vis("s_town" if t == "town" or t == "vil" else "s_city"):
			_lay.set_instance(_i_mk[pid], Rect2(), Rect2())
			_lay.set_instance(_i_lb[pid], Rect2(), Rect2())
	if not MapVis.vis("s_city"):
		for k in _chips.size():
			_lay.set_instance(base + k * 2, Rect2(), Rect2())
			_lay.set_instance(base + k * 2 + 1, Rect2(), Rect2())
	_atlas.render_target_update_mode = SubViewport.UPDATE_ONCE


## where everything goes for this view of the camera (C++), then one buffer for the MultiMesh
func _layout() -> void:
	var a: Variant = _P(camera.tx, camera.tz)
	var b: Variant = _P(camera.tx + 1, camera.tz)
	var ppu: float = a.distance_to(b) / dpr if a != null and b != null else 40.0
	var vp := camera.get_camera_projection() * Projection(camera.get_camera_transform().affine_inverse())
	var vsize := camera.get_viewport().get_visible_rect().size
	var cp_size: float = clampf(ppu / 40, 3.5, 7) if ppu > 45 else 0.0
	# past 3/4 of the zoom out the small towns go (a "pixels per unit" under their threshold of 0)
	var zo := (camera.dist - camera.min_dist) / maxf(.01, camera.world_size.x * 1.25 - camera.min_dist)
	_lbl_r = _lay.layout(vp, vsize, dpr, ppu if zo <= .75 else -.5, cp_size, camera.dist > 11)
	_mm.multimesh.buffer = _lay.buffer()



## the settlement under a point of the screen (coPlaceAt): a country chip, a label
func place_at(pos: Vector2) -> int:
	var p := pos * dpr
	for i in range(_lbl_r.size() - 5, -1, -5):
		if Rect2(_lbl_r[i + 1] - 4, _lbl_r[i + 2], _lbl_r[i + 3] + 4, _lbl_r[i + 4]).has_point(p):
			return int(_lbl_r[i])
	return -1


## what a town shows: the drawing of its marker and label and their rectangles (made again only when the
## hubs, the headquarters or the scale change)
func _town_info(pid: int) -> Dictionary:
	var p: Dictionary = towns[pid]
	var hb: Variant = _hub(pid)
	var hq: bool = sim != null and pid == sim.CO.get("hq", -1)
	var I := {}
	var mk := I
	var lb := {}
	I.lb = lb
	var d := dpr
	# the marker: an orange square for a hub, a diamond for a town without one
	I.mk = p.type != "cap"
	var s: float = ({"big": 6, "city": 5, "town": 4, "vil": 3}.get(p.type, 4) if hb != null else (4.0 if p.type == "big" or p.type == "city" else (3.0 if p.type == "town" else 2.2))) * d
	I.s = s
	if hb != null:
		var hs: float = {"cap": 7, "big": 6, "city": 5, "town": 4, "vil": 3}.get(p.type, 4) * d
		var rent: bool = hb.get("rent", false)
		I.mk_b = Rect2(-hs - 2, -hs - 2, hs * 2 + 4, hs * 2 + 4)
		mk.fn = func(n: Node2D) -> void:
			var hr := Rect2(-hs, -hs, hs * 2, hs * 2)
			n.draw_rect(hr, Color("#a9b4be") if rent else Color("#ffb347"))
			n.draw_rect(hr, Color("#06121b"), false, 1.4 * d)
	else:
		var dd := s * .86 * sqrt(2.0)
		var col := Color.WHITE if p.type == "vil" or p.type == "town" else Color("#5cc8f2")
		I.mk_b = Rect2(-dd - 2, -dd - 2, dd * 2 + 4, dd * 2 + 4)
		mk.fn = func(n: Node2D) -> void:
			var dia := PackedVector2Array([Vector2(0, -dd), Vector2(dd, 0), Vector2(0, dd), Vector2(-dd, 0)])
			n.draw_colored_polygon(dia, col)
			dia.append(dia[0])
			n.draw_polyline(dia, Color("#071420"), 1.3 * d, true)
	# the label
	var big: bool = p.type == "big" or p.type == "city"
	var fs := (12.0 if big else (10.5 if p.type == "town" else 9.5)) * d
	var font: Font = F_INTER_B if big else F_INTER_SB
	var tag := ""
	if hb != null:
		tag = ("★ ШТАБ · " if hq else "") + ("ОРЕНДА · " if hb.get("rent") else "") + String(GameData.HUB_LV[hb.lvl]).to_upper()
	var tgw := _tw(F_MONO_B, tag, int(round(9 * d))) if tag else 0.0
	var icl := []
	if p.port and MapVis.vis("port"):
		icl.append("anchor")
	if (p.air_ov or p.type == "big") and MapVis.vis("air"):
		icl.append("plane")
	if rail_nodes.has(p.node) and MapVis.vis("rails"):
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
	I.lb_b = Rect2(-1, -1, tw + 2, th + 2)
	I.fn = mk.fn
	return I


## a checkpoint: a dark square with a red-white barrier band and a light border, at half size sz
func _draw_cp(n: Node2D, size_: float) -> void:
	var sz := size_ * dpr
	var r := Rect2(-sz, -sz, sz * 2, sz * 2)
	n.draw_rect(r, Color("#0b1520"))
	var band := PackedVector2Array([Vector2(-sz, -sz * .35), Vector2(sz, -sz * .35), Vector2(sz, sz * .35), Vector2(-sz, sz * .35)])
	for k in range(-3, 4):
		var st := PackedVector2Array([Vector2(k * sz * .5, -sz), Vector2(k * sz * .5 + sz * .5, -sz), Vector2(k * sz * .5, sz), Vector2(k * sz * .5 - sz * .5, sz)])
		for poly in Geometry2D.intersect_polygons(st, band):
			n.draw_colored_polygon(poly, Color("#f0625f") if k % 2 else Color.WHITE)
	n.draw_rect(r, Color("#e8edf2"), false, 1.2 * dpr)


## text with its vertical middle at pos.y (textBaseline = "middle")
static func _text(n: CanvasItem, font: Font, s: String, pos: Vector2, fsize: int, col: Color) -> void:
	var asc := font.get_ascent(fsize)
	var desc := font.get_descent(fsize)
	n.draw_string(font, Vector2(pos.x, pos.y + (asc - desc) / 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


# ---------- country chips at the capitals (logcities.js and its CSS, company mode) ----------
## a country chip, far (only the name) or near (with the capital): its drawing and rectangles
func _chip_info(ch: Dictionary, far: bool) -> Dictionary:
	var hb: Variant = _hub(ch.pid)
	var hq: bool = sim != null and ch.pid == sim.CO.get("hq", -1)
	var mine: bool = sim != null and ch.cid == sim.me
	var out := {}
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
	out.w = w
	out.h = h
	out.lx = lx
	var ext := (half + 2) * 1.5 * d + 2
	out.b = Rect2(-ext, -h / 2 - 9 * d, ext + lx + w + 9 * d, h + 21 * d)
	var rent: bool = hb != null and hb.get("rent", false)
	var has_hb := hb != null
	var border := Color(146 / 255.0, 186 / 255.0, 214 / 255.0, .32)
	if has_hb:
		border = Color("#a9b4be") if rent else Color("#ffb347")
	elif mine:
		border = Color("#5cc8f2")
	var self_ := self
	out.fn = func(n: Node2D) -> void:
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
	return out


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
