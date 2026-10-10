extends "res://tests/shop_test.gd"
## Real server transactions, per-laser depletion, persistence, expiry and menu input.


func request(client: Sector, sequence: int, action: String, subject: String, ship: String = "", slot: String = "", life: int = 0) -> void:
	client.session.combat.station_request.rpc_id(1, sequence, action, subject, ship, slot, life)
	await settle(0.1)


func screenshot(client: Sector, label: String) -> void:
	await capture(client, label)


func type_upgrade_amount(client: Sector, text: String) -> void:
	var input := client.resource_workshop.upgrade_amount.get_line_edit()
	await click(client, input)
	input.select_all()
	var erase := InputEventKey.new()
	erase.keycode = KEY_BACKSPACE
	erase.pressed = true
	client.get_viewport().push_input(erase)
	for character in text:
		var event := InputEventKey.new()
		event.unicode = character.unicode_at(0)
		event.pressed = true
		client.get_viewport().push_input(event)
	await settle()


func check_refining_costs() -> void:
	for fixture: Array in [
		[{"prometium": 200, "endurium": 200, "terbium": 200}, 1, {"promerium": 1}],
		[{"prometid": 6, "duranium": 3, "prometium": 80, "endurium": 110, "terbium": 140, "seprom": 4}, 1, {"promerium": 1, "seprom": 4}],
		[{"prometid": 25, "duranium": 22, "prometium": 50, "endurium": 50, "terbium": 50}, 2, {"prometid": 5, "duranium": 2, "prometium": 50, "endurium": 50, "terbium": 50, "promerium": 2}],
	]:
		var hold: Dictionary = fixture[0].duplicate(true)
		check(ResourceBoosts.maximum(hold, "promerium") == fixture[1], "Max accounts for existing intermediates and raw ores: %s" % hold)
		check(ResourceBoosts.refine(hold, "promerium", fixture[1]).is_empty() and hold == fixture[2], "Refining uses existing intermediates first and creates only the missing units")
	var scarce := {"prometium": 400, "endurium": 300, "terbium": 400}
	var before := scarce.duplicate()
	check(ResourceBoosts.maximum(scarce, "promerium") == 1, "Max shares Endurium between both intermediate recipes")
	check(not ResourceBoosts.refine(scarce, "promerium", 2).is_empty() and scarce == before, "An unaffordable chain consumes no partial ingredients")
	for output: String in ["promerium", "seprom", "unknown"]:
		check(not ResourceBoosts.refine(scarce, output, 0).is_empty() and scarce == before, "Invalid chained refining preserves cargo: " + output)
	var plan := ResourceBoosts.refining_plan({"prometid": 6, "duranium": 3}, "promerium", 1)
	check(plan["intermediates"] == {"prometid": 4, "duranium": 7} and plan["consumed"] == {"prometid": 6, "duranium": 3, "prometium": 80, "endurium": 110, "terbium": 140}, "Preview lists actual cargo costs and exactly the missing intermediates")


func drag_resource(client: Sector, key: String, target: String, corner: bool = false) -> void:
	var viewport := client.get_viewport()
	var start := client.resource_workshop.upgrade_cards[key].get_global_rect().get_center()
	var destination: Control = client.resource_workshop.boost_icons[target] if corner else client.resource_workshop.groups[target]
	var finish := destination.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.position = start
	down.pressed = true
	viewport.push_input(down)
	await process_frame
	for point: Vector2 in [start + Vector2(20, 0), finish]:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.relative = point - start
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(motion)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = finish
	viewport.push_input(up)
	await settle()


