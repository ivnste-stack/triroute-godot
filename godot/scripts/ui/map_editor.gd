class_name MapEditor
extends Control
## The map editor (the HTML version's 08n-editor.js, rebuilt): the world is the lattice of triangles — sqd
## the diagonal of every square, sql the owner of each half (-1 sea, a state, 120 neutral). The tools change
## sql, the settlements and the roads. A change is drawn at once by the map shader from the editor's own
## lattice texture (MapView.edit_update); after every stroke the native world follows (TRWorldGen.edit_apply:
## the owner raster, the states, coasts and borders, ~40 ms) and the map's textures are built again on a copy
## of the generator in a worker thread, so the editor never waits for them.
## Opened before a new game, on a generated world or on an empty ocean. «Почати гру» hands the edit to the
## game: MapEditor.build_world makes the states, the board and the textures of it — the same function makes
## the world again when a saved game is loaded.

signal finished(edit: Dictionary)
signal cancelled

const UNDO_N := 40
const SQ := 0.125   # a lattice square in world units (tri_s / 80)
const NEU := 120
const MAX_STATES := 118
const TOOLS := [
	["sel", "Вибір", "eye", "Клік по державі чи поселенню: назва, колір, столиця, порт."],
	["paint", "Пензель", "plus", "Затисни ліву кнопку й веди: суша обраної держави. Мапу рухає права кнопка."],
	["sea", "Море", "wave", "Затисни ліву кнопку й веди: суша стає морем. Мапу рухає права кнопка."],
	["line", "Кордон", "pin", "Клікай по вузлах сітки. Замкни лінію на першому вузлі — усередині з'явиться нова держава."],
	["isl", "Острів → державі", "anchor", "Клік по острову чи материку: уся ця суша переходить до обраної держави."],
	["islDel", "Стерти острів", "trash", "Клік по острову: уся його суша стає морем."],
	["town", "Поселення", "building", "Клік по суші: нове поселення у вузлі сітки."],
	["townDel", "Стерти поселення", "close", "Клік по поселенню: прибрати його."],
	["road", "Дорога", "road", "Клікай точки: шлях прокладеться по суші. Правий клік чи Esc — завершити лінію."],
	["roadDel", "Стерти дорогу", "minus", "Клік по дорозі чи колії: прибрати її відрізок між вузлами."],
]
const TOWN_T := [["city", "Місто"], ["town", "Містечко"], ["vil", "Село"]]
const TYPE_N := {"cap": "Столиця", "big": "Велике місто", "city": "Місто", "town": "Містечко", "vil": "Село"}
const ROAD_M := [["road", "Дорога"], ["main", "Магістраль"], ["rail", "Залізниця"]]
const NAME_A := ["Нов", "Бер", "Гран", "Сол", "Віл", "Мар", "Кор", "Тал", "Ост", "Дар", "Лім", "Сен", "Ар", "Вест", "Річ", "Зал"]
const NAME_M := ["о", "е", "ан", "ор", "ел", "ар", "ін", "ос", "ур", "ив", "ес", "ал"]
const NAME_B := ["град", "порт", "бург", "ополь", "ен", "ія", "ов", "ар", "іс", "мир", "ськ", "віль", "анда", "ехт"]
const NAME_V := ["івка", "ичі", "ине", "ове", "ка", "ці", "ин", "енки"]
const STATE_A := ["Ал", "Бор", "Вел", "Гар", "Дов", "Ер", "Зор", "Іл", "Кар", "Лув", "Мор", "Нор", "Ор", "Пал", "Рав", "Сар", "Тор", "Ульм", "Фер", "Хаз"]
const STATE_B := ["ія", "ана", "енія", "ландія", "ора", "истан", "інія", "ада", "емія", "унія"]

var map: MapView
var gen: Object
var toast: Callable = Callable()   # (tone, title, body)
var _gtx: Object                   # a copy of the generator: the textures are built on it in a worker thread

# the world: sizes, the lattice, the owner raster and the states from the last edit_apply
var MW := 1800
var MH := 1200
var TS := 10
var SQW := 180
var SQH := 120
var WX := 22.5
var WZ := 15.0
var NX := 181      # board lattice (the roads' nodes): the triangles' lattice or, on the test net, twice as dense
var NZ := 121
var ST := 0.125
var seed_value := 0
var sqd := PackedByteArray()
var sql := PackedInt32Array()
var own := PackedByteArray()
var countries: Array = []
var base: Dictionary = {}          # the sizes of the world, for build_world

var S: Array = []                  # states: {name, color, pop}
var towns: Array = []              # {x, z, type, name, pop, port_ov, air_ov, cid}
var roads: Array = []              # {lv, p}
var rails: Array = []              # PackedFloat32Array
var roads_edited := false

var tool := "sel"
var sel := -1
var sel_t := -1
var brush := 2
var town_type := "town"
var road_mode := "road"
var poly: Array = []               # Vector2i lattice nodes of the border being drawn
var road_pts: Array = []           # board nodes of the road being drawn
var cap_for := -1                  # picking the capital of this state

var _undo: Array = []
var _redo: Array = []
var _lines: Array = []
var _tex := PackedByteArray()
var _tex_dirty := false
var _painting := false
var _stroke_any := false
var _land_changed := false
var _dirty := Rect2()        # where a brush stroke changed the land (empty: anywhere, when _land_changed)
var _mouse := Vector2(-1, -1)
var _rdown := Vector2(-1e9, 0)
var _tx_task := -1
var _tx_result := {}
var _tx_again := false
var _busy := false
var _rng := RandomNumberGenerator.new()

var _panel: PanelContainer
var _body: VBoxContainer
var _status: Label
var _name_edit: LineEdit


# ---------------------------------------------------------------- start / end
func start(map_: MapView, gen_: Object, w: Dictionary, blank: bool) -> void:
	map = map_
	gen = gen_
	MW = int(w.mw)
	MH = int(w.mh)
	TS = int(w.tri_s)
	SQW = int(w.sqw)
	SQH = int(w.sqh)
	WX = MW / 80.0
	WZ = MH / 80.0
	NX = int(w.board.nx)
	NZ = int(w.board.nz)
	ST = float(w.board.st)
	seed_value = int(w.get("seed", 0))
	base = {"mw": w.mw, "mh": w.mh, "tri_s": w.tri_s, "sqw": w.sqw, "sqh": w.sqh, "T": w.get("T", 0.0), "top": w.get("top", 1.0), "bot": w.get("bot", 1.0)}
	sqd = PackedByteArray(w.sqd)
	sql = PackedInt32Array(w.sql)
	_rng.seed = seed_value ^ 0x1d3
	if blank:   # an empty ocean: diagonals at random, so the coasts the brush leaves are not all one slant
		for k in sqd.size():
			sqd[k] = _rng.randi() & 1
		sql.fill(-1)
	else:
		for st in w.states:
			S.append({"name": String(st.name), "color": String(st.color), "pop": float(st.pop)})
		for t in w.board.towns:
			towns.append({"x": float(t.x), "z": float(t.z), "type": String(t.type), "name": String(t.name), "pop": float(t.pop),
				"port_ov": -1, "air_ov": false, "cid": int(t.cid)})
		for r in w.board.roads:
			roads.append({"lv": float(r.lv), "p": PackedFloat32Array(r.p)})
		for r in w.board.railways:
			rails.append(PackedFloat32Array(r))
	_tex.resize(SQW * SQH * 4)
	_tex_all()
	map.edit_begin(SQW, SQH, _tex)
	map.set_sel(-1)
	_gtx = gen.clone()
	map.camera.clicked.connect(_click)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if blank:   # the first state is ready and the brush in hand: the ocean is painted at once
		sel = new_state()
		tool = "paint"
		brush = 3
	_build_panel()
	_land_changed = blank
	_commit()
	map.set_sel(sel)
	map.camera.look_at_point(Vector2(-WX * .07, .3), WX * 1.08)   # the panel covers the left of the screen


