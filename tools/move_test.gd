extends Node
## Pruebas de movimiento con piloto automático y capturas de Lía.
## Uso: Godot --path . -- --ib-move

var world: World
var player: Player
var rig: CamRig
var fails := 0


func _check(cond: bool, what: String) -> void:
	print(("OK    " if cond else "FALLO ") + what)
	if not cond:
		fails += 1


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://captures/move_%s.png" % n))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Mantiene la dirección `dir` (mundo) durante `secs`, con salto/sprint opcionales.
func _hold(dir: Vector3, secs: float, extra := {}) -> void:
	var t := 0.0
	while t < secs:
		var d := dir
		if extra.has("towards"):
			var tgt: Vector3 = extra["towards"]
			d = Vector3(tgt.x - player.global_position.x, 0, tgt.z - player.global_position.z).normalized()
		player.cam_yaw = atan2(-d.x, -d.z)
		var ap := {"move": Vector2(0, -1) if d != Vector3.ZERO else Vector2.ZERO}
		ap.merge(extra, true)
		if extra.has("jump_every"):
			ap["jump"] = fmod(t, extra["jump_every"]) < 0.1
		player.autopilot = ap
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if extra.has("until") and (extra["until"] as Callable).call():
			break
	player.autopilot = {"move": Vector2.ZERO}


