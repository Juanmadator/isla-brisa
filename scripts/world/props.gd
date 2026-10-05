class_name Props
extends RefCounted
## Modelos procedurales del mundo: casas, molino, faros, muelle, ruinas, cofres,
## coleccionables... Todos con cel-shading y contorno. Los que se pueden pisar o escalar
## llevan colisión (StaticBody3D).

const WOOD := Color(0.62, 0.43, 0.28)
const WOOD_DARK := Color(0.45, 0.3, 0.2)
const STONE := Color(0.78, 0.76, 0.7)
const STONE_DARK := Color(0.6, 0.58, 0.55)
const WHITE_WALL := Color(0.97, 0.94, 0.86)
const WINDOW := Color(0.2, 0.28, 0.4)
const GOLD := Color(1.0, 0.82, 0.3)


static func _m(c: Color, _outline := 0.03) -> ShaderMaterial:
	return MeshKit.surface_mat(c, surface_for(c))


## Material que corresponde a un color de la paleta: marrones = madera, grises = piedra,
## casi blancos = enlucido. El resto (tejados, telas, metal, cristal), sin dibujo.
static func surface_for(c: Color) -> String:
	if c.s < 0.25 and c.v > 0.86:
		return "plaster"
	if c.s < 0.25 and c.v >= 0.4:
		return "stone"
	if c.h > 0.02 and c.h < 0.13 and c.s > 0.3 and c.v < 0.8 and c.v > 0.15:
		return "wood"
	return ""


static func _p(parent: Node3D, mesh: Mesh, c: Color, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, outline := 0.03) -> MeshInstance3D:
	return MeshKit.part(parent, mesh, _m(c, outline), pos, rot, scl)


static func _box(parent: Node3D, size: Vector3, c: Color, pos := Vector3.ZERO, rot := Vector3.ZERO, radius := 0.05, outline := 0.03) -> MeshInstance3D:
	return _p(parent, MeshKit.rounded_box(size, radius, 2), c, pos, rot, Vector3.ONE, outline)


## Cristal de ventana: azul oscuro de día y luz cálida de noche (lo enciende el shader).
static func glass() -> ShaderMaterial:
	return MeshKit.night_glow_mat(WINDOW, 1.6)


static func body(parent: Node3D) -> StaticBody3D:
	var b := StaticBody3D.new()
	parent.add_child(b)
	return b


static func box_col(b: StaticBody3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	cs.rotation_degrees = rot
	b.add_child(cs)


static func cyl_col(b: StaticBody3D, radius: float, height: float, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	cs.shape = s
	cs.position = pos
	b.add_child(cs)


## Prisma triangular (tejado a dos aguas) de ancho `w`, alto `h` y fondo `d`, centrado.
static func roof_mesh(w: float, h: float, d: float) -> ArrayMesh:
	var poly := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(0, -h)])
	var m := MeshKit.extrude(poly, d)
	return m


static func _roof(parent: Node3D, w: float, h: float, d: float, c: Color, pos: Vector3, yaw := 0.0) -> MeshInstance3D:
	# extrude() levanta en Y un polígono XZ: lo giramos para que el triángulo quede de pie.
	# Girar +90° en X lleva el vértice (z = -h) hacia arriba y la extrusión (Y) hacia +Z.
	var mi := _p(parent, roof_mesh(w, h, d), c, pos, Vector3(90, yaw, 0), Vector3.ONE, 0.045)
	mi.position = pos + Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)) * Vector3(0, 0, -d * 0.5)
	return mi


# --- Casas ----------------------------------------------------------------------

static func house(seed_value: int, roof_color: Color, wall := WHITE_WALL, size := Vector3(6.0, 3.6, 5.0)) -> Node3D:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var root := Node3D.new()
	var w := size.x
	var h := size.y
	var d := size.z
	var top := h + 0.3
	# Zócalo de piedra y paredes
	MeshKit.part(root, MeshKit.soft_box(Vector3(w + 0.3, 0.6, d + 0.3), 0.12, 0.035, 0.0, seed_value), _m(STONE_DARK), Vector3(0, 0.3, 0))
	MeshKit.part(root, MeshKit.soft_box(Vector3(w, h, d), 0.14, 0.03, 0.025, seed_value + 1), _m(wall), Vector3(0, h * 0.5 + 0.3, 0))
	# Entramado de madera: pilares en las esquinas y viga corrida arriba.
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			_box(root, Vector3(0.28, h, 0.28), WOOD_DARK, Vector3(sx * w * 0.5, h * 0.5 + 0.3, sz * d * 0.5), Vector3.ZERO, 0.04, 0.025)
	for sz: int in [-1, 1]:
		_box(root, Vector3(w + 0.1, 0.24, 0.2), WOOD_DARK, Vector3(0, top - 0.1, sz * d * 0.5), Vector3.ZERO, 0.04, 0.025)
	for sx: int in [-1, 1]:
		_box(root, Vector3(0.2, 0.24, d + 0.1), WOOD_DARK, Vector3(sx * w * 0.5, top - 0.1, 0), Vector3.ZERO, 0.04, 0.025)
	# Tejado
	var roof_h := w * 0.42
	_gable_roof(root, w, d, top, roof_h, roof_color, wall)
	# Puerta (fachada sur, +Z) con marco, tejadillo y escalón
	var door_x := -w * 0.18
	_box(root, Vector3(1.5, 2.3, 0.1), WOOD_DARK, Vector3(door_x, 1.4, d * 0.5 + 0.02), Vector3.ZERO, 0.04, 0.025)
	_box(root, Vector3(1.2, 2.1, 0.12), WOOD, Vector3(door_x, 1.35, d * 0.5 + 0.06), Vector3.ZERO, 0.05, 0.025)
	for k in 2:
		_box(root, Vector3(1.0, 0.06, 0.04), WOOD_DARK, Vector3(door_x, 0.85 + k * 1.0, d * 0.5 + 0.13), Vector3.ZERO, 0.01, 0.0)
	_p(root, MeshKit.sphere(0.06, 6), GOLD, Vector3(door_x + 0.4, 1.35, d * 0.5 + 0.15), Vector3.ZERO, Vector3.ONE, 0.0)
	_box(root, Vector3(1.9, 0.1, 0.8), roof_color, Vector3(door_x, 2.75, d * 0.5 + 0.4), Vector3(18, 0, 0), 0.03, 0.025)
	for sx: int in [-1, 1]:
		_box(root, Vector3(0.08, 0.08, 0.6), WOOD_DARK, Vector3(door_x + sx * 0.75, 2.58, d * 0.5 + 0.3), Vector3(-35, 0, 0), 0.02, 0.015)
	_box(root, Vector3(1.7, 0.2, 0.7), STONE, Vector3(door_x, 0.1, d * 0.5 + 0.5), Vector3.ZERO, 0.05, 0.03)
	# Ventanas con contraventanas (la de la fachada, con jardinera)
	_window(root, Vector3(w * 0.22, h * 0.55 + 0.3, d * 0.5 + 0.03), 0.0, roof_color, true, r.randi())
	_window(root, Vector3(w * 0.5 + 0.03, h * 0.55 + 0.3, 0), 90.0, roof_color)
	_window(root, Vector3(-w * 0.5 - 0.03, h * 0.55 + 0.3, 0), -90.0, roof_color)
	# Ojo de buey en el hastial
	var oy := top + roof_h * 0.38
	MeshKit.part(root, MeshKit.cylinder(0.36, 0.36, 0.1, 14), glass(), Vector3(0, oy, d * 0.5 + 0.02), Vector3(90, 0, 0))
	_p(root, MeshKit.torus(0.34, 0.46), WOOD_DARK, Vector3(0, oy, d * 0.5 + 0.06), Vector3(90, 0, 0), Vector3.ONE, 0.02)
	_box(root, Vector3(0.1, 0.32, 0.02), WINDOW.lightened(0.4), Vector3(-0.08, oy + 0.04, d * 0.5 + 0.08), Vector3(0, 0, -35), 0.01, 0.0)
	# Chimenea
	if r.randf() < 0.7:
		var cx := w * 0.25
		var cy := top + roof_h * (1.0 - cx / ((w + 1.1) * 0.5))
		MeshKit.part(root, MeshKit.soft_box(Vector3(0.7, 1.7, 0.7), 0.08, 0.02, 0.06, seed_value + 2), _m(STONE), Vector3(cx, cy + 0.35, -d * 0.2), Vector3(0, 0, r.randf_range(-2.0, 2.0)))
		_box(root, Vector3(0.86, 0.18, 0.86), STONE_DARK, Vector3(cx, cy + 1.2, -d * 0.2), Vector3.ZERO, 0.04, 0.025)
		root.add_child(smoke(Vector3(cx, cy + 1.4, -d * 0.2)))
	# Macetas
	for i in r.randi_range(1, 3):
		var px := r.randf_range(-w * 0.45, w * 0.45)
		if absf(px - door_x) < 1.2:
			continue
		flower_pot(root, Vector3(px, 0.6, d * 0.5 + 0.45), r.randi())
	var b := body(root)
	box_col(b, Vector3(w + 0.2, h + 0.6, d + 0.2), Vector3(0, (h + 0.6) * 0.5, 0))
	var roof_shape := ConvexPolygonShape3D.new()
	var hw := (w + 1.1) * 0.5
	var hd := (d + 0.9) * 0.5
	roof_shape.points = PackedVector3Array([
		Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(0, roof_h, -hd),
		Vector3(-hw, 0, hd), Vector3(hw, 0, hd), Vector3(0, roof_h, hd)])
	var rcs := CollisionShape3D.new()
	rcs.shape = roof_shape
	rcs.position = Vector3(0, top, 0)
	b.add_child(rcs)
	return root


