class_name Places
extends Node3D
## Construcciones fijas de la isla y los puntos de referencia (anclas) que usa el juego
## para colocar personajes, coleccionables y retos.

const REGION_COLORS := {
	"faro_cliff": Color(0.95, 0.45, 0.35),
	"faro_forest": Color(0.4, 0.8, 0.45),
	"faro_islet": Color(0.35, 0.65, 0.95),
	"faro_ruins": Color(0.95, 0.75, 0.3),
	"faro_summit": Color(0.85, 0.55, 1.0),
}

## Lugares con nombre: [id, nombre, centro XZ, radio, altura mínima]
const NAMED := [
	["village", "Pueblo Brisa", Vector2(15, 168), 58.0, -10.0],
	["dock", "Muelle de Tomeu", Vector2(15, 232), 20.0, -10.0],
	["windmill", "Colina del Molino", Vector2(92, 132), 34.0, 14.0],
	["summit", "Pico Brisa", Vector2(0, -170), 45.0, 88.0],
	["forest", "Bosque Susurro", Vector2(-190, 40), 80.0, -10.0],
	["lake", "Lago Espejo", Vector2(-150, -48), 62.0, -10.0],
	["penon", "Peñón del Salto", Vector2(-165, 158), 30.0, 40.0],
	["islet", "Islote del Faro", Vector2(-262, 268), 30.0, -10.0],
	["cliff", "Acantilado del Este", Vector2(236, 8), 42.0, 30.0],
	["ruins", "Ruinas del Viento", Vector2(168, -138), 58.0, 38.0],
	["beach", "Playa de las Conchas", Vector2(130, 205), 50.0, -10.0],
	["farm", "Granja del Prado", Vector2(66, 30), 30.0, -10.0],
	["meadow", "Prado de los Vientos", Vector2(40, 40), 60.0, -10.0],
]

var island: Island
var clear_zones: Array = []
var anchors := {}
var yaws := {}
var beacons := {}        # id -> diccionario de Props.beacon
var lamps: Array = []    # diccionarios de Props.lamp_post
## Animales del cercado del refugio de Lola: [modelo, centro del cercado, radio].
var pen_animals: Array = []
## Bancos donde sentarse: [posición del asiento en el suelo, orientación de quien se sienta].
var benches: Array = []
## Obstáculos que los vecinos rodean al pasear: [centro, radio].
var obstacles: Array = []
## Guirnaldas de banderines: nodos "Flags" cuyos hijos se mecen con el viento.
var buntings: Array = []
var windmill_hub: Node3D
var flames: Array = []
var race_rings: Array = []   # Vector3
var farm: Farm
var tomeu_boat: Node3D


func build(isl: Island) -> void:
	island = isl
	_compute_anchors()
	_build_village()
	_build_dock()
	_build_windmill()
	_build_beacons()
	_build_ruins()
	_build_camps()
	_build_extras()
	farm = Farm.new()
	farm.name = "Farm"
	add_child(farm)
	farm.build(island, self)


func anchor(id: String) -> Vector3:
	return anchors.get(id, Vector3.ZERO)


func _put(id: String, p: Vector2, clear := 0.0, lift := 0.0) -> Vector3:
	var v := island.ground(p, lift)
	anchors[id] = v
	if clear > 0.0:
		clear_zones.append(Vector3(p.x, p.y, clear))
	return v


## Coloca un nodo sobre el terreno. Si `yaw` es NAN, mira hacia `face`.
func _place(n: Node3D, p: Vector2, yaw := 0.0, sink := 0.15) -> Node3D:
	add_child(n)
	n.position = island.ground(p, -sink)
	n.rotation.y = yaw
	return n


static func yaw_towards(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y)


## Punto más bajo bajo una huella cuadrada (para que las casas no floten en cuestas).
func _min_ground(p: Vector2, r: float) -> float:
	var m := INF
	for dx: float in [-r, 0.0, r]:
		for dz: float in [-r, 0.0, r]:
			m = minf(m, island.height_at(p.x + dx, p.y + dz))
	return m


