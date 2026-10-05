class_name Pet
extends Node3D
## Mascota que acompaña a Lía: modelo procedural según la especie, sigue a Lía por el
## suelo (o volando, el loro), se sienta cuando ella se para, nada si cae al agua y de vez
## en cuando escarba y encuentra conchas.
## Especies: dog, cat, bunny, chick, fox, parrot.

signal found_shells(n: int)

var kind := "dog"
var pet_name := ""
var player: Player
var island: Island
## Segundos entre hallazgos y conchas por hallazgo (según la especie).
var dig_every := 90.0
var dig_amount := Vector2i(1, 2)

var model: Node3D
var body: Node3D
var head: Node3D
var tail: Node3D
var legs: Array[Node3D] = []
var wings: Array[Node3D] = []
var ears: Array[Node3D] = []

var _t := 0.0
var _phase := 0.0
var _yaw := 0.0
var _vel := Vector3.ZERO
var _sit := 0.0
var _idle_t := 0.0
var _dig_clock := 0.0
var _dig_t := 0.0
var _happy_t := 0.0
var _hop := 0.0
var _flying := false
var _side := 1.0

const SPECS := {
	"dog": {"walk": 7.5, "dig": 70.0, "amount": Vector2i(1, 3)},
	"cat": {"walk": 7.0, "dig": 110.0, "amount": Vector2i(1, 2)},
	"bunny": {"walk": 7.0, "dig": 95.0, "amount": Vector2i(1, 2)},
	"chick": {"walk": 6.0, "dig": 100.0, "amount": Vector2i(1, 2)},
	"fox": {"walk": 8.0, "dig": 80.0, "amount": Vector2i(1, 3)},
	"parrot": {"walk": 9.0, "dig": 120.0, "amount": Vector2i(2, 3)},
}


func setup(pet_kind: String, display_name: String, colors: Array, p: Player, isl: Island) -> void:
	kind = pet_kind
	pet_name = display_name
	player = p
	island = isl
	var sp: Dictionary = SPECS.get(kind, SPECS["dog"])
	dig_every = sp["dig"]
	dig_amount = sp["amount"]
	_dig_clock = dig_every * randf_range(0.5, 0.8)
	_flying = kind == "parrot"
	model = build_model(kind, colors)
	add_child(model)
	body = model.get_node("Body")
	head = model.get_node("Body/Head")
	tail = model.get_node_or_null("Body/Tail")
	for c in model.get_node("Body").get_children():
		if c.name.begins_with("Leg"):
			legs.append(c)
		elif c.name.begins_with("Wing"):
			wings.append(c)
	for c in head.get_children():
		if c.name.begins_with("Ear"):
			ears.append(c)


## Coloca la mascota junto a Lía (al empezar o si se queda muy atrás).
func snap_to_player() -> void:
	if player == null:
		return
	var b := player.global_transform.basis
	var target := player.global_position + b.z * 1.4 + b.x * 0.9 * _side
	global_position = Vector3(target.x, _floor_y(target, player.global_position.y), target.z)
	_yaw = player.facing


func pet_me() -> void:
	_happy_t = 2.0
	_sit = 0.0


func _process(delta: float) -> void:
	if player == null or model == null:
		return
	_t += delta
	var pp := player.global_position
	var b := Basis(Vector3.UP, player.facing)
	var idle_player := player.velocity.length() < 0.5
	# Sitio al lado de Lía (detrás y a un lado); cambia de lado de vez en cuando.
	if fmod(_t, 23.0) < delta:
		_side = -_side
	var target := pp + b.z * 1.5 + b.x * 0.95 * _side
	if _flying:
		_process_flying(delta, pp, b, idle_player)
		return
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	# Muy lejos (Lía planeó, escaló o se teletransportó): reaparece a su lado al aterrizar.
	if (dist > 28.0 or absf(pp.y - global_position.y) > 9.0) and player.state == "ground":
		snap_to_player()
		Fx.dust(get_parent(), global_position, 0.7)
		return
	var walk: float = SPECS.get(kind, SPECS["dog"])["walk"]
	var want := Vector3.ZERO
	if _dig_t <= 0.0 and dist > 0.35:
		var speed := clampf((dist - 0.3) * 2.6, 0.0, walk * (1.6 if dist > 8.0 else 1.0))
		want = to / dist * speed
	_vel = _vel.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	global_position += _vel * delta
	var water := island.water_level(global_position.x, global_position.z)
	var fy := _floor_y(global_position, global_position.y)
	var swimming := fy < water - 0.25
	var gy := water - 0.18 if swimming else fy
	global_position.y = lerpf(global_position.y, gy, clampf(delta * 14.0, 0.0, 1.0))
	var moving := _vel.length() > 0.4
	if moving:
		_yaw = rotate_toward(_yaw, atan2(-_vel.x, -_vel.z), delta * 9.0)
		_idle_t = 0.0
	else:
		_idle_t += delta
		var face := pp - global_position
		if face.length() > 0.5 and _idle_t > 0.6:
			_yaw = rotate_toward(_yaw, atan2(-face.x, -face.z), delta * 3.0)
	model.rotation.y = _yaw
	# Escarbar: cuenta solo mientras Lía va de un lado a otro.
	if not idle_player and player.state == "ground" and not swimming:
		_dig_clock -= delta
	if _dig_clock <= 0.0 and not moving and not swimming and dist < 3.0:
		_dig_clock = dig_every * randf_range(0.8, 1.25)
		_dig_t = 1.6
	if _dig_t > 0.0:
		_dig_t -= delta
		if fmod(_dig_t, 0.3) < delta:
			Fx.dust(get_parent(), global_position + model.basis.z * -0.3, 0.35)
		if _dig_t <= 0.0:
			found_shells.emit(randi_range(dig_amount.x, dig_amount.y))
			_happy_t = 1.5
	_animate(delta, moving, swimming)


