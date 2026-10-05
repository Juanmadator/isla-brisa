class_name MeshKit
extends RefCounted
## Generación procedural de mallas y materiales cel-shading cacheados.
## Todo el arte 3D del juego sale de aquí: no hay modelos externos.

## Godot considera cara frontal la de orden horario.
const CLOCKWISE_FRONT := true

static var _mat_cache := {}
static var _mesh_cache := {}


## Libera las cachés estáticas antes de cerrar (evita recursos vivos tras apagar el motor).
static func clear_cache() -> void:
	_mat_cache.clear()
	_mesh_cache.clear()
	_toon_shader = null


static var _toon_shader: Shader


## Material del juego (sombreado suave). `_outline` se ignora: el arte ya no lleva contornos
## negros; el parámetro sigue ahí para no cambiar todas las llamadas.
static func mat(color: Color, _outline := 0.02, emission := 0.0, emission_color := Color(0, 0, 0, 0), rim := 0.22) -> ShaderMaterial:
	var key := "%s|%.2f|%s|%.2f" % [color.to_html(), emission, emission_color.to_html(), rim]
	if _mat_cache.has(key):
		return _mat_cache[key]
	if _toon_shader == null:
		_toon_shader = load("res://shaders/toon.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _toon_shader
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rim_amount", rim)
	if emission > 0.0:
		m.set_shader_parameter("emission_color", emission_color if emission_color.a > 0.0 else color)
		m.set_shader_parameter("emission_energy", emission)
	_mat_cache[key] = m
	return m


## Igual que `mat` pero usa el color de los vértices (mallas con varios colores).
static func vcol_mat(_outline := 0.02, rim := 0.22) -> ShaderMaterial:
	var key := "vcol|%.2f" % rim
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: ShaderMaterial = mat(Color.WHITE, 0.0, 0.0, Color(0, 0, 0, 0), rim).duplicate()
	m.set_shader_parameter("use_vertex_color", true)
	_mat_cache[key] = m
	return m


## Material sin contorno que de noche se vuelve luz cálida (ventanas).
static func night_glow_mat(color: Color, energy: float) -> ShaderMaterial:
	var key := "night|%s|%.2f" % [color.to_html(), energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: ShaderMaterial = mat(color, 0.0, 0.0, Color(0, 0, 0, 0), 0.0).duplicate()
	m.set_shader_parameter("night_emission", energy)
	_mat_cache[key] = m
	return m


static func unshaded(color: Color, energy := 1.0) -> StandardMaterial3D:
	var key := "unshaded|%s|%.2f" % [color.to_html(), energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	if color.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.disable_receive_shadows = true
	_mat_cache[key] = m
	return m


# --- Ayudantes de triángulos -------------------------------------------------

static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var face := (b - a).cross(c - a)
	var want := na + nb + nc
	var is_ccw := face.dot(want) > 0.0
	if is_ccw == CLOCKWISE_FRONT:
		var tmp := b
		b = c
		c = tmp
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


# --- Caja redondeada ---------------------------------------------------------

static func _axis_samples(half: float, r: float, segs: int) -> PackedFloat32Array:
	var inner := maxf(half - r, 0.0)
	var out := PackedFloat32Array()
	for i in range(segs, 0, -1):
		out.append(-inner - r * sin(PI * 0.5 * float(i) / segs))
	out.append(-inner)
	if inner > 0.0001:
		out.append(inner)
	for i in range(1, segs + 1):
		out.append(inner + r * sin(PI * 0.5 * float(i) / segs))
	return out


static func rounded_box(size: Vector3, radius := 0.08, segs := 3) -> ArrayMesh:
	var key := "rbox|%s|%.3f|%d" % [size, radius, segs]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var half := size * 0.5
	var r := minf(radius, minf(half.x, minf(half.y, half.z)))
	var inner := Vector3(half.x - r, half.y - r, half.z - r)
	var samples := [_axis_samples(half.x, r, segs), _axis_samples(half.y, r, segs), _axis_samples(half.z, r, segs)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sgn: float in [-1.0, 1.0]:
			var su: PackedFloat32Array = samples[u]
			var sv: PackedFloat32Array = samples[v]
			var grid := []
			for i in su.size():
				var row := []
				for j in sv.size():
					var p := Vector3.ZERO
					p[axis] = sgn * half[axis]
					p[u] = su[i]
					p[v] = sv[j]
					var q := p.clamp(-inner, inner)
					var n := (p - q).normalized()
					if n == Vector3.ZERO:
						n = Vector3.ZERO
						n[axis] = sgn
					row.append([q + n * r, n])
				grid.append(row)
			for i in su.size() - 1:
				for j in sv.size() - 1:
					var a: Array = grid[i][j]
					var b: Array = grid[i + 1][j]
					var c: Array = grid[i + 1][j + 1]
					var d: Array = grid[i][j + 1]
					if (a[0] as Vector3).distance_squared_to(c[0]) < 1e-10:
						continue
					_add_tri(st, a[0], b[0], c[0], a[1], b[1], c[1])
					_add_tri(st, a[0], c[0], d[0], a[1], c[1], d[1])
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


# --- Superficies paramétricas -----------------------------------------------

## f(u, v) -> Vector3 con u, v en [0, 1]. Las normales se calculan por diferencias finitas
## y se orientan hacia fuera respecto a `center` (sirve para formas convexas o casi).
static func param_surface(f: Callable, nu: int, nv: int, center := Vector3.ZERO, closed_v := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	var nrm := []
	var e := 0.001
	for i in nu + 1:
		var prow := []
		var nrow := []
		var u := float(i) / nu
		for j in nv + 1:
			var v := float(j) / nv
			if closed_v and j == nv:
				v = 0.0
			var p: Vector3 = f.call(u, v)
			var pu: Vector3 = f.call(clampf(u + e, 0.0, 1.0), v) - f.call(clampf(u - e, 0.0, 1.0), v)
			var pv: Vector3 = f.call(u, v + e) - f.call(u, v - e)
			var n := pu.cross(pv)
			if n.length_squared() < 1e-14:
				n = p - center
			n = n.normalized()
			if n.dot(p - center) < 0.0:
				n = -n
			prow.append(p)
			nrow.append(n)
		pts.append(prow)
		nrm.append(nrow)
	for i in nu:
		for j in nv:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			if (b - a).cross(c - a).length_squared() > 1e-16:
				_add_tri(st, a, b, c, nrm[i][j], nrm[i + 1][j], nrm[i + 1][j + 1])
			if (c - a).cross(d - a).length_squared() > 1e-16:
				_add_tri(st, a, c, d, nrm[i][j], nrm[i + 1][j + 1], nrm[i][j + 1])
	return st.commit()


static func blob(radius: float, squash := 1.0, noise_amount := 0.0, seed_value := 0, segs := 18) -> ArrayMesh:
	var key := "blob|%.3f|%.3f|%.3f|%d|%d" % [radius, squash, noise_amount, seed_value, segs]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var s := float(seed_value) * 1.7
	var f := func(u: float, v: float) -> Vector3:
		var th := u * PI
		var ph := v * TAU
		var dir := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		var nz := 1.0 + noise_amount * (sin(dir.x * 3.1 + s) * sin(dir.y * 2.7 + s * 0.5) + 0.6 * sin(dir.z * 4.3 + s * 1.3))
		return Vector3(dir.x * radius * nz, dir.y * radius * squash * nz, dir.z * radius * nz)
	var mesh := param_surface(f, segs, segs * 2)
	_mesh_cache[key] = mesh
	return mesh


static func pumpkin(radius: float, ribs := 8, squash := 0.78) -> ArrayMesh:
	var key := "pumpkin|%.3f|%d|%.3f" % [radius, ribs, squash]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var f := func(u: float, v: float) -> Vector3:
		var th := u * PI
		var ph := v * TAU
		var rib := 1.0 - 0.10 * (0.5 - 0.5 * cos(ph * ribs))
		var r := radius * rib
		var y := cos(th) * radius * squash
		y -= radius * 0.18 * exp(-pow(th / 0.45, 2.0))
		y += radius * 0.12 * exp(-pow((PI - th) / 0.45, 2.0))
		return Vector3(sin(th) * cos(ph) * r, y, sin(th) * sin(ph) * r)
	var mesh := param_surface(f, 16, ribs * 6)
	_mesh_cache[key] = mesh
	return mesh


## Superficie de revolución. `profile` son puntos (radio, altura) desde el eje inferior
## hacia fuera, subiendo por el exterior y bajando por el interior si lo hay.
static func lathe(profile: PackedVector2Array, segs := 24) -> ArrayMesh:
	var key := "lathe|%s|%d" % [profile, segs]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_prof := profile.size()
	# Normal 2D de cada segmento del perfil (hacia "fuera" del recorrido).
	var seg_n := []
	for i in n_prof - 1:
		var t := (profile[i + 1] - profile[i]).normalized()
		seg_n.append(Vector2(t.y, -t.x))
	for i in n_prof - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		var n2: Vector2 = seg_n[i]
		for j in segs:
			var a0 := TAU * j / segs
			var a1 := TAU * (j + 1) / segs
			var v00 := Vector3(p0.x * cos(a0), p0.y, p0.x * sin(a0))
			var v01 := Vector3(p0.x * cos(a1), p0.y, p0.x * sin(a1))
			var v10 := Vector3(p1.x * cos(a0), p1.y, p1.x * sin(a0))
			var v11 := Vector3(p1.x * cos(a1), p1.y, p1.x * sin(a1))
			var n0 := Vector3(n2.x * cos(a0), n2.y, n2.x * sin(a0)).normalized()
			var n1 := Vector3(n2.x * cos(a1), n2.y, n2.x * sin(a1)).normalized()
			if v00.distance_squared_to(v01) > 1e-12:
				_add_tri(st, v00, v10, v11, n0, n0, n1)
				_add_tri(st, v00, v11, v01, n0, n1, n1)
			else:
				_add_tri(st, v00, v10, v11, n0, n0, n1)
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


## Prisma extruido a partir de un polígono en XZ, con caras planas.
static func extrude(polygon: PackedVector2Array, height: float) -> ArrayMesh:
	var key := "extrude|%s|%.3f" % [polygon, height]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(polygon)
	for k in range(0, tris.size(), 3):
		var a := polygon[tris[k]]
		var b := polygon[tris[k + 1]]
		var c := polygon[tris[k + 2]]
		_add_tri(st, Vector3(a.x, height, a.y), Vector3(b.x, height, b.y), Vector3(c.x, height, c.y), Vector3.UP, Vector3.UP, Vector3.UP)
		_add_tri(st, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(c.x, 0, c.y), Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
	var centroid := Vector2.ZERO
	for p in polygon:
		centroid += p
	centroid /= polygon.size()
	for i in polygon.size():
		var p0 := polygon[i]
		var p1 := polygon[(i + 1) % polygon.size()]
		var edge := p1 - p0
		var n2 := Vector2(edge.y, -edge.x).normalized()
		if n2.dot((p0 + p1) * 0.5 - centroid) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, 0, n2.y)
		var a := Vector3(p0.x, 0, p0.y)
		var b := Vector3(p1.x, 0, p1.y)
		var c := Vector3(p1.x, height, p1.y)
		var d := Vector3(p0.x, height, p0.y)
		_add_tri(st, a, b, c, n, n, n)
		_add_tri(st, a, c, d, n, n, n)
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


# --- Primitivas cacheadas ----------------------------------------------------

static func sphere(radius: float, segs := 16) -> SphereMesh:
	var key := "sphere|%.3f|%d" % [radius, segs]
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segs * 2
		m.rings = segs
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func cylinder(top: float, bottom: float, height: float, segs := 16) -> CylinderMesh:
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [top, bottom, height, segs]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = segs
		m.rings = 1
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var key := "capsule|%.3f|%.3f" % [radius, height]
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = 24
		m.rings = 8
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "torus|%.3f|%.3f" % [inner, outer]
	if not _mesh_cache.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 24
		m.ring_segments = 10
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func cone(radius: float, height: float, segs := 16) -> CylinderMesh:
	return cylinder(0.0, radius, height, segs)


static func quad(size: Vector2) -> PlaneMesh:
	var key := "quad|%s" % size
	if not _mesh_cache.has(key):
		var m := PlaneMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


# --- Instanciado -------------------------------------------------------------

static func part(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, scl := Vector3.ONE, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
