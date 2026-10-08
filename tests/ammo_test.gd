extends "res://tests/shop_test.gd"
## Authenticated ammo purchases, real physics shots, persistence and HUD input.


func run() -> void:
	var server := make_sector("AmmoServer", true, 24836)
	var store := server.session.store
	check(store.pilots["pilot0"]["ammo"] == Ammunition.starter(), "Legacy migration grants 10,000 x1 shots once")
	check(JSON.parse_string(FileAccess.get_file_as_string(store.path))["version"] == 5, "Ammo migration writes schema 5")
	check(store.commit({"pilot0": 1000}), "Fund ammo purchases")
	var client := make_sector("AmmoPilot")
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", 24836)
	await settle(0.5)
	await replicate(server)
	if not client.session.active:
		check(false, "Ammo pilot authenticates")
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	var remote := server.session.ships[id]
	var combat := client.session.combat
	var shop := client.shop
	check(client.player.ammo == Ammunition.starter(), "Starter inventory replicates to the owner")
	shop.select_category("ammo")
	check(shop.models_in_category("ammo") == ["x1", "x2", "x3", "x4"], "Shop lists ammo in multiplier order")
	client.main_menu.select_page("shop")
	for kind: String in ["x1", "x2", "x3"]:
		shop.select_model(kind)
		shop.set_purchase_quantity(2)
		var credits := client.credits
		var before: int = remote.ammo[kind]
		var sequence: int = combat.inventory["revision"] + 1
		await click(client, shop.buys[kind])
		await replicate(server)
		check(remote.ammo[kind] == before + 200 and client.player.ammo[kind] == before + 200, "Two batches grant exactly 200 " + kind + " shots")
		check(client.credits == credits - int(Ammunition.TYPES[kind]["price"]) * 2, "Exact batch price charged for " + kind)
		combat.station_request.rpc_id(1, sequence, "buy_ammo", kind + ":2", "", "", 0)
		await settle()
		check(remote.ammo[kind] == before + 200 and client.credits == credits - int(Ammunition.TYPES[kind]["price"]) * 2, "Duplicate ammo purchase cannot charge or grant again")
	shop.select_model("x4")
	check(shop.buys["x4"].disabled and shop.price.text == "Not for sale", "x4 remains a special reward, unavailable in the shop")
	var before := store.pilots.duplicate(true)
	for subject: String in ["x4:1", "x0:1", "x1:0", "x1:-1", "x1:10001", "x1:100000", "x1:1.5", "x1:", "x1:1:2", "x2:999"]:
		combat.station_request.rpc_id(1, int(combat.inventory["revision"]) + 1, "buy_ammo", subject, "", "", 0)
		await settle()
		check(store.pilots == before, "Invalid or unaffordable purchase preserves the whole ledger: " + subject)
	check(store.commit({"pilot0": 3_000_000}), "Fund million-round orders")
	server.session.combat.records[id]["credits"] = 3_000_000
	await replicate(server)
	for kind: String in ["x1", "x2", "x3"]:
		shop.select_model(kind)
		shop.edit_purchase_quantity("10000")
		var credits := client.credits
		var rounds: int = remote.ammo[kind]
		var sequence: int = combat.inventory["revision"] + 1
		check(shop.purchase_quantity == 10_000 and shop.buys[kind].text == "BUY 1,000,000 SHOTS" and shop.purchase_increase.disabled, "Shop accepts the million-round limit for " + kind)
		await click(client, shop.buys[kind])
		await replicate(server)
		check(remote.ammo[kind] == rounds + 1_000_000 and client.player.ammo[kind] == rounds + 1_000_000 and store.pilots["pilot0"]["ammo"][kind] == rounds + 1_000_000, "Million-round " + kind + " purchase is saved and replicated")
		check(client.credits == credits - int(Ammunition.TYPES[kind]["price"]) * 10_000, "Million-round " + kind + " order charges the exact batch price")
		combat.station_request.rpc_id(1, sequence, "buy_ammo", kind + ":10000", "", "", 0)
		await settle()
		check(remote.ammo[kind] == rounds + 1_000_000 and client.credits == credits - int(Ammunition.TYPES[kind]["price"]) * 10_000, "Duplicate million-round order cannot charge or deliver twice")
	shop.set_purchase_quantity(10_001)
	check(shop.purchase_quantity == 10_000, "Ammo input clamps to one million rounds per order")
	var funded_before := store.pilots.duplicate(true)
	combat.station_request.rpc_id(1, int(combat.inventory["revision"]) + 1, "buy_ammo", "x3:10001", "", "", 0)
	await settle()
	check(store.pilots == funded_before, "Server rejects over-limit orders even with sufficient credits")
	combat.station_message = "" # Capture the current offer after adversarial requests.
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900)]:
		client.get_viewport().size = dimensions
		await settle()
		check(shop.get_global_rect().encloses(shop.purchase_controls.get_global_rect()) and shop.get_global_rect().encloses(shop.buys["x3"].get_global_rect()), "Ammo order controls fit at %s" % dimensions)
		await capture(client, "ammo-shop-%d" % dimensions.x)
	await prepare_lasers(server, client)
	client.main_menu.hide()
	client.main_menu.hide_pages()
	client.set_paused(false)
	client.session.launch()
	await settle()
	await replicate(server)
	remote.position = Vector3(0, 200, 0)
	remote.rotation = Vector3.ZERO
	var enemy := server.alien
	enemy.position = Vector3(0, 200, -100)
	enemy.home_position = enemy.position
	await physics_frame
	await replicate(server)
	for kind: String in Ammunition.TYPES:
		await press(client, int(KEY_1) + int(kind.trim_prefix("x")) - 1 as Key)
		await replicate(server)
		check(remote.ammo_type == kind and client.player.ammo_type == kind, "Number key selects " + kind + " on the authority and client")
		remote.shot_cooldown = 0
		if kind == "x4":
			check(not remote.try_fire(enemy) and remote.firing_blocker(enemy).contains("OUT OF AMMO"), "Empty ammo blocks firing without falling back")
			var grant := remote.ammo.duplicate()
			grant["x4"] = 5
			check(store.commit({}, {}, {}, {"pilot0": grant}), "Server can grant x4 through the reward inventory path")
			remote.ammo = grant
		enemy.reset_health()
		var total := enemy.hull + enemy.shield
		var amount: int = remote.ammo[kind]
		remote.npc_laser_damage = 26.25
		check(remote.try_fire(enemy), "Authoritative " + kind + " shot fires")
		check(is_equal_approx(total - enemy.hull - enemy.shield, (remote.laser_damage + 26.25) * int(Ammunition.TYPES[kind]["multiplier"])), kind + " multiplies fitted laser damage including alien bonuses")
		check(remote.ammo[kind] == amount - 4 and store.pilots["pilot0"]["ammo"][kind] == amount - 4, "Four fitted lasers consume and save four " + kind + " rounds")
		check(not remote.try_fire(enemy) and remote.ammo[kind] == amount - 4, "Cooldown rejection consumes no extra ammo")
		if DisplayServer.get_name() != "headless":
			await check_network_beam(client, kind)
		await replicate(server)
		check(client.player.ammo == remote.ammo, "Consumed inventory replicates")
		check(not client.player.try_fire(client.alien), "Client cannot fire or debit ammunition locally")
	remote.npc_laser_damage = 0
	remote.shot_cooldown = 0
	var insufficient_before := store.pilots.duplicate(true)
	var health_before := enemy.hull + enemy.shield
	check(remote.ammo["x4"] == 1 and remote.firing_blocker(enemy).contains("NEED 4 ROUNDS") and not remote.try_fire(enemy), "Four lasers cannot fire with only one round remaining")
	check(store.pilots == insufficient_before and remote.ammo["x4"] == 1 and enemy.hull + enemy.shield == health_before and remote.shot_cooldown == 0, "Incomplete volley preserves rounds, damage, cooldown and ledger")
	remote.ammo_type = "x1"
	remote.shot_cooldown = 0
	var ammo_before := remote.ammo.duplicate()
	for point: Vector3 in [Vector3(0, 200, -900), Vector3(0, 200, 100)]:
		enemy.position = point
		await physics_frame
		check(not remote.try_fire(enemy) and remote.ammo == ammo_before, "Range and arc blockers spend no ammo")
	remote.position = Sector.SPAWN_POSITION
	enemy.position = remote.position + Vector3(0, 0, -50)
	await physics_frame
	check(not remote.try_fire(enemy) and remote.ammo == ammo_before, "Station protection spends no ammo")
	# Purchases still require station range even when the shop can be opened in flight.
	remote.position = Vector3(0, 200, 0)
	combat.station_request.rpc_id(1, int(combat.inventory["revision"]) + 1, "buy_ammo", "x1:1", "", "", int(remote.get_meta("life", 0)))
	await settle()
	check(remote.ammo == ammo_before, "Out-of-station purchase is rejected")
	await replicate(server)
	for kind: String in Ammunition.TYPES:
		await click(client, client.hud.ammo_bar.buttons[kind])
		await replicate(server)
		check(remote.ammo_type == kind and client.hud.ammo_bar.buttons[kind].button_pressed, "Clicking the ammo symbol selects " + kind)
	var chosen := remote.ammo_type
	combat.select_ammo.rpc_id(1, 99, "x1")
	combat.select_ammo.rpc_id(1, 0, "invalid")
	await settle()
	check(remote.ammo_type == chosen, "Stale-life and unknown ammo selection requests are rejected")
	client.set_paused(true)
	await press(client, KEY_1)
	await replicate(server)
	check(remote.ammo_type == chosen and not client.hud.ammo_bar.visible, "Menus hide the bar and ignore ammo shortcuts")
	client.set_paused(false)
	await press(client, KEY_2)
	await replicate(server)
	for dimensions in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		client.get_viewport().size = dimensions
		client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await settle()
		var bar := client.hud.ammo_bar.get_rect()
		check(client.hud.ammo_bar.counts["x4"].get_theme_color("font_color") == FlightHud.RED and client.hud.ammo_bar.buttons["x4"].tooltip_text.contains("4 rounds per volley"), "HUD marks an incomplete volley and explains the fitted round cost")
		check(not bar.intersects(client.hud.navigation.guidance_rect()) and not bar.intersects(client.hud.ship_rect()) and not bar.intersects(client.hud.target_rect()), "Ammo bar clears other HUD panels at %s" % dimensions)
		check(absf(bar.get_center().x - client.hud.size.x * 0.5) < 1 and bar.end.y < client.hud.size.y - 45, "Ammo bar is centered above controls at %s" % dimensions)
		for button: Button in client.hud.ammo_bar.buttons.values():
			var rows := button.get_child(0) as Control
			check(button.get_global_rect().encloses(rows.get_global_rect()), "Ammo contents fit within their framed slot at %s" % dimensions)
		await capture(client, "ammo-flight-%d" % dimensions.x)
	remote.take_damage(remote.max_hull + remote.max_shield + 1, enemy)
	server.session.combat.tick(3.1)
	check(remote.alive and remote.ammo == ammo_before, "Rescue preserves all remaining ammunition")
	var saved_ammo := remote.ammo.duplicate()
	client.session.disconnect_session("Ammo restart")
	server.session.disconnect_session("Ammo restart")
	await settle()
	check(server.session.host(24836) == OK, "Restart loads the ammo ledger")
	client.session.join("127.0.0.1", 24836)
	await settle(0.5)
	await replicate(server)
	check(client.player.ammo == saved_ammo, "Restart and reconnect retain consumed ammo without another starter grant")
	check(server.session.ships[client.multiplayer.get_unique_id()].laser_count == 4 and client.player.laser_count == 4, "Reconnect restores ammo consumption from the persisted active fitting")
	var confirmed_sequence := combat.ammo_sequence
	combat.ammo_snapshot(PackedInt32Array([10000, 0, 0, 0, 0]), confirmed_sequence - 1)
	combat.station_result(combat.inventory, "", false, {}, -1, Ammunition.starter(), confirmed_sequence - 1)
	check(client.player.ammo == saved_ammo, "Delayed snapshots and station replies cannot restore older ammunition counts")
	await check_failed_debit(server, client)
	finish()


