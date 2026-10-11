extends "res://tests/map_layout_playthrough.gd"
## Exercise actual map controls, gate input, local projection and home rescue.


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	sector.show_performance = false
	var navigation := sector.hud.navigation
	for pixels in [Vector2i(960, 600), Vector2i(1280, 720)]:
		root.size = pixels
		root.content_scale_size = pixels
		DisplayServer.window_set_size(pixels)
		await tap_key(KEY_M)
		await sync_physics()
		var bar := navigation.tabs.get_tab_bar()
		await click_at(bar.global_position + bar.get_tab_rect(1).get_center())
		check(navigation.tabs.current_tab == 1, "M opens the map and the connections tab is clickable")
		await capture("connected-map-network-%d" % pixels.x)
		check(Rect2(Vector2.ZERO, Vector2(pixels)).encloses(navigation.overview.get_global_rect()), "Connections view fits the %d window" % pixels.x)
		await click_at(navigation.network_plot.global_position + navigation.network_plot.map_rect(3).get_center())
		check(navigation.waypoint_key == "gate1" and not navigation.overview.visible and not sector.paused, "Clicking M4 from M1 selects the first gate on its route")
	for destination in [1, 2, 3, 2, 1, 3, 1, 0]:
		var source := sector.map_id
		sector.player.position = SectorMaps.gate_position(source, destination) + Vector3(0, 0, 42)
		sector.player.look_at(SectorMaps.gate_position(source, destination), Vector3.UP)
		sector.session.jump_until.erase(1)
		sector.select_target(sector.alien)
		sector.auto_fire = true
		sector.autopilot.enabled = true
		await capture("connected-map-gate-m%d-m%d" % [source + 1, destination + 1])
		await tap_key(KEY_J)
		check(sector.map_id == destination and sector.player.map_id == destination and sector.aliens.size() == 5, "Jump input follows the reciprocal M%d-M%d gate" % [source + 1, destination + 1])
		check(sector.target == null and not sector.auto_fire and not sector.autopilot.enabled and sector.player.velocity.is_zero_approx(), "Offline transfer resets flight and combat intent")
		check(SectorMaps.protected(sector.player), "Offline arrival remains protected")
		await tap_key(KEY_M)
		navigation.tabs.current_tab = 0
		await sync_physics()
		check(navigation.contacts().filter(func(contact: Dictionary): return contact["key"].begins_with("gate")).size() == SectorMaps.GATES[destination].size(), "Local map lists exactly the current sector's gates")
		check(navigation.contacts().any(func(contact: Dictionary): return contact["key"] == "station") == (destination == 0), "Station contact appears only at home")
		check(navigation.plot_point(SectorMaps.origin(destination)).is_equal_approx(navigation.plot.size * 0.5), "Local overview remains centered after map transfer")
		await capture("connected-map-local-m%d" % (destination + 1))
		await tap_key(KEY_ESCAPE)
		sector.player.position = SectorMaps.origin(destination) + Vector3(0, 150, 0)
		var hull := sector.player.hull
		sector.tick_radiation(sector.player, 1)
		check(sector.player.hull == hull and navigation.destination()["key"] != "safe", "Safe-space and guidance use each map's origin")
		sector.player.position = SectorMaps.origin(destination) + Vector3(0, Sector.MAP_RADIUS + 10, 0)
		sector.tick_radiation(sector.player, 1)
		check(sector.player.hull < hull and navigation.destination()["key"] == "safe", "Every map has radiation beyond its own boundary")
		sector.player.reset_health()
	# Inspect a new procedural alien during ordinary flight.
	sector.player.map_id = 3
	sector.activate_map(3)
	var enemy := sector.alien
	sector.player.position = enemy.position + Vector3(0, 0, 65)
	sector.player.look_at(enemy.position, Vector3.UP)
	sector.select_target(enemy)
	await capture("connected-map-frontier-alien")
	sector.player.take_damage(sector.player.max_hull + sector.player.max_shield + 1, null)
	sector._physics_process(3.1)
	check(sector.player.alive and sector.map_id == 0 and sector.player.position == Sector.SPAWN_POSITION, "Offline destruction returns to the home station")
	print("Connected-map flight replay: %d passed, %d failed" % [checks - failures, failures])
	sector.free()
	quit(0 if failures == 0 else 1)
