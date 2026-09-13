extends "res://tests/flight_playthrough.gd"
## Presentation load fixture, not a multiplayer throughput benchmark.


func run() -> void:
	root.size = Vector2i(2560, 1440)
	root.content_scale_size = Vector2i(2560, 1440)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	current_scene = sector
	sector.set_physics_process(false)
	sector.session.active = true
	sector.show_performance = true
	sector.player.position = Vector3(0, 30, -100)
	sector.session.ships[1] = sector.player
	for index in range(9):
		var pilot := Pilot.new()
		sector.add_child(pilot)
		pilot.position = Vector3((index - 4) * 9, 30 + index % 3 * 3, -150 - index % 2 * 15)
		pilot.camera.current = false
		sector.session.ships[index + 2] = pilot
	sector.player.camera.make_current()
	sector.alien.position = Vector3(0, 38, -210)
	sector.select_target(sector.alien)
	sector.auto_fire = true
	sector.weapon_status = sector.player.firing_blocker(sector.target)
	await create_timer(0.5).timeout
	sampling = true
	for volley in range(80):
		for ship: Pilot in sector.session.ships.values():
			SectorVisuals.laser(sector, ship.position, sector.alien.position, false)
			SectorVisuals.impact(ship, ship.position, volley % 2 == 0, volley % 2 != 0)
		if volley % 10 == 0:
			SectorVisuals.explosion(sector, sector.alien.position + Vector3(12, 0, 0))
		check(get_nodes_in_group("transient_feedback").size() <= 80, "Transient effects remain bounded")
		if volley == 20:
			await snapshot("feedback-busy")
		await create_timer(0.1).timeout
	sampling = false
	frame_times.sort()
	print("Busy feedback: 10 pilot models, 1 alien, 100 laser + 100 impact requests/s; p95=%.2f ms; frames=%d; GPU=%s" % [frame_times[int(frame_times.size() * 0.95)], frame_times.size(), RenderingServer.get_video_adapter_name()])
	sector.session.active = false
	sector.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
