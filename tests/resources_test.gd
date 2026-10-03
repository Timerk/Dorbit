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
		alien.take_damage(alien.max_hull + alien.max_shield + 1.0, ship)
		await settle()
		var drop_id: int = server.loot.drops.keys().back()
		check(server.loot.drops[drop_id]["position"] == alien.position and client.loot.drops.has(drop_id), "%s death drops replicated resources at the wreck" % alien.kind)
		var count := server.loot.drops.size()
		alien.take_damage(alien.max_hull + alien.max_shield + 1.0, ship)
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
	ship.take_damage(ship.max_hull + ship.max_shield + 1.0, server.alien)
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
	await check_resource_shop(server, client)
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
	probe.transact("pilot0", int(probe.pilots["pilot0"]["equipment"]["revision"]) + 1, "sell", "all", "", "")
	check(probe.failed and probe.pilots == before and FileAccess.get_file_as_string(probe.path) == disk_before, "Write failure preserves cargo, credits, sequence and disk ledger")
	probe.close()
	finish()


func click_control(client: Sector, control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	client.get_viewport().push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	client.get_viewport().push_input(event)
	await settle()


func check_resource_shop(server: Sector, client: Sector) -> void:
	var store := server.session.store
	var combat := server.session.combat
	var id := client.multiplayer.get_unique_id()
	var hold := {}
	for resource: String in CargoResources.TYPES:
		hold[resource] = 10
	check(store.commit({"pilot0": 1000}, {}, {"pilot0": {"starter": hold}}), "Seed all seven ores for the trading controls")
	combat.records[id]["credits"] = 1000
	combat.cargo_holds[id] = {"starter": hold.duplicate()}
	combat.publish_inventory(id)
	await settle()
	client.get_viewport().size = Vector2i(960, 600)
	client.shop.open()
	client.shop.equipment_page.hide()
	client.shop.cargo_page.show()
	await settle()
	var shop := client.shop
	check(shop.visible and shop.sells.size() == 7 and shop.selected["seprom"] == 10, "Trading displays all seven resources with full quantities initially selected")
	check(shop.get_global_rect().position.x >= 0 and shop.get_global_rect().end.x <= 960 and shop.get_global_rect().end.y <= 600, "Ore cards fit the minimum supported viewport")
	for resource: String in CargoResources.TYPES:
		check(shop.sells[resource].get_global_rect().end.x <= shop.get_global_rect().end.x and shop.sells[resource].get_global_rect().end.y <= shop.get_global_rect().end.y, "%s sale control stays inside the shop" % resource)
	await screenshot(client, "resource-shop")
	await click_control(client, shop.decreases["seprom"])
	check(shop.selected["seprom"] == 9 and shop.totals["seprom"].text == "576 CR", "Real minus-button input updates quantity and exact proceeds")
	await click_control(client, shop.increases["seprom"])
	check(shop.selected["seprom"] == 10 and shop.increases["seprom"].disabled, "Plus button stops at held quantity")
	await click_control(client, shop.quantities["seprom"])
	shop.quantities["seprom"].select_all()
	var key := InputEventKey.new()
	key.keycode = KEY_BACKSPACE
	key.pressed = true
	client.get_viewport().push_input(key)
	await process_frame
	for digit in "10":
		key = InputEventKey.new()
		key.keycode = digit.unicode_at(0)
		key.unicode = digit.unicode_at(0)
		key.pressed = true
		client.get_viewport().push_input(key)
		await process_frame
	check(shop.selected["seprom"] == 10 and shop.quantities["seprom"].text == "10", "Clearing and typing a multi-digit quantity preserves normal cursor behavior")
	shop.quantities["seprom"].select_all()
	key = InputEventKey.new()
	key.keycode = KEY_3
	key.unicode = 51
	key.pressed = true
	client.get_viewport().push_input(key)
	await settle()
	check(shop.totals["seprom"].text == "192 CR", "Editable quantity updates the sale total")
	client.session.combat.station_pending = true
	await settle()
	check(shop.sells["seprom"].disabled and shop.increases["seprom"].disabled and not shop.quantities["seprom"].editable, "Pending server reply blocks quantity changes and further sales")
	client.session.combat.station_pending = false
	var revision: int = client.session.combat.inventory["revision"]
	for subject in ["seprom:0", "seprom:-1", "seprom:11", "seprom:1.5", "seprom:abc", "seprom:", "seprom:1:2", "all:1", "seprom:99999999999999999999"]:
		await request(client, revision + 1, "sell", subject)
		check(store.pilots["pilot0"]["credits"] == 1000 and store.pilots["pilot0"]["cargo"]["starter"] == hold and store.pilots["pilot0"]["equipment"]["revision"] == revision, "Reject malformed or unavailable amount: " + subject)
	await click_control(client, shop.sells["seprom"])
	check(client.cargo["seprom"] == 7 and client.credits == 1192 and store.pilots["pilot0"]["cargo"]["starter"]["seprom"] == 7, "Selected-quantity button saves and replicates exactly three sold units")
	check(shop.selected["seprom"] == 3 and shop.held["seprom"].text == "In hold: 7", "Partial sale preserves the smaller selection and updates held amount")
	await request(client, revision + 1, "sell", "seprom:3")
	check(client.credits == 1192 and client.cargo["seprom"] == 7, "Repeated partial sale cannot pay twice")
	shop.set_quantity("seprom", 999)
	await settle()
	check(shop.selected["seprom"] == 7, "Quantity cannot exceed remaining cargo")
	shop.set_quantity("seprom", 0)
	await settle()
	check(shop.sells["seprom"].disabled and shop.decreases["seprom"].disabled, "Zero selection disables selling and decrement")
	check(store.commit({"pilot0": PilotStore.MAX_CREDITS - 3}), "Seed wallet space for a partial sale")
	combat.records[id]["credits"] = PilotStore.MAX_CREDITS - 3
	combat.publish_inventory(id)
	await settle()
	shop.set_quantity("endurium", 2)
	await settle()
	check(shop.sells["endurium"].disabled, "Selected amount exceeding remaining wallet space is disabled")
	await request(client, revision + 2, "sell", "endurium:2")
	check(client.cargo["endurium"] == 10 and client.credits == PilotStore.MAX_CREDITS - 3, "Server rejects an overflowing partial sale without removing cargo")
	shop.set_quantity("endurium", 1)
	await settle()
	check(not shop.sells["endurium"].disabled, "A smaller affordable sale is enabled even when selling the whole type is blocked")
	check(store.commit({"pilot0": 1192}), "Restore the sale fixture wallet")
	combat.records[id]["credits"] = 1192
	combat.publish_inventory(id)
	await settle()
	client.get_viewport().size = Vector2i(1440, 900)
	await settle()
	await screenshot(client, "resource-shop-large")
	check(shop.get_global_rect().position.x >= 0 and shop.get_global_rect().end.x <= 1440, "Trading fits the larger viewport")
	client.get_viewport().size = Vector2i(960, 600)
	shop.close()
