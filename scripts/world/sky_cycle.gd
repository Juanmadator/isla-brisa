class_name SkyCycle
extends Node3D
## Ciclo de día y noche: sol/luna, colores del cielo, ambiente, niebla y uniformes globales.

const DAY_SECONDS := 20.0 * 60.0

## Paleta por hora: [hora, cénit, horizonte, luz, energía luz, ambiente, nubes luz, nubes sombra, noche]
const KEYS := [
	[0.0, Color(0.03, 0.06, 0.17), Color(0.1, 0.16, 0.32), Color(0.55, 0.66, 1.0), 0.32, Color(0.2, 0.27, 0.48), Color(0.3, 0.36, 0.55), Color(0.12, 0.16, 0.3), 1.0],
	[4.8, Color(0.05, 0.08, 0.2), Color(0.16, 0.2, 0.38), Color(0.55, 0.66, 1.0), 0.28, Color(0.22, 0.28, 0.48), Color(0.32, 0.36, 0.55), Color(0.14, 0.18, 0.32), 1.0],
	[6.0, Color(0.28, 0.38, 0.7), Color(1.0, 0.66, 0.5), Color(1.0, 0.7, 0.5), 0.55, Color(0.48, 0.45, 0.62), Color(1.0, 0.8, 0.72), Color(0.6, 0.5, 0.66), 0.3],
	[7.5, Color(0.25, 0.5, 0.88), Color(0.86, 0.86, 0.9), Color(1.0, 0.9, 0.78), 0.85, Color(0.55, 0.6, 0.78), Color(1.0, 0.97, 0.94), Color(0.7, 0.74, 0.86), 0.0],
	[12.0, Color(0.2, 0.5, 0.94), Color(0.7, 0.87, 0.99), Color(1.0, 0.98, 0.92), 0.95, Color(0.56, 0.63, 0.82), Color(1.0, 1.0, 1.0), Color(0.68, 0.76, 0.9), 0.0],
	[16.5, Color(0.22, 0.48, 0.9), Color(0.82, 0.86, 0.92), Color(1.0, 0.93, 0.8), 0.9, Color(0.56, 0.6, 0.78), Color(1.0, 0.97, 0.92), Color(0.7, 0.72, 0.85), 0.0],
	[18.2, Color(0.3, 0.32, 0.66), Color(1.0, 0.55, 0.38), Color(1.0, 0.6, 0.4), 0.7, Color(0.5, 0.44, 0.6), Color(1.0, 0.72, 0.6), Color(0.58, 0.44, 0.6), 0.15],
	[19.6, Color(0.08, 0.1, 0.28), Color(0.42, 0.3, 0.46), Color(0.6, 0.6, 0.95), 0.3, Color(0.26, 0.28, 0.48), Color(0.45, 0.38, 0.55), Color(0.2, 0.2, 0.36), 0.8],
	[21.0, Color(0.03, 0.06, 0.17), Color(0.1, 0.16, 0.32), Color(0.55, 0.66, 1.0), 0.32, Color(0.2, 0.27, 0.48), Color(0.3, 0.36, 0.55), Color(0.12, 0.16, 0.3), 1.0],
	[24.0, Color(0.03, 0.06, 0.17), Color(0.1, 0.16, 0.32), Color(0.55, 0.66, 1.0), 0.32, Color(0.2, 0.27, 0.48), Color(0.3, 0.36, 0.55), Color(0.12, 0.16, 0.3), 1.0],
]

var hour := 8.0
var running := true
var time_scale := 1.0
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var night := 0.0
var _cloud_time := 0.0

signal hour_changed(h: int)
## Ha amanecido un día nuevo (a las 6:00).
signal day_passed


