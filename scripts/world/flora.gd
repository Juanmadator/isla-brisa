class_name Flora
extends Node3D
## Árboles, pinos, arbustos y rocas (MultiMesh con colisión) y hierba/flores por trozos
## que se generan alrededor del foco (el jugador o la cámara).

const GRASS_CHUNK := 24.0
const GRASS_RADIUS := 3
const GRASS_SPACING := 0.85

var island: Island
var focus := Vector3.ZERO
var clear_zones: Array = []   # Vector3(x, z, radio)
var tree_points: Array[Vector3] = []

var _grass_mesh: ArrayMesh
var _flower_mesh: Mesh
var _grass_mat: ShaderMaterial
var _flower_mat: ShaderMaterial
var _grass_chunks := {}
var _grass_parent: Node3D


func build(isl: Island, zones: Array) -> void:
	island = isl
	clear_zones = zones
	_grass_parent = Node3D.new()
	_grass_parent.name = "Grass"
	add_child(_grass_parent)
	_grass_mesh = _make_grass_mesh()
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = load("res://shaders/grass.gdshader")
	_grass_mat.set_shader_parameter("rim_amount", 0.0)
	_grass_mat.set_shader_parameter("band_soft", 0.12)
	_flower_mesh = MeshKit.blob(0.09, 0.8, 0.0, 0, 6)
	_flower_mat = MeshKit.mat(Color.WHITE, 0.0, 0.25, Color(1, 1, 1, 0), 0.0).duplicate()
	_flower_mat.set_shader_parameter("use_instance_tint", true)
	_scatter_trees()
	_scatter_rocks()
	_scatter_lake_plants()


func _is_clear(p: Vector2, extra := 0.0) -> bool:
	for z in clear_zones:
		if p.distance_to(Vector2(z.x, z.y)) < z.z + extra:
			return false
	return true


# --- Árboles y rocas -------------------------------------------------------------

