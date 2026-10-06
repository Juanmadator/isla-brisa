class_name Home
extends Node3D
## Casa de Lía por dentro: una habitación apartada de la isla (Lía entra por la puerta de la
## casa del tejado morado y aparece aquí tras un fundido). Tiene huecos fijos para los muebles
## que vende Martín y paredes y suelo que se pueden cambiar. El sol no la ilumina (va en su
## propia capa visual): la luz entra por las ventanas (que muestran el cielo de esta hora) y
## sale del farol del techo y de las lámparas, la estufa o la pecera.

const ORIGIN := Vector3(1500, 200, 1500)
const HALF := Vector2(4.0, 3.3)
const HEIGHT := 3.2
const WALL := 0.3
## Capa visual del interior (el sol la excluye).
const LAYER := 1 << 9
## Puerta (en la pared delantera, +Z) y atril con el cuaderno de decoración.
const DOOR_X := 1.6
const BOOK := Vector3(3.15, 0, 2.85)
## Huecos: id -> [categoría, posición en el suelo (o en la pared), giro en grados, nombre]
const SLOTS := {
	"bed": ["bed", Vector3(-2.92, 0, -2.2), 0.0, "Cama"],
	"lamp": ["lamp", Vector3(-1.82, 0, -2.98), 0.0, "Lámpara"],
	"art_back": ["art", Vector3(0.1, 1.75, -HALF.y), 0.0, "Cuadro del fondo"],
	"shelf": ["shelf", Vector3(2.55, 0, -3.08), 0.0, "Estantería"],
	"stove": ["stove", Vector3(3.62, 0, -1.55), -90.0, "Estufa"],
	"fish": ["fish", Vector3(3.6, 0, 1.75), -90.0, "Pecera"],
	"table": ["table", Vector3(1.0, 0, -0.1), 0.0, "Mesa"],
	"rug": ["rug", Vector3(-1.3, 0, 0.75), 0.0, "Alfombra"],
	"art_left": ["art", Vector3(-HALF.x, 1.75, 0.3), 90.0, "Cuadro de la izquierda"],
	"plant_a": ["plant", Vector3(-3.5, 0, 2.85), 0.0, "Planta junto a la ventana"],
	"plant_b": ["plant", Vector3(-0.35, 0, 2.95), 0.0, "Planta de la entrada"],
}
const CATEGORY_NAMES := {"bed": "Cama", "table": "Mesa", "rug": "Alfombra", "lamp": "Lámpara", "plant": "Planta",
	"art": "Cuadro", "shelf": "Estantería", "fish": "Pecera", "stove": "Estufa", "wall": "Paredes", "floor": "Suelo"}

var sky: SkyCycle
var _slots := {}
var _walls: Array[MeshInstance3D] = []
var _wainscots: Array[MeshInstance3D] = []
var _floor: MeshInstance3D
var _stars: Node3D
var _ceiling_light: OmniLight3D
var _window_lights: Array[OmniLight3D] = []
var _t := 0.0
var _ctx := {}


func build(sky_cycle: SkyCycle) -> void:
	sky = sky_cycle
	position = ORIGIN
	name = "Home"
	_build_room()
	for id in SLOTS:
		var n := Node3D.new()
		n.name = "Slot_" + id
		var s: Array = SLOTS[id]
		n.position = s[1]
		n.rotation_degrees.y = s[2]
		add_child(n)
		_slots[id] = n
	refresh()


## Punto de entrada (dentro, junto a la puerta) en coordenadas del mundo.
func entry_point() -> Vector3:
	return ORIGIN + Vector3(DOOR_X, 0.05, HALF.y - 0.9)


func exit_point() -> Vector3:
	return ORIGIN + Vector3(DOOR_X, 0.0, HALF.y - 0.45)


func book_point() -> Vector3:
	return ORIGIN + BOOK


func bed_point() -> Vector3:
	return ORIGIN + (SLOTS["bed"][1] as Vector3)


func contains(p: Vector3) -> bool:
	var l := p - ORIGIN
	return absf(l.x) < HALF.x + 1.0 and absf(l.z) < HALF.y + 1.0 and l.y > -2.0 and l.y < HEIGHT + 2.0


## Vuelve a montar los muebles según la partida (y lo que muestran: peces, plumas, faros).
func refresh(ctx := {}) -> void:
	if not ctx.is_empty():
		_ctx = ctx
	for id in _slots:
		var holder: Node3D = _slots[id]
		for c in holder.get_children():
			c.queue_free()
		var item := SaveGame.home_item(id)
		if item != "" and Catalog.ITEMS.has(item):
			holder.add_child(Furniture.build(item, _ctx))
	_apply_surfaces()
	_set_layer(self)


