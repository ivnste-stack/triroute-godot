class_name NetLayer
extends Control
## The network of the alternative balance on the map (SimNet): a box with a count in the towns where cargo waits
## for a pick-up (the runs are the vehicles on the map, with no traces of their routes). Drawn again only when
## the camera or the network changes.

const BOX_DX := 0.0   # the box's left edge against the label's
const F_MONO_B := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")

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
	var k := "%s|%s|%d|%d|%d|%d" % [camera.global_transform, size, int(session.sim.co_now() * 8), CO.net.cs.size(), CO.net.runs.size(), CO.hubs.size()]
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
