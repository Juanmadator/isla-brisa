class_name Menus
extends CanvasLayer
## Pantallas superpuestas: título, pausa (mapa, encargos, aspecto, opciones), tienda y final.

var main
var current: Control
var kind := ""
var map_tex: Texture2D
var _tab := "map"
var _tab_body: Control
var _shop_id := "marisol"
var _room: FittingRoom

const SLOTS := [["outfit", "Ropa"], ["hat", "Sombreros"], ["scarf", "Bufandas"], ["glider", "Paravelas"], ["pet", "Mascotas"], ["special", "Especial"]]


func _init() -> void:
	layer = 10


func close() -> void:
	if current:
		current.queue_free()
	current = null
	kind = ""


func is_open() -> bool:
	return current != null


func _overlay(dim := 0.45) -> Control:
	close()
	var root := UiKit.full_rect(Control.new())
	root.theme = UiKit.make_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.1, 0.15, dim)
	UiKit.full_rect(bg)
	root.add_child(bg)
	add_child(root)
	current = root
	return root


# --- Título --------------------------------------------------------------------------

func show_title() -> void:
	var root := _overlay(0.0)
	kind = "title"
	var v := UiKit.vbox(14)
	root.add_child(v)
	UiKit.place(v, Vector2(0, 0.5), Vector2(90, -290), Vector2(560, 580))
	var title := UiKit.label("Isla Brisa", 96, UiKit.C_WHITE, 700, 18)
	v.add_child(title)
	var sub := UiKit.label("Una aventura que trae el viento", 26, Color(1.0, 0.95, 0.8), 500, 8)
	v.add_child(sub)
	v.add_child(UiKit.spacer(26))
	var first: Button
	if SaveGame.has_save():
		first = UiKit.accent_button("Continuar", func() -> void: main.start_game(false), 26, 320)
		v.add_child(first)
		v.add_child(UiKit.button("Nueva partida", func() -> void: _confirm_new(), 22, 320))
	else:
		first = UiKit.accent_button("Empezar", func() -> void: main.start_game(true), 26, 320)
		v.add_child(first)
	v.add_child(UiKit.button("Opciones", func() -> void: show_options_standalone(), 22, 320))
	v.add_child(UiKit.button("Salir", func() -> void: main.quit_game(), 22, 320))
	var foot := UiKit.label("Ratón y teclado o mando · Hecho con Godot", 16, Color(1, 1, 1, 0.85), 500, 4)
	root.add_child(foot)
	UiKit.place(foot, Vector2(0, 1), Vector2(90, -50), Vector2(600, 30))
	for i in v.get_child_count():
		UiKit.pop_in(v.get_child(i), 0.1 + i * 0.07)
	first.call_deferred("grab_focus")


func _confirm_new() -> void:
	var root := _overlay(0.55)
	kind = "confirm"
	var p := UiKit.panel()
	var v := UiKit.vbox(16)
	p.add_child(v)
	v.add_child(UiKit.label("¿Empezar una partida nueva?", 30, UiKit.C_TEXT, 700))
	v.add_child(UiKit.label("Se borrará el progreso guardado.", 20, UiKit.C_MUTED))
	var h := UiKit.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var no := UiKit.button("Cancelar", func() -> void: show_title(), 22, 180)
	h.add_child(no)
	h.add_child(UiKit.accent_button("Empezar de cero", func() -> void: main.start_game(true), 22, 220))
	v.add_child(h)
	root.add_child(UiKit.center(p))
	UiKit.pop_in(p)
	no.call_deferred("grab_focus")


func show_options_standalone() -> void:
	var root := _overlay(0.55)
	kind = "options"
	var p := UiKit.panel()
	p.custom_minimum_size = Vector2(620, 0)
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.label("Opciones", 34, UiKit.C_TEXT, 700))
	v.add_child(_options_body())
	var back := UiKit.accent_button("Volver", func() -> void: show_title(), 22, 200)
	v.add_child(back)
	root.add_child(UiKit.center(p))
	UiKit.pop_in(p)
	back.call_deferred("grab_focus")


# --- Pausa --------------------------------------------------------------------------------

