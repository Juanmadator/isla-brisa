class_name ClimbGear
extends Node3D
## Gancho y cuerda de escalada de Lía. Al empezar a trepar lanza el gancho en arco hasta el
## borde de la pared (o lo clava en la roca si la pared es muy alta), sube por la cuerda y la
## recoge al llegar arriba o al soltarse. La cuerda se dibuja con tramos de cilindro: con
## comba mientras vuela el gancho, tensa al trepar y con el sobrante colgando de las manos.

const SEGMENTS := 10
const TAIL_SEGMENTS := 4
const THROW_TIME := 0.3
const REEL_TIME := 0.25

## "off", "throw", "set", "reel"
var mode := "off"
var anchor := Vector3.ZERO
var anchor_normal := Vector3.BACK

var _hook: Node3D
var _segs: Array[MeshInstance3D] = []
var _tail: Array[MeshInstance3D] = []
var _t := 0.0
var _from := Vector3.ZERO
var _hand := Vector3.ZERO


func _ready() -> void:
	top_level = true
	var rope_mat := MeshKit.mat(Color(0.78, 0.62, 0.4))
	var seg_mesh := MeshKit.cylinder(0.022, 0.022, 1.0, 6)
	for i in SEGMENTS + TAIL_SEGMENTS:
		var mi := MeshInstance3D.new()
		mi.mesh = seg_mesh
		mi.material_override = rope_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		if i < SEGMENTS:
			_segs.append(mi)
		else:
			_tail.append(mi)
	_hook = _build_hook()
	_hook.visible = false
	add_child(_hook)


static func _build_hook() -> Node3D:
	# Gancho de tres puntas: vástago, anilla para la cuerda y puntas curvas.
	var root := Node3D.new()
	var metal := MeshKit.mat(Color(0.55, 0.58, 0.62), 0.0, 0.0, Color(0, 0, 0, 0), 0.5)
	MeshKit.part(root, MeshKit.cylinder(0.025, 0.03, 0.34, 8), metal, Vector3(0, 0.17, 0))
	MeshKit.part(root, MeshKit.torus(0.03, 0.055), metal, Vector3(0, 0.0, 0), Vector3(90, 0, 0))
	for k in 3:
		var a := TAU * k / 3.0
		var prong := Node3D.new()
		prong.rotation.y = a
		prong.position = Vector3(0, 0.32, 0)
		root.add_child(prong)
		MeshKit.part(prong, MeshKit.cylinder(0.018, 0.022, 0.2, 6), metal, Vector3(0, -0.02, 0.07), Vector3(-60, 0, 0))
		MeshKit.part(prong, MeshKit.cone(0.022, 0.07, 6), metal, Vector3(0, -0.1, 0.14), Vector3(-160, 0, 0))
	return root


func is_set() -> bool:
	return mode == "set"


## Lanza el gancho desde la mano hasta `to` (en el borde o clavado en la pared).
func throw_to(hand: Vector3, to: Vector3, wall_normal: Vector3) -> void:
	_from = hand
	_hand = hand
	anchor = to
	anchor_normal = wall_normal
	mode = "throw"
	_t = 0.0
	_hook.visible = true
	_set_rope_visible(true)


func release() -> void:
	if mode == "off" or mode == "reel":
		return
	mode = "reel"
	_t = 0.0


func hide_now() -> void:
	mode = "off"
	_hook.visible = false
	_set_rope_visible(false)


func _set_rope_visible(v: bool) -> void:
	for s in _segs:
		s.visible = v
	for s in _tail:
		s.visible = v and mode == "set"


## Actualiza la cuerda con la posición de las manos (llamar cada fotograma).
func update(hand: Vector3, dt: float) -> void:
	_hand = hand
	if mode == "off":
		return
	_t += dt
	var hook_pos := anchor
	var sag := 0.0
	match mode:
		"throw":
			var k := clampf(_t / THROW_TIME, 0.0, 1.0)
			# Arco: sube por encima de la línea recta y cae sobre el borde.
			hook_pos = _from.lerp(anchor, k) + Vector3.UP * sin(k * PI) * 1.2 + anchor_normal * sin(k * PI) * 0.6
			sag = (1.0 - k) * 0.8
			if k >= 1.0:
				mode = "set"
				_set_rope_visible(true)
		"set":
			sag = 0.04
		"reel":
			var k := clampf(_t / REEL_TIME, 0.0, 1.0)
			hook_pos = anchor.lerp(hand, k * k)
			sag = 0.3 * k
			if k >= 1.0:
				hide_now()
				return
	_place_hook(hook_pos)
	# Cuerda del gancho a las manos.
	var prev := hook_pos
	for i in SEGMENTS:
		var u := float(i + 1) / SEGMENTS
		var p := hook_pos.lerp(hand, u) + Vector3.DOWN * sin(u * PI) * sag * hook_pos.distance_to(hand) * 0.25
		_segment(_segs[i], prev, p)
		prev = p
	# Sobrante que cuelga de las manos.
	if mode == "set":
		var tp := hand
		for i in TAIL_SEGMENTS:
			var np := tp + Vector3(sin(_t * 1.7 + i) * 0.03, -0.3, 0.0) + anchor_normal * 0.04
			_segment(_tail[i], tp, np)
			_tail[i].visible = true
			tp = np
	else:
		for s in _tail:
			s.visible = false


func _place_hook(p: Vector3) -> void:
	_hook.global_position = p
	# La anilla mira hacia la cuerda (las manos) y las puntas se agarran al borde.
	var to_hand := (_hand - p)
	if to_hand.length() < 0.01:
		return
	var down := to_hand.normalized()
	var up := -down
	var side := up.cross(anchor_normal)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var fwd := side.cross(up).normalized()
	_hook.global_basis = Basis(side, up, fwd)


static func _segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		mi.visible = false
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)