func stop() -> void:
	if map.camera.clicked.is_connected(_click):
		map.camera.clicked.disconnect(_click)
	map.camera.left_locked = false
	map.set_sel(-1)
	if _tx_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_tx_task)
		_tx_task = -1


func _say(tone: String, t: String, d: String = "") -> void:
	if toast.is_valid():
		toast.call(tone, t, d)


# ---------------------------------------------------------------- the lattice
static func code(o: int) -> int:
	return 0 if o < 0 else o + 1


func _tex_sq(k: int) -> void:
	if _tex.size() < (k + 1) * 4:
		return
	_tex[k * 4] = code(sql[k * 2])
	_tex[k * 4 + 1] = code(sql[k * 2 + 1])
	_tex[k * 4 + 2] = 255 if sqd[k] else 0
	_tex[k * 4 + 3] = 255


func _tex_all() -> void:
	for k in SQW * SQH:
		_tex_sq(k)
	_tex_dirty = true


## the triangle (square * 2 + half) at a world point, -1 off the board
func tri_at(x: float, z: float) -> int:
	var fx_ := (x + WX / 2) / SQ
	var fy_ := (z + WZ / 2) / SQ
	if fx_ < 0 or fy_ < 0:
		return -1
	var i := int(fx_)
	var j := int(fy_)
	if i >= SQW or j >= SQH:
		return -1
	var fx := fx_ - i
	var fy := fy_ - j
	var k := j * SQW + i
	var h := (0 if fx > fy else 1) if sqd[k] else (0 if fx + fy < 1 else 1)
	return k * 2 + h


func tri_centre(t: int) -> Vector2:
	var k := t >> 1
	var h := t & 1
	var i := k % SQW
	var j := k / SQW
	var c := (Vector2(1.0 / 3, 2.0 / 3) if h else Vector2(2.0 / 3, 1.0 / 3)) if sqd[k] else (Vector2(2.0 / 3, 2.0 / 3) if h else Vector2(1.0 / 3, 1.0 / 3))
	return Vector2(-WX / 2 + (i + c.x) * SQ, -WZ / 2 + (j + c.y) * SQ)


## the triangles across the three sides of a triangle
func tri_nb(t: int) -> Array:
	var k := t >> 1
	var h := t & 1
	var i := k % SQW
	var j := k / SQW
	var out := [k * 2 + (1 - h)]
	var sides: Array = (["b", "l"] if h else ["t", "r"]) if sqd[k] else (["b", "r"] if h else ["t", "l"])
	for s in sides:
		match s:
			"t":
				if j > 0:
					out.append((k - SQW) * 2 + 1)
			"b":
				if j < SQH - 1:
					out.append((k + SQW) * 2)
			"l":
				if i > 0:
					out.append((k - 1) * 2 + (0 if sqd[k - 1] else 1))
			"r":
				if i < SQW - 1:
					out.append((k + 1) * 2 + (1 if sqd[k + 1] else 0))
	return out


