class_name SettingsMenu
extends Control
## Pause navigation and settings use normal Controls for mouse and keyboard access.

var sector: Sector
var panel: PanelContainer
var pause_panel: PanelContainer
var tabs: TabContainer
var sensitivity: HSlider
var sensitivity_label: Label
var master: HSlider
var effects: HSlider
var master_label: Label
var effects_label: Label
var mute: CheckButton
var fullscreen: CheckButton
var vsync: CheckButton
var quality: OptionButton
var performance: CheckButton
var resolution: OptionButton
var resolutions: Array[Vector2i] = []
var binding_buttons: Dictionary[String, Button] = {}
var binding_help: Label
var save_status: Label
var back_button: Button
var resume_button: Button
var reset_button: Button
var pending_action: String = ""
var from_connection: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = menu_theme()
	pause_panel = make_panel(Vector2(540, 340))
	var pause_rows := content(pause_panel)
	label(pause_rows, "DORBIT / PILOT CONSOLE", 11)
	label(pause_rows, "FLIGHT MENU", 28)
	resume_button = button(pause_rows, "Resume flight", func(): sector.set_paused(false))
	button(pause_rows, "Settings", func(): open())
	button(pause_rows, "Multiplayer session", sector.session.open_menu)
	button(pause_rows, "Quit to desktop", func(): get_tree().quit())
	label(pause_rows, "In multiplayer, the world keeps running while menus are open.", 14)
	pause_panel.hide()
	panel = make_panel(Vector2(880, 680))
	var rows := content(panel)
	label(rows, "PILOT CONSOLE / DEVICE PREFERENCES", 11)
	label(rows, "SETTINGS", 28)
	label(rows, "Changes apply immediately and are saved on this device.", 14)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(tabs)
	build_controls(page("Controls"))
	build_audio(page("Audio"))
	build_graphics(page("Graphics"))
	var footer := HBoxContainer.new()
	rows.add_child(footer)
	save_status = label(footer, "", 14)
	save_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back_button = button(footer, "Back  /  Esc", close)
	back_button.custom_minimum_size.x = 180
	panel.hide()
	get_viewport().size_changed.connect(func():
		layout()
		if panel.visible:
			sync_resolution())
	layout()


