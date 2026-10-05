class_name Gameplay
extends Node3D
## Reglas del juego en el mundo: vecinos y sus diálogos, coleccionables, cofres, faros,
## Carrera del Viento, repartos, mascota, recompensas, descubrimiento de lugares y encargos.
## La interfaz (diálogos, avisos, tienda, escenas) la pone Main a través de señales.

signal say(lines: Array, on_done: Callable)
signal toast(text: String, icon: String)
signal banner(title: String, subtitle: String)
## Abre un comercio de Catalog.SHOPS.
signal open_shop(shop_id: String)
signal beacon_cutscene(id: String, on_done: Callable)
signal ending_requested
signal stamina_upgraded
## Escena de primer encuentro: entrada del cuaderno, modo (item, creature, npc), foco y continuación.
signal showcase(entry: String, mode: String, focus: Node3D, on_done: Callable)

const SHELL_RADIUS := 1.3
## Vecinos que pasean por su zona (radio en metros); el resto se queda en su sitio.
const WANDER := {"pia": 7.0, "bruno": 5.0, "nerea": 5.0, "tito": 6.0, "ulises": 6.0, "gema": 6.0}

var world: World
var player: Player
var places: Places
var island: Island
var npcs := {}
var pickups: Array = []
var interactables: Array = []
var chests := {}
var kittens := {}
var current: Dictionary = {}
var race := {}
var wind := 0.0
var locked := false
var talking_npc: Npc
## Las pruebas automáticas saltan las escenas de primer encuentro.
var skip_showcase := false

var _discover_t := 0.0
var _shell_combo := 0
var _shell_combo_t := 0.0
var _t := 0.0
var _fireflies: GPUParticles3D
var _beacon_beams := {}
var _meow_t := 3.0
var _hinted := {}
var pet: Pet
var _pet_interact: Dictionary
var fishing: Fishing
var _fish_interact := {}
## Barca del jugador (cuando ya la tiene) y su punto para subir.
var my_boat: Node3D
var _boat_interact := {}
## Regata: {buoys, idx, time, countdown, state}
var regatta := {}
## Ovejas del prado: punto de interacción de cada una.
var _sheep_interacts: Array = []
var _npc_interacts := {}
var _pen_t := {}


func setup(w: World, p: Player) -> void:
	world = w
	player = p
	places = w.places
	island = w.island
	player.updrafts.clear()
	player.updrafts.append([places.anchor("updraft_penon"), 3.5, 26.0])
	player.updrafts.append([places.anchor("updraft_ruins"), 3.5, 30.0])
	_spawn_npcs()
	_spawn_pickups()
	_spawn_chests()
	_spawn_kittens()
	_setup_beacons()
	_setup_race_stone()
	_setup_fireflies()
	_setup_benches()
	_setup_fishing()
	if player.on_bike:
		player.set_bike(false)
	player.boat = null
	_setup_farm()
	_setup_board()
	_spawn_daily()
	_spawn_lost_sheep()
	refresh_boat()
	world.sky.day_passed.connect(_on_new_day)
	refresh_pet()
	apply_progress()


# --- Utilidades -------------------------------------------------------------------------

func resolve(anchor: String, offset := Vector3.ZERO) -> Vector3:
	if anchor.begins_with("@"):
		var parts := anchor.substr(1).split(",")
		var p := Vector2(float(parts[0]), float(parts[1]))
		return island.ground(_flat_spot(p)) + offset
	var base := places.anchor(anchor)
	if offset != Vector3.ZERO and offset.y == 0.0 and anchor != "pillar_top" and not anchor.ends_with("_top"):
		var q := base + offset
		return island.ground(Vector2(q.x, q.z))
	return base + offset


## Punto llano y en tierra más cercano a `p` (los cofres y setas no quedan en cuestas).
func _flat_spot(p: Vector2) -> Vector2:
	for r in range(0, 80, 2):
		var steps := maxi(1, r * 2)
		for k in steps:
			var a := TAU * k / steps
			var q := p + Vector2(cos(a), sin(a)) * r
			if island.height_at(q.x, q.y) < island.water_level(q.x, q.y) + 0.6:
				continue
			if island.normal_at(q.x, q.y).y > 0.9 and _is_free(q):
				return q
	return p


func _is_free(q: Vector2) -> bool:
	for t in world.flora.tree_points:
		if Vector2(t.x, t.z).distance_to(q) < 1.6:
			return false
	return true


func lit_count() -> int:
	var n := 0
	for id in Catalog.REGULAR_BEACONS:
		if SaveGame.flag("lit_" + id):
			n += 1
	return n


func _add_interact(id: String, pos: Vector3, radius: float, prompt: Callable, action: Callable, active := Callable()) -> Dictionary:
	var it := {"id": id, "pos": pos, "radius": radius, "prompt": prompt, "action": action, "active": active}
	interactables.append(it)
	return it


func _remove_interact(id: String) -> void:
	for i in range(interactables.size() - 1, -1, -1):
		if interactables[i]["id"] == id:
			interactables.remove_at(i)


# --- Vecinos -------------------------------------------------------------------------------

func _spawn_npcs() -> void:
	for id in Catalog.NPCS:
		var data: Dictionary = Catalog.NPCS[id]
		var npc := Npc.new()
		add_child(npc)
		npc.setup(id, data)
		npc.position = places.anchor(data["anchor"])
		var to := Vector3(Island.VILLAGE.x, 0, Island.VILLAGE.y) - npc.position
		if to.length() < 3.0 or id in ["tomeu"]:
			to = Vector3(0, 0, -1)
		npc.base_yaw = atan2(-to.x, -to.z)
		npc.avatar.rotation.y = npc.base_yaw
		npc.player = player
		npc.island = island
		npc.home = npc.position
		npc.wander_radius = WANDER.get(id, 0.0)
		npc.blockers = _house_blockers()
		npcs[id] = npc
		var nid: String = id
		_npc_interacts[id] = _add_interact("npc_" + id, npc.position, 2.8, func() -> String: return "Hablar con " + data["name"], func() -> void: talk(nid))


## Casas del pueblo y otras construcciones que los vecinos rodean al pasear: [centro, radio].
func _house_blockers() -> Array:
	var out := []
	for k in ["town_hall", "pia_house", "post", "workshop", "house_a", "house_b", "house_c", "house_d"]:
		if places.anchors.has(k):
			out.append([places.anchors[k], 5.2])
	out.append([places.anchor("village"), 3.6])
	if places.anchors.has("pen"):
		out.append([places.anchors["pen"], 4.6])
	if places.anchors.has("stall"):
		out.append([places.anchors["stall"], 2.4])
	out.append_array(places.obstacles)
	for b in places.benches:
		out.append([b[0], 1.2])
	return out


func talk(id: String) -> void:
	var npc: Npc = npcs[id]
	npc.talking = true
	talking_npc = npc
	var to := npc.global_position - player.global_position
	player.facing = atan2(-to.x, -to.z)
	maybe_showcase("npc_" + id, "npc", npc, func() -> void:
		var d: Dictionary = call("_talk_" + id)
		var lines: Array = d["lines"]
		var after: Callable = d.get("after", Callable())
		if parcel_target() == id:
			var pay := _parcel_reward(id)
			var who: String = Catalog.NPCS[id]["name"].split(" ")[-1]
			lines = [_l(who, "¿Un paquete de Correos para mí? ¡Por fin! Toma, Lía: %d conchas por traérmelo." % pay)] + lines
			var inner := after
			after = func() -> void:
				_finish_parcel(pay)
				if inner.is_valid():
					inner.call()
		say.emit(lines, func() -> void:
			npc.talking = false
			talking_npc = null
			if after.is_valid():
				after.call()
			apply_progress()))


## Lanza la escena de primer encuentro si es la primera vez; si no, continúa directamente.
func maybe_showcase(entry: String, mode: String, focus: Node3D, cb: Callable) -> void:
	if SaveGame.in_journal(entry) or skip_showcase or showcase.get_connections().is_empty():
		SaveGame.add_journal(entry)
		cb.call()
		return
	SaveGame.add_journal(entry)
	showcase.emit(entry, mode, focus, cb)


func _l(who: String, text: String) -> Array:
	return [who, text]


func _talk_tomeu() -> Dictionary:
	if not SaveGame.flag("intro_done"):
		return {"lines": [
			_l("Tomeu", "¡Ah del barco! Bienvenida a Isla Brisa, Lía. ¡Cuánto tiempo sin verte por aquí!"),
			_l("Tomeu", "Tu abuela Olga se va a poner contentísima. Sigue viviendo junto al Acantilado del Este."),
			_l("Tomeu", "Aunque llegas en un momento raro... ¿Lo notas? Ni una brizna de viento. Las velas cuelgan como trapos."),
			_l("Tomeu", "Los Faros del Viento se apagaron hace una semana, y desde entonces el viento se ha olvidado de nosotros."),
			_l("Tomeu", "Sube al pueblo y habla con la alcaldesa Rosa, junto a la fuente. Ella sabrá qué hacer."),
			_l("Tomeu", "Ah, y mira los controles: muévete con WASD, salta con Espacio y corre más rápido con Shift."),
		], "after": func() -> void:
			SaveGame.set_flag("intro_done")
			toast.emit("Nuevo encargo: Llegada a Isla Brisa", "quest")
			Audio.play("quest_new")}
	if SaveGame.flag("met_rosa") and not SaveGame.flag("has_rod"):
		return {"lines": [
			_l("Tomeu", "¡Lía! Mientras vuelve el viento, ¿por qué no pescas un poco? Toma mi caña de repuesto."),
			_l("Tomeu", "Acércate al agua, mira hacia ella y pulsa E. Espera a que el flotador se hunda del todo y entonces, ¡E! Los mordisqueos no cuentan."),
			_l("Tomeu", "Luego mantén E para recoger el sedal, pero suelta si se tensa demasiado o se romperá. Te compro todo lo que pesques."),
			_l("Tomeu", "Y si consigues pescar de todo, hasta la Brisa dorada... te daré algo que guardo desde hace años."),
		], "after": func() -> void:
			SaveGame.set_flag("has_rod")
			maybe_showcase("rod", "item", null, func() -> void:
				banner.emit("¡Caña de pescar!", "Mira hacia el agua y pulsa E")
				Audio.play("item"))}
	var boat_talk := _talk_tomeu_boat()
	var sale := _tomeu_fish_sale()
	if not sale.is_empty() and not boat_talk.is_empty():
		# Primero compra el pescado y luego habla de la barca, en la misma conversación.
		var sale_after: Callable = sale["after"]
		var boat_after: Callable = boat_talk.get("after", Callable())
		return {"lines": sale["lines"] + boat_talk["lines"], "after": func() -> void:
			sale_after.call()
			if boat_after.is_valid():
				boat_after.call()}
	if not boat_talk.is_empty():
		return boat_talk
	if fish_species() >= Catalog.FISH.size() and not SaveGame.flag("fish_done"):
		return {"lines": [
			_l("Tomeu", "¿Has pescado de todo? ¿¡También la Brisa dorada!? Cuarenta años intentándolo...") ,
			_l("Tomeu", "Toma, mi bufanda dorada de la suerte. Y unas conchas, que te las has ganado."),
		], "after": func() -> void:
			SaveGame.set_flag("fish_done")
			SaveGame.give("scarf_gold")
			reward(100, "Pescadora de Isla Brisa")
			banner.emit("¡Bufanda dorada!", "Póntela en Esc → Aspecto")
			Audio.play("quest_done")}
	if not sale.is_empty():
		return sale
	if SaveGame.flag("ending_seen"):
		return {"lines": [_l("Tomeu", "¡Mira esas velas, hinchadas como panzas! Gracias a ti, mañana salgo a pescar.")]}
	if lit_count() > 0:
		return {"lines": [_l("Tomeu", "He notado una brisilla en la cara, ¿sabes? Algo estás haciendo bien, Lía.")]}
	return {"lines": [_l("Tomeu", "La alcaldesa Rosa está en la plaza, junto a la fuente. Sigue el camino de tierra hacia el norte.")]}


func _talk_rosa() -> Dictionary:
	if not SaveGame.flag("met_rosa"):
		return {"lines": [
			_l("Rosa", "¡Lía! ¡Pero qué mayor estás! Tomeu ya me avisó de que llegabas en su barca."),
			_l("Rosa", "La isla tiene cinco Faros del Viento: cuatro repartidos por la costa y el Gran Faro, en lo alto del Pico Brisa."),
			_l("Rosa", "Encendidos, llaman al viento. Sin viento no giran los molinos, no vuelan las cometas... ni zarpan los barcos."),
			_l("Rosa", "Tu abuela Olga los cuidaba, pero ya no está para trepar acantilados. ¿Nos echarías una mano?"),
			_l("Lía", "¡Claro que sí! ¿Por dónde empiezo?"),
			_l("Rosa", "Primero necesitarás una paravela para moverte por la isla. Nerea, la de las cometas, estaba terminando una..."),
			_l("Rosa", "...pero creo que se le escapó volando. Su taller es la casa del tejado turquesa, al oeste de la plaza."),
		], "after": func() -> void:
			SaveGame.set_flag("met_rosa")
			toast.emit("Nuevo encargo: La paravela perdida", "quest")
			Audio.play("quest_new")}
	var bouquet := _talk_rosa_flowers()
	if not bouquet.is_empty():
		return bouquet
	if SaveGame.flag("ending_seen"):
		return {"lines": [_l("Rosa", "Gracias, Lía. Isla Brisa vuelve a respirar. Esta noche haremos una fiesta de cometas en tu honor.")]}
	if SaveGame.flag("lit_faro_summit"):
		return {"lines": [_l("Rosa", "¡Lo has logrado! ¡Escucha el viento!")]}
	var n := lit_count()
	if not SaveGame.flag("has_glider"):
		return {"lines": [_l("Rosa", "Habla con Nerea, en su taller del tejado turquesa. Con su paravela podrás llegar a cualquier rincón.")]}
	if n == 4:
		return {"lines": [
			_l("Rosa", "¡Los cuatro faros brillan! ¿Notas cómo se mueven las hojas?"),
			_l("Rosa", "Ahora sube al Pico Brisa y enciende el Gran Faro. Es la última pieza."),
		]}
	var lines := [_l("Rosa", "Faros encendidos: %d de 4. ¡Cada uno trae un poco más de brisa!" % n)]
	for id in Catalog.REGULAR_BEACONS:
		if not SaveGame.flag("lit_" + id):
			var info := _beacon_step(id)
			lines.append(_l("Rosa", "El %s está %s. %s" % [Catalog.BEACONS[id][0], describe_location(places.anchor(id)), info[1]]))
			break
	lines.append(_l("Rosa", "Y si te pierdes, abre el mapa con M: la flecha amarilla marca adónde ir."))
	return {"lines": lines}


