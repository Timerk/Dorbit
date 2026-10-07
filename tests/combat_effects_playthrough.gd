extends "res://tests/flight_playthrough.gd"
## Rendered close-range feedback gallery using real shot validation and damage.


func snapshot(label: String) -> void:
	if not rendered:
		return
	# Capture a consistent 50 ms phase, even if shader compilation stalls a frame.
	var tweens := get_processed_tweens()
	for tween: Tween in tweens:
		tween.pause()
		tween.custom_step(0.05)
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://build/validation")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	for tween: Tween in tweens:
		if tween.is_valid():
			tween.play()


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	current_scene = sector
	sector.set_physics_process(false)
	sector.set_paused(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	sector.show_performance = false
	for enemy: Alien in sector.aliens.values():
		if enemy != sector.alien:
			enemy.alive = false
			enemy.hide()
	sector.player.position = Vector3(200, 100, 50)
	sector.alien.position = sector.player.position + Vector3(14, 2, -32)
	sector.alien.home_position = sector.alien.position
	sector.alien.rotation = Vector3.ZERO
	sector.select_target(sector.alien)
	sector.auto_fire = true
	sector.weapon_status = ""
	# Warm the effect shaders before timing the brief impacts for screenshots.
	SectorVisuals.laser(sector, sector.player.position, sector.alien.position, false)
	SectorVisuals.impact(sector.alien, sector.alien.position, true, true)
	SectorVisuals.explosion(sector, sector.alien.position)
	await create_timer(1.0).timeout
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		root.content_scale_size = size
		await create_timer(0.4).timeout
		if rendered:
			check(root.get_texture().get_size() == Vector2(size), "Gallery uses the requested render resolution")
		sector.alien.reset_health()
		sector.alien.shield_absorption = 1.0
		sector.player.shot_cooldown = 0.0
		check(sector.player.try_fire(sector.alien), "Gallery shield shot uses actual firing validation")
		await snapshot("combat-laser-shield-%d" % size.x)
		await create_timer(0.45).timeout
		sector.alien.shield = 0.0
		sector.player.shot_cooldown = 0.0
		check(sector.player.try_fire(sector.alien), "Gallery hull shot uses actual firing validation")
		await snapshot("combat-laser-hull-%d" % size.x)
		await create_timer(0.45).timeout
		SectorVisuals.laser(sector, sector.alien.position, sector.player.position, true)
		SectorVisuals.impact(sector.player, sector.player.position, true, true)
		await snapshot("combat-hostile-%d" % size.x)
		await create_timer(0.45).timeout
		sector.alien.take_damage(sector.alien.hull + 1.0, sector.player)
		check(not sector.alien.alive and sector.kills > 0, "Gallery destruction uses the actual death and reward path")
		await snapshot("combat-destruction-%d" % size.x)
		await create_timer(0.7).timeout
	sector.queue_free()
	await process_frame
	print("Combat gallery: %d failures" % failures)
	quit(0 if failures == 0 else 1)
