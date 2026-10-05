class_name Fishing
extends Node3D
## Pesca: Lía lanza la caña al agua, espera a que pique (los mordisqueos son falsas alarmas),
## clava el anzuelo con E y recoge el sedal manteniendo E sin que la tensión lo rompa.
## Fases: "cast" -> "wait" -> "bite" -> "reel" -> "catch" (o "fail") -> se cierra.

signal finished(fish_id: String, size_cm: int)
signal message(text: String)

const CAST_TIME := 0.7
const BITE_WINDOW := 0.95

var player: Player
var island: Island
var sky: SkyCycle
var phase := ""
var fish_id := ""
var size_cm := 0
var progress := 0.0
var tension := 0.0
## Para las pruebas: {"press": bool, "hold": bool} sustituye al teclado.
var auto_input = null

var _t := 0.0
var _wait := 0.0
var _nibbles := 0
var _nibble_t := 0.0
var _water := "sea"
var _target := Vector3.ZERO
var _bobber: Node3D
var _rod: Node3D
var _tip: Node3D
var _line: Array[MeshInstance3D] = []
var _fish_node: Node3D
var _pressed := false
## Inclinación de la caña sobre la horizontal (grados); >90 = echada hacia atrás.
var _rod_pitch := 40.0


func _ready() -> void:
	top_level = true
	_bobber = Node3D.new()
	add_child(_bobber)
	MeshKit.part(_bobber, MeshKit.sphere(0.09, 10), MeshKit.mat(Color(0.95, 0.25, 0.2)), Vector3(0, 0.04, 0))
	MeshKit.part(_bobber, MeshKit.sphere(0.07, 10), MeshKit.mat(Color(0.98, 0.98, 0.95)), Vector3(0, -0.04, 0))
	MeshKit.part(_bobber, MeshKit.cylinder(0.012, 0.012, 0.12, 5), MeshKit.mat(Color(0.95, 0.25, 0.2)), Vector3(0, 0.14, 0))
	_bobber.visible = false
	var seg := MeshKit.cylinder(0.006, 0.006, 1.0, 4)
	var mat := MeshKit.mat(Color(0.92, 0.92, 0.9))
	for i in 8:
		var mi := MeshInstance3D.new()
		mi.mesh = seg
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_line.append(mi)


## Caña de pescar (de la mano derecha hacia delante y arriba). `tip` = punta.
static func rod_model() -> Node3D:
	var root := Node3D.new()
	var wood := MeshKit.mat(Color(0.55, 0.38, 0.22))
	MeshKit.part(root, MeshKit.cylinder(0.022, 0.03, 0.38, 8), MeshKit.mat(Color(0.25, 0.22, 0.2)), Vector3(0, 0.05, 0))
	MeshKit.part(root, MeshKit.cylinder(0.008, 0.02, 1.5, 6), wood, Vector3(0, 0.95, 0))
	MeshKit.part(root, MeshKit.cylinder(0.05, 0.05, 0.05, 10), MeshKit.mat(Color(0.7, 0.72, 0.75)), Vector3(0.04, 0.12, 0), Vector3(0, 0, 90))
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = Vector3(0, 1.7, 0)
	root.add_child(tip)
	return root


## Modelo de un pez (o de la bota vieja) para enseñarlo al pescarlo.
static func fish_model(id: String) -> Node3D:
	var info: Array = Catalog.FISH.get(id, Catalog.FISH["fish_sardine"])
	var col: Color = info[5]
	var root := Node3D.new()
	if id == "fish_boot":
		MeshKit.part(root, MeshKit.rounded_box(Vector3(0.16, 0.3, 0.18), 0.05, 2), MeshKit.mat(col), Vector3(0, 0.08, 0))
		MeshKit.part(root, MeshKit.rounded_box(Vector3(0.16, 0.12, 0.32), 0.05, 2), MeshKit.mat(col), Vector3(0, -0.05, -0.08))
		return root
	if id == "fish_octopus":
		MeshKit.part(root, MeshKit.blob(0.16, 1.2, 0.0, 0, 12), MeshKit.mat(col), Vector3(0, 0.1, 0))
		for k in 6:
			var a := TAU * k / 6.0
			MeshKit.part(root, MeshKit.capsule(0.035, 0.32), MeshKit.mat(col.darkened(0.1)), Vector3(cos(a) * 0.08, -0.12, sin(a) * 0.08), Vector3(cos(a) * 25.0, 0, sin(a) * 25.0))
		for sx: float in [-1.0, 1.0]:
			MeshKit.part(root, MeshKit.sphere(0.03, 8), MeshKit.mat(Color(0.1, 0.1, 0.1)), Vector3(sx * 0.07, 0.12, -0.13))
		return root
	var body := Node3D.new()
	body.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(body)
	var m := MeshKit.mat(col)
	MeshKit.part(body, MeshKit.blob(0.1, 3.0, 0.0, 0, 12), m, Vector3.ZERO, Vector3.ZERO, Vector3(0.75, 1.0, 1.0))
	MeshKit.part(body, MeshKit.blob(0.07, 1.4, 0.0, 0, 8), MeshKit.mat(col.lightened(0.35)), Vector3(0.0, 0.0, 0.035), Vector3.ZERO, Vector3(0.6, 1.8, 0.7))
	var tail := MeshKit.extrude(PackedVector2Array([Vector2(0, 0), Vector2(-0.13, 0.17), Vector2(0.13, 0.17)]), 0.02)
	MeshKit.part(body, tail, MeshKit.mat(col.darkened(0.15)), Vector3(0, -0.36, 0.01), Vector3(-90, 0, 180))
	MeshKit.part(body, MeshKit.sphere(0.022, 8), MeshKit.mat(Color(0.08, 0.08, 0.1)), Vector3(0.04, 0.2, 0.05))
	MeshKit.part(body, MeshKit.sphere(0.022, 8), MeshKit.mat(Color(0.08, 0.08, 0.1)), Vector3(0.04, 0.2, -0.05))
	if id == "fish_glow" or id == "fish_legend":
		var glow := MeshKit.part(body, MeshKit.sphere(0.2, 10), MeshKit.unshaded(Color(col.r, col.g, col.b, 0.25), 1.6), Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 2.2, 0.8))
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func active() -> bool:
	return phase != ""


