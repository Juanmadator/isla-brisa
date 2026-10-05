class_name MapView
extends Control
## Mapa de la isla: imagen cenital con faros, vecinos, lugares descubiertos, objetivo y Lía.

var tex: Texture2D
var gp: Gameplay
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func world_to_map(p: Vector3, rect: Rect2) -> Vector2:
	var u := (p.x + Island.HALF) / (Island.HALF * 2.0)
	var v := (p.z + Island.HALF) / (Island.HALF * 2.0)
	return rect.position + Vector2(u, v) * rect.size


func _draw() -> void:
	if tex == null or gp == null:
		return
	var s := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
	draw_texture_rect(tex, rect, false)
	draw_rect(rect, Color(0.1, 0.18, 0.26), false, 3.0)
	var font := UiKit.font(600)
	# Nombres de lugares descubiertos
	for n in Places.NAMED:
		if not SaveGame.is_discovered(n[0]):
			continue
		var c: Vector2 = n[2]
		var mp := world_to_map(Vector3(c.x, 0, c.y), rect)
		var txt: String = n[1]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string_outline(font, mp - Vector2(w * 0.5, -22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(1, 1, 1, 0.9))
		draw_string(font, mp - Vector2(w * 0.5, -22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.15, 0.2, 0.28))
	# Faros
	for id in Catalog.BEACONS:
		var mp := world_to_map(gp.places.anchor(id), rect)
		var lit := SaveGame.flag("lit_" + id)
		var col: Color = Places.REGION_COLORS[id] if lit else Color(0.72, 0.76, 0.8)
		if lit:
			draw_circle(mp, 13.0 + sin(_t * 3.0) * 2.0, Color(col.r, col.g, col.b, 0.35))
		draw_rect(Rect2(mp - Vector2(5, 9), Vector2(10, 18)), col)
		draw_rect(Rect2(mp - Vector2(5, 9), Vector2(10, 18)), Color(0.1, 0.12, 0.16), false, 2.0)
	# Vecinos (solo los que ya conoces o los del pueblo)
	for id in gp.npcs:
		var npc: Npc = gp.npcs[id]
		var mp := world_to_map(npc.position, rect)
		draw_circle(mp, 5.0, Color(0.98, 0.9, 0.75))
		draw_arc(mp, 5.0, 0, TAU, 12, Color(0.1, 0.12, 0.16), 1.5, true)
		if npc.has_news:
			draw_string_outline(font, mp + Vector2(-4, -8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0.3, 0.15, 0.0))
			draw_string(font, mp + Vector2(-4, -8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiKit.C_GOLD)
	# Objetivo
	var q := gp.tracked_quest()
	if not q.is_empty() and q.get("target", Vector3.ZERO) != Vector3.ZERO:
		var mp := world_to_map(q["target"], rect)
		var rad: float = q.get("radius", 0.0)
		if rad > 0.0:
			var rp := rad / (Island.HALF * 2.0) * rect.size.x * 1.6 + 6.0
			draw_circle(mp, rp, Color(1.0, 0.82, 0.3, 0.22))
			draw_arc(mp, rp, 0, TAU, 32, Color(1.0, 0.75, 0.2, 0.9), 2.0, true)
		var bob := sin(_t * 4.0) * 3.0
		var pts := PackedVector2Array([mp + Vector2(0, -4 + bob), mp + Vector2(-9, -20 + bob), mp + Vector2(9, -20 + bob)])
		draw_colored_polygon(pts, UiKit.C_GOLD)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.2, 0.12, 0.0), 2.0, true)
	# Lía
	var pp := world_to_map(gp.player.global_position, rect)
	var yaw: float = gp.player.facing
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var tri := PackedVector2Array([pp + fwd * 12.0, pp - fwd * 7.0 + right * 7.0, pp - fwd * 4.0, pp - fwd * 7.0 - right * 7.0])
	draw_colored_polygon(tri, Color(1.0, 0.35, 0.3))
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(1, 1, 1), 2.0, true)
