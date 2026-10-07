extends "res://tests/encounter_test.gd"
## Rendered flight across the real sphere, radiation feedback, re-entry and map layouts.


func _process(_delta: float) -> bool:
	# Desktop focus changes are outside this automated input fixture. Keep its
	# menu state determined by the overview while retaining real game input paths.
	if is_instance_valid(sector) and is_instance_valid(sector.hud):
		sector.set_paused(sector.hud.navigation.overview.visible)
	return false


func capture(label: String) -> void:
	await create_timer(0.15).timeout
	sector.set_paused(sector.hud.navigation.overview.visible)
	await process_frame
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://build/validation")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func click_at(point: Vector2) -> void:
	# Route hover before pressing, as native pointer input does. This also clears
	# the preceding button's hover after a window resize.
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await create_timer(0.05).timeout


func drag_map(navigation: FlightNavigation, button: int) -> void:
	# Starting over a contact must still rotate without selecting on press.
	var start := navigation.plot.global_position + navigation.plot_point(sector.aliens[1].position)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.position = start
	press.pressed = true
	root.push_input(press)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(50, 25)
	motion.relative = Vector2(50, 25)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(motion)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.position = motion.position
	release.pressed = false
	root.push_input(release)
	await process_frame


func scroll_map(point: Vector2, up: bool, ctrl: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.position = point
	event.ctrl_pressed = ctrl
	event.pressed = true
	root.push_input(event)
	await process_frame
	# Native wheel input includes its release; don't leave the GUI mouse grab held.
	event.pressed = false
	root.push_input(event)
	await process_frame


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	sector.show_performance = false
	await sync_physics()
	# Keep pointer tests and captures reproducible. Random homes are tested over ENet.
	var fixture_positions := {0: Vector3(-600, 0, -400), 2: Vector3(-500, -400, 400), 3: Vector3(300, -450, -600), 4: Vector3(400, 200, -700)}
	for id: int in fixture_positions:
		sector.aliens[id].position = fixture_positions[id]
	var navigation := sector.hud.navigation
	var transform := Transform3D(Basis.from_euler(Vector3(0.4, 1.2, 0.0)), Vector3(100, 200, 300))
	check(FlightNavigation.relative_position(transform, transform * Vector3(40, 25, -100)).is_equal_approx(Vector3(40, 25, -100)), "Radar follows both ship yaw and pitch with forward at top")
	check(FlightNavigation.compass_point(Vector3(1, 1, -1)).x > 0 and FlightNavigation.compass_point(Vector3(1, 1, -1)).y < 0, "Compass guides right and up")
	check(FlightNavigation.turn_hint(Vector3(0, 0, 100)).contains("BEHIND"), "Behind guidance asks pilot to turn around")
	check(FlightNavigation.turn_hint(Vector3(0, 0, -100)).contains("ALIGNED"), "Forward guidance confirms alignment")
	for step in range(10):
		navigation.change_range(-1)
	check(navigation.range_index == 0, "Radar range stops at minimum")
	for step in range(10):
		navigation.change_range(1)
	check(navigation.range_index == navigation.RANGES.size() - 1, "Radar range stops at maximum")
	navigation.change_range(-2)
	for pixels in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		root.size = pixels
		root.content_scale_size = pixels
		DisplayServer.window_set_size(pixels)
		sector.player.position = Vector3(500, 350, 600)
		sector.player.rotation = Vector3(0.1, 0.5, 0)
		sector.aliens[1].position = Vector3(600, 440, 320)
		sector.select_target(sector.aliens[1])
		await capture("map-navigation-%d" % pixels.x)
		check(navigation.waypoint_key == "alien1", "Manual target becomes destination at %d" % pixels.x)
		await click_at(navigation.range_more.get_global_rect().get_center())
		check(navigation.range_index == 2, "Mouse range button increases radar range")
		await click_at(navigation.range_less.get_global_rect().get_center())
		check(navigation.range_index == 1, "Mouse range button decreases radar range")
		sector.auto_fire = true
		sector.player.steering = true
		tap_key(KEY_M)
		await sync_physics()
		check(navigation.overview.visible and sector.paused and not sector.auto_fire and not sector.player.steering, "M opens overview and releases flight/fire controls")
		await capture("map-overview-%d" % pixels.x)
		for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			var previous_yaw := navigation.view_yaw
			var previous_pitch := navigation.view_pitch
			await drag_map(navigation, button)
			check(navigation.view_yaw > previous_yaw and navigation.view_pitch > previous_pitch and sector.player.rotation.is_equal_approx(Vector3(0.1, 0.5, 0)), "Mouse %d rotates overview horizontally and vertically without steering" % button)
			check(navigation.overview.visible and navigation.waypoint_key == "alien1", "Dragging from a contact does not select it or close overview")
			if button == MOUSE_BUTTON_LEFT:
				await capture("map-overview-rotated-%d" % pixels.x)
			await click_at(navigation.reset_button.get_global_rect().get_center())
			check(is_equal_approx(navigation.view_yaw, -0.55) and is_equal_approx(navigation.view_pitch, atan2(0.55, 0.7)), "Reset view restores rotation")
		var zoom_point := navigation.plot_point(sector.aliens[1].position)
		await scroll_map(navigation.plot.global_position + zoom_point, true)
		check(navigation.view_zoom > 1 and navigation.plot_point(sector.aliens[1].position).is_equal_approx(zoom_point), "Plain wheel zooms around the contact under the cursor")
		await scroll_map(navigation.plot.global_position + zoom_point, false)
		check(is_equal_approx(navigation.view_zoom, 1), "Plain wheel down zooms back out")
		await scroll_map(navigation.plot.global_position + zoom_point, true, true)
		check(navigation.view_zoom > 1, "Holding Ctrl does not block wheel zoom")
		navigation.reset_view()
		for step in range(12):
			await scroll_map(navigation.plot.get_global_rect().get_center(), true)
		check(is_equal_approx(navigation.view_zoom, 3), "Zoom stops at readable maximum")
		await capture("map-overview-zoom-%d" % pixels.x)
		await click_at(navigation.reset_button.get_global_rect().get_center())
		check(navigation.view_zoom == 1 and navigation.view_offset.is_zero_approx(), "Reset view restores zoom and cursor offset")
		for step in range(12):
			await scroll_map(navigation.plot.get_global_rect().get_center(), false)
		check(is_equal_approx(navigation.view_zoom, 0.6), "Zoom stops at full-sector minimum")
		navigation.reset_view()
		var label_rect := navigation.plot_labels()["alien1"]
		var hover := InputEventMouseMotion.new()
		hover.position = navigation.plot.global_position + label_rect.get_center()
		root.push_input(hover)
		await process_frame
		check(navigation.plot.hovered_key == "alien1" and navigation.plot.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "Map names show a clickable hover highlight")
		await click_at(navigation.plot.global_position + label_rect.get_center())
		check(sector.target == sector.aliens[1] and not navigation.overview.visible and not sector.paused, "Map name selects an alien destination and returns to flight")
		navigation.open_overview()
		await sync_physics()
		var alien_position := sector.aliens[1].position
		# The stem's midpoint falls under the outpost caption at this projection.
		# Click its exposed lower section to exercise height-line selection.
		var stem_point := navigation.plot_point(alien_position).lerp(navigation.plot_point(Vector3(alien_position.x, 0, alien_position.z)), 0.8)
		await click_at(navigation.plot.global_position + stem_point)
		check(not navigation.overview.visible and navigation.waypoint_key == "alien1", "Height stem selects its destination directly on the map")
		navigation.open_overview()
		check(not sector.settings_menu.pause_panel.visible, "Overview owns its menu without pause panel overlay")
		check(Rect2(Vector2.ZERO, Vector2(pixels)).encloses(navigation.overview.get_global_rect()), "Overview fits %d window" % pixels.x)
		await click_at(navigation.plot.global_position + navigation.plot_point(Sector.STATION_POSITION))
		check(navigation.waypoint_key == "station" and sector.target == null and not sector.paused, "Map contact chooses station waypoint and resumes")
		navigation.open_overview()
		await click_at(navigation.contact_buttons["alien1"].get_global_rect().get_center())
		check(sector.target == sector.aliens[1] and navigation.waypoint_key == "alien1" and not sector.paused, "Contact row chooses alien and resumes")
		navigation.open_overview()
		tap_key(KEY_ESCAPE)
		await sync_physics()
		check(not navigation.overview.visible and not sector.paused, "Esc closes overview directly to flight")
	root.size = Vector2i(960, 600)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	var player := sector.player
	player.position = Vector3(0, 300, 1100)
	player.rotation = Vector3.ZERO
	await capture("map-edge-approach")
	Input.action_press("backward")
	for frame in range(240):
		sector.set_paused(false)
		sector._physics_process(1.0 / 60.0)
		await physics_frame
	Input.action_release("backward")
	check(player.position.length() > Sector.MAP_RADIUS and player.radiation_exposure > 0, "Flight crosses boundary and builds radiation exposure")
	check(player.hull < player.max_hull and player.alive, "Radiation damages the live ship")
	check(navigation.destination()["key"] == "safe", "Radiation overrides guidance with closest safe point")
	await capture("map-radiation")
	player.look_at(Vector3.ZERO, Vector3.UP)
	Input.action_press("forward")
	for frame in range(300):
		sector.set_paused(false)
		sector._physics_process(1.0 / 60.0)
		await physics_frame
		if player.position.length() < Sector.MAP_RADIUS - 50:
			break
	Input.action_release("forward")
	check(player.position.length() < Sector.MAP_RADIUS and player.radiation_exposure == 0, "Turning inward returns freely and stops radiation")
	check(navigation.destination()["key"] == navigation.waypoint_key, "Re-entry restores chosen destination")
	await capture("map-safe-return")
	navigation.open_overview()
	sector.player.alive = false
	await create_timer(0.05).timeout
	check(not navigation.overview.visible and not sector.paused, "Rescue closes overview and releases menu state")
	sector.player.reset_health()
	sector.select_target(null)
	await create_timer(0.05).timeout
	check(navigation.waypoint_key == "station", "Cleared alien target returns guidance to outpost")
	print("Map flight replay: %d passed, %d failed" % [checks - failures, failures])
	sector.free()
	quit(0 if failures == 0 else 1)
