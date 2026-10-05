class_name Farm
extends Node3D
## Granja del Prado: casa de Amparo, granero, silo, gallinero, huerto, manzanos y un prado
## vallado con ovejas y vacas que pastan y pasean. Se construye en coordenadas locales
## (+Z = fachada, hacia el camino) y cada pieza se apoya en el terreno.

const CENTER := Vector2(66, 30)
const FRONT_TO := Vector2(30, 40)
## Prado (local): x de 15 a 32, z de -4 a 16.
const PASTURE := Rect2(15, -4, 17, 20)
## Corral del gallinero (local).
const COOP_RUN := Rect2(-15, -3.5, 6, 5)

var island: Island
var places: Places
var yaw := 0.0
## Ovejas del prado: [{model, goal, wait, phase, sheared}]; vacas y gallinas igual.
var sheep: Array = []
var cows: Array = []
var chickens: Array = []
## Manzanos: [{pos (mundo), fruit: Node3D con las manzanas}]
var apple_trees: Array = []
var coop_pos := Vector3.ZERO
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func build(isl: Island, pl: Places) -> void:
	island = isl
	places = pl
	_rng.seed = 909
	yaw = Places.yaw_towards(CENTER, FRONT_TO)
	position = island.ground(CENTER)
	rotation.y = yaw
	pl.clear_zones.append(Vector3(CENTER.x, CENTER.y, 38.0))
	_farmhouse()
	_barn()
	_silo()
	_coop()
	_pasture()
	_crops()
	_orchard()
	_details()


## Punto local (x, z) en el mundo, apoyado en el suelo.
func world_at(lx: float, lz: float, lift := 0.0) -> Vector3:
	var w := global_transform * Vector3(lx, 0, lz) if is_inside_tree() else position + Basis(Vector3.UP, yaw) * Vector3(lx, 0, lz)
	return island.ground(Vector2(w.x, w.z), lift)


## Coloca `n` en el punto local (x, z), girado `local_yaw` y apoyado en el terreno.
func _put(n: Node3D, lx: float, lz: float, local_yaw := 0.0, sink := 0.1) -> Node3D:
	add_child(n)
	var w := world_at(lx, lz)
	n.position = Vector3(lx, w.y - position.y - sink, lz)
	n.rotation.y = local_yaw
	return n


func _obstacle(lx: float, lz: float, r: float) -> void:
	places.obstacles.append([world_at(lx, lz), r])


# --- Edificios -------------------------------------------------------------------------

func _farmhouse() -> void:
	var h := Props.house(321, Color(0.36, 0.56, 0.3), Props.WHITE_WALL, Vector3(6.5, 3.6, 5.2))
	_put(h, -6, 10, 0.0, 0.05)
	places.anchors["farmhouse"] = world_at(-6, 10)
	places.anchors["amparo_spot"] = world_at(-3.5, 15.2)
	_obstacle(-6, 10, 5.0)


