extends Node
## Flujo del juego: título, partida, diálogos, menús, escenas de los faros y final.

var world: World
var player: Player
var rig: CamRig
var gameplay: Gameplay
var hud: Hud
var menus: Menus
var title_cam: Camera3D
var cut_cam: Camera3D
var state := "boot"

var _title_t := 0.0
var _autosave := 30.0
var _cut := {}
var _low_warned := false
var _was_state := ""
var _show := {}
var _dlg_cam := false
var _last_step := {}
var _dof: CameraAttributesPractical
var _dlg_shot := {}
var _fill_light: OmniLight3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if Array(args).any(func(a: String) -> bool: return a.begins_with("--ib-")):
		get_tree().create_timer(240.0).timeout.connect(func() -> void:
			printerr("TIEMPO AGOTADO")
			get_tree().quit(2))
	for tool in [["--ib-look", "res://tools/look.gd"], ["--ib-move", "res://tools/move_test.gd"], ["--ib-clip", "res://tools/clip.gd"]]:
		if tool[0] in args:
			add_child(load(tool[1]).new())
			return
	if "--ib-test" in args or "--ib-capture" in args or "--ib-items" in args or "--ib-trailer" in args or "--ib-perf" in args:
		SaveGame.persist = false
		SaveGame.load_game()
	SaveGame.apply_settings()
	_build()
	if "--ib-test" in args:
		var t: Node = load("res://scripts/tests/selftest.gd").new()
		t.main = self
		add_child(t)
		return
	if "--ib-items" in args:
		var it: Node = load("res://tools/items_shot.gd").new()
		it.main = self
		add_child(it)
		return
	if "--ib-trailer" in args:
		var tr: Node = load("res://tools/trailer.gd").new()
		tr.main = self
		add_child(tr)
		return
	if "--ib-perf" in args:
		var pf: Node = load("res://tools/perf.gd").new()
		pf.main = self
		add_child(pf)
		return
	if "--ib-capture" in args:
		var c: Node = load("res://scripts/tests/capture.gd").new()
		c.main = self
		add_child(c)
		return
	go_title()


func _build() -> void:
	world = World.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.build()
	player = Player.new()
	player.name = "Player"
	player.island = world.island
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.position = world.places.anchor("spawn")
	rig = CamRig.new()
	rig.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(rig)
	rig.attach(player)
	Npc.game_cam = rig.cam
	rig.sensitivity = 0.0032 * float(SaveGame.setting("sensitivity"))
	rig.invert_y = bool(SaveGame.setting("invert_y"))
	world.sky.sun.shadow_enabled = bool(SaveGame.setting("shadows"))
	world.set_quality(int(SaveGame.setting("quality")))
	gameplay = Gameplay.new()
	gameplay.name = "Gameplay"
	gameplay.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(gameplay)
	gameplay.setup(world, player)
	hud = Hud.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	hud.main = self
	hud.build()
	hud.dialogue.line_started.connect(func(who: String) -> void: _speaker = who)
	menus = Menus.new()
	menus.process_mode = Node.PROCESS_MODE_ALWAYS
	menus.main = self
	add_child(menus)
	menus.map_tex = ImageTexture.create_from_image(world.island.map_image(1.25))
	title_cam = Camera3D.new()
	title_cam.fov = 60
	title_cam.far = 3000
	add_child(title_cam)
	cut_cam = Camera3D.new()
	cut_cam.fov = 60
	cut_cam.far = 3000
	add_child(cut_cam)
	# Luz de relleno que acompaña a la cámara en los primeros planos.
	_fill_light = OmniLight3D.new()
	_fill_light.light_energy = 1.1
	_fill_light.omni_range = 9.0
	_fill_light.light_color = Color(1.0, 0.96, 0.9)
	_fill_light.shadow_enabled = false
	_fill_light.visible = false
	_fill_light.position = Vector3(0.6, 0.4, 0)
	cut_cam.add_child(_fill_light)
	_dof = CameraAttributesPractical.new()
	_dof.dof_blur_far_enabled = true
	_dof.dof_blur_far_distance = 6.0
	_dof.dof_blur_far_transition = 6.0
	_dof.dof_blur_amount = 0.08
	# Señales
	_connect_gameplay()
	player.jumped.connect(func() -> void: Audio.play("jump", 0.08, -5.0))
	player.landed.connect(func(heavy: bool) -> void:
		Audio.play("land_heavy" if heavy else "land", 0.08, -3.0)
		player.avatar.squash(-0.5 if heavy else -0.22)
		player.avatar.impact(1.0 if heavy else 0.55)
		Fx.dust(world, player.global_position, 1.6 if heavy else 0.8)
		if heavy:
			rig.shake = 0.6)
	player.splashed.connect(func() -> void:
		Audio.play("splash", 0.1)
		Fx.splash(world, Vector3(player.global_position.x, player.water_surface(), player.global_position.z), 1.0))
	player.glide_started.connect(func() -> void: Audio.play("glide_open", 0.05))
	player.glide_ended.connect(func() -> void: Audio.play("glide_close", 0.05, -3.0))
	player.climb_grab.connect(func() -> void: Audio.play("climb", 0.1))
	player.step.connect(_on_step)
	player.stamina_empty.connect(func() -> void: Audio.play("stamina_low", 0.0, -2.0))
	player.exhausted_in_water.connect(_on_drown)
	apply_looks()


