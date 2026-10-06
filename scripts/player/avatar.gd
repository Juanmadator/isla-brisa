class_name Avatar
extends Node3D
## Personaje procedural (Lía y los vecinos) con esqueleto y animación por código.
## El cuerpo es una malla continua con pesos de huesos (BodyKit): tronco, brazos y piernas se
## doblan como una sola pieza. Las piernas usan cinemática inversa: al andar, cada pie sigue
## un ciclo de marcha sincronizado con la velocidad (no patina) y se apoya en el suelo real
## (cuestas, escalones, muelles); parada, Lía planta los pies y da pasitos para girar.
## Todas las articulaciones se mueven con muelles amortiguados, así que los cambios de
## postura tienen inercia en vez de interpolarse en línea recta.
## El modelo mira hacia -Z y su origen está en los pies.
## Quien lo usa pone `state` (idle, walk, jump, fall, glide, hook, climb, swim, talk, wave, sit,
## mantle, land, hold_up, cheer...) y `speed` (m/s) cada fotograma.

## Un pie se acaba de apoyar en el suelo (0 = izquierdo, 1 = derecho; posición en el mundo).
signal foot_planted(side: int, pos: Vector3)

var state := "idle"
var speed := 0.0
var climb_move := Vector2.ZERO
var lean := 0.0
## Avance de la voltereta (0 a 1) mientras state == "roll".
var roll_k := 0.0
## Giro de los pedales (radianes) mientras state == "bike".
var pedal := 0.0
## Punto del mundo al que mira (INF = a ninguno): la cabeza y los ojos lo siguen.
var look_target := Vector3.INF
## Punto del mundo que toca con la mano derecha al agacharse (recoger, acariciar, abrir).
var reach_target := Vector3.INF
## Pies apoyados en el suelo con rayos (solo los personajes que están en el mundo).
var ground_ik := true
## Cuerpos que ignoran los rayos de los pies (la cápsula del propio personaje).
var ray_exclude: Array[RID] = []
## El dueño mueve al personaje en _physics_process (con interpolación física).
var physics_owner := false

var spec := {}
var skel: Skeleton3D
var head: Node3D
var glider: Node3D
var hat_holder: Node3D
var eyes: Array[Node3D] = []
var pivot: Node3D
## Punto sobre la cabeza donde Lía sostiene lo que encuentra.
var hold_point: Node3D
var mouth_smile: Node3D
var mouth_open: Node3D
var brows: Array[Node3D] = []
## Manos (0 = izquierda, 1 = derecha), para sujetar la cuerda o la caña.
var hands: Array[Node3D] = []
## Expresión forzada (vacía = según el estado): "happy", "surprised", "talk".
var mood := ""
## En una conversación: está diciendo su frase (mueve la boca) o escuchando (asiente).
var speaking := false
var listening := false

## Huesos.
enum {HIPS, SPINE, CHEST, NECK, HEAD, UARM_L, FARM_L, HAND_L, UARM_R, FARM_R, HAND_R,
	THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R}
