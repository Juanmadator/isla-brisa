extends Node
## Capturas de todas las pantallas para revisar el aspecto. Uso: Godot --path . -- --ib-capture

var main


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	img.save_png(ProjectSettings.globalize_path("res://captures/%s.png" % n))
	print("captura: ", n, "  fps=", Engine.get_frames_per_second())


## Cierra escenas de descubrimiento y diálogos hasta volver a jugar.
func _skip() -> void:
	var guard := 0
	while main.state != "play" and guard < 400:
		guard += 1
		if main.state == "showcase":
			if main.hud.card_ready:
				main._end_showcase()
		elif main.state == "dialog":
			main.hud.dialogue.advance()
			main.hud.dialogue.advance()
		await get_tree().process_frame


func _walk(dir_yaw: float, secs: float, extra := {}) -> void:
	var p: Player = main.player
	var t := 0.0
	while t < secs:
		p.cam_yaw = dir_yaw
		main.rig.yaw = dir_yaw
		var ap := {"move": Vector2(0, -1)}
		ap.merge(extra, true)
		p.autopilot = ap
		await get_tree().physics_frame
		t += 1.0 / 60.0
	p.autopilot = null


func _place(pos: Vector3, look_yaw: float, pitch := -0.22) -> void:
	main.player.teleport(pos, look_yaw)
	main.world.set_focus(pos)
	main.world.flora.warm_up()
	main.rig.look_dir(look_yaw, pitch)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