func show_pause(tab := "map") -> void:
	var root := _overlay(0.5)
	kind = "pause"
	_tab = tab
	var p := UiKit.panel()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 60
	p.offset_right = -60
	p.offset_top = 40
	p.offset_bottom = -40
	root.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	var tabs := UiKit.hbox(10)
	v.add_child(tabs)
	var names := [["map", "Mapa"], ["quests", "Encargos"], ["bag", "Mochila"], ["journal", "Cuaderno"], ["looks", "Aspecto"], ["options", "Opciones"]]
	var first: Button
	for t in names:
		var tid: String = t[0]
		var b := UiKit.accent_button(t[1], func() -> void: _switch_tab(tid), 20, 132) if tid == _tab else UiKit.button(t[1], func() -> void: _switch_tab(tid), 20, 132)
		tabs.add_child(b)
		if tid == _tab:
			first = b
	tabs.add_child(UiKit.expand_spacer())
	tabs.add_child(UiKit.button("Guardar y salir", func() -> void: main.save_and_title(), 20))
	tabs.add_child(UiKit.accent_button("Continuar", func() -> void: main.resume(), 20, 170))
	_tab_body = Control.new()
	_tab_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_tab_body)
	match _tab:
		"map":
			_build_map_tab()
		"quests":
			_build_quests_tab()
		"looks":
			_build_looks_tab()
		"bag":
			_build_bag_tab()
		"journal":
			_build_journal_tab()
		"options":
			var sc := ScrollContainer.new()
			UiKit.full_rect(sc)
			var holder := UiKit.vbox(10)
			holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			holder.add_child(_options_body())
			sc.add_child(holder)
			_tab_body.add_child(sc)
	if first:
		first.call_deferred("grab_focus")


func _switch_tab(t: String) -> void:
	if t == "journal":
		Audio.play("page", 0.05)
	show_pause(t)


func _journal_card(icon_kind: String, title: String, cat: String, desc: String, known: bool) -> Control:
	var card := UiKit.panel(Color(1, 1, 1, 0.75) if known else Color(0.9, 0.92, 0.93, 0.6), UiKit.C_BORDER if known else Color(0.7, 0.75, 0.78), 14, 16)
	card.custom_minimum_size = Vector2(350, 118)
	var h := UiKit.hbox(12)
	card.add_child(h)
	h.add_child(UiKit.icon(icon_kind if known else "lock", 48))
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiKit.label(title if known else "???", 21, UiKit.C_TEXT if known else UiKit.C_MUTED, 700))
	v.add_child(UiKit.label(cat if known else "Sin descubrir", 15, UiKit.C_ACCENT.darkened(0.2) if known else UiKit.C_MUTED, 600))
	if known:
		var d := UiKit.label(desc, 15, UiKit.C_TEXT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 250
		v.add_child(d)
	return card


func _build_journal_tab() -> void:
	var sc := ScrollContainer.new()
	UiKit.full_rect(sc)
	_tab_body.add_child(sc)
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var total := 0
	var known_n := 0
	for sec in Catalog.JOURNAL_ORDER:
		v.add_child(UiKit.label(sec[0], 26, UiKit.C_TEXT, 700))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 12)
		v.add_child(flow)
		for id in sec[1]:
			var e: Array = Catalog.JOURNAL[id]
			var known := SaveGame.in_journal(id)
			total += 1
			if known:
				known_n += 1
			flow.add_child(_journal_card(e[2], e[0], e[1], e[3], known))
	v.add_child(UiKit.label("Lugares", 26, UiKit.C_TEXT, 700))
	var pf := HFlowContainer.new()
	pf.add_theme_constant_override("h_separation", 12)
	pf.add_theme_constant_override("v_separation", 12)
	v.add_child(pf)
	for n in Places.NAMED:
		var known := SaveGame.is_discovered(n[0])
		total += 1
		if known:
			known_n += 1
		pf.add_child(_journal_card("star", n[1], "Lugar", Catalog.PLACE_DESC.get(n[0], ""), known))
	var head := UiKit.label("Cuaderno de Lía · %d de %d páginas completas" % [known_n, total], 20, UiKit.C_MUTED, 600)
	v.add_child(head)
	v.move_child(head, 0)


