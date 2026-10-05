class_name Avatar
extends Node3D
## Personaje procedural (Lía y los vecinos) con animación por código.
## El modelo mira hacia -Z y su origen está en los pies.
## Quien lo usa pone `state` (idle, walk, jump, fall, glide, hook, climb, swim, talk, wave, sit,
## mantle, land, hold_up, cheer) y `speed` (m/s) cada fotograma.

var state := "idle"
var speed := 0.0
var climb_move := Vector2.ZERO
var lean := 0.0
## Avance de la voltereta (0 a 1) mientras state == "roll".
var roll_k := 0.0

var spec := {}
var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var scarf_tail: Node3D
var glider: Node3D
var hat_holder: Node3D
var eyes: Array[Node3D] = []
var pivot: Node3D
## Punto sobre la cabeza donde Lía sostiene lo que encuentra.
var hold_point: Node3D
var mouth_smile: Node3D
var mouth_open: Node3D
var brows: Array[Node3D] = []
## Codos y rodillas: "arm_l", "arm_r", "leg_l", "leg_r" -> articulación del medio.
var joints := {}
## Manos (0 = izquierda, 1 = derecha), para sujetar la cuerda.
var hands: Array[Node3D] = []
## Expresión forzada (vacía = según el estado): "happy", "surprised", "talk".
var mood := ""
## Animación de "estirar y aplastar" (1 = normal).
var _sq := 1.0
var _sq_v := 0.0

var _phase := 0.0
var _t := 0.0
var _blink := 2.0
var _ang := {}
var _tail_ang := Vector2.ZERO
var _last_pos := Vector3.ZERO
var _last_state := ""
var _state_t := 0.0

const DEFAULT := {
	"skin": Color(1.0, 0.82, 0.68),
	"hair": Color(0.42, 0.24, 0.16),
	"hair_style": "bob",
	"shirt": Color(0.35, 0.62, 0.9),
	"pants": Color(0.95, 0.9, 0.78),
	"shoes": Color(0.5, 0.33, 0.22),
	"scarf": Color(0.95, 0.35, 0.3),
	"hat": "none",
	"hat_color": Color(0.95, 0.85, 0.5),
	"beard": false,
	"glasses": false,
	"apron": null,
	"bag": false,
	"backpack": false,
	"height": 1.0,
	"girth": 1.0,
	"dress": true,
	"eye_color": Color(0.35, 0.22, 0.12),
}


