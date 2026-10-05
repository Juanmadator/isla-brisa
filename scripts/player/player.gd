class_name Player
extends CharacterBody3D
## Lía: correr, esprintar, saltar, escalar paredes empinadas con gancho y cuerda, planear con
## la paravela, nadar y encaramarse a los bordes. La resistencia (aguante) limita escalar,
## esprintar, planear y nadar.

signal jumped
signal landed(heavy: bool)
signal splashed
signal exhausted_in_water
signal glide_started
signal glide_ended
signal step(biome: int)
signal stamina_empty
signal climb_grab

const WALK := 3.2
const RUN := 6.6
const SPRINT := 10.2
const GRAVITY := 24.0
const JUMP_V := 8.2
const CLIMB_SPEED := 2.4
const GLIDE_SPEED := 10.0
const GLIDE_SINK := 2.1
const SWIM_SPEED := 3.3
const SWIM_SPRINT := 5.6
const RADIUS := 0.32
const HEIGHT := 1.5

const DRAIN_SPRINT := 0.26
const DRAIN_CLIMB := 0.15
const DRAIN_CLIMB_IDLE := 0.03
const DRAIN_GLIDE := 0.055
const DRAIN_SWIM := 0.045
const DRAIN_SWIM_SPRINT := 0.33
const LEAP_COST := 0.3
## Tiempo que tarda en lanzar el gancho antes de empezar a trepar.
const HOOK_THROW := 0.3
## Altura máxima a la que llega el gancho; en paredes más altas se clava en la roca.
const HOOK_REACH := 12.0
const BIKE_SPEED := 12.5
const BOAT_SPEED := 9.0
const BOAT_SPRINT := 13.5
const REGEN := 0.95

var state := "ground"
var island: Island
var cam_yaw := 0.0
var avatar: Avatar
var has_glider := false
var locked := false
var stamina := 3.0
var stamina_max := 3.0
var exhausted := false
var updrafts: Array = []   # [Vector3 base, radio, alto]
var facing := 0.0
var last_safe := Vector3.ZERO
var in_updraft := false
var debug_infinite_stamina := false
## Pose fija mientras dura una escena (p. ej. "hold_up"); vacía = animación normal.
var anim_override := ""
var _trails: Array[Ribbon] = []

## Entrada simulada para pruebas automáticas: {move: Vector2, jump, sprint, drop}
var autopilot = null

var _move := Vector2.ZERO
var _jump_pressed := false
var _jump_held := false
var _sprint := false
var _drop := false
var _coyote := 0.0
var _jump_buffer := 0.0
var _climb_intent := 0.0
var _regen_delay := 0.0
var _land_lock := 0.0
var _fall_peak := 0.0
var _safe_timer := 0.0
var _step_timer := 0.0
var _leap := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_t := 0.0
var _no_climb := 0.0
var _no_glide := 0.0
var wall_normal := Vector3.BACK
var climb_move := Vector2.ZERO
var gear: ClimbGear
var _hook_t := 0.0
## Vehículos: bici (modifica el movimiento a pie) y barca (estado "boat").
var has_bike := false
var on_bike := false
var bike_model: Node3D
var boat: Node3D
var boat_speed := 0.0
var _bike_phase := 0.0
var _boat_t := 0.0
signal vehicle_changed
## Acción breve en el suelo ("pickup", "kneel"...): la pose del avatar y Lía se queda quieta.
var _action := ""
var _action_t := 0.0
var _roll_t := 0.0
var _lean := 0.0
var _prev_facing := 0.0


func _ready() -> void:
	floor_max_angle = deg_to_rad(47.0)
	floor_snap_length = 0.45
	floor_stop_on_slope = true
	floor_constant_speed = true
	max_slides = 5
	safe_margin = 0.02
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, HEIGHT * 0.5, 0)
	add_child(cs)
	avatar = Avatar.new()
	add_child(avatar)
	avatar.build({"backpack": true, "hair_style": "bob"})
	gear = ClimbGear.new()
	gear.name = "ClimbGear"
	add_child(gear)
	last_safe = global_position
	for i in 2:
		var r := Ribbon.new()
		r.width = 0.07
		r.max_points = 22
		r.color = Color(1, 1, 1, 0.7)
		add_child(r)
		_trails.append(r)