func _compute_anchors() -> void:
	var shore := island.find_shore(Island.VILLAGE, Vector2(0, 1))
	anchors["shore"] = island.ground(shore)
	_put("dock", shore + Vector2(0, -6), 10.0)
	_put("village", Island.VILLAGE, 46.0)
	_put("windmill", Island.WINDMILL_HILL, 9.0)
	_put("needle", Island.WINDMILL_HILL + Vector2(-17, 9), 5.0)
	_put("faro_summit", Island.MOUNT, 14.0)
	_put("faro_cliff", Island.CLIFF + Vector2(8, -2), 8.0)
	_put("faro_islet", Island.ISLET, 6.0)
	_put("faro_ruins", Island.RUINS + Vector2(16, -16), 10.0)
	_put("faro_forest", Vector2(-218, 64), 9.0)
	_put("penon", Island.PENON + Vector2(-2, 2), 8.0)
	var lake_dir := Vector2(1.0, 0.45).normalized()
	_put("lake_cabin", Island.LAKE + lake_dir * 62.0, 9.0)
	_put("ruins_camp", Vector2(128, -94), 8.0)
	_put("cliff_hut", Vector2(186, 38), 8.0)
	_put("penon_foot", Vector2(-126, 140), 6.0)
	_put("race_start", Island.RUINS + Vector2(-8, 22), 6.0)
	_put("stump", Vector2(-190, 100), 6.0)
	_put("lake_islet_top", Island.LAKE_ISLET, 4.0)
	_put("sea_stack", Vector2(214, -112), 0.0)


# --- Pueblo -------------------------------------------------------------------------------

