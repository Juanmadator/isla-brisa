class_name Catalog
extends RefCounted
## Datos del juego: vecinos, coleccionables, cofres, tienda y faros.

## Vecinos: id -> {name, anchor, spec (aspecto), role}
const NPCS := {
	"tomeu": {"name": "Tomeu", "anchor": "tomeu", "role": "Pescador",
		"spec": {"hair_style": "bald", "hair": Color(0.75, 0.75, 0.78), "beard": true, "hat": "fisher", "hat_color": Color(1.0, 0.82, 0.3),
			"shirt": Color(0.2, 0.32, 0.55), "pants": Color(0.5, 0.38, 0.28), "scarf": null, "girth": 1.25, "height": 1.05, "dress": false}},
	"rosa": {"name": "Alcaldesa Rosa", "anchor": "town_hall_door", "role": "Alcaldesa",
		"spec": {"hair_style": "bun", "hair": Color(0.55, 0.45, 0.4), "glasses": true, "shirt": Color(0.82, 0.3, 0.32),
			"pants": Color(0.3, 0.25, 0.3), "scarf": Color(1.0, 0.85, 0.35), "girth": 1.1}},
	"nerea": {"name": "Nerea", "anchor": "workshop_door", "role": "Cometera",
		"spec": {"hair_style": "pigtails", "hair": Color(0.95, 0.5, 0.2), "shirt": Color(0.2, 0.62, 0.6), "apron": Color(0.95, 0.9, 0.75),
			"pants": Color(0.35, 0.3, 0.45), "scarf": null}},
	"bruno": {"name": "Bruno", "anchor": "post_door", "role": "Cartero",
		"spec": {"hair_style": "short", "hair": Color(0.15, 0.12, 0.12), "hat": "postman", "hat_color": Color(0.25, 0.42, 0.75),
			"shirt": Color(0.55, 0.72, 0.92), "pants": Color(0.22, 0.3, 0.5), "bag": true, "scarf": null, "dress": false, "height": 1.08}},
	"pia": {"name": "Pía", "anchor": "pia_spot", "role": "Niña",
		"spec": {"hair_style": "pony", "hair": Color(0.95, 0.8, 0.4), "shirt": Color(1.0, 0.55, 0.7), "pants": Color(1.0, 0.95, 0.9),
			"scarf": null, "height": 0.74, "girth": 0.9}},
	"marisol": {"name": "Marisol", "anchor": "marisol_spot", "role": "Tendera",
		"spec": {"hair_style": "long", "hair": Color(0.12, 0.1, 0.1), "hat": "bandana", "hat_color": Color(1.0, 0.8, 0.25),
			"shirt": Color(0.98, 0.55, 0.3), "apron": Color(0.95, 0.95, 0.9), "scarf": null}},
	"ulises": {"name": "Ulises", "anchor": "ulises", "role": "Ermitaño",
		"spec": {"hair_style": "long", "hair": Color(0.92, 0.92, 0.9), "beard": true, "hat": "straw", "hat_color": Color(0.92, 0.8, 0.5),
			"shirt": Color(0.4, 0.6, 0.38), "pants": Color(0.55, 0.45, 0.32), "scarf": null, "dress": false}},
	"gema": {"name": "Gema", "anchor": "gema", "role": "Arqueóloga",
		"spec": {"hair_style": "short", "hair": Color(0.75, 0.25, 0.15), "hat": "miner", "hat_color": Color(0.95, 0.75, 0.25),
			"shirt": Color(0.78, 0.7, 0.5), "pants": Color(0.4, 0.38, 0.3), "bag": true, "scarf": Color(0.3, 0.55, 0.45), "dress": false}},
	"olga": {"name": "Abuela Olga", "anchor": "olga", "role": "Farera retirada",
		"spec": {"hair_style": "bun", "hair": Color(0.95, 0.95, 0.95), "glasses": true, "hat": "beret", "hat_color": Color(0.2, 0.28, 0.5),
			"shirt": Color(0.55, 0.42, 0.7), "pants": Color(0.3, 0.3, 0.4), "scarf": Color(0.95, 0.35, 0.3), "height": 0.95}},
	"valeria": {"name": "Valeria", "anchor": "tailor_spot", "role": "Sastra",
		"spec": {"hair_style": "long", "hair": Color(0.55, 0.18, 0.2), "glasses": true, "shirt": Color(0.55, 0.35, 0.7),
			"pants": Color(0.25, 0.22, 0.3), "scarf": Color(0.98, 0.85, 0.4), "apron": Color(0.95, 0.88, 0.8), "height": 1.02}},
	"lola": {"name": "Lola", "anchor": "petshop_spot", "role": "Cuidadora de animales",
		"spec": {"hair_style": "pony", "hair": Color(0.35, 0.22, 0.14), "hat": "straw", "hat_color": Color(0.95, 0.85, 0.55),
			"shirt": Color(0.45, 0.68, 0.4), "pants": Color(0.45, 0.35, 0.25), "scarf": Color(1.0, 0.55, 0.35), "dress": false}},
	"amparo": {"name": "Amparo", "anchor": "amparo_spot", "role": "Granjera",
		"spec": {"hair_style": "bun", "hair": Color(0.82, 0.62, 0.35), "hat": "straw", "hat_color": Color(0.92, 0.82, 0.5),
			"shirt": Color(0.62, 0.42, 0.3), "pants": Color(0.32, 0.45, 0.68), "apron": Color(0.95, 0.9, 0.78), "scarf": Color(0.85, 0.3, 0.3), "girth": 1.15, "dress": false}},
	"rafa": {"name": "Rafa", "anchor": "bakery_spot", "role": "Panadero",
		"spec": {"hair_style": "short", "hair": Color(0.2, 0.15, 0.12), "beard": true, "hat": "beanie", "hat_color": Color(0.98, 0.98, 0.95),
			"shirt": Color(0.98, 0.96, 0.92), "pants": Color(0.4, 0.35, 0.32), "apron": Color(0.95, 0.85, 0.7), "scarf": null, "girth": 1.25, "dress": false, "height": 1.05}},
	"tito": {"name": "Tito", "anchor": "tito", "role": "Niño",
		"spec": {"hair_style": "short", "hair": Color(0.45, 0.28, 0.15), "hat": "bandana", "hat_color": Color(0.9, 0.3, 0.3),
			"shirt": Color(1.0, 0.85, 0.3), "pants": Color(0.3, 0.45, 0.7), "scarf": null, "height": 0.8, "dress": false}},
}

