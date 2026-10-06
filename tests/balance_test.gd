extends "res://tests/network_combat_test.gd"
## Damage splitting, expanded fitting and authoritative replication at the new scale.


func fight(kind: String, lasers: int, pilots: int = 1) -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var enemy := Alien.new()
	enemy.kind = kind
	enemy.render_enabled = false
	enemy.home_position = Vector3(0, 100, 0)
	world.add_child(enemy)
	enemy.position = enemy.home_position
	var ships: Array[SpaceShip] = []
	for index in range(pilots):
		var ship := SpaceShip.new()
		ship.render_enabled = false
		ship.laser_damage = lasers * 65.0
		world.add_child(ship)
		ship.position = Vector3(index * 8, 100, 100)
		ship.look_at(enemy.position)
		ships.append(ship)
	await physics_frame
	var seconds := 0.0
	while enemy.alive and ships.any(func(ship: SpaceShip): return ship.alive) and seconds < 120:
		for ship: SpaceShip in ships:
			ship.tick_combat(0.01)
			ship.try_fire(enemy)
		enemy.tick_combat(0.01)
		for ship: SpaceShip in ships:
			if ship.alive:
				enemy.look_at(ship.position)
				enemy.try_fire(ship)
				break
		seconds += 0.01
	var result := {"kill": not enemy.alive, "survivors": ships.filter(func(ship: SpaceShip): return ship.alive).size(), "seconds": seconds}
	print("Balance encounter %s: %d laser(s), %d pilot(s), %s" % [kind, lasers, pilots, result])
	world.queue_free()
	await process_frame
	return result


func run() -> void:
	var scout := await fight("Scout", 1)
	check(scout["kill"] and scout["survivors"] == 1, "One starter laser can win a Scout fight")
	var sentinel := await fight("Sentinel", 1)
	check(not sentinel["kill"] and sentinel["survivors"] == 0, "A starter fitting must upgrade or group for a Sentinel")
	sentinel = await fight("Sentinel", 3)
	check(sentinel["kill"] and sentinel["survivors"] == 1, "Three starter lasers can win a Sentinel fight")
	var heavy := await fight("Heavy", 4)
	check(not heavy["kill"] and heavy["survivors"] == 0, "A Heavy remains dangerous with four starter lasers")
	heavy = await fight("Heavy", 4, 3)
	check(heavy["kill"] and heavy["survivors"] == 3, "Three fitted pilots can win a Heavy fight")
	var target := SpaceShip.new()
	target.render_enabled = false
	root.add_child(target)
	target.shield_absorption = 0.8
	target.take_damage(100, null)
	check(target.shield == 920 and target.hull == target.max_hull - 20, "80% absorption splits a hit 80 shield / 20 hull")
	target.shield = 30
	var hull := target.hull
	target.take_damage(100, null)
	check(target.shield == 0 and target.hull == hull - 70, "Insufficient shields spill the unabsorbed share into hull")
	hull = target.hull
	target.take_damage(100, null)
	check(target.hull == hull - 100, "Depleted shields send all damage to hull")
	target.tick_combat(5)
	check(target.shield == 0, "Recovery waits six seconds after the last hit")
	target.tick_combat(1)
	check(is_equal_approx(target.shield, target.max_shield / 12), "Recovery scales with capacity")
	target.tick_combat(12)
	check(target.shield == target.max_shield, "Recovery caps at capacity")
	target.hull = 10
	target.shield = 200
	target.take_damage(100, null)
	check(not target.alive and target.shield == 120, "Hull destruction can occur while shields remain")
	target.reset_health()
	target.simulation_authority = false
	target.take_damage(100, null)
	check(target.hull == target.max_hull and target.shield == target.max_shield, "Clients cannot apply split damage locally")
	target.queue_free()

	var fitting := Equipment.starter()
	for index in range(2, 5):
		fitting["items"]["laser-%d" % index] = {"model": "laser", "ship": "starter", "slot": "laser%d" % index}
	fitting["items"]["starter-engine"]["ship"] = ""
	fitting["items"]["starter-engine"]["slot"] = ""
	for index in range(2, 7):
		fitting["items"]["shield-%d" % index] = {"model": "shield", "ship": "starter", "slot": "generator%d" % index}
	check(Equipment.valid(fitting), "All four lasers and six generators can be fitted together")
	var values := Equipment.stats(fitting)
	check(values["damage"] == 260 and values["shield"] == 6000 and is_equal_approx(values["absorption"], 0.4), "Capacity stacks while absorption remains 40%")
	check(not Equipment.fitting_blocker(fitting, "starter-engine", "starter", "extra1").is_empty(), "Extras reject current generator equipment")
	fitting["items"]["laser-4"]["slot"] = "laser5"
	check(not Equipment.valid(fitting), "A fifth laser slot is rejected")
	fitting["items"]["laser-4"]["slot"] = "laser4"
	fitting["items"]["shield-6"]["slot"] = "generator7"
	check(not Equipment.valid(fitting), "A seventh generator slot is rejected")

	var server := make_sector("BalanceServer", true, 24741)
	var client := make_sector("BalanceClient")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", 24741)
	await settle(0.5)
	var id := client.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var store := server.session.store
	check(store.commit({"pilot0": 30000}), "Fund expanded fitting test")
	server.session.combat.records[id]["credits"] = 30000
	var sequence := 0
	for slot in ["laser3", "laser4", "generator6"]:
		sequence += 1
		var item_id := "purchase-%d" % sequence
		client.session.combat.station_request.rpc_id(1, sequence, "buy", "shield" if slot == "generator6" else "laser", "", "", 0)
		await settle()
		sequence += 1
		client.session.combat.station_request.rpc_id(1, sequence, "fit", item_id, "starter", slot, 0)
		await settle()
	await replicate(server)
	check(ship.laser_damage == 195 and ship.max_shield == 2000 and is_equal_approx(ship.shield_absorption, 0.4), "Server accepts fitting into the new laser and generator slots")
	check(client.player.laser_damage == 195 and client.player.max_shield == 2000 and is_equal_approx(client.player.shield_absorption, 0.4), "Client receives authoritative capacity and absorption")
	check(ship.shield == 1000, "Adding shield capacity does not refill charge")
	ship.take_damage(100, server.alien)
	await replicate(server)
	check(ship.shield == 960 and ship.hull == ship.max_hull - 60 and client.player.shield == ship.shield and client.player.hull == ship.hull, "40% starter split damage replicates exactly")
	ship.time_since_hit = 6
	client.session.combat.station_request.rpc_id(1, 7, "fit", "starter-shield", "", "", 0)
	await settle()
	client.session.combat.station_request.rpc_id(1, 8, "fit", "purchase-5", "", "", 0)
	await settle()
	await replicate(server)
	check(ship.max_shield == 0 and ship.shield_absorption == 0 and client.player.shield_absorption == 0, "Removing all shields clears absorption on both peers")
	client.session.disconnect_session("Restart expanded fitting")
	await settle()
	server.session.disconnect_session("Restart expanded fitting")
	check(server.session.host(24741) == OK, "Expanded fittings load after restart")
	check(server.session.store.pilots["pilot0"]["equipment"]["items"]["purchase-3"]["slot"] == "laser4", "Restart preserves the fourth laser slot and existing items")
	finish()