## Tejado a dos aguas: dos faldones con grosor, filas de tejas, cumbrera y los hastiales
## (del color de la pared) rellenando el desván. La cara exterior de los faldones sigue
## la línea del alero (±(w + 1.1) / 2, 0) a la cumbrera (0, roof_h), como la colisión.
static func _gable_roof(root: Node3D, w: float, d: float, top: float, roof_h: float, c: Color, wall: Color) -> void:
	var half := (w + 1.1) * 0.5
	var depth := d + 0.9
	var thick := 0.22
	var a := atan2(roof_h, half)
	var slope_len := sqrt(half * half + roof_h * roof_h)
	var tile := c.darkened(0.14)
	for sx: float in [-1.0, 1.0]:
		var n := Vector3(sx * sin(a), cos(a), 0)
		var dir := Vector3(-sx * cos(a), sin(a), 0)
		var eave := Vector3(sx * half, top, 0)
		var rot := Vector3(0, 0, -sx * rad_to_deg(a))
		# Faldón algo ondulado (como un tejado viejo que ha cedido un poco).
		MeshKit.part(root, MeshKit.soft_box(Vector3(slope_len + 0.12, thick, depth), 0.05, 0.035, 0.0, int(w * 10.0 + sx)), MeshKit.surface_mat(c, "tile", 0.1),
			eave + dir * slope_len * 0.5 - n * thick * 0.5, rot)
		# Filas de tejas: listones algo más oscuros que sobresalen del faldón.
		for k in 4:
			var t := 0.1 + k * 0.22
			_box(root, Vector3(0.14, 0.07, depth + 0.02), tile, eave + dir * slope_len * t + n * 0.02, rot, 0.02, 0.0)
	# Cumbrera de tejas curvas solapadas.
	var ridge_n := int(depth / 0.42) + 1
	for k in ridge_n:
		var z := -depth * 0.5 + (k + 0.5) * depth / ridge_n
		_p(root, MeshKit.cylinder(0.15, 0.18, depth / ridge_n + 0.08, 12), c.darkened(0.24 + 0.04 * float(k % 2)), Vector3(0, top + roof_h + 0.01, z), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.8))
	var under := thick / cos(a) + 0.02
	var ye := maxf(roof_h * (1.0 - w / (half * 2.0)) - under, 0.02)
	var gable := PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, ye), Vector2(0, roof_h - under), Vector2(-w * 0.5, ye)])
	_prism(root, gable, d, wall, Vector3(0, top, 0), 0.045)


## Prisma de un polígono vertical (x, y) extruido en Z y centrado en `pos`.
static func _prism(parent: Node3D, poly: PackedVector2Array, depth: float, c: Color, pos: Vector3, outline := 0.03) -> MeshInstance3D:
	# extrude() levanta en Y un polígono XZ: con +90° en X, z = -y queda hacia arriba
	# y la extrusión pasa a +Z.
	var flipped := PackedVector2Array()
	for q in poly:
		flipped.append(Vector2(q.x, -q.y))
	return _p(parent, MeshKit.extrude(flipped, depth), c, pos + Vector3(0, 0, -depth * 0.5), Vector3(90, 0, 0), Vector3.ONE, outline)


static func _window(root: Node3D, pos: Vector3, yaw: float, shutter: Color, planter := false, seed_value := 0) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = yaw
	root.add_child(holder)
	var frame := WHITE_WALL.lightened(0.3)
	MeshKit.part(holder, MeshKit.rounded_box(Vector3(0.9, 0.9, 0.08), 0.03, 2), glass(), Vector3.ZERO)
	# Reflejo del cristal
	_box(holder, Vector3(0.1, 0.5, 0.02), WINDOW.lightened(0.35), Vector3(-0.16, 0.12, 0.05), Vector3(0, 0, -35), 0.01, 0.0)
	# Marco y cruz
	_box(holder, Vector3(1.04, 0.1, 0.12), WOOD_DARK, Vector3(0, 0.5, 0.03), Vector3.ZERO, 0.02, 0.02)
	for sx: int in [-1, 1]:
		_box(holder, Vector3(0.08, 0.92, 0.12), WOOD_DARK, Vector3(sx * 0.48, 0, 0.03), Vector3.ZERO, 0.02, 0.0)
	_box(holder, Vector3(0.06, 0.86, 0.06), frame, Vector3(0, 0, 0.05), Vector3.ZERO, 0.02, 0.0)
	_box(holder, Vector3(0.86, 0.06, 0.06), frame, Vector3(0, 0.02, 0.05), Vector3.ZERO, 0.02, 0.0)
	_box(holder, Vector3(1.12, 0.12, 0.18), WOOD, Vector3(0, -0.5, 0.05), Vector3.ZERO, 0.03, 0.02)
	for s: int in [-1, 1]:
		MeshKit.part(holder, MeshKit.rounded_box(Vector3(0.42, 0.95, 0.06), 0.02, 3), MeshKit.surface_mat(shutter.lightened(0.15), "wood", 0.1), Vector3(s * 0.74, 0, 0.04))
		for k in 3:
			_box(holder, Vector3(0.34, 0.035, 0.02), shutter.darkened(0.05), Vector3(s * 0.74, -0.28 + k * 0.28, 0.08), Vector3.ZERO, 0.01, 0.0)
	if planter:
		var cols := [Color(1, 0.45, 0.45), Color(1, 0.85, 0.3), Color(0.85, 0.55, 1.0), Color(1, 1, 1)]
		_box(holder, Vector3(0.98, 0.24, 0.28), shutter.darkened(0.15), Vector3(0, -0.68, 0.17), Vector3.ZERO, 0.03, 0.02)
		_p(holder, MeshKit.blob(0.5, 0.35, 0.25, seed_value % 7, 8), Color(0.35, 0.65, 0.3), Vector3(0, -0.55, 0.17), Vector3.ZERO, Vector3(1.0, 1.0, 0.36), 0.02)
		for i in 5:
			_p(holder, MeshKit.sphere(0.065, 6), cols[(seed_value + i) % cols.size()], Vector3(-0.36 + i * 0.18, -0.46 + (i % 2) * 0.05, 0.2 + (i % 2) * 0.05), Vector3.ZERO, Vector3.ONE, 0.0)


static func smoke(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = 10
	p.lifetime = 5.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 12, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.25, 0.1, 0.1)
	pm.scale_min = 0.5
	pm.scale_max = 0.8
	var c := Curve.new()
	c.add_point(Vector2(0, 0.35))
	c.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.15, Color(1, 1, 1, 0.55))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	mesh.radial_segments = 8
	mesh.rings = 4
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.92, 0.92, 0.95)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.disable_receive_shadows = true
	mesh.material = m
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func flower_pot(root: Node3D, pos: Vector3, seed_value: int) -> void:
	var cols := [Color(1, 0.45, 0.45), Color(1, 0.85, 0.3), Color(0.85, 0.55, 1.0), Color(1, 1, 1)]
	_p(root, MeshKit.cylinder(0.22, 0.16, 0.3, 10), Color(0.8, 0.45, 0.3), pos + Vector3(0, 0.15, 0), Vector3.ZERO, Vector3.ONE, 0.02)
	_p(root, MeshKit.blob(0.22, 0.7, 0.2, seed_value % 7, 8), Color(0.35, 0.65, 0.3), pos + Vector3(0, 0.38, 0), Vector3.ZERO, Vector3.ONE, 0.02)
	for i in 3:
		var a := TAU * i / 3.0 + seed_value
		_p(root, MeshKit.sphere(0.07, 6), cols[(seed_value + i) % cols.size()], pos + Vector3(cos(a) * 0.12, 0.5, sin(a) * 0.12), Vector3.ZERO, Vector3.ONE, 0.0)


# --- Molino ---------------------------------------------------------------------

