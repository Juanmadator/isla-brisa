extends SceneTree
## Vista cenital de la isla y alturas de los lugares clave.
## Uso: Godot --headless --path . --script res://tools/preview_map.gd

func _init() -> void:
	var t := Time.get_ticks_msec()
	var isl := Island.new()
	isl.generate()
	print("generada en %d ms" % (Time.get_ticks_msec() - t))
	var img := isl.map_image(1.0)
	img.save_png(ProjectSettings.globalize_path("res://captures/map_preview.png"))
	var places := {
		"summit": Island.MOUNT, "cliff": Island.CLIFF, "windmill": Island.WINDMILL_HILL,
		"penon": Island.PENON, "islet": Island.ISLET, "lake": Island.LAKE, "lake_islet": Island.LAKE_ISLET,
		"village": Island.VILLAGE, "ruins": Island.RUINS, "forest": Island.FOREST,
	}
	for k in places:
		var p: Vector2 = places[k]
		print("%-11s h=%6.1f biome=%d" % [k, isl.height_at(p.x, p.y), isl.biome_at(p.x, p.y)])
	print("shore south of village: ", isl.find_shore(Island.VILLAGE, Vector2(0, 1)))
	var mx := -INF
	for h in isl.heights:
		mx = maxf(mx, h)
	print("max h ", mx)
	quit()
