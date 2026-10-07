# Siguientes pasos de Isla Brisa

Prioridades acordadas (6 de octubre de 2026), en este orden:

1. **Optimización considerable:** jugar con los máximos FPS posibles.
2. **Fluidez:** sin tirones, con un tiempo por fotograma estable.
3. **Físicas con objetos:** que se puedan empujar, coger, llevar y lanzar, y que nada atraviese nada.

Este documento recoge lo que ya está medido y el plan concreto de cada punto.

---

## Avance (7 de octubre de 2026)

Rama `optimizacion-fisicas`. Medido en una RTX 5050 a 1600x900 y sin vsync.

### Hecho

**Banco de vistas** (`--ib-look --only=bench`): media de 6 vistas.

| Vista | Antes | Ahora, calidad Alta | Ahora, calidad Ultra |
|---|---|---|---|
| Pueblo | 68 FPS | 164 FPS | 115 FPS |
| Bosque | 71 FPS | 138 FPS | 120 FPS |
| Pradera | 85 FPS | 198 FPS | 151 FPS |
| Playa | 80 FPS | 186 FPS | 152 FPS |
| Ruinas | 111 FPS | 229 FPS | 167 FPS |
| Vista aérea | 85 FPS | 156 FPS | 135 FPS |
| **Media** | **83 FPS** | **178 FPS** | **140 FPS** |

En calidad Baja la media es de 230 FPS y en Media de 212 FPS. Las dos chocan con el límite de la CPU.

Qué se ha cambiado:

- **Vegetación troceada por zonas** (`Flora._multimesh`, zonas de 48 m). Antes cada tipo de árbol, pino, arbusto o roca era un único MultiMesh para toda la isla, así que se dibujaban todos en cada fotograma y en las 4 cascadas de sombra. Ahora la cámara y cada cascada descartan lo que no ven.
- **Copas por distancia:**
  - Hasta 45 m (`TREE_SHADOW`): tarjetas de hojas con su sombra recortada.
  - De 45 a 110 m (`TREE_LOD`): tarjetas sin sombra; la sombra la da una copa de bultos que solo proyecta sombra.
  - Más allá de 110 m: copa sencilla de bultos.
  - Igual con pinos y arbustos.
  - Las bandas que se relevan entre sí no llevan margen de histéresis: con margen, tras un salto de cámara quedaban árboles sin copa.
- **LOD automático de mallas** (`MeshKit.with_lods`, con `ImporterMesh.generate_lods`) en props y vegetación, salvo las tarjetas de hojas. Fue la mejora más grande después del troceado. Cuesta unos 0,6 s más al arrancar.
- **Rango de visibilidad por tamaño** (`MeshKit.auto_ranges`, aplicado a `Places`). Cada pieza deja de dibujarse cuando ocuparía unos 6 px, y las piezas de menos de 35 cm no proyectan sombra.
- **Shader `toon`:** el dibujo de la superficie y el ruido de detalle se apagan con la distancia. La ganancia es pequeña.
- **Calidad Baja, Media, Alta y Ultra** (`World.set_quality`), con resolución 3D (FSR 1), vsync y límite de FPS en el menú de opciones. Las partidas antiguas con "alta calidad" desactivada pasan a calidad Baja.
  - MSAA 2x solo en Ultra, porque costaba unos 2 ms. Alta usa SMAA.
  - Medido: lo caro es la **geometría de las sombras** y el **MSAA**. SSAO, SSIL, niebla volumétrica, glow y SMAA cuestan entre 0,1 y 0,3 ms cada uno. FSR al 77 % no gana nada en este equipo, porque la GPU está limitada por triángulos y no por píxeles.
- **Gameplay:**
  - Los coleccionables solo se animan a menos de 80 m.
  - Las farolas solo cambian de material al encenderse o apagarse.
  - Los banderines solo se mueven a menos de 150 m.
  - En juego apenas se nota.
