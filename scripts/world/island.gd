class_name Island
extends RefCounted
## Datos de Isla Brisa: alturas, colores y biomas del terreno, y los lugares clave.
## Todo sale de funciones deterministas (misma semilla, misma isla), sin archivos externos.
## Ejes: X hacia el este, Z hacia el sur (el norte es -Z).

const HALF := 320.0
const STEP := 1.0
const N := 641
## El ruido (lo caro) se evalúa en una rejilla de 2 m y luego se interpola a 1 m.
const COARSE_STEP := 2.0
const COARSE_N := 321
const SEA_LEVEL := 0.0
const LAKE_LEVEL := 15.0

# Lugares que dan forma al relieve.
const MOUNT := Vector2(0, -170)
const SUMMIT_Y := 121.0
const CLIFF := Vector2(236, 8)
const CLIFF_Y := 46.0
const WINDMILL_HILL := Vector2(92, 132)
const PENON := Vector2(-165, 158)
const PENON_Y := 64.0
const ISLET := Vector2(-262, 268)
const ISLET_Y := 21.0
const FOREST := Vector2(-165, 10)
const LAKE := Vector2(-150, -48)
const LAKE_ISLET := Vector2(-141, -41)
const VILLAGE := Vector2(15, 168)
const VILLAGE_Y := 5.5
const RUINS := Vector2(168, -138)
const RUINS_Y := 50.0

enum Biome { WATER, SAND, GRASS, FOREST, ROCK, SNOW, PATH, MEADOW }

## Caminos de tierra (polilíneas en XZ) que unen el pueblo con cada región.
const PATHS := [
	[Vector2(8, 222), Vector2(12, 196), Vector2(15, 168)],
	[Vector2(15, 168), Vector2(52, 150), Vector2(78, 138)],
	[Vector2(15, 168), Vector2(-30, 140), Vector2(-80, 100), Vector2(-118, 40), Vector2(-128, -2)],
	[Vector2(15, 168), Vector2(70, 110), Vector2(130, 70), Vector2(186, 40)],
	[Vector2(15, 168), Vector2(20, 110), Vector2(30, 40), Vector2(60, -20), Vector2(110, -70), Vector2(132, -98)],
	[Vector2(20, 110), Vector2(-5, 60), Vector2(-8, 0)],
	[Vector2(-30, 140), Vector2(-100, 150), Vector2(-128, 146)],
]

var _n := N
var _step := STEP
var heights := PackedFloat32Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var biomes := PackedByteArray()

var _n_hills := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_coast := FastNoiseLite.new()
var _n_color := FastNoiseLite.new()


func _init() -> void:
	_n_hills.seed = 1207
	_n_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_hills.frequency = 0.0065
	_n_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_hills.fractal_octaves = 4
	_n_detail.seed = 77
	_n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_detail.frequency = 0.035
	_n_detail.fractal_octaves = 2
	_n_ridge.seed = 4242
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_ridge.frequency = 0.011
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 4
	_n_coast.seed = 99
	_n_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_coast.frequency = 0.012
	_n_color.seed = 5
	_n_color.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_color.frequency = 0.02
	_n_color.fractal_octaves = 3


static func ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Meseta de radio `r_top` a altura `top`: paredes de `wall_w` metros de ancho y, en la
## dirección `ramp_dir`, una rampa de `ramp_w` metros para subir andando.
static func _plateau(h: float, rel: Vector2, top: float, r_top: float, wall_w: float, ramp_dir: Vector2, ramp_w: float) -> float:
	var d := rel.length()
	var cosang := rel.dot(ramp_dir) / maxf(d, 0.001)
	var rk := ss(0.62, 0.92, cosang) if ramp_w > 0.0 else 0.0
	var width := lerpf(wall_w, ramp_w, rk)
	var k := ss(r_top + width, r_top, d)
	return maxf(h, lerpf(h, top, k))


func coast_radius(dir: Vector2) -> float:
	return 238.0 + 34.0 * _n_coast.get_noise_2d(dir.x * 60.0, dir.y * 60.0) + 14.0 * _n_coast.get_noise_2d(dir.x * 160.0 + 50.0, dir.y * 160.0)


