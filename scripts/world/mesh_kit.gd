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


const SURFACES := {"wood": 1, "stone": 2, "plaster": 3, "tile": 4, "bark": 5, "thatch": 6}


## Material con el dibujo y el relieve de un material ("wood", "stone", "plaster", "tile",
## "bark") y los cantos aclarados. Sin `surface`, es el material normal.
static func surface_mat(color: Color, surface: String, edge := 0.12, scale := 1.0) -> ShaderMaterial:
	if surface == "" or not SURFACES.has(surface):
		return mat(color)
	var key := "surf|%s|%s|%.2f|%.2f" % [color.to_html(), surface, edge, scale]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: ShaderMaterial = mat(color).duplicate()
	m.set_shader_parameter("surface", SURFACES[surface])
	m.set_shader_parameter("edge_highlight", edge)
	m.set_shader_parameter("surface_scale", scale)
	m.set_shader_parameter("detail", 0.035)
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
	# Bisel generoso y proporcional al tamaño: los cantos finos e iguales parecen de baja
	# poligonización; los redondeados recogen la luz y parecen hechos a mano.
	var min_dim := minf(size.x, minf(size.y, size.z))
	radius = maxf(radius, minf(min_dim * 0.16, 0.14))
	segs = maxi(segs, 3)
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


## Caja "hecha a mano": caja redondeada subdividida cuyas caras se abomban un poco con ruido
## (`wobble` en metros) y que se estrecha arriba (`taper`). Las líneas dejan de ser de regla.
static func soft_box(size: Vector3, radius := 0.1, wobble := 0.025, taper := 0.02, seed_value := 0) -> ArrayMesh:
	var key := "sbox|%s|%.3f|%.3f|%.3f|%d" % [size, radius, wobble, taper, seed_value]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var half := size * 0.5
	var r := minf(maxf(radius, minf(minf(size.x, minf(size.y, size.z)) * 0.16, 0.14)), minf(half.x, minf(half.y, half.z)))
	var inner := Vector3(half.x - r, half.y - r, half.z - r)
	var samples := []
	for ax in 3:
		var base := _axis_samples(half[ax], r, 3)
		# Más cortes en las caras planas para que se puedan abombar.
		var dense := PackedFloat32Array()
		for i in base.size():
			dense.append(base[i])
			if i + 1 < base.size():
				var gap: float = base[i + 1] - base[i]
				var n := int(gap / 0.45)
				for k in range(1, n):
					dense.append(base[i] + gap * k / n)
		samples.append(dense)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.35
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shape := func(p: Vector3) -> Vector3:
		var q := p.clamp(-inner, inner)
		var nrm := (p - q).normalized()
		var out := q + nrm * r
		# Abombado suave (más en el centro de las caras que en los cantos) y estrechamiento.
		out += nrm * noise.get_noise_3dv(out * 1.0) * wobble
		var k := 1.0 - taper * clampf((out.y + half.y) / maxf(size.y, 0.001), 0.0, 1.0)
		out.x *= k
		out.z *= k
		return out
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sgn: float in [-1.0, 1.0]:
			var su: PackedFloat32Array = samples[u]
			var sv: PackedFloat32Array = samples[v]
			for i in su.size() - 1:
				for j in sv.size() - 1:
					var corners := []
					for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
						var p := Vector3.ZERO
						p[axis] = sgn * half[axis]
						p[u] = su[c[0]]
						p[v] = sv[c[1]]
						corners.append(shape.call(p))
					var face: Vector3 = ((corners[1] as Vector3) - corners[0]).cross((corners[2] as Vector3) - corners[0])
					var want := Vector3.ZERO
					want[axis] = sgn
					if face.length_squared() < 1e-12:
						continue
					# Sin normales propias: al indexar se unen los vértices de caras vecinas y
					# generate_normals() suaviza todo el contorno sin costuras.
					for tri in [[corners[0], corners[1], corners[2]], [corners[0], corners[2], corners[3]]]:
						var ta: Vector3 = tri[0]
						var tb: Vector3 = tri[1]
						var tc: Vector3 = tri[2]
						if ((tb - ta).cross(tc - ta).dot(want) > 0.0) == CLOCKWISE_FRONT:
							var tmp := tb
							tb = tc
							tc = tmp
						st.add_vertex(ta)
						st.add_vertex(tb)
						st.add_vertex(tc)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