func _connect_gameplay() -> void:
	gameplay.say.connect(_on_say)
	gameplay.toast.connect(func(t: String, i: String) -> void: hud.show_toast(t, i))
	gameplay.banner.connect(func(t: String, s: String) -> void: hud.show_banner(t, s))
	gameplay.open_shop.connect(func(id: String) -> void: _open_menu("shop:" + id))
	gameplay.beacon_cutscene.connect(_beacon_cutscene)
	gameplay.ending_requested.connect(_ending)
	gameplay.showcase.connect(_on_showcase)
	gameplay.stamina_upgraded.connect(func() -> void: Audio.play("stamina_up", 0.0, -3.0))


# --- Estados ------------------------------------------------------------------------------

func go_title() -> void:
	state = "title"
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	title_cam.make_current()
	hud.set_gameplay_visible(false)
	hud.dialogue.visible = false
	world.sky.hour = 17.2
	world.sky.running = false
	world.sky.apply()
	player.visible = false
	player.locked = true
	gameplay.locked = true
	Audio.play_music("title")
	Audio.set_ambience({"sea": 0.6, "wind": 0.5})
	menus.show_title()


func start_game(new_game: bool) -> void:
	menus.close()
	hud.fade.color.a = 1.0
	if new_game:
		SaveGame.new_game()
		_reset_world()
		player.teleport(world.places.anchor("spawn"), world.places.yaws.get("spawn", PI))
		world.sky.hour = 8.5
	else:
		var p: Array = SaveGame.data["pos"]
		var pos := Vector3(p[0], p[1], p[2])
		if pos == Vector3.ZERO:
			pos = world.places.anchor("spawn")
		player.teleport(pos + Vector3(0, 0.3, 0), float(SaveGame.data.get("yaw", 0.0)))
		world.sky.hour = float(SaveGame.data.get("hour", 8.0))
	SaveGame.data["started"] = true
	gameplay.apply_progress()
	player.refill_stamina()
	player.visible = true
	player.locked = false
	gameplay.locked = false
	world.sky.running = true
	world.set_focus(player.global_position)
	world.flora.warm_up()
	rig.cam.make_current()
	rig.look_dir(player.facing, -0.22)
	hud.set_gameplay_visible(true)
	hud.fade_to(0.0, 1.2)
	state = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_autosave = 30.0
	if not SaveGame.flag("intro_done"):
		await get_tree().create_timer(1.3).timeout
		if state == "play":
			gameplay.talk("tomeu")


## Tras "Nueva partida" hay que volver a crear los objetos del mundo recogibles.
func _reset_world() -> void:
	gameplay.queue_free()
	gameplay = Gameplay.new()
	gameplay.name = "Gameplay2"
	gameplay.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(gameplay)
	gameplay.setup(world, player)
	_connect_gameplay()
	for id in Catalog.BEACONS:
		gameplay._set_beacon_visual(id, false, false)
	apply_looks()


func resume() -> void:
	menus.close()
	get_tree().paused = false
	state = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	gameplay.locked = false
	player.locked = false
	Audio.play("ui_close", 0.0, -4.0)


func _open_menu(kind: String) -> void:
	state = "menu"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play("ui_open", 0.0, -4.0)
	if kind.begins_with("shop:"):
		menus.show_shop(kind.substr(5))
	else:
		menus.show_pause(kind)