## Granero rojo con tejado holandés (dos pendientes por lado), portón en aspa y pajar.
func _barn() -> void:
	var root := Node3D.new()
	_put(root, 6, -6, 0.0, 0.05)
	var w := 9.0
	var hgt := 5.0
	var d := 11.0
	var red := Color(0.72, 0.22, 0.18)
	var trim := Color(0.96, 0.94, 0.88)
	MeshKit.part(root, MeshKit.soft_box(Vector3(w + 0.3, 0.5, d + 0.3), 0.1, 0.03, 0.0, 41), Props._m(Props.STONE_DARK), Vector3(0, 0.25, 0))
	MeshKit.part(root, MeshKit.soft_box(Vector3(w, hgt, d), 0.12, 0.03, 0.0, 42), MeshKit.surface_mat(red, "wood", 0.1), Vector3(0, hgt * 0.5 + 0.4, 0))
	# Tablas verticales y esquinas blancas.
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			Props._box(root, Vector3(0.24, hgt, 0.24), trim, Vector3(sx * w * 0.5, hgt * 0.5 + 0.4, sz * d * 0.5))
	# Tejado holandés: pendiente fuerte abajo y suave arriba, en cada lado.
	var top := hgt + 0.4
	var roof := Color(0.42, 0.42, 0.46)
	var pts := [Vector2(w * 0.5 + 0.5, top), Vector2(w * 0.32, top + 2.0), Vector2(0.0, top + 3.0)]
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var mid := (a + b) * 0.5
			var rz := rad_to_deg(atan2(b.y - a.y, sx * (b.x - a.x)))
			MeshKit.part(root, MeshKit.soft_box(Vector3(a.distance_to(b) + 0.3, 0.2, d + 0.8), 0.06, 0.03, 0.0, 43 + k), MeshKit.surface_mat(roof, "tile", 0.08),
				Vector3(sx * mid.x, mid.y + 0.1, 0), Vector3(0, 0, rz))
	# Hastiales (frontal y trasero) con el contorno del tejado.
	var gable := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(w * 0.32, 1.85), Vector2(0, 2.85), Vector2(-w * 0.32, 1.85)])
	for sz: int in [-1, 1]:
		Props._prism(root, gable, 0.2, red, Vector3(0, top, sz * (d * 0.5 - 0.1)))
	# Portón doble con aspas blancas y puerta del pajar.
	for sx: int in [-1, 1]:
		var door := Node3D.new()
		door.position = Vector3(sx * 1.3, 1.9, d * 0.5 + 0.06)
		root.add_child(door)
		Props._box(door, Vector3(2.5, 3.0, 0.12), red.darkened(0.1), Vector3.ZERO)
		Props._box(door, Vector3(2.6, 0.16, 0.16), trim, Vector3(0, 1.45, 0.04))
		Props._box(door, Vector3(2.6, 0.16, 0.16), trim, Vector3(0, -1.45, 0.04))
		Props._box(door, Vector3(0.16, 3.0, 0.16), trim, Vector3(sx * 1.22, 0, 0.04))
		Props._box(door, Vector3(0.14, 3.6, 0.1), trim, Vector3(0, 0, 0.06), Vector3(0, 0, 40))
		Props._box(door, Vector3(0.14, 3.6, 0.1), trim, Vector3(0, 0, 0.06), Vector3(0, 0, -40))
	Props._box(root, Vector3(1.8, 1.5, 0.12), red.darkened(0.1), Vector3(0, top + 0.9, d * 0.5 + 0.08))
	Props._box(root, Vector3(2.0, 0.14, 0.16), trim, Vector3(0, top + 1.7, d * 0.5 + 0.1))
	Props._box(root, Vector3(2.0, 0.14, 0.16), trim, Vector3(0, top + 0.12, d * 0.5 + 0.1))
	# Paja asomando por el pajar.
	MeshKit.part(root, MeshKit.blob(0.7, 0.45, 0.3, 8, 14), MeshKit.surface_mat(Color(0.9, 0.78, 0.45), "thatch", 0.0), Vector3(0, top + 0.3, d * 0.5 + 0.35))
	var b := Props.body(root)
	Props.box_col(b, Vector3(w, hgt + 3.0, d), Vector3(0, (hgt + 3.0) * 0.5 + 0.4, 0))
	_obstacle(6, -6, 7.5)


func _silo() -> void:
	var root := Node3D.new()
	_put(root, 12.8, -12.5, 0.0, 0.1)
	var metal := Color(0.75, 0.78, 0.8)
	Props._p(root, MeshKit.lathe(PackedVector2Array([Vector2(2.2, 0), Vector2(2.2, 9.5), Vector2(0.0, 9.5)]), 18), metal)
	for k in 6:
		Props._p(root, MeshKit.torus(2.18, 2.3), metal.darkened(0.15), Vector3(0, 1.2 + k * 1.5, 0))
	Props._p(root, MeshKit.lathe(PackedVector2Array([Vector2(2.35, 0), Vector2(2.1, 0.7), Vector2(1.2, 1.7), Vector2(0.3, 2.1), Vector2(0.0, 2.2)]), 18), Color(0.72, 0.22, 0.18), Vector3(0, 9.45, 0))
	var b := Props.body(root)
	Props.cyl_col(b, 2.25, 11.5, Vector3(0, 5.75, 0))
	_obstacle(12.8, -12.5, 3.2)


