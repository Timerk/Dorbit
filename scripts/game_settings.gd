class_name GameSettings
extends RefCounted
## Device-local controls and display preferences. Audio retains its existing config file.

const PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY := 0.003
const ACTIONS := {
	"forward": "Move forward", "backward": "Move backward",
	"strafe_left": "Strafe left", "strafe_right": "Strafe right",
	"move_down": "Move down", "move_up": "Move up", "boost": "Boost",
	"steer": "Hold to steer", "select_target": "Select under cursor",
	"cycle_target": "Cycle target", "fire": "Toggle automatic fire", "repair": "Repair",
}
# Negative codes denote mouse buttons; positive codes denote physical keys.
const DEFAULT_BINDINGS := {
	"forward": KEY_W, "backward": KEY_S, "strafe_left": KEY_A,
	"strafe_right": KEY_D, "move_down": KEY_Q, "move_up": KEY_E,
	"boost": KEY_SHIFT, "steer": -MOUSE_BUTTON_RIGHT, "select_target": -MOUSE_BUTTON_LEFT,
	"cycle_target": KEY_TAB, "fire": KEY_SPACE, "repair": KEY_R,
}
const SHORTCUTS := {
	"pause_game": KEY_ESCAPE, "fullscreen": KEY_F11, "performance": KEY_F3,
	"quality": KEY_F4, "quit_game": KEY_F10, "resolution_down": KEY_F5,
	"resolution_up": KEY_F6, "multiplayer_menu": KEY_F7,
}

var sensitivity: float = DEFAULT_SENSITIVITY
var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()
var fullscreen: bool = false
var low_quality: bool = false
var show_performance: bool = false
var resolution := Vector2i(1440, 900)
var save_failed: bool = false


func load_from(path: String = PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	var value: Variant = config.get_value("controls", "sensitivity", sensitivity)
	if (value is float or value is int) and is_finite(float(value)):
		sensitivity = clampf(float(value), 0.0003, 0.009)
	for action: String in ACTIONS:
		value = config.get_value("bindings", action, bindings[action])
		if value is int and valid_binding(value):
			rebind(action, value)
	for setting in ["fullscreen", "low_quality", "show_performance"]:
		value = config.get_value("graphics", setting, get(setting))
		if value is bool:
			set(setting, value)
	value = config.get_value("graphics", "resolution", resolution)
	if value is Vector2i and value.x >= 960 and value.y >= 600:
		resolution = value


func save(path: String = PATH) -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "sensitivity", sensitivity)
	for action: String in ACTIONS:
		config.set_value("bindings", action, bindings[action])
	for setting in ["fullscreen", "low_quality", "show_performance", "resolution"]:
		config.set_value("graphics", setting, get(setting))
	save_failed = config.save(path) != OK


static func valid_binding(code: int) -> bool:
	if code < 0:
		return -code in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
	return code != KEY_NONE and code not in SHORTCUTS.values() and not OS.get_keycode_string(code).is_empty()


# Swapping prevents duplicate actions and keeps every action bound.
func rebind(action: String, code: int) -> void:
	if not ACTIONS.has(action) or not valid_binding(code):
		return
	var previous: int = bindings[action]
	for other: String in ACTIONS:
		if other != action and bindings[other] == code:
			bindings[other] = previous
			install_binding(other, previous)
	bindings[action] = code
	install_binding(action, code)


func reset_controls() -> void:
	sensitivity = DEFAULT_SENSITIVITY
	bindings = DEFAULT_BINDINGS.duplicate()
	configure_input()


func configure_input() -> void:
	for action: String in bindings:
		install_binding(action, bindings[action])
	for action: String in SHORTCUTS:
		install_binding(action, SHORTCUTS[action])


static func install_binding(action: String, code: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	Input.action_release(action)
	InputMap.action_erase_events(action)
	if code < 0:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = -code as MouseButton
		InputMap.action_add_event(action, mouse)
	else:
		var key := InputEventKey.new()
		key.physical_keycode = code as Key
		InputMap.action_add_event(action, key)
		# Remote/accessibility input can supply only a logical key.
		var logical := InputEventKey.new()
		logical.keycode = code as Key
		InputMap.action_add_event(action, logical)


static func binding_text(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "?"
	var event := events[0]
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
	return event.as_text_physical_keycode() if event is InputEventKey else event.as_text()
