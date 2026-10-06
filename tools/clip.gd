extends Node
## Clips de juego con piloto automático, vistos con la cámara del juego: hojas de fotogramas
## (4x3) para revisar cómo se mueve Lía (arrancar, girar, esprintar, media vuelta, frenar,
## saltar y aterrizar) y cómo la sigue la cámara.
## Uso: Godot --path . -- --ib-clip [--only=run,turn,skid,jump,stop]

var world: World
var player: Player
var rig: CamRig
var only: PackedStringArray = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	world = World.new()
	add_child(world)
	world.build()
	world.sky.running = false
	world.sky.hour = 10.0
	world.sky.apply()
	player = Player.new()
	player.island = world.island
	add_child(player)
	rig = CamRig.new()
	add_child(rig)
	rig.attach(player)
	rig.cam.make_current()
	var pl := world.places
	var start := pl.anchor("village") + Vector3(0, 0.5, 14)
	# Arrancar desde parada y correr en línea recta (cámara detrás).
	await _clip("run", start, PI * 0.5, [[Vector3(1, 0, 0), 1.6, {}]], 0.12)
	# Correr y girar 90° en marcha.
	await _clip("turn", start, PI * 0.5, [[Vector3(1, 0, 0), 0.8, {}], [Vector3(0, 0, -1), 1.0, {}]], 0.15)
	# Esprintar y dar media vuelta (frenazo).
	await _clip("skid", start, PI * 0.5, [[Vector3(1, 0, 0), 1.0, {"sprint": true}], [Vector3(-1, 0, 0), 1.2, {"sprint": true}]], 0.18)
	# Correr y frenar en seco.
	await _clip("stop", start, PI * 0.5, [[Vector3(1, 0, 0), 1.0, {}], [Vector3.ZERO, 1.0, {}]], 0.17)
	# Saltar corriendo y aterrizar.
	await _clip("jump", start, PI * 0.5, [[Vector3(1, 0, 0), 0.4, {}], [Vector3(1, 0, 0), 1.2, {"jump_at": 0.05}]], 0.12)
	await _prints()
	get_tree().quit()


## Huellas en la playa: corre un trecho por la arena y mira atrás.
func _prints() -> void:
	if not only.is_empty() and not "prints" in only:
		return
	# Un punto de arena llana cerca de la playa de las palmeras.
	var bp := Vector3(120, 0, 200)
	for r in range(0, 90, 3):
		var found := false
		for k in 16:
			var q := Vector2(120, 200) + Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0)) * r
			if world.island.biome_at(q.x, q.y) == Island.Biome.SAND and world.island.normal_at(q.x, q.y).y > 0.85 and world.island.height_at(q.x, q.y) > world.island.water_level(q.x, q.y) + 0.5:
				bp = Vector3(q.x, 0, q.y)
				found = true
				break
		if found:
			break
	bp.y = world.island.height_at(bp.x, bp.z) + 0.3
	var steps := [0]
	player.step.connect(func(_b: int) -> void: steps[0] += 1)
	# A lo largo de la orilla (perpendicular a la pendiente).
	var isl := world.island
	var g := Vector2(isl.height_at(bp.x + 1.0, bp.z) - isl.height_at(bp.x - 1.0, bp.z), isl.height_at(bp.x, bp.z + 1.0) - isl.height_at(bp.x, bp.z - 1.0))
	var along := Vector2(-g.y, g.x).normalized()
	var dir := Vector3(along.x, 0, along.y)
	# Sin Main: las huellas se ponen aquí (como en Main._on_step).
	player.step.connect(func(biome: int) -> void:
		if biome == Island.Biome.SAND or biome == Island.Biome.PATH:
			Fx.footprint(world, player.last_step_pos, player.facing, player.last_step_side))
	var saved := only
	only = PackedStringArray()
	await _clip("beach", bp, atan2(-dir.x, -dir.z), [[dir, 1.4, {}], [Vector3.ZERO, 0.8, {}]], 0.3)
	only = saved
	print("pasos: ", steps[0], " huellas: ", Fx._prints.size(), " jugador ", player.global_position, " estado ", player.state, " bioma ", world.island.biome_at(player.global_position.x, player.global_position.z))
	# Mirar hacia atrás, desde arriba.
	var p := player.global_position
	rig.enabled = false
	rig.cam.global_position = p + dir * 1.5 + Vector3(0, 2.6, 0)
	rig.cam.look_at(p - dir * 3.0)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/clip_prints.png"))
	rig.enabled = true
	print("captura: huellas")


## Teletransporta, coloca la cámara y ejecuta los tramos [dirección, segundos, extra],
## guardando un fotograma cada `every` segundos (12 como mucho).
func _clip(n: String, at: Vector3, yaw: float, legs: Array, every: float) -> void:
	if not only.is_empty() and not n in only:
		return
	player.teleport(at, yaw)
	rig.look_dir(yaw + 0.5, -0.22)
	player.autopilot = {"move": Vector2.ZERO}
	world.set_focus(at)
	world.flora.warm_up()
	for i in 40:
		await get_tree().physics_frame
	var frames: Array[Image] = []
	var t := 0.0
	var next := 0.0
	for leg in legs:
		var d: Vector3 = leg[0]
		var secs: float = leg[1]
		var extra: Dictionary = leg[2]
		var lt := 0.0
		while lt < secs:
			var ap := {"move": Vector2(0, -1) if d != Vector3.ZERO else Vector2.ZERO}
			if d != Vector3.ZERO:
				player.cam_yaw = atan2(-d.x, -d.z)
			ap["sprint"] = extra.get("sprint", false)
			if extra.has("jump_at"):
				ap["jump"] = lt >= float(extra["jump_at"]) and lt < float(extra["jump_at"]) + 0.15
			player.autopilot = ap
			# La cámara de juego usa su propio yaw: que no siga al jugador con el yaw del piloto.
			await get_tree().process_frame
			var dt := get_process_delta_time()
			t += dt
			lt += dt
			if t >= next and frames.size() < 12:
				next += every
				await RenderingServer.frame_post_draw
				frames.append(get_viewport().get_texture().get_image())
	player.autopilot = {"move": Vector2.ZERO}
	if frames.is_empty():
		return
	var w := frames[0].get_width() / 4
	var h := frames[0].get_height() / 4
	var sheet := Image.create(w * 4, h * 3, false, frames[0].get_format())
	for i in frames.size():
		var f := frames[i]
		f.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(f, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
	sheet.save_png(ProjectSettings.globalize_path("res://captures/clip_%s.png" % n))
	print("captura: clip ", n)