## Faros: id -> [nombre, región]
const BEACONS := {
	"faro_cliff": ["Faro del Acantilado", "cliff"],
	"faro_forest": ["Faro del Bosque", "forest"],
	"faro_islet": ["Faro del Islote", "islet"],
	"faro_ruins": ["Faro de las Ruinas", "ruins"],
	"faro_summit": ["Gran Faro", "summit"],
}
const REGULAR_BEACONS := ["faro_cliff", "faro_forest", "faro_islet", "faro_ruins"]

## Plumas doradas repartidas por el mundo: id -> [ancla, desplazamiento]
const FEATHERS := {
	"feather_summit": ["faro_summit", Vector3(6, 0, 5)],
	"feather_islet": ["faro_islet", Vector3(-4, 0, 5)],
	"feather_cliff": ["faro_cliff", Vector3(-7, 0, -8)],
	"feather_pillar": ["pillar_top", Vector3.ZERO],
	"feather_stack": ["sea_stack_top", Vector3.ZERO],
	"feather_penon": ["penon", Vector3(-4, 0, -3)],
	"feather_north": ["@-12,-232", Vector3.ZERO],
}
const TOTAL_FEATHERS := 15   # 7 en el mundo + 4 faros + 3 encargos + 1 tienda

## Cofres: id -> [ancla, desplazamiento, recompensa]
const CHESTS := {
	"chest_windmill": ["windmill", Vector3(-5, 0, -6), "shells:15"],
	"chest_beach": ["@150,212", Vector3.ZERO, "shells:10"],
	"chest_lake": ["@-212,-40", Vector3.ZERO, "shells:20"],
	"chest_ruins": ["ruins_arch", Vector3(0, 0, 2.5), "hat_crown"],
	"chest_mountain": ["@-42,-118", Vector3.ZERO, "shells:25"],
	"chest_north": ["@40,-226", Vector3.ZERO, "shells:20"],
	"chest_penon": ["@-196,190", Vector3.ZERO, "glider_star"],
	"chest_forest": ["@-226,30", Vector3.ZERO, "shells:15"],
}