func _ready() -> void:
	world = World.new()
	add_child(world)
	world.build()
	world.sky.running = false
	world.sky.hour = 10.0
	world.sky.apply()
	player = Player.new()
	player.island = world.island
	add_child(player)
	for u in [["updraft_penon", 3.5, 26.0], ["updraft_ruins", 3.5, 30.0]]:
		player.updrafts.append([world.places.anchor(u[0]), u[1], u[2]])
	rig = CamRig.new()
	add_child(rig)
	rig.attach(player)
	rig.cam.make_current()
	var isl := world.island
	var pl := world.places

	# 1. Andar y correr por el pueblo
	var start := pl.anchor("village") + Vector3(0, 0.5, 14)
	player.teleport(start)
	await _frames(20)
	await _hold(Vector3(1, 0, 0), 2.0)
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check(moved > 10.0, "corre por el pueblo (%.1f m en 2 s)" % moved)
	await _hold(Vector3(-1, 0, 0), 1.5, {"sprint": true})
	_check(player.stamina < player.stamina_max, "esprintar gasta aguante (%.2f)" % player.stamina)
	rig.look_dir(PI * 0.75)
	await _frames(40)
	await _shot("village")

	# 2. Saltar
	await _frames(60)
	var y0 := player.global_position.y
	player.autopilot = {"jump": true}
	await _frames(14)
	_check(player.global_position.y > y0 + 0.8, "salta (%.2f m)" % (player.global_position.y - y0))
	player.autopilot = {}
	await _frames(60)

	# 3. Escalar la Roca Aguja con el aguante inicial
	var needle := pl.anchor("needle")
	var np := needle + Vector3(-6, 0, 0)
	np.y = isl.height_at(np.x, np.z) + 0.3
	player.teleport(np)
	player.refill_stamina()
	await _frames(30)
	var st := {"climbed": false, "max_y": -INF}
	await _hold(Vector3.ZERO, 14.0, {"towards": needle, "until": func() -> bool:
		if player.state == "climb":
			st["climbed"] = true
		return st["climbed"] and player.state == "ground" and player.global_position.y > pl.anchor("needle_top").y - 1.5})
	_check(st["climbed"], "empieza a escalar la Roca Aguja")
	_check(player.global_position.y > pl.anchor("needle_top").y - 1.5, "llega arriba de la Roca Aguja (y=%.1f, cima %.1f, aguante %.2f)" % [player.global_position.y, pl.anchor("needle_top").y, player.stamina])
	rig.look_dir(0.6, -0.4)
	await _frames(30)
	await _shot("needle_top")

	# 3b. Capturas del gancho: al lanzarlo y trepando por la cuerda (vista de lado)
	player.teleport(np)
	player.refill_stamina()
	await _frames(30)
	var to_n := Vector3(needle.x - np.x, 0, needle.z - np.z).normalized()
	await _hold(Vector3.ZERO, 6.0, {"towards": needle, "until": func() -> bool: return player.state == "climb"})
	rig.look_dir(atan2(-to_n.x, -to_n.z) + 2.0, -0.15)
	await _frames(6)
	await _shot("hook_throw")
	player.autopilot = {"move": Vector2(0, -0.7)}
	await _frames(70)
	await _shot("rope")
	player.autopilot = {"move": Vector2.ZERO}

	# 4. Escalar el acantilado del este (pared de ~35 m): con 3 de aguante no debería bastar
	var cliff := pl.anchor("faro_cliff")
	var base := Vector3(cliff.x - 48, 0, cliff.z + 4)
	base.y = isl.height_at(base.x, base.z) + 0.3
	player.teleport(base)
	player.refill_stamina()
	await _frames(30)
	await _hold(Vector3.ZERO, 30.0, {"towards": cliff, "until": func() -> bool:
		st["max_y"] = maxf(st["max_y"], player.global_position.y)
		return player.exhausted or player.global_position.y > Island.CLIFF_Y - 1.0})
	print("   acantilado con 3 de aguante: altura máx %.1f de %.1f (base %.1f)" % [st["max_y"], Island.CLIFF_Y, base.y])
	await _frames(10)
	rig.look_dir(atan2(-(cliff.x - base.x), -(cliff.z - base.z)) + PI, -0.1)
	await _shot("cliff_climb")
	# Con más aguante (plumas) sí
	player.teleport(base)
	player.stamina_max = 6.0
	player.refill_stamina()
	await _frames(30)
	await _hold(Vector3.ZERO, 40.0, {"towards": cliff, "until": func() -> bool:
		return player.state == "ground" and player.global_position.y > Island.CLIFF_Y - 2.0})
	_check(player.global_position.y > Island.CLIFF_Y - 2.0, "sube el acantilado con 6 de aguante (y=%.1f, aguante %.2f, estado %s, normal %s)" % [player.global_position.y, player.stamina, player.state, player.wall_normal])
	await _shot("cliff_top")
	player.stamina_max = 3.0

	# 5. Planear desde el Peñón hasta el islote con la paravela y el aguante inicial
	player.has_glider = true
	var pen := pl.anchor("penon")
	var islet := pl.anchor("faro_islet")
	player.teleport(pen + Vector3(0, 0.5, 0))
	player.refill_stamina()
	await _frames(30)
	var dir := Vector3(islet.x - pen.x, 0, islet.z - pen.z).normalized()
	var glided := false
	await _hold(dir, 6.0, {"until": func() -> bool: return player.state == "air"})
	for k in 20:
		player.autopilot = {"move": Vector2(0, -1), "jump": true}
		await _frames(2)
		player.autopilot = {"move": Vector2(0, -1), "jump": false}
		await _frames(4)
		if player.state == "glide":
			break
	glided = player.state == "glide"
	_check(glided, "abre la paravela al saltar desde el Peñón")
	rig.look_dir(atan2(-dir.x, -dir.z), -0.2)
	await _hold(dir, 2.0, {"towards": islet})
	await _shot("glide")
	await _hold(dir, 40.0, {"towards": islet, "until": func() -> bool: return player.state in ["ground", "swim", "climb"]})
	var d_islet := Vector2(player.global_position.x - islet.x, player.global_position.z - islet.z).length()
	_check(player.state != "swim" and d_islet < 22.0, "llega planeando al islote (estado %s, a %.1f m, aguante %.2f)" % [player.state, d_islet, player.stamina])

	# 6. Nadar
	var sea := pl.anchor("dock") + Vector3(18, 0, 22)
	player.teleport(Vector3(sea.x, -0.5, sea.z))
	await _frames(20)
	await _hold(Vector3(1, 0, 0), 1.0)
	_check(player.state == "swim", "nada en el mar (%s)" % player.state)
	rig.look_dir(PI * 0.5, -0.2)
	await _frames(20)
	await _shot("swim")

	# 7. Encaramarse a una caja del muelle
	print("MOVE_TEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)