static func _combine(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		st.append_from(part[0], 0, part[1])
	return st.commit()


## Bultos que forman una copa de árbol: [centro, radio, achatado].
static func _canopy_lobes(variant: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 300 + variant
	var lobes := [[Vector3(0, 5.6, 0), 2.4, 0.82]]
	for i in 4:
		var a := TAU * i / 4.0 + r.randf() * 0.8
		lobes.append([Vector3(cos(a) * 1.7, r.randf_range(4.3, 5.4), sin(a) * 1.7), r.randf_range(1.3, 1.8), 0.85])
	lobes.append([Vector3(0.3, 7.2, -0.2), 1.5, 0.9])
	return lobes


static func broadleaf_canopy(variant: int) -> ArrayMesh:
	var parts := []
	var lobes := _canopy_lobes(variant)
	for i in lobes.size():
		var l: Array = lobes[i]
		parts.append([MeshKit.blob(l[1], l[2], 0.12, variant + i, 11), Transform3D(Basis(), l[0])])
	return _combine(parts)


## Copa frondosa: núcleo oscuro (los mismos bultos, más pequeños) y tarjetas de hojas por
## encima. Dos superficies: 0 = núcleo, 1 = hojas.
static func leafy_mesh(lobes: Array, card: float, per_m2: float, seed_value: int) -> ArrayMesh:
	var core := []
	for i in lobes.size():
		var l: Array = lobes[i]
		core.append([MeshKit.blob(l[1] * 0.7, l[2], 0.12, seed_value + i, 9), Transform3D(Basis(), l[0])])
	var mesh := _combine(core)
	var r := RandomNumberGenerator.new()
	r.seed = 900 + seed_value
	var center := Vector3.ZERO
	var outer := 0.0
	for l in lobes:
		center += l[0]
	center /= lobes.size()
	for l in lobes:
		outer = maxf(outer, (l[0] as Vector3).distance_to(center) + float(l[1]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for l in lobes:
		var c: Vector3 = l[0]
		var rad: float = l[1]
		var count := maxi(6, int(4.0 * PI * rad * rad * per_m2))
		for k in count:
			# Puntos repartidos por la esfera (espiral de Fibonacci) con algo de azar.
			var y := 1.0 - 2.0 * (k + 0.5) / count
			var ring := sqrt(maxf(1.0 - y * y, 0.0))
			var phi := k * 2.39996 + r.randf() * 0.4
			var dir := Vector3(cos(phi) * ring, y * float(l[2]), sin(phi) * ring)
			var pos := c + dir * rad * r.randf_range(0.72, 1.02)
			var from_center := pos - center
			var nrm := (from_center.normalized() * 0.6 + dir.normalized() * 0.4).normalized()
			var depth := clampf(from_center.length() / outer * 1.1 + nrm.y * 0.15, 0.25, 1.0)
			_add_card(st, n, pos, nrm, depth, card * r.randf_range(0.85, 1.15), r.randf())
			n += 4
	st.commit(mesh)
	return mesh


## Una tarjeta de hojas: cuatro vértices en el mismo punto (el shader la abre hacia la
## cámara). COLOR.r = tamaño, UV2 = (semilla, profundidad en la copa).
static func _add_card(st: SurfaceTool, n: int, pos: Vector3, nrm: Vector3, depth: float, size: float, seed_f: float) -> void:
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		st.set_color(Color(size, 0, 0))
		st.set_normal(nrm)
		st.set_uv(corner)
		st.set_uv2(Vector2(seed_f, depth))
		st.add_vertex(pos)
	for k in [0, 1, 2, 0, 2, 3]:
		st.add_index(n + k)


## Pino frondoso: los conos de siempre (más pequeños y oscuros) cubiertos de tarjetas de
## agujas por cada piso.
static func pine_leafy_mesh() -> ArrayMesh:
	var core := []
	var layers := [[2.3, 1.6, 2.6], [1.8, 3.2, 2.3], [1.25, 4.7, 2.0], [0.7, 6.0, 1.5]]
	for l in layers:
		var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(l[0] * 0.82, 0.15), Vector2(0.0, l[2] * 0.92)])
		core.append([MeshKit.lathe(prof, 8), Transform3D(Basis(), Vector3(0, l[1], 0))])
	var mesh := _combine(core)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for li in layers.size():
		var l: Array = layers[li]
		var rad: float = l[0]
		var h: float = l[2]
		var count := int(18 + rad * 16)
		for k in count:
			var a := k * 2.39996 + r.randf() * 0.5
			var t := sqrt(r.randf())
			var ring := rad * t * r.randf_range(0.85, 1.05)
			var y: float = float(l[1]) + 0.15 + h * (1.0 - t) * 0.85
			var pos := Vector3(cos(a) * ring, y, sin(a) * ring)
			var nrm := Vector3(cos(a), 0.9, sin(a)).normalized()
			var depth := clampf(0.45 + t * 0.4 + float(li) * 0.08, 0.3, 1.0)
			_add_card(st, n, pos, nrm, depth, r.randf_range(0.5, 0.72), r.randf())
			n += 4
	st.commit(mesh)
	return mesh


## Tronco algo curvado con raíces que asoman en la base y tres ramas que se abren hacia la copa.
static func trunk_mesh(height: float, radius: float) -> ArrayMesh:
	var f := func(u: float, v: float) -> Vector3:
		var y := u * height
		var ang := v * TAU
		var r := radius * lerpf(1.0, 0.72, u)
		# Raíces: cuatro contrafuertes que ensanchan la base.
		var root_k := pow(1.0 - clampf(u / 0.18, 0.0, 1.0), 2.0)
		r *= 1.0 + root_k * (0.55 + 0.45 * pow(absf(cos(ang * 2.0)), 3.0))
		r *= 1.0 + sin(ang * 5.0 + u * 7.0) * 0.04
		var bend := Vector3(sin(u * 2.2) * radius * 0.6, 0, cos(u * 1.7) * radius * 0.3 - radius * 0.3)
		return Vector3(cos(ang) * r, y, sin(ang) * r) + bend
	var parts := [[MeshKit.param_surface(f, 12, 14, Vector3(0, height * 0.5, 0), true), Transform3D()]]
	var r := RandomNumberGenerator.new()
	r.seed = int(height * 10.0)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var len := height * r.randf_range(0.32, 0.45)
		var base_y := height * r.randf_range(0.62, 0.82)
		var tilt := Basis(Vector3(-sin(a), 0, cos(a)), deg_to_rad(r.randf_range(38.0, 55.0)))
		var origin := Vector3(sin(2.2 * base_y / height) * radius * 0.6, base_y, 0)
		parts.append([MeshKit.cylinder(radius * 0.22, radius * 0.45, len, 8), Transform3D(tilt, origin + tilt * Vector3(0, len * 0.5, 0))])
	return _combine(parts)


## Tronco de palmera curvado (anillos superpuestos).
static func palm_trunk_mesh() -> ArrayMesh:
	var parts := []
	for i in 9:
		var t := i / 8.0
		var pos := Vector3(t * t * 1.6, t * 6.0, 0)
		var r := lerpf(0.3, 0.18, t)
		parts.append([MeshKit.cylinder(r * 0.85, r, 0.75, 8), Transform3D(Basis(Vector3.BACK, -t * 0.45), pos)])
	return _combine(parts)


static func palm_fronds_mesh() -> ArrayMesh:
	var parts := []
	var top := Vector3(1.6, 6.1, 0)
	for i in 7:
		var a := TAU * i / 7.0
		var leaf := MeshKit.blob(1.0, 0.12, 0.0, i, 8)
		var basis := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.35) * Basis().scaled(Vector3(0.45, 1.0, 1.9))
		parts.append([leaf, Transform3D(basis, top + Basis(Vector3.UP, a) * Vector3(0, -0.35, -1.3))])
	parts.append([MeshKit.sphere(0.35, 8), Transform3D(Basis(), top)])
	return _combine(parts)


static func pine_mesh() -> ArrayMesh:
	var parts := []
	var layers := [[2.3, 1.6, 2.6], [1.8, 3.2, 2.3], [1.25, 4.7, 2.0], [0.7, 6.0, 1.5]]
	for l in layers:
		var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(l[0], 0.15), Vector2(l[0] * 0.92, 0.35), Vector2(0.0, l[2])])
		parts.append([MeshKit.lathe(prof, 9), Transform3D(Basis(), Vector3(0, l[1], 0))])
	return _combine(parts)