## Empieza a pescar hacia `water_point` (un punto de la superficie del agua).
func start(water_point: Vector3, water_kind: String) -> void:
	_water = water_kind
	_target = water_point
	phase = "cast"
	_t = 0.0
	progress = 0.3
	tension = 0.0
	fish_id = ""
	player.locked = true
	var to := water_point - player.global_position
	player.facing = atan2(-to.x, -to.z)
	player.anim_override = "fish_cast"
	_rod = rod_model()
	_tip = _rod.get_node("Tip")
	player.avatar.hands[1].add_child(_rod)
	_rod_pitch = 60.0
	Audio.play("glide_open", 0.1, -6.0)


func stop() -> void:
	phase = ""
	player.locked = false
	player.anim_override = ""
	_bobber.visible = false
	for l in _line:
		l.visible = false
	if _rod:
		_rod.queue_free()
		_rod = null
	if _fish_node:
		_fish_node.queue_free()
		_fish_node = null


## Pulsación de E durante la pesca (la manda Gameplay.interact).
func press() -> void:
	_pressed = true


func _input_press() -> bool:
	if auto_input != null:
		return auto_input.get("press", false)
	var p := _pressed
	_pressed = false
	return p


func _input_hold() -> bool:
	if auto_input != null:
		return auto_input.get("hold", false)
	return Input.is_action_pressed("interact")


func _cancel_pressed() -> bool:
	if auto_input != null:
		return auto_input.get("cancel", false)
	return Input.is_action_just_pressed("drop") or Input.is_action_just_pressed("jump")


