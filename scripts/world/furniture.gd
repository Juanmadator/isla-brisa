class_name Furniture
extends RefCounted
## Muebles de la casa de Lía (los vende Martín en la carpintería). Todos con el origen en el
## suelo y el frente hacia +Z (hacia el centro de la habitación); los cuadros, con el origen
## en la pared. Las lámparas, la estufa y la pecera traen su luz (nodo "Light", que la casa
## sube de noche). La pecera muestra los peces que ha pescado Lía (nodo "Fish") y la vitrina,
## las plumas doradas y los faros encendidos.

const PINE := Color(0.8, 0.62, 0.42)
const OAK := Props.WOOD
const DARK := Props.WOOD_DARK
const LINEN := Color(0.97, 0.95, 0.9)
const WARM := Color(1.0, 0.78, 0.5)

## Paredes: id -> [color de la pared, color del zócalo, dibujo, estrellas]
const WALLS := {
	"furn_wall_white": [Color(0.97, 0.94, 0.86), Color(0.62, 0.43, 0.28), "plaster", false],
	"furn_wall_sea": [Color(0.66, 0.83, 0.94), Color(0.96, 0.96, 0.93), "plaster", false],
	"furn_wall_flowers": [Color(1.0, 0.86, 0.86), Color(0.55, 0.72, 0.5), "cloth", false],
	"furn_wall_pine": [Color(0.86, 0.68, 0.48), Color(0.55, 0.38, 0.25), "wood", false],
	"furn_wall_night": [Color(0.2, 0.24, 0.45), Color(0.14, 0.16, 0.3), "plaster", true],
}
## Suelos: id -> [color, dibujo]
const FLOORS := {
	"furn_floor_planks": [Color(0.66, 0.47, 0.31), "wood"],
	"furn_floor_terracotta": [Color(0.82, 0.48, 0.34), "tile"],
	"furn_floor_stone": [Color(0.86, 0.84, 0.78), "tile"],
	"furn_floor_dark": [Color(0.4, 0.27, 0.18), "wood"],
}


static func _b(root: Node3D, size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO, r := 0.03) -> MeshInstance3D:
	return Props._box(root, size, col, pos, rot, r)