func _build_map_tab() -> void:
	var h := UiKit.hbox(20)
	UiKit.full_rect(h)
	_tab_body.add_child(h)
	var mv := MapView.new()
	mv.tex = map_tex
	mv.gp = main.gameplay
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(mv)
	var side := UiKit.vbox(10)
	side.custom_minimum_size.x = 330
	h.add_child(side)
	var place: String = main.gameplay.place_name_at(main.player.global_position)
	side.add_child(UiKit.label(place, 28, UiKit.C_TEXT, 700))
	side.add_child(UiKit.label("Faros del Viento", 22, UiKit.C_ACCENT.darkened(0.2), 700))
	for id in Catalog.BEACONS:
		var row := UiKit.hbox(8)
		var lit := SaveGame.flag("lit_" + id)
		row.add_child(UiKit.icon("beacon", 24, Places.REGION_COLORS[id] if lit else Color(0, 0, 0, 0)))
		row.add_child(UiKit.label(Catalog.BEACONS[id][0], 19, UiKit.C_TEXT if lit else UiKit.C_MUTED, 600 if lit else 500))
		if lit:
			row.add_child(UiKit.icon("check", 20))
		side.add_child(row)
	side.add_child(UiKit.spacer(8))
	side.add_child(UiKit.label("Colección", 22, UiKit.C_ACCENT.darkened(0.2), 700))
	var stats := [
		["feather", "Plumas doradas", "%d / %d" % [SaveGame.feathers(), Catalog.TOTAL_FEATHERS]],
		["shell", "Conchas", str(SaveGame.shells())],
		["chest", "Cofres", "%d / %d" % [SaveGame.count_collected("chest_"), Catalog.CHESTS.size()]],
		["kitten", "Gatitos", "%d / %d" % [SaveGame.count_collected("kitten_"), Catalog.KITTENS.size()]],
		["mushroom", "Setas brillantes", "%d / %d" % [SaveGame.count_collected("mushroom_"), Catalog.MUSHROOMS.size()]],
		["star", "Lugares", "%d / %d" % [SaveGame.data["discovered"].size(), Places.NAMED.size()]],
	]
	for s in stats:
		var row := UiKit.hbox(8)
		row.add_child(UiKit.icon(s[0], 22))
		row.add_child(UiKit.label(s[1], 18))
		row.add_child(UiKit.expand_spacer())
		row.add_child(UiKit.label(s[2], 18, UiKit.C_TEXT, 600))
		side.add_child(row)
	side.add_child(UiKit.expand_spacer())
	var mins := int(SaveGame.data.get("play_time", 0.0) / 60.0)
	side.add_child(UiKit.label("Tiempo de juego: %d h %02d min" % [mins / 60, mins % 60], 16, UiKit.C_MUTED))