static func windmill() -> Dictionary:
	var root := Node3D.new()
	# Torre encalada, algo abombada, sobre un zócalo de piedra.
	var prof := PackedVector2Array([Vector2(2.62, 0), Vector2(2.56, 0.6), Vector2(2.44, 1.6), Vector2(2.3, 3.2),
		Vector2(2.14, 5.0), Vector2(2.0, 6.6), Vector2(1.94, 7.5), Vector2(0.0, 7.5)])
	_p(root, MeshKit.lathe(prof, 18), WHITE_WALL)
	_p(root, MeshKit.lathe(PackedVector2Array([Vector2(2.86, 0), Vector2(2.84, 0.5), Vector2(2.66, 0.72), Vector2(0.0, 0.72)]), 18), STONE_DARK)
	_p(root, MeshKit.cylinder(2.06, 2.08, 0.24, 18), WOOD_DARK, Vector3(0, 7.45, 0))
	# Tejado cónico de paja con el alero algo levantado.
	MeshKit.part(root, MeshKit.lathe(PackedVector2Array([Vector2(2.5, -0.05), Vector2(2.44, 0.2), Vector2(1.95, 0.75),
		Vector2(1.05, 1.75), Vector2(0.38, 2.45), Vector2(0.0, 2.75)]), 18), MeshKit.surface_mat(Color(0.8, 0.66, 0.42), "thatch", 0.1), Vector3(0, 7.5, 0))
	# Puerta con marco y escalón.
	_box(root, Vector3(1.55, 2.35, 0.24), WOOD_DARK, Vector3(0, 1.2, 2.42))
	_box(root, Vector3(1.2, 2.05, 0.2), WOOD, Vector3(0, 1.08, 2.5))
	_box(root, Vector3(1.8, 0.2, 0.8), STONE, Vector3(0, 0.1, 2.85))
	MeshKit.part(root, MeshKit.rounded_box(Vector3(0.8, 0.8, 0.2), 0.03, 2), glass(), Vector3(0, 4.5, 2.13), Vector3(-6, 0, 0))
	# Ventanucos alrededor de la torre.
	for w in [[-0.75, 3.1], [0.9, 5.3], [2.6, 4.0], [3.7, 2.4]]:
		var ang: float = w[0]
		var y: float = w[1]
		var rad := lerpf(2.44, 1.94, clampf((y - 1.6) / 5.9, 0.0, 1.0)) + 0.02
		var holder := Node3D.new()
		holder.position = Vector3(sin(ang) * rad, y, cos(ang) * rad)
		holder.rotation.y = ang
		root.add_child(holder)
		_box(holder, Vector3(0.62, 0.8, 0.16), WOOD_DARK, Vector3.ZERO)
		MeshKit.part(holder, MeshKit.rounded_box(Vector3(0.44, 0.62, 0.12), 0.03, 2), glass(), Vector3(0, 0, 0.03))
		_box(holder, Vector3(0.72, 0.1, 0.24), STONE, Vector3(0, -0.44, 0.05))
	var hub := Node3D.new()
	hub.position = Vector3(0, 7.2, 2.4)
	root.add_child(hub)
	_p(hub, MeshKit.sphere(0.35, 8), WOOD_DARK, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 0.03)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = TAU * i / 4.0
		hub.add_child(arm)
		_box(arm, Vector3(0.18, 5.2, 0.12), WOOD_DARK, Vector3(0, 2.6, 0), Vector3.ZERO, 0.03, 0.02)
		# Vela de lona sobre un bastidor de listones.
		_box(arm, Vector3(1.3, 4.0, 0.04), Color(0.98, 0.95, 0.88), Vector3(0.72, 3.0, 0.07), Vector3.ZERO, 0.02, 0.025)
		_box(arm, Vector3(0.08, 4.1, 0.08), WOOD, Vector3(1.38, 3.0, 0.06), Vector3.ZERO, 0.02, 0.015)
		for k in 5:
			_box(arm, Vector3(1.42, 0.06, 0.07), WOOD, Vector3(0.7, 1.1 + k * 0.95, 0.1), Vector3.ZERO, 0.02, 0.0)
	var b := body(root)
	cyl_col(b, 2.4, 7.5, Vector3(0, 3.75, 0))
	cyl_col(b, 2.2, 2.4, Vector3(0, 8.6, 0))
	return {"root": root, "hub": hub}


# --- Faros del Viento -------------------------------------------------------------

## Faro de piedra blanca con franjas del color de la región. Devuelve las piezas que se
## iluminan al encenderlo.
static func beacon(stripe: Color, height := 13.0) -> Dictionary:
	var root := Node3D.new()
	var base_r := 2.6
	var top_r := 1.7
	var prof := PackedVector2Array([Vector2(base_r + 0.6, 0), Vector2(base_r + 0.5, 0.8), Vector2(base_r, 1.0), Vector2(top_r, height), Vector2(0.0, height)])
	_p(root, MeshKit.lathe(prof, 16), WHITE_WALL, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 0.06)
	# Franjas
	for k: float in [0.33, 0.66]:
		var y := height * k
		var rr := lerpf(base_r, top_r, k) + 0.06
		_p(root, MeshKit.cylinder(rr, rr + 0.06, height * 0.1, 16), stripe, Vector3(0, y, 0), Vector3.ZERO, Vector3.ONE, 0.03)
	# Zócalo de piedra
	_p(root, MeshKit.lathe(PackedVector2Array([Vector2(base_r + 0.85, 0), Vector2(base_r + 0.8, 0.55), Vector2(base_r + 0.55, 0.8), Vector2(0.0, 0.8)]), 18), STONE_DARK)
	# Puerta con marco de piedra
	_box(root, Vector3(1.75, 2.6, 0.32), STONE, Vector3(0, 1.3 + 0.8, base_r - 0.02))
	_box(root, Vector3(1.3, 2.2, 0.3), WOOD, Vector3(0, 1.1 + 0.8, base_r + 0.05), Vector3.ZERO, 0.06, 0.03)
	# Ventanas que suben en espiral por la torre
	for k in 3:
		var y := height * (0.3 + 0.2 * k)
		var ang := 0.9 + k * 2.2
		var rad := lerpf(base_r, top_r, (y - 1.0) / (height - 1.0)) + 0.03
		var holder := Node3D.new()
		holder.position = Vector3(sin(ang) * rad, y, cos(ang) * rad)
		holder.rotation.y = ang
		root.add_child(holder)
		_box(holder, Vector3(0.62, 0.85, 0.16), STONE, Vector3.ZERO)
		MeshKit.part(holder, MeshKit.rounded_box(Vector3(0.42, 0.62, 0.12), 0.03, 2), glass(), Vector3(0, 0, 0.04))
	# Balcón
	_p(root, MeshKit.cylinder(top_r + 0.9, top_r + 0.5, 0.4, 18), STONE, Vector3(0, height + 0.2, 0), Vector3.ZERO, Vector3.ONE, 0.04)
	for i in 12:
		var a := TAU * i / 12.0
		_p(root, MeshKit.cylinder(0.06, 0.06, 0.8, 6), STONE_DARK, Vector3(cos(a) * (top_r + 0.8), height + 0.8, sin(a) * (top_r + 0.8)), Vector3.ZERO, Vector3.ONE, 0.0)
	_p(root, MeshKit.torus(top_r + 0.72, top_r + 0.88), STONE_DARK, Vector3(0, height + 1.2, 0), Vector3.ZERO, Vector3.ONE, 0.0)
	# Linterna: columnas, cristal del viento y tejado
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		_p(root, MeshKit.cylinder(0.1, 0.1, 2.2, 6), stripe.darkened(0.2), Vector3(cos(a) * 1.0, height + 1.5, sin(a) * 1.0), Vector3.ZERO, Vector3.ONE, 0.02)
	var crystal_off := MeshKit.mat(Color(0.55, 0.6, 0.66), 0.03)
	var crystal_on := MeshKit.mat(stripe.lightened(0.45), 0.03, 3.5, stripe.lightened(0.3))
	var crystal := MeshKit.part(root, MeshKit.blob(0.62, 1.5, 0.0, 0, 6), crystal_off, Vector3(0, height + 1.5, 0))
	_p(root, MeshKit.lathe(PackedVector2Array([Vector2(1.6, 0), Vector2(1.5, 0.25), Vector2(0.0, 1.9)]), 16), stripe, Vector3(0, height + 2.6, 0), Vector3.ZERO, Vector3.ONE, 0.05)
	# Veleta
	var vane := Node3D.new()
	vane.position = Vector3(0, height + 4.6, 0)
	root.add_child(vane)
	_p(vane, MeshKit.cylinder(0.04, 0.04, 0.9, 6), STONE_DARK, Vector3(0, -0.2, 0), Vector3.ZERO, Vector3.ONE, 0.0)
	_box(vane, Vector3(0.06, 0.4, 1.1), GOLD, Vector3(0, 0.15, 0.25), Vector3.ZERO, 0.02, 0.015)
	# Pedestal del viento junto a la puerta: aquí se enciende.
	var altar := Node3D.new()
	altar.position = Vector3(0, 0, base_r + 3.0)
	root.add_child(altar)
	_p(altar, MeshKit.cylinder(0.55, 0.7, 1.0, 8), STONE, Vector3(0, 0.5, 0), Vector3.ZERO, Vector3.ONE, 0.03)
	var orb_off := MeshKit.mat(Color(0.5, 0.55, 0.62), 0.02)
	var orb_on := MeshKit.mat(stripe.lightened(0.5), 0.02, 2.5, stripe.lightened(0.3))
	var orb := MeshKit.part(altar, MeshKit.sphere(0.32, 10), orb_off, Vector3(0, 1.35, 0))
	var light := OmniLight3D.new()
	light.position = Vector3(0, height + 1.5, 0)
	light.light_color = stripe.lightened(0.4)
	light.light_energy = 0.0
	light.omni_range = 26.0
	root.add_child(light)
	var b := body(root)
	cyl_col(b, base_r + 0.2, height, Vector3(0, height * 0.5, 0))
	cyl_col(b, top_r + 0.9, 0.4, Vector3(0, height + 0.2, 0))
	cyl_col(b, 0.6, 1.0, altar.position + Vector3(0, 0.5, 0))
	return {"root": root, "crystal": crystal, "crystal_on": crystal_on, "crystal_off": crystal_off,
		"orb": orb, "orb_on": orb_on, "orb_off": orb_off, "light": light, "vane": vane,
		"altar": altar, "top": Vector3(0, height + 1.5, 0)}


