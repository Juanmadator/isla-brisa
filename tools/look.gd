extends Node
## Capturas del mundo desde varios puntos de vista (sin jugador) para ajustar el aspecto.
## Uso: Godot --path . -- --ib-look [--hour=8] [--only=aerial,village]

var world: World
var cam: Camera3D
var only: PackedStringArray = []


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	img.save_png(ProjectSettings.globalize_path("res://captures/look_%s.png" % n))
	print("captura: ", n, "  fps=", Engine.get_frames_per_second())


func _view(from: Vector3, to: Vector3, n: String, wait := 1.2) -> void:
	if not only.is_empty() and not n in only and not (n.begins_with("poses") and "poses" in only) and not (n.begins_with("closeup") and "closeup" in only):
		return
	cam.global_position = from
	cam.look_at(to)
	world.set_focus(Vector3(from.x, 0, from.z).lerp(Vector3(to.x, 0, to.z), 0.25))
	world.flora.warm_up()
	await get_tree().create_timer(wait).timeout
	await _shot(n)


func _ready() -> void:
	world = World.new()
	add_child(world)
	world.build()
	world.sky.running = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="):
			world.sky.hour = float(a.substr(7))
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		if a.begins_with("--tonemap="):   # probar otros mapeos de tono: linear, filmic, aces, agx
			world.sky.env.tonemap_mode = ["linear", "reinhard", "filmic", "aces", "agx"].find(a.substr(10)) as Environment.ToneMapper
		if a.begins_with("--exposure="):
			world.sky.env.tonemap_exposure = float(a.substr(11))
		if a.begins_with("--white="):
			world.sky.env.tonemap_white = float(a.substr(8))
		if a.begins_with("--nofx="):   # comparar sin efectos: --nofx=ssil,vol,aerial,ssao
			var fx := a.substr(7).split(",")
			var env := world.sky.env
			env.ssil_enabled = env.ssil_enabled and not "ssil" in fx
			env.volumetric_fog_enabled = env.volumetric_fog_enabled and not "vol" in fx
			env.ssao_enabled = env.ssao_enabled and not "ssao" in fx
			if "aerial" in fx:
				env.fog_aerial_perspective = 0.0
	world.sky.apply()
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 3000
	add_child(cam)
	cam.make_current()
	var isl := world.island
	if "bench" in only:
		await _bench()
		get_tree().quit()
		return
	var v := world.places.anchor("village")
	await _view(v + Vector3(22, 9, 34), v + Vector3(0, 2, 0), "village", 2.0)
	var hp := world.places.anchor("post")
	var hd := world.places.anchor("post_door")
	var out := (hd - hp).normalized()
	await _view(hd + out * 7.0 + out.cross(Vector3.UP) * 4.0 + Vector3(0, 2.2, 0), hp + Vector3(0, 3.0, 0), "house")
	await _view(world.places.anchor("spawn") + Vector3(4, 4, 10), world.places.anchor("village"), "dock")
	await _view(world.places.anchor("windmill") + Vector3(18, 6, 22), world.places.anchor("windmill") + Vector3(0, 5, 0), "windmill")
	await _view(world.places.anchor("faro_ruins") + Vector3(-20, 8, 26), world.places.anchor("faro_ruins") + Vector3(0, 6, 0), "ruins")
	await _view(isl.ground(Vector2(-60, 120), 6), isl.ground(Vector2(0, -150), 40), "mountain")
	await _view(isl.ground(Vector2(-128, 52), 2.4), isl.ground(Vector2(-180, 12), 3.0), "forest")
	await _view(isl.ground(Vector2(170, 30), 3), world.places.anchor("faro_cliff"), "cliff")
	await _view(world.places.anchor("penon") + Vector3(8, 3, -4), world.places.anchor("faro_islet"), "penon")
	await _view(isl.ground(Vector2(-100, -20), 8), isl.ground(Vector2(-150, -48), 0), "lake")
	var ld := Vector2(-0.35, 1.0).normalized()
	var shore := Island.LAKE + ld * 50.0
	var sh := maxf(isl.height_at(shore.x, shore.y), Island.LAKE_LEVEL) + 1.7
	await _view(Vector3(shore.x, sh, shore.y), Vector3(Island.LAKE.x, Island.LAKE_LEVEL + 1.0, Island.LAKE.y) - Vector3(ld.x, 0, ld.y) * 10.0, "lakeshore")
	var fm: Farm = world.places.farm
	await _view(fm.world_at(-4, 30, 9.0), fm.world_at(2, -4, 2.0), "farm")
	await _view(fm.world_at(12, 18, 3.0), fm.world_at(24, 4, 0.5), "pasture")
	world.traffic._move_cart(0.0)
	var cart: Vector3 = world.traffic._cart.global_position
	var cpos := cart + Vector3(-7.0, 0, 5.0)
	cpos.y = maxf(cart.y, world.island.height_at(cpos.x, cpos.z)) + 3.0
	await _view(cpos, cart + Vector3(0, 1.0, 0), "road", 0.3)
	var bt := world.places.anchor("boat")
	await _view(bt + Vector3(5.5, 2.6, 4.0), bt + Vector3(0, 1.0, 0), "boat")
	var st := world.places.anchor("stall")
	await _view(st + Vector3(4.5, 2.2, 5.5), st + Vector3(-1.0, 1.0, 0), "plaza")
	var wm := world.places.anchor("windmill")
	var to_v := (Vector3(Island.VILLAGE.x, wm.y, Island.VILLAGE.y) - wm).normalized()
	await _view(wm + to_v * 13.0 + to_v.cross(Vector3.UP) * 4.0 + Vector3(0, 3.5, 0), wm + Vector3(0, 4.5, 0), "mill")
	var fc := world.places.anchor("faro_cliff")
	var alt: Vector3 = (world.places.beacons["faro_cliff"]["altar"] as Node3D).global_position
	var bout := (alt - fc).normalized()
	await _view(alt + bout * 9.0 + bout.cross(Vector3.UP) * 6.0 + Vector3(0, 3.0, 0), fc + Vector3(0, 6.0, 0), "beacon")
	var arch := world.places.anchor("ruins_arch")
	await _view(arch + Vector3(9, 3.0, 7), arch + Vector3(0, 3.0, 0), "arch")
	var ul := world.places.anchor("ulises")
	await _view(ul + Vector3(-7.0, 2.6, 6.0), ul + Vector3(3.0, 1.5, -1.0), "cabin")
	var gm := world.places.anchor("gema")
	await _view(gm + Vector3(-5, 2.6, 7), gm + Vector3(3, 1.0, -3), "camp")
	await _view(Vector3(0, 380, 420), Vector3(0, 0, 0), "aerial")
	# Hacia donde se pone el sol, desde la playa: estela del sol en el mar.
	var sp := world.places.anchor("spawn")
	await _view(sp + Vector3(-6, 2.5, 4), sp + Vector3(-200, -2, 76), "seaward")
	await _view(isl.ground(Vector2(10, 150), 1.6), isl.ground(Vector2(14, 120), 1.5), "ground")
	await _lineup()
	await _gait()
	await _animals()
	await _poses()
	get_tree().quit()