const BONE_NAMES := ["hips", "spine", "chest", "neck", "head", "upperarm_l", "forearm_l", "hand_l",
	"upperarm_r", "forearm_r", "hand_r", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
const HIP_Y := 0.62
const THIGH := 0.25
const SHIN := 0.235
const ANKLE := 0.075
const UPPER_ARM := 0.21
const FOREARM := 0.21
const LEG := THIGH + SHIN

## Articulaciones que se mueven con muelle (radianes, salvo hips_* en metros).
const POSE_KEYS := ["arm_l", "arm_r", "arm_lz", "arm_rz", "elbow_l", "elbow_r", "wrist_l", "wrist_r",
	"leg_l", "leg_r", "leg_lz", "leg_rz", "knee_l", "knee_r", "foot_l", "foot_r",
	"hips_y", "hips_side", "hips_x", "hips_yaw", "hips_roll", "torso_x", "torso_y", "torso_z",
	"head_x", "head_y", "head_z", "ik"]

## Estados con los pies apoyados (cinemática inversa en las piernas).
const IK_STATES := ["idle", "talk", "wave", "walk", "land", "fish", "fish_cast", "fish_reel", "hold_up", "pickup"]

var _g := 1.0
var _rest: Array[Vector3] = []
var _x := {}
var _v := {}
var _sq := 1.0
var _sq_v := 0.0
var _t := 0.0
var _blink := 2.0
var _tail_ang := Vector2.ZERO
var _last_pos := Vector3.ZERO
var _last_state := ""
var _state_t := 0.0
## Marcha: fase del ciclo (0-1), y datos del ciclo actual.
var _phase := 0.0
var _gait_w := 0.0
var _prev_speed := 0.0
var _accel := 0.0
## Pies: posición plantada en el mundo (cuando está parada) y pasito en curso.
var _plant: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _step_t: Array[float] = [-1.0, -1.0]
var _step_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_to: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _ground: Array[float] = [0.0, 0.0]
var _ground_n: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _hip_drop := 0.0
var _look := Vector2.ZERO
var _hair_swing: Node3D
var _hair_ang := Vector2.ZERO
var _hair_vel := Vector2.ZERO
var _pack: Node3D
var _pack_v := 0.0
var _pack_x := 0.0
var _prev_vel := Vector3.ZERO
## Alguien (una conversación) controla cuándo habla: entonces la boca solo se mueve al hablar.
var _dialog_driven := false
const SCARF_N := 4
const SCARF_SEG := 0.085
var _scarf_anchor: Node3D
var _scarf_segs: Array[MeshInstance3D] = []
var _scarf_pts: Array[Vector3] = []
var _scarf_prev: Array[Vector3] = []
## Cápsulas del cuerpo en el espacio del modelo: [a, b, radio].
var _scarf_colliders: Array = []

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
		remove_child(c)
		c.queue_free()
	eyes.clear()
	hands.clear()
	brows.clear()
	_scarf_segs.clear()
	_scarf_pts.clear()
	_hair_swing = null
	_pack = null
	var g: float = spec["girth"]
	_g = g
	scale = Vector3.ONE * float(spec["height"])
	pivot = Node3D.new()
	add_child(pivot)
	hold_point = Node3D.new()
	hold_point.position = Vector3(0, 2.12, -0.06)
	pivot.add_child(hold_point)
	_build_skeleton(g)
	_build_body(g)
	# Cabeza (rígida, pegada a su hueso).
	head = _attach(HEAD)
	_build_head()
	hat_holder = Node3D.new()
	hat_holder.position = Vector3(0, 0.25, 0)
	head.add_child(hat_holder)
	set_hat(spec["hat"], spec["hat_color"])
	# Paravela (oculta salvo al planear)
	glider = Node3D.new()
	glider.position = Vector3(0, 1.72, 0.0)
	glider.visible = false
	glider.scale = Vector3.ONE * 1.3
	add_child(glider)
	_build_glider(Color(0.98, 0.95, 0.85), Color(0.95, 0.4, 0.35))
	for k in POSE_KEYS:
		_x[k] = 0.0
		_v[k] = 0.0
	_x["ik"] = 1.0
	_plant = [Vector3.INF, Vector3.INF]
	_step_t = [-1.0, -1.0]


# --- Esqueleto y cuerpo -------------------------------------------------------------

func _build_skeleton(g: float) -> void:
	skel = Skeleton3D.new()
	skel.name = "Skeleton"
	pivot.add_child(skel)
	var bones := [
		[-1, Vector3(0, HIP_Y, 0)], [HIPS, Vector3(0, 0.1, 0)], [SPINE, Vector3(0, 0.17, 0)], [CHEST, Vector3(0, 0.19, 0)], [NECK, Vector3(0, 0.04, 0)],
		[CHEST, Vector3(-0.2 * g, 0.11, 0)], [UARM_L, Vector3(0, -UPPER_ARM, 0)], [FARM_L, Vector3(0, -FOREARM, 0)],
		[CHEST, Vector3(0.2 * g, 0.11, 0)], [UARM_R, Vector3(0, -UPPER_ARM, 0)], [FARM_R, Vector3(0, -FOREARM, 0)],
		[HIPS, Vector3(-0.09 * g, -0.06, 0)], [THIGH_L, Vector3(0, -THIGH, 0)], [SHIN_L, Vector3(0, -SHIN, 0)],
		[HIPS, Vector3(0.09 * g, -0.06, 0)], [THIGH_R, Vector3(0, -THIGH, 0)], [SHIN_R, Vector3(0, -SHIN, 0)],
	]
	_rest.clear()
	for i in bones.size():
		skel.add_bone(BONE_NAMES[i])
		skel.set_bone_parent(i, bones[i][0])
		skel.set_bone_rest(i, Transform3D(Basis(), bones[i][1]))
		_rest.append(bones[i][1])
	skel.reset_bone_poses()


## Posición de reposo de un hueso en el espacio del modelo.
func _rest_global(b: int) -> Vector3:
	var p := Vector3.ZERO
	while b >= 0:
		p += _rest[b]
		b = skel.get_bone_parent(b)
	return p


func _attach(bone: int) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = BONE_NAMES[bone]
	skel.add_child(ba)
	return ba


func _skinned(mesh: ArrayMesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = _skin
	mi.extra_cull_margin = 0.8
	return mi


var _skin: Skin


func _build_body(g: float) -> void:
	_skin = skel.create_skin_from_rest_transforms()
	var shirt: Color = spec["shirt"]
	var skin_col: Color = spec["skin"]
	var dress: bool = spec["dress"]
	var hem := 0.25 * g if dress else 0.18 * g
	_skinned(_torso_mesh(g, hem, dress), BodyKit.cloth_mat(shirt))
	for side in [-1.0, 1.0]:
		_skinned(_arm_mesh(g, side), BodyKit.cloth_mat(shirt))
		_skinned(_leg_mesh(g, side), BodyKit.cloth_mat(spec["pants"]))
	# Cinturón (rígido en la cadera, que no se dobla).
	var hips_att := _attach(HIPS)
	MeshKit.part(hips_att, MeshKit.torus(0.15 * g, 0.2 * g), MeshKit.mat(Color(0.45, 0.3, 0.2), 0.0), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.62, 0.85))
	var spine_att := _attach(SPINE)
	var chest_att := _attach(CHEST)
	var o := 0.022
	if spec["apron"] != null:
		# Del pecho a medio muslo, ceñido al tronco y algo abierto abajo.
		MeshKit.part(spine_att, BodyKit.apron(0.19 * g, 0.168 * g, 0.2, -0.27, 0.62), MeshKit.surface_mat(spec["apron"], "cloth", 0.06))
		for sx: float in [-1.0, 1.0]:
			MeshKit.part(chest_att, MeshKit.rounded_box(Vector3(0.025, 0.2, 0.012), 0.005, 1), MeshKit.mat((spec["apron"] as Color).darkened(0.1), 0.0), Vector3(sx * 0.07 * g, 0.12, -0.14 * g), Vector3(-12, 0, -sx * 10.0))
	if spec["bag"]:
		MeshKit.part(spine_att, MeshKit.soft_box(Vector3(0.28, 0.24, 0.12), 0.04, 0.008, 0.0, 4), MeshKit.surface_mat(Color(0.55, 0.35, 0.2), "cloth", 0.08), Vector3(0.2 * g, -0.12, 0.05))
		MeshKit.part(chest_att, MeshKit.rounded_box(Vector3(0.04, 0.62, 0.025), 0.01, 1), MeshKit.mat(Color(0.45, 0.28, 0.16), 0.0), Vector3(0.02, -0.07, -0.03), Vector3(0, 0, 38))
	if spec["backpack"]:
		_pack = Node3D.new()
		_pack.position = Vector3(0, 0.1, 0.12)
		chest_att.add_child(_pack)
		var pk := MeshKit.surface_mat(Color(0.6, 0.42, 0.28), "cloth", 0.08)
		MeshKit.part(_pack, MeshKit.soft_box(Vector3(0.25, 0.27, 0.11), 0.045, 0.006, 0.05, 5), pk, Vector3(0, -0.12, 0.04))
		MeshKit.part(_pack, MeshKit.soft_box(Vector3(0.18, 0.1, 0.04), 0.02, 0.003, 0.0, 6), MeshKit.surface_mat(Color(0.52, 0.36, 0.24), "cloth", 0.08), Vector3(0, -0.15, 0.105))
		MeshKit.part(_pack, MeshKit.capsule(0.085, 0.44), MeshKit.surface_mat(Color(0.95, 0.9, 0.75), "cloth", 0.06), Vector3(0, 0.03, 0.05), Vector3(0, 0, 90))
		for sx: float in [-1.0, 1.0]:
			MeshKit.part(chest_att, MeshKit.rounded_box(Vector3(0.035, 0.26, 0.02), 0.008, 1), MeshKit.mat(Color(0.45, 0.3, 0.2), 0.0), Vector3(sx * 0.1 * g, 0.03, -0.135 * g), Vector3(-8, 0, 0))
	# Manos (manoplas con pulgar).
	for side in [-1.0, 1.0]:
		var hb := HAND_L if side < 0.0 else HAND_R
		var hand := _attach(hb)
		hands.append(hand)
		var hand_m := BodyKit.skin_mat(skin_col)
		MeshKit.part(hand, BodyKit.mitten(0.06), hand_m, Vector3(0, -0.005, 0), Vector3.ZERO, Vector3(-side, 1.0, 1.0))
		MeshKit.part(hand, MeshKit.capsule(0.021, 0.07), hand_m, Vector3(-side * 0.014, -0.03, -0.05), Vector3(-30, 0, side * 18.0))
	# Zapatos.
	for side in [-1.0, 1.0]:
		var fb := FOOT_L if side < 0.0 else FOOT_R
		var foot := _attach(fb)
		var shoe_c: Color = spec["shoes"]
		MeshKit.part(foot, BodyKit.shoe(ANKLE, 0.062), MeshKit.surface_mat(shoe_c, "cloth", 0.1))
		MeshKit.part(foot, MeshKit.soft_box(Vector3(0.12, 0.022, 0.215), 0.01, 0.002, 0.0, 7), MeshKit.mat(shoe_c.darkened(0.4), 0.0), Vector3(0, -ANKLE + 0.011, -0.04))
	# Bufanda con cola que ondea.
	if spec["scarf"] != null:
		var sc: Color = spec["scarf"]
		MeshKit.part(chest_att, MeshKit.torus(0.068, 0.15), MeshKit.surface_mat(sc, "cloth", 0.06), Vector3(0, 0.19, 0), Vector3(-6, 0, 0), Vector3(1, 1.7, 0.95))
		# Cola de la bufanda: cadena de tramos de tela con física (ver _scarf_sim).
		_scarf_anchor = Node3D.new()
		_scarf_anchor.position = Vector3(0.06, 0.205, 0.1)
		_scarf_colliders = [[Vector3(0, 0.5, 0), Vector3(0, 0.93, -0.01), 0.19 * g], [Vector3(0, 0.98, 0), Vector3(0, 1.06, 0), 0.06]]
		if spec["backpack"]:
			_scarf_colliders.append([Vector3(-0.08, 0.86, 0.16), Vector3(0.08, 0.86, 0.16), 0.11])
			_scarf_colliders.append([Vector3(-0.22, 1.02, 0.17), Vector3(0.22, 1.02, 0.17), 0.095])
		chest_att.add_child(_scarf_anchor)
		var seg := MeshKit.soft_box(Vector3(0.1, 0.026, SCARF_SEG * 1.12), 0.012, 0.003, 0.0, 2)
		for k in SCARF_N:
			var mi := MeshKit.part(self, seg, MeshKit.surface_mat(sc.darkened(0.06 * (k % 2)), "cloth", 0.06), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, k < SCARF_N - 1)
			mi.top_level = true
			mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			_scarf_segs.append(mi)
		_scarf_pts.clear()
	else:
		_scarf_anchor = null


## Tronco con faldón: de una pieza, más ancho que profundo, pecho algo adelantado, hombros
## caídos y pliegues en el bajo. El faldón sigue un poco a los muslos al andar.
func _torso_mesh(g: float, hem: float, dress: bool) -> ArrayMesh:
	var skirt := lerpf(hem, 0.2 * g, 0.45)
	var y0 := HIP_Y
	var secs := [
		[Vector3(0, y0 - 0.166, 0), hem * 0.96, hem * 0.83], [Vector3(0, y0 - 0.14, 0), hem, hem * 0.86],
		[Vector3(0, y0 - 0.07, 0), skirt, skirt * 0.86], [Vector3(0, y0 + 0.04, 0), 0.188 * g, 0.162 * g], [Vector3(0, y0 + 0.13, -0.006), 0.176 * g, 0.15 * g],
		[Vector3(0, y0 + 0.24, -0.014), 0.18 * g, 0.156 * g], [Vector3(0, y0 + 0.31, -0.016), 0.178 * g, 0.15 * g], [Vector3(0, y0 + 0.36, -0.008), 0.164 * g, 0.136 * g],
		[Vector3(0, y0 + 0.405, 0.0), 0.138 * g, 0.116 * g], [Vector3(0, y0 + 0.446, 0.004), 0.1 * g, 0.088 * g],
		[Vector3(0, y0 + 0.478, 0.006), 0.074, 0.068], [Vector3(0, y0 + 0.5, 0.006), 0.05, 0.05]]
	var folds := func(u: float, v: float) -> float:
		var k := clampf(1.0 - u / 0.3, 0.0, 1.0)
		return 1.0 + sin(v * TAU * 7.0 + 0.6) * 0.03 * k * k * (1.0 if dress else 0.4)
	var weights := func(p: Vector3, _u: float) -> Array:
		var ws: Array = []
		var y := p.y
		if y < y0 + 0.06:
			# Faldón: cadera y algo de cada muslo según el lado (se mueve con las piernas).
			var down := clampf((y0 + 0.02 - y) / 0.17, 0.0, 1.0)
			var side := clampf(p.x / (0.16 * g), -1.0, 1.0)
			var tl := down * 0.42 * clampf(0.5 - side * 0.5, 0.0, 1.0)
			var tr := down * 0.42 * clampf(0.5 + side * 0.5, 0.0, 1.0)
			var hw := 1.0 - tl - tr
			var up := clampf((y - (y0 + 0.0)) / 0.06, 0.0, 1.0)
			ws = [[HIPS, hw * (1.0 - up * 0.5)], [SPINE, hw * up * 0.5], [THIGH_L, tl], [THIGH_R, tr]]
		elif y < y0 + 0.2:
			var t := clampf((y - (y0 + 0.06)) / 0.14, 0.0, 1.0)
			ws = [[HIPS, 0.5 * (1.0 - t)], [SPINE, 0.5 + 0.2 * t], [CHEST, 0.3 * t]]
		elif y < y0 + 0.44:
			var t := clampf((y - (y0 + 0.2)) / 0.14, 0.0, 1.0)
			ws = [[SPINE, 0.7 * (1.0 - t)], [CHEST, 0.3 + 0.7 * t]]
			# Hombros: la parte de arriba y de fuera sigue un poco al brazo.
			var sh := smoothstep(0.1 * g, 0.19 * g, absf(p.x)) * smoothstep(y0 + 0.3, y0 + 0.4, y)
			if sh > 0.0:
				ws.append([UARM_L if p.x < 0.0 else UARM_R, sh * 0.35])
		else:
			var t := clampf((y - (y0 + 0.44)) / 0.06, 0.0, 1.0)
			ws = [[CHEST, 1.0 - t * 0.6], [NECK, t * 0.6]]
		return ws
	# Dobladillo algo más oscuro.
	var shade := func(p: Vector3, _u: float) -> float:
		return 0.84 if p.y < y0 - 0.125 else 1.0
	return BodyKit.tube("torso|%.3f|%.3f|%s" % [g, hem, dress], secs, 28, 4, weights, folds, shade, 0.0)


## Brazo con manga de una pieza, del hombro a la muñeca: se dobla por el codo sin juntas.
func _arm_mesh(g: float, side: float) -> ArrayMesh:
	var x := side * 0.2 * g
	var top := HIP_Y + 0.27 + 0.11
	var ua := UARM_L if side < 0.0 else UARM_R
	var fa := FARM_L if side < 0.0 else FARM_R
	var hb := HAND_L if side < 0.0 else HAND_R
	var elbow := top - UPPER_ARM
	var wrist := elbow - FOREARM
	var secs := [
		[Vector3(x, top + 0.055, 0), 0.026, 0.026], [Vector3(x, top + 0.042, 0), 0.052, 0.05], [Vector3(x, top, 0), 0.066, 0.064],
		[Vector3(x, top - 0.08, 0), 0.058, 0.056], [Vector3(x, elbow + 0.02, 0), 0.051, 0.05], [Vector3(x, elbow - 0.04, 0), 0.05, 0.049],
		[Vector3(x, wrist + 0.07, 0), 0.046, 0.045], [Vector3(x, wrist + 0.03, 0), 0.051, 0.05], [Vector3(x, wrist + 0.012, 0), 0.05, 0.049],
		[Vector3(x, wrist + 0.005, 0), 0.02, 0.02]]
	var weights := func(p: Vector3, _u: float) -> Array:
		if p.y > elbow + 0.04:
			return [[ua, 1.0]]
		if p.y > elbow - 0.04:
			return BodyKit.blend_y(p, elbow, 0.08, ua, fa)
		if p.y > wrist + 0.035:
			return [[fa, 1.0]]
		return BodyKit.blend_y(p, wrist + 0.02, 0.03, fa, hb)
	var shade := func(p: Vector3, _u: float) -> float:
		return 0.84 if p.y < wrist + 0.04 else 1.0
	return BodyKit.tube("arm|%.3f|%d" % [g, int(side)], secs, 18, 4, weights, Callable(), shade, x)


## Pierna de una pieza de la cadera al tobillo; se dobla por la rodilla.
func _leg_mesh(g: float, side: float) -> ArrayMesh:
	var x := side * 0.09 * g
	var th := THIGH_L if side < 0.0 else THIGH_R
	var sh := SHIN_L if side < 0.0 else SHIN_R
	var fb := FOOT_L if side < 0.0 else FOOT_R
	var hip := HIP_Y - 0.06
	var knee := hip - THIGH
	var ankle := knee - SHIN
	var secs := [
		[Vector3(x, hip + 0.11, 0), 0.05, 0.05], [Vector3(x, hip + 0.07, 0), 0.08, 0.082], [Vector3(x, hip - 0.04, 0), 0.077, 0.08],
		[Vector3(x, knee + 0.1, -0.003), 0.068, 0.07], [Vector3(x, knee + 0.01, -0.006), 0.06, 0.062], [Vector3(x, knee - 0.07, 0.004), 0.062, 0.066],
		[Vector3(x, ankle + 0.1, 0.0), 0.053, 0.054], [Vector3(x, ankle + 0.04, 0), 0.049, 0.05], [Vector3(x, ankle + 0.005, 0), 0.044, 0.045],
		[Vector3(x, ankle - 0.02, 0), 0.02, 0.02]]
	var weights := func(p: Vector3, _u: float) -> Array:
		if p.y > hip + 0.02:
			var t := clampf((p.y - (hip + 0.02)) / 0.08, 0.0, 1.0)
			return [[th, 1.0 - t * 0.45], [HIPS, t * 0.45]]
		if p.y > knee + 0.045:
			return [[th, 1.0]]
		if p.y > knee - 0.045:
			return BodyKit.blend_y(p, knee, 0.09, th, sh)
		if p.y > ankle + 0.03:
			return [[sh, 1.0]]
		return BodyKit.blend_y(p, ankle + 0.01, 0.04, sh, fb)
	var shade := func(p: Vector3, _u: float) -> float:
		return 0.86 if p.y < ankle + 0.06 and p.y > ankle + 0.025 else 1.0
	return BodyKit.tube("leg|%.3f|%d" % [g, int(side)], secs, 18, 4, weights, Callable(), shade, x)


func _build_head() -> void:
	var o := 0.022
	var skin: Color = spec["skin"]
	var skin_m := MeshKit.mat(skin, 0.0).duplicate() as ShaderMaterial
	skin_m.set_shader_parameter("sheen", 0.14)
	skin_m.set_shader_parameter("rim_amount", 0.3)
	skin_m.set_shader_parameter("detail", 0.02)
	MeshKit.part(head, MeshKit.capsule(0.062, 0.18), skin_m, Vector3(0, 0.0, 0.005))
	MeshKit.part(head, BodyKit.head(0.25), skin_m, Vector3(0, 0.25, 0))
	# Nariz, orejas con su pliegue.
	MeshKit.part(head, MeshKit.blob(0.036, 1.2, 0.0, 0, 14), skin_m, Vector3(0, 0.212, -0.25), Vector3(-12, 0, 0), Vector3(0.95, 1.0, 0.85))
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(head, MeshKit.blob(0.056, 1.25, 0.0, 0, 14), skin_m, Vector3(sx * 0.243, 0.245, 0.02), Vector3(0, sx * 15.0, 0), Vector3(0.5, 1.0, 0.85))
		MeshKit.part(head, MeshKit.blob(0.03, 1.2, 0.0, 0, 12), MeshKit.mat(skin.darkened(0.14), 0.0), Vector3(sx * 0.262, 0.245, 0.012), Vector3(0, sx * 15.0, 0), Vector3(0.3, 1.0, 0.65))
	var iris_col: Color = spec["eye_color"]
	var brow_col: Color = (spec["hair"] as Color).darkened(0.25)
	for sx: float in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(sx * 0.088, 0.275, -0.205)
		eye.rotation_degrees = Vector3(6, sx * 14.0, 0)
		head.add_child(eye)
		eyes.append(eye)
		MeshKit.part(eye, MeshKit.sphere(0.058, 16), MeshKit.mat(Color(1, 1, 1), 0.006, 0.0, Color(0, 0, 0, 0), 0.0), Vector3.ZERO, Vector3.ZERO, Vector3(0.82, 1.18, 0.42))
		var iris := Node3D.new()
		iris.name = "Iris"
		eye.add_child(iris)
		MeshKit.part(iris, MeshKit.sphere(0.04, 16), MeshKit.mat(iris_col, 0.0, 0.0, Color(0, 0, 0, 0), 0.0), Vector3(0, -0.006, -0.016), Vector3.ZERO, Vector3(0.85, 1.12, 0.4))
		MeshKit.part(iris, MeshKit.sphere(0.022, 12), MeshKit.mat(Color(0.06, 0.05, 0.08), 0.0, 0.0, Color(0, 0, 0, 0), 0.0), Vector3(0, -0.006, -0.024), Vector3.ZERO, Vector3(0.9, 1.1, 0.4))
		MeshKit.part(iris, MeshKit.sphere(0.013, 12), MeshKit.unshaded(Color.WHITE), Vector3(sx * -0.01 + 0.012, 0.022, -0.03))
		var brow := MeshKit.part(head, MeshKit.capsule(0.011, 0.075), MeshKit.mat(brow_col, 0.0), Vector3(sx * 0.09, 0.365, -0.213), Vector3(0, 0, 90.0 - sx * 8.0))
		brows.append(brow)
		MeshKit.part(head, MeshKit.sphere(0.045, 12), MeshKit.mat(Color(1.0, 0.6, 0.6), 0.0), Vector3(sx * 0.15, 0.19, -0.2), Vector3.ZERO, Vector3(1, 0.6, 0.4))
	var mouth := Node3D.new()
	mouth.position = Vector3(0, 0.155, -0.238)
	head.add_child(mouth)
	mouth_smile = Node3D.new()
	mouth.add_child(mouth_smile)
	var lip := MeshKit.mat(Color(0.45, 0.18, 0.15), 0.0)
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(mouth_smile, MeshKit.capsule(0.008, 0.042), lip, Vector3(sx * 0.016, 0.004, 0), Vector3(0, 0, 90.0 + sx * 22.0))
	mouth_open = Node3D.new()
	mouth.add_child(mouth_open)
	MeshKit.part(mouth_open, MeshKit.sphere(0.03, 12), MeshKit.mat(Color(0.35, 0.1, 0.1), 0.0), Vector3(0, 0, 0.004), Vector3.ZERO, Vector3(1.1, 0.85, 0.35))
	MeshKit.part(mouth_open, MeshKit.sphere(0.018, 12), MeshKit.mat(Color(1.0, 0.55, 0.55), 0.0), Vector3(0, -0.012, -0.004), Vector3.ZERO, Vector3(1.2, 0.6, 0.3))
	mouth_open.visible = false
	if spec["glasses"]:
		for sx: float in [-1.0, 1.0]:
			MeshKit.part(head, MeshKit.torus(0.05, 0.065), MeshKit.mat(Color(0.2, 0.2, 0.22), 0.0), Vector3(sx * 0.085, 0.27, -0.245), Vector3(90, 0, 0))
		MeshKit.part(head, MeshKit.capsule(0.006, 0.05), MeshKit.mat(Color(0.2, 0.2, 0.22), 0.0), Vector3(0, 0.275, -0.255), Vector3(0, 0, 90))
	if spec["beard"]:
		MeshKit.part(head, MeshKit.blob(0.17, 0.9, 0.15, 3, 14), MeshKit.surface_mat(spec["hair"], "hair", 0.06), Vector3(0, 0.1, -0.15), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
	_build_hair(head, o)


## Mechones sueltos: blobs alargados entre `a` y `b` (posiciones en la cabeza) que caen con
## inclinaciones algo distintas; rompen el "casco" de pelo liso.
func _locks(h: Node3D, m: Material, n: int, a: Vector3, b: Vector3, size: float, stretch: float, tilt_x: float, seed_value: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	for i in n:
		var t := (i + 0.5) / n
		var p := a.lerp(b, t)
		var side := p.x
		var rot := Vector3(tilt_x + r.randf_range(-8, 8), 0, -side * 90.0 + r.randf_range(-10, 10))
		MeshKit.part(h, MeshKit.blob(size * r.randf_range(0.85, 1.15), stretch, 0.08, i + seed_value, 12), m, p, rot, Vector3(1.0, 1.0, 0.55))


func _build_hair(h: Node3D, _o: float) -> void:
	var hc: Color = spec["hair"]
	var m := MeshKit.surface_mat(hc, "hair", 0.08)
	var hs: String = spec["hair_style"]
	var sd := int(hc.r * 97.0 + hc.g * 31.0)
	# Lo que cuelga por detrás (coletas, melena) va en un pivote que se balancea con muelle.
	_hair_swing = Node3D.new()
	_hair_swing.position = Vector3(0, 0.36, 0.12)
	h.add_child(_hair_swing)
	var back := func(p: Vector3) -> Vector3:
		return p - _hair_swing.position
	if hs in ["bob", "long", "pony", "pigtails", "bun"]:
		_locks(h, m, 5, Vector3(-0.15, 0.445, -0.205), Vector3(0.15, 0.445, -0.205), 0.062, 1.25, -38.0, sd)
	elif hs == "short":
		_locks(h, m, 4, Vector3(-0.12, 0.47, -0.17), Vector3(0.12, 0.47, -0.17), 0.05, 1.1, -45.0, sd)
		for i in 6:
			var a := TAU * i / 6.0
			MeshKit.part(h, MeshKit.blob(0.06, 1.6, 0.1, i + sd, 12), m, Vector3(cos(a) * 0.1, 0.55, 0.06 + sin(a) * 0.1), Vector3(-25 + sin(a) * 20.0, 0, -cos(a) * 25.0), Vector3(1.0, 1.0, 0.7))
	if hs == "long":
		var r := RandomNumberGenerator.new()
		r.seed = sd + 5
		for i in 5:
			var t := (i + 0.5) / 5.0
			var p: Vector3 = back.call(Vector3(lerpf(-0.17, 0.17, t), 0.12, 0.17))
			MeshKit.part(_hair_swing, MeshKit.blob(0.075 * r.randf_range(0.85, 1.15), 2.0, 0.08, i + sd + 5, 12), m, p, Vector3(10 + r.randf_range(-8, 8), 0, -p.x * 90.0 + r.randf_range(-10, 10)), Vector3(1.0, 1.0, 0.55))
	match hs:
		"bob":
			MeshKit.part(h, MeshKit.blob(0.275, 0.95, 0.06, 4, 20), m, Vector3(0, 0.3, 0.035))
			MeshKit.part(h, MeshKit.blob(0.2, 0.55, 0.1, 5, 14), m, Vector3(0, 0.44, -0.12), Vector3(-20, 0, 0))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(h, MeshKit.blob(0.12, 1.4, 0.1, 6, 14), m, Vector3(sx * 0.2, 0.18, 0.02))
		"short":
			MeshKit.part(h, MeshKit.blob(0.265, 0.85, 0.12, 7, 20), m, Vector3(0, 0.33, 0.04))
		"bun":
			MeshKit.part(h, MeshKit.blob(0.268, 0.9, 0.04, 8, 20), m, Vector3(0, 0.31, 0.04))
			MeshKit.part(h, MeshKit.blob(0.12, 0.95, 0.12, 9, 14), m, Vector3(0, 0.5, 0.15))
		"long":
			MeshKit.part(h, MeshKit.blob(0.275, 0.95, 0.06, 9, 20), m, Vector3(0, 0.3, 0.04))
			MeshKit.part(_hair_swing, MeshKit.blob(0.22, 1.6, 0.08, 10, 16), m, back.call(Vector3(0, 0.08, 0.13)))
		"pony":
			MeshKit.part(h, MeshKit.blob(0.268, 0.9, 0.04, 11, 20), m, Vector3(0, 0.31, 0.04))
			MeshKit.part(_hair_swing, MeshKit.blob(0.09, 2.2, 0.1, 12, 14), m, back.call(Vector3(0, 0.22, 0.3)), Vector3(30, 0, 0))
		"bald":
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(h, MeshKit.blob(0.1, 1.2, 0.15, 13, 12), m, Vector3(sx * 0.22, 0.24, 0.06))
		"pigtails":
			MeshKit.part(h, MeshKit.blob(0.268, 0.9, 0.05, 14, 20), m, Vector3(0, 0.31, 0.04))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(_hair_swing, MeshKit.blob(0.1, 1.5, 0.1, 15, 14), m, back.call(Vector3(sx * 0.28, 0.24, 0.08)), Vector3(0, 0, sx * 25))


func set_hat(kind: String, color: Color) -> void:
	if hat_holder == null:
		return
	for c in hat_holder.get_children():
		c.queue_free()
	var o := 0.02
	match kind:
		"straw":
			MeshKit.part(hat_holder, MeshKit.cylinder(0.42, 0.42, 0.03, 24), MeshKit.surface_mat(color, "thatch", 0.05, 3.0), Vector3(0, 0.13, 0))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.2, 0.24, 0.18, 20), MeshKit.surface_mat(color, "thatch", 0.05, 3.0), Vector3(0, 0.22, 0))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.245, 0.245, 0.05, 20), MeshKit.mat(Color(0.9, 0.35, 0.3), 0.0), Vector3(0, 0.16, 0))
		"postman":
			MeshKit.part(hat_holder, MeshKit.cylinder(0.25, 0.26, 0.16, 20), MeshKit.mat(color, o), Vector3(0, 0.2, 0.02))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.2, 0.2, 0.02, 16), MeshKit.mat(color.darkened(0.3), o), Vector3(0, 0.12, -0.14), Vector3(-10, 0, 0), Vector3(1, 1, 0.6))
			MeshKit.part(hat_holder, MeshKit.sphere(0.04, 12), MeshKit.mat(Color(1.0, 0.82, 0.3), 0.0), Vector3(0, 0.22, -0.24))
		"beret":
			MeshKit.part(hat_holder, MeshKit.blob(0.26, 0.4, 0.05, 2, 16), MeshKit.surface_mat(color, "cloth", 0.05), Vector3(0.04, 0.19, 0.02), Vector3(0, 0, -10))
		"bandana":
			MeshKit.part(hat_holder, MeshKit.blob(0.275, 0.55, 0.0, 3, 16), MeshKit.surface_mat(color, "cloth", 0.05), Vector3(0, 0.1, 0.03))
		"flowers":
			MeshKit.part(hat_holder, MeshKit.torus(0.2, 0.26), MeshKit.mat(Color(0.35, 0.65, 0.3), o), Vector3(0, 0.12, 0.02), Vector3(-8, 0, 0))
			var cols := [Color(1, 0.5, 0.6), Color(1, 0.9, 0.35), Color(1, 1, 1), Color(0.7, 0.6, 1)]
			for i in 8:
				var a := TAU * i / 8.0
				MeshKit.part(hat_holder, MeshKit.blob(0.055, 0.7, 0.2, i, 12), MeshKit.mat(cols[i % 4], 0.0), Vector3(cos(a) * 0.23, 0.14, sin(a) * 0.23))
		"miner":
			MeshKit.part(hat_holder, MeshKit.blob(0.28, 0.65, 0.0, 4, 16), MeshKit.mat(color, o), Vector3(0, 0.12, 0.02))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.06, 0.07, 0.06, 14), MeshKit.mat(Color(1, 0.95, 0.7), 0.0, 1.5), Vector3(0, 0.22, -0.24), Vector3(80, 0, 0))
		"fisher":
			MeshKit.part(hat_holder, MeshKit.lathe(PackedVector2Array([Vector2(0.38, -0.02), Vector2(0.3, 0.04), Vector2(0.22, 0.2), Vector2(0.0, 0.24)]), 20), MeshKit.surface_mat(color, "cloth", 0.05), Vector3(0, 0.08, 0.02))
		"cap":
			MeshKit.part(hat_holder, MeshKit.blob(0.275, 0.62, 0.0, 0, 16), MeshKit.surface_mat(color, "cloth", 0.05), Vector3(0, 0.1, 0.02))
			MeshKit.part(hat_holder, MeshKit.rounded_box(Vector3(0.36, 0.035, 0.24), 0.015, 2), MeshKit.mat(color.darkened(0.15), o), Vector3(0, 0.06, -0.3), Vector3(-8, 0, 0))
			MeshKit.part(hat_holder, MeshKit.sphere(0.035, 12), MeshKit.mat(color.lightened(0.4), 0.0), Vector3(0, 0.27, 0.02))
		"beanie":
			MeshKit.part(hat_holder, MeshKit.blob(0.285, 0.78, 0.0, 0, 16), MeshKit.surface_mat(color, "cloth", 0.05), Vector3(0, 0.1, 0.03))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.29, 0.295, 0.09, 20), MeshKit.surface_mat(color.darkened(0.12), "cloth", 0.05), Vector3(0, 0.02, 0.03))
			MeshKit.part(hat_holder, MeshKit.blob(0.075, 1.0, 0.25, 3, 12), MeshKit.surface_mat(Color(0.98, 0.95, 0.9), "hair", 0.05), Vector3(0, 0.33, 0.03))
		"sailor":
			MeshKit.part(hat_holder, MeshKit.cylinder(0.25, 0.27, 0.14, 20), MeshKit.mat(color, o), Vector3(0, 0.12, 0.02))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.275, 0.275, 0.05, 20), MeshKit.mat(Color(0.18, 0.25, 0.45), 0.0), Vector3(0, 0.08, 0.02))
			MeshKit.part(hat_holder, MeshKit.cylinder(0.3, 0.27, 0.03, 20), MeshKit.mat(color.darkened(0.04), o), Vector3(0, 0.205, 0.02))
		"crown":
			MeshKit.part(hat_holder, MeshKit.cylinder(0.17, 0.17, 0.1, 16), MeshKit.mat(Color(1.0, 0.82, 0.3), o, 0.4), Vector3(0, 0.25, 0))
			for i in 5:
				var a := TAU * i / 5.0
				MeshKit.part(hat_holder, MeshKit.cone(0.045, 0.12, 8), MeshKit.mat(Color(1.0, 0.82, 0.3), 0.0, 0.4), Vector3(cos(a) * 0.15, 0.34, sin(a) * 0.15))