func _ready() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	main.go_title()
	await _wait(3.5)
	await _shot("01_title")
	if only == "title":
		get_tree().quit()
		return
	main.start_game(true)
	await _wait(3.2)
	await _shot("02_meet_tomeu")
	main._end_showcase()
	await _wait(2.5)
	await _shot("03_dialog_tomeu")
	await _skip()
	await _wait(0.6)
	await _shot("04_dock_hint")
	var gp: Gameplay = main.gameplay
	var pl: Places = main.world.places
	# Pueblo y Rosa
	var rosa: Npc = gp.npcs["rosa"]
	var stand := rosa.position - (rosa.position - pl.anchor("village")).normalized() * 3.0
	stand.y = main.world.island.height_at(stand.x, stand.z) + 0.2
	_place(stand, _yaw_to(stand, rosa.position))
	await _wait(1.2)
	await _shot("05_village")
	gp.talk("rosa")
	await _wait(3.0)
	await _shot("06_meet_rosa")
	await _skip()
	# Objeto nuevo: la primera concha
	var shell := {}
	for p in gp.pickups:
		if p["kind"] == "shell":
			shell = p
			break
	var sp: Vector3 = shell["pos"]
	_place(sp + Vector3(0, 0.3, 0), 0.0)
	await _wait(3.4)
	await _shot("07_showcase_shell")
	await _skip()
	# Gatito (criatura)
	SaveGame.set_flag("pia_quest")
	var kid := "kitten_forest"
	var kn: Node3D = gp.kittens[kid]
	var kp := kn.position + Vector3(2.0, 0, 1.0)
	kp.y = main.world.island.height_at(kp.x, kp.z) + 0.3
	_place(kp, _yaw_to(kp, kn.position))
	await _wait(1.0)
	gp._pet_kitten(kid)
	await _wait(2.6)
	await _shot("08_showcase_kitten")
	await _skip()
	# Mapa con zona de búsqueda y pista
	SaveGame.data["tracked"] = "kittens"
	await _wait(0.5)
	await _shot("09_hint_hud")
	main._open_menu("map")
	await _wait(0.8)
	await _shot("10_map_area")
	main.menus.show_pause("journal")
	await _wait(0.6)
	await _shot("11_journal")
	main.resume()
	# Tiendas nuevas, probador y mascota
	SaveGame.data["shells"] = 420
	var lola: Npc = gp.npcs["lola"]
	var lp := lola.position + (pl.anchor("pen") - lola.position).normalized() * -2.5
	lp.y = main.world.island.height_at(lp.x, lp.z) + 0.2
	_place(lp, _yaw_to(lp, pl.anchor("pen")))
	await _wait(0.6)
	main._open_menu("shop:tailor")
	await _wait(1.4)
	await _shot("16_shop_tailor")
	main.menus.show_shop("pets")
	await _wait(1.2)
	await _shot("17_shop_pets")
	main.menus._buy("pet_dog")
	await _wait(0.4)
	main.resume()
	await _wait(0.6)
	await _walk(_yaw_to(lp, pl.anchor("village")), 1.4)
	main.rig.look_dir(main.player.facing + PI * 0.8, -0.3)
	await _wait(2.2)
	await _shot("18_pet_follow")
	main._open_menu("looks")
	await _wait(1.2)
	await _shot("19_looks")
	main.resume()
	# Pesca en el muelle
	SaveGame.set_flag("has_rod")
	var dock_p: Vector3 = pl.anchor("spawn")
	_place(dock_p + Vector3(0, 0.2, 0), PI, -0.12)
	await _wait(0.8)
	main.rig.look_dir(PI + 2.3, -0.18)
	gp.start_fishing()
	var fsh: Fishing = gp.fishing
	fsh.auto_input = {}
	await _wait(1.4)
	await _shot("20_fishing")
	fsh._wait = 0.0
	fsh._nibbles = 0
	await _wait(0.1)
	fsh.fish_id = "fish_bream"
	fsh.auto_input = {"press": true}
	await _wait(0.1)
	var tt := 0.0
	while fsh.phase == "reel" and tt < 2.0:
		fsh.auto_input = {"hold": fsh.tension < 0.55}
		await get_tree().process_frame
		tt += get_process_delta_time()
	await _shot("21_reel")
	while fsh.phase == "reel":
		fsh.auto_input = {"hold": fsh.tension < 0.55}
		await get_tree().process_frame
	await _wait(0.8)
	await _shot("22_catch")
	fsh.auto_input = null
	await _wait(1.5)
	await _skip()
	# Viento de vuelta: remolinos y estelas al planear
	for id in Catalog.REGULAR_BEACONS:
		SaveGame.set_flag("lit_" + id)
	SaveGame.set_flag("has_glider")
	gp.apply_progress()
	gp.wind = 1.0
	var pen := pl.anchor("penon")
	var islet := pl.anchor("faro_islet")
	var yaw_i := _yaw_to(pen, islet)
	_place(pen + Vector3(0, 0.5, 0), yaw_i)
	for i in 240:
		var j: bool = main.player.state == "air" and i % 8 < 2
		main.player.cam_yaw = yaw_i
		main.rig.yaw = yaw_i
		main.player.autopilot = {"move": Vector2(0, -1), "jump": j}
		await get_tree().physics_frame
		if main.player.state == "glide" and i > 100:
			break
	main.player.autopilot = {"move": Vector2(0, -1)}
	main.rig.look_dir(yaw_i + 0.7, -0.12)
	await _wait(1.6)
	await _shot("12_glide_trails")
	main.player.autopilot = null
	# Prado con viento, mariposas y sombras de nubes
	var mp := Vector3(40, 0, 60)
	mp.y = main.world.island.height_at(mp.x, mp.z) + 0.3
	_place(mp, PI * 0.15, -0.12)
	await _wait(3.0)
	await _shot("13_meadow_wind")
	# Playa con palmeras
	var bp := Vector3(120, 0, 200)
	bp.y = main.world.island.height_at(bp.x, bp.z) + 0.3
	_place(bp, _yaw_to(bp, Vector3(160, 0, 230)), -0.1)
	await _wait(1.5)
	await _shot("14_beach")
	# Vista aérea con sombras de nubes
	main.title_cam.global_position = Vector3(60, 120, 260)
	main.title_cam.look_at(Vector3(0, 10, 80))
	main.title_cam.make_current()
	main.hud.set_gameplay_visible(false)
	await _wait(1.5)
	await _shot("15_aerial_clouds")
	get_tree().quit()
