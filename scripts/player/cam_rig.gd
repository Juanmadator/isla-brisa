class_name CamRig
extends Node3D
## Cámara en tercera persona: gira con el ratón o el stick derecho, se acerca al chocar
## con el terreno y se coloca sola detrás de Lía cuando corre un rato sin tocarla.

var target: Player
var yaw := 0.0
var pitch := -0.28
var dist := 5.6
var dist_target := 5.6
var sensitivity := 0.0032
var invert_y := false
var cam: Camera3D
var arm: SpringArm3D
var enabled := true
var shake := 0.0

var _idle_look := 10.0
var _follow := Vector3.ZERO
var _fov := 68.0


func _ready() -> void:
	top_level = true
	arm = SpringArm3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	arm.shape = sphere
	arm.spring_length = dist
	arm.margin = 0.15
	add_child(arm)
	cam = Camera3D.new()
	cam.fov = _fov
	cam.near = 0.08
	cam.far = 3000.0
	arm.add_child(cam)


func attach(p: Player) -> void:
	target = p
	arm.add_excluded_object(p.get_rid())
	_follow = p.global_position + Vector3(0, 1.45, 0)
	global_position = _follow


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * sensitivity
		pitch -= event.relative.y * sensitivity * (-1.0 if invert_y else 1.0)
		pitch = clampf(pitch, -1.3, 0.75)
		_idle_look = 0.0
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist_target = clampf(dist_target - 0.6, 2.5, 11.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist_target = clampf(dist_target + 0.6, 2.5, 11.0)


func _process(dt: float) -> void:
	if target == null or not enabled:
		return
	var stick := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if stick.length() > 0.1:
		yaw -= stick.x * 2.6 * dt
		pitch = clampf(pitch - stick.y * 1.8 * dt * (-1.0 if invert_y else 1.0), -1.3, 0.75)
		_idle_look = 0.0
	_idle_look += dt
	var tp := target.get_global_transform_interpolated().origin
	var st := target.state
	var head := 1.45
	if st == "swim":
		head = 1.1
	var want := tp + Vector3(0, head, 0)
	var k := 1.0 - exp(-16.0 * dt)
	var ky := 1.0 - exp(-(9.0 if st == "ground" else 14.0) * dt)
	_follow.x = lerpf(_follow.x, want.x, k)
	_follow.z = lerpf(_follow.z, want.z, k)
	_follow.y = lerpf(_follow.y, want.y, ky)
	global_position = _follow
	# Recolocación suave detrás de Lía al moverse sin tocar la cámara.
	var hv := Vector2(target.velocity.x, target.velocity.z)
	if _idle_look > 1.6 and hv.length() > 3.0 and st != "climb":
		var behind := atan2(-hv.x, -hv.y)
		var rate := 0.9 if st == "glide" else 0.45
		yaw = rotate_toward(yaw, behind, rate * dt * clampf(hv.length() / 8.0, 0.3, 1.2))
	var d := dist_target
	var fov := 68.0
	if st == "glide":
		d += 2.0
		fov = 74.0
	elif st == "ground" and hv.length() > Player.RUN + 1.0:
		fov = 73.0
	elif st == "climb":
		d -= 0.6
	dist = lerpf(dist, d, 1.0 - exp(-4.0 * dt))
	arm.spring_length = dist
	_fov = lerpf(_fov, fov, 1.0 - exp(-3.0 * dt))
	cam.fov = _fov
	rotation = Vector3(pitch, yaw, 0)
	if shake > 0.0:
		shake = maxf(shake - dt * 2.0, 0.0)
		cam.h_offset = randf_range(-1, 1) * shake * 0.15
		cam.v_offset = randf_range(-1, 1) * shake * 0.15
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
	target.cam_yaw = yaw


## Orienta la cámara para mirar en una dirección (al teletransportar o en escenas).
func look_dir(dir_yaw: float, p := -0.25) -> void:
	yaw = dir_yaw
	pitch = p
	if target:
		_follow = target.global_position + Vector3(0, 1.45, 0)
		global_position = _follow
