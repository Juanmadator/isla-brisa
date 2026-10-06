class_name BodyKit
extends RefCounted
## Mallas de personaje con esqueleto: el tronco, los brazos y las piernas son tubos de una
## pieza (secciones elípticas interpoladas con Catmull-Rom) cuyos vértices llevan pesos de
## varios huesos. Al doblar un codo o una rodilla la manga se curva entera, sin bolas ni
## juntas a la vista.

static var _cache := {}
static var _mat_cache := {}


static func clear_cache() -> void:
	_cache.clear()
	_mat_cache.clear()


## Material de ropa con dibujo de tela que respeta el color de vértice (bandas más oscuras en
## dobladillos y puños) y lee la posición de reposo de CUSTOM0.
static func cloth_mat(color: Color, surface := "cloth") -> ShaderMaterial:
	var key := "%s|%s" % [color.to_html(), surface]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: ShaderMaterial = MeshKit.surface_mat(color, surface, 0.06).duplicate()
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("rest_from_custom", true)
	m.set_shader_parameter("sheen", 0.1)
	_mat_cache[key] = m
	return m


static func skin_mat(color: Color) -> ShaderMaterial:
	var key := "skin|%s" % color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: ShaderMaterial = MeshKit.mat(color, 0.0).duplicate()
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("rest_from_custom", true)
	m.set_shader_parameter("detail", 0.025)
	m.set_shader_parameter("sheen", 0.14)
	m.set_shader_parameter("rim_amount", 0.3)
	_mat_cache[key] = m
	return m