## `material` null = usa los materiales de cada superficie de la malla.
func _multimesh(mesh: Mesh, material: Material, xforms: Array, tints: Array, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, tints[i] if i < tints.size() else Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if material:
		mmi.material_override = material
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


static func _tinted(color: Color, sway: float, surface := "") -> ShaderMaterial:
	var m: ShaderMaterial = MeshKit.surface_mat(color, surface).duplicate()
	m.set_shader_parameter("use_instance_tint", true)
	m.set_shader_parameter("sway", sway)
	return m


## Materiales de una copa frondosa: [núcleo, hojas].
static func leafy_materials(sway: float, needles := false) -> Array:
	var core := _tinted(Color(0.5, 0.54, 0.48), sway)
	core.set_shader_parameter("detail", 0.0)
	core.set_shader_parameter("rim_amount", 0.0)
	var leaves := ShaderMaterial.new()
	leaves.shader = load("res://shaders/foliage.gdshader")
	leaves.set_shader_parameter("sway", sway)
	leaves.set_shader_parameter("translucency", 0.35)
	leaves.set_shader_parameter("rim_amount", 0.12)
	leaves.set_shader_parameter("softness", 0.85)
	leaves.set_shader_parameter("shadow_lift", 0.45)
	if needles:
		leaves.set_shader_parameter("albedo", Color(0.72, 0.84, 0.6))
		leaves.set_shader_parameter("translucency", 0.18)
		leaves.set_shader_parameter("leaf_shape", Vector2(0.1, 0.5))
		leaves.set_shader_parameter("leaf_count", 9.0)
	return [core, leaves]


## Mata de hojas para una malla suelta (no MultiMesh): el color va en el material.
static func leafy_clump(radius: float, flat: float, color: Color, seed_value: int) -> ArrayMesh:
	var lobes := [[Vector3.ZERO, radius, flat]]
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	for k in 3:
		var a := TAU * k / 3.0 + r.randf()
		lobes.append([Vector3(cos(a) * radius * 0.55, -radius * flat * 0.2, sin(a) * radius * 0.55), radius * 0.6, flat])
	var mesh := leafy_mesh(lobes, clampf(radius * 0.45, 0.25, 0.6), 4.0 / maxf(radius, 0.5), seed_value)
	var mats := leafy_materials(0.2)
	for m: ShaderMaterial in mats:
		m.set_shader_parameter("use_instance_tint", false)
		m.set_shader_parameter("albedo", color if m.shader.resource_path.ends_with("foliage.gdshader") else color.darkened(0.35))
	mesh.surface_set_material(0, mats[0])
	mesh.surface_set_material(1, mats[1])
	return mesh


static func _leafy(mesh: ArrayMesh, sway: float, needles := false) -> ArrayMesh:
	var mats := leafy_materials(sway, needles)
	mesh.surface_set_material(0, mats[0])
	mesh.surface_set_material(1, mats[1])
	return mesh


func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var canopies := []
	for v in 3:
		canopies.append(_leafy(leafy_mesh(_canopy_lobes(v), 0.95, 1.35, v), 1.0))
	var canopy_x := [[], [], []]
	var canopy_t := [[], [], []]
	var trunk_x := []
	var pine_x := []
	var pine_t := []
	var pine_trunk_x := []
	var bush_x := []
	var bush_t := []
	var palm_x := []
	var palm_t := []
	var body := StaticBody3D.new()
	body.name = "Trees"
	add_child(body)
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.5
	trunk_shape.height = 6.0
	var cell := 7.0
	var x := -Island.HALF
	while x < Island.HALF:
		var z := -Island.HALF
		while z < Island.HALF:
			var p := Vector2(x + rng.randf_range(0.5, cell - 0.5), z + rng.randf_range(0.5, cell - 0.5))
			var roll := rng.randf()
			var b := island.biome_at(p.x, p.y)
			var h := island.height_at(p.x, p.y)
			var ny := island.normal_at(p.x, p.y).y
			z += cell
			if ny < 0.82 or h < 1.5 or not _is_clear(p):
				continue
			if island.path_distance(p) < 4.0:
				continue
			var kind := ""
			if h > 50.0 and h < 88.0 and b != Island.Biome.MEADOW:
				if roll < 0.22:
					kind = "pine"
			elif b == Island.Biome.FOREST:
				if roll < 0.62:
					kind = "pine" if rng.randf() < 0.18 else "tree"
				elif roll < 0.72:
					kind = "bush"
			elif b == Island.Biome.GRASS:
				if roll < 0.045:
					kind = "blossom" if p.distance_to(Island.VILLAGE) < 150.0 and rng.randf() < 0.45 else "tree"
				elif roll < 0.08:
					kind = "bush"
			elif b == Island.Biome.SAND:
				if roll < 0.14 and island.normal_at(p.x, p.y).y > 0.88:
					kind = "palm"
			elif b == Island.Biome.MEADOW:
				if roll < 0.02:
					kind = "bush"
			if kind == "":
				continue
			var s := rng.randf_range(0.8, 1.25)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			var pos := Vector3(p.x, h - 0.2, p.y)
			var xf := Transform3D(basis, pos)
			var green := Color.from_hsv(rng.randf_range(0.24, 0.32), rng.randf_range(0.55, 0.7), rng.randf_range(0.62, 0.8))
			match kind:
				"blossom":
					var v2 := rng.randi() % 3
					canopy_x[v2].append(xf)
					canopy_t[v2].append(Color.from_hsv(rng.randf_range(0.9, 0.97), rng.randf_range(0.28, 0.42), rng.randf_range(0.95, 1.0)))
					trunk_x.append(xf)
				"palm":
					palm_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), pos))
					palm_t.append(Color.from_hsv(rng.randf_range(0.25, 0.31), rng.randf_range(0.55, 0.7), rng.randf_range(0.7, 0.85)))
				"tree":
					var v := rng.randi() % 3
					canopy_x[v].append(xf)
					canopy_t[v].append(green)
					trunk_x.append(xf)
				"pine":
					pine_x.append(xf)
					pine_t.append(Color.from_hsv(rng.randf_range(0.36, 0.42), rng.randf_range(0.45, 0.6), rng.randf_range(0.42, 0.55)))
					pine_trunk_x.append(xf)
				"bush":
					bush_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s)), pos + Vector3(0, 0.3, 0)))
					bush_t.append(green.darkened(0.05))
			if kind != "bush":
				tree_points.append(pos)
				var cs := CollisionShape3D.new()
				cs.shape = trunk_shape
				cs.position = pos + Vector3(0, 3.0, 0)
				body.add_child(cs)
		x += cell
	for v in 3:
		_multimesh(canopies[v], null, canopy_x[v], canopy_t[v])
	_multimesh(trunk_mesh(5.0, 0.32), _tinted(Color(0.55, 0.38, 0.26), 0.3, "bark"), trunk_x, [])
	_multimesh(_leafy(pine_leafy_mesh(), 0.6, true), null, pine_x, pine_t)
	_multimesh(trunk_mesh(2.0, 0.22), _tinted(Color(0.5, 0.36, 0.26), 0.0, "bark"), pine_trunk_x, [])
	var bush := _leafy(leafy_mesh([[Vector3(0, 0.1, 0), 1.0, 0.8], [Vector3(0.55, -0.05, 0.2), 0.6, 0.8], [Vector3(-0.45, 0.0, -0.3), 0.65, 0.8]], 0.45, 3.2, 7), 0.4)
	_multimesh(bush, null, bush_x, bush_t)
	if not palm_x.is_empty():
		_multimesh(palm_trunk_mesh(), _tinted(Color(0.72, 0.55, 0.36), 0.5, "bark"), palm_x, [])
		_multimesh(palm_fronds_mesh(), _tinted(Color(1, 1, 1), 1.2), palm_x, palm_t)


