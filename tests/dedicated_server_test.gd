extends "res://tests/network_combat_test.gd"
## A server has no local pilot. Exercise all ten slots and combat with real ENet clients.


func replicate(host: Sector) -> void:
	var expected := host.session.snapshot_sequence + 1
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		host.session.send_snapshot()
		await settle(0.05)
		var complete := true
		for viewport in worlds:
			var peer: Sector = viewport.get_child(0)
			if peer == host or not peer.session.active:
				continue
			for id: int in host.session.ships:
				if peer.session.player_sequences.get(id, -1) < expected:
					complete = false
		if complete:
			return
	check(false, "All ten clients must receive fresh state within the convergence timeout")


func run() -> void:
	var server := make_sector("Dedicated", true)
	check(server.player == null and server.hud == null and server.session.menu == null, "Server creates no local player, HUD or menu")
	check(server.session.active and server.session.ships.is_empty(), "Dedicated server starts with zero pilots")
	check(server.find_children("*", "MeshInstance3D", true, false).is_empty(), "Server creates no render meshes")
	var time := server.alien.patrol_time
	server.session.tick(0.1)
	check(server.alien.patrol_time > time, "Empty server continues simulating without a host pilot")
	var clients: Array[Sector] = []
	for index in range(10):
		var client := make_sector("Client%d" % index)
		client.session.credential_id = "pilot%d" % index
		client.session.credential_token = test_token(index)
		clients.append(client)
		check(client.session.join("127.0.0.1", 24683) == OK, "Client %d begins joining" % index)
	await settle(0.5)
	check(server.session.ships.size() == 10 and not server.session.ships.has(1), "All ten slots belong to clients, with no ghost host ship")
	if server.session.ships.size() != 10:
		finish()
		return
	var deadline := Time.get_ticks_msec() + 8000
	while clients.any(func(peer: Sector): return not peer.session.received_snapshot) and Time.get_ticks_msec() < deadline:
		await replicate(server)
	for client in clients:
		check(client.session.ships.size() == 10 and client.session.received_snapshot, "Client receives full ten-player roster and snapshot")
	check(server.find_children("*", "Camera3D", true, false).is_empty(), "Remote server pilots create no cameras")
	check(collision_geometry(server) == collision_geometry(clients[0]), "Headless station and asteroid colliders match the rendered client's geometry")
	var client := clients[0]
	var id := client.multiplayer.get_unique_id()
	var remote := server.session.ships[id]
	var combat := server.session.combat
	var alien := server.alien
	remote.position = Vector3(0, 60, 0)
	alien.position = Vector3(0, 60, -100)
	var start := remote.position
	client.session.command_flight.rpc_id(1, Vector3(0, 0, -1), Vector3.ZERO, true)
	await settle()
	server.session.tick(0.1)
	check(remote.position.z < start.z and remote.energy < 100, "Dedicated server simulates client movement and boost")
	await physics_frame
	var initial := alien.shield
	await send_fire(client)
	combat.tick(0.01)
	check(alien.shield < initial and id in combat.contributors, "Dedicated server validates client fire and contribution")
	alien.take_damage(999, remote)
	await replicate(server)
	check(client.credits == 75 and client.kills == 1, "Dedicated server awards the full pool to the sole contributor")
	check(clients[1].credits == 0, "Uninvolved clients receive no reward")
	remote.take_damage(80, alien)
	remote.position = combat.records[id]["spawn"]
	remote.velocity = Vector3.ZERO
	remote.time_since_hit = 6
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	await replicate(server)
	check(client.credits == 73 and client.player.hull == 120, "Repair is charged and confirmed by the dedicated server")
	check(clients[1].session.ships[id].hull == 120, "An observing client receives repaired health")
	remote.take_damage(999, alien)
	await replicate(server)
	check(not client.player.alive and client.credits == 63, "Dedicated server applies destruction and rescue fee")
	combat.tick(3.1)
	await replicate(server)
	check(client.player.alive and client.player.position.is_equal_approx(remote.position), "Dedicated server respawns the player")
	var sequence := server.session.snapshot_sequence + 2
	var saved: Dictionary = client.session.goals[id].duplicate()
	var newer := saved.duplicate()
	newer["shield"] = 20.0
	client.session.snapshot({id: newer}, combat.pack_alien(), sequence)
	client.session.snapshot({id: saved}, combat.pack_alien(), sequence - 1)
	check(client.player.shield == 20.0, "An older chunk cannot roll back a newer player snapshot")
	var other_id := clients[1].multiplayer.get_unique_id()
	var other: Dictionary = client.session.goals[other_id].duplicate()
	other["shield"] = 30.0
	client.session.snapshot({other_id: other}, combat.pack_alien(), sequence - 1)
	check(client.session.ships[other_id].shield == 30.0, "An out-of-order chunk for a different pilot is still applied")
	server.session.snapshot_sequence = sequence
	await replicate(server)
	check(client.player.shield == remote.shield, "Subsequent server snapshots converge after reordered chunks")
	for peer in clients:
		peer.session.disconnect_session("Test disconnect")
	await settle(0.5)
	check(server.session.active and server.session.ships.is_empty() and combat.records.is_empty(), "Last player leaving keeps the server running and clears player state")
	server.session.tick(13)
	check(server.alien.alive, "Alien respawns on an empty server")
	client.client_only = true
	client.session.join("127.0.0.1", 24683)
	await settle(0.5)
	await replicate(server)
	check(client.session.ships.size() == 1 and client.session.received_snapshot, "A player reconnects to the still-running server")
	check(client.credits == 63, "Reconnect restores the authenticated pilot's saved credits")
	server.session.disconnect_session("Test shutdown")
	await settle(0.5)
	check(not client.session.active and client.session.menu.visible, "Server shutdown returns client to connection menu")
	var before := client.alien.patrol_time
	client.set_paused(false)
	client._physics_process(1.0)
	check(client.alien.patrol_time == before, "Disconnected normal client cannot start a separate solo simulation")
	print("Dedicated server checks complete")
	finish()


func collision_geometry(sector: Sector) -> Dictionary:
	var result: Dictionary = {}
	for body: StaticBody3D in sector.find_children("*", "StaticBody3D", true, false):
		for collider: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
			result[str(body.global_position)] = collider.shape.get_debug_mesh().get_aabb()
	return result