static func _cloth(root: Node3D, mesh: Mesh, col: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return MeshKit.part(root, mesh, MeshKit.surface_mat(col, "cloth", 0.06), pos, rot, scl)


static func _glow(col: Color, energy := 1.2) -> ShaderMaterial:
	return MeshKit.mat(col, 0.0, energy, col)


static func _light(root: Node3D, pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "Light"
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.set_meta("base", energy)
	root.add_child(l)
	return l


static func _solid(root: Node3D, size: Vector3, pos: Vector3) -> void:
	var b := Props.body(root)
	Props.box_col(b, size, pos)


## Modelo de un mueble. `ctx` trae lo que algunos muestran: "fish" (especies pescadas),
## "feathers" (plumas doradas) y "beacons" (faros encendidos).
static func build(id: String, ctx := {}) -> Node3D:
	var root := Node3D.new()
	root.name = id
	match id:
		"furn_bed_pine": _bed(root, PINE, Color(0.55, 0.72, 0.5), "plain")
		"furn_bed_sailor": _bed(root, Color(0.95, 0.95, 0.92), Color(0.25, 0.42, 0.72), "stripes")
		"furn_bed_flowers": _bed(root, Color(0.92, 0.8, 0.62), Color(1.0, 0.66, 0.74), "flowers")
		"furn_bed_stars": _bed(root, Color(0.22, 0.27, 0.48), Color(0.16, 0.2, 0.4), "stars")
		"furn_table_pine": _table(root, PINE, "square")
		"furn_table_round": _table(root, OAK, "round")
		"furn_table_captain": _table(root, DARK, "captain")
		"furn_rug_wool": _rug(root, "round")
		"furn_rug_stripes": _rug(root, "stripes")
		"furn_rug_waves": _rug(root, "waves")
		"furn_lamp_oil": _lamp(root, "oil")
		"furn_lamp_floor": _lamp(root, "floor")
		"furn_lamp_lighthouse": _lamp(root, "lighthouse")
		"furn_plant_geranium": _plant(root, "geranium")
		"furn_plant_fern": _plant(root, "fern")
		"furn_plant_lemon": _plant(root, "lemon")
		"furn_art_lighthouse": _art(root, "lighthouse")
		"furn_art_map": _art(root, "map")
		"furn_art_kite": _art(root, "kite")
		"furn_art_olga": _art(root, "olga")
		"furn_shelf_books": _shelf(root, false, ctx)
		"furn_shelf_trophies": _shelf(root, true, ctx)
		"furn_aquarium": _aquarium(root, ctx)
		"furn_stove": _stove(root)
		_:
			if WALLS.has(id) or FLOORS.has(id):
				_sample(root, id)
	return root


## Tamaño aproximado (para encuadrarlo en el probador de la tienda): [alto, ancho].
static func frame_size(id: String) -> Vector2:
	var cat := category(id)
	match cat:
		"bed": return Vector2(1.2, 2.2)
		"table": return Vector2(1.0, 2.2)
		"rug": return Vector2(0.3, 2.6)
		"lamp": return Vector2(1.7 if id != "furn_lamp_oil" else 1.0, 0.8)
		"plant": return Vector2(1.5 if id == "furn_plant_lemon" else 0.9, 0.9)
		"art": return Vector2(1.1, 1.2)
		"shelf": return Vector2(1.9, 1.3)
		"fish": return Vector2(1.4, 1.3)
		"stove": return Vector2(1.6, 1.0)
	return Vector2(1.2, 1.4)


static func category(id: String) -> String:
	if Catalog.ITEMS.has(id) and Catalog.ITEMS[id][0] == "furn":
		return Catalog.ITEMS[id][3]
	return ""


# --- Camas ---------------------------------------------------------------------------------

static func _bed(root: Node3D, frame: Color, blanket: Color, deco: String) -> void:
	var w := 1.36
	var l := 2.1
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_b(root, Vector3(0.11, 0.34, 0.11), frame.darkened(0.08), Vector3(sx * (w * 0.5 - 0.06), 0.17, sz * (l * 0.5 - 0.06)))
	_b(root, Vector3(w, 0.2, l), frame, Vector3(0, 0.38, 0), Vector3.ZERO, 0.05)
	# Cabecero redondeado y pie de cama.
	var head_h := 1.05
	_b(root, Vector3(w + 0.06, head_h, 0.09), frame, Vector3(0, head_h * 0.5 + 0.1, -l * 0.5 + 0.02), Vector3.ZERO, 0.04)
	MeshKit.part(root, MeshKit.cylinder(w * 0.5, w * 0.5, 0.09, 24), Props._m(frame), Vector3(0, head_h + 0.02, -l * 0.5 + 0.02), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.35))
	_b(root, Vector3(w + 0.06, 0.62, 0.08), frame, Vector3(0, 0.4, l * 0.5 - 0.02), Vector3.ZERO, 0.04)
	# Colchón, sábana doblada, manta y almohada mullida.
	_cloth(root, MeshKit.soft_box(Vector3(w - 0.1, 0.2, l - 0.12), 0.08, 0.01, 0.0, 3), LINEN, Vector3(0, 0.58, 0))
	_cloth(root, MeshKit.soft_box(Vector3(w - 0.04, 0.09, l * 0.62), 0.04, 0.012, 0.0, 4), blanket, Vector3(0, 0.71, 0.32))
	_cloth(root, MeshKit.soft_box(Vector3(w - 0.03, 0.05, 0.2), 0.025, 0.008, 0.0, 5), LINEN, Vector3(0, 0.73, 0.32 - l * 0.31 + 0.08))
	_cloth(root, MeshKit.blob(0.32, 0.36, 0.05, 2, 14), LINEN, Vector3(0, 0.75, -l * 0.5 + 0.35), Vector3.ZERO, Vector3(1.5, 1.0, 0.85))
	match deco:
		"stripes":
			for k in 4:
				_cloth(root, MeshKit.soft_box(Vector3(w - 0.02, 0.095, 0.1), 0.02, 0.0, 0.0, 6), Color(0.96, 0.96, 0.94), Vector3(0, 0.712, 0.0 + k * 0.28))
			# Ancla en el cabecero.
			var gold := Props.GOLD
			_b(root, Vector3(0.05, 0.36, 0.03), gold, Vector3(0, 0.72, -l * 0.5 + 0.08), Vector3.ZERO, 0.01)
			_b(root, Vector3(0.22, 0.05, 0.03), gold, Vector3(0, 0.84, -l * 0.5 + 0.08), Vector3.ZERO, 0.01)
			MeshKit.part(root, MeshKit.torus(0.12, 0.16), Props._m(gold), Vector3(0, 0.6, -l * 0.5 + 0.08), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.5))
		"flowers":
			var r := RandomNumberGenerator.new()
			r.seed = 7
			for k in 14:
				var p := Vector3(r.randf_range(-w * 0.45, w * 0.45), 0.76, r.randf_range(0.0, l * 0.58))
				MeshKit.part(root, MeshKit.blob(0.035, 0.5, 0.0, 0, 8), MeshKit.mat(Color(1, 1, 1) if k % 3 else Color(1.0, 0.9, 0.4)), p)
			for k in 5:
				MeshKit.part(root, MeshKit.blob(0.05, 0.6, 0.0, 0, 8), MeshKit.mat(Color(0.95, 0.45, 0.55)), Vector3(-0.45 + k * 0.22, head_h - 0.05, -l * 0.5 + 0.08))
		"stars":
			var r := RandomNumberGenerator.new()
			r.seed = 9
			for k in 16:
				var p := Vector3(r.randf_range(-w * 0.45, w * 0.45), 0.76, r.randf_range(0.0, l * 0.58))
				MeshKit.part(root, MeshKit.sphere(0.022, 6), _glow(Color(1.0, 0.86, 0.4), 0.6), p)
			# Luna creciente en el cabecero.
			MeshKit.part(root, MeshKit.cylinder(0.2, 0.2, 0.04, 24), _glow(Color(1.0, 0.9, 0.55), 0.5), Vector3(0, 0.85, -l * 0.5 + 0.07), Vector3(90, 0, 0))
			MeshKit.part(root, MeshKit.cylinder(0.17, 0.17, 0.05, 24), Props._m(frame), Vector3(0.09, 0.9, -l * 0.5 + 0.08), Vector3(90, 0, 0))
	_solid(root, Vector3(w, 0.8, l), Vector3(0, 0.4, 0))


# --- Mesas ---------------------------------------------------------------------------------

static func _chair(root: Node3D, col: Color, pos: Vector3, yaw: float, stool := false) -> void:
	var c := Node3D.new()
	c.position = pos
	c.rotation.y = yaw
	root.add_child(c)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_b(c, Vector3(0.05, 0.45, 0.05), col.darkened(0.08), Vector3(sx * 0.17, 0.225, sz * 0.17), Vector3.ZERO, 0.015)
	if stool:
		MeshKit.part(c, MeshKit.cylinder(0.22, 0.22, 0.06, 18), Props._m(col), Vector3(0, 0.47, 0))
		return
	_b(c, Vector3(0.42, 0.05, 0.42), col, Vector3(0, 0.47, 0), Vector3.ZERO, 0.02)
	for sx: float in [-1.0, 1.0]:
		_b(c, Vector3(0.05, 0.5, 0.05), col.darkened(0.08), Vector3(sx * 0.17, 0.72, 0.18), Vector3.ZERO, 0.015)
	for k in 2:
		_b(c, Vector3(0.36, 0.05, 0.03), col, Vector3(0, 0.66 + k * 0.24, 0.18), Vector3.ZERO, 0.012)