## Prueba un mueble en un hueco sin guardarlo (para ver cómo queda desde el cuaderno).
func preview(slot: String, item: String) -> void:
	if slot == "wall" or slot == "floor":
		_apply_surfaces({slot: item})
		_set_layer(self)
		return
	var holder: Node3D = _slots[slot]
	for c in holder.get_children():
		c.queue_free()
	if item != "":
		holder.add_child(Furniture.build(item, _ctx))
	_set_layer(holder)


## Cuántos huecos tienen algo (paredes y suelo aparte).
func placed_count() -> int:
	var n := 0
	for id in SLOTS:
		if SaveGame.home_item(id) != "":
			n += 1
	return n


func has_bed() -> bool:
	return SaveGame.home_item("bed") != ""


func _set_layer(n: Node) -> void:
	if n is VisualInstance3D and not n is Light3D:
		(n as VisualInstance3D).layers = LAYER
	for c in n.get_children():
		_set_layer(c)


# --- Habitación ----------------------------------------------------------------------------

func _wall_piece(size: Vector3, pos: Vector3) -> void:
	var mi := MeshKit.part(self, MeshKit.rounded_box(size, 0.02, 1), null, pos)
	_walls.append(mi)


func _build_room() -> void:
	var body := Props.body(self)
	var w := HALF.x
	var d := HALF.y
	var h := HEIGHT
	# Suelo y techo con vigas.
	_floor = MeshKit.part(self, MeshKit.rounded_box(Vector3(w * 2.0 + 0.2, 0.2, d * 2.0 + 0.2), 0.02, 1), null, Vector3(0, -0.1, 0))
	Props.box_col(body, Vector3(w * 2.0 + 1.0, 0.4, d * 2.0 + 1.0), Vector3(0, -0.2, 0))
	MeshKit.part(self, MeshKit.rounded_box(Vector3(w * 2.0 + 0.6, 0.2, d * 2.0 + 0.6), 0.02, 1), MeshKit.surface_mat(Color(0.93, 0.9, 0.82), "plaster"), Vector3(0, h + 0.1, 0))
	Props.box_col(body, Vector3(w * 2.0 + 1.0, 0.4, d * 2.0 + 1.0), Vector3(0, h + 0.2, 0))
	for k in 5:
		Props._box(self, Vector3(0.2, 0.22, d * 2.0), Props.WOOD_DARK, Vector3(-w + 0.8 + k * (w * 2.0 - 1.6) / 4.0, h - 0.11, 0), Vector3.ZERO, 0.03)
	Props._box(self, Vector3(w * 2.0, 0.24, 0.24), Props.WOOD_DARK, Vector3(0, h - 0.3, 0), Vector3.ZERO, 0.03)
	# Paredes: fondo con ventana, lados (derecho con ventana), delante con puerta y ventana.
	var win := Vector2(1.0, 1.0)
	var wy := 1.85
	# Fondo (z = -d): ventana sobre la cama.
	var bx := SLOTS["bed"][1].x as float
	_wall_with_window(Vector3(0, 0, -d - WALL * 0.5), w * 2.0, bx, win, wy, 0.0, body)
	# Derecha (x = +w): ventana entre la estufa y la pecera.
	_wall_with_window(Vector3(w + WALL * 0.5, 0, 0), d * 2.0, 0.1, win, wy, -90.0, body)
	# Izquierda (x = -w): pared entera.
	_wall_with_window(Vector3(-w - WALL * 0.5, 0, 0), d * 2.0, 0.0, Vector2.ZERO, wy, 90.0, body)
	# Delante (z = +d): puerta y ventana.
	_front_wall(Vector3(0, 0, d + WALL * 0.5), w * 2.0, body)
	# Farol del techo.
	var lantern := Node3D.new()
	lantern.position = Vector3(-0.4, h - 0.3, 0.3)
	add_child(lantern)
	MeshKit.part(lantern, MeshKit.cylinder(0.01, 0.01, 0.5, 4), MeshKit.mat(Color(0.2, 0.2, 0.2)), Vector3(0, 0.0, 0))
	MeshKit.part(lantern, MeshKit.cylinder(0.12, 0.16, 0.06, 12), Props._m(Color(0.25, 0.25, 0.27)), Vector3(0, -0.28, 0))
	MeshKit.part(lantern, MeshKit.cylinder(0.1, 0.1, 0.22, 12), MeshKit.mat(Color(1.0, 0.88, 0.6), 0.0, 1.6, Color(1.0, 0.85, 0.55)), Vector3(0, -0.42, 0))
	MeshKit.part(lantern, MeshKit.cylinder(0.14, 0.12, 0.05, 12), Props._m(Color(0.25, 0.25, 0.27)), Vector3(0, -0.55, 0))
	_ceiling_light = OmniLight3D.new()
	_ceiling_light.position = lantern.position + Vector3(0, -0.45, 0)
	_ceiling_light.light_color = Color(1.0, 0.86, 0.66)
	_ceiling_light.omni_range = 9.0
	_ceiling_light.omni_attenuation = 1.2
	_ceiling_light.shadow_enabled = true
	add_child(_ceiling_light)
	# Atril con el cuaderno de decoración.
	var lect := Node3D.new()
	lect.position = BOOK
	lect.rotation_degrees.y = -150.0
	add_child(lect)
	Props._box(lect, Vector3(0.08, 1.0, 0.08), Props.WOOD_DARK, Vector3(0, 0.5, 0), Vector3.ZERO, 0.02)
	Props._box(lect, Vector3(0.4, 0.04, 0.3), Props.WOOD_DARK, Vector3(0, 0.02, 0), Vector3.ZERO, 0.01)
	Props._box(lect, Vector3(0.5, 0.04, 0.38), Props.WOOD, Vector3(0, 1.02, 0), Vector3(-25, 0, 0), 0.01)
	Props._box(lect, Vector3(0.42, 0.04, 0.3), Color(0.95, 0.92, 0.84), Vector3(0, 1.06, 0.0), Vector3(-25, 0, 0), 0.01)
	Props._box(lect, Vector3(0.02, 0.05, 0.3), Color(0.75, 0.25, 0.25), Vector3(0, 1.07, 0.0), Vector3(-25, 0, 0), 0.004)
	var lb := Props.body(lect)
	Props.box_col(lb, Vector3(0.45, 1.1, 0.4), Vector3(0, 0.55, 0))
	# Estrellas de la pared "noche estrellada" (se ven solo con esa pared).
	_stars = Node3D.new()
	add_child(_stars)
	var r := RandomNumberGenerator.new()
	r.seed = 12
	var star_m := MeshKit.mat(Color(1.0, 0.9, 0.5), 0.0, 1.4, Color(1.0, 0.9, 0.5))
	for k in 60:
		var side := k % 4
		var p := Vector3.ZERO
		var u := r.randf_range(-0.95, 0.95)
		var y := r.randf_range(1.2, h - 0.2)
		match side:
			0: p = Vector3(u * w, y, -d + 0.02)
			1: p = Vector3(u * w, y, d - 0.02)
			2: p = Vector3(-w + 0.02, y, u * d)
			3: p = Vector3(w - 0.02, y, u * d)
		MeshKit.part(_stars, MeshKit.sphere(r.randf_range(0.012, 0.03), 6), star_m, p, Vector3.ZERO, Vector3.ONE, false)