# Match the navy/slate surfaces and cyan interaction states in the station menus.
static func style(background: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = background
	result.border_color = border
	result.set_border_width_all(width)
	result.set_corner_radius_all(3)
	result.set_content_margin_all(8)
	return result


static func menu_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	for type: String in ["Label", "Button", "OptionButton", "CheckButton", "PopupMenu", "TabContainer", "TabBar"]:
		result.set_color("font_color", type, FlightHud.INK)
		result.set_color("font_hover_color", type, FlightHud.INK)
		result.set_color("font_pressed_color", type, FlightHud.CYAN)
		result.set_color("font_focus_color", type, FlightHud.CYAN)
		result.set_color("font_disabled_color", type, FlightHud.MUTED)
	for type: String in ["Button", "OptionButton", "CheckButton"]:
		result.set_stylebox("normal", type, style(Color("192838"), Color("3c5163")))
		result.set_stylebox("hover", type, style(Color("233c50"), FlightHud.CYAN))
		result.set_stylebox("pressed", type, style(Color("164358"), FlightHud.CYAN, 2))
		result.set_stylebox("hover_pressed", type, style(Color("164358"), FlightHud.CYAN, 2))
		result.set_stylebox("focus", type, style(Color(0, 0, 0, 0), FlightHud.CYAN))
		result.set_stylebox("disabled", type, style(Color("111e2a"), Color("293b4b")))
	for type: String in ["TabContainer", "TabBar"]:
		result.set_stylebox("tab_unselected", type, style(Color("192838"), Color("3c5163")))
		result.set_stylebox("tab_hovered", type, style(Color("233c50"), FlightHud.CYAN))
		result.set_stylebox("tab_selected", type, style(Color("164358"), FlightHud.CYAN))
		result.set_stylebox("tab_focus", type, style(Color(0, 0, 0, 0), FlightHud.CYAN))
		result.set_color("font_selected_color", type, FlightHud.CYAN)
		result.set_color("font_unselected_color", type, FlightHud.MUTED)
		result.set_constant("side_margin", type, 18)
	result.set_stylebox("panel", "TabContainer", style(Color("09131f"), Color("2d4356")))
	result.set_stylebox("panel", "PopupMenu", style(Color("111c29"), Color("526779")))
	result.set_stylebox("hover", "PopupMenu", style(Color("233c50"), FlightHud.CYAN))
	var track := style(Color("192838"), Color("3c5163"))
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	result.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("164358")
	fill.border_color = FlightHud.CYAN
	result.set_stylebox("grabber_area", "HSlider", fill)
	result.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return result


func layout() -> void:
	for entry: PanelContainer in [panel, pause_panel]:
		var preferred := Vector2(880, 680) if entry == panel else Vector2(540, 340)
		var dimensions := preferred.min(get_viewport_rect().size - Vector2(32, 32))
		entry.offset_left = -dimensions.x / 2
		entry.offset_right = dimensions.x / 2
		entry.offset_top = -dimensions.y / 2
		entry.offset_bottom = dimensions.y / 2


func make_panel(dimensions: Vector2) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", style(Color("111c29"), Color("526779"), 2))
	add_child(result)
	result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result.offset_left = -dimensions.x / 2
	result.offset_right = dimensions.x / 2
	result.offset_top = -dimensions.y / 2
	result.offset_bottom = dimensions.y / 2
	return result


func content(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	parent.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)
	return rows


func page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var rows := content(scroll)
	rows.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rows


func label(parent: Node, text: String, font_size: int = 16) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", FlightHud.CYAN if font_size == 11 else (FlightHud.MUTED if font_size == 14 else FlightHud.INK))
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result


func button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 36
	result.pressed.connect(action)
	parent.add_child(result)
	return result


func volume_slider(parent: Node) -> HSlider:
	var result := HSlider.new()
	result.max_value = 100.0
	result.step = 1.0
	result.custom_minimum_size.y = 30
	parent.add_child(result)
	return result


func checkbox(parent: Node, title: String, action: Callable) -> CheckButton:
	var result := CheckButton.new()
	result.text = title
	result.toggled.connect(action)
	parent.add_child(result)
	return result


func build_controls(rows: VBoxContainer) -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	rows.add_child(columns)
	rows = section(columns, "FLIGHT RESPONSE")
	rows.get_parent().get_parent().custom_minimum_size.x = 250
	sensitivity_label = label(rows, "Mouse sensitivity")
	sensitivity = HSlider.new()
	sensitivity.min_value = 0.1
	sensitivity.max_value = 3.0
	sensitivity.step = 0.05
	sensitivity.custom_minimum_size.y = 30
	rows.add_child(sensitivity)
	sensitivity.value_changed.connect(func(value: float):
		sector.settings.sensitivity = value * GameSettings.DEFAULT_SENSITIVITY
		sector.player.mouse_sensitivity = sector.settings.sensitivity
		sensitivity_label.text = "Mouse sensitivity  /  %.2fx" % value
		sector.settings.save())
	binding_help = label(rows, "Select a binding, then press a key or mouse button.\nAn occupied binding swaps actions. Esc cancels.", 14)
	rows = section(columns, "FLIGHT & COMBAT BINDINGS")
	rows.get_parent().get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for action: String in GameSettings.ACTIONS:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var caption := label(row, GameSettings.ACTIONS[action])
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var binding := button(row, "", func(): begin_binding(action))
		binding.custom_minimum_size.x = 160
		binding_buttons[action] = binding
	reset_button = button(rows, "Restore default controls", func():
		sector.settings.reset_controls()
		sector.player.mouse_sensitivity = sector.settings.sensitivity
		sector.settings.save()
		sync_controls())
	label(rows, "Menu shortcuts stay fixed: B, I, C, Esc, F3 to F7, F10 and F11.", 14)


func build_audio(rows: VBoxContainer) -> void:
	rows = section(rows, "SOUND LEVELS")
	master_label = label(rows, "Master volume")
	master = volume_slider(rows)
	effects_label = label(rows, "Effects volume")
	effects = volume_slider(rows)
	master.value_changed.connect(func(value: float):
		sector.audio.master = value / 100.0
		sector.audio.save_preferences())
	effects.value_changed.connect(func(value: float):
		sector.audio.effects = value / 100.0
		sector.audio.save_preferences())
	mute = checkbox(rows, "Mute all sound", func(value: bool):
		sector.audio.muted = value
		sector.audio.save_preferences())
	button(rows, "Test sound", func(): sector.audio.play("purchase", sector.player.camera.global_position))


func build_graphics(rows: VBoxContainer) -> void:
	rows = section(rows, "DISPLAY & PERFORMANCE")
	fullscreen = checkbox(rows, "Fullscreen", func(value: bool):
		sector.settings.fullscreen = value
		sector.apply_graphics(false)
		sector.settings.save())
	vsync = checkbox(rows, "VSync", func(value: bool):
		sector.settings.vsync = value
		sector.apply_graphics(false)
		sector.settings.save())
	label(rows, "Sync frames to your screen's refresh rate to reduce tearing. Off by default.", 14)
	label(rows, "Antialiasing")
	quality = OptionButton.new()
	quality.add_item("Off")
	quality.add_item("4x MSAA")
	rows.add_child(quality)
	quality.item_selected.connect(func(index: int):
		sector.settings.low_quality = index == 0
		sector.apply_graphics(false)
		sector.settings.save())
	performance = checkbox(rows, "Show performance overlay", func(value: bool):
		sector.settings.show_performance = value
		sector.apply_graphics(false)
		sector.settings.save())
	label(rows, "Window resolution")
	resolution = OptionButton.new()
	rows.add_child(resolution)
	resolution.item_selected.connect(func(index: int):
		sector.settings.resolution = resolutions[index]
		sector.settings.fullscreen = false
		sector.apply_graphics()
		sector.settings.save()
		fullscreen.set_pressed_no_signal(false))
	label(rows, "Selecting a resolution switches to windowed mode.\nFullscreen uses your desktop resolution.", 14)


func section(parent: Node, title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", style(Color("091522"), Color("263e53")))
	parent.add_child(card)
	var rows := content(card)
	rows.add_theme_constant_override("separation", 8)
	for side in ["left", "right", "top", "bottom"]:
		rows.get_parent().add_theme_constant_override("margin_" + side, 12)
	label(rows, title, 11)
	return rows


func open(connection: bool = false) -> void:
	from_connection = connection
	sector.set_paused(true)
	sector.shop.hide()
	sector.equipment_menu.hide()
	sector.hud.contract_panel.hide()
	sector.session.menu.hide()
	pause_panel.hide()
	panel.show()
	sync_controls()
	back_button.grab_focus()


func close() -> void:
	dismiss()
	if from_connection:
		sector.session.open_menu()
	else:
		pause_panel.show()
		resume_button.grab_focus()


func dismiss() -> void:
	pending_action = ""
	panel.hide()
	pause_panel.hide()


func sync_controls() -> void:
	sensitivity.set_value_no_signal(sector.settings.sensitivity / GameSettings.DEFAULT_SENSITIVITY)
	sensitivity_label.text = "Mouse sensitivity  /  %.2fx" % sensitivity.value
	for action: String in binding_buttons:
		binding_buttons[action].text = GameSettings.binding_text(action)
		binding_buttons[action].remove_theme_stylebox_override("normal")
	master.set_value_no_signal(sector.audio.master * 100.0)
	effects.set_value_no_signal(sector.audio.effects * 100.0)
	mute.set_pressed_no_signal(sector.audio.muted)
	fullscreen.set_pressed_no_signal(sector.settings.fullscreen)
	vsync.set_pressed_no_signal(sector.settings.vsync)
	quality.select(0 if sector.low_quality else 1)
	performance.set_pressed_no_signal(sector.show_performance)
	sync_resolution()
	binding_help.text = "Select a binding, then press a key or mouse button.\nAn occupied binding swaps actions. Esc cancels."


func sync_resolution() -> void:
	resolutions = sector.available_resolutions()
	var current := DisplayServer.window_get_size()
	if current not in resolutions:
		resolutions.append(current)
	resolution.clear()
	for pixels in resolutions:
		resolution.add_item("%d x %d" % [pixels.x, pixels.y])
	resolution.select(resolutions.find(current))


func begin_binding(action: String) -> void:
	pending_action = action
	binding_buttons[action].text = "Press a key..."
	binding_buttons[action].add_theme_stylebox_override("normal", style(Color("164358"), FlightHud.CYAN, 2))
	binding_help.text = "Binding: %s\nPress a key or mouse button. Esc cancels." % GameSettings.ACTIONS[action]


func _input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if not pending_action.is_empty():
		get_viewport().set_input_as_handled()
		if event.is_action_pressed("pause_game"):
			pending_action = ""
			sync_controls()
		elif event.is_pressed() and not event.is_echo():
			var code := 0
			if event is InputEventKey:
				code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			elif event is InputEventMouseButton:
				code = -event.button_index
			if not GameSettings.valid_binding(code):
				binding_help.text = "That input is reserved or unsupported.\nChoose another key or mouse button. Esc cancels."
				return
			sector.settings.rebind(pending_action, code)
			sector.settings.save()
			pending_action = ""
			sync_controls()
	elif event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	var show_pause := sector.paused and not sector.session.menu.visible and not panel.visible and not sector.shop.visible and not sector.equipment_menu.visible and not sector.hud.contract_panel.visible and not sector.hud.navigation.overview.visible
	if show_pause and not pause_panel.visible:
		pause_panel.show()
		resume_button.grab_focus()
	pause_panel.visible = show_pause
	if panel.visible:
		master_label.text = "Master volume  /  %d%%" % master.value
		effects_label.text = "Effects volume  /  %d%%" % effects.value
		save_status.text = "Could not save settings. Changes will last for this session." if sector.settings.save_failed or sector.audio.save_failed else "Saved on this device"
		save_status.add_theme_color_override("font_color", FlightHud.RED if sector.settings.save_failed or sector.audio.save_failed else FlightHud.GREEN)