## Gatitos de Pía: id -> [ancla, desplazamiento, color]
const KITTENS := {
	"kitten_roof": ["pia_roof", Vector3.ZERO, Color(1.0, 0.65, 0.3)],
	"kitten_boat": ["boat", Vector3(0, 0.55, 0.4), Color(0.25, 0.25, 0.28)],
	"kitten_forest": ["@-158,72", Vector3.ZERO, Color(0.95, 0.95, 0.95)],
	"kitten_ruins": ["ruins_arch_top", Vector3.ZERO, Color(0.6, 0.55, 0.5)],
}

## Setas brillantes del Bosque Susurro
const MUSHROOMS := {
	"mushroom_a": ["@-148,28", Vector3.ZERO],
	"mushroom_b": ["@-206,-12", Vector3.ZERO],
	"mushroom_c": ["@-232,92", Vector3.ZERO],
	"mushroom_d": ["@-176,96", Vector3.ZERO],
	"mushroom_e": ["@-118,8", Vector3.ZERO],
}

## Chispas para el Faro del Bosque
const SPARKS := {
	"spark_lake": ["lake_islet_top", Vector3(0, 1.2, 0)],
	"spark_rocks": ["rock_stack_top", Vector3(0, 0.9, 0)],
	"spark_stump": ["stump_top", Vector3(0, 0.9, 0)],
}

## Cartas de Bruno: destinatario -> descripción
const LETTERS := {"ulises": "Ulises (Lago Espejo)", "gema": "Gema (Ruinas del Viento)", "olga": "Abuela Olga (Acantilado del Este)"}

