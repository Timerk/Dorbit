extends "res://tests/equipment_test.gd"
## Reference catalog exercised through real purchases, fittings, combat and restart.

const EXPECTED := {
	# Credits, damage, shield, absorption, speed. Prices follow the supplied references.
	"laser": [10000, 65, 0, 0.0, 0], "mp-1": [40000, 70, 0, 0.0, 0],
	"lf-2": [500000, 140, 0, 0.0, 0], "lf-3": [1000000, 175, 0, 0.0, 0],
	"lf-4": [0, 200, 0, 0.0, 0],
	"shield": [8000, 0, 1000, 0.4, 0], "sg3n-a02": [16000, 0, 2000, 0.5, 0],
	"fs-01": [256000, 0, 3200, 0.7, 0], "sg3n-a03": [128000, 0, 5000, 0.6, 0],
	"sg3n-b00": [0, 0, 9000, 0.7, 0], "sg3n-b01": [250000, 0, 9500, 0.7, 0],
	"sg3n-b02": [1000000, 0, 10000, 0.8, 0],
	"g3n-1010": [2000, 0, 0, 0.0, 2], "g3n-2010": [4000, 0, 0, 0.0, 3],
	"g3n-3210": [8000, 0, 0, 0.0, 4], "g3n-3310": [16000, 0, 0, 0.0, 5],
	"g3n-6900": [100000, 0, 0, 0.0, 7], "g3n-7900": [200000, 0, 0, 0.0, 10],
}