func _scatter_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var meshes := []
	var shapes := []
	for v in 4:
		var m := MeshKit.rock(40 + v)
		meshes.append(m)
		shapes.append(m.create_convex_shape(true, true))
	var xf := [[], [], [], []]
	var tints := [[], [], [], []]
	var body := StaticBody3D.new()
	body.name = "Rocks"
	add_child(body)
	var count := 0
	var tries := 0
	while count < 420 and tries < 6000:
		tries += 1
		var p := Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))
		var h := island.height_at(p.x, p.y)
		if h < -1.0 or not _is_clear(p, 2.0) or island.path_distance(p) < 3.0:
			continue
		# Nada de rocas pegadas a las paredes: estorbarían al escalar.
		if island.normal_at(p.x, p.y).y < 0.8:
			continue
		var b := island.biome_at(p.x, p.y)
		var chance := 0.08
		if h > 60.0:
			chance = 0.5
		elif b == Island.Biome.SAND:
			chance = 0.25
		elif b == Island.Biome.MEADOW:
			chance = 0.35
		if rng.randf() > chance:
			continue
		var s := rng.randf_range(0.5, 1.6)
		if rng.randf() < 0.12:
			s = rng.randf_range(2.2, 4.0)
		var v := rng.randi() % 4
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
		var pos := Vector3(p.x, h - 0.15 * s, p.y)
		xf[v].append(Transform3D(basis.scaled(Vector3.ONE * s), pos))
		var g := rng.randf_range(0.6, 0.78)
		tints[v].append(Color(g * 1.02, g * 0.97, g * 0.94))
		var cs := CollisionShape3D.new()
		cs.shape = shapes[v]
		cs.transform = Transform3D(basis, pos)
		cs.scale = Vector3.ONE * s
		body.add_child(cs)
		count += 1
	var rock_mat := _tinted(Color(0.9, 0.86, 0.76), 0.0, "stone")
	for v in 4:
		_multimesh(meshes[v], rock_mat, xf[v], tints[v])