func save_and_title() -> void:
	_store_position()
	SaveGame.save_game()
	menus.close()
	go_title()


func quit_game() -> void:
	if state == "play" or state == "menu":
		_store_position()
	SaveGame.save_game()
	get_tree().quit()


func _store_position() -> void:
	var p := player.global_position
	if player.state in ["ground"]:
		p = player.global_position
	else:
		p = player.last_safe
	SaveGame.data["pos"] = [p.x, p.y, p.z]
	SaveGame.data["yaw"] = player.facing
	SaveGame.data["hour"] = world.sky.hour


func apply_looks() -> void:
	var eq: Dictionary = SaveGame.data["equipped"]
	var gl := Catalog.glider_for(eq)
	player.set_avatar_look(Catalog.look_for(eq), gl[0], gl[1])
	if gameplay:
		gameplay.refresh_pet()


# --- Diálogos ---------------------------------------------------------------------------------

func _on_say(lines: Array, on_done: Callable) -> void:
	if lines.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	state = "dialog"
	player.locked = true
	gameplay.locked = true
	_dlg_shot = {}
	_dlg_cam = gameplay.talking_npc != null
	if _dlg_cam:
		if get_viewport().get_camera_3d() != cut_cam:
			cut_cam.global_transform = rig.cam.global_transform
			cut_cam.fov = rig.cam.fov
		cut_cam.attributes = _dof
		cut_cam.make_current()
		hud.set_gameplay_visible(false)
	hud.dialogue.open(lines, func() -> void:
		player.avatar.speaking = false
		player.avatar.listening = false
		if gameplay.talking_npc:
			gameplay.talking_npc.avatar.speaking = false
			gameplay.talking_npc.avatar.listening = false
			player.anim_override = ""
		player.locked = false
		gameplay.locked = false
		if _dlg_cam:
			_dlg_cam = false
			cut_cam.attributes = null
			rig.cam.make_current()
			hud.set_gameplay_visible(true)
		if state == "dialog":
			state = "play"
		if on_done.is_valid():
			on_done.call())


