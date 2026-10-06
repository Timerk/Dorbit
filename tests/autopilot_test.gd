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


func run() -> void:
	if "--network-only" in OS.get_cmdline_user_args():
		await network_checks()
		await finish()
		return
	var sector := make_sector("Autopilot")
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
	client.session.join("127.0.0.1", 24693)
	await settle(0.5)
	await replicate(server)
	check(client.session.active and server.session.ships.size() == 1, "Authenticated autopilot client connects")
	if server.session.ships.size() == 1:
		var id := client.multiplayer.get_unique_id()
		var ship := server.session.ships[id]
		ship.position = Vector3(400, 250, 0)
		server.aliens[1].position = Vector3(400, 250, -120)
		server.aliens[1].home_position = server.aliens[1].position
		await replicate(server)
		client.select_target(client.aliens[1])
		client.autopilot.toggle()
		var start := ship.position
		for frame in range(90):
			client.session.tick(1.0 / 60.0)
			await physics_frame
			server.session.tick(1.0 / 60.0)
		check(ship.position.z < start.z - 10 and ship.velocity.length() <= ship.cruise_speed + 0.1, "Autopilot moves the authoritative ship using bounded normal flight commands")
		check(ship.energy == 100 and not server.session.commands[id]["boost"], "Server retains flight and boost rules")
		ship.take_damage(ship.max_hull + ship.max_shield + 1, server.aliens[1])
		await replicate(server)
		check(not client.autopilot.enabled and not client.player.alive, "Authoritative destruction cancels autopilot on the client")
		server.session.combat.tick(3.1)
		await replicate(server)
		check(not client.autopilot.enabled and client.player.alive, "Rescue does not restart the cancelled route")
		var friend := make_sector("AutopilotFriend")
		friend.session.credential_id = "pilot1"
		friend.session.credential_token = test_token(1)
		friend.session.join("127.0.0.1", 24693)
		await settle(0.5)
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
		var button := sector.hud.navigation.autopilot_button
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		await process_frame
		check(sector.autopilot.enabled and button.button_pressed, "HUD button toggles autopilot through real mouse input")
		sector.player.fly_command(1.0 / 60.0, sector.read_flight_movement(1.0 / 60.0), false)
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://build/validation")
		DirAccess.make_dir_recursive_absolute(directory)
		root.get_texture().get_image().save_png(directory.path_join("autopilot-%d.png" % pixels.x))
		sector.autopilot.cancel()
	sector.queue_free()
	await process_frame