## the land that holds triangle t (every state on it)
func island(t: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if t < 0 or sql[t] < 0:
		return out
	var seen := PackedByteArray()
	seen.resize(sql.size())
	var st := [t]
	seen[t] = 1
	while st.size():
		var q: int = st.pop_back()
		out.append(q)
		for n in tri_nb(q):
			if not seen[n] and sql[n] >= 0:
				seen[n] = 1
				st.append(n)
	return out


## the state of the land at a world point (-1 sea or neutral)
func own_at(x: float, z: float) -> int:
	var t := tri_at(x, z)
	if t < 0:
		return -1
	var o := sql[t]
	return o if o >= 0 and o < NEU else -1


## the state a settlement at a board node belongs to: the most of the land around it
func node_own(x: float, z: float) -> int:
	var q := ST * .3
	var cnt := {}
	var best := -1
	for d in [Vector2(q, q), Vector2(-q, q), Vector2(q, -q), Vector2(-q, -q)]:
		var o := own_at(x + d.x, z + d.y)
		if o >= 0:
			cnt[o] = cnt.get(o, 0) + 1
			if best < 0 or cnt[o] > cnt[best]:
				best = o
	return best


func node_xz(n: int) -> Vector2:
	return Vector2(-WX / 2 + (n % NX) * ST, -WZ / 2 + (n / NX) * ST)


func node_at(p: Vector2) -> int:
	var i := clampi(roundi((p.x + WX / 2) / ST), 0, NX - 1)
	var j := clampi(roundi((p.y + WZ / 2) / ST), 0, NZ - 1)
	return j * NX + i


## the triangles under the brush at a world point
func brush_tris(x: float, z: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r := brush
	var i0 := int(floor((x + WX / 2) / SQ)) - r - 1
	var j0 := int(floor((z + WZ / 2) / SQ)) - r - 1
	var lim := (r - .35) * SQ + SQ * .45
	for j in range(j0, j0 + 2 * r + 3):
		for i in range(i0, i0 + 2 * r + 3):
			if i < 0 or j < 0 or i >= SQW or j >= SQH:
				continue
			for h in 2:
				var t := (j * SQW + i) * 2 + h
				if tri_centre(t).distance_to(Vector2(x, z)) <= lim:
					out.append(t)
	return out


func _world(mp: Vector2) -> Variant:
	var p: Variant = map.camera.pick_plane(mp)
	if p == null:
		return null
	var v := Vector2(p.x, p.z)
	if absf(v.x) > WX / 2 or absf(v.y) > WZ / 2:
		return null
	return v


func _scr(x: float, z: float) -> Variant:
	var w := Vector3(x, 0, z)
	if map.camera.is_position_behind(w):
		return null
	return map.camera.unproject_position(w)


# ---------------------------------------------------------------- the world after an edit
## the native world follows the lattice: owner raster, states, coasts and borders; then the layers on the
## map, and the textures in the background
func _commit() -> void:
	var t0 := Time.get_ticks_usec()
	var caps := PackedInt32Array()
	caps.resize(S.size() * 2)
	caps.fill(-1)
	for t in towns:
		if t.type == "cap" and t.cid >= 0 and t.cid < S.size():
			caps[t.cid * 2] = clampi(int((t.x + WX / 2) * 80), 0, MW - 1)
			caps[t.cid * 2 + 1] = clampi(int((t.z + WZ / 2) * 80), 0, MH - 1)
	var d: Dictionary = gen.edit_apply(sqd, sql, S.size(), caps)
	own = d.own
	countries = d.countries
	_lines = gen.lines()
	var t1 := Time.get_ticks_usec()
	_fix_towns()
	if _land_changed:
		_prune_roads()
		_land_changed = false
	_dirty = Rect2()
	var t2 := Time.get_ticks_usec()
	_show_layers()
	var t3 := Time.get_ticks_usec()
	_queue_tx()
	_panel_refresh()
	if OS.get_cmdline_user_args().has("--edscript"):   # test: what an edit costs
		print("editor commit %.0f ms (native %.0f, towns+roads %.0f, layers %.0f)" % [(Time.get_ticks_usec() - t0) / 1000.0, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0])


## settlements whose land is gone are dropped; the rest take the state of their land
func _fix_towns() -> void:
	var keep := []
	for i in towns.size():
		var t: Dictionary = towns[i]
		var o := node_own(t.x, t.z)
		if o < 0:
			if i == sel_t:
				sel_t = -1
			continue
		t.cid = o
		if i == sel_t:
			sel_t = keep.size()
		keep.append(t)
	towns = keep


## a step of a road between two points lies on land when, at a quarter, the middle and three quarters of it,
## land is on one side at least (the native edit_path takes the same rule)
func _step_ok(a: Vector2, b: Vector2) -> bool:
	var pp := Vector2(-(b.y - a.y), b.x - a.x) * .2
	for t in [.25, .5, .75]:
		var m := a.lerp(b, t)
		if own_at(m.x + pp.x, m.y + pp.y) < 0 and own_at(m.x - pp.x, m.y - pp.y) < 0:
			return false
	return true


## roads and railways are cut where the land under them was erased
func _prune_roads() -> void:
	var box := _dirty
	var cut := func(p: PackedFloat32Array) -> Array:
		var out := []
		var run := PackedFloat32Array([p[0], p[1]])
		for k in range(2, p.size(), 2):
			var a := Vector2(p[k - 2], p[k - 1])
			var b := Vector2(p[k], p[k + 1])
			var n := maxi(1, roundi(maxf(absf(b.x - a.x), absf(b.y - a.y)) / ST))
			var ok := true
			if box.size != Vector2.ZERO and not box.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(ST)):
				n = 0   # far from the change: the land under it is as it was
			for s in n:
				if not _step_ok(a.lerp(b, float(s) / n), a.lerp(b, float(s + 1) / n)):
					ok = false
					break
			if ok:
				run.append_array([b.x, b.y])
			else:
				if run.size() >= 4:
					out.append(run)
				run = PackedFloat32Array([b.x, b.y])
		if run.size() >= 4:
			out.append(run)
		return out
	var nr := []
	for r in roads:
		for p in cut.call(r.p):
			nr.append({"lv": r.lv, "p": p})
	roads = nr
	var nl := []
	for r in rails:
		nl.append_array(cut.call(r))
	rails = nl


## the board as the map's layers draw it: the settlements on their nodes, the drawn roads and railways
func _board_view() -> Dictionary:
	var rb := PackedByteArray()
	rb.resize(NX * NZ)
	for r in rails:
		var p: PackedFloat32Array = r
		for k in range(2, p.size(), 2):
			var a := node_at(Vector2(p[k - 2], p[k - 1]))
			var b := node_at(Vector2(p[k], p[k + 1]))
			var ai := a % NX
			var aj := a / NX
			var bi := b % NX
			var bj := b / NX
			rb[a] = 1
			for g in 5000:
				if ai == bi and aj == bj:
					break
				ai += signi(bi - ai)
				aj += signi(bj - aj)
				rb[aj * NX + ai] = 1
	var tv := []
	for t in towns:
		tv.append({"x": t.x, "z": t.z, "type": t.type, "name": t.name, "cid": t.cid, "node": node_at(Vector2(t.x, t.z)), "port": false,
			"air_ov": t.air_ov, "pop": t.pop})
	return {"towns": tv, "roads": roads, "railways": rails, "checkpoints": [], "rbits": rb}


func _show_layers() -> void:
	if map == null:
		return
	var cs := countries.filter(func(c): return c.has_label)
	map.show_layers(_lines, _board_view(), S, cs, own, Vector2i(MW, MH))
	_colors()


func _colors() -> void:
	if map != null:
		map.set_colors(S.map(func(s): return Color(s.color)))


func _queue_tx() -> void:
	if _tx_task >= 0:
		_tx_again = true
		return
	var a := sqd.duplicate()
	var b := sql.duplicate()
	var n := S.size()
	var g: Object = _gtx
	_tx_task = WorkerThreadPool.add_task(func():
		g.edit_apply(a, b, n, PackedInt32Array())
		_tx_result = g.build_textures(true), true, "editor textures")
	_status_upd()


func _process(_delta: float) -> void:
	if _tex_dirty:
		_tex_dirty = false
		map.edit_update(_tex)
	if _tx_task >= 0 and WorkerThreadPool.is_task_completed(_tx_task):
		WorkerThreadPool.wait_for_task_completion(_tx_task)
		_tx_task = -1
		if not _tx_result.is_empty():
			map.set_textures(_tx_result)
		_tx_result = {}
		if _tx_again:
			_tx_again = false
			_queue_tx()
		_status_upd()
	map.camera.left_locked = tool in ["paint", "sea"] and not _busy
	queue_redraw()


# ---------------------------------------------------------------- undo
func _snap() -> Dictionary:
	return {"sqd": sqd.duplicate(), "sql": sql.duplicate(), "towns": towns.duplicate(true), "roads": roads.duplicate(true),
		"rails": rails.duplicate(true), "S": S.duplicate(true), "re": roads_edited, "sel": sel}


func _push_undo() -> void:
	_undo.append(_snap())
	if _undo.size() > UNDO_N:
		_undo.pop_front()
	_redo.clear()


func _restore(s: Dictionary) -> void:
	sqd = s.sqd
	sql = s.sql
	towns = s.towns
	roads = s.roads
	rails = s.rails
	S = s.S
	roads_edited = s.re
	sel = s.sel if s.sel < S.size() else -1
	sel_t = -1
	poly = []
	road_pts = []
	cap_for = -1
	_tex_all()
	_commit()
	map.set_sel(sel)


func undo() -> void:
	if _busy:
		return
	if _undo.is_empty():
		_say("", "Нічого скасовувати")
		return
	_redo.append(_snap())
	_restore(_undo.pop_back())


func redo() -> void:
	if _busy or _redo.is_empty():
		return
	_undo.append(_snap())
	_restore(_redo.pop_back())


# ---------------------------------------------------------------- states and settlements
func _state_name() -> String:
	var used := {}
	for s in S:
		used[s.name] = true
	for k in 80:
		var n: String = STATE_A[_rng.randi() % STATE_A.size()] + STATE_B[_rng.randi() % STATE_B.size()]
		if not used.has(n):
			return n
	return "Нова територія %d" % (S.size() + 1)


func _state_color() -> String:
	var used := {}
	for s in S:
		used[s.color] = true
	for c in MapView.COUNTRY_COLS:
		if not used.has(c):
			return c
	return Color.from_hsv(_rng.randf(), .45 + _rng.randf() * .2, .55 + _rng.randf() * .2).to_html(false)


func new_state() -> int:
	if S.size() >= MAX_STATES:
		_say("warn", "Забагато держав", "Не більше %d" % MAX_STATES)
		return -1
	S.append({"name": _state_name(), "color": "#" + _state_color().trim_prefix("#"), "pop": 0.0})
	return S.size() - 1


func _town_name(vil: bool) -> String:
	var used := {}
	for t in towns:
		used[t.name] = true
	for k in 200:
		var n: String = NAME_A[_rng.randi() % NAME_A.size()] + (NAME_M[_rng.randi() % NAME_M.size()] if k >= 30 else "") + \
			(NAME_V[_rng.randi() % NAME_V.size()] if vil else NAME_B[_rng.randi() % NAME_B.size()])
		if not used.has(n):
			return n
	return "Нове %s%d" % [NAME_A[_rng.randi() % NAME_A.size()], _rng.randi_range(2, 99)]


## a settlement at the board node nearest to p, or null (sea, a settlement too close)
func add_town(p: Vector2, type: String) -> Variant:
	var xz := node_xz(node_at(p))
	var o := node_own(xz.x, xz.y)
	if o < 0:
		_say("warn", "Тут море", "Поселення ставиться на суходіл")
		return null
	for t in towns:
		if Vector2(t.x, t.z).distance_to(xz) < SQ * .9:
			_say("warn", "Тут уже є поселення", t.name)
			return null
	var t := {"x": xz.x, "z": xz.y, "type": type, "name": _town_name(type == "vil"), "pop": 0.0, "port_ov": -1, "air_ov": false, "cid": o}
	towns.append(t)
	return t


func near_town(mp: Vector2, r: float = 16.0) -> int:
	var best := -1
	var bd := r
	for i in towns.size():
		var q: Variant = _scr(towns[i].x, towns[i].z)
		if q == null:
			continue
		var d: float = (q as Vector2).distance_to(mp)
		if d < bd:
			bd = d
			best = i
	return best


func set_capital(cid: int, ti: int) -> void:
	for t in towns:
		if t.cid == cid and t.type == "cap":
			t.type = "city"
	towns[ti].type = "cap"


func capital_of(cid: int) -> int:
	for i in towns.size():
		if towns[i].cid == cid and towns[i].type == "cap":
			return i
	return -1


func area_of(cid: int) -> float:
	for c in countries:
		if c.idx == cid:
			return float(c.area)
	return 0.0


## a state is deleted: its land becomes sea, its settlements go with it
func delete_state(cid: int) -> void:
	_push_undo()
	for t in sql.size():
		if sql[t] == cid:
			sql[t] = -1
	_tex_all()
	_land_changed = true
	sel = -1
	map.set_sel(-1)
	_commit()


# ---------------------------------------------------------------- the line tool
func _lattice_node(p: Vector2) -> Vector2i:
	return Vector2i(clampi(roundi((p.x + WX / 2) / SQ), 0, SQW), clampi(roundi((p.y + WZ / 2) / SQ), 0, SQH))


## lattice steps from a to b: diagonal steps first, then straight
static func _steps(a: Vector2i, b: Vector2i) -> Array:
	var out := []
	var i := a.x
	var j := a.y
	while i != b.x or j != b.y:
		i += signi(b.x - i)
		j += signi(b.y - j)
		out.append(Vector2i(i, j))
	return out


func _close_poly() -> void:
	var P := poly
	poly = []
	if P.size() < 4:
		return
	_push_undo()
	# the diagonal sides follow the squares' diagonals, so the border runs exactly along the drawn line
	for k in range(1, P.size()):
		var a: Vector2i = P[k - 1]
		var b: Vector2i = P[k]
		var di := b.x - a.x
		var dj := b.y - a.y
		if di != 0 and dj != 0:
			var ci := mini(a.x, b.x)
			var cj := mini(a.y, b.y)
			if ci >= 0 and cj >= 0 and ci < SQW and cj < SQH:
				var q := cj * SQW + ci
				var nd := 1 if di * dj > 0 else 0
				if sqd[q] != nd:
					sqd[q] = nd
	var id := new_state()
	if id < 0:
		_undo.pop_back()
		return
	var xs := P.map(func(v): return v.x)
	var ys := P.map(func(v): return v.y)
	var inside := func(x: float, y: float) -> bool:
		var c := false
		var bb := P.size() - 1
		for aa in P.size():
			var pi: Vector2i = P[aa]
			var pj: Vector2i = P[bb]
			if (pi.y > y) != (pj.y > y) and x < float(pj.x - pi.x) * (y - pi.y) / float(pj.y - pi.y) + pi.x:
				c = not c
			bb = aa
		return c
	var n := 0
	for j in range(ys.min(), ys.max()):
		for i in range(xs.min(), xs.max()):
			if i < 0 or j < 0 or i >= SQW or j >= SQH:
				continue
			for h in 2:
				var t := (j * SQW + i) * 2 + h
				var c := tri_centre(t)
				if inside.call((c.x + WX / 2) / SQ, (c.y + WZ / 2) / SQ):
					sql[t] = id
					n += 1
	if n == 0:
		S.pop_back()
		_restore(_undo.pop_back())
		_say("warn", "Порожня область", "Лінія не охопила жодного трикутника")
		return
	_tex_all()
	_land_changed = true
	sel = id
	map.set_sel(sel)
	_commit()
	_say("good", "Нова держава", "%s · назву й колір зміни в картці ліворуч" % S[id].name)


# ---------------------------------------------------------------- roads
func _road_add(a: int, b: int) -> bool:
	var nodes: PackedInt32Array = gen.edit_path(a, b)
	if nodes.size() < 2:
		_say("warn", "Дорогу не прокласти", "Між точками море")
		return false
	var pts := PackedFloat32Array()
	for k in nodes.size():
		if k > 0 and k < nodes.size() - 1 and nodes[k] - nodes[k - 1] == nodes[k + 1] - nodes[k]:
			continue   # a straight run keeps its ends only
		var p := node_xz(nodes[k])
		pts.append_array([p.x, p.y])
	_push_undo()
	if road_mode == "rail":
		rails.append(pts)
	else:
		roads.append({"lv": 3.0 if road_mode == "main" else 2.0, "p": pts})
	roads_edited = true
	_show_layers()
	_panel_refresh()
	return true


## the nearest segment of a road or railway within 10 px of the click goes; the rest of the line stays
func _road_del(mp: Vector2) -> void:
	var best: Array = []
	var bd := 10.0
	for L in [0, 1]:
		var arr: Array = roads if L == 0 else rails
		for i in arr.size():
			var p: PackedFloat32Array = arr[i].p if L == 0 else arr[i]
			for k in range(2, p.size(), 2):
				var a: Variant = _scr(p[k - 2], p[k - 1])
				var b: Variant = _scr(p[k], p[k + 1])
				if a == null or b == null:
					continue
				var q := Geometry2D.get_closest_point_to_segment(mp, a, b)
				var d := q.distance_to(mp)
				if d < bd:
					bd = d
					best = [L, i, k]
	if best.is_empty():
		return
	_push_undo()
	var L: int = best[0]
	var i: int = best[1]
	var k: int = best[2]
	var arr: Array = roads if L == 0 else rails
	var p: PackedFloat32Array = arr[i].p if L == 0 else arr[i]
	# a long segment is split at the lattice node nearest to the click: only the stretch around it goes
	var a := Vector2(p[k - 2], p[k - 1])
	var b := Vector2(p[k], p[k + 1])
	var n := maxi(1, roundi(maxf(absf(b.x - a.x), absf(b.y - a.y)) / ST))
	var w: Variant = _world(mp)
	var s := 0
	if w != null and n > 1:
		s = clampi(int(floor(Geometry2D.get_closest_point_to_segment(w, a, b).distance_to(a) / a.distance_to(b) * n)), 0, n - 1)
	var c0 := a.lerp(b, float(s) / n)
	var c1 := a.lerp(b, float(s + 1) / n)
	var head := p.slice(0, k)
	if c0.distance_to(a) > 1e-4:
		head.append_array([c0.x, c0.y])
	var tail := PackedFloat32Array()
	if c1.distance_to(b) > 1e-4:
		tail.append_array([c1.x, c1.y])
	tail.append_array(p.slice(k))
	var parts := []
	for q in [head, tail]:
		if q.size() >= 4:
			parts.append(q)
	if L == 0:
		var lv: float = arr[i].lv
		arr.remove_at(i)
		for q in parts:
			arr.append({"lv": lv, "p": q})
	else:
		arr.remove_at(i)
		arr.append_array(parts)
	roads_edited = true
	_show_layers()
	_panel_refresh()


## roads and railways generated for the world as it is now (the editor's own lines are replaced)
func auto_roads() -> void:
	if _busy:
		return
	_push_undo()
	var pops := PackedFloat64Array()
	for s in S:
		pops.append(s.pop if s.pop > 0 else 10.0)
	var b: Dictionary = gen.generate_board_given(pops, towns, [], [], true)
	roads = []
	for r in b.roads:
		roads.append({"lv": float(r.lv), "p": PackedFloat32Array(r.p)})
	rails = []
	for r in b.railways:
		rails.append(PackedFloat32Array(r))
	roads_edited = false
	_show_layers()
	_panel_refresh()
	_say("good", "Дороги прокладено", "%d доріг і %d залізниць для поточних поселень" % [roads.size(), rails.size()])


# ---------------------------------------------------------------- input
func _over_panel(mp: Vector2) -> bool:
	return _panel != null and _panel.get_global_rect().has_point(mp)


func _paint_at(mp: Vector2) -> void:
	var w: Variant = _world(mp)
	if w != null:
		paint_w(w, -1 if tool == "sea" else sel)


## the brush at a world point: its triangles take the owner v (-1 sea)
func paint_w(w: Vector2, v: int) -> void:
	var r := (brush + 1.5) * SQ
	var b := Rect2(w - Vector2(r, r), Vector2(r, r) * 2)
	_dirty = b if _dirty.size == Vector2.ZERO else _dirty.merge(b)
	for t in brush_tris(w.x, w.y):
		if sql[t] != v:
			sql[t] = v
			_tex_sq(t >> 1)
			_tex_dirty = true
			_stroke_any = true


func _unhandled_input(ev: InputEvent) -> void:
	if _busy or not visible:
		return
	if ev is InputEventMouseMotion:
		_mouse = ev.position
		if _painting:
			_paint_at(ev.position)
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and tool in ["paint", "sea"]:
			if mb.pressed and not _over_panel(mb.position):
				if tool == "paint" and (sel < 0 or sel >= S.size()):
					_say("warn", "Спершу обери державу", "Клікни по ній інструментом «Вибір» або створи нову")
					return
				_push_undo()
				_painting = true
				_stroke_any = false
				_paint_at(mb.position)
			elif not mb.pressed and _painting:
				_painting = false
				if _stroke_any:
					_land_changed = true
					_commit()
				else:
					_undo.pop_back()
					_dirty = Rect2()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rdown = mb.position
			elif mb.position.distance_to(_rdown) < 5:
				_cancel()


func _unhandled_key_input(ev: InputEvent) -> void:
	if _busy or not visible or not (ev is InputEventKey) or not ev.pressed:
		return
	var k := ev as InputEventKey
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit:
		return
	if k.keycode == KEY_Z and k.ctrl_pressed and not k.shift_pressed:
		undo()
	elif (k.keycode == KEY_Y and k.ctrl_pressed) or (k.keycode == KEY_Z and k.ctrl_pressed and k.shift_pressed):
		redo()
	elif k.keycode == KEY_ESCAPE:
		_cancel()
	elif k.keycode == KEY_BRACKETLEFT or k.keycode == KEY_BRACKETRIGHT:
		var sizes := [1, 2, 3, 5, 8]
		var i := sizes.find(brush)
		brush = sizes[clampi(i + (1 if k.keycode == KEY_BRACKETRIGHT else -1), 0, sizes.size() - 1)]
		_panel_refresh()
	else:
		return
	get_viewport().set_input_as_handled()


## Esc / a right click: the line, the road or the capital being picked is dropped
func _cancel() -> void:
	if poly.size() or road_pts.size() or cap_for >= 0:
		poly = []
		road_pts = []
		cap_for = -1
		_panel_refresh()


func _click(mp: Vector2) -> void:
	if _busy or not visible or _over_panel(mp):
		return
	var w: Variant = _world(mp)
	if w == null:
		return
	var t := tri_at(w.x, w.y)
	if cap_for >= 0:
		var c := cap_for
		cap_for = -1
		var ti := near_town(mp)
		if ti >= 0 and towns[ti].cid != c:
			ti = -1
		_push_undo()
		if ti < 0:
			var nt: Variant = add_town(w, "cap")
			if nt == null:
				_undo.pop_back()
				_panel_refresh()
				return
			if nt.cid != c:
				towns.pop_back()
				_undo.pop_back()
				_say("warn", "Столиця має бути на землі держави", S[c].name)
				_panel_refresh()
				return
			ti = towns.size() - 1
		set_capital(c, ti)
		_commit()
		_say("good", "Столицю призначено", towns[ti].name)
		return
	match tool:
		"sel":
			var ti := near_town(mp)
			if ti >= 0:
				sel_t = ti
				sel = towns[ti].cid
			else:
				sel_t = -1
				sel = sql[t] if t >= 0 and sql[t] < NEU else -1
			map.set_sel(sel)
			_panel_refresh()
		"line":
			var nd := _lattice_node(w)
			if poly.size() > 2 and nd == poly[0]:
				poly.append_array(_steps(poly[poly.size() - 1], nd))
				poly.pop_back()
				_close_poly()
				return
			if poly.is_empty():
				poly.append(nd)
			else:
				poly.append_array(_steps(poly[poly.size() - 1], nd))
			_panel_refresh()
		"isl", "islDel":
			if tool == "isl" and (sel < 0 or sel >= S.size()):
				_say("warn", "Спершу обери державу", "Інструментом «Вибір» або кнопкою «Нова держава»")
				return
			var L := island(t)
			if L.is_empty():
				return
			_push_undo()
			var v := sel if tool == "isl" else -1
			for q in L:
				sql[q] = v
			_tex_all()
			_land_changed = true
			_commit()
		"town":
			_push_undo()
			if add_town(w, town_type) == null:
				_undo.pop_back()
				return
			sel_t = towns.size() - 1
			_show_layers()
			_panel_refresh()
		"townDel":
			var ti := near_town(mp)
			if ti < 0:
				return
			_push_undo()
			towns.remove_at(ti)
			sel_t = -1
			_show_layers()
			_panel_refresh()
		"road":
			var n := node_at(w)
			if road_pts.size():
				if n == road_pts[road_pts.size() - 1]:
					return
				if not _road_add(road_pts[road_pts.size() - 1], n):
					return
			road_pts.append(n)
			_panel_refresh()
		"roadDel":
			_road_del(mp)


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if map == null or _busy:
		return
	var acc := Color("#5cc8f2")
	if tool in ["paint", "sea"] and not _over_panel(_mouse):
		var w: Variant = _world(_mouse)
		if w != null:
			var r := (brush - .35) * SQ + SQ * .45
			var pts := PackedVector2Array()
			for k in 41:
				var a := TAU * k / 40.0
				var q: Variant = _scr(w.x + cos(a) * r, w.y + sin(a) * r)
				if q != null:
					pts.append(q)
			if pts.size() > 2:
				var col := Color("#8fd3ff") if tool == "sea" else (Color(S[sel].color).lightened(.35) if sel >= 0 and sel < S.size() else Color.WHITE)
				draw_polyline(pts, Color(0, 0, 0, .5), 3.0, true)
				draw_polyline(pts, col, 1.5, true)
	# the border being drawn: its nodes and the step to the pointer
	if tool == "line":
		var line := PackedVector2Array()
		for nd in poly:
			var q: Variant = _scr(-WX / 2 + nd.x * SQ, -WZ / 2 + nd.y * SQ)
			if q != null:
				line.append(q)
		var hw: Variant = _world(_mouse)
		if hw != null:
			var nd := _lattice_node(hw)
			var q: Variant = _scr(-WX / 2 + nd.x * SQ, -WZ / 2 + nd.y * SQ)
			if q != null:
				if line.size():
					draw_dashed_line(line[line.size() - 1], q, Color(1, 1, 1, .6), 1.5, 6.0)
				draw_circle(q, 4.0, Color(1, 1, 1, .85))
		if line.size() > 1:
			draw_polyline(line, Color(0, 0, 0, .55), 4.0, true)
			draw_polyline(line, Color("#ffd27a"), 2.0, true)
		if line.size():
			draw_circle(line[0], 6.0, Color("#ffd27a"))
			draw_circle(line[0], 3.0, Color(0, 0, 0, .7))
	# the road being drawn
	if tool == "road":
		var prev: Variant = null
		for n in road_pts:
			var p := node_xz(n)
			var q: Variant = _scr(p.x, p.y)
			if q != null:
				draw_circle(q, 4.5, Color("#f6b94f"))
				prev = q
		var hw: Variant = _world(_mouse)
		if hw != null:
			var p := node_xz(node_at(hw))
			var q: Variant = _scr(p.x, p.y)
			if q != null:
				if prev != null:
					draw_dashed_line(prev, q, Color("#f6b94f", .8), 1.5, 6.0)
				draw_arc(q, 5.0, 0, TAU, 20, Color.WHITE, 1.5, true)
	if tool == "town" or cap_for >= 0:
		var hw: Variant = _world(_mouse)
		if hw != null:
			var p := node_xz(node_at(hw))
			var q: Variant = _scr(p.x, p.y)
			if q != null:
				var ok := node_own(p.x, p.y) >= 0
				draw_arc(q, 6.0, 0, TAU, 20, Color.WHITE if ok else Color("#f0625f"), 1.6, true)
	if sel_t >= 0 and sel_t < towns.size():
		var q: Variant = _scr(towns[sel_t].x, towns[sel_t].z)
		if q != null:
			draw_arc(q, 11.0, 0, TAU, 28, Color(0, 0, 0, .55), 4.0, true)
			draw_arc(q, 11.0, 0, TAU, 28, acc, 2.0, true)


# ---------------------------------------------------------------- the panel
func _build_panel() -> void:
	_panel = Ui.glass()
	_panel.anchor_top = 0
	_panel.anchor_bottom = 1
	_panel.offset_left = 14
	_panel.offset_top = 14
	_panel.offset_bottom = -14
	_panel.custom_minimum_size.x = 318
	add_child(_panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(Ui.margin(sc, 14))
	_body = Ui.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	_panel_refresh()


func _status_upd() -> void:
	if _status != null:
		_status.text = "Оновлення мапи…" if _tx_task >= 0 else ""


func _tool_btn(t: Array) -> Button:
	var on: bool = tool == t[0]
	var b := Ui.btn(t[1], "sm", t[2], func():
		tool = t[0]
		poly = []
		road_pts = []
		cap_for = -1
		_panel_refresh())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = t[3]
	if on:
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, Ui.box(Ui.ACCENT_SOFT, Ui.ACCENT, 1, Vector4(10, 0, 10, 0)))
		b.icon = Icons.tex(t[2], Ui.ACCENT, 16, 1.8)
		b.add_theme_color_override("font_color", Ui.ACCENT)
		b.add_theme_color_override("font_hover_color", Ui.ACCENT)
	return b


func _panel_refresh() -> void:
	if _body == null:
		return
	_name_edit = null
	for c in _body.get_children():
		c.queue_free()
	var head := Ui.hbox(8, [Ui.icon("edit", 18, Ui.ACCENT), Ui.heading("Редактор мапи", 16)])
	_body.add_child(head)
	var n_alive := 0
	for c in countries:
		if c.area > 0:
			n_alive += 1
	_body.add_child(Ui.note("держав: %d · поселень: %d · доріг: %d · залізниць: %d" % [n_alive, towns.size(), roads.size(), rails.size()], Ui.MUTED))
	# the tools, two in a row
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for t in TOOLS:
		g.add_child(_tool_btn(t))
	_body.add_child(g)
	var hint: String = ""
	for t in TOOLS:
		if t[0] == tool:
			hint = t[3]
	if cap_for >= 0:
		hint = "Клікни по поселенню держави «%s» або по її суші: там стане столиця. Esc — скасувати." % S[cap_for].name
	_body.add_child(Ui.hint(hint))
	# the options of the tool
	if tool in ["paint", "sea"]:
		_body.add_child(Ui.hbox(10, [Ui.lbl("Пензель"), Ui.seg([[1, "1"], [2, "2"], [3, "3"], [5, "5"], [8, "8"]], brush, func(v): brush = v)]))
	if tool == "town":
		_body.add_child(Ui.seg(TOWN_T, town_type, func(v): town_type = v))
	if tool == "road":
		_body.add_child(Ui.seg(ROAD_M, road_mode, func(v): road_mode = v))
	if tool in ["paint", "isl", "line", "sel"]:
		var nb := Ui.btn("Нова держава", "sm", "flag", func():
			_push_undo()
			var id := new_state()
			if id < 0:
				_undo.pop_back()
				return
			sel = id
			sel_t = -1
			map.set_sel(sel)
			if tool == "sel":
				tool = "paint"
			_commit()
			_say("good", "Нова держава", "%s · малюй її сушу пензлем" % S[id].name))
		_body.add_child(nb)
	# the selected settlement, or the selected state
	if sel_t >= 0 and sel_t < towns.size():
		_body.add_child(_town_card(sel_t))
	elif sel >= 0 and sel < S.size():
		_body.add_child(_state_card(sel))
	_body.add_child(HSeparator.new())
	var ur := Ui.hbox(6, [Ui.btn("Скасувати", "sm", "refresh", undo), Ui.btn("Повторити", "sm", "", redo)])
	(ur.get_child(0) as Button).disabled = _undo.is_empty()
	(ur.get_child(1) as Button).disabled = _redo.is_empty()
	(ur.get_child(0) as Button).tooltip_text = "Ctrl+Z"
	(ur.get_child(1) as Button).tooltip_text = "Ctrl+Y"
	_body.add_child(ur)
	var ar := Ui.btn("Прокласти дороги автоматично", "sm", "road", auto_roads)
	ar.tooltip_text = "Дороги й залізниці між поточними поселеннями, як у згенерованому світі"
	_body.add_child(ar)
	_body.add_child(Ui.note("Дороги: " + ("намальовані вручну — у грі будуть саме вони" if roads_edited else "автоматичні — у грі прокладуться заново для зміненої мапи"), Ui.MUTED))
	_status = Ui.label("", 12, Ui.ACCENT, Ui.font("mono", 500))
	_body.add_child(_status)
	_status_upd()
	var go := Ui.btn("Почати гру", "pri", "play", _finish)
	go.custom_minimum_size.y = 40
	_body.add_child(go)
	_body.add_child(Ui.btn("Вийти в меню", "sm", "close", func(): cancelled.emit()))
	_body.add_child(Ui.note("Права кнопка або WASD — рух мапи, коліщатко — масштаб, [ ] — розмір пензля.", Ui.MUTED))


func _state_card(cid: int) -> Control:
	var s: Dictionary = S[cid]
	var v := Ui.vbox(8)
	var cp := ColorPickerButton.new()
	cp.color = Color(s.color)
	cp.custom_minimum_size = Vector2(34, 30)
	cp.edit_alpha = false
	cp.color_changed.connect(func(c: Color):
		s.color = "#" + c.to_html(false)
		_colors())
	cp.picker_created.connect(func(): cp.get_picker().presets_visible = false)
	cp.popup_closed.connect(func(): _panel_refresh())
	var e := LineEdit.new()
	e.text = s.name
	e.max_length = 32
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(func(t):
		if t.strip_edges() != "":
			s.name = t.strip_edges())
	e.text_submitted.connect(func(_t):
		e.release_focus())
	e.focus_exited.connect(func(): _show_layers())
	_name_edit = e
	v.add_child(Ui.lbl("Держава"))
	v.add_child(Ui.hbox(8, [cp, e]))
	var ci := capital_of(cid)
	var area := area_of(cid)
	var ntw := towns.filter(func(t): return t.cid == cid).size()
	v.add_child(Ui.note("Суша: %d кл. · поселень: %d · столиця: %s" % [int(area / (TS * TS)), ntw, towns[ci].name if ci >= 0 else "не обрано"], Ui.FG2))
	var row := Ui.hbox(6)
	row.add_child(Ui.btn("Обрати столицю", "sm", "crown", func():
		cap_for = cid
		_panel_refresh()))
	row.add_child(Ui.btn("Колір", "sm", "dice", func():
		_push_undo()
		var c := Color.from_hsv(_rng.randf(), .4 + _rng.randf() * .25, .5 + _rng.randf() * .25)
		s.color = "#" + c.to_html(false)
		_colors()
		_panel_refresh()))
	v.add_child(row)
	var del := Ui.btn("Видалити державу", "sm", "trash", func(): delete_state(cid))
	del.tooltip_text = "Її суша стане морем (Ctrl+Z поверне)"
	v.add_child(del)
	return Ui.blk(v, Color(Color(s.color), .6))


func _town_card(ti: int) -> Control:
	var t: Dictionary = towns[ti]
	var v := Ui.vbox(8)
	var e := LineEdit.new()
	e.text = t.name
	e.max_length = 32
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(func(x):
		if x.strip_edges() != "":
			t.name = x.strip_edges())
	e.text_submitted.connect(func(_x): e.release_focus())
	e.focus_exited.connect(func(): _show_layers())
	_name_edit = e
	v.add_child(Ui.lbl(TYPE_N.get(t.type, "Поселення") + " · " + (S[t.cid].name if t.cid >= 0 and t.cid < S.size() else "")))
	v.add_child(e)
	var types := [["city", "Місто"], ["town", "Містечко"], ["vil", "Село"]]
	if t.type in ["cap", "big"]:
		types.push_front([t.type, TYPE_N[t.type]])
	v.add_child(Ui.seg(types, t.type, func(x):
		_push_undo()
		t.type = x
		_show_layers()
		_panel_refresh()))
	var mk := Ui.hbox(6)
	if t.type != "cap":
		mk.add_child(Ui.btn("Зробити столицею", "sm", "crown", func():
			_push_undo()
			set_capital(t.cid, ti)
			_commit()))
	if t.type != "big" and t.type != "cap":
		mk.add_child(Ui.btn("Велике", "sm", "star", func():
			_push_undo()
			t.type = "big"
			_show_layers()
			_panel_refresh()))
	v.add_child(mk)
	v.add_child(Ui.hbox(8, [Ui.lbl("Порт"), Ui.seg([[-1, "Авто"], [1, "Так"], [0, "Ні"]], t.port_ov, func(x):
		_push_undo()
		t.port_ov = x)]))
	var air := CheckBox.new()
	air.text = "Аеропорт навіть у малому поселенні"
	air.button_pressed = t.air_ov
	air.add_theme_font_size_override("font_size", 12)
	air.toggled.connect(func(on):
		_push_undo()
		t.air_ov = on)
	v.add_child(air)
	v.add_child(Ui.note("Порт «Авто»: біля моря в містах, у частини містечок; на малих островах — завжди.", Ui.MUTED))
	v.add_child(Ui.btn("Прибрати поселення", "sm", "trash", func():
		_push_undo()
		towns.remove_at(ti)
		sel_t = -1
		_show_layers()
		_panel_refresh()))
	return Ui.blk(v)


# ---------------------------------------------------------------- tests
## a scripted edit (main.gd --edscript): a new state painted out into the sea, its settlements and a road;
## the land of a state of the world given to its neighbour; then the panel of the new state
func test_script() -> void:
	var id := new_state()
	sel = id
	_push_undo()
	brush = 3
	var c := Vector2(-WX * .3, WZ * .05)
	for k in 60:
		var a := k / 60.0 * TAU
		paint_w(c + Vector2(cos(a) * 1.6, sin(a * 2) * .7), id)
	brush = 5
	paint_w(c, id)
	_stroke_any = true
	_land_changed = true
	_commit()
	brush = 2
	tool = "sea"
	_push_undo()
	paint_w(c + Vector2(.2, 0), -1)
	_land_changed = true
	_commit()
	var t1: Variant = add_town(c + Vector2(-1.2, .1), "city")
	var t2: Variant = add_town(c + Vector2(1.3, .2), "town")
	add_town(c + Vector2(.1, -.55), "vil")
	if t1 != null and t2 != null:
		road_mode = "main"
		_road_add(node_at(Vector2(t1.x, t1.z)), node_at(Vector2(t2.x, t2.z)))
	if S.size() > 2:
		var L := island(tri_at(c.x, c.y))
		print("TEST editor: state %d, island %d triangles, %d towns, %d roads, %d rails" % [id, L.size(), towns.size(), roads.size(), rails.size()])
	tool = "paint"
	sel_t = -1
	map.set_sel(sel)
	_panel_refresh()


# ---------------------------------------------------------------- the end: the edit for the game
## the states with land, each with a capital (the biggest settlement, or a new one at its centre); states
## without land are dropped and the others renumbered. Returns the edit, or {} when it cannot start yet.
func make_edit() -> Dictionary:
	var alive := []
	for c in countries:
		if c.area > 0 and c.idx < S.size():
			alive.append(int(c.idx))
	if alive.is_empty():
		_say("warn", "Немає жодної держави", "Намалюй сушу пензлем держави")
		return {}
	var order := {"cap": 0, "big": 1, "city": 2, "town": 3, "vil": 4}
	var made := 0
	for cid in alive:
		var ts := []
		for i in towns.size():
			if towns[i].cid == cid:
				ts.append(i)
		var caps := ts.filter(func(i): return towns[i].type == "cap")
		for k in range(1, caps.size()):
			towns[caps[k]].type = "city"
		if caps.size():
			continue
		if ts.size():
			ts.sort_custom(func(a, b): return order[towns[a].type] < order[towns[b].type] or (order[towns[a].type] == order[towns[b].type] and towns[a].pop > towns[b].pop))
			towns[ts[0]].type = "cap"
			continue
		# no settlement: a capital at the board node of the state nearest to its label point
		var c: Dictionary = countries[cid]
		var lp := Vector2(c.lx / 80.0 - WX / 2, c.ly / 80.0 - WZ / 2)
		var n0 := node_at(lp)
		var best := -1
		var bd := INF
		var i0 := n0 % NX
		var j0 := n0 / NX
		for r in range(0, maxi(NX, NZ)):
			var ring := []   # the nodes r steps away (the square's border)
			for q in range(-r, r + 1):
				ring.append_array([Vector2i(i0 + q, j0 - r), Vector2i(i0 + q, j0 + r)])
				if absi(q) != r:
					ring.append_array([Vector2i(i0 - r, j0 + q), Vector2i(i0 + r, j0 + q)])
			for v: Vector2i in ring:
				if v.x < 1 or v.y < 1 or v.x >= NX - 1 or v.y >= NZ - 1:
					continue
				var p := node_xz(v.y * NX + v.x)
				if node_own(p.x, p.y) == cid:
					var d := p.distance_squared_to(lp)
					if d < bd:
						bd = d
						best = v.y * NX + v.x
			if best >= 0:
				break
		if best >= 0:
			var p := node_xz(best)
			towns.append({"x": p.x, "z": p.y, "type": "cap", "name": _town_name(false), "pop": 0.0, "port_ov": -1, "air_ov": false, "cid": cid})
			made += 1
	var remap := {}
	for i in alive.size():
		remap[alive[i]] = i
	var sq := sql.duplicate()
	for t in sq.size():
		var o := sq[t]
		if o >= 0 and o < NEU:
			sq[t] = remap.get(o, -1)
	var tw := []
	for t in towns:
		if remap.has(t.cid):
			tw.append({"x": t.x, "z": t.z, "type": t.type, "name": t.name, "pop": t.pop, "port_ov": t.port_ov, "air_ov": t.air_ov})
	var st := []
	for k in alive:
		st.append({"name": S[k].name, "color": S[k].color})
	if made:
		_say("", "Столиці додано", "%d держав без поселень отримали столицю" % made)
	return {"v": 1, "sqd": sqd.duplicate(), "sql": sq, "states": st, "towns": tw, "roads": roads.duplicate(true) if roads_edited else [],
		"rails": rails.duplicate(true) if roads_edited else [], "roads_edited": roads_edited}


func _finish() -> void:
	if _busy:
		return
	if _painting:
		return
	var e := make_edit()
	if e.is_empty():
		return
	_busy = true
	if _tx_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_tx_task)
		_tx_task = -1
	finished.emit(e)


