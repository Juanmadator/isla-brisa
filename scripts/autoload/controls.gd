extends Node
## Acciones de entrada (teclado, ratón y mando) registradas al arrancar.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_E, KEY_ENTER],
	"drop": [KEY_Q, KEY_CTRL],
	"pause": [KEY_ESCAPE, KEY_P],
	"map": [KEY_M, KEY_TAB],
	"quests": [KEY_J],
	"hint": [KEY_H],
}
const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"sprint": [JOY_BUTTON_B],
	"interact": [JOY_BUTTON_X],
	"drop": [JOY_BUTTON_Y],
	"pause": [JOY_BUTTON_START],
	"map": [JOY_BUTTON_BACK],
}
const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"cam_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"cam_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"cam_left": [JOY_AXIS_RIGHT_X, -1.0],
	"cam_right": [JOY_AXIS_RIGHT_X, 1.0],
}

const LABELS := {
	"interact": "E",
	"jump": "Espacio",
	"sprint": "Shift",
	"drop": "Q",
	"map": "M",
	"pause": "Esc",
}


func _enter_tree() -> void:
	for action in KEYS:
		_ensure(action)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in PAD_BUTTONS:
		_ensure(action)
		for b in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			InputMap.action_add_event(action, ev)
	for action in PAD_AXES:
		_ensure(action)
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func label(action: String) -> String:
	return LABELS.get(action, action)
