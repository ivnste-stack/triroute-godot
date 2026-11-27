class_name LineLayer
extends Node2D
## One stroke of polylines on the map, as the HTML version strokes a path on its 2D canvas: a width in screen
## pixels, one colour, one alpha for the whole stroke (shaders/overlay_line.gdshader projects and widens the
## geometry on the GPU). A translucent stroke is drawn opaque inside a CanvasGroup and composited once, so
## segments and joins that overlap do not darken. Strokes are drawn in tree order (the order they are added).

static var _shader: Shader

var _mat: ShaderMaterial
var _mat_d: ShaderMaterial
var _group: CanvasGroup
var _color := Color.WHITE


## geometry: build_geometry(); joins: a disc at every vertex (round joins and caps)
func _init(geometry: Dictionary, color: Color, width_px: float) -> void:
	if _shader == null:
		_shader = load("res://shaders/overlay_line.gdshader")
	_group = CanvasGroup.new()
	_group.fit_margin = 0.0
	_group.clear_margin = 0.0
	add_child(_group)
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_group.add_child(_instances(geometry.seg, _quad(Vector2(0, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0, 1)), _mat))
	if geometry.disc.size():
		_mat_d = ShaderMaterial.new()
		_mat_d.shader = _shader
		_mat_d.set_shader_parameter("discs", true)
		_group.add_child(_instances(geometry.disc, _quad(Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)), _mat_d))
	set_style(color, width_px)


static func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([a, b, c, d])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## one instance per entry of data (4 floats: a.x, a.z, b.x, b.z)
static func _instances(data: PackedFloat32Array, mesh: ArrayMesh, mat: ShaderMaterial) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = mesh
	var n := data.size() / 4
	mm.instance_count = n
	# per instance: a 2D transform (8 floats, identity) and the custom data (4 floats)
	var buf := PackedFloat32Array()
	buf.resize(n * 12)
	for i in n:
		var o := i * 12
		buf[o] = 1.0
		buf[o + 5] = 1.0
		buf[o + 8] = data[i * 4]
		buf[o + 9] = data[i * 4 + 1]
		buf[o + 10] = data[i * 4 + 2]
		buf[o + 11] = data[i * 4 + 3]
	if n:
		mm.buffer = buf
	mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1), Vector3(2e5, 2e5, 2))   # the quads move in the shader
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.material = mat
	return node


func set_style(color: Color, width_px: float) -> void:
	_color = color
	for m in [_mat, _mat_d]:
		if m != null:
			m.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	_group.self_modulate = Color(1, 1, 1, color.a)
	set_width(width_px)


func set_width(width_px: float) -> void:
	for m in [_mat, _mat_d]:
		if m != null:
			m.set_shader_parameter("width_px", width_px)


## stripes across the line (period in pixels, 0 — none) in a second colour: the toll motorways
func set_hatch(period_px: float, color2: Color) -> void:
	for m in [_mat, _mat_d]:
		if m != null:
			m.set_shader_parameter("hatch", period_px)
			m.set_shader_parameter("color2", Vector3(color2.r, color2.g, color2.b))


## alpha on top of the stroke's own (fading grid levels)
func set_alpha(a: float) -> void:
	_group.self_modulate = Color(1, 1, 1, _color.a * a)
	visible = a > 0.0


func set_camera(view_proj: Projection, screen: Vector2) -> void:
	for m in [_mat, _mat_d]:
		if m != null:
			m.set_shader_parameter("view_proj", view_proj)
			m.set_shader_parameter("screen", screen)


## polylines: Array of PackedFloat32Array (x, z pairs) or PackedVector2Array → {seg, disc} instance data
static func build_geometry(polylines: Array, joins: bool = true) -> Dictionary:
	var seg := PackedFloat32Array()
	var disc := PackedFloat32Array()
	for pl in polylines:
		var pts := PackedVector2Array()
		if pl is PackedVector2Array:
			pts = pl
		else:
			for i in range(0, pl.size() - 1, 2):
				pts.append(Vector2(pl[i], pl[i + 1]))
		if pts.size() < 2:
			continue
		for i in range(1, pts.size()):
			if pts[i - 1] != pts[i]:
				seg.append_array([pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y])
		if joins:
			for p in pts:
				disc.append_array([p.x, p.y, 0.0, 0.0])
	return {"seg": seg, "disc": disc}