## Gallinero sobre patas con rampa, ponedero y corral de malla.
func _coop() -> void:
	var root := Node3D.new()
	_put(root, -12, -7, 0.0, 0.05)
	var wood := Color(0.8, 0.62, 0.38)
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			Props._p(root, MeshKit.cylinder(0.08, 0.09, 0.9, 8), Props.WOOD_DARK, Vector3(sx * 1.3, 0.45, sz * 0.9))
	Props._box(root, Vector3(3.0, 1.6, 2.2), wood, Vector3(0, 1.7, 0))
	Props._box(root, Vector3(3.5, 0.15, 2.8), Color(0.72, 0.22, 0.18), Vector3(0, 2.62, 0.05), Vector3(14, 0, 0))
	Props._box(root, Vector3(0.6, 0.7, 0.08), Props.WOOD_DARK, Vector3(0.6, 1.4, 1.12))
	# Rampa con travesaños.
	Props._box(root, Vector3(0.5, 0.05, 1.6), Props.WOOD, Vector3(0.6, 0.55, 1.8), Vector3(-34, 0, 0))
	for k in 4:
		Props._box(root, Vector3(0.5, 0.05, 0.05), Props.WOOD_DARK, Vector3(0.6, 0.25 + k * 0.22, 2.35 - k * 0.32))
	# Ponedero lateral con paja.
	Props._box(root, Vector3(0.8, 0.6, 1.4), wood.darkened(0.08), Vector3(-1.85, 1.5, 0))
	MeshKit.part(root, MeshKit.blob(0.35, 0.4, 0.3, 4, 12), MeshKit.surface_mat(Color(0.9, 0.78, 0.45), "thatch", 0.0), Vector3(-1.85, 1.85, 0))
	coop_pos = world_at(-12, -4.5)
	places.anchors["coop"] = coop_pos
	_obstacle(-12, -7, 2.4)
	# Corral: valla baja alrededor.
	var r := COOP_RUN
	for side in [[r.position.x + r.size.x * 0.5, r.position.y, r.size.x, 0.0], [r.position.x + r.size.x * 0.5, r.end.y, r.size.x, 0.0],
			[r.position.x, r.position.y + r.size.y * 0.5, r.size.y, PI / 2], [r.end.x, r.position.y + r.size.y * 0.5, r.size.y, PI / 2]]:
		var f := Props.fence(side[2])
		f.scale = Vector3(1.0, 0.7, 1.0)
		_put(f, side[0], side[1], side[3], 0.05)
	for k in 6:
		var c := Animals.chicken(k)
		_put(c, _rng.randf_range(r.position.x + 0.6, r.end.x - 0.6), _rng.randf_range(r.position.y + 0.6, r.end.y - 0.6), _rng.randf() * TAU, 0.0)
		chickens.append({"model": c, "goal": c.position, "wait": _rng.randf_range(0.2, 2.0), "phase": 0.0, "rect": r, "speed": 1.2})


func _pasture() -> void:
	var r := PASTURE
	for side in [[r.position.x + r.size.x * 0.5, r.position.y, r.size.x, 0.0], [r.position.x + r.size.x * 0.5, r.end.y, r.size.x, 0.0],
			[r.position.x, r.position.y + r.size.y * 0.5, r.size.y, PI / 2], [r.end.x, r.position.y + r.size.y * 0.5, r.size.y, PI / 2]]:
		_put(Props.fence(side[2]), side[0], side[1], side[3], 0.05)
	places.anchors["pasture"] = world_at(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5)
	# Abrevadero
	var trough := Node3D.new()
	_put(trough, 18.5, 1.0, 0.3, 0.05)
	Props._box(trough, Vector3(2.0, 0.55, 0.7), Props.WOOD, Vector3(0, 0.28, 0))
	var water := MeshKit.part(trough, MeshKit.rounded_box(Vector3(1.8, 0.05, 0.5), 0.02, 2), MeshKit.mat(Color(0.4, 0.7, 0.85), 0.0, 0.2), Vector3(0, 0.5, 0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 5:
		var s := Animals.sheep(k)
		_put(s, _rng.randf_range(r.position.x + 1.5, r.end.x - 1.5), _rng.randf_range(r.position.y + 1.5, r.end.y - 1.5), _rng.randf() * TAU, 0.0)
		sheep.append({"model": s, "goal": s.position, "wait": _rng.randf_range(1.0, 6.0), "phase": 0.0, "rect": r, "speed": 0.9, "sheared": -1})
	for k in 2:
		var c := Animals.cow(k)
		_put(c, _rng.randf_range(r.position.x + 3.0, r.end.x - 3.0), _rng.randf_range(r.position.y + 3.0, r.end.y - 3.0), _rng.randf() * TAU, 0.0)
		cows.append({"model": c, "goal": c.position, "wait": _rng.randf_range(2.0, 8.0), "phase": 0.0, "rect": r.grow(-1.5), "speed": 0.7})


## Huerto: surcos de tierra con coles y trigo, y un espantapájaros.
func _crops() -> void:
	var soil := MeshKit.surface_mat(Color(0.4, 0.3, 0.21), "plaster", 0.0)
	var cabbage := _combine_cabbage()
	var wheat := _wheat_tuft()
	for row in 6:
		var x := -29.0 + row * 2.3
		# El surco va en tramos que siguen el terreno.
		for seg in 4:
			_put(_soil_row(soil), x, 5.5 + seg * 4.1, 0.0, 0.12)
		var xf := []
		for k in 9:
			var z := 5.0 + k * 1.75
			var w := world_at(x, z)
			xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.85, 1.15)), Vector3(x, w.y - position.y + 0.05, z)))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cabbage if row % 2 == 0 else wheat
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	_scarecrow()