## Aspecto de Lía: `look` lleva los campos del Avatar que cambian (bufanda, sombrero, ropa).
func set_avatar_look(look: Dictionary, glider_a: Color, glider_b: Color) -> void:
	var spec := {"backpack": true, "hair_style": "bob"}
	spec.merge(look, true)
	avatar.build(spec)
	avatar.set_glider_colors(glider_a, glider_b)


# --- Entrada ------------------------------------------------------------------------------

func _read_input() -> void:
	if autopilot != null:
		_move = autopilot.get("move", Vector2.ZERO)
		var j: bool = autopilot.get("jump", false)
		_jump_pressed = j and not _jump_held
		_jump_held = j
		_sprint = autopilot.get("sprint", false)
		_drop = autopilot.get("drop", false)
		return
	if locked:
		_move = Vector2.ZERO
		_jump_pressed = false
		_jump_held = false
		_sprint = false
		_drop = false
		return
	_move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_jump_pressed = Input.is_action_just_pressed("jump")
	_jump_held = Input.is_action_pressed("jump")
	_sprint = Input.is_action_pressed("sprint")
	_drop = Input.is_action_just_pressed("drop")


## Dirección de movimiento en el mundo según la cámara.
func _move_dir() -> Vector3:
	if _move.length() < 0.05:
		return Vector3.ZERO
	var b := Basis(Vector3.UP, cam_yaw)
	var d := b * Vector3(_move.x, 0, _move.y)
	return d.limit_length(1.0)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func water_surface() -> float:
	return island.water_level(global_position.x, global_position.z) if island else -1000.0


# --- Bucle ----------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_read_input()
	if _jump_pressed:
		_jump_buffer = 0.14
	_jump_buffer = maxf(_jump_buffer - dt, 0.0)
	_no_climb = maxf(_no_climb - dt, 0.0)
	_no_glide = maxf(_no_glide - dt, 0.0)
	in_updraft = _check_updraft()
	match state:
		"ground":
			_ground(dt)
		"air":
			_air(dt)
		"glide":
			_glide(dt)
		"climb":
			_climb(dt)
		"mantle":
			_mantle(dt)
		"swim":
			_swim(dt)
		"sit":
			_sit(dt)
		"boat":
			_boat(dt)
	_stamina(dt)
	_animate(dt)
	if global_position.y < -40.0:
		respawn(last_safe)


func _set_state(s: String) -> void:
	if s == state:
		return
	var old := state
	state = s
	if old == "climb" and gear:
		gear.release()
	if old == "glide":
		glide_ended.emit()
	if s == "glide":
		glide_started.emit()
	if s == "air":
		_fall_peak = global_position.y