## The world of an edit, ready for the game (TRWorldGen: edit_apply, the states, the board of the edit's
## settlements with its roads or generated ones, the textures and the lines). gen holds the base world of the
## same seed and size; thread-safe for one generator. The board's settlements with their populations go
## back into the edit, so a saved game makes the very same board again.
static func build_world(gen: Object, base_: Dictionary, edit: Dictionary) -> Dictionary:
	var n: int = edit.states.size()
	var d: Dictionary = gen.edit_apply(edit.sqd, edit.sql, n, PackedInt32Array())
	var w := {}
	for k in ["mw", "mh", "tri_s", "sqw", "sqh", "T", "top", "bot"]:
		if base_.has(k):
			w[k] = base_[k]
	w.own = d.own
	w.countries = d.countries
	w.land_count = d.land_count
	w.sqd = edit.sqd
	w.sql = edit.sql
	var st: Array = gen.generate_states()
	for i in mini(n, st.size()):
		var e: Dictionary = edit.states[i]
		var old := String(st[i].name)
		st[i].name = e.name
		st[i].full = String(st[i].full).replace(old, e.name) if old != "" and String(st[i].full).contains(old) else e.name
		st[i].color = e.color
	w.states = st
	var pops := PackedFloat64Array()
	for s in st:
		pops.append(float(s.pop))
	w.board = gen.generate_board_given(pops, edit.towns, edit.get("roads", []), edit.get("rails", []), not edit.get("roads_edited", false))
	# the settlements as the board placed them (with their populations); the port choice is the edit's own
	var ov := {}
	for t in edit.towns:
		ov["%.3f,%.3f" % [t.x, t.z]] = t
	var tw := []
	for t in w.board.towns:
		var o: Dictionary = ov.get("%.3f,%.3f" % [t.x, t.z], {})
		tw.append({"x": t.x, "z": t.z, "type": t.type, "name": t.name, "pop": t.pop, "port_ov": int(o.get("port_ov", -1)), "air_ov": bool(o.get("air_ov", false))})
	edit.towns = tw
	w.textures = gen.build_textures()
	w.lines = gen.lines()
	w.edit = edit
	return w