func _build_village() -> void:
	var v := Island.VILLAGE
	add_child(_at(Props.fountain(), v))
	var houses := [
		["town_hall", Vector2(0, -21), Color(0.82, 0.32, 0.28), Vector3(8.0, 4.4, 6.0)],
		["pia_house", Vector2(-22, -10), Color(0.85, 0.45, 0.35), Vector3(6.0, 3.6, 5.0)],
		["post", Vector2(23, -12), Color(0.3, 0.5, 0.82), Vector3(6.0, 3.6, 5.0)],
		["workshop", Vector2(-25, 13), Color(0.25, 0.65, 0.62), Vector3(6.5, 3.8, 5.0)],
		["house_a", Vector2(27, 14), Color(0.95, 0.6, 0.3), Vector3(5.5, 3.4, 4.6)],
		["house_b", Vector2(-12, 30), Color(0.6, 0.42, 0.75), Vector3(5.5, 3.4, 4.6)],
		["house_c", Vector2(33, 32), Color(0.85, 0.35, 0.45), Vector3(5.0, 3.2, 4.4)],
		["house_d", Vector2(-36, -28), Color(0.4, 0.62, 0.35), Vector3(5.0, 3.2, 4.4)],
	]
	var i := 0
	for h in houses:
		var p: Vector2 = v + h[1]
		var yaw := yaw_towards(p, v)
		var node := Props.house(100 + i, h[2], Props.WHITE_WALL, h[3])
		add_child(node)
		node.position = Vector3(p.x, _min_ground(p, 3.0) - 0.05, p.y)
		node.rotation.y = yaw
		anchors[h[0]] = node.position
		yaws[h[0]] = yaw
		# Ancla delante de la puerta
		var door := Basis(Vector3.UP, yaw) * Vector3(-h[3].x * 0.18, 0, h[3].z * 0.5 + 1.8)
		anchors[h[0] + "_door"] = island.ground(p + Vector2(door.x, door.z))
		i += 1
	anchors["pia_spot"] = island.ground(v + Vector2(4.5, 3.5))
	anchors["pia_roof"] = anchors["pia_house"] + Vector3(0, 0.3 + 3.6 + 6.0 * 0.42 + 0.17, 0)
	# Cartel de correos y cometas del taller
	var post_sign := Props.signpost("Correos")
	add_child(post_sign)
	var pp: Vector3 = anchors["post_door"]
	post_sign.position = pp + Basis(Vector3.UP, yaws["post"]) * Vector3(2.4, -0.1, 0.4)
	post_sign.rotation.y = yaws["post"]
	var kite_cols := [[Color(1, 0.4, 0.35), Color(1, 0.85, 0.3)], [Color(0.35, 0.6, 1), Color(1, 1, 1)], [Color(0.5, 0.85, 0.4), Color(1, 0.55, 0.7)]]
	var wp: Vector3 = anchors["workshop"]
	for k in 3:
		var kt := Props.kite(kite_cols[k][0], kite_cols[k][1], 0.9)
		add_child(kt)
		kt.position = wp + Basis(Vector3.UP, yaws["workshop"]) * Vector3(-2.2 + k * 2.2, 5.6 + (k % 2) * 0.5, 3.0)
		kt.rotation.y = yaws["workshop"] + (k - 1) * 0.3
		kt.rotation.z = (k - 1) * 0.25
	_build_shops(v)
	# Panadería de Rafa (al oeste de la plaza) y tablón de encargos junto a la fuente.
	var bk := v + Vector2(-44, -6)
	var bk_yaw := yaw_towards(bk, v)
	var bakery := Props.house(55, Color(0.82, 0.5, 0.3), Color(0.98, 0.92, 0.8), Vector3(7.0, 3.6, 5.4))
	Props.bakery_front(bakery, 7.0, 5.4)
	add_child(bakery)
	bakery.position = Vector3(bk.x, _min_ground(bk, 3.5) - 0.05, bk.y)
	bakery.rotation.y = bk_yaw
	anchors["bakery"] = bakery.position
	var bk_out := Basis(Vector3.UP, bk_yaw) * Vector3(0, 0, 1)
	var bk_right := Basis(Vector3.UP, bk_yaw) * Vector3(1, 0, 0)
	anchors["bakery_spot"] = island.ground(Vector2(bakery.position.x, bakery.position.z) + Vector2(bk_out.x, bk_out.z) * 4.6 + Vector2(bk_right.x, bk_right.z) * 2.6)
	obstacles.append([bakery.position, 5.6])
	var nb := v + Vector2(-3, 6.5)
	_place(Props.noticeboard(), nb, yaw_towards(nb, v), 0.1)
	anchors["noticeboard"] = island.ground(nb + (v - nb).normalized() * 1.6)
	obstacles.append([island.ground(nb), 1.4])
	# Puesto del mercado de Marisol
	var stall_p := v + Vector2(11, 7)
	var stall := Props.market_stall(Color(0.95, 0.45, 0.4))
	_place(stall, stall_p, yaw_towards(stall_p, v))
	anchors["stall"] = island.ground(stall_p)
	yaws["stall"] = yaw_towards(stall_p, v)
	anchors["marisol_spot"] = island.ground(stall_p + (stall_p - v).normalized() * 1.4)
	# Farolas, bancos y cajas
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		var lp := v + Vector2(cos(a), sin(a)) * 9.5
		var lamp := Props.lamp_post()
		_place(lamp["root"], lp, 0.0, 0.1)
		lamps.append(lamp)
	# Guirnaldas de banderines de farola a farola, cruzando la plaza.
	for k in 3:
		var la: Vector3 = (lamps[k]["root"] as Node3D).position + Vector3(0, 3.3, 0)
		var lb: Vector3 = (lamps[k + 3]["root"] as Node3D).position + Vector3(0, 3.3, 0)
		var bunt := Props.bunting(la, lb, 1.1)
		add_child(bunt)
		buntings.append(bunt.get_node("Flags"))
	for k in 3:
		var a := TAU * k / 3.0 + 1.2
		var bp := v + Vector2(cos(a), sin(a)) * 6.0
		_add_bench(bp, yaw_towards(bp, v) + PI)
	_place(Props.crate(), v + Vector2(14, 10))
	_place(Props.crate(Props.WOOD.lightened(0.1)), v + Vector2(14.6, 11.2), 0.4)
	_place(Props.barrel(), v + Vector2(-27, 16))
	_place(Props.barrel(), v + Vector2(-28, 17.2))
	_place(Props.fence(10.0), v + Vector2(-34, 0), PI / 2)
	_place(Props.fence(8.0), v + Vector2(40, 2), PI / 2)
	var village_sign := Props.signpost("Pueblo Brisa")
	_place(village_sign, v + Vector2(-4, 40), PI)


