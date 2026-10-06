extends "res://tests/equipment_test.gd"
## Buy and activate the complete roster through authenticated station RPCs.


func transaction(client: Sector, action: String, subject: String, ship: String = "", slot: String = "") -> void:
	await request(client, int(client.session.combat.inventory["revision"]) + 1, action, subject, ship, slot, int(client.player.get_meta("life", 0)))


func run() -> void:
	check(ShipCatalog.MODELS.size() == 12, "Exactly the twelve PR 14 hulls are playable")
	var server := make_sector("ShipServer", true, 24736)
	check(server.session.store.commit({"pilot0": 100000000}), "Seed ship purchase budget")
	var client := make_sector("ShipPilot")
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if DisplayServer.get_name() != "headless":
		var screen := TextureRect.new()
		screen.texture = client.get_viewport().get_texture()
		root.add_child(screen)
		root.size = Vector2i(960, 600)
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", 24736)
	var observer := make_sector("ShipObserver")
	observer.session.credential_id = "pilot1"
	observer.session.credential_token = test_token(1)
	observer.session.join("127.0.0.1", 24736)
	await settle(0.6)
	await replicate(server)
	check(client.session.active and observer.session.active, "Both pilots authenticate")
	if not client.session.active or not observer.session.active:
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	var remote := server.session.ships[id]
	var store := server.session.store
	check(client.player.ship_model == "liberator" and client.cargo_capacity == 400, "Legacy Pathfinder loads as the modeled Liberator with its real cargo hold")
	await screenshot(client, "ships-liberator-flight")
	check(store.commit({"pilot0": 1}), "Temporarily restrict ship budget")
	await transaction(client, "buy_ship", "goliath")
	check(store.pilots["pilot0"]["credits"] == 1 and store.pilots["pilot0"]["equipment"]["revision"] == 0, "Insufficient ship funds preserve credits, ownership and revision")
	check(store.commit({"pilot0": 100000000}), "Restore ship purchase budget")
	var original: Dictionary = store.pilots["pilot0"].duplicate(true)
	await transaction(client, "buy_ship", "liberator")
	await transaction(client, "buy_ship", "unknown")
	await transaction(client, "switch_ship", "not-owned")
	check(store.pilots["pilot0"] == original, "Duplicate models, unknown ships and unowned switches cannot change the save")
	for model: String in ShipCatalog.MODELS:
		var entry := ShipCatalog.info(model)
		var scene := ShipCatalog.model_scene(model)
		check(scene.find_children("*", "MeshInstance3D", true, false).size() == 1 and scene.find_children("*", "Camera3D", true, false).is_empty() and scene.find_children("*", "Light3D", true, false).is_empty(), model + " imports one hull mesh with no studio")
		check(StationUi.texture(model) != null, model + " has a shop preview")
		scene.free()
		var data := client.session.combat.inventory
		var owned := ShipCatalog.owned_id(data, model)
		if owned.is_empty():
			var before: int = client.credits
			if model == "phoenix":
				client.shop.open()
				client.shop.select_category("ships")
				client.shop.select_model(model)
				await settle()
				client.shop.buys[model].pressed.emit()
				check(client.session.combat.station_pending, "Ship Buy control sends the purchase request")
				client.shop.buys[model].pressed.emit()
				await settle(0.2)
				check(client.session.combat.inventory["ships"].size() == 2, "Repeated Buy clicks add the free Phoenix only once")
				client.shop.close()
			else:
				await transaction(client, "buy_ship", model)
			data = client.session.combat.inventory
			owned = ShipCatalog.owned_id(data, model)
			check(not owned.is_empty() and client.credits == before - ShipCatalog.price(model), model + " purchase charges the authoritative credit price")
			check(data["active_ship"] == "starter" and store.pilots["pilot0"]["cargo"][owned].is_empty(), model + " purchase adds an empty hull without activating it")
			check(Equipment.stats(data, owned)["damage"] == 0 and Equipment.stats(data, owned)["shield"] == 0, model + " arrives with an empty fitting")
		var available := Equipment.slots(data, owned)
		check(available.values().count("laser") == entry["lasers"] and available.values().count("generator") == entry["generators"] and available.values().count("extra") == entry["extras"], model + " has its exact hull slot counts")
		if owned != "starter":
			remote.hull = 90000
			remote.energy = 42
			remote.shot_cooldown = 0.3
			remote.time_since_hit = 5
			var life: int = server.session.combat.records[id]["life"]
			if model == "phoenix":
				client.equipment_menu.open()
				client.equipment_menu.ship_choice.select(client.equipment_menu.owned_ships.find(owned))
				await settle()
				check(not client.equipment_menu.activate_button.disabled, "Owned-ship selector enables activation")
				client.equipment_menu.activate_button.pressed.emit()
				await settle(0.2)
			else:
				await transaction(client, "switch_ship", owned)
			check(remote.hull == 90000 and remote.energy == 42 and remote.shot_cooldown == 0.3 and remote.time_since_hit == 5, model + " switch grants no repair, boost or cooldown reset")
			check(server.session.combat.records[id]["life"] == life + 1 and not server.session.commands.has(id), model + " switch invalidates old flight and fire commands")
			await replicate(server)
			check(client.player.ship_model == model and observer.session.ships[id].ship_model == model and client.player.max_hull == entry["hull"] and observer.session.ships[id].max_hull == entry["hull"], model + " model and hull replicate to owner and observer")
			check(client.cargo_capacity == entry["cargo"] and is_equal_approx(remote.cruise_speed, entry["speed"] * 0.1), model + " uses its cargo capacity and proportional flight speed")
			client.equipment_menu.open()
			await settle()
			check(client.equipment_menu.slots.size() == available.size() and client.equipment_menu.ship_title.text == entry["name"].to_upper(), model + " fitting screen follows the active hull")
			check(Rect2(Vector2.ZERO, Vector2(960, 600)).encloses(client.equipment_menu.get_global_rect()), model + " fitting screen fits the minimum window")
			await screenshot(client, "ships-" + model + "-equipment")
			await transaction(client, "fit", "starter-laser", owned, "laser%d" % int(entry["lasers"]))
			check(remote.laser_damage == 65, model + " accepts equipment in its final laser slot")
			var revision: int = client.session.combat.inventory["revision"]
			await transaction(client, "fit", "starter-laser", owned, "laser%d" % (int(entry["lasers"]) + 1))
			check(client.session.combat.inventory["revision"] == revision, model + " rejects the next laser slot")
			await transaction(client, "fit", "starter-engine", owned, "generator%d" % int(entry["generators"]))
			check(is_equal_approx(remote.cruise_speed, entry["speed"] * 0.1 + 8), model + " accepts an engine in its final generator slot")
			await transaction(client, "fit", "starter-engine", owned, "generator%d" % (int(entry["generators"]) + 1))
			check(client.session.combat.station_message.contains("Incompatible"), model + " rejects the next generator slot")
			await transaction(client, "fit", "starter-laser", "starter", "laser1")
			await transaction(client, "fit", "starter-engine", "starter", "generator2")
			await transaction(client, "switch_ship", "starter")
			await replicate(server)
			client.equipment_menu.close()
	# Validate transaction replay and station restrictions on ship actions.
	var saved: Dictionary = store.pilots["pilot0"].duplicate(true)
	await request(client, int(saved["equipment"]["revision"]), "buy_ship", "goliath", "", "", int(remote.get_meta("life")))
	check(store.pilots["pilot0"] == saved, "Successful ship sequences cannot run twice")
	var goliath := ShipCatalog.owned_id(saved["equipment"], "goliath")
	for blocker in ["distance", "speed", "damage", "dead", "life"]:
		remote.position = Vector3(0, 0, 400) if blocker == "distance" else Sector.SPAWN_POSITION
		remote.velocity = Vector3(10, 0, 0) if blocker == "speed" else Vector3.ZERO
		remote.time_since_hit = 0 if blocker == "damage" else 5
		remote.alive = blocker != "dead"
		await request(client, int(saved["equipment"]["revision"]) + 1, "switch_ship", goliath, "", "", -1 if blocker == "life" else int(remote.get_meta("life")))
		check(store.pilots["pilot0"] == saved, "Server rejects ship switching for " + blocker)
	remote.alive = true
	remote.time_since_hit = 5
	check(store.commit({}, {}, {"pilot0": {"starter": {"seprom": 2}}.merged(saved["cargo"], false)}), "Seed cargo on the starter")
	await transaction(client, "switch_ship", goliath)
	await replicate(server)
	check(client.cargo.is_empty() and store.pilots["pilot0"]["cargo"]["starter"] == {"seprom": 2}, "Switching preserves cargo on its original ship")
	client.equipment_menu.close()
	await screenshot(client, "ships-goliath-flight")
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		client.shop.open()
		client.shop.select_category("ships")
		client.shop.select_model("goliath")
		await settle()
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(client.shop.get_global_rect()) and client.shop.get_global_rect().encloses(client.shop.buys["goliath"].get_global_rect()), "Ship catalog and purchase control fit at %s" % dimensions)
		await screenshot(client, "ships-shop-%d" % dimensions.x)
		client.equipment_menu.open()
		await settle()
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(client.equipment_menu.get_global_rect()), "Goliath fitting screen fits at %s" % dimensions)
		await screenshot(client, "ships-goliath-equipment-%d" % dimensions.x)
		client.equipment_menu.close()
	var large_holds: Dictionary = store.pilots["pilot0"]["cargo"].duplicate(true)
	large_holds[goliath] = {"prometium": 1200}
	check(store.commit({}, {}, {"pilot0": large_holds}), "Larger hull accepts four-digit cargo quantities")
	server.session.combat.publish_inventory(id)
	await settle()
	client.shop.open()
	client.shop.edit_quantity("prometium", "1200")
	check(client.shop.quantities["prometium"].max_length == 4 and client.shop.selected["prometium"] == 1200, "Cargo controls support four-digit sale quantities")
	var sale_balance: int = client.credits
	client.shop.sells["prometium"].pressed.emit()
	await settle(0.2)
	check(client.cargo.is_empty() and client.credits == sale_balance + 1200 and store.pilots["pilot0"]["cargo"]["starter"] == {"seprom": 2}, "Four-digit station sale pays exactly and preserves the inactive hull's cargo")
	client.shop.close()
	var late := make_sector("ShipLate")
	late.session.credential_id = "pilot2"
	late.session.credential_token = test_token(2)
	late.session.join("127.0.0.1", 24736)
	await settle(0.5)
	await replicate(server)
	check(late.session.ships[id].ship_model == "goliath" and late.session.ships[id].max_hull == 356000, "Late join gets the current model and hull")
	remote.take_damage(remote.max_hull + remote.max_shield + 1, server.alien)
	server.session.combat.tick(3.1)
	await replicate(server)
	check(client.player.alive and client.player.ship_model == "goliath" and client.player.hull == 356000, "Rescue retains the active hull and resets to its own maximum")
	var final: Dictionary = store.pilots["pilot0"].duplicate(true)
	client.session.disconnect_session("Restart")
	observer.session.disconnect_session("Restart")
	late.session.disconnect_session("Restart")
	await settle()
	server.session.disconnect_session("Restart")
	check(server.session.host(24736) == OK, "Server restarts with all purchased hulls")
	client.session.join("127.0.0.1", 24736)
	await settle(0.5)
	await replicate(server)
	check(server.session.store.pilots["pilot0"] == final and client.player.ship_model == "goliath" and client.session.combat.inventory["ships"].size() == 12, "Ownership, fittings, cargo, active hull and wallet survive restart")
	finish()