# --- Entrada ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	match state:
		"play":
			if event.is_action_pressed("pause"):
				_open_menu("map")
			elif event.is_action_pressed("map"):
				_open_menu("map")
			elif event.is_action_pressed("quests"):
				_open_menu("quests")
			elif event.is_action_pressed("hint"):
				hud.show_hint()
				Audio.play("hint", 0.0, -4.0)
			elif event.is_action_pressed("interact"):
				if gameplay.interact():
					get_viewport().set_input_as_handled()
			elif event.is_action_pressed("vehicle"):
				gameplay.toggle_bike()
			elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		"dialog":
			if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept") \
					or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
				hud.dialogue.advance()
				get_viewport().set_input_as_handled()
		"showcase":
			if hud.card_ready and (event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept") \
					or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)):
				_end_showcase()
				get_viewport().set_input_as_handled()
		"menu":
			if event.is_action_pressed("pause") or (event.is_action_pressed("map") and menus.kind == "pause"):
				resume()
				get_viewport().set_input_as_handled()
		"ending":
			pass


# --- Bucle ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	match state:
		"title":
			_title_t += delta
			var a := _title_t * 0.05
			var center := Vector3(10, 30, 60)
			title_cam.global_position = center + Vector3(sin(a) * 230.0, 90.0 + sin(_title_t * 0.1) * 10.0, cos(a) * 230.0)
			title_cam.look_at(center + Vector3(-60, 0, -40))
			world.set_focus(title_cam.global_position)
		"play", "dialog":
			_play_process(delta)
			if state == "dialog" and _dlg_cam:
				_dialog_cam_process(delta)
			_dialog_acting()
		"showcase":
			_showcase_process(delta)
		"cutscene", "ending":
			_cut_process(delta)


## Conversación: quien habla mueve la boca mientras se escribe su frase y gesticula; quien
## escucha asiente de vez en cuando.
var _speaker := ""


func _dialog_acting() -> void:
	var npc: Npc = gameplay.talking_npc
	var typing: bool = state == "dialog" and hud.dialogue.visible and hud.dialogue.is_typing()
	var lia_speaks := state == "dialog" and npc != null and _speaker == "Lía"
	player.avatar.speaking = lia_speaks and typing
	if npc:
		var npc_speaks := not lia_speaks and _speaker != ""
		npc.avatar.speaking = npc_speaks and typing
		npc.avatar.listening = lia_speaks
		player.avatar.listening = state == "dialog" and npc_speaks
		if state == "dialog":
			player.anim_override = "talk" if lia_speaks else ""
	elif player.avatar.listening or player.avatar.speaking:
		player.avatar.listening = false


func _play_process(delta: float) -> void:
	SaveGame.data["play_time"] = float(SaveGame.data.get("play_time", 0.0)) + delta
	# Sentada en un banco, el día corre: 24 horas en medio minuto.
	world.sky.time_scale = 40.0 if player.state == "sit" else 1.0
	world.set_focus(player.global_position)
	hud.update_hud(gameplay, player, rig.cam, world.sky, delta)
	_update_audio()
	_autosave -= delta
	if _autosave <= 0.0 and state == "play" and player.state == "ground":
		_autosave = 45.0
		_store_position()
		SaveGame.save_game()


func _update_audio() -> void:
	var pp := player.global_position
	var night := world.sky.night
	var to_village := Vector2(pp.x, pp.z).distance_to(Island.VILLAGE)
	if SaveGame.flag("ending_seen") and Vector2(pp.x, pp.z).distance_to(Island.MOUNT) < 40.0 and pp.y > 90.0:
		Audio.play_music("ending")
	elif night > 0.6:
		Audio.play_music("night")
	elif to_village < 70.0:
		Audio.play_music("village")
	else:
		Audio.play_music("day")
	var ground := world.island.height_at(pp.x, pp.z)
	var lake := Vector2(pp.x, pp.z).distance_to(Island.LAKE) < 70.0
	var sea := 0.0 if lake else clampf(1.0 - ground / 10.0, 0.0, 1.0) * clampf(1.0 - (pp.y - 2.0) / 40.0, 0.0, 1.0)
	var high := clampf((pp.y - 35.0) / 60.0, 0.0, 1.0)
	var wind := maxf(high, 0.85 if player.state == "glide" else 0.0) * (0.6 + gameplay.wind * 0.4) + 0.1
	Audio.set_ambience({
		"sea": sea * 0.9,
		"wind": wind,
		"birds": (1.0 - night) * (1.0 - high) * 0.7,
		"night": night * 0.8,
	})


func _on_step(biome: int) -> void:
	var pp := player.global_position
	var above := pp.y - world.island.height_at(pp.x, pp.z)
	var kind := "grass"
	var ground := world.island.height_at(pp.x, pp.z)
	if pp.y < player.water_surface() + 0.15 and ground < player.water_surface():
		kind = "water"
	elif above > 0.6:
		kind = "wood"
	elif biome == Island.Biome.SAND:
		kind = "sand"
	elif biome == Island.Biome.ROCK or biome == Island.Biome.SNOW:
		kind = "stone"
	# Variante al azar sin repetir la anterior, con tono y volumen ligeramente distintos.
	var last: int = _last_step.get(kind, 0)
	var v := randi_range(1, 6)
	if v == last:
		v = v % 6 + 1
	_last_step[kind] = v
	var spd := Vector2(player.velocity.x, player.velocity.z).length()
	var vol := -7.0 + randf_range(-1.5, 1.0) + (2.0 if spd > Player.RUN + 1.0 else 0.0) - (3.0 if spd < 4.0 else 0.0) - (5.0 if spd < 1.0 else 0.0)
	# Huellas en la arena (y en la tierra de los caminos, más suaves).
	if kind == "sand" or (biome == Island.Biome.PATH and kind == "grass"):
		Fx.footprint(world, player.last_step_pos, player.facing, player.last_step_side)
	vol += {"sand": 3.0, "wood": 3.0}.get(kind, 0.0)
	Audio.play("step_%s_%d" % [kind, v], 0.05, vol)
	if spd > Player.RUN + 1.0 and kind in ["sand", "grass", "stone"]:
		Fx.dust(world, player.last_step_pos, 0.45)
	elif spd > 3.0 and (kind == "sand" or biome == Island.Biome.PATH):
		Fx.dust(world, player.last_step_pos, 0.18)
	elif kind == "water":
		Fx.splash(world, pp + Vector3(0, 0.1, 0), 0.35)


func _on_drown() -> void:
	if state != "play" and state != "dialog":
		return
	state = "cutscene"
	_cut = {"kind": "drown", "t": 0.0}
	player.locked = true
	hud.fade_to(1.0, 0.6).tween_callback(func() -> void:
		player.respawn(player.last_safe)
		world.set_focus(player.global_position)
		world.flora.warm_up()
		hud.fade_to(0.0, 0.8)
		hud.show_toast("Lía se agotó nadando y volvió a la orilla", "")
		player.locked = false
		state = "play")


# --- Escenas ------------------------------------------------------------------------------------

func _beacon_cutscene(id: String, on_done: Callable) -> void:
	state = "cutscene"
	player.locked = true
	gameplay.locked = true
	var b: Dictionary = world.places.beacons[id]
	var root: Node3D = b["root"]
	var top: Vector3 = root.global_position + (b["top"] as Vector3)
	_cut = {"kind": "beacon", "t": 0.0, "dur": 5.5, "center": top, "on_done": on_done, "yaw": rig.yaw}
	cut_cam.make_current()
	hud.set_gameplay_visible(false)
	Audio.duck(8.0)


func _ending() -> void:
	state = "ending"
	player.locked = true
	gameplay.locked = true
	_cut = {"kind": "ending", "t": 0.0}
	cut_cam.make_current()
	hud.set_gameplay_visible(false)
	Audio.play_music("ending", 3.0)
	await get_tree().create_timer(6.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.show_ending()


func finish_ending() -> void:
	SaveGame.set_flag("ending_seen")
	SaveGame.save_game()
	menus.close()
	rig.cam.make_current()
	hud.set_gameplay_visible(true)
	player.locked = false
	gameplay.locked = false
	state = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_banner("Fin... ¿o no?", "Sigue explorando: quedan plumas, cofres y secretos")


func _cut_process(delta: float) -> void:
	world.set_focus(player.global_position)
	_cut["t"] = float(_cut.get("t", 0.0)) + delta
	var t: float = _cut["t"]
	match _cut.get("kind", ""):
		"beacon":
			var c: Vector3 = _cut["center"]
			var a: float = _cut["yaw"] + t * 0.35
			var dist := 22.0 - t * 1.2
			cut_cam.global_position = c + Vector3(sin(a) * dist, 2.0 + t * 1.2, cos(a) * dist)
			cut_cam.look_at(c + Vector3(0, 1.0, 0))
			if t >= _cut["dur"]:
				var cb: Callable = _cut["on_done"]
				_cut = {}
				rig.cam.make_current()
				hud.set_gameplay_visible(true)
				Audio.duck(0.0)
				player.locked = false
				gameplay.locked = false
				state = "play"
				if cb.is_valid():
					cb.call()
		"ending":
			var a := t * 0.06 + 0.4
			var center := Vector3(0, 40, 20)
			var r := 260.0 + t * 4.0
			cut_cam.global_position = center + Vector3(sin(a) * r, 110.0 + t * 1.5, cos(a) * r)
			cut_cam.look_at(Vector3(0, 30, -40))
	hud.update_hud(gameplay, player, rig.cam, world.sky, delta)


func _exit_tree() -> void:
	MeshKit.clear_cache()
	BodyKit.clear_cache()
	Fx.clear_cache()
	UiKit.clear_cache()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if state in ["play", "menu", "dialog"]:
			_store_position()
		SaveGame.save_game()
		MeshKit.clear_cache()
		BodyKit.clear_cache()
		Fx.clear_cache()
		UiKit.clear_cache()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "play" and SaveGame.persist:
		_open_menu("map")


# --- Primer encuentro y cámara de diálogo --------------------------------------------------

func _showcase_model(entry: String) -> Node3D:
	var n: Node3D
	match entry:
		"shell":
			n = Props.shell()
			n.scale = Vector3.ONE * 1.3
		"feather":
			n = Props.feather()
			n.scale = Vector3.ONE * 1.1
			n.position.y = -0.5
		"spark":
			n = Props.spark()
		"mushroom":
			n = Props.mushroom(true)
			n.scale = Vector3.ONE * 1.6
			n.position.y = -0.3
		"kite", "glider":
			var kite := Props.kite(Color(0.98, 0.95, 0.85), Color(0.95, 0.4, 0.35), 0.9)
			n = Node3D.new()
			n.add_child(kite)
		"letters":
			n = Node3D.new()
			for i in 3:
				var env := MeshKit.part(n, MeshKit.rounded_box(Vector3(0.42, 0.28, 0.03), 0.02, 1), MeshKit.mat(Color(0.98, 0.95, 0.85), 0.012), Vector3(i * 0.06 - 0.06, i * 0.05, i * 0.02), Vector3(0, 0, -8 + i * 8))
				MeshKit.part(env, MeshKit.cylinder(0.04, 0.04, 0.02, 10), MeshKit.mat(Color(0.85, 0.2, 0.2), 0.0), Vector3(0, 0, -0.02), Vector3(90, 0, 0))
		"rod":
			n = Fishing.rod_model()
			n.rotation_degrees = Vector3(0, 0, -50)
			n.position = Vector3(0.2, -0.6, 0)
		"parcel":
			n = Node3D.new()
			MeshKit.part(n, MeshKit.rounded_box(Vector3(0.5, 0.36, 0.4), 0.03, 2), MeshKit.mat(Color(0.8, 0.6, 0.4)), Vector3.ZERO)
			MeshKit.part(n, MeshKit.rounded_box(Vector3(0.52, 0.06, 0.42), 0.01, 1), MeshKit.mat(Color(0.95, 0.9, 0.75)), Vector3(0, 0.05, 0))
		"egg":
			n = Node3D.new()
			MeshKit.part(n, MeshKit.sphere(0.12, 14), MeshKit.mat(Color(0.98, 0.94, 0.86)), Vector3.ZERO, Vector3.ZERO, Vector3(0.85, 1.1, 0.85))
			n.scale = Vector3.ONE * 2.0
		"apple":
			n = gameplay._apple_node()
			n.scale = Vector3.ONE * 2.0
		"wool":
			n = Node3D.new()
			for k in 7:
				var a := TAU * k / 7.0
				MeshKit.part(n, MeshKit.blob(0.12, 1.0, 0.25, k, 12), MeshKit.surface_mat(Color(0.97, 0.95, 0.9), "cloth", 0.1), Vector3(cos(a) * 0.12, sin(k) * 0.05, sin(a) * 0.12))
			n.scale = Vector3.ONE * 1.6
		"flower":
			n = gameplay._flower_node(1)
			n.scale = Vector3.ONE * 1.6
			n.position.y = -0.4
		"bread":
			n = Node3D.new()
			MeshKit.part(n, MeshKit.blob(0.2, 0.6, 0.05, 1, 14), MeshKit.mat(Color(0.82, 0.55, 0.28)), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 1.7))
		"boat":
			n = Props.boat(true)
			n.scale = Vector3.ONE * 0.28
			n.position.y = -0.5
		"bike":
			n = Props.bicycle()
			n.scale = Vector3.ONE * 0.7
			n.position.y = -0.5
		"board":
			n = Props.noticeboard()
			n.scale = Vector3.ONE * 0.4
			n.position.y = -0.5
		"chest":
			var ch := Props.chest()
			n = Node3D.new()
			n.add_child(ch["root"])
			ch["root"].scale = Vector3.ONE * 0.6
			ch["root"].position.y = -0.25
			(ch["lid"] as Node3D).rotation.x = -1.6
		_:
			if entry.begins_with("fish_"):
				n = Fishing.fish_model(entry)
				n.scale = Vector3.ONE * 1.6
			else:
				n = Props.feather()
	return n


func _on_showcase(entry: String, mode: String, focus: Node3D, cb: Callable) -> void:
	var data: Array = Catalog.JOURNAL.get(entry, [entry, "", "star", ""])
	state = "showcase"
	player.locked = true
	gameplay.locked = true
	hud.set_gameplay_visible(false)
	hud.prompt_box.visible = false
	var pp := player.global_position
	var from := rig.cam.global_transform if get_viewport().get_camera_3d() != cut_cam else cut_cam.global_transform
	var to_pos: Vector3
	var look: Vector3
	var model: Node3D = null
	var rays: MeshInstance3D = null
	match mode:
		"item":
			var to_cam := rig.cam.global_position - pp
			to_cam.y = 0.0
			to_cam = to_cam.normalized() if to_cam.length() > 0.1 else Vector3(0, 0, 1)
			player.facing = atan2(-to_cam.x, -to_cam.z)
			player.anim_override = "hold_up"
			model = _showcase_model(entry)
			player.avatar.hold_point.add_child(model)
			model.add_child(Fx.sparkles(Color(1.0, 0.9, 0.5), 10, 0.5))
			rays = Fx.rays(Color(1.0, 0.85, 0.45), 3.4)
			world.add_child(rays)
			look = pp + Vector3(0, 1.3, 0)
			to_pos = _clear_shot(pp, look, (to_cam + to_cam.cross(Vector3.UP) * 0.12).normalized(), 3.6, 1.9, [])
			Audio.play("showcase")
		"creature":
			var fp := focus.global_position
			var d := pp - fp
			d.y = 0.0
			d = d.normalized() if d.length() > 0.1 else Vector3(0, 0, 1)
			focus.rotation.y = atan2(-d.x, -d.z)
			look = fp + Vector3(0, 0.2, 0)
			# De lado respecto a Lía, para que no tape a la criatura.
			to_pos = _clear_shot(fp, look, d.rotated(Vector3.UP, 1.25), 2.3, 1.0, [pp + Vector3(0, 0.5, 0), pp + Vector3(0, 1.3, 0)])
			rays = Fx.rays(Color(1.0, 0.8, 0.55), 2.2)
			world.add_child(rays)
			var tw := focus.create_tween()
			tw.tween_property(focus, "position:y", focus.position.y + 0.35, 0.18).set_ease(Tween.EASE_OUT)
			tw.tween_property(focus, "position:y", focus.position.y, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
			player.anim_override = "cheer"
			Audio.play("showcase")
			Audio.play("kitten", 0.05)
		"npc":
			var npc := focus as Npc
			var np := npc.global_position
			var hgt: float = 1.75 * float(npc.avatar.spec.get("height", 1.0))
			var d := pp - np
			d.y = 0.0
			d = d.normalized() if d.length() > 0.1 else Vector3(0, 0, 1)
			look = np + Vector3(0, hgt * 0.55, 0)
			to_pos = _clear_shot(np, look, d.rotated(Vector3.UP, 0.85), 2.6, hgt * 0.85, [pp + Vector3(0, 0.6, 0), pp + Vector3(0, 1.35, 0)])
			npc.avatar.rotation.y = atan2(-d.x, -d.z)
			npc._wave_t = 2.5
			Audio.play("meet")
	cut_cam.global_transform = from
	cut_cam.attributes = _dof
	_fill_light.visible = true
	_dof.dof_blur_far_distance = to_pos.distance_to(look) + 1.5
	cut_cam.make_current()
	hud.show_card(data[0], data[1], data[3], data[2])
	_show = {"cb": cb, "model": model, "rays": rays, "t": 0.0, "from": from, "to": to_pos, "look": look, "mode": mode, "focus": focus}


## Sitio para la cámara alrededor de `center` (a `dist` m y `height` m de altura) desde el que se
## vea `look` sin paredes ni rocas en medio, sin quedar bajo tierra y sin que ninguno de los
## puntos de `avoid` (Lía) tape el plano. Prueba ángulos cada vez más lejos de `pref_dir`.
func _clear_shot(center: Vector3, look: Vector3, pref_dir: Vector3, dist: float, height: float, avoid: Array) -> Vector3:
	var space := world.get_world_3d().direct_space_state
	var base := atan2(pref_dir.x, pref_dir.z)
	var fallback := center + Vector3(sin(base), 0, cos(base)) * dist + Vector3.UP * height
	for d_scale: float in [1.0, 0.75]:
		for off: float in [0.0, 0.45, -0.45, 0.9, -0.9, 1.35, -1.35, 1.9, -1.9, 2.5, -2.5, PI]:
			var a := base + off
			var pos := center + Vector3(sin(a), 0, cos(a)) * dist * d_scale + Vector3.UP * height
			var ground := world.island.height_at(pos.x, pos.z)
			if pos.y < ground + 0.6:
				pos.y = ground + 0.6
			if pos.y < world.island.water_level(pos.x, pos.z) + 0.3:
				continue
			var dir := (pos - look).normalized()
			var q := PhysicsRayQueryParameters3D.create(look + dir * 0.45, pos + dir * 0.3)
			q.exclude = [player.get_rid()]
			if not space.intersect_ray(q).is_empty():
				continue
			var blocked := false
			for p in avoid:
				var seg := pos - look
				var t := clampf((p - look).dot(seg) / seg.length_squared(), 0.0, 1.0)
				if (look + seg * t).distance_to(p) < 0.5:
					blocked = true
					break
			if not blocked:
				return pos
	return fallback


func _showcase_process(delta: float) -> void:
	world.set_focus(player.global_position)
	_show["t"] = float(_show["t"]) + delta
	var t: float = _show["t"]
	var k := 1.0 - pow(1.0 - clampf(t / 0.9, 0.0, 1.0), 3.0)
	var to: Vector3 = _show["to"]
	var look: Vector3 = _show["look"]
	# Pequeño travelling hacia delante mientras dura la escena.
	var dolly := (look - to).normalized() * minf(t * 0.08, 0.35)
	var target := Transform3D(Basis.looking_at(look - (to + dolly), Vector3.UP), to + dolly)
	var from: Transform3D = _show["from"]
	cut_cam.global_transform = from.interpolate_with(target, k)
	cut_cam.fov = lerpf(rig.cam.fov, 48.0, k)
	var model: Node3D = _show["model"]
	if model and is_instance_valid(model):
		model.rotate_y(delta * 1.6)
	var rays: MeshInstance3D = _show["rays"]
	if rays and is_instance_valid(rays):
		var center: Vector3 = player.avatar.hold_point.global_position if _show["mode"] == "item" else (_show["focus"] as Node3D).global_position + Vector3(0, 0.3, 0)
		rays.global_position = center + (center - cut_cam.global_position).normalized() * 0.4
		rays.scale = Vector3.ONE * clampf(t * 2.5, 0.0, 1.0)
	hud.update_hud(gameplay, player, rig.cam, world.sky, delta)


func _end_showcase() -> void:
	hud.hide_card()
	var model: Node3D = _show.get("model")
	if model and is_instance_valid(model):
		model.queue_free()
	var rays: MeshInstance3D = _show.get("rays")
	if rays and is_instance_valid(rays):
		rays.queue_free()
	var cb: Callable = _show.get("cb", Callable())
	var mode: String = _show.get("mode", "")
	_show = {}
	_fill_light.visible = false
	player.anim_override = ""
	player.locked = false
	gameplay.locked = false
	state = "play"
	if cb.is_valid():
		cb.call()
	# Si no ha empezado un diálogo (que usa su propia cámara), volver a la cámara normal.
	if state == "play":
		cut_cam.attributes = null
		rig.cam.make_current()
		hud.set_gameplay_visible(true)
	elif mode == "npc" and state == "dialog":
		pass


## Plano por encima del hombro de Lía mirando al vecino con el que habla.
func _dialog_cam_process(delta: float) -> void:
	var npc := gameplay.talking_npc
	if npc == null:
		return
	var np := npc.global_position
	var pp := player.global_position
	var d := np - pp
	d.y = 0.0
	d = d.normalized() if d.length() > 0.1 else Vector3(0, 0, -1)
	var side := d.cross(Vector3.UP)
	var hgt: float = 1.75 * float(npc.avatar.spec.get("height", 1.0))
	var pos := pp + Vector3(0, 1.75, 0) - d * 1.9 + side * 0.85
	var look := (np + Vector3(0, hgt * 0.78, 0)).lerp(pp + Vector3(0, 1.5, 0), 0.2)
	# Si detrás de Lía hay una pared, buscar otro sitio (una vez por diálogo).
	if not _dlg_shot.has(npc):
		var q := PhysicsRayQueryParameters3D.create(look, pos)
		q.exclude = [player.get_rid()]
		var clear := world.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		_dlg_shot = {npc: Vector3.INF if clear else _clear_shot(np, look, -d.rotated(Vector3.UP, -0.7), 3.2, hgt * 0.9, [pp + Vector3(0, 1.0, 0)])}
	if _dlg_shot[npc] != Vector3.INF:
		pos = _dlg_shot[npc]
	var target := Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	var k := 1.0 - exp(-5.0 * delta)
	cut_cam.global_transform = cut_cam.global_transform.interpolate_with(target, k)
	cut_cam.fov = lerpf(cut_cam.fov, 50.0, k)
	_dof.dof_blur_far_distance = pos.distance_to(np) + 2.0