func station_action(server: Sector, client: Sector, action: String, subject: String, ship: String = "", slot: String = "") -> void:
	var combat := client.session.combat
	combat.station_request.rpc_id(1, int(combat.inventory["revision"]) + 1, action, subject, ship, slot, int(client.player.get_meta("life", 0)))
	await settle()
	await replicate(server)


func prepare_lasers(server: Sector, client: Sector) -> void:
	var remote := server.session.ships[client.multiplayer.get_unique_id()]
	check(remote.laser_count == 1 and client.player.laser_count == 1, "Starter shield and engine do not consume laser rounds")
	var sequence: int = client.session.combat.inventory["revision"] + 1
	await station_action(server, client, "buy", "laser:3")
	check(remote.laser_count == 1, "Stored lasers do not increase ammo consumption")
	var items := ["purchase-%d" % sequence, "purchase-%d-2" % sequence, "purchase-%d-3" % sequence]
	for index in range(items.size()):
		await station_action(server, client, "fit", items[index], "starter", "laser%d" % (index + 2))
		check(remote.laser_count == index + 2 and client.player.laser_count == index + 2, "Fitting laser %d updates the server and owner round cost" % (index + 2))
	await station_action(server, client, "fit", items[0])
	check(remote.laser_count == 3 and client.player.laser_count == 3, "Removing a fitted laser lowers the round cost")
	await station_action(server, client, "fit", items[0], "starter", "laser2")
	await station_action(server, client, "buy_ship", "phoenix")
	var phoenix := ShipCatalog.owned_id(client.session.combat.inventory, "phoenix")
	await station_action(server, client, "switch_ship", phoenix)
	check(remote.laser_count == 0 and client.player.laser_count == 0, "Inactive ship lasers do not contribute to the empty ship's round cost")
	await station_action(server, client, "switch_ship", "starter")
	check(remote.laser_count == 4 and client.player.laser_count == 4, "Returning to the fitted ship restores four rounds per volley")