func run() -> void:
	var server := make_sector("ReferenceServer", true, 24743)
	var store := server.session.store
	check(store.commit({"pilot0": 6000000}), "Fund a disposable catalog test pilot")
	var client := make_sector("ReferencePilot")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24743))
	await settle(0.5)
	await replicate(server)
	check(client.session.active, "Reference pilot authenticates")
	if not client.session.active:
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var combat := client.session.combat
	var sequence := 0
	var wallet := client.credits
	var owned: Dictionary[String, String] = {}
	check(Equipment.catalog_models() == EXPECTED.keys() and not client.shop.cards.has("engine"), "Catalog contains the 18 requested models and hides the legacy engine")
	for model: String in EXPECTED:
		var reference: Array = EXPECTED[model]
		var info: Dictionary = Equipment.MODELS[model]
		check(info["price"] == reference[0] and info["damage"] == reference[1] and info["shield"] == reference[2] and is_equal_approx(info.get("absorption", 0.0), reference[3]) and info["speed"] == reference[4], "Reference values: " + info["name"])
		if model in ["lf-4", "sg3n-b00"]:
			var before := FileAccess.get_file_as_string(store.path)
			await request(client, sequence + 1, "buy", model)
			check(combat.station_message.contains("Unavailable") and combat.inventory["revision"] == sequence and conserved_ledger(FileAccess.get_file_as_string(store.path)) == conserved_ledger(before), "Server rejects unavailable " + info["name"] + " without changing saved ownership or currency")
			continue
		sequence += 1
		var item_id := "purchase-%d" % sequence
		owned[model] = item_id
		await request(client, sequence, "buy", model)
		wallet -= int(reference[0])
		check(store.pilots["pilot0"]["credits"] == wallet and combat.inventory["items"].get(item_id) == {"model": model, "ship": "", "slot": ""}, "Purchase commits the reference price and stored " + info["name"])
		await request(client, sequence, "buy", model)
		check(store.pilots["pilot0"]["credits"] == wallet and combat.inventory["revision"] == sequence, "Duplicate " + info["name"] + " purchase cannot charge again")
		sequence += 1
		await request(client, sequence, "fit", item_id, "starter", "laser2" if info["kind"] == "laser" else "generator3")
		await replicate(server)
		var expected_absorption: float = (400.0 + float(reference[2]) * float(reference[3])) / (1000.0 + float(reference[2]))
		check(ship.laser_damage == 65 + reference[1] and ship.max_shield == 1000 + reference[2] and is_equal_approx(ship.shield_absorption, expected_absorption) and ship.cruise_speed == 41 + reference[4] and ship.boost_speed == 83 + reference[4], "Fitted " + info["name"] + " affects authoritative stats")
		check(client.player.laser_damage == ship.laser_damage and client.player.max_shield == ship.max_shield and is_equal_approx(client.player.shield_absorption, ship.shield_absorption) and client.player.cruise_speed == ship.cruise_speed, "Fitted " + info["name"] + " replicates to the pilot")
		check(ship.shield == 1000, "Installing " + info["name"] + " never refills shield charge")
		sequence += 1
		await request(client, sequence, "fit", item_id)
	check(Equipment.stats(combat.inventory) == Equipment.stats(Equipment.starter()), "Stored equipment has no effect and the original starter fitting survives")
	await request(client, sequence + 1, "buy", "engine")
	check(combat.inventory["revision"] == sequence and combat.station_message.contains("Starter equipment"), "Legacy Ion engines remain valid but cannot be purchased")
	for entry: Array in [["lf-3", "laser2"], ["fs-01", "generator3"], ["sg3n-b02", "generator5"], ["g3n-7900", "generator6"]]:
		sequence += 1
		await request(client, sequence, "fit", owned[entry[0]], "starter", entry[1])
	sequence += 1
	await request(client, sequence, "buy", "fs-01")
	var second_fusion := "purchase-%d" % sequence
	sequence += 1
	await request(client, sequence, "fit", second_fusion, "starter", "generator4")
	await replicate(server)
	check(ship.laser_damage == 240 and ship.npc_laser_damage == 26.25 and client.player.npc_laser_damage == 26.25, "LF-3 adds 175 base damage and 15% alien damage without multiplying other lasers")
	var doubled := combat.inventory.duplicate(true)
	doubled["items"]["second-lf3"] = {"model": "lf-3", "ship": "starter", "slot": "laser3"}
	check(Equipment.valid(doubled) and Equipment.stats(doubled)["damage"] == 415 and Equipment.stats(doubled)["npc_damage"] == 52.5, "Each LF-3 contributes its own fractional bonus in a mixed fitting")
	check(ship.max_shield == 17400 and is_equal_approx(ship.shield_absorption, 12880.0 / 17400.0), "Mixed shield absorption is capacity-weighted")
	check(ship.shield_regen_bonus == 0.125 and client.player.shield_regen_bonus == 0.125, "Two FS-01 bonuses add to 12.5% and replicate")
	check(ship.cruise_speed == 51 and ship.boost_speed == 93, "Reference engine stacks with the existing starter engine")
	ship.shield = 20
	ship.time_since_hit = 5.0
	ship.tick_combat(0.5)
	check(ship.shield == 20, "Fusion shields respect the existing recovery delay")
	ship.time_since_hit = 6.0
	ship.tick_combat(1.0)
	check(is_equal_approx(ship.shield, 1651.25), "Fusion recovery multiplies the total shield regeneration rate")
	ship.shield = ship.max_shield - 1
	ship.tick_combat(1.0)
	check(ship.shield == ship.max_shield, "Fusion regeneration is capped at maximum capacity")
	ship.simulation_authority = false
	ship.shield = 20
	ship.tick_combat(1.0)
	check(ship.shield == 20, "Non-authoritative peers cannot regenerate locally")
	ship.simulation_authority = true
	ship.position = Vector3(0, 100, 0)
	ship.rotation = Vector3.ZERO
	server.alien.position = Vector3(0, 100, -100)
	server.alien.home_position = server.alien.position
	await physics_frame
	var health_before := server.alien.shield + server.alien.hull
	ship.shot_cooldown = 0
	check(ship.try_fire(server.alien) and is_equal_approx(health_before - server.alien.shield - server.alien.hull, 266.25), "Live shot applies LF-3 alien bonus exactly once")
	var target_ship := Pilot.new()
	target_ship.render_enabled = false
	server.add_child(target_ship)
	target_ship.position = Vector3(0, 100, -50)
	await physics_frame
	health_before = target_ship.shield + target_ship.hull
	ship.shot_cooldown = 0
	check(ship.try_fire(target_ship) and is_equal_approx(health_before - target_ship.shield - target_ship.hull, 240), "Alien bonus does not apply to ship targets")
	target_ship.queue_free()
	ship.position = Sector.SPAWN_POSITION
	ship.time_since_hit = 6
	await replicate(server)
	sequence += 1
	await request(client, sequence, "buy_ship", "phoenix")
	var phoenix := ShipCatalog.owned_id(combat.inventory, "phoenix")
	check(not phoenix.is_empty(), "Reference equipment pilot can purchase a ship through the combined catalog")
	sequence += 1
	await request(client, sequence, "switch_ship", phoenix)
	await replicate(server)
	check(ship.ship_model == "phoenix" and ship.npc_laser_damage == 0 and ship.shield_regen_bonus == 0 and client.player.npc_laser_damage == 0 and client.player.shield_regen_bonus == 0, "Switching to an empty hull clears both equipment bonuses on server and client")
	sequence += 1
	await request(client, sequence, "switch_ship", "starter", "", "", int(client.player.get_meta("life", 0)))
	await replicate(server)
	check(ship.ship_model == "liberator" and ship.npc_laser_damage == 26.25 and ship.shield_regen_bonus == 0.125 and ship.cruise_speed == 51 and client.player.npc_laser_damage == 26.25 and client.player.shield_regen_bonus == 0.125, "Returning to Liberator restores its own reference fitting and bonuses")
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if DisplayServer.get_name() != "headless":
		var screen := TextureRect.new()
		screen.texture = client.get_viewport().get_texture()
		root.add_child(screen)
		root.size = Vector2i(960, 600)
	client.shop.open()
	for model: String in ["lf-3", "lf-4", "fs-01", "sg3n-b00", "g3n-7900"]:
		client.shop.select_category(Equipment.category(model))
		client.shop.select_model(model)
		await settle()
		check(client.shop.product_title.text == Equipment.MODELS[model]["name"] and client.shop.bonus.text == StationUi.bonus(model), "Shop previews " + model + " with its actual bonuses")
		if model in ["lf-4", "sg3n-b00"]:
			check(client.shop.price.text == "Not for sale" and client.shop.buys[model].disabled and client.shop.availability.text.contains("Unavailable"), "Unavailable " + model + " has no credit offer")
			client.shop.buys[model].pressed.emit()
			check(not combat.station_pending and combat.inventory["revision"] == sequence, "Unavailable " + model + " cannot send a shop intent")
		await screenshot(client, "darkorbit-" + model)
	client.equipment_menu.open()
	await settle()
	check(client.equipment_menu.ship_stats.text.contains("+26.25 damage against aliens") and client.equipment_menu.ship_stats.text.contains("12.50%"), "Fitting screen explains both special bonuses")
	await screenshot(client, "darkorbit-fitting")
	var saved: Dictionary = combat.inventory.duplicate(true)
	client.session.disconnect_session("Reference restart")
	await settle()
	server.session.disconnect_session("Reference restart")
	check(server.session.host(test_port(24743)) == OK, "Server restarts with the expanded catalog save")
	client.session.join("127.0.0.1", test_port(24743))
	await settle(0.5)
	await replicate(server)
	check(combat.inventory == saved and client.player.npc_laser_damage == 26.25 and client.player.shield_regen_bonus == 0.125 and client.player.cruise_speed == 51, "Restart preserves every reference item, fitting and special bonus")
	finish()
