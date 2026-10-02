extends "res://tests/equipment_test.gd"
## Actual ENet kills, shared pickups, station sales and restart recovery.

func run() -> void:
	var previous := 0
	for info: Dictionary in CargoResources.TYPES.values():
		check(info["price"] > previous, "%s increases in value" % info["name"])
		previous = info["price"]
	var tiers_valid := true
	for iteration in range(30):
		var scout := CargoResources.roll("Scout")
		var sentinel := CargoResources.roll("Sentinel")
		var heavy := CargoResources.roll("Heavy")
		tiers_valid = tiers_valid and scout.size() == 3 and sentinel.size() == 5 and heavy.size() == 7 and CargoResources.units(scout) < CargoResources.units(sentinel) and CargoResources.units(sentinel) < CargoResources.units(heavy)
	check(tiers_valid, "Loot tiers increase quantity and quality across thirty rolls")
	var server := make_sector("ResourceServer", true, 24732)
	var client := make_sector("ResourceClient")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", 24732)
	await settle(0.5)
	await replicate(server)
	var id := client.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var store := server.session.store
	var combat := server.session.combat
	check(client.cargo.is_empty() and client.cargo_capacity == 200, "Existing pilot migrates to an empty Pathfinder hold")
	var owned := Equipment.starter()
	owned["ships"]["spare"] = "pathfinder"
	check(CargoResources.valid({"starter": {"seprom": 2}, "spare": {}}, owned), "Cargo belongs to individual owned ships")
	check(not CargoResources.valid({"starter": {"seprom": 201}, "spare": {}}, owned), "Each ship has its own capacity limit")
	ship.position = Vector3(0, 100, 0)
	for slot in [1, 0, 4]:
		var alien: Alien = server.aliens[slot]
		alien.take_damage(9999, ship)
		await settle()
		var drop_id: int = server.loot.drops.keys().back()
		check(server.loot.drops[drop_id]["position"] == alien.position and client.loot.drops.has(drop_id), "%s death drops replicated resources at the wreck" % alien.kind)
		var count := server.loot.drops.size()
		alien.take_damage(9999, ship)
		check(server.loot.drops.size() == count, "Repeated damage cannot duplicate %s loot" % alien.kind)
	check(server.loot.meshes.is_empty(), "Dedicated server creates no loot meshes")
	server.loot.clear()
	combat.loot_state.rpc(server.loot.drops)
	var location := Vector3(0, 100, -200)
	server.loot.change(100, {"position": location, "resources": {"prometium": 10, "seprom": 2}, "ttl": 180.0})
	ship.position = location + Vector3(0, 0, 13)
	combat.collect_loot()
	check(combat.cargo_holds[id]["starter"].is_empty(), "Collection requires the authoritative ship within 12 m")
	client.player.position = location
	client.session.combat.collect_loot()
	check(store.pilots["pilot0"]["cargo"]["starter"].is_empty(), "Clients cannot grant themselves resources")
	var late := make_sector("ResourceLate")
	late.session.credential_id = "pilot1"
	late.session.credential_token = test_token(1)
	late.session.join("127.0.0.1", 24732)
	await settle(0.5)
	await replicate(server)
	check(late.loot.drops.has(100) and late.loot.drops[100]["resources"] == {"prometium": 10, "seprom": 2}, "Late join receives current uncollected loot")
	var late_id := late.multiplayer.get_unique_id()
	var other := server.session.ships[late_id]
	var holds := {"starter": {"endurium": 197}}
	store.commit({}, {}, {"pilot0": holds})
	combat.cargo_holds[id] = holds.duplicate(true)
	ship.position = location
	other.position = location + Vector3(0, 0, 1)
	combat.collect_loot()
	await settle()
	check(client.cargo == {"endurium": 197, "seprom": 2, "prometium": 1}, "Nearest pilot takes exactly its free capacity, valuable resources first")
	check(late.cargo == {"prometium": 9}, "Second nearby pilot takes the remainder without duplication")
	check(not server.loot.drops.has(100) and not client.loot.drops.has(100) and not late.loot.drops.has(100), "Empty boxes disappear for all peers")
	server.loot.change(101, {"position": location, "resources": {"duranium": 3}, "ttl": 180.0})
	other.position = Sector.SPAWN_POSITION
	combat.collect_loot()
	check(server.loot.drops[101]["resources"] == {"duranium": 3}, "Full cargo leaves resources in space")
	holds = {"starter": {"endurium": 199}}
	store.commit({}, {}, {"pilot0": holds})
	combat.cargo_holds[id] = holds.duplicate(true)
	combat.collect_loot()
	await settle()
	check(client.cargo == {"endurium": 199, "duranium": 1} and server.loot.drops[101]["resources"] == {"duranium": 2}, "Partial pickup preserves every excess unit")
	ship.take_damage(9999, server.alien)
	combat.collect_loot()
	check(server.loot.drops[101]["resources"] == {"duranium": 2}, "Destroyed ships cannot collect")
	combat.tick(3.1)
	await replicate(server)
	check(client.cargo == {"endurium": 199, "duranium": 1}, "Rescue preserves cargo")
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	client.shop.open()
	client.shop.equipment_page.hide()
	client.shop.cargo_page.show()
	await settle()
	await screenshot(client, "resources-full-hold")
	check(client.shop.sell_all.text.contains("414 CR") and not client.shop.sell_all.disabled, "Cargo panel displays exact value and enables selling")
	for reason in ["distance", "speed", "damage", "life"]:
		ship.position = location if reason == "distance" else combat.records[id]["spawn"]
		ship.velocity = Vector3(10, 0, 0) if reason == "speed" else Vector3.ZERO
		ship.time_since_hit = 0 if reason == "damage" else 5
		await request(client, 1, "sell", "all", "", "", 99 if reason == "life" else 1)
		check(store.pilots["pilot0"]["equipment"]["revision"] == 0 and CargoResources.units(store.pilots["pilot0"]["cargo"]["starter"]) == 200, "Server rejects sale for " + reason)
	ship.time_since_hit = 5
	await request(client, 1, "sell", "unknown", "", "", 1)
	check(client.session.combat.station_message.contains("Unknown"), "Unknown resource grants no money")
	var balance: int = store.pilots["pilot0"]["credits"]
	await request(client, 1, "sell", "duranium", "", "", 1)
	check(client.cargo == {"endurium": 199} and store.pilots["pilot0"]["credits"] == balance + 16, "Individual sale credits the exact price and preserves other resources")
	await request(client, 1, "sell", "duranium", "", "", 1)
	check(store.pilots["pilot0"]["credits"] == balance + 16, "Duplicate sale pays only once")
	client.shop.sell_all.pressed.emit()
	await settle()
	check(client.cargo.is_empty() and store.pilots["pilot0"]["credits"] == balance + 414, "Sell-all button atomically clears cargo and credits its entire value")
	await screenshot(client, "resources-sold")
	await request(client, 3, "sell", "all", "", "", 1)
	check(client.session.combat.inventory["revision"] == 2 and client.session.combat.station_message.contains("No resources"), "Empty sale does not advance the revision")
	client.shop.close()
	ship.position = location
	combat.collect_loot()
	await settle()
	check(client.cargo == {"duranium": 2} and not server.loot.drops.has(101), "A return trip after selling collects the preserved remainder")
	await replicate(server)
	server.loot.change(102, {"position": location + Vector3(18, 8, -45), "resources": {"seprom": 2}, "ttl": 180.0})
	await settle()
	await screenshot(client, "resources-in-space")
	server.loot.tick(181)
	await settle()
	check(server.loot.drops.is_empty() and client.loot.drops.is_empty(), "Uncollected boxes expire on all peers")
	for index in range(ResourceLoot.MAX_DROPS + 1):
		server.loot.spawn_drop(server.alien)
	check(server.loot.drops.size() == ResourceLoot.MAX_DROPS, "Space loot has a bounded population")
	late.session.disconnect_session("Restart")
	client.session.disconnect_session("Restart")
	await settle()
	server.session.disconnect_session("Restart")
	check(server.session.host(24732) == OK, "Server restarts with saved cargo")
	client.session.join("127.0.0.1", 24732)
	await settle(0.5)
	await replicate(server)
	check(client.cargo == {"duranium": 2} and client.credits == balance + 414 and client.loot.drops.is_empty(), "Restart preserves cargo and sales; uncollected loot is session state")
	await request(client, 2, "sell", "all")
	check(client.cargo == {"duranium": 2} and client.credits == balance + 414, "Restart retains duplicate-sale protection")
	store = server.session.store
	id = client.multiplayer.get_unique_id()
	store.commit({"pilot0": PilotStore.MAX_CREDITS - 1})
	combat.records[id]["credits"] = PilotStore.MAX_CREDITS - 1
	await request(client, 3, "sell", "all")
	check(client.cargo == {"duranium": 2} and client.session.combat.station_message.contains("credit limit"), "Wallet limit rejects the whole sale and keeps cargo")
	var failure_dir := store.path.get_base_dir().path_join("resource-failure")
	DirAccess.make_dir_absolute(failure_dir)
	var file := FileAccess.open(failure_dir.path_join("pilots.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 3, "pilots": {"pilot0": store.pilots["pilot0"]}}))
	file.close()
	var probe := PilotStore.new()
	check(probe.open(failure_dir), "Open isolated cargo failure fixture")
	probe.commit({"pilot0": 0})
	var before := probe.pilots.duplicate(true)
	var disk_before := FileAccess.get_file_as_string(probe.path)
	DirAccess.make_dir_absolute(probe.path + ".tmp")
	probe.transact("pilot0", 3, "sell", "all", "", "")
	check(probe.failed and probe.pilots == before and FileAccess.get_file_as_string(probe.path) == disk_before, "Write failure preserves cargo, credits, sequence and disk ledger")
	probe.close()
	finish()
