class_name Icon
extends Control
## Iconos vectoriales dibujados con código: concha, pluma, estrella, faro, carta, gatito,
## seta, chispa, cofre, reloj, candado, marca de verificación, flecha, persona, huella,
## sombrero, camiseta, bufanda y paquete.

var kind := "star":
	set(v):
		kind = v
		queue_redraw()
var tint := Color(0, 0, 0, 0):
	set(v):
		tint = v
		queue_redraw()

const OUT := Color(0.1, 0.16, 0.24)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _col(default: Color) -> Color:
	return tint if tint.a > 0.0 else default


func _poly(pts: PackedVector2Array, fill: Color, width := 2.0) -> void:
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, OUT, width, true)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5
	var w := maxf(1.5, s * 0.07)
	match kind:
		"shell":
			var pts := PackedVector2Array()
			for i in 13:
				var a := lerpf(PI * 1.05, TAU - PI * 0.05, i / 12.0)
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.82 + Vector2(0, r * 0.25))
			pts.append(c + Vector2(r * 0.22, r * 0.7))
			pts.append(c + Vector2(-r * 0.22, r * 0.7))
			_poly(pts, _col(Color(1.0, 0.72, 0.66)), w)
			for i in 4:
				var a := lerpf(PI * 1.2, PI * 1.8, i / 3.0)
				draw_line(c + Vector2(0, r * 0.6), c + Vector2(cos(a), sin(a)) * r * 0.7 + Vector2(0, r * 0.25), OUT, w * 0.6, true)
		"feather":
			var pts := PackedVector2Array()
			for i in 16:
				var t := i / 15.0
				var a := t * TAU
				pts.append(c + Vector2(sin(a) * r * 0.32, -cos(a) * r * 0.85).rotated(0.5))
			_poly(pts, _col(Color(1.0, 0.8, 0.3)), w)
			draw_line(c + Vector2(0, r * 0.95).rotated(0.5), c + Vector2(0, -r * 0.6).rotated(0.5), OUT, w * 0.8, true)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + i * PI / 5
				pts.append(c + Vector2(cos(a), sin(a)) * (r * 0.92 if i % 2 == 0 else r * 0.4))
			_poly(pts, _col(Color(1.0, 0.82, 0.3)), w)
		"beacon":
			_poly(PackedVector2Array([c + Vector2(-r * 0.4, r * 0.9), c + Vector2(r * 0.4, r * 0.9), c + Vector2(r * 0.25, -r * 0.35), c + Vector2(-r * 0.25, -r * 0.35)]), _col(Color(0.98, 0.96, 0.9)), w)
			_poly(PackedVector2Array([c + Vector2(-r * 0.32, -r * 0.35), c + Vector2(r * 0.32, -r * 0.35), c + Vector2(r * 0.25, -r * 0.65), c + Vector2(-r * 0.25, -r * 0.65)]), Color(1.0, 0.85, 0.4) if tint.a > 0.0 else Color(0.6, 0.66, 0.72), w)
			_poly(PackedVector2Array([c + Vector2(-r * 0.38, -r * 0.65), c + Vector2(r * 0.38, -r * 0.65), c + Vector2(0, -r * 0.98)]), _col(Color(0.9, 0.4, 0.35)), w)
		"letter":
			var rect := Rect2(c - Vector2(r * 0.85, r * 0.55), Vector2(r * 1.7, r * 1.1))
			draw_rect(rect, _col(Color(0.98, 0.95, 0.85)))
			draw_rect(rect, OUT, false, w)
			draw_polyline(PackedVector2Array([rect.position, c + Vector2(0, r * 0.1), rect.position + Vector2(rect.size.x, 0)]), OUT, w, true)
		"kitten":
			draw_circle(c + Vector2(0, r * 0.15), r * 0.6, _col(Color(1.0, 0.7, 0.4)))
			_poly(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.05), c + Vector2(-r * 0.5, -r * 0.8), c + Vector2(-r * 0.1, -r * 0.4)]), _col(Color(1.0, 0.7, 0.4)), w)
			_poly(PackedVector2Array([c + Vector2(r * 0.6, -r * 0.05), c + Vector2(r * 0.5, -r * 0.8), c + Vector2(r * 0.1, -r * 0.4)]), _col(Color(1.0, 0.7, 0.4)), w)
			draw_arc(c + Vector2(0, r * 0.15), r * 0.6, 0, TAU, 24, OUT, w, true)
			draw_circle(c + Vector2(-r * 0.22, r * 0.05), r * 0.08, OUT)
			draw_circle(c + Vector2(r * 0.22, r * 0.05), r * 0.08, OUT)
		"mushroom":
			draw_rect(Rect2(c + Vector2(-r * 0.18, -r * 0.1), Vector2(r * 0.36, r * 0.95)), Color(0.98, 0.95, 0.88))
			var pts := PackedVector2Array()
			for i in 13:
				var a := PI + i * PI / 12.0
				pts.append(c + Vector2(cos(a) * r * 0.85, sin(a) * r * 0.7))
			_poly(pts, _col(Color(0.45, 0.85, 1.0)), w)
		"spark":
			draw_circle(c, r * 0.9, Color(1.0, 0.6, 0.2, 0.3))
			var pts := PackedVector2Array()
			for i in 8:
				var a := -PI / 2 + i * PI / 4
				pts.append(c + Vector2(cos(a), sin(a)) * (r * 0.8 if i % 2 == 0 else r * 0.3))
			_poly(pts, _col(Color(1.0, 0.75, 0.3)), w)
		"chest":
			var rect := Rect2(c - Vector2(r * 0.85, r * 0.3), Vector2(r * 1.7, r * 1.0))
			draw_rect(rect, _col(Color(0.66, 0.4, 0.25)))
			draw_rect(rect, OUT, false, w)
			draw_rect(Rect2(c - Vector2(r * 0.85, r * 0.75), Vector2(r * 1.7, r * 0.45)), _col(Color(0.74, 0.46, 0.28)))
			draw_rect(Rect2(c - Vector2(r * 0.85, r * 0.75), Vector2(r * 1.7, r * 0.45)), OUT, false, w)
			draw_rect(Rect2(c - Vector2(r * 0.15, r * 0.45), Vector2(r * 0.3, r * 0.35)), Color(1.0, 0.82, 0.3))
		"clock":
			draw_circle(c, r * 0.85, _col(Color(0.98, 0.96, 0.9)))
			draw_arc(c, r * 0.85, 0, TAU, 28, OUT, w, true)
			draw_line(c, c + Vector2(0, -r * 0.55), OUT, w, true)
			draw_line(c, c + Vector2(r * 0.4, 0), OUT, w, true)
		"lock":
			draw_arc(c + Vector2(0, -r * 0.15), r * 0.4, PI, TAU, 16, OUT, w * 1.4, true)
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.15), Vector2(r * 1.2, r * 0.95)), _col(Color(1.0, 0.8, 0.3)))
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.15), Vector2(r * 1.2, r * 0.95)), OUT, false, w)
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, 0), c + Vector2(-r * 0.15, r * 0.5), c + Vector2(r * 0.7, -r * 0.55)]), _col(Color(0.33, 0.68, 0.36)), w * 2.0, true)
		"arrow":
			_poly(PackedVector2Array([c + Vector2(0, -r * 0.9), c + Vector2(r * 0.6, r * 0.75), c + Vector2(0, r * 0.4), c + Vector2(-r * 0.6, r * 0.75)]), _col(Color(1.0, 0.85, 0.3)), w)
		"person":
			draw_circle(c + Vector2(0, -r * 0.35), r * 0.32, _col(Color(0.98, 0.85, 0.7)))
			draw_arc(c + Vector2(0, -r * 0.35), r * 0.32, 0, TAU, 20, OUT, w, true)
			_poly(PackedVector2Array([c + Vector2(-r * 0.55, r * 0.85), c + Vector2(r * 0.55, r * 0.85), c + Vector2(r * 0.35, r * 0.05), c + Vector2(-r * 0.35, r * 0.05)]), _col(Color(0.4, 0.65, 0.9)), w)
		"quest":
			draw_circle(c, r * 0.85, _col(Color(1.0, 0.82, 0.3)))
			draw_arc(c, r * 0.85, 0, TAU, 24, OUT, w, true)
			draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.15), OUT, w * 1.4, true)
			draw_circle(c + Vector2(0, r * 0.45), w * 0.8, OUT)
		"paw":
			var col := _col(Color(0.85, 0.6, 0.35))
			draw_circle(c + Vector2(0, r * 0.3), r * 0.42, col)
			draw_arc(c + Vector2(0, r * 0.3), r * 0.42, 0, TAU, 20, OUT, w, true)
			for k in 4:
				var a := lerpf(-2.5, -0.64, k / 3.0)
				var tp := c + Vector2(0, r * 0.3) + Vector2(cos(a), sin(a)) * r * 0.72
				draw_circle(tp, r * 0.17, col)
				draw_arc(tp, r * 0.17, 0, TAU, 12, OUT, w * 0.8, true)
		"hat":
			var col := _col(Color(0.95, 0.85, 0.5))
			_poly(PackedVector2Array([c + Vector2(-r * 0.95, r * 0.35), c + Vector2(r * 0.95, r * 0.35), c + Vector2(r * 0.8, r * 0.55), c + Vector2(-r * 0.8, r * 0.55)]), col, w)
			_poly(PackedVector2Array([c + Vector2(-r * 0.5, r * 0.35), c + Vector2(-r * 0.4, -r * 0.45), c + Vector2(r * 0.4, -r * 0.45), c + Vector2(r * 0.5, r * 0.35)]), col, w)
			draw_rect(Rect2(c + Vector2(-r * 0.47, r * 0.08), Vector2(r * 0.94, r * 0.18)), Color(0.9, 0.35, 0.3))
		"shirt":
			var col := _col(Color(0.4, 0.65, 0.9))
			_poly(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.8), c + Vector2(-r * 0.95, -r * 0.4), c + Vector2(-r * 0.7, 0), c + Vector2(-r * 0.5, -r * 0.15),
				c + Vector2(-r * 0.5, r * 0.85), c + Vector2(r * 0.5, r * 0.85), c + Vector2(r * 0.5, -r * 0.15), c + Vector2(r * 0.7, 0),
				c + Vector2(r * 0.95, -r * 0.4), c + Vector2(r * 0.3, -r * 0.8), c + Vector2(0, -r * 0.55)]), col, w)
		"scarf":
			var col := _col(Color(0.95, 0.35, 0.3))
			_poly(PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.5), c + Vector2(r * 0.8, -r * 0.5), c + Vector2(r * 0.7, -r * 0.1), c + Vector2(-r * 0.7, -r * 0.1)]), col, w)
			_poly(PackedVector2Array([c + Vector2(r * 0.15, -r * 0.15), c + Vector2(r * 0.55, -r * 0.15), c + Vector2(r * 0.45, r * 0.9), c + Vector2(r * 0.1, r * 0.85)]), col.darkened(0.1), w)
		"parcel":
			var rect := Rect2(c - Vector2(r * 0.8, r * 0.6), Vector2(r * 1.6, r * 1.3))
			draw_rect(rect, _col(Color(0.8, 0.6, 0.4)))
			draw_rect(rect, OUT, false, w)
			draw_line(c + Vector2(0, -r * 0.6), c + Vector2(0, r * 0.7), Color(0.95, 0.9, 0.75), w * 1.6)
			draw_line(c + Vector2(-r * 0.8, -r * 0.05), c + Vector2(r * 0.8, -r * 0.05), Color(0.95, 0.9, 0.75), w * 1.6)
		"fish":
			var col := _col(Color(0.55, 0.72, 0.85))
			var pts := PackedVector2Array()
			for i in 16:
				var a := TAU * i / 16.0
				pts.append(c + Vector2(cos(a) * r * 0.62 - r * 0.1, sin(a) * r * 0.36))
			_poly(pts, col, w)
			_poly(PackedVector2Array([c + Vector2(r * 0.45, 0), c + Vector2(r * 0.95, -r * 0.4), c + Vector2(r * 0.95, r * 0.4)]), col.darkened(0.15), w)
			draw_circle(c + Vector2(-r * 0.42, -r * 0.06), r * 0.08, OUT)
		"dot":
			draw_circle(c, r * 0.6, _col(Color(1.0, 0.85, 0.3)))
			draw_arc(c, r * 0.6, 0, TAU, 20, OUT, w, true)