static func _soil_row(mat: Material) -> Node3D:
	var n := Node3D.new()
	MeshKit.part(n, MeshKit.soft_box(Vector3(1.3, 0.3, 4.4), 0.12, 0.05, 0.0, 77), mat, Vector3(0, 0.05, 0))
	return n


static func _combine_cabbage() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(MeshKit.blob(0.32, 0.8, 0.15, 3, 12), 0, Transform3D(Basis(), Vector3(0, 0.22, 0)))
	for k in 5:
		var a := TAU * k / 5.0
		st.append_from(MeshKit.blob(0.26, 0.35, 0.2, k, 10), 0, Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.6), Vector3(cos(a) * 0.2, 0.15, sin(a) * 0.2)))
	var mesh := st.commit()
	mesh.surface_set_material(0, MeshKit.surface_mat(Color(0.5, 0.75, 0.38), "cloth", 0.15))
	return mesh


static func _wheat_tuft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for k in 9:
		var a := r.randf() * TAU
		var tilt := Basis(Vector3(cos(a), 0, sin(a)), r.randf_range(0.0, 0.25))
		var h := r.randf_range(0.8, 1.15)
		st.append_from(MeshKit.cylinder(0.012, 0.018, h, 5), 0, Transform3D(tilt, tilt * Vector3(0, h * 0.5, 0) + Vector3(cos(a), 0, sin(a)) * 0.12))
		st.append_from(MeshKit.blob(0.035, 3.0, 0.1, k, 8), 0, Transform3D(tilt, tilt * Vector3(0, h + 0.06, 0) + Vector3(cos(a), 0, sin(a)) * 0.12))
	var mesh := st.commit()
	mesh.surface_set_material(0, MeshKit.surface_mat(Color(0.92, 0.78, 0.42), "thatch", 0.1))
	return mesh


