extends "res://tests/network_test.gd"
## Authoritative combat exercised through actual client RPCs and host snapshots.


func send_fire(client: Sector, fire: bool = true, life: int = 0, encounter_id: int = 0) -> void:
	client.session.command_flight.rpc_id(1, Vector3.ZERO, Vector3.ZERO, false, fire, life, encounter_id)
	await settle(0.06)


func replicate(host: Sector) -> void:
	var state: Dictionary = {}
	for id: int in host.session.ships:
		var ship := host.session.ships[id]
		state[id] = {"position": ship.position, "rotation": ship.rotation, "velocity": ship.velocity, "energy": ship.energy}
		state[id].merge(host.session.combat.pack_player(id))
	host.session.snapshot.rpc(state, host.session.combat.pack_alien())
	await settle(0.08)


func run() -> void:
	var host := make_sector("HostCombat")
	var client := make_sector("ClientCombat")
	var late := make_sector("LateCombat")
	host.credits = 123
	client.credits = 456
	host.session.host(24681)
	client.session.join("127.0.0.1", 24681)
	await settle(0.5)
	check(host.session.ships.size() == 2, "Combat client joins")
	if host.session.ships.size() != 2:
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	var combat := host.session.combat
	var remote := host.session.ships[id]
	var alien := host.alien
	check(host.credits == 0 and client.credits == 0, "Shared wallets start independently of solo credits")
	host.player.position = Vector3(-12, 60, 0)
	remote.position = Vector3(12, 60, 0)
	alien.position = Vector3(0, 60, -100)
	await physics_frame
	await replicate(host)
	check(client.alien.position.is_equal_approx(alien.position), "Client receives the host's alien position")
	client.alien.take_damage(999, client.player)
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
	check(id in combat.contributors, "A valid hit records the contributing player")
	# Server geometry, rather than client HUD/aim claims, determines whether a shot is legal.
	remote.position = Vector3(0, 60, 300)
	remote.shot_cooldown = 0
	await send_fire(client)
	await physics_frame
	var before_blocked := alien.shield
	combat.tick(0.01)
	check(alien.shield == before_blocked, "Host rejects out-of-range fire intent")
	remote.position = Vector3(12, 60, 0)
	client.session.command_flight.rpc_id(1, Vector3.ZERO, Vector3(0, PI, 0), false, true, 0, 0)
	await settle(0.06)
	host.session.tick(0.01)
	check(alien.shield == before_blocked, "Host rejects shots facing away from the alien")
	remote.rotation = Vector3.ZERO
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 50, 4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 60, -50)
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
	late.session.join("127.0.0.1", 24681)
	await settle(0.5)
	await replicate(host)
	check(late.alien.shield == damaged_shield and alien.shield == damaged_shield, "Late join preserves and receives current alien health")
	var late_id := late.multiplayer.get_unique_id()
	check(host.player in host.session.ships.values(), "Host retains its own ship")
	# The client is closer, so the alien attacks it rather than always targeting the host.
	remote.position = alien.position + Vector3(0, 0, 80)
	host.player.position = Vector3(-100, 60, 0)
	check(combat.choose_target() == remote, "Alien chooses the nearest eligible player")
	remote.take_damage(80, alien)
	await replicate(host)
	check(client.player.shield == 0 and client.player.hull == 110, "Player shield overflow and hull damage replicate")
	# Only the two contributors share the conserved reward pool; a spectator gets none.
	alien.take_damage(999, host.player)
	alien.take_damage(999, host.player)
	await replicate(host)
	check(combat.records[1]["credits"] + combat.records[id]["credits"] == 75, "Reward pool is awarded exactly once and conserved")
	check(absi(combat.records[1]["credits"] - combat.records[id]["credits"]) <= 1, "Contributors receive equal integer shares")
	check(combat.records[late_id]["credits"] == 0, "A spectator receives no reward")
	check(client.credits == combat.records[id]["credits"] and client.kills == 1, "Personal rewards and kill count reach the client")
	check(not client.alien.alive and not late.alien.alive and client.target == null, "Alien death and target clearing reach every client")
	check(client.alien_respawn > 0, "Clients receive the alien respawn countdown")
	# Repair validates the requesting peer's ship, location, speed, cooldown and wallet.
	var wallet: int = combat.records[id]["credits"]
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	check(remote.hull == 110 and combat.records[id]["credits"] == wallet, "Remote repairs fail away from station")
	remote.position = combat.records[id]["spawn"]
	remote.velocity = Vector3(20, 0, 0)
	remote.time_since_hit = 6
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	check(remote.hull == 110, "Remote repairs fail while moving too fast")
	remote.velocity = Vector3.ZERO
	remote.time_since_hit = 1
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	check(remote.hull == 110, "Remote repairs fail after recent damage")
	remote.time_since_hit = 6
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	await replicate(host)
	check(remote.hull == remote.max_hull and client.player.hull == remote.max_hull, "Accepted remote repair restores and replicates health")
	check(late.session.ships[id].hull == remote.max_hull and late.session.ships[id].shield == remote.max_shield, "A teammate observer receives the repaired hull and shields")
	check(client.credits == wallet - 2 and client.objective_stage == 4, "Host deducts the repair price and confirms encounter completion")
	client.session.combat.repair_request.rpc_id(1, 0)
	await settle()
	check(combat.records[id]["credits"] == wallet - 2, "Repeated repair cannot charge twice for the same damage")
	# Player death charges once and does not reset the alien's respawn timer.
	remote.take_damage(999, alien)
	remote.take_damage(999, alien)
	await replicate(host)
	check(not client.player.alive and client.player_respawn == 3.0, "Remote destruction and rescue timer replicate")
	check(client.credits == wallet - 12, "Rescue fee is charged once")
	var alien_timer := combat.alien_respawn
	combat.tick(3.1)
	await replicate(host)
	check(client.player.alive and client.player.position.is_equal_approx(remote.position), "Host respawn teleports the client to the station")
	check(remote.position.is_equal_approx(combat.records[id]["spawn"]) and int(remote.get_meta("life")) == 1, "Respawn starts a fresh player life")
	check(not alien.alive and combat.alien_respawn < alien_timer, "Player rescue does not reset the shared alien encounter")
	await send_fire(client, true, 0)
	check(not host.session.commands.has(id), "Commands from a previous player life are rejected")
	combat.tick(13)
	await replicate(host)
	check(alien.alive and client.alien.alive and combat.encounter == 1, "Alien respawns once and reaches all clients")
	await send_fire(client, true, 1, 0)
	check(not combat.remote_firing(id), "Old fire intent cannot attack a newly spawned alien")
	# A disconnected contributor does not receive a reward or leave stale state.
	alien.take_damage(1, host.player)
	alien.take_damage(1, remote)
	client.session.disconnect_session("Test leave")
	await settle()
	check(id not in combat.contributors and not combat.records.has(id), "Leaving removes combat state and reward eligibility")
	check(client.credits == 456, "Leaving restores the client's separate solo credits")
	alien.take_damage(999, host.player)
	check(combat.records[1]["credits"] == 113, "Remaining contributor receives the next reward pool")
	host.session.disconnect_session("Test complete")
	await settle()
	check(host.credits == 123 and late.alien.simulation_authority, "Host shutdown restores solo credits and simulation")
	print("Shared combat checks complete")
	finish()
