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
	if not only.is_empty() and not n in only and not (n.begins_with("poses") and "poses" in only):
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
	world.sky.apply()
	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 3000
	add_child(cam)
	cam.make_current()
	var isl := world.island
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
	await _view(Vector3(0, 380, 420), Vector3(0, 0, 0), "aerial")
	await _view(isl.ground(Vector2(10, 150), 1.6), isl.ground(Vector2(14, 120), 1.5), "ground")
	await _lineup()
	await _poses()
	get_tree().quit()


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
		var mid := world.island.ground(base + Vector2(3.2, 0))
		await _view(mid + Vector3(0, 1.3, 6.2), mid + Vector3(0, 0.9, 0), "poses_%d" % batch, 0.9)
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
