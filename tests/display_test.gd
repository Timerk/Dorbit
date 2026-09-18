extends "res://tests/encounter_test.gd"
## Uses an isolated APPDATA profile. Also run rendered for screenshots, then -- --restart.


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	root.add_child(sector)
	sector.set_physics_process(false)
	await sync_physics()
	var menu := sector.settings_menu
	if "--restart" in OS.get_cmdline_user_args():
		check(is_equal_approx(sector.player.mouse_sensitivity, 0.006), "Sensitivity survives a new process")
		check(sector.settings.bindings.fire == KEY_G and sector.settings.bindings.forward == KEY_S, "Bindings survive a new process")
		check(sector.low_quality and sector.show_performance, "Graphics preferences survive a new process")
		check(is_equal_approx(sector.audio.master, 0.35) and is_equal_approx(sector.audio.effects, 0.45) and sector.audio.muted, "Audio preferences survive a new process")
		sector.settings = GameSettings.new()
		sector.settings.save()
		sector.audio.master = 0.7
		sector.audio.effects = 0.7
		sector.audio.muted = false
		sector.audio.save_preferences()
		finish()
		return

	check(sector.session.menu.visible, "Normal client starts at the connection menu")
	menu.open(true)
	await process_frame
	check(menu.panel.visible and not sector.session.menu.visible and sector.paused, "Settings can open before connecting")
	await tap_key(KEY_ESCAPE)
	check(not menu.panel.visible and sector.session.menu.visible, "Escape returns settings to the connection menu")
	sector.client_only = false
	sector.session.menu.hide()
	sector.set_paused(false)
	await tap_key(KEY_ESCAPE)
	menu.open()
	await process_frame
	menu.sensitivity.value = 1.5
	menu.begin_binding("fire")
	await tap_key(KEY_H)
	menu.reset_button.pressed.emit()
	check(sector.settings.bindings == GameSettings.DEFAULT_BINDINGS and is_equal_approx(sector.player.mouse_sensitivity, GameSettings.DEFAULT_SENSITIVITY), "Restore default controls resets bindings and actual sensitivity")
	menu.sensitivity.value = 2.0
	var player := sector.player
	player.steering = true
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(100, -50)
	player.handle_mouse(motion)
	check(player.pending_look.is_equal_approx(Vector2(-0.6, 0.3)), "Slider changes actual screen-relative steering sensitivity")
	player.release_mouse()

	menu.binding_buttons.fire.pressed.emit()
	await tap_key(KEY_F10)
	check(menu.pending_action == "fire" and sector.settings.bindings.fire == KEY_SPACE, "Reserved shortcuts cannot be rebound or quit during capture")
	await tap_key(KEY_ESCAPE)
	check(menu.pending_action.is_empty() and menu.panel.visible, "Escape cancels capture without leaving settings")
	menu.begin_binding("fire")
	await tap_key(KEY_G)
	check(sector.settings.bindings.fire == KEY_G and not sector.auto_fire, "Key capture updates binding without firing")
	menu.begin_binding("forward")
	await tap_key(KEY_S)
	check(sector.settings.bindings.forward == KEY_S and sector.settings.bindings.backward == KEY_W, "Conflicting keys swap without leaving either action unbound")
	menu.begin_binding("steer")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await process_frame
	mouse = mouse.duplicate()
	mouse.pressed = false
	Input.parse_input_event(mouse)
	await process_frame
	check(sector.settings.bindings.steer == -MOUSE_BUTTON_MIDDLE and not player.steering, "Mouse binding capture does not capture flight cursor")
	menu.master.value = 35
	menu.effects.value = 45
	menu.mute.button_pressed = true
	menu.quality.select(0)
	menu.quality.item_selected.emit(0)
	menu.performance.button_pressed = true
	check(root.msaa_3d == Viewport.MSAA_DISABLED and sector.show_performance, "Graphics controls update the viewport and overlay")
	await tap_key(KEY_ESCAPE)
	check(sector.paused and not menu.panel.visible, "Escape returns settings to the pause menu")
	await tap_key(KEY_ESCAPE)
	check(not sector.paused, "Second Escape resumes flight")
	await tap_key(KEY_TAB)
	await tap_key(KEY_SPACE)
	check(not sector.auto_fire, "Old fire key no longer fires")
	await tap_key(KEY_G, false)
	check(sector.auto_fire, "Rebound fire works with logical-only input")
	await tap_key(KEY_G)
	check(not sector.auto_fire and sector.hud.fire_feedback().contains("G"), "Physical key and HUD use the new binding")
	var forward := InputEventKey.new()
	forward.physical_keycode = KEY_S
	forward.pressed = true
	Input.parse_input_event(forward)
	await process_frame
	check(player.read_movement() == Vector3.FORWARD, "Rebound movement produces forward flight intent")
	forward = forward.duplicate()
	forward.pressed = false
	Input.parse_input_event(forward)
	mouse = mouse.duplicate()
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await process_frame
	check(player.steering, "Rebound mouse button steers in flight")
	sector.auto_fire = true
	menu.open()
	check(not player.steering and not sector.auto_fire and player.pending_look.is_zero_approx(), "Opening settings clears steering and fire")
	mouse = mouse.duplicate()
	mouse.pressed = false
	Input.parse_input_event(mouse)

	var invalid := ConfigFile.new()
	invalid.set_value("controls", "sensitivity", "bad")
	invalid.set_value("bindings", "fire", KEY_ESCAPE)
	invalid.set_value("graphics", "fullscreen", "yes")
	invalid.set_value("graphics", "resolution", Vector2i(-1, -1))
	invalid.save("user://invalid-settings.cfg")
	var loaded := GameSettings.new()
	loaded.load_from("user://invalid-settings.cfg")
	check(loaded.sensitivity == GameSettings.DEFAULT_SENSITIVITY and loaded.bindings.fire == KEY_SPACE and not loaded.fullscreen and loaded.resolution == Vector2i(1440, 900), "Malformed preferences retain usable defaults")
	loaded.save("user://missing-directory/settings.cfg")
	check(loaded.save_failed, "Failed preference writes are reported")
	sector.settings.configure_input()

	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build/validation")
		for pixels in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(1920, 1080)]:
			DisplayServer.window_set_size(pixels)
			await create_timer(0.2).timeout
			for tab in range(menu.tabs.get_tab_count()):
				menu.tabs.current_tab = tab
				await process_frame
				await RenderingServer.frame_post_draw
				check(root.get_visible_rect().encloses(menu.panel.get_global_rect()), "Settings panel fits at %d px, tab %d" % [pixels.x, tab])
				root.get_texture().get_image().save_png("res://build/validation/settings-%d-%d.png" % [pixels.x, tab])
		menu.fullscreen.button_pressed = true
		await create_timer(0.2).timeout
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Fullscreen control enters fullscreen")
		menu.sync_controls()
		menu.resolution.item_selected.emit(0)
		await create_timer(0.2).timeout
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_size() == menu.resolutions[0], "Resolution selection returns to a sized window")
	sector.settings.save()
	finish()


func finish() -> void:
	print("Settings checks: %d passed, %d failed" % [checks - failures, failures])
	sector.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
