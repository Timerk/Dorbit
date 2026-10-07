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
var main_menu_button: Button
var ship_menus_button: Button
var reset_button: Button
var pending_action: String = ""
var from_connection: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = menu_theme()
	pause_panel = make_panel(Vector2(540, 400))
	var pause_rows := content(pause_panel)
	label(pause_rows, "FLIGHT MENU", 28).autowrap_mode = TextServer.AUTOWRAP_OFF
	resume_button = button(pause_rows, "Resume flight", func(): sector.set_paused(false))
	ship_menus_button = button(pause_rows, "Ship menus", func(): sector.main_menu.show_home())
	button(pause_rows, "Settings", func(): open())
	button(pause_rows, "Multiplayer session", sector.session.open_menu)
	main_menu_button = button(pause_rows, "Quit to main menu", sector.session.quit_to_menu)
	button(pause_rows, "Quit to desktop", func(): get_tree().quit())
	pause_panel.tooltip_text = "In multiplayer, the world keeps running while menus are open."
	pause_panel.hide()
	panel = make_panel(Vector2(1050, 640))
	var rows := content(panel)
	label(rows, "SETTINGS", 28)
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



static func menu_theme() -> Theme:
	return StationUi.menu_theme()


func layout() -> void:
	for entry: PanelContainer in [panel, pause_panel]:
		if entry == panel and is_instance_valid(sector.main_menu) and sector.main_menu.visible:
			sector.main_menu.fit_panel(entry, Vector2(1050, 640))
			continue
		var preferred := Vector2(1050, 640) if entry == panel else Vector2(540, 400)
		StationUi.centered(entry, preferred)


func make_panel(dimensions: Vector2) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", StationUi.style(StationUi.SURFACE, StationUi.LINE))
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
	result.add_theme_color_override("font_color", StationUi.AMBER if font_size == 11 else (FlightHud.MUTED if font_size == 14 else FlightHud.INK))
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
	var response := HBoxContainer.new()
	rows.add_child(response)
	sensitivity_label = label(response, "Mouse sensitivity")
	sensitivity_label.custom_minimum_size.x = 300
	sensitivity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sensitivity = HSlider.new()
	sensitivity.min_value = 0.1
	sensitivity.max_value = 3.0
	sensitivity.step = 0.05
	sensitivity.custom_minimum_size.y = 36
	sensitivity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response.add_child(sensitivity)
	sensitivity.value_changed.connect(func(value: float):
		sector.settings.sensitivity = value * GameSettings.DEFAULT_SENSITIVITY
		sector.player.mouse_sensitivity = sector.settings.sensitivity
		sensitivity_label.text = "Mouse sensitivity  /  %.2fx" % value
		sector.settings.save())
	rows.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	rows.add_child(columns)
	var bindings: Array[VBoxContainer] = []
	for index in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 12)
		columns.add_child(column)
		bindings.append(column)
	var rows_per_column := ceili(GameSettings.ACTIONS.size() / 2.0)
	var index := 0
	for action: String in GameSettings.ACTIONS:
		var row := HBoxContainer.new()
		bindings[index / rows_per_column].add_child(row)
		index += 1
		var caption := label(row, GameSettings.ACTIONS[action])
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var binding := button(row, "", func(): begin_binding(action))
		binding.custom_minimum_size.x = 150
		binding.tooltip_text = "Choose a key or mouse button. An occupied binding swaps actions; Esc cancels."
		binding_buttons[action] = binding
	binding_help = label(rows, "", 14)
	reset_button = button(rows, "Restore defaults", func():
		sector.settings.reset_controls()
		sector.player.mouse_sensitivity = sector.settings.sensitivity
		sector.settings.save()
		sync_controls())
	reset_button.size_flags_horizontal = Control.SIZE_SHRINK_END