static func _table(root: Node3D, col: Color, kind: String) -> void:
	var h := 0.78
	match kind:
		"round":
			MeshKit.part(root, MeshKit.cylinder(0.62, 0.62, 0.06, 28), Props._m(col), Vector3(0, h, 0))
			MeshKit.part(root, MeshKit.cylinder(0.06, 0.09, h - 0.05, 12), Props._m(col.darkened(0.1)), Vector3(0, (h - 0.05) * 0.5, 0))
			MeshKit.part(root, MeshKit.cylinder(0.3, 0.34, 0.05, 18), Props._m(col.darkened(0.1)), Vector3(0, 0.025, 0))
			# Mantel de cuadros y jarrón con flores.
			var cloth := MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.66, 0.0), Vector2(0.7, -0.16), Vector2(0.7, -0.2)]), 28)
			_cloth(root, cloth, Color(0.92, 0.42, 0.4), Vector3(0, h + 0.035, 0))
			MeshKit.part(root, MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.09, 0.08), Vector2(0.05, 0.2), Vector2(0.06, 0.24), Vector2(0.0, 0.24)]), 14),
				MeshKit.mat(Color(0.45, 0.65, 0.85)), Vector3(0, h + 0.04, 0))
			for k in 5:
				var a := TAU * k / 5.0
				MeshKit.part(root, MeshKit.cylinder(0.006, 0.006, 0.2, 4), MeshKit.mat(Color(0.35, 0.6, 0.3)), Vector3(cos(a) * 0.02, h + 0.33, sin(a) * 0.02), Vector3(cos(a) * 15.0, 0, sin(a) * 15.0))
				MeshKit.part(root, MeshKit.blob(0.045, 0.8, 0.1, k, 8), MeshKit.mat([Color(1, 0.85, 0.3), Color(1, 0.55, 0.6), Color(1, 1, 1)][k % 3]), Vector3(cos(a) * 0.07, h + 0.44, sin(a) * 0.07))
			_chair(root, col.lightened(0.05), Vector3(-0.85, 0, 0.0), PI * 0.5 + PI)
			_chair(root, col.lightened(0.05), Vector3(0.85, 0, 0.0), PI * 0.5)
			_solid(root, Vector3(1.3, h, 1.3), Vector3(0, h * 0.5, 0))
		"captain":
			_b(root, Vector3(1.5, 0.09, 0.9), col, Vector3(0, h, 0), Vector3.ZERO, 0.03)
			for sx: float in [-1.0, 1.0]:
				_b(root, Vector3(0.14, h - 0.05, 0.7), col.darkened(0.1), Vector3(sx * 0.6, (h - 0.05) * 0.5, 0), Vector3.ZERO, 0.03)
			_b(root, Vector3(1.1, 0.08, 0.1), col.darkened(0.1), Vector3(0, 0.18, 0), Vector3.ZERO, 0.02)
			# Mapa enrollado, brújula y vela.
			_b(root, Vector3(0.7, 0.012, 0.5), Color(0.95, 0.88, 0.7), Vector3(-0.15, h + 0.05, 0), Vector3(0, 8, 0), 0.004)
			MeshKit.part(root, MeshKit.cylinder(0.03, 0.03, 0.5, 10), MeshKit.mat(Color(0.93, 0.85, 0.65)), Vector3(-0.15, h + 0.08, 0.27), Vector3(0, 8, 90))
			MeshKit.part(root, MeshKit.cylinder(0.08, 0.08, 0.03, 16), Props._m(Props.GOLD), Vector3(0.42, h + 0.06, -0.15))
			MeshKit.part(root, MeshKit.cylinder(0.06, 0.06, 0.035, 16), MeshKit.mat(Color(0.96, 0.95, 0.9)), Vector3(0.42, h + 0.065, -0.15))
			MeshKit.part(root, MeshKit.cylinder(0.035, 0.035, 0.14, 10), MeshKit.mat(LINEN), Vector3(0.5, h + 0.12, 0.2))
			MeshKit.part(root, MeshKit.blob(0.02, 1.8, 0.0, 0, 8), _glow(Color(1.0, 0.75, 0.35), 2.5), Vector3(0.5, h + 0.22, 0.2))
			_light(root, Vector3(0.5, h + 0.35, 0.2), WARM, 0.5, 3.0)
			_chair(root, col, Vector3(0, 0, 0.75), PI, true)
			_chair(root, col, Vector3(-0.5, 0, -0.75), 0.0, true)
			_solid(root, Vector3(1.5, h, 0.9), Vector3(0, h * 0.5, 0))
		_:
			_b(root, Vector3(1.4, 0.07, 0.85), col, Vector3(0, h, 0), Vector3.ZERO, 0.03)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_b(root, Vector3(0.08, h - 0.04, 0.08), col.darkened(0.08), Vector3(sx * 0.6, (h - 0.04) * 0.5, sz * 0.34), Vector3.ZERO, 0.02)
			# Frutero con manzanas.
			MeshKit.part(root, MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.18, 0.08), Vector2(0.16, 0.09), Vector2(0.0, 0.03)]), 18),
				Props._m(Props.WOOD), Vector3(0.2, h + 0.035, 0))
			for k in 4:
				var a := TAU * k / 4.0
				MeshKit.part(root, MeshKit.sphere(0.05, 10), MeshKit.mat(Color(0.88, 0.2, 0.18) if k % 2 == 0 else Color(0.6, 0.8, 0.25)), Vector3(0.2 + cos(a) * 0.07, h + 0.11, sin(a) * 0.07))
			_chair(root, col, Vector3(0, 0, 0.62), 0.0)
			_chair(root, col, Vector3(0, 0, -0.62), PI)
			_solid(root, Vector3(1.4, h, 0.85), Vector3(0, h * 0.5, 0))