func _horizontal(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _approach(target: Vector3, accel: float, dt: float) -> void:
	var h := _horizontal(velocity)
	h = h.move_toward(target, accel * dt)
	velocity.x = h.x
	velocity.z = h.z


func can_use_stamina() -> bool:
	return not exhausted and stamina > 0.0


func _ground(dt: float) -> void:
	var dir := _move_dir()
	var mag := _move.length()
	var target_speed := RUN * clampf(mag * 1.15, 0.0, 1.0)
	var sprinting := _sprint and mag > 0.3 and can_use_stamina() and not on_bike
	if on_bike:
		target_speed = BIKE_SPEED * clampf(mag * 1.15, 0.0, 1.0)
	if sprinting:
		target_speed = SPRINT
		_drain(DRAIN_SPRINT * dt)
	if exhausted:
		target_speed = minf(target_speed, WALK)
	if _land_lock > 0.0:
		_land_lock -= dt
		target_speed *= 0.3
	if _action_t > 0.0:
		_action_t -= dt
		target_speed = 0.0
	if _roll_t > 0.0:
		# Voltereta: conserva el impulso hacia delante.
		_roll_t -= dt
		target_speed = maxf(target_speed, RUN * 0.9)
		dir = Vector3(-sin(facing), 0, -cos(facing))
	_approach(dir * target_speed, 55.0 if dir != Vector3.ZERO else 40.0, dt)
	velocity.y -= GRAVITY * dt
	if _jump_buffer > 0.0 and _coyote > 0.0 and _land_lock <= 0.0:
		_jump()
		return
	move_and_slide()
	if is_on_floor():
		_coyote = 0.12
		velocity.y = minf(velocity.y, 0.0)
		_safe_timer -= dt
		if _safe_timer <= 0.0:
			_safe_timer = 0.5
			var n := get_floor_normal()
			if n.y > 0.8 and global_position.y > water_surface() + 0.3:
				last_safe = global_position
	else:
		_coyote -= dt
		if _coyote <= 0.0:
			_set_state("air")
			return
	# Pasos
	var hs := _horizontal(velocity).length()
	if hs > 0.8 and is_on_floor():
		_step_timer -= dt * hs
		if _step_timer <= 0.0:
			_step_timer = 2.2
			step.emit(island.biome_at(global_position.x, global_position.z) if island else 2)
	if _check_water():
		return
	# Escalar (hay que empujar contra la pared un momento) o encaramarse a algo bajo.
	if dir != Vector3.ZERO and is_on_wall() and not on_bike:
		_climb_intent += dt
		if _climb_intent > 0.12:
			_try_climb(dir, true)
	else:
		_climb_intent = 0.0


func _jump() -> void:
	avatar.squash(0.55)
	velocity.y = JUMP_V
	_jump_buffer = 0.0
	_coyote = 0.0
	_set_state("air")
	jumped.emit()
	move_and_slide()


func _air(dt: float) -> void:
	var dir := _move_dir()
	var hs := _horizontal(velocity).length()
	var max_s := maxf(hs, RUN)
	_approach(dir * max_s, 16.0 if dir != Vector3.ZERO else 3.0, dt)
	var g := GRAVITY * (1.3 if velocity.y < 0.0 else 1.0)
	if not _jump_held and velocity.y > 2.0:
		g *= 1.8
	velocity.y = maxf(velocity.y - g * dt, -42.0)
	_fall_peak = maxf(_fall_peak, global_position.y)
	if _jump_pressed and has_glider and can_use_stamina() and _no_glide <= 0.0 and velocity.y < 3.0 and _height_above_ground() > 1.6:
		if on_bike:
			set_bike(false)
		_set_state("glide")
		facing = atan2(-velocity.x, -velocity.z) if hs > 1.0 else facing
		velocity.y = maxf(velocity.y, -3.0)
		return
	move_and_slide()
	if is_on_floor():
		var drop := _fall_peak - global_position.y
		var heavy := drop > 9.0
		landed.emit(heavy)
		if heavy and hs > 3.5 and dir != Vector3.ZERO:
			_roll_t = 0.55
		elif heavy:
			_land_lock = 0.3
		_set_state("ground")
		_coyote = 0.12
		return
	if _check_water():
		return
	if dir != Vector3.ZERO and _no_climb <= 0.0 and not on_bike:
		_try_climb(dir, false)


# --- Vehículos ---------------------------------------------------------------------------

## Sube o baja de la bici (solo a pie y en el suelo para subir).
func set_bike(on: bool) -> void:
	if on == on_bike:
		return
	if on and (not has_bike or state != "ground"):
		return
	on_bike = on
	if on and bike_model == null:
		bike_model = Props.bicycle()
		bike_model.top_level = true
		add_child(bike_model)
	if bike_model:
		bike_model.visible = on
	avatar.position.y = 0.33 if on else 0.0
	vehicle_changed.emit()


## Se sube a la barca `b` (un nodo del mundo que mira hacia -Z).
func board(b: Node3D) -> void:
	if on_bike:
		set_bike(false)
	boat = b
	boat_speed = 0.0
	facing = b.rotation.y
	global_position = b.global_transform * Props.BOAT_SEAT
	velocity = Vector3.ZERO
	_set_state("boat")
	reset_physics_interpolation()
	vehicle_changed.emit()


## Busca dónde bajarse de la barca: tierra firme o el muelle a menos de 5 m.
func landing_spot() -> Vector3:
	var surf := water_surface()
	var best := Vector3.INF
	var best_d := INF
	for r: float in [1.8, 2.8, 3.8, 4.8]:
		for k in 16:
			var a := TAU * k / 16.0
			var p := global_position + Vector3(sin(a), 0, cos(a)) * r
			var hit := _ray(p + Vector3.UP * 4.0, p + Vector3.DOWN * 3.0)
			if hit.is_empty() or hit["normal"].y < 0.6:
				continue
			var hp: Vector3 = hit["position"]
			if hp.y < surf + 0.25:
				continue
			if not _ray(hp + Vector3(0, 0.1, 0), hp + Vector3(0, HEIGHT, 0)).is_empty():
				continue
			if r < best_d:
				best_d = r
				best = hp
	return best


## Baja de la barca a `spot` (la barca se queda amarrada donde está).
func leave_boat(spot: Vector3) -> void:
	boat_speed = 0.0
	boat = null
	teleport(spot + Vector3(0, 0.1, 0), facing)
	_set_state("ground")
	vehicle_changed.emit()


func _boat(dt: float) -> void:
	_boat_t += dt
	var surf := water_surface()
	var throttle := -_move.y
	var steer := _move.x
	var top := BOAT_SPRINT if _sprint else BOAT_SPEED
	var want := throttle * top * (1.0 if throttle >= 0.0 else 0.35)
	boat_speed = move_toward(boat_speed, want, dt * (3.2 if absf(throttle) > 0.05 else 1.4))
	var turn := steer * dt * lerpf(0.5, 1.3, clampf(absf(boat_speed) / 4.0, 0.0, 1.0))
	facing -= turn * (1.0 if boat_speed >= -0.2 else -1.0)
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	# Encallar: delante (o detrás, marcha atrás) hay poca agua.
	var probe := global_position + fwd * (2.7 if boat_speed >= 0.0 else -2.4)
	if island and island.height_at(probe.x, probe.z) > surf - 0.45:
		boat_speed = 0.0
	var bob := sin(_boat_t * 1.6) * 0.06 + sin(_boat_t * 2.3 + 1.0) * 0.03
	velocity = fwd * boat_speed
	velocity.y = (surf + 0.02 + bob - global_position.y) * 6.0
	move_and_slide()
	if is_on_wall():
		boat_speed *= 0.4
	if boat:
		var basis := Basis.from_euler(Vector3(sin(_boat_t * 1.3) * 0.03 - boat_speed * 0.004, facing, -steer * clampf(boat_speed / 8.0, -1.0, 1.0) * 0.12 + sin(_boat_t * 1.7) * 0.025))
		boat.global_transform = Transform3D(basis, global_position - basis * Props.BOAT_SEAT)
		var boom := boat.find_child("Boom", true, false) as Node3D
		if boom:
			boom.rotation.y = lerpf(boom.rotation.y, -steer * 0.5 + sin(_boat_t * 0.7) * 0.08, dt * 2.0)


## Acción breve en el suelo: Lía se para y hace el gesto (y mira a `look_at` si se indica).
func play_action(action: String, secs: float, look_at := Vector3.INF) -> void:
	if state != "ground":
		return
	_action = action
	_action_t = secs
	if look_at != Vector3.INF:
		var to := look_at - global_position
		if Vector2(to.x, to.z).length() > 0.1:
			facing = atan2(-to.x, -to.z)


## Sentarse en un banco: Lía se coloca en `pos` mirando a `yaw` hasta que se mueva.
func sit_at(pos: Vector3, yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	facing = yaw
	_set_state("sit")
	reset_physics_interpolation()


func _sit(_dt: float) -> void:
	velocity = Vector3.ZERO
	if _move.length() > 0.3 or _jump_pressed:
		_set_state("ground")


func _height_above_ground() -> float:
	var hit := _ray(global_position + Vector3.UP * 0.2, global_position + Vector3.DOWN * 30.0)
	var gy: float = hit["position"].y if hit else -100.0
	return minf(global_position.y - gy, global_position.y - water_surface())


func _check_updraft() -> bool:
	var p := global_position
	for u in updrafts:
		var base: Vector3 = u[0]
		if Vector2(p.x - base.x, p.z - base.z).length() < u[1] and p.y > base.y - 2.0 and p.y < base.y + u[2] + 8.0:
			return true
	return false


func _glide(dt: float) -> void:
	var dir := _move_dir()
	if dir != Vector3.ZERO:
		var want := atan2(-dir.x, -dir.z)
		facing = rotate_toward(facing, want, 2.8 * dt)
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var spd := GLIDE_SPEED if dir != Vector3.ZERO else GLIDE_SPEED * 0.65
	_approach(fwd * spd, 9.0, dt)
	if in_updraft:
		velocity.y = move_toward(velocity.y, 11.0, 34.0 * dt)
	else:
		velocity.y = move_toward(velocity.y, -GLIDE_SINK, 14.0 * dt)
	_drain(DRAIN_GLIDE * dt)
	if not can_use_stamina() or _jump_pressed or _drop:
		_set_state("air")
		_no_glide = 0.3
		return
	move_and_slide()
	if is_on_floor():
		landed.emit(false)
		_set_state("ground")
		return
	if _check_water():
		return
	if is_on_wall() and dir != Vector3.ZERO:
		_try_climb(dir, false)


func _check_water() -> bool:
	var surf := water_surface()
	if surf - global_position.y > 1.05:
		if on_bike:
			set_bike(false)
		if state != "swim":
			splashed.emit()
			velocity.y *= 0.2
		_set_state("swim")
		return true
	return false


# --- Escalada -----------------------------------------------------------------------------

func _try_climb(dir: Vector3, from_ground: bool) -> bool:
	if exhausted or stamina <= 0.0:
		return false
	var chest := global_position + Vector3(0, 1.0, 0)
	var hit := _ray(chest, chest + dir.normalized() * (RADIUS + 0.75))
	if hit.is_empty():
		# ¿Pared baja a la altura de los pies/rodillas? Encaramarse.
		if from_ground:
			var knee := global_position + Vector3(0, 0.45, 0)
			var low := _ray(knee, knee + dir.normalized() * (RADIUS + 0.6))
			if not low.is_empty() and low["normal"].y < 0.6:
				return _start_mantle(low["normal"])
		return false
	var n: Vector3 = hit["normal"]
	if n.y > 0.64 or n.y < -0.4:
		return false
	var nh := _horizontal(n).normalized()
	if dir.normalized().dot(-nh) < 0.45:
		return false
	# Si a la altura de la cabeza no hay pared, es un escalón: encaramarse.
	var headp := global_position + Vector3(0, 1.75, 0)
	if from_ground and _ray(headp, headp + dir.normalized() * (RADIUS + 0.8)).is_empty():
		return _start_mantle(n)
	wall_normal = n
	_set_state("climb")
	velocity = Vector3.ZERO
	_leap = 0.0
	_hook_t = HOOK_THROW
	gear.throw_to(avatar.hand_position(1), _find_anchor(), _horizontal(n).normalized())
	climb_grab.emit()
	return true


## Punto donde se engancha la cuerda: sube palpando la pared metro a metro; si se acaba,
## el gancho cae sobre el borde; si sigue más allá de HOOK_REACH, se clava en la roca.
func _find_anchor() -> Vector3:
	var n := _horizontal(wall_normal).normalized()
	if n == Vector3.ZERO:
		n = Vector3.BACK
	var last := global_position + Vector3(0, 1.0, 0) - n * RADIUS
	for i in int(HOOK_REACH):
		var probe := last + Vector3.UP * 1.0 + n * 0.9
		var hit := _ray(probe, probe - n * 3.2)
		if hit.is_empty():
			var over := last + Vector3.UP * 1.6 - n * 0.6
			var top := _ray(over, over + Vector3.DOWN * 2.6)
			if not top.is_empty():
				return top["position"] + Vector3.UP * 0.05
			return last + Vector3.UP * 0.6
		last = hit["position"]
		if hit["normal"].y > 0.7:
			return last
	return last + n * 0.05


func _climb_axes() -> Array:
	var n := wall_normal
	var up := (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
	var right := up.cross(n).normalized()
	return [up, right]


func _climb(dt: float) -> void:
	var axes := _climb_axes()
	var up: Vector3 = axes[0]
	var right: Vector3 = axes[1]
	climb_move = Vector2(_move.x, -_move.y)
	if climb_move.length() > 1.0:
		climb_move = climb_move.normalized()
	if _hook_t > 0.0:
		# Lanzando el gancho: aún no trepa.
		_hook_t -= dt
		climb_move = Vector2.ZERO
	var moving := climb_move.length() > 0.1
	if _drop:
		_let_go(wall_normal * 2.0)
		return
	if _jump_pressed and _hook_t <= 0.0:
		if climb_move.y < -0.5:
			# Saltar hacia atrás, separándose de la pared.
			_let_go(wall_normal * 6.0 + Vector3.UP * 5.0)
			facing = atan2(-wall_normal.x, -wall_normal.z) + PI
			return
		if stamina > 0.05:
			_leap = 0.32
			_drain(LEAP_COST)
	var v: Vector3
	if _leap > 0.0:
		_leap -= dt
		v = (up * 1.0 + right * climb_move.x * 0.4) * 7.0
	else:
		var spd := CLIMB_SPEED
		v = (up * climb_move.y + right * climb_move.x) * spd
		_drain((DRAIN_CLIMB if moving else DRAIN_CLIMB_IDLE) * dt)
	velocity = v - wall_normal * 1.2
	move_and_slide()
	# Un alero o saliente encima: intentar encaramarse por encima de él.
	if is_on_ceiling() and climb_move.y > 0.1:
		if _start_mantle(wall_normal, false):
			return
	if not can_use_stamina():
		stamina_empty.emit()
		_let_go(wall_normal * 1.0)
		return
	# Volver a palpar la pared a la altura del pecho.
	var chest := global_position + Vector3(0, 1.0, 0)
	var hit := _ray(chest + wall_normal * 0.3, chest - wall_normal * (RADIUS + 1.0))
	if hit.is_empty():
		var feet := global_position + Vector3(0, 0.3, 0)
		var low := _ray(feet + wall_normal * 0.3, feet - wall_normal * (RADIUS + 1.0))
		if low.is_empty():
			# Ya no hay pared: estamos por encima del borde. Caer hacia dentro.
			_let_go(-_horizontal(wall_normal) * 1.5 + Vector3.UP * 2.0)
		elif climb_move.y > 0.1 or _leap > 0.0:
			# En el borde: encaramarse si hay suelo firme; si no (borde roto), seguir subiendo.
			_start_mantle(wall_normal, false)
		return
	var n: Vector3 = hit["normal"]
	if n.y > 0.7:
		# La superficie ya es transitable: subir a ella.
		if climb_move.y >= 0.0:
			_start_mantle(wall_normal)
		else:
			_set_state("ground")
		return
	if n.y < -0.45:
		_let_go(wall_normal)
		return
	wall_normal = wall_normal.slerp(n, clampf(10.0 * dt, 0.0, 1.0)).normalized()
	# Mantener la distancia a la pared.
	var want: Vector3 = hit["position"] + wall_normal * (RADIUS + 0.08)
	var off := want - (global_position + Vector3(0, 1.0, 0))
	off = wall_normal * off.dot(wall_normal)
	global_position += off * clampf(12.0 * dt, 0.0, 1.0)
	_update_hook()
	if is_on_floor() and climb_move.y < -0.1:
		_set_state("ground")


## Relanza el gancho si Lía ha subido hasta él o se ha desplazado mucho de lado.
func _update_hook() -> void:
	if not gear.is_set():
		return
	var hands_y := global_position.y + 1.75
	var n := _horizontal(wall_normal).normalized()
	var lat := _horizontal(gear.anchor - global_position)
	lat -= n * lat.dot(n)
	if gear.anchor.y - hands_y < 0.6 or lat.length() > 2.4:
		var a := _find_anchor()
		if a.y > hands_y + 0.8 and a.distance_to(gear.anchor) > 0.8:
			gear.throw_to(avatar.hand_position(1), a, n)


func _let_go(push: Vector3) -> void:
	velocity = push
	_no_climb = 0.35
	_set_state("air")


func _start_mantle(n: Vector3, let_go_on_fail := true) -> bool:
	var nh := _horizontal(n).normalized()
	if nh == Vector3.ZERO:
		return false
	# Buscar suelo firme pasado el borde (los bordes del terreno son redondeados).
	var top := Vector3.ZERO
	var found := false
	for reach: float in [0.55, 0.95, 1.4, 1.9, 2.5]:
		var probe := global_position + Vector3(0, 2.9, 0) - nh * (RADIUS + reach)
		var hit := _ray(probe, probe + Vector3.DOWN * 3.6)
		if hit.is_empty() or hit["normal"].y < 0.5:
			continue
		var cand: Vector3 = hit["position"]
		if cand.y - global_position.y > 2.7 or cand.y < global_position.y - 0.5:
			continue
		# ¿Hay sitio para estar de pie?
		if not _ray(cand + Vector3(0, 0.1, 0), cand + Vector3(0, HEIGHT, 0)).is_empty():
			continue
		top = cand
		found = true
		break
	if not found:
		if state == "climb" and let_go_on_fail:
			_let_go(n * 0.5)
		return false
	_mantle_from = global_position
	_mantle_to = top + Vector3(0, 0.05, 0)
	_mantle_t = 0.0
	velocity = Vector3.ZERO
	facing = atan2(nh.x, nh.z)
	_set_state("mantle")
	return true


func _mantle(dt: float) -> void:
	_mantle_t += dt / 0.38
	var t := clampf(_mantle_t, 0.0, 1.0)
	var up_t := clampf(t * 1.6, 0.0, 1.0)
	var fw_t := clampf((t - 0.35) / 0.65, 0.0, 1.0)
	var p := _mantle_from
	p.y = lerpf(_mantle_from.y, _mantle_to.y + 0.1, up_t)
	p.x = lerpf(_mantle_from.x, _mantle_to.x, fw_t)
	p.z = lerpf(_mantle_from.z, _mantle_to.z, fw_t)
	global_position = p
	if t >= 1.0:
		velocity = Vector3.ZERO
		_set_state("ground")
		_coyote = 0.12
		move_and_slide()


# --- Nado -------------------------------------------------------------------------------------

func _swim(dt: float) -> void:
	var surf := water_surface()
	var dir := _move_dir()
	var sprinting := _sprint and dir != Vector3.ZERO and can_use_stamina()
	var spd := SWIM_SPRINT if sprinting else SWIM_SPEED
	if exhausted:
		spd = SWIM_SPEED * 0.5
	_drain((DRAIN_SWIM_SPRINT if sprinting else DRAIN_SWIM) * dt)
	_approach(dir * spd, 10.0, dt)
	var target_y := surf - 1.12
	velocity.y = (target_y - global_position.y) * 5.0
	move_and_slide()
	var ground := island.height_at(global_position.x, global_position.z) if island else -100.0
	if ground > surf - 0.95 or (is_on_floor() and surf - global_position.y < 0.9):
		_set_state("ground")
		return
	if stamina <= 0.0 and not debug_infinite_stamina:
		exhausted_in_water.emit()
		return
	if _jump_pressed and is_on_wall():
		# Salir del agua trepando por la orilla.
		var nh := _horizontal(get_wall_normal()).normalized()
		_start_mantle(nh)
	elif dir != Vector3.ZERO and is_on_wall():
		_try_climb(dir, false)


# --- Aguante ---------------------------------------------------------------------------------

func _drain(amount: float) -> void:
	if debug_infinite_stamina:
		return
	stamina = maxf(stamina - amount, 0.0)
	_regen_delay = 0.7
	if stamina <= 0.0 and not exhausted:
		exhausted = true
		stamina_empty.emit()


func _stamina(dt: float) -> void:
	if state in ["ground", "sit", "boat"] and not (_sprint and _move.length() > 0.3 and not exhausted and state == "ground" and not on_bike):
		_regen_delay -= dt
		if _regen_delay <= 0.0:
			stamina = minf(stamina + REGEN * dt * (0.7 if exhausted else 1.0) * maxf(1.0, stamina_max / 5.0), stamina_max)
	if exhausted and stamina >= stamina_max - 0.001:
		exhausted = false


func refill_stamina() -> void:
	stamina = stamina_max
	exhausted = false


# --- Utilidades -------------------------------------------------------------------------------

func respawn(p: Vector3) -> void:
	global_position = p + Vector3(0, 0.3, 0)
	velocity = Vector3.ZERO
	_set_state("air")
	refill_stamina()
	reset_physics_interpolation()


func teleport(p: Vector3, yaw := NAN) -> void:
	if gear:
		gear.hide_now()
	_action_t = 0.0
	_roll_t = 0.0
	global_position = p
	velocity = Vector3.ZERO
	if not is_nan(yaw):
		facing = yaw
		avatar.rotation.y = yaw
	_set_state("air")
	reset_physics_interpolation()


func _update_trails() -> void:
	if _trails.is_empty():
		return
	if state == "glide" and avatar.glider:
		var g := avatar.glider.global_transform
		_trails[0].push(g * Vector3(-1.5, 0.3, 0.3))
		_trails[1].push(g * Vector3(1.5, 0.3, 0.3))
	else:
		for t in _trails:
			t.shrink()


func _animate(dt: float) -> void:
	_update_trails()
	if gear:
		var hand := avatar.hand_position(1)
		if state == "climb" and _hook_t <= 0.0:
			hand = (avatar.hand_position(0) + avatar.hand_position(1)) * 0.5
		gear.update(hand, dt)
	if anim_override != "":
		avatar.state = anim_override
		avatar.rotation.y = facing
		return
	var hs := _horizontal(velocity).length()
	var target_face := facing
	match state:
		"ground", "air", "swim":
			if hs > 0.6:
				target_face = atan2(-velocity.x, -velocity.z)
		"climb":
			target_face = atan2(wall_normal.x, wall_normal.z)
	if _action_t > 0.0 or state == "sit":
		target_face = facing
	facing = rotate_toward(facing, target_face, (14.0 if state != "swim" else 6.0) * dt)
	avatar.rotation.y = facing
	# Al correr en curva, el cuerpo se inclina hacia dentro.
	var turn := angle_difference(_prev_facing, facing) / maxf(dt, 0.001)
	_prev_facing = facing
	var lean_target := clampf(-turn * hs * 0.012, -0.28, 0.28) if state == "ground" else 0.0
	_lean = lerpf(_lean, lean_target, clampf(dt * 8.0, 0.0, 1.0))
	if state != "glide":
		avatar.rotation.z = _lean
	avatar.speed = hs
	avatar.climb_move = climb_move
	if bike_model and on_bike:
		var bb := Basis.from_euler(Vector3(0, facing, _lean * 1.4))
		bike_model.global_transform = Transform3D(bb, global_position + bb * Vector3(0, 0, -0.18))
		_bike_phase += hs * dt * 2.6
		for wn in ["WheelF", "WheelB"]:
			(bike_model.get_node(wn) as Node3D).rotation.x = -_bike_phase * 1.9
		(bike_model.get_node("Pedals") as Node3D).rotation.x = -_bike_phase
		avatar.pedal = _bike_phase
	match state:
		"ground":
			if on_bike:
				avatar.state = "bike"
			elif _roll_t > 0.0:
				avatar.state = "roll"
				avatar.roll_k = 1.0 - _roll_t / 0.55
			elif _action_t > 0.0:
				avatar.state = _action
			elif _land_lock > 0.0:
				avatar.state = "land"
			elif hs > 0.4:
				avatar.state = "walk"
			else:
				avatar.state = "idle"
		"air":
			avatar.state = "jump" if velocity.y > 0.5 else "fall"
		"glide":
			avatar.state = "glide"
		"climb":
			avatar.state = "hook" if _hook_t > 0.0 else "climb"
			avatar.climb_move = climb_move if _leap <= 0.0 else Vector2(0, 1)
		"mantle":
			avatar.state = "mantle"
		"swim":
			avatar.state = "swim"
		"sit", "boat":
			avatar.state = "sit"
	if state == "glide":
		avatar.rotation.z = lerpf(avatar.rotation.z, clampf(angle_difference(facing, atan2(-velocity.x, -velocity.z)) * 2.0, -0.4, 0.4), 4.0 * dt)
	else:
		avatar.rotation.z = lerpf(avatar.rotation.z, 0.0, 8.0 * dt)
