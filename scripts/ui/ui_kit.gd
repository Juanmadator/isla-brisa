class_name UiKit
extends RefCounted
## Tema visual y constructores de widgets de la interfaz de Isla Brisa.

const FONT := preload("res://assets/fonts/Fredoka.ttf")

const C_PANEL := Color(1.0, 0.98, 0.93, 0.96)
const C_PANEL_DARK := Color(0.1, 0.16, 0.22, 0.72)
const C_BORDER := Color(0.22, 0.42, 0.52)
const C_TEXT := Color(0.16, 0.23, 0.3)
const C_MUTED := Color(0.42, 0.5, 0.56)
const C_ACCENT := Color(0.26, 0.64, 0.86)
const C_GOOD := Color(0.33, 0.68, 0.36)
const C_GOLD := Color(1.0, 0.8, 0.3)
const C_SHELL := Color(1.0, 0.7, 0.66)
const C_WHITE := Color(1, 1, 1)
const C_OUTLINE := Color(0.1, 0.18, 0.26)

static var _fonts := {}


static func clear_cache() -> void:
	_fonts.clear()


static func font(weight := 500) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	fv.base_font = FONT
	fv.variation_opentype = {"wght": weight}
	_fonts[weight] = fv
	return fv


static func box(bg: Color, radius := 18, border := 0, border_col := C_BORDER, pad := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_col
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 20
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_outline_color", "Label", C_OUTLINE)
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("panel", "PanelContainer", box(C_PANEL, 22, 3, C_BORDER, 22))
	t.set_stylebox("panel", "Panel", box(C_PANEL, 22, 3, C_BORDER, 22))
	var normal := box(Color(0.96, 0.95, 0.9), 16, 3, C_BORDER, 18)
	var hover := box(Color(1.0, 1.0, 0.97), 16, 3, C_ACCENT, 18)
	var pressed := box(Color(0.88, 0.92, 0.94), 16, 3, C_ACCENT, 18)
	var disabled := box(Color(0.88, 0.88, 0.86, 0.85), 16, 3, Color(0.68, 0.72, 0.74), 18)
	var focus := box(Color(0, 0, 0, 0), 16, 4, C_GOLD, 18)
	focus.shadow_size = 0
	for st in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled], ["focus", focus], ["hover_pressed", hover]]:
		t.set_stylebox(st[0], "Button", st[1])
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT.darkened(0.2))
	t.set_color("font_pressed_color", "Button", C_ACCENT.darkened(0.3))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.64, 0.66))
	t.set_color("font_focus_color", "Button", C_TEXT)
	t.set_font("font", "Button", font(600))
	t.set_font_size("font_size", "Button", 22)
	t.set_stylebox("slider", "HSlider", box(Color(0.8, 0.85, 0.86), 8, 0, C_BORDER, 4))
	t.set_stylebox("grabber_area", "HSlider", box(C_ACCENT, 8, 0, C_BORDER, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(C_ACCENT.lightened(0.2), 8, 0, C_BORDER, 4))
	t.set_color("font_color", "CheckButton", C_TEXT)
	for s in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(s, "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("scroll", "VScrollBar", box(Color(0.82, 0.86, 0.88, 0.6), 6, 0, C_BORDER, 3))
	t.set_stylebox("grabber", "VScrollBar", box(C_BORDER, 6, 0, C_BORDER, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(C_ACCENT, 6, 0, C_BORDER, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(C_ACCENT, 6, 0, C_BORDER, 3))
	t.set_stylebox("panel", "TooltipPanel", box(C_PANEL, 10, 2, C_BORDER, 10))
	t.set_color("font_color", "TooltipLabel", C_TEXT)
	return t


static func label(text: String, size := 20, color := C_TEXT, weight := 500, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != 500:
		l.add_theme_font_override("font", font(weight))
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", C_OUTLINE)
	return l


static func button(text: String, callback: Callable, size := 22, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(func() -> void:
		Audio.play("ui_click", 0.05)
		callback.call())
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.play("ui_hover", 0.1))
	b.focus_mode = Control.FOCUS_ALL
	return b


static func accent_button(text: String, callback: Callable, size := 24, min_w := 0.0) -> Button:
	var b := button(text, callback, size, min_w)
	var dark := Color(0.14, 0.42, 0.6)
	b.add_theme_stylebox_override("normal", box(C_ACCENT, 16, 3, dark, 18))
	b.add_theme_stylebox_override("hover", box(C_ACCENT.lightened(0.12), 16, 3, dark, 18))
	b.add_theme_stylebox_override("pressed", box(C_ACCENT.darkened(0.12), 16, 3, dark, 18))
	b.add_theme_stylebox_override("disabled", box(Color(0.7, 0.76, 0.8, 0.85), 16, 3, Color(0.55, 0.6, 0.64), 18))
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.92, 0.97, 1))
	b.add_theme_color_override("font_disabled_color", Color(0.95, 0.95, 0.95))
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("font_outline_color", dark)
	return b


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(bg := C_PANEL, border_col := C_BORDER, pad := 22, radius := 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, radius, 3, border_col, pad))
	return p


static func dark_panel(pad := 14) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(C_PANEL_DARK, 16, 0, C_BORDER, pad)
	sb.shadow_size = 0
	p.add_theme_stylebox_override("panel", sb)
	return p


static func spacer(h := 0.0, w := 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c


static func expand_spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Coloca `c` respecto a un punto de anclaje (0..1 en cada eje) con un desplazamiento y
## un tamaño. Crece hacia el lado contrario al anclaje.
static func place(c: Control, anchor: Vector2, offset: Vector2, sz := Vector2.ZERO) -> Control:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + sz.x
	c.offset_bottom = offset.y + sz.y
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH if anchor.x == 0.5 else (Control.GROW_DIRECTION_BEGIN if anchor.x == 1.0 else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BOTH if anchor.y == 0.5 else (Control.GROW_DIRECTION_BEGIN if anchor.y == 1.0 else Control.GROW_DIRECTION_END)
	return c


## Franja horizontal de lado a lado (para centrar contenido de ancho variable).
static func band(c: Control, anchor_y: float, top: float, height: float) -> Control:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = anchor_y
	c.anchor_bottom = anchor_y
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.offset_top = top
	c.offset_bottom = top + height
	return c


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func center(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	full_rect(cc)
	cc.add_child(c)
	return cc


static func icon(kind: String, size := 26.0, tint := Color(0, 0, 0, 0)) -> Icon:
	var s := Icon.new()
	s.kind = kind
	s.tint = tint
	s.custom_minimum_size = Vector2(size, size)
	return s


static func pop_in(c: Control, delay := 0.0) -> void:
	c.pivot_offset = c.size * 0.5
	c.modulate.a = 0.0
	c.scale = Vector2(0.92, 0.92)
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.25).set_delay(delay)
	tw.tween_property(c, "scale", Vector2.ONE, 0.35).set_delay(delay)