# --- Plantas del lago ---------------------------------------------------------

## Hoja de nenúfar de radio 1: disco de borde ondulado, con la muesca hasta el centro y los
## bordes algo levantados (como una hoja de verdad, no un plato).
static func lily_pad_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 28
	var notch := 0.42
	var c := Vector3(0, 0.0, 0)
	var prev := Vector3.ZERO
	var prev_n := Vector3.UP
	for i in segs + 1:
		var a := notch * 0.5 + (TAU - notch) * float(i) / segs
		var r := 1.0 + sin(a * 7.0) * 0.025
		var p := Vector3(cos(a) * r, 0.05 + sin(a * 3.0 + 1.0) * 0.02, sin(a) * r)
		var n := Vector3(-cos(a) * 0.12, 1.0, -sin(a) * 0.12).normalized()
		if i > 0:
			MeshKit._add_tri(st, c, prev, p, Vector3.UP, prev_n, n)
		prev = p
		prev_n = n
	return MeshKit.double_sided(st.commit())


## Flor de nenúfar: dos coronas de pétalos abiertos en copa y el centro amarillo aparte.
static func lily_flower_meshes() -> Array:
	var petal := MeshKit.blob(1.0, 0.28, 0.0, 0, 12)
	var parts := []
	for ring in 2:
		var n := 8 if ring == 0 else 6
		var tilt := 0.45 if ring == 0 else 0.95
		var size := Vector3(0.05, 0.05, 0.13) if ring == 0 else Vector3(0.045, 0.045, 0.1)
		for k in n:
			var yaw := TAU * k / n + ring * 0.4
			var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt)
			var off := b * Vector3(0, 0, size.z * 0.8)
			parts.append([petal, Transform3D(b.scaled(size), off + Vector3(0, 0.03 + ring * 0.02, 0))])
	var centre := MeshKit.blob(0.045, 0.6, 0.0, 0, 12)
	return [_combine(parts), centre]