func _process_flying(delta: float, pp: Vector3, b: Basis, idle_player: bool) -> void:
	# El loro revolotea sobre el hombro de Lía y se posa en él si ella se para.
	var perch := pp + b.x * 0.21 + Vector3(0, 1.08, 0) + b.z * 0.03
	var hover := pp + b.z * 1.2 + b.x * 0.8 * _side + Vector3(0, 2.3 + sin(_t * 1.7) * 0.25, 0)
	var on_shoulder := idle_player and player.state == "ground"
	var target := perch if on_shoulder else hover
	var to := target - global_position
	if to.length() > 30.0:
		global_position = hover
		return
	var k := clampf(delta * (7.0 if on_shoulder else 3.5), 0.0, 1.0)
	global_position = global_position.lerp(target, k)
	var flat := Vector3(to.x, 0, to.z)
	if flat.length() > 0.3 and not on_shoulder:
		_yaw = rotate_toward(_yaw, atan2(-flat.x, -flat.z), delta * 6.0)
	elif on_shoulder:
		_yaw = rotate_toward(_yaw, player.facing, delta * 8.0)
	model.rotation.y = _yaw
	var perched := on_shoulder and to.length() < 0.15
	var flap := 0.0 if perched else sin(_t * 22.0) * 0.9
	for i in wings.size():
		wings[i].rotation.z = (flap + (0.0 if not perched else -0.1)) * (1.0 if i == 0 else -1.0)
	body.rotation.x = 0.0 if perched else -0.25
	head.rotation.y = sin(_t * 0.9) * 0.5 if perched else 0.0
	if tail:
		tail.rotation.x = sin(_t * 3.0) * 0.1
	_dig_clock -= delta if not idle_player else 0.0
	if _dig_clock <= 0.0:
		_dig_clock = dig_every * randf_range(0.8, 1.25)
		found_shells.emit(randi_range(dig_amount.x, dig_amount.y))


