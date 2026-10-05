class_name Animals
extends RefCounted
## Modelos de los animales de granja y del burro del carro. Todos miran hacia -Z con el
## origen en el suelo y tienen nodos con nombre para animarlos: Body, Body/Head, Body/Leg*,
## Body/Tail y, en la oveja, Body/Wool (la lana que se esquila).


static func _leg(parent: Node3D, n: int, pos: Vector3, r: float, len: float, col: Color, hoof: Color) -> void:
	var leg := Node3D.new()
	leg.name = "Leg%d" % n
	leg.position = pos
	parent.add_child(leg)
	MeshKit.part(leg, MeshKit.capsule(r, len), MeshKit.mat(col), Vector3(0, -len * 0.45, 0))
	MeshKit.part(leg, MeshKit.cylinder(r * 1.05, r * 1.15, 0.07, 10), MeshKit.mat(hoof), Vector3(0, -len + 0.04, 0))


static func _eyes(head: Node3D, x: float, y: float, z: float, r := 0.025) -> void:
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(head, MeshKit.sphere(r, 10), MeshKit.mat(Color(0.06, 0.05, 0.06)), Vector3(sx * x, y, z))
		MeshKit.part(head, MeshKit.sphere(r * 0.35, 8), MeshKit.unshaded(Color.WHITE), Vector3(sx * x + r * 0.3, y + r * 0.4, z - r * 0.7))


## Oveja: cuerpo de vellones de lana (muchas bolas), cara y patas oscuras.
static func sheep(seed_value := 0) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 11
	var wool_col := Color(0.96, 0.94, 0.9).darkened(r.randf() * 0.08)
	var skin := Color(0.25, 0.22, 0.22) if r.randf() < 0.75 else Color(0.95, 0.9, 0.85)
	MeshKit.part(body, MeshKit.capsule(0.22, 0.7), MeshKit.mat(wool_col.darkened(0.25)), Vector3(0, 0.6, 0), Vector3(90, 0, 0))
	var wool := Node3D.new()
	wool.name = "Wool"
	body.add_child(wool)
	var wm := MeshKit.surface_mat(wool_col, "cloth", 0.15)
	for k in 26:
		var a := r.randf() * TAU
		var z := r.randf_range(-0.34, 0.34)
		var p := Vector3(cos(a) * 0.24, 0.62 + sin(a) * 0.2, z)
		if p.y < 0.5:
			p.y = 0.5 + (0.5 - p.y) * 0.3
		MeshKit.part(wool, MeshKit.blob(r.randf_range(0.12, 0.17), 1.0, 0.25, k % 9, 12), wm, p)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.74, -0.42)
	body.add_child(head)
	MeshKit.part(head, MeshKit.blob(0.12, 1.1, 0.0, 0, 12), MeshKit.mat(skin), Vector3(0, -0.02, -0.06), Vector3(30, 0, 0), Vector3(0.9, 1.0, 1.15))
	MeshKit.part(head, MeshKit.blob(0.1, 0.8, 0.25, 3, 10), wm, Vector3(0, 0.1, 0.02))
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(head, MeshKit.blob(0.06, 0.4, 0.0, 0, 8), MeshKit.mat(skin), Vector3(sx * 0.13, 0.04, 0.02), Vector3(0, 0, sx * 70.0), Vector3(1.0, 1.0, 0.6))
	_eyes(head, 0.06, 0.03, -0.13, 0.02)
	for i in 4:
		_leg(body, i, Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.13, 0.44, -0.24 if i < 2 else 0.24), 0.045, 0.44, skin, Color(0.15, 0.12, 0.1))
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0.66, 0.44)
	body.add_child(tail)
	MeshKit.part(tail, MeshKit.blob(0.08, 1.2, 0.2, 5, 8), wm, Vector3(0, -0.04, 0.02))
	return root