func raw_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var c := p - Vector2(0, 15)
	var d := c.length()
	var cr := coast_radius(c / maxf(d, 0.001))
	var land := ss(cr + 18.0, cr - 32.0, d)
	var h := lerpf(-14.0, 5.0, land)
	var inland := ss(cr - 15.0, cr - 95.0, d)
	h += (_n_hills.get_noise_2d(x, z) * 0.5 + 0.5) * 15.0 * inland
	h += _n_detail.get_noise_2d(x, z) * 1.1 * land

	# Bosque: una meseta suave al oeste.
	var df := p.distance_to(FOREST)
	h += 12.0 * ss(135.0, 70.0, df) * land

	# Pico Brisa
	var dm := p.distance_to(MOUNT)
	var mt := maxf(0.0, 1.0 - dm / 178.0)
	h += 104.0 * pow(mt, 1.65) + (_n_ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 16.0 * pow(mt, 0.8)
	h = lerpf(h, SUMMIT_Y, ss(17.0, 9.0, dm))

	# Colina del molino
	var dw := p.distance_to(WINDMILL_HILL)
	h += 22.0 * exp(-pow(dw / 40.0, 2.0))

	# Acantilado del este: meseta con paredes verticales.
	var da := p.distance_to(CLIFF) + _n_detail.get_noise_2d(x * 2.0, z * 2.0) * 2.0 + _n_coast.get_noise_2d(x * 4.0, z * 4.0) * 7.0
	h = lerpf(h, CLIFF_Y + _n_detail.get_noise_2d(x, z) * 1.2, ss(37.0, 31.0, da))

	# Peñón del Salto: rampa desde el interior (NE) y pared hacia el mar.
	var pn := _n_detail.get_noise_2d(x * 2.0, z * 2.0) * 2.5
	h = _plateau(h, p - PENON, PENON_Y, 9.0 + pn, 14.0, Vector2(0.75, -0.66).normalized(), 110.0)

	# Islote del faro, en mar abierto.
	var di := p.distance_to(ISLET) + _n_detail.get_noise_2d(x * 3.0, z * 3.0) * 1.5
	h = maxf(h, lerpf(h, ISLET_Y, ss(17.0, 12.0, di)))

	# Meseta de las ruinas con rampa hacia el suroeste.
	var rn := _n_coast.get_noise_2d(x * 3.0, z * 3.0) * 7.0
	h = _plateau(h, p - RUINS, RUINS_Y + _n_detail.get_noise_2d(x * 0.5, z * 0.5) * 1.5, 46.0 + rn, 9.0, Vector2(-0.62, 0.78).normalized(), 120.0)

	# Pueblo: llano.
	var dv := p.distance_to(VILLAGE)
	h = lerpf(h, VILLAGE_Y, ss(64.0, 42.0, dv))

	# Lago Espejo: cubeta con borde asegurado por encima del agua y un islote.
	var dl := p.distance_to(LAKE) + _n_coast.get_noise_2d(x * 4.0, z * 4.0) * 8.0
	var rim_h := maxf(h, LAKE_LEVEL + 3.5)
	h = lerpf(lerpf(h, rim_h, ss(92.0, 66.0, dl)), 6.5, ss(46.0, 24.0, dl))
	var dli := p.distance_to(LAKE_ISLET)
	h = maxf(h, lerpf(h, LAKE_LEVEL + 2.2, ss(7.5, 4.0, dli)))
	return h


func generate() -> void:
	# 1) Relieve, normales y colores en la rejilla gruesa (2 m).
	_n = COARSE_N
	_step = COARSE_STEP
	heights.resize(_n * _n)
	for zi in _n:
		var z := -HALF + zi * _step
		for xi in _n:
			heights[zi * _n + xi] = raw_height(-HALF + xi * _step, z)
	_compute_normals()
	_paint()
	# 2) Rejilla fina (1 m): alturas con Catmull-Rom, colores bilineales, biomas al más cercano.
	var ch := heights
	var cc := colors
	var cb := biomes
	_n = N
	_step = STEP
	heights = _upsample(ch, COARSE_N)
	colors = _upsample_colors(cc, COARSE_N)
	biomes = _upsample_nearest(cb, COARSE_N)
	_compute_normals()


static func _mid(p0: float, p1: float, p2: float, p3: float) -> float:
	var v := (-p0 + 9.0 * p1 + 9.0 * p2 - p3) / 16.0
	return clampf(v, minf(p1, p2) - 0.35, maxf(p1, p2) + 0.35)


## Duplica la resolución de una rejilla cuadrada (cn x cn -> 2cn-1).
static func _upsample(c: PackedFloat32Array, cn: int) -> PackedFloat32Array:
	var fn := cn * 2 - 1
	var tmp := PackedFloat32Array()
	tmp.resize(fn * cn)
	for z in cn:
		var row := z * cn
		for x in fn:
			var i := x >> 1
			if x & 1 == 0:
				tmp[z * fn + x] = c[row + i]
			else:
				tmp[z * fn + x] = _mid(c[row + maxi(i - 1, 0)], c[row + i], c[row + i + 1], c[row + mini(i + 2, cn - 1)])
	var out := PackedFloat32Array()
	out.resize(fn * fn)
	for z in fn:
		var i := z >> 1
		if z & 1 == 0:
			for x in fn:
				out[z * fn + x] = tmp[i * fn + x]
		else:
			var r0 := maxi(i - 1, 0) * fn
			var r1 := i * fn
			var r2 := (i + 1) * fn
			var r3 := mini(i + 2, cn - 1) * fn
			for x in fn:
				out[z * fn + x] = _mid(tmp[r0 + x], tmp[r1 + x], tmp[r2 + x], tmp[r3 + x])
	return out


static func _upsample_colors(c: PackedColorArray, cn: int) -> PackedColorArray:
	var fn := cn * 2 - 1
	var out := PackedColorArray()
	out.resize(fn * fn)
	for z in fn:
		var z0 := z >> 1
		var z1 := mini(z0 + (z & 1), cn - 1)
		for x in fn:
			var x0 := x >> 1
			var x1 := mini(x0 + (x & 1), cn - 1)
			out[z * fn + x] = (c[z0 * cn + x0] + c[z0 * cn + x1] + c[z1 * cn + x0] + c[z1 * cn + x1]) * 0.25
	return out


static func _upsample_nearest(c: PackedByteArray, cn: int) -> PackedByteArray:
	var fn := cn * 2 - 1
	var out := PackedByteArray()
	out.resize(fn * fn)
	for z in fn:
		for x in fn:
			out[z * fn + x] = c[(z >> 1) * cn + (x >> 1)]
	return out


func _compute_normals() -> void:
	normals.resize(_n * _n)
	for zi in _n:
		for xi in _n:
			var hl := heights[zi * _n + maxi(xi - 1, 0)]
			var hr := heights[zi * _n + mini(xi + 1, _n - 1)]
			var hu := heights[maxi(zi - 1, 0) * _n + xi]
			var hd := heights[mini(zi + 1, _n - 1) * _n + xi]
			normals[zi * _n + xi] = Vector3(hl - hr, 2.0 * _step, hu - hd).normalized()


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func path_distance(p: Vector2) -> float:
	var best := INF
	for line in PATHS:
		for i in line.size() - 1:
			best = minf(best, _seg_dist(p, line[i], line[i + 1]))
	return best


func _paint() -> void:
	colors.resize(_n * _n)
	biomes.resize(_n * _n)
	var sand := Color(0.95, 0.87, 0.62)
	var wet_sand := Color(0.8, 0.74, 0.56)
	var sea_floor := Color(0.5, 0.62, 0.56)
	var grass_a := Color(0.40, 0.71, 0.27)
	var grass_b := Color(0.6, 0.78, 0.3)
	var forest := Color(0.27, 0.53, 0.25)
	var meadow := Color(0.82, 0.75, 0.4)
	var alpine := Color(0.52, 0.63, 0.4)
	var rock_a := Color(0.64, 0.57, 0.5)
	var rock_b := Color(0.5, 0.47, 0.47)
	var snow := Color(0.95, 0.97, 1.0)
	var dirt := Color(0.78, 0.63, 0.42)
	for zi in _n:
		var z := -HALF + zi * _step
		for xi in _n:
			var x := -HALF + xi * _step
			var i := zi * _n + xi
			var h := heights[i]
			var ny := normals[i].y
			# La pendiente se mira también en los vecinos para que las paredes no tengan vetas verdes.
			for o: int in [-1, 1]:
				ny = minf(ny, normals[zi * _n + clampi(xi + o, 0, _n - 1)].y + 0.06)
				ny = minf(ny, normals[clampi(zi + o, 0, _n - 1) * _n + xi].y + 0.06)
			var p := Vector2(x, z)
			var cn := _n_color.get_noise_2d(x, z) * 0.5 + 0.5
			var wl := water_level(x, z)
			var col: Color
			var biome := Biome.GRASS
			var rocky := 0.0
			if h < wl - 0.6:
				col = wet_sand.lerp(sea_floor, ss(wl - 0.6, wl - 8.0, h))
				biome = Biome.WATER
			elif h < wl + 1.6 + cn * 1.2 and wl == SEA_LEVEL:
				col = sand.lerp(wet_sand, ss(wl + 0.6, wl - 0.6, h))
				biome = Biome.SAND
			else:
				col = grass_a.lerp(grass_b, ss(0.35, 0.75, cn))
				var df := p.distance_to(FOREST)
				var fk := ss(120.0, 85.0, df + cn * 30.0)
				if fk > 0.5:
					biome = Biome.FOREST
				col = col.lerp(forest, fk)
				var dr := p.distance_to(RUINS)
				var mk := ss(75.0, 55.0, dr) * ss(RUINS_Y - 14.0, RUINS_Y - 4.0, h)
				if mk > 0.5:
					biome = Biome.MEADOW
				col = col.lerp(meadow, mk)
				col = col.lerp(alpine, ss(55.0, 85.0, h))
				if h > 84.0 + cn * 10.0 and ny > 0.7:
					col = snow
					biome = Biome.SNOW
				var pd := path_distance(p) + cn * 0.8
				if pd < 2.2 and ny > 0.8:
					col = col.lerp(dirt, ss(2.2, 1.2, pd))
					if pd < 1.6:
						biome = Biome.PATH
			if biome != Biome.WATER:
				var rk := ss(0.8, 0.66, ny)
				if rk > 0.5:
					biome = Biome.ROCK if biome != Biome.SNOW else biome
				col = col.lerp(rock_a.lerp(rock_b, cn), rk)
				rocky = rk
			col.a = rocky
			colors[i] = col
			biomes[i] = biome


# --- Consultas ---------------------------------------------------------------

func water_level(x: float, z: float) -> float:
	if Vector2(x, z).distance_to(LAKE) < 57.0:
		return LAKE_LEVEL
	return SEA_LEVEL


func _cell(x: float, z: float) -> Vector2:
	return Vector2(clampf((x + HALF) / _step, 0.0, _n - 1.001), clampf((z + HALF) / _step, 0.0, _n - 1.001))


## Altura del terreno (interpolada igual que los triángulos de la malla).
func height_at(x: float, z: float) -> float:
	var c := _cell(x, z)
	var xi := int(c.x)
	var zi := int(c.y)
	var fx := c.x - xi
	var fz := c.y - zi
	var h00 := heights[zi * _n + xi]
	var h10 := heights[zi * _n + xi + 1]
	var h01 := heights[(zi + 1) * _n + xi]
	var h11 := heights[(zi + 1) * _n + xi + 1]
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


func normal_at(x: float, z: float) -> Vector3:
	var c := _cell(x, z)
	return normals[int(roundf(c.y)) * _n + int(roundf(c.x))]


func biome_at(x: float, z: float) -> int:
	var c := _cell(x, z)
	return biomes[int(roundf(c.y)) * _n + int(roundf(c.x))]


func color_at(x: float, z: float) -> Color:
	var c := _cell(x, z)
	return colors[int(roundf(c.y)) * _n + int(roundf(c.x))]


func ground(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y) + lift, p.y)