- **Herramientas:**
  - `--ib-look --only=bench`: añade playa y ruinas, percentil 99, tiempo de CPU y GPU, llamadas de dibujo y triángulos.
  - Opciones del banco: `--quality=N`, `--nofx=msaa,smaa,shadow,penumbra,glow,fsr,...`, `IB_VIEWS=pueblo,bosque` e `IB_HIDE=flora,grass,places,terrain,sea`.
  - `--ib-look --only=tris`: triángulos por nodo de la escena.
  - **`--ib-perf`** (`tools/perf.gd`): partida real con piloto automático por playa, pueblo, pradera y bosque. Da FPS, percentil 99, máximo, tirones de más de 25 ms (con lugar), física y GPU.
  - Opciones de `--ib-perf`: `--route=pueblo`, `--quality=N`, `IB_OFF=avatar,npc,gameplay,...` (apaga el `_process` de esos scripts) e `IB_NOHUD=1`.

### Hallazgo importante: jugando, el límite es la CPU

`--ib-perf` en calidad Alta da **unos 90 FPS** (percentil 99 de unos 15 ms y 14 tirones en 5.800 fotogramas, el peor de 115 ms en el bosque). La GPU solo tarda unos 6 ms, así que el límite es la CPU, a unos 11 ms por fotograma.

- Con todos los scripts del mundo apagados (`IB_OFF=...`) sube a 143 FPS. Los scripts cuestan unos 4,4 ms.
- Por partes (con mucho ruido, ±10 %):
  - `gameplay.gd`: unos 1,9 ms. Su propio código son 0,8 ms; el resto lo paga el motor al aplicar transformaciones.
  - 17 avatares: unos 1 ms.
  - Granja: unos 0,4 ms.
- Los otros ~3 ms de diferencia con el banco de vistas salen del render en CPU (unas 3.000 llamadas de dibujo en el pueblo, unos 2,3 ms) y de lo que el juego añade: jugador, HUD, sonido y física.
- `Performance.TIME_PROCESS` no sirve para medir los scripts: incluye todo el fotograma.

### Lo que falta

**1. Optimización (CPU, lo prioritario ahora):**

- **LOD de animación de los avatares** (ver 1.3): sin rayos de pies a más de 25 m, muelles cada 2 fotogramas a más de 25 m, pose fija a más de 60 m y nada fuera de cámara. También el muelle exacto en vez de subpasos de 1/120 s.
- **Vecinos (`npc.gd`):** a más de 60 m, actualizar cada 3 o 4 fotogramas.
- **Granja y animales:** animar cada 2 o 3 fotogramas a media distancia.
- **`ribbon.gd`** (12 cintas con física): pararlas lejos.
- **Llamadas de dibujo:** juntar las piezas estáticas de cada casa o prop por material, para bajar de 3.000 a unas pocas centenas.
  - Ojo: el shader `toon` usa el espacio del objeto para el dibujo de madera, corteza o paja. Al juntar piezas hay que pasar la posición y normal locales en `CUSTOM0` y `CUSTOM1` (ya existe `rest_from_custom`).
  - Excluir lo que el código anima o busca por nombre: banderines (`Flags`), llamas, farolas, cofres, aros, faros y animales.
- **Perfilar mejor:** medir con `--ib-perf` y repetir 2 o 3 veces, porque hay ±10 % de ruido entre ejecuciones.
- Pendiente de antes: generar la hierba en un hilo (1.3), cachear o paralelizar el arranque, que ahora tarda unos 3,5 s (con los LOD, 2,5 s solo para lugares y flora), y precompilar shaders (1.4).
- **Terreno:** cuesta unos 3 ms en la vista aérea. Se podría hacer LOD por trozos, con cuidado de las grietas entre trozos.

**2. Fluidez:** todo lo del apartado 2 sigue pendiente. `--ib-perf` ya da los tirones con su lugar: hay picos de hasta 115 ms en el bosque, probablemente por la hierba o por compilar shaders. Hay que investigarlos.

**3. Físicas con objetos:** todo lo del apartado 3 sigue pendiente.

### Cómo medir

```powershell
python tools/run_hidden.py --timeout=300 -- --path . --audio-driver Dummy --disable-vsync -- --ib-look --hour=10 --only=bench --quality=2
python tools/run_hidden.py --timeout=300 -- --path . --audio-driver Dummy -- --ib-perf
```

`--ib-perf` desactiva el vsync por su cuenta.

---

## 0. Punto de partida (medido)

Medido con `--ib-look --only=bench`, a 1600x900 y sin vsync, en una RTX 5050:

| Vista | Versión original (`927ec13`…`6dc18f8`) | Versión actual |
|---|---|---|
| Pueblo (con 12 vecinos) | 82,6 FPS | 67,7 FPS |
| Bosque | 66,9 FPS | 70,1 FPS |
| Pradera | 98,3 FPS | 84,4 FPS |
| Vista aérea | 98,6 FPS | 84,2 FPS |

Comando para medir:

```powershell
python tools/run_hidden.py --timeout=300 -- --path . --audio-driver Dummy --disable-vsync -- --ib-look --hour=10 --only=bench
```

Con `IB_NOAV=1` se mide sin los 12 vecinos.

Coste aproximado de cada efecto, medido quitándolo de uno en uno en la vista del pueblo:

| Efecto | Coste |
|---|---|
| Hierba fina cercana (`Flora.GRASS_NEAR`) | ~4 FPS |
| Penumbra de las sombras (`light_angular_distance`) | ~3 FPS |
| 12 avatares con esqueleto, IK y rayos | ~2,5 FPS |
| Filtro de sombras suaves (`soft_shadow_filter_quality`) | 4 → 3 ya aplicado |
| Detalle del terreno | ya optimizado con ramas por distancia |
| Hojas de los árboles | ya optimizado con tabla constante; el bosque pasó de 40 a 70 FPS |

Sin medir aún: SSAO, SSIL, niebla volumétrica, glow, reflejos del agua (SSR), MSAA 2x + SMAA, y el coste de CPU de GDScript.

**Objetivo:** ≥ 120 FPS en el pueblo en calidad alta en este equipo, ≥ 60 FPS en gráficas integradas en calidad baja, y ningún fotograma por encima de 25 ms al pasear.

---

## 1. Optimización (máximos FPS)

### 1.1 Medir antes de tocar

- **Medidor en el juego:** añadir un modo de rendimiento que muestre los FPS, el tiempo de CPU y GPU por fotograma (`RenderingServer.viewport_get_measured_render_time_*`), las llamadas de dibujo y los triángulos (`Performance.RENDER_TOTAL_*`).
- **Banco ampliado:** sumar a `bench` vistas de playa, ruinas, noche (farolas y ventanas) y una carrera en bici por el pueblo. Además de la media, registrar el **percentil 99** del tiempo por fotograma.
- **CPU o GPU:** averiguar qué limita en cada vista con el perfilador de Godot (`--profiling`) y con el tiempo de GPU medido.

### 1.2 GPU

- **Ajustes de calidad en el menú:** Baja, Media, Alta y Ultra, en lugar del interruptor actual de dos estados. Cada nivel controla:
  - SSAO, SSIL, niebla volumétrica, SSR del agua y glow.
  - Penumbra y filtro de las sombras.
  - Distancia de sombras, número de cascadas (4 → 2 en Baja) y tamaño del mapa de sombras (4096 → 2048).
  - MSAA (desactivado, 2x o 4x) y SMAA o FXAA.
  - Radio de la hierba fina y de la hierba total, y densidad de tarjetas de hojas.
  - Escala de resolución 3D con FSR 2 (`viewport.scaling_3d_mode`) al 67 % o 77 %, que es lo que más FPS da en equipos modestos.
- **Hierba:**
  - Variantes de malla por distancia (20 briznas → 9 → 4), en vez de solo cercana y lejana.
  - Trozos de hierba más pequeños solo cerca, para que el cambio de detalle sea más fino.
  - Comprobar que la hierba no proyecta sombras (ya es así) y que la cercana no hace sobredibujo innecesario.
- **Árboles:**
  - Impostores (tarjeta con la copa prerenderizada) más allá de unos 120 m.
  - Las tarjetas de hojas no deberían proyectar sombras desde lejos: sombra solo del núcleo de la copa a partir de cierta distancia (dos MultiMesh: núcleo con sombra y hojas sin ella lejos).
  - Revisar la "sombra con recorte alfa" de las hojas, que también ejecuta el shader de hojas en el pase de sombras.
- **Rangos de visibilidad (HLOD):** poner `visibility_range` a todos los props del pueblo, las granjas, las vallas, los banderines y los personajes. Lo lejano se dibuja con mallas simplificadas o no se dibuja.
- **Menos llamadas de dibujo:**
  - Juntar las piezas estáticas de cada casa o prop en una sola malla por material (`SurfaceTool.append_from`). Ahora muchos props son decenas de `MeshInstance3D` sueltos.
  - Los avatares tienen unas 40 piezas cada uno (pelo, ojos, sombrero...). Juntar la cabeza en una sola malla y dejar aparte solo lo que se anima (ojos, boca, cejas).
