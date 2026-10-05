extends Node
## Una captura pequeña de cada objeto colocable (plumas, cofres, gatitos, chispas, setas,
## vecinos) para comprobar que ninguno flota ni queda enterrado.
## Uso: Godot --path . -- --ib-items   (después: python tools/contact_sheet.py)

var main


func _ready() -> void:
	await get_tree().process_frame
	SaveGame.persist = false
	SaveGame.new_game()
	main._reset_world()
	main.world.sky.running = false
	main.world.sky.hour = 11.0
	main.world.sky.apply()
	main.player.visible = false
	main.hud.set_gameplay_visible(false)
	var cam := Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.make_current()
	var gp: Gameplay = main.gameplay
	var targets := []
	for p in gp.pickups:
		if p["kind"] != "shell":
			targets.append([p["id"], p["pos"]])
	for id in gp.chests:
		targets.append([id, (gp.chests[id]["root"] as Node3D).position])
	for id in gp.kittens:
		targets.append([id, (gp.kittens[id] as Node3D).position])
	for id in gp.npcs:
		targets.append(["npc_" + id, (gp.npcs[id] as Node3D).position + Vector3(0, 0.8, 0)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/items"))
	var isl: Island = main.world.island
	for t in targets:
		var pos: Vector3 = t[1]
		# Buscar un punto de vista libre alrededor del objeto.
		var best := pos + Vector3(5, 3, 5)
		for k in 8:
			var a := TAU * k / 8.0
			var c := pos + Vector3(cos(a) * 6.0, 0, sin(a) * 6.0)
			c.y = maxf(pos.y + 2.5, isl.height_at(c.x, c.z) + 1.8)
			if c.y - pos.y < 5.0:
				best = c
				break
		cam.global_position = best
		cam.look_at(pos)
		main.world.set_focus(pos)
		main.world.flora.warm_up()
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(480, 270)
		img.save_png(ProjectSettings.globalize_path("res://captures/items/%s.png" % t[0]))
	print("ITEMS ", targets.size())
	get_tree().quit()
