class_name Ribbon
extends MeshInstance3D
## Cinta que sigue una lista de puntos y siempre mira a la cámara (estelas de viento).

var points: Array[Vector3] = []
var max_points := 26
var width := 0.06
var color := Color(1, 1, 1, 0.75)

var _im := ImmediateMesh.new()
static var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.vertex_color_use_as_albedo = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.disable_receive_shadows = true
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 200.0


func push(p: Vector3) -> void:
	points.push_front(p)
	while points.size() > max_points:
		points.pop_back()


func shrink() -> void:
	if not points.is_empty():
		points.pop_back()


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	if points.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := points.size()
	for i in n:
		var p := points[i]
		var dir := (points[i - 1] - p) if i > 0 else (p - points[i + 1])
		var to_cam := (cp - p).normalized()
		var side := dir.cross(to_cam)
		if side.length_squared() < 1e-8:
			side = Vector3.UP
		var t := float(i) / (n - 1)
		var w := width * sin(PI * clampf(t * 1.1 + 0.05, 0.0, 1.0))
		side = side.normalized() * w
		var c := Color(color.r, color.g, color.b, color.a * (1.0 - t))
		_im.surface_set_color(c)
		_im.surface_add_vertex(p + side)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - side)
	_im.surface_end()


static func clear_cache() -> void:
	_mat = null