## Sastrería de Valeria (casa del tejado frambuesa) y refugio de animales de Lola
## (casa del tejado verde, con un cercado al lado).
func _build_shops(v: Vector2) -> void:
	for shop in [["house_c", "tailor", "Sastrería"], ["house_d", "petshop", "Refugio de Lola"]]:
		var hp: Vector3 = anchors[shop[0]]
		var door: Vector3 = anchors[shop[0] + "_door"]
		var yaw: float = yaws[shop[0]]
		var out: Vector3 = door - hp
		out.y = 0.0
		out = out.normalized()
		var right := out.cross(Vector3.UP).normalized()
		anchors[shop[1] + "_spot"] = island.ground(Vector2(door.x, door.z) + Vector2(out.x, out.z) * 0.6 + Vector2(right.x, right.z) * 1.6)
		var sign_p := door + out * 2.2 - right * 2.0
		var sign_n := Props.signpost(shop[2])
		_place(sign_n, Vector2(sign_p.x, sign_p.z), yaw)
	# Tendedero con ropa delante de la sastrería.
	var tp: Vector3 = anchors["house_c"]
	var tout: Vector3 = anchors["house_c_door"] - tp
	tout.y = 0.0
	tout = tout.normalized()
	var tright: Vector3 = tout.cross(Vector3.UP).normalized()
	var line_p: Vector3 = tp + tright * 5.8 + tout * 1.0
	_place(Props.clothes_line(), Vector2(line_p.x, line_p.z), yaws["house_c"] + PI / 2)
	# Cercado del refugio con animales sueltos.
	var pp: Vector3 = anchors["house_d"]
	var pout: Vector3 = anchors["house_d_door"] - pp
	pout.y = 0.0
	pout = pout.normalized()
	var pright: Vector3 = pout.cross(Vector3.UP).normalized()
	var c3: Vector3 = pp - pright * 8.5 + pout * 1.5
	var c := Vector2(c3.x, c3.z)
	var yaw_d: float = yaws["house_d"]
	clear_zones.append(Vector3(c.x, c.y, 6.0))
	var half := 3.6
	for k in 4:
		var a := yaw_d + k * PI / 2.0
		var off := Vector2(sin(a), cos(a)) * half
		_place(Props.fence(7.2), c + off, a, 0.1)
	anchors["pen"] = island.ground(c)
	var animals := [["dog", [Color(0.55, 0.4, 0.3), Color(0.95, 0.92, 0.85)]], ["bunny", [Color(0.75, 0.62, 0.5), Color(1, 1, 1)]],
		["chick", [Color(1.0, 0.88, 0.35), Color(1.0, 0.5, 0.2)]], ["cat", [Color(1.0, 0.68, 0.35), Color(1, 0.95, 0.9)]]]
	for i in animals.size():
		var m: Node3D = Pet.build_model(animals[i][0], animals[i][1])
		add_child(m)
		var q := c + Vector2(cos(i * 1.7), sin(i * 1.7)) * 1.6
		m.position = island.ground(q)
		pen_animals.append([m, c, 2.4])
	# Comedero y caseta
	var trough := Props.barrel()
	_place(trough, c - Vector2(pright.x, pright.z) * 2.3 + Vector2(pout.x, pout.z) * 2.3)


func _add_bench(p: Vector2, yaw: float) -> void:
	_place(Props.bench(), p, yaw)
	# El asiento mira hacia +Z del banco; el avatar mira hacia -Z: se sienta girado media vuelta.
	var seat := island.ground(p) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.12)
	benches.append([seat, yaw + PI])


