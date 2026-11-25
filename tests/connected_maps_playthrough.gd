extends "res://tests/map_layout_playthrough.gd"
## Exercise actual map controls, gate input, local projection and home rescue.

var interactions_checked: Array[int] = []


func run() -> void:
	sector = preload("res://scenes/sector.tscn").instantiate()
	sector.client_only = false
	root.add_child(sector)
	sector.set_physics_process(false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	sector.show_performance = false
	check(sector.map_scenery.keys() == [0], "Rendered startup contains only home scenery")
	var navigation := sector.hud.navigation
	for pixels in [Vector2i(960, 600), Vector2i(1280, 720), Vector2i(1920,1080)]:
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
		var chart := navigation.network_plot
		for map: int in SectorMaps.network_maps():
			check(Rect2(Vector2.ZERO, chart.size).encloses(chart.map_rect(map)), "Image card remains inside the map canvas")
			check(chart.PICTURES[map].get_width() >= 720, "Every card uses a detailed sector capture")
			for other: int in SectorMaps.network_maps():
				if map < other:
					check(not chart.map_rect(map).intersects(chart.map_rect(other)), "Sector images do not overlap")
		var route := chart.route_edges(3)
		check(route == [Vector2i(0,1),Vector2i(1,3)], "Route preview to M4 follows real M1-M2-M4 gates")
		var hover := InputEventMouseMotion.new()
		hover.position = chart.get_global_transform() * chart.map_rect(3).get_center()
		root.push_input(hover)
		await process_frame
		check(chart.hovered_map == 3 and chart.tooltip_text.contains("M2"), "Hover shows the destination details and real next gate")
		if pixels.x == 1280:
			await capture("connected-map-route-preview")
		await click_at(chart.get_global_transform() * chart.map_rect(3).get_center())
		check(navigation.waypoint_key == "gate1" and not navigation.overview.visible and not sector.paused, "Clicking M4 from M1 selects the first gate on its route")
	# Keyboard selection follows the same travel action as image-card clicks.
	await tap_key(KEY_M)
	navigation.tabs.current_tab = 1
	await sync_physics()
	navigation.network_plot.grab_focus()
	await tap_key(KEY_RIGHT)
	check(navigation.network_plot.keyboard_map == 1, "Arrow keys select the next illustrated map")
	await tap_key(KEY_ENTER)
	check(navigation.waypoint_key == "gate1" and not navigation.overview.visible, "Enter sets the selected map's gate waypoint")
	sector.player.position = SectorMaps.gate_position(0, 1)
	sector.session.jump_until[1] = Time.get_ticks_msec() + 2000
	await tap_key(KEY_J)
	check(sector.map_id == 0 and sector.map_scenery.keys() == [0], "Rejected first jump does not build an unvisited map")
	check(not sector.session.jump_pending and not is_instance_valid(sector.session.jump_cover), "Rejected first jump clears its transit cover")
	for destination in [1, 2, 3, 2, 1, 3, 1, 0]:
		var source := sector.map_id
		sector.player.position = SectorMaps.gate_position(source, destination) + Vector3(0, 0, 42)
		sector.player.look_at(SectorMaps.gate_position(source, destination), Vector3.UP)
		sector.session.jump_until.erase(1)
		sector.select_target(sector.alien)
		sector.auto_fire = true
		sector.autopilot.enabled = true
		await capture("connected-map-gate-m%d-m%d" % [source + 1, destination + 1])
		var first_visit := not sector.map_scenery.has(destination)
		var jump_started := Time.get_ticks_usec()
		await tap_key(KEY_J)
		print("SCENERY_JUMP=" + JSON.stringify({"source": source + 1, "destination": destination + 1, "first_visit": first_visit, "jump_ms": (Time.get_ticks_usec() - jump_started) / 1000.0, "static_bytes": OS.get_static_memory_usage(), "video_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)}))
		check(sector.map_id == destination and sector.player.map_id == destination and sector.aliens.size() == 5, "Jump input follows the reciprocal M%d-M%d gate" % [source + 1, destination + 1])
		check(sector.target == null and not sector.auto_fire and not sector.autopilot.enabled and sector.player.velocity.is_zero_approx(), "Offline transfer resets flight and combat intent")
		check(SectorMaps.protected(sector.player), "Offline arrival remains protected")
		check(sector.map_scenery.has(destination), "Gate entry builds destination scenery")
		await check_map_interactions(destination)
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
	# Inspect each enlarged M3/M4 type at the same ordinary combat distance.
	for map in [2, 3]:
		sector.player.map_id = map
		sector.activate_map(map)
		var captured: Array[String] = []
		for enemy: Alien in sector.aliens.values():
			if enemy.kind in captured:
				continue
			captured.append(enemy.kind)
			sector.player.position = enemy.position + Vector3(0, 0, 90)
			sector.player.look_at(enemy.position, Vector3.UP)
			enemy.look_at(sector.player.position, Vector3.UP)
			sector.select_target(enemy)
			await capture("connected-map-%s-enlarged" % enemy.kind.to_lower())
		check(captured.size() == 2, "Rendered flight inspects both stronger M%d types" % (map + 1))
	sector.player.take_damage(sector.player.max_hull + sector.player.max_shield + 1, null)
	sector._physics_process(3.1)
	check(sector.player.alive and sector.map_id == 0 and sector.player.position == Sector.SPAWN_POSITION, "Offline destruction returns to the home station")
	print("Connected-map flight replay: %d passed, %d failed" % [checks - failures, failures])
	sector.free()
	quit(0 if failures == 0 else 1)


func check_map_interactions(map: int) -> void:
	if map in interactions_checked:
		return
	interactions_checked.append(map)
	var body := sector.get_node("Asteroid0") as StaticBody3D if map == 0 else sector.map_terrain[map].get_child(0) as StaticBody3D
	var collider := body.get_children().filter(func(node: Node): return node is CollisionShape3D)[0] as CollisionShape3D
	var radius := (collider.shape as SphereShape3D).radius
	var center := body.global_position
	await sync_physics()
	var hit := sector.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3.FORWARD * (radius + 10), center, 1))
	check(hit.get("collider") == body, "M%d asteroid collision is active after gate entry" % (map + 1))
	sector.autopilot.collect_obstacles()
	var start := center + Vector3(0, 0, radius + 40)
	var finish := center - Vector3(0, 0, radius + 40)
	var job := sector.autopilot.begin_plan(start, finish)
	for slice in range(10000):
		if job.done:
			break
		sector.autopilot.advance_plan(job)
	check(job.done and not job.result.is_empty(), "M%d autopilot plans around real asteroid collision" % (map + 1))
	for point: Vector3 in job.result:
		check(sector.autopilot.segment_clear(start, point), "M%d autopilot detour keeps obstacle clearance" % (map + 1))
		start = point
	var enemy := sector.alien
	var before := enemy.position
	for frame in range(120):
		enemy.fly(1.0 / 60.0, null, Sector.STATION_POSITION)
	check(enemy.position.distance_to(before) > 0.01 and enemy.position.distance_to(SectorMaps.origin(map)) < Sector.MAP_RADIUS, "M%d alien patrol stays active in its map" % (map + 1))
	var destination: int = SectorMaps.GATES[map].keys()[0]
	var gate := SectorMaps.gate_position(map, destination)
	var inward := (SectorMaps.origin(map) - gate).normalized()
	sector.player.position = gate + inward * 140.0
	sector.player.velocity = Vector3.ZERO
	sector.player.look_at(gate, Vector3.UP)
	sector.hud.navigation.waypoint_key = "gate%d" % destination
	sector.set_paused(false)
	sector.autopilot.toggle()
	check(sector.autopilot.enabled, "M%d autopilot enables for its gate waypoint" % (map + 1))
	for frame in range(900):
		sector.player.fly_command(1.0 / 60.0, sector.read_flight_movement(1.0 / 60.0), false)
		if not sector.autopilot.enabled and sector.player.velocity.length() < 1:
			break
		await physics_frame
	check(sector.player.position.distance_to(gate) < SectorMaps.JUMP_RADIUS, "M%d autopilot flies to the real jump range" % (map + 1))
	sector.player.position = SectorMaps.origin(map) + Vector3(0, 180, 120)
	sector.player.look_at(SectorMaps.origin(map) + SectorBackdrop.THEMES[map]["planet"], Vector3.UP)
	await capture("lazy-scenery-m%d" % (map + 1))