func _animate(delta: float, moving: bool, swimming: bool) -> void:
	var sp := _vel.length()
	var hopper := kind == "bunny" or kind == "chick"
	_sit = move_toward(_sit, 1.0 if (_idle_t > 2.5 and _dig_t <= 0.0 and _happy_t <= 0.0 and not swimming) else 0.0, delta * 2.5)
	if moving:
		_phase += delta * (5.0 + sp * 1.6)
	var s := sin(_phase)
	var y := 0.0
	if hopper and moving:
		_hop = absf(sin(_phase * 0.6)) * 0.22
		y = _hop
	elif moving:
		y = absf(s) * 0.04
	if _happy_t > 0.0:
		_happy_t -= delta
		y += absf(sin(_t * 9.0)) * 0.14
	body.position.y = lerpf(body.position.y, y - _sit * 0.06, clampf(delta * 16.0, 0.0, 1.0))
	body.rotation.x = lerpf(body.rotation.x, (-0.35 * _sit) + (0.45 if _dig_t > 0.0 else 0.0), clampf(delta * 8.0, 0.0, 1.0))
	for i in legs.size():
		var front := i < 2
		var sign_ := 1.0 if (i % 2 == 0) == front else -1.0
		var swing := s * 0.7 * sign_ if moving and not hopper else 0.0
		if _dig_t > 0.0 and front:
			swing = sin(_t * 18.0 + i) * 0.9
		if not front:
			swing -= _sit * 1.1
		legs[i].rotation.x = lerpf(legs[i].rotation.x, swing, clampf(delta * 14.0, 0.0, 1.0))
	for i in wings.size():
		var flap := sin(_t * 20.0) * 0.6 if (_happy_t > 0.0 or (hopper and _hop > 0.12)) else 0.0
		wings[i].rotation.z = flap * (1.0 if i == 0 else -1.0)
	if tail:
		var wag := 0.35 + (0.5 if _happy_t > 0.0 else 0.0)
		tail.rotation.y = sin(_t * (6.0 if _happy_t <= 0.0 else 16.0)) * wag
	head.rotation.y = sin(_t * 0.7) * 0.35 * float(_idle_t > 1.0)
	head.rotation.x = 0.3 if _dig_t > 0.0 else sin(_t * 1.3) * 0.05
	for i in ears.size():
		ears[i].rotation.z = sin(_t * 2.0 + i) * 0.06 + (0.1 if _happy_t > 0.0 else 0.0) * (1.0 if i == 0 else -1.0)


func _floor_y(p: Vector3, from_y: float) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, from_y + 1.2, p.z), Vector3(p.x, from_y - 8.0, p.z))
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		return (hit["position"] as Vector3).y
	return island.height_at(p.x, p.z)


# --- Modelos -----------------------------------------------------------------------------

