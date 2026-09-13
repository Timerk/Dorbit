extends "res://tests/dedicated_server_test.gd"
## Independent encounters over real ENet peers, including life changes and late joins.


func fire_at(client: Sector, enemy: Alien, life: int = -1) -> void:
	client.session.command_flight.rpc_id(1, Vector3.ZERO, Vector3.ZERO, false, true,
		int(client.player.get_meta("life", 0)), enemy.life if life < 0 else life, enemy.alien_id)
	await settle(0.06)


func run() -> void:
	var server := make_sector("HuntServer", true)
	var first := make_sector("First")
	var second := make_sector("Second")
	var late := make_sector("Late")
	var clients: Array[Sector] = [first, second, late]
	for index in range(2):
		clients[index].session.credential_id = "pilot%d" % index
		clients[index].session.credential_token = test_token(index)
		clients[index].session.join("127.0.0.1", 24683)
	await settle(0.5)
	check(server.session.ships.size() == 2, "Two authenticated pilots join the hunt")
	if server.session.ships.size() != 2:
		await finish()
		return
	var combat := server.session.combat
	var first_id := first.multiplayer.get_unique_id()
	var second_id := second.multiplayer.get_unique_id()
	var p := server.session.ships[first_id]
	var q := server.session.ships[second_id]
	var scout := server.aliens[1]
	var heavy := server.aliens[4]
	p.position = scout.position + Vector3(0, 0, 90)
	q.position = heavy.position + Vector3(0, 0, 90)
	await physics_frame
	await replicate(server)
	check(server.aliens.size() == 5 and first.aliens.size() == 5, "Bounded roster contains two Scouts, two Sentinels and one Heavy")
	for enemy: Alien in server.aliens.values():
		check(var_to_bytes([{}, combat.pack_alien(enemy), 1]).size() < 1200, "Alien snapshot fits below the packet budget")
		check(not first.aliens[enemy.alien_id].simulation_authority, "Clients cannot simulate any alien")
	first.session.command_flight.rpc_id(1, Vector3.ZERO, Vector3.ZERO, false, true, 0, 0, 999)
	await settle(0.06)
	check(not combat.remote_firing(first_id), "Unknown alien IDs cannot fire or claim a reward")
	await fire_at(first, scout)
	await fire_at(second, heavy)
	combat.tick(0.01)
	check(scout.shield < scout.max_shield and heavy.shield < heavy.max_shield, "Two simultaneous fire intents damage independent aliens")
	check(scout.contributors == [first_id] and heavy.contributors == [second_id], "Contributions belong only to the damaged alien")
	check(combat.choose_target(scout) == p and combat.choose_target(heavy) == q, "Aliens independently choose nearby eligible opponents")
	check(scout.engaged and heavy.engaged, "Both encounters run at the same time")
	await replicate(server)
	second.select_target(second.aliens[4])
	second.auto_fire = true
	var heavy_health := heavy.hull + heavy.shield
	var heavy_life := heavy.life
	scout.take_damage(999, p)
	await replicate(server)
	check(combat.records[first_id]["credits"] == 30 and combat.records[second_id]["credits"] == 0, "Scout pays only its contributor")
	check(heavy.hull + heavy.shield == heavy_health and heavy.life == heavy_life and heavy.contributors == [second_id], "Scout death preserves Heavy health, life and contributions")
	check(second.target == second.aliens[4] and second.auto_fire and combat.remote_firing(second_id), "Another alien's death leaves Heavy targeting and fire active")
	var timer := scout.respawn
	# Crossing the leash invalidates the life before any queued lethal shot can land.
	heavy.position = heavy.home_position + Vector3(float(heavy.tuning()["leash"]) + 1, 0, 0)
	heavy.take_damage(9999, q)
	check(heavy.alive, "Lethal damage outside the leash cannot grant a kill")
	combat.tick(0.01)
	check(heavy.returning and heavy.life == heavy_life + 1 and heavy.contributors.is_empty(), "Leash reset clears only that life's contributions")
	check(heavy.hull == heavy.max_hull and heavy.shield == heavy.max_shield and scout.respawn < timer, "Reset restores health without restarting another respawn")
	heavy.take_damage(9999, q)
	check(heavy.alive and combat.records[second_id]["credits"] == 0, "Returning alien rejects damage and rewards")
	await replicate(server)
	check(second.target == null and not second.auto_fire, "Returning target clears on its client")
	late.session.credential_id = "pilot2"
	late.session.credential_token = test_token(2)
	late.session.join("127.0.0.1", 24683)
	await settle(0.5)
	await replicate(server)
	for enemy: Alien in server.aliens.values():
		var copy := late.aliens[enemy.alien_id]
		check(copy.kind == enemy.kind and copy.life == enemy.life and copy.alive == enemy.alive and copy.returning == enemy.returning and copy.hull == enemy.hull and copy.shield == enemy.shield and copy.respawn == enemy.respawn and copy.position.is_equal_approx(enemy.position), "Late join receives current identity, position, health, reset and respawn state")
	# Reject stale snapshots independently; another entity's older chunk is still useful.
	var newer := combat.pack_alien(heavy)
	newer["hull"] = 200.0
	var sequence := server.session.snapshot_sequence + 2
	late.session.snapshot({}, newer, sequence)
	late.session.snapshot({}, combat.pack_alien(heavy), sequence - 1)
	late.session.snapshot({}, combat.pack_alien(scout), sequence - 1)
	check(late.aliens[4].hull == 200 and not late.aliens[1].alive, "Reordered alien chunks converge independently")
	server.session.snapshot_sequence = sequence
	p.position = Sector.STATION_POSITION
	for step in range(1800):
		if not heavy.returning:
			break
		await physics_frame
		combat.tick(1.0 / 60.0)
	check(heavy.position.distance_to(heavy.home_position) <= 3.0, "Returning alien actually flies back to its territory")
	check(not heavy.returning and heavy.available(), "Alien becomes huntable again only at home")
	await fire_at(second, heavy, heavy_life)
	check(not combat.remote_firing(second_id), "Old fire intent cannot cross a retreat reset")
	# Abandoning an active fight for station protection also resets eligibility.
	q.position = Sector.STATION_POSITION
	var shield := q.shield
	heavy.try_fire(q)
	check(q.shield == shield, "Alien cannot attack a station-protected pilot")
	heavy.take_damage(9999, q)
	check(heavy.alive and heavy.contributors.is_empty(), "Protected pilot cannot farm an alien")
	p.position = heavy.position + Vector3(0, 0, 90)
	heavy.take_damage(1, p)
	heavy.engaged = true
	p.position = Sector.STATION_POSITION
	combat.tick(0.01)
	check(heavy.contributors.is_empty(), "Abandoned encounter loses reward eligibility")
	# A new life rewards only new contributions, including equal integer splitting.
	heavy.position = heavy.home_position
	combat.tick(0.01)
	p.position = heavy.position + Vector3(0, 0, 90)
	q.position = heavy.position + Vector3(20, 0, 90)
	heavy.take_damage(1, p)
	p.take_damage(9999, heavy)
	heavy.take_damage(9999, q)
	check(combat.records[first_id]["credits"] == 110 and combat.records[second_id]["credits"] == 90, "Heavy pool splits equally, including a contributor awaiting rescue after its fee")
	heavy.take_damage(9999, q)
	check(combat.records[second_id]["credits"] == 90, "Repeated destruction cannot pay twice")
	# No connected pilots are needed to restore the bounded population.
	for client in clients:
		client.session.disconnect_session("Empty-sector check")
	await settle(0.4)
	for step in range(25):
		server.session.tick(1.0)
	check(server.session.ships.is_empty() and server.aliens.size() == 5, "Empty server keeps the fixed population bound")
	for enemy: Alien in server.aliens.values():
		check(enemy.alive and enemy.contributors.is_empty(), "Every slot respawns without stale contributors")
	check(scout.life == 1 and heavy.life == 3, "Each death respawns once and retreat resets increment only their own life")
	var blocked := server.aliens[0]
	blocked.position = blocked.home_position + Vector3(240, 0, 0)
	blocked.check_retreat(null)
	SectorVisuals.add_box_collider(server, blocked.position, Vector3(30, 30, 30))
	await physics_frame
	blocked.fly(0.01, null, Sector.STATION_POSITION)
	check(blocked.returning, "Blocked return stays unavailable")
	blocked.fly(Alien.RETURN_TIMEOUT, null, Sector.STATION_POSITION)
	check(blocked.available() and blocked.position.is_equal_approx(blocked.home_position) and blocked.contributors.is_empty(), "Return timeout restores a blocked slot safely at home")
	# Target controls use nearest-first, then stable slot order.
	var control := first
	(control.get_parent() as SubViewport).size = Vector2i(1280, 720)
	control.player.position = Sector.SPAWN_POSITION
	for enemy: Alien in control.aliens.values():
		enemy.position = enemy.home_position
		enemy.returning = false
		enemy.reset_health()
	control.cycle_target()
	check(control.target == control.aliens[1], "First Tab selects the nearest available enemy")
	var visited: Array[int] = []
	for step in range(5):
		visited.append((control.target as Alien).alien_id)
		control.cycle_target()
	check(visited.size() == 5 and visited.count(1) == 1 and control.target == control.aliens[1], "Tab cycles all nearby aliens in a stable order")
	control.aliens[1].returning = true
	control.validate_target()
	check(control.target == null and not control.auto_fire, "Unavailable target clears immediately")
	control.select_target(control.aliens[0])
	control.player.position = Vector3(0, 0, 699)
	control.validate_target()
	check(control.target == null, "Out-of-range target clears")
	control.player.position = Vector3(0, 100, 0)
	control.player.rotation = Vector3.ZERO
	control.aliens[2].position = Vector3(0, 100, -80)
	control.aliens[2].returning = false
	await physics_frame
	await process_frame
	control.pick_target(control.player.camera.unproject_position(control.aliens[2].global_position))

	check(control.target == control.aliens[2], "Left click selects the alien under the camera ray")
	control.aliens[2].alive = false
	control.validate_target()
	check(control.target == null, "Destroyed click target clears")
	server.session.disconnect_session("Complete")
	await finish()