func set_scarf_color(c: Color) -> void:
	spec["scarf"] = c
	build(spec)


func _build_glider(c1: Color, c2: Color) -> void:
	for c in glider.get_children():
		c.queue_free()
	# Vela de tela de una pieza, combada, con franjas de colores alternos (color de vértice).
	var segs := 7
	for i in segs:
		var a := lerpf(-1.1, 1.1, (i + 0.5) / segs)
		var pos := Vector3(sin(a) * 1.3, cos(a) * 0.5 + 0.25, 0.05)
		MeshKit.part(glider, MeshKit.soft_box(Vector3(0.4, 0.04, 0.95), 0.02, 0.006, 0.0, i), MeshKit.surface_mat(c1 if i % 2 == 0 else c2, "cloth", 0.04), pos, Vector3(0, 0, -rad_to_deg(a)))
	var line := MeshKit.mat(Color(0.4, 0.35, 0.3), 0.0)
	for sx: float in [-1.0, 1.0]:
		var from := Vector3(sx * 0.18, -0.15, -0.05)
		var to := Vector3(sx * 1.15, 0.45, 0.05)
		var mid := (from + to) * 0.5
		var l := MeshKit.part(glider, MeshKit.cylinder(0.008, 0.008, from.distance_to(to), 6), line, mid)
		l.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	MeshKit.part(glider, MeshKit.cylinder(0.02, 0.02, 0.6, 10), MeshKit.surface_mat(Color(0.5, 0.36, 0.25), "wood", 0.05), Vector3(0, -0.15, -0.05), Vector3(0, 0, 90))