## Anillo de crecimiento en el corte del tocón (un aro fino apenas por encima de la madera).
func _place_ring(parent: Node3D, radius: float, col: Color) -> void:
	var ring := func(u: float, v: float) -> Vector3:
		var ang := v * TAU
		var r := radius * (1.0 + sin(ang * 3.0 + 1.0) * 0.05) + (u - 0.5) * 0.06
		return Vector3(cos(ang) * r, 5.1 + sin(ang * 2.0) * 0.18 * (r / 2.35) - (r / 2.35) * (r / 2.35) * 0.08 + 0.012, sin(ang) * r)
	MeshKit.part(parent, MeshKit.param_surface(ring, 1, 40, Vector3(0, -10, 0), true), MeshKit.mat(col), Vector3.ZERO)


func _at(n: Node3D, p: Vector2) -> Node3D:
	n.position = island.ground(p, -0.1)
	return n


# --- Muelle ---------------------------------------------------------------------------------

func _build_dock() -> void:
	var shore: Vector3 = anchors["shore"]
	var d := Props.dock(26.0)
	add_child(d)
	d.position = Vector3(shore.x, 0.0, shore.z - 8.0)
	var boat := Props.boat()
	add_child(boat)
	boat.position = Vector3(shore.x + 3.8, 0.1, shore.z + 12.0)
	anchors["boat"] = boat.position
	anchors["spawn"] = Vector3(shore.x, 1.5, shore.z + 13.0)
	yaws["spawn"] = 0.0
	anchors["tomeu"] = Vector3(shore.x - 0.8, 1.3, shore.z + 6.0)
	for k in 3:
		var c := Props.crate() if k < 2 else Props.barrel()
		add_child(c)
		c.position = Vector3(shore.x - 1.1, 1.25, shore.z + 1.0 + k * 1.0)
	anchors["dock_end"] = Vector3(shore.x + 1.0, 2.2, shore.z + 1.0)
	tomeu_boat = boat
	# Caseta de pescadores en la arena, con redes secándose.
	var hut_p := Vector2(shore.x + 14.0, shore.z - 7.0)
	var hut := Props.house(88, Color(0.3, 0.5, 0.7), Color(0.62, 0.46, 0.32), Vector3(4.6, 2.8, 4.0))
	add_child(hut)
	hut.position = Vector3(hut_p.x, _min_ground(hut_p, 2.5) - 0.05, hut_p.y)
	hut.rotation.y = PI * 0.5
	obstacles.append([hut.position, 3.6])
	var rack := Node3D.new()
	_place(rack, hut_p + Vector2(4.0, 4.0), 0.3, 0.1)
	for sx: int in [-1, 1]:
		Props._p(rack, MeshKit.cylinder(0.05, 0.06, 1.9, 6), Props.WOOD_DARK, Vector3(sx * 1.4, 0.95, 0))
	Props._p(rack, MeshKit.cylinder(0.03, 0.03, 3.0, 6), Props.WOOD_DARK, Vector3(0, 1.85, 0), Vector3(0, 0, 90))
	var net := func(u: float, v2: float) -> Vector3:
		return Vector3((u - 0.5) * 2.8, 1.85 - v2 * 1.3 - sin(u * PI) * 0.25, sin(v2 * PI) * 0.08)
	MeshKit.part(rack, MeshKit.double_sided(MeshKit.param_surface(net, 8, 6, Vector3(0, 5, -2), false)), MeshKit.surface_mat(Color(0.55, 0.62, 0.55), "cloth", 0.0, 0.5))


# --- Molino y Roca Aguja -------------------------------------------------------------------

