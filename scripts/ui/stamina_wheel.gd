class_name StaminaWheel
extends Control
## Círculo de aguante por segmentos (uno por punto de aguante), estilo BotW.
## Aparece al gastar y se oculta cuando está lleno un rato.

var value := 3.0
var max_value := 3.0
var exhausted := false

var _visible_t := 0.0
var _alpha := 0.0
var _blink := 0.0
var _last := 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(70, 70)


func tick(delta: float) -> void:
	_blink += delta
	if value < max_value - 0.001 or exhausted:
		_visible_t = 1.2
	else:
		_visible_t -= delta
	var want := 1.0 if _visible_t > 0.0 else 0.0
	_alpha = move_toward(_alpha, want, delta * 4.0)
	if value < _last - 0.0001 and value < max_value * 0.25 and int(_blink * 2.0) % 2 == 0:
		pass
	_last = value
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01:
		return
	var c := Vector2(0, 0)
	var rings := 1 if max_value <= 8.0 else 2
	var per_ring := ceili(max_value / rings)
	var low := value < minf(1.0, max_value * 0.3)
	var full_col := Color(0.45, 0.9, 0.4)
	if exhausted:
		full_col = Color(1.0, 0.45, 0.35)
	elif low:
		full_col = Color(1.0, 0.85, 0.3) if fmod(_blink, 0.5) < 0.25 else Color(1.0, 0.5, 0.3)
	full_col.a = _alpha
	var back := Color(0.05, 0.1, 0.12, 0.55 * _alpha)
	var outline := Color(0.05, 0.08, 0.1, 0.8 * _alpha)
	for ring in rings:
		var r := 24.0 - ring * 10.0
		var w := 8.0 if ring == 0 else 6.5
		var count := per_ring if ring == 0 else int(max_value) - per_ring
		if count <= 0:
			continue
		var gap := 0.06 if count > 1 else 0.0
		for i in count:
			var seg_index := i + ring * per_ring
			var a0 := -PI / 2 + TAU * i / count + gap * 0.5
			var a1 := -PI / 2 + TAU * (i + 1) / count - gap * 0.5
			draw_arc(c, r, a0, a1, 16, outline, w + 3.0, true)
			draw_arc(c, r, a0, a1, 16, back, w, true)
			var fill := clampf(value - seg_index, 0.0, 1.0)
			if fill > 0.0:
				draw_arc(c, r, a0, lerpf(a0, a1, fill), 16, full_col, w, true)