## Tubo con esqueleto. `sections`: [centro, radio x, radio del otro eje]; `weights(p, u)`
## devuelve [[hueso, peso], ...] para cada vértice (p en reposo, u de 0 a 1 a lo largo);
## `radial(u, v)` (opcional) multiplica el radio; `shade(p, u)` (opcional) da un gris que
## multiplica el color (bandas). `axis_x` es la x del eje del miembro (para el dibujo de tela).
static func tube(key: String, sections: Array, nv: int, sub: int, weights: Callable, radial := Callable(), shade := Callable(), axis_x := 0.0, caps := true) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var n := sections.size()
	var cs: Array[Vector3] = []
	var rxs: Array[float] = []
	var rys: Array[float] = []
	var total := (n - 1) * sub
	for i in total + 1:
		var f := float(i) / sub
		var k := mini(int(f), n - 2)
		var s := f - k
		var a0: Array = sections[maxi(k - 1, 0)]
		var a1: Array = sections[k]
		var a2: Array = sections[k + 1]
		var a3: Array = sections[mini(k + 2, n - 1)]
		cs.append((a1[0] as Vector3).cubic_interpolate(a2[0], a0[0], a3[0], s))
		rxs.append(maxf(cubic_interpolate(a1[1], a2[1], a0[1], a3[1], s), 0.001))
		rys.append(maxf(cubic_interpolate(a1[2], a2[2], a0[2], a3[2], s), 0.001))
	var rings := cs.size()
	var tans: Array[Vector3] = []
	for i in rings:
		tans.append((cs[mini(i + 1, rings - 1)] - cs[maxi(i - 1, 0)]).normalized())
	var pts: Array = []
	for i in rings:
		var x_ax := Vector3.RIGHT
		var y_ax := x_ax.cross(tans[i]).normalized()
		var row: Array[Vector3] = []
		for j in nv:
			var a := TAU * j / nv
			var m := 1.0
			if radial.is_valid():
				m = radial.call(float(i) / (rings - 1), float(j) / nv)
			row.append(cs[i] + x_ax * cos(a) * rxs[i] * m + y_ax * sin(a) * rys[i] * m)
		pts.append(row)
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var add := func(p: Vector3, nrm: Vector3, u: float) -> void:
		var ws: Array = weights.call(p, u)
		var bones := PackedInt32Array([0, 0, 0, 0])
		var wv := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		var sum := 0.0
		for q in mini(ws.size(), 4):
			bones[q] = int(ws[q][0])
			wv[q] = float(ws[q][1])
			sum += wv[q]
		if sum <= 0.0:
			wv[0] = 1.0
			sum = 1.0
		for q in 4:
			wv[q] /= sum
		var g := 1.0
		if shade.is_valid():
			g = shade.call(p, u)
		st.set_color(Color(g, g, g))
		st.set_normal(nrm)
		st.set_custom(0, Color(p.x, p.y, p.z, axis_x))
		st.set_bones(bones)
		st.set_weights(wv)
		st.add_vertex(p)
	# Vértices de la rejilla con normales analíticas.
	for i in rings:
		var u := float(i) / (rings - 1)
		for j in nv:
			var du: Vector3 = pts[mini(i + 1, rings - 1)][j] - pts[maxi(i - 1, 0)][j]
			var dv: Vector3 = pts[i][(j + 1) % nv] - pts[i][(j - 1 + nv) % nv]
			var nn := du.cross(dv)
			if nn.length_squared() < 1e-14:
				nn = pts[i][j] - cs[i]
			nn = nn.normalized()
			if nn.dot(pts[i][j] - cs[i]) < 0.0:
				nn = -nn
			add.call(pts[i][j], nn, u)
	# Polos de los casquetes.
	var pole0 := rings * nv
	if caps:
		add.call(cs[0] - tans[0] * minf(rxs[0], rys[0]) * 0.55, -tans[0], 0.0)
		add.call(cs[rings - 1] + tans[rings - 1] * minf(rxs[rings - 1], rys[rings - 1]) * 0.55, tans[rings - 1], 1.0)
	var vp: Array[Vector3] = []
	for i in rings:
		for j in nv:
			vp.append(pts[i][j])
	if caps:
		vp.append(cs[0] - tans[0])
		vp.append(cs[rings - 1] + tans[rings - 1])
	# Cada triángulo se orienta según su dirección "hacia fuera" (`out`).
	var tri := func(a: int, b: int, c: int, out: Vector3) -> void:
		if _needs_flip(vp[a], vp[b], vp[c], out):
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
		else:
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
	for i in rings - 1:
		for j in nv:
			var j1 := (j + 1) % nv
			var out := vp[i * nv + j] - cs[i]
			tri.call(i * nv + j, (i + 1) * nv + j, (i + 1) * nv + j1, out)
			tri.call(i * nv + j, (i + 1) * nv + j1, i * nv + j1, out)
	if caps:
		var last := (rings - 1) * nv
		for j in nv:
			var j1 := (j + 1) % nv
			tri.call(pole0, j, j1, -tans[0])
			tri.call(pole0 + 1, last + j, last + j1, tans[rings - 1])
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## ¿Hay que invertir el orden (a, b, c) para que la cara frontal mire hacia `out`?
static func _needs_flip(a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> bool:
	var face := (b - a).cross(c - a)
	# Godot considera frontal la cara de orden horario visto desde fuera.
	return (face.dot(out) > 0.0) == MeshKit.CLOCKWISE_FRONT


## Pesos que pasan de `a` a `b` alrededor de `y0` (franja de ancho `w`, en altura).
static func blend_y(p: Vector3, y0: float, w: float, a: int, b: int) -> Array:
	var t := clampf((y0 + w * 0.5 - p.y) / w, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return [[a, 1.0 - t], [b, t]]


## Zapato de una pieza (puntera redondeada, talón, suela plana). Origen en el tobillo, la
## puntera hacia -Z y la suela a `-ankle`.
static func shoe(ankle: float, r: float) -> ArrayMesh:
	var key := "shoe|%.3f|%.3f" % [ankle, r]
	if _cache.has(key):
		return _cache[key]
	var base := -ankle
	var secs := [
		[Vector3(0, base + 0.045, 0.075), 0.016, 0.012],
		[Vector3(0, base + 0.048, 0.062), r * 0.86, r * 0.82],
		[Vector3(0, base + 0.052, 0.015), r * 1.04, r * 0.98],
		[Vector3(0, base + 0.04, -0.05), r * 1.12, r * 0.78],
		[Vector3(0, base + 0.034, -0.105), r * 1.02, r * 0.62],
		[Vector3(0, base + 0.03, -0.138), r * 0.7, r * 0.45],
		[Vector3(0, base + 0.03, -0.152), r * 0.2, r * 0.15],
	]
	# Aplana la mitad de abajo (suela) y levanta un poco el empeine.
	var radial := func(_u: float, v: float) -> float:
		var s := sin(v * TAU)
		return 1.0 - maxf(-s, 0.0) * 0.32
	var mesh := MeshKit.loft(secs, 20, 4, radial)
	_cache[key] = mesh
	return mesh


## Cabeza: algo más ancha en los mofletes, mandíbula redondeada, nuca plana y coronilla alta.
static func head(radius: float) -> ArrayMesh:
	var key := "head|%.3f" % radius
	if _cache.has(key):
		return _cache[key]
	var f := func(u: float, v: float) -> Vector3:
		var th := u * PI
		var ph := v * TAU
		var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		var r := radius
		# Mofletes: la mitad baja de la cara (z < 0 es delante) algo más llena.
		var front := maxf(-d.z, 0.0)
		var low := maxf(-d.y, 0.0)
		r *= 1.0 + 0.07 * front * smoothstep(0.0, 0.6, low) * (1.0 - smoothstep(0.6, 1.0, low))
		# Mandíbula: se estrecha hacia la barbilla.
		var x := d.x * (1.0 - 0.13 * low * low)
		var z := d.z
		# Nuca un poco plana y frente algo vertical.
		if z > 0.0:
			z *= 0.93
		var y := d.y * 0.97
		return Vector3(x * r, y * r, z * r)
	var mesh := MeshKit.param_surface(f, 26, 52)
	_cache[key] = mesh
	return mesh


## Mano de manopla con los dedos juntos un poco curvados y el pulgar aparte.
static func mitten(r: float) -> ArrayMesh:
	var key := "mitten|%.3f" % r
	if _cache.has(key):
		return _cache[key]
	# Sección: estrecha de lado (grosor de la palma) y ancha de delante atrás; los dedos se
	# curvan un poco hacia dentro (la palma mira al cuerpo).
	var secs := [
		[Vector3(0, 0.035, 0.0), r * 0.42, r * 0.55],
		[Vector3(0, 0.0, 0.0), r * 0.58, r * 0.84],
		[Vector3(0, -0.04, -0.004), r * 0.64, r * 1.02],
		[Vector3(0, -0.075, -0.004), r * 0.6, r * 0.96],
		[Vector3(0.006, -0.1, 0.0), r * 0.5, r * 0.76],
		[Vector3(0.014, -0.114, 0.0), r * 0.3, r * 0.42],
	]
	var mesh := MeshKit.loft(secs, 18, 3)
	_cache[key] = mesh
	return mesh


## Delantal: trozo de tela curvado que se ciñe al tronco (radio `r` en x, `rz` en z), de
## `top` a `bottom` (altura) y `half_ang` radianes a cada lado; un poco más abierto abajo.
static func apron(r: float, rz: float, top: float, bottom: float, half_ang: float) -> ArrayMesh:
	var key := "apron|%.3f|%.3f|%.3f|%.3f|%.3f" % [r, rz, top, bottom, half_ang]
	if _cache.has(key):
		return _cache[key]
	var f := func(u: float, v: float) -> Vector3:
		var y := lerpf(top, bottom, u)
		var a := lerpf(-half_ang, half_ang, v) * (1.0 + 0.12 * u)
		var flare := 1.0 + 0.1 * u * u
		# Pliegues suaves que caen desde la cintura.
		var fold := 1.0 + sin(v * TAU * 3.0) * 0.012 * u
		return Vector3(sin(a) * r * flare * fold, y, -cos(a) * rz * flare * fold)
	var mesh := MeshKit.double_sided(MeshKit.param_surface(f, 8, 16, Vector3(0, (top + bottom) * 0.5, 0), false))
	_cache[key] = mesh
	return mesh