func _talk_nerea() -> Dictionary:
	if SaveGame.flag("has_glider"):
		var extra := ""
		if lit_count() >= 2:
			extra = " ¡Y ya noto el viento en los dedos!"
		return {"lines": [_l("Nerea", "Cuando vuelva el viento del todo, llenaré el cielo de cometas." + extra)]}
	if SaveGame.flag("has_kite"):
		return {"lines": [
			_l("Nerea", "¡Mi paravela! ¡La has encontrado! Y ni un rasguño... bueno, uno pequeñito."),
			_l("Nerea", "Quédatela, te la has ganado. Cuando estés en el aire, pulsa Saltar otra vez para abrirla."),
			_l("Nerea", "Planear también gasta aguante, pero muy poco. Y si te metes en una corriente de viento que sube... ¡whoosh! Te elevará."),
			_l("Nerea", "Hay una en lo alto del Peñón del Salto y otra junto a la rampa de las Ruinas del Viento."),
			_l("Nerea", "Ah, y toma estas conchas por las molestias. ¡Gástatelas en la sastrería de Valeria!"),
		], "after": func() -> void:
			SaveGame.set_flag("has_glider")
			player.has_glider = true
			reward(Catalog.REWARDS["glider"], "La paravela perdida")
			maybe_showcase("glider", "item", null, func() -> void:
				banner.emit("¡Paravela!", "En el aire, pulsa Saltar para planear")
				Audio.play("item"))}
	if SaveGame.flag("kite_quest"):
		return {"lines": [
			_l("Nerea", "Mi paravela sigue en lo alto de la Roca Aguja: el pilar de piedra junto al molino, " + describe_location(places.anchor("needle")) + "."),
			_l("Nerea", "Camina contra la roca y no la sueltes. Si se te acaba el aguante, baja y vuelve a intentarlo."),
		]}
	if SaveGame.flag("met_rosa"):
		return {"lines": [
			_l("Nerea", "¿Te manda Rosa? Ay, mi paravela... La estaba probando en la Colina del Molino y la última ráfaga que hubo se la llevó."),
			_l("Nerea", "Se quedó enganchada en lo alto de la Roca Aguja, al lado del molino. Yo no sé trepar, pero tú pareces ágil."),
			_l("Nerea", "Para escalar, camina contra una pared y no la sueltes. Cansa, así que vigila tu círculo de aguante."),
			_l("Nerea", "Si te quedas sin aguante, te soltarás. Puedes descansar en cualquier saliente."),
		], "after": func() -> void:
			SaveGame.set_flag("kite_quest")}
	return {"lines": [_l("Nerea", "¡Hola! Soy Nerea, hago cometas. Bueno, las hacía... sin viento no hay manera.")]}


func _talk_bruno() -> Dictionary:
	if not SaveGame.flag("letters_taken"):
		return {"lines": [
			_l("Bruno", "¡Correo de Isla Brisa, a su servicio! Más o menos... Sin viento, el barco del correo no llega y yo no puedo salir."),
			_l("Bruno", "Tengo tres cartas atascadas. ¿Me harías el favor de repartirlas?"),
			_l("Bruno", "Una para Ulises, en la cabaña del Lago Espejo. Otra para Gema, que acampa al pie de las Ruinas del Viento."),
			_l("Bruno", "Y la tercera... ¡para tu abuela Olga! Seguro que te alegra llevársela."),
		], "after": func() -> void:
			SaveGame.set_flag("letters_taken")
			maybe_showcase("letters", "item", null, func() -> void:
				toast.emit("Nuevo encargo: Correo urgente", "letter")
				Audio.play("quest_new"))}
	var left := _letters_left()
	if left > 0:
		return {"lines": [_l("Bruno", "Te quedan %d %s por repartir. ¡Ánimo, cartera!" % [left, "carta" if left == 1 else "cartas"])]}
	if not SaveGame.flag("bruno_done"):
		return {"lines": [
			_l("Bruno", "¿Todas entregadas? ¡Eres más rápida que el barco del correo!"),
			_l("Bruno", "Toma: una pluma dorada que llegó en un paquete sin remitente, mi gorra de repuesto y tu paga de cartera."),
			_l("Bruno", "Y si quieres ganarte más conchas, pásate cuando quieras: siempre tengo paquetes por repartir."),
		], "after": func() -> void:
			SaveGame.set_flag("bruno_done")
			SaveGame.give("hat_postman")
			reward(Catalog.REWARDS["letters"], "Correo urgente")
			_grant_feather("Recompensa de Bruno")
			Audio.play("quest_done")}
	var to := parcel_target()
	if to != "":
		return {"lines": [_l("Bruno", "El paquete es para %s. Está %s." % [Catalog.NPCS[to]["name"], describe_location(npcs[to].position)])]}
	if SaveGame.counter("parcels_done") >= 3 and not SaveGame.flag("has_bike"):
		return {"lines": [
			_l("Bruno", "¡Tres repartos sin perder ni un sello! Eres la mejor cartera que ha tenido la isla."),
			_l("Bruno", "Toma mi bici de repuesto. Con ella llegarás a cualquier buzón en un periquete. Pulsa V para subir y bajar."),
		], "after": func() -> void:
			SaveGame.set_flag("has_bike")
			player.has_bike = true
			maybe_showcase("bike", "item", null, func() -> void:
				banner.emit("¡Bici de cartero!", "Pulsa V para subir o bajar")
				Audio.play("item"))}
	var next := _pick_parcel_target()
	var who: String = Catalog.NPCS[next]["name"]
	return {"lines": [
		_l("Bruno", "¿Vienes a por trabajo? ¡Tengo un paquete para %s!" % who),
		_l("Bruno", "Está %s. Te dará una propina al recibirlo: cuanto más lejos, más conchas." % describe_location(npcs[next].position)),
	], "after": func() -> void:
		SaveGame.data["flags"]["parcel_to"] = next
		SaveGame.changed.emit()
		maybe_showcase("parcel", "item", null, func() -> void:
			toast.emit("Reparto: lleva el paquete a " + who, "parcel")
			Audio.play("quest_new"))}


func _letters_left() -> int:
	var n := 0
	for who in Catalog.LETTERS:
		if not SaveGame.flag("letter_" + who):
			n += 1
	return n


func _deliver_letter(who: String) -> bool:
	if SaveGame.flag("letters_taken") and not SaveGame.flag("letter_" + who):
		SaveGame.set_flag("letter_" + who)
		Audio.play("item")
		toast.emit("Carta entregada (%d/3)" % (3 - _letters_left()), "letter")
		return true
	return false


func _talk_pia() -> Dictionary:
	var found := SaveGame.count_collected("kitten_")
	if not SaveGame.flag("pia_quest"):
		return {"lines": [
			_l("Pía", "¡Mis gatitos se han escapado! ¡Los cuatro! Sin viento se aburren y se van de aventuras."),
			_l("Pía", "Uno se subió a un tejado del pueblo, otro se fue al muelle, otro se metió en el bosque..."),
			_l("Pía", "...y el más valiente, ¡a las Ruinas del Viento! Si los encuentras, háblales y vendrán solos a casa."),
		], "after": func() -> void:
			SaveGame.set_flag("pia_quest")
			toast.emit("Nuevo encargo: Los gatitos de Pía", "kitten")
			Audio.play("quest_new")}
	if found < 4:
		var lines := [_l("Pía", "¡Ya han vuelto %d! Me faltan %d." % [found, 4 - found])]
		var hint := _kitten_hint()
		if hint != "":
			lines.append(_l("Pía", hint))
		return {"lines": lines}
	if not SaveGame.flag("pia_done"):
		return {"lines": [
			_l("Pía", "¡Están todos! ¡Gracias, gracias, gracias!"),
			_l("Pía", "Toma, la encontré brillando en el jardín. Mi madre dice que es una pluma de las aves del viento."),
			_l("Pía", "¡Y mi hucha entera! Para que te compres una mascota en el refugio de Lola."),
		], "after": func() -> void:
			SaveGame.set_flag("pia_done")
			reward(Catalog.REWARDS["kittens"], "Los gatitos de Pía")
			_grant_feather("Regalo de Pía")
			Audio.play("quest_done")}
	return {"lines": [_l("Pía", "Los gatitos ya no se escapan. Bueno... casi nunca.")]}


func _talk_marisol() -> Dictionary:
	return {"lines": [
		_l("Marisol", "¡Bienvenida al puesto de Marisol! Aquí todo se paga en conchas." if not SaveGame.flag("met_marisol") else "¿Qué te apetece hoy, Lía?"),
	] + ([_l("Marisol", "Las conchas aparecen en las playas. ¡Y en los cofres escondidos por la isla!")] if not SaveGame.flag("met_marisol") else []),
		"after": func() -> void:
			SaveGame.set_flag("met_marisol")
			open_shop.emit("marisol")}


func _talk_valeria() -> Dictionary:
	if not SaveGame.flag("met_valeria"):
		return {"lines": [
			_l("Valeria", "¡Hola, hola! Soy Valeria, la sastra. Tú debes de ser la nieta de Olga: tienes su misma bufanda."),
			_l("Valeria", "Coso ropa para toda la isla. Conjuntos, sombreros... Lo que te pruebes, lo verás puesto antes de pagar."),
			_l("Valeria", "Si te faltan conchas, Bruno siempre busca quien reparta paquetes. ¡Y los vecinos pagan bien sus encargos!"),
		], "after": func() -> void:
			SaveGame.set_flag("met_valeria")
			open_shop.emit("tailor")}
	if SaveGame.flag("boat_quest") and not SaveGame.flag("has_sail"):
		if SaveGame.bag_count("wool") >= 3:
			return {"lines": [
				_l("Valeria", "¿Lana para la vela de Tomeu? ¡Qué suave! Dame un momento..."),
				_l("Valeria", "Hilo, aguja, un poco de cera para que no entre el agua... ¡Lista! La vela más bonita del puerto."),
			], "after": func() -> void:
				SaveGame.bag_take("wool", 3)
				SaveGame.set_flag("has_sail")
				toast.emit("Vela nueva: llévasela a Tomeu", "boat")
				Audio.play("quest_done", 0.0, -4.0)}
		return {"lines": [_l("Valeria", "Para coser una vela nueva necesito 3 ovillos de lana (tienes %d). Las ovejas de Amparo tienen de sobra." % SaveGame.bag_count("wool"))],
			"after": func() -> void: open_shop.emit("tailor")}
	return {"lines": [_l("Valeria", "¿Vienes a renovar el armario? Pasa, pasa.")],
		"after": func() -> void: open_shop.emit("tailor")}


func _talk_lola() -> Dictionary:
	if not SaveGame.flag("met_lola"):
		return {"lines": [
			_l("Lola", "¡Bienvenida al refugio! Yo soy Lola. Aquí cuido de los animales que buscan una familia."),
			_l("Lola", "Si adoptas a uno, te seguirá a todas partes. Y tienen buen olfato: a veces escarban y encuentran conchas."),
			_l("Lola", "Pídeme una ración de cariño de vez en cuando: acércate a tu mascota y pulsa E para acariciarla."),
		], "after": func() -> void:
			SaveGame.set_flag("met_lola")
			open_shop.emit("pets")}
	if pet:
		return {"lines": [_l("Lola", "¡Qué buena pinta tiene %s! Se nota que la cuidas." % pet.pet_name)],
			"after": func() -> void: open_shop.emit("pets")}
	return {"lines": [_l("Lola", "Los animales del cercado están deseando conocerte.")],
		"after": func() -> void: open_shop.emit("pets")}


func _talk_ulises() -> Dictionary:
	var lines := []
	var after := Callable()
	if _deliver_letter("ulises"):
		lines.append(_l("Ulises", "¿Una carta? ¡Es de mi hermana! Hacía meses que no sabía de ella. Gracias, muchacha."))
	if not SaveGame.flag("met_ulises"):
		lines.append_array([
			_l("Ulises", "Hmm, visitas. Soy Ulises. Vivo aquí con el lago, que es buen conversador si sabes escuchar."),
			_l("Ulises", "¿Ves la chispa de luz en el islote del lago? Lleva ahí desde que se apagaron los faros. Dicen que el Faro del Bosque se alimenta de ellas."),
			_l("Ulises", "Por cierto: en el Bosque Susurro crecen setas que brillan. De noche se ven desde lejos. Tráeme cinco y te daré algo especial."),
		])
		after = func() -> void:
			SaveGame.set_flag("met_ulises")
			toast.emit("Nuevo encargo: Setas brillantes", "mushroom")
			Audio.play("quest_new")
	elif not SaveGame.flag("ulises_done"):
		var m := SaveGame.count_collected("mushroom_")
		if m >= 5:
			lines.append_array([
				_l("Ulises", "¡Cinco setas brillantes! Con ellas el lago se verá precioso de noche."),
				_l("Ulises", "Toma esta pluma dorada. La encontré flotando en el lago hace muchos años. Y unas conchas para el camino."),
			])
			after = func() -> void:
				SaveGame.set_flag("ulises_done")
				reward(Catalog.REWARDS["mushrooms"], "Setas brillantes")
				_grant_feather("Regalo de Ulises")
				Audio.play("quest_done")
		elif lines.is_empty():
			lines.append(_l("Ulises", "Setas brillantes: %d de 5. Búscalas entre los árboles del Bosque Susurro; de noche brillan más." % m))
			var near := _nearest_pickup("mushroom")
			if near != Vector3.ZERO:
				lines.append(_l("Ulises", "Hmm... el lago me susurra que hay una " + describe_location(near) + "."))
	elif lines.is_empty():
		lines.append(_l("Ulises", "El lago dice que el viento está volviendo. Y el lago nunca miente."))
	return {"lines": lines, "after": after}


func _talk_gema() -> Dictionary:
	var lines := []
	if _deliver_letter("gema"):
		lines.append(_l("Gema", "¿Carta para mí? ¡Es de la universidad! ¡Me dan otro año para estudiar las ruinas!"))
	if SaveGame.flag("race_won"):
		lines.append(_l("Gema", "¡Lo conseguiste! Desde aquí oí zumbar el pedestal del faro. Los antiguos sí que sabían divertirse."))
	elif not SaveGame.flag("met_gema"):
		lines.append_array([
			_l("Gema", "¡Hola! Soy Gema, arqueóloga. Estas ruinas están llenas de mecanismos antiguos que funcionan con viento."),
			_l("Gema", "El pedestal del Faro de las Ruinas está frío. Según los grabados, se despierta superando la Carrera del Viento."),
			_l("Gema", "Sube a la torre de piedra de las ruinas y toca la piedra de salida. Tendrás que pasar por todos los anillos antes de que se acabe el tiempo."),
			_l("Gema", "Con una paravela es mucho más fácil. Y si te quedas corta de altura, hay una corriente de aire al pie de la rampa."),
		])
	else:
		lines.append(_l("Gema", "La torre de salida está en lo alto de las ruinas. ¡Planea por los anillos, deprisa!"))
	return {"lines": lines, "after": func() -> void: SaveGame.set_flag("met_gema")}


