class_name Hud
extends CanvasLayer
## Interfaz en juego: aguante, brújula, objetivo, conchas y plumas, avisos, rótulos,
## indicador de interacción, diálogos y cronómetro de la carrera.

var main
var root: Control
var stamina_wheel: StaminaWheel
var compass: Compass
var objective_box: PanelContainer
var objective_title: Label
var objective_text: Label
var shells_label: Label
var feathers_label: Label
var clock_label: Label
var prompt_box: PanelContainer
var prompt_label: Label
var prompt_key: Label
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var toast_box: VBoxContainer
var race_box: PanelContainer
var race_label: Label
var fish_box: PanelContainer
var fish_label: Label
var fish_bars: Control
var fish_progress: ColorRect
var fish_tension: ColorRect
var hint_label: Label
var fade: ColorRect
var vignette: TextureRect
var hint_text: Label
var card: PanelContainer
var card_title: Label
var card_cat: Label
var card_desc: Label
var card_icon: Icon
var card_continue: Label
var card_ready := false
var _card_tw: Tween
var _hint_show := 0.0
var _last_obj := ""
var dialogue: DialogueBox

var cinematic := false
var counters: Control
var _banner_queue: Array = []
var _banner_busy := false
var _hint_t := 0.0


func _init() -> void:
	layer = 5


func build() -> void:
	root = UiKit.full_rect(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.make_theme()
	add_child(root)
	# Viñeteado suave en los bordes (más fuerte en las escenas).
	vignette = TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.add_point(0.55, Color(0, 0, 0, 0))
	g.set_color(g.get_point_count() - 1, Color(0.02, 0.05, 0.1, 0.55))
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.45
	UiKit.full_rect(vignette)
	root.add_child(vignette)
	# Aguante
	stamina_wheel = StaminaWheel.new()
	root.add_child(stamina_wheel)
	# Brújula arriba
	compass = Compass.new()
	root.add_child(compass)
	UiKit.place(compass, Vector2(0.5, 0), Vector2(-260, 14), Vector2(520, 46))
	# Contadores arriba a la derecha
	counters = UiKit.dark_panel(12)
	counters.custom_minimum_size = Vector2(210, 0)
	root.add_child(counters)
	UiKit.place(counters, Vector2(1, 0), Vector2(-230, 14), Vector2(210, 0))
	var cv := UiKit.vbox(4)
	counters.add_child(cv)
	var r1 := UiKit.hbox(8)
	r1.add_child(UiKit.icon("shell", 26))
	shells_label = UiKit.label("0", 22, UiKit.C_WHITE, 600, 4)
	r1.add_child(shells_label)
	r1.add_child(UiKit.expand_spacer())
	r1.add_child(UiKit.icon("feather", 26))
	feathers_label = UiKit.label("0", 22, UiKit.C_WHITE, 600, 4)
	r1.add_child(feathers_label)
	cv.add_child(r1)
	var r2 := UiKit.hbox(8)
	r2.add_child(UiKit.icon("clock", 22))
	clock_label = UiKit.label("08:00", 18, Color(0.9, 0.95, 1.0), 500, 3)
	r2.add_child(clock_label)
	cv.add_child(r2)
	# Objetivo a la derecha
	objective_box = UiKit.dark_panel(14)
	objective_box.custom_minimum_size = Vector2(360, 0)
	root.add_child(objective_box)
	UiKit.place(objective_box, Vector2(1, 0), Vector2(-380, 112), Vector2(360, 0))
	var ov := UiKit.vbox(2)
	objective_box.add_child(ov)
	var oh := UiKit.hbox(8)
	oh.add_child(UiKit.icon("quest", 22))
	objective_title = UiKit.label("", 19, UiKit.C_GOLD, 600, 4)
	oh.add_child(objective_title)
	ov.add_child(oh)
	objective_text = UiKit.label("", 17, UiKit.C_WHITE, 500, 3)
	objective_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_text.custom_minimum_size.x = 330
	ov.add_child(objective_text)
	hint_text = UiKit.label("", 15, Color(0.85, 0.92, 1.0), 500, 3)
	hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_text.custom_minimum_size.x = 330
	ov.add_child(hint_text)
	# Indicador de interacción
	prompt_box = UiKit.dark_panel(12)
	var prompt_band := CenterContainer.new()
	prompt_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_band)
	UiKit.band(prompt_band, 1.0, -170, 60)
	prompt_band.add_child(prompt_box)
	var ph := UiKit.hbox(10)
	prompt_box.add_child(ph)
	var keybox := PanelContainer.new()
	keybox.add_theme_stylebox_override("panel", UiKit.box(UiKit.C_WHITE, 8, 2, UiKit.C_BORDER, 6))
	prompt_key = UiKit.label("E", 18, UiKit.C_TEXT, 700)
	keybox.add_child(prompt_key)
	ph.add_child(keybox)
	prompt_label = UiKit.label("", 21, UiKit.C_WHITE, 600, 4)
	ph.add_child(prompt_label)
	prompt_box.visible = false
	# Rótulo grande
	banner_box = UiKit.vbox(0)
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(banner_box)
	UiKit.band(banner_box, 0.0, 140, 120)
	banner_title = UiKit.label("", 52, UiKit.C_WHITE, 700, 10)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_title)
	banner_sub = UiKit.label("", 22, Color(1.0, 0.92, 0.7), 500, 6)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_sub)
	banner_box.modulate.a = 0.0
	# Avisos
	toast_box = UiKit.vbox(6)
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)
	UiKit.place(toast_box, Vector2(0, 1), Vector2(24, -300), Vector2(520, 240))
	# Carrera
	race_box = UiKit.dark_panel(12)
	race_box.custom_minimum_size = Vector2(240, 0)
	race_label = UiKit.label("", 28, UiKit.C_WHITE, 700, 6)
	race_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_box.add_child(race_label)
	race_box.visible = false
	var race_band := CenterContainer.new()
	race_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(race_band)
	UiKit.band(race_band, 0.0, 84, 60)
	race_band.add_child(race_box)
	# Pesca: aviso y barras de recogida y tensión del sedal
	fish_box = UiKit.dark_panel(14)
	fish_box.custom_minimum_size = Vector2(460, 0)
	var fv := UiKit.vbox(8)
	fish_box.add_child(fv)
	fish_label = UiKit.label("", 22, UiKit.C_WHITE, 600, 4)
	fish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fv.add_child(fish_label)
	fish_bars = UiKit.vbox(6)
	fv.add_child(fish_bars)
	fish_progress = _bar(fish_bars, "Recoger", Color(0.4, 0.8, 0.95))
	fish_tension = _bar(fish_bars, "Tensión", Color(1.0, 0.55, 0.4))
	fish_box.visible = false
	var fish_band := CenterContainer.new()
	fish_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fish_band)
	UiKit.band(fish_band, 1.0, -250, 120)
	fish_band.add_child(fish_box)
	# Pistas de controles
	hint_label = UiKit.label("", 17, UiKit.C_WHITE, 500, 4)
	root.add_child(hint_label)
	UiKit.place(hint_label, Vector2(0, 1), Vector2(24, -42), Vector2(900, 30))
	_build_card()
	# Diálogo
	dialogue = DialogueBox.new()
	root.add_child(dialogue)
	dialogue.build()
	# Fundido
	fade = ColorRect.new()
	fade.color = Color(0.06, 0.1, 0.16, 0.0)
	UiKit.full_rect(fade)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)