# --- Muelle y barca ---------------------------------------------------------------

static func dock(length: float) -> Node3D:
	var root := Node3D.new()
	var b := body(root)
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var n := int(length / 0.6)
	for i in n:
		# Tablas de largo y tono distintos, algo torcidas y con rendijas entre ellas.
		var c := WOOD.lerp(WOOD.lightened(0.12), r.randf()).darkened(r.randf() * 0.08)
		var w := 3.2 + r.randf_range(-0.12, 0.08)
		_box(root, Vector3(w, 0.16, 0.54), c, Vector3(r.randf_range(-0.08, 0.08), 1.2 + r.randf_range(-0.015, 0.015), i * 0.6),
			Vector3(r.randf_range(-0.8, 0.8), r.randf_range(-1.6, 1.6), r.randf_range(-0.6, 0.6)))
	# Largueros bajo las tablas y pilotes de troncos con cuerdas.
	for s: int in [-1, 1]:
		_p(root, MeshKit.cylinder(0.11, 0.11, length, 8), WOOD_DARK, Vector3(s * 1.2, 1.02, length * 0.5 - 0.3), Vector3(90, 0, 0))
	for i in range(0, int(length / 3.0) + 1):
		for s: int in [-1, 1]:
			var tilt := Vector3(r.randf_range(-2.5, 2.5), r.randf() * 360.0, r.randf_range(-2.5, 2.5))
			_p(root, MeshKit.cylinder(0.15, 0.19, 4.2, 10), WOOD_DARK, Vector3(s * 1.5, -0.75, i * 3.0), tilt)
			_p(root, MeshKit.torus(0.17, 0.215), Color(0.82, 0.74, 0.55), Vector3(s * 1.5, 0.55 + r.randf_range(-0.1, 0.1), i * 3.0), Vector3(r.randf_range(-6.0, 6.0), 0, 0))
	box_col(b, Vector3(3.2, 0.3, length), Vector3(0, 1.15, length * 0.5 - 0.3))
	return root


static func boat() -> Node3D:
	var root := Node3D.new()
	var paint := Color(0.25, 0.5, 0.75)
	# Casco de dos proas, pintado, con una franja blanca bajo la borda.
	MeshKit.part(root, MeshKit.hull(5.2, 2.5, 0.62), MeshKit.surface_mat(paint, "wood", 0.1), Vector3(0, 0.05, 0))
	# Forro interior de madera (el casco se ve por dentro).
	MeshKit.part(root, MeshKit.hull(5.08, 2.38, 0.56), MeshKit.surface_mat(WOOD.lightened(0.05), "wood", 0.0), Vector3(0, 0.07, 0))
	MeshKit.part(root, MeshKit.hull(5.2, 2.5, 0.62, Vector2(0.02, 0.12), 0.012), MeshKit.surface_mat(Color(0.96, 0.94, 0.88), "wood", 0.1), Vector3(0, 0.05, 0))
	MeshKit.part(root, MeshKit.hull(5.2, 2.5, 0.62, Vector2(0.88, 0.98), 0.012), MeshKit.surface_mat(Color(0.96, 0.94, 0.88), "wood", 0.1), Vector3(0, 0.05, 0))
	# Tablas del fondo, bancada (ahí se sienta el gatito) y regala.
	for k in 5:
		_box(root, Vector3(0.24, 0.05, 3.2 - absf(k - 2) * 0.6), WOOD, Vector3(-0.56 + k * 0.28, -0.12, 0))
	_box(root, Vector3(2.1, 0.08, 0.36), WOOD, Vector3(0, 0.44, 0.4))
	_box(root, Vector3(1.7, 0.08, 0.3), WOOD, Vector3(0, 0.4, -1.3))
	# Mástil, botavara y vela hinchada por el viento.
	var mast_z := -0.5
	_p(root, MeshKit.cylinder(0.055, 0.075, 4.1, 8), WOOD_DARK, Vector3(0, 2.05, mast_z))
	_p(root, MeshKit.cylinder(0.04, 0.045, 2.3, 8), WOOD_DARK, Vector3(0, 0.85, mast_z + 1.12), Vector3(90, 0, 0))
	var tack := Vector3(0, 0.88, mast_z + 0.06)
	var head := Vector3(0, 3.9, mast_z + 0.06)
	var clew := Vector3(0, 0.9, mast_z + 2.2)
	var sail := func(u: float, v: float) -> Vector3:
		var p := tack + (clew - tack) * v * (1.0 - u) + (head - tack) * u
		p.x += sin(v * PI) * 0.32 * (1.0 - u * 0.7)
		return p
	var sail_mesh := MeshKit.double_sided(MeshKit.param_surface(sail, 10, 8, Vector3(-3, 2, 0), false))
	MeshKit.part(root, sail_mesh, MeshKit.mat(Color(0.98, 0.94, 0.85)))
	# Jarcia: obenque a proa y escota a popa.
	for line in [[head, Vector3(0, 0.4, -2.3)], [clew, Vector3(0, 0.45, 2.3)]]:
		var from: Vector3 = line[0]
		var to: Vector3 = line[1]
		var l := MeshKit.part(root, MeshKit.cylinder(0.008, 0.008, from.distance_to(to), 4), MeshKit.mat(Color(0.85, 0.82, 0.75)), (from + to) * 0.5)
		l.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	return root


# --- Plaza ------------------------------------------------------------------------