## Pared de `length` m centrada en `center` (girada `yaw` grados), con una ventana opcional
## (tamaño `win`, centro a `wx` m del centro y `wy` m de alto) y zócalo.
func _wall_with_window(center: Vector3, length: float, wx: float, win: Vector2, wy: float, yaw: float, body: StaticBody3D) -> void:
	var holder := Node3D.new()
	holder.position = center
	holder.rotation_degrees.y = yaw
	add_child(holder)
	var h := HEIGHT
	var pieces := []
	if win == Vector2.ZERO:
		pieces.append([Vector3(length, h, WALL), Vector3(0, h * 0.5, 0)])
	else:
		var left := (wx - win.x * 0.5) + length * 0.5
		var right := length * 0.5 - (wx + win.x * 0.5)
		pieces.append([Vector3(left, h, WALL), Vector3(-length * 0.5 + left * 0.5, h * 0.5, 0)])
		pieces.append([Vector3(right, h, WALL), Vector3(length * 0.5 - right * 0.5, h * 0.5, 0)])
		var below := wy - win.y * 0.5
		var above := h - (wy + win.y * 0.5)
		pieces.append([Vector3(win.x, below, WALL), Vector3(wx, below * 0.5, 0)])
		pieces.append([Vector3(win.x, above, WALL), Vector3(wx, h - above * 0.5, 0)])
		_window(holder, Vector3(wx, wy, 0), win, 1.0)
	for pc in pieces:
		var mi := MeshKit.part(holder, MeshKit.rounded_box(pc[0], 0.015, 1), null, pc[1])
		_walls.append(mi)
	var col_size := Vector3(length + WALL * 2.0, h, WALL) if yaw == 0.0 else Vector3(WALL, h, length + WALL * 2.0)
	Props.box_col(body, col_size, center + Vector3(0, h * 0.5, 0))
	# Zócalo a lo largo de la pared, por dentro (en estas paredes, el interior es +Z local).
	var ws := MeshKit.part(holder, MeshKit.rounded_box(Vector3(length, 0.75, 0.05), 0.015, 1), null, Vector3(0, 0.375, WALL * 0.5 + 0.02))
	_wainscots.append(ws)