func update_hud(gp: Gameplay, player: Player, cam: Camera3D, sky: SkyCycle, delta: float) -> void:
	for c in [stamina_wheel, compass, objective_box, hint_label, counters]:
		(c as CanvasItem).visible = not cinematic
	banner_box.visible = not cinematic
	if cinematic:
		prompt_box.visible = false
		race_box.visible = false
		return
	shells_label.text = str(SaveGame.shells())
	feathers_label.text = "%d/%d" % [SaveGame.feathers(), Catalog.TOTAL_FEATHERS]
	clock_label.text = sky.clock_text() + ("  ☾" if sky.is_night() else "")
	# Aguante sobre el hombro de Lía
	stamina_wheel.max_value = player.stamina_max
	stamina_wheel.value = player.stamina
	stamina_wheel.exhausted = player.exhausted
	var shoulder := player.get_global_transform_interpolated().origin + Vector3(0, 1.6, 0)
	if not cam.is_position_behind(shoulder):
		var sp := cam.unproject_position(shoulder)
		var vp := root.get_viewport_rect().size
		var scale_f := root.size.x / maxf(vp.x, 1.0)
		stamina_wheel.position = sp * scale_f + Vector2(42, -46)
	stamina_wheel.tick(delta)
	# Brújula
	compass.cam_yaw = player.cam_yaw
	compass.player_pos = player.global_position
	compass.markers = _compass_markers(gp)
	compass.queue_redraw()
	# Objetivo
	var q := gp.tracked_quest()
	var obj := gp.next_objective()
	objective_box.visible = obj != "" and not dialogue.visible
	objective_title.text = q.get("title", "Siguiente paso")
	objective_text.text = obj
	if obj != _last_obj:
		_last_obj = obj
		_hint_show = 14.0
	_hint_show -= delta
	var hint := gp.next_hint()
	hint_text.visible = _hint_show > 0.0 and hint != ""
	hint_text.text = "Pista: " + hint
	if not hint_text.visible and hint != "":
		hint_text.visible = true
		hint_text.text = "H: ver pista"
		hint_text.modulate.a = 0.75
	else:
		hint_text.modulate.a = 1.0
	# Interacción
	var pt := gp.prompt_text()
	prompt_box.visible = pt != "" and not dialogue.visible
	if prompt_box.visible:
		prompt_label.text = pt
	# Carrera
	race_box.visible = gp.race_active()
	if race_box.visible:
		var r: Dictionary = gp.race
		if r["state"] == "countdown":
			var cd := int(ceil(r["countdown"]))
			race_label.text = str(cd) if cd <= 3 else "¿Preparada?"
		else:
			race_label.text = "%.1f s   ·   %d/%d" % [maxf(r["time"], 0.0), r["idx"], (r["rings"] as Array).size()]
			race_label.add_theme_color_override("font_color", Color(1, 0.5, 0.45) if r["time"] < 10.0 else UiKit.C_WHITE)
	_update_fishing(gp)
	# Pistas
	_hint_t += delta
	hint_label.text = "" if fish_box.visible else _hint(player)