func build(s: Dictionary) -> void:
	spec = DEFAULT.duplicate()
	spec.merge(s, true)
	for c in get_children():
		c.queue_free()
	eyes.clear()
	joints.clear()
	hands.clear()
	var g: float = spec["girth"]
	scale = Vector3.ONE * float(spec["height"])
	brows.clear()
	pivot = Node3D.new()
	add_child(pivot)
	hips = Node3D.new()
	hips.position = Vector3(0, 0.62, 0)
	pivot.add_child(hips)
	hold_point = Node3D.new()
	hold_point.position = Vector3(0, 2.12, -0.06)
	pivot.add_child(hold_point)
	torso = Node3D.new()
	hips.add_child(torso)
	var shirt: Color = spec["shirt"]
	var o := 0.022
	# Torso con faldón de túnica
	# Perfil redondeado: bajo acampanado (túnica) o recto, cintura y hombros curvos.
	var hem := 0.25 * g if spec["dress"] else 0.18 * g
	var prof := PackedVector2Array([
		Vector2(0.0, -0.16), Vector2(hem, -0.16), Vector2(lerpf(hem, 0.2 * g, 0.45), -0.07), Vector2(0.195 * g, 0.04),
		Vector2(0.178 * g, 0.17), Vector2(0.172 * g, 0.29), Vector2(0.158 * g, 0.38), Vector2(0.125 * g, 0.445),
		Vector2(0.075, 0.485), Vector2(0.0, 0.5)])
	MeshKit.part(torso, MeshKit.lathe(prof, 18), MeshKit.mat(shirt, o), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.84))
	# Dobladillo un poco más oscuro.
	if spec["dress"]:
		MeshKit.part(torso, MeshKit.lathe(PackedVector2Array([Vector2(hem * 1.01, -0.165), Vector2(hem * 0.985, -0.125), Vector2(0.0, -0.125)]), 18), MeshKit.mat(shirt.darkened(0.15), 0.0), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.84))
	MeshKit.part(torso, MeshKit.torus(0.15 * g, 0.2 * g), MeshKit.mat(Color(0.45, 0.3, 0.2), 0.0), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.7, 0.85))
	if spec["apron"] != null:
		MeshKit.part(torso, MeshKit.rounded_box(Vector3(0.28 * g, 0.42, 0.04), 0.02, 1), MeshKit.mat(spec["apron"], o), Vector3(0, 0.08, -0.17 * g))
	if spec["bag"]:
		MeshKit.part(torso, MeshKit.rounded_box(Vector3(0.28, 0.24, 0.12), 0.04, 2), MeshKit.mat(Color(0.55, 0.35, 0.2), o), Vector3(0.2 * g, -0.02, 0.05))
		MeshKit.part(torso, MeshKit.rounded_box(Vector3(0.04, 0.62, 0.04), 0.01, 1), MeshKit.mat(Color(0.45, 0.28, 0.16), 0.0), Vector3(0.02, 0.2, -0.02), Vector3(0, 0, 38))
	if spec["backpack"]:
		MeshKit.part(torso, MeshKit.capsule(0.09, 0.46), MeshKit.mat(Color(0.95, 0.9, 0.75), o), Vector3(0, 0.3, 0.17), Vector3(0, 0, 90))
		MeshKit.part(torso, MeshKit.rounded_box(Vector3(0.24, 0.26, 0.1), 0.04, 2), MeshKit.mat(Color(0.6, 0.42, 0.28), o), Vector3(0, 0.15, 0.16))
	# Cabeza
	head = Node3D.new()
	head.position = Vector3(0, 0.5, 0)
	torso.add_child(head)
	var skin: Color = spec["skin"]
	MeshKit.part(head, MeshKit.capsule(0.06, 0.16), MeshKit.mat(skin, 0.0), Vector3(0, 0.02, 0))
	MeshKit.part(head, MeshKit.blob(0.25, 0.96, 0.0, 0, 14), MeshKit.mat(skin, o), Vector3(0, 0.25, 0))
	MeshKit.part(head, MeshKit.sphere(0.04, 6), MeshKit.mat(skin.darkened(0.08), 0.0), Vector3(0, 0.22, -0.25))
	var iris_col: Color = spec["eye_color"]
	var brow_col: Color = (spec["hair"] as Color).darkened(0.25)
	for sx: float in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(sx * 0.088, 0.275, -0.205)
		eye.rotation_degrees = Vector3(6, sx * 14.0, 0)
		head.add_child(eye)
		eyes.append(eye)
		MeshKit.part(eye, MeshKit.sphere(0.058, 10), MeshKit.mat(Color(1, 1, 1), 0.006, 0.0, Color(0, 0, 0, 0), 0.0), Vector3.ZERO, Vector3.ZERO, Vector3(0.82, 1.18, 0.42))
		MeshKit.part(eye, MeshKit.sphere(0.04, 10), MeshKit.mat(iris_col, 0.0, 0.0, Color(0, 0, 0, 0), 0.0), Vector3(0, -0.006, -0.016), Vector3.ZERO, Vector3(0.85, 1.12, 0.4))
		MeshKit.part(eye, MeshKit.sphere(0.022, 8), MeshKit.mat(Color(0.06, 0.05, 0.08), 0.0, 0.0, Color(0, 0, 0, 0), 0.0), Vector3(0, -0.006, -0.024), Vector3.ZERO, Vector3(0.9, 1.1, 0.4))
		MeshKit.part(eye, MeshKit.sphere(0.013, 5), MeshKit.unshaded(Color.WHITE), Vector3(sx * -0.01 + 0.012, 0.022, -0.03))
		var brow := MeshKit.part(head, MeshKit.capsule(0.011, 0.075), MeshKit.mat(brow_col, 0.0), Vector3(sx * 0.09, 0.365, -0.213), Vector3(0, 0, 90.0 - sx * 8.0))
		brows.append(brow)
		MeshKit.part(head, MeshKit.sphere(0.045, 6), MeshKit.mat(Color(1.0, 0.6, 0.6), 0.0), Vector3(sx * 0.15, 0.19, -0.19), Vector3.ZERO, Vector3(1, 0.6, 0.4))
	var mouth := Node3D.new()
	mouth.position = Vector3(0, 0.155, -0.236)
	head.add_child(mouth)
	mouth_smile = Node3D.new()
	mouth.add_child(mouth_smile)
	var lip := MeshKit.mat(Color(0.45, 0.18, 0.15), 0.0)
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(mouth_smile, MeshKit.capsule(0.008, 0.042), lip, Vector3(sx * 0.016, 0.004, 0), Vector3(0, 0, 90.0 + sx * 22.0))
	mouth_open = Node3D.new()
	mouth.add_child(mouth_open)
	MeshKit.part(mouth_open, MeshKit.sphere(0.03, 8), MeshKit.mat(Color(0.35, 0.1, 0.1), 0.0), Vector3(0, 0, 0.004), Vector3.ZERO, Vector3(1.1, 0.85, 0.35))
	MeshKit.part(mouth_open, MeshKit.sphere(0.018, 6), MeshKit.mat(Color(1.0, 0.55, 0.55), 0.0), Vector3(0, -0.012, -0.004), Vector3.ZERO, Vector3(1.2, 0.6, 0.3))
	mouth_open.visible = false
	if spec["glasses"]:
		for sx: float in [-1.0, 1.0]:
			MeshKit.part(head, MeshKit.torus(0.05, 0.065), MeshKit.mat(Color(0.2, 0.2, 0.22), 0.0), Vector3(sx * 0.085, 0.27, -0.245), Vector3(90, 0, 0))
	if spec["beard"]:
		MeshKit.part(head, MeshKit.blob(0.17, 0.9, 0.15, 3, 8), MeshKit.mat(spec["hair"], o), Vector3(0, 0.1, -0.15), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
	_build_hair(head, o)
	hat_holder = Node3D.new()
	hat_holder.position = Vector3(0, 0.25, 0)
	head.add_child(hat_holder)
	set_hat(spec["hat"], spec["hat_color"])
	# Brazos
	arm_l = _limb(torso, Vector3(-0.2 * g, 0.38, 0), 0.055, 0.42, shirt, skin, true, "arm_l")
	arm_r = _limb(torso, Vector3(0.2 * g, 0.38, 0), 0.055, 0.42, shirt, skin, true, "arm_r")
	# Piernas
	leg_l = _limb(hips, Vector3(-0.09 * g, -0.06, 0), 0.07, 0.5, spec["pants"], spec["shoes"], false, "leg_l")
	leg_r = _limb(hips, Vector3(0.09 * g, -0.06, 0), 0.07, 0.5, spec["pants"], spec["shoes"], false, "leg_r")
	# Bufanda con cola que ondea
	if spec["scarf"] != null:
		var sc: Color = spec["scarf"]
		MeshKit.part(torso, MeshKit.torus(0.07, 0.15), MeshKit.mat(sc, o), Vector3(0, 0.46, 0), Vector3.ZERO, Vector3(1, 1.6, 1))
		scarf_tail = Node3D.new()
		scarf_tail.position = Vector3(0.06, 0.46, 0.1)
		torso.add_child(scarf_tail)
		var seg := MeshKit.rounded_box(Vector3(0.1, 0.03, 0.22), 0.012, 1)
		MeshKit.part(scarf_tail, seg, MeshKit.mat(sc, o), Vector3(0, 0, 0.11))
		var tip := Node3D.new()
		tip.name = "Tip"
		tip.position = Vector3(0, 0, 0.21)
		scarf_tail.add_child(tip)
		MeshKit.part(tip, seg, MeshKit.mat(sc.darkened(0.08), o), Vector3(0, 0, 0.1))
	# Paravela (oculta salvo al planear)
	glider = Node3D.new()
	glider.position = Vector3(0, 1.72, 0.0)
	glider.visible = false
	glider.scale = Vector3.ONE * 1.3
	add_child(glider)
	_build_glider(Color(0.98, 0.95, 0.85), Color(0.95, 0.4, 0.35))
	for k in POSE_KEYS:
		_ang[k] = 0.0


func _build_hair(h: Node3D, o: float) -> void:
	var hc: Color = spec["hair"]
	var m := MeshKit.mat(hc, o)
	match spec["hair_style"]:
		"bob":
			MeshKit.part(h, MeshKit.blob(0.275, 0.95, 0.06, 4, 12), m, Vector3(0, 0.3, 0.035))
			MeshKit.part(h, MeshKit.blob(0.2, 0.55, 0.1, 5, 9), m, Vector3(0, 0.44, -0.12), Vector3(-20, 0, 0))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(h, MeshKit.blob(0.12, 1.4, 0.1, 6, 8), m, Vector3(sx * 0.2, 0.18, 0.02))
		"short":
			MeshKit.part(h, MeshKit.blob(0.265, 0.85, 0.12, 7, 12), m, Vector3(0, 0.33, 0.04))
		"bun":
			MeshKit.part(h, MeshKit.blob(0.268, 0.9, 0.04, 8, 12), m, Vector3(0, 0.31, 0.04))
			MeshKit.part(h, MeshKit.sphere(0.12, 8), m, Vector3(0, 0.5, 0.15))
		"long":
			MeshKit.part(h, MeshKit.blob(0.275, 0.95, 0.06, 9, 12), m, Vector3(0, 0.3, 0.04))
			MeshKit.part(h, MeshKit.blob(0.22, 1.6, 0.08, 10, 10), m, Vector3(0, 0.08, 0.13))
		"pony":
			MeshKit.part(h, MeshKit.blob(0.268, 0.9, 0.04, 11, 12), m, Vector3(0, 0.31, 0.04))
			MeshKit.part(h, MeshKit.blob(0.09, 2.2, 0.1, 12, 8), m, Vector3(0, 0.22, 0.3), Vector3(30, 0, 0))
		"bald":
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(h, MeshKit.blob(0.1, 1.2, 0.15, 13, 8), m, Vector3(sx * 0.22, 0.24, 0.06))
		"pigtails":
			MeshKit.part(h, MeshKit.blob(0.268, 0.9, 0.05, 14, 12), m, Vector3(0, 0.31, 0.04))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(h, MeshKit.blob(0.1, 1.5, 0.1, 15, 8), m, Vector3(sx * 0.28, 0.24, 0.08), Vector3(0, 0, sx * 25))


func set_hat(kind: String, color: Color) -> void:
	if hat_holder == null:
		return
	for c in hat_holder.get_children():
		c.queue_free()
	var o := 0.02
	match kind:
		"straw":
			MeshKit.part(hat_holder, MeshKit.cylinder(0.42, 0.42, 0.03, 18), MeshKit.mat(color, o), Vector3(0, 0.13, 0))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.2, 0.24, 0.18, 14), MeshKit.mat(color, o), Vector3(0, 0.22, 0))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.245, 0.245, 0.05, 14), MeshKit.mat(Color(0.9, 0.35, 0.3), 0.0), Vector3(0, 0.16, 0))
		"postman":
			MeshKit.part(hat_holder, MeshKit.cylinder(0.25, 0.26, 0.16, 14), MeshKit.mat(color, o), Vector3(0, 0.2, 0.02))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.2, 0.2, 0.02, 12), MeshKit.mat(color.darkened(0.3), o), Vector3(0, 0.12, -0.14), Vector3(-10, 0, 0), Vector3(1, 1, 0.6))
			MeshKit.part(hat_holder, MeshKit.sphere(0.04, 6), MeshKit.mat(Color(1.0, 0.82, 0.3), 0.0), Vector3(0, 0.22, -0.24))
		"beret":
			MeshKit.part(hat_holder, MeshKit.blob(0.26, 0.4, 0.05, 2, 10), MeshKit.mat(color, o), Vector3(0.04, 0.19, 0.02), Vector3(0, 0, -10))
		"bandana":
			MeshKit.part(hat_holder, MeshKit.blob(0.275, 0.55, 0.0, 3, 10), MeshKit.mat(color, o), Vector3(0, 0.1, 0.03))
		"flowers":
			MeshKit.part(hat_holder, MeshKit.torus(0.2, 0.26), MeshKit.mat(Color(0.35, 0.65, 0.3), o), Vector3(0, 0.12, 0.02), Vector3(-8, 0, 0))
			var cols := [Color(1, 0.5, 0.6), Color(1, 0.9, 0.35), Color(1, 1, 1), Color(0.7, 0.6, 1)]
			for i in 8:
				var a := TAU * i / 8.0
				MeshKit.part(hat_holder, MeshKit.sphere(0.055, 6), MeshKit.mat(cols[i % 4], 0.0), Vector3(cos(a) * 0.23, 0.14, sin(a) * 0.23))
		"miner":
			MeshKit.part(hat_holder, MeshKit.blob(0.28, 0.65, 0.0, 4, 10), MeshKit.mat(color, o), Vector3(0, 0.12, 0.02))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.06, 0.07, 0.06, 10), MeshKit.mat(Color(1, 0.95, 0.7), 0.0, 1.5), Vector3(0, 0.22, -0.24), Vector3(80, 0, 0))
		"fisher":
			MeshKit.part(hat_holder, MeshKit.lathe(PackedVector2Array([Vector2(0.38, -0.02), Vector2(0.3, 0.04), Vector2(0.22, 0.2), Vector2(0.0, 0.24)]), 14), MeshKit.mat(color, o), Vector3(0, 0.08, 0.02))
		"cap":
			MeshKit.part(hat_holder, MeshKit.blob(0.275, 0.62, 0.0, 0, 12), MeshKit.mat(color, o), Vector3(0, 0.1, 0.02))
			MeshKit.part(hat_holder, MeshKit.rounded_box(Vector3(0.36, 0.035, 0.24), 0.015, 2), MeshKit.mat(color.darkened(0.15), o), Vector3(0, 0.06, -0.3), Vector3(-8, 0, 0))
			MeshKit.part(hat_holder, MeshKit.sphere(0.035, 6), MeshKit.mat(color.lightened(0.4), 0.0), Vector3(0, 0.27, 0.02))
		"beanie":
			MeshKit.part(hat_holder, MeshKit.blob(0.285, 0.78, 0.0, 0, 12), MeshKit.mat(color, o), Vector3(0, 0.1, 0.03))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.29, 0.295, 0.09, 16), MeshKit.mat(color.darkened(0.12), o), Vector3(0, 0.02, 0.03))
			MeshKit.part(hat_holder, MeshKit.blob(0.075, 1.0, 0.25, 3, 8), MeshKit.mat(Color(0.98, 0.95, 0.9), o), Vector3(0, 0.33, 0.03))
		"sailor":
			MeshKit.part(hat_holder, MeshKit.cylinder(0.25, 0.27, 0.14, 16), MeshKit.mat(color, o), Vector3(0, 0.12, 0.02))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.275, 0.275, 0.05, 16), MeshKit.mat(Color(0.18, 0.25, 0.45), 0.0), Vector3(0, 0.08, 0.02))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.3, 0.27, 0.03, 16), MeshKit.mat(color.darkened(0.04), o), Vector3(0, 0.205, 0.02))
		"crown":
			MeshKit.part(hat_holder, MeshKit.cylinder(0.17, 0.17, 0.1, 10), MeshKit.mat(Color(1.0, 0.82, 0.3), o, 0.4), Vector3(0, 0.25, 0))
			for i in 5:
				var a := TAU * i / 5.0
				MeshKit.part(hat_holder, MeshKit.cone(0.045, 0.12, 5), MeshKit.mat(Color(1.0, 0.82, 0.3), 0.0, 0.4), Vector3(cos(a) * 0.15, 0.34, sin(a) * 0.15))


