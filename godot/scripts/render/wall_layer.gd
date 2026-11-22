class_name WallLayer
extends Node2D
## Coastal side walls (drawWalls / wallSegs in 08e-company.js), drawn by shaders/overlay_wall.gdshader:
## one instance per coastline segment, the faces and the lines in two passes.

const LX := -.45
const LZ := .89

var _faces: ShaderMaterial
var _lines: ShaderMaterial
var _world := Vector2.ZERO


## lines: TRWorldGen.lines(); own: the owner per texture pixel (int8 as bytes, < 0 sea); mwh: texture size
func build(lines: Array, own: PackedByteArray, mwh: Vector2i) -> void:
	for c in get_children():
		c.queue_free()
	var MW := mwh.x
	var MH := mwh.y
	_world = Vector2(MW / 80.0, MH / 80.0)
	var WX := _world.x
	var WZ := _world.y
	var wat := func(x: float, z: float) -> bool:
		var px := int(floor((x + WX / 2) / WX * MW))
		var py := int(floor((z + WZ / 2) / WZ * MH))
		if px < 0 or py < 0 or px >= MW or py >= MH:
			return true
		return own[py * MW + px] > 127   # int8 < 0: sea
	var data := PackedFloat32Array()
	for l in lines:
		if l.a != 0:
			continue
		var p: PackedFloat32Array = l.p
		for i in range(2, p.size(), 2):
			var x1 := p[i - 2]
			var z1 := p[i - 1]
			var x2 := p[i]
			var z2 := p[i + 1]
			var L := JS.hypot(x2 - x1, z2 - z1)
			if L < 1e-6:
				continue
			var nx := -(z2 - z1) / L
			var nz := (x2 - x1) / L
			var mx := (x1 + x2) / 2
			var mz := (z1 + z2) / 2
			if not wat.call(mx + nx * .02, mz + nz * .02):
				nx = -nx
				nz = -nz
			var lv := JS.round_js(maxf(0, nx * LX + nz * LZ) * 6)
			data.append_array([x1, z1, x2, z2, nx, nz, lv])
	# the land mask for the shader
	var img := Image.create(MW, MH, false, Image.FORMAT_R8)
	var bytes := PackedByteArray()
	bytes.resize(MW * MH)
	for i in MW * MH:
		bytes[i] = 0 if own[i] > 127 else 255
	img.set_data(MW, MH, false, Image.FORMAT_R8, bytes)
	var land := ImageTexture.create_from_image(img)
	var shader: Shader = load("res://shaders/overlay_wall.gdshader")
	_faces = ShaderMaterial.new()
	_faces.shader = shader
	_lines = ShaderMaterial.new()
	_lines.shader = shader
	_lines.set_shader_parameter("lines", true)
	for m in [_faces, _lines]:
		m.set_shader_parameter("land", land)
		m.set_shader_parameter("world", _world)
	add_child(_instances(data, _face_mesh(), _faces))
	add_child(_instances(data, _line_mesh(), _lines))


static func _face_mesh() -> ArrayMesh:
	# soil: depth 0 … .5, water: .5 … 1 (separate vertices, the part is in UV.x)
	var V := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, .5), Vector2(0, .5), Vector2(0, .5), Vector2(1, .5), Vector2(1, 1), Vector2(0, 1)])
	var U := PackedVector2Array([Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 0), Vector2(1, 0), Vector2(1, 0)])
	return _mesh(V, U, PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7]))


static func _line_mesh() -> ArrayMesh:
	var V := PackedVector2Array()
	var U := PackedVector2Array()
	var I := PackedInt32Array()
	for id in 3:
		var b := V.size()
		for c in [[0, -1], [1, -1], [1, 1], [0, 1]]:
			V.append(Vector2(c[0], 0))
			U.append(Vector2(c[1], id))
		I.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	return _mesh(V, U, I)


static func _mesh(V: PackedVector2Array, U: PackedVector2Array, I: PackedInt32Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## data: 7 floats per wall (x1, z1, x2, z2, nx, nz, light level)
static func _instances(data: PackedFloat32Array, mesh: ArrayMesh, mat: ShaderMaterial) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	var n := data.size() / 7
	mm.instance_count = n
	var buf := PackedFloat32Array()
	buf.resize(n * 16)   # transform (8) + colour (4) + custom (4)
	for i in n:
		var o := i * 16
		var d := i * 7
		buf[o] = 1.0
		buf[o + 5] = 1.0
		buf[o + 8] = data[d + 4]
		buf[o + 9] = data[d + 5]
		buf[o + 10] = data[d + 6]
		buf[o + 11] = 1.0
		buf[o + 12] = data[d]
		buf[o + 13] = data[d + 1]
		buf[o + 14] = data[d + 2]
		buf[o + 15] = data[d + 3]
	if n:
		mm.buffer = buf
	mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1), Vector3(2e5, 2e5, 2))
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.material = mat
	return node


## the terrain texture and its lattice: the walls hide behind land triangle by triangle, as the map draws it
func set_terrain(t0: Texture2D, tri_s: float, mwh: Vector2) -> void:
	for m in [_faces, _lines]:
		if m != null:
			m.set_shader_parameter("t0", t0)
			m.set_shader_parameter("triS", tri_s)
			m.set_shader_parameter("MWH", mwh)


func update(camera: MapCamera, view_proj: Projection, screen: Vector2) -> void:
	if _faces == null:
		return
	# the height: half a lattice square, stretched as the view flattens (×1…6), none when too small
	var h0 := .125 / 2
	var a := camera.unproject_position(Vector3(camera.tx, 0, camera.tz))
	var b := camera.unproject_position(Vector3(camera.tx, -h0, camera.tz))
	var c := camera.unproject_position(Vector3(camera.tx, 0, camera.tz + h0))
	var vl := a.distance_to(b)
	var dl := a.distance_to(c)
	var H := h0 * clampf(dl / maxf(vl, 1e-3), 1, 6)
	visible = dl >= 1.5
	var e := camera.global_position
	for m in [_faces, _lines]:
		m.set_shader_parameter("view_proj", view_proj)
		m.set_shader_parameter("inv_view_proj", view_proj.inverse())
		m.set_shader_parameter("screen", screen)
		m.set_shader_parameter("eye", e)
		m.set_shader_parameter("wall_h", H)