static func fountain() -> Node3D:
	var root := Node3D.new()
	_p(root, MeshKit.lathe(PackedVector2Array([Vector2(3.0, 0), Vector2(3.0, 0.7), Vector2(2.6, 0.75), Vector2(2.6, 0.3), Vector2(0, 0.3)]), 24), STONE, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, 0.04)
	var water := MeshKit.part(root, MeshKit.cylinder(2.6, 2.6, 0.05, 24), MeshKit.mat(Color(0.45, 0.82, 0.92), 0.0, 0.25), Vector3(0, 0.58, 0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_p(root, MeshKit.lathe(PackedVector2Array([Vector2(0.5, 0), Vector2(0.35, 1.4), Vector2(1.1, 1.6), Vector2(1.0, 1.8), Vector2(0.25, 1.8), Vector2(0.2, 2.6), Vector2(0.0, 2.8)]), 16), STONE, Vector3(0, 0.3, 0), Vector3.ZERO, Vector3.ONE, 0.035)
	var b := body(root)
	cyl_col(b, 3.0, 0.75, Vector3(0, 0.375, 0))
	cyl_col(b, 0.5, 2.8, Vector3(0, 1.4, 0))
	return root


static func market_stall(awning: Color) -> Node3D:
	var root := Node3D.new()
	# Mostrador de tablas con frente de listones verticales.
	_box(root, Vector3(3.2, 0.12, 1.4), WOOD, Vector3(0, 1.0, 0))
	for i in 9:
		_box(root, Vector3(0.34, 0.92, 0.07), WOOD if i % 2 == 0 else WOOD.lightened(0.06), Vector3(-1.42 + i * 0.355, 0.47, 0.66), Vector3(0, 0, (i % 3 - 1) * 0.8))
	_box(root, Vector3(3.1, 0.9, 1.3), WOOD_DARK, Vector3(0, 0.46, -0.03))
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			_p(root, MeshKit.cylinder(0.07, 0.08, 2.65, 8), WOOD_DARK, Vector3(sx * 1.5, 1.32, sz * 0.6))
	# Toldo de tela a rayas: cae en una curva suave y acaba en festón.
	var fab := [awning, Color(0.98, 0.96, 0.9)]
	for i in 6:
		var stripe := Node3D.new()
		stripe.position = Vector3(-1.4 + i * 0.56, 2.65, 0.15)
		stripe.rotation_degrees.x = 14.0
		root.add_child(stripe)
		for k in 4:
			var t := k / 3.0
			_p(stripe, MeshKit.rounded_box(Vector3(0.56, 0.05, 0.52), 0.02, 2), fab[i % 2], Vector3(0, -t * t * 0.18, -0.75 + k * 0.5), Vector3(t * 12.0, 0, 0))
		_p(stripe, MeshKit.cylinder(0.28, 0.28, 0.04, 14), fab[i % 2], Vector3(0, -0.22, 1.02), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.55))
	var fruit := [Color(1, 0.45, 0.3), Color(1, 0.8, 0.3), Color(0.6, 0.85, 0.35), Color(0.65, 0.4, 0.8)]
	for i in 4:
		# Cestas de mimbre (madera clara) con fruta amontonada.
		_p(root, MeshKit.lathe(PackedVector2Array([Vector2(0.22, 0), Vector2(0.3, 0.06), Vector2(0.34, 0.22), Vector2(0.3, 0.24), Vector2(0.0, 0.2)]), 12),
			WOOD.lightened(0.2), Vector3(-1.1 + i * 0.73, 1.06, 0.1))
		for k in 6:
			var a := TAU * k / 6.0 + i
			_p(root, MeshKit.sphere(0.1, 10), fruit[i], Vector3(-1.1 + i * 0.73 + cos(a) * 0.14, 1.32 + (k % 3) * 0.04, 0.1 + sin(a) * 0.14))
	var b := body(root)
	box_col(b, Vector3(3.2, 1.0, 1.4), Vector3(0, 0.5, 0))
	return root


static func lamp_post() -> Dictionary:
	var root := Node3D.new()
	var metal := Color(0.25, 0.27, 0.3)
	# Pie moldeado, fuste fino con anillos, ménsula curva y farol con tejadillo.
	_p(root, MeshKit.lathe(PackedVector2Array([Vector2(0.24, 0), Vector2(0.24, 0.08), Vector2(0.18, 0.16), Vector2(0.15, 0.32),
		Vector2(0.1, 0.4), Vector2(0.0, 0.42)]), 12), metal)
	_p(root, MeshKit.cylinder(0.065, 0.085, 2.6, 10), metal, Vector3(0, 1.65, 0))
	for y: float in [0.55, 2.5]:
		_p(root, MeshKit.torus(0.06, 0.11), metal, Vector3(0, y, 0))
	_p(root, MeshKit.lathe(PackedVector2Array([Vector2(0.08, 0), Vector2(0.26, 0.04), Vector2(0.28, 0.08), Vector2(0.0, 0.1)]), 12), metal, Vector3(0, 2.9, 0))
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			_p(root, MeshKit.cylinder(0.022, 0.022, 0.52, 6), metal, Vector3(sx * 0.17, 3.24, sz * 0.17))
	_p(root, MeshKit.lathe(PackedVector2Array([Vector2(0.34, 0), Vector2(0.32, 0.05), Vector2(0.12, 0.26), Vector2(0.06, 0.32), Vector2(0.0, 0.42)]), 12), metal, Vector3(0, 3.5, 0))
	_p(root, MeshKit.sphere(0.05, 10), metal, Vector3(0, 3.95, 0))
	var glow_off := MeshKit.mat(Color(0.9, 0.88, 0.75), 0.0)
	var glow_on := MeshKit.mat(Color(1.0, 0.85, 0.5), 0.0, 4.0, Color(1.0, 0.75, 0.4))
	var glass := MeshKit.part(root, MeshKit.rounded_box(Vector3(0.34, 0.48, 0.34), 0.03, 1), glow_off, Vector3(0, 3.22, 0))
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.position = Vector3(0, 3.1, 0)
	light.light_color = Color(1.0, 0.75, 0.45)
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.visible = false
	root.add_child(light)
	var b := body(root)
	cyl_col(b, 0.15, 3.4, Vector3(0, 1.7, 0))
	return {"root": root, "glass": glass, "on": glow_on, "off": glow_off, "light": light}


static func bench() -> Node3D:
	var root := Node3D.new()
	# Asiento y respaldo de listones separados, sobre patas de hierro curvadas.
	for k in 3:
		_box(root, Vector3(1.8, 0.05, 0.14), WOOD, Vector3(0, 0.5, -0.17 + k * 0.17), Vector3(0, (k - 1) * 0.6, 0))
	for k in 2:
		_box(root, Vector3(1.8, 0.13, 0.04), WOOD, Vector3(0, 0.72 + k * 0.2, -0.25 - k * 0.03), Vector3(-12, 0, 0))
	var iron := Color(0.22, 0.24, 0.26)
	for s2: int in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(s2 * 0.75, 0, 0)
		root.add_child(leg)
		_p(leg, MeshKit.cylinder(0.025, 0.03, 0.5, 6), iron, Vector3(0, 0.24, 0.17), Vector3(-8, 0, 0))
		_p(leg, MeshKit.cylinder(0.025, 0.03, 0.95, 6), iron, Vector3(0, 0.47, -0.2), Vector3(-12, 0, 0))
		_p(leg, MeshKit.cylinder(0.022, 0.022, 0.42, 6), iron, Vector3(0, 0.46, -0.01), Vector3(90, 0, 0))
		_p(leg, MeshKit.torus(0.03, 0.06), iron, Vector3(0, 0.62, 0.2), Vector3(0, 0, 90))
	return root


## Valla rústica: postes y travesaños de troncos, cada uno algo torcido.
static func fence(length: float) -> Node3D:
	var root := Node3D.new()
	var r := RandomNumberGenerator.new()
	r.seed = int(length * 100.0)
	var posts := int(length / 2.0) + 1
	for i in posts:
		var h := r.randf_range(1.05, 1.2)
		_p(root, MeshKit.cylinder(0.075, 0.09, h, 8), WOOD, Vector3(i * 2.0 - length * 0.5, h * 0.5 - 0.05, 0),
			Vector3(r.randf_range(-3.0, 3.0), r.randf_range(0, 360), r.randf_range(-3.0, 3.0)))
	for y: float in [0.45, 0.85]:
		_p(root, MeshKit.cylinder(0.05, 0.055, length + 0.2, 8), WOOD.lightened(0.08), Vector3(0, y + r.randf_range(-0.03, 0.03), 0.06),
			Vector3(0, 0, 90.0 + r.randf_range(-1.5, 1.5)))
	return root


## Tendedero con prendas de colores (delante de la sastrería).
static func clothes_line() -> Node3D:
	var root := Node3D.new()
	for sx: int in [-1, 1]:
		_p(root, MeshKit.cylinder(0.07, 0.09, 2.2, 8), WOOD_DARK, Vector3(sx * 2.0, 1.1, 0))
	_p(root, MeshKit.cylinder(0.012, 0.012, 4.0, 4), Color(0.9, 0.88, 0.82), Vector3(0, 2.05, 0), Vector3(0, 0, 90))
	var cols := [Color(0.95, 0.45, 0.5), Color(0.45, 0.7, 0.95), Color(1.0, 0.85, 0.35), Color(0.55, 0.8, 0.5), Color(0.75, 0.55, 0.9)]
	for i in 5:
		var x := -1.5 + i * 0.75
		var garment := Node3D.new()
		garment.position = Vector3(x, 2.02, 0)
		garment.rotation_degrees = Vector3(0, 0, (i % 2) * 4.0 - 2.0)
		root.add_child(garment)
		if i % 2 == 0:
			# Camiseta: cuerpo y mangas
			_box(garment, Vector3(0.5, 0.6, 0.04), cols[i], Vector3(0, -0.32, 0), Vector3.ZERO, 0.03, 0.0)
			for sx: int in [-1, 1]:
				_box(garment, Vector3(0.2, 0.18, 0.04), cols[i], Vector3(sx * 0.3, -0.1, 0), Vector3(0, 0, sx * -25.0), 0.02, 0.0)
		else:
			# Pantalón corto o bufanda
			_box(garment, Vector3(0.22, 0.7, 0.03), cols[i], Vector3(0, -0.36, 0), Vector3.ZERO, 0.02, 0.0)
		_box(garment, Vector3(0.05, 0.08, 0.06), WOOD, Vector3(0, 0.0, 0), Vector3.ZERO, 0.01, 0.0)
	return root


static func crate(c := WOOD) -> Node3D:
	var root := Node3D.new()
	# Caja de tablas: cuerpo algo hundido y un marco de listones en los cantos y en aspa.
	_box(root, Vector3(0.84, 0.84, 0.84), c.darkened(0.08), Vector3(0, 0.45, 0))
	var frame := c.darkened(0.22)
	for sy: int in [-1, 1]:
		for sz: int in [-1, 1]:
			_box(root, Vector3(0.92, 0.09, 0.09), frame, Vector3(0, 0.45 + sy * 0.42, sz * 0.42))
			_box(root, Vector3(0.09, 0.09, 0.92), frame, Vector3(sy * 0.42, 0.45 + sz * 0.42, 0))
			_box(root, Vector3(0.09, 0.92, 0.09), frame, Vector3(sy * 0.42, 0.45, sz * 0.42))
	for face: int in [-1, 1]:
		_box(root, Vector3(1.05, 0.08, 0.05), frame, Vector3(0, 0.45, face * 0.44), Vector3(0, 0, 45))
	var b := body(root)
	box_col(b, Vector3(0.9, 0.9, 0.9), Vector3(0, 0.45, 0))
	return root


static func barrel() -> Node3D:
	var root := Node3D.new()
	# Duelas: tablas curvas de tono algo distinto, con aros de hierro y tapa hundida.
	var staves := 12
	var prof := PackedVector2Array([Vector2(0.37, 0), Vector2(0.43, 0.25), Vector2(0.46, 0.5), Vector2(0.43, 0.75), Vector2(0.37, 1.0)])
	for k in staves:
		var a0 := TAU * k / staves
		var stave := Node3D.new()
		stave.rotation.y = -a0
		root.add_child(stave)
		var tone := WOOD.darkened(0.04 * float(k % 3)).lightened(0.03 * float((k * 7) % 2))
		for i in prof.size() - 1:
			var p0 := prof[i]
			var p1 := prof[i + 1]
			var mid := (p0 + p1) * 0.5
			var ang := rad_to_deg(atan2(p1.x - p0.x, p1.y - p0.y))
			_p(stave, MeshKit.rounded_box(Vector3(0.05, p0.distance_to(p1) + 0.01, 2.0 * PI * mid.x / staves - 0.012), 0.012, 2),
				tone, Vector3(mid.x - 0.025, mid.y, 0), Vector3(0, 0, -ang))
	_p(root, MeshKit.cylinder(0.36, 0.36, 0.04, 16), WOOD.darkened(0.1), Vector3(0, 0.95, 0))
	for y: float in [0.14, 0.86]:
		_p(root, MeshKit.torus(0.4, 0.45), Color(0.32, 0.32, 0.35), Vector3(0, y, 0), Vector3.ZERO, Vector3(1, 0.7, 1))
	var b := body(root)
	cyl_col(b, 0.45, 1.0, Vector3(0, 0.5, 0))
	return root


## Cometas de colores colgadas de una cuerda (taller de Nerea).
static func kite(c1: Color, c2: Color, size := 1.0) -> Node3D:
	var root := Node3D.new()
	# Cuatro paños de tela combados por el viento entre las varillas (dos colores alternos).
	var tips := [Vector2(0, 0.5), Vector2(0.55, 0), Vector2(0, -0.9), Vector2(-0.55, 0)]
	for q in 4:
		var a: Vector2 = tips[q]
		var b: Vector2 = tips[(q + 1) % 4]
		var panel := func(u: float, v: float) -> Vector3:
			var p := (a * (1.0 - v) + b * v) * u
			var bulge := sin(u * PI) * sin(v * PI) * 0.06 + u * 0.03
			return Vector3(p.x, p.y, bulge) * size
		var m := MeshKit.double_sided(MeshKit.param_surface(panel, 6, 6, Vector3(0, 0, -1.0), false))
		MeshKit.part(root, m, MeshKit.mat(c1 if q % 2 == 0 else c2))
	# Varillas y cola de lazos.
	var stick := MeshKit.mat(WOOD_DARK)
	MeshKit.part(root, MeshKit.cylinder(0.012, 0.012, 1.4 * size, 5), stick, Vector3(0, -0.2 * size, 0.035 * size))
	MeshKit.part(root, MeshKit.cylinder(0.012, 0.012, 1.1 * size, 5), stick, Vector3(0, 0, 0.035 * size), Vector3(0, 0, 90))
	for i in 4:
		var bow := Node3D.new()
		bow.position = Vector3(sin(i * 1.3) * 0.08, -0.95 * size - i * 0.22 * size, 0)
		bow.rotation.z = sin(i * 1.7) * 0.4
		root.add_child(bow)
		for sx: float in [-1.0, 1.0]:
			_p(bow, MeshKit.cone(0.05 * size, 0.1 * size, 8), [c1, c2, GOLD, c1][i], Vector3(sx * 0.045 * size, 0, 0), Vector3(0, 0, sx * 90.0), Vector3(1.0, 1.0, 0.4))
	return root


# --- Naturaleza especial --------------------------------------------------------------

## Roca Aguja: pilar escalable hecho de capas de roca facetadas, cada una algo girada y
## desplazada, con salientes, matas de hierba en las repisas y la cima cubierta de verde.
static func needle_rock(height := 11.0) -> Node3D:
	var root := Node3D.new()
	var r := RandomNumberGenerator.new()
	r.seed = 11 + int(height)
	var col := Color(0.72, 0.66, 0.58) if height < 14.0 else Color(0.66, 0.62, 0.58)
	_p(root, MeshKit.spire(height, 3.1, 1.75, int(height) * 7), col, Vector3.ZERO, Vector3(0, r.randf() * 360.0, 0))
	# Matas de hierba en algunas repisas y la cima cubierta de verde.
	for i in int(height / 2.2):
		if r.randf() < 0.5:
			var a := r.randf() * TAU
			var y := (i + 1) * 2.2
			var rad := lerpf(3.1, 1.75, y / height) * 0.98
			var g := Color(0.42, 0.68, 0.3).lerp(Color(0.55, 0.75, 0.32), r.randf())
			var clump := MeshInstance3D.new()
			clump.mesh = Flora.leafy_clump(0.6, 0.5, g, i + 20)
			clump.position = Vector3(cos(a) * rad, y + 0.15, sin(a) * rad)
			root.add_child(clump)
	_p(root, MeshKit.blob(1.6, 0.18, 0.2, 2, 12), Color(0.36, 0.55, 0.26), Vector3(0, height + 0.05, 0))
	var cap := MeshInstance3D.new()
	cap.mesh = Flora.leafy_clump(1.5, 0.35, Color(0.62, 0.86, 0.45), 77)
	cap.position = Vector3(0, height + 0.35, 0)
	root.add_child(cap)
	var b := body(root)
	cyl_col(b, 2.4, height, Vector3(0, height * 0.5, 0))
	return root


static func ruin_pillar(height: float, broken := false) -> Node3D:
	var root := Node3D.new()
	var sd := int(height * 17.0) + (1 if broken else 0)
	# Plinto, basa con molduras, fuste acanalado y capitel (o un trozo roto encima).
	MeshKit.part(root, MeshKit.soft_box(Vector3(1.6, 0.45, 1.6), 0.1, 0.04, 0.0, sd), _m(STONE_DARK), Vector3(0, 0.22, 0))
	_p(root, MeshKit.lathe(PackedVector2Array([Vector2(0.72, 0.0), Vector2(0.74, 0.1), Vector2(0.66, 0.18), Vector2(0.62, 0.24),
		Vector2(0.64, 0.3), Vector2(0.58, 0.36), Vector2(0.0, 0.36)]), 16), STONE, Vector3(0, 0.45, 0))
	_p(root, MeshKit.column(height - 0.2, 0.56, 16, sd), STONE, Vector3(0, 0.78, 0))
	var top := height + 0.58
	if not broken:
		_p(root, MeshKit.lathe(PackedVector2Array([Vector2(0.48, 0.0), Vector2(0.56, 0.08), Vector2(0.7, 0.2), Vector2(0.0, 0.22)]), 16), STONE, Vector3(0, top - 0.02, 0))
		MeshKit.part(root, MeshKit.soft_box(Vector3(1.5, 0.36, 1.5), 0.08, 0.03, 0.0, sd + 1), _m(STONE_DARK), Vector3(0, top + 0.36, 0))
	else:
		_p(root, MeshKit.cylinder(0.5, 0.5, 0.06, 12), STONE, Vector3(0, top - 0.04, 0))
		_p(root, MeshKit.rock(sd, 0.5, 14), STONE, Vector3(0.2, top + 0.1, 0), Vector3(0, 0, 25), Vector3.ONE * 0.6)
	var b := body(root)
	cyl_col(b, 0.65, height + 0.9, Vector3(0, (height + 0.9) * 0.5, 0))
	return root


static func ruin_arch(width: float, height: float) -> Node3D:
	var root := Node3D.new()
	# Pilares de sillares desgastados (cada bloque algo distinto) y dintel.
	for sx: int in [-1, 1]:
		var blocks := maxi(2, int(height / 1.1))
		var bh := height / blocks
		for k in blocks:
			var sz := Vector3(1.2 - (k % 2) * 0.08, bh - 0.02, 1.2 - ((k + 1) % 2) * 0.08)
			MeshKit.part(root, MeshKit.soft_box(sz, 0.12, 0.05, 0.0, int(width * 10) + k * 3 + sx), _m(STONE),
				Vector3(sx * width * 0.5, bh * (k + 0.5), 0), Vector3(0, (k * 37 % 7) - 3.0, 0))
	MeshKit.part(root, MeshKit.soft_box(Vector3(width + 1.6, 1.0, 1.4), 0.14, 0.06, 0.0, int(height * 10)), _m(STONE_DARK), Vector3(0, height + 0.5, 0), Vector3(0, 0, 1.2))
	var b := body(root)
	for s: int in [-1, 1]:
		box_col(b, Vector3(1.2, height, 1.2), Vector3(s * width * 0.5, height * 0.5, 0))
	box_col(b, Vector3(width + 1.6, 1.0, 1.4), Vector3(0, height + 0.5, 0))
	return root


## Plataforma de piedra (escalones de las ruinas, torre de salida de la carrera).
static func stone_block(size: Vector3, c := STONE) -> Node3D:
	var root := Node3D.new()
	MeshKit.part(root, MeshKit.soft_box(size, 0.14, minf(0.06, size.y * 0.05), 0.0, int(size.x * 13.0 + size.y * 7.0)), _m(c), Vector3(0, size.y * 0.5, 0))
	var b := body(root)
	box_col(b, size, Vector3(0, size.y * 0.5, 0))
	return root


static func cabin(log_color := WOOD) -> Node3D:
	var root := Node3D.new()
	var r := RandomNumberGenerator.new()
	r.seed = 515
	# Troncos con corteza, de grosor algo distinto, que se cruzan y sobresalen en las esquinas.
	var bark := Color(0.5, 0.36, 0.24)
	for i in 7:
		var y := 0.25 + i * 0.42
		for side in 4:
			var along_x := side % 2 == 0
			var sgn := -1 if side < 2 else 1
			var len := 5.8 if along_x else 4.8
			var rad := 0.22 * r.randf_range(0.92, 1.08)
			var c := log_color.lerp(bark, 0.35).darkened(r.randf() * 0.1)
			var pos := Vector3(r.randf_range(-0.08, 0.08), y + (0.21 if not along_x else 0.0), sgn * 2.0) if along_x else Vector3(sgn * 2.5, y + 0.21, r.randf_range(-0.08, 0.08))
			var rot := Vector3(0, r.randf_range(-0.6, 0.6), 90) if along_x else Vector3(90, 0, r.randf_range(-0.6, 0.6))
			MeshKit.part(root, MeshKit.cylinder(rad, rad, len, 12), MeshKit.surface_mat(c, "bark", 0.08), pos, rot)
			# Testa clara del tronco en cada extremo.
			for e: int in [-1, 1]:
				var cap_pos := pos + (Vector3(e * len * 0.5, 0, 0) if along_x else Vector3(0, 0, e * len * 0.5))
				_p(root, MeshKit.cylinder(rad * 0.9, rad * 0.9, 0.02, 12), log_color.lightened(0.25), cap_pos, rot)
	# Tejado de tablas cubierto de musgo, con hastiales de tablas verticales.
	var top := 3.15
	var roof_h := 2.0
	var half := 3.3
	var depth := 5.6
	var a := atan2(roof_h, half)
	var slope := sqrt(half * half + roof_h * roof_h)
	var moss := Color(0.42, 0.55, 0.32)
	for sx: float in [-1.0, 1.0]:
		var n := Vector3(sx * sin(a), cos(a), 0)
		var dir := Vector3(-sx * cos(a), sin(a), 0)
		var eave := Vector3(sx * half, top, 0)
		var rot := Vector3(0, 0, -sx * rad_to_deg(a))
		for k in 6:
			var t := (k + 0.5) / 6.0
			_box(root, Vector3(slope / 6.0 + 0.06, 0.1, depth + r.randf_range(-0.1, 0.15)), WOOD_DARK.lerp(moss, 0.25),
				eave + dir * slope * t - n * 0.05 + n * 0.012 * k, rot + Vector3(r.randf_range(-1.0, 1.0), 0, 0))
		# Almohadillas de musgo encima de las tablas.
		for k in 5:
			var t2 := r.randf_range(0.15, 0.85)
			var z := r.randf_range(-depth * 0.4, depth * 0.4)
			_p(root, MeshKit.blob(r.randf_range(0.5, 0.9), 0.22, 0.25, k + int(sx * 10.0), 12), moss.lightened(r.randf() * 0.12),
				eave + dir * slope * t2 + n * 0.06 + Vector3(0, 0, z), rot)
	_p(root, MeshKit.cylinder(0.16, 0.16, depth + 0.3, 10), log_color.lerp(bark, 0.4), Vector3(0, top + roof_h, 0), Vector3(90, 0, 0))
	for sz: int in [-1, 1]:
		var gable := PackedVector2Array([Vector2(-2.5, 0), Vector2(2.5, 0), Vector2(0, roof_h * 0.72)])
		_prism(root, gable, 0.1, WOOD, Vector3(0, top, sz * 2.05))
	_box(root, Vector3(1.1, 2.0, 0.15), WOOD_DARK, Vector3(0.8, 1.0, 2.25))
	_window(root, Vector3(-1.2, 1.7, 2.3), 0.0, moss)
	# Leña apilada junto a la pared.
	for k in 6:
		_p(root, MeshKit.cylinder(0.11, 0.11, 0.9, 10), log_color.lerp(bark, 0.3), Vector3(-2.95, 0.12 + (k / 3) * 0.2, -0.6 + (k % 3) * 0.23 + (k / 3) * 0.1), Vector3(0, 0, 90))
	var b := body(root)
	box_col(b, Vector3(5.2, 3.0, 4.2), Vector3(0, 1.5, 0))
	return root


static func tent(c: Color) -> Node3D:
	var root := Node3D.new()
	# Lona: triángulo con los lados algo hundidos (tela tensada entre palos).
	var pts := PackedVector2Array([Vector2(-1.7, 0)])
	for k in range(1, 6):
		var t := k / 6.0
		var sag := sin(t * PI) * 0.16
		pts.append(Vector2(-1.7 + 1.7 * t + sag * 0.6, 2.2 * t - sag))
	pts.append(Vector2(0, 2.2))
	for k in range(1, 6):
		var t := 1.0 - k / 6.0
		var sag := sin(t * PI) * 0.16
		pts.append(Vector2(1.7 - 1.7 * t - sag * 0.6, 2.2 * t - sag))
	pts.append(Vector2(1.7, 0))
	_prism(root, pts, 3.6, c, Vector3.ZERO)
	for sz: int in [-1, 1]:
		_p(root, MeshKit.cylinder(0.04, 0.05, 2.35, 6), WOOD_DARK, Vector3(0, 1.15, sz * 1.82))
	_p(root, MeshKit.cylinder(0.05, 0.05, 2.4, 6), WOOD_DARK, Vector3(0, 1.2, 1.9), Vector3.ZERO, Vector3.ONE, 0.0)
	var b := body(root)
	box_col(b, Vector3(3.0, 1.6, 3.4), Vector3(0, 0.8, 0))
	return root


static func campfire() -> Dictionary:
	var root := Node3D.new()
	for i in 7:
		var a := TAU * i / 7.0
		_p(root, MeshKit.rock(60 + i, 0.6, 12), STONE_DARK, Vector3(cos(a) * 0.65, 0.08, sin(a) * 0.65), Vector3(0, i * 47, 0), Vector3.ONE * 0.22)
	for i in 3:
		_p(root, MeshKit.cylinder(0.08, 0.08, 1.0, 6), WOOD_DARK, Vector3(0, 0.15, 0), Vector3(80, i * 60, 0), Vector3.ONE, 0.015)
	# Llamas: tres lenguas de fuego dibujadas por shader, de distinto tamaño y ritmo.
	var flame := Node3D.new()
	flame.position = Vector3(0, 0.12, 0)
	root.add_child(flame)
	for k in 3:
		var fm := ShaderMaterial.new()
		fm.shader = load("res://shaders/flame.gdshader")
		fm.set_shader_parameter("seed", k * 1.37)
		fm.set_shader_parameter("speed", 2.0 + k * 0.35)
		fm.set_shader_parameter("intensity", 2.2 - k * 0.4)
		var q := QuadMesh.new()
		q.size = Vector2(0.75 - k * 0.15, 1.25 - k * 0.2)
		var fq := MeshKit.part(flame, q, fm, Vector3((k - 1) * 0.12, 0.6 - k * 0.08, (k % 2) * 0.08 - 0.04))
		fq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Brasas que suben y un poco de humo.
	var embers := GPUParticles3D.new()
	embers.amount = 14
	embers.lifetime = 1.6
	embers.position = Vector3(0, 0.3, 0)
	embers.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 4, 2))
	var em := ParticleProcessMaterial.new()
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	em.emission_sphere_radius = 0.2
	em.direction = Vector3.UP
	em.spread = 18.0
	em.initial_velocity_min = 0.6
	em.initial_velocity_max = 1.4
	em.gravity = Vector3(0, 0.4, 0)
	em.turbulence_enabled = true
	em.turbulence_noise_strength = 0.6
	em.scale_min = 0.5
	em.scale_max = 1.0
	var eg := Gradient.new()
	eg.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	eg.set_color(eg.get_point_count() - 1, Color(1.0, 0.3, 0.05, 0.0))
	var egt := GradientTexture1D.new()
	egt.gradient = eg
	em.color_ramp = egt
	embers.process_material = em
	var dot := QuadMesh.new()
	dot.size = Vector2(0.045, 0.045)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dot.material = dm
	embers.draw_pass_1 = dot
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(embers)
	var smk := smoke(Vector3(0, 1.4, 0))
	smk.amount = 6
	root.add_child(smk)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.0, 0)
	light.light_color = Color(1.0, 0.65, 0.35)
	light.light_energy = 1.5
	light.omni_range = 9.0
	root.add_child(light)
	return {"root": root, "flame": flame}


