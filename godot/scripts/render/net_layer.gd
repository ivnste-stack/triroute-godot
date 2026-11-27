class_name NetLayer
extends Control
## The network of the alternative balance on the map (SimNet): the flows of the last weeks along the roads,
## railways and sea lanes the company's runs took (thicker with more tons, coloured by the kind of transport) and
## a box with a count in the towns where cargo waits for a pick-up. Drawn again only when the camera or the
## network changes.

const BOX_DX := 0.0   # the box's left edge against the label's
const F_MONO_B := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const FLOW_COL := Color("#8b959e")   # one solid grey for every kind of transport

var camera: MapCamera
var towns: TownLayer           # where the towns' labels are on the screen (the boxes sit over them)
var session: GameSession
var dpr := 1.0
var _key := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _on() -> bool:
	return session != null and session.sim != null and camera != null and not session.sim.CO.is_empty() and session.sim.alt() and MapVis.vis("hub")


func _process(_delta: float) -> void:
	if not _on():
		if _key != "":
			_key = ""
			queue_redraw()
		return
	var CO: Dictionary = session.sim.CO
	var k := "%s|%s|%d|%d|%d|%d|%d" % [camera.global_transform, size, int(session.sim.co_now() * 8), CO.net.cs.size(), CO.net.runs.size(), CO.hubs.size(), CO.net.flow.size()]
	if k != _key:
		_key = k
		queue_redraw()


func _P(x: float, z: float) -> Variant:
	var w := Vector3(x, 0, z)
	if camera.is_position_behind(w):
		return null
	return camera.unproject_position(w)


var _routes := {}   # "a:b:m" → the world points of the route (the routes change only with closures)
var _routes_v := -2


## a flow's route on the screen: the world points of co_route projected; the parts behind the camera left out
func _route_pts(sim: Sim, m: String, a: int, b: int, A: Dictionary, B: Dictionary) -> PackedVector2Array:
	if _routes_v != sim.blk_v:
		_routes_v = sim.blk_v
		_routes = {}
	var key := "%d:%d:%s" % [a, b, m]
	if not _routes.has(key):
		var w := PackedFloat32Array([A.x, A.z, B.x, B.z])
		if m != "air":
			var r: Variant = sim.co_route(m, a, b)
			if r != null:
				w = r.p
		_routes[key] = w
	var wp: PackedFloat32Array = _routes[key]
	var out := PackedVector2Array()
	for i in range(0, wp.size(), 2):
		var q: Variant = _P(wp[i], wp[i + 1])
		if q != null:
			out.append(q)
	return out


func _draw() -> void:
	if not _on():
		return
	var sim: Sim = session.sim
	var CO: Dictionary = sim.CO
	var rect := Rect2(Vector2(-60, -60), size + Vector2(120, 120))
	# flows; a road is 1.15 × the zoom factor wide (MapOverlay)
	var rw := 1.15 * clampf(pow(12.0 / camera.dist, .6), .8, 3.6) * dpr
	for key in CO.net.flow:
		var p: PackedStringArray = String(key).split(":")
		var A: Dictionary = sim.PL[int(p[0])]
		var B: Dictionary = sim.PL[int(p[1])]
		var t: float = CO.net.flow[key]
		var wd := rw * (.75 + minf(.15, log(1 + t) * .03))   # a little thinner than a road, a little wider with more tons
		var col: Color = FLOW_COL
		# along the road, the railway or the sea lane the runs take (a plane flies straight)
		var pts := _route_pts(sim, p[2], int(p[0]), int(p[1]), A, B)
		if pts.size() < 2:
			continue
		var bb := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			bb = bb.expand(q)
		if not bb.intersects(rect):
			continue
		draw_polyline(pts, col, wd)   # one solid line: no halo, no blur
	# cargo waiting in towns
	var wait := {}
	for c in CO.net.cs:
		if c.st == "wait" and c.run < 0:
			wait[c.at] = wait.get(c.at, 0) + 1
	var fs := int(11 * dpr)
	var lbl := {}   # town → its label's rectangle on the screen
	if towns != null:
		var R: PackedFloat32Array = towns._lbl_r
		var k := maxf(.01, towns.dpr)
		for i in range(0, R.size() - 4, 5):
			lbl[int(R[i])] = Rect2(R[i + 1] / k, R[i + 2] / k, R[i + 3] / k, R[i + 4] / k)
	for pid in wait:
		var P: Dictionary = sim.PL[pid]
		var s: Variant = _P(P.x, P.z)
		if s == null or not rect.has_point(s):
			continue
		var txt := str(wait[pid])
		var tw := F_MONO_B.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(s + Vector2(1, -25) * dpr, Vector2(22 * dpr + tw, 18 * dpr))
		if lbl.has(pid):   # over the town's name, from the left edge of its label
			var L: Rect2 = lbl[pid]
			r.position = Vector2(L.position.x + BOX_DX * dpr, L.position.y - r.size.y - 3 * dpr)
		var c := Vector2(r.position.x + 9 * dpr, r.get_center().y)
		draw_rect(r, Color(8 / 255.0, 18 / 255.0, 28 / 255.0, .92))
		draw_rect(r, Color("#f1c453"), false, 1.2 * dpr)
		Icons.draw(self, "box", r.position.x + 3 * dpr, c.y, 12 * dpr, Color("#f1c453"))
		draw_string(F_MONO_B, Vector2(r.position.x + 17 * dpr, c.y + 4 * dpr), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f1c453"))