## Barra horizontal con su nombre; devuelve el relleno (se ajusta con su `anchor_right`).
func _bar(parent: Control, text: String, col: Color) -> ColorRect:
	var row := UiKit.hbox(10)
	parent.add_child(row)
	var l := UiKit.label(text, 18, UiKit.C_WHITE, 500, 3)
	l.custom_minimum_size.x = 92
	row.add_child(l)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.15)
	bg.custom_minimum_size = Vector2(320, 16)
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bg)
	var fill := ColorRect.new()
	fill.color = col
	fill.anchor_bottom = 1.0
	fill.anchor_right = 0.5
	bg.add_child(fill)
	return fill


func _update_fishing(gp: Gameplay) -> void:
	var f := gp.fishing
	fish_box.visible = f != null and f.active() and f.phase != "catch"
	if not fish_box.visible:
		return
	match f.phase:
		"cast", "wait":
			fish_label.text = "Espera a que el flotador se hunda del todo · Q: dejarlo"
		"bite":
			fish_label.text = "¡Pica! ¡Pulsa E!"
		"reel":
			fish_label.text = "Mantén E para recoger · suelta si se tensa"
	fish_bars.visible = f.phase == "reel"
	fish_progress.anchor_right = clampf(f.progress, 0.0, 1.0)
	fish_tension.anchor_right = clampf(f.tension, 0.0, 1.0)
	fish_tension.color = Color(1.0, 0.55, 0.4).lerp(Color(1.0, 0.2, 0.2), smoothstep(0.6, 0.95, f.tension))


func _hint(player: Player) -> String:
	match player.state:
		"climb":
			return "Escalando · Espacio: impulso · Q: soltarse · Atrás + Espacio: saltar hacia atrás"
		"glide":
			return "Planeando · Espacio o Q: cerrar la paravela"
		"swim":
			return "Nadando · Shift: nadar rápido (gasta aguante)"
		"sit":
			return "Descansando · el tiempo pasa más deprisa · muévete para levantarte"
		"air":
			if player.has_glider and player.velocity.y < 2.0:
				return "Espacio: abrir la paravela"
	if _hint_t < 40.0:
		return "WASD: moverse · Espacio: saltar · Shift: correr · E: hablar · M: mapa · Esc: menú"
	return ""


func _compass_markers(gp: Gameplay) -> Array:
	var out := []
	var q := gp.tracked_quest()
	if not q.is_empty() and q.get("target", Vector3.ZERO) != Vector3.ZERO:
		out.append({"pos": q["target"], "kind": "quest", "color": UiKit.C_GOLD, "radius": q.get("radius", 0.0)})
	for id in Catalog.BEACONS:
		var lit := SaveGame.flag("lit_" + id)
		out.append({"pos": gp.places.anchor(id), "kind": "beacon", "color": Places.REGION_COLORS[id] if lit else Color(0.75, 0.8, 0.85)})
	if SaveGame.owns("shop_compass"):
		var best := INF
		var bp := Vector3.ZERO
		for p in gp.pickups:
			if p["kind"] == "feather":
				var d: float = (p["pos"] as Vector3).distance_to(gp.player.global_position)
				if d < best:
					best = d
					bp = p["pos"]
		if best < INF:
			out.append({"pos": bp, "kind": "feather", "color": UiKit.C_GOLD})
	return out


