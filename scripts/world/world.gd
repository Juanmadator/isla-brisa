class_name World
extends Node3D
## El mundo de Isla Brisa: terreno, agua, cielo, vegetación y lugares.

var island: Island
var terrain: TerrainView
var sky: SkyCycle
var flora: Flora
var places: Places
var critters: Critters
var wind_lines: WindLines
var traffic: Traffic
var home: Home


func build() -> void:
	var t0 := Time.get_ticks_msec()
	island = Island.new()
	island.generate()
	var t1 := Time.get_ticks_msec()
	sky = SkyCycle.new()
	sky.name = "Sky"
	add_child(sky)
	terrain = TerrainView.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(island)
	var t2 := Time.get_ticks_msec()
	places = Places.new()
	places.name = "Places"
	add_child(places)
	places.build(island)
	flora = Flora.new()
	flora.name = "Flora"
	add_child(flora)
	flora.build(island, places.clear_zones)
	critters = Critters.new()
	critters.name = "Critters"
	add_child(critters)
	critters.build(island)
	traffic = Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.build(island)
	wind_lines = WindLines.new()
	wind_lines.name = "WindLines"
	wind_lines.island = island
	add_child(wind_lines)
	# Casa de Lía por dentro (lejos de la isla). El sol no ilumina su capa.
	home = Home.new()
	add_child(home)
	home.build(sky)
	sky.sun.light_cull_mask &= ~Home.LAYER
	var t3 := Time.get_ticks_msec()
	print("mundo: isla %d ms, terreno %d ms, lugares+flora %d ms" % [t1 - t0, t2 - t1, t3 - t2])


func set_focus(p: Vector3) -> void:
	if flora:
		flora.focus = p
	if critters:
		critters.focus = p
		critters.daylight = 1.0 - sky.night
	if wind_lines:
		wind_lines.focus = p
	RenderingServer.global_shader_parameter_set("player_pos", p)


const QUALITY_NAMES := ["Baja", "Media", "Alta", "Ultra"]
var quality := 2


## Nivel de calidad gráfica (0 = Baja ... 3 = Ultra). Lo que más cuesta en la GPU es la
## geometría de las sombras y el MSAA; los efectos de pantalla (SSAO, SSIL, niebla) poco.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 3)
	if sky and sky.env:
		var env := sky.env
		env.ssao_enabled = quality >= 2
		env.ssil_enabled = quality >= 2
		env.volumetric_fog_enabled = quality >= 1
		env.glow_enabled = quality >= 1
		var sun := sky.sun
		# Penumbra de las sombras (más blanda cuanto más lejos está lo que la proyecta).
		sun.light_angular_distance = [0.0, 0.0, 0.4, 0.6][quality]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = [110.0, 160.0, 200.0, 240.0][quality]
	RenderingServer.directional_shadow_atlas_set_size(2048 if quality <= 1 else 4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality])
	if flora:
		flora.set_grass_near([10.0, 18.0, Flora.GRASS_NEAR, Flora.GRASS_NEAR][quality])
	if terrain:
		terrain.set_water_quality([0.0, 0.5, 1.0, 1.0][quality])
	var vp := get_viewport()
	if vp:
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == 0 else Viewport.SCREEN_SPACE_AA_SMAA
		vp.msaa_3d = Viewport.MSAA_2X if quality == 3 else Viewport.MSAA_DISABLED