## Mata de juncos: hojas finas y largas que se curvan hacia fuera, y alguna enea (tallo
## con la mazorca marrón). Devuelve [hojas, mazorcas].
static func reed_clump_meshes(seed_value: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 11
	for b in blades:
		var yaw := r.randf() * TAU
		var dir := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-dir.z, 0, dir.x)
		var h := r.randf_range(0.9, 1.7)
		var bend := r.randf_range(0.15, 0.45)
		var w := r.randf_range(0.035, 0.06)
		var base := dir * r.randf_range(0.0, 0.18)
		var segs := 5
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in segs + 1:
			var t := float(i) / segs
			var centre := base + dir * bend * t * t + Vector3.UP * h * t
			var half := w * (1.0 - t * 0.92)
			var l := centre - side * half
			var rr := centre + side * half
			var n := (Vector3.UP * -bend * 2.0 * t + dir * h).normalized().lerp(Vector3.UP, 0.3).normalized()
			if i > 0:
				MeshKit._add_tri(st, prev_l, prev_r, rr, n, n, n)
				MeshKit._add_tri(st, prev_l, rr, l, n, n, n)
			prev_l = l
			prev_r = rr
	var leaves := MeshKit.double_sided(st.commit())
	var heads := []
	var stem := MeshKit.cylinder(0.012, 0.016, 1.0, 5)
	var head := MeshKit.capsule(0.035, 0.22)
	for k in r.randi_range(1, 3):
		var yaw := r.randf() * TAU
		var p := Vector3(cos(yaw), 0, sin(yaw)) * r.randf_range(0.0, 0.12)
		var h := r.randf_range(1.4, 1.9)
		heads.append([stem, Transform3D(Basis().scaled(Vector3(1, h, 1)), p + Vector3.UP * h * 0.5)])
		heads.append([head, Transform3D(Basis(), p + Vector3.UP * (h + 0.06))])
	return [leaves, _combine(heads)]