func _talk_olga() -> Dictionary:
	var lines := []
	if not SaveGame.flag("met_olga"):
		lines.append_array([
			_l("Olga", "¡Mi niña! ¡Lía! Ven aquí, que te dé un abrazo. Estás altísima."),
			_l("Olga", "Así que Rosa te ha liado con los faros... Me alegro. Yo ya no tengo rodillas para esos trotes."),
			_l("Olga", "Consejos de farera: el Faro del Acantilado está ahí arriba. Se llega trepando. Ve recta y no te entretengas."),
			_l("Olga", "El del Bosque necesita tres chispas de fuego. El del Islote se alcanza planeando desde el Peñón del Salto."),
			_l("Olga", "Y el de las Ruinas... pregúntale a Gema, la arqueóloga. Ella entiende de cacharros antiguos."),
			_l("Olga", "Y cuando enciendas los cuatro, sube al Pico Brisa. El Gran Faro hará el resto."),
		])
	if _deliver_letter("olga"):
		lines.append(_l("Olga", "¿Una carta de tu madre? ¡Qué alegría! Dice que te portes bien... y que comas. Típico de ella."))
	if lines.is_empty():
		var n := lit_count()
		if SaveGame.flag("ending_seen"):
			lines.append(_l("Olga", "Estoy muy orgullosa de ti, farera Lía. Los faros están en buenas manos."))
		elif n < 4:
			lines.append(_l("Olga", "Llevas %d de 4 faros. Si te falta aguante, busca plumas doradas: cada una te hace un poco más fuerte." % n))
			for id in Catalog.REGULAR_BEACONS:
				if not SaveGame.flag("lit_" + id):
					lines.append(_l("Olga", "Consejo de farera: " + _beacon_step(id)[1]))
					break
		else:
			lines.append(_l("Olga", "¡Los cuatro! Ahora, al Pico Brisa. Desde la cima se ve toda la isla."))
	return {"lines": lines, "after": func() -> void: SaveGame.set_flag("met_olga")}


func _talk_tito() -> Dictionary:
	if SaveGame.flag("lit_faro_islet"):
		return {"lines": [_l("Tito", "¡Te vi volar hasta el islote! ¡Fue lo más alucinante que he visto en mi vida!")]}
	if SaveGame.flag("has_glider"):
		return {"lines": [
			_l("Tito", "¡Tienes una paravela! Sube al Peñón por la rampa, métete en la corriente de aire y planea hacia el islote."),
			_l("Tito", "Ve recto hacia el faro y no gastes aguante dando vueltas. ¡Ojo con caer al mar!"),
		]}
	return {"lines": [
		_l("Tito", "¡Eh! Soy Tito. Desde lo alto del Peñón del Salto se ve el Islote del Faro, ahí en medio del mar."),
		_l("Tito", "Mi abuelo dice que en la cima hay una corriente de aire que te sube por los aires. ¡Si tuviera una paravela...!"),
	]}


func npc_has_news(id: String) -> bool:
	if parcel_target() == id:
		return true
	if id == "tomeu" and (_boat_news() or (SaveGame.flag("has_boat") and not SaveGame.flag("regatta_won"))):
		return true
	if id == "rosa" and SaveGame.flag("met_rosa") and SaveGame.flag("has_glider") and (not SaveGame.flag("flowers_quest") or (SaveGame.bag_count("flower") >= 8 and not SaveGame.flag("flowers_done"))):
		return true
	if id == "bruno" and SaveGame.counter("parcels_done") >= 3 and not SaveGame.flag("has_bike"):
		return true
	match id:
		"tomeu":
			return not SaveGame.flag("intro_done") or (SaveGame.flag("met_rosa") and not SaveGame.flag("has_rod")) \
				or fish_value() > 0 or (fish_species() >= Catalog.FISH.size() and not SaveGame.flag("fish_done"))
		"rosa":
			return SaveGame.flag("intro_done") and not SaveGame.flag("met_rosa")
		"nerea":
			return SaveGame.flag("met_rosa") and not SaveGame.flag("has_glider") and (not SaveGame.flag("kite_quest") or SaveGame.flag("has_kite"))
		"bruno":
			return SaveGame.flag("met_rosa") and (not SaveGame.flag("letters_taken") or (_letters_left() == 0 and not SaveGame.flag("bruno_done")))
		"pia":
			return SaveGame.flag("met_rosa") and (not SaveGame.flag("pia_quest") or (SaveGame.count_collected("kitten_") >= 4 and not SaveGame.flag("pia_done")))
		"ulises":
			return not SaveGame.flag("met_ulises") or (SaveGame.flag("letters_taken") and not SaveGame.flag("letter_ulises")) or (SaveGame.count_collected("mushroom_") >= 5 and not SaveGame.flag("ulises_done"))
		"gema":
			return not SaveGame.flag("met_gema") or (SaveGame.flag("letters_taken") and not SaveGame.flag("letter_gema"))
		"olga":
			return not SaveGame.flag("met_olga") or (SaveGame.flag("letters_taken") and not SaveGame.flag("letter_olga"))
		"valeria":
			return (SaveGame.flag("met_rosa") and not SaveGame.flag("met_valeria")) \
				or (SaveGame.flag("boat_quest") and not SaveGame.flag("has_sail") and SaveGame.bag_count("wool") >= 3)
		"amparo":
			return not SaveGame.flag("met_amparo") or (SaveGame.flag("boat_quest") and not SaveGame.flag("has_shears")) \
				or (SaveGame.flag("sheep_quest") and SaveGame.count_collected("lostsheep_") >= 3 and not SaveGame.flag("sheep_done"))
		"rafa":
			return not SaveGame.flag("met_rafa") or (SaveGame.flag("bread_quest") and not SaveGame.flag("bread_done") \
				and SaveGame.bag_count("egg") >= 4 and SaveGame.bag_count("apple") >= 3)
		"lola":
			return SaveGame.flag("met_rosa") and not SaveGame.flag("met_lola")
	return parcel_target() == id


# --- Dinero, repartos y mascota --------------------------------------------------------------

## Da conchas con aviso y sonido.
func reward(n: int, why: String) -> void:
	SaveGame.add_shells(n)
	toast.emit("+%d conchas · %s" % [n, why], "shell")
	Audio.play("buy", 0.0, -2.0)
	SaveGame.save_game()


## Vecino al que hay que llevar el paquete de Correos ("" si no hay reparto en curso).
func parcel_target() -> String:
	return String(SaveGame.data["flags"].get("parcel_to", ""))


func _pick_parcel_target() -> String:
	var options := []
	var last := String(SaveGame.data["flags"].get("parcel_last", ""))
	for id in Catalog.NPCS:
		if id in ["bruno", last]:
			continue
		options.append(id)
	return options[randi() % options.size()]


## Propina según lo lejos que está el destinatario de Correos.
func _parcel_reward(id: String) -> int:
	var d := Vector2(npcs[id].position.x - npcs["bruno"].position.x, npcs[id].position.z - npcs["bruno"].position.z).length()
	return clampi(int(Catalog.REWARDS["parcel_min"] + d / 14.0), Catalog.REWARDS["parcel_min"], Catalog.REWARDS["parcel_max"])


func _finish_parcel(pay: int) -> void:
	SaveGame.data["flags"]["parcel_last"] = parcel_target()
	SaveGame.data["flags"]["parcel_to"] = ""
	var n := SaveGame.add_counter("parcels_done")
	reward(pay, "Reparto entregado (%d en total)" % n)
	Audio.play("quest_done", 0.0, -3.0)


# --- Pesca ------------------------------------------------------------------------------------

func _setup_fishing() -> void:
	fishing = Fishing.new()
	fishing.name = "Fishing"
	add_child(fishing)
	fishing.player = player
	fishing.island = island
	fishing.sky = world.sky
	fishing.finished.connect(_on_fish)
	fishing.message.connect(func(t: String) -> void: toast.emit(t, "fish"))
	_fish_interact = {"id": "fish", "pos": Vector3.ZERO, "radius": 99.0, "active": Callable(),
		"prompt": func() -> String: return "Pescar",
		"action": func() -> void: start_fishing()}


## Punto del agua delante de Lía donde echar la caña ({point, kind}) o vacío si no se puede.
func fishing_spot() -> Dictionary:
	if not SaveGame.flag("has_rod") or player.state != "ground" or race_active():
		return {}
	var fwd := Vector3(-sin(player.facing), 0, -cos(player.facing))
	for d: float in [4.0, 5.5, 7.0]:
		var p := player.global_position + fwd * d
		var wl := island.water_level(p.x, p.z)
		var py := player.global_position.y
		if island.height_at(p.x, p.z) < wl - 0.8 and py > wl - 0.2 and py < wl + 4.5:
			return {"point": Vector3(p.x, wl, p.z), "kind": "lake" if wl > Island.SEA_LEVEL + 1.0 else "sea"}
	return {}


func start_fishing() -> void:
	var spot := fishing_spot()
	if spot.is_empty():
		return
	fishing.start(spot["point"], spot["kind"])


func _on_fish(id: String, size: int) -> void:
	if id == "":
		return
	var fish: Dictionary = SaveGame.data["fish"]
	fish[id] = int(fish.get(id, 0)) + 1
	var best_key := "fish_best_" + id
	var record := size > SaveGame.counter(best_key)
	if record:
		SaveGame.data["flags"][best_key] = size
	SaveGame.add_counter("fish_caught")
	SaveGame.save_game()
	var info: Array = Catalog.FISH[id]
	var sub := "Bueno... algo es algo" if id == "fish_boot" else ("%d cm · ¡nuevo récord!" % size if record else "%d cm" % size)
	maybe_showcase(id, "item", null, func() -> void:
		banner.emit("¡%s!" % info[0], sub)
		if fish_species() >= Catalog.FISH.size() and not SaveGame.flag("fish_done"):
			toast.emit("¡Has pescado de todo! Cuéntaselo a Tomeu", "fish"))


## Conchas que paga Tomeu por lo que llevas en la cesta.
func fish_value() -> int:
	var total := 0
	for id in SaveGame.data["fish"]:
		total += int(SaveGame.data["fish"][id]) * int(Catalog.FISH[id][4])
	return total


## Cuántas especies distintas has pescado alguna vez.
func fish_species() -> int:
	var n := 0
	for id in Catalog.FISH:
		if SaveGame.counter("fish_best_" + id) > 0:
			n += 1
	return n


## Bancos: sentarse a descansar. Sentada, el tiempo pasa deprisa (para esperar a la noche).
func _setup_benches() -> void:
	for i in places.benches.size():
		var b: Array = places.benches[i]
		var seat: Vector3 = b[0]
		var yaw: float = b[1]
		_add_interact("bench_%d" % i, seat, 1.8, func() -> String: return "Sentarse a descansar",
			func() -> void: player.sit_at(seat, yaw))


## Crea (o quita) la mascota según lo que lleva puesto Lía.
func refresh_pet() -> void:
	var spec = Catalog.pet_for(SaveGame.data["equipped"])
	var want := "" if spec == null else String(spec[0]) + String(spec[1])
	var have := "" if pet == null else pet.kind + pet.pet_name
	if want == have:
		return
	if pet:
		pet.queue_free()
		pet = null
		_remove_interact("pet")
		_pet_interact = {}
	if spec == null:
		return
	pet = Pet.new()
	pet.name = "Pet"
	add_child(pet)
	pet.setup(spec[0], spec[1], spec[2], player, island)
	pet.snap_to_player()
	pet.found_shells.connect(func(n: int) -> void:
		SaveGame.add_shells(n)
		toast.emit("¡%s ha encontrado %d %s!" % [pet.pet_name, n, "concha" if n == 1 else "conchas"], "shell")
		Audio.play("shell", 0.05)
		Fx.burst(self, pet.global_position + Vector3(0, 0.4, 0), Color(1.0, 0.8, 0.7), 10, 2.5, 0.12))
	_pet_interact = _add_interact("pet", pet.global_position, 1.8,
		func() -> String: return "Acariciar a " + pet.pet_name,
		func() -> void: _pet_the_pet(),
		func() -> bool: return pet != null and player.velocity.length() < 0.5)


func _pet_the_pet() -> void:
	if pet == null:
		return
	pet.pet_me()
	player.play_action("kneel", 1.2, pet.global_position)
	Fx.burst(self, pet.global_position + Vector3(0, 0.7, 0), Color(1.0, 0.45, 0.55), 8, 1.6, 0.14, 0.8, 1.2, -0.5)
	Audio.play("meet", 0.1, -6.0)
	maybe_showcase("pet", "creature", pet, func() -> void: pass)


# --- Coleccionables -------------------------------------------------------------------------

func _shell_positions() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4040
	var out := []
	var tries := 0
	while out.size() < Catalog.SHELL_COUNT and tries < 80000:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(120.0, 320.0)
		var p := Vector2(cos(a), sin(a)) * r + Vector2(0, 15)
		if absf(p.x) > 300 or absf(p.y) > 300:
			continue
		if island.biome_at(p.x, p.y) != Island.Biome.SAND:
			continue
		var h := island.height_at(p.x, p.y)
		if h < 0.25 or island.normal_at(p.x, p.y).y < 0.85:
			continue
		var ok := true
		for q in out:
			if Vector2(q.x, q.z).distance_to(p) < 7.0:
				ok = false
				break
		if ok:
			out.append(Vector3(p.x, h + 0.25, p.y))
	return out


func _add_pickup(id: String, kind: String, node: Node3D, pos: Vector3, radius: float) -> void:
	add_child(node)
	node.position = pos
	pickups.append({"id": id, "kind": kind, "node": node, "pos": pos, "radius": radius, "phase": randf() * TAU})