# --- Objetos del juego ------------------------------------------------------------------

static func chest() -> Dictionary:
	var root := Node3D.new()
	var wood := Color(0.6, 0.35, 0.22)
	# Cuerpo de tablas horizontales con cantoneras y bandas de latón.
	for k in 3:
		_box(root, Vector3(1.1, 0.2, 0.75), wood.lightened(0.04 * float(k % 2)), Vector3(0, 0.1 + k * 0.2, 0))
	for x: float in [-0.4, 0.4]:
		_box(root, Vector3(0.1, 0.62, 0.78), GOLD, Vector3(x, 0.31, 0))
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			_box(root, Vector3(0.12, 0.14, 0.12), GOLD.darkened(0.1), Vector3(sx * 0.52, 0.07, sz * 0.34))
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.6, -0.37)
	root.add_child(lid)
	# Tapa abombada (medio cilindro) con bandas de latón y cerradura.
	_p(lid, MeshKit.cylinder(0.38, 0.38, 1.12, 16), wood.lightened(0.06), Vector3(0, 0.0, 0.37), Vector3(0, 0, 90), Vector3(1.0, 1.0, 0.78))
	for x: float in [-0.4, 0.4]:
		_p(lid, MeshKit.cylinder(0.395, 0.395, 0.1, 16), GOLD, Vector3(x, 0.0, 0.37), Vector3(0, 0, 90), Vector3(1.0, 1.0, 0.79))
	_box(lid, Vector3(0.22, 0.26, 0.08), GOLD, Vector3(0, 0.0, 0.77), Vector3.ZERO, 0.03, 0.015)
	_p(lid, MeshKit.sphere(0.035, 10), Color(0.2, 0.15, 0.1), Vector3(0, -0.03, 0.82))
	var b := body(root)
	box_col(b, Vector3(1.1, 0.9, 0.75), Vector3(0, 0.45, 0))
	return {"root": root, "lid": lid}