func _scatter_lake_plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	var y := Island.LAKE_LEVEL + 0.09
	# Nenúfares en corros, lejos del islote y del centro (donde más se refleja el cielo).
	var pads := []
	var pad_tints := []
	var flowers := []
	var flower_tints := []
	var corros := 0
	while corros < 16:
		var a := rng.randf() * TAU
		var c := Island.LAKE + Vector2(cos(a), sin(a)) * rng.randf_range(24.0, 50.0)
		if c.distance_to(Island.LAKE_ISLET) < 10.0 or island.height_at(c.x, c.y) > Island.LAKE_LEVEL - 0.6:
			continue
		corros += 1
		for k in rng.randi_range(4, 10):
			var p := c + Vector2(rng.randfn(0.0, 1.4), rng.randfn(0.0, 1.4))
			if island.height_at(p.x, p.y) > Island.LAKE_LEVEL - 0.3 or p.distance_to(Island.LAKE) > 54.0:
				continue
			var s := rng.randf_range(0.32, 0.62)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
			pads.append(Transform3D(basis, Vector3(p.x, y + rng.randf() * 0.01, p.y)))
			var g := rng.randf_range(0.85, 1.1)
			pad_tints.append(Color(0.34 * g, 0.56 * g, 0.24 * g * rng.randf_range(0.9, 1.15)))
			if rng.randf() < 0.18:
				var fp := p + Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15))
				flowers.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(fp.x, y + 0.03, fp.y)))
				flower_tints.append(Color(1.0, 0.93, 0.96) if rng.randf() < 0.6 else Color(1.0, 0.7, 0.82))
	var pad_mat := _tinted(Color(1, 1, 1), 0.0)
	pad_mat.set_shader_parameter("rim_amount", 0.0)
	_multimesh(lily_pad_mesh(), pad_mat, pads, pad_tints, false)
	var fl := lily_flower_meshes()
	_multimesh(fl[0], _tinted(Color(1, 1, 1), 0.0), flowers, flower_tints, false)
	var yellow := []
	for t: Transform3D in flowers:
		yellow.append(t.translated(Vector3(0, 0.05, 0)))
	_multimesh(fl[1], MeshKit.mat(Color(1.0, 0.82, 0.25), 0.0, 0.25, Color(1.0, 0.75, 0.2)), yellow, [], false)
	# Juncos y eneas donde el agua es muy poco profunda o justo en la orilla.
	var reeds := [reed_clump_meshes(1), reed_clump_meshes(2)]
	var rx := [[], []]
	var rt := [[], []]
	var hx := [[], []]
	var tries := 0
	var placed := 0
	while placed < 140 and tries < 4000:
		tries += 1
		var a := rng.randf() * TAU
		var p := Island.LAKE + Vector2(cos(a), sin(a)) * rng.randf_range(26.0, 56.0)
		var h := island.height_at(p.x, p.y)
		if h < Island.LAKE_LEVEL - 0.7 or h > Island.LAKE_LEVEL + 0.5:
			continue
		if not _is_clear(p, 1.0) or island.path_distance(p) < 2.5:
			continue
		# En matas de varias juntas, no repartidos uno a uno.
		var n := rng.randi_range(2, 5)
		for k in n:
			var q := p + Vector2(rng.randfn(0.0, 0.7), rng.randfn(0.0, 0.7))
			var qh := island.height_at(q.x, q.y)
			if qh < Island.LAKE_LEVEL - 0.9 or qh > Island.LAKE_LEVEL + 0.7:
				continue
			var v := rng.randi() % 2
			var s := rng.randf_range(0.75, 1.2)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s)), Vector3(q.x, qh - 0.05, q.y))
			rx[v].append(xf)
			var g := rng.randf_range(0.85, 1.1)
			rt[v].append(Color(0.45 * g, 0.62 * g, 0.3 * g))
			if rng.randf() < 0.5:
				hx[v].append(xf)
			placed += 1
	var reed_mat := _tinted(Color(1, 1, 1), 3.0)
	reed_mat.set_shader_parameter("rim_amount", 0.0)
	var head_mat := _tinted(Color(0.42, 0.27, 0.16), 3.0)
	for v in 2:
		_multimesh(reeds[v][0], reed_mat, rx[v], rt[v], true)
		var ht := []
		for _i in hx[v].size():
			ht.append(Color(1, 1, 1))
		_multimesh(reeds[v][1], head_mat, hx[v], ht, true)


# --- Hierba por trozos ---------------------------------------------------------