- **Shaders:**
  - El shader `toon` evalúa patrones de superficie (vóronoi a tres proyecciones) en cada píxel de piedra y enlucido. Apagarlo por distancia con ramas, como ya se hace en el terreno.
  - En calidad baja, una variante sin relieve.
- **Oclusión:** probar el *occlusion culling* de Godot (`OccluderInstance3D`) en el pueblo (casas) y en los acantilados.
- **Agua:** SSR con menos pasos en Media y desactivado en Baja; el mar lejano con menos subdivisiones.

### 1.3 CPU (GDScript)

- **Avatares:**
  - El `_process` de cada vecino (muelles de unas 28 articulaciones, IK y 2 rayos) corre aunque esté lejos. Usar LOD de animación:
    - A más de 25 m: sin rayos de pies, y muelles a media frecuencia o cada 2 fotogramas.
    - A más de 60 m: pose fija o solo la marcha básica.
    - Fuera de cámara: no animar (`VisibleOnScreenNotifier3D`).
  - Reducir los subpasos de los muelles: usar la solución exacta del muelle críticamente amortiguado en vez de integrar en pasos de 1/120 s.
- **Granja y animales:** ya se paran a más de 160 m; además, animar cada 2 o 3 fotogramas a media distancia.
- **Generación de hierba:** se construyen 2 trozos por fotograma en el hilo principal, y genera picos al correr o en bici. Moverlo a un hilo (`WorkerThreadPool`) que solo calcule las transformaciones y los colores, y crear el `MultiMesh` en el hilo principal con `RenderingServer.multimesh_set_buffer` (un solo `PackedFloat32Array`, mucho más rápido que `set_instance_transform` en bucle).
- **Arranque:** la isla, el terreno y la flora tardan unos 3 s. Cachear en disco los resultados deterministas (alturas, normales, colores) o generar en hilos.

### 1.4 Ajustes de proyecto

- **Vsync y límite de FPS:** opción de *vsync* en el menú (activado, desactivado o adaptativo) y de límite de FPS (`Engine.max_fps`: 60, 120, 144 o sin límite).
- **Precompilar shaders:** en la pantalla de título o de carga, enseñar un fotograma con todos los materiales (agua, hojas, hierba, avatares, fuego, partículas) para que no compilen a mitad del juego. En Godot 4.4+ hay *ubershaders*, pero conviene verificar.

---

## 2. Fluidez (sin tirones)

- **Ticks de física:** subir `physics_ticks_per_second` de 60 a 120 (o igualarlo a la frecuencia de la pantalla) si la CPU lo permite. Ya hay interpolación física; revisar que todo lo que se mueve en `_physics_process` la use: jugador, barca, carro, mascotas.
- **Vecinos, mascotas y animales:** ahora se mueven en `_process`. Funciona, pero el movimiento depende del fotograma. Pasarlos a física con interpolación, o al menos suavizar con `delta` estable.
- **Picos de un fotograma:**
  - Hierba (ver 1.3).
  - Primera aparición de partículas: precalentar con `GPUParticles3D.preprocess` y crear las partículas de polvo una vez y reutilizarlas.
  - Carga de audio: ya se cargan bajo demanda con `load()`; precargar en `Audio`.
  - `queue_free` masivo al cambiar de zona.
- **Cámara:** revisar que use la posición interpolada de todo (ya usa la del jugador) y que el *spring arm* no dé saltos al chocar. Suavizar la distancia al recuperar.
- **Medir el ritmo de fotogramas:** registrar el percentil 99 del tiempo por fotograma en el banco y en el clip de juego (`--ib-clip`).

---

## 3. Físicas con objetos (empujar, coger, lanzar, no atravesar)

El proyecto ya usa **Jolt Physics**.

### 3.1 Objetos físicos

- **Nueva clase `PhysProp`** (`RigidBody3D`): masa, material físico (fricción y rebote), forma de colisión simple (caja, cilindro o cápsula) y sonido de golpe según la velocidad del impacto (`body_entered` y `contact_monitor`).
- **Candidatos:**

  | Tipo | Objetos |
  |---|---|
  | Ligeros (se cogen y se lanzan) | cubos, cestas, cajas pequeñas, balones, cocos, piedras pequeñas, troncos cortos, macetas, paquetes de Correos, pan |
  | Pesados (solo se empujan) | barriles, cajas grandes, balas de paja |

  Hoy las cajas y los barriles de `Props` son estáticos (`StaticBody3D`).