func set_glider_colors(c1: Color, c2: Color) -> void:
	_build_glider(c1, c2)


## Posición en el mundo de la mano izquierda (0) o derecha (1).
func hand_position(side: int) -> Vector3:
	if side < hands.size() and is_instance_valid(hands[side]):
		return hands[side].global_transform * Vector3(0, -0.05, 0)
	return global_position + Vector3(0, 1.4, 0)


## Impulso de estirar (>0, al saltar) o aplastar (<0, al aterrizar).
func squash(amount: float) -> void:
	_sq_v += amount * 6.0


## Golpe al aterrizar (0-1): la cadera baja de golpe y las rodillas lo amortiguan (los pies
## siguen apoyados por la IK), el tronco se inclina y los brazos se abren un poco.
func impact(k: float) -> void:
	if _v.is_empty():
		return
	_v["hips_y"] -= 2.2 * k
	_v["torso_x"] -= 4.0 * k
	_v["head_x"] += 2.5 * k
	_v["arm_lz"] -= 3.0 * k
	_v["arm_rz"] += 3.0 * k
	_v["arm_l"] += 3.0 * k
	_v["arm_r"] += 3.0 * k
	_v["ik"] = maxf(_v["ik"], 0.0) + 8.0


# --- Animación ------------------------------------------------------------------------
# Ángulos (radianes): arm_* / leg_*: hombro y cadera hacia delante (+) o atrás (-);
# arm_*z / leg_*z: abrir/cerrar; elbow_*: flexión del codo (+); knee_*: flexión de la rodilla
# (-, se dobla hacia atrás); foot_*: puntera arriba (+); hips_x / torso_x: inclinación (+ hacia
# atrás); torso_y / hips_yaw: giro; head_*: cabeza. hips_y / hips_side en metros.

