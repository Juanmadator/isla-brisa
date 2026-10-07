extends Node
## Partida guardada: posición, hora, banderas de historia, objetos recogidos, inventario,
## cosméticos, lugares descubiertos y ajustes. Se guarda en user://isla_brisa_save.json.

const PATH := "user://isla_brisa_save.json"
const VERSION := 1

var data := {}
var persist := true

signal changed


func _ready() -> void:
	load_game()


func default_data() -> Dictionary:
	return {
		"version": VERSION,
		"started": false,
		"pos": [0.0, 0.0, 0.0],
		"yaw": 0.0,
		"hour": 8.0,
		"flags": {},
		"collected": {},
		"discovered": {},
		"journal": {},
		"shells": 0,
		"feathers": 0,
		"fish": {},
		"bag": {},
		"day": 0,
		"daily": {},
		"owned": {"scarf_red": true, "glider_classic": true, "hat_none": true, "outfit_travel": true, "pet_none": true,
			"furn_wall_white": true, "furn_floor_planks": true},
		# Casa de Lía: hueco -> mueble ("wall" y "floor": paredes y suelo).
		"home": {"wall": "furn_wall_white", "floor": "furn_floor_planks"},
		"equipped": {"scarf": "scarf_red", "hat": "hat_none", "glider": "glider_classic", "outfit": "outfit_travel", "pet": "pet_none"},
		"tracked": "",
		"play_time": 0.0,
		"settings": {
			"music": 0.75,
			"sfx": 0.85,
			"ambience": 0.7,
			"sensitivity": 1.0,
			"invert_y": false,
			"fullscreen": false,
			"shadows": true,
			# 0 Baja, 1 Media, 2 Alta, 3 Ultra.
			"quality": 2,
			# 0 sin vsync, 1 vsync, 2 vsync adaptativo.
			"vsync": 1,
			# Límite de FPS (0 = sin límite).
			"max_fps": 0,
			# Resolución 3D (1 = nativa; menos, reescalada con FSR).
			"render_scale": 1.0,
		},
	}


func load_game() -> void:
	data = default_data()
	if persist and FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_merge(data, parsed)
				# Ajuste antiguo de dos estados: "alta calidad" desactivada = calidad Baja.
				var st: Dictionary = parsed["settings"] if parsed.get("settings") is Dictionary else {}
				if st.has("high_quality") and not st.has("quality"):
					data["settings"]["quality"] = 2 if bool(st["high_quality"]) else 0
				data["settings"].erase("high_quality")
	# Partidas de versiones anteriores: añade lo que viene de serie y las ranuras nuevas.
	var def := default_data()
	for id in def["owned"]:
		data["owned"][id] = true
	for slot in def["equipped"]:
		if not data["equipped"].has(slot):
			data["equipped"][slot] = def["equipped"][slot]


func save_game() -> void:
	if not persist:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


func _merge(base: Dictionary, incoming: Dictionary) -> void:
	for k in incoming:
		if base.has(k) and base[k] is Dictionary and incoming[k] is Dictionary:
			if k in ["flags", "collected", "discovered", "owned", "equipped", "journal", "fish", "bag", "daily", "home"]:
				base[k] = incoming[k]
			else:
				_merge(base[k], incoming[k])
		else:
			base[k] = incoming[k]


## Borra el progreso pero conserva los ajustes.
func new_game() -> void:
	var settings: Dictionary = data["settings"]
	data = default_data()
	data["settings"] = settings
	data["started"] = true
	save_game()
	changed.emit()


func has_save() -> bool:
	return data.get("started", false)


# --- Banderas y objetos -------------------------------------------------------------

func flag(k: String) -> bool:
	return data["flags"].get(k, false)


func set_flag(k: String, v := true) -> void:
	data["flags"][k] = v
	changed.emit()


func counter(k: String) -> int:
	return int(data["flags"].get(k, 0))


func add_counter(k: String, n := 1) -> int:
	data["flags"][k] = counter(k) + n
	changed.emit()
	return counter(k)


func is_collected(id: String) -> bool:
	return data["collected"].has(id)


func collect(id: String) -> void:
	data["collected"][id] = true
	changed.emit()


func count_collected(prefix: String) -> int:
	var n := 0
	for k in data["collected"]:
		if String(k).begins_with(prefix):
			n += 1
	return n


func in_journal(id: String) -> bool:
	return data["journal"].has(id)


func add_journal(id: String) -> void:
	data["journal"][id] = true
	changed.emit()


func is_discovered(id: String) -> bool:
	return data["discovered"].has(id)


func discover(id: String) -> void:
	data["discovered"][id] = true
	changed.emit()


# --- Moneda, plumas y cosméticos ------------------------------------------------------

func shells() -> int:
	return int(data["shells"])


func add_shells(n: int) -> void:
	data["shells"] = shells() + n
	changed.emit()


func spend(n: int) -> bool:
	if shells() < n:
		return false
	data["shells"] = shells() - n
	changed.emit()
	return true


func feathers() -> int:
	return int(data["feathers"])


func add_feather() -> void:
	data["feathers"] = feathers() + 1
	changed.emit()


func owns(id: String) -> bool:
	return data["owned"].has(id)


func give(id: String) -> void:
	data["owned"][id] = true
	changed.emit()


func equipped(slot: String) -> String:
	return data["equipped"].get(slot, "")


func equip(slot: String, id: String) -> void:
	data["equipped"][slot] = id
	changed.emit()


# --- Mochila (objetos que se gastan) y cosas que se renuevan cada día --------------------

## Casa de Lía: mueble puesto en un hueco ("" si está vacío).
func home_item(slot: String) -> String:
	return data["home"].get(slot, "")


func set_home_item(slot: String, id: String) -> void:
	if id == "":
		data["home"].erase(slot)
	else:
		data["home"][slot] = id
	changed.emit()


func bag_count(id: String) -> int:
	return int(data["bag"].get(id, 0))


func bag_add(id: String, n := 1) -> void:
	data["bag"][id] = bag_count(id) + n
	changed.emit()


func bag_take(id: String, n := 1) -> bool:
	if bag_count(id) < n:
		return false
	data["bag"][id] = bag_count(id) - n
	changed.emit()
	return true


func day() -> int:
	return int(data.get("day", 0))


## Marca algo como hecho hoy (huevos recogidos, oveja esquilada, manzano sacudido...).
func daily_done(key: String) -> bool:
	return data["daily"].has(key)


func set_daily(key: String) -> void:
	data["daily"][key] = true
	changed.emit()


## Empieza un día nuevo: lo diario vuelve a estar disponible.
func next_day() -> void:
	data["day"] = day() + 1
	data["daily"] = {}
	changed.emit()


# --- Ajustes ------------------------------------------------------------------------------

func setting(k: String):
	return data["settings"].get(k, default_data()["settings"].get(k))


func set_setting(k: String, v) -> void:
	data["settings"][k] = v
	apply_settings()
	save_game()


func apply_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Engine.max_fps = int(setting("max_fps"))
	var vs: DisplayServer.VSyncMode = [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE][clampi(int(setting("vsync")), 0, 2)]
	if DisplayServer.window_get_vsync_mode() != vs:
		DisplayServer.window_set_vsync_mode(vs)
	var root := get_tree().root
	var rs := clampf(float(setting("render_scale")), 0.5, 1.0)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if rs >= 0.999 else Viewport.SCALING_3D_MODE_FSR
	root.scaling_3d_scale = rs
	var fs: bool = setting("fullscreen")
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and not (not fs and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(want)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
