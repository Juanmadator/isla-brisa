class_name FittingRoom
extends SubViewportContainer
## Probador: Lía en 3D (con su propio mundo, luz y cámara) para ver la ropa, la paravela o la
## mascota antes de comprarla. Gira despacio de un lado a otro. Funciona con el juego en pausa.

var _vp: SubViewport
var _cam: Camera3D
var _turn: Node3D
var _avatar: Avatar
var _pet_model: Node3D


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(340, 460)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var root := Node3D.new()
	_vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.82)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.light_energy = 0.35
	root.add_child(fill)
	# Peana redonda bajo los pies.
	var base := MeshKit.part(root, MeshKit.cylinder(0.75, 0.8, 0.08, 32), MeshKit.mat(Color(0.93, 0.88, 0.78)), Vector3(0, -0.04, 0))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_turn = Node3D.new()
	root.add_child(_turn)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	root.add_child(_cam)
	_frame(false)


func _ready() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(_turn, "rotation:y", 0.55, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_turn, "rotation:y", -0.55, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _frame(wide: bool, with_pet := false) -> void:
	# Sin look_at: el probador se prepara antes de entrar en el árbol de escena.
	var pos := Vector3(0, 1.7, 7.2) if wide else (Vector3(0.25, 1.1, 5.4) if with_pet else Vector3(0, 1.15, 4.6))
	var target := Vector3(0, 1.45, 0) if wide else (Vector3(0.25, 0.8, 0) if with_pet else Vector3(0, 0.88, 0))
	_cam.transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


## Muestra a Lía con lo que lleva puesto (`eq`), cambiando lo de `try_id` si se indica.
func show_look(eq: Dictionary, try_id := "") -> void:
	var e := eq.duplicate()
	var slot := ""
	if Catalog.ITEMS.has(try_id):
		slot = Catalog.ITEMS[try_id][0]
		if slot != "special":
			e[slot] = try_id
	if _avatar == null:
		_avatar = Avatar.new()
		_avatar.process_mode = Node.PROCESS_MODE_ALWAYS
		_turn.add_child(_avatar)
		# El modelo mira hacia -Z: lo giramos para que mire a cámara.
		_avatar.rotation.y = PI
	var spec := {"backpack": true, "hair_style": "bob"}
	spec.merge(Catalog.look_for(e), true)
	_avatar.build(spec)
	var gl := Catalog.glider_for(e)
	_avatar.set_glider_colors(gl[0], gl[1])
	_avatar.state = "glide" if slot == "glider" else "idle"
	if _pet_model:
		_pet_model.queue_free()
		_pet_model = null
	var pet_spec = Catalog.pet_for(e)
	if pet_spec != null:
		_pet_model = Pet.build_model(pet_spec[0], pet_spec[2])
		_turn.add_child(_pet_model)
		if pet_spec[0] == "parrot":
			_pet_model.position = Vector3(-0.21, 1.08, 0.03)
			_pet_model.rotation.y = PI
		else:
			_pet_model.position = Vector3(0.6, 0, -0.15)
			_pet_model.rotation.y = PI - 0.45
			_pet_model.scale = Vector3.ONE * 1.1
	_frame(slot == "glider", pet_spec != null and pet_spec[0] != "parrot")