func _scarecrow() -> void:
	var root := Node3D.new()
	_put(root, -23.0, 13.0, 0.4, 0.2)
	Props._p(root, MeshKit.cylinder(0.06, 0.07, 2.4, 8), Props.WOOD_DARK, Vector3(0, 1.2, 0))
	Props._p(root, MeshKit.cylinder(0.05, 0.05, 1.8, 8), Props.WOOD_DARK, Vector3(0, 1.75, 0), Vector3(0, 0, 90))
	MeshKit.part(root, MeshKit.lathe(PackedVector2Array([Vector2(0.0, -0.2), Vector2(0.3, -0.2), Vector2(0.34, 0.3), Vector2(0.24, 0.6), Vector2(0.0, 0.62)]), 10),
		MeshKit.surface_mat(Color(0.35, 0.5, 0.75), "cloth", 0.1), Vector3(0, 1.35, 0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(root, MeshKit.capsule(0.09, 0.75), MeshKit.surface_mat(Color(0.35, 0.5, 0.75), "cloth", 0.1), Vector3(sx * 0.5, 1.75, 0), Vector3(0, 0, 90))
		MeshKit.part(root, MeshKit.blob(0.1, 1.5, 0.3, 3, 8), MeshKit.surface_mat(Color(0.9, 0.78, 0.45), "thatch", 0.0), Vector3(sx * 0.92, 1.72, 0), Vector3(0, 0, 90))
	MeshKit.part(root, MeshKit.blob(0.22, 1.05, 0.1, 6, 12), MeshKit.surface_mat(Color(0.86, 0.76, 0.58), "cloth", 0.1), Vector3(0, 2.25, 0))
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(root, MeshKit.sphere(0.03, 8), MeshKit.mat(Color(0.1, 0.08, 0.08)), Vector3(sx * 0.07, 2.3, -0.2))
	Props._p(root, MeshKit.cylinder(0.42, 0.42, 0.03, 16), Color(0.92, 0.8, 0.5), Vector3(0, 2.42, 0))
	Props._p(root, MeshKit.cylinder(0.17, 0.22, 0.2, 14), Color(0.92, 0.8, 0.5), Vector3(0, 2.52, 0))


## Manzanos con manzanas que se pueden recoger (se sacuden y caen).
func _orchard() -> void:
	var trunk := Flora.trunk_mesh(2.6, 0.2)
	var bark := MeshKit.surface_mat(Color(0.5, 0.36, 0.25), "bark", 0.1)
	var crown := Flora.leafy_clump(1.6, 0.85, Color(0.55, 0.78, 0.36), 31)
	for k in 6:
		var lx := -27.0 + (k % 3) * 5.0
		var lz := -15.0 + (k / 3) * 6.0
		var root := Node3D.new()
		_put(root, lx, lz, _rng.randf() * TAU, 0.15)
		MeshKit.part(root, trunk, bark, Vector3.ZERO)
		var crown_mi := MeshInstance3D.new()
		crown_mi.mesh = crown
		crown_mi.position = Vector3(0, 3.0, 0)
		root.add_child(crown_mi)
		var fruit := Node3D.new()
		fruit.name = "Fruit"
		root.add_child(fruit)
		for a in 7:
			var ang := TAU * a / 7.0 + _rng.randf()
			var p := Vector3(cos(ang) * 1.45, 2.4 + _rng.randf_range(0.0, 1.2), sin(ang) * 1.45)
			MeshKit.part(fruit, MeshKit.sphere(0.11, 12), MeshKit.mat(Color(0.85, 0.18, 0.15) if a % 3 != 0 else Color(0.95, 0.75, 0.2)), p)
		apple_trees.append({"pos": world_at(lx, lz), "fruit": fruit, "node": root})
		_obstacle(lx, lz, 1.0)


func _details() -> void:
	for p in [[2.5, 2.5, 0.2], [4.0, 3.2, 1.1], [-1.5, -1.5, 0.6]]:
		var bale := Node3D.new()
		_put(bale, p[0], p[1], p[2], 0.05)
		Props._p(bale, MeshKit.cylinder(0.55, 0.55, 1.0, 16), Color(0.92, 0.8, 0.48), Vector3(0, 0.55, 0), Vector3(0, 0, 90))
		var b := Props.body(bale)
		Props.box_col(b, Vector3(1.0, 1.1, 1.1), Vector3(0, 0.55, 0))
	_put(Props.barrel(), 9.5, 0.5, 0.0, 0.05)
	_put(Props.crate(), -3.0, -2.0, 0.5, 0.05)
	var sign_n := Props.signpost("Granja del Prado")
	_put(sign_n, -2.0, 22.0, PI * 0.1, 0.1)


# --- Animales --------------------------------------------------------------------------------

func _process(dt: float) -> void:
	_t += dt
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(global_position) > 160.0:
		return
	for group in [sheep, cows, chickens]:
		for a in group:
			_wander(a, dt)


func _wander(a: Dictionary, dt: float) -> void:
	var m: Node3D = a["model"]
	var goal: Vector3 = a["goal"]
	var to := goal - m.position
	to.y = 0.0
	var moving := false
	if a["wait"] > 0.0:
		a["wait"] -= dt
		if a["wait"] <= 0.0:
			var r: Rect2 = a["rect"]
			a["goal"] = Vector3(_rng.randf_range(r.position.x + 0.8, r.end.x - 0.8), 0, _rng.randf_range(r.position.y + 0.8, r.end.y - 0.8))
	elif to.length() > 0.2:
		var step := to.normalized() * minf(float(a["speed"]) * dt, to.length())
		m.position += step
		var w := world_at(m.position.x, m.position.z)
		m.position.y = w.y - position.y
		m.rotation.y = rotate_toward(m.rotation.y, atan2(-to.x, -to.z), dt * 3.0)
		a["phase"] = float(a["phase"]) + dt * float(a["speed"]) * 7.0
		moving = true
	else:
		a["wait"] = _rng.randf_range(2.0, 9.0)
	var grazing := 0.0 if moving else (0.5 + 0.5 * sin(_t * 0.7 + m.position.x))
	Animals.animate(m, a["phase"], moving, grazing, _t)