func _spawn_pickups() -> void:
	var shells := _shell_positions()
	for i in shells.size():
		var id := "shell_%d" % i
		if SaveGame.is_collected(id):
			continue
		var n := Props.shell()
		n.scale = Vector3.ONE * 1.5
		_add_pickup(id, "shell", n, shells[i], SHELL_RADIUS)
	for id in Catalog.FEATHERS:
		if SaveGame.is_collected(id):
			continue
		var f: Array = Catalog.FEATHERS[id]
		_add_pickup(id, "feather", _feather_node(), resolve(f[0], f[1]) + Vector3(0, 0.6, 0), 1.7)
	for id in Catalog.SPARKS:
		if SaveGame.is_collected(id):
			continue
		var s: Array = Catalog.SPARKS[id]
		var sn := Props.spark()
		if ResourceLoader.exists("res://assets/audio/sfx_crackle_loop.wav"):
			var crackle := AudioStreamPlayer3D.new()
			crackle.stream = load("res://assets/audio/sfx_crackle_loop.wav")
			crackle.max_distance = 28.0
			crackle.unit_size = 4.0
			crackle.volume_db = -4.0
			crackle.autoplay = true
			sn.add_child(crackle)
		_add_pickup(id, "spark", sn, resolve(s[0]) + s[1], 1.8)
	for id in Catalog.MUSHROOMS:
		if SaveGame.is_collected(id):
			continue
		var m: Array = Catalog.MUSHROOMS[id]
		var node := Props.mushroom(true)
		node.scale = Vector3.ONE * 1.6
		node.add_child(Fx.sparkles(Color(0.55, 0.9, 1.0), 6, 0.6))
		_add_pickup(id, "mushroom", node, resolve(m[0], m[1]), 1.5)
	if not SaveGame.flag("has_kite") and not SaveGame.flag("has_glider"):
		var k := Props.kite(Color(0.98, 0.95, 0.85), Color(0.95, 0.4, 0.35), 1.6)
		_add_pickup("kite", "kite", k, places.anchor("needle_top") + Vector3(0, 1.4, 0), 2.2)


func _feather_node() -> Node3D:
	var n := Props.feather()
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.4)
	l.light_energy = 1.0
	l.omni_range = 5.0
	l.position = Vector3(0, 0.6, 0)
	n.add_child(l)
	var halo := MeshKit.part(n, MeshKit.sphere(0.7, 10), MeshKit.unshaded(Color(1.0, 0.85, 0.4, 0.18), 1.4), Vector3(0, 0.55, 0))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func _collect(p: Dictionary) -> void:
	var id: String = p["id"]
	if p.get("daily", false):
		SaveGame.set_daily(id)
	else:
		SaveGame.collect(id)
	var node: Node3D = p["node"]
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "position:y", node.position.y + 1.2, 0.35)
	tw.tween_property(node, "scale", Vector3.ONE * 0.05, 0.35)
	tw.chain().tween_callback(node.queue_free)
	var kind: String = p["kind"]
	maybe_showcase(kind, "item", null, func() -> void: _collect_effect(p))


func _collect_effect(p: Dictionary) -> void:
	match p["kind"]:
		"shell":
			_shell_combo = mini(_shell_combo + 1, 8) if _shell_combo_t > 0.0 else 0
			_shell_combo_t = 2.0
			Audio.play("shell", 0.0, 0.0, 1.0 + _shell_combo * 0.06)
			SaveGame.add_shells(1)
		"feather":
			_grant_feather("¡Pluma dorada!")
		"spark":
			player.play_action("pickup", 0.45, p["pos"])
			Audio.play("spark")
			var n := SaveGame.count_collected("spark_")
			toast.emit("Chispa de fuego (%d/3)" % n, "spark")
			if n == 3:
				banner.emit("¡Tres chispas!", "Llévalas al Faro del Bosque")
		"mushroom":
			player.play_action("pickup", 0.45, p["pos"])
			Audio.play("item", 0.0, -4.0)
			toast.emit("Seta brillante (%d/5)" % SaveGame.count_collected("mushroom_"), "mushroom")
		"flower":
			player.play_action("pickup", 0.4, p["pos"])
			SaveGame.bag_add("flower")
			Audio.play("item", 0.1, -6.0, 1.2)
			toast.emit("Flor silvestre (%d en la mochila)" % SaveGame.bag_count("flower"), "flower")
		"apple":
			SaveGame.bag_add("apple")
			Audio.play("shell", 0.05, -4.0, 0.8)
			toast.emit("Manzana (%d en la mochila)" % SaveGame.bag_count("apple"), "apple")
		"kite":
			SaveGame.set_flag("has_kite")
			Audio.play("item")
			banner.emit("¡La paravela de Nerea!", "Devuélvesela a Nerea, en el pueblo")
	SaveGame.save_game()


func _grant_feather(title: String) -> void:
	SaveGame.add_feather()
	player.stamina_max = 3.0 + SaveGame.feathers()
	player.refill_stamina()
	Audio.play("feather")
	banner.emit(title, "Pluma dorada %d/%d · ¡Tu aguante aumenta!" % [SaveGame.feathers(), Catalog.TOTAL_FEATHERS])
	stamina_upgraded.emit()
	SaveGame.save_game()


# --- Cofres y gatitos -------------------------------------------------------------------------

func _spawn_chests() -> void:
	for id in Catalog.CHESTS:
		var c: Array = Catalog.CHESTS[id]
		var pos := resolve(c[0], c[1])
		var ch := Props.chest()
		add_child(ch["root"])
		ch["root"].position = pos - Vector3(0, 0.05, 0)
		ch["root"].rotation.y = randf() * TAU
		chests[id] = ch
		if SaveGame.is_collected(id):
			(ch["lid"] as Node3D).rotation.x = -1.9
			continue
		var cid: String = id
		_add_interact(id, pos, 2.2, func() -> String: return "Abrir cofre", func() -> void: _open_chest(cid))


func _open_chest(id: String) -> void:
	_remove_interact(id)
	SaveGame.collect(id)
	var ch: Dictionary = chests[id]
	player.play_action("kneel", 0.7, (ch["root"] as Node3D).global_position)
	var lid: Node3D = ch["lid"]
	lid.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(lid, "rotation:x", -1.9, 0.6)
	Audio.play("chest")
	var reward: String = Catalog.CHESTS[id][2]
	maybe_showcase("chest", "item", null, func() -> void: _chest_reward(reward))


func _chest_reward(reward: String) -> void:
	if reward.begins_with("shells:"):
		var n := int(reward.substr(7))
		SaveGame.add_shells(n)
		banner.emit("¡%d conchas!" % n, "Tienes %d conchas" % SaveGame.shells())
	else:
		SaveGame.give(reward)
		banner.emit("¡%s!" % Catalog.item_name(reward), "Cámbiatelo desde el menú (Esc → Aspecto)")
	SaveGame.save_game()


func _kitten_node(col: Color) -> Node3D:
	var root := Node3D.new()
	var m := MeshKit.mat(col, 0.015)
	MeshKit.part(root, MeshKit.blob(0.2, 0.75, 0.0, 0, 8), m, Vector3(0, 0.17, 0.05), Vector3.ZERO, Vector3(0.85, 1, 1.25))
	MeshKit.part(root, MeshKit.sphere(0.15, 10), m, Vector3(0, 0.33, -0.17))
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(root, MeshKit.cone(0.06, 0.12, 6), m, Vector3(sx * 0.08, 0.48, -0.17), Vector3(0, 0, -sx * 15))
		MeshKit.part(root, MeshKit.sphere(0.022, 5), MeshKit.mat(Color(0.1, 0.1, 0.1), 0.0), Vector3(sx * 0.055, 0.36, -0.305))
	var tail := MeshKit.part(root, MeshKit.capsule(0.03, 0.3), m, Vector3(0, 0.3, 0.3), Vector3(-35, 0, 0))
	tail.name = "Tail"
	return root


func _spawn_kittens() -> void:
	for id in Catalog.KITTENS:
		if SaveGame.is_collected(id):
			continue
		var k: Array = Catalog.KITTENS[id]
		var pos := resolve(k[0], k[1])
		var n := _kitten_node(k[2])
		add_child(n)
		n.position = pos
		n.rotation.y = randf() * TAU
		kittens[id] = n
		var kid: String = id
		_add_interact(id, pos, 2.4, func() -> String: return "Acariciar al gatito", func() -> void: _pet_kitten(kid))
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Voice"
		voice.max_distance = 45.0
		voice.unit_size = 7.0
		voice.position = Vector3(0, 0.4, 0)
		n.add_child(voice)


func _pet_kitten(id: String) -> void:
	_remove_interact(id)
	SaveGame.collect(id)
	var n: Node3D = kittens[id]
	player.play_action("kneel", 1.0, n.global_position)
	maybe_showcase("kitten", "creature", n, func() -> void: _kitten_leaves(id))


func _kitten_leaves(id: String) -> void:
	Audio.play("kitten", 0.08)
	var n: Node3D = kittens[id]
	var tw := n.create_tween()
	tw.tween_property(n, "position:y", n.position.y + 0.6, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.3)
	tw.tween_callback(n.queue_free)
	var found := SaveGame.count_collected("kitten_")
	toast.emit("¡Miau! El gatito vuelve a casa de Pía (%d/4)" % found, "kitten")
	SaveGame.save_game()


# --- Faros ----------------------------------------------------------------------------------

func _setup_beacons() -> void:
	for id in Catalog.BEACONS:
		var bid: String = id
		_add_interact("altar_" + id, places.anchor(id + "_altar"), 2.6,
			func() -> String: return "Encender el faro" if _beacon_ready(bid) else "Examinar el pedestal",
			func() -> void: _altar(bid),
			func() -> bool: return not SaveGame.flag("lit_" + bid))
		_set_beacon_visual(id, SaveGame.flag("lit_" + id), false)


func _beacon_ready(id: String) -> bool:
	match id:
		"faro_forest":
			return SaveGame.count_collected("spark_") >= 3
		"faro_ruins":
			return SaveGame.flag("race_won")
		"faro_summit":
			return lit_count() >= 4
	return true


func _altar(id: String) -> void:
	if _beacon_ready(id):
		_light_beacon(id)
		return
	var lines := []
	match id:
		"faro_forest":
			lines = [_l("", "El pedestal está frío. Tiene tres huecos con forma de llama. (Chispas de fuego: %d/3)" % SaveGame.count_collected("spark_"))]
		"faro_ruins":
			lines = [_l("", "El pedestal está frío. Alrededor hay grabados de anillos y remolinos. Quizá Gema, la arqueóloga, sepa algo.")]
		"faro_summit":
			lines = [_l("", "El Gran Faro duerme. Cuatro surcos rodean el pedestal, uno por faro. (Faros encendidos: %d/4)" % lit_count())]
	Audio.play("error")
	say.emit(lines, Callable())


func _light_beacon(id: String) -> void:
	SaveGame.set_flag("lit_" + id)
	SaveGame.save_game()
	_remove_interact("altar_" + id)
	beacon_cutscene.emit(id, func() -> void:
		if id == "faro_summit":
			ending_requested.emit()
		else:
			_grant_feather("¡%s encendido!" % Catalog.BEACONS[id][0])
			reward(Catalog.REWARDS["beacon"], "Rosa te manda una recompensa")
		apply_progress())
	_set_beacon_visual(id, true, true)
	Audio.play("beacon")


