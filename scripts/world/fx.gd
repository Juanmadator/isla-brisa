class_name Fx
extends RefCounted
## Efectos de partículas sencillos: chispitas, polvo, salpicaduras y rayos de luz.

static var _puff_mesh: SphereMesh
static var _spark_mesh: QuadMesh


static func _puff() -> SphereMesh:
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = 0.5
		_puff_mesh.height = 1.0
		_puff_mesh.radial_segments = 8
		_puff_mesh.rings = 4
	return _puff_mesh


static func _particle_material(color: Color, unshaded := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.disable_receive_shadows = true
	return m


static func _fade_ramp(color: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, 0.0))
	g.add_point(0.15, color)
	g.set_color(g.get_point_count() - 1, Color(color.r, color.g, color.b, 0.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _scale_curve(a: float, b: float) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Chispitas continuas alrededor de un objeto.
static func sparkles(color: Color, amount := 8, radius := 0.8) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.4
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3.UP
	pm.spread = 30.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _fade_ramp(Color(color.r, color.g, color.b, 1.0))
	pm.scale_curve = _scale_curve(0.3, 1.0)
	p.process_material = pm
	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.09, 0.09)
	var q: QuadMesh = _spark_mesh.duplicate()
	var m := _particle_material(Color(1, 1, 1))
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Ráfaga única que se borra sola.
static func burst(parent: Node, pos: Vector3, color: Color, amount: int, speed: float, size: float, life := 0.6, up := 0.4, gravity := -2.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3(0, up, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = size * 0.6
	pm.scale_max = size
	pm.scale_curve = _scale_curve(0.6, 1.0)
	pm.color_ramp = _fade_ramp(color)
	p.process_material = pm
	var mesh: SphereMesh = _puff().duplicate()
	mesh.material = _particle_material(Color(1, 1, 1), false)
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func dust(parent: Node, pos: Vector3, strength := 1.0) -> void:
	burst(parent, pos + Vector3(0, 0.1, 0), Color(0.93, 0.88, 0.76, 0.7), int(6 * strength) + 2, 1.6 * strength, 0.35, 0.55, 0.25, 0.4)


static func splash(parent: Node, pos: Vector3, strength := 1.0) -> void:
	burst(parent, pos, Color(0.9, 0.97, 1.0, 0.85), int(14 * strength), 4.5 * strength, 0.22, 0.7, 1.0, -12.0)


## Rayos de luz giratorios (para la escena de descubrimiento).
static func rays(color := Color(1.0, 0.85, 0.45), size := 3.2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rays.gdshader")
	m.set_shader_parameter("color", color)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func clear_cache() -> void:
	_puff_mesh = null
	_spark_mesh = null
