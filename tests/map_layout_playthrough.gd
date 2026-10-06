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
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await create_timer(0.05).timeout


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	sector.show_performance = false
	await sync_physics()
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
	for pixels in [Vector2i(960, 600), Vector2i(1440, 900)]:
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
		var previous_yaw := navigation.view_yaw
		var drag_start := navigation.plot.get_global_rect().get_center()
		var right_button := InputEventMouseButton.new()
		right_button.button_index = MOUSE_BUTTON_RIGHT
		right_button.position = drag_start
		right_button.pressed = true
		root.push_input(right_button)
		await process_frame
		var motion := InputEventMouseMotion.new()
		motion.position = drag_start + Vector2(50, 0)
		motion.relative = Vector2(50, 0)
		motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
		root.push_input(motion)
		await process_frame
		right_button = InputEventMouseButton.new()
		right_button.button_index = MOUSE_BUTTON_RIGHT
		right_button.position = motion.position
		right_button.pressed = false
		root.push_input(right_button)
		await process_frame
		check(navigation.view_yaw > previous_yaw and sector.player.rotation.is_equal_approx(Vector3(0.1, 0.5, 0)), "Right mouse rotates overview without steering the ship")
		navigation.view_yaw = previous_yaw
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
