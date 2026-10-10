extends "res://tests/dedicated_server_test.gd"
## Real physics routes and an authenticated client using the normal movement RPC.


class ReplaySector extends Sector:
	func _notification(what: int) -> void:
		# Desktop focus can change while a rendered replay runs unattended.
		# The fixture drives menu cancellation explicitly; production still pauses on focus loss.
		if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
			super._notification(what)


func instantiate_sector() -> Sector:
	var sector := ReplaySector.new()
	sector.name = "Sector"
	return sector


func step_flight(sector: Sector, frames: int = 1200) -> float:
	var distance := 0.0
	for frame in range(frames):
		var before := sector.player.position
		sector.player.fly_command(1.0 / 60.0, sector.read_flight_movement(1.0 / 60.0), false)
		distance += before.distance_to(sector.player.position)
		if not sector.autopilot.enabled and sector.player.velocity.length() < 1:
			break
		await physics_frame
	return distance


func place(sector: Sector, location: Vector3) -> void:
	sector.autopilot.cancel()
	sector.player.position = location
	sector.player.rotation = Vector3.ZERO
	sector.player.velocity = Vector3.ZERO
	sector.player.reset_health()
	sector.set_paused(false)


func press(sector: Sector, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	sector._unhandled_input(event)


func route_length(start: Vector3, points: Array[Vector3]) -> float:
	var length := 0.0
	for point in points:
		length += start.distance_to(point)
		start = point
	return length


func complete_plan(planner: FlightAutopilot, start: Vector3, finish: Vector3, full_graph: bool = false) -> FlightAutopilot.PlanningJob:
	var plan_started := Time.get_ticks_usec()
	var job := planner.begin_plan(start, finish)
	if full_graph and not job.done:
		for index in range(planner.obstacles.size()):
			job.included[index] = true
			job.points.append_array(planner.obstacle_points(planner.obstacles[index], start, finish))
		job.restart_search()
	var slices := 0
	var peak_usec := 0
	while not job.done and slices < 10000:
		var started := Time.get_ticks_usec()
		planner.advance_plan(job)
		peak_usec = maxi(peak_usec, Time.get_ticks_usec() - started)
		slices += 1
	check(job.done, "Sliced planner completes within the work limit")
	if not full_graph:
		print("AUTOPILOT PLAN total_ms=%.3f slices=%d peak_ms=%.3f candidates=%d/%d visibility=%d cache_hits=%d" % [(Time.get_ticks_usec() - plan_started) / 1000.0, slices, peak_usec / 1000.0, job.included.size(), planner.obstacles.size(), job.visibility_checks, job.cache_hits])
	return job


func planning_checks(sector: Sector) -> void:
	var planner := FlightAutopilot.new()
	planner.sector = sector
	planner.collect_obstacles()
	var rock := sector.get_node("Asteroid0") as Node3D
	var cases: Array[Array] = [
		[rock.position + Vector3(0, 0, 80), rock.position - Vector3(0, 0, 80)],
		[Sector.STATION_POSITION + Vector3(0, 270, 0), Sector.STATION_POSITION + Vector3(0, 0, 50)],
	]
	planner.planning = planner.begin_plan(cases[0][0], cases[0][1])
	planner.collect_obstacles()
	check(planner.planning == null, "Refreshing collision geometry invalidates pending visibility and planning state")
	for points in cases:
		var job := complete_plan(planner, points[0], points[1])
		var full := complete_plan(planner, points[0], points[1], true)
		check(not job.result.is_empty() and absf(route_length(points[0], job.result) - route_length(points[0], full.result)) < 0.01, "Reduced candidates retain the full graph's shortest sampled route")
		check(job.included.size() < planner.obstacles.size(), "Detours exclude irrelevant candidate obstacles")
		var checks_before := job.visibility_checks
		var forward := job.edge_clear(planner, 0, 1)
		var backward := job.edge_clear(planner, 1, 0)
		check(forward == backward and job.visibility_checks <= checks_before + 1, "Visibility is reused in both edge directions")
	var clear := planner.begin_plan(Vector3(400, 250, 0), Vector3(400, 250, -140))
	check(clear.done and clear.result.size() == 1 and clear.points.size() == 2, "Clear routes finish immediately without generating obstacle candidates")
	# Side obstacles cover every direct blocker's corner without intersecting
	# the direct route. Their candidates must be added to connect the graph.
	planner.obstacles = [
		{"box": AABB(Vector3(-10, -10, -90), Vector3(20, 20, 20))},
	]
	for axis in [0, 1]:
		for side in [-1.0, 1.0]:
			var center := Vector3(0, 0, -80)
			center[axis] = side * 11.0
			var size := Vector3(30, 30, 50)
			size[axis] = 4.0
			planner.obstacles.append({"box": AABB(center - size * 0.5, size)})
	var clustered := complete_plan(planner, Vector3.ZERO, Vector3(0, 0, -160))
	var full_cluster := complete_plan(planner, Vector3.ZERO, Vector3(0, 0, -160), true)
	check(not clustered.result.is_empty() and clustered.included.size() > 1 and absf(route_length(Vector3.ZERO, clustered.result) - route_length(Vector3.ZERO, full_cluster.result)) < 0.01, "Detour blockers outside the direct route remain part of shortest-route planning")
	var pending := planner.begin_plan(Vector3.ZERO, Vector3(0, 0, -160))
	planner.advance_plan(pending, 1000000, 1)
	check(not pending.done, "Blocked search can yield after a single work unit")
	planner.planning = pending
	planner.cancel()
	check(planner.planning == null and planner.route.is_empty(), "Cancellation discards pending planning without publishing a stale route")
	planner.obstacles.clear()
	for axis in range(3):
		for side in [-1.0, 1.0]:
			var center := Vector3(0, 0, -100)
			center[axis] += side * 30.0
			var size := Vector3.ONE * 70.0
			size[axis] = 10.0
			planner.obstacles.append({"box": AABB(center - size * 0.5, size)})
	var enclosed := complete_plan(planner, Vector3.ZERO, Vector3(0, 0, -100))
	check(enclosed.result.is_empty() and enclosed.included.size() == planner.obstacles.size(), "Disconnected local graph expands to every obstacle before reporting no route")
	# Boundary/zero-length broad-phase checks must preserve exact clearance.
	planner.collect_obstacles()
	for obstacle in planner.obstacles:
		if obstacle.has("radius"):
			var edge: Vector3 = obstacle["center"] + Vector3.RIGHT * float(obstacle["radius"])
			check(planner.segment_clear(edge, edge) == not planner.obstacle_blocks(edge, edge, obstacle), "Sphere boundary clearance survives the visibility broad phase")
			break


func settle_planning(sector: Sector) -> void:
	for frame in range(1000):
		sector.read_flight_movement(1.0 / 60.0)
		if sector.autopilot.planning == null:
			return
		await physics_frame
	check(false, "Flight planning must complete within 1000 frames")


func run() -> void:
	if "--hud-only" in OS.get_cmdline_user_args():
		await rendered_checks(make_sector("AutopilotHud"))
		await finish()
		return
	if "--network-only" in OS.get_cmdline_user_args():
		await network_checks()
		await finish()
		return
	var sector := make_sector("Autopilot")
	planning_checks(sector)
	if "--planning-only" in OS.get_cmdline_user_args():
		await finish()
		return
	var nav := sector.hud.navigation
	var enemy := sector.aliens[1]
	enemy.position = Vector3(200, 250, -200)
	sector.select_target(enemy)
	place(sector, Vector3(0, 250, 0))
	await physics_frame
	press(sector, "autopilot")
	check(sector.autopilot.enabled and InputMap.has_action("autopilot"), "Rebindable autopilot action enables the selected target")
	var initial := sector.player.position.distance_to(enemy.position)
	var traveled := await step_flight(sector)
	check(sector.autopilot.status == "ARRIVED" and sector.player.position.distance_to(enemy.position) <= 21.1, "Direct travel brakes at 20 m and turns autopilot off")
	check(traveled <= initial - 20 + 1 and sector.player.velocity.length() < 1, "Clear travel follows the shortest straight route and stops")
	check(sector.target == enemy and not sector.auto_fire and sector.player.energy == 100, "Autopilot preserves target without enabling fire or boost")

	for vertical in [Vector3.UP, Vector3.DOWN]:
		place(sector, Vector3(400, 200, 0))
		enemy.position = sector.player.position + vertical * 100
		sector.autopilot.toggle()
		await step_flight(sector)
		check(sector.autopilot.status == "ARRIVED" and sector.player.position.distance_to(enemy.position) < 21.1, "Autopilot reaches a purely vertical destination")

	place(sector, Vector3(400, 200, 0))
	enemy.position = Vector3(400, 200, -160)
	var rock := StaticBody3D.new()
	rock.position = Vector3(400, 200, -80)
	rock.collision_layer = 1
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 16
	collider.shape = sphere
	rock.add_child(collider)
	sector.add_child(rock)
	await physics_frame
	sector.autopilot.toggle()
	var planning_movement := sector.read_flight_movement(1.0 / 60.0)
	check(sector.autopilot.enabled and sector.autopilot.planning != null and planning_movement == Vector3.ZERO, "Blocked flight brakes while planning continues across frames")
	var pending_job := sector.autopilot.planning
	enemy.position.x += 30.0
	sector.read_flight_movement(1.0 / 60.0)
	check(sector.autopilot.planning != pending_job and sector.autopilot.goal.x > 420, "Moving contacts replace a pending plan instead of publishing its stale goal")
	enemy.position.x -= 30.0
	sector.read_flight_movement(1.0 / 60.0)
	Input.action_press("strafe_right")
	sector.read_flight_movement(1.0 / 60.0)
	Input.action_release("strafe_right")
	check(not sector.autopilot.enabled and sector.autopilot.planning == null, "Manual input cancels planning immediately")
	sector.autopilot.toggle()
	var planned := sector.autopilot.plan(sector.player.position, enemy.position + Vector3(0, 0, 20))
	var previous := sector.player.position
	var clear := planned.size() > 1
	for point in planned:
		clear = clear and sector.autopilot.segment_clear(previous, point)
		previous = point
	check(clear, "Blocked straight flight produces a clear sampled shortest detour")
	var route_length := 0.0
	previous = sector.player.position
	for point in planned:
		route_length += previous.distance_to(point)
		previous = point
	check(route_length < 150, "Sampled detour stays close to the shortest tangent route around a single rock")
	var closest := INF
	for frame in range(1500):
		sector.player.fly_command(1.0 / 60.0, sector.read_flight_movement(1.0 / 60.0), false)
		closest = minf(closest, sector.player.position.distance_to(rock.position))
		if not sector.autopilot.enabled:
			break
		await physics_frame
	check(sector.autopilot.status == "ARRIVED" and closest > sphere.radius + 2.2, "Real ship flies around the asteroid without collision and arrives (status=%s, clearance=%.2f, position=%s)" % [sector.autopilot.status, closest, sector.player.position])
	rock.queue_free()
	await physics_frame
	SectorVisuals.add_box_collider(sector, Vector3(400, 200, -80), Vector3(20, 20, 20))
	sector.autopilot.collect_obstacles()
	planned = sector.autopilot.plan(Vector3(400, 200, 0), Vector3(400, 200, -140))
	previous = Vector3(400, 200, 0)
	clear = planned.size() > 1
	for point in planned:
		clear = clear and sector.autopilot.segment_clear(previous, point)
		previous = point
	check(clear, "Expanded box corners provide a clear station-style detour")
	check(sector.autopilot.plan(Vector3(400, 200, 0), Vector3(400, 200, -80)).is_empty(), "An obstructed destination returns no route instead of thrusting into it")
	sector.get_child(sector.get_child_count() - 1).queue_free()
	await physics_frame

	place(sector, Vector3(400, 200, 0))
	enemy.position = Vector3(400, 200, -200)
	sector.autopilot.toggle()
	sector.read_flight_movement(0.1)
	var old_goal := sector.autopilot.goal
	enemy.position += Vector3(30, 20, 0)
	sector.read_flight_movement(0.1)
	check(sector.autopilot.goal.distance_to(old_goal) > 8, "Moving contacts replan their approach")
	old_goal = sector.autopilot.goal
	enemy.position.x += 1
	sector.read_flight_movement(0.1)
	check(sector.autopilot.goal.distance_to(old_goal) > 0.5, "Small target movements also update the final approach")
	Input.action_press("strafe_right")
	var manual := sector.read_flight_movement(0.1)
	Input.action_release("strafe_right")
	check(not sector.autopilot.enabled and manual == Vector3.RIGHT, "Manual thrust cancels and takes over immediately")
	sector.autopilot.toggle()
	press(sector, "steer")
	check(not sector.autopilot.enabled, "Mouse steering cancels autopilot")
	sector.player.release_mouse()
	sector.autopilot.toggle()
	sector.set_paused(true)
	check(not sector.autopilot.enabled, "Opening any flight menu cancels autopilot")
	sector.set_paused(false)
	sector.autopilot.toggle()
	press(sector, "autopilot")
	check(not sector.autopilot.enabled, "Pressing the toggle again disables autopilot")
	sector.autopilot.toggle()
	enemy.alive = false
	sector.validate_target()
	check(not sector.autopilot.enabled and sector.target == null, "Target death cancels autopilot")
	enemy.reset_health()
	sector.select_target(enemy)
	sector.autopilot.toggle()
	sector.select_target(sector.aliens[2])
	check(not sector.autopilot.enabled, "Retargeting cancels autopilot")
	place(sector, Vector3(150, -8, 0))
	nav.choose_contact("station")
	sector.autopilot.toggle()
	await step_flight(sector)
	check(sector.autopilot.status == "ARRIVED" and sector.repair_blocker().is_empty(), "Outpost approach stops clear of station colliders in service range")
	for approach in [Vector3(0, 270, 0), Vector3(0, -140, 0)]:
		place(sector, Sector.STATION_POSITION + approach)
		nav.choose_contact("station")
		sector.autopilot.toggle()
		await settle_planning(sector)
		var approach_clear := sector.autopilot.enabled and not sector.autopilot.route.is_empty()
		previous = sector.player.position
		for point in sector.autopilot.route:
			approach_clear = approach_clear and sector.autopilot.segment_clear(previous, point)
			previous = point
		check(approach_clear and sector.autopilot.goal.distance_to(Sector.STATION_POSITION) < Sector.REPAIR_RADIUS, "Vertical station approach plans around the tower/reactor to a clear service point")
	place(sector, Vector3(0, 1300, 0))
	sector.autopilot.toggle()
	sector.read_flight_movement(0.1)
	check(sector.autopilot.destination_key == "safe" and sector.autopilot.goal.length() < Sector.MAP_RADIUS, "Radiation guidance prioritizes re-entry before the selected destination")
	for frame in range(400):
		sector.player.fly_command(1.0 / 60.0, sector.read_flight_movement(1.0 / 60.0), false)
		if sector.player.position.length() < Sector.MAP_RADIUS - 5:
			break
		await physics_frame
	sector.read_flight_movement(0.1)
	check(sector.autopilot.enabled and sector.autopilot.destination_key == "station", "Safe re-entry resumes the selected destination")
	sector.autopilot.cancel()
	await rendered_checks(sector)
	await network_checks()
	await finish()


func network_checks() -> void:
	var server := make_sector("AutopilotServer", true, 24693)
	var client := make_sector("AutopilotClient")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24693))
	if not await wait_for_pilot(server, client):
		return
	await replicate(server)
	check(client.session.active and server.session.ships.size() == 1, "Authenticated autopilot client connects")
	if server.session.ships.size() == 1:
		var id := client.multiplayer.get_unique_id()
		var ship := server.session.ships[id]
		ship.position = Vector3(400, 250, 0)
		server.aliens[1].position = Vector3(400, 250, -120)
		server.aliens[1].home_position = server.aliens[1].position
		await replicate(server)
		# Replication updates alien interpolation goals, not their visible positions.
		# Start planning only after applying the fixture's freshly relocated target.
		client.session.combat.interpolate(0.1)
		client.select_target(client.aliens[1])
		client.autopilot.toggle()
		var start := ship.position
		for frame in range(90):
			client.session.tick(1.0 / 60.0)
			await physics_frame
			server.session.tick(1.0 / 60.0)
		check(ship.position.z < start.z - 10 and ship.velocity.length() <= ship.cruise_speed + 0.1, "Autopilot moves the authoritative ship using bounded normal flight commands (start=%s, position=%s, velocity=%s, status=%s)" % [start, ship.position, ship.velocity, client.autopilot.status])
		check(ship.energy == 100 and not server.session.commands[id]["boost"], "Server retains flight and boost rules")
		client.hud.navigation.choose_contact("station")
		client.autopilot.toggle()
		check(client.autopilot.enabled and client.target == null, "A station route can run without a combat target")
		client.session.quit_to_menu()
		await replicate(server)
		check(client.preflight and not client.autopilot.enabled, "Returning directly to the docked main menu cancels autopilot")
		client.session.launch_request.rpc_id(1)
		await settle()
		await replicate(server)
		check(not client.preflight and not client.autopilot.enabled, "Relaunch does not resume the previous autopilot route")
		ship.take_damage(ship.max_hull + ship.max_shield + 1, server.aliens[1])
		await replicate(server)
		check(not client.autopilot.enabled and not client.player.alive, "Authoritative destruction cancels autopilot on the client")
		server.session.combat.tick(3.1)
		await replicate(server)
		check(not client.autopilot.enabled and client.player.alive, "Rescue does not restart the cancelled route")
		var friend := make_sector("AutopilotFriend")
		friend.session.credential_id = "pilot1"
		friend.session.credential_token = test_token(1)
		friend.session.join("127.0.0.1", test_port(24693))
		if not await wait_for_pilot(server, friend):
			return
		var friend_id := friend.multiplayer.get_unique_id()
		server.session.ships[friend_id].position = Vector3(400, 250, 0)
		await replicate(server)
		client.session.tick(0.1) # Apply the ordinary remote-ship interpolation before selecting its contact.
		client.hud.navigation.choose_contact("friend%d" % friend_id)
		client.autopilot.toggle()
		client.read_flight_movement(0.1)
		check(client.autopilot.enabled and client.autopilot.destination_key == "friend%d" % friend_id and client.target == null, "A selected friendly contact supplies the flight destination without a combat target (status=%s, paused=%s, waypoint=%s, pilot=%s, friend=%s)" % [client.autopilot.status, client.paused, client.hud.navigation.waypoint_key, client.player.position, client.session.ships[friend_id].position])
		client.player.position = Vector3(0, 1300, 0)
		client.read_flight_movement(0.1)
		check(client.autopilot.destination_key == "safe", "Friendly destinations retain safe re-entry guidance")
		friend.session.disconnect_session("Friendly destination disappears")
		await settle()
		client.read_flight_movement(0.1)
		check(not client.autopilot.enabled, "A missing friendly destination cancels rather than flying to the fallback station")
		client.select_target(client.aliens[1])
		client.autopilot.toggle()
		client.set_paused(true)
		for frame in range(60):
			client.session.tick(1.0 / 60.0)
			await physics_frame
			server.session.tick(1.0 / 60.0)
		check(not client.autopilot.enabled and ship.velocity.length() < 1, "A client menu cancels autopilot and brakes its server ship")
		client.set_paused(false)
		client.autopilot.toggle()
		client.session.disconnect_session("Autopilot disconnect check")
		check(not client.autopilot.enabled, "Disconnect cancels flight assistance")