## Objetos de las tiendas y del armario: id -> [ranura, nombre, precio, valor]
## Precio 0 = de serie; -1 = no se vende (recompensa).
## Valor según la ranura: scarf -> Color; hat -> [tipo, Color]; glider -> [Color, Color];
## outfit -> [camisa, pantalón, zapatos, túnica?]; pet -> [especie, nombre, [color, acento]].
const ITEMS := {
	"scarf_red": ["scarf", "Bufanda roja", 0, Color(0.95, 0.35, 0.3)],
	"scarf_sky": ["scarf", "Bufanda celeste", 15, Color(0.45, 0.75, 1.0)],
	"scarf_mint": ["scarf", "Bufanda menta", 15, Color(0.45, 0.88, 0.7)],
	"scarf_sun": ["scarf", "Bufanda sol", 15, Color(1.0, 0.82, 0.3)],
	"scarf_plum": ["scarf", "Bufanda ciruela", 20, Color(0.62, 0.4, 0.82)],
	"scarf_gold": ["scarf", "Bufanda dorada", -1, Color(1.0, 0.75, 0.2)],
	"scarf_rainbow": ["scarf", "Bufanda arcoíris", -1, Color(0.95, 0.5, 0.75)],
	"hat_none": ["hat", "Sin sombrero", 0, ["none", Color.WHITE]],
	"hat_straw": ["hat", "Sombrero de paja", 25, ["straw", Color(0.95, 0.85, 0.5)]],
	"hat_beret": ["hat", "Boina", 25, ["beret", Color(0.85, 0.3, 0.35)]],
	"hat_cap": ["hat", "Gorra de excursión", 30, ["cap", Color(0.3, 0.55, 0.85)]],
	"hat_beanie": ["hat", "Gorro de lana", 30, ["beanie", Color(0.95, 0.55, 0.35)]],
	"hat_flowers": ["hat", "Corona de flores", 35, ["flowers", Color.WHITE]],
	"hat_sailor": ["hat", "Gorro marinero", 40, ["sailor", Color(0.98, 0.98, 1.0)]],
	"hat_postman": ["hat", "Gorra de cartero", -1, ["postman", Color(0.25, 0.42, 0.75)]],
	"hat_crown": ["hat", "Corona del viento", -1, ["crown", Color.WHITE]],
	"hat_captain": ["hat", "Gorro de capitán", -1, ["sailor", Color(0.18, 0.25, 0.45)]],
	"glider_classic": ["glider", "Paravela clásica", 0, [Color(0.98, 0.95, 0.85), Color(0.95, 0.4, 0.35)]],
	"glider_dawn": ["glider", "Paravela amanecer", 30, [Color(1.0, 0.75, 0.4), Color(0.95, 0.45, 0.6)]],
	"glider_ocean": ["glider", "Paravela océano", 30, [Color(0.4, 0.75, 1.0), Color(0.95, 0.98, 1.0)]],
	"glider_rainbow": ["glider", "Paravela arcoíris", 50, [Color(0.5, 0.85, 0.45), Color(0.6, 0.5, 0.95)]],
	"glider_star": ["glider", "Paravela estrellada", -1, [Color(0.15, 0.2, 0.45), Color(1.0, 0.85, 0.35)]],
	"outfit_travel": ["outfit", "Ropa de viaje", 0, [Color(0.35, 0.62, 0.9), Color(0.95, 0.9, 0.78), Color(0.5, 0.33, 0.22), true]],
	"outfit_sailor": ["outfit", "Conjunto marinero", 45, [Color(0.96, 0.96, 0.98), Color(0.18, 0.25, 0.45), Color(0.15, 0.15, 0.2), false]],
	"outfit_denim": ["outfit", "Peto vaquero", 50, [Color(0.98, 0.92, 0.75), Color(0.32, 0.45, 0.72), Color(0.55, 0.3, 0.2), false]],
	"outfit_rain": ["outfit", "Chubasquero", 55, [Color(1.0, 0.82, 0.2), Color(0.3, 0.35, 0.45), Color(0.2, 0.5, 0.35), true]],
	"outfit_flowers": ["outfit", "Vestido de flores", 60, [Color(1.0, 0.62, 0.72), Color(1.0, 0.95, 0.92), Color(0.85, 0.4, 0.45), true]],
	"outfit_forest": ["outfit", "Capa del bosque", 65, [Color(0.3, 0.55, 0.32), Color(0.5, 0.4, 0.3), Color(0.35, 0.25, 0.18), true]],
	"outfit_explorer": ["outfit", "Exploradora", 70, [Color(0.72, 0.62, 0.42), Color(0.45, 0.38, 0.28), Color(0.35, 0.25, 0.18), false]],
	"outfit_night": ["outfit", "Noche estrellada", 120, [Color(0.16, 0.2, 0.42), Color(0.95, 0.85, 0.45), Color(0.15, 0.15, 0.25), true]],
	"outfit_farmer": ["outfit", "Peto de granjera", -1, [Color(0.92, 0.55, 0.45), Color(0.3, 0.45, 0.68), Color(0.4, 0.28, 0.2), false]],
	"outfit_keeper": ["outfit", "Uniforme de farera", -1, [Color(0.95, 0.95, 0.95), Color(0.85, 0.25, 0.25), Color(0.25, 0.2, 0.2), false]],
	"pet_none": ["pet", "Sin mascota", 0, null],
	"pet_chick": ["pet", "Pipo, el pollito", 60, ["chick", "Pipo", [Color(1.0, 0.88, 0.35), Color(1.0, 0.5, 0.2)]]],
	"pet_bunny": ["pet", "Algodón, el conejo", 90, ["bunny", "Algodón", [Color(0.97, 0.95, 0.93), Color(1.0, 1.0, 1.0)]]],
	"pet_cat": ["pet", "Miso, el gato", 110, ["cat", "Miso", [Color(0.38, 0.38, 0.44), Color(0.96, 0.96, 0.96)]]],
	"pet_dog": ["pet", "Canela, la perrita", 120, ["dog", "Canela", [Color(0.85, 0.6, 0.35), Color(1.0, 0.95, 0.88)]]],
	"pet_fox": ["pet", "Brasa, la zorrita", 160, ["fox", "Brasa", [Color(0.95, 0.5, 0.2), Color(1.0, 0.96, 0.9)]]],
	"pet_parrot": ["pet", "Kiwi, el loro", 200, ["parrot", "Kiwi", [Color(0.3, 0.75, 0.35), Color(0.95, 0.3, 0.25)]]],
	"food_bread": ["food", "Pan de Rafa", 8, "bread"],
	"shop_feather": ["special", "Pluma dorada", 60, null],
	"shop_compass": ["special", "Brújula de plumas", 40, null],
}