## Rendimiento: FPS medios (2 s, tras 2 s de calentamiento) en varios puntos de vista.
func _bench() -> void:
	var v := world.places.anchor("village")
	var views := [["pueblo", v + Vector3(22, 9, 34), v + Vector3(0, 2, 0)],
		["bosque", world.island.ground(Vector2(-128, 52), 2.4), world.island.ground(Vector2(-180, 12), 3.0)],
		["pradera", world.island.ground(Vector2(10, 150), 1.6), world.island.ground(Vector2(14, 120), 1.5)],
		["aereo", Vector3(0, 380, 420), Vector3.ZERO]]
	# Vecinos andando por el pueblo, como en el juego.
	var holder := Node3D.new()
	add_child(holder)
	for i in (0 if OS.has_environment("IB_NOAV") else 12):
		var av := Avatar.new()
		holder.add_child(av)
		av.build({"hair_style": "short"})
		av.position = world.island.ground(Vector2(v.x, v.z) + Vector2(i * 1.7 - 10.0, 6.0))
		av.state = "walk" if i % 2 == 0 else "idle"
		av.speed = 1.3
	for vw in views:
		cam.global_position = vw[1]
		cam.look_at(vw[2])
		world.set_focus(vw[1])
		world.flora.warm_up()
		await get_tree().create_timer(2.0).timeout
		var t0 := Time.get_ticks_usec()
		var f0 := Engine.get_frames_drawn()
		await get_tree().create_timer(2.0).timeout
		var fps := (Engine.get_frames_drawn() - f0) / ((Time.get_ticks_usec() - t0) / 1e6)
		print("bench %s: %.1f fps" % [vw[0], fps])
	holder.queue_free()


