class_name Critters
extends Node3D
## Vida del paisaje: mariposas alrededor del jugador (de día, en la hierba) y gaviotas
## que planean en círculos sobre la costa.

const BUTTERFLIES := 12
const GULL_SPOTS := [Vector3(15, 22, 240), Vector3(130, 26, 215), Vector3(-120, 30, 205), Vector3(225, 55, -40), Vector3(-30, 28, -240)]

var island: Island
var focus := Vector3.ZERO
var daylight := 1.0
var _flies: Array = []
var _gulls: Array = []
var _rng := RandomNumberGenerator.new()
var _t := 0.0


func build(isl: Island) -> void:
	island = isl
	_rng.seed = 31
	var cols := [Color(1.0, 0.85, 0.3), Color(0.55, 0.75, 1.0), Color(1.0, 0.6, 0.75), Color(1.0, 1.0, 1.0), Color(1.0, 0.55, 0.25)]
	for i in BUTTERFLIES:
		var b := _butterfly(cols[i % cols.size()])
		add_child(b["root"])
		b["home"] = Vector3.ZERO
		b["phase"] = _rng.randf() * TAU
		b["speed"] = _rng.randf_range(0.8, 1.4)
		_flies.append(b)
		_place_fly(b)
	var idx := 0
	for spot in GULL_SPOTS:
		for k in 2:
			var g := _gull()
			add_child(g["root"])
			g["center"] = spot + Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-3, 5), _rng.randf_range(-8, 8))
			g["radius"] = _rng.randf_range(12.0, 22.0)
			g["phase"] = _rng.randf() * TAU
			g["dir"] = 1.0 if (idx + k) % 2 == 0 else -1.0
			g["speed"] = _rng.randf_range(0.18, 0.28)
			_gulls.append(g)
		idx += 1


func _butterfly(col: Color) -> Dictionary:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var wings := []
	for sx: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		root.add_child(pivot)
		var w := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.14, 0.12)
		w.mesh = q
		w.material_override = mat
		w.rotation_degrees.x = -90
		w.position = Vector3(sx * 0.07, 0, 0)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(w)
		wings.append(pivot)
	MeshKit.part(root, MeshKit.capsule(0.012, 0.09), MeshKit.mat(Color(0.15, 0.12, 0.1), 0.0), Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
	return {"root": root, "wings": wings}


func _gull() -> Dictionary:
	var root := Node3D.new()
	var white := MeshKit.mat(Color(0.98, 0.98, 0.96), 0.015)
	var grey := MeshKit.mat(Color(0.6, 0.64, 0.7), 0.015)
	MeshKit.part(root, MeshKit.capsule(0.09, 0.5), white, Vector3.ZERO, Vector3(90, 0, 0))
	MeshKit.part(root, MeshKit.cone(0.03, 0.1, 6), MeshKit.mat(Color(1.0, 0.75, 0.25), 0.0), Vector3(0, 0.02, -0.3), Vector3(-90, 0, 0))
	var wings := []
	for sx: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 0.06, 0.03, 0)
		root.add_child(pivot)
		MeshKit.part(pivot, MeshKit.rounded_box(Vector3(0.55, 0.03, 0.2), 0.012, 1), white, Vector3(sx * 0.3, 0, 0))
		MeshKit.part(pivot, MeshKit.rounded_box(Vector3(0.18, 0.032, 0.16), 0.012, 1), grey, Vector3(sx * 0.62, 0, 0.02))
		wings.append(pivot)
	return {"root": root, "wings": wings}


func _place_fly(b: Dictionary) -> void:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(4.0, 22.0)
	var p := focus + Vector3(cos(a) * r, 0, sin(a) * r)
	b["home"] = p


func _process(delta: float) -> void:
	_t += delta
	# Mariposas: solo de día y sobre hierba o prado.
	for b in _flies:
		var root: Node3D = b["root"]
		var home: Vector3 = b["home"]
		if Vector2(home.x - focus.x, home.z - focus.z).length() > 30.0:
			_place_fly(b)
			home = b["home"]
		var biome := island.biome_at(home.x, home.z)
		var ok := daylight > 0.5 and (biome == Island.Biome.GRASS or biome == Island.Biome.MEADOW or biome == Island.Biome.FOREST)
		root.visible = ok
		if not ok:
			continue
		var ph: float = b["phase"] + _t * b["speed"]
		var off := Vector3(sin(ph * 0.7) * 2.2 + sin(ph * 1.9) * 0.6, 0.0, cos(ph * 0.5) * 2.2 + sin(ph * 2.3) * 0.5)
		var p := home + off
		p.y = island.height_at(p.x, p.z) + 0.8 + sin(ph * 2.7) * 0.35
		var prev := root.position
		root.position = p
		var mv := p - prev
		if mv.length() > 0.0005:
			root.rotation.y = atan2(-mv.x, -mv.z)
		var flap := sin(_t * 22.0 + ph * 3.0) * 1.1
		(b["wings"][0] as Node3D).rotation.z = flap
		(b["wings"][1] as Node3D).rotation.z = -flap
	# Gaviotas en círculos.
	for g in _gulls:
		var root: Node3D = g["root"]
		var ph: float = g["phase"] + _t * g["speed"] * g["dir"]
		var c: Vector3 = g["center"]
		var r: float = g["radius"]
		root.position = c + Vector3(cos(ph) * r, sin(ph * 2.0) * 1.5, sin(ph) * r)
		var tangent: Vector3 = Vector3(-sin(ph), 0, cos(ph)) * float(g["dir"])
		root.rotation = Vector3(0, atan2(-tangent.x, -tangent.z), -0.35 * g["dir"])
		var flapping := fmod(ph * 0.6, 1.0) < 0.35
		var a := sin(_t * 9.0) * 0.6 if flapping else 0.08
		(g["wings"][0] as Node3D).rotation.z = a
		(g["wings"][1] as Node3D).rotation.z = -a