## Copia de la malla con cada triángulo también por detrás (normal invertida): para
## superficies abiertas que se ven por las dos caras (casco de una barca, velas, telas).
static func double_sided(mesh: ArrayMesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := idx.size() if idx.size() > 0 else verts.size()
	for t in range(0, count, 3):
		var ids := [idx[t], idx[t + 1], idx[t + 2]] if idx.size() > 0 else [t, t + 1, t + 2]
		for k in [0, 1, 2]:
			st.set_normal(norms[ids[k]])
			st.add_vertex(verts[ids[k]])
		for k in [0, 2, 1]:
			st.set_normal(-norms[ids[k]])
			st.add_vertex(verts[ids[k]])
	return st.commit()


## Casco de barca de dos proas (como un llaüt): fino en los extremos, con la quilla que sube
## hacia proa y popa y la borda arqueada. `v` de 0 a 1 recorre de una borda a la otra.
## Abierto por arriba y de dos caras. Con `band` = [v0, v1] devuelve solo esa franja,
## separada `lift` hacia fuera (para la franja pintada de la borda).
static func hull(length: float, width: float, depth: float, band := Vector2(0.0, 1.0), lift := 0.0) -> ArrayMesh:
	var key := "hull|%.2f|%.2f|%.2f|%s|%.3f" % [length, width, depth, band, lift]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var f := func(u: float, v: float) -> Vector3:
		var s := sin(u * PI)
		var w := width * 0.5 * pow(s, 0.55)
		var top := 0.32 + 0.32 * pow(absf(2.0 * u - 1.0), 3.0)
		var bottom := -depth * pow(s, 0.35)
		var vv := lerpf(band.x, band.y, v)
		var a := (vv - 0.5) * PI
		var x := w * sin(a) * (1.0 + 0.12 * (1.0 - cos(a)))
		var y := lerpf(bottom, top, 1.0 - cos(a))
		var p := Vector3(x, y, (u - 0.5) * length)
		if lift > 0.0:
			p += Vector3(signf(x), 0.0, 0.0) * lift
		return p
	var mesh := double_sided(param_surface(f, 28, 18, Vector3(0, -depth * 2.0, 0), false))
	_mesh_cache[key] = mesh
	return mesh


## Fuste de columna clásica: acanaladuras, éntasis (algo más ancha a un tercio de la altura),
## se estrecha arriba y tiene desconchones aquí y allá. Base en y = 0, abierta por los extremos.
static func column(height: float, radius: float, flutes := 16, seed_value := 0) -> ArrayMesh:
	var key := "column|%.2f|%.2f|%d|%d" % [height, radius, flutes, seed_value]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.6
	var f := func(u: float, v: float) -> Vector3:
		var ang := v * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var r := radius * (1.0 - 0.12 * u + 0.035 * sin(u * PI))
		var groove := pow(maxf(cos(ang * flutes), 0.0), 2.0)
		r -= radius * 0.06 * groove
		# Desconchones: el ruido "muerde" la piedra en algunos sitios.
		var chip := noise.get_noise_3d(dir.x * 1.3, u * height * 0.5, dir.y * 1.3)
		if chip > 0.35:
			r -= radius * (chip - 0.35) * 0.35
		return Vector3(dir.x * r, u * height, dir.y * r)
	var mesh := param_surface(f, int(height * 2.0) + 6, flutes * 4, Vector3(0, height * 0.5, 0))
	_mesh_cache[key] = mesh
	return mesh


## Pilar de roca de una pieza: se estrecha hacia arriba, tiene repisas de estratos cada
## `ledge` metros, ruido 3D y caras talladas. Base en y = 0.
static func spire(height: float, r_bottom: float, r_top: float, seed_value := 0, ledge := 2.2) -> ArrayMesh:
	var key := "spire|%.2f|%.2f|%.2f|%d|%.2f" % [height, r_bottom, r_top, seed_value, ledge]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.22
	noise.fractal_octaves = 3
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 5
	var cuts := []
	for k in 9:
		var a := r.randf() * TAU
		cuts.append([Vector2(cos(a), sin(a)), r.randf_range(0.0, height), r.randf_range(0.82, 0.95)])
	var f := func(u: float, v: float) -> Vector3:
		var y := u * height
		var t := u
		var ang := v * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var rad := lerpf(r_bottom, r_top, t)
		# Repisas: cada estrato sobresale un poco por abajo y se mete por arriba.
		var lf := fposmod(y / ledge + noise.get_noise_2d(ang * 3.0, 0.0) * 0.4, 1.0)
		rad *= 1.0 + (0.5 - lf) * 0.16
		rad *= 1.0 + noise.get_noise_3d(dir.x * 3.0, y * 0.35, dir.y * 3.0) * 0.22
		# Caras talladas: planos verticales que recortan el contorno a ciertas alturas.
		for c in cuts:
			var w := 1.0 - smoothstep(0.0, 3.0, absf(y - float(c[1])))
			var d: float = dir.dot(c[0])
			if d > c[2]:
				rad *= lerpf(1.0, c[2] / d, w)
		if u >= 0.999:
			rad *= 0.6
		var top := 0.0
		if u >= 0.999:
			top = 0.35
		return Vector3(dir.x * rad, y + top, dir.y * rad)
	var mesh := param_surface(f, int(height * 2.5) + 8, 36, Vector3(0, height * 0.5, 0))
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
	segs = maxi(segs, 12)
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


## Roca natural de radio ~1 (base aplastada): ruido 3D en varias octavas y unos cuantos
## planos de corte que dejan caras talladas, como una piedra partida. `flat` aplasta en vertical.
static func rock(seed_value: int, flat := 0.72, segs := 22) -> ArrayMesh:
	var key := "rock|%d|%.2f|%d" % [seed_value, flat, segs]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0
	noise.fractal_octaves = 3
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 7 + 3
	var cuts := []
	for k in 7:
		var d := Vector3(r.randf_range(-1.0, 1.0), r.randf_range(-0.2, 1.0), r.randf_range(-1.0, 1.0)).normalized()
		cuts.append([d, r.randf_range(0.66, 0.9)])
	var f := func(u: float, v: float) -> Vector3:
		var th := u * PI
		var ph := v * TAU
		var dir := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		var p := dir * (1.0 + noise.get_noise_3dv(dir * 1.4) * 0.3)
		for c in cuts:
			var dd: float = p.dot(c[0])
			if dd > c[1]:
				p -= (c[0] as Vector3) * (dd - c[1])
		p.y *= flat
		if p.y < -0.3:
			p.y = -0.3 + (p.y + 0.3) * 0.25
		return p
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
## hacia fuera, subiendo por el exterior y bajando por el interior si lo hay. Las normales se
## suavizan entre tramos del perfil que forman menos de 45° (curvas sin bandas) y se
## mantienen duras en las esquinas.
static func lathe(profile: PackedVector2Array, segs := 24) -> ArrayMesh:
	segs = maxi(segs * 2, 14)
	var key := "lathe|%s|%d" % [profile, segs]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_prof := profile.size()
	# Normal 2D de cada tramo del perfil (hacia "fuera" del recorrido).
	var seg_n := []
	for i in n_prof - 1:
		var t := (profile[i + 1] - profile[i]).normalized()
		seg_n.append(Vector2(t.y, -t.x))
	for i in n_prof - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		var n2: Vector2 = seg_n[i]
		var na := n2
		var nb := n2
		if i > 0 and (seg_n[i - 1] as Vector2).dot(n2) > 0.7:
			na = ((seg_n[i - 1] as Vector2) + n2).normalized()
		if i < n_prof - 2 and (seg_n[i + 1] as Vector2).dot(n2) > 0.7:
			nb = ((seg_n[i + 1] as Vector2) + n2).normalized()
		for j in segs:
			var a0 := TAU * j / segs
			var a1 := TAU * (j + 1) / segs
			var v00 := Vector3(p0.x * cos(a0), p0.y, p0.x * sin(a0))
			var v01 := Vector3(p0.x * cos(a1), p0.y, p0.x * sin(a1))
			var v10 := Vector3(p1.x * cos(a0), p1.y, p1.x * sin(a0))
			var v11 := Vector3(p1.x * cos(a1), p1.y, p1.x * sin(a1))
			var n00 := Vector3(na.x * cos(a0), na.y, na.x * sin(a0)).normalized()
			var n01 := Vector3(na.x * cos(a1), na.y, na.x * sin(a1)).normalized()
			var n10 := Vector3(nb.x * cos(a0), nb.y, nb.x * sin(a0)).normalized()
			var n11 := Vector3(nb.x * cos(a1), nb.y, nb.x * sin(a1)).normalized()
			if v00.distance_squared_to(v01) > 1e-12:
				_add_tri(st, v00, v10, v11, n00, n10, n11)
				_add_tri(st, v00, v11, v01, n00, n11, n01)
			elif v10.distance_squared_to(v11) > 1e-12:
				_add_tri(st, v00, v10, v11, n00, n10, n11)
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
	segs = maxi(segs, 12)
	var key := "sphere|%.3f|%d" % [radius, segs]
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segs * 2
		m.rings = segs
		_mesh_cache[key] = m
	return _mesh_cache[key]


## Cilindro (o cono, con `top` = 0) centrado en el origen, con los bordes biselados.
static func cylinder(top: float, bottom: float, height: float, segs := 16) -> Mesh:
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [top, bottom, height, segs]
	if not _mesh_cache.has(key):
		var h := height * 0.5
		var b := clampf(minf(maxf(top, bottom), height) * 0.2, 0.003, 0.06)
		var prof := PackedVector2Array([Vector2(0.0, -h)])
		if bottom > 0.0:
			var bb := minf(b, bottom * 0.5)
			prof.append_array([Vector2(bottom - bb, -h), Vector2(bottom - bb * 0.29, -h + bb * 0.29), Vector2(bottom, -h + bb)])
		if top > 0.0:
			var bt := minf(b, top * 0.5)
			prof.append_array([Vector2(top, h - bt), Vector2(top - bt * 0.29, h - bt * 0.29), Vector2(top - bt, h)])
		prof.append(Vector2(0.0, h))
		_mesh_cache[key] = lathe(prof, segs)
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
		m.rings = 32
		m.ring_segments = 14
		_mesh_cache[key] = m
	return _mesh_cache[key]


static func cone(radius: float, height: float, segs := 16) -> Mesh:
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