static func shell() -> Node3D:
	# Concha de vieira: abanico de estrías con una base pequeña.
	var root := Node3D.new()
	var a := MeshKit.mat(Color(1.0, 0.7, 0.62), 0.012)
	var b := MeshKit.mat(Color(1.0, 0.86, 0.78), 0.012)
	for i in 7:
		var ang := lerpf(-55.0, 55.0, i / 6.0)
		var rib := Node3D.new()
		rib.rotation_degrees = Vector3(0, ang, 0)
		root.add_child(rib)
		MeshKit.part(rib, MeshKit.rounded_box(Vector3(0.085, 0.05, 0.3), 0.03, 2), a if i % 2 == 0 else b, Vector3(0, 0.03 + 0.012 * (1.0 - absf(ang) / 55.0), -0.14), Vector3(-8, 0, 0))
	MeshKit.part(root, MeshKit.rounded_box(Vector3(0.12, 0.05, 0.07), 0.02, 1), b, Vector3(0, 0.02, 0.03))
	root.rotation_degrees.x = 15
	return root


static func feather() -> Node3D:
	var root := Node3D.new()
	var vane := MeshKit.blob(0.32, 1.0, 0.0, 0, 8)
	MeshKit.part(root, vane, MeshKit.mat(GOLD, 0.02, 0.9, Color(1.0, 0.75, 0.25)), Vector3(0, 0.5, 0), Vector3(0, 0, 12), Vector3(0.45, 1.5, 0.12))
	MeshKit.part(root, MeshKit.cylinder(0.025, 0.035, 1.1, 6), MeshKit.mat(Color(1.0, 0.95, 0.75), 0.0, 0.5), Vector3(0.04, 0.45, 0), Vector3(0, 0, 12))
	return root


