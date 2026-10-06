class_name DialogueBox
extends Control
## Caja de diálogo con nombre, texto que se escribe letra a letra y "blips" de voz.

signal finished
## Empieza una frase de `who` (para que hable su personaje).
signal line_started(who: String)

var lines: Array = []
var index := 0
var on_done := Callable()
var name_tag: PanelContainer
var name_label: Label
var text_label: RichTextLabel
var arrow: Label
var _chars := 0.0
var _voice_pitch := 1.0
var _blip_t := 0.0
var _arrow_t := 0.0

const VOICES := {"Tomeu": 0.75, "Rosa": 1.05, "Nerea": 1.25, "Bruno": 0.9, "Pía": 1.5, "Marisol": 1.15,
	"Ulises": 0.7, "Gema": 1.1, "Olga": 1.0, "Tito": 1.45, "Lía": 1.3}


func build() -> void:
	UiKit.place(self, Vector2(0.5, 1), Vector2(-410, -210), Vector2(820, 170))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := UiKit.panel(UiKit.C_PANEL, UiKit.C_BORDER, 26, 26)
	panel.custom_minimum_size = Vector2(820, 150)
	panel.position = Vector2(0, 20)
	add_child(panel)
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.custom_minimum_size = Vector2(760, 100)
	text_label.add_theme_font_size_override("normal_font_size", 24)
	text_label.add_theme_color_override("default_color", UiKit.C_TEXT)
	text_label.add_theme_font_override("normal_font", UiKit.font(500))
	panel.add_child(text_label)
	name_tag = PanelContainer.new()
	name_tag.add_theme_stylebox_override("panel", UiKit.box(UiKit.C_ACCENT, 14, 3, UiKit.C_BORDER, 16))
	name_tag.position = Vector2(30, 0)
	name_label = UiKit.label("", 22, UiKit.C_WHITE, 700, 5)
	name_tag.add_child(name_label)
	add_child(name_tag)
	arrow = UiKit.label("▼", 22, UiKit.C_ACCENT, 700)
	arrow.position = Vector2(780, 136)
	add_child(arrow)
	visible = false


func open(new_lines: Array, done: Callable) -> void:
	lines = new_lines
	index = 0
	on_done = done
	visible = true
	if lines.is_empty():
		close()
		return
	_show_line()
	UiKit.pop_in(self)


func _show_line() -> void:
	var l: Array = lines[index]
	var who: String = l[0]
	name_tag.visible = who != ""
	name_label.text = who
	text_label.text = l[1]
	text_label.visible_characters = 0
	_chars = 0.0
	_voice_pitch = VOICES.get(who.split(" ")[-1], VOICES.get(who, 1.0))
	if who.begins_with("Alcaldesa"):
		_voice_pitch = VOICES["Rosa"]
	if who.begins_with("Abuela"):
		_voice_pitch = VOICES["Olga"]
	line_started.emit(who)


func is_typing() -> bool:
	return text_label.visible_characters >= 0 and text_label.visible_characters < text_label.get_total_character_count()


func advance() -> void:
	if not visible:
		return
	if is_typing():
		text_label.visible_characters = -1
		return
	index += 1
	if index >= lines.size():
		close()
	else:
		Audio.play("ui_click", 0.05, -6.0)
		_show_line()


func close() -> void:
	visible = false
	var cb := on_done
	on_done = Callable()
	finished.emit()
	if cb.is_valid():
		cb.call()


func _process(delta: float) -> void:
	if not visible:
		return
	_arrow_t += delta
	arrow.visible = not is_typing()
	arrow.position.y = 136 + sin(_arrow_t * 6.0) * 3.0
	if is_typing():
		_chars += delta * 52.0
		var n := int(_chars)
		if n != text_label.visible_characters:
			text_label.visible_characters = n
			_blip_t -= delta
			if _blip_t <= 0.0 and name_tag.visible:
				_blip_t = 0.07
				Audio.play("talk", 0.08, 0.0, _voice_pitch)
