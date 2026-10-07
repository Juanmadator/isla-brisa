class_name TerrainView
extends Node3D
## Malla del terreno en trozos, colisión de mapa de alturas y el agua (mar y lago).

const CHUNK := 64

var island: Island
var body: StaticBody3D
## Materiales del mar y del lago: [material, pasos de reflejo en calidad alta].
var water_mats: Array = []


func build(isl: Island) -> void:
	island = isl
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("rim_amount", 0.0)
	mat.set_shader_parameter("band_soft", 0.12)
	var cells := Island.N - 1
	for cz in range(0, cells, CHUNK):
		for cx in range(0, cells, CHUNK):
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(cx, cz, mini(CHUNK, cells - cx), mini(CHUNK, cells - cz))
			mi.material_override = mat
			add_child(mi)
	_build_collision()
	_build_water()


func _chunk_mesh(cx: int, cz: int, w: int, d: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var n := Island.N
	for zi in d + 1:
		for xi in w + 1:
			var gi := (cz + zi) * n + cx + xi
			verts.append(Vector3(-Island.HALF + (cx + xi) * Island.STEP, island.heights[gi], -Island.HALF + (cz + zi) * Island.STEP))
			norms.append(island.normals[gi])
			cols.append(island.colors[gi])
	var row := w + 1
	for zi in d:
		for xi in w:
			var a := zi * row + xi
			var b := a + 1
			var c := a + row
			var e := c + 1
			# Godot toma como cara frontal la de orden horario visto desde fuera.
			idx.append_array([a, b, c, e, c, b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_collision() -> void:
	body = StaticBody3D.new()
	body.name = "TerrainBody"
	add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = Island.N
	shape.map_depth = Island.N
	var data := PackedFloat32Array()
	data.resize(Island.N * Island.N)
	for i in data.size():
		data[i] = island.heights[i] / Island.STEP
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * Island.STEP
	body.add_child(cs)


func _build_water() -> void:
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water.gdshader")
	wmat.render_priority = 10
	var sea := MeshInstance3D.new()
	sea.mesh = _sea_mesh(1400.0, 220, 4500.0)
	sea.material_override = wmat
	sea.position = Vector3(0, Island.SEA_LEVEL, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.extra_cull_margin = 64.0
	sea.name = "Sea"
	add_child(sea)
	var lake := MeshInstance3D.new()
	var lm := PlaneMesh.new()
	lm.size = Vector2(120, 120)
	lm.subdivide_width = 40
	lm.subdivide_depth = 40
	lake.mesh = lm
	var lmat: ShaderMaterial = wmat.duplicate()
	lmat.set_shader_parameter("wave_height", 0.06)
	lmat.set_shader_parameter("shallow_color", Color(0.42, 0.85, 0.78))
	lmat.set_shader_parameter("depth_range", 6.0)
	lmat.set_shader_parameter("clip_center", Island.LAKE)
	lmat.set_shader_parameter("clip_radius", 57.0)
	# Lago Espejo: casi sin rizos, refleja mucho y con nitidez.
	lmat.set_shader_parameter("ripple_amount", 0.25)
	lmat.set_shader_parameter("reflect_min", 0.3)
	lmat.set_shader_parameter("reflect_max", 0.92)
	lmat.set_shader_parameter("ssr_strength", 1.0)
	lmat.set_shader_parameter("deep_color", Color(0.08, 0.3, 0.36))
	lake.material_override = lmat
	water_mats = [[wmat, 40], [lmat, 48]]
	lake.position = Vector3(Island.LAKE.x, Island.LAKE_LEVEL, Island.LAKE.y)
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lake.name = "Lake"
	add_child(lake)


## Mar en una sola malla: rejilla fina de `size` m en el centro (para las olas) y cuatro
## faldones de anillos hasta `reach` m que comparten los vértices del borde (sin juntas).
static func _sea_mesh(size: float, cells: int, reach: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var h := size * 0.5
	var step := size / cells
	var row := cells + 1
	for zi in row:
		for xi in row:
			verts.append(Vector3(-h + xi * step, 0.0, -h + zi * step))
	for zi in cells:
		for xi in cells:
			var a := zi * row + xi
			idx.append_array([a, a + 1, a + row, a + row + 1, a + row, a + 1])
	# Bordes en sentido horario visto desde arriba: norte (z = -h), este, sur y oeste.
	var edges := []
	var north := []
	var east := []
	var south := []
	var west := []
	for i in row:
		north.append(i)
		east.append(i * row + cells)
		south.append(cells * row + (cells - i))
		west.append((cells - i) * row)
	edges = [north, east, south, west]
	# Anillos cada vez más separados: la niebla y la luz se interpolan bien en todo el faldón.
	var rings := 8
	for e in edges:
		var inner: Array = e
		for r in rings:
			var k := pow(reach / h, float(r + 1) / rings)
			var base := verts.size()
			var ring := []
			for vi in e:
				var v: Vector3 = verts[vi]
				verts.append(Vector3(v.x * k, 0.0, v.z * k))
			for i in row:
				ring.append(base + i)
			for i in cells:
				var in0: int = inner[i]
				var in1: int = inner[i + 1]
				var out0: int = ring[i]
				var out1: int = ring[i + 1]
				idx.append_array([in0, out0, in1, in1, out0, out1])
			inner = ring
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Reflejos en pantalla del agua: `k` = fracción de los pasos (0 = solo refleja el cielo).
func set_water_quality(k: float) -> void:
	for wm in water_mats:
		(wm[0] as ShaderMaterial).set_shader_parameter("ssr_steps", int(wm[1] * k))