func _make_grass_mesh() -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	for b in 7:
		var a := r.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.3)
		var h := r.randf_range(0.45, 0.85)
		var w := r.randf_range(0.07, 0.11)
		var face := r.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face)) * w
		var lean := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.05, 0.22)
		var mid := base + lean * 0.4 + Vector3(0, h * 0.55, 0)
		var top := base + lean + Vector3(0, h, 0)
		var p0 := base - side
		var p1 := base + side
		var p2 := mid - side * 0.6
		var p3 := mid + side * 0.6
		for tri in [[p0, p1, p3, 0.0, 0.0, 0.55], [p0, p3, p2, 0.0, 0.55, 0.55], [p2, p3, top, 0.55, 0.55, 1.0]]:
			verts.append_array([tri[0], tri[1], tri[2]])
			uvs.append_array([Vector2(0, tri[3]), Vector2(1, tri[4]), Vector2(0.5, tri[5])])
			norms.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _process(_delta: float) -> void:
	if _grass_parent == null:
		return
	var cx := int(floor(focus.x / GRASS_CHUNK))
	var cz := int(floor(focus.z / GRASS_CHUNK))
	var built := 0
	for ring in GRASS_RADIUS + 1:
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var key := Vector2i(cx + dx, cz + dz)
				if not _grass_chunks.has(key):
					_grass_chunks[key] = _build_grass_chunk(key)
					built += 1
					if built >= 2:
						return
	for key in _grass_chunks.keys():
		if maxi(absi(key.x - cx), absi(key.y - cz)) > GRASS_RADIUS + 1:
			var n: Node = _grass_chunks[key]
			if n:
				n.queue_free()
			_grass_chunks.erase(key)


## Construye toda la hierba alrededor del foco de golpe (al cargar o teletransportar).
func warm_up() -> void:
	for i in 200:
		var before := _grass_chunks.size()
		_process(0.0)
		if _grass_chunks.size() == before:
			break


func _build_grass_chunk(key: Vector2i) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var ox := key.x * GRASS_CHUNK
	var oz := key.y * GRASS_CHUNK
	if absf(ox) > Island.HALF or absf(oz) > Island.HALF:
		return null
	var xf := []
	var tints := []
	var fx := []
	var ft := []
	var flower_cols := [Color(1, 1, 1), Color(1, 0.86, 0.3), Color(1, 0.6, 0.75), Color(0.75, 0.68, 1.0)]
	var steps := int(GRASS_CHUNK / GRASS_SPACING)
	for iz in steps:
		for ix in steps:
			var p := Vector2(ox + (ix + rng.randf()) * GRASS_SPACING, oz + (iz + rng.randf()) * GRASS_SPACING)
			var b := island.biome_at(p.x, p.y)
			var density := 0.0
			match b:
				Island.Biome.GRASS:
					density = 0.9
				Island.Biome.MEADOW:
					density = 0.95
				Island.Biome.FOREST:
					density = 0.45
				Island.Biome.PATH:
					density = 0.05
			if rng.randf() > density:
				continue
			var n := island.normal_at(p.x, p.y)
			if n.y < 0.78:
				continue
			var h := island.height_at(p.x, p.y)
			if h < island.water_level(p.x, p.y) + 0.4:
				continue
			var s := rng.randf_range(0.6, 1.05)
			if b == Island.Biome.MEADOW:
				s *= 1.3
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s))
			var col := island.color_at(p.x, p.y)
			col = Color(col.r, col.g, col.b).lerp(Color(0.75, 0.85, 0.35), rng.randf() * 0.12)
			xf.append(Transform3D(basis, Vector3(p.x, h - 0.05, p.y)))
			tints.append(col)
			if (b == Island.Biome.GRASS or b == Island.Biome.MEADOW) and rng.randf() < 0.035:
				fx.append(Transform3D(Basis(), Vector3(p.x + 0.2, h + 0.38 * s, p.y)))
				ft.append(flower_cols[rng.randi() % flower_cols.size()])
	var holder := Node3D.new()
	_grass_parent.add_child(holder)
	if xf.size() > 0:
		var g := _make_mm(_grass_mesh, _grass_mat, xf, tints)
		g.visibility_range_end = GRASS_CHUNK * GRASS_RADIUS
		g.visibility_range_end_margin = 8.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(g)
	if fx.size() > 0:
		var f := _make_mm(_flower_mesh, _flower_mat, fx, ft)
		f.visibility_range_end = GRASS_CHUNK * GRASS_RADIUS
		holder.add_child(f)
	return holder


func _make_mm(mesh: Mesh, material: Material, xforms: Array, tints: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
