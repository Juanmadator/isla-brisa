extends Node
## Tráiler del juego (25 s como máximo): cortes rápidos con cámara de cine, rótulos, bandas y fundidos.
## Se graba con el modo Movie Maker de Godot (fotograma a fotograma), a 2560x1440 para luego
## reducirlo a 1080p (más nítido):
##   Godot --path . --write-movie captures/trailer/trailer.avi --fixed-fps 30 --resolution 2560x1440 -- --ib-trailer
## y luego `python tools/make_trailer.py` le pone la música y lo convierte a MP4.
## Para probar planos sueltos sin grabar: -- --ib-trailer --shots=3,4

const SHOTS := ["_s_island", "_s_run", "_s_climb", "_s_glide", "_s_fish", "_s_pet", "_s_night", "_s_beacon", "_s_title"]

var main
var cam: Camera3D
var attrs: CameraAttributesPractical
var layer: CanvasLayer
var fade: ColorRect
var title: Label
var subtitle: Label
var _text_tw: Tween
var pl: Places
var p: Player
var gp: Gameplay


func _ready() -> void:
	SaveGame.data["started"] = true
	main.state = "trailer"
	main.hud.visible = false
	main.rig.process_mode = Node.PROCESS_MODE_DISABLED
	pl = main.world.places
	p = main.player
	gp = main.gameplay
	gp.skip_showcase = true
	gp.locked = true
	main.world.sky.running = false
	# Nitidez: MSAA en lugar del suavizado por pantalla (que emborrona un poco).
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	get_viewport().msaa_3d = Viewport.MSAA_4X
	Audio.set_ambience({"sea": 0.5, "wind": 0.4, "birds": 0.4})
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 3500.0
	attrs = CameraAttributesPractical.new()
	cam.attributes = attrs
	add_child(cam)
	cam.make_current()
	_build_overlay()
	p.visible = true
	p.debug_infinite_stamina = true
	for id in ["pet_dog", "pet_fox", "outfit_flowers", "hat_straw"]:
		SaveGame.give(id)
	SaveGame.equip("pet", "pet_dog")
	SaveGame.set_flag("has_glider")
	SaveGame.set_flag("has_rod")
	gp.apply_progress()
	main.apply_looks()
	var shots := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			for n in a.substr(8).split(","):
				shots.append(int(n))
	for i in SHOTS.size():
		if shots.is_empty() or (i + 1) in shots:
			await call(SHOTS[i])
	get_tree().quit()


# --- Rótulos, bandas y fundidos ------------------------------------------------------------

func _build_overlay() -> void:
	layer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var root := UiKit.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 0.885
		bar.anchor_bottom = 0.115 if top else 1.0
		root.add_child(bar)
	title = UiKit.label("", 104, UiKit.C_WHITE, 600, 10)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.16, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.anchor_top = 0.34
	title.anchor_bottom = 0.5
	root.add_child(title)
	subtitle = UiKit.label("", 40, UiKit.C_WHITE, 500, 8)
	subtitle.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.16, 0.8))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_right = 1.0
	subtitle.anchor_top = 0.74
	subtitle.anchor_bottom = 0.84
	root.add_child(subtitle)
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	fade = ColorRect.new()
	fade.color = Color.BLACK
	UiKit.full_rect(fade)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)


func _caption(text: String, dur: float, big := false) -> void:
	if _text_tw:
		_text_tw.kill()
	var l := title if big else subtitle
	(subtitle if big else title).modulate.a = 0.0
	l.text = text
	l.modulate.a = 0.0
	_text_tw = create_tween()
	_text_tw.tween_property(l, "modulate:a", 1.0, 0.35)
	_text_tw.tween_interval(maxf(dur - 0.75, 0.1))
	_text_tw.tween_property(l, "modulate:a", 0.0, 0.4)