## Ventana en una pared; `inner` es el lado de la habitación en el eje Z local (+1 o -1).
func _window(holder: Node3D, pos: Vector3, win: Vector2, inner: float) -> void:
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/window_sky.gdshader")
	MeshKit.part(holder, MeshKit.quad(win), glass, pos, Vector3(90, 0, 0), Vector3.ONE, false)
	# Marco, cruceta, alféizar y cortinas a los lados (por dentro).
	var fz := 0.0
	for sy: float in [-1.0, 1.0]:
		Props._box(holder, Vector3(win.x + 0.16, 0.08, WALL + 0.06), Color(0.95, 0.94, 0.9), pos + Vector3(0, sy * win.y * 0.5, fz), Vector3.ZERO, 0.02)
	for sx: float in [-1.0, 1.0]:
		Props._box(holder, Vector3(0.08, win.y + 0.16, WALL + 0.06), Color(0.95, 0.94, 0.9), pos + Vector3(sx * win.x * 0.5, 0, fz), Vector3.ZERO, 0.02)
	Props._box(holder, Vector3(0.04, win.y, 0.04), Color(0.95, 0.94, 0.9), pos, Vector3.ZERO, 0.01)
	Props._box(holder, Vector3(win.x, 0.04, 0.04), Color(0.95, 0.94, 0.9), pos, Vector3.ZERO, 0.01)
	Props._box(holder, Vector3(win.x + 0.3, 0.06, 0.26), Color(0.95, 0.94, 0.9), pos + Vector3(0, -win.y * 0.5 - 0.05, inner * 0.2), Vector3.ZERO, 0.02)
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(holder, MeshKit.soft_box(Vector3(0.3, win.y + 0.5, 0.06), 0.03, 0.02, 0.0, 3), MeshKit.surface_mat(Color(0.95, 0.88, 0.7), "cloth", 0.05),
			pos + Vector3(sx * (win.x * 0.5 + 0.2), 0.05, inner * 0.22))
	Props._box(holder, Vector3(win.x + 1.0, 0.04, 0.04), Props.WOOD_DARK, pos + Vector3(0, win.y * 0.5 + 0.28, inner * 0.24), Vector3.ZERO, 0.01)
	# Luz del día que entra por la ventana.
	var l := OmniLight3D.new()
	l.position = holder.position + holder.basis * (pos + Vector3(0, 0, inner * 1.0))
	l.omni_range = 5.0
	l.omni_attenuation = 1.0
	l.shadow_enabled = false
	add_child(l)
	_window_lights.append(l)


