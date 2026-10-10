extends "res://tests/dedicated_server_test.gd"
## Radiation, randomized lives and 3D navigation through real authoritative peers.


func run() -> void:
	var server := make_sector("MapServer", true)
	server.spawn_rng.seed = 84021
	var client := make_sector("MapClient")
	var late := make_sector("MapLate")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24683))
	await settle(0.5)
	check(server.session.ships.size() == 1, "Authenticated map pilot connects")
	if server.session.ships.size() != 1:
		await finish()
		return
	var id := client.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var enemy := server.aliens[1]
	var above := false
	var below := false
	var front := false
	var back := false
	var clearance := SphereShape3D.new()
	clearance.radius = 35.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = clearance
	query.collision_mask = 1
	for roll in range(100):
		server.relocate_alien(enemy)
		var point := enemy.home_position
		query.transform = Transform3D(Basis.IDENTITY, point)
		var clear := server.get_world_3d().direct_space_state.intersect_shape(query).is_empty()
		clear = clear and point.length() + float(enemy.tuning()["leash"]) < Sector.MAP_RADIUS
		clear = clear and point.distance_to(Sector.STATION_POSITION) > float(enemy.tuning()["detection"]) + Sector.PROTECTION_RADIUS
		for other: Alien in server.aliens.values():
			clear = clear and (other == enemy or point.distance_to(other.home_position) >= 180)
		check(clear, "Random home leaves actual colliders, station, neighbors and full leash clear")
		above = above or point.y > 150
		below = below or point.y < -150
		front = front or point.z < -150
		back = back or point.z > 150
	check(above and below and front and back, "Homes fill three dimensions on both sides of the station")
	var home := enemy.home_position
	ship.position = home + Vector3(0, 0, 50)
	enemy.take_damage(enemy.max_hull + enemy.max_shield + 1, ship)
	server.session.combat.tick(float(enemy.tuning()["respawn"]) + 0.1)
	check(enemy.alive and enemy.life == 1 and enemy.home_position != home, "Death respawns one new life at a new random home")
	check(server.aliens.size() == 5 and enemy.contributors.is_empty(), "Respawn preserves bounded roster and clears contributions")
	await replicate(server)
	check(client.aliens[1].home_position == enemy.home_position, "New random home replicates to connected client")
	late.session.credential_id = "pilot1"
	late.session.credential_token = test_token(1)
	late.session.join("127.0.0.1", test_port(24683))
	await settle(0.5)
	await replicate(server)
	check(late.aliens[1].home_position == enemy.home_position and late.aliens[1].life == enemy.life, "Late join receives current home and life")
	check(var_to_bytes([{}, server.session.combat.pack_alien(enemy), 1]).size() < 1200, "Random-home snapshot stays below ENet packet budget")

	ship.reset_health()
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		ship.position = direction * (Sector.MAP_RADIUS - 1)
		server.tick_radiation(ship, 1)
		check(ship.radiation_exposure == 0, "Inside sphere is safe along every axis")
		ship.position = direction * (Sector.MAP_RADIUS + 1)
		var previous := ship.hull + ship.shield
		server.tick_radiation(ship, 1)
		check(ship.radiation_exposure == 1 and ship.hull + ship.shield < previous, "Outside sphere takes radiation along every axis")
	ship.reset_health()
	ship.position = Vector3(0, Sector.MAP_RADIUS + 30, 0)
	ship.velocity = Vector3(0, 10, 0)
	server.session.tick(0.1)
	check(ship.position.y > Sector.MAP_RADIUS and ship.velocity.y > 0, "Authoritative movement crosses edge without clamping or stopping")
	await replicate(server)
	check(is_equal_approx(client.player.radiation_exposure, ship.radiation_exposure), "Exposure and health replicate from server")
	client.set_paused(true)
	var health_before := ship.hull + ship.shield
	server.session.tick(1)
	check(ship.hull + ship.shield < health_before, "A client menu does not pause radiation on the server")
	var local_health := client.player.hull
	client.tick_radiation(client.player, 10)
	check(client.player.hull == local_health, "Client cannot apply radiation damage")
	ship.reset_health()
	ship.position = Vector3(0, 1300, 0)
	server.tick_radiation(ship, 1)
	var after_first := ship.hull + ship.shield
	server.tick_radiation(ship, 1)
	check(after_first - ship.hull - ship.shield > ship.max_hull + ship.max_shield - after_first, "Second second deals more damage than first")
	var combined := ship.hull + ship.shield
	ship.reset_health()
	server.tick_radiation(ship, 2)
	check(is_equal_approx(combined, ship.hull + ship.shield), "Damage integral is independent of simulation step size")
	ship.position = Vector3(0, 1190, 0)
	server.tick_radiation(ship, 0.1)
	check(ship.radiation_exposure == 0, "Re-entry immediately resets exposure")
	ship.reset_health()
	ship.position = Vector3(0, 1300, 0)
	server.tick_radiation(ship, 30)
	check(not ship.alive and server.session.combat.records[id]["respawn"] > 0, "Prolonged exposure enters normal authoritative rescue")
	server.session.combat.tick(3.1)
	check(ship.alive and ship.position.distance_to(Sector.STATION_POSITION) < 75 and ship.radiation_exposure == 0, "Rescue returns pilot safely with exposure reset")
	await replicate(server)
	check(client.player.alive and client.player.radiation_exposure == 0, "Rescue state reaches owner")
	check(var_to_bytes([{id: server.session.combat.pack_player(id)}, {}, 1]).size() < 1200, "Radiation player state stays below packet budget")
	check(FlightNavigation.compass_point(Vector3.FORWARD).is_equal_approx(Vector2.ZERO), "Forward destination centers the compass")
	check(FlightNavigation.compass_point(Vector3.BACK).is_equal_approx(Vector2.DOWN), "Behind destination stays on compass rim")
	(client.get_parent() as SubViewport).size = Vector2i(960, 600)
	client.player.position = Vector3(0, 100, 0)
	client.player.rotation = Vector3.ZERO
	client.aliens[1].position = Vector3(0, 100, -2200)
	await physics_frame
	await process_frame
	client.pick_target(client.player.camera.unproject_position(client.aliens[1].global_position))
	check(client.target == client.aliens[1], "Click acquisition spans the enlarged sector beyond the old ray length")
	server.session.disconnect_session("Complete")
	await finish()