# --- Alfombras -----------------------------------------------------------------------------

static func _rug(root: Node3D, kind: String) -> void:
	match kind:
		"round":
			for k in 3:
				var r := 1.25 - k * 0.38
				var col: Color = [Color(0.93, 0.88, 0.78), Color(0.75, 0.55, 0.4), Color(0.95, 0.9, 0.82)][k]
				_cloth(root, MeshKit.cylinder(r, r, 0.02, 40), col, Vector3(0, 0.012 + k * 0.004, 0))
		"stripes":
			var cols := [Color(0.9, 0.35, 0.3), Color(0.98, 0.9, 0.7), Color(0.3, 0.5, 0.75), Color(0.98, 0.9, 0.7)]
			for k in 9:
				_cloth(root, MeshKit.soft_box(Vector3(2.6, 0.02, 0.22), 0.01, 0.0, 0.0, k), cols[k % cols.size()], Vector3(0, 0.012, -0.88 + k * 0.22))
			for sx: float in [-1.0, 1.0]:
				for k in 9:
					MeshKit.part(root, MeshKit.cylinder(0.008, 0.008, 0.1, 4), MeshKit.mat(LINEN), Vector3(sx * 1.35, 0.012, -0.88 + k * 0.22), Vector3(0, 0, 90))
		"waves":
			_cloth(root, MeshKit.soft_box(Vector3(2.6, 0.02, 1.8), 0.05, 0.0, 0.0, 1), Color(0.28, 0.52, 0.78), Vector3(0, 0.012, 0))
			for row in 4:
				for k in 7:
					var p := Vector3(-1.05 + k * 0.35, 0.026, -0.6 + row * 0.4)
					MeshKit.part(root, MeshKit.torus(0.09, 0.12), MeshKit.surface_mat(Color(0.95, 0.97, 1.0), "cloth"), p, Vector3(0, 0, 0), Vector3(1.0, 0.25, 0.6))


# --- Lámparas ------------------------------------------------------------------------------

static func _lamp(root: Node3D, kind: String) -> void:
	match kind:
		"oil":
			# Mesilla con farol de aceite.
			_b(root, Vector3(0.5, 0.5, 0.45), PINE, Vector3(0, 0.25, 0), Vector3.ZERO, 0.03)
			_b(root, Vector3(0.42, 0.16, 0.02), PINE.darkened(0.12), Vector3(0, 0.32, 0.23), Vector3.ZERO, 0.01)
			MeshKit.part(root, MeshKit.sphere(0.025, 6), Props._m(Props.GOLD), Vector3(0, 0.32, 0.25))
			MeshKit.part(root, MeshKit.cylinder(0.08, 0.1, 0.04, 12), Props._m(DARK), Vector3(0, 0.52, 0))
			MeshKit.part(root, MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.09, 0.1), Vector2(0.06, 0.2), Vector2(0.0, 0.2)]), 16),
				_glow(Color(1.0, 0.85, 0.55), 1.5), Vector3(0, 0.54, 0))
			MeshKit.part(root, MeshKit.torus(0.035, 0.05), Props._m(DARK), Vector3(0, 0.8, 0), Vector3(90, 0, 0))
			_light(root, Vector3(0, 0.75, 0.1), WARM, 0.9, 4.5)
		"floor":
			MeshKit.part(root, MeshKit.cylinder(0.18, 0.22, 0.05, 18), Props._m(DARK), Vector3(0, 0.025, 0))
			MeshKit.part(root, MeshKit.cylinder(0.025, 0.025, 1.45, 8), Props._m(DARK), Vector3(0, 0.75, 0))
			var shade := MeshKit.lathe(PackedVector2Array([Vector2(0.26, 0.0), Vector2(0.16, 0.32), Vector2(0.14, 0.32), Vector2(0.24, 0.0)]), 20)
			MeshKit.part(root, MeshKit.double_sided(shade), _glow(Color(0.98, 0.88, 0.7), 0.7), Vector3(0, 1.38, 0))
			MeshKit.part(root, MeshKit.sphere(0.06, 10), _glow(Color(1.0, 0.92, 0.7), 3.0), Vector3(0, 1.45, 0))
			_light(root, Vector3(0, 1.4, 0), WARM, 1.1, 5.5)
		"lighthouse":
			# Faro en miniatura: rayas rojas, galería y linterna que gira.
			var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.24, 0.0), Vector2(0.2, 1.1), Vector2(0.0, 1.1)])
			MeshKit.part(root, MeshKit.lathe(prof, 20), MeshKit.surface_mat(Color(0.97, 0.96, 0.92), "plaster"), Vector3.ZERO)
			for k in 3:
				var y := 0.15 + k * 0.33
				var r0 := lerpf(0.24, 0.2, y / 1.1) + 0.006
				MeshKit.part(root, MeshKit.cylinder(r0 - 0.01, r0, 0.14, 20), MeshKit.mat(Color(0.86, 0.25, 0.25)), Vector3(0, y + 0.07, 0))
			MeshKit.part(root, MeshKit.cylinder(0.26, 0.26, 0.04, 20), Props._m(DARK), Vector3(0, 1.12, 0))
			MeshKit.part(root, MeshKit.cylinder(0.13, 0.13, 0.22, 14), _glow(Color(1.0, 0.92, 0.55), 2.0), Vector3(0, 1.25, 0))
			MeshKit.part(root, MeshKit.cone(0.17, 0.14, 14), MeshKit.mat(Color(0.86, 0.25, 0.25)), Vector3(0, 1.43, 0))
			var beam := Node3D.new()
			beam.name = "Spin"
			beam.position = Vector3(0, 1.25, 0)
			root.add_child(beam)
			MeshKit.part(beam, MeshKit.cone(0.1, 0.5, 10), MeshKit.unshaded(Color(1.0, 0.95, 0.7, 0.25)), Vector3(0.3, 0, 0), Vector3(0, 0, 90))
			_light(root, Vector3(0, 1.25, 0.1), Color(1.0, 0.88, 0.6), 1.0, 5.0)
			_solid(root, Vector3(0.45, 1.1, 0.45), Vector3(0, 0.55, 0))


