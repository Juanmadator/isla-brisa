class_name Animals
extends RefCounted
## Modelos de los animales de granja y del burro del carro. Todos miran hacia -Z con el
## origen en el suelo y tienen nodos con nombre para animarlos: Body, Body/Head, Body/Leg*,
## Body/Tail y, en la oveja, Body/Wool (la lana que se esquila).
## Cuerpos, cuellos y patas son de una pieza (`MeshKit.loft`): lomo, barriga, cruz y
## corvejones en vez de cápsulas. La cabeza cuelga de la base del cuello, así que al pastar
## baja todo el cuello. La meta "graze" es cuánto baja (radianes).

static var _leg_cache := {}
static var _fur: ShaderMaterial


## Material de pelo con el color en los vértices (manchas, tripa clara, pezuñas).
static func _fur_mat() -> ShaderMaterial:
	if _fur == null:
		_fur = MeshKit.vcol_mat(0.0, 0.1).duplicate()
		_fur.set_shader_parameter("surface", MeshKit.SURFACES["cloth"])
		_fur.set_shader_parameter("surface_scale", 1.6)
		_fur.set_shader_parameter("detail", 0.03)
	return _fur


static func _node(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var nd := Node3D.new()
	nd.name = n
	nd.position = pos
	parent.add_child(nd)
	return nd


## Pata de una pieza: muslo (o antebrazo), rodilla (en las traseras, el corvejón hacia
## atrás), caña fina, menudillo y pezuña oscura. El pivote queda arriba, dentro del cuerpo.
static func _leg(parent: Node3D, n: int, pos: Vector3, r: float, len: float, col: Color, hoof: Color, rear := false, hoof_h := 0.08) -> void:
	var leg := _node(parent, "Leg%d" % n, pos)
	var key := "%.3f|%.3f|%s|%s|%s|%.3f" % [r, len, col.to_html(), hoof.to_html(), rear, hoof_h]
	if not _leg_cache.has(key):
		var back := 1.0 if rear else -0.35
		var secs := [
			[Vector3(0, r * 0.9, 0), r * 0.5, r * 0.5],
			[Vector3(0, 0.0, 0), r * 1.5, r * 1.75],
			[Vector3(0, -len * 0.28, r * 0.3 * back), r * 1.1, r * 1.3],
			[Vector3(0, -len * 0.5, r * 0.6 * back), r * 0.75, r * 0.9],
			[Vector3(0, -len * 0.74, r * 0.12 * back), r * 0.58, r * 0.62],
			[Vector3(0, -len + hoof_h * 1.4, -r * 0.08), r * 0.74, r * 0.8],
			[Vector3(0, -len + hoof_h * 0.5, -r * 0.22), r * 0.92, r * 1.05],
			[Vector3(0, -len + 0.01, -r * 0.25), r * 0.86, r * 1.0],
		]
		var cut := -len + hoof_h
		var colorf := func(p: Vector3) -> Color:
			return hoof if p.y < cut else col
		_leg_cache[key] = MeshKit.loft(secs, 10, 3, Callable(), colorf)
	MeshKit.part(leg, _leg_cache[key], _fur_mat())


static func _eyes(head: Node3D, x: float, y: float, z: float, r := 0.025, side_look := 0.0) -> void:
	for sx: float in [-1.0, 1.0]:
		var e := _node(head, "Eye", Vector3(sx * x, y, z))
		e.rotation.y = sx * side_look
		MeshKit.part(e, MeshKit.sphere(r, 10), MeshKit.mat(Color(0.06, 0.05, 0.06)), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
		MeshKit.part(e, MeshKit.sphere(r * 0.35, 8), MeshKit.unshaded(Color.WHITE), Vector3(sx * r * 0.25, r * 0.4, -r * 0.6))


## Oveja: vellones de lana repartidos sobre el cuerpo (más arriba que en la tripa), cara
## alargada oscura (o clara), orejas caídas hacia los lados y patas finas.
static func sheep(seed_value := 0) -> Node3D:
	var root := Node3D.new()
	root.set_meta("graze", 1.0)
	var body := _node(root, "Body", Vector3.ZERO)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 11
	var wool_col := Color(0.96, 0.94, 0.9).darkened(r.randf() * 0.08)
	var skin := Color(0.22, 0.19, 0.19) if r.randf() < 0.75 else Color(0.93, 0.87, 0.82)
	# Cuerpo bajo la lana (se ve algo al esquilarla).
	var core := MeshKit.loft([
		[Vector3(0, 0.68, 0.42), 0.05, 0.05], [Vector3(0, 0.67, 0.34), 0.19, 0.2], [Vector3(0, 0.64, 0.02), 0.23, 0.24],
		[Vector3(0, 0.68, -0.28), 0.19, 0.21], [Vector3(0, 0.72, -0.38), 0.06, 0.06]], 14, 3)
	MeshKit.part(body, core, MeshKit.mat(wool_col.darkened(0.2)))
	var wool := _node(body, "Wool", Vector3.ZERO)
	var wm := MeshKit.surface_mat(wool_col, "cloth", 0.15)
	var count := 52
	for k in count:
		var y := 1.0 - 2.0 * (k + 0.5) / count
		if y < -0.6:
			continue
		var rad := sqrt(1.0 - y * y)
		var phi := k * 2.39996 + r.randf() * 0.4
		var dir := Vector3(cos(phi) * rad, y, sin(phi) * rad)
		var p := Vector3(dir.x * 0.25, 0.68 + dir.y * 0.21, dir.z * 0.4)
		MeshKit.part(wool, MeshKit.blob(r.randf_range(0.1, 0.14), 1.0, 0.3, k % 9, 10), wm, p)
	# Cuello y cabeza de una pieza; el pivote está en el pecho y baja al pastar.
	var head := _node(body, "Head", Vector3(0, 0.7, -0.3))
	var face := MeshKit.loft([
		[Vector3(0, -0.02, 0.1), 0.06, 0.06], [Vector3(0, 0.0, 0.0), 0.11, 0.13], [Vector3(0, 0.08, -0.12), 0.1, 0.11],
		[Vector3(0, 0.12, -0.2), 0.105, 0.1], [Vector3(0, 0.07, -0.3), 0.075, 0.075], [Vector3(0, 0.03, -0.36), 0.06, 0.055],
		[Vector3(0, 0.02, -0.38), 0.02, 0.02]], 14, 3)
	MeshKit.part(head, face, MeshKit.mat(skin))
	MeshKit.part(head, MeshKit.blob(0.1, 0.75, 0.3, 3, 10), wm, Vector3(0, 0.19, -0.17))
	MeshKit.part(head, MeshKit.blob(0.12, 1.0, 0.3, 4, 10), wm, Vector3(0, 0.06, 0.0))
	for sx: float in [-1.0, 1.0]:
		var ear := _node(head, "Ear%d" % (0 if sx < 0 else 1), Vector3(sx * 0.1, 0.15, -0.16))
		MeshKit.part(ear, MeshKit.blob(0.055, 0.42, 0.0, 0, 8), MeshKit.mat(skin), Vector3(sx * 0.05, -0.015, 0), Vector3(0, sx * -15.0, sx * -25.0), Vector3(1.8, 1.0, 0.9))
		MeshKit.part(head, MeshKit.sphere(0.008, 5), MeshKit.mat(Color(0.1, 0.08, 0.08)), Vector3(sx * 0.022, 0.04, -0.375))
	_eyes(head, 0.08, 0.13, -0.22, 0.019, 0.5)
	for i in 4:
		var rear := i >= 2
		_leg(body, i, Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.12, 0.5, -0.22 if not rear else 0.24), 0.034, 0.5, skin, Color(0.13, 0.1, 0.09), rear, 0.06)
	var tail := _node(body, "Tail", Vector3(0, 0.7, 0.42))
	MeshKit.part(tail, MeshKit.blob(0.07, 1.4, 0.25, 5, 8), wm, Vector3(0, -0.06, 0.03))
	return root


## Vaca: cuerpo de una pieza con cadera marcada, barriga y cruz; manchas irregulares pintadas
## en la piel (no pegotes encima), morro ancho rosado, cuernos, orejas de lado y ubre.
static func cow(seed_value := 0) -> Node3D:
	var root := Node3D.new()
	root.set_meta("graze", 1.15)
	var body := _node(root, "Body", Vector3.ZERO)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 23
	var base := Color(0.95, 0.94, 0.9) if r.randf() < 0.6 else Color(0.6, 0.4, 0.26)
	var spot := Color(0.13, 0.11, 0.11) if base.v > 0.8 else Color(0.95, 0.93, 0.9)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value * 7 + 3
	noise.frequency = 1.5
	noise.fractal_octaves = 2
	var pink := Color(0.98, 0.72, 0.7)
	var skin := func(p: Vector3) -> Color:
		var k := smoothstep(0.1, 0.2, noise.get_noise_3dv(p))
		return base.lerp(spot, k)
	var trunk := MeshKit.loft([
		[Vector3(0, 1.13, 0.95), 0.06, 0.06], [Vector3(0, 1.11, 0.88), 0.24, 0.26], [Vector3(0, 1.08, 0.66), 0.37, 0.37],
		[Vector3(0, 1.02, 0.3), 0.41, 0.44], [Vector3(0, 0.98, -0.1), 0.43, 0.47], [Vector3(0, 1.03, -0.45), 0.38, 0.44],
		[Vector3(0, 1.1, -0.7), 0.29, 0.37], [Vector3(0, 1.2, -0.84), 0.17, 0.21], [Vector3(0, 1.24, -0.9), 0.05, 0.05]], 24, 5, Callable(), skin)
	MeshKit.part(body, trunk, _fur_mat())
	# Ubre
	MeshKit.part(body, MeshKit.blob(0.15, 0.7, 0.0, 0, 12), MeshKit.mat(pink), Vector3(0, 0.6, 0.42), Vector3.ZERO, Vector3(1.0, 1.0, 1.2))
	for k in 4:
		MeshKit.part(body, MeshKit.cylinder(0.018, 0.022, 0.08, 6), MeshKit.mat(pink.darkened(0.08)), Vector3((-1.0 if k % 2 == 0 else 1.0) * 0.06, 0.5, 0.36 + (k >> 1) * 0.12))
	# Cuello y cabeza: pivote en la base del cuello.
	var head := _node(body, "Head", Vector3(0, 1.16, -0.76))
	var face_col := func(p: Vector3) -> Color:
		var c: Color = skin.call(p + Vector3(0, 1.16, -0.76))
		return c.lerp(pink, clampf((-0.58 - p.z) * 12.0, 0.0, 1.0))
	var neck_head := MeshKit.loft([
		[Vector3(0, -0.02, 0.14), 0.1, 0.1], [Vector3(0, 0.02, 0.04), 0.2, 0.28], [Vector3(0, 0.14, -0.16), 0.17, 0.24],
		[Vector3(0, 0.25, -0.32), 0.17, 0.18], [Vector3(0, 0.2, -0.44), 0.15, 0.15], [Vector3(0, 0.06, -0.55), 0.115, 0.12],
		[Vector3(0, -0.06, -0.63), 0.12, 0.11], [Vector3(0, -0.11, -0.68), 0.1, 0.08], [Vector3(0, -0.13, -0.7), 0.04, 0.04]], 20, 4, Callable(), face_col)
	MeshKit.part(head, neck_head, _fur_mat())
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(head, MeshKit.blob(0.022, 0.7, 0.0, 0, 8), MeshKit.mat(Color(0.35, 0.2, 0.2)), Vector3(sx * 0.045, -0.1, -0.7))
		# Cuerno: arranca de lo alto de la frente hacia fuera y se curva hacia arriba.
		var horn := _node(head, "Horn", Vector3(sx * 0.12, 0.38, -0.36))
		MeshKit.part(horn, MeshKit.cylinder(0.026, 0.04, 0.12, 8), MeshKit.mat(Color(0.95, 0.9, 0.78)), Vector3(sx * 0.05, 0.0, 0), Vector3(0, 0, -sx * 80.0))
		MeshKit.part(horn, MeshKit.cone(0.027, 0.12, 8), MeshKit.mat(Color(0.9, 0.84, 0.7)), Vector3(sx * 0.13, 0.05, 0), Vector3(0, 0, -sx * 35.0))
		# Oreja: por debajo del cuerno, hacia fuera y algo caída.
		var ear := _node(head, "Ear%d" % (0 if sx < 0 else 1), Vector3(sx * 0.14, 0.27, -0.33))
		MeshKit.part(ear, MeshKit.blob(0.08, 0.4, 0.0, 0, 10), MeshKit.mat(base.darkened(0.06)), Vector3(sx * 0.1, -0.03, 0), Vector3(0, sx * 20.0, sx * -22.0), Vector3(1.6, 1.0, 0.85))
		MeshKit.part(ear, MeshKit.blob(0.05, 0.3, 0.0, 0, 8), MeshKit.mat(pink), Vector3(sx * 0.11, -0.03, -0.022), Vector3(0, sx * 20.0, sx * -22.0), Vector3(1.6, 1.0, 0.5))
	_eyes(head, 0.125, 0.2, -0.47, 0.028, 0.6)
	for i in 4:
		var rear := i >= 2
		_leg(body, i, Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.24, 0.76, -0.56 if not rear else 0.62), 0.066, 0.76, base if r.randf() < 0.7 else spot, Color(0.16, 0.12, 0.1), rear, 0.1)
	var tail := _node(body, "Tail", Vector3(0, 1.12, 0.94))
	MeshKit.part(tail, MeshKit.cylinder(0.018, 0.03, 0.72, 6), MeshKit.mat(base), Vector3(0, -0.36, 0.04))
	MeshKit.part(tail, MeshKit.blob(0.055, 1.6, 0.25, 2, 8), MeshKit.mat(spot if base.v > 0.8 else base.darkened(0.3)), Vector3(0, -0.74, 0.04))
	return root


