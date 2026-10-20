extends "res://tests/network_test.gd"
## Authoritative combat exercised through actual client RPCs and host snapshots.


## Turns allowed for loopback ENet to deliver a resent intent. Bounded by
## attempts rather than elapsed time, so slow CI frames cannot exhaust it.
## A server that will reject the intent ends the wait early with its reason.
const RECEIPT_ATTEMPTS := 60


func intent(fire: bool, life: int, encounter: int, target: int = 0, movement := Vector3.ZERO, boost := false, angles := Vector3.ZERO) -> Dictionary:
	return {"movement": movement, "angles": angles, "boost": boost, "fire": fire, "life": life, "encounter": encounter, "target": target}


## Resend each client's unreliable flight intent, as production clients do every
## frame, until the server stores all of them in the same turn. command_flight
## stores a new Dictionary per accepted packet, so a changed reference across this
## turn's server poll marks a receipt of a packet sent after the request, without
## judging freshness by wall-clock age. Callers assert or tick combat before
## another frame can age the receipt past COMMAND_TIMEOUT. Returns false and
## prints per-peer samples if the server never stores the intents.
func deliver_intents(server: Sector, clients: Array[Sector], intents: Array[Dictionary], phase: String = "intent") -> bool:
	var samples: Array[Dictionary] = []
	for attempt in range(1, RECEIPT_ATTEMPTS + 1):
		await process_frame
		for index in range(clients.size()):
			var sent := intents[index]
			clients[index].session.command_flight.rpc_id(1, sent["movement"], sent["angles"], sent["boost"], sent["fire"], sent["life"], sent["encounter"], sent["target"])
		# Flush clients before the authority so this turn's packets reach its poll.
		for client in clients:
			client.multiplayer.poll()
		var prior: Array = []
		for client in clients:
			prior.append(server.session.commands.get(client.multiplayer.get_unique_id()))
		server.multiplayer.poll()
		var complete := true
		var rejected := false
		for index in range(clients.size()):
			var id := clients[index].multiplayer.get_unique_id()
			var sent := intents[index]
			var command: Dictionary = server.session.commands.get(id, {})
			var received := not command.is_empty() and not is_same(command, prior[index])
			var facing := Vector3(clampf(sent["angles"].x, -1.48, 1.48), wrapf(sent["angles"].y, -PI, PI), 0)
			var matches: bool = command.get("movement") == sent["movement"].limit_length() and command.get("rotation", Vector3.INF).is_equal_approx(facing) and command.get("boost") == sent["boost"] and command.get("fire") == sent["fire"] and command.get("encounter") == sent["encounter"] and command.get("target") == sent["target"]
			# command_flight drops packets from missing, docked or dead ships and other lives.
			var ship: SpaceShip = server.session.ships.get(id)
			var blocker := ""
			if ship == null:
				blocker = "no server ship"
			elif ship.get_meta("docked", false):
				blocker = "docked"
			elif not ship.alive:
				blocker = "server ship destroyed"
			elif server.session.combat.records[id]["life"] != sent["life"]:
				blocker = "life %d, server life %d" % [sent["life"], server.session.combat.records[id]["life"]]
			complete = complete and received and matches
			rejected = rejected or blocker != ""
			samples.append({"phase": phase, "attempt": attempt, "peer": id, "sent": str(sent),
				"command": str(command), "received": received, "matches": matches, "blocker": blocker})
		while samples.size() > clients.size() * 8:
			samples.pop_front()
		if complete:
			return true
		if rejected:
			break
	print("Intent convergence failure: ", JSON.stringify(samples))
	return false


## Waits for receipt when the server accepts the command. Commands from another
## pilot life are never stored, so those negative checks keep a short settle.
func send_fire(client: Sector, fire: bool = true, life: int = 0, encounter_id: int = 0) -> void:
	var server := authority_for(client)
	if server == null or server.session.combat.records.get(client.multiplayer.get_unique_id(), {}).get("life", -1) != life:
		client.session.command_flight.rpc_id(1, Vector3.ZERO, Vector3.ZERO, false, fire, life, encounter_id, 0)
		await settle(0.06)
		return
	check(await deliver_intents(server, [client], [intent(fire, life, encounter_id)], "send_fire"), "Server receives the client's fire intent")


func authority_for(client: Sector) -> Sector:
	for viewport in worlds:
		var sector := viewport.get_child(0) as Sector
		if sector != null and sector != client and sector.session.active and sector.multiplayer.is_server() and sector.session.ships.has(client.multiplayer.get_unique_id()):
			return sector
	return null


func replicate(host: Sector) -> void:
	# Unreliable snapshots converge over successive ticks; an individual packet may be dropped.
	for frame in range(3):
		host.session.send_snapshot()
		await settle(0.05)
	await settle(0.08)