func _set_beacon_visual(id: String, on: bool, animate: bool) -> void:
	var b: Dictionary = places.beacons[id]
	var crystal: MeshInstance3D = b["crystal"]
	var orb: MeshInstance3D = b["orb"]
	crystal.material_override = b["crystal_on"] if on else b["crystal_off"]
	orb.material_override = b["orb_on"] if on else b["orb_off"]
	var light: OmniLight3D = b["light"]
	if animate:
		light.light_energy = 0.0
		create_tween().tween_property(light, "light_energy", 3.0, 2.5)
	else:
		light.light_energy = 3.0 if on else 0.0
	var root: Node3D = b["root"]
	if not on:
		var old := root.get_node_or_null("Beam")
		if old:
			old.queue_free()
		_beacon_beams.erase(id)
	if on and not _beacon_beams.has(id):
		var beam := Node3D.new()
		beam.name = "Beam"
		root.add_child(beam)
		beam.position = b["top"]
		var col: Color = Places.REGION_COLORS[id]
		var mat := MeshKit.unshaded(Color(col.r, col.g, col.b, 0.22).lightened(0.3), 1.3)
		var mi := MeshKit.part(beam, MeshKit.cylinder(1.2, 0.5, 60.0, 12), mat, Vector3(0, 30.0, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beacon_beams[id] = beam
		if animate:
			beam.scale = Vector3(1, 0.01, 1)
			beam.create_tween().tween_property(beam, "scale", Vector3.ONE, 2.0).set_trans(Tween.TRANS_SINE)


# --- Carrera del Viento --------------------------------------------------------------------------

func _setup_race_stone() -> void:
	var top := places.anchor("race_top")
	var stone := Node3D.new()
	add_child(stone)
	stone.position = top + Vector3(0, 0, -0.4)
	MeshKit.part(stone, MeshKit.cylinder(0.35, 0.45, 0.9, 8), MeshKit.mat(Props.STONE, 0.03), Vector3(0, 0.45, 0))
	MeshKit.part(stone, MeshKit.sphere(0.25, 8), MeshKit.mat(Color(0.5, 0.9, 1.0), 0.02, 1.5, Color(0.4, 0.85, 1.0)), Vector3(0, 1.05, 0))
	_add_interact("race_stone", top, 2.2,
		func() -> String: return "Empezar la Carrera del Viento" if not SaveGame.flag("race_won") else "Repetir la Carrera del Viento",
		func() -> void: start_race(),
		func() -> bool: return race.is_empty())


func start_race() -> void:
	if not SaveGame.flag("has_glider"):
		say.emit([_l("", "Grabado en la piedra: «Solo quien vuela con el viento puede seguir los anillos». Necesitas una paravela.")], Callable())
		return
	var rings := []
	var pts: Array = places.race_rings
	for i in pts.size():
		var r := Props.wind_ring(3.4)
		add_child(r["root"])
		r["root"].position = pts[i]
		var next: Vector3 = pts[i + 1] if i + 1 < pts.size() else pts[i] + (pts[i] - pts[i - 1])
		var d: Vector3 = next - pts[i]
		r["root"].rotation.y = atan2(-d.x, -d.z)
		rings.append(r)
	race = {"rings": rings, "idx": 0, "time": 48.0, "countdown": 3.5, "state": "countdown", "last_beep": 4}
	var top := places.anchor("race_top")
	var first: Vector3 = pts[0]
	player.teleport(top + Vector3(0, 0.2, 0), atan2(-(first.x - top.x), -(first.z - top.z)))
	player.locked = true
	_update_rings()


func _update_rings() -> void:
	var rings: Array = race["rings"]
	for i in rings.size():
		var r: Dictionary = rings[i]
		var ring: MeshInstance3D = r["ring"]
		if i < race["idx"]:
			ring.material_override = r["done"]
		elif i == race["idx"]:
			ring.material_override = r["on"]
		else:
			ring.material_override = r["off"]


func _race_process(dt: float) -> void:
	if race.is_empty():
		return
	match race["state"]:
		"countdown":
			race["countdown"] -= dt
			var c := int(ceil(race["countdown"]))
			if c < race["last_beep"] and c <= 3 and c >= 1:
				race["last_beep"] = c
				Audio.play("countdown")
			if race["countdown"] <= 0.0:
				race["state"] = "run"
				player.locked = false
				Audio.play("go")
				banner.emit("¡Ya!", "Pasa por todos los anillos")
		"run":
			race["time"] -= dt
			var rings: Array = race["rings"]
			var idx: int = race["idx"]
			var target: Vector3 = rings[idx]["root"].position
			if (player.global_position + Vector3(0, 0.9, 0)).distance_to(target) < 3.6:
				race["idx"] = idx + 1
				Audio.play("ring", 0.0, 0.0, 1.0 + idx * 0.07)
				_update_rings()
				if race["idx"] >= rings.size():
					_end_race(true)
					return
			if race["time"] <= 0.0:
				_end_race(false)
			for r in rings:
				(r["root"] as Node3D).rotate_object_local(Vector3.FORWARD, dt * 1.5)


func _end_race(won: bool) -> void:
	var rings: Array = race["rings"]
	for r in rings:
		(r["root"] as Node3D).queue_free()
	var t: float = race["time"]
	race = {}
	player.locked = false
	if won:
		var first := not SaveGame.flag("race_won")
		SaveGame.set_flag("race_won")
		var best := float(SaveGame.data["flags"].get("race_best", 0.0))
		if t > best:
			SaveGame.data["flags"]["race_best"] = t
		Audio.play("quest_done")
		banner.emit("¡Carrera del Viento superada!", ("El pedestal de las ruinas despierta" if first else "Te sobraron %.1f s" % t))
		if first:
			reward(Catalog.REWARDS["race_first"], "Carrera del Viento")
		else:
			var pay: int = Catalog.REWARDS["race_again"] + (Catalog.REWARDS["race_record"] if t > best else 0)
			reward(pay, "¡Nuevo récord!" if t > best else "Carrera del Viento")
		SaveGame.save_game()
	else:
		Audio.play("fail")
		banner.emit("¡Casi!", "Toca la piedra de salida para intentarlo otra vez")
	apply_progress()


func race_active() -> bool:
	return not race.is_empty()


# --- Bucle --------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if player == null:
		return
	_t += dt
	_shell_combo_t -= dt
	var pp := player.global_position
	# Animación y recogida de coleccionables
	for i in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[i]
		if not is_instance_valid(p["node"]):
			pickups.remove_at(i)
			continue
		var node: Node3D = p["node"]
		var base: Vector3 = p["pos"]
		node.position.y = base.y + sin(_t * 2.0 + p["phase"]) * 0.12
		node.rotation.y += dt * (2.0 if p["kind"] != "kite" else 0.6)
		if (pp + Vector3(0, 0.8, 0)).distance_to(base) < p["radius"] and not locked:
			pickups.remove_at(i)
			_collect(p)
	_meow_t -= dt
	for id in kittens:
		if is_instance_valid(kittens[id]):
			var n: Node3D = kittens[id]
			if _meow_t <= 0.0 and n.position.distance_to(pp) < 40.0 and not SaveGame.is_collected(id):
				var voice := n.get_node_or_null("Voice") as AudioStreamPlayer3D
				if voice and not voice.playing:
					var path := "res://assets/audio/sfx_meow_%d.wav" % (randi() % 3 + 1)
					if ResourceLoader.exists(path):
						voice.stream = load(path)
						voice.volume_db = linear_to_db(maxf(float(SaveGame.setting("sfx")), 0.001)) - 2.0
						voice.play()
			var tail := n.get_node_or_null("Tail") as Node3D
			if tail:
				tail.rotation.z = sin(_t * 4.0 + n.position.x) * 0.5
	if _meow_t <= 0.0:
		_meow_t = randf_range(4.0, 7.0)
	_hint_cues(pp)
	_race_process(dt)
	if pet and not _pet_interact.is_empty():
		_pet_interact["pos"] = pet.global_position
	var is_night: bool = world.sky.night > 0.5
	for id in _npc_interacts:
		var npc: Npc = npcs[id]
		(_npc_interacts[id] as Dictionary)["pos"] = npc.position
		npc.night = is_night
	# Interacción más cercana
	current = {}
	if not locked and player.state in ["ground", "swim"] and not (fishing and fishing.active()):
		var best := INF
		for it in interactables:
			if it["active"].is_valid() and not it["active"].call():
				continue
			if it["id"] == "pet":
				continue
			var d := Vector2(pp.x - it["pos"].x, pp.z - it["pos"].z).length()
			var dy: float = absf(pp.y - it["pos"].y)
			if d < it["radius"] and dy < 3.5 and d < best:
				best = d
				current = it
		if current.is_empty() and fishing and not fishing.active() and not fishing_spot().is_empty():
			current = _fish_interact
		if current.is_empty() and not _pet_interact.is_empty() and (_pet_interact["active"] as Callable).call():
			var pd := Vector2(pp.x - _pet_interact["pos"].x, pp.z - _pet_interact["pos"].z).length()
			if pd < _pet_interact["radius"]:
				current = _pet_interact
	# Descubrimientos y ambiente
	_discover_t -= dt
	if _discover_t <= 0.0:
		_discover_t = 0.4
		_check_discovery()
		for id in npcs:
			(npcs[id] as Npc).has_news = npc_has_news(id)
	_update_world_life(dt)


func interact() -> bool:
	if fishing and fishing.active():
		fishing.press()
		return true
	if player.state == "boat":
		if not regatta.is_empty():
			return true
		var spot := player.landing_spot()
		if spot == Vector3.INF:
			toast.emit("Acércate a la orilla o al muelle para bajar", "boat")
			Audio.play("error", 0.0, -8.0)
			return true
		player.leave_boat(spot)
		_store_boat()
		return true
	if current.is_empty():
		return false
	var a: Callable = current["action"]
	a.call()
	return true


func prompt_text() -> String:
	if current.is_empty():
		return ""
	return (current["prompt"] as Callable).call()


func _check_discovery() -> void:
	if locked or player.locked:
		return
	var pp := player.global_position
	for n in Places.NAMED:
		var id: String = n[0]
		if SaveGame.is_discovered(id):
			continue
		var c: Vector2 = n[2]
		if Vector2(pp.x, pp.z).distance_to(c) < n[3] and pp.y > n[4] and player.state in ["ground", "swim", "climb"]:
			SaveGame.discover(id)
			banner.emit(n[1], "Lugar descubierto")
			Audio.play("discover")
			SaveGame.save_game()
			break


func place_name_at(p: Vector3) -> String:
	for n in Places.NAMED:
		var c: Vector2 = n[2]
		if Vector2(p.x, p.z).distance_to(c) < n[3]:
			return n[1]
	return "Isla Brisa"


## El viento vuelve poco a poco: hierba, molino, ambiente y faroles de noche.
func _update_world_life(dt: float) -> void:
	var target := 0.08 + lit_count() * 0.2 + (0.2 if SaveGame.flag("lit_faro_summit") else 0.0)
	wind = move_toward(wind, target, dt * 0.2)
	RenderingServer.global_shader_parameter_set("wind_dir", Vector2(1.0, 0.35) * (0.4 + wind))
	if world.wind_lines:
		world.wind_lines.strength = 0.12 + wind
	if world.flora and world.flora._grass_mat:
		world.flora._grass_mat.set_shader_parameter("wind_strength", 0.12 + wind * 0.35)
	if places.windmill_hub:
		places.windmill_hub.rotate_object_local(Vector3.FORWARD, dt * (0.05 + wind * 1.4))
	for id in _beacon_beams:
		var b: Node3D = _beacon_beams[id]
		b.rotation.y += dt * 0.4
	var vane_speed := 0.3 + wind * 3.0
	for id in places.beacons:
		(places.beacons[id]["vane"] as Node3D).rotation.y += dt * vane_speed * (1.0 if SaveGame.flag("lit_" + id) else 0.1)
	var night := world.sky.night
	for lamp in places.lamps:
		var glass: MeshInstance3D = lamp["glass"]
		var on := night > 0.4
		glass.material_override = lamp["on"] if on else lamp["off"]
		(lamp["light"] as OmniLight3D).visible = on
	for f in places.flames:
		var fl: Node3D = f
		fl.scale = Vector3(1.0, 1.0 + sin(_t * 9.0 + fl.position.x) * 0.12, 1.0)
	if _fireflies:
		_fireflies.emitting = night > 0.5
		_fireflies.global_position = player.global_position + Vector3(0, 1.5, 0)
	_animate_pen(dt)
	_update_life(dt)


## Los animales del cercado de Lola pasean, se paran y dan saltitos.
func _animate_pen(dt: float) -> void:
	for i in places.pen_animals.size():
		var a: Array = places.pen_animals[i]
		var m: Node3D = a[0]
		if m.global_position.distance_to(player.global_position) > 60.0:
			continue
		var st: Dictionary = _pen_t.get(i, {"wait": randf_range(0.5, 3.0), "to": m.position, "phase": 0.0})
		var target: Vector3 = st["to"]
		var to := target - m.position
		to.y = 0.0
		if st["wait"] > 0.0:
			st["wait"] -= dt
			if st["wait"] <= 0.0:
				var c: Vector2 = a[1]
				var q: Vector2 = c + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * float(a[2])
				st["to"] = island.ground(q)
		elif to.length() > 0.15:
			var step := to.normalized() * minf(dt * 1.6, to.length())
			m.position += step
			m.position.y = island.height_at(m.position.x, m.position.z)
			m.rotation.y = rotate_toward(m.rotation.y, atan2(-to.x, -to.z), dt * 6.0)
			st["phase"] += dt * 10.0
			var body := m.get_node("Body") as Node3D
			body.position.y = absf(sin(st["phase"])) * 0.08
		else:
			st["wait"] = randf_range(1.5, 5.0)
			(m.get_node("Body") as Node3D).position.y = 0.0
		_pen_t[i] = st


func _setup_fireflies() -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 5.0
	p.visibility_aabb = AABB(Vector3(-25, -10, -25), Vector3(50, 20, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 3, 22)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 0.5, 0))
	grad.add_point(0.3, Color(1, 1, 0.5, 1))
	grad.add_point(0.7, Color(1, 1, 0.5, 1))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 0.5, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.95, 0.5)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.9, 0.4)
	m.emission_energy_multiplier = 3.0
	q.material = m
	p.draw_pass_1 = q
	p.emitting = false
	p.local_coords = false
	add_child(p)
	_fireflies = p


## Aplica el estado guardado: paravela, aguante, avisos de vecinos.
func apply_progress() -> void:
	player.has_glider = SaveGame.flag("has_glider")
	player.has_bike = SaveGame.flag("has_bike")
	player.stamina_max = 3.0 + SaveGame.feathers()
	player.stamina = minf(player.stamina, player.stamina_max)
	for id in npcs:
		(npcs[id] as Npc).has_news = npc_has_news(id)


# --- Encargos ------------------------------------------------------------------------------------

