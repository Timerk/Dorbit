class_name GameSettings
extends RefCounted
## Device-local controls and display preferences. Audio retains its existing config file.

const PATH := "user://settings.cfg"
const RENDERER_PATH := "user://graphics-renderer.cfg"
const ANISOTROPY_SETTING := "rendering/textures/default_filters/anisotropic_filtering_level"
const DEFAULT_SENSITIVITY := 0.003
# Only supported menu values are accepted from device-local profiles.
const GRAPHICS_LEVELS := {
	"render_scale": [1.0, 0.85, 0.75, 0.5],
	"msaa_3d": [0, 1, 2, 3],
	"anisotropic_filtering": [0, 1, 2, 3, 4],
	"shadow_quality": [0, 1, 2, 3],
	"effects_quality": [0, 1, 2],
}
const GRAPHICS_BOOLEANS := ["fullscreen", "vsync", "show_performance", "bloom", "ssao"]
const ACTIONS := {
	"forward": "Move forward", "backward": "Move backward",
	"strafe_left": "Strafe left", "strafe_right": "Strafe right",
	"move_down": "Move down", "move_up": "Move up", "boost": "Boost",
	"steer": "Hold to steer", "select_target": "Select under cursor",
	"cycle_target": "Cycle target", "fire": "Toggle automatic fire", "repair": "Repair",
	"autopilot": "Toggle autopilot",
	"rocket": "Fire single rocket", "launcher": "Load / fire Hellstorm",
}
# Negative codes denote mouse buttons; positive codes denote physical keys.
const DEFAULT_BINDINGS := {
	"forward": KEY_W, "backward": KEY_S, "strafe_left": KEY_A,
	"strafe_right": KEY_D, "move_down": KEY_Q, "move_up": KEY_E,
	"boost": KEY_SHIFT, "steer": -MOUSE_BUTTON_RIGHT, "select_target": -MOUSE_BUTTON_LEFT,
	"cycle_target": KEY_TAB, "fire": KEY_SPACE, "repair": KEY_R,
	"autopilot": KEY_P,
	"rocket": KEY_F, "launcher": KEY_G,
}
const SHORTCUTS := {
	"pause_game": KEY_ESCAPE, "fullscreen": KEY_F11, "performance": KEY_F3,
	"quality": KEY_F4, "quit_game": KEY_F10, "resolution_down": KEY_F5,
	"resolution_up": KEY_F6, "multiplayer_menu": KEY_F7,
	"contracts": KEY_C, "station_shop": KEY_B, "ship_equipment": KEY_I,
	"sector_map": KEY_M,
	"ammo_x1": KEY_1, "ammo_x2": KEY_2, "ammo_x3": KEY_3, "ammo_x4": KEY_4,
}

var sensitivity: float = DEFAULT_SENSITIVITY
var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()
var fullscreen: bool = false
var vsync: bool = false
var msaa_3d: int = 2
# Retain the F4 on/off shortcut and migrate profiles from the original boolean.
var low_quality: bool:
	get: return msaa_3d == 0
	set(value): msaa_3d = 0 if value else 2
var show_performance: bool = false
var resolution := Vector2i(1440, 900)
var render_scale: float = 1.0
var anisotropic_filtering: int = 0
var bloom: bool = false
var ssao: bool = false
var shadow_quality: int = 0
var effects_quality: int = 2
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
	for setting in GRAPHICS_BOOLEANS:
		value = config.get_value("graphics", setting, get(setting))
		if value is bool:
			set(setting, value)
	value = config.get_value("graphics", "low_quality", false)
	if value is bool:
		low_quality = value
	for setting: String in GRAPHICS_LEVELS:
		value = config.get_value("graphics", setting, get(setting))
		if setting == "render_scale":
			if (value is float or value is int) and float(value) in GRAPHICS_LEVELS[setting]:
				render_scale = float(value)
		elif value is int and value in GRAPHICS_LEVELS[setting]:
			set(setting, value)
	value = config.get_value("graphics", "resolution", resolution)
	if value is Vector2i and value.x >= 960 and value.y >= 600:
		resolution = value


func save(path: String = PATH) -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "sensitivity", sensitivity)
	for action: String in ACTIONS:
		config.set_value("bindings", action, bindings[action])
	for setting in GRAPHICS_BOOLEANS + GRAPHICS_LEVELS.keys() + ["resolution"]:
		config.set_value("graphics", setting, get(setting))
	save_failed = config.save(path) != OK
	if path == PATH:
		# GLES3 captures the hardware sampler maximum before scripts run. The
		# user override is loaded by Godot before renderer initialization next time.
		var renderer := ConfigFile.new()
		renderer.set_value("rendering", "textures/default_filters/anisotropic_filtering_level", anisotropic_filtering if anisotropic_filtering > 0 else 4)
		save_failed = renderer.save(RENDERER_PATH) != OK or save_failed


static func startup_filtering_level() -> int:
	return int(ProjectSettings.get_setting(ANISOTROPY_SETTING, 4))


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