func wait_for_pilot(server: Sector, client: Sector) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if client.session.active and server.session.ships.has(client.multiplayer.get_unique_id()):
			return true
		await settle(0.05)
	check(false, "Autopilot fixture pilot authenticates on both peers within eight seconds")
	return false


func rendered_checks(sector: Sector) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Put the fixture in the root viewport so the camera and actual HUD are visible.
	var viewport := sector.get_parent()
	worlds.erase(viewport)
	sector.reparent(root)
	viewport.queue_free()
	place(sector, Vector3(0, 200, 0))
	sector.aliens[1].position = Vector3(100, 210, -200)
	sector.select_target(sector.aliens[1])
	await settle(0.1) # Let the reparented root viewport finish layout before routing keyboard input.
	sector.settings.rebind("autopilot", KEY_L)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	check(sector.autopilot.enabled, "Rebound keyboard input toggles autopilot through the real viewport")
	sector.autopilot.cancel()
	sector.settings.configure_input()
	sector.settings.rebind("autopilot", KEY_P)
	for pixels in [Vector2i(960, 600), Vector2i(1440, 900)]:
		root.content_scale_size = pixels
		root.size = pixels
		DisplayServer.window_set_size(pixels)
		await settle(0.1)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_P
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		await process_frame
		check(sector.autopilot.enabled and sector.hud.navigation.autopilot_status.visible, "Keyboard toggle shows the compact autopilot status under the radar")
		sector.player.fly_command(1.0 / 60.0, sector.read_flight_movement(1.0 / 60.0), false)
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://build/validation")
		DirAccess.make_dir_recursive_absolute(directory)
		root.get_texture().get_image().save_png(directory.path_join("autopilot-%d.png" % pixels.x))
		event = event.duplicate()
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		await process_frame
		check(not sector.autopilot.enabled and not sector.hud.navigation.autopilot_status.visible, "Disabling autopilot hides its status")
	sector.queue_free()
	await process_frame