## Lista de encargos para el diario y el objetivo marcado.
## Cada uno: {id, title, giver, main, done, steps: [[texto, hecho, pista]], target: Vector3,
## radius: zona de búsqueda (0 = punto exacto)}
func quests() -> Array:
	var q := []
	var f := SaveGame.flag
	if f.call("intro_done"):
		q.append({"id": "arrival", "title": "Llegada a Isla Brisa", "giver": "Tomeu", "main": true,
			"done": f.call("met_rosa"), "radius": 0.0,
			"steps": [["Habla con la alcaldesa Rosa en la plaza del pueblo", f.call("met_rosa"),
				"Sube por el camino de tierra desde el muelle hacia el norte. Rosa está en la puerta del ayuntamiento, la casa grande de tejado rojo junto a la fuente."]],
			"target": npcs["rosa"].position})
	if f.call("met_rosa"):
		var kite_target: Vector3 = npcs["nerea"].position
		if f.call("kite_quest") and not f.call("has_kite"):
			kite_target = places.anchor("needle_top")
		q.append({"id": "glider", "title": "La paravela perdida", "giver": "Rosa", "main": true,
			"done": f.call("has_glider"), "radius": 0.0, "steps": [
				["Habla con Nerea en su taller", f.call("kite_quest") or f.call("has_kite") or f.call("has_glider"),
					"El taller es la casa del tejado turquesa con cometas colgadas, al oeste de la plaza."],
				["Recupera la paravela de lo alto de la Roca Aguja", f.call("has_kite") or f.call("has_glider"),
					"La Roca Aguja es el pilar de piedra junto al molino, en la colina al noreste del pueblo. Camina contra la roca para escalarla."],
				["Devuélvesela a Nerea", f.call("has_glider"), "Vuelve al taller del tejado turquesa, en el pueblo."]],
			"target": kite_target})
	if f.call("has_glider"):
		var steps := []
		var target := Vector3.ZERO
		for id in Catalog.REGULAR_BEACONS:
			var lit: bool = f.call("lit_" + id)
			var info := _beacon_step(id)
			steps.append([info[0], lit, info[1]])
			if not lit and target == Vector3.ZERO:
				target = info[2]
		q.append({"id": "beacons", "title": "Los Faros del Viento", "giver": "Rosa", "main": true,
			"done": lit_count() >= 4, "steps": steps, "target": target, "radius": 0.0})
	if lit_count() >= 4:
		q.append({"id": "summit", "title": "El Gran Faro", "giver": "Rosa", "main": true, "radius": 0.0,
			"done": f.call("lit_faro_summit"), "steps": [["Sube al Pico Brisa y enciende el Gran Faro", f.call("lit_faro_summit"),
				"El Pico Brisa es la montaña nevada del norte. Sube por la ladera sur; si te cansas, descansa en los rellanos."]],
			"target": places.anchor("faro_summit")})
	if f.call("letters_taken"):
		var steps := []
		var target := Vector3.ZERO
		var where := {"ulises": "La cabaña de Ulises está en la orilla este del Lago Espejo, al noroeste del pueblo. Sigue el camino que entra en el bosque.",
			"gema": "Gema acampa al final del camino del norte, al pie de la rampa de las Ruinas del Viento. Busca su tienda naranja.",
			"olga": "La casita de la abuela Olga está al final del camino del este, al pie del Acantilado del Este."}
		for who in Catalog.LETTERS:
			var done: bool = f.call("letter_" + who)
			steps.append(["Entrega la carta de " + Catalog.LETTERS[who], done, where[who]])
			if not done and target == Vector3.ZERO:
				target = npcs[who].position
		var all := _letters_left() == 0
		steps.append(["Vuelve con Bruno", f.call("bruno_done"), "Bruno está en la puerta de Correos, la casa del tejado azul del pueblo."])
		if all and not f.call("bruno_done"):
			target = npcs["bruno"].position
		q.append({"id": "letters", "title": "Correo urgente", "giver": "Bruno", "main": false, "radius": 0.0,
			"done": f.call("bruno_done"), "steps": steps, "target": target})
	if f.call("pia_quest"):
		var found := SaveGame.count_collected("kitten_")
		var steps := []
		var where := {"kitten_roof": ["Un gatito en un tejado del pueblo", "Mira los tejados alrededor de la plaza. Puedes trepar por las paredes de las casas."],
			"kitten_boat": ["Un gatito en el muelle", "Está en la barca de Tomeu, junto al muelle. Puedes llegar nadando o desde las tablas."],
			"kitten_forest": ["Un gatito en el bosque", "Se metió en el Bosque Susurro, cerca del camino que va al lago. Escucha sus maullidos."],
			"kitten_ruins": ["Un gatito en las ruinas", "Está en lo alto del arco de piedra de las Ruinas del Viento. ¡Trepa!"]}
		var target := Vector3.ZERO
		var radius := 0.0
		var best := INF
		for id in Catalog.KITTENS:
			var got := SaveGame.is_collected(id)
			steps.append([where[id][0], got, where[id][1]])
			if not got:
				var pos := resolve(Catalog.KITTENS[id][0], Catalog.KITTENS[id][1])
				var d := pos.distance_to(player.global_position)
				if d < best:
					best = d
					target = _fuzz(pos, 18.0)
					radius = 18.0
		steps.append(["Vuelve con Pía", f.call("pia_done"), "Pía espera junto a la fuente de la plaza."])
		if found >= 4:
			target = npcs["pia"].position
			radius = 0.0
		q.append({"id": "kittens", "title": "Los gatitos de Pía (%d/4)" % found, "giver": "Pía", "main": false,
			"done": f.call("pia_done"), "steps": steps, "target": target, "radius": radius})
	if f.call("met_ulises"):
		var m := SaveGame.count_collected("mushroom_")
		var target: Vector3 = npcs["ulises"].position
		var radius := 0.0
		if m < 5:
			target = _fuzz(_nearest_pickup("mushroom"), 14.0)
			radius = 14.0
		q.append({"id": "mushrooms", "title": "Setas brillantes", "giver": "Ulises", "main": false, "radius": radius,
			"done": f.call("ulises_done"), "steps": [
				["Recoge setas brillantes (%d/5)" % m, m >= 5, "Crecen en el suelo del Bosque Susurro, al oeste de la isla. Son azules y brillan; de noche se ven desde lejos."],
				["Llévaselas a Ulises", f.call("ulises_done"), "Ulises vive en la cabaña de la orilla este del Lago Espejo."]],
			"target": target})
	_life_quests(q)
	if f.call("has_rod") and not f.call("fish_done"):
		var n := fish_species()
		var all := n >= Catalog.FISH.size()
		q.append({"id": "fishing", "title": "La cesta de Tomeu", "giver": "Tomeu", "main": false, "radius": 0.0,
			"done": false, "steps": [
				["Pesca todas las especies (%d/%d)" % [n, Catalog.FISH.size()], all,
					"En el mar pican sardinas, caballas, doradas (de día) y pulpos (de noche); en el Lago Espejo, truchas, carpas y peces luna (de noche). Al amanecer y al atardecer pican antes."],
				["Enséñaselo a Tomeu", f.call("fish_done"), "Tomeu está en su muelle, al sur del pueblo."]],
			"target": npcs["tomeu"].position if all else Vector3.ZERO})
	var to := parcel_target()
	if to != "":
		q.append({"id": "parcel", "title": "Reparto de Correos", "giver": "Bruno", "main": false, "radius": 0.0,
			"done": false, "steps": [["Lleva el paquete a " + Catalog.NPCS[to]["name"], false,
				"Está %s. Al recibirlo te dará una propina en conchas." % describe_location(npcs[to].position)]],
			"target": npcs[to].position})
	return q


## Texto, pista y destino de cada faro según el progreso.
func _beacon_step(id: String) -> Array:
	var f := SaveGame.flag
	var pp := player.global_position
	match id:
		"faro_cliff":
			return ["Faro del Acantilado: escala el Acantilado del Este",
				"Sigue el camino del este desde el pueblo hasta la casita de la abuela Olga. El faro está arriba de la pared de roca: camina contra ella para trepar.",
				places.anchor(id)]
		"faro_forest":
			var n := SaveGame.count_collected("spark_")
			if n < 3:
				var hint := "Las chispas flotan y brillan: una en el islote del Lago Espejo, otra sobre una pila de piedras junto a la costa oeste y otra encima de un tocón gigante del bosque."
				return ["Faro del Bosque: reúne 3 chispas de fuego (%d/3)" % n, hint, _nearest_pickup("spark")]
			return ["Faro del Bosque: lleva las chispas al faro", "El faro está en el extremo oeste del Bosque Susurro, cerca de la costa.", places.anchor(id)]
		"faro_islet":
			var pen := places.anchor("penon")
			var near_penon := Vector2(pp.x - pen.x, pp.z - pen.z).length() < 35.0 and pp.y > pen.y - 12.0
			if near_penon or player.state == "glide" or Vector2(pp.x - Island.ISLET.x, pp.z - Island.ISLET.y).length() < 60.0:
				return ["Faro del Islote: planea hasta el islote", "Métete en la corriente de aire del borde del Peñón para ganar altura y planea recto hacia el faro del islote.", places.anchor(id)]
			return ["Faro del Islote: sube al Peñón del Salto",
				"El Peñón del Salto es el risco alto del suroeste. Sube por la rampa de hierba desde el banco de Tito y desde arriba planea hasta el islote.", pen]
		"faro_ruins":
			if f.call("race_won"):
				return ["Faro de las Ruinas: ¡el pedestal ha despertado!", "Enciéndelo en la meseta de las Ruinas del Viento, al noreste.", places.anchor(id)]
			if not f.call("met_gema"):
				return ["Faro de las Ruinas: habla con Gema", "Gema acampa al final del camino del norte, al pie de la rampa de las ruinas. Sabe cómo despertar el faro.", npcs["gema"].position]
			return ["Faro de las Ruinas: gana la Carrera del Viento", "Sube por la rampa a la meseta de las ruinas. La piedra de salida brilla en lo alto de la torre de bloques.", places.anchor("race_top")]
	return ["", "", Vector3.ZERO]


## Centro de una zona de búsqueda: desplazado de forma fija para no delatar el punto exacto.
func _fuzz(pos: Vector3, radius: float) -> Vector3:
	var h := hash(Vector2i(int(pos.x), int(pos.z)))
	var a := float(h % 360) * PI / 180.0
	var r := radius * (0.35 + float((h / 360) % 100) / 100.0 * 0.3)
	return pos + Vector3(cos(a) * r, 0, sin(a) * r)


func _nearest_pickup(kind: String) -> Vector3:
	var best := INF
	var out := Vector3.ZERO
	for p in pickups:
		if p["kind"] != kind:
			continue
		var d: float = (p["pos"] as Vector3).distance_to(player.global_position)
		if d < best:
			best = d
			out = p["pos"]
	return out


func tracked_quest() -> Dictionary:
	var list := quests()
	var want: String = SaveGame.data.get("tracked", "")
	for q in list:
		if q["id"] == want and not q["done"]:
			return q
	for q in list:
		if not q["done"] and q["main"]:
			return q
	for q in list:
		if not q["done"]:
			return q
	return {}


func _current_step(q: Dictionary) -> Array:
	for s in q["steps"]:
		if not s[1]:
			return s
	return []


func next_objective() -> String:
	if not SaveGame.flag("intro_done"):
		return "Habla con Tomeu en el muelle"
	var q := tracked_quest()
	if q.is_empty():
		if SaveGame.flag("ending_seen"):
			return "Explora la isla y busca plumas doradas"
		return ""
	var s := _current_step(q)
	return s[0] if not s.is_empty() else q["title"]


func next_hint() -> String:
	if not SaveGame.flag("intro_done"):
		return "Tomeu está en el muelle, justo delante de ti."
	var q := tracked_quest()
	if q.is_empty():
		return ""
	var s := _current_step(q)
	return s[2] if s.size() > 2 else ""


## "en el Bosque Susurro, al noroeste de aquí"
func describe_location(pos: Vector3) -> String:
	var to := pos - player.global_position
	var dist := Vector2(to.x, to.z).length()
	var place := place_name_at(pos)
	if dist < 25.0:
		return "muy cerca de aquí"
	var dirs := ["norte", "noreste", "este", "sureste", "sur", "suroeste", "oeste", "noroeste"]
	var ang := fposmod(atan2(to.x, -to.z), TAU)
	var dname: String = dirs[int(round(ang / (TAU / 8.0))) % 8]
	if place == "Isla Brisa":
		return "al %s de aquí" % dname
	return "por %s, al %s de aquí" % [place, dname]


## Pista sonora la primera vez que te acercas a un objeto escondido de un encargo activo.
func _hint_cues(pp: Vector3) -> void:
	for p in pickups:
		var kind: String = p["kind"]
		if kind != "mushroom" and kind != "spark" and kind != "feather":
			continue
		if _hinted.has(p["id"]):
			continue
		if (p["pos"] as Vector3).distance_to(pp) < 16.0:
			_hinted[p["id"]] = true
			Audio.play("hint", 0.05)


func _kitten_hint() -> String:
	var best := INF
	var best_id := ""
	for id in Catalog.KITTENS:
		if SaveGame.is_collected(id):
			continue
		var pos := resolve(Catalog.KITTENS[id][0], Catalog.KITTENS[id][1])
		var d := pos.distance_to(player.global_position)
		if d < best:
			best = d
			best_id = id
	if best_id == "":
		return ""
	var pos := resolve(Catalog.KITTENS[best_id][0], Catalog.KITTENS[best_id][1])
	var extra := {"kitten_roof": "Le encantan los tejados: ¡trepa por la pared de una casa!",
		"kitten_boat": "Se pasa el día mirando los peces desde la barca de Tomeu.",
		"kitten_forest": "Le gusta esconderse entre los árboles. Escucha bien: maúlla mucho.",
		"kitten_ruins": "Es el más valiente: seguro que está en lo más alto de un arco de piedra."}
	return "Creo que hay uno %s. %s" % [describe_location(pos), extra[best_id]]


# --- Granja, mochila y cosas de cada día --------------------------------------------------

## Vecinos nuevos: Amparo (granja) y Rafa (panadería).
func _talk_amparo() -> Dictionary:
	if not SaveGame.flag("met_amparo"):
		return {"lines": [
			_l("Amparo", "¡Buenas! Soy Amparo. Bienvenida a la Granja del Prado: ovejas, vacas, gallinas y el mejor huerto de la isla."),
			_l("Amparo", "Coge lo que necesites: los huevos del gallinero y las manzanas de los manzanos. Sacúdelos y caerán solas."),
			_l("Amparo", "Cada mañana hay más. Y en el tablón de la plaza los vecinos siempre piden cosas de la granja, ¡y pagan bien!"),
		], "after": func() -> void:
			SaveGame.set_flag("met_amparo")
			maybe_showcase("board", "item", null, func() -> void: pass)}
	if SaveGame.flag("boat_quest") and not SaveGame.flag("has_shears"):
		return {"lines": [
			_l("Amparo", "¿Lana para la vela de Tomeu? ¡Mis ovejas tienen de sobra! Toma mis tijeras de esquilar."),
			_l("Amparo", "Acércate a una oveja y pulsa E. A cada una se le puede esquilar una vez al día. Valeria necesitará tres ovillos."),
		], "after": func() -> void:
			SaveGame.set_flag("has_shears")
			toast.emit("Tijeras de esquilar: esquila 3 ovejas", "wool")
			Audio.play("item")}
	if not SaveGame.flag("sheep_quest"):
		return {"lines": [
			_l("Amparo", "Ay, Lía, ¿me harías un favor? Con el aire quieto, tres ovejas se escaparon buscando hierba fresca."),
			_l("Amparo", "Una se fue hacia el lago, otra hacia la playa del este y la más traviesa, hacia el Peñón. Si las encuentras, tráelas."),
		], "after": func() -> void:
			SaveGame.set_flag("sheep_quest")
			toast.emit("Nuevo encargo: El rebaño perdido", "wool")
			Audio.play("quest_new")}
	var found := SaveGame.count_collected("lostsheep_")
	if found >= 3 and not SaveGame.flag("sheep_done"):
		return {"lines": [
			_l("Amparo", "¡Las tres en casa! Ya me veía haciendo jerséis con lana de menos."),
			_l("Amparo", "Toma: conchas por la ayuda y un peto de granjera, que te queda que ni pintado."),
		], "after": func() -> void:
			SaveGame.set_flag("sheep_done")
			SaveGame.give("outfit_farmer")
			reward(Catalog.REWARDS["lost_sheep"], "El rebaño perdido")
			banner.emit("¡Peto de granjera!", "Póntelo en Esc → Aspecto")
			Audio.play("quest_done")}
	if found < 3 and SaveGame.flag("sheep_quest"):
		return {"lines": [_l("Amparo", "Me faltan %d ovejas. Búscalas cerca del lago, de la playa del este y del Peñón." % (3 - found))]}
	return {"lines": [_l("Amparo", "Las gallinas ponen cada mañana y los manzanos vuelven a dar fruta. ¡Coge lo que quieras!")]}


func _talk_rafa() -> Dictionary:
	if not SaveGame.flag("met_rafa"):
		return {"lines": [
			_l("Rafa", "¡Hombre, Lía! Huele bien, ¿eh? Soy Rafa, el panadero. Llevo horneando desde las cinco."),
			_l("Rafa", "Quiero hacer una tarta de manzana para todo el pueblo, pero no tengo ni huevos ni manzanas."),
			_l("Rafa", "Si me traes 4 huevos y 3 manzanas de la granja de Amparo, te enseñaré mi pan. Te deja como nueva."),
		], "after": func() -> void:
			SaveGame.set_flag("met_rafa")
			SaveGame.set_flag("bread_quest")
			toast.emit("Nuevo encargo: Pan para todos", "bread")
			Audio.play("quest_new")}
	if not SaveGame.flag("bread_done"):
		if SaveGame.bag_count("egg") >= 4 and SaveGame.bag_count("apple") >= 3:
			return {"lines": [
				_l("Rafa", "¡Huevos y manzanas! Esta tarde todo el pueblo comerá tarta. Gracias, Lía."),
				_l("Rafa", "Toma tus conchas y estas tres hogazas. Cuando te quedes sin aguante, cómete una (Esc → Mochila)."),
			], "after": func() -> void:
				SaveGame.bag_take("egg", 4)
				SaveGame.bag_take("apple", 3)
				SaveGame.set_flag("bread_done")
				SaveGame.bag_add("bread", 3)
				reward(Catalog.REWARDS["bread"], "Pan para todos")
				Audio.play("quest_done")}
		return {"lines": [_l("Rafa", "Me hacen falta 4 huevos (tienes %d) y 3 manzanas (tienes %d). La granja de Amparo está en el prado, al norte." % [SaveGame.bag_count("egg"), SaveGame.bag_count("apple")])]}
	return {"lines": [_l("Rafa", "¿Un poco de pan para el camino? Recién salido del horno.")],
		"after": func() -> void: open_shop.emit("bakery")}