func run() -> void:
	check_refining_costs()
	var server := make_sector("UpgradeServer", true, 24743)
	var client := make_sector("UpgradeClient")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24743))
	await settle(0.5)
	await replicate(server)
	var id := client.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	var store := server.session.store
	var combat := server.session.combat
	var menu := client.resource_workshop
	for key: String in ResourceBoosts.BONUSES:
		var boost := {"lasers": {"resource": key, "remaining": 1}}
		var expected: float = {"prometid": 0.15, "duranium": 0.0, "promerium": 0.30, "seprom": 0.60}[key]
		check(is_equal_approx(ResourceBoosts.laser_damage([{"damage": 100, "npc_damage": 0}], false, boost), 100 * (1 + expected)), "%s weapon bonus matches requested percentage" % key)
	check(store.pilots["pilot0"]["boosts"] == {"starter": {}}, "Legacy pilots migrate to empty boosts without losing cargo or fitting")
	var cargo := {"starter": {"prometium": 40, "endurium": 40, "terbium": 40, "prometid": 20, "duranium": 20, "promerium": 10, "seprom": 10}}
	check(store.commit({}, {}, {"pilot0": cargo}), "Seed isolated resource fixture")
	combat.cargo_holds[id] = cargo.duplicate(true)
	combat.publish_inventory(id)
	await settle()
	var before := store.pilots.duplicate(true)
	for args: Array in [["refine", "prometid:0", ""], ["refine", "prometid:-1", ""], ["refine", "prometid:1.5", ""], ["refine", "prometid:999999", ""], ["refine", "seprom:1", ""], ["refine", "promerium:3", ""], ["boost", "seprom:1", "engines"], ["boost", "prometid:1", "shields"], ["boost", "duranium:1", "rockets"], ["boost", "seprom:11", "lasers"]]:
		await request(client, 1, args[0], args[1], args[2])
		check(conserved_ledger(JSON.stringify({"pilots": store.pilots})) == conserved_ledger(JSON.stringify({"pilots": before})), "Invalid recipe, quantity or boost cannot consume cargo: %s" % str(args))
	for reason: String in ["distance", "speed", "damage", "life"]:
		ship.position = Vector3(0, 100, 0) if reason == "distance" else combat.records[id]["spawn"]
		ship.velocity = Vector3(9, 0, 0) if reason == "speed" else Vector3.ZERO
		ship.time_since_hit = 0 if reason == "damage" else 6
		await request(client, 1, "refine", "prometid:1", "", "", 99 if reason == "life" else 0)
		check(conserved_ledger(JSON.stringify({"pilots": store.pilots})) == conserved_ledger(JSON.stringify({"pilots": before})), "Refining validates authoritative " + reason)
	ship.time_since_hit = 6
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	client.main_menu.select_page("refining")
	await settle()
	await click(client, menu.resource_cards["prometid"])
	await click(client, menu.refine_amount.get_parent().get_child(1))
	check(menu.refine_amount.value == 2 and menu.recipe.text.contains("40 Prometium"), "Max quantity previews the exact batch ingredients before confirmation")
	client.session.combat.station_message = "" # Capture the current recipe without earlier rejection feedback.
	await screenshot(client, "refining-ready")
	await click(client, menu.refine_button)
	check(client.cargo["prometid"] == 22 and not client.cargo.has("prometium") and client.cargo["endurium"] == 20, "Refine selected amount consumes exactly 20 Prometium + 10 Endurium per output")
	await request(client, 1, "refine", "prometid:2")
	check(client.cargo["prometid"] == 22 and store.pilots["pilot0"]["equipment"]["revision"] == 1, "Duplicate refining consumes no additional ingredients")
	await request(client, 2, "refine", "duranium:2")
	check(client.cargo["duranium"] == 22 and not client.cargo.has("endurium") and not client.cargo.has("terbium"), "Duranium consumes exactly 10 Endurium + 20 Terbium")
	await request(client, 3, "refine", "promerium:2")
	check(client.cargo["promerium"] == 12 and client.cargo["prometid"] == 2 and client.cargo["duranium"] == 2, "Promerium consumes 10 of each intermediate without Xenomit")
	for dimensions: Vector2i in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		client.main_menu.select_page("refining")
		await settle()
		check(menu.visible and client.main_menu.content_rect().encloses(menu.get_global_rect()), "Refining fits the shared menu at %s" % dimensions)
		await click(client, menu.tabs["refining"])
		await click(client, menu.resource_cards["promerium"])
		check(menu.output == "promerium" and menu.refine_button.disabled, "Real recipe selection previews unavailable ingredients without consuming cargo")
		await screenshot(client, "refining-%d" % dimensions.x)
		await click(client, menu.tabs["update"])
		await click(client, menu.groups["rockets"])
		check(not menu.upgrade_button.disabled and menu.upgrade_description.text.contains("boosted rockets"), "Rocket preview enables compatible resources")
		var held := client.cargo.duplicate(true)
		await drag_resource(client, "promerium", "rockets")
		check(client.cargo == held and menu.group == "rockets" and not menu.upgrade_button.disabled, "Rocket drops enable confirmation without consuming cargo")
		await screenshot(client, "rocket-upgrades-%d" % dimensions.x)
		await click(client, menu.groups["engines"])
		await drag_resource(client, "seprom", "engines")
		check(menu.group == "engines" and client.cargo == held and menu.upgrade_button.disabled, "Incompatible Seprom engine drop cannot apply a boost")
		await drag_resource(client, "promerium", "shields")
		check(menu.group == "shields" and menu.resource == "promerium" and client.cargo == held and client.player.resource_boosts.is_empty(), "Compatible drop selects equipment and resource without spending before confirmation")
		for key: String in menu.groups:
			check(menu.get_global_rect().encloses(menu.groups[key].get_global_rect()) and menu.groups[key].get_global_rect().encloses(menu.boost_icons[key].get_global_rect()), "Equipment card and corner badge fit at %s: %s" % [dimensions, key])
		await drag_resource(client, "seprom", "lasers")
		check(menu.group == "lasers" and menu.resource == "seprom" and menu.boost_icons["lasers"].texture == null, "Resource bar stays draggable across categories and empty badge does not preview an unconfirmed boost")
		await type_upgrade_amount(client, "9999")
		check(menu.upgrade_amount.value == 10 and menu.upgrade_amount.get_line_edit().text == "10" and client.cargo == held, "Typed boost amounts clamp immediately to current cargo without spending resources")
		await click(client, menu.upgrade_amount.get_parent().get_child(1))
		check(menu.upgrade_amount.value == 10, "Boost Max uses current stock")
		menu.select_resource("duranium")
		check(menu.upgrade_amount.max_value == 2 and menu.upgrade_amount.value <= 2, "Changing resource immediately updates the input cap")
		menu.select_resource("seprom")
		menu.upgrade_amount.value = 1
		await screenshot(client, "resource-upgrades-%d" % dimensions.x)
	menu.upgrade_amount.value = 10
	var reduced_cargo: Dictionary = store.pilots["pilot0"]["cargo"].duplicate(true)
	reduced_cargo["starter"]["seprom"] = 3
	check(store.commit({}, {}, {"pilot0": reduced_cargo}), "Reduce selected resource through an authoritative cargo update")
	combat.cargo_holds[id] = reduced_cargo.duplicate(true)
	combat.publish_inventory(id)
	await settle()
	check(menu.upgrade_amount.value == 3 and menu.upgrade_amount.max_value == 3 and menu.upgrade_amount.get_line_edit().text == "3", "A cargo update clamps an already-entered amount down to the new stock")
	reduced_cargo["starter"]["seprom"] = 10
	check(store.commit({}, {}, {"pilot0": reduced_cargo}), "Restore resource fixture after quantity-cap check")
	combat.cargo_holds[id] = reduced_cargo.duplicate(true)
	combat.publish_inventory(id)
	await settle()
	var drop := {"boost_resource": "seprom", "workshop": menu}
	client.session.combat.station_pending = true
	check(not menu.can_drop_resource(Vector2.ZERO, drop, "lasers") and menu.resource_drag(Vector2.ZERO, "seprom") == null, "Pending server action blocks new resource drags and drops")
	client.session.combat.station_pending = false
	check(not menu.can_drop_resource(Vector2.ZERO, {"equipment_item": "laser"}, "lasers"), "Equipment inventory drags cannot be treated as boost resources")
	menu.upgrade_amount.value = 1
	await click(client, menu.upgrade_button)
	await replicate(server)
	check(client.player.resource_boosts["lasers"] == {"resource": "seprom", "remaining": 10} and client.cargo["seprom"] == 9, "Update button consumes one unit for ten individual rounds")
	check(menu.upgrade_amount.max_value == 9, "Server cargo changes reduce the boost amount cap")
	check(menu.boost_icons["lasers"].texture.resource_path.ends_with("seprom.png") and menu.reserve_labels["lasers"].text.contains("10 rounds"), "Confirmed laser boost shows Seprom in its corner badge and remaining rounds")
	await drag_resource(client, "prometid", "lasers", true)
	check(menu.replace_warning.visible and menu.upgrade_button.disabled and menu.upgrade_description.text.contains("WARNING"), "Changing resource requires an explicit warning and confirmation")
	check(menu.boost_icons["lasers"].texture.resource_path.ends_with("seprom.png"), "Replacement preview retains the currently applied resource icon")
	before = store.pilots.duplicate(true)
	await request(client, 5, "boost", "prometid:1", "lasers")
	check(conserved_ledger(JSON.stringify({"pilots": store.pilots})) == conserved_ledger(JSON.stringify({"pilots": before})), "Server rejects an unconfirmed replacement")
	await click(client, menu.replace_warning)
	await click(client, menu.upgrade_button)
	check(client.player.resource_boosts["lasers"]["resource"] == "prometid" and client.player.resource_boosts["lasers"]["remaining"] == 10, "Confirmed replacement discards the old reserve")
	check(menu.boost_icons["lasers"].texture.resource_path.ends_with("prometid.png"), "Confirmed replacement changes the active corner resource icon")
	await request(client, 6, "boost", "prometid:1", "lasers")
	check(client.player.resource_boosts["lasers"]["remaining"] == 20 and ResourceBoosts.bonus(ship.resource_boosts, "lasers") == 0.15, "Same resource adds rounds without stacking percentage")
	check(menu.resource_drag(Vector2.ZERO, "prometid") == null, "Empty resource card cannot start a drag")
	check(menu.upgrade_amount.value == 0 and menu.upgrade_amount.max_value == 0 and not menu.upgrade_amount.editable and menu.upgrade_button.disabled, "Empty stock shows zero and disables amount input and applying boosts")
	await click(client, menu.upgrade_amount.get_parent().get_child(1))
	check(menu.upgrade_amount.value == 0, "Max cannot select resources from empty stock")
	await request(client, 7, "boost", "duranium:1", "shields")
	await request(client, 8, "boost", "duranium:1", "engines")
	await replicate(server)
	check(menu.boost_icons["shields"].texture.resource_path.ends_with("duranium.png") and menu.boost_icons["engines"].texture.resource_path.ends_with("duranium.png"), "Each timed equipment card shows its own authoritative resource")
	check(is_equal_approx(ship.max_shield, 1100) and is_equal_approx(ship.cruise_speed, 45.1) and is_equal_approx(ship.boost_speed, 91.3), "Shield and engine boosts multiply the fitted capacity and cruise/boost speed")
	check(ship.shield == 1000 and ship.shield_absorption == 0.4, "Applying a shield boost does not grant charge or change absorption")
	combat.tick(30)
	check(is_equal_approx(ResourceBoosts.remaining(ship.resource_boosts, "engines"), 570), "Online authoritative time reduces the duration by exactly thirty seconds")
	check(is_equal_approx(store.pilots["pilot0"]["boosts"]["starter"]["engines"]["remaining"], 570), "Periodic checkpoint saves remaining online duration")
	check(is_equal_approx(client.player.max_shield, 1100) and is_equal_approx(client.player.cruise_speed, ship.cruise_speed), "Effective timed stats replicate to clients")
	var payload: Dictionary = client.session.goals[id].duplicate(true)
	payload["contracts"] = {}
	for offer: String in HuntingContracts.OFFERS:
		payload["contracts"][offer] = HuntingContracts.accept(offer)
	print("Boosted pilot with three contracts: %d bytes" % var_to_bytes([{id: payload}, {}, 1]).size())
	check(var_to_bytes([{id: payload}, {}, 1]).size() < 1400 and not payload.has("boosts"), "Three concurrent contracts retain the existing world packet size below ENet's MTU")
	check(var_to_bytes([ship.resource_boosts, 1, 8]).size() < 600, "Owner boost reserves fit one small packet independently of contracts")
	var owner_boosts := client.player.resource_boosts.duplicate(true)
	client.session.combat.boost_state({}, client.session.combat.boost_sequence - 1, int(client.session.combat.inventory["revision"]))
	client.session.combat.boost_state({}, client.session.combat.boost_sequence + 1, int(client.session.combat.inventory["revision"]) - 1)
	check(client.player.resource_boosts == owner_boosts, "Old boost packets and prior inventory revisions cannot roll back reserves")
	await request(client, 9, "replace_boost", "seprom:1", "lasers")
	await request(client, 10, "replace_boost", "promerium:1", "shields")
	var remaining_time := ResourceBoosts.remaining(ship.resource_boosts, "shields")
	await request(client, 11, "boost", "promerium:2", "shields")
	check(ResourceBoosts.remaining(ship.resource_boosts, "shields") > remaining_time + 1198 and is_equal_approx(ship.max_shield, 1200), "More resources add exactly ten minutes per unit at a fixed capacity bonus")
	# Fitting multiple lasers includes each LF-3's alien bonus before its resource multiplier.
	var next := store.pilots.duplicate(true)
	for index in [2, 3, 4]:
		next["pilot0"]["equipment"]["items"]["test-laser%d" % index] = {"model": "lf-3" if index == 2 else "laser", "ship": "starter", "slot": "laser%d" % index}
	check(store.persist(next), "Save four-laser fixture")
	combat.apply_equipment(id)
	ship.position = Vector3(0, 100, 0)
	ship.rotation = Vector3.ZERO
	var alien := server.alien
	alien.position = Vector3(0, 100, -100)
	alien.home_position = alien.position
	alien.max_hull = 100000
	alien.reset_health()
	await physics_frame
	var expected_base := 65.0 * 3 + 201.25
	var grant := ship.ammo.duplicate()
	grant["x2"] = 20
	check(store.commit({}, {}, {}, {"pilot0": grant}), "Seed ammunition for combined boost volleys")
	ship.ammo = grant
	ship.ammo_type = "x2"
	for volley in range(3):
		ship.shot_cooldown = 0
		var health := alien.hull + alien.shield
		check(ship.try_fire(alien), "Authoritative boosted volley %d fires" % volley)
		var expected := expected_base * 1.6 if volley < 2 else expected_base + (65.0 + 201.25) * 0.6
		check(is_equal_approx(health - alien.hull - alien.shield, expected * 2), "Volley %d combines x2 ammunition with partial boost reserves and LF-3 NPC damage" % volley)
		check(ResourceBoosts.remaining(ship.resource_boosts, "lasers") == maxi(0, 10 - (volley + 1) * 4), "Four installed lasers consume four rounds per volley")
		check(ship.ammo["x2"] == 20 - (volley + 1) * 4 and store.pilots["pilot0"]["ammo"]["x2"] == ship.ammo["x2"], "Ammunition and boost debit persist together")
	check(not store.pilots["pilot0"]["boosts"]["starter"].has("lasers"), "Depleted laser reserve is persisted before damage")
	await replicate(server)
	check(menu.boost_icons["lasers"].texture == null and menu.reserve_labels["lasers"].text == "0 rounds", "Depleting laser rounds clears the corner badge")
	# Range, cooldown and client authority cannot spend boosted rounds.
	ship.position = combat.records[id]["spawn"]
	ship.velocity = Vector3.ZERO
	ship.time_since_hit = 6
	await request(client, 12, "boost", "seprom:2", "lasers")
	var insufficient := ship.ammo.duplicate()
	insufficient["x2"] = 3
	check(store.commit({}, {}, {}, {"pilot0": insufficient}), "Seed incomplete ammunition volley")
	ship.ammo = insufficient
	ship.position = Vector3(0, 100, 0)
	var blocked_health := alien.hull + alien.shield
	ship.shot_cooldown = 0
	check(not ship.try_fire(alien) and ship.ammo["x2"] == 3 and ResourceBoosts.remaining(ship.resource_boosts, "lasers") == 20 and alien.hull + alien.shield == blocked_health, "Insufficient ammunition preserves boost rounds and damage")
	ship.ammo_type = "x1"
	ship.position = Vector3(0, 100, 1000)
	ship.shot_cooldown = 0
	check(not ship.try_fire(alien) and ResourceBoosts.remaining(ship.resource_boosts, "lasers") == 20, "Blocked shots consume no rounds")
	check(not client.player.try_fire(client.alien), "Clients cannot spend authoritative boost reserves or apply damage")
	ship.shot_cooldown = 1
	ship.position = Vector3(0, 100, 0)
	check(not ship.try_fire(alien) and ResourceBoosts.remaining(ship.resource_boosts, "lasers") == 20, "Cooldown consumes no rounds")
	ship.position = combat.records[id]["spawn"]
	ship.shot_cooldown = 0
	ship.time_since_hit = 6
	await replicate(server)
	client.main_menu.select_page("refining")
	menu.select_tab("update")
	menu.select_group("shields")
	menu.select_resource("seprom")
	await settle()
	await screenshot(client, "resource-upgrades-active")
	var saved_cargo: Dictionary = store.pilots["pilot0"]["cargo"].duplicate(true)
	combat.tick(0.25)
	var saved_duration := ResourceBoosts.remaining(ship.resource_boosts, "shields")
	client.session.disconnect_session("Restart")
	await settle()
	server.session.disconnect_session("Restart")
	check(server.session.host(test_port(24743)) == OK, "Restart resource-upgrade server")
	client.session.join("127.0.0.1", test_port(24743))
	await settle(0.5)
	await replicate(server)
	store = server.session.store
	id = client.multiplayer.get_unique_id()
	ship = server.session.ships[id]
	check(store.pilots["pilot0"]["cargo"] == saved_cargo and ResourceBoosts.remaining(ship.resource_boosts, "lasers") == 20 and is_equal_approx(ship.max_shield, 1200), "Restart preserves cargo, remaining rounds and timed boosts")
	check(is_equal_approx(ResourceBoosts.remaining(ship.resource_boosts, "shields"), saved_duration), "Disconnect flushes sub-checkpoint time; offline time consumes none")
	await request(client, 12, "boost", "seprom:2", "lasers")
	check(ResourceBoosts.remaining(ship.resource_boosts, "lasers") == 20, "Restart preserves duplicate-boost protection")
	client.main_menu.select_page("refining")
	menu.select_tab("update")
	await settle()
	var expired: Dictionary = store.pilots["pilot0"]["boosts"].duplicate(true)
	for key: String in ["shields", "engines"]:
		expired["starter"][key]["remaining"] = 0.001
	check(store.commit({}, {}, {}, {}, {"pilot0": expired}), "Save timed-expiry fixture")
	server.session.combat.apply_equipment(id)
	server.session.combat.tick(0.01)
	await replicate(server)
	check(ship.max_shield == 1000 and ship.shield <= 1000 and ship.cruise_speed == 41 and client.player.max_shield == 1000, "Expired timed boosts return to fitted stats, clamp excess charge and replicate")
	check(ResourceBoosts.remaining(ship.resource_boosts, "lasers") == 20, "Timed expiry leaves weapon rounds alone")
	check(menu.boost_icons["shields"].texture == null and menu.boost_icons["engines"].texture == null and menu.boost_icons["lasers"].texture.resource_path.ends_with("seprom.png"), "Timer expiry clears only the expired equipment icons")
	var fleet := store.pilots.duplicate(true)
	fleet["pilot0"]["equipment"]["ships"]["spare"] = "phoenix"
	fleet["pilot0"]["cargo"]["spare"] = {}
	fleet["pilot0"]["boosts"]["spare"] = {"engines": {"resource": "promerium", "remaining": 30}}
	fleet["pilot0"]["boosts"]["starter"]["shields"] = {"resource": "duranium", "remaining": 300}
	check(store.persist(fleet), "Save isolated second-hull boost fixture")
	server.session.combat.apply_equipment(id)
	await request(client, 13, "switch_ship", "spare")
	check(ship.resource_boosts.has("engines") and not ship.resource_boosts.has("lasers"), "Ship activation loads only that hull's boost reserve")
	server.session.combat.tick(10)
	check(ResourceBoosts.remaining(ship.resource_boosts, "engines") == 20 and store.pilots["pilot0"]["boosts"]["starter"]["shields"]["remaining"] == 300, "Only active-hull timers consume online time")
	await request(client, 14, "switch_ship", "starter", "", "", 1)
	check(ResourceBoosts.remaining(ship.resource_boosts, "lasers") == 20 and ship.max_shield == 1100, "Switching back restores the original laser rounds and shield boost")
	server.session.combat.tick(1)
	var current_time := ResourceBoosts.remaining(ship.resource_boosts, "shields")
	await request(client, 15, "boost", "seprom:99", "lasers", "", 2)
	check(ResourceBoosts.remaining(ship.resource_boosts, "shields") == current_time, "Rejected actions cannot restore time from an older checkpoint")
	# Quantity purchases must checkpoint live boosts while preserving their reserves.
	check(store.commit({"pilot0": 100000}), "Fund isolated batch-purchase fixture")
	await request(client, 15, "buy", "laser:2", "", "", 2)
	var purchased: Dictionary = store.pilots["pilot0"]
	check(purchased["equipment"]["items"].has("purchase-15") and purchased["equipment"]["items"].has("purchase-15-2") and purchased["credits"] == 80000, "Quantity purchases remain atomic alongside resource upgrades")
	check(ResourceBoosts.remaining(ship.resource_boosts, "shields") == current_time and purchased["boosts"]["starter"]["shields"]["remaining"] == current_time and ResourceBoosts.remaining(ship.resource_boosts, "lasers") == 20, "Batch purchase saves live shield time without changing remaining laser rounds")
	# A larger test hull can hold the 600 raw ore units needed for one Promerium.
	var raw_fixture := store.pilots.duplicate(true)
	raw_fixture["pilot0"]["equipment"]["ships"]["starter"] = "goliath"
	raw_fixture["pilot0"]["cargo"]["starter"] = {"prometium": 200, "endurium": 200, "terbium": 200, "seprom": 5}
	check(store.persist(raw_fixture), "Seed authenticated raw-only refining fixture")
	server.session.combat.cargo_holds[id] = raw_fixture["pilot0"]["cargo"].duplicate(true)
	server.session.combat.apply_equipment(id)
	server.session.combat.publish_inventory(id)
	await replicate(server)
	client.main_menu.select_page("refining")
	menu.select_tab("refining")
	menu.select_output("promerium")
	await settle()
	check(not menu.refine_button.disabled and menu.recipe.text.contains("200 Endurium") and menu.recipe.text.contains("AUTO-REFINES") and menu.recipe.text.contains("10 Prometid + 10 Duranium"), "Raw-only cargo enables Promerium and previews both intermediate steps")
	await click(client, menu.refine_amount.get_parent().get_child(1))
	check(menu.refine_amount.value == 1, "Refining Max includes automatically produced intermediates")
	for dimensions: Vector2i in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		await settle()
		check(menu.get_global_rect().encloses(menu.recipe.get_global_rect()) and menu.get_global_rect().encloses(menu.refine_button.get_global_rect()), "Automatic recipe and confirmation fit at %s" % dimensions)
		await screenshot(client, "refining-auto-intermediates-%d" % dimensions.x)
	await click(client, menu.refine_button)
	check(client.cargo == {"promerium": 1, "seprom": 5} and store.pilots["pilot0"]["cargo"]["starter"] == client.cargo, "One confirmed server transaction refines raw ores through both intermediates into Promerium")
	await request(client, 16, "refine", "promerium:1", "", "", 2)
	check(client.cargo == {"promerium": 1, "seprom": 5}, "Duplicate chained refining cannot consume cargo again")
	client.session.disconnect_session("Chained refining restart")
	await settle()
	server.session.disconnect_session("Chained refining restart")
	check(server.session.host(test_port(24743)) == OK, "Restart chained refining server")
	client.session.join("127.0.0.1", test_port(24743))
	await settle(0.5)
	await replicate(server)
	store = server.session.store
	check(client.cargo == {"promerium": 1, "seprom": 5}, "Restart retains the completed chain without intermediate leftovers")
	id = client.multiplayer.get_unique_id()
	var mixed_cargo: Dictionary = store.pilots["pilot0"]["cargo"].duplicate(true)
	mixed_cargo["starter"] = {"prometid": 6, "duranium": 3, "prometium": 80, "endurium": 110, "terbium": 140, "seprom": 5}
	check(store.commit({}, {}, {"pilot0": mixed_cargo}), "Seed authenticated mixed-ingredient refining fixture")
	server.session.combat.cargo_holds[id] = mixed_cargo.duplicate(true)
	server.session.combat.publish_inventory(id)
	await replicate(server)
	client.main_menu.select_page("refining")
	menu.select_tab("refining")
	menu.select_output("promerium")
	for dimensions: Vector2i in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		await settle()
		check(menu.recipe.text.contains("4 Prometid + 7 Duranium") and menu.get_global_rect().encloses(menu.refine_button.get_global_rect()), "Mixed recipe previews only missing intermediates and fits at %s" % dimensions)
		await screenshot(client, "refining-mixed-intermediates-%d" % dimensions.x)
	await click(client, menu.refine_button)
	check(client.cargo == {"promerium": 1, "seprom": 5}, "Authenticated mixed refining consumes existing intermediates before making their shortfall")
	# Save failures must leave both cargo and reserves untouched.
	var failed_dir := store.path.get_base_dir().path_join("boost-failure")
	DirAccess.make_dir_absolute(failed_dir)
	var file := FileAccess.open(failed_dir.path_join("pilots.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 7, "pilots": {"pilot0": store.pilots["pilot0"]}}))
	file.close()
	var probe := PilotStore.new()
	check(probe.open(failed_dir), "Open isolated failure ledger")
	before = probe.pilots.duplicate(true)
	DirAccess.make_dir_absolute(probe.path + ".tmp")
	probe.transact("pilot0", int(probe.pilots["pilot0"]["equipment"]["revision"]) + 1, "boost", "seprom:1", "lasers", "")
	check(probe.failed and probe.pilots == before, "Failed boost persistence consumes neither resource nor reserve")
	probe.close()
	var failed_refine_dir := store.path.get_base_dir().path_join("refining-failure")
	DirAccess.make_dir_absolute(failed_refine_dir)
	file = FileAccess.open(failed_refine_dir.path_join("pilots.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 7, "pilots": {"pilot0": raw_fixture["pilot0"]}}))
	file.close()
	probe = PilotStore.new()
	check(probe.open(failed_refine_dir), "Open isolated chained refining failure ledger")
	before = probe.pilots.duplicate(true)
	var disk_before := FileAccess.get_file_as_string(probe.path)
	DirAccess.make_dir_absolute(probe.path + ".tmp")
	probe.transact("pilot0", 16, "refine", "promerium:1", "", "")
	check(probe.failed and probe.pilots == before and FileAccess.get_file_as_string(probe.path) == disk_before, "Failed chained refining persistence consumes no ores or intermediates")
	probe.close()
	finish()