# --- Rótulos y avisos -----------------------------------------------------------------

func show_banner(title: String, sub: String) -> void:
	_banner_queue.append([title, sub])
	if not _banner_busy:
		_next_banner()


func _next_banner() -> void:
	if _banner_queue.is_empty():
		_banner_busy = false
		return
	if cinematic or dialogue.visible:
		get_tree().create_timer(0.4).timeout.connect(_next_banner)
		return
	_banner_busy = true
	var b: Array = _banner_queue.pop_front()
	banner_title.text = b[0]
	banner_sub.text = b[1]
	var tw := create_tween()
	banner_box.modulate.a = 0.0
	tw.tween_property(banner_box, "modulate:a", 1.0, 0.4)
	tw.chain().tween_interval(2.6)
	tw.chain().tween_property(banner_box, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(_next_banner)


func show_toast(text: String, icon_kind := "") -> void:
	var p := UiKit.dark_panel(10)
	var h := UiKit.hbox(8)
	p.add_child(h)
	if icon_kind != "":
		h.add_child(UiKit.icon(icon_kind, 24))
	h.add_child(UiKit.label(text, 19, UiKit.C_WHITE, 500, 3))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toast_box.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).free()


func fade_to(alpha: float, time := 0.5) -> Tween:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", alpha, time)
	return tw


func set_gameplay_visible(v: bool) -> void:
	cinematic = not v
	for c in [stamina_wheel, compass, objective_box, prompt_box, race_box, hint_label, counters]:
		(c as CanvasItem).visible = v and c != prompt_box and c != race_box


func show_hint() -> void:
	_hint_show = 14.0


# --- Tarjeta de descubrimiento -------------------------------------------------------

func _build_card() -> void:
	card = UiKit.panel(UiKit.C_PANEL, UiKit.C_GOLD.darkened(0.25), 22, 24)
	root.add_child(card)
	UiKit.place(card, Vector2(1, 1), Vector2(-640, -250), Vector2(600, 0))
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.custom_minimum_size = Vector2(600, 0)
	var v := UiKit.vbox(6)
	card.add_child(v)
	var ribbon := PanelContainer.new()
	ribbon.add_theme_stylebox_override("panel", UiKit.box(UiKit.C_GOLD, 10, 0, UiKit.C_BORDER, 10))
	var rl := UiKit.label("¡NUEVO EN EL CUADERNO!", 16, Color(0.35, 0.22, 0.05), 700)
	ribbon.add_child(rl)
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(ribbon)
	var h := UiKit.hbox(16)
	v.add_child(h)
	card_icon = UiKit.icon("star", 72)
	h.add_child(card_icon)
	var tv := UiKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	card_title = UiKit.label("", 40, UiKit.C_TEXT, 700)
	tv.add_child(card_title)
	card_cat = UiKit.label("", 18, UiKit.C_ACCENT.darkened(0.2), 600)
	tv.add_child(card_cat)
	card_desc = UiKit.label("", 21, UiKit.C_TEXT)
	card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_desc.custom_minimum_size.x = 550
	v.add_child(card_desc)
	card_continue = UiKit.label("E · Continuar", 18, UiKit.C_MUTED, 600)
	card_continue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(card_continue)
	card.visible = false


func show_card(title: String, category: String, desc: String, icon_kind: String) -> void:
	card_title.text = title
	card_cat.text = category
	card_desc.text = desc
	card_icon.kind = icon_kind
	card.visible = true
	card_ready = false
	card_continue.modulate.a = 0.0
	card.modulate.a = 0.0
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.9, 0.9)
	if _card_tw:
		_card_tw.kill()
	var tw := create_tween().set_parallel(true)
	_card_tw = tw
	tw.tween_property(card, "modulate:a", 1.0, 0.45).set_delay(0.5)
	tw.tween_property(card, "scale", Vector2.ONE, 0.6).set_delay(0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(vignette, "modulate:a", 1.0, 0.6)
	tw.chain().tween_interval(0.7)
	tw.chain().tween_callback(func() -> void:
		card_ready = true
		card_continue.create_tween().tween_property(card_continue, "modulate:a", 1.0, 0.3))


func hide_card() -> void:
	card_ready = false
	if _card_tw:
		_card_tw.kill()
	var tw := create_tween().set_parallel(true)
	_card_tw = tw
	tw.tween_property(card, "modulate:a", 0.0, 0.25)
	tw.tween_property(vignette, "modulate:a", 0.45, 0.6)
	tw.chain().tween_callback(func() -> void: card.visible = false)