## Gallina: cuerpo en gota (cola levantada, pechuga redonda), cresta de tres lóbulos,
## barbillas, alas plegadas y cola de plumas.
static func chicken(seed_value := 0) -> Node3D:
	var root := Node3D.new()
	root.set_meta("graze", 1.0)
	var body := _node(root, "Body", Vector3.ZERO)
	var cols := [Color(0.97, 0.95, 0.9), Color(0.75, 0.45, 0.25), Color(0.35, 0.3, 0.28)]
	var col: Color = cols[seed_value % cols.size()]
	var m := MeshKit.surface_mat(col, "cloth", 0.1)
	var trunk := MeshKit.loft([
		[Vector3(0, 0.36, 0.2), 0.02, 0.02], [Vector3(0, 0.31, 0.15), 0.06, 0.07], [Vector3(0, 0.24, 0.06), 0.12, 0.12],
		[Vector3(0, 0.21, -0.04), 0.13, 0.13], [Vector3(0, 0.26, -0.11), 0.095, 0.1], [Vector3(0, 0.32, -0.12), 0.05, 0.05]], 16, 3)
	MeshKit.part(body, trunk, m)
	var head := _node(body, "Head", Vector3(0, 0.36, -0.12))
	MeshKit.part(head, MeshKit.blob(0.065, 1.1, 0.0, 0, 10), m, Vector3(0, 0.02, -0.01))
	MeshKit.part(head, MeshKit.cone(0.022, 0.055, 8), MeshKit.mat(Color(1.0, 0.72, 0.25)), Vector3(0, 0.0, -0.085), Vector3(-90, 0, 0), Vector3(1.0, 1.0, 0.75))
	var red := MeshKit.mat(Color(0.88, 0.15, 0.14))
	for k in 3:
		MeshKit.part(head, MeshKit.blob(0.022, 1.3, 0.0, 0, 8), red, Vector3(0, 0.085 + (1 - absi(k - 1)) * 0.012, -0.035 + k * 0.025), Vector3(0, 0, 0), Vector3(0.45, 1.0, 1.0))
	MeshKit.part(head, MeshKit.blob(0.02, 1.4, 0.0, 0, 8), red, Vector3(0, -0.045, -0.06), Vector3.ZERO, Vector3(0.6, 1.0, 1.0))
	_eyes(head, 0.042, 0.035, -0.04, 0.013, 0.6)
	var tail := _node(body, "Tail", Vector3(0, 0.3, 0.15))
	for k in 5:
		var a := (k - 2) * 16.0
		MeshKit.part(tail, MeshKit.blob(0.055, 1.8, 0.0, 0, 8), MeshKit.mat(col.darkened(0.06 * (k % 3))), Vector3((k - 2) * 0.018, 0.07, 0.02), Vector3(-30, 0, a), Vector3(0.35, 1.0, 1.0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(body, MeshKit.blob(0.09, 1.2, 0.0, 0, 8), MeshKit.surface_mat(col.darkened(0.08), "cloth", 0.1), Vector3(sx * 0.115, 0.245, 0.03), Vector3(18, 0, 0), Vector3(0.32, 0.75, 1.0))
	var foot := MeshKit.mat(Color(1.0, 0.72, 0.25))
	for i in 2:
		var leg := _node(body, "Leg%d" % i, Vector3((-1.0 if i == 0 else 1.0) * 0.05, 0.12, 0.0))
		MeshKit.part(leg, MeshKit.blob(0.04, 1.3, 0.0, 0, 8), m, Vector3(0, 0.02, 0))
		MeshKit.part(leg, MeshKit.cylinder(0.01, 0.012, 0.1, 5), foot, Vector3(0, -0.06, 0))
		for t in 3:
			MeshKit.part(leg, MeshKit.cylinder(0.006, 0.008, 0.05, 4), foot, Vector3((t - 1) * 0.012, -0.11, -0.02), Vector3(-90, (t - 1) * 30.0, 0))
	return root


## Burro: cuerpo gris de una pieza con tripa y morro claros, cuello con crin, orejas largas.
static func donkey() -> Node3D:
	var root := Node3D.new()
	root.set_meta("graze", 0.9)
	var body := _node(root, "Body", Vector3.ZERO)
	var grey := Color(0.55, 0.52, 0.5)
	var light := Color(0.86, 0.84, 0.8)
	var shade := func(p: Vector3) -> Color:
		return grey.lerp(light, clampf((0.78 - p.y) * 6.0, 0.0, 1.0))
	var trunk := MeshKit.loft([
		[Vector3(0, 0.94, 0.68), 0.05, 0.05], [Vector3(0, 0.93, 0.6), 0.19, 0.21], [Vector3(0, 0.91, 0.42), 0.27, 0.29],
		[Vector3(0, 0.86, 0.05), 0.29, 0.32], [Vector3(0, 0.88, -0.3), 0.26, 0.3], [Vector3(0, 0.96, -0.5), 0.2, 0.26],
		[Vector3(0, 1.04, -0.6), 0.06, 0.06]], 20, 4, Callable(), shade)
	MeshKit.part(body, trunk, _fur_mat())
	var head := _node(body, "Head", Vector3(0, 1.0, -0.5))
	var face := func(p: Vector3) -> Color:
		return grey.lerp(light, clampf((-0.42 - p.z) * 10.0, 0.0, 1.0))
	var neck_head := MeshKit.loft([
		[Vector3(0, -0.02, 0.1), 0.08, 0.08], [Vector3(0, 0.0, 0.0), 0.14, 0.2], [Vector3(0, 0.2, -0.12), 0.11, 0.15],
		[Vector3(0, 0.34, -0.2), 0.12, 0.13], [Vector3(0, 0.28, -0.34), 0.11, 0.11], [Vector3(0, 0.18, -0.46), 0.09, 0.09],
		[Vector3(0, 0.13, -0.52), 0.085, 0.07], [Vector3(0, 0.12, -0.55), 0.03, 0.03]], 16, 4, Callable(), face)
	MeshKit.part(head, neck_head, _fur_mat())
	var mane := MeshKit.mat(Color(0.25, 0.22, 0.2))
	for k in 7:
		var t := k / 6.0
		var p := Vector3(0, 0.05, 0.08).lerp(Vector3(0, 0.46, -0.18), t)
		MeshKit.part(head, MeshKit.blob(0.05, 1.3, 0.2, k, 8), mane, p, Vector3(-35, 0, 0), Vector3(0.6, 1.0, 1.0))
	for sx: float in [-1.0, 1.0]:
		var ear := _node(head, "Ear%d" % (0 if sx < 0 else 1), Vector3(sx * 0.07, 0.42, -0.2))
		MeshKit.part(ear, MeshKit.blob(0.05, 3.0, 0.0, 0, 8), MeshKit.mat(grey), Vector3(sx * 0.03, 0.13, 0), Vector3(0, 0, -sx * 18.0), Vector3(1.0, 1.0, 0.55))
		MeshKit.part(ear, MeshKit.blob(0.03, 2.6, 0.0, 0, 8), MeshKit.mat(light), Vector3(sx * 0.03, 0.12, -0.02), Vector3(0, 0, -sx * 18.0), Vector3(1.0, 1.0, 0.4))
		MeshKit.part(head, MeshKit.blob(0.016, 0.7, 0.0, 0, 6), MeshKit.mat(Color(0.2, 0.17, 0.16)), Vector3(sx * 0.045, 0.12, -0.555))
	_eyes(head, 0.1, 0.32, -0.3, 0.024, 0.5)
	for i in 4:
		var rear := i >= 2
		_leg(body, i, Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.16, 0.66, -0.42 if not rear else 0.44), 0.05, 0.66, grey, Color(0.2, 0.18, 0.16), rear, 0.07)
	var tail := _node(body, "Tail", Vector3(0, 0.94, 0.66))
	MeshKit.part(tail, MeshKit.cylinder(0.015, 0.025, 0.5, 6), MeshKit.mat(grey), Vector3(0, -0.25, 0.04))
	MeshKit.part(tail, MeshKit.blob(0.05, 1.6, 0.2, 2, 8), mane, Vector3(0, -0.52, 0.04))
	return root


## Animación de paseo para cualquiera de estos modelos: patas, cabeza y cola.
## `phase` avanza al andar; `grazing` (0 a 1) baja el cuello a pastar; `t` es el tiempo.
static func animate(model: Node3D, phase: float, moving: bool, grazing: float, t: float) -> void:
	var body := model.get_node("Body") as Node3D
	var head := body.get_node("Head") as Node3D
	var s := sin(phase)
	var legs := 0
	for c in body.get_children():
		if c.name.begins_with("Leg"):
			var front := legs < 2
			var sign_ := 1.0 if (legs % 2 == 0) == front else -1.0
			(c as Node3D).rotation.x = s * 0.5 * sign_ if moving else lerpf((c as Node3D).rotation.x, 0.0, 0.2)
			legs += 1
	body.position.y = absf(s) * 0.025 if moving else 0.0
	# rotation.x negativo baja el morro (que apunta a -Z).
	var down := float(model.get_meta("graze", 0.9))
	head.rotation.x = lerpf(head.rotation.x, -grazing * down + sin(t * 1.3) * 0.04, 0.1)
	var tail := body.get_node_or_null("Tail") as Node3D
	if tail:
		tail.rotation.z = sin(t * 3.0 + phase) * 0.35