func check_network_beam(client: Sector, kind: String) -> void:
	# Inspect the received shot, rather than calling the presentation RPC locally.
	var deadline := Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < deadline:
		await process_frame
		for effect: Node in get_nodes_in_group("transient_feedback"):
			if effect.get_parent() != client or not effect.get_meta("laser", false):
				continue
			var mesh := effect.get_child(0) as MeshInstance3D
			var surface := mesh.material_override as StandardMaterial3D
			check(surface.emission.is_equal_approx(Ammunition.TYPES[kind]["color"].lerp(Color.WHITE, 0.35)), "Network shot renders the firing color for " + kind)
			return
	check(false, "Receive the network beam for " + kind)


func check_failed_debit(server: Sector, client: Sector) -> void:
	var directory := server.session.store.path.get_base_dir().path_join("failed-ammo")
	DirAccess.make_dir_absolute(directory)
	var file := FileAccess.open(directory.path_join("pilots.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 4, "pilots": {"pilot0": server.session.store.pilots["pilot0"]}}))
	file.close()
	var probe := PilotStore.new()
	check(probe.open(directory), "Open isolated debit failure ledger")
	var capped: Dictionary = probe.pilots["pilot0"]["ammo"].duplicate()
	capped["x1"] = Ammunition.MAX_SHOTS - 99
	check(probe.commit({}, {}, {}, {"pilot0": capped}), "Prepare an inventory near the ammunition limit")
	var capped_before := probe.pilots.duplicate(true)
	var capped_disk := FileAccess.get_file_as_string(probe.path)
	var result := probe.transact("pilot0", int(probe.pilots["pilot0"]["equipment"]["revision"]) + 1, "buy_ammo", "x1:1", "", "")
	check(result.contains("limit") and probe.pilots == capped_before and FileAccess.get_file_as_string(probe.path) == capped_disk, "Overflow rejects the entire batch without changing shots, credits or revision")
	for value: Variant in [{}, capped.merged({"x1": -1}, true), capped.merged({"x2": 1.5}, true), capped.merged({"x4": true}, true), capped.merged({"x3": Ammunition.MAX_SHOTS + 1}, true), capped.merged({"unknown": 1}, true)]:
		check(not Ammunition.valid(value), "Runtime rejects malformed ammunition inventory")
	var remote := server.session.ships[client.multiplayer.get_unique_id()]
	remote.position = Vector3(0, 200, 0)
	remote.rotation = Vector3.ZERO
	remote.shot_cooldown = 0
	server.alien.position = Vector3(0, 200, -100)
	server.alien.reset_health()
	await physics_frame
	var ammo_before := remote.ammo.duplicate()
	var health_before := server.alien.hull + server.alien.shield
	var disk_before := FileAccess.get_file_as_string(probe.path)
	DirAccess.make_dir_absolute(probe.path + ".tmp")
	remote.ammo_debit = func():
		var next := remote.ammo.duplicate()
		next[remote.ammo_type] -= remote.laser_count
		return probe.commit({}, {}, {}, {"pilot0": next})
	check(not remote.try_fire(server.alien) and probe.failed, "Failed durable debit cancels the shot")
	check(remote.ammo == ammo_before and server.alien.hull + server.alien.shield == health_before and remote.shot_cooldown == 0 and FileAccess.get_file_as_string(probe.path) == disk_before, "Debit failure preserves ammunition, damage, cooldown and disk")
	remote.ammo_debit = Callable()
	probe.close()
