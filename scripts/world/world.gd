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


## Alterna los efectos caros (oclusión ambiental, antialiasing por pantalla).
func set_quality(high: bool) -> void:
	if sky and sky.env:
		sky.env.ssao_enabled = high
	var vp := get_viewport()
	if vp:
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if high else Viewport.SCREEN_SPACE_AA_FXAA
		vp.msaa_3d = Viewport.MSAA_2X if high else Viewport.MSAA_DISABLED
