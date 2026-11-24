class_name WallMesh
extends MeshInstance3D
## Coastal side walls (drawWalls / wallSegs in 08e-company.js) as one static 3D mesh: a vertical face on the
## water side of every coastline segment, built once with the world. The map shader puts the water's depth a
## little below the walls' foot, so the depth buffer hides a wall behind land in front of it (shaders/
## wall.gdshader). The height is a uniform that follows the view, like the original.

const LX := -.45
const LZ := .89

var _mat: ShaderMaterial


## lines: TRWorldGen.lines(); own: the owner per texture pixel (int8 as bytes, < 0 sea); mwh: texture size
func build(lines: Array, own: PackedByteArray, mwh: Vector2i) -> void:
	var MW := mwh.x
	var MH := mwh.y
	var WX := MW / 80.0
	var WZ := MH / 80.0
	var wat := func(x: float, z: float) -> bool:
		var px := int(floor((x + WX / 2) / WX * MW))
		var py := int(floor((z + WZ / 2) / WZ * MH))
		if px < 0 or py < 0 or px >= MW or py >= MH:
			return true
		return own[py * MW + px] > 127   # int8 < 0: sea
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var U := PackedVector2Array()
	var U2 := PackedVector2Array()
	var I := PackedInt32Array()
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
			if not wat.call((x1 + x2) / 2 + nx * .02, (z1 + z2) / 2 + nz * .02):
				nx = -nx
				nz = -nz
			var lv := JS.round_js(maxf(0, nx * LX + nz * LZ) * 6) / 6.0
			# two quads: soil (0 … .5 of the height) and water (.5 … 1), separate so each part is flat-coloured
			for part in 2:
				var b := V.size()
				var d0 := .5 * part
				var d1 := d0 + .5
				for c in [[0.0, d0], [1.0, d0], [1.0, d1], [0.0, d1]]:
					var t: float = c[0]
					V.append(Vector3(lerpf(x1, x2, t), -c[1], lerpf(z1, z2, t)))
					N.append(Vector3(nx, 0, nz))
					C.append(Color(lv, part, 0, 1))
					U.append(Vector2(t * L, c[1]))
					U2.append(Vector2(L, 0))
				I.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = C
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	if V.size():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = m
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/wall.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the walls hang below the plane: a box that holds them, so they are never culled while on screen
	custom_aabb = AABB(Vector3(-WX / 2 - 1, -2, -WZ / 2 - 1), Vector3(WX + 2, 3, WZ + 2))


## the height for this view (half a lattice square, stretched ×1…6 as the view flattens; none when tiny);
## returned so the map shader lowers the water's depth by the same amount
func update(camera: MapCamera) -> float:
	var h0 := .125 / 2
	var a := camera.unproject_position(Vector3(camera.tx, 0, camera.tz))
	var b := camera.unproject_position(Vector3(camera.tx, -h0, camera.tz))
	var c := camera.unproject_position(Vector3(camera.tx, 0, camera.tz + h0))
	var vl := a.distance_to(b)
	var dl := a.distance_to(c)
	var H := h0 * clampf(dl / maxf(vl, 1e-3), 1, 6)
	visible = dl >= 1.5
	if _mat != null:
		_mat.set_shader_parameter("wall_h", H)
	return H if visible else 0.0