# --- Plantas -------------------------------------------------------------------------------

static func _pot(root: Node3D, r: float, h: float, col := Color(0.78, 0.42, 0.28)) -> void:
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(r * 0.75, 0.0), Vector2(r, h * 0.9), Vector2(r * 1.08, h * 0.92), Vector2(r * 1.08, h), Vector2(r * 0.9, h), Vector2(r * 0.9, h * 0.9), Vector2(0.0, h * 0.9)])
	MeshKit.part(root, MeshKit.lathe(prof, 20), MeshKit.surface_mat(col, "tile", 0.08), Vector3.ZERO)
	MeshKit.part(root, MeshKit.cylinder(r * 0.88, r * 0.88, 0.02, 16), Props._m(Color(0.35, 0.25, 0.18)), Vector3(0, h * 0.88, 0))


static func _plant(root: Node3D, kind: String) -> void:
	match kind:
		"geranium":
			_pot(root, 0.2, 0.3)
			MeshKit.part(root, Flora.leafy_clump(0.28, 0.75, Color(0.38, 0.62, 0.3), 31), null, Vector3(0, 0.5, 0))
			var r := RandomNumberGenerator.new()
			r.seed = 3
			for k in 9:
				var a := r.randf() * TAU
				var p := Vector3(cos(a) * r.randf_range(0.05, 0.24), 0.6 + r.randf() * 0.18, sin(a) * r.randf_range(0.05, 0.24))
				MeshKit.part(root, MeshKit.blob(0.06, 0.9, 0.3, k, 8), MeshKit.mat(Color(0.92, 0.18, 0.25)), p)
		"fern":
			_pot(root, 0.22, 0.34, Color(0.92, 0.9, 0.85))
			for k in 10:
				var a := TAU * k / 10.0
				var frond := Node3D.new()
				frond.position = Vector3(0, 0.36, 0)
				frond.rotation = Vector3(0, a, 0)
				root.add_child(frond)
				for j in 5:
					var t := j / 4.0
					MeshKit.part(frond, MeshKit.blob(0.07 * (1.0 - t * 0.5), 1.0, 0.0, 0, 8), MeshKit.mat(Color(0.3, 0.6, 0.32).lightened(t * 0.15)),
						Vector3(0, 0.1 + sin(t * 1.8) * 0.28, 0.08 + t * 0.42), Vector3(-30 + t * 60.0, 0, 0), Vector3(1.4, 0.3, 1.0))
		"lemon":
			_pot(root, 0.28, 0.42, Color(0.85, 0.82, 0.75))
			MeshKit.part(root, MeshKit.cylinder(0.035, 0.05, 0.7, 8), Props._m(Color(0.5, 0.36, 0.25)), Vector3(0, 0.75, 0))
			MeshKit.part(root, Flora.leafy_clump(0.42, 0.85, Color(0.35, 0.58, 0.3), 77), null, Vector3(0, 1.22, 0))
			for k in 7:
				var a := TAU * k / 7.0
				MeshKit.part(root, MeshKit.blob(0.055, 1.25, 0.0, 0, 10), MeshKit.mat(Color(1.0, 0.85, 0.2)), Vector3(cos(a) * 0.32, 1.1 + (k % 3) * 0.1, sin(a) * 0.32))
			_solid(root, Vector3(0.5, 0.42, 0.5), Vector3(0, 0.21, 0))


# --- Cuadros (origen en la pared, mirando a +Z) -------------------------------------------