func _front_wall(center: Vector3, length: float, body: StaticBody3D) -> void:
	# Pared delantera: puerta en DOOR_X y una ventana en -1.7.
	var holder := Node3D.new()
	holder.position = center
	add_child(holder)
	var h := HEIGHT
	var door := Vector2(1.2, 2.3)
	var win := Vector2(1.0, 1.0)
	var wx := -1.7
	var wy := 1.85
	var x0 := -length * 0.5
	var segs := [[x0, wx - win.x * 0.5], [wx + win.x * 0.5, DOOR_X - door.x * 0.5], [DOOR_X + door.x * 0.5, length * 0.5]]
	for sg in segs:
		var a: float = sg[0]
		var b: float = sg[1]
		var mi := MeshKit.part(holder, MeshKit.rounded_box(Vector3(b - a, h, WALL), 0.015, 1), null, Vector3((a + b) * 0.5, h * 0.5, 0))
		_walls.append(mi)
	_walls.append(MeshKit.part(holder, MeshKit.rounded_box(Vector3(win.x, wy - win.y * 0.5, WALL), 0.015, 1), null, Vector3(wx, (wy - win.y * 0.5) * 0.5, 0)))
	var above_w := h - (wy + win.y * 0.5)
	_walls.append(MeshKit.part(holder, MeshKit.rounded_box(Vector3(win.x, above_w, WALL), 0.015, 1), null, Vector3(wx, h - above_w * 0.5, 0)))
	var above_d := h - door.y
	_walls.append(MeshKit.part(holder, MeshKit.rounded_box(Vector3(door.x, above_d, WALL), 0.015, 1), null, Vector3(DOOR_X, h - above_d * 0.5, 0)))
	_window(holder, Vector3(wx, wy, 0), win, -1.0)
	# Puerta cerrada (se sale con E) con marco y pomo.
	Props._box(holder, Vector3(door.x + 0.2, door.y + 0.12, WALL + 0.08), Props.WOOD_DARK, Vector3(DOOR_X, door.y * 0.5, 0), Vector3.ZERO, 0.03)
	Props._box(holder, Vector3(door.x - 0.1, door.y - 0.1, WALL + 0.1), Props.WOOD, Vector3(DOOR_X, door.y * 0.5 - 0.02, 0), Vector3.ZERO, 0.03)
	for k in 3:
		Props._box(holder, Vector3(door.x - 0.2, 0.05, 0.03), Props.WOOD_DARK, Vector3(DOOR_X, 0.45 + k * 0.7, -WALL * 0.5 - 0.06), Vector3.ZERO, 0.01)
	MeshKit.part(holder, MeshKit.sphere(0.06, 8), Props._m(Props.GOLD), Vector3(DOOR_X - door.x * 0.5 + 0.18, 1.1, -WALL * 0.5 - 0.08))
	# Felpudo.
	MeshKit.part(self, MeshKit.soft_box(Vector3(1.1, 0.025, 0.6), 0.02, 0.0, 0.0, 2), MeshKit.surface_mat(Color(0.75, 0.6, 0.38), "thatch", 0.0), Vector3(DOOR_X, 0.012, HALF.y - 0.45))
	Props.box_col(body, Vector3(length + WALL * 2.0, h, WALL), center + Vector3(0, h * 0.5, 0))
	# Zócalo por dentro, a los dos lados de la puerta.
	for sg in [[x0, DOOR_X - door.x * 0.5 - 0.12], [DOOR_X + door.x * 0.5 + 0.12, length * 0.5]]:
		var a: float = sg[0]
		var b: float = sg[1]
		var ws := MeshKit.part(holder, MeshKit.rounded_box(Vector3(b - a, 0.75, 0.05), 0.015, 1), null, Vector3((a + b) * 0.5, 0.375, -WALL * 0.5 - 0.02))
		_wainscots.append(ws)


func _apply_surfaces(override := {}) -> void:
	var wall_id: String = override.get("wall", SaveGame.home_item("wall"))
	var floor_id: String = override.get("floor", SaveGame.home_item("floor"))
	if not Furniture.WALLS.has(wall_id):
		wall_id = "furn_wall_white"
	if not Furniture.FLOORS.has(floor_id):
		floor_id = "furn_floor_planks"
	var wl: Array = Furniture.WALLS[wall_id]
	var wm := MeshKit.surface_mat(wl[0], wl[2], 0.0, 0.8)
	for mi in _walls:
		mi.material_override = wm
	var wsm := Props._m(wl[1])
	for mi in _wainscots:
		mi.material_override = wsm
	_stars.visible = wl[3]
	var fl: Array = Furniture.FLOORS[floor_id]
	_floor.material_override = MeshKit.surface_mat(fl[0], fl[1], 0.1, 0.55)


func _process(dt: float) -> void:
	_t += dt
	if sky == null:
		return
	var night := sky.night
	_ceiling_light.light_energy = lerpf(0.55, 1.5, night)
	var sky_col: Color = (sky.sample(sky.hour)[2] as Color).lerp(Color(1, 1, 1), 0.3)
	for l in _window_lights:
		l.light_color = sky_col
		l.light_energy = lerpf(1.1, 0.05, night)
	for id in _slots:
		for f in (_slots[id] as Node3D).get_children():
			var lt := f.get_node_or_null("Light") as OmniLight3D
			if lt:
				var base: float = lt.get_meta("base", 1.0)
				var flicker := 1.0 + (sin(_t * 13.0) * 0.06 + sin(_t * 7.3) * 0.05 if id == "stove" else 0.0)
				lt.light_energy = base * lerpf(0.7, 1.5, night) * flicker
			var spin := f.get_node_or_null("Spin") as Node3D
			if spin:
				spin.rotation.y = _t * 1.2
			var fish := f.get_node_or_null("Fish") as Node3D
			if fish:
				Furniture.swim(fish, _t)