func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > water_level(x, z) + 0.3


## Punto de la costa yendo desde `from` en dirección `dir` (para colocar el muelle).
func find_shore(from: Vector2, dir: Vector2) -> Vector2:
	var p := from
	for i in 400:
		if height_at(p.x, p.y) < 0.4:
			return p
		p += dir.normalized()
	return p


## Imagen cenital del mapa (un píxel cada `px` metros).
func map_image(px := 2.0) -> Image:
	var size := int(HALF * 2.0 / px)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var shallow := Color(0.47, 0.84, 0.86)
	var deep := Color(0.2, 0.5, 0.75)
	for y in size:
		for x in size:
			var wx := -HALF + (x + 0.5) * px
			var wz := -HALF + (y + 0.5) * px
			var h := height_at(wx, wz)
			var wl := water_level(wx, wz)
			var col: Color
			if h < wl:
				col = shallow.lerp(deep, ss(wl - 0.5, wl - 12.0, h))
				if h > wl - 0.9:
					col = col.lerp(Color.WHITE, 0.55)
			else:
				col = color_at(wx, wz)
				col.a = 1.0
				var n := normal_at(wx, wz)
				var shade := clampf(n.dot(Vector3(-0.55, 0.75, -0.4).normalized()), 0.0, 1.0)
				col = col * (0.72 + 0.4 * shade)
				# Curvas de nivel cada 10 m
				if fmod(h, 10.0) < 0.6 and h > 2.0:
					col = col.darkened(0.12)
			col.a = 1.0
			img.set_pixel(x, y, col)
	return img
