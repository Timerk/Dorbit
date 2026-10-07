extends "res://tests/hunting_contracts_test.gd"
## Earn an upgrade from an empty wallet, then conserve a three-pilot Heavy payout.


func connect_pilot(client: Sector, index: int) -> void:
	await super.connect_pilot(client, index)
	var deadline := Time.get_ticks_msec() + 5000
	while client.session.active and not client.session.received_snapshot and Time.get_ticks_msec() < deadline:
		await process_frame


func run() -> void:
	var server := make_sector("EconomyServer", true, CONTRACT_PORT)
	var pilot := make_sector("EconomyPilot")
	await connect_pilot(pilot, 0)
	if server.session.ships.size() != 1:
		check(false, "Economy pilot authenticates")
		finish()
		return
	var id := pilot.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var combat := server.session.combat
	# Five short contracts with minimum rolls must fund the 10,000-CR LF-1.
	# Use the actual kill, collection, sale and purchase transactions without test grants.
	for trip in range(5):
		station(server, pilot)
		await action(server, pilot, "accept", "scout")
		for hunt in range(3):
			await kill(server, "Scout", [pilot])
			var drop_id: int = server.loot.next_id
			var drop: Dictionary = server.loot.drops[drop_id].duplicate(true)
			var minimum := {}
			for resource: String in CargoResources.LOOT["Scout"]:
				minimum[resource] = CargoResources.LOOT["Scout"][resource].x
			drop["resources"] = minimum
			server.loot.change(drop_id, drop)
			ship.position = drop["position"]
			combat.collect_loot()
			await replicate(server)
		check(not pilot.active_contracts.has("scout"), "Trip %d pays its Scout contract once" % trip)
	check(pilot.credits == 9000 and CargoResources.value(pilot.cargo) == 2100, "Fifteen minimum-loot Scouts earn 9,000 CR plus 2,100 CR cargo")
	station(server, pilot)
	pilot.session.combat.station_request.rpc_id(1, 1, "sell", "all", "", "", 0)
	await settle()
	await replicate(server)
	check(pilot.cargo.is_empty() and pilot.credits == 11100, "Selling the earned cargo funds the first laser from zero")
	pilot.session.combat.station_request.rpc_id(1, 2, "buy", "laser", "", "", 0)
	await settle()
	await replicate(server)
	check(pilot.credits == 1100 and pilot.session.combat.inventory["items"].has("purchase-2"), "Earned credits buy an upgrade and leave a repair reserve")
	# Loot value bounds make the contribution of station trading reviewable.
	var bounds := {"Scout": Vector2i(140, 260), "Sentinel": Vector2i(700, 1240), "Heavy": Vector2i(3140, 5400)}
	for kind: String in bounds:
		var low := {}
		var high := {}
		for resource: String in CargoResources.LOOT[kind]:
			low[resource] = CargoResources.LOOT[kind][resource].x
			high[resource] = CargoResources.LOOT[kind][resource].y
		check(CargoResources.value(low) == bounds[kind].x and CargoResources.value(high) == bounds[kind].y, kind + " loot supports the documented income range")
	var partner := make_sector("EconomyPartner")
	var third := make_sector("EconomyThird")
	await connect_pilot(partner, 1)
	await connect_pilot(third, 2)
	var clients: Array[Sector] = [pilot, partner, third]
	var before := {}
	for client in clients:
		station(server, client)
		await action(server, client, "accept", "heavy")
		before[client.multiplayer.get_unique_id()] = client.credits
	await kill(server, "Heavy", clients)
	var ordered := before.keys()
	ordered.sort()
	var total := 0
	for client in clients:
		var peer_id := client.multiplayer.get_unique_id()
		var earned: int = client.credits - before[peer_id]
		check(earned == 33333 + (1 if peer_id == ordered[0] else 0) and client.active_contracts.is_empty(), "Each contributor receives the full contract and its ordered integer kill share")
		total += earned
	check(total == 100000, "Three Heavy contracts plus the shared kill pool conserve exactly 100,000 CR")
	var balances := clients.map(func(client: Sector): return client.credits)
	server.aliens[4].take_damage(1000000, ship)
	await replicate(server)
	check(clients.map(func(client: Sector): return client.credits) == balances, "Duplicate Heavy destruction cannot repeat the larger payments")
	server.session.disconnect_session("Economy restart")
	await settle(0.3)
	check(server.session.host(CONTRACT_PORT) == OK, "Economy ledger reopens")
	await connect_pilot(pilot, 0)
	await replicate(server)
	check(pilot.credits == balances[0] and pilot.active_contracts.is_empty() and pilot.session.combat.inventory["items"].has("purchase-2"), "Restart retains earned upgrade, payout and cleared contracts")
	finish()