func build_audio(rows: VBoxContainer) -> void:
	var master_row := HBoxContainer.new()
	rows.add_child(master_row)
	master_label = label(master_row, "Master volume")
	master_label.custom_minimum_size.x = 300
	master_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	master = volume_slider(master_row)
	master.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var effects_row := HBoxContainer.new()
	rows.add_child(effects_row)
	effects_label = label(effects_row, "Effects volume")
	effects_label.custom_minimum_size.x = 300
	effects_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	effects = volume_slider(effects_row)
	effects.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master.value_changed.connect(func(value: float):
		sector.audio.master = value / 100.0
		sector.audio.save_preferences())
	effects.value_changed.connect(func(value: float):
		sector.audio.effects = value / 100.0
		sector.audio.save_preferences())
	rows.add_child(HSeparator.new())
	mute = checkbox(rows, "Mute", func(value: bool):
		sector.audio.muted = value
		sector.audio.save_preferences())
	var test_sound := button(rows, "Test sound", func(): sector.audio.play("purchase", sector.player.camera.global_position))
	test_sound.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func build_graphics(rows: VBoxContainer) -> void:
	fullscreen = checkbox(rows, "Fullscreen", func(value: bool):
		sector.settings.fullscreen = value
		sector.apply_graphics(false)
		sector.settings.save())
	var resolution_row := HBoxContainer.new()
	rows.add_child(resolution_row)
	var resolution_label := label(resolution_row, "Window resolution")
	resolution_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	resolution = OptionButton.new()
	resolution.custom_minimum_size.x = 240
	resolution_row.add_child(resolution)
	resolution.tooltip_text = "Selecting a resolution switches to windowed mode. Fullscreen uses your desktop resolution."
	resolution.item_selected.connect(func(index: int):
		sector.settings.resolution = resolutions[index]
		sector.settings.fullscreen = false
		sector.apply_graphics()
		sector.settings.save()
		fullscreen.set_pressed_no_signal(false))
	vsync = checkbox(rows, "VSync", func(value: bool):
		sector.settings.vsync = value
		sector.apply_graphics(false)
		sector.settings.save())
	vsync.tooltip_text = "Sync frames to the screen to reduce tearing."
	var quality_row := HBoxContainer.new()
	rows.add_child(quality_row)
	var quality_label := label(quality_row, "Antialiasing")
	quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quality = OptionButton.new()
	quality.custom_minimum_size.x = 240
	quality.add_item("Off")
	quality.add_item("4x MSAA")
	quality_row.add_child(quality)
	quality.item_selected.connect(func(index: int):
		sector.settings.low_quality = index == 0
		sector.apply_graphics(false)
		sector.settings.save())
	performance = checkbox(rows, "Show performance overlay", func(value: bool):
		sector.settings.show_performance = value
		sector.apply_graphics(false)
		sector.settings.save())


func open(connection: bool = false) -> void:
	if not connection and sector.main_menu.route_page("settings"):
		return
	from_connection = connection
	sector.set_paused(true)
	sector.shop.hide()
	sector.equipment_menu.hide()
	sector.hud.contract_panel.hide()
	sector.session.menu.hide()
	pause_panel.hide()
	panel.show()
	layout()
	sync_controls()
	back_button.grab_focus()


func close() -> void:
	dismiss()
	if sector.preflight and not from_connection:
		sector.main_menu.show_home()
		return
	if from_connection:
		sector.session.open_menu()
	elif sector.main_menu.visible:
		sector.set_paused(false)
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
	binding_help.text = ""
	binding_help.hide()


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
	binding_help.show()
	binding_buttons[action].text = "Press a key..."
	binding_buttons[action].add_theme_stylebox_override("normal", StationUi.style(Color("30251a"), StationUi.AMBER))
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
	main_menu_button.visible = sector.session.active or sector.session.offline_main_menu()
	main_menu_button.tooltip_text = "Stops the development host and disconnects its pilots." if sector.session.active and multiplayer.is_server() else ""
	var show_pause := sector.paused and not sector.preflight and not sector.main_menu.visible and not sector.session.menu.visible and not panel.visible and not sector.shop.visible and not sector.equipment_menu.visible and not sector.hud.contract_panel.visible and not sector.hud.navigation.overview.visible
	if show_pause and not pause_panel.visible:
		pause_panel.show()
		resume_button.grab_focus()
	pause_panel.visible = show_pause
	if show_pause:
		# Container minimum sizes settle after _ready and after button visibility changes.
		StationUi.centered(pause_panel, Vector2(540, 400))
	if panel.visible:
		layout()
		master_label.text = "Master volume  /  %d%%" % master.value
		effects_label.text = "Effects volume  /  %d%%" % effects.value
		save_status.text = "Could not save settings. Changes will last for this session." if sector.settings.save_failed or sector.audio.save_failed else "Saved on this device"
		save_status.visible = sector.settings.save_failed or sector.audio.save_failed
		back_button.visible = not sector.main_menu.visible or from_connection
		save_status.add_theme_color_override("font_color", FlightHud.RED if sector.settings.save_failed or sector.audio.save_failed else FlightHud.GREEN)