static func _art(root: Node3D, kind: String) -> void:
	if kind == "kite":
		var k := Props.kite(Color(0.95, 0.4, 0.35), Color(1.0, 0.85, 0.3), 0.8)
		k.position = Vector3(0, 0, 0.12)
		root.add_child(k)
		return
	var w := 0.9 if kind != "olga" else 0.6
	var h := 0.7 if kind != "olga" else 0.78
	_b(root, Vector3(w + 0.12, h + 0.12, 0.05), Props.GOLD.darkened(0.25) if kind == "olga" else DARK, Vector3(0, 0, 0.025), Vector3.ZERO, 0.02)
	var z := 0.055
	# Capas pintadas, cada una un poco más hacia fuera que la anterior (capa n -> z + n * 6 mm).
	var bg := func(c: Color, size: Vector2, pos: Vector2, layer: int) -> void:
		MeshKit.part(root, MeshKit.rounded_box(Vector3(size.x, size.y, 0.01), 0.004, 1), MeshKit.mat(c), Vector3(pos.x, pos.y, z + layer * 0.006))
	match kind:
		"lighthouse":
			bg.call(Color(0.62, 0.8, 0.95), Vector2(w, h), Vector2.ZERO, 0)
			bg.call(Color(0.25, 0.48, 0.75), Vector2(w, h * 0.34), Vector2(0, -h * 0.33), 1)
			bg.call(Color(0.55, 0.5, 0.45), Vector2(w * 0.35, h * 0.18), Vector2(w * 0.2, -h * 0.25), 2)
			bg.call(Color(0.97, 0.96, 0.92), Vector2(0.09, h * 0.5), Vector2(w * 0.2, h * 0.02), 3)
			for k in 2:
				bg.call(Color(0.86, 0.25, 0.25), Vector2(0.095, 0.06), Vector2(w * 0.2, -h * 0.12 + k * 0.17), 4)
			bg.call(Color(1.0, 0.85, 0.4), Vector2(0.07, 0.06), Vector2(w * 0.2, h * 0.3), 4)
			bg.call(Color(1.0, 1.0, 1.0), Vector2(0.22, 0.06), Vector2(-w * 0.25, h * 0.28), 1)
		"map":
			bg.call(Color(0.93, 0.86, 0.68), Vector2(w, h), Vector2.ZERO, 0)
			bg.call(Color(0.62, 0.78, 0.85), Vector2(w * 0.92, h * 0.88), Vector2.ZERO, 1)
			var zm := z + 0.012
			MeshKit.part(root, MeshKit.blob(0.25, 0.08, 0.35, 5, 14), MeshKit.mat(Color(0.55, 0.72, 0.42)), Vector3(0, 0, zm), Vector3(90, 0, 0), Vector3(1.4, 1.0, 1.0))
			MeshKit.part(root, MeshKit.cone(0.06, 0.1, 8), MeshKit.mat(Color(0.55, 0.5, 0.45)), Vector3(0.0, 0.06, zm + 0.02), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.3))
			for k in 6:
				MeshKit.part(root, MeshKit.sphere(0.01, 5), MeshKit.mat(Color(0.75, 0.2, 0.2)), Vector3(-0.2 + k * 0.06, -0.12 + sin(k * 1.3) * 0.03, zm + 0.02))
			MeshKit.part(root, MeshKit.cylinder(0.03, 0.03, 0.01, 12), MeshKit.mat(Color(0.75, 0.2, 0.2)), Vector3(0.14, -0.1, zm + 0.02), Vector3(90, 0, 0))
		"olga":
			bg.call(Color(0.62, 0.55, 0.72), Vector2(w, h), Vector2.ZERO, 0)
			var zo := z + 0.006
			MeshKit.part(root, MeshKit.blob(0.2, 1.0, 0.0, 0, 14), MeshKit.mat(Color(0.55, 0.42, 0.7)), Vector3(0, -h * 0.42, zo), Vector3.ZERO, Vector3(1.2, 0.8, 0.15))
			MeshKit.part(root, MeshKit.sphere(0.13, 14), MeshKit.mat(Color(1.0, 0.82, 0.68)), Vector3(0, 0.03, zo + 0.01), Vector3.ZERO, Vector3(1.0, 1.0, 0.25))
			MeshKit.part(root, MeshKit.blob(0.14, 0.7, 0.05, 2, 12), MeshKit.surface_mat(Color(0.95, 0.95, 0.95), "hair"), Vector3(0, 0.11, zo + 0.015), Vector3.ZERO, Vector3(1.0, 1.0, 0.25))
			MeshKit.part(root, MeshKit.sphere(0.06, 10), MeshKit.surface_mat(Color(0.95, 0.95, 0.95), "hair"), Vector3(0, 0.2, zo + 0.01), Vector3.ZERO, Vector3(1.0, 1.0, 0.3))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(root, MeshKit.torus(0.028, 0.038), MeshKit.mat(Color(0.2, 0.2, 0.22)), Vector3(sx * 0.045, 0.04, zo + 0.05), Vector3(90, 0, 0))
				MeshKit.part(root, MeshKit.sphere(0.012, 6), MeshKit.mat(Color(0.1, 0.08, 0.08)), Vector3(sx * 0.045, 0.04, zo + 0.045))
			MeshKit.part(root, MeshKit.capsule(0.007, 0.05), MeshKit.mat(Color(0.5, 0.2, 0.2)), Vector3(0, -0.04, zo + 0.045), Vector3(0, 0, 90))
			MeshKit.part(root, MeshKit.blob(0.13, 1.0, 0.0, 0, 10), MeshKit.surface_mat(Color(0.95, 0.35, 0.3), "cloth"), Vector3(0, -0.12, zo + 0.02), Vector3.ZERO, Vector3(1.1, 0.35, 0.2))


# --- Estanterías ---------------------------------------------------------------------------