func _build_windmill() -> void:
	var wm := Props.windmill()
	var p := Island.WINDMILL_HILL
	_place(wm["root"], p, yaw_towards(p, Island.VILLAGE), 0.4)
	windmill_hub = wm["hub"]
	anchors["windmill_top"] = island.ground(p, 9.6)
	var needle := Props.needle_rock(11.0)
	var np: Vector2 = Vector2(anchors["needle"].x, anchors["needle"].z)
	_place(needle, np, 0.0, 0.5)
	anchors["needle_top"] = island.ground(np, 11.0)


# --- Faros ----------------------------------------------------------------------------------

func _build_beacons() -> void:
	for id in REGION_COLORS:
		var p3: Vector3 = anchors[id]
		var p := Vector2(p3.x, p3.z)
		var height := 18.0 if id == "faro_summit" else 13.0
		var b := Props.beacon(REGION_COLORS[id], height)
		# El pedestal mira hacia el centro de la isla (por donde se llega).
		var face := Vector2(0, 40)
		if id == "faro_islet":
			face = Island.PENON
		var yaw := yaw_towards(p, face)
		add_child(b["root"])
		b["root"].position = Vector3(p.x, _min_ground(p, 2.5) - 0.1, p.y)
		b["root"].rotation.y = yaw
		beacons[id] = b
		var altar: Node3D = b["altar"]
		anchors[id + "_altar"] = b["root"].position + Basis(Vector3.UP, yaw) * (altar.position + Vector3(0, 0, 1.6))


# --- Ruinas -------------------------------------------------------------------------------------

func _build_ruins() -> void:
	var c := Island.RUINS
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for k in 9:
		var a := TAU * k / 9.0
		var p := c + Vector2(cos(a), sin(a)) * 26.0
		var tall := 5.0 + rng.randf() * 4.0
		var pillar := Props.ruin_pillar(tall, k % 3 == 1)
		_place(pillar, p, rng.randf() * TAU, 0.3)
		if k == 4:
			anchors["pillar_top"] = pillar.position + Vector3(0, tall + 1.0, 0)
	var arch := Props.ruin_arch(5.0, 5.0)
	_place(arch, c + Vector2(-10, 8), yaw_towards(c + Vector2(-10, 8), c) + PI / 2, 0.3)
	anchors["ruins_arch"] = island.ground(c + Vector2(-10, 8))
	anchors["ruins_arch_top"] = anchors["ruins_arch"] + Vector3(0, 5.72, 0)
	for k in 5:
		var p := c + Vector2(rng.randf_range(-18, 18), rng.randf_range(-18, 18))
		if p.distance_to(Vector2(anchors["faro_ruins"].x, anchors["faro_ruins"].z)) < 9.0:
			continue
		_place(Props.stone_block(Vector3(rng.randf_range(1.5, 3.0), rng.randf_range(0.6, 1.4), rng.randf_range(1.5, 3.0)), Props.STONE_DARK), p, rng.randf() * TAU, 0.3)
	# Torre de salida de la carrera, con escalones.
	var sp: Vector3 = anchors["race_start"]
	var spv := Vector2(sp.x, sp.z)
	var steps := [[Vector3(5, 1.5, 5), Vector2(0, 0)], [Vector3(3.6, 3.0, 3.6), Vector2(0, -0.4)], [Vector3(2.4, 4.6, 2.4), Vector2(0, -0.6)]]
	for s in steps:
		_place(Props.stone_block(s[0]), spv + s[1], 0.0, 0.2)
	anchors["race_top"] = Vector3(sp.x, island.height_at(spv.x, spv.y) - 0.2 + 4.6 + 0.1, sp.z - 0.6)
	_place(Props.stone_block(Vector3(1.6, 0.75, 1.6)), spv + Vector2(3.5, 2.8), 0.3, 0.2)
	_build_race_course()


