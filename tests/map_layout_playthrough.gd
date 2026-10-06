extends "res://tests/encounter_test.gd"
## Rendered flight across the real sphere, radiation feedback, re-entry and map layouts.


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await create_timer(0.15).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://build/validation")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	sector.show_performance = false
	await sync_physics()
	for pixels in [Vector2i(960, 600), Vector2i(1440, 900)]:
		root.size = pixels
		root.content_scale_size = pixels
		DisplayServer.window_set_size(pixels)
		sector.player.position = Vector3(500, 350, 600)
		sector.select_target(sector.aliens[1])
		await capture("map-navigation-%d" % pixels.x)
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
	await capture("map-safe-return")
	print("Map flight replay: %d passed, %d failed" % [checks - failures, failures])
	sector.free()
	quit(0 if failures == 0 else 1)