func _process(dt: float) -> void:
	if phase == "":
		return
	_t += dt
	var press := _input_press()
	if _cancel_pressed() and phase in ["wait", "bite"]:
		message.emit("Recoges el sedal.")
		stop()
		return
	var bob := _target + Vector3(0, sin(_t * 2.2) * 0.03, 0)
	match phase:
		"cast":
			var k := clampf((_t - 0.25) / (CAST_TIME - 0.25), 0.0, 1.0)
			# La caña se echa atrás por encima del hombro y sale disparada hacia delante.
			_rod_pitch = lerpf(60.0, 125.0, _t / 0.25) if _t < 0.25 else lerpf(125.0, 25.0, minf(k * 2.0, 1.0))
			var from := _tip.global_position
			bob = from.lerp(_target, k) + Vector3.UP * sin(k * PI) * 2.2
			_bobber.visible = _t > 0.25
			if _t >= CAST_TIME:
				Audio.play("splash", 0.1, -8.0)
				Fx.splash(get_parent(), _target, 0.25)
				phase = "wait"
				player.anim_override = "fish"
				_t = 0.0
				_wait = randf_range(2.5, 7.0) * (0.7 if _good_hour() else 1.0)
				_nibbles = randi_range(0, 2)
				_nibble_t = randf_range(0.8, _wait * 0.8) if _nibbles > 0 else INF
		"wait":
			if _t > _nibble_t and _nibbles > 0:
				# Mordisqueo: el flotador se hunde un poco. Si clavas ahora, el pez se asusta.
				bob.y -= 0.08
				if _t > _nibble_t + 0.25:
					_nibbles -= 1
					_nibble_t = _t + randf_range(0.7, 1.6)
			if press:
				message.emit("¡Demasiado pronto! El pez se ha asustado.")
				Audio.play("error", 0.0, -6.0)
				_t = 0.0
				_wait = randf_range(3.0, 6.0)
				_nibbles = randi_range(0, 1)
				_nibble_t = randf_range(0.8, 2.0) if _nibbles > 0 else INF
			elif _t >= _wait:
				phase = "bite"
				_t = 0.0
				fish_id = _pick_fish()
				Audio.play("splash", 0.1, -2.0)
				Fx.splash(get_parent(), _target, 0.5)
				message.emit("¡Pica! ¡Pulsa E!")
		"bite":
			bob.y -= 0.22
			if press:
				phase = "reel"
				_t = 0.0
				player.anim_override = "fish_reel"
				Audio.play("glide_close", 0.05, -4.0)
			elif _t > BITE_WINDOW:
				message.emit("Se ha escapado...")
				phase = "wait"
				_t = 0.0
				_wait = randf_range(3.0, 6.0)
				_nibbles = 0
				_nibble_t = INF
		"reel":
			var info: Array = Catalog.FISH[fish_id]
			var strength: float = info[3]
			var pull := strength * (0.55 + 0.45 * sin(_t * (2.0 + strength * 4.0))) * 0.42
			if _input_hold():
				progress += 0.3 * dt
				tension += (0.35 + strength * 0.75) * dt
			else:
				tension -= 0.7 * dt
			progress -= pull * dt
			tension = clampf(tension, 0.0, 1.0)
			_rod_pitch = 45.0 + sin(_t * 9.0) * (4.0 + strength * 8.0)
			# El flotador se acerca a la orilla según se recoge.
			var start := _target
			bob = start.lerp(player.global_position + Vector3(0, 0.0, 0), clampf(progress, 0.0, 1.0) * 0.7)
			bob.y = _target.y - 0.15
			if tension >= 1.0:
				message.emit("¡Se ha roto el sedal!")
				Audio.play("fail", 0.0, -4.0)
				_end("")
			elif progress <= 0.0:
				message.emit("El pez se ha soltado...")
				Audio.play("fail", 0.0, -6.0)
				_end("")
			elif progress >= 1.0:
				_catch()
		"catch":
			_rod_pitch = lerpf(_rod_pitch, 75.0, dt * 6.0)
			if _t > 1.8:
				_end(fish_id)
	if phase == "wait":
		_rod_pitch = lerpf(_rod_pitch, 30.0 + sin(_t * 1.5) * 2.0, dt * 4.0)
	elif phase == "bite":
		_rod_pitch = lerpf(_rod_pitch, 18.0, dt * 10.0)
	_aim_rod()
	_bobber.global_position = bob
	_update_line()


func _aim_rod() -> void:
	if _rod == null:
		return
	var fwd := Vector3(-sin(player.facing), 0, -cos(player.facing))
	var p := deg_to_rad(_rod_pitch)
	var dir := (fwd * cos(p) + Vector3.UP * sin(p)).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var z := right.cross(dir).normalized()
	_rod.global_basis = Basis(right, dir, z)


func _update_line() -> void:
	var show := phase in ["cast", "wait", "bite", "reel"] and _bobber.visible
	if not show:
		for l in _line:
			l.visible = false
		return
	var a := _tip.global_position
	var b := _bobber.global_position + Vector3(0, 0.2, 0)
	var sag := 0.6 if phase == "wait" else 0.1
	var prev := a
	for i in _line.size():
		var u := float(i + 1) / _line.size()
		var p := a.lerp(b, u) + Vector3.DOWN * sin(u * PI) * sag
		ClimbGear._segment(_line[i], prev, p)
		_line[i].visible = true
		prev = p


func _good_hour() -> bool:
	# Al amanecer y al atardecer pican antes.
	var h: float = sky.hour if sky else 12.0
	return (h > 5.5 and h < 8.5) or (h > 17.5 and h < 20.5)


func _pick_fish() -> String:
	var night: bool = sky != null and sky.is_night()
	var pool := []
	var total := 0.0
	for id in Catalog.FISH:
		var f: Array = Catalog.FISH[id]
		if f[1] != "any" and f[1] != _water:
			continue
		if f[7] == "night" and not night:
			continue
		if f[7] == "day" and night:
			continue
		pool.append([id, float(f[2])])
		total += float(f[2])
	var r := randf() * total
	for e in pool:
		r -= e[1]
		if r <= 0.0:
			return e[0]
	return pool[0][0]


func _catch() -> void:
	phase = "catch"
	_t = 0.0
	var info: Array = Catalog.FISH[fish_id]
	var sz: Array = info[6]
	size_cm = randi_range(sz[0], sz[1])
	player.anim_override = "hold_up"
	_bobber.visible = false
	if _rod:
		_rod.visible = false
	_fish_node = fish_model(fish_id)
	player.avatar.hold_point.add_child(_fish_node)
	_fish_node.scale = Vector3.ONE * clampf(1.0 + size_cm / 40.0, 1.2, 3.2)
	Fx.splash(get_parent(), _target, 0.6)
	Audio.play("item")


func _end(id: String) -> void:
	var sz := size_cm
	stop()
	finished.emit(id, sz)