func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Lineal a propósito: los colores del juego están ajustados para él (AgX y ACES los lavan).
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 160.0
	env.fog_depth_end = 1900.0
	env.fog_depth_curve = 1.3
	env.fog_density = 0.65
	env.fog_sky_affect = 0.0
	# Perspectiva aérea: lo lejano toma el color del cielo (profundidad, como en la realidad).
	env.fog_aerial_perspective = 0.35
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.6
	env.ssao_detail = 0.4
	env.ssao_light_affect = 0.0
	env.ssao_ao_channel_affect = 0.0
	# Luz rebotada en pantalla: los colores se contagian a lo que tienen cerca (hierba en las
	# paredes, tejados en los aleros) y las sombras dejan de ser planas.
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.9
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0
	# Bruma volumétrica muy ligera: rayos de sol entre los árboles y profundidad en el aire.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_albedo = Color(0.95, 0.97, 1.0)
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 1.5
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.03
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 0.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.0
	add_child(sun)
	apply()


func _process(delta: float) -> void:
	_cloud_time += delta
	sky_mat.set_shader_parameter("cloud_time", _cloud_time)
	RenderingServer.global_shader_parameter_set("cloud_offset", Vector2(_cloud_time * 2.2, _cloud_time * 0.9))
	RenderingServer.global_shader_parameter_set("cloud_shadow", clampf(1.0 - night * 1.5, 0.0, 1.0))
	if running:
		var before := int(hour)
		hour = fmod(hour + delta * 24.0 / DAY_SECONDS * time_scale, 24.0)
		if int(hour) != before:
			hour_changed.emit(int(hour))
			if int(hour) == 6:
				day_passed.emit()
		apply()


static func _lerp_key(a: Array, b: Array, t: float, i: int):
	if a[i] is Color:
		return (a[i] as Color).lerp(b[i], t)
	return lerpf(a[i], b[i], t)


func sample(h: float) -> Array:
	for k in KEYS.size() - 1:
		var a: Array = KEYS[k]
		var b: Array = KEYS[k + 1]
		if h >= a[0] and h <= b[0]:
			var t: float = (h - a[0]) / (b[0] - a[0])
			t = t * t * (3.0 - 2.0 * t)
			var out := []
			for i in a.size():
				out.append(_lerp_key(a, b, t, i))
			return out
	return KEYS[0]


func sun_direction(h: float) -> Vector3:
	var a := (h - 6.0) / 12.0 * PI
	return Vector3(cos(a), sin(a) * 0.92, 0.38).normalized()


func is_night() -> bool:
	return night > 0.5


func apply() -> void:
	var k := sample(hour)
	night = k[8]
	var sd := sun_direction(hour)
	var light_dir := sd
	# De noche ilumina la luna (opuesta al sol, algo elevada).
	var moon := Vector3(-sd.x, maxf(-sd.y, 0.25), -sd.z * 0.6).normalized()
	if sd.y < 0.05:
		light_dir = sd.lerp(moon, Island.ss(0.05, -0.12, sd.y)).normalized()
	if light_dir.y < 0.08:
		light_dir.y = 0.08
		light_dir = light_dir.normalized()
	sun.look_at_from_position(Vector3.ZERO, -light_dir, Vector3.UP if absf(light_dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = k[3]
	sun.light_energy = k[4]
	env.ambient_light_color = k[5]
	env.ambient_light_energy = 1.0
	env.fog_light_color = (k[2] as Color).lerp(k[1], 0.15)
	sky_mat.set_shader_parameter("top_color", k[1])
	sky_mat.set_shader_parameter("horizon_color", k[2])
	sky_mat.set_shader_parameter("sun_color", (k[3] as Color).lerp(Color(1, 1, 0.9), 0.4))
	sky_mat.set_shader_parameter("cloud_light", k[6])
	sky_mat.set_shader_parameter("cloud_shade", k[7])
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("moon_dir", moon)
	sky_mat.set_shader_parameter("sun_vec", sd)
	var tint: Color = (k[5] as Color) * 0.75 + (k[3] as Color) * (k[4] as float) * 0.45
	RenderingServer.global_shader_parameter_set("sun_dir", light_dir)
	RenderingServer.global_shader_parameter_set("day_tint", Color(minf(tint.r, 1.2), minf(tint.g, 1.2), minf(tint.b, 1.2)))
	RenderingServer.global_shader_parameter_set("night_amount", night)


func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