## Anillos de la Carrera del Viento: bajan por la rampa de las ruinas hacia el suroeste,
## a una altura que se alcanza planeando desde la torre o corriendo y saltando.
func _build_race_course() -> void:
	var start: Vector3 = anchors["race_top"]
	var dir := Vector2(-0.62, 0.78).normalized()
	var side := Vector2(dir.y, -dir.x)
	var p := Vector2(start.x, start.z)
	var y := start.y
	for k in 8:
		var dist := 14.0 + k * 13.0
		var wiggle := sin(k * 1.3) * 9.0
		var q := Vector2(start.x, start.z) + dir * dist + side * wiggle
		var ground := island.height_at(q.x, q.y)
		var glide_y := start.y - dist / 4.0
		var ry := maxf(ground + 2.6, minf(glide_y, ground + 7.0))
		race_rings.append(Vector3(q.x, ry, q.y))
	anchors["race_end"] = race_rings[race_rings.size() - 1]


# --- Campamentos y cabañas ------------------------------------------------------------

func _build_camps() -> void:
	var lc: Vector3 = anchors["lake_cabin"]
	var lcp := Vector2(lc.x, lc.z)
	var cabin := Props.cabin()
	_place(cabin, lcp + Vector2(4, 0), yaw_towards(lcp, Island.LAKE), 0.3)
	obstacles.append([island.ground(lcp + Vector2(4, 0)), 4.2])
	anchors["ulises"] = island.ground(lcp + (Island.LAKE - lcp).normalized() * 4.0)
	var fire := Props.campfire()
	_place(fire["root"], lcp + (Island.LAKE - lcp).normalized() * 7.0 + Vector2(3, 0))
	obstacles.append([island.ground(lcp + (Island.LAKE - lcp).normalized() * 7.0 + Vector2(3, 0)), 1.6])
	flames.append(fire["flame"])
	var rc: Vector3 = anchors["ruins_camp"]
	var rcp := Vector2(rc.x, rc.z)
	_place(Props.tent(Color(0.95, 0.65, 0.3)), rcp + Vector2(3, -3), 0.6)
	obstacles.append([island.ground(rcp + Vector2(3, -3)), 2.8])
	var f2 := Props.campfire()
	_place(f2["root"], rcp + Vector2(-1, 2))
	obstacles.append([island.ground(rcp + Vector2(-1, 2)), 1.5])
	obstacles.append([island.ground(rcp + Vector2(5.5, 1.0)), 1.2])
	flames.append(f2["flame"])
	_place(Props.crate(), rcp + Vector2(5.5, 1.0))
	anchors["gema"] = island.ground(rcp + Vector2(-2.5, 0))
	var ch: Vector3 = anchors["cliff_hut"]
	var chp := Vector2(ch.x, ch.z)
	var hut := Props.house(77, Color(0.3, 0.45, 0.7), Color(0.88, 0.86, 0.8), Vector3(4.6, 3.0, 4.0))
	add_child(hut)
	hut.position = Vector3(chp.x, _min_ground(chp, 2.5) - 0.05, chp.y)
	hut.rotation.y = yaw_towards(chp, Island.VILLAGE)
	anchors["olga"] = island.ground(chp + (Island.VILLAGE - chp).normalized() * 4.6)
	var pf: Vector3 = anchors["penon_foot"]
	var pfp := Vector2(pf.x, pf.z)
	_add_bench(pfp + Vector2(2, 1), 0.8)
	anchors["tito"] = island.ground(pfp)
	var sp := Props.signpost("Peñón del Salto")
	_place(sp, pfp + Vector2(-3, -2), yaw_towards(pfp, Island.VILLAGE))