func _setup_farm() -> void:
	var farm: Farm = places.farm
	if farm == null:
		return
	_add_interact("coop", farm.coop_pos, 2.6,
		func() -> String: return "Recoger huevos" if not SaveGame.daily_done("eggs") else "Mirar el gallinero",
		func() -> void: _collect_eggs())
	for k in farm.apple_trees.size():
		var tree: Dictionary = farm.apple_trees[k]
		var tk := k
		_add_interact("tree_%d" % k, tree["pos"], 2.4,
			func() -> String: return "Sacudir el manzano",
			func() -> void: _shake_tree(tk),
			func() -> bool: return not SaveGame.daily_done("tree_%d" % tk))
	for k in farm.sheep.size():
		var sk := k
		var it := _add_interact("sheep_%d" % k, Vector3.ZERO, 1.8,
			func() -> String: return "Esquilar la oveja" if SaveGame.flag("has_shears") else "Acariciar la oveja",
			func() -> void: _shear(sk))
		_sheep_interacts.append(it)
	_refresh_farm()


## Aspecto de la granja según lo hecho hoy (manzanas en los árboles, ovejas esquiladas).
func _refresh_farm() -> void:
	var farm: Farm = places.farm
	if farm == null:
		return
	for k in farm.apple_trees.size():
		(farm.apple_trees[k]["fruit"] as Node3D).visible = not SaveGame.daily_done("tree_%d" % k)
	for k in farm.sheep.size():
		var wool := (farm.sheep[k]["model"] as Node3D).get_node("Body/Wool") as Node3D
		wool.scale = Vector3.ONE * (0.72 if SaveGame.daily_done("shear_%d" % k) else 1.0)


func _collect_eggs() -> void:
	var farm: Farm = places.farm
	player.play_action("kneel", 0.8, farm.coop_pos)
	if SaveGame.daily_done("eggs"):
		toast.emit("Hoy ya has recogido los huevos. Vuelve mañana.", "egg")
		return
	SaveGame.set_daily("eggs")
	SaveGame.bag_add("egg", 3)
	maybe_showcase("egg", "item", null, func() -> void:
		toast.emit("+3 huevos (%d en la mochila)" % SaveGame.bag_count("egg"), "egg")
		Audio.play("item", 0.05, -4.0))


func _shake_tree(k: int) -> void:
	var farm: Farm = places.farm
	var tree: Dictionary = farm.apple_trees[k]
	SaveGame.set_daily("tree_%d" % k)
	(tree["fruit"] as Node3D).visible = false
	var root: Node3D = tree["node"]
	var tw := root.create_tween()
	for i in 4:
		tw.tween_property(root, "rotation:z", 0.06 * (1.0 if i % 2 == 0 else -1.0), 0.07)
	tw.tween_property(root, "rotation:z", 0.0, 0.08)
	Audio.play("dust", 0.1, -6.0)
	var base: Vector3 = tree["pos"]
	for i in 3:
		var a := TAU * i / 3.0 + randf()
		var q := Vector2(base.x + cos(a) * 1.6, base.z + sin(a) * 1.6)
		var pos := island.ground(q, 0.15)
		var n := _apple_node()
		var id := "apple_%d_%d" % [k, i]
		_add_pickup(id, "apple", n, pos, 1.2)
		pickups[-1]["daily"] = true
		n.position = pos + Vector3(0, 2.6, 0)
		var ft := n.create_tween()
		ft.tween_property(n, "position:y", pos.y, 0.45 + i * 0.08).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _apple_node() -> Node3D:
	var n := Node3D.new()
	MeshKit.part(n, MeshKit.sphere(0.16, 12), MeshKit.mat(Color(0.85, 0.18, 0.15)), Vector3.ZERO)
	MeshKit.part(n, MeshKit.cylinder(0.012, 0.012, 0.1, 5), MeshKit.mat(Props.WOOD_DARK), Vector3(0, 0.17, 0))
	MeshKit.part(n, MeshKit.blob(0.05, 0.3, 0.0, 0, 8), MeshKit.mat(Color(0.4, 0.7, 0.3)), Vector3(0.05, 0.19, 0), Vector3(0, 0, -30))
	return n


func _shear(k: int) -> void:
	var farm: Farm = places.farm
	var m: Node3D = farm.sheep[k]["model"]
	if not SaveGame.flag("has_shears"):
		player.play_action("kneel", 0.8, m.global_position)
		Fx.burst(self, m.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.5, 0.6), 6, 1.4, 0.12, 0.8, 1.0, -0.5)
		return
	if SaveGame.daily_done("shear_%d" % k):
		toast.emit("A esta oveja ya la has esquilado hoy", "wool")
		return
	player.play_action("kneel", 1.0, m.global_position)
	SaveGame.set_daily("shear_%d" % k)
	SaveGame.bag_add("wool")
	_refresh_farm()
	Fx.burst(self, m.global_position + Vector3(0, 0.7, 0), Color(0.98, 0.96, 0.92), 14, 2.0, 0.16, 0.9, 0.6, -1.0)
	maybe_showcase("wool", "item", null, func() -> void:
		toast.emit("+1 lana (%d en la mochila)" % SaveGame.bag_count("wool"), "wool")
		Audio.play("item", 0.05, -4.0))


## Flores silvestres: puntos fijos por los prados que vuelven a florecer cada día.
func _flower_spots() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var out := []
	var tries := 0
	while out.size() < 36 and tries < 20000:
		tries += 1
		var p := Vector2(rng.randf_range(-220, 220), rng.randf_range(-120, 230))
		var b := island.biome_at(p.x, p.y)
		if b != Island.Biome.GRASS and b != Island.Biome.MEADOW:
			continue
		if island.normal_at(p.x, p.y).y < 0.9 or island.path_distance(p) < 3.0 or p.distance_to(Island.VILLAGE) < 40.0:
			continue
		var ok := true
		for q in out:
			if Vector2(q.x, q.z).distance_to(p) < 14.0:
				ok = false
				break
		if ok:
			out.append(island.ground(p, 0.05))
	return out


func _flower_node(seed_value: int) -> Node3D:
	var n := Node3D.new()
	var cols := [Color(1.0, 0.45, 0.6), Color(1.0, 0.85, 0.3), Color(0.7, 0.55, 1.0), Color(1.0, 1.0, 1.0)]
	var col: Color = cols[seed_value % cols.size()]
	for k in 3:
		var a := TAU * k / 3.0 + seed_value
		var stem := Node3D.new()
		stem.position = Vector3(cos(a) * 0.12, 0, sin(a) * 0.12)
		stem.rotation = Vector3(cos(a) * 0.15, 0, sin(a) * 0.15)
		n.add_child(stem)
		MeshKit.part(stem, MeshKit.cylinder(0.012, 0.016, 0.45, 5), MeshKit.mat(Color(0.35, 0.6, 0.28)), Vector3(0, 0.22, 0))
		for p in 5:
			var pa := TAU * p / 5.0
			MeshKit.part(stem, MeshKit.sphere(0.045, 8), MeshKit.mat(col), Vector3(cos(pa) * 0.05, 0.47, sin(pa) * 0.05), Vector3.ZERO, Vector3(1.0, 0.5, 1.0))
		MeshKit.part(stem, MeshKit.sphere(0.03, 8), MeshKit.mat(Color(1.0, 0.85, 0.3)), Vector3(0, 0.48, 0))
	MeshKit.part(n, MeshKit.blob(0.14, 0.4, 0.2, seed_value, 8), MeshKit.mat(Color(0.38, 0.62, 0.3)), Vector3(0, 0.04, 0))
	return n


## Lo que se renueva cada día: flores. (Las manzanas caen al sacudir los manzanos.)
func _spawn_daily() -> void:
	var spots := _flower_spots()
	for k in spots.size():
		var id := "flower_%d" % k
		if SaveGame.daily_done(id) or _has_pickup(id):
			continue
		_add_pickup(id, "flower", _flower_node(k), spots[k], 1.3)
		pickups[-1]["daily"] = true


func _has_pickup(id: String) -> bool:
	for p in pickups:
		if p["id"] == id and is_instance_valid(p["node"]):
			return true
	return false


func _on_new_day() -> void:
	SaveGame.next_day()
	# Las manzanas que nadie recogió se pudren; vuelven a salir flores y fruta.
	for i in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[i]
		if p["kind"] == "apple":
			(p["node"] as Node3D).queue_free()
			pickups.remove_at(i)
	_spawn_daily()
	_refresh_farm()
	toast.emit("Día %d: hay encargos nuevos en el tablón" % (SaveGame.day() + 1), "quest")
	SaveGame.save_game()


# --- Ovejas perdidas ----------------------------------------------------------------------

const LOST_SHEEP := {"lostsheep_lake": "@-104,-6", "lostsheep_beach": "@168,150", "lostsheep_penon": "@-118,176"}


func _spawn_lost_sheep() -> void:
	for id in LOST_SHEEP:
		if SaveGame.is_collected(id):
			continue
		var pos := resolve(LOST_SHEEP[id])
		var m := Animals.sheep(id.length())
		add_child(m)
		m.position = pos
		m.rotation.y = randf() * TAU
		var sid: String = id
		_add_interact(id, pos, 2.6,
			func() -> String: return "Llevar la oveja a casa",
			func() -> void: _rescue_sheep(sid, m),
			func() -> bool: return SaveGame.flag("sheep_quest"))


func _rescue_sheep(id: String, m: Node3D) -> void:
	_remove_interact(id)
	SaveGame.collect(id)
	player.play_action("kneel", 0.8, m.global_position)
	var tw := m.create_tween()
	tw.tween_property(m, "position:y", m.position.y + 0.5, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "scale", Vector3.ONE * 0.01, 0.35)
	tw.tween_callback(m.queue_free)
	Audio.play("meet", 0.1, -4.0)
	toast.emit("¡Beee! La oveja vuelve a la granja (%d/3)" % SaveGame.count_collected("lostsheep_"), "wool")
	SaveGame.save_game()


# --- Ramo de flores para Rosa ------------------------------------------------------------

func _talk_rosa_flowers() -> Dictionary:
	if not SaveGame.flag("has_glider") or SaveGame.flag("flowers_done"):
		return {}
	if not SaveGame.flag("flowers_quest"):
		return {"lines": [
			_l("Rosa", "Por cierto, Lía: cuando vuelva el viento haremos una fiesta y quiero llenar la plaza de flores."),
			_l("Rosa", "¿Me traerías 8 flores silvestres? Crecen por los prados y vuelven a salir cada mañana."),
		], "after": func() -> void:
			SaveGame.set_flag("flowers_quest")
			toast.emit("Nuevo encargo: Ramo para la fiesta", "flower")
			Audio.play("quest_new")}
	if SaveGame.bag_count("flower") >= 8:
		return {"lines": [
			_l("Rosa", "¡Qué ramo tan precioso! La plaza va a parecer un jardín."),
			_l("Rosa", "Toma, unas conchas del ayuntamiento y una bufanda arcoíris que tejió Valeria para la fiesta."),
		], "after": func() -> void:
			SaveGame.bag_take("flower", 8)
			SaveGame.set_flag("flowers_done")
			SaveGame.give("scarf_rainbow")
			reward(Catalog.REWARDS["flowers"], "Ramo para la fiesta")
			Audio.play("quest_done")}
	return {}


# --- Tablón de encargos del día ------------------------------------------------------------

const BOARD_WHO := ["rosa", "valeria", "rafa", "amparo", "ulises", "olga", "pia", "marisol", "gema", "tito", "nerea", "lola"]


func _setup_board() -> void:
	_add_interact("board", places.anchor("noticeboard"), 2.4,
		func() -> String: return "Mirar el tablón de encargos",
		func() -> void:
			maybe_showcase("board", "item", null, func() -> void: open_shop.emit("board")))


## Encargos de hoy (3): [{item, n, reward, who, done}]. Salen siempre iguales para el mismo día.
func board_requests() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SaveGame.day() * 7919 + 13
	var pool := ["apple", "egg", "flower", "flower"]
	if SaveGame.flag("has_shears"):
		pool.append("wool")
	if SaveGame.flag("has_rod"):
		pool.append_array(["fish", "fish"])
	if SaveGame.flag("bread_done"):
		pool.append("bread")
	var out := []
	var used := {}
	for i in 3:
		var item: String = pool[rng.randi() % pool.size()]
		var tries := 0
		while used.has(item) and tries < 10:
			item = pool[rng.randi() % pool.size()]
			tries += 1
		used[item] = true
		var n := rng.randi_range(2, 5) if item in ["apple", "flower"] else rng.randi_range(1, 3)
		var value := 5 if item == "fish" else (8 if item == "bread" else int(Catalog.BAG[item][2]))
		out.append({"item": item, "n": n, "reward": n * value * 2 + 6, "who": BOARD_WHO[rng.randi() % BOARD_WHO.size()],
			"done": SaveGame.daily_done("board_%d" % i)})
	return out


## Cuántas unidades de `item` tiene Lía (los peces cuentan los de la cesta).
func have_item(item: String) -> int:
	if item == "fish":
		var n := 0
		for id in SaveGame.data["fish"]:
			if id != "fish_boot":
				n += int(SaveGame.data["fish"][id])
		return n
	return SaveGame.bag_count(item)


func item_label(item: String, n: int) -> String:
	if item == "fish":
		return "%d %s" % [n, "pez" if n == 1 else "peces"]
	var name: String = Catalog.BAG[item][0]
	return "%d × %s" % [n, name]


## Entrega el encargo `i` del tablón si hay bastante. Devuelve si se pudo.
func deliver_request(i: int) -> bool:
	var reqs := board_requests()
	var r: Dictionary = reqs[i]
	if r["done"] or have_item(r["item"]) < r["n"]:
		return false
	var item: String = r["item"]
	if item == "fish":
		var left: int = r["n"]
		for id in SaveGame.data["fish"].keys():
			if id == "fish_boot":
				continue
			while left > 0 and int(SaveGame.data["fish"][id]) > 0:
				SaveGame.data["fish"][id] = int(SaveGame.data["fish"][id]) - 1
				left -= 1
	else:
		SaveGame.bag_take(item, r["n"])
	SaveGame.set_daily("board_%d" % i)
	SaveGame.add_counter("board_done")
	reward(r["reward"], "Encargo para %s" % Catalog.NPCS[r["who"]]["name"])
	return true