- **Rendimiento:** los objetos duermen (`can_sleep`) y solo existen como `RigidBody3D` cerca de Lía, a menos de unos 40 m; lejos son decoración estática. Guardar su posición si se han movido (`SaveGame`).
- **Agua:** flotabilidad sencilla en mar y lago, con fuerza hacia arriba según lo sumergido y amortiguación.

### 3.2 Interacción de Lía

- **Empujar:** al chocar el `CharacterBody3D` contra un `RigidBody3D`, aplicarle un impulso (`apply_central_impulse` según `get_slide_collision`), limitado por la masa. Los pesados se empujan despacio y Lía pone la pose de empujar (las dos manos contra el objeto por IK).
- **Coger y llevar:** con E delante de un objeto ligero, Lía se agacha (pose `pickup` + IK de brazo, ya existente), lo levanta y lo lleva con las dos manos delante del pecho.
  - El objeto sigue un punto con un muelle físico (fuerza o velocidad hacia el objetivo), no con la transformación a pelo. Así choca con paredes y no las atraviesa.
  - Si queda atascado lejos del punto, se suelta.
  - Mientras lleva algo: no escala ni planea, y corre un poco más despacio según la masa.
- **Soltar y lanzar:** Q para soltar; mantener E y soltar para lanzar con una fuerza que crece mientras se mantiene, con un arco de previsualización.
- **Animales y mascotas:** que reaccionen (se aparten o persigan la pelota).

### 3.3 No atravesar

- **Detección continua (CCD):** `continuous_cd = true` en objetos lanzados o rápidos.
- **Capas de colisión:** hoy 1 = mundo y 3 = personajes. Añadir 4 = objetos físicos y 5 = lo que se lleva en la mano. Lo que se lleva no choca con Lía pero sí con el mundo; los rayos de los pies (máscara 1) ignoran los objetos o los incluyen según convenga (pisar una caja).
- **Personajes:**
  - Que el cuerpo del avatar no atraviese paredes al girar o al estar pegado a ellas: hoy la cápsula es de 0,32 m de radio y la mochila y los brazos sobresalen. Opciones: radio algo mayor, o empujar el avatar visual hacia fuera con un rayo hacia atrás.
  - Manos y pies contra paredes al escalar (los pies ya se apoyan por IK).
  - Que el pelo, la bufanda y la mochila no atraviesen el propio cuerpo (la bufanda ya usa cápsulas del cuerpo).
- **Vecinos:** que no se atraviesen entre sí ni con Lía al pasear, con una evitación sencilla (separación entre ellos y rodear obstáculos con rayos). Ahora pasean en línea recta evitando solo las casas.
- **Cámara:** que no atraviese la hierba alta ni los objetos físicos (máscara del `SpringArm3D`).

### 3.4 Pruebas

- **Pruebas automáticas** en `--ib-move`:
  - Lía empuja una caja 2 m.
  - Coge un objeto, lo lleva por el pueblo sin que atraviese una casa y lo lanza.
  - Un objeto lanzado contra una pared no la atraviesa (CCD).
  - Un objeto en el agua flota.
- **Clip visual** en `--ib-clip`: coger, llevar y lanzar.

---

## Estado al dejar esto documentado

- **Hecho en esta tanda (sin confirmar en git):**
  - Personajes con esqueleto, IK de piernas y brazo, muelles y bufanda con física.
  - Movimiento con inercia y cámara mejorada.
  - Hierba, hojas, roca, agua y tienda nuevas.
  - Marchas de los animales y mascotas, y pasos con huellas.
- **Ejecutable:** `dist/windows/IslaBrisa.exe` regenerado el 7 de octubre de 2026 (con las mejoras de rendimiento); pasa `--ib-test` (403 comprobaciones).
- **Herramientas nuevas:**
  - `--ib-clip`: clips de juego con piloto automático.
  - `--ib-look --only=bench`: rendimiento.
  - `--only=gait`: tiras de la marcha.
  - `--only=closeup`: primeros planos.
  - `--tonemap` y `--exposure`.
