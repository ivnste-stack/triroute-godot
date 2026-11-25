class_name NetLayer
extends Control
## The network of the alternative balance on the map (SimNet): the flows of the last weeks between the places
## the company's runs went (thicker with more tons, coloured by the kind of transport), a warehouse badge over
## every hub (how full it is, how many consignments, a terminal event) and a box with a count in the towns where
## cargo waits for a pick-up. Drawn again only when the camera or the network changes.

const F_MONO_B := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const MODE_COL := {"road": Color("#f5a742"), "rail": Color("#e0884f"), "sea": Color("#5aa9ff"), "air": Color("#b58cff")}

var camera: MapCamera
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


func _draw() -> void:
	if not _on():
		return
	var sim: Sim = session.sim
	var CO: Dictionary = sim.CO
	var rect := Rect2(Vector2(-60, -60), size + Vector2(120, 120))
	# flows
	for key in CO.net.flow:
		var p: PackedStringArray = String(key).split(":")
		var A: Dictionary = sim.PL[int(p[0])]
		var B: Dictionary = sim.PL[int(p[1])]
		var a: Variant = _P(A.x, A.z)
		var b: Variant = _P(B.x, B.z)
		if a == null or b == null or not (rect.has_point(a) or rect.has_point(b)):
			continue
		var t: float = CO.net.flow[key]
		var wd := (1.2 + log(1 + t) * .9) * dpr
		var col: Color = MODE_COL.get(p[2], Color.WHITE)
		draw_line(a, b, Color(col, .22), wd + 3 * dpr, true)
		draw_line(a, b, Color(col, .75), wd, true)
	# cargo waiting in towns
	var wait := {}
	for c in CO.net.cs:
		if c.st == "wait" and c.run < 0:
			wait[c.at] = wait.get(c.at, 0) + 1
	var fs := int(11 * dpr)
	for pid in wait:
		var P: Dictionary = sim.PL[pid]
		var s: Variant = _P(P.x, P.z)
		if s == null or not rect.has_point(s):
			continue
		var c: Vector2 = s + Vector2(10, -16) * dpr
		var txt := str(wait[pid])
		var tw := F_MONO_B.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(c - Vector2(9, 9) * dpr, Vector2(22 * dpr + tw, 18 * dpr))
		draw_rect(r, Color(8 / 255.0, 18 / 255.0, 28 / 255.0, .92))
		draw_rect(r, Color("#f1c453"), false, 1.2 * dpr)
		Icons.draw(self, "box", r.position.x + 3 * dpr, c.y, 12 * dpr, Color("#f1c453"))
		draw_string(F_MONO_B, Vector2(r.position.x + 17 * dpr, c.y + 4 * dpr), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f1c453"))
	# the hubs' warehouses
	for h in CO.hubs:
		var P: Dictionary = sim.PL[h.pid]
		var s: Variant = _P(P.x, P.z)
		if s == null or not rect.has_point(s):
			continue
		var st := sim.n_stored(h.pid)
		var cap := sim.n_cap(h.pid)
		var n := 0
		for c in CO.net.cs:
			if c.at == h.pid and (c.st == "ready" or c.st == "proc"):
				n += 1
		var f := clampf(st / cap, 0, 1) if cap > 0 else 0.0
		var col := Color("#f0625f") if st > cap else (Color("#f1c453") if f > .85 else Color("#4fd1c5"))
		var o: Vector2 = s + Vector2(-26, 14) * dpr
		var r := Rect2(o, Vector2(52, 16) * dpr)
		draw_rect(r, Color(8 / 255.0, 18 / 255.0, 28 / 255.0, .92))
		draw_rect(Rect2(o + Vector2(2, 11) * dpr, Vector2(48 * f, 3) * dpr), col)
		draw_rect(r, Color(col, .8), false, 1.0 * dpr)
		draw_string(F_MONO_B, o + Vector2(4, 9) * dpr, "%d · %dт" % [n, int(round(st))], HORIZONTAL_ALIGNMENT_LEFT, 44 * dpr, int(9 * dpr), Color("#e7eef4"))
		var T: Variant = sim.net_term(h.pid)
		if T != null:
			var ex := 0.0
			for e in T.ev:
				if e.until > sim.co_now():
					var c2: Vector2 = o + Vector2(60 + ex, 8) * dpr
					draw_circle(c2, 9 * dpr, Color(8 / 255.0, 18 / 255.0, 28 / 255.0, .92))
					draw_arc(c2, 9 * dpr, 0, TAU, 24, Color("#f0625f"), 1.3 * dpr, true)
					Icons.draw(self, SimNet.NET_EV[e.k][1], c2.x - 6 * dpr, c2.y, 12 * dpr, Color("#f0625f"))
					ex += 22
