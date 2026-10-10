extends "res://tests/dedicated_server_test.gd"
## Bidirectional travel, map isolation and stale packets over authenticated ENet peers.


func replicate(host: Sector) -> void:
	var expected := host.session.snapshot_sequence + 1
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		host.session.send_snapshot()
		await settle(0.05)
		var complete := true
		for viewport in worlds:
			var peer := viewport.get_child(0) as Sector
			if peer == host or not peer.session.active:
				continue
			for alien_id: int in host.map_rosters[peer.map_id]:
				complete = complete and peer.session.alien_sequences.get(alien_id, -1) >= expected
			for id: int in host.session.ships:
				if id != peer.multiplayer.get_unique_id() and (host.session.ships[id].map_id != peer.map_id or host.session.ships[id].get_meta("docked", false)):
					continue
				complete = complete and peer.session.player_sequences.get(id, -1) >= expected
		if complete:
			return
	check(false, "Current-map snapshots converge")


func travel(server: Sector, client: Sector, destination: int) -> void:
	var id := client.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var source := ship.map_id
	ship.position = SectorMaps.gate_position(source, destination)
	server.session.jump_until.erase(id)
	await replicate(server)
	client.set_paused(false)
	client.session.request_jump()
	await settle()
	check(ship.map_id == destination and client.map_id == destination, "Gate transfers authority and owner from M%d to M%d" % [source + 1, destination + 1])
	check(not client.session.jump_pending and ship.velocity.is_zero_approx() and client.target == null and not client.auto_fire, "Transfer clears intent and finishes acknowledgement")
	check(ship.position.distance_to(SectorMaps.gate_position(destination, source)) <= SectorMaps.JUMP_RADIUS and SectorMaps.protected(ship), "Arrival is beside the reciprocal gate and protected")
	await replicate(server)
	for enemy: Alien in client.world_aliens.values():
		check(enemy.visible == (enemy.map_id == destination and enemy.alive), "Only current-map aliens are rendered")