## Modelo de la especie. Mira hacia -Z con el origen en el suelo. Nodos con nombre:
## Body, Body/Head, Body/Tail, Body/Leg*, Body/Wing*, Body/Head/Ear* (para animarlos).
static func build_model(pet_kind: String, colors: Array) -> Node3D:
	var main: Color = colors[0] if colors.size() > 0 else Color(0.8, 0.6, 0.4)
	var accent: Color = colors[1] if colors.size() > 1 else Color(1, 1, 1)
	var root := Node3D.new()
	var body_n := Node3D.new()
	body_n.name = "Body"
	root.add_child(body_n)
	var m := MeshKit.mat(main)
	var ma := MeshKit.mat(accent)
	var dark := MeshKit.mat(Color(0.08, 0.07, 0.08))
	var nose := MeshKit.mat(Color(0.2, 0.12, 0.12))
	var head_n := Node3D.new()
	head_n.name = "Head"
	body_n.add_child(head_n)
	match pet_kind:
		"dog", "fox", "cat":
			var fox := pet_kind == "fox"
			var cat := pet_kind == "cat"
			# Cuerpo de una pieza: grupa, cintura recogida y pecho más hondo (el gato, más fino).
			var w := 0.86 if cat else 1.0
			var trunk := MeshKit.loft([
				[Vector3(0, 0.41, 0.3), 0.04, 0.04], [Vector3(0, 0.4, 0.25), 0.13 * w, 0.13], [Vector3(0, 0.39, 0.13), 0.14 * w, 0.14],
				[Vector3(0, 0.38, 0.0), 0.12 * w, 0.115], [Vector3(0, 0.36, -0.12), 0.15 * w, 0.16], [Vector3(0, 0.42, -0.21), 0.12 * w, 0.13],
				[Vector3(0, 0.5, -0.25), 0.04, 0.04]], 16, 3)
			MeshKit.part(body_n, trunk, m)
			MeshKit.part(body_n, MeshKit.blob(0.12, 0.9, 0.0, 0, 10), ma, Vector3(0, 0.33, -0.15), Vector3.ZERO, Vector3(0.85 * w, 1.0, 0.8))
			head_n.position = Vector3(0, 0.56, -0.26)
			MeshKit.part(head_n, MeshKit.blob(0.16, 0.95, 0.0, 0, 12), m, Vector3.ZERO)
			var snout_len := 0.11 if not cat else 0.05
			MeshKit.part(head_n, MeshKit.blob(0.085, 0.8, 0.0, 0, 10), ma if fox or cat else m, Vector3(0, -0.04, -0.13 - snout_len * 0.3), Vector3.ZERO, Vector3(0.9, 0.85, 1.0 + snout_len * 4.0))
			MeshKit.part(head_n, MeshKit.sphere(0.03, 8), nose, Vector3(0, -0.01, -0.21 - snout_len * 0.7))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(head_n, MeshKit.sphere(0.026, 8), dark, Vector3(sx * 0.07, 0.04, -0.135))
				MeshKit.part(head_n, MeshKit.sphere(0.009, 5), MeshKit.unshaded(Color.WHITE), Vector3(sx * 0.07 + 0.008, 0.052, -0.158))
				var ear := Node3D.new()
				ear.name = "Ear%d" % (0 if sx < 0 else 1)
				ear.position = Vector3(sx * 0.09, 0.1, 0.0)
				head_n.add_child(ear)
				if pet_kind == "dog":
					MeshKit.part(ear, MeshKit.blob(0.07, 1.6, 0.0, 0, 8), MeshKit.mat(main.darkened(0.25)), Vector3(sx * 0.04, -0.06, 0.02), Vector3(0, 0, sx * 25.0), Vector3(0.6, 1.0, 0.9))
				else:
					MeshKit.part(ear, MeshKit.cone(0.06 if fox else 0.05, 0.14 if fox else 0.11, 6), m, Vector3(0, 0.04, 0), Vector3(0, 0, -sx * 12.0), Vector3(1.0, 1.0, 0.6))
					MeshKit.part(ear, MeshKit.cone(0.032, 0.09, 6), MeshKit.mat(Color(1.0, 0.75, 0.75) if cat else Color(0.15, 0.1, 0.1)), Vector3(0, 0.035, -0.015), Vector3(0, 0, -sx * 12.0), Vector3(1.0, 1.0, 0.4))
			for i in 4:
				var front := i < 2
				var paw: Color = Color(0.2, 0.15, 0.13) if fox else main
				Animals._leg(body_n, i, Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.085 * w, 0.32, -0.15 if front else 0.2), 0.032, 0.32, main, paw, not front, 0.05)
			var tail_n := Node3D.new()
			tail_n.name = "Tail"
			tail_n.position = Vector3(0, 0.42, 0.3)
			body_n.add_child(tail_n)
			if fox:
				MeshKit.part(tail_n, MeshKit.blob(0.12, 2.2, 0.0, 0, 10), m, Vector3(0, 0.02, 0.2), Vector3(-60, 0, 0))
				MeshKit.part(tail_n, MeshKit.blob(0.08, 1.4, 0.0, 0, 8), ma, Vector3(0, 0.1, 0.4), Vector3(-60, 0, 0))
			elif cat:
				MeshKit.part(tail_n, MeshKit.capsule(0.035, 0.42), m, Vector3(0, 0.15, 0.08), Vector3(-25, 0, 0))
			else:
				# Desde la grupa hacia arriba y atrás.
				tail_n.position = Vector3(0, 0.42, 0.26)
				MeshKit.part(tail_n, MeshKit.capsule(0.038, 0.26), m, Vector3(0, 0.08, 0.08), Vector3(45, 0, 0))
		"bunny":
			MeshKit.part(body_n, MeshKit.blob(0.2, 0.9, 0.0, 0, 12), m, Vector3(0, 0.22, 0.04), Vector3.ZERO, Vector3(1.0, 1.0, 1.15))
			head_n.position = Vector3(0, 0.38, -0.14)
			MeshKit.part(head_n, MeshKit.blob(0.14, 0.95, 0.0, 0, 12), m, Vector3.ZERO)
			MeshKit.part(head_n, MeshKit.sphere(0.022, 6), MeshKit.mat(Color(1.0, 0.6, 0.65)), Vector3(0, -0.02, -0.135))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(head_n, MeshKit.sphere(0.024, 8), dark, Vector3(sx * 0.065, 0.03, -0.11))
				var ear := Node3D.new()
				ear.name = "Ear%d" % (0 if sx < 0 else 1)
				ear.position = Vector3(sx * 0.05, 0.1, 0.02)
				head_n.add_child(ear)
				MeshKit.part(ear, MeshKit.capsule(0.04, 0.26), m, Vector3(0, 0.12, 0), Vector3(-8, 0, sx * -10.0), Vector3(1.0, 1.0, 0.6))
				MeshKit.part(ear, MeshKit.capsule(0.022, 0.18), MeshKit.mat(Color(1.0, 0.78, 0.8)), Vector3(0, 0.12, -0.02), Vector3(-8, 0, sx * -10.0), Vector3(1.0, 1.0, 0.4))
			for i in 4:
				var leg := Node3D.new()
				leg.name = "Leg%d" % i
				leg.position = Vector3((-1.0 if i % 2 == 0 else 1.0) * 0.09, 0.08, -0.08 if i < 2 else 0.12)
				body_n.add_child(leg)
				MeshKit.part(leg, MeshKit.blob(0.055, 0.7, 0.0, 0, 8), m, Vector3(0, -0.04, -0.03), Vector3.ZERO, Vector3(1.0, 1.0, 1.6 if i >= 2 else 1.0))
			var tail_n := Node3D.new()
			tail_n.name = "Tail"
			tail_n.position = Vector3(0, 0.22, 0.25)
			body_n.add_child(tail_n)
			MeshKit.part(tail_n, MeshKit.sphere(0.07, 8), ma, Vector3.ZERO)
		"chick":
			MeshKit.part(body_n, MeshKit.blob(0.17, 0.95, 0.0, 0, 12), m, Vector3(0, 0.2, 0.02))
			head_n.position = Vector3(0, 0.36, -0.04)
			MeshKit.part(head_n, MeshKit.blob(0.12, 1.0, 0.0, 0, 12), m, Vector3.ZERO)
			MeshKit.part(head_n, MeshKit.cone(0.035, 0.07, 6), MeshKit.mat(Color(1.0, 0.55, 0.15)), Vector3(0, -0.01, -0.13), Vector3(-90, 0, 0))
			MeshKit.part(head_n, MeshKit.blob(0.04, 1.2, 0.0, 0, 6), MeshKit.mat(accent), Vector3(0, 0.12, 0.0))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(head_n, MeshKit.sphere(0.022, 8), dark, Vector3(sx * 0.055, 0.03, -0.095))
				var wing := Node3D.new()
				wing.name = "Wing%d" % (0 if sx < 0 else 1)
				wing.position = Vector3(sx * 0.15, 0.24, 0.02)
				body_n.add_child(wing)
				MeshKit.part(wing, MeshKit.blob(0.08, 1.3, 0.0, 0, 8), m, Vector3(sx * 0.02, -0.03, 0.0), Vector3(0, 0, sx * 20.0), Vector3(0.45, 1.0, 1.0))
			for i in 2:
				var leg := Node3D.new()
				leg.name = "Leg%d" % i
				leg.position = Vector3((-1.0 if i == 0 else 1.0) * 0.06, 0.06, 0.0)
				body_n.add_child(leg)
				MeshKit.part(leg, MeshKit.cylinder(0.012, 0.012, 0.08, 5), MeshKit.mat(Color(1.0, 0.55, 0.15)), Vector3(0, -0.02, 0))
				MeshKit.part(leg, MeshKit.rounded_box(Vector3(0.06, 0.015, 0.07), 0.006, 1), MeshKit.mat(Color(1.0, 0.55, 0.15)), Vector3(0, -0.055, -0.02))
		"parrot":
			MeshKit.part(body_n, MeshKit.blob(0.1, 1.5, 0.0, 0, 10), m, Vector3(0, 0.12, 0.0), Vector3(15, 0, 0))
			head_n.position = Vector3(0, 0.27, -0.03)
			MeshKit.part(head_n, MeshKit.blob(0.08, 1.0, 0.0, 0, 10), m, Vector3.ZERO)
			MeshKit.part(head_n, MeshKit.blob(0.035, 1.2, 0.0, 0, 8), MeshKit.mat(Color(0.95, 0.9, 0.75)), Vector3(0, -0.02, -0.08), Vector3(30, 0, 0), Vector3(0.8, 1.0, 1.0))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(head_n, MeshKit.sphere(0.022, 8), MeshKit.mat(Color.WHITE), Vector3(sx * 0.05, 0.02, -0.045))
				MeshKit.part(head_n, MeshKit.sphere(0.013, 6), dark, Vector3(sx * 0.056, 0.022, -0.058))
				var wing := Node3D.new()
				wing.name = "Wing%d" % (0 if sx < 0 else 1)
				wing.position = Vector3(sx * 0.08, 0.17, 0.02)
				body_n.add_child(wing)
				MeshKit.part(wing, MeshKit.blob(0.1, 1.0, 0.0, 0, 8), ma, Vector3(sx * 0.09, 0.0, 0.03), Vector3.ZERO, Vector3(1.0, 0.18, 0.6))
			var tail_n := Node3D.new()
			tail_n.name = "Tail"
			tail_n.position = Vector3(0, 0.05, 0.08)
			body_n.add_child(tail_n)
			MeshKit.part(tail_n, MeshKit.blob(0.05, 3.2, 0.0, 0, 8), ma, Vector3(0, -0.07, 0.08), Vector3(-55, 0, 0), Vector3(1.0, 1.0, 0.4))
	return root