func _fade(to: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", to, secs)
	await tw.finished


func _hour(h: float) -> void:
	main.world.sky.hour = h
	main.world.sky.apply()


## Mantiene la escena `secs` segundos: mueve la cámara con `move(k)` (k de 0 a 1) y la hierba
## y la vida siguen a `focus` (o a Lía).
func _hold(secs: float, move: Callable, focus: Callable = Callable()) -> void:
	var t := 0.0
	while t < secs:
		move.call(t / secs)
		var f: Vector3 = focus.call() if focus.is_valid() else p.global_position
		main.world.set_focus(f)
		await get_tree().process_frame
		t += get_process_delta_time()


## Corte: negro breve mientras se prepara el siguiente plano (`setup`), y vuelta a la imagen.
func _cut(setup: Callable, settle := 0.08) -> void:
	await _fade(1.0, 0.12)
	setup.call()
	main.world.flora.warm_up()
	await _hold(settle, func(_k: float) -> void: pass)
	_fade(0.0, 0.15)


static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


## Coloca la cámara; si entre el punto mirado y la cámara hay una pared, tejado o roca,
## la acerca hasta delante del obstáculo (como un brazo con muelle).
func _place_cam(pos: Vector3, look: Vector3) -> void:
	var dir := pos - look
	if dir.length() > 0.5:
		var q := PhysicsRayQueryParameters3D.create(look + dir.normalized() * 0.4, pos)
		q.exclude = [p.get_rid()]
		var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			pos = (hit["position"] as Vector3) - dir.normalized() * 0.35
	pos.y = maxf(pos.y, main.world.island.height_at(pos.x, pos.z) + 0.6)
	cam.global_position = pos
	if pos.distance_to(look) > 0.01:
		cam.look_at(look)


func _dof(dist: float) -> void:
	attrs.dof_blur_far_enabled = dist > 0.0
	attrs.dof_blur_far_distance = maxf(dist, 1.0)
	attrs.dof_blur_far_transition = maxf(dist, 1.0) * 1.5
	attrs.dof_blur_amount = 0.03


func _ground(q: Vector2, lift := 0.0) -> Vector3:
	return main.world.island.ground(q, lift)


func _walk(yaw: float, sprint := false, jump := false, amount := 1.0) -> void:
	p.cam_yaw = yaw
	p.autopilot = {"move": Vector2(0, -amount), "sprint": sprint, "jump": jump}


func _stop() -> void:
	p.autopilot = {"move": Vector2.ZERO}


func _yaw_to(a: Vector3, b: Vector3) -> float:
	return atan2(-(b.x - a.x), -(b.z - a.z))


static func _fwd(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


# --- Planos ---------------------------------------------------------------------------------

## 1. Amanecer: la isla aparece en el mar (3 s).
func _s_island() -> void:
	_hour(6.7)
	_dof(0.0)
	p.teleport(pl.anchor("spawn"), PI)
	_stop()
	_place_cam(Vector3(-30, 55, 470), Vector3(0, 40, 0))
	main.world.flora.warm_up()
	await _hold(0.1, func(_k: float) -> void: pass)
	_fade(0.0, 0.6)
	_caption("Una isla donde el viento se ha detenido...", 2.5)
	await _hold(2.4, func(k: float) -> void:
		var e := _ease(k)
		_place_cam(Vector3(-30, 55, 470).lerp(Vector3(0, 48, 360), e), Vector3(0, 42, 0)),
		func() -> Vector3: return Vector3(0, 0, 250))


## 2. Correr por la hierba alta con Canela (2,5 s).
func _s_run() -> void:
	var yaw := -0.6
	await _cut(func() -> void:
		_hour(10.5)
		_dof(14.0)
		p.teleport(_ground(Vector2(40, 60), 0.3), yaw)
		gp.pet.snap_to_player()
		_walk(yaw, true))
	_caption("Explora cada rincón", 2.0)
	await _hold(2.0, func(k: float) -> void:
		var pp := p.global_position
		var f := _fwd(yaw)
		var side := f.cross(Vector3.UP)
		_place_cam(pp + side * (3.0 - k * 0.6) + f * (2.0 + k) + Vector3(0, 1.0, 0), pp + Vector3(0, 0.8, 0) - f * 1.2))


## 3. Lanzar el gancho y trepar por la cuerda (3 s).
func _s_climb() -> void:
	var needle: Vector3 = pl.anchor("needle")
	var to_n := Vector3.ZERO
	await _cut(func() -> void:
		_hour(14.5)
		_dof(0.0)
		var start := needle + Vector3(-3.3, 0, 0)
		start.y = main.world.island.height_at(start.x, start.z) + 0.2
		to_n = Vector3(needle.x - start.x, 0, needle.z - start.z).normalized()
		p.teleport(start, _yaw_to(start, needle))
		_walk(_yaw_to(start, needle)), 0.08)
	_caption("Escala con gancho y cuerda", 2.8)
	var side := to_n.cross(Vector3.UP)
	await _hold(2.8, func(k: float) -> void:
		if p.state == "climb":
			_walk(_yaw_to(p.global_position, needle), false, false, 0.8)
		var pp := p.global_position
		# Desde fuera y algo por encima: la base de la roca es más ancha y taparía un plano bajo.
		_place_cam(pp - to_n * (6.5 + k * 1.5) + side * (3.5 - k) + Vector3(0, 2.6 + k * 0.6, 0), pp + Vector3(0, 1.2, 0)))


## 4. Saltar del Peñón y planear hacia el islote (3 s).
func _s_glide() -> void:
	var pen: Vector3 = pl.anchor("penon")
	var islet: Vector3 = pl.anchor("faro_islet")
	var yaw := _yaw_to(pen, islet)
	await _cut(func() -> void:
		_hour(16.3)
		_dof(0.0)
		p.teleport(pen + _fwd(yaw) * 14.0 + Vector3(0, 1.0, 0), yaw)
		_walk(yaw, false, true), 0.1)
	_walk(yaw)
	_caption("Planea sobre el mar", 2.8)
	await _hold(2.8, func(k: float) -> void:
		if p.state == "air":
			_walk(yaw, false, int(k * 90) % 6 < 2)
		var pp := p.global_position
		var f := _fwd(yaw)
		var side := f.cross(Vector3.UP)
		var e := _ease(k)
		_place_cam(pp - f * (5.0 + e * 5.0) + side * (2.5 + e * 5.0) + Vector3(0, 1.2 + e * 1.5, 0), pp + f * 5.0 + Vector3(0, 0.5, 0)))


## 5. Pescar en el muelle al atardecer y sacar una dorada (3 s).
func _s_fish() -> void:
	var f: Fishing = gp.fishing
	await _cut(func() -> void:
		_hour(18.3)
		_dof(0.0)
		p.teleport(pl.anchor("spawn") + Vector3(0, 0.2, 0), PI)
		_stop()
		gp.pet.snap_to_player(), 0.15)
	f.auto_input = {}
	gp.start_fishing()
	_caption("Pesca, colecciona y gana conchas", 2.8)
	await _hold(2.8, func(k: float) -> void:
		if f.phase == "wait" and k > 0.3:
			f._wait = 0.0
			f._nibbles = 0
		if f.phase == "bite":
			f.fish_id = "fish_bream"
			f.auto_input = {"press": true}
		elif f.phase == "reel":
			f.progress = maxf(f.progress, 0.85)
			f.auto_input = {"hold": true}
		var pp := p.global_position
		var a := PI * 0.5 + 0.35 - k * 0.25
		_place_cam(pp + Vector3(sin(a) * 4.0, 1.35, cos(a) * 4.0), pp + Vector3(0, 1.2, 1.2)))
	f.auto_input = null
	f.stop()


## 6. Ropa nueva y una zorrita por el pueblo (2,5 s).
func _s_pet() -> void:
	var v: Vector3 = pl.anchor("village")
	await _cut(func() -> void:
		_hour(12.5)
		_dof(12.0)
		SaveGame.equip("outfit", "outfit_flowers")
		SaveGame.equip("hat", "hat_straw")
		SaveGame.equip("pet", "pet_fox")
		main.apply_looks()
		var start := _ground(Vector2(v.x - 12, v.z + 14), 0.2)
		p.teleport(start, _yaw_to(start, v))
		gp.pet.snap_to_player()
		_walk(_yaw_to(start, v), false, false, 0.55), 0.12)
	_caption("Adopta una mascota y viste a tu manera", 2.1)
	await _hold(2.1, func(k: float) -> void:
		var pp := p.global_position
		var f := _fwd(p.facing)
		var side := f.cross(Vector3.UP)
		_place_cam(pp + f * (3.4 - k * 0.5) + side * 1.4 + Vector3(0, 1.3, 0), pp + Vector3(0, 0.7, 0)))
	_stop()


## 7. La noche en el pueblo: ventanas, farolas y luciérnagas (2,5 s).
func _s_night() -> void:
	var v: Vector3 = pl.anchor("village")
	await _cut(func() -> void:
		_hour(22.3)
		_dof(0.0)
		var np := _ground(Vector2(v.x + 3, v.z + 7), 0.2)
		p.teleport(np, _yaw_to(np, v))
		_stop()
		gp.pet.snap_to_player(), 0.12)
	await _hold(2.2, func(k: float) -> void:
		var a := 0.75 + _ease(k) * 0.45
		_place_cam(v + Vector3(sin(a) * 13.0, 3.2 + k * 0.8, cos(a) * 13.0), v + Vector3(0, 1.6, 0)))


## 8. Un Faro del Viento se enciende (3 s).
func _s_beacon() -> void:
	var b: Dictionary = pl.beacons["faro_cliff"]
	var root: Node3D = b["root"]
	var top: Vector3 = root.global_position + (b["top"] as Vector3)
	await _cut(func() -> void:
		_hour(19.3)
		_dof(0.0)
		var altar: Vector3 = (b["altar"] as Node3D).global_position
		p.teleport(altar + (altar - root.global_position).normalized() * 1.5 + Vector3(0, 0.3, 0), _yaw_to(altar, root.global_position) + PI)
		_stop()
		gp._set_beacon_visual("faro_cliff", false, false), 0.1)
	_caption("Enciende los Faros del Viento", 2.7)
	var lit := {"done": false}
	await _hold(2.7, func(k: float) -> void:
		if k > 0.12 and not lit["done"]:
			lit["done"] = true
			gp._set_beacon_visual("faro_cliff", true, true)
			Audio.play("beacon")
			gp.wind = 1.0
		var a := 1.0 + k * 0.5
		var d := 24.0 - k * 4.0
		_place_cam(top + Vector3(sin(a) * d, -5.0 + k * 5.0, cos(a) * d), top + Vector3(0, -2.5 + k * 2.5, 0)),
		func() -> Vector3: return root.global_position)


## 9. Título sobre la isla al atardecer (3,5 s).
func _s_title() -> void:
	await _cut(func() -> void:
		_hour(18.0)
		_dof(0.0)
		_place_cam(Vector3(160, 95, 330), Vector3(0, 35, 0)), 0.1)
	_caption("Isla Brisa", 3.1, true)
	var sub_tw := create_tween()
	subtitle.text = "Una aventura que trae el viento"
	subtitle.modulate.a = 0.0
	sub_tw.tween_interval(0.6)
	sub_tw.tween_property(subtitle, "modulate:a", 1.0, 0.5)
	await _hold(2.6, func(k: float) -> void:
		_place_cam(Vector3(160, 95, 330).lerp(Vector3(125, 125, 430), _ease(k)), Vector3(0, 35, 0)),
		func() -> Vector3: return Vector3(0, 0, 150))
	await _fade(1.0, 0.5)