static func _shelf(root: Node3D, trophies: bool, ctx: Dictionary) -> void:
	var col := DARK if trophies else OAK
	var w := 1.2
	var h := 1.85
	var d := 0.36
	for sx: float in [-1.0, 1.0]:
		_b(root, Vector3(0.06, h, d), col, Vector3(sx * w * 0.5, h * 0.5, 0), Vector3.ZERO, 0.02)
	_b(root, Vector3(w + 0.06, 0.05, d), col, Vector3(0, h, 0), Vector3.ZERO, 0.02)
	_b(root, Vector3(w, h, 0.03), col.darkened(0.15), Vector3(0, h * 0.5, -d * 0.5 + 0.015), Vector3.ZERO, 0.01)
	var levels := [0.06, 0.5, 0.95, 1.4]
	for y in levels:
		_b(root, Vector3(w, 0.04, d), col, Vector3(0, y, 0), Vector3.ZERO, 0.01)
	var r := RandomNumberGenerator.new()
	r.seed = 21
	if not trophies:
		var book_cols := [Color(0.75, 0.25, 0.25), Color(0.25, 0.45, 0.7), Color(0.35, 0.6, 0.35), Color(0.9, 0.75, 0.35), Color(0.55, 0.35, 0.6), Color(0.95, 0.92, 0.85)]
		for li in 3:
			var x := -w * 0.5 + 0.06
			while x < w * 0.5 - 0.12:
				var bw := r.randf_range(0.04, 0.08)
				var bh := r.randf_range(0.26, 0.36)
				var lean := 0.0 if r.randf() > 0.12 else 10.0
				_b(root, Vector3(bw, bh, 0.24), book_cols[r.randi() % book_cols.size()], Vector3(x + bw * 0.5, levels[li] + 0.02 + bh * 0.5, 0.02), Vector3(0, 0, lean), 0.008)
				x += bw + 0.008
				if r.randf() < 0.08:
					x += 0.12
		_pot(root, 0.08, 0.12)
		root.get_child(root.get_child_count() - 2).position = Vector3(0.35, levels[3] + 0.02, 0)
		root.get_child(root.get_child_count() - 1).position = Vector3(0.35, levels[3] + 0.02 + 0.105, 0)
		MeshKit.part(root, Flora.leafy_clump(0.12, 0.8, Color(0.4, 0.65, 0.35), 5), null, Vector3(0.35, levels[3] + 0.22, 0))
		_solid(root, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
		return
	# Vitrina: puertas de cristal y recuerdos de la aventura.
	var feathers: int = mini(int(ctx.get("feathers", 0)), 6)
	for k in feathers:
		var f := Props.feather()
		f.scale = Vector3.ONE * 0.28
		f.position = Vector3(-0.42 + k * 0.17, levels[2] + 0.22, 0.0)
		f.rotation.z = 0.3
		root.add_child(f)
	var beacons: int = mini(int(ctx.get("beacons", 0)), 5)
	for k in 5:
		var b := Node3D.new()
		b.position = Vector3(-0.44 + k * 0.22, levels[1] + 0.02, 0.0)
		root.add_child(b)
		var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.045, 0.3), Vector2(0.0, 0.3)])
		MeshKit.part(b, MeshKit.lathe(prof, 12), MeshKit.mat(Color(0.97, 0.96, 0.92)), Vector3.ZERO)
		MeshKit.part(b, MeshKit.cylinder(0.04, 0.04, 0.06, 10), _glow(Color(1.0, 0.85, 0.4), 2.0) if k < beacons else MeshKit.mat(Color(0.35, 0.38, 0.45)), Vector3(0, 0.33, 0))
		MeshKit.part(b, MeshKit.cone(0.055, 0.06, 10), MeshKit.mat(Color(0.86, 0.25, 0.25)), Vector3(0, 0.39, 0))
	# Bote de conchas.
	MeshKit.part(root, MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.0), Vector2(0.1, 0.22), Vector2(0.0, 0.22)]), 14),
		MeshKit.unshaded(Color(0.8, 0.92, 1.0, 0.35)), Vector3(0.3, levels[0] + 0.03, 0))
	for k in 6:
		var s := Props.shell()
		s.scale = Vector3.ONE * 0.22
		s.position = Vector3(0.3 + r.randf_range(-0.05, 0.05), levels[0] + 0.06 + k * 0.025, r.randf_range(-0.05, 0.05))
		root.add_child(s)
	_b(root, Vector3(0.32, 0.22, 0.22), Props.GOLD.darkened(0.1), Vector3(-0.3, levels[0] + 0.14, 0), Vector3.ZERO, 0.03)
	var glass := MeshKit.unshaded(Color(0.85, 0.95, 1.0, 0.16))
	MeshKit.part(root, MeshKit.rounded_box(Vector3(w - 0.04, h - 0.1, 0.01), 0.004, 1), glass, Vector3(0, h * 0.5, d * 0.5))
	_light(root, Vector3(0, h - 0.15, 0.1), Color(1.0, 0.9, 0.7), 0.35, 2.0)
	_solid(root, Vector3(w, h, d), Vector3(0, h * 0.5, 0))


# --- Pecera --------------------------------------------------------------------------------