## Vaca: cuerpo grande con manchas, morro rosado, cuernos y ubre.
static func cow(seed_value := 0) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 23
	var base := Color(0.96, 0.95, 0.92) if r.randf() < 0.6 else Color(0.62, 0.42, 0.28)
	var spot := Color(0.15, 0.13, 0.13) if base.v > 0.8 else Color(0.95, 0.93, 0.9)
	MeshKit.part(body, MeshKit.capsule(0.42, 1.55), MeshKit.surface_mat(base, "cloth", 0.08), Vector3(0, 1.0, 0), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.92))
	for k in 6:
		var a := r.randf_range(-1.6, 1.6)
		var z := r.randf_range(-0.5, 0.5)
		MeshKit.part(body, MeshKit.blob(r.randf_range(0.18, 0.3), 0.5, 0.3, k, 12), MeshKit.mat(spot),
			Vector3(sin(a) * 0.4, 1.0 + cos(a) * 0.38, z), Vector3(0, 0, -rad_to_deg(a)), Vector3(1.0, 0.25, 1.0))
	MeshKit.part(body, MeshKit.blob(0.14, 0.7, 0.0, 0, 10), MeshKit.mat(Color(1.0, 0.75, 0.75)), Vector3(0, 0.62, 0.35))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.22, -0.88)
	body.add_child(head)
	MeshKit.part(head, MeshKit.blob(0.24, 1.15, 0.0, 0, 12), MeshKit.mat(base), Vector3(0, 0, -0.04), Vector3(25, 0, 0), Vector3(0.85, 1.0, 1.0))
	MeshKit.part(head, MeshKit.blob(0.16, 0.75, 0.0, 0, 12), MeshKit.mat(Color(1.0, 0.76, 0.72)), Vector3(0, -0.18, -0.22), Vector3.ZERO, Vector3(1.1, 1.0, 0.85))
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(head, MeshKit.sphere(0.025, 8), MeshKit.mat(Color(0.35, 0.2, 0.2)), Vector3(sx * 0.06, -0.17, -0.37))
		MeshKit.part(head, MeshKit.cone(0.04, 0.16, 8), MeshKit.mat(Color(0.95, 0.9, 0.78)), Vector3(sx * 0.17, 0.2, 0.04), Vector3(0, 0, -sx * 60.0))
		MeshKit.part(head, MeshKit.blob(0.08, 0.5, 0.0, 0, 8), MeshKit.mat(base.darkened(0.1)), Vector3(sx * 0.24, 0.1, 0.05), Vector3(0, 0, sx * 80.0), Vector3(1.0, 1.0, 0.5))
	_eyes(head, 0.13, 0.08, -0.17, 0.03)
	for i in 4:
		_leg(body, i, Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.26, 0.72, -0.6 if i < 2 else 0.6), 0.08, 0.72, base, Color(0.18, 0.14, 0.12))
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 1.3, 0.95)
	body.add_child(tail)
	MeshKit.part(tail, MeshKit.cylinder(0.02, 0.03, 0.7, 6), MeshKit.mat(base), Vector3(0, -0.35, 0.05))
	MeshKit.part(tail, MeshKit.blob(0.06, 1.4, 0.2, 2, 8), MeshKit.mat(spot), Vector3(0, -0.72, 0.05))
	return root