func set_scarf_color(c: Color) -> void:
	spec["scarf"] = c
	build(spec)


func _build_glider(c1: Color, c2: Color) -> void:
	for c in glider.get_children():
		c.queue_free()
	var segs := 7
	for i in segs:
		var a := lerpf(-1.1, 1.1, (i + 0.5) / segs)
		var pos := Vector3(sin(a) * 1.3, cos(a) * 0.5 + 0.25, 0.05)
		MeshKit.part(glider, MeshKit.rounded_box(Vector3(0.4, 0.05, 0.95), 0.02, 1), MeshKit.mat(c1 if i % 2 == 0 else c2, 0.02), pos, Vector3(0, 0, -rad_to_deg(a)))
	var line := MeshKit.mat(Color(0.4, 0.35, 0.3), 0.0)
	for sx: float in [-1.0, 1.0]:
		var from := Vector3(sx * 0.18, -0.15, -0.05)
		var to := Vector3(sx * 1.15, 0.45, 0.05)
		var mid := (from + to) * 0.5
		var l := MeshKit.part(glider, MeshKit.cylinder(0.008, 0.008, from.distance_to(to), 4), line, mid)
		l.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	MeshKit.part(glider, MeshKit.cylinder(0.02, 0.02, 0.6, 6), MeshKit.mat(Color(0.5, 0.36, 0.25), 0.0), Vector3(0, -0.15, -0.05), Vector3(0, 0, 90))


