class_name WindLines
extends Node3D
## Remolinos de viento blancos que cruzan el aire alrededor del jugador (como en BotW).
## Su cantidad depende de `strength` (el viento que ha vuelto a la isla).

const COUNT := 10

var focus := Vector3.ZERO
var strength := 0.0
var wind_dir := Vector2(1.0, 0.35)
var island: Island
var _streaks: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 77
	for i in COUNT:
		var r := Ribbon.new()
		r.width = 0.1
		r.max_points = 34
		r.color = Color(1, 1, 1, 0.75)
		add_child(r)
		_streaks.append({"ribbon": r, "life": -_rng.randf() * 4.0, "dur": 2.5, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "curl_at": 1.0, "curl": 0.0})


func _spawn(s: Dictionary) -> void:
	var cam := get_viewport().get_camera_3d()
	var fwd := Vector3(0, 0, -1)
	if cam:
		fwd = -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var wind := Vector3(wind_dir.x, 0, wind_dir.y).normalized()
	var p := focus + fwd * _rng.randf_range(6.0, 24.0) + side * _rng.randf_range(-16.0, 16.0) - wind * 8.0
	var ground := island.height_at(p.x, p.z) if island else 0.0
	p.y = maxf(ground, 0.0) + _rng.randf_range(1.0, 7.0)
	s["pos"] = p
	s["vel"] = wind * _rng.randf_range(6.0, 10.0) + Vector3(0, _rng.randf_range(-0.3, 0.6), 0)
	s["life"] = 0.0
	s["dur"] = _rng.randf_range(1.6, 2.6)
	s["curl_at"] = _rng.randf_range(0.3, 0.6)
	s["curl"] = (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(7.0, 10.0)
	(s["ribbon"] as Ribbon).points.clear()


func _process(delta: float) -> void:
	var active := int(round(clampf(strength, 0.0, 1.2) / 1.2 * COUNT))
	for i in _streaks.size():
		var s: Dictionary = _streaks[i]
		var r: Ribbon = s["ribbon"]
		s["life"] += delta
		if s["life"] < 0.0:
			continue
		var t: float = s["life"] / s["dur"]
		if t >= 1.0:
			r.shrink()
			r.shrink()
			if r.points.size() <= 1:
				if i < active:
					_spawn(s)
				else:
					s["life"] = -_rng.randf_range(0.5, 2.0)
					r.points.clear()
			continue
		var vel: Vector3 = s["vel"]
		# Un rizo en mitad del recorrido.
		var ct: float = s["curl_at"]
		if t > ct and t < ct + 0.3:
			vel = vel.rotated(Vector3(vel.z, 0, -vel.x).normalized(), float(s["curl"]) * delta * 0.9)
		s["vel"] = vel
		s["pos"] = (s["pos"] as Vector3) + vel * delta
		r.push(s["pos"])