## Comercios: id -> título, dueña, despedida, texto y objetos a la venta (en orden).
const SHOPS := {
	"marisol": {"title": "Puesto de Marisol", "owner": "Marisol", "bye": "Adiós, Marisol",
		"blurb": "Bufandas, paravelas y alguna rareza. Todo se paga en conchas.",
		"items": ["shop_feather", "shop_compass", "scarf_sky", "scarf_mint", "scarf_sun", "scarf_plum",
			"glider_dawn", "glider_ocean", "glider_rainbow"]},
	"tailor": {"title": "Sastrería de Valeria", "owner": "Valeria", "bye": "Gracias, Valeria",
		"blurb": "Ropa y sombreros cosidos a mano. Pruébatelos antes de comprar.",
		"items": ["outfit_sailor", "outfit_denim", "outfit_rain", "outfit_flowers", "outfit_forest", "outfit_explorer",
			"outfit_night", "hat_straw", "hat_beret", "hat_cap", "hat_beanie", "hat_flowers", "hat_sailor"]},
	"bakery": {"title": "Panadería de Rafa", "owner": "Rafa", "bye": "Gracias, Rafa",
		"blurb": "Pan recién hecho. Cómetelo desde la mochila (Esc → Mochila) para recuperar todo el aguante.",
		"items": ["food_bread"]},
	"pets": {"title": "Refugio de Lola", "owner": "Lola", "bye": "Hasta luego, Lola",
		"blurb": "Animales que buscan compañía. Te seguirán a todas partes y a veces encuentran conchas.",
		"items": ["pet_chick", "pet_bunny", "pet_cat", "pet_dog", "pet_fox", "pet_parrot"]},
}

## Peces: id -> [nombre, agua (sea, lake, any), frecuencia, fuerza 0-1, precio, color,
## [talla mínima, máxima] en cm, hora (day, night, any)]
const FISH := {
	"fish_sardine": ["Sardina", "sea", 30, 0.25, 4, Color(0.62, 0.72, 0.82), [12, 20], "any"],
	"fish_mackerel": ["Caballa", "sea", 22, 0.4, 7, Color(0.35, 0.58, 0.62), [20, 35], "any"],
	"fish_bream": ["Dorada", "sea", 12, 0.55, 14, Color(0.88, 0.76, 0.45), [25, 45], "day"],
	"fish_octopus": ["Pulpo", "sea", 6, 0.75, 25, Color(0.85, 0.42, 0.45), [30, 70], "night"],
	"fish_legend": ["Brisa dorada", "sea", 1, 0.95, 120, Color(1.0, 0.82, 0.3), [80, 120], "any"],
	"fish_trout": ["Trucha", "lake", 30, 0.35, 6, Color(0.55, 0.62, 0.45), [18, 35], "any"],
	"fish_carp": ["Carpa", "lake", 20, 0.5, 10, Color(0.82, 0.6, 0.3), [30, 60], "any"],
	"fish_glow": ["Pez luna", "lake", 5, 0.8, 40, Color(0.5, 0.85, 1.0), [20, 30], "night"],
	"fish_boot": ["Bota vieja", "any", 6, 0.1, 1, Color(0.42, 0.3, 0.22), [28, 28], "any"],
}