func set_glider_colors(c1: Color, c2: Color) -> void:
	_build_glider(c1, c2)


## Extremidad de dos tramos (hombro-codo-mano o cadera-rodilla-pie). Devuelve el pivote del
## hombro/cadera; la articulación del medio queda en `joints[name]` y la mano en `hands`.
func _limb(parent: Node3D, at: Vector3, radius: float, length: float, color: Color, end_color: Color, is_arm: bool, limb_name := "") -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	var r := radius
	var half := length * 0.5
	var joint := Node3D.new()
	joint.name = "Joint"
	joint.position = Vector3(0, -half, 0)
	pivot.add_child(joint)
	joints[limb_name] = joint
	var cloth := MeshKit.mat(color, 0.02)
	if is_arm:
		# Manga: hombro redondo y algo más ancha arriba; antebrazo con puño y mano de manopla.
		var up := PackedVector2Array([Vector2(0.0, -half - 0.02), Vector2(r * 0.94, -half), Vector2(r * 1.02, -half * 0.5),
			Vector2(r * 1.05, -0.08), Vector2(r * 0.95, 0.0), Vector2(r * 0.6, 0.04), Vector2(0.0, 0.05)])
		MeshKit.part(pivot, MeshKit.lathe(up, 12), cloth, Vector3.ZERO)
		MeshKit.part(pivot, MeshKit.sphere(r * 1.3, 10), cloth, Vector3(0, -0.01, 0), Vector3.ZERO, Vector3(1.0, 0.9, 1.0))
		MeshKit.part(joint, MeshKit.sphere(r * 0.93, 10), cloth, Vector3.ZERO)
		var low := PackedVector2Array([Vector2(0.0, -half + 0.05), Vector2(r * 0.82, -half + 0.06), Vector2(r * 0.9, -half * 0.5),
			Vector2(r * 0.92, 0.0), Vector2(0.0, 0.02)])
		MeshKit.part(joint, MeshKit.lathe(low, 12), cloth, Vector3.ZERO)
		MeshKit.part(joint, MeshKit.cylinder(r * 0.98, r * 1.02, 0.05, 12), MeshKit.mat(color.darkened(0.15), 0.015), Vector3(0, -half + 0.07, 0))
		var inward := -signf(at.x) if absf(at.x) > 0.001 else 1.0
		var hand_m := MeshKit.mat(end_color, 0.02)
		var hand := Node3D.new()
		hand.position = Vector3(0, -half - 0.02, 0)
		joint.add_child(hand)
		hands.append(hand)
		MeshKit.part(hand, MeshKit.blob(r * 1.2, 1.0, 0.0, 0, 10), hand_m, Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 1.12, 0.95))
		MeshKit.part(hand, MeshKit.sphere(r * 0.5, 8), hand_m, Vector3(inward * r * 0.75, 0.02, -r * 0.45), Vector3.ZERO, Vector3(1.0, 1.3, 1.0))
	else:
		MeshKit.part(pivot, MeshKit.capsule(r, half + r * 1.2), cloth, Vector3(0, -half * 0.5, 0))
		MeshKit.part(joint, MeshKit.sphere(r * 0.98, 10), cloth, Vector3.ZERO)
		MeshKit.part(joint, MeshKit.capsule(r * 0.95, half + r), cloth, Vector3(0, -half * 0.5 + r * 0.3, 0))
		MeshKit.part(joint, MeshKit.cylinder(r * 1.12, r * 1.15, 0.05, 12), MeshKit.mat(color.darkened(0.12), 0.015), Vector3(0, -half + 0.12, 0))
		# Zapato redondeado con suela más oscura.
		MeshKit.part(joint, MeshKit.blob(r * 1.25, 0.7, 0.0, 0, 10), MeshKit.mat(end_color, 0.02), Vector3(0, -half + 0.05, -r * 0.55), Vector3.ZERO, Vector3(0.95, 1.0, 1.45))
		MeshKit.part(joint, MeshKit.rounded_box(Vector3(r * 2.3, 0.04, r * 3.5), 0.018, 1), MeshKit.mat(end_color.darkened(0.35), 0.015), Vector3(0, -half + 0.0, -r * 0.55))
	return pivot


