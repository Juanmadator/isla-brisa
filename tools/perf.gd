extends Node
## Rendimiento jugando de verdad: partida nueva y Lía recorre la isla con piloto automático
## (playa, pueblo, pradera, bosque) corriendo y esprintando. Mide el tiempo de cada fotograma
## (media, percentil 99, máximo y tirones), el tiempo de los scripts y de la física, y apunta
## dónde y cuándo salen los fotogramas más lentos.
## Uso: Godot --path . -- --ib-perf [--quality=2] [--route=pueblo,bosque]

var main
const HITCH_MS := 25.0


func _ready() -> void:
	var quality := 2
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			quality = int(a.substr(10))
		if a.begins_with("--route="):
			only = a.substr(8).split(",")
	SaveGame.data["settings"]["quality"] = quality
	SaveGame.set_setting("vsync", 0)
	SaveGame.set_flag("intro_done")
	main.world.set_quality(quality)
	main.start_game(false)
	await get_tree().create_timer(2.5).timeout
	var pl: Places = main.world.places
	var isl: Island = main.world.island
	var v := pl.anchor("village")
	var legs := [
		["playa", [pl.anchor("spawn") + Vector3(20, 0, -10), v + Vector3(0, 0, 30)]],
		["pueblo", [v + Vector3(14, 0, 8), v + Vector3(0, 0, -16), v + Vector3(-16, 0, 4), v + Vector3(0, 0, 18)]],
		["pradera", [isl.ground(Vector2(10, 150)), isl.ground(Vector2(14, 100)), isl.ground(Vector2(60, 60))]],
		["bosque", [isl.ground(Vector2(-110, 40)), isl.ground(Vector2(-150, 20)), isl.ground(Vector2(-170, 60))]],
	]
	_census()
	_switch_off()
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var all: Array[float] = []
	var worst := []
	print("perf calidad: ", World.QUALITY_NAMES[main.world.quality])
	for leg in legs:
		if not only.is_empty() and not leg[0] in only:
			continue
		var times: Array[float] = []
		var phys := 0.0
		var gpu := 0.0
		var last := Time.get_ticks_usec()
		for target: Vector3 in leg[1]:
			var t_leg := 0.0
			var p: Player = main.player
			while t_leg < 14.0:
				var d := Vector2(target.x - p.global_position.x, target.z - p.global_position.z)
				if d.length() < 3.0:
					break
				var yaw := atan2(-d.x, -d.y)
				p.cam_yaw = yaw
				main.rig.yaw = lerp_angle(main.rig.yaw, yaw, 0.08)
				p.autopilot = {"move": Vector2(0, -1), "sprint": true}
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				var ms := (now - last) / 1000.0
				last = now
				t_leg += ms / 1000.0
				times.append(ms)
				phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				if ms > HITCH_MS:
					worst.append([ms, leg[0], p.global_position.round(), p.state])
			if t_leg >= 14.0:
				# Atascada: salta al siguiente punto.
				p.teleport(target + Vector3(0, 1.0, 0), p.facing)
				main.world.set_focus(target)
				await get_tree().process_frame
				last = Time.get_ticks_usec()
		main.player.autopilot = null
		var n := times.size()
		if n == 0:
			continue
		all.append_array(times)
		print("perf %-8s %s  fisica %5.2f ms  gpu %5.2f ms" % [leg[0], _stats(times), phys / n, gpu / n])
	print("perf total    ", _stats(all))
	worst.sort_custom(func(a, b): return a[0] > b[0])
	for w in worst.slice(0, 8):
		print("  tirón %6.1f ms  %-8s %s %s" % w)
	get_tree().quit()


func _stats(times: Array[float]) -> String:
	var s := times.duplicate()
	s.sort()
	var n := s.size()
	var total := 0.0
	var hitches := 0
	for t in s:
		total += t
		if t > HITCH_MS:
			hitches += 1
	return "%6.1f fps  p99 %5.1f ms  max %6.1f ms  tirones %d/%d" % [n / (total / 1000.0), s[mini(n - 1, int(n * 0.99))], s[n - 1], hitches, n]


## Cuántos nodos procesan cada fotograma, por script.
func _census() -> void:
	var count := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.is_processing() or n.is_physics_processing():
			var k: String = n.get_script().resource_path.get_file() if n.get_script() else n.get_class()
			count[k] = count.get(k, 0) + 1
	var keys := count.keys()
	keys.sort_custom(func(a, b): return count[a] > count[b])
	print("perf nodos con _process: ", ", ".join(keys.map(func(k): return "%s x%d" % [k, count[k]])))


## IB_OFF=avatar,npc,pet,animals,critters,traffic,hud,gameplay,flora,wind,fx: apaga el
## _process de esos scripts para medir cuánto cuestan.
func _switch_off() -> void:
	if OS.has_environment("IB_NOHUD"):
		main.hud.visible = false
		for c in main.hud.get_children():
			if c is CanvasItem:
				c.visible = false
	var off := OS.get_environment("IB_OFF").split(",", false)
	if off.is_empty():
		return
	var stack: Array[Node] = [get_tree().root]
	var n_off := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.get_script() == null or n == main.player or n == self:
			continue
		var f: String = n.get_script().resource_path.get_file().get_basename()
		if f.replace("_", "") in off or f in off:
			n.set_process(false)
			n.set_physics_process(false)
			n_off += 1
	print("perf apagados: ", n_off, " nodos (", ",".join(off), ")")