## Cosas de la mochila: id -> [nombre, icono, precio de venta, descripción]
const BAG := {
	"apple": ["Manzana", "apple", 3, "De los manzanos de Amparo. Sacude un manzano para que caigan."],
	"egg": ["Huevo", "egg", 4, "Las gallinas de Amparo ponen huevos cada día."],
	"wool": ["Lana", "wool", 6, "Lana de oveja recién esquilada. Valeria hace maravillas con ella."],
	"flower": ["Flor silvestre", "flower", 2, "Crecen en los prados. Vuelven a salir cada día."],
	"bread": ["Pan de Rafa", "bread", 0, "Recién hecho. Cómelo desde la mochila para recuperar todo el aguante."],
}

## Recompensas en conchas.
const REWARDS := {
	"glider": 20, "letters": 40, "kittens": 50, "mushrooms": 40, "beacon": 30, "race_first": 40,
	"race_again": 15, "race_record": 10, "parcel_min": 10, "parcel_max": 32,
	"boat": 30, "regatta": 60, "bread": 40, "lost_sheep": 50, "flowers": 35,
}

const SHELL_COUNT := 70


static func item_name(id: String) -> String:
	return ITEMS[id][1] if ITEMS.has(id) else id


static func _item_value(eq: Dictionary, slot: String, fallback: String):
	var id: String = eq.get(slot, fallback)
	if not ITEMS.has(id) or ITEMS[id][0] != slot:
		id = fallback
	return ITEMS[id][3]


## Campos del Avatar de Lía para lo que lleva puesto (`eq`: ranura -> id).
static func look_for(eq: Dictionary) -> Dictionary:
	var hat: Array = _item_value(eq, "hat", "hat_none")
	var outfit: Array = _item_value(eq, "outfit", "outfit_travel")
	return {"scarf": _item_value(eq, "scarf", "scarf_red"), "hat": hat[0], "hat_color": hat[1],
		"shirt": outfit[0], "pants": outfit[1], "shoes": outfit[2], "dress": outfit[3]}


static func glider_for(eq: Dictionary) -> Array:
	return _item_value(eq, "glider", "glider_classic")


## [especie, nombre, colores] de la mascota puesta, o null.
static func pet_for(eq: Dictionary):
	return _item_value(eq, "pet", "pet_none")