static func _aquarium(root: Node3D, ctx: Dictionary) -> void:
	var w := 1.1
	var d := 0.5
	_b(root, Vector3(w + 0.1, 0.75, d + 0.1), OAK, Vector3(0, 0.375, 0), Vector3.ZERO, 0.03)
	_b(root, Vector3(w + 0.14, 0.05, d + 0.14), OAK.darkened(0.1), Vector3(0, 0.77, 0), Vector3.ZERO, 0.02)
	var y0 := 0.8
	var th := 0.55
	MeshKit.part(root, MeshKit.rounded_box(Vector3(w, 0.08, d), 0.01, 1), MeshKit.surface_mat(Color(0.92, 0.85, 0.65), "tile"), Vector3(0, y0 + 0.04, 0))
	var water := MeshKit.part(root, MeshKit.rounded_box(Vector3(w - 0.02, th - 0.1, d - 0.02), 0.01, 1), MeshKit.unshaded(Color(0.45, 0.78, 0.9, 0.35)), Vector3(0, y0 + 0.08 + (th - 0.1) * 0.5, 0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 4:
		var a := k * 1.7
		MeshKit.part(root, MeshKit.blob(0.03, 4.0, 0.2, k, 8), MeshKit.mat(Color(0.3, 0.62, 0.35)), Vector3(-0.4 + k * 0.26, y0 + 0.22, -0.12 + sin(a) * 0.08), Vector3(0, 0, sin(a) * 10.0))
	MeshKit.part(root, MeshKit.rock(5, 0.6, 12), Props._m(Props.STONE), Vector3(0.25, y0 + 0.1, 0.05), Vector3.ZERO, Vector3.ONE * 0.12)
	# Marco del cristal
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_b(root, Vector3(0.03, th, 0.03), DARK, Vector3(sx * w * 0.5, y0 + th * 0.5, sz * d * 0.5), Vector3.ZERO, 0.008)
	_b(root, Vector3(w + 0.04, 0.04, d + 0.04), DARK, Vector3(0, y0 + th, 0), Vector3.ZERO, 0.01)
	# Peces: uno por especie pescada (sin la bota).
	var fish := Node3D.new()
	fish.name = "Fish"
	fish.position = Vector3(0, y0 + 0.28, 0)
	root.add_child(fish)
	var kinds: Array = ctx.get("fish", [])
	var i := 0
	for id in kinds:
		if id == "fish_boot" or not Catalog.FISH.has(id):
			continue
		var f := Node3D.new()
		f.set_meta("phase", i * 1.3)
		fish.add_child(f)
		var col: Color = Catalog.FISH[id][5]
		var sz := 0.05 if id != "fish_legend" else 0.07
		MeshKit.part(f, MeshKit.blob(sz, 0.55, 0.0, 0, 10), _glow(col, 0.35) if id == "fish_glow" else MeshKit.mat(col), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, 1.0, 1.8))
		MeshKit.part(f, MeshKit.cone(sz * 0.7, sz * 1.0, 6), MeshKit.mat(col.darkened(0.15)), Vector3(0, 0, sz * 1.9), Vector3(-90, 0, 0), Vector3(0.3, 1.0, 1.0))
		i += 1
	_light(root, Vector3(0, y0 + th + 0.1, 0.2), Color(0.6, 0.85, 1.0), 0.45, 2.5)
	_solid(root, Vector3(w + 0.1, y0 + th, d + 0.1), Vector3(0, (y0 + th) * 0.5, 0))


## Mueve los peces de la pecera (lo llama la casa cada fotograma).
static func swim(fish_root: Node3D, t: float) -> void:
	for f: Node3D in fish_root.get_children():
		var ph: float = f.get_meta("phase", 0.0)
		var a := t * 0.6 + ph
		f.position = Vector3(cos(a) * 0.38, sin(t * 1.3 + ph) * 0.08, sin(a) * 0.12)
		f.rotation.y = -a + PI


# --- Estufa --------------------------------------------------------------------------------

static func _stove(root: Node3D) -> void:
	var iron := Color(0.22, 0.22, 0.24)
	_b(root, Vector3(0.8, 0.7, 0.6), iron, Vector3(0, 0.45, 0), Vector3.ZERO, 0.06)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_b(root, Vector3(0.08, 0.12, 0.08), iron, Vector3(sx * 0.32, 0.06, sz * 0.24), Vector3.ZERO, 0.02)
	_b(root, Vector3(0.86, 0.05, 0.66), iron.lightened(0.1), Vector3(0, 0.82, 0), Vector3.ZERO, 0.02)
	# Ventanilla con el fuego.
	_b(root, Vector3(0.42, 0.3, 0.03), iron.lightened(0.15), Vector3(0, 0.45, 0.3), Vector3.ZERO, 0.02)
	var fire := MeshKit.part(root, MeshKit.rounded_box(Vector3(0.34, 0.22, 0.02), 0.01, 1), _glow(Color(1.0, 0.55, 0.2), 2.5), Vector3(0, 0.45, 0.31))
	fire.name = "Fire"
	# Tubo de la chimenea hasta el techo y una tetera.
	MeshKit.part(root, MeshKit.cylinder(0.08, 0.08, 2.4, 12), Props._m(iron), Vector3(0, 2.05, -0.12))
	MeshKit.part(root, MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.12, 0.08), Vector2(0.06, 0.16), Vector2(0.0, 0.17)]), 14),
		MeshKit.mat(Color(0.3, 0.5, 0.7)), Vector3(0.22, 0.845, 0.1))
	MeshKit.part(root, MeshKit.cylinder(0.012, 0.016, 0.12, 6), MeshKit.mat(Color(0.3, 0.5, 0.7)), Vector3(0.34, 0.92, 0.1), Vector3(0, 0, -50))
	_light(root, Vector3(0, 0.5, 0.55), Color(1.0, 0.6, 0.3), 1.0, 4.5)
	_solid(root, Vector3(0.8, 0.9, 0.6), Vector3(0, 0.45, 0))


## Muestra de pared o suelo para la tienda: un trozo de pared con zócalo o unas baldosas.
static func _sample(root: Node3D, id: String) -> void:
	if WALLS.has(id):
		var wl: Array = WALLS[id]
		MeshKit.part(root, MeshKit.rounded_box(Vector3(1.2, 1.3, 0.1), 0.02, 1), MeshKit.surface_mat(wl[0], wl[2]), Vector3(0, 0.85, 0))
		_b(root, Vector3(1.24, 0.5, 0.14), wl[1], Vector3(0, 0.25, 0.01), Vector3.ZERO, 0.02)
		if wl[3]:
			var r := RandomNumberGenerator.new()
			r.seed = 4
			for k in 10:
				MeshKit.part(root, MeshKit.sphere(0.02, 6), _glow(Color(1.0, 0.9, 0.5), 1.0), Vector3(r.randf_range(-0.55, 0.55), r.randf_range(0.6, 1.45), 0.06))
	else:
		var fl: Array = FLOORS[id]
		MeshKit.part(root, MeshKit.rounded_box(Vector3(1.4, 0.08, 1.4), 0.02, 1), MeshKit.surface_mat(fl[0], fl[1], 0.12, 0.6), Vector3(0, 0.04, 0))
