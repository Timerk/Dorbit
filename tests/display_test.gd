extends SceneTree
## Run with a rendered window to verify display controls and capture the pause HUD.


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/validation")
	var sector := preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	await process_frame
	sector.set_paused(true)
	var failures := 0
	for resolution in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(resolution)
		await create_timer(0.3).timeout
		var motion := InputEventMouseMotion.new()
		motion.screen_relative = Vector2(100, -50)
		motion.relative = Vector2(100, -50) * 1440.0 / resolution.x
		sector.player.steering = true
		sector.player.rotation = Vector3.ZERO
		sector.player.handle_mouse(motion)
		if not sector.player.rotation.is_equal_approx(Vector3(0.15, -0.3, 0)):
			failures += 1
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png("res://build/validation/display-%d.png" % resolution.x) != OK:
			failures += 1
	var previous := DisplayServer.window_get_size()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F5
	key.pressed = true
	Input.parse_input_event(key)
	await create_timer(0.3).timeout
	if DisplayServer.window_get_size() == previous:
		failures += 1
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	print("Display checks: %d failures" % failures)
	quit(0 if failures == 0 else 1)