## Cuaderno de Lía: id -> [nombre, categoría, icono, descripción]
const JOURNAL := {
	"npc_tomeu": ["Tomeu", "Vecino · Pescador", "person", "Lleva cuarenta años saliendo a pescar desde su muelle. Sin viento, su barca no se mueve ni un palmo."],
	"npc_rosa": ["Alcaldesa Rosa", "Vecina · Alcaldesa", "person", "Lo organiza todo en Isla Brisa. Siempre lleva su bufanda amarilla, haga el tiempo que haga."],
	"npc_nerea": ["Nerea", "Vecina · Cometera", "person", "Construye cometas en su taller del tejado turquesa. Inventó la paravela para volar sin cuerda."],
	"npc_bruno": ["Bruno", "Vecino · Cartero", "person", "Conoce cada buzón y cada atajo de la isla. Sin viento, el barco del correo no llega."],
	"npc_pia": ["Pía", "Vecina · Niña", "person", "Tiene cuatro gatitos traviesos y una curiosidad sin fondo."],
	"npc_marisol": ["Marisol", "Vecina · Tendera", "person", "Atiende el puesto de la plaza. Cambia conchas por cosas bonitas."],
	"npc_ulises": ["Ulises", "Vecino · Ermitaño", "person", "Vive solo junto al Lago Espejo. Dice que el lago le habla, y casi nadie le lleva la contraria."],
	"npc_gema": ["Gema", "Vecina · Arqueóloga", "person", "Estudia los mecanismos de viento de las ruinas antiguas. Siempre lleva el casco puesto."],
	"npc_olga": ["Abuela Olga", "Familia · Farera retirada", "person", "La abuela de Lía. Cuidó los Faros del Viento durante cincuenta años."],
	"npc_tito": ["Tito", "Vecino · Niño", "person", "Sueña con saltar desde el Peñón y volar hasta el islote."],
	"npc_valeria": ["Valeria", "Vecina · Sastra", "person", "Cose toda la ropa de la isla en su sastrería, la casa del tejado frambuesa. Dice que cada prenda tiene su propio viento."],
	"npc_lola": ["Lola", "Vecina · Cuidadora de animales", "person", "Cuida de los animales sin hogar en su refugio, la casa del cercado al noroeste de la plaza."],
	"pet": ["Mascota", "Compañera", "paw", "Te sigue a todas partes. Acaríciala con E. Mientras exploras, a veces escarba y encuentra conchas."],
	"rod": ["Caña de pescar", "Objeto clave", "fish", "Regalo de Tomeu. Acércate al agua (orilla, muelle o lago) y pulsa E. Cuando pique, pulsa E y luego mantén E para recoger sin que se rompa el sedal."],
	"fish_sardine": ["Sardina", "Pez · Mar", "fish", "Pequeña y plateada. Pica a cualquier hora en el mar."],
	"fish_mackerel": ["Caballa", "Pez · Mar", "fish", "Rayada y peleona. Abunda junto al muelle."],
	"fish_bream": ["Dorada", "Pez · Mar (de día)", "fish", "Tiene una ceja dorada. Solo pica con luz."],
	"fish_octopus": ["Pulpo", "Criatura · Mar (de noche)", "fish", "Sale a cazar de noche. Tira con mucha fuerza."],
	"fish_legend": ["Brisa dorada", "Pez legendario · Mar", "fish", "Dicen que solo la ha visto Tomeu, y nadie le cree. Brilla como un faro."],
	"fish_trout": ["Trucha", "Pez · Lago", "fish", "Moteada y rápida. Vive en el Lago Espejo."],
	"fish_carp": ["Carpa", "Pez · Lago", "fish", "Grande y tranquila, pero cuando tira, tira."],
	"fish_glow": ["Pez luna", "Pez · Lago (de noche)", "fish", "Brilla en el agua oscura del lago. Ulises dice que es el lago que sueña."],
	"fish_boot": ["Bota vieja", "Objeto", "fish", "Alguien la perdió hace mucho. Tomeu te da una concha por ella, por las risas."],
	"npc_amparo": ["Amparo", "Vecina · Granjera", "person", "Lleva la Granja del Prado: ovejas, vacas, gallinas y los mejores manzanos de la isla."],
	"npc_rafa": ["Rafa", "Vecino · Panadero", "person", "Hace el pan de todo el pueblo desde antes de que salga el sol. Su horno huele a gloria."],
	"apple": ["Manzana", "Objeto · Granja", "apple", "Sacude un manzano de la granja y recoge las que caen. Vuelven a salir cada día."],
	"egg": ["Huevo", "Objeto · Granja", "egg", "Recógelos en el gallinero de Amparo. Las gallinas ponen cada mañana."],
	"wool": ["Lana", "Objeto · Granja", "wool", "Con las tijeras de Amparo puedes esquilar a cada oveja una vez al día."],
	"flower": ["Flor silvestre", "Objeto", "flower", "Florecen en los prados de la isla. Rosa y el tablón de encargos siempre piden ramos."],
	"bread": ["Pan de Rafa", "Comida", "bread", "Cómelo desde la mochila (Esc → Mochila) para recuperar todo el aguante."],
	"boat": ["Barca de vela", "Vehículo", "boat", "La barca de Tomeu, con su vela nueva. Súbete en el muelle y navega alrededor de la isla."],
	"bike": ["Bici de cartero", "Vehículo", "bike", "Regalo de Bruno. Pulsa V para subir o bajar. Va mucho más rápida por los caminos."],
	"board": ["Tablón de encargos", "Lugar", "quest", "Junto a la fuente. Cada día hay encargos nuevos de los vecinos, pagados en conchas."],
	"parcel": ["Paquete de Correos", "Objeto", "parcel", "Un paquete que Bruno te pidió repartir. Quien lo recibe te da una propina en conchas."],
	"kitten": ["Gatito de Pía", "Criatura", "kitten", "Pequeño, curioso y escurridizo. Le encantan los sitios altos y maúlla cuando se pierde."],
	"shell": ["Concha", "Objeto", "shell", "La moneda de Isla Brisa. Aparece en las playas y en los cofres, y te la dan como recompensa por los encargos y los repartos."],
	"feather": ["Pluma dorada", "Objeto", "feather", "Una pluma de las aves del viento. Cada una añade un segmento a tu aguante."],
	"spark": ["Chispa de fuego", "Objeto", "spark", "Un resto de la llama de los faros. El Faro del Bosque necesita tres para volver a arder."],
	"mushroom": ["Seta brillante", "Objeto", "mushroom", "Crece en el Bosque Susurro y brilla en la oscuridad. Ulises las colecciona."],
	"kite": ["Paravela de Nerea", "Objeto clave", "star", "La paravela que se llevó la última ráfaga de viento. Hay que devolvérsela a Nerea."],
	"glider": ["Paravela", "Objeto clave", "star", "Pulsa Saltar en el aire para planear. Las corrientes de aire te suben muy alto."],
	"letters": ["Cartas de Bruno", "Objeto clave", "letter", "Tres cartas atascadas por la falta de viento: para Ulises, para Gema y para la abuela Olga."],
	"chest": ["Cofre", "Objeto", "chest", "Hay cofres escondidos por toda la isla. Dentro hay conchas o algún tesoro."],
}
const JOURNAL_ORDER := [
	["Vecinos", ["npc_tomeu", "npc_rosa", "npc_nerea", "npc_bruno", "npc_pia", "npc_marisol", "npc_valeria", "npc_lola", "npc_amparo", "npc_rafa", "npc_ulises", "npc_gema", "npc_olga", "npc_tito"]],
	["Criaturas", ["kitten", "pet"]],
	["Peces", ["fish_sardine", "fish_mackerel", "fish_bream", "fish_octopus", "fish_legend", "fish_trout", "fish_carp", "fish_glow", "fish_boot"]],
	["Granja", ["apple", "egg", "wool", "flower", "bread"]],
	["Objetos", ["shell", "feather", "spark", "mushroom", "chest", "kite", "glider", "letters", "parcel", "rod", "board"]],
	["Vehículos", ["boat", "bike"]],
]
const PLACE_DESC := {
	"village": "El corazón de la isla: casas blancas, la fuente y el puesto de Marisol.",
	"dock": "Donde amarra Tomeu y donde empezó todo.",
	"windmill": "Un molino que solo gira cuando sopla el viento, y la Roca Aguja a su lado.",
	"summit": "El techo de la isla. Arriba espera el Gran Faro.",
	"forest": "Árboles altos, setas que brillan y susurros entre las hojas.",
	"lake": "Un lago tan quieto que refleja el cielo. Ulises vive en su orilla.",
	"penon": "Un risco altísimo sobre el mar, perfecto para lanzarse a planear.",
	"islet": "Una roca solitaria en mitad del mar con su propio faro.",
	"cliff": "Paredes de roca de cuarenta metros sobre el océano.",
	"ruins": "Restos de una civilización que sabía hablar con el viento.",
	"beach": "La playa más larga de la isla, llena de conchas.",
	"meadow": "Hierba alta que ondea en cuanto vuelve la brisa.",
	"farm": "La granja de Amparo: ovejas, vacas, gallinas, un huerto y los mejores manzanos de la isla.",
}
