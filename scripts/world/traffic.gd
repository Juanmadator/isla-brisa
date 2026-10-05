class_name Traffic
extends Node3D
## Lo que se mueve solo por la isla: veleros que navegan alrededor de la costa y el carro de
## Paco, tirado por un burro, que va y viene por el camino del este con su carga.

## Veleros: [radio x, radio z, velocidad angular, fase]
const SAILS := [[395.0, 380.0, 0.016, 0.0], [440.0, 420.0, -0.012, 2.2], [480.0, 460.0, 0.014, 4.1]]
## Camino del carro (una de las rutas de Island.PATHS: pueblo → acantilado).
const CART_PATH := 3

var island: Island
var _boats: Array = []
var _cart: Node3D
var _donkey: Node3D
var _driver: Avatar
var _cart_wheels: Array = []
var _route: Array = []
var _route_len := 0.0
var _cart_s := 0.0
var _cart_dir := 1.0
var _cart_wait := 0.0
var _t := 0.0
var _phase := 0.0


func build(isl: Island) -> void:
	island = isl
	for spec in SAILS:
		var b := Props.boat()
		b.scale = Vector3.ONE * 1.25
		add_child(b)
		_boats.append({"node": b, "spec": spec})
	_build_cart()


func _build_cart() -> void:
	var pts: Array = Island.PATHS[CART_PATH]
	_route = []
	for p in pts:
		_route.append(p)
	_route_len = 0.0
	for i in _route.size() - 1:
		_route_len += (_route[i] as Vector2).distance_to(_route[i + 1])
	_cart_s = _route_len * 0.3
	_donkey = Animals.donkey()
	add_child(_donkey)
	_cart = Node3D.new()
	add_child(_cart)
	var wood := Props.WOOD
	Props._box(_cart, Vector3(1.5, 0.14, 2.1), wood, Vector3(0, 0.75, 0))
	for sx: int in [-1, 1]:
		Props._box(_cart, Vector3(0.08, 0.45, 2.1), wood.darkened(0.1), Vector3(sx * 0.72, 1.0, 0))
	Props._box(_cart, Vector3(1.5, 0.45, 0.08), wood.darkened(0.1), Vector3(0, 1.0, 1.02))
	# Varas que van hasta el burro.
	for sx: int in [-1, 1]:
		Props._p(_cart, MeshKit.cylinder(0.035, 0.04, 1.9, 6), Props.WOOD_DARK, Vector3(sx * 0.45, 0.85, -1.85), Vector3(90, 0, 0))
	for sx: int in [-1, 1]:
		var wheel := Node3D.new()
		wheel.position = Vector3(sx * 0.82, 0.42, 0.2)
		_cart.add_child(wheel)
		Props._p(wheel, MeshKit.torus(0.34, 0.42), Props.WOOD_DARK, Vector3.ZERO, Vector3(0, 0, 90))
		for k in 6:
			Props._p(wheel, MeshKit.cylinder(0.025, 0.025, 0.72, 5), Props.WOOD, Vector3.ZERO, Vector3(k * 30.0, 0, 0))
		Props._p(wheel, MeshKit.cylinder(0.08, 0.08, 0.12, 10), Props.WOOD_DARK, Vector3.ZERO, Vector3(0, 0, 90))
		_cart_wheels.append(wheel)
	# Carga: heno, un barril y una caja.
	Props._p(_cart, MeshKit.cylinder(0.42, 0.42, 0.9, 14), Color(0.92, 0.8, 0.48), Vector3(0, 1.25, 0.45), Vector3(0, 0, 90))
	var barrel := Props.barrel()
	barrel.position = Vector3(-0.35, 0.82, -0.45)
	barrel.scale = Vector3.ONE * 0.75
	_cart.add_child(barrel)
	var crate := Props.crate()
	crate.position = Vector3(0.35, 0.82, -0.5)
	crate.scale = Vector3.ONE * 0.55
	_cart.add_child(crate)
	# Paco, el carretero, sentado delante.
	_driver = Avatar.new()
	_cart.add_child(_driver)
	_driver.build({"hair_style": "short", "hair": Color(0.5, 0.5, 0.52), "beard": true, "hat": "straw", "hat_color": Color(0.9, 0.8, 0.5),
		"shirt": Color(0.75, 0.4, 0.3), "pants": Color(0.35, 0.32, 0.3), "scarf": Color(0.3, 0.5, 0.75), "dress": false, "girth": 1.2})
	_driver.position = Vector3(0, 0.72, -0.75)
	_driver.state = "sit"


## Punto y dirección del camino a `s` metros del principio.
func _route_at(s: float) -> Array:
	var acc := 0.0
	for i in _route.size() - 1:
		var a: Vector2 = _route[i]
		var b: Vector2 = _route[i + 1]
		var l := a.distance_to(b)
		if s <= acc + l or i == _route.size() - 2:
			var k := clampf((s - acc) / l, 0.0, 1.0)
			return [a.lerp(b, k), (b - a).normalized()]
		acc += l
	return [_route[0], Vector2(0, 1)]


func _process(dt: float) -> void:
	_t += dt
	for b in _boats:
		var spec: Array = b["spec"]
		var ang: float = _t * spec[2] + spec[3]
		var p := Vector3(cos(ang) * spec[0], 0.0, sin(ang) * spec[1] + 30.0)
		var tangent := Vector3(-sin(ang) * spec[0], 0.0, cos(ang) * spec[1]) * signf(spec[2])
		var node: Node3D = b["node"]
		node.position = p + Vector3(0, sin(_t * 1.3 + spec[3]) * 0.12 - 0.05, 0)
		node.rotation = Vector3(sin(_t * 1.1 + spec[3]) * 0.03, atan2(-tangent.x, -tangent.z), 0.08 + sin(_t * 0.9) * 0.03)
	_move_cart(dt)


func _move_cart(dt: float) -> void:
	var moving := _cart_wait <= 0.0
	if not moving:
		_cart_wait -= dt
	else:
		_cart_s += _cart_dir * dt * 2.2
		if _cart_s >= _route_len - 4.0 or _cart_s <= 6.0:
			_cart_s = clampf(_cart_s, 6.0, _route_len - 4.0)
			_cart_dir = -_cart_dir
			_cart_wait = 8.0
	var front := _route_at(_cart_s + _cart_dir * 2.4)
	var here := _route_at(_cart_s)
	var dir: Vector2 = (front[0] as Vector2 - here[0] as Vector2).normalized()
	# El camino pasa por el centro: el carro va por la derecha.
	var side := Vector2(-dir.y, dir.x) * 1.4
	var cp: Vector2 = here[0] + side
	var dp: Vector2 = front[0] + side
	var yaw := atan2(-dir.x, -dir.y)
	_cart.position = island.ground(cp, -0.05)
	_cart.rotation.y = yaw
	var ahead := island.height_at(cp.x + dir.x, cp.y + dir.y) - island.height_at(cp.x - dir.x, cp.y - dir.y)
	_cart.rotation.x = clampf(ahead * 0.25, -0.2, 0.2)
	_donkey.position = island.ground(dp, -0.02)
	_donkey.rotation.y = yaw
	if moving:
		_phase += dt * 6.0
		for w in _cart_wheels:
			(w as Node3D).rotation.x -= dt * 2.2 / 0.42
	Animals.animate(_donkey, _phase, moving, 0.0 if moving else 0.6, _t)