# --- Barca, regata y bici --------------------------------------------------------------------

func _boat_news() -> bool:
	if SaveGame.flag("has_boat"):
		return false
	if not SaveGame.flag("boat_quest"):
		return lit_count() >= 1
	return SaveGame.flag("has_sail")


func _talk_tomeu_boat() -> Dictionary:
	if not SaveGame.flag("has_glider") or lit_count() < 1:
		return {}
	if not SaveGame.flag("boat_quest"):
		return {"lines": [
			_l("Tomeu", "¿Notas la brisa, Lía? ¡Con un faro encendido ya se podría navegar un poco!"),
			_l("Tomeu", "Pero mira mi barca: la vela está hecha jirones. Sin vela no hay quien la mueva."),
			_l("Tomeu", "Valeria, la sastra, me coserá una nueva si le llevamos lana. Las ovejas de Amparo, en la granja del prado, tienen de sobra."),
			_l("Tomeu", "Si me ayudas, la barca es tuya. Yo ya estoy mayor para ir y venir."),
		], "after": func() -> void:
			SaveGame.set_flag("boat_quest")
			toast.emit("Nuevo encargo: La barca de Tomeu", "boat")
			Audio.play("quest_new")}
	if not SaveGame.flag("has_boat"):
		if SaveGame.flag("has_sail"):
			return {"lines": [
				_l("Tomeu", "¡Qué vela tan bonita! Déjame ponerla... ¡Ya está! Mira cómo se hincha con la brisa."),
				_l("Tomeu", "Es tuya. Súbete desde el muelle con E y navega: W y S para avanzar, A y D para el timón."),
				_l("Tomeu", "Para bajar, acércate a la orilla o al muelle y pulsa E. ¡Y cuando quieras, te reto a una regata!"),
			], "after": func() -> void:
				SaveGame.set_flag("has_boat")
				refresh_boat()
				reward(Catalog.REWARDS["boat"], "La barca de Tomeu")
				maybe_showcase("boat", "item", null, func() -> void:
					banner.emit("¡Barca de vela!", "Súbete desde el muelle con E")
					Audio.play("quest_done"))}
		return {}
	if not SaveGame.flag("regatta_won") and regatta.is_empty():
		return {"lines": [
			_l("Tomeu", "¿Una regata? ¡Así me gusta! Rodea las seis boyas en orden antes de que se acabe el tiempo."),
			_l("Tomeu", "Shift despliega toda la vela. ¡Tres, dos, uno...!"),
		], "after": func() -> void: start_regatta()}
	return {}


## Crea la barca del jugador (si ya la tiene) donde la dejó amarrada la última vez.
func refresh_boat() -> void:
	if not SaveGame.flag("has_boat"):
		if places.tomeu_boat:
			places.tomeu_boat.visible = true
		return
	if my_boat != null:
		return
	var tb: Node3D = places.tomeu_boat
	my_boat = Props.boat(true)
	my_boat.name = "MyBoat"
	add_child(my_boat)
	var saved = SaveGame.data["flags"].get("boat_at", null)
	if saved is Array and saved.size() == 3:
		my_boat.position = Vector3(saved[0], 0.0, saved[1])
		my_boat.rotation.y = saved[2]
	else:
		my_boat.global_transform = tb.global_transform
	if tb:
		tb.visible = false
	_boat_interact = _add_interact("myboat", my_boat.global_position, 4.0,
		func() -> String: return "Subir a la barca",
		func() -> void: player.board(my_boat),
		func() -> bool: return player.state != "boat")


func _store_boat() -> void:
	if my_boat:
		SaveGame.data["flags"]["boat_at"] = [my_boat.global_position.x, my_boat.global_position.z, my_boat.global_rotation.y]
		SaveGame.save_game()


## Recorrido de la regata: seis boyas por la bahía del muelle (siempre en agua profunda).
func regatta_course() -> Array:
	var c := Vector2(15, 168)
	var pts := [Vector2(40, 262), Vector2(78, 290), Vector2(58, 330), Vector2(6, 342), Vector2(-42, 312), Vector2(-30, 270)]
	var out := []
	for p: Vector2 in pts:
		var q := p
		var guard := 0
		while island.height_at(q.x, q.y) > -2.5 and guard < 60:
			q += (q - c).normalized() * 4.0
			guard += 1
		out.append(Vector3(q.x, 0.0, q.y))
	return out


func start_regatta() -> void:
	if my_boat == null:
		return
	var course := regatta_course()
	var start: Vector3 = places.tomeu_boat.global_position
	my_boat.global_position = Vector3(start.x, 0.0, start.z + 4.0)
	var first: Vector3 = course[0]
	my_boat.rotation.y = atan2(-(first.x - start.x), -(first.z - start.z))
	player.board(my_boat)
	var buoys := []
	for i in course.size():
		var b := Props.buoy(Color(0.95, 0.35, 0.3) if i % 2 == 0 else Color(1.0, 0.8, 0.25))
		add_child(b)
		b.position = course[i]
		buoys.append(b)
	regatta = {"buoys": buoys, "idx": 0, "time": 80.0, "countdown": 3.5, "state": "countdown", "last_beep": 4}
	player.locked = true
	_update_buoys()


func _update_buoys() -> void:
	var buoys: Array = regatta["buoys"]
	for i in buoys.size():
		var b: Node3D = buoys[i]
		b.scale = Vector3.ONE * (1.6 if i == regatta["idx"] else 1.0)
		var flag := b.get_node("Flag") as Node3D
		flag.visible = i >= regatta["idx"]


func regatta_active() -> bool:
	return not regatta.is_empty()


func _regatta_process(dt: float) -> void:
	if regatta.is_empty():
		return
	for b in regatta["buoys"]:
		var bn: Node3D = b
		bn.position.y = sin(_t * 1.5 + bn.position.x) * 0.15
		(bn.get_node("Flag") as Node3D).rotation.y = sin(_t * 3.0 + bn.position.z) * 0.4
	match regatta["state"]:
		"countdown":
			regatta["countdown"] -= dt
			var c := int(ceil(regatta["countdown"]))
			if c < regatta["last_beep"] and c <= 3 and c >= 1:
				regatta["last_beep"] = c
				Audio.play("countdown")
			if regatta["countdown"] <= 0.0:
				regatta["state"] = "run"
				player.locked = false
				Audio.play("go")
				banner.emit("¡Ya!", "Rodea las boyas en orden")
		"run":
			regatta["time"] -= dt
			var buoys: Array = regatta["buoys"]
			var target: Vector3 = (buoys[regatta["idx"]] as Node3D).position
			if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 8.0:
				regatta["idx"] = int(regatta["idx"]) + 1
				Audio.play("ring", 0.0, 0.0, 1.0 + regatta["idx"] * 0.08)
				if regatta["idx"] >= buoys.size():
					_end_regatta(true)
					return
				_update_buoys()
			if regatta["time"] <= 0.0 or player.state != "boat":
				_end_regatta(false)


func _end_regatta(won: bool) -> void:
	var t: float = regatta["time"]
	for b in regatta["buoys"]:
		(b as Node3D).queue_free()
	regatta = {}
	player.locked = false
	if won:
		var first := not SaveGame.flag("regatta_won")
		SaveGame.set_flag("regatta_won")
		if first:
			SaveGame.give("hat_captain")
			reward(Catalog.REWARDS["regatta"], "Regata del Muelle")
			banner.emit("¡Regata ganada!", "Gorro de capitán · Póntelo en Esc → Aspecto")
		else:
			reward(Catalog.REWARDS["race_again"], "Regata del Muelle")
			banner.emit("¡Regata ganada!", "Te sobraron %.1f s" % t)
		Audio.play("quest_done")
	else:
		Audio.play("fail")
		banner.emit("¡Casi!", "Habla con Tomeu para intentarlo otra vez")
	_store_boat()
	SaveGame.save_game()


## V: subir o bajar de la bici.
func toggle_bike() -> void:
	if not SaveGame.flag("has_bike"):
		return
	player.has_bike = true
	if player.on_bike:
		player.set_bike(false)
	elif player.state == "ground":
		player.set_bike(true)
		Audio.play("ui_click", 0.05, -4.0)


func _update_life(dt: float) -> void:
	_regatta_process(dt)
	var farm: Farm = places.farm
	if farm:
		for k in _sheep_interacts.size():
			(_sheep_interacts[k] as Dictionary)["pos"] = (farm.sheep[k]["model"] as Node3D).global_position
	if my_boat and not _boat_interact.is_empty():
		_boat_interact["pos"] = my_boat.global_position
		if player.state != "boat":
			my_boat.position.y = sin(_t * 1.4) * 0.05 - 0.02
			my_boat.rotation.z = sin(_t * 1.1) * 0.03


func _life_quests(q: Array) -> void:
	var f := SaveGame.flag
	if f.call("boat_quest"):
		var wool := mini(SaveGame.bag_count("wool"), 3)
		var steps := [
			["Pide las tijeras de esquilar a Amparo", f.call("has_shears") or f.call("has_sail"), "Amparo está en la Granja del Prado, al norte del pueblo siguiendo el camino del prado."],
			["Esquila ovejas: lana %d/3" % (3 if f.call("has_sail") else wool), f.call("has_sail") or wool >= 3, "Acércate a las ovejas del prado vallado de la granja y pulsa E. Cada oveja da lana una vez al día."],
			["Lleva la lana a Valeria para que cosa la vela", f.call("has_sail"), "La sastrería de Valeria es la casa del tejado frambuesa, con el tendedero."],
			["Lleva la vela a Tomeu", f.call("has_boat"), "Tomeu está en su muelle, al sur del pueblo."]]
		var target: Vector3 = npcs["tomeu"].position
		for st in steps:
			if not st[1]:
				target = npcs["amparo"].position if st == steps[0] else (places.farm.world_at(23, 6) if st == steps[1] else (npcs["valeria"].position if st == steps[2] else npcs["tomeu"].position))
				break
		q.append({"id": "boat", "title": "La barca de Tomeu", "giver": "Tomeu", "main": true, "radius": 0.0,
			"done": f.call("has_boat"), "steps": steps, "target": target})
	if f.call("has_boat"):
		q.append({"id": "regatta", "title": "La regata del muelle", "giver": "Tomeu", "main": false, "radius": 0.0,
			"done": f.call("regatta_won"), "steps": [["Gana la regata: rodea las 6 boyas a tiempo", f.call("regatta_won"),
				"Habla con Tomeu en el muelle para empezar. Shift despliega toda la vela; frena un poco antes de cada giro."]],
			"target": npcs["tomeu"].position})
	if f.call("bread_quest"):
		q.append({"id": "bread", "title": "Pan para todos", "giver": "Rafa", "main": false, "radius": 0.0,
			"done": f.call("bread_done"), "steps": [
				["Consigue 4 huevos (%d/4)" % mini(SaveGame.bag_count("egg"), 4), f.call("bread_done") or SaveGame.bag_count("egg") >= 4, "En el gallinero de la granja de Amparo: pulsa E junto a él. Hay huevos cada mañana."],
				["Consigue 3 manzanas (%d/3)" % mini(SaveGame.bag_count("apple"), 3), f.call("bread_done") or SaveGame.bag_count("apple") >= 3, "Sacude los manzanos de la granja con E y recoge las que caen."],
				["Llévaselos a Rafa", f.call("bread_done"), "La panadería de Rafa está al oeste de la plaza, con un toldo a rayas y una hogaza en el rótulo."]],
			"target": npcs["rafa"].position if SaveGame.bag_count("egg") >= 4 and SaveGame.bag_count("apple") >= 3 else places.farm.coop_pos})
	if f.call("sheep_quest"):
		var found := SaveGame.count_collected("lostsheep_")
		var target: Vector3 = npcs["amparo"].position
		var radius := 0.0
		for id in LOST_SHEEP:
			if not SaveGame.is_collected(id):
				target = _fuzz(resolve(LOST_SHEEP[id]), 16.0)
				radius = 16.0
				break
		q.append({"id": "sheep", "title": "El rebaño perdido (%d/3)" % found, "giver": "Amparo", "main": false, "radius": radius,
			"done": f.call("sheep_done"), "steps": [
				["Encuentra las 3 ovejas escapadas", found >= 3, "Una está cerca del Lago Espejo, otra junto a la playa del este y otra al pie del Peñón del Salto."],
				["Vuelve con Amparo", f.call("sheep_done"), "Amparo está en la Granja del Prado."]],
			"target": target})
	if f.call("flowers_quest"):
		var n := mini(SaveGame.bag_count("flower"), 8)
		q.append({"id": "flowers", "title": "Ramo para la fiesta", "giver": "Rosa", "main": false, "radius": 0.0,
			"done": f.call("flowers_done"), "steps": [
				["Recoge 8 flores silvestres (%d/8)" % n, f.call("flowers_done") or n >= 8, "Crecen por los prados de la isla, lejos del pueblo. Vuelven a salir cada mañana."],
				["Llévaselas a Rosa", f.call("flowers_done"), "Rosa está en la puerta del ayuntamiento, junto a la fuente."]],
			"target": npcs["rosa"].position if n >= 8 else Vector3.ZERO})
	if f.call("bruno_done") and not f.call("has_bike"):
		var p := SaveGame.counter("parcels_done")
		q.append({"id": "bike", "title": "Cartero sobre ruedas", "giver": "Bruno", "main": false, "radius": 0.0,
			"done": false, "steps": [["Haz 3 repartos de Correos (%d/3)" % mini(p, 3), p >= 3, "Pide paquetes a Bruno en Correos y llévalos a quien te diga."],
				["Vuelve con Bruno", false, "Bruno está en la puerta de Correos, la casa del tejado azul."]],
			"target": npcs["bruno"].position})



## Tomeu compra todo el pescado de la cesta ({} si no hay nada que vender).
func _tomeu_fish_sale() -> Dictionary:
	var value := fish_value()
	if value <= 0:
		return {}
	var count := 0
	for id in SaveGame.data["fish"]:
		count += int(SaveGame.data["fish"][id])
	return {"lines": [
		_l("Tomeu", "¡Vaya cesta! %d %s. Te doy %d conchas por todo, ¿trato hecho?" % [count, "pieza" if count == 1 else "piezas", value]),
	], "after": func() -> void:
		SaveGame.data["fish"] = {}
		reward(value, "Venta de pescado")}
