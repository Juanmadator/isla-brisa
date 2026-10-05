class_name Npc
extends Node3D
## Vecino de la isla: modelo, nombre flotante, aviso "!" cuando tiene algo que decir,
## y gira la cabeza (y el cuerpo) hacia Lía cuando se acerca. Algunos pasean por su zona
## durante el día (`wander_radius` > 0) y de noche vuelven a su sitio.

var id := ""
var display_name := ""
var avatar: Avatar
var base_yaw := 0.0
var talking := false
var has_news := false:
	set(v):
		has_news = v
		if _mark:
			_mark.visible = v
var player: Node3D
var island: Island
## Cámara de juego: los nombres y avisos solo se ven con ella (no en escenas ni en el tráiler).
static var game_cam: Camera3D
## Zona de paseo: centro (su sitio de siempre) y radio; 0 = no se mueve.
var home := Vector3.ZERO
var wander_radius := 0.0
## Puntos que evitar al pasear (casas): [centro, radio].
var blockers: Array = []
## De noche (lo pone Gameplay): vuelve a casa y se queda quieto.
var night := false
const WALK_SPEED := 1.3
var _goal := Vector3.ZERO
var _pause := 2.0

var _label: Label3D
var _mark: Label3D
var _t := 0.0
var _waved := false
var _wave_t := 0.0


func setup(npc_id: String, data: Dictionary) -> void:
	id = npc_id
	display_name = data["name"]
	avatar = Avatar.new()
	add_child(avatar)
	avatar.build(data["spec"])
	var h := 1.75 * float(data["spec"].get("height", 1.0))
	_label = Label3D.new()
	_label.text = display_name
	_label.font = load("res://assets/fonts/Fredoka.ttf")
	_label.font_size = 44
	_label.pixel_size = 0.0075
	_label.outline_size = 14
	_label.modulate = Color(1, 1, 1)
	_label.outline_modulate = Color(0.1, 0.16, 0.24)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.position = Vector3(0, h + 0.35, 0)
	_label.visible = false
	add_child(_label)
	_mark = Label3D.new()
	_mark.text = "!"
	_mark.font = load("res://assets/fonts/Fredoka.ttf")
	_mark.font_size = 120
	_mark.pixel_size = 0.005
	_mark.outline_size = 22
	_mark.modulate = Color(1.0, 0.82, 0.3)
	_mark.outline_modulate = Color(0.35, 0.2, 0.05)
	_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mark.position = Vector3(0, h + 0.8, 0)
	_mark.visible = false
	add_child(_mark)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = h
	cs.shape = cap
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	add_child(body)


func _process(delta: float) -> void:
	_t += delta
	var in_game := game_cam != null and get_viewport().get_camera_3d() == game_cam
	_mark.visible = has_news and in_game
	if _mark.visible:
		_mark.position.y = _label.position.y + 0.45 + sin(_t * 3.0) * 0.08
	if player == null:
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	_label.visible = dist < 9.0 and not talking and in_game and dist > 2.5
	var yaw := base_yaw
	var walking := false
	if wander_radius > 0.0 and not talking and dist > 4.0:
		walking = _wander(delta)
		if walking:
			var mv := _goal - position
			yaw = atan2(-mv.x, -mv.z)
	if (dist < 6.0 and not walking) or talking:
		yaw = atan2(-to.x, -to.z)
	avatar.rotation.y = rotate_toward(avatar.rotation.y, yaw, (6.0 if walking else 4.0) * delta)
	avatar.speed = WALK_SPEED if walking else 0.0
	if walking:
		avatar.state = "walk"
	elif talking:
		avatar.state = "talk"
	elif _wave_t > 0.0:
		_wave_t -= delta
		avatar.state = "wave"
	else:
		avatar.state = "idle"
	if dist < 7.0 and not _waved and not walking:
		_waved = true
		_wave_t = 1.6
	elif dist > 14.0:
		_waved = false


## Pasea hacia un punto de su zona, se para un rato y elige otro. Devuelve si está andando.
func _wander(delta: float) -> bool:
	if _goal == Vector3.ZERO:
		_goal = home
	if night:
		_goal = home
		_pause = 0.0
	var mv := _goal - position
	mv.y = 0.0
	if mv.length() < 0.25:
		if night:
			return false
		_pause -= delta
		if _pause <= 0.0:
			_pause = randf_range(4.0, 12.0)
			_goal = _pick_goal()
		return false
	var step := mv.normalized() * minf(WALK_SPEED * delta, mv.length())
	var next := position + step
	if island:
		next.y = island.height_at(next.x, next.z)
	position = next
	return true


func _pick_goal() -> Vector3:
	for i in 12:
		var a := randf() * TAU
		var r := sqrt(randf()) * wander_radius
		var p := home + Vector3(cos(a) * r, 0, sin(a) * r)
		if island == null:
			return p
		if island.normal_at(p.x, p.z).y < 0.88 or island.height_at(p.x, p.z) < island.water_level(p.x, p.z) + 0.4:
			continue
		var ok := true
		for b in blockers:
			var c: Vector3 = b[0]
			if Vector2(p.x - c.x, p.z - c.z).length() < float(b[1]):
				ok = false
				break
		# Que el camino recto tampoco atraviese una casa.
		for b in blockers:
			var c: Vector3 = b[0]
			var mid := (position + p) * 0.5
			if Vector2(mid.x - c.x, mid.z - c.z).length() < float(b[1]):
				ok = false
				break
		if ok:
			p.y = island.height_at(p.x, p.z)
			return p
	return home
