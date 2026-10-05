extends Node
## Pruebas sin ventana: isla, colocación de objetos, historia completa por código, tiendas,
## dinero (recompensas y repartos), mascotas, guardado y movimiento con piloto automático.
## Uso: Godot --headless --path . -- --ib-test

var main
var _fails := 0
var _checks := 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FALLO: ", what)


func _ready() -> void:
	await get_tree().process_frame
	SaveGame.new_game()
	main._reset_world()
	main.gameplay.skip_showcase = true
	await get_tree().process_frame
	_test_island()
	_test_placements()
	_test_story()
	_test_shop_and_save()
	await _test_economy_and_pets()
	await _test_fishing()
	await _test_movement()
	print("IB_TEST %s checks=%d fails=%d" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_island() -> void:
	var isl: Island = main.world.island
	_check(absf(isl.height_at(Island.MOUNT.x, Island.MOUNT.y) - Island.SUMMIT_Y) < 1.0, "la cima está a la altura prevista")
	_check(isl.height_at(Island.CLIFF.x + 6, Island.CLIFF.y) > 40.0, "la meseta del acantilado es alta")
	_check(isl.height_at(Island.ISLET.x, Island.ISLET.y) > 15.0, "el islote sobresale del mar")
	var mid := (Island.PENON + Island.ISLET) * 0.5
	_check(isl.height_at(mid.x, mid.y) < -2.0, "entre el Peñón y el islote hay mar")
	_check(isl.height_at(Island.LAKE.x, Island.LAKE.y) < Island.LAKE_LEVEL - 3.0, "el lago es profundo")
	var rim_ok := true
	for i in 72:
		for rr: float in [50.0, 54.0, 57.0]:
			var a := TAU * i / 72.0
			var p := Island.LAKE + Vector2(cos(a), sin(a)) * rr
			if isl.height_at(p.x, p.y) < Island.LAKE_LEVEL:
				rim_ok = false
	_check(rim_ok, "el borde del lago está por encima del agua")
	_check(isl.is_land(Island.VILLAGE.x, Island.VILLAGE.y), "el pueblo está en tierra")
	var shore: Vector3 = main.world.places.anchor("shore")
	_check(shore.y < 1.0 and shore.z > Island.VILLAGE.y, "la orilla del muelle está al sur del pueblo")


func _test_placements() -> void:
	var gp: Gameplay = main.gameplay
	var isl: Island = main.world.island
	var shells := 0
	for p in gp.pickups:
		var pos: Vector3 = p["pos"]
		_check(pos.y > isl.water_level(pos.x, pos.z) - 0.2, "%s no está bajo el agua (%s)" % [p["id"], pos])
		if p["kind"] == "shell":
			shells += 1
	_check(shells == Catalog.SHELL_COUNT, "hay %d conchas (%d)" % [Catalog.SHELL_COUNT, shells])
	for id in Catalog.FEATHERS:
		var found := false
		for p in gp.pickups:
			found = found or p["id"] == id
		_check(found, "la pluma %s está en el mundo" % id)
	for id in Catalog.CHESTS:
		var c: Dictionary = gp.chests[id]
		var pos: Vector3 = (c["root"] as Node3D).position
		_check(isl.is_land(pos.x, pos.z) or pos.y > 1.0, "el cofre %s está en tierra" % id)
	for id in Catalog.KITTENS:
		_check(gp.kittens.has(id), "el gatito %s está en el mundo" % id)
	for id in Catalog.NPCS:
		var npc: Npc = gp.npcs[id]
		_check(npc.position.y > isl.water_level(npc.position.x, npc.position.z), "%s está en tierra firme" % id)
	_check(main.world.places.race_rings.size() == 8, "la carrera tiene 8 anillos")
	var top: Vector3 = main.world.places.anchor("race_top")
	var glide_ok := true
	for r in main.world.places.race_rings:
		var d := Vector2(r.x - top.x, r.z - top.z).length()
		var ground: float = main.world.island.height_at(r.x, r.z)
		if r.y > top.y - d / 4.6 + 0.5 and r.y - ground > 3.0:
			glide_ok = false
	_check(glide_ok, "los anillos se alcanzan planeando desde la torre o corriendo")


func _run(d: Dictionary) -> void:
	var after: Callable = d.get("after", Callable())
	if after.is_valid():
		after.call()


func _test_story() -> void:
	var gp: Gameplay = main.gameplay
	_check(gp.next_objective().contains("Tomeu"), "el primer objetivo es hablar con Tomeu")
	_check(gp.npc_has_news("tomeu"), "Tomeu tiene algo que decir al empezar")
	_run(gp._talk_tomeu())
	_check(SaveGame.flag("intro_done"), "tras Tomeu, la introducción termina")
	_check(gp.tracked_quest().get("id", "") == "arrival", "el encargo activo es la llegada")
	_run(gp._talk_rosa())
	_check(SaveGame.flag("met_rosa"), "Rosa da el encargo de la paravela")
	_check(gp.tracked_quest().get("id", "") == "glider", "el encargo activo es la paravela")
	_run(gp._talk_nerea())
	_check(SaveGame.flag("kite_quest"), "Nerea pide recuperar la paravela")
	var q := gp.tracked_quest()
	_check((q["target"] as Vector3).distance_to(main.world.places.anchor("needle_top")) < 1.0, "el objetivo apunta a la Roca Aguja")
	# Recoger la cometa
	var kite := {}
	for p in gp.pickups:
		if p["id"] == "kite":
			kite = p
	_check(not kite.is_empty(), "la paravela está en la Roca Aguja")
	gp._collect(kite)
	_check(SaveGame.flag("has_kite"), "recoger la paravela la añade")
	_run(gp._talk_nerea())
	_check(SaveGame.flag("has_glider") and main.player.has_glider, "Nerea entrega la paravela")
	_check(gp.tracked_quest().get("id", "") == "beacons", "después toca encender los faros")
	# Faros
	_check(gp._beacon_ready("faro_cliff"), "el faro del acantilado se enciende al llegar")
	_check(not gp._beacon_ready("faro_forest"), "el faro del bosque necesita chispas")
	_check(not gp._beacon_ready("faro_ruins"), "el faro de las ruinas necesita la carrera")
	_check(not gp._beacon_ready("faro_summit"), "el Gran Faro necesita los cuatro faros")
	var f0 := SaveGame.feathers()
	gp._light_beacon("faro_cliff")
	_check(SaveGame.flag("lit_faro_cliff"), "encender el faro del acantilado")
	for id in Catalog.SPARKS:
		SaveGame.collect(id)
	_check(gp._beacon_ready("faro_forest"), "con tres chispas el faro del bosque está listo")
	gp._light_beacon("faro_forest")
	gp._light_beacon("faro_islet")
	SaveGame.set_flag("race_won")
	_check(gp._beacon_ready("faro_ruins"), "tras la carrera el faro de las ruinas está listo")
	gp._light_beacon("faro_ruins")
	_check(gp.lit_count() == 4, "cuatro faros encendidos")
	_check(gp._beacon_ready("faro_summit"), "el Gran Faro se puede encender")
	_check(gp.tracked_quest().get("id", "") == "summit", "el encargo activo es el Gran Faro")
	# Las plumas de los faros se dan al acabar la escena: simularlo.
	for i in 4:
		gp._grant_feather("prueba")
	_check(SaveGame.feathers() == f0 + 4, "cada faro da una pluma dorada")
	_check(is_equal_approx(main.player.stamina_max, 3.0 + SaveGame.feathers()), "las plumas aumentan el aguante")
	# Encargos secundarios
	_run(gp._talk_bruno())
	_check(SaveGame.flag("letters_taken"), "Bruno da las cartas")
	_check(gp._letters_left() == 3, "tres cartas por entregar")
	_run(gp._talk_ulises())
	_run(gp._talk_gema())
	_run(gp._talk_olga())
	_check(gp._letters_left() == 0, "las tres cartas se entregan al hablar")
	var before := SaveGame.feathers()
	var shells_b := SaveGame.shells()
	_run(gp._talk_bruno())
	_check(SaveGame.flag("bruno_done") and SaveGame.feathers() == before + 1 and SaveGame.owns("hat_postman"), "Bruno recompensa con pluma y gorra")
	_check(SaveGame.shells() == shells_b + Catalog.REWARDS["letters"], "Bruno paga %d conchas por el correo" % Catalog.REWARDS["letters"])
	_run(gp._talk_pia())
	for id in Catalog.KITTENS:
		gp._pet_kitten(id)
	_run(gp._talk_pia())
	_check(SaveGame.flag("pia_done"), "Pía recompensa al encontrar los gatitos")
	for id in Catalog.MUSHROOMS:
		SaveGame.collect(id)
	_run(gp._talk_ulises())
	_check(SaveGame.flag("ulises_done"), "Ulises recompensa por las setas")
	# Cofres
	var shells0 := SaveGame.shells()
	gp._open_chest("chest_windmill")
	_check(SaveGame.shells() == shells0 + 15, "el cofre del molino da 15 conchas")
	gp._open_chest("chest_ruins")
	_check(SaveGame.owns("hat_crown"), "el cofre de las ruinas da la corona")
	# Pistas: cada paso pendiente tiene una pista y cada encargo un destino
	SaveGame.data["flags"].erase("pia_done")
	SaveGame.data["flags"].erase("ulises_done")
	for qq in gp.quests():
		for st in qq["steps"]:
			_check(st.size() > 2 and String(st[2]).length() > 20, "el paso «%s» tiene pista" % st[0])
	_check(gp.describe_location(main.world.places.anchor("faro_summit")).contains("norte"), "describe_location orienta hacia el norte del Pico")
	_check(SaveGame.in_journal("kitten") and SaveGame.in_journal("chest") and SaveGame.in_journal("kite"), "el cuaderno registra lo descubierto")
	SaveGame.set_flag("pia_done")
	SaveGame.set_flag("ulises_done")
	# Final
	gp._light_beacon("faro_summit")
	_check(SaveGame.flag("lit_faro_summit"), "el Gran Faro se enciende")
	var main_left := 0
	for qq in gp.quests():
		if qq["main"] and not qq["done"]:
			main_left += 1
	_check(main_left == 0, "no quedan encargos de la historia")
	_check(SaveGame.feathers() <= Catalog.TOTAL_FEATHERS, "las plumas no superan el total")
	# El estado de la escena del faro se resuelve en main; devolverlo a jugar.
	main.state = "play"
	main.player.locked = false
	main.gameplay.locked = false


func _test_shop_and_save() -> void:
	SaveGame.data["shells"] = 200
	main.menus._buy("scarf_sky")
	_check(SaveGame.owns("scarf_sky") and SaveGame.equipped("scarf") == "scarf_sky", "comprar una bufanda la equipa")
	var f := SaveGame.feathers()
	main.menus._buy("shop_feather")
	_check(SaveGame.feathers() == f + 1, "la pluma de la tienda aumenta las plumas")
	_check(SaveGame.shells() == 200 - 15 - 60, "las compras gastan conchas")
	main.menus.close()
	var text := JSON.stringify(SaveGame.data)
	var parsed = JSON.parse_string(text)
	var copy := SaveGame.default_data()
	SaveGame._merge(copy, parsed)
	_check(copy["flags"].get("lit_faro_summit", false) and copy["shells"] == SaveGame.shells(), "el guardado conserva el progreso")
	_check(copy["equipped"]["scarf"] == "scarf_sky", "el guardado conserva el aspecto")


func _test_economy_and_pets() -> void:
	var gp: Gameplay = main.gameplay
	var pl: Places = main.world.places
	# Vecinos y comercios nuevos
	for id in ["valeria", "lola"]:
		_check(gp.npcs.has(id), "%s está en el pueblo" % id)
	_check(pl.pen_animals.size() == 4, "hay animales en el cercado del refugio")
	for shop_id in Catalog.SHOPS:
		for id in Catalog.SHOPS[shop_id]["items"]:
			var it: Array = Catalog.ITEMS[id]
			_check(int(it[2]) > 0, "%s tiene precio en %s" % [id, shop_id])
	_run(gp._talk_valeria())
	_check(main.menus.kind == "shop" and main.menus._shop_id == "tailor", "Valeria abre la sastrería")
	main.resume()
	_run(gp._talk_lola())
	_check(main.menus.kind == "shop" and main.menus._shop_id == "pets", "Lola abre el refugio")
	main.resume()
	# Repartos de Correos (Bruno ya terminó su encargo)
	_run(gp._talk_bruno())
	var to := gp.parcel_target()
	_check(to != "" and to != "bruno" and Catalog.NPCS.has(to), "Bruno da un paquete para otro vecino (%s)" % to)
	_check(gp.npc_has_news(to), "el destinatario del paquete tiene aviso")
	var has_q := false
	for q in gp.quests():
		has_q = has_q or q["id"] == "parcel"
	_check(has_q, "el reparto aparece en la lista de encargos")
	var pay := gp._parcel_reward(to)
	_check(pay >= Catalog.REWARDS["parcel_min"] and pay <= Catalog.REWARDS["parcel_max"], "la propina del reparto está en su rango (%d)" % pay)
	var s0 := SaveGame.shells()
	gp._finish_parcel(pay)
	_check(SaveGame.shells() == s0 + pay and gp.parcel_target() == "" and SaveGame.counter("parcels_done") == 1, "entregar el paquete paga la propina")
	_run(gp._talk_bruno())
	_check(gp.parcel_target() != "" and gp.parcel_target() != to, "el siguiente paquete va a otra persona")
	# Ropa
	SaveGame.data["shells"] = 600
	main.menus._buy("outfit_sailor")
	_check(SaveGame.equipped("outfit") == "outfit_sailor", "comprar un conjunto lo pone")
	_check((main.player.avatar.spec["shirt"] as Color).is_equal_approx(Catalog.ITEMS["outfit_sailor"][3][0]), "Lía lleva la camisa del conjunto")
	main.menus._buy("hat_beanie")
	_check(SaveGame.equipped("hat") == "hat_beanie" and main.player.avatar.hat_holder.get_child_count() > 0, "el gorro de lana se ve puesto")
	# Mascotas
	_check(gp.pet == null, "al empezar no hay mascota")
	main.menus._buy("pet_dog")
	main.menus.close()
	_check(SaveGame.equipped("pet") == "pet_dog" and gp.pet != null and gp.pet.kind == "dog", "adoptar a Canela la trae contigo")
	_check(SaveGame.shells() == 600 - 45 - 30 - 120, "la ropa y la mascota cuestan lo que marcan")
	var far: Vector3 = main.world.places.anchor("pia_house_door")
	main.player.teleport(far)
	await _frames(20)
	_check(gp.pet.global_position.distance_to(main.player.global_position) < 6.0, "la mascota aparece junto a Lía tras un viaje largo")
	var s1 := SaveGame.shells()
	gp.pet.found_shells.emit(2)
	_check(SaveGame.shells() == s1 + 2, "lo que encuentra la mascota suma conchas")
	SaveGame.equip("pet", "pet_none")
	main.apply_looks()
	_check(gp.pet == null, "quitar la mascota la retira del mundo")
	SaveGame.equip("pet", "pet_parrot")
	main.apply_looks()
	await _frames(30)
	_check(gp.pet != null and gp.pet.kind == "parrot" and gp.pet.global_position.y > main.player.global_position.y + 0.5, "el loro vuela sobre Lía")
	# Partida antigua sin las ranuras nuevas
	var old := SaveGame.default_data()
	old["equipped"].erase("outfit")
	old["owned"].erase("pet_none")
	var copy := SaveGame.default_data()
	SaveGame._merge(copy, old)
	_check(not copy["equipped"].has("outfit"), "(la prueba de partida antigua parte sin ranura de ropa)")
	_check(Catalog.look_for(copy["equipped"])["shirt"] is Color, "una partida antigua usa la ropa de serie")


func _test_fishing() -> void:
	var gp: Gameplay = main.gameplay
	_run(gp._talk_tomeu())
	_check(SaveGame.flag("has_rod"), "Tomeu regala la caña de pescar")
	# En el muelle, mirando al mar.
	main.player.teleport(main.world.places.anchor("spawn") + Vector3(0, 0.2, 0), PI)
	await _frames(20)
	var spot := gp.fishing_spot()
	_check(not spot.is_empty() and spot.get("kind", "") == "sea", "desde el muelle se puede pescar en el mar")
	var f: Fishing = gp.fishing
	f.auto_input = {}
	gp.start_fishing()
	_check(f.active() and main.player.locked, "empieza a pescar y Lía se queda quieta")
	await _frames(50)
	_check(f.phase == "wait", "el flotador cae al agua (%s)" % f.phase)
	f._wait = 0.0
	f._nibbles = 0
	f._nibble_t = INF
	await _frames(3)
	_check(f.phase == "bite", "pica un pez")
	f.fish_id = "fish_sardine"
	f.auto_input = {"press": true}
	await _frames(2)
	f.auto_input = {}
	_check(f.phase == "reel", "al pulsar E se clava el anzuelo")
	var guard := 0
	var max_tension := 0.0
	while f.active() and guard < 60 * 40:
		f.auto_input = {"hold": f.tension < 0.6}
		max_tension = maxf(max_tension, f.tension)
		await get_tree().process_frame
		guard += 1
	_check(int(SaveGame.data["fish"].get("fish_sardine", 0)) >= 1, "recogiendo con cuidado se pesca la sardina (tensión máx %.2f)" % max_tension)
	_check(not main.player.locked, "al terminar Lía puede moverse")
	_check(gp.fish_species() >= 1, "la sardina cuenta para la colección")
	var has_q := false
	for q in gp.quests():
		has_q = has_q or q["id"] == "fishing"
	_check(has_q, "la colección de peces aparece en los encargos")
	var value := gp.fish_value()
	var s0 := SaveGame.shells()
	_run(gp._talk_tomeu())
	_check(value > 0 and SaveGame.shells() == s0 + value and gp.fish_value() == 0, "Tomeu compra el pescado (%d conchas)" % value)
	# Romper el sedal: tirar sin soltar nunca
	gp.start_fishing()
	await _frames(50)
	f._wait = 0.0
	f._nibbles = 0
	await _frames(3)
	f.fish_id = "fish_octopus"
	f.auto_input = {"press": true}
	await _frames(2)
	guard = 0
	while f.active() and guard < 60 * 20:
		f.auto_input = {"hold": true}
		await get_tree().process_frame
		guard += 1
	_check(int(SaveGame.data["fish"].get("fish_octopus", 0)) == 0, "si no se suelta nunca, el sedal se rompe")
	f.auto_input = null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _test_movement() -> void:
	var p: Player = main.player
	var pl: Places = main.world.places
	var isl: Island = main.world.island
	main.state = "test"
	p.visible = true
	p.locked = false
	p.stamina_max = 3.0
	# Escalar la Roca Aguja con el aguante inicial
	var needle := pl.anchor("needle")
	var start := needle + Vector3(-6, 0, 0)
	start.y = isl.height_at(start.x, start.z) + 0.3
	p.teleport(start)
	p.refill_stamina()
	await _frames(20)
	var reached := false
	for i in 60 * 14:
		var d := Vector3(needle.x - p.global_position.x, 0, needle.z - p.global_position.z).normalized()
		p.cam_yaw = atan2(-d.x, -d.z)
		p.autopilot = {"move": Vector2(0, -1)}
		await get_tree().physics_frame
		if p.state == "ground" and p.global_position.y > pl.anchor("needle_top").y - 1.5:
			reached = true
			break
	_check(reached, "Lía escala la Roca Aguja con 3 de aguante")
	# Planear del Peñón al islote
	p.has_glider = true
	var pen := pl.anchor("penon")
	var islet := pl.anchor("faro_islet")
	p.teleport(pen + Vector3(0, 0.5, 0))
	p.refill_stamina()
	await _frames(20)
	var landed_ok := false
	for i in 60 * 50:
		var d := Vector3(islet.x - p.global_position.x, 0, islet.z - p.global_position.z).normalized()
		p.cam_yaw = atan2(-d.x, -d.z)
		var jump := p.state == "air" and i % 8 < 2
		p.autopilot = {"move": Vector2(0, -1), "jump": jump}
		await get_tree().physics_frame
		if i > 120 and p.state == "ground" and Vector2(p.global_position.x - islet.x, p.global_position.z - islet.z).length() < 20.0:
			landed_ok = true
			break
		if p.state == "swim":
			break
	_check(landed_ok, "Lía llega planeando al islote (acaba en %s)" % p.state)
	# Subir al tejado de Pía (gatito del tejado)
	var roof: Vector3 = pl.anchor("pia_roof")
	var house: Vector3 = pl.anchor("pia_house")
	var door: Vector3 = pl.anchor("pia_house_door")
	var from := door + (door - house).normalized() * 2.0
	from.y = isl.height_at(from.x, from.z) + 0.3
	p.teleport(from)
	p.refill_stamina()
	await _frames(20)
	var on_roof := false
	for i in 60 * 15:
		var d := Vector3(roof.x - p.global_position.x, 0, roof.z - p.global_position.z)
		if d.length() > 0.3:
			d = d.normalized()
		p.cam_yaw = atan2(-d.x, -d.z)
		p.autopilot = {"move": Vector2(0, -1) if Vector2(roof.x - p.global_position.x, roof.z - p.global_position.z).length() > 1.0 else Vector2.ZERO}
		await get_tree().physics_frame
		if Vector2(p.global_position.x - roof.x, p.global_position.z - roof.z).length() < 2.4 and absf(p.global_position.y - roof.y) < 3.0:
			on_roof = true
			break
	_check(on_roof, "Lía llega al tejado de Pía (y=%.1f, tejado %.1f, %s)" % [p.global_position.y, roof.y, p.state])
	# Carrera del Viento
	SaveGame.set_flag("has_glider")
	var gp: Gameplay = main.gameplay
	gp.start_race()
	var won := false
	for i in 60 * 60:
		if gp.race.is_empty():
			won = SaveGame.flag("race_won")
			break
		if gp.race["state"] == "run":
			var target: Vector3 = gp.race["rings"][gp.race["idx"]]["root"].position
			var to := target - p.global_position
			var dh := Vector3(to.x, 0, to.z)
			p.cam_yaw = atan2(-dh.x, -dh.z)
			var jump := false
			var drop := false
			match p.state:
				"ground":
					jump = i % 20 == 0
				"air":
					jump = p.velocity.y < 0.0 and to.y > -4.0 and i % 6 == 0
				"glide":
					drop = to.y < -6.0 and dh.length() < 25.0
			p.autopilot = {"move": Vector2(0, -1), "jump": jump, "drop": drop}
		await get_tree().physics_frame
	var best := float(SaveGame.data["flags"].get("race_best", 0.0))
	_check(won, "la Carrera del Viento se puede ganar a tiempo (sobran %.1f s)" % best)
	if not gp.race.is_empty():
		print("   carrera: anillo %d de 8, tiempo %.1f" % [gp.race["idx"], gp.race["time"]])
		gp._end_race(false)
	p.autopilot = null
