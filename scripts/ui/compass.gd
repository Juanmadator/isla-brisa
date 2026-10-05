class_name Compass
extends Control
## Brújula horizontal: puntos cardinales y marcadores (encargo, faros, plumas).

var cam_yaw := 0.0
var player_pos := Vector3.ZERO
var markers: Array = []

const FOV := PI * 0.9


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _x_for(world_yaw: float) -> float:
	var d := angle_difference(cam_yaw, world_yaw)
	return size.x * 0.5 - d / FOV * size.x


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, h * 0.25, w, h * 0.5), Color(0.05, 0.1, 0.14, 0.5))
	draw_line(Vector2(0, h * 0.25), Vector2(w, h * 0.25), Color(1, 1, 1, 0.25), 1.0)
	draw_line(Vector2(0, h * 0.75), Vector2(w, h * 0.75), Color(1, 1, 1, 0.25), 1.0)
	var font := UiKit.font(700)
	# Rumbo hacia el norte (-Z) = yaw 0
	var labels := {0.0: "N", PI * 0.5: "O", PI: "S", -PI * 0.5: "E"}
	for i in 16:
		var yaw := TAU * i / 16.0
		var x := _x_for(yaw)
		if x < 0 or x > w:
			continue
		if i % 4 == 0:
			continue
		var tick := 4.0
		draw_line(Vector2(x, h * 0.5 - tick), Vector2(x, h * 0.5 + tick), Color(1, 1, 1, 0.6), 2.0)
	for yaw in labels:
		var x := _x_for(yaw)
		if x < 10 or x > w - 10:
			continue
		var txt: String = labels[yaw]
		var col := Color(1.0, 0.5, 0.45) if txt == "N" else Color(1, 1, 1)
		draw_string_outline(font, Vector2(x - 8, h * 0.5 + 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color(0.05, 0.1, 0.14))
		draw_string(font, Vector2(x - 8, h * 0.5 + 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
	for m in markers:
		var p: Vector3 = m["pos"]
		var to := p - player_pos
		if Vector2(to.x, to.z).length() < 4.0:
			continue
		var yaw := atan2(-to.x, -to.z)
		var x := clampf(_x_for(yaw), 8.0, w - 8.0)
		var col: Color = m["color"]
		match m["kind"]:
			"quest":
				var pts := PackedVector2Array([Vector2(x, h - 2), Vector2(x - 9, h - 18), Vector2(x + 9, h - 18)])
				draw_colored_polygon(pts, col)
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.1, 0.1, 0.1), 2.0, true)
				var dist := Vector2(to.x, to.z).length()
				var label := "%d m" % int(dist)
				if float(m.get("radius", 0.0)) > 0.0:
					label = "zona · %d m" % int(maxf(dist - float(m["radius"]), 0.0)) if dist > float(m["radius"]) else "¡Por aquí!"
				draw_string_outline(font, Vector2(x - 40, h + 16), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 15, 4, Color(0.05, 0.1, 0.14))
				draw_string(font, Vector2(x - 40, h + 16), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 15, col)
			"beacon":
				var dm := PackedVector2Array([Vector2(x, 2), Vector2(x + 5, 8), Vector2(x, 14), Vector2(x - 5, 8)])
				draw_colored_polygon(dm, col)
				draw_polyline(PackedVector2Array([dm[0], dm[1], dm[2], dm[3], dm[0]]), Color(0.05, 0.1, 0.14), 1.5, true)
			"feather":
				draw_circle(Vector2(x, 9), 5.0, col)