func run() -> void:
	var host := make_sector("HostCombat")
	var client := make_sector("ClientCombat")
	var late := make_sector("LateCombat")
	host.credits = 123
	client.credits = 456
	host_session(host, 24681)
	client.session.join("127.0.0.1", test_port(24681))
	await settle(0.5)
	check(host.session.ships.size() == 2, "Combat client joins")
	if host.session.ships.size() != 2:
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	var combat := host.session.combat
	var remote := host.session.ships[id]
	var alien := host.alien
	# This fixture exercises one encounter. Random sector homes must not introduce
	# unrelated attackers into the scripted damage, repair and rescue assertions.
	for other: Alien in host.aliens.values():
		if other != alien:
			other.home_position = Vector3(700, 600, other.alien_id * 40)
			other.position = other.home_position
	check(host.credits == 0 and client.credits == 0, "Shared wallets start independently of solo credits")
	host.player.position = Vector3(-12, 200, 0)
	remote.position = Vector3(12, 200, 0)
	alien.position = Vector3(0, 200, -100)
	alien.home_position = alien.position
	await physics_frame
	await replicate(host)
	check(client.alien.position.is_equal_approx(alien.position), "Client receives the host's alien position")
	client.alien.take_damage(client.alien.max_hull + client.alien.max_shield + 1.0, client.player)
	check(client.alien.alive and client.alien.hull == alien.hull, "Client cannot apply local damage")
	check(not client.player.try_fire(client.alien), "Client cannot simulate an authoritative shot")
	var initial := alien.shield
	await send_fire(client)
	combat.tick(0.01)
	check(alien.shield < initial, "Client fire intent damages the alien on the host")
	var after_first := alien.shield
	combat.tick(0.01)
	check(alien.shield == after_first, "Repeated fire intent obeys the weapon cooldown")
	await replicate(host)
	check(is_equal_approx(client.alien.shield, alien.shield), "Alien damage is replicated exactly")
	check(id in alien.contributors, "A valid hit records the contributing player")
	# Server geometry, rather than client HUD/aim claims, determines whether a shot is legal.
	remote.position = Vector3(0, 200, 500)
	remote.shot_cooldown = 0
	await send_fire(client)
	await physics_frame
	var before_blocked := alien.shield
	combat.tick(0.01)
	check(alien.shield == before_blocked, "Host rejects out-of-range fire intent")
	remote.position = Vector3(12, 200, 0)
	# Turn away without fire first: the ship still faces the alien early in a limited turn.
	check(await deliver_intents(host, [client], [intent(false, 0, 0, 0, Vector3.ZERO, false, Vector3(0, PI, 0))], "turn away"), "Host receives the turn-away command")
	for frame in range(20):
		host.session.tick(1.0 / 60.0)
	check(remote.firing_blocker(alien) == "TURN TOWARD TARGET", "Server-limited rotation reaches the requested facing")
	check(await deliver_intents(host, [client], [intent(true, 0, 0, 0, Vector3.ZERO, false, Vector3(0, PI, 0))], "fire facing away"), "Host receives fire while facing away")
	host.session.tick(1.0 / 60.0)
	check(alien.shield == before_blocked, "Host rejects shots facing away from the alien")
	# A modified client cannot snap back onto the target: the arc uses the server's limited turn.
	check(await deliver_intents(host, [client], [intent(true, 0, 0)], "instant turn back"), "Host receives the instant turn back")
	host.session.tick(1.0 / 60.0)
	check(absf(remote.rotation.y) > 2.0 and remote.firing_blocker(alien) == "TURN TOWARD TARGET", "Firing arc uses the server-limited rotation")
	check(alien.shield == before_blocked, "Host rejects fire after an instant client turn")
	for frame in range(20):
		host.session.tick(1.0 / 60.0)
	check(alien.shield < before_blocked, "Fire resumes once the server turn faces the alien")
	before_blocked = alien.shield
	remote.shot_cooldown = 0
	remote.rotation = Vector3.ZERO
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 50, 4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 200, -50)
	host.add_child(wall)
	await physics_frame
	await send_fire(client)
	combat.tick(0.01)
	check(alien.shield == before_blocked, "Host obstacles block client laser damage")
	wall.queue_free()
	await physics_frame
	await send_fire(client, false)
	# A late join sees an already damaged encounter, without resetting it.
	alien.take_damage(15, host.player)
	var damaged_shield := alien.shield
	late.session.join("127.0.0.1", test_port(24681))
	await settle(0.5)
	await replicate(host)
	check(late.alien.shield == damaged_shield and alien.shield == damaged_shield, "Late join preserves and receives current alien health")
	var late_id := late.multiplayer.get_unique_id()
	check(host.player in host.session.ships.values(), "Host retains its own ship")
	# The client is closer, so the alien attacks it rather than always targeting the host.
	remote.position = alien.position + Vector3(0, 0, 80)
	host.player.position = Vector3(-100, 200, 0)
	check(combat.choose_target(alien) == remote, "Alien chooses the nearest eligible player")
	# The alien now reaches the remote throughout this test; measure one hit from full health.
	remote.reset_health()
	alien.shot_cooldown = 60.0
	remote.take_damage(remote.max_shield + remote.max_hull / 12.0, alien)
	await replicate(host)
	check(client.player.shield == 0 and client.player.hull == remote.max_hull - remote.max_hull / 12.0, "Split damage and shield depletion replicate")
	# Only the two contributors share the conserved reward pool; a spectator gets none.
	alien.take_damage(alien.max_hull + alien.max_shield + 1.0, host.player)
	alien.take_damage(alien.max_hull + alien.max_shield + 1.0, host.player)
	await replicate(host)
	# Unreliable alien chunks may arrive after the reliable reward notification.
	var death_deadline := Time.get_ticks_msec() + 2000
	while (client.alien.alive or late.alien.alive or client.target != null) and Time.get_ticks_msec() < death_deadline:
		await replicate(host)
	check(combat.records[1]["credits"] + combat.records[id]["credits"] == 1500, "Reward pool is awarded exactly once and conserved")
	check(absi(combat.records[1]["credits"] - combat.records[id]["credits"]) <= 1, "Contributors receive equal integer shares")
	check(combat.records[late_id]["credits"] == 0, "A spectator receives no reward")
	check(client.credits == combat.records[id]["credits"] and client.kills == 1, "Personal rewards and kill count reach the client")
	check(client.toast.contains("Your share: +%d credits" % client.credits), "Reward feedback names the local awarded share, not the total pool")
	check(not client.alien.alive and not late.alien.alive and client.target == null, "Alien death and target clearing reach every client")
	check(client.alien.respawn > 0, "Clients receive the alien respawn countdown")
	# Repair validates the requesting peer's ship, location, speed, cooldown and wallet.
	var wallet: int = combat.records[id]["credits"]
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	check(remote.hull == remote.max_hull - remote.max_hull / 12.0 and combat.records[id]["credits"] == wallet, "Remote repairs fail away from station")
	remote.position = Sector.STATION_POSITION + Vector3(0, 120, 0)
	remote.velocity = Vector3(20, 0, 0)
	remote.time_since_hit = 6
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	check(remote.hull == remote.max_hull - remote.max_hull / 12.0, "Remote repairs fail while moving too fast")
	remote.velocity = Vector3.ZERO
	remote.time_since_hit = 1
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	check(remote.hull == remote.max_hull - remote.max_hull / 12.0, "Remote repairs fail after recent damage")
	remote.time_since_hit = 6
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	await replicate(host)
	check(remote.hull == remote.max_hull and client.player.hull == remote.max_hull, "Accepted remote repair at the 120 m boundary restores and replicates health")
	check(late.session.ships[id].hull == remote.max_hull and late.session.ships[id].shield == remote.max_shield, "A teammate observer receives the repaired hull and shields")
	check(client.credits == wallet - 2 and client.objective_stage == 4, "Host deducts the repair price and confirms encounter completion")
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	check(combat.records[id]["credits"] == wallet - 2, "Repeated repair cannot charge twice for the same damage")
	# Player death charges once and does not reset the alien's respawn timer.
	remote.take_damage(remote.max_hull + remote.max_shield + 1.0, alien)
	remote.take_damage(remote.max_hull + remote.max_shield + 1.0, alien)
	await replicate(host)
	check(not client.player.alive and client.player_respawn == 3.0, "Remote destruction and rescue timer replicate")
	check(client.credits == wallet - 12, "Rescue fee is charged once")
	var alien_timer := alien.respawn
	combat.tick(3.1)
	await replicate(host)
	check(client.player.alive and client.player.position.is_equal_approx(remote.position), "Host respawn teleports the client to the station")
	check(remote.position.is_equal_approx(combat.records[id]["spawn"]) and int(remote.get_meta("life")) == 1, "Respawn starts a fresh player life")
	check(not alien.alive and alien.respawn < alien_timer, "Player rescue does not reset the shared alien encounter")
	await send_fire(client, true, 0)
	check(not host.session.commands.has(id), "Commands from a previous player life are rejected")
	combat.tick(13)
	await replicate(host)
	check(alien.alive and client.alien.alive and alien.life == 1, "Alien respawns once and reaches all clients")
	await send_fire(client, true, 1, 0)
	check(not combat.remote_firing(id), "Old fire intent cannot attack a newly spawned alien")
	# A disconnected contributor does not receive a reward or leave stale state.
	alien.take_damage(1, host.player)
	alien.take_damage(1, remote)
	client.hud.navigation.choose_contact("friend1")
	check(client.target == null and client.hud.navigation.destination()["ship"] == client.session.ships[1], "Friendly waypoint guides without creating a combat target")
	client.hud.navigation.open_overview()
	client.session.disconnect_session("Test leave")
	await settle()
	check(not client.hud.navigation.overview.visible and client.hud.navigation.waypoint_key == "station", "Disconnect clears overview and missing friendly waypoint")
	check(id not in alien.contributors and not combat.records.has(id), "Leaving removes combat state and reward eligibility")
	check(client.credits == 456, "Leaving restores the client's separate solo credits")
	alien.take_damage(alien.max_hull + alien.max_shield + 1.0, host.player)
	check(combat.records[1]["credits"] == 2250, "Remaining contributor receives the next reward pool")
	host.session.disconnect_session("Test complete")
	await settle()
	check(host.credits == 123 and late.alien.simulation_authority, "Host shutdown restores solo credits and simulation")
	print("Shared combat checks complete")
	finish()