static func spark() -> Node3D:
	var root := Node3D.new()
	var core := MeshKit.part(root, MeshKit.sphere(0.28, 8), MeshKit.mat(Color(1.0, 0.75, 0.3), 0.0, 4.0, Color(1.0, 0.55, 0.15)), Vector3.ZERO)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := MeshKit.part(root, MeshKit.sphere(0.5, 8), MeshKit.unshaded(Color(1.0, 0.6, 0.2, 0.25), 1.5), Vector3.ZERO)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 1.2
	light.omni_range = 6.0
	root.add_child(light)
	return root


static func mushroom(glow: bool) -> Node3D:
	var root := Node3D.new()
	_p(root, MeshKit.cylinder(0.08, 0.1, 0.35, 8), Color(0.95, 0.92, 0.85), Vector3(0, 0.17, 0), Vector3.ZERO, Vector3.ONE, 0.015)
	var cap_col := Color(0.45, 0.85, 1.0) if glow else Color(0.85, 0.3, 0.25)
	var cap := MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.28, 0.0), Vector2(0.24, 0.12), Vector2(0.0, 0.22)]), 10)
	MeshKit.part(root, cap, MeshKit.mat(cap_col, 0.015, 1.6 if glow else 0.0, cap_col), Vector3(0, 0.33, 0))
	for i in 3:
		var a := TAU * i / 3.0
		_p(root, MeshKit.sphere(0.035, 4), Color(1, 1, 1), Vector3(cos(a) * 0.14, 0.45, sin(a) * 0.14), Vector3.ZERO, Vector3.ONE, 0.0)
	return root


## Anillo de viento de la carrera.
static func wind_ring(radius := 3.0) -> Dictionary:
	var root := Node3D.new()
	var on := MeshKit.mat(Color(0.55, 0.95, 1.0), 0.03, 1.4, Color(0.4, 0.9, 1.0))
	var done := MeshKit.mat(Color(1.0, 0.85, 0.35), 0.03, 1.0, Color(1.0, 0.8, 0.3))
	var off := MeshKit.unshaded(Color(0.8, 0.9, 1.0, 0.25))
	var ring := MeshKit.part(root, MeshKit.torus(radius - 0.2, radius + 0.2), off, Vector3.ZERO, Vector3(90, 0, 0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"root": root, "ring": ring, "on": on, "done": done, "off": off}


## Columna de viento ascendente (la paravela sube dentro).
static func updraft(height: float, radius: float) -> Node3D:
	var root := Node3D.new()
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 2.6
	p.visibility_aabb = AABB(Vector3(-radius, 0, -radius), Vector3(radius * 2, height + 4, radius * 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius * 0.8
	pm.emission_ring_inner_radius = radius * 0.2
	pm.emission_ring_height = 0.5
	pm.direction = Vector3.UP
	pm.spread = 4.0
	pm.initial_velocity_min = height / 2.6 * 0.8
	pm.initial_velocity_max = height / 2.6 * 1.1
	pm.gravity = Vector3.ZERO
	pm.orbit_velocity_min = 0.08
	pm.orbit_velocity_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.add_point(0.2, Color(1, 1, 1, 0.7))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.08, 1.6)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	sm.albedo_color = Color(0.95, 0.98, 1.0, 0.8)
	streak.material = sm
	p.draw_pass_1 = streak
	root.add_child(p)
	return root


static func signpost(text: String) -> Node3D:
	var root := Node3D.new()
	_p(root, MeshKit.cylinder(0.08, 0.1, 1.8, 6), WOOD_DARK, Vector3(0, 0.9, 0), Vector3.ZERO, Vector3.ONE, 0.02)
	# Tabla con punta de flecha, sujeta con dos clavos.
	var arrow := PackedVector2Array([Vector2(-0.45, -0.2), Vector2(0.75, -0.2), Vector2(1.0, 0.0), Vector2(0.75, 0.2), Vector2(-0.45, 0.2)])
	_prism(root, arrow, 0.08, WOOD, Vector3(0.0, 1.5, 0))
	for nx: float in [-0.3, 0.6]:
		_p(root, MeshKit.sphere(0.025, 10), Color(0.3, 0.3, 0.32), Vector3(nx, 1.5, 0.05))
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.004
	l.modulate = Color(0.25, 0.15, 0.08)
	l.outline_size = 0
	l.position = Vector3(0.3, 1.5, 0.05)
	l.font = load("res://assets/fonts/Fredoka.ttf")
	root.add_child(l)
	return root