## Gallina: cuerpo redondo, cresta roja, pico y cola de plumas.
static func chicken(seed_value := 0) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var cols := [Color(0.97, 0.95, 0.9), Color(0.75, 0.45, 0.25), Color(0.35, 0.3, 0.28)]
	var col: Color = cols[seed_value % cols.size()]
	var m := MeshKit.surface_mat(col, "cloth", 0.1)
	MeshKit.part(body, MeshKit.blob(0.15, 0.9, 0.0, 0, 12), m, Vector3(0, 0.22, 0.02), Vector3.ZERO, Vector3(0.85, 1.0, 1.15))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.38, -0.12)
	body.add_child(head)
	MeshKit.part(head, MeshKit.blob(0.075, 1.05, 0.0, 0, 10), m, Vector3.ZERO)
	MeshKit.part(head, MeshKit.cone(0.025, 0.06, 8), MeshKit.mat(Color(1.0, 0.7, 0.2)), Vector3(0, -0.01, -0.09), Vector3(-90, 0, 0))
	for k in 3:
		MeshKit.part(head, MeshKit.sphere(0.022, 8), MeshKit.mat(Color(0.9, 0.15, 0.15)), Vector3(0, 0.075, -0.03 + k * 0.03))
	MeshKit.part(head, MeshKit.blob(0.022, 1.4, 0.0, 0, 8), MeshKit.mat(Color(0.9, 0.15, 0.15)), Vector3(0, -0.06, -0.06))
	_eyes(head, 0.04, 0.02, -0.05, 0.014)
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0.3, 0.16)
	body.add_child(tail)
	for k in 3:
		MeshKit.part(tail, MeshKit.blob(0.06, 1.6, 0.0, 0, 8), MeshKit.mat(col.darkened(0.12 * k)), Vector3((k - 1) * 0.04, 0.06, 0.03), Vector3(-35, 0, (k - 1) * 18.0), Vector3(0.5, 1.0, 1.0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(body, MeshKit.blob(0.08, 1.3, 0.0, 0, 8), MeshKit.mat(col.darkened(0.06)), Vector3(sx * 0.12, 0.24, 0.03), Vector3(10, 0, 0), Vector3(0.35, 0.8, 1.0))
	for i in 2:
		var leg := Node3D.new()
		leg.name = "Leg%d" % i
		leg.position = Vector3((-1.0 if i == 0 else 1.0) * 0.05, 0.1, 0.02)
		body.add_child(leg)
		MeshKit.part(leg, MeshKit.cylinder(0.01, 0.01, 0.1, 5), MeshKit.mat(Color(1.0, 0.7, 0.2)), Vector3(0, -0.05, 0))
		MeshKit.part(leg, MeshKit.rounded_box(Vector3(0.05, 0.012, 0.06), 0.005, 1), MeshKit.mat(Color(1.0, 0.7, 0.2)), Vector3(0, -0.1, -0.015))
	return root


## Burro: cuerpo gris, orejas largas, crin oscura y morro claro.
static func donkey() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var grey := Color(0.55, 0.52, 0.5)
	MeshKit.part(body, MeshKit.capsule(0.3, 1.1), MeshKit.surface_mat(grey, "cloth", 0.08), Vector3(0, 0.85, 0), Vector3(90, 0, 0))
	MeshKit.part(body, MeshKit.blob(0.22, 0.6, 0.0, 0, 10), MeshKit.mat(Color(0.85, 0.82, 0.78)), Vector3(0, 0.66, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.8))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.22, -0.58)
	body.add_child(head)
	MeshKit.part(head, MeshKit.capsule(0.13, 0.5), MeshKit.mat(grey), Vector3(0, -0.02, -0.12), Vector3(-60, 0, 0))
	MeshKit.part(head, MeshKit.blob(0.12, 0.85, 0.0, 0, 10), MeshKit.mat(Color(0.86, 0.84, 0.8)), Vector3(0, -0.14, -0.32))
	for sx: float in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.name = "Ear%d" % (0 if sx < 0 else 1)
		ear.position = Vector3(sx * 0.07, 0.16, 0.0)
		head.add_child(ear)
		MeshKit.part(ear, MeshKit.blob(0.05, 3.2, 0.0, 0, 8), MeshKit.mat(grey), Vector3(sx * 0.03, 0.14, 0), Vector3(0, 0, -sx * 18.0), Vector3(1.0, 1.0, 0.55))
	_eyes(head, 0.1, 0.05, -0.12, 0.025)
	for k in 6:
		MeshKit.part(body, MeshKit.blob(0.05, 1.4, 0.2, k, 8), MeshKit.mat(Color(0.25, 0.22, 0.2)), Vector3(0, 1.18 - k * 0.02, -0.5 + k * 0.08))
	for i in 4:
		_leg(body, i, Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.18, 0.62, -0.42 if i < 2 else 0.42), 0.06, 0.62, grey, Color(0.2, 0.18, 0.16))
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 1.0, 0.62)
	body.add_child(tail)
	MeshKit.part(tail, MeshKit.cylinder(0.015, 0.025, 0.5, 6), MeshKit.mat(grey), Vector3(0, -0.25, 0.04))
	MeshKit.part(tail, MeshKit.blob(0.05, 1.6, 0.2, 2, 8), MeshKit.mat(Color(0.25, 0.22, 0.2)), Vector3(0, -0.52, 0.04))
	return root


## Animación de paseo para cualquiera de estos modelos: patas, cabeza y cola.
## `phase` avanza al andar; `grazing` baja la cabeza a pastar; `t` es el tiempo.
static func animate(model: Node3D, phase: float, moving: bool, grazing: float, t: float) -> void:
	var body := model.get_node("Body") as Node3D
	var head := body.get_node("Head") as Node3D
	var s := sin(phase)
	var legs := 0
	for c in body.get_children():
		if c.name.begins_with("Leg"):
			var front := legs < 2
			var sign_ := 1.0 if (legs % 2 == 0) == front else -1.0
			(c as Node3D).rotation.x = s * 0.55 * sign_ if moving else lerpf((c as Node3D).rotation.x, 0.0, 0.2)
			legs += 1
	body.position.y = absf(s) * 0.03 if moving else 0.0
	head.rotation.x = lerpf(head.rotation.x, grazing * 0.9 + sin(t * 1.3) * 0.04, 0.1)
	var tail := body.get_node_or_null("Tail") as Node3D
	if tail:
		tail.rotation.z = sin(t * 3.0 + phase) * 0.35