## Lía de cerca y andando/corriendo de verdad (el nodo avanza): una tira de fotogramas
## por velocidad, de lado, para revisar el ciclo de marcha y que los pies no patinen.
func _gait() -> void:
	if not only.is_empty() and not "gait" in only and not "closeup" in only:
		return
	var st := world.places.anchor("stall")
	var base := Vector2(st.x, st.z) + Vector2(-6.0, 3.0)
	var av := Avatar.new()
	add_child(av)
	av.build({"backpack": true, "hair_style": "bob"})
	av.position = world.island.ground(base)
	av.rotation.y = PI
	av.state = "idle"
	var mid := av.position
	# Sin hierba, para ver bien los pies.
	world.flora.get_node("Grass").visible = false
	if only.is_empty() or "closeup" in only:
		await _view(mid + Vector3(-1.0, 1.3, 2.2), mid + Vector3(0, 0.95, 0), "closeup", 1.0)
		await _view(mid + Vector3(1.6, 1.0, -1.4), mid + Vector3(0, 0.85, 0), "closeup_back", 0.5)
	if not only.is_empty() and not "gait" in only:
		av.queue_free()
		world.flora.get_node("Grass").visible = true
		return
	for spd: float in [1.3, 6.6, 10.2]:
		av.rotation.y = PI * 0.5
		var start := base + Vector2(4.0, 0.0)
		av.position = world.island.ground(start)
		av.state = "walk"
		av.speed = spd
		var frames: Array[Image] = []
		var t := 0.0
		var shot_every := 0.6 / 7.0 * (6.6 / maxf(spd, 1.0)) if spd > 2.0 else 0.11
		var next := 0.4
		var dist := 0.0
		while frames.size() < 8:
			var dt := get_process_delta_time()
			t += dt
			dist += spd * dt
			var p := start + Vector2(-dist, 0.0)
			av.position = world.island.ground(p)
			if t >= next:
				next += shot_every
				cam.global_position = av.position + Vector3(0.0, 0.9, 3.4)
				cam.look_at(av.position + Vector3(0, 0.75, 0))
				await RenderingServer.frame_post_draw
				frames.append(get_viewport().get_texture().get_image())
			else:
				await get_tree().process_frame
		var w := frames[0].get_width() / 4
		var h := frames[0].get_height() / 2
		var sheet := Image.create(w * 4, h * 2, false, frames[0].get_format())
		for i in frames.size():
			var f := frames[i]
			var c := f.get_region(Rect2i(f.get_width() / 2 - w / 2, f.get_height() / 2 - h / 2, w, h))
			sheet.blit_rect(c, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
		sheet.save_png(ProjectSettings.globalize_path("res://captures/look_gait_%d.png" % int(spd * 10)))
		print("captura: gait ", spd, " bufanda: ", av._scarf_pts.map(func(q): return (av.global_transform.affine_inverse() * q).snappedf(0.01)))
	av.queue_free()
	world.flora.get_node("Grass").visible = true


## Hoja de poses: Lía en varias animaciones, de lado, en dos tandas de cinco.
func _poses() -> void:
	if not only.is_empty() and not "poses" in only:
		return
	var states := [["walk", 7.0], ["climb", 0.0], ["hook", 0.0], ["sit", 0.0], ["kneel", 0.0], ["pickup", 0.0], ["roll", 0.0], ["land", 0.0], ["jump", 0.0], ["glide", 0.0]]
	for batch in 2:
		var base := Island.VILLAGE + Vector2(-3.2, 14)
		var holder := Node3D.new()
		add_child(holder)
		for j in 5:
			var st: Array = states[batch * 5 + j]
			var av := Avatar.new()
			holder.add_child(av)
			av.build({"backpack": true, "hair_style": "bob"})
			var lift := 0.7 if st[0] in ["climb", "hook", "glide", "jump"] else 0.0
			av.position = world.island.ground(base + Vector2(j * 1.6, 0)) + Vector3(0, lift, 0)
			av.rotation.y = PI * 0.5
			av.state = st[0]
			av.speed = st[1]
			av.climb_move = Vector2(0, 1) if st[0] == "climb" else Vector2.ZERO
			av.roll_k = 0.35
			if st[0] in ["kneel", "pickup"]:
				av.reach_target = av.position + Vector3(-0.5, 0.06, 0.05)
		var mid := world.island.ground(base + Vector2(3.2, 0))
		world.flora.get_node("Grass").visible = false
		await _view(mid + Vector3(0, 1.1, 5.0), mid + Vector3(0, 0.8, 0), "poses_%d" % batch, 0.9)
		world.flora.get_node("Grass").visible = true
		holder.queue_free()


## Animales de granja de cerca: de tres cuartos y uno de cada pastando.
func _animals() -> void:
	if not only.is_empty() and not "animals" in only and not "animals_graze" in only:
		return
	var base := Island.VILLAGE + Vector2(-6, 16)
	var holder := Node3D.new()
	add_child(holder)
	var models := [Animals.cow(0), Animals.cow(1), Animals.donkey(), Animals.sheep(0), Animals.sheep(3), Animals.chicken(0), Animals.chicken(1),
		Pet.build_model("dog", [Color(0.85, 0.62, 0.38), Color(1, 0.95, 0.88)]), Pet.build_model("fox", [Color(0.95, 0.5, 0.2), Color(1, 0.97, 0.92)]),
		Pet.build_model("cat", [Color(0.45, 0.45, 0.5), Color(1, 1, 1)])]
	var xs := [0.0, 2.2, 4.4, 6.0, 7.2, 8.2, 8.7, 3.6, 4.6, 5.5]
	for i in models.size():
		var m: Node3D = models[i]
		holder.add_child(m)
		m.position = world.island.ground(base + Vector2(xs[i], 2.2 if i >= 7 else 0.0))
		m.rotation.y = deg_to_rad(130)
	var mid := world.island.ground(base + Vector2(4.4, 0))
	await _view(mid + Vector3(-0.5, 1.5, 5.2), mid + Vector3(0, 0.7, 0), "animals")
	for i in models.size():
		Animals.animate(models[i], 0.0, false, 1.0, 0.0)
		(models[i].get_node("Body/Head") as Node3D).rotation.x = -float(models[i].get_meta("graze", 0.9))
	await _view(mid + Vector3(-1.0, 1.7, 6.0), mid + Vector3(0, 0.7, 0), "animals_graze")
	holder.queue_free()


## Lía y todos los vecinos en fila, de cara a la cámara.
func _lineup() -> void:
	var specs: Array = [{"backpack": true, "hair_style": "bob"}]
	for id in Catalog.NPCS:
		specs.append(Catalog.NPCS[id]["spec"])
	var base := Island.VILLAGE + Vector2(-8, 12)
	var holder := Node3D.new()
	add_child(holder)
	for i in specs.size():
		var av := Avatar.new()
		holder.add_child(av)
		av.build(specs[i])
		var p := base + Vector2(i * 1.5, 0)
		av.position = world.island.ground(p)
		av.rotation.y = PI
	var mid := world.island.ground(base + Vector2((specs.size() - 1) * 0.75, 0))
	await _view(mid + Vector3(0, 1.6, 10.5), mid + Vector3(0, 0.9, 0), "lineup")
	var first := world.island.ground(base + Vector2(0.75, 0))
	await _view(first + Vector3(0.2, 1.3, 3.2), first + Vector3(0, 1.0, 0), "faces")
	holder.queue_free()