func _build_quests_tab() -> void:
	var sc := ScrollContainer.new()
	UiKit.full_rect(sc)
	_tab_body.add_child(sc)
	var v := UiKit.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var list: Array = main.gameplay.quests()
	if list.is_empty():
		v.add_child(UiKit.label("Todavía no tienes encargos. Habla con la gente de la isla.", 22, UiKit.C_MUTED))
	var tracked: Dictionary = main.gameplay.tracked_quest()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["done"] != b["done"]:
			return not a["done"]
		return a["main"] and not b["main"])
	for q in list:
		var card := UiKit.panel(Color(1, 1, 1, 0.7) if not q["done"] else Color(0.93, 0.95, 0.93, 0.6), UiKit.C_BORDER if not q["done"] else Color(0.6, 0.7, 0.65), 16, 16)
		var cv := UiKit.vbox(6)
		card.add_child(cv)
		var head := UiKit.hbox(10)
		head.add_child(UiKit.icon("check" if q["done"] else "quest", 26))
		head.add_child(UiKit.label(q["title"], 24, UiKit.C_TEXT, 700))
		head.add_child(UiKit.label("· " + ("Historia" if q["main"] else "Encargo de " + q["giver"]), 18, UiKit.C_MUTED))
		head.add_child(UiKit.expand_spacer())
		if not q["done"]:
			var qid: String = q["id"]
			if tracked.get("id", "") == qid:
				head.add_child(UiKit.label("Siguiendo", 18, UiKit.C_ACCENT.darkened(0.2), 700))
			else:
				head.add_child(UiKit.button("Seguir", func() -> void:
					SaveGame.data["tracked"] = qid
					show_pause("quests"), 18))
		cv.add_child(head)
		for s in q["steps"]:
			var row := UiKit.hbox(8)
			row.add_child(UiKit.spacer(0, 30))
			row.add_child(UiKit.icon("check", 20) if s[1] else UiKit.icon("dot", 14))
			var l := UiKit.label(s[0], 19, UiKit.C_MUTED if s[1] else UiKit.C_TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			cv.add_child(row)
		v.add_child(card)


func _build_bag_tab() -> void:
	var sc := ScrollContainer.new()
	UiKit.full_rect(sc)
	_tab_body.add_child(sc)
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var head := UiKit.hbox(16)
	head.add_child(UiKit.icon("shell", 30))
	head.add_child(UiKit.label("%d conchas" % SaveGame.shells(), 24, UiKit.C_TEXT, 700))
	head.add_child(UiKit.spacer(0, 20))
	head.add_child(UiKit.icon("feather", 30))
	head.add_child(UiKit.label("%d plumas" % SaveGame.feathers(), 24, UiKit.C_TEXT, 700))
	head.add_child(UiKit.expand_spacer())
	head.add_child(UiKit.label("Día %d" % (SaveGame.day() + 1), 22, UiKit.C_MUTED, 600))
	v.add_child(head)
	var any := false
	for id in Catalog.BAG:
		var n := SaveGame.bag_count(id)
		if n <= 0:
			continue
		any = true
		var info: Array = Catalog.BAG[id]
		var row := UiKit.hbox(14)
		row.add_child(UiKit.icon(info[1], 38))
		var tv := UiKit.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UiKit.label("%s × %d" % [info[0], n], 22, UiKit.C_TEXT, 600))
		var d := UiKit.label(info[3], 17, UiKit.C_MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(d)
		row.add_child(tv)
		if id == "bread":
			row.add_child(UiKit.accent_button("Comer", func() -> void:
				if SaveGame.bag_take("bread"):
					main.player.refill_stamina()
					Audio.play("stamina_up", 0.0, -3.0)
					main.hud.show_toast("¡Qué rico! Aguante al máximo", "bread")
					show_pause("bag"), 19, 140))
		v.add_child(row)
	var fish := 0
	for fid in SaveGame.data["fish"]:
		fish += int(SaveGame.data["fish"][fid])
	if fish > 0:
		any = true
		var row := UiKit.hbox(14)
		row.add_child(UiKit.icon("fish", 38))
		row.add_child(UiKit.label("Cesta de pescado: %d %s (Tomeu te la compra)" % [fish, "pieza" if fish == 1 else "piezas"], 22, UiKit.C_TEXT, 600))
		v.add_child(row)
	if not any:
		var l := UiKit.label("La mochila está vacía. Recoge huevos y manzanas en la granja, flores en los prados o compra pan a Rafa.", 19, UiKit.C_MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)


func _build_looks_tab() -> void:
	var h := UiKit.hbox(18)
	UiKit.full_rect(h)
	_tab_body.add_child(h)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(sc)
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var intro := UiKit.label("Elige cómo va Lía y quién la acompaña. Hay más cosas en las tiendas del pueblo y en los cofres.", 19, UiKit.C_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	_room = FittingRoom.new()
	var eq: Dictionary = SaveGame.data["equipped"]
	for slot in SLOTS:
		if slot[0] == "special":
			continue
		v.add_child(UiKit.label(slot[1], 24, UiKit.C_TEXT, 700))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		v.add_child(flow)
		for id in Catalog.ITEMS:
			var it: Array = Catalog.ITEMS[id]
			if it[0] != slot[0] or not SaveGame.owns(id):
				continue
			var iid: String = id
			var s: String = slot[0]
			var on: bool = SaveGame.equipped(s) == id
			var b := UiKit.accent_button(it[1], func() -> void: pass, 19) if on else UiKit.button(it[1], func() -> void:
				SaveGame.equip(s, iid)
				main.apply_looks()
				SaveGame.save_game()
				show_pause("looks"), 19)
			_hook_preview(b, iid)
			flow.add_child(b)
	h.add_child(_room_panel())
	_room.show_look(eq)


## Panel claro con el probador dentro.
func _room_panel() -> Control:
	var rp := UiKit.panel(Color(0.86, 0.92, 0.97, 1.0), UiKit.C_BORDER, 8, 18)
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rp.add_child(_room)
	return rp


## Al pasar el ratón o el foco por un botón, el probador muestra ese objeto puesto.
func _hook_preview(b: Button, id: String) -> void:
	var show := func() -> void:
		if _room and is_instance_valid(_room):
			_room.show_look(SaveGame.data["equipped"], id)
	b.mouse_entered.connect(show)
	b.focus_entered.connect(show)


func _options_body() -> Control:
	var v := UiKit.vbox(12)
	v.add_child(_slider("Música", "music", 0.0, 1.0, func(x: float) -> void: Audio.refresh_volumes()))
	v.add_child(_slider("Efectos", "sfx", 0.0, 1.0, Callable()))
	v.add_child(_slider("Ambiente", "ambience", 0.0, 1.0, Callable()))
	v.add_child(_slider("Sensibilidad del ratón", "sensitivity", 0.3, 2.5, func(x: float) -> void:
		if main and main.rig:
			main.rig.sensitivity = 0.0032 * x))
	v.add_child(_check("Invertir eje vertical de la cámara", "invert_y", func(x: bool) -> void:
		if main and main.rig:
			main.rig.invert_y = x))
	v.add_child(_check("Sombras", "shadows", func(x: bool) -> void:
		if main and main.world:
			main.world.sky.sun.shadow_enabled = x))
	v.add_child(_check("Gráficos de alta calidad (oclusión ambiental y antialiasing)", "high_quality", func(x: bool) -> void:
		if main and main.world:
			main.world.set_quality(x)))
	v.add_child(_check("Pantalla completa", "fullscreen", Callable()))
	return v


func _slider(text: String, key: String, lo: float, hi: float, cb: Callable) -> Control:
	var h := UiKit.hbox(14)
	var l := UiKit.label(text, 20)
	l.custom_minimum_size.x = 260
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = float(SaveGame.setting(key))
	s.custom_minimum_size = Vector2(280, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(x: float) -> void:
		SaveGame.set_setting(key, x)
		if cb.is_valid():
			cb.call(x))
	h.add_child(s)
	return h


func _check(text: String, key: String, cb: Callable) -> Control:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(SaveGame.setting(key))
	c.add_theme_font_size_override("font_size", 20)
	c.toggled.connect(func(x: bool) -> void:
		SaveGame.set_setting(key, x)
		if cb.is_valid():
			cb.call(x))
	return c


# --- Tienda ----------------------------------------------------------------------------------

func show_shop(shop_id := "") -> void:
	if shop_id != "":
		_shop_id = shop_id
	if _shop_id == "board":
		show_board()
		return
	var shop: Dictionary = Catalog.SHOPS[_shop_id]
	var root := _overlay(0.45)
	kind = "shop"
	var p := UiKit.panel()
	p.custom_minimum_size = Vector2(1040, 600)
	var v := UiKit.vbox(10)
	p.add_child(v)
	var head := UiKit.hbox(10)
	head.add_child(UiKit.label(shop["title"], 34, UiKit.C_TEXT, 700))
	head.add_child(UiKit.expand_spacer())
	head.add_child(UiKit.icon("shell", 30))
	head.add_child(UiKit.label(str(SaveGame.shells()), 28, UiKit.C_TEXT, 700))
	v.add_child(head)
	v.add_child(UiKit.label(shop["blurb"], 19, UiKit.C_MUTED))
	var body := UiKit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(640, 440)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(sc)
	var list := UiKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	_room = FittingRoom.new()
	body.add_child(_room_panel())
	var first: Button
	var items: Array = shop["items"]
	for slot in SLOTS:
		var in_slot := items.filter(func(id: String) -> bool: return Catalog.ITEMS[id][0] == slot[0])
		if in_slot.is_empty():
			continue
		if items.size() > 6:
			list.add_child(UiKit.label(slot[1], 22, UiKit.C_TEXT, 700))
		for id in in_slot:
			var row := _shop_row(id)
			list.add_child(row[0])
			if first == null and not (row[1] as Button).disabled:
				first = row[1]
	var close_b := UiKit.button(shop["bye"], func() -> void: main.resume(), 22, 240)
	v.add_child(close_b)
	root.add_child(UiKit.center(p))
	UiKit.pop_in(p)
	_room.show_look(SaveGame.data["equipped"], first.get_meta("item") if first and first.has_meta("item") else "")
	(first if first else close_b).call_deferred("grab_focus")


## Fila de la tienda: muestra de color, nombre, precio y botón. Devuelve [fila, botón].
func _shop_row(id: String) -> Array:
	var it: Array = Catalog.ITEMS[id]
	var row := UiKit.hbox(12)
	row.add_child(_swatch(id))
	var name_l := UiKit.label(it[1], 22, UiKit.C_TEXT, 600)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	var owned := SaveGame.owns(id)
	var slot: String = it[0]
	var b: Button
	if slot == "food":
		var price: int = it[2]
		name_l.text = "%s (tienes %d)" % [it[1], SaveGame.bag_count(it[3])]
		b = UiKit.accent_button("Comprar · %d" % price, func() -> void: _buy(id), 19, 210)
		b.disabled = SaveGame.shells() < price
	elif owned and slot == "special":
		b = UiKit.button("Comprado", func() -> void: pass, 19, 210)
		b.disabled = true
	elif owned:
		var on: bool = SaveGame.equipped(slot) == id
		b = UiKit.button("Puesto" if on else ("Llevar" if slot == "pet" else "Ponérselo"), func() -> void:
			SaveGame.equip(slot, id)
			main.apply_looks()
			SaveGame.save_game()
			show_shop(), 19, 210)
		b.disabled = on
	else:
		var price: int = it[2]
		b = UiKit.accent_button(("Adoptar · %d" if slot == "pet" else "Comprar · %d") % price, func() -> void: _buy(id), 19, 210)
		b.disabled = SaveGame.shells() < price
		if b.disabled:
			b.tooltip_text = "Te faltan %d conchas" % (price - SaveGame.shells())
	b.set_meta("item", id)
	# Aunque no se pueda comprar, se puede probar: el botón deshabilitado no recibe foco,
	# así que también reacciona al pasar el ratón por la fila.
	_hook_preview(b, id)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_entered.connect(func() -> void:
		if _room and is_instance_valid(_room):
			_room.show_look(SaveGame.data["equipped"], id))
	row.add_child(b)
	return [row, b]


## Muestra pequeña del objeto: icono o círculo con sus colores.
func _swatch(id: String) -> Control:
	var it: Array = Catalog.ITEMS[id]
	match it[0]:
		"special":
			return UiKit.icon("feather" if id == "shop_feather" else "arrow", 34)
		"food":
			return UiKit.icon(Catalog.BAG[it[3]][1], 34)
		"pet":
			return UiKit.icon("paw", 34, (it[3][2][0] as Color) if it[3] != null else Color(0, 0, 0, 0))
		"hat":
			return UiKit.icon("hat", 34, it[3][1])
		"outfit":
			return UiKit.icon("shirt", 34, it[3][0])
		"glider":
			return UiKit.icon("star", 34, it[3][0])
	return UiKit.icon("scarf", 34, it[3])


func _buy(id: String) -> void:
	var it: Array = Catalog.ITEMS[id]
	if not SaveGame.spend(it[2]):
		Audio.play("error")
		return
	Audio.play("buy")
	if it[0] == "food":
		SaveGame.bag_add(it[3])
		SaveGame.save_game()
		show_shop()
		return
	SaveGame.give(id)
	if id == "shop_feather":
		main.gameplay._grant_feather("¡Pluma dorada de Marisol!")
	elif id == "shop_compass":
		main.hud.show_banner("¡Brújula de plumas!", "La brújula marca la pluma dorada más cercana")
	else:
		SaveGame.equip(it[0], id)
		main.apply_looks()
		if it[0] == "pet":
			main.hud.show_banner("¡%s se viene contigo!" % it[3][1], "Acércate y pulsa E para acariciarla")
	SaveGame.save_game()
	show_shop()


# --- Tablón de encargos ------------------------------------------------------------------------

func show_board() -> void:
	var root := _overlay(0.45)
	kind = "shop"
	var gp = main.gameplay
	var p := UiKit.panel()
	p.custom_minimum_size = Vector2(820, 520)
	var v := UiKit.vbox(12)
	p.add_child(v)
	var head := UiKit.hbox(10)
	head.add_child(UiKit.icon("quest", 34))
	head.add_child(UiKit.label("Tablón de encargos", 34, UiKit.C_TEXT, 700))
	head.add_child(UiKit.expand_spacer())
	head.add_child(UiKit.label("Día %d" % (SaveGame.day() + 1), 22, UiKit.C_MUTED, 600))
	v.add_child(head)
	var blurb := UiKit.label("Los vecinos dejan aquí lo que necesitan. Cada mañana hay encargos nuevos.", 19, UiKit.C_MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(blurb)
	var first: Button
	var reqs: Array = gp.board_requests()
	for i in reqs.size():
		var r: Dictionary = reqs[i]
		var card := UiKit.panel(Color(1.0, 0.96, 0.86, 1.0), UiKit.C_BORDER, 14, 14)
		var row := UiKit.hbox(14)
		card.add_child(row)
		row.add_child(UiKit.icon("fish" if r["item"] == "fish" else Catalog.BAG[r["item"]][1], 40))
		var tv := UiKit.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var who: String = Catalog.NPCS[r["who"]]["name"]
		tv.add_child(UiKit.label("%s necesita %s" % [who, gp.item_label(r["item"], r["n"])], 22, UiKit.C_TEXT, 600))
		var have: int = gp.have_item(r["item"])
		tv.add_child(UiKit.label("Tienes %d · Recompensa: %d conchas" % [have, r["reward"]], 18, UiKit.C_MUTED))
		row.add_child(tv)
		var ri: int = i
		var b: Button
		if r["done"]:
			b = UiKit.button("Hecho", func() -> void: pass, 19, 170)
			b.disabled = true
		else:
			b = UiKit.accent_button("Entregar", func() -> void:
				if gp.deliver_request(ri):
					Audio.play("quest_done", 0.0, -4.0)
				else:
					Audio.play("error")
				show_board(), 19, 170)
			b.disabled = have < int(r["n"])
		row.add_child(b)
		v.add_child(card)
		if first == null and not b.disabled:
			first = b
	var close_b := UiKit.button("Cerrar", func() -> void: main.resume(), 22, 240)
	v.add_child(close_b)
	root.add_child(UiKit.center(p))
	UiKit.pop_in(p)
	(first if first else close_b).call_deferred("grab_focus")


# --- Final -----------------------------------------------------------------------------------

func show_ending() -> void:
	var root := _overlay(0.0)
	kind = "ending"
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.06, 0.1, 0.0)
	UiKit.full_rect(shade)
	root.add_child(shade)
	shade.create_tween().tween_property(shade, "color:a", 0.45, 3.0)
	var v := UiKit.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(v)
	UiKit.band(v, 1.0, 40, 620)
	var lines := [
		["Isla Brisa vuelve a respirar", 54, 700],
		["", 20, 500],
		["Los cinco Faros del Viento brillan de nuevo.", 26, 500],
		["Los molinos giran, las cometas vuelan y los barcos ya pueden zarpar.", 26, 500],
		["", 20, 500],
		["Gracias por jugar, farera Lía.", 30, 600],
		["", 30, 500],
		["Plumas doradas: %d / %d" % [SaveGame.feathers(), Catalog.TOTAL_FEATHERS], 22, 500],
		["Cofres: %d / %d · Gatitos: %d / %d" % [SaveGame.count_collected("chest_"), Catalog.CHESTS.size(), SaveGame.count_collected("kitten_"), Catalog.KITTENS.size()], 22, 500],
		["", 30, 500],
		["La isla sigue ahí: quedan rincones por descubrir.", 22, 500],
	]
	for l in lines:
		var lab := UiKit.label(l[0], l[1], UiKit.C_WHITE, l[2], 8)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lab)
	var b := UiKit.accent_button("Seguir explorando", func() -> void: main.finish_ending(), 26, 320)
	var bc := CenterContainer.new()
	bc.add_child(b)
	v.add_child(bc)
	var tw := v.create_tween().set_parallel(true)
	tw.tween_property(v, "offset_top", -660.0, 12.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "offset_bottom", -40.0, 12.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	b.call_deferred("grab_focus")