## Posición en el mundo de la mano izquierda (0) o derecha (1).
func hand_position(side: int) -> Vector3:
	if side < hands.size() and is_instance_valid(hands[side]):
		return hands[side].global_position
	return global_position + Vector3(0, 1.4, 0)


# --- Animación --------------------------------------------------------------------
# Ángulos (radianes) que se interpolan cada fotograma hacia su objetivo:
# arm_* / leg_*: hombro y cadera hacia delante (+) o atrás (-); arm_*z: abrir/cerrar brazos;
# elbow_*: flexión del codo (+); knee_*: flexión de la rodilla (-, la pierna se dobla hacia atrás);
# hips_x / torso_x: inclinación (+ hacia atrás); torso_y: giro del tronco; head_*: cabeza.

const POSE_KEYS := ["arm_l", "arm_r", "leg_l", "leg_r", "hips_y", "hips_x", "torso_x", "torso_y", "head_x", "head_y",
	"arm_lz", "arm_rz", "elbow_l", "elbow_r", "knee_l", "knee_r"]


func _process(delta: float) -> void:
	if hips == null:
		return
	_t += delta
	if state != _last_state:
		_last_state = state
		_state_t = 0.0
	_state_t += delta
	var sp := clampf(speed, 0.0, 12.0)
	var run := clampf(sp / 7.0, 0.0, 1.0)
	var breath := sin(_t * 1.9)
	var t := {"arm_l": 0.06, "arm_r": 0.06, "leg_l": 0.0, "leg_r": 0.0, "hips_y": 0.0, "hips_x": 0.0,
		"torso_x": breath * 0.012, "torso_y": 0.0, "head_x": 0.0, "head_y": 0.0, "arm_lz": -0.17, "arm_rz": 0.17,
		"elbow_l": 0.14, "elbow_r": 0.14, "knee_l": -0.04, "knee_r": -0.04}
	var rate := 12.0
	glider.visible = state == "glide"
	match state:
		"idle", "talk":
			# Respira, pasa el peso de una pierna a otra y mira alrededor.
			var shift := sin(_t * 0.45)
			t["hips_y"] = breath * 0.006 - absf(shift) * 0.01
			t["arm_l"] = 0.05 + breath * 0.02
			t["arm_r"] = 0.05 - breath * 0.02
			t["knee_l"] = -0.04 - maxf(shift, 0.0) * 0.18
			t["knee_r"] = -0.04 - maxf(-shift, 0.0) * 0.18
			t["head_y"] = sin(_t * 0.6) * 0.15
			t["head_x"] = sin(_t * 0.37) * 0.05
			if state == "talk":
				t["arm_r"] = 0.55 + sin(_t * 5.0) * 0.2
				t["elbow_r"] = 0.9 + sin(_t * 5.0) * 0.25
				t["arm_rz"] = 0.3
				t["head_x"] = sin(_t * 7.0) * 0.06
		"hold_up":
			var hb := sin(_t * 2.5)
			t["arm_l"] = 3.0
			t["arm_r"] = 3.0
			t["arm_lz"] = 0.3
			t["arm_rz"] = -0.3
			t["elbow_l"] = 0.25
			t["elbow_r"] = 0.25
			t["head_x"] = -0.28
			t["hips_y"] = 0.02 + hb * 0.01
			t["leg_l"] = 0.05
			t["leg_r"] = -0.05
			rate = 9.0
		"cheer":
			var cb := absf(sin(_t * 6.0))
			t["arm_l"] = 2.8
			t["arm_r"] = 2.8
			t["arm_lz"] = -0.5
			t["arm_rz"] = 0.5
			t["elbow_l"] = 0.3
			t["elbow_r"] = 0.3
			t["hips_y"] = cb * 0.06
			t["knee_l"] = -0.5 * (1.0 - cb)
			t["knee_r"] = -0.5 * (1.0 - cb)
			t["head_x"] = -0.2
		"wave":
			t["arm_r"] = 2.5
			t["arm_rz"] = 0.35
			t["elbow_r"] = 0.6 + sin(_t * 9.0) * 0.4
			t["head_x"] = -0.1
		"sit":
			var swing := sin(_t * 1.4)
			t["leg_l"] = 1.45
			t["leg_r"] = 1.45
			t["knee_l"] = -1.35 + swing * 0.18
			t["knee_r"] = -1.35 - swing * 0.18
			t["hips_y"] = -0.24
			t["torso_x"] = 0.06 + breath * 0.012
			t["head_y"] = sin(_t * 0.35) * 0.4
			t["arm_l"] = 0.4
			t["arm_r"] = 0.4
			t["elbow_l"] = 0.7
			t["elbow_r"] = 0.7
		"walk":
			_phase += delta * (4.0 + sp * 1.05)
			var s := sin(_phase)
			var c := cos(_phase)
			var amp := lerpf(0.42, 0.9, run)
			t["leg_l"] = s * amp
			t["leg_r"] = -s * amp
			# La rodilla se dobla mientras la pierna avanza por el aire.
			var lift := lerpf(0.55, 1.35, run)
			t["knee_l"] = -0.08 - maxf(c, 0.0) * lift
			t["knee_r"] = -0.08 - maxf(-c, 0.0) * lift
			t["arm_l"] = -s * amp * 0.75 + 0.05
			t["arm_r"] = s * amp * 0.75 + 0.05
			t["elbow_l"] = lerpf(0.25, 1.2, run) + maxf(-s, 0.0) * 0.3
			t["elbow_r"] = lerpf(0.25, 1.2, run) + maxf(s, 0.0) * 0.3
			t["hips_y"] = absf(c) * lerpf(0.02, 0.07, run) - run * 0.03
			t["torso_x"] = -lerpf(0.04, 0.24, run) - lean * 0.15
			t["torso_y"] = s * lerpf(0.05, 0.14, run)
			t["head_y"] = -s * lerpf(0.03, 0.08, run)
			t["arm_lz"] = -0.15 - run * 0.1
			t["arm_rz"] = 0.15 + run * 0.1
			rate = 18.0
		"jump":
			# Encoge las piernas y estira los brazos hacia arriba.
			var k := clampf(_state_t / 0.25, 0.0, 1.0)
			t["leg_l"] = lerpf(0.2, 0.95, k)
			t["leg_r"] = -0.25
			t["knee_l"] = -lerpf(0.4, 1.3, k)
			t["knee_r"] = -0.55
			t["arm_l"] = 2.2
			t["arm_r"] = 1.1
			t["elbow_l"] = 0.35
			t["elbow_r"] = 0.9
			t["arm_lz"] = -0.3
			t["arm_rz"] = 0.4
			t["torso_x"] = -0.12
			rate = 16.0
		"fall":
			var f := sin(_t * 9.0) * 0.25
			t["leg_l"] = 0.4 + f
			t["leg_r"] = 0.1 - f
			t["knee_l"] = -0.6 - f
			t["knee_r"] = -0.35 + f
			t["arm_l"] = 2.3 + f
			t["arm_r"] = 2.3 - f
			t["elbow_l"] = 0.5
			t["elbow_r"] = 0.5
			t["arm_lz"] = -0.75
			t["arm_rz"] = 0.75
		"land":
			# Flexión de rodillas al caer: amortigua con todo el cuerpo.
			t["leg_l"] = 0.75
			t["leg_r"] = 0.75
			t["knee_l"] = -1.35
			t["knee_r"] = -1.35
			t["hips_y"] = -0.2
			t["torso_x"] = -0.45
			t["arm_l"] = 0.7
			t["arm_r"] = 0.7
			t["elbow_l"] = 0.7
			t["elbow_r"] = 0.7
			t["arm_lz"] = -0.4
			t["arm_rz"] = 0.4
			rate = 25.0
		"glide":
			var sw := sin(_t * 3.0)
			t["arm_l"] = 2.95
			t["arm_r"] = 2.95
			t["arm_lz"] = -0.22
			t["arm_rz"] = 0.22
			t["elbow_l"] = 0.2
			t["elbow_r"] = 0.2
			t["leg_l"] = -0.15 + sw * 0.18
			t["leg_r"] = 0.05 - sw * 0.18
			t["knee_l"] = -0.35 - sw * 0.15
			t["knee_r"] = -0.5 + sw * 0.15
			t["torso_x"] = -0.15
		"hook":
			# Lanzar el gancho: echa el brazo atrás y lo suelta hacia arriba.
			var throw := _state_t > 0.13
			t["arm_r"] = 3.0 if throw else -0.7
			t["elbow_r"] = 0.05 if throw else 1.5
			t["arm_rz"] = 0.1
			t["arm_l"] = 0.9
			t["elbow_l"] = 0.8
			t["torso_y"] = -0.2 if throw else 0.35
			t["torso_x"] = 0.15 if throw else -0.1
			t["head_x"] = -0.45
			t["knee_l"] = -0.35
			t["knee_r"] = -0.2
			rate = 22.0
		"climb":
			# Trepar por la cuerda: cuerpo echado atrás, pies contra la pared y mano sobre mano.
			_phase += delta * 6.5 * clampf(climb_move.length(), 0.0, 1.0)
			var c := sin(_phase)
			var idle_sway := sin(_t * 1.3) * 0.04
			t["hips_x"] = 0.38 + idle_sway
			t["torso_x"] = -0.2
			t["leg_l"] = 0.95 + c * 0.32
			t["leg_r"] = 0.95 - c * 0.32
			t["knee_l"] = -0.95 + c * 0.35
			t["knee_r"] = -0.95 - c * 0.35
			t["arm_l"] = 2.55 + c * 0.32
			t["arm_r"] = 2.55 - c * 0.32
			t["elbow_l"] = 0.45 - c * 0.35
			t["elbow_r"] = 0.45 + c * 0.35
			t["arm_lz"] = 0.2
			t["arm_rz"] = -0.2
			t["head_x"] = -0.4
			if climb_move.y > 0.9 and climb_move.length() > 0.95:
				# Impulso fuerte: tira de la cuerda con los dos brazos.
				t["arm_l"] = 1.7
				t["arm_r"] = 1.7
				t["elbow_l"] = 1.4
				t["elbow_r"] = 1.4
		"pickup", "kneel":
			# Agacharse: rodillas dobladas, tronco inclinado y manos hacia el suelo.
			var down := clampf(_state_t / 0.18, 0.0, 1.0)
			if state == "pickup" and _state_t > 0.3:
				down = 1.0 - clampf((_state_t - 0.3) / 0.15, 0.0, 1.0)
			t["leg_l"] = 1.25 * down
			t["leg_r"] = 0.55 * down
			t["knee_l"] = -1.9 * down
			t["knee_r"] = -2.1 * down
			t["hips_y"] = -0.3 * down
			t["torso_x"] = -0.55 * down
			t["head_x"] = 0.35 * down
			t["arm_l"] = 0.9 * down + 0.06
			t["arm_r"] = 1.05 * down + 0.06
			t["elbow_l"] = 0.25
			t["elbow_r"] = 0.25 + (sin(_t * 9.0) * 0.35 if state == "kneel" else 0.0)
			t["arm_rz"] = 0.17 - (0.25 if state == "kneel" else 0.0)
			rate = 20.0
		"fish_cast":
			# Lanzar la caña: el brazo se echa atrás por encima del hombro y sale hacia delante.
			var back := _state_t < 0.25
			t["arm_r"] = 2.9 if back else 1.25
			t["elbow_r"] = 1.3 if back else 0.25
			t["arm_l"] = 0.7
			t["elbow_l"] = 0.9
			t["arm_lz"] = 0.35
			t["torso_x"] = 0.18 if back else -0.22
			t["torso_y"] = 0.25 if back else -0.15
			t["leg_l"] = 0.3
			t["knee_l"] = -0.25
			t["leg_r"] = -0.2
			rate = 22.0
		"fish":
			t["arm_r"] = 1.0
			t["elbow_r"] = 0.75
			t["arm_rz"] = -0.05
			t["arm_l"] = 0.85
			t["elbow_l"] = 1.0
			t["arm_lz"] = 0.35
			t["torso_x"] = -0.05 + breath * 0.012
			t["leg_l"] = 0.2
			t["knee_l"] = -0.2
			t["head_x"] = 0.2
		"fish_reel":
			# Tira de la caña echándose atrás y da vueltas al carrete con la otra mano.
			t["arm_r"] = 1.15 + sin(_t * 9.0) * 0.12
			t["elbow_r"] = 0.9
			t["arm_l"] = 0.95 + sin(_t * 12.0) * 0.18
			t["elbow_l"] = 1.25 + cos(_t * 12.0) * 0.3
			t["arm_lz"] = 0.4
			t["torso_x"] = 0.25
			t["leg_l"] = 0.45
			t["knee_l"] = -0.55
			t["leg_r"] = -0.25
			t["knee_r"] = -0.3
			t["head_x"] = 0.15
			rate = 16.0
		"roll":
			# Voltereta: hecha un ovillo mientras el cuerpo gira (ver más abajo).
			t["leg_l"] = 1.7
			t["leg_r"] = 1.7
			t["knee_l"] = -2.2
			t["knee_r"] = -2.2
			t["arm_l"] = 1.3
			t["arm_r"] = 1.3
			t["elbow_l"] = 1.4
			t["elbow_r"] = 1.4
			t["torso_x"] = -0.7
			t["head_x"] = 0.4
			rate = 30.0
		"mantle":
			var mt := clampf(_state_t / 0.38, 0.0, 1.0)
			t["arm_l"] = lerpf(2.6, 0.6, mt)
			t["arm_r"] = lerpf(2.6, 0.6, mt)
			t["elbow_l"] = lerpf(0.4, 1.3, mt)
			t["elbow_r"] = lerpf(0.4, 1.3, mt)
			t["leg_l"] = 1.4
			t["knee_l"] = -1.8
			t["leg_r"] = 0.2
			t["knee_r"] = -0.6
			t["torso_x"] = -0.55
			rate = 20.0
		"swim":
			_phase += delta * (3.0 + sp * 0.9)
			var s2 := sin(_phase)
			t["hips_x"] = -1.15
			t["head_x"] = 0.85
			t["arm_l"] = 1.6 + s2 * 1.4
			t["arm_r"] = 1.6 - s2 * 1.4
			t["elbow_l"] = 0.25 + maxf(s2, 0.0) * 0.8
			t["elbow_r"] = 0.25 + maxf(-s2, 0.0) * 0.8
			t["arm_lz"] = -0.4
			t["arm_rz"] = 0.4
			t["leg_l"] = sin(_phase * 2.0) * 0.35 - 0.1
			t["leg_r"] = -sin(_phase * 2.0) * 0.35 - 0.1
			t["knee_l"] = -0.25 - maxf(sin(_phase * 2.0), 0.0) * 0.5
			t["knee_r"] = -0.25 - maxf(-sin(_phase * 2.0), 0.0) * 0.5
			t["hips_y"] = 0.25
	var k := clampf(rate * delta, 0.0, 1.0)
	for key in t:
		_ang[key] = lerpf(_ang[key], t[key], k)
	arm_l.rotation = Vector3(_ang["arm_l"], 0, _ang["arm_lz"])
	arm_r.rotation = Vector3(_ang["arm_r"], 0, _ang["arm_rz"])
	leg_l.rotation.x = _ang["leg_l"]
	leg_r.rotation.x = _ang["leg_r"]
	(joints["arm_l"] as Node3D).rotation.x = _ang["elbow_l"]
	(joints["arm_r"] as Node3D).rotation.x = _ang["elbow_r"]
	(joints["leg_l"] as Node3D).rotation.x = _ang["knee_l"]
	(joints["leg_r"] as Node3D).rotation.x = _ang["knee_r"]
	hips.position.y = 0.62 + _ang["hips_y"]
	hips.rotation.x = _ang["hips_x"]
	# Voltereta: todo el cuerpo gira hacia delante alrededor de su centro.
	if state == "roll":
		var c := 0.42
		pivot.rotation.x = -TAU * clampf(roll_k, 0.0, 1.0)
		pivot.position = Vector3(0, c, 0)
		hips.position.y -= c
	else:
		pivot.rotation.x = 0.0
		pivot.position = Vector3.ZERO
	torso.rotation = Vector3(_ang["torso_x"], _ang["torso_y"], 0)
	head.rotation = Vector3(_ang["head_x"], _ang["head_y"], 0)
	# Parpadeo
	_blink -= delta
	var eye_s := 1.0
	if _blink < 0.0:
		eye_s = 0.15
		if _blink < -0.12:
			_blink = randf_range(2.0, 5.0)
	for e in eyes:
		e.scale.y = eye_s
	_update_face()
	# Estirar y aplastar con un muelle amortiguado.
	_sq_v += (1.0 - _sq) * 260.0 * delta
	_sq_v *= exp(-14.0 * delta)
	_sq += _sq_v * delta
	var sq := clampf(_sq, 0.7, 1.3)
	pivot.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
	# Bufanda: se arrastra según la velocidad real.
	if scarf_tail:
		var gp := global_position
		var vel := (gp - _last_pos) / maxf(delta, 0.001)
		_last_pos = gp
		var local_v := global_transform.basis.inverse() * vel
		var flow := clampf(Vector2(local_v.x, local_v.z).length() / 9.0 + absf(local_v.y) / 12.0, 0.0, 1.0)
		var flap := sin(_t * (6.0 + flow * 14.0)) * (0.1 + flow * 0.35)
		var target := Vector2(lerpf(1.3, 0.05, flow) + flap * 0.4, clampf(-local_v.x * 0.05, -0.6, 0.6) + flap)
		_tail_ang = _tail_ang.lerp(target, clampf(8.0 * delta, 0.0, 1.0))
		scarf_tail.rotation = Vector3(_tail_ang.x, _tail_ang.y, 0)
		var tip := scarf_tail.get_node("Tip") as Node3D
		tip.rotation = Vector3(flap * 0.6, flap * 0.8, 0)


## Impulso de estirar (>0, al saltar) o aplastar (<0, al aterrizar).
func squash(amount: float) -> void:
	_sq_v += amount * 6.0


func _update_face() -> void:
	if mouth_smile == null:
		return
	var m := mood
	if m == "":
		match state:
			"jump", "fall", "glide", "hold_up", "cheer":
				m = "surprised"
			"talk":
				m = "talk"
			"climb", "mantle", "swim", "hook", "roll", "fish_reel":
				m = "effort"
			_:
				m = "happy"
	var open := false
	var brow_y := 0.365
	match m:
		"surprised":
			open = true
			brow_y = 0.38
		"talk":
			open = fmod(_t, 0.24) < 0.12
		"effort":
			brow_y = 0.352
	mouth_open.visible = open
	mouth_smile.visible = not open
	for b in brows:
		b.position.y = lerpf(b.position.y, brow_y, 0.3)