func run() -> void:
	var server := make_sector("MapServer", true)
	var first := make_sector("FirstMapPilot")
	var second := make_sector("SecondMapPilot")
	var late := make_sector("LateMapPilot")
	var clients: Array[Sector] = [first, second, late]
	check(server.world_aliens.size() == 20 and server.map_rosters.size() == 4, "Four bounded maps contain five alien slots each")
	var gates := 0
	for map: int in SectorMaps.GATES:
		for destination: int in SectorMaps.GATES[map]:
			gates += 1
			check(SectorMaps.GATES[destination].has(map), "Every gate has a reciprocal return gate")
			check(SectorMaps.GATES[map][destination].length() + SectorMaps.PROTECTION_RADIUS < Sector.MAP_RADIUS, "Gate protection remains inside safe space")
	check(gates == 8 and not SectorMaps.GATES[0].has(2) and not SectorMaps.GATES[0].has(3), "Approved topology contains exactly eight gates")
	for enemy: Alien in server.world_aliens.values():
		check(server.alien_home_clear(enemy.home_position, enemy), "Alien homes avoid gates, station and colliders")
		check(not CargoResources.roll(enemy.kind).is_empty(), "Every alien type has resource loot")
	for property: String in ["hull", "shield", "damage", "reward"]:
		check(Alien.TYPES["Marauder"][property] > Alien.TYPES["Raider"][property] and Alien.TYPES["Ravager"][property] > Alien.TYPES["Warden"][property], "All new-map encounters increase %s between tiers" % property)
	for index in range(2):
		clients[index].client_only = true
		clients[index].session.credential_id = "pilot%d" % index
		clients[index].session.credential_token = test_token(index)
		clients[index].session.join("127.0.0.1", test_port(24683))
	await settle(0.6)
	check(server.session.ships.size() == 2, "Two authenticated pilots connect")
	if server.session.ships.size() != 2:
		await finish()
		return
	await replicate(server)
	for client in [first, second]:
		client.session.launch()
	await settle()
	await replicate(server)
	var id := first.multiplayer.get_unique_id()
	var other_id := second.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var combat := server.session.combat
	ship.set_meta("docked", true)
	check(not server.session.jump(id, 0, 1).is_empty(), "Docked pilots cannot request travel")
	ship.set_meta("docked", false)
	ship.alive = false
	check(not server.session.jump(id, 0, 1).is_empty(), "Dead pilots cannot request travel")
	ship.alive = true
	check(not server.session.jump(id, 0, 2).is_empty(), "Authority rejects a nonexistent direct M1-M3 gate")
	check(not server.session.jump(id, 0, 1).is_empty(), "Authority rejects distant jump requests")
	ship.hull -= 123
	ship.shield -= 456
	ship.energy = 63
	var resources := {"promerium": 7}
	combat.cargo_holds[id]["starter"] = resources.duplicate()
	var ammo := ship.ammo.duplicate()
	var hull := ship.hull
	var shield := ship.shield
	var old_visit := first.player.map_visit
	var old_alien := combat.pack_alien(server.alien)
	await travel(server, first, 1)
	check(ship.hull == hull and ship.shield == shield and ship.energy == 63 and ship.ammo == ammo and combat.cargo_holds[id]["starter"] == resources, "Jump preserves health, boost, ammunition and cargo")
	check(not server.session.jump(id, combat.records[id]["life"], 0).is_empty(), "Authority enforces jump cooldown")
	check(not first.repair_blocker().is_empty(), "Station services are unavailable on M2")
	check(not first.session.ships[other_id].visible and not second.session.ships[id].visible, "Pilots on different maps are hidden")
	first.session.snapshot({}, old_alien, 999999, old_visit)
	first.session.combat.loot_changed(999, {"map": 0, "position": Vector3.ZERO, "resources": {"prometium": 1}}, old_visit)
	var effect_count := first.get_child_count()
	first.session.combat.show_laser(first.player.position, first.player.position + Vector3.FORWARD * 50, true, "x1", old_visit)
	first.session.combat.show_explosion(first.player.position, 10, old_visit)
	first.session.combat.ammo_snapshot(PackedInt32Array(), 999999, {}, old_visit)
	check(first.get_child_count() == effect_count and first.player.ammo == ammo, "Delayed effects and owner ammunition cannot enter the new visit")
	check(first.world_aliens[0].snapshot_goal.is_empty() and not first.loot.drops.has(999), "Delayed world snapshots and loot from a prior visit are discarded")
	first.session.command_flight.rpc_id(1, Vector3.ONE, Vector3.ZERO, false, true, 0, 0, 0)
	await settle(0.06)
	check(not server.session.commands.has(id), "Prior-flight movement and fire cannot cross the gate")
	var enemy: Alien = server.map_rosters[1][100]
	var home := enemy.home_position
	enemy.position = ship.position + Vector3(0, 0, -100)
	enemy.home_position = enemy.position
	check(ship.firing_blocker(enemy) == "STATION PROTECTION" and enemy.firing_blocker(ship) == "STATION PROTECTION" and ship.rockets.target_blocker(enemy, "r-310") == "STATION PROTECTION", "Gate protection blocks lasers and rockets in both directions")
	var protected_health := enemy.hull + enemy.shield
	enemy.take_damage(1000, ship)
	check(enemy.hull + enemy.shield == protected_health and combat.choose_target(enemy) == null, "Protected pilots cannot damage or aggro aliens")
	enemy.position = home
	enemy.home_position = home
	var same_position := enemy.position
	var other := server.session.ships[other_id]
	other.position = same_position + Vector3(0, 0, 10)
	check(combat.choose_target(enemy) == null, "Map membership prevents aggro even with overlapping coordinates")
	var health := enemy.hull + enemy.shield
	enemy.take_damage(10000, other)
	check(enemy.hull + enemy.shield == health, "Cross-map direct damage is rejected")
	other.position = Sector.SPAWN_POSITION
	ship.position = enemy.position + Vector3(0, 0, 50)
	ship.rotation = Vector3.ZERO
	await physics_frame
	await replicate(server)
	first.select_target(first.aliens[100])
	await fire_at(first, first.aliens[100])
	combat.tick(0.01)
	check(enemy.shield < enemy.max_shield and enemy.contributors == [id], "New-map aliens receive authorized laser fire")
	enemy.take_damage(enemy.hull + enemy.shield + 1, ship)
	await replicate(server)
	check(combat.records[id]["credits"] == Alien.TYPES["Skirmisher"]["reward"] and first.loot.drops.size() == 1 and second.loot.drops.is_empty(), "New alien rewards and loot remain in their map")
	var other_hold: Dictionary = combat.cargo_holds[other_id]["starter"].duplicate()
	other.position = server.loot.drops.values()[0]["position"]
	combat.collect_loot()
	check(combat.cargo_holds[other_id]["starter"] == other_hold, "Loot cannot be collected from another map at overlapping coordinates")
	other.position = Sector.SPAWN_POSITION
	await travel(server, second, 1)
	check(first.session.ships[other_id].visible and second.session.ships[id].visible, "Pilots become visible together on M2")
	var rocket_target: Alien = server.map_rosters[1][101]
	ship.position = rocket_target.position + Vector3(0, 0, 50)
	ship.rotation = Vector3.ZERO
	await physics_frame
	check(ship.rockets.fire_single(rocket_target).is_empty() and not ship.rockets.pending.is_empty(), "Authority launches a rocket before transfer")
	var rocket_health := rocket_target.hull + rocket_target.shield
	await travel(server, first, 2)
	ship.rockets.tick(1)
	check(ship.rockets.pending.is_empty() and rocket_target.hull + rocket_target.shield == rocket_health, "A rocket launched on M2 cannot hit after its owner jumps to M3")
	late.client_only = true
	late.session.credential_id = "pilot2"
	late.session.credential_token = test_token(2)
	late.session.join("127.0.0.1", test_port(24683))
	await settle(0.5)
	await replicate(server)
	check(late.session.active and late.map_id == 0 and late.session.ships[id].map_id == 2 and not late.session.ships[id].visible, "Late join starts on M1 and knows off-map roster membership")
	for destination in [3, 2, 1, 3, 1, 0]:
		await travel(server, first, destination)
	check(first.loot.drops.is_empty(), "Returning home removes the previous map's loot presentation")
	var current_alien := first.alien.position
	first.session.snapshot({}, old_alien, 999999, old_visit)
	check(first.alien.position == current_alien, "Returning to M1 still rejects packets from the initial M1 visit")
	await travel(server, first, 1)
	await travel(server, first, 3)
	ship.take_damage(ship.max_hull + ship.max_shield + 1, null)
	combat.records[id]["respawn"] = 0.001
	combat.tick(0.01)
	await settle()
	await replicate(server)
	check(first.map_id == 0 and ship.map_id == 0 and ship.alive and first.player.alive and ship.position == combat.records[id]["spawn"], "Death on M4 rescues the pilot to the home station")
	await travel(server, first, 1)
	await travel(server, first, 2)
	first.session.quit_to_menu()
	await settle()
	await replicate(server)
	check(first.preflight and first.map_id == 0 and ship.map_id == 0 and ship.get_meta("docked", false), "Quit to station from another map returns home")
	first.session.launch()
	await settle()
	await replicate(server)
	check(first.map_id == 0 and not first.preflight and not ship.get_meta("docked", false), "Relaunch starts on home map")
	for viewer in clients:
		viewer.session.disconnect_session("Map validation complete")
	await settle()
	server.session.disconnect_session("Validation complete")
	await finish()


func fire_at(client: Sector, enemy: Alien) -> void:
	client.session.command_flight.rpc_id(1, Vector3.ZERO, Vector3.ZERO, false, true, int(client.player.get_meta("life", 0)), enemy.life, enemy.alien_id)
	await settle(0.06)