func _build_extras() -> void:
	# Updrafts: en lo alto del Peñón (hacia el islote) y al pie de la rampa de las ruinas.
	var pe: Vector3 = anchors["penon"]
	var ud := Props.updraft(26.0, 3.5)
	add_child(ud)
	var to_islet := (Island.ISLET - Vector2(pe.x, pe.z)).normalized()
	var ud_p := Vector2(pe.x, pe.z) + to_islet * 14.0
	ud.position = Vector3(ud_p.x, island.height_at(ud_p.x, ud_p.y) - 2.0, ud_p.y)
	anchors["updraft_penon"] = ud.position
	var ud2 := Props.updraft(30.0, 3.5)
	add_child(ud2)
	var u2 := Vector2(96, -64)
	ud2.position = island.ground(u2, -0.5)
	anchors["updraft_ruins"] = ud2.position
	# Tocón gigante del bosque
	var st: Vector3 = anchors["stump"]
	var stump := Node3D.new()
	add_child(stump)
	stump.position = st - Vector3(0, 0.3, 0)
	# Tronco con corteza y contrafuertes de raíces, corte irregular y anillos en la madera.
	var trunk := func(u: float, v: float) -> Vector3:
		var ang := v * TAU
		var y := u * 5.1
		var r := 2.35 + sin(ang * 3.0 + 1.0) * 0.12 + sin(ang * 7.0) * 0.05
		var root_k := pow(1.0 - clampf(u / 0.3, 0.0, 1.0), 2.0)
		r *= 1.0 + root_k * (0.35 + 0.6 * pow(absf(cos(ang * 2.5)), 4.0))
		y += sin(ang * 2.0) * 0.18 * u
		return Vector3(cos(ang) * r, y, sin(ang) * r)
	MeshKit.part(stump, MeshKit.param_surface(trunk, 12, 40, Vector3(0, 2.5, 0), true), MeshKit.surface_mat(Color(0.5, 0.36, 0.25), "bark", 0.1, 0.5), Vector3.ZERO)
	var top := func(u: float, v: float) -> Vector3:
		var ang := v * TAU
		var r := u * 2.35 * (1.0 + sin(ang * 3.0 + 1.0) * 0.05)
		return Vector3(cos(ang) * r, 5.1 + sin(ang * 2.0) * 0.18 * u - u * u * 0.08, sin(ang) * r)
	var ring_mat := MeshKit.mat(Color(0.86, 0.7, 0.46))
	MeshKit.part(stump, MeshKit.param_surface(top, 8, 40, Vector3(0, 0, 0), true), ring_mat, Vector3.ZERO)
	for k in range(1, 5):
		_place_ring(stump, k * 0.45, Color(0.72, 0.55, 0.34))
	var sb := Props.body(stump)
	Props.cyl_col(sb, 2.5, 5.2, Vector3(0, 2.6, 0))
	anchors["stump_top"] = stump.position + Vector3(0, 5.3, 0)
	# Farallón en el mar (noreste)
	var ss := anchors["sea_stack"] as Vector3
	var stack := Props.needle_rock(16.0)
	add_child(stack)
	stack.position = Vector3(ss.x, minf(ss.y, -1.0) - 1.0, ss.z)
	anchors["sea_stack_top"] = stack.position + Vector3(0, 16.4, 0)
	# Pila de piedras (marca de camino) para la chispa del bosque: dos rocas grandes apiladas.
	var spark_b := Vector2(-236, -6)
	var pile := Node3D.new()
	add_child(pile)
	pile.position = island.ground(spark_b, -0.3)
	MeshKit.part(pile, MeshKit.rock(901, 0.7), MeshKit.surface_mat(Props.STONE_DARK, "stone", 0.1), Vector3(0, 0.75, 0), Vector3(0, 20, 0), Vector3(1.8, 1.5, 1.7))
	MeshKit.part(pile, MeshKit.rock(902, 0.75), MeshKit.surface_mat(Props.STONE, "stone", 0.1), Vector3(0.2, 2.75, -0.1), Vector3(0, 70, 4), Vector3(1.2, 1.25, 1.15))
	MeshKit.part(pile, MeshKit.blob(0.5, 0.35, 0.25, 7, 12), MeshKit.mat(Color(0.42, 0.6, 0.3)), Vector3(-0.9, 1.6, 0.8))
	var pb := Props.body(pile)
	Props.cyl_col(pb, 1.7, 2.0, Vector3(0, 1.0, 0))
	Props.cyl_col(pb, 1.1, 1.8, Vector3(0.2, 2.9, -0.1))
	anchors["rock_stack_top"] = island.ground(spark_b, 4.2)
	clear_zones.append(Vector3(spark_b.x, spark_b.y, 4.0))