func _base_pose(breath: float) -> Dictionary:
	return {"arm_l": 0.06, "arm_r": 0.06, "arm_lz": -0.14, "arm_rz": 0.14, "elbow_l": 0.18, "elbow_r": 0.18,
		"wrist_l": 0.1, "wrist_r": 0.1, "leg_l": 0.0, "leg_r": 0.0, "leg_lz": 0.0, "leg_rz": 0.0,
		"knee_l": -0.04, "knee_r": -0.04, "foot_l": 0.0, "foot_r": 0.0,
		"hips_y": 0.0, "hips_side": 0.0, "hips_x": 0.0, "hips_yaw": 0.0, "hips_roll": 0.0,
		"torso_x": breath * 0.014, "torso_y": 0.0, "torso_z": 0.0, "head_x": 0.0, "head_y": 0.0, "head_z": 0.0, "ik": 0.0}


func _process(delta: float) -> void:
	if skel == null:
		return
	delta = minf(delta, 0.1)
	_t += delta
	if state != _last_state:
		_last_state = state
		_state_t = 0.0
		if not state in ["pickup", "kneel"]:
			reach_target = Vector3.INF
	_state_t += delta
	var sc := maxf(scale.y, 0.01)
	var sp := clampf(speed, 0.0, 14.0)
	var vm := sp / sc
	_accel = lerpf(_accel, (sp - _prev_speed) / maxf(delta, 0.001), clampf(delta * 6.0, 0.0, 1.0))
	_prev_speed = sp
	var run := smoothstep(2.2, 5.5, vm)
	var breath := sin(_t * 1.9)
	var t := _base_pose(breath)
	var rate := 12.0
	var damp := 0.82
	var gait := state == "walk" and vm > 0.05
	glider.visible = state == "glide"
	# Postura en los pies: [z del pie izq., z del pie dcho.] respecto a la cadera (delante < 0).
	var stance := [0.0, 0.0]
	match state:
		"idle", "talk":
			# Respira, pasa el peso de una pierna a otra (la rodilla del otro lado se afloja) y
			# mira alrededor de vez en cuando.
			var shift := sin(_t * 0.45) + sin(_t * 0.17) * 0.4
			t["hips_side"] = shift * 0.016
			t["hips_roll"] = -shift * 0.03
			t["hips_y"] = -0.012 + breath * 0.004
			t["torso_z"] = shift * 0.025
			t["arm_l"] = 0.05 + breath * 0.02
			t["arm_r"] = 0.05 - breath * 0.02
			t["head_y"] = sin(_t * 0.6) * 0.12 + sin(_t * 0.23) * 0.1
			t["head_x"] = sin(_t * 0.37) * 0.05
			t["head_z"] = -shift * 0.03
			stance = [-0.03, 0.04]
			if state == "talk":
				t["arm_r"] = 0.55 + sin(_t * 5.0) * 0.2
				t["elbow_r"] = 0.95 + sin(_t * 5.0) * 0.25
				t["arm_rz"] = 0.3
				t["wrist_r"] = -0.3
				t["head_x"] = sin(_t * 7.0) * 0.05
				t["head_z"] = sin(_t * 2.1) * 0.06
		"hold_up":
			var hb := sin(_t * 2.5)
			t["arm_l"] = 3.0
			t["arm_r"] = 3.0
			t["arm_lz"] = 0.3
			t["arm_rz"] = -0.3
			t["elbow_l"] = 0.25
			t["elbow_r"] = 0.25
			t["head_x"] = -0.28
			t["torso_x"] = 0.08
			t["hips_y"] = hb * 0.008
			stance = [-0.06, 0.06]
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
			t["leg_l"] = 0.25 * (1.0 - cb)
			t["leg_r"] = 0.25 * (1.0 - cb)
			t["foot_l"] = -0.3 * cb
			t["foot_r"] = -0.3 * cb
			t["head_x"] = -0.2
		"wave":
			t["arm_r"] = 2.5
			t["arm_rz"] = 0.35
			t["elbow_r"] = 0.6 + sin(_t * 9.0) * 0.4
			t["wrist_r"] = sin(_t * 9.0 + 0.6) * 0.3
			t["head_x"] = -0.1
			t["head_z"] = 0.08
			t["torso_z"] = -0.04
			t["hips_side"] = -0.012
			stance = [0.0, 0.02]
		"sit":
			var swing := sin(_t * 1.4)
			t["leg_l"] = 1.45
			t["leg_r"] = 1.45
			t["knee_l"] = -1.35 + swing * 0.18
			t["knee_r"] = -1.35 - swing * 0.18
			t["foot_l"] = -0.25
			t["foot_r"] = -0.25
			t["hips_y"] = -0.24
			t["torso_x"] = 0.08 + breath * 0.014
			t["head_y"] = sin(_t * 0.35) * 0.4
			t["arm_l"] = 0.4
			t["arm_r"] = 0.4
			t["elbow_l"] = 0.7
			t["elbow_r"] = 0.7
			t["wrist_l"] = 0.4
			t["wrist_r"] = 0.4
		"walk":
			rate = 18.0
		"jump":
			# Despegue: estira el cuerpo y luego recoge una pierna y sube los brazos.
			var k := clampf(_state_t / 0.25, 0.0, 1.0)
			t["leg_l"] = lerpf(0.2, 0.95, k)
			t["leg_r"] = lerpf(-0.1, -0.3, k)
			t["knee_l"] = -lerpf(0.4, 1.4, k)
			t["knee_r"] = -lerpf(0.2, 0.6, k)
			t["foot_l"] = -0.2
			t["foot_r"] = -0.6
			t["arm_l"] = 2.2
			t["arm_r"] = 1.1
			t["elbow_l"] = 0.35
			t["elbow_r"] = 0.9
			t["arm_lz"] = -0.3
			t["arm_rz"] = 0.4
			t["torso_x"] = -0.12
			t["head_x"] = -0.12
			rate = 16.0
		"fall":
			var f := sin(_t * 9.0) * 0.25
			t["leg_l"] = 0.4 + f
			t["leg_r"] = 0.1 - f
			t["knee_l"] = -0.6 - f
			t["knee_r"] = -0.35 + f
			t["foot_l"] = 0.1
			t["foot_r"] = -0.2
			t["arm_l"] = 2.3 + f
			t["arm_r"] = 2.3 - f
			t["elbow_l"] = 0.5
			t["elbow_r"] = 0.5
			t["arm_lz"] = -0.75
			t["arm_rz"] = 0.75
			t["head_x"] = 0.15
			rate = 10.0
		"land":
			# Amortigua con todo el cuerpo: la cadera baja y las rodillas se doblan solas (IK).
			var k := clampf(_state_t / 0.12, 0.0, 1.0)
			t["hips_y"] = -0.17 * (1.0 - 0.3 * k)
			t["torso_x"] = -0.45
			t["head_x"] = 0.25
			t["arm_l"] = 0.7
			t["arm_r"] = 0.7
			t["elbow_l"] = 0.7
			t["elbow_r"] = 0.7
			t["arm_lz"] = -0.4
			t["arm_rz"] = 0.4
			stance = [-0.05, 0.07]
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
			t["foot_l"] = -0.5
			t["foot_r"] = -0.5
			t["torso_x"] = -0.15
			t["head_x"] = 0.1
			rate = 8.0
		"hook":
			# Lanzar el gancho: echa el brazo atrás y lo suelta hacia arriba.
			var throw := _state_t > 0.13
			t["arm_r"] = 3.0 if throw else -0.7
			t["elbow_r"] = 0.05 if throw else 1.5
			t["arm_rz"] = 0.1
			t["arm_l"] = 0.9
			t["elbow_l"] = 0.8
			t["torso_y"] = -0.25 if throw else 0.35
			t["torso_x"] = 0.15 if throw else -0.1
			t["hips_yaw"] = -0.1 if throw else 0.12
			t["head_x"] = -0.45
			t["knee_l"] = -0.35
			t["knee_r"] = -0.2
			t["leg_l"] = 0.2
			rate = 22.0
		"climb":
			# Trepar por la cuerda: cuerpo echado atrás, pies contra la pared y mano sobre mano.
			_phase += delta * 1.05 * clampf(climb_move.length(), 0.0, 1.0)
			var c := sin(_phase * TAU)
			var idle_sway := sin(_t * 1.3) * 0.04
			t["hips_x"] = 0.38 + idle_sway
			t["torso_x"] = -0.2
			t["torso_y"] = c * 0.08
			t["leg_l"] = 0.95 + c * 0.32
			t["leg_r"] = 0.95 - c * 0.32
			t["knee_l"] = -0.95 + c * 0.35
			t["knee_r"] = -0.95 - c * 0.35
			t["foot_l"] = 0.35
			t["foot_r"] = 0.35
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
			rate = 14.0
		"bike":
			# Sentada en la bici: manos al manillar y piernas pedaleando en círculo.
			var pl := pedal
			t["leg_l"] = 1.15 + sin(pl) * 0.38
			t["leg_r"] = 1.15 - sin(pl) * 0.38
			t["knee_l"] = -1.25 - cos(pl) * 0.42
			t["knee_r"] = -1.25 + cos(pl) * 0.42
			t["foot_l"] = -0.1 + cos(pl) * 0.2
			t["foot_r"] = -0.1 - cos(pl) * 0.2
			t["arm_l"] = 1.15
			t["arm_r"] = 1.15
			t["elbow_l"] = 0.35
			t["elbow_r"] = 0.35
			t["arm_lz"] = -0.25
			t["arm_rz"] = 0.25
			t["torso_x"] = -0.32
			t["head_x"] = 0.15
			rate = 30.0
		"pickup":
			# Agacharse con las dos rodillas (IK) y la mano al suelo.
			var down := clampf(_state_t / 0.18, 0.0, 1.0)
			if _state_t > 0.3:
				down = 1.0 - clampf((_state_t - 0.3) / 0.15, 0.0, 1.0)
			t["hips_y"] = -0.27 * down
			t["torso_x"] = -0.6 * down
			t["head_x"] = 0.35 * down
			t["arm_l"] = 0.7 * down + 0.06
			t["arm_r"] = 1.15 * down + 0.06
			t["elbow_l"] = 0.4
			t["elbow_r"] = 0.2
			stance = [-0.12, 0.08]
			rate = 20.0
		"kneel":
			# Rodilla en tierra, escarbando o acariciando con la mano derecha.
			var down := clampf(_state_t / 0.18, 0.0, 1.0)
			t["leg_l"] = 1.25 * down
			t["leg_r"] = 0.3 * down
			t["knee_l"] = -1.9 * down
			t["knee_r"] = -2.2 * down
			t["foot_l"] = -0.3 * down
			t["foot_r"] = -1.1 * down
			t["hips_y"] = -0.3 * down
			t["torso_x"] = -0.5 * down
			t["head_x"] = 0.35 * down
			t["arm_l"] = 0.7 * down + 0.06
			t["arm_r"] = 1.05 * down + 0.06
			t["elbow_l"] = 0.6
			t["elbow_r"] = 0.25 + sin(_t * 9.0) * 0.35
			t["arm_rz"] = -0.08
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
			t["hips_yaw"] = 0.1 if back else -0.08
			t["hips_side"] = 0.015 if back else -0.02
			stance = [-0.14, 0.06]
			rate = 22.0
		"fish":
			t["arm_r"] = 1.0
			t["elbow_r"] = 0.75
			t["arm_rz"] = -0.05
			t["arm_l"] = 0.85
			t["elbow_l"] = 1.0
			t["arm_lz"] = 0.35
			t["torso_x"] = -0.05 + breath * 0.012
			t["head_x"] = 0.2
			stance = [-0.12, 0.05]
		"fish_reel":
			# Tira de la caña echándose atrás y da vueltas al carrete con la otra mano.
			t["arm_r"] = 1.15 + sin(_t * 9.0) * 0.12
			t["elbow_r"] = 0.9
			t["arm_l"] = 0.95 + sin(_t * 12.0) * 0.18
			t["elbow_l"] = 1.25 + cos(_t * 12.0) * 0.3
			t["arm_lz"] = 0.4
			t["torso_x"] = 0.25
			t["hips_y"] = -0.05
			t["head_x"] = 0.15
			stance = [-0.16, 0.1]
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
			t["foot_r"] = -0.5
			t["torso_x"] = -0.55
			rate = 20.0
		"swim":
			# Braza de costado: brazos alternos, patada con las piernas y la cabeza fuera.
			_phase += delta * (0.5 + vm * 0.14)
			var ph := _phase * TAU
			var s2 := sin(ph)
			t["hips_x"] = -1.15
			t["head_x"] = 0.85
			t["torso_y"] = s2 * 0.18
			t["hips_yaw"] = -s2 * 0.1
			t["arm_l"] = 1.6 + s2 * 1.4
			t["arm_r"] = 1.6 - s2 * 1.4
			t["elbow_l"] = 0.25 + maxf(s2, 0.0) * 0.8
			t["elbow_r"] = 0.25 + maxf(-s2, 0.0) * 0.8
			t["arm_lz"] = -0.4
			t["arm_rz"] = 0.4
			t["leg_l"] = sin(ph * 2.0) * 0.35 - 0.1
			t["leg_r"] = -sin(ph * 2.0) * 0.35 - 0.1
			t["knee_l"] = -0.25 - maxf(sin(ph * 2.0), 0.0) * 0.5
			t["knee_r"] = -0.25 - maxf(-sin(ph * 2.0), 0.0) * 0.5
			t["foot_l"] = -0.7
			t["foot_r"] = -0.7
			t["hips_y"] = 0.25
			rate = 9.0
	if speaking or listening:
		_dialog_driven = true
	if state != "talk" and not listening:
		_dialog_driven = false
	if listening and state in ["idle", "talk"]:
		# Escucha: asiente despacio de vez en cuando e inclina un poco la cabeza.
		var nod := pow(maxf(sin(_t * 1.1), 0.0), 8.0)
		t["head_x"] += nod * 0.22 + 0.04
		t["head_z"] += 0.07
		t["arm_r"] = 0.06
		t["elbow_r"] = 0.18
	if state == "talk" and _dialog_driven and not speaking:
		# Su turno ha terminado: baja la mano y espera.
		t["arm_r"] = 0.12
		t["elbow_r"] = 0.35
		t["arm_rz"] = 0.14
	var use_ik := state in IK_STATES
	t["ik"] = 1.0 if use_ik or state == "climb" else 0.0
	# Marcha: fase, braceo, balanceo de cadera y hombros, inclinación por velocidad y aceleración.
	var gw_target := 1.0 if gait else 0.0
	_gait_w = move_toward(_gait_w, gw_target, delta * 6.0)
	var g := _gait_params(vm, run)
	if gait:
		_phase = fposmod(_phase + delta * vm / g["cycle"], 1.0)
		var beta: float = g["beta"]
		var fl := -sin(TAU * (_phase - beta * 0.5))
		var amp := lerpf(0.6, 1.0, run)
		var bob_a := lerpf(0.01, 0.028, run)
		t["hips_y"] = bob_a * lerpf(1.0, -1.0, run) * cos(2.0 * TAU * (_phase - beta * 0.5)) - g["drop"]
		t["hips_yaw"] = -0.1 * fl * amp
		t["hips_roll"] = 0.03 * cos(2.0 * TAU * (_phase - beta * 0.5)) * fl * (1.0 - run)
		t["torso_y"] = 0.16 * fl * amp
		var lean_f := lerpf(0.04, 0.2, run) + 0.12 * smoothstep(7.0, 10.0, vm) + clampf(_accel * 0.025, -0.15, 0.25)
		t["torso_x"] = -lean_f
		t["head_x"] = lean_f * 0.6
		t["head_y"] = -t["torso_y"] * 0.85
		var arm_amp := lerpf(0.32, 0.8, run)
		t["arm_l"] = 0.05 - fl * arm_amp
		t["arm_r"] = 0.05 + fl * arm_amp
		t["elbow_l"] = lerpf(0.25, 1.35, run) + maxf(-fl, 0.0) * lerpf(0.15, 0.35, run)
		t["elbow_r"] = lerpf(0.25, 1.35, run) + maxf(fl, 0.0) * lerpf(0.15, 0.35, run)
		t["arm_lz"] = -0.12 - run * 0.08
		t["arm_rz"] = 0.12 + run * 0.08
		t["wrist_l"] = 0.2
		t["wrist_r"] = 0.2
	# Al agacharse, la mano derecha va hasta lo que coge (IK del brazo).
	if reach_target != Vector3.INF and state in ["pickup", "kneel"] and is_inside_tree():
		var w := clampf(_state_t / 0.15, 0.0, 1.0)
		if state == "pickup" and _state_t > 0.3:
			w = 1.0 - clampf((_state_t - 0.3) / 0.15, 0.0, 1.0)
		var arm := _reach_ik(reach_target)
		if not arm.is_empty():
			t["arm_r"] = lerpf(t["arm_r"], arm[0], w)
			t["arm_rz"] = lerpf(t["arm_rz"], arm[1], w)
			t["elbow_r"] = lerpf(t["elbow_r"], arm[2], w)
			t["wrist_r"] = lerpf(t["wrist_r"], 0.35, w)
	# Mirada: cabeza (y algo el cuello) hacia `look_target`.
	_update_look(delta, t)
	_springs(t, delta, rate, damp, ["leg_l", "leg_r", "leg_lz", "leg_rz", "knee_l", "knee_r", "foot_l", "foot_r"])
	# Cadera y piernas.
	var hips_b := Basis.from_euler(Vector3(_x["hips_x"], _x["hips_yaw"], _x["hips_roll"]))
	var hips_p := Vector3(_x["hips_side"], HIP_Y + _x["hips_y"], 0.0)
	var legs := {}
	if state == "climb":
		# Escalando: los pies buscan la pared y se apoyan en ella (rayos hacia delante).
		legs = _climb_legs(hips_p, hips_b)
		if legs.size() == 2:
			use_ik = true
	elif use_ik or _x["ik"] > 0.01:
		_foot_targets(delta, vm, run, g, stance, gait)
		# Bajar la cadera si un pie no llega (cuestas, escalones, zancadas largas).
		var need := 0.0
		for i in 2:
			var hj := hips_p + hips_b * _rest[THIGH_L if i == 0 else THIGH_R]
			var f: Vector3 = _foot_world_to_model(i)
			var dh := Vector2(f.x - hj.x, f.z - hj.z).length()
			var reach := LEG * 0.985
			var vy := sqrt(maxf(reach * reach - dh * dh, 0.0))
			need = maxf(need, (hj.y - f.y) - vy)
		need = clampf(need, 0.0, 0.3)
		_hip_drop = lerpf(_hip_drop, need, clampf(delta * (30.0 if need > _hip_drop else 10.0), 0.0, 1.0))
		hips_p.y -= _hip_drop * _x["ik"]
		for i in 2:
			legs[i] = _solve_leg(i, hips_p, hips_b, _foot_world_to_model(i), vm, run, gait)
	else:
		_hip_drop = lerpf(_hip_drop, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		_plant = [Vector3.INF, Vector3.INF]
	# Las piernas por FK siguen a la IK mientras está activa (salida suave al saltar).
	var lt := {}
	for k in ["leg_l", "leg_r", "leg_lz", "leg_rz", "knee_l", "knee_r", "foot_l", "foot_r"]:
		lt[k] = t[k]
	if use_ik and not legs.is_empty():
		for i in 2:
			var s := "l" if i == 0 else "r"
			var r: Array = legs[i]
			lt["leg_" + s] = r[0]
			lt["leg_" + s + "z"] = r[1]
			lt["knee_" + s] = r[2]
	_springs(lt, delta, rate, damp, [], true)
	var ikw: float = clampf(_x["ik"], 0.0, 1.0)
	# Poses de los huesos.
	skel.set_bone_pose_position(HIPS, hips_p)
	skel.set_bone_pose_rotation(HIPS, hips_b.get_rotation_quaternion())
	var tx: float = _x["torso_x"]
	var ty: float = _x["torso_y"] - _x["hips_yaw"]
	var tz: float = _x["torso_z"]
	skel.set_bone_pose_rotation(SPINE, Quaternion.from_euler(Vector3(tx * 0.45, ty * 0.4, tz * 0.5)))
	skel.set_bone_pose_rotation(CHEST, Quaternion.from_euler(Vector3(tx * 0.55 + breath * 0.01, ty * 0.6, tz * 0.5)))
	var hx: float = _x["head_x"]
	var hy: float = _x["head_y"]
	skel.set_bone_pose_rotation(NECK, Quaternion.from_euler(Vector3(hx * 0.35, hy * 0.35, _x["head_z"] * 0.4)))
	skel.set_bone_pose_rotation(HEAD, Quaternion.from_euler(Vector3(hx * 0.65, hy * 0.65, _x["head_z"] * 0.6)))
	for i in 2:
		var s := "l" if i == 0 else "r"
		var ua := UARM_L if i == 0 else UARM_R
		skel.set_bone_pose_rotation(ua, Quaternion.from_euler(Vector3(_x["arm_" + s], 0.0, _x["arm_" + s + "z"])))
		skel.set_bone_pose_rotation(ua + 1, Quaternion.from_euler(Vector3(_x["elbow_" + s], 0.0, 0.0)))
		skel.set_bone_pose_rotation(ua + 2, Quaternion.from_euler(Vector3(_x["wrist_" + s], 0.0, 0.0)))
		var th := THIGH_L if i == 0 else THIGH_R
		var lx: float = _x["leg_" + s]
		var lz: float = _x["leg_" + s + "z"]
		var kn: float = _x["knee_" + s]
		var fp: float = _x["foot_" + s]
		var foot_q := Quaternion.from_euler(Vector3(fp, 0.0, 0.0))
		if ikw > 0.0 and legs.has(i):
			var r: Array = legs[i]
			lx = lerpf(lx, r[0], ikw)
			lz = lerpf(lz, r[1], ikw)
			kn = lerpf(kn, r[2], ikw)
			foot_q = foot_q.slerp(r[3], ikw)
		var thigh_q := Quaternion(Vector3.BACK, lz) * Quaternion(Vector3.RIGHT, lx)
		skel.set_bone_pose_rotation(th, thigh_q)
		skel.set_bone_pose_rotation(th + 1, Quaternion(Vector3.RIGHT, kn))
		skel.set_bone_pose_rotation(th + 2, foot_q)
	# Voltereta: todo el cuerpo gira hacia delante alrededor de su centro.
	if state == "roll":
		var c := 0.42
		pivot.rotation.x = -TAU * clampf(roll_k, 0.0, 1.0)
		pivot.position = Vector3(0, c, 0)
		skel.position = Vector3(0, -c, 0)
	else:
		pivot.rotation.x = 0.0
		pivot.position = Vector3.ZERO
		skel.position = Vector3.ZERO
	_update_face(delta)
	# Estirar y aplastar con un muelle amortiguado.
	_sq_v += (1.0 - _sq) * 260.0 * delta
	_sq_v *= exp(-14.0 * delta)
	_sq += _sq_v * delta
	var sq := clampf(_sq, 0.75, 1.25)
	pivot.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
	_secondary(delta)


## Integra los muelles de las articulaciones hacia `t` (semi-implícito, en pasos pequeños).
## `skip`: claves que no se tocan ahora. `only`: si es true, solo las de `t`.
func _springs(t: Dictionary, delta: float, rate: float, damp: float, skip: Array, only := false) -> void:
	var steps := int(ceil(delta / (1.0 / 120.0)))
	var h := delta / maxf(steps, 1)
	var w := rate
	var keys: Array = t.keys() if only else POSE_KEYS
	for key in keys:
		if key in skip or not t.has(key):
			continue
		var x: float = _x[key]
		var v: float = _v[key]
		var tg: float = t[key]
		var ww := w * (0.6 if key == "ik" else 1.0)
		for s in steps:
			v += ((tg - x) * ww * ww - 2.0 * damp * ww * v) * h
			x += v * h
		_x[key] = x
		_v[key] = v


## Ciclo de marcha según la velocidad: longitud de la zancada (ciclo completo), fracción de
## apoyo y cuánto baja la cadera. Si la zancada no cabe en el alcance de la pierna, se
## acorta el apoyo (más vuelo al correr) y, si aún no cabe, sube la cadencia.
func _gait_params(vm: float, run: float) -> Dictionary:
	var cycle := clampf(0.48 + vm * 0.26, 0.5, 2.5)
	var beta := lerpf(0.6, 0.34, run)
	var beta_min := lerpf(0.52, 0.22, run)
	var drop := lerpf(0.022, 0.06, run)
	var hy := (HIP_Y - 0.06 - drop) - ANKLE - 0.03
	var reach := sqrt(maxf(pow(LEG * 0.97, 2.0) - hy * hy, 0.0004))
	var s_max := 2.0 * reach
	if cycle * beta > s_max:
		beta = maxf(s_max / cycle, beta_min)
		if cycle * beta > s_max:
			cycle = s_max / beta
	return {"cycle": cycle, "beta": beta, "stride": cycle * beta, "drop": drop}


## Posición del tobillo de cada pie (en el mundo) según la marcha o la postura de parada.
var _feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _foot_pitch: Array[float] = [0.0, 0.0]
var _prev_p: Array[float] = [0.0, 0.5]


func _foot_targets(delta: float, vm: float, run: float, g: Dictionary, stance: Array, gait: bool) -> void:
	var xf := _model_xform()
	var inv := xf.affine_inverse()
	var beta: float = g["beta"]
	var stride: float = g["stride"]
	var lift := lerpf(0.05, 0.1, run) * clampf(vm / 1.2, 0.3, 1.0)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var rest_x := side * 0.09 * _g
		var gait_p := Vector3.ZERO
		var pitch := 0.0
		if _gait_w > 0.0:
			var p := fposmod(_phase + (0.0 if i == 0 else 0.5), 1.0)
			# Empieza el apoyo (la fase da la vuelta): el pie toca el suelo.
			if gait and p < _prev_p[i] and _prev_p[i] - p > 0.5:
				var fx := rest_x * lerpf(1.0, 0.72, run)
				var zc0 := -lerpf(0.01, 0.035, run) - stride * 0.5
				foot_planted.emit(i, xf * Vector3(fx, _ground[i], zc0))
			_prev_p[i] = p
			var x := rest_x * lerpf(1.0, 0.72, run)
			var zc := -lerpf(0.01, 0.035, run)
			var y := 0.0
			var z := 0.0
			if p < beta:
				# Apoyo: el pie va hacia atrás exactamente a la velocidad del cuerpo.
				var s := p / beta
				z = zc - stride * 0.5 + s * stride
				# Talón al principio, despegue de puntera al final.
				pitch = lerpf(0.28, 0.06, run) * (1.0 - smoothstep(0.0, 0.18, s)) - lerpf(0.55, 0.8, run) * smoothstep(0.62, 1.0, s)
			else:
				var s := (p - beta) / (1.0 - beta)
				var e := s * s * (3.0 - 2.0 * s)
				z = zc + stride * 0.5 - e * stride
				y = lift * sin(PI * pow(s, 0.8))
				# Al correr, el talón sube hacia atrás al empezar el vuelo.
				y += run * 0.13 * sin(PI * clampf(s / 0.55, 0.0, 1.0)) * (1.0 - s)
				pitch = lerpf(-lerpf(0.55, 0.8, run), lerpf(0.25, 0.05, run), smoothstep(0.15, 0.9, s))
			# El tobillo sube cuando el pie rueda sobre la puntera o el talón.
			y += maxf(-pitch, 0.0) * 0.085 + maxf(pitch, 0.0) * 0.03
			gait_p = Vector3(x, y, z)
		# Postura de parada: pies plantados en el mundo; si el cuerpo gira o se aleja mucho,
		# se da un pasito hasta su sitio (uno cada vez).
		var want_m := Vector3(rest_x * 1.05, 0.0, stance[i])
		var want_w := xf * want_m
		if _plant[i] == Vector3.INF or gait:
			_plant[i] = xf * Vector3(gait_p.x if _gait_w > 0.0 else want_m.x, 0.0, gait_p.z if _gait_w > 0.0 else want_m.z)
			_step_t[i] = -1.0
		var other := 1 - i
		if not gait and _step_t[i] < 0.0 and _step_t[other] < 0.0:
			var off := Vector2(_plant[i].x - want_w.x, _plant[i].z - want_w.z).length() / maxf(scale.y, 0.01)
			if off > 0.06:
				_step_t[i] = 0.0
				_step_from[i] = _plant[i]
				_step_to[i] = want_w
		var stand_p: Vector3 = inv * Vector3(_plant[i].x, xf.origin.y, _plant[i].z)
		stand_p.y = 0.0
		var step_lift := 0.0
		if _step_t[i] >= 0.0:
			_step_t[i] += delta / 0.2
			var s := clampf(_step_t[i], 0.0, 1.0)
			var e := s * s * (3.0 - 2.0 * s)
			_plant[i] = _step_from[i].lerp(_step_to[i], e)
			stand_p = inv * Vector3(_plant[i].x, xf.origin.y, _plant[i].z)
			stand_p.y = 0.0
			step_lift = 0.06 * sin(PI * s)
			if s >= 1.0:
				_step_t[i] = -1.0
				foot_planted.emit(i, _plant[i])
		var pm := stand_p.lerp(gait_p, _gait_w)
		pm.y = lerpf(step_lift, gait_p.y, _gait_w)
		_foot_pitch[i] = pitch * _gait_w
		# Suelo bajo el pie.
		var wp := xf * Vector3(pm.x, 0.0, pm.z)
		_probe_ground(i, wp, xf)
		pm.y += _ground[i] + ANKLE
		_feet[i] = pm


## Transformación modelo → mundo. Si el dueño se mueve en el paso de física (Lía), la que se
## dibuja es la interpolada; si se mueve en _process (vecinos), la normal.
func _model_xform() -> Transform3D:
	if not is_inside_tree():
		return transform
	if physics_owner:
		return get_global_transform_interpolated()
	return global_transform


func _foot_world_to_model(i: int) -> Vector3:
	return _feet[i]


## Altura del suelo bajo el pie `i` (en el espacio del modelo, relativa a los pies).
func _probe_ground(i: int, wp: Vector3, xf: Transform3D) -> void:
	var gy := 0.0
	var n := Vector3.UP
	if ground_ik and is_inside_tree():
		var sc := maxf(scale.y, 0.01)
		var from := wp + xf.basis.y.normalized() * 0.55 * sc
		var to := wp - xf.basis.y.normalized() * 0.45 * sc
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		q.exclude = ray_exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var hm: Vector3 = xf.affine_inverse() * (hit["position"] as Vector3)
			gy = clampf(hm.y, -0.32, 0.32)
			n = (xf.basis.inverse() * (hit["normal"] as Vector3)).normalized()
			if n.y < 0.55:
				n = Vector3.UP
	_ground[i] = lerpf(_ground[i], gy, 0.5)
	_ground_n[i] = _ground_n[i].lerp(n, 0.3).normalized()


## Pies contra la pared al trepar: cada pie a su altura (suben alternados con el ritmo de la
## escalada) y apoyado en la roca con la suela plana. Devuelve las piernas resueltas por IK
## o {} si alguna no encuentra pared (cornisas, salientes: entonces cuelgan por FK).
func _climb_legs(hips_p: Vector3, hips_b: Basis) -> Dictionary:
	if not is_inside_tree() or not ground_ik:
		return {}
	var xf := _model_xform()
	var inv := xf.affine_inverse()
	var space := get_world_3d().direct_space_state
	var c := sin(_phase * TAU)
	var out := {}
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var y := 0.34 + side * -c * 0.12
		var from := xf * Vector3(side * 0.11 * _g, y, 0.15)
		var to := xf * Vector3(side * 0.11 * _g, y, -1.0)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		q.exclude = ray_exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var n: Vector3 = (xf.basis.inverse() * (hit["normal"] as Vector3)).normalized()
		var foot: Vector3 = inv * (hit["position"] as Vector3) + n * ANKLE * 0.95
		_ground_n[i] = _ground_n[i].lerp(n, 0.4).normalized()
		_foot_pitch[i] = 0.0
		_feet[i] = foot
		out[i] = _solve_leg(i, hips_p, hips_b, foot, 0.0, 0.0, false)
	return out


## Cinemática inversa de una pierna: [ángulo del muslo, apertura, rodilla, rotación del pie].
func _solve_leg(i: int, hips_p: Vector3, hips_b: Basis, foot: Vector3, _vm: float, _run: float, _gait: bool) -> Array:
	var th := THIGH_L if i == 0 else THIGH_R
	var hj := hips_p + hips_b * _rest[th]
	var d := hips_b.inverse() * (foot - hj)
	var phi := atan2(d.x, maxf(-d.y, 0.01))
	var r := sqrt(d.x * d.x + d.y * d.y)
	var dist := clampf(sqrt(r * r + d.z * d.z), 0.08, LEG - 0.0005)
	var line := atan2(-d.z, r)
	var ca := clampf((THIGH * THIGH + dist * dist - SHIN * SHIN) / (2.0 * THIGH * dist), -1.0, 1.0)
	var ck := clampf((THIGH * THIGH + SHIN * SHIN - dist * dist) / (2.0 * THIGH * SHIN), -1.0, 1.0)
	var lx := line + acos(ca)
	var knee := -(PI - acos(ck))
	# Pie: plano sobre el suelo (pendiente) más el balanceo talón-puntera de la marcha.
	var n: Vector3 = _ground_n[i]
	var pitch_g := atan2(n.z, n.y)
	var roll_g := atan2(-n.x, n.y)
	var desired := Basis(Vector3.BACK, roll_g) * Basis(Vector3.RIGHT, pitch_g + _foot_pitch[i])
	var shin_b := hips_b * Basis(Vector3.BACK, phi) * Basis(Vector3.RIGHT, lx) * Basis(Vector3.RIGHT, knee)
	var foot_q := (shin_b.inverse() * desired).get_rotation_quaternion()
	return [lx, phi, knee, foot_q]


## Brazo derecho hacia `target` (mundo): [hombro adelante, apertura, codo] o [] si no hay
## postura. Usa la postura actual de la cadera y el tronco.
func _reach_ik(target: Vector3) -> Array:
	var xf := _model_xform()
	var tm := xf.affine_inverse() * target
	var hips_b := Basis.from_euler(Vector3(_x["hips_x"], _x["hips_yaw"], _x["hips_roll"]))
	var hips_xf := Transform3D(hips_b, Vector3(_x["hips_side"], HIP_Y + _x["hips_y"] - _hip_drop, 0.0))
	var tx: float = _x["torso_x"]
	var ty: float = _x["torso_y"] - _x["hips_yaw"]
	var tz: float = _x["torso_z"]
	var spine_xf := hips_xf * Transform3D(Basis.from_euler(Vector3(tx * 0.45, ty * 0.4, tz * 0.5)), _rest[SPINE])
	var chest_xf := spine_xf * Transform3D(Basis.from_euler(Vector3(tx * 0.55, ty * 0.6, tz * 0.5)), _rest[CHEST])
	var shoulder := chest_xf * _rest[UARM_R]
	var d := chest_xf.basis.inverse() * (tm - shoulder)
	if d.length() < 0.01:
		return []
	var a := UPPER_ARM
	var b := FOREARM + 0.05
	var dist := clampf(d.length(), 0.08, a + b - 0.002)
	var dn := d.normalized()
	var phi := asin(clampf(dn.x, -1.0, 1.0))
	var theta := atan2(-dn.z, -dn.y)
	var alpha := acos(clampf((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0))
	var gamma := acos(clampf((a * a + b * b - dist * dist) / (2.0 * a * b), -1.0, 1.0))
	return [theta - alpha, clampf(phi, -0.3, 1.2), PI - gamma]


## Cabeza y ojos hacia `look_target` (si está a la vista, sin girar más de lo natural).
func _update_look(delta: float, t: Dictionary) -> void:
	var want := Vector2.ZERO
	var look_target := reach_target if reach_target != Vector3.INF else self.look_target
	if look_target != Vector3.INF and is_inside_tree():
		var xf := _model_xform()
		var hp := xf * Vector3(0, 1.35, 0)
		var d := xf.basis.inverse() * (look_target - hp)
		var yaw := atan2(-d.x, -d.z)
		if absf(yaw) < 2.0:
			var pitch := atan2(d.y, Vector2(d.x, d.z).length())
			want = Vector2(clampf(yaw, -1.1, 1.1), clampf(pitch, -0.5, 0.45))
	_look = _look.lerp(want, clampf(delta * 5.0, 0.0, 1.0))
	t["head_y"] += _look.x
	t["head_x"] -= _look.y
	t["torso_y"] += _look.x * 0.2
	for e in eyes:
		var iris := e.get_node_or_null("Iris") as Node3D
		if iris:
			iris.position = Vector3(clampf((want.x - _look.x) * -0.02, -0.01, 0.01), clampf((want.y - _look.y) * 0.02, -0.008, 0.008), 0.0)


## Movimiento secundario: melena/coletas con muelle, mochila que bota, bufanda al viento.
func _secondary(delta: float) -> void:
	var xf := _model_xform()
	var gp := xf.origin
	var vel := (gp - _last_pos) / maxf(delta, 0.001)
	if vel.length() > 30.0:
		vel = Vector3.ZERO
	_last_pos = gp
	var acc := (vel - _prev_vel) / maxf(delta, 0.001)
	_prev_vel = vel
	var local_v := xf.basis.inverse() * vel
	var local_a := xf.basis.inverse() * acc
	if _hair_swing:
		# El pelo se queda atrás al acelerar y rebota al frenar o al botar al correr.
		var target := Vector2(clampf(local_v.z * 0.04 - absf(local_v.y) * 0.02, -0.5, 0.5), clampf(-local_v.x * 0.04, -0.4, 0.4))
		var force := (target - _hair_ang) * 140.0 - _hair_vel * 9.0 + Vector2(clampf(local_a.z * 0.006 + local_a.y * 0.004, -3.0, 3.0), clampf(-local_a.x * 0.006, -3.0, 3.0))
		_hair_vel += force * delta
		_hair_ang += _hair_vel * delta
		_hair_ang = _hair_ang.clamp(Vector2(-0.7, -0.5), Vector2(0.7, 0.5))
		_hair_swing.rotation = Vector3(_hair_ang.x, 0.0, _hair_ang.y)
	if _pack:
		var f := -(local_a.y * 0.0006) - _pack_x * 220.0 - _pack_v * 14.0
		_pack_v += f * delta
		_pack_x += _pack_v * delta
		_pack_x = clampf(_pack_x, -0.03, 0.03)
		_pack.position.y = 0.1 + _pack_x
		_pack.rotation.x = -_pack_x * 3.0
	if _scarf_anchor:
		_scarf_sim(delta, xf, local_v)


## Cola de la bufanda: puntos con integración de Verlet (gravedad, rozamiento del aire y un
## aleteo que crece con la velocidad), tramos de longitud fija y la espalda como obstáculo.
func _scarf_sim(delta: float, xf: Transform3D, local_v: Vector3) -> void:
	var sc := maxf(scale.y, 0.01)
	# El ancla en el espacio del modelo y luego con la transformación que se dibuja.
	var anchor := xf * (global_transform.affine_inverse() * _scarf_anchor.global_position)
	var seg := SCARF_SEG * sc
	var down := -xf.basis.y.normalized()
	var back := xf.basis.z.normalized()
	if _scarf_pts.size() != SCARF_N + 1 or _scarf_pts[0].distance_to(anchor) > 2.0:
		_scarf_pts.clear()
		_scarf_prev.clear()
		for k in SCARF_N + 1:
			var p := anchor + (down * 0.8 + back * 0.6).normalized() * seg * k
			_scarf_pts.append(p)
			_scarf_prev.append(p)
	var steps := clampi(int(ceil(delta / (1.0 / 90.0))), 1, 4)
	var h := delta / steps
	var speed_k := clampf(Vector2(local_v.x, local_v.z).length() / 8.0, 0.0, 1.0)
	var inv := xf.affine_inverse()
	for s in steps:
		_scarf_pts[0] = anchor
		_scarf_prev[0] = anchor
		for k in range(1, SCARF_N + 1):
			var p := _scarf_pts[k]
			var vel := (p - _scarf_prev[k]) * pow(0.9, h * 60.0)
			_scarf_prev[k] = p
			var flap := xf.basis.x.normalized() * sin(_t * (8.0 + speed_k * 9.0) + k * 1.3) * (0.3 + speed_k * 1.4) * k
			flap += xf.basis.y.normalized() * cos(_t * 10.0 + k * 0.9) * speed_k * 1.2 * k
			_scarf_pts[k] = p + vel + (Vector3(0, -9.8, 0) + flap) * h * h
		for it in 3:
			for k in range(1, SCARF_N + 1):
				var a := _scarf_pts[k - 1]
				var d := _scarf_pts[k] - a
				var l := d.length()
				if l > 0.0001:
					_scarf_pts[k] = a + d / l * seg
				# El cuerpo (y la mochila) como cápsulas: la bufanda no los atraviesa.
				var m: Vector3 = inv * _scarf_pts[k]
				var moved := false
				for c in _scarf_colliders:
					var a0: Vector3 = c[0]
					var a1: Vector3 = c[1]
					var rad: float = c[2]
					var ab := a1 - a0
					var tq := clampf((m - a0).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					var q := a0 + ab * tq
					var off := m - q
					if off.length() < rad:
						m = q + (off.normalized() if off.length() > 0.0001 else Vector3.BACK) * rad
						moved = true
				if moved:
					_scarf_pts[k] = xf * m
					# Rozamiento con la ropa: pierde casi toda la velocidad al tocar.
					_scarf_prev[k] = _scarf_prev[k].lerp(_scarf_pts[k], 0.6)
	for k in SCARF_N:
		var a := _scarf_pts[k]
		var b := _scarf_pts[k + 1]
		var dir := b - a
		if dir.length() < 0.0001:
			continue
		var z := dir.normalized()
		var up := back.cross(xf.basis.x.normalized())
		var x := up.cross(z).normalized()
		if x.length() < 0.01:
			x = xf.basis.x.normalized()
		var y := z.cross(x).normalized()
		_scarf_segs[k].global_transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * sc), (a + b) * 0.5)


func _update_face(delta: float) -> void:
	# Parpadeo (a veces doble).
	_blink -= delta
	var eye_s := 1.0
	if _blink < 0.0:
		eye_s = 0.12
		if _blink < -0.11:
			_blink = randf_range(0.25, 0.4) if randf() < 0.18 else randf_range(2.0, 5.0)
	for e in eyes:
		e.scale.y = lerpf(e.scale.y, eye_s, clampf(delta * 40.0, 0.0, 1.0))
	if mouth_smile == null:
		return
	var m := mood
	if m == "":
		match state:
			"jump", "fall", "glide", "hold_up", "cheer":
				m = "surprised"
			"talk":
				m = "talk" if speaking or not _dialog_driven else "happy"
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
			# La boca se mueve con sílabas de duración irregular.
			var syl := sin(_t * 17.0) + sin(_t * 23.0 + 1.3) * 0.6
			open = syl > 0.2
		"effort":
			brow_y = 0.352
	mouth_open.visible = open
	mouth_smile.visible = not open
	for b in brows:
		b.position.y = lerpf(b.position.y, brow_y, 0.3)
