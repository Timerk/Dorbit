extends "res://tests/equipment_test.gd"
## Authenticated grants through the real shop, RPC, persistence and restart paths.


func run() -> void:
	OS.unset_environment("DORBIT_PREVIEW_TOOLS")
	OS.unset_environment("DORBIT_PREVIEW_PILOTS")
	var server := make_sector("PreviewServer", true, 24732)
	var client := make_sector("PreviewPilot")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24732))
	await settle(0.5)
	await replicate(server)
	check(client.session.active, "Preview pilot authenticates")
	if not client.session.active:
		finish()
		return
	var store := server.session.store
	var original := FileAccess.get_file_as_string(store.path)
	client.shop.open()
	await settle()
	check(not client.session.combat.preview_tools_available and not client.shop.test_credits_button.visible, "Default server hides test credits")
	await request(client, 1, "test_credits", "")
	check(FileAccess.get_file_as_string(store.path) == original, "Forged grant on the default server changes no saved fields")
	OS.set_environment("DORBIT_PREVIEW_TOOLS", "1")
	OS.set_environment("DORBIT_PREVIEW_PILOTS", "pilot0")
	await request(client, 1, "test_credits", "")
	check(FileAccess.get_file_as_string(store.path) == original, "Changing client environment cannot enable grants on the running server")
	client.session.disconnect_session("Enable preview configuration")
	await settle()
	server.session.disconnect_session("Enable preview configuration")
	OS.unset_environment("DORBIT_PREVIEW_PILOTS")
	check(server.session.host(test_port(24732)) == OK, "Preview server restarts with no allowlist")
	client.session.join("127.0.0.1", test_port(24732))
	await settle(0.5)
	await request(client, 1, "test_credits", "")
	check(not client.session.combat.preview_tools_available and client.credits == 0, "Enabling tools without an allowed pilot grants no access")
	client.session.disconnect_session("Configure allowed pilot")
	await settle()
	server.session.disconnect_session("Configure allowed pilot")
	OS.set_environment("DORBIT_PREVIEW_PILOTS", "pilot0")
	check(server.session.host(test_port(24732)) == OK, "Preview configuration loads when the server starts")
	OS.unset_environment("DORBIT_PREVIEW_TOOLS")
	OS.unset_environment("DORBIT_PREVIEW_PILOTS")
	client.session.join("127.0.0.1", test_port(24732))
	var other := make_sector("OtherPilot")
	other.session.credential_id = "pilot1"
	other.session.credential_token = test_token(1)
	other.session.join("127.0.0.1", test_port(24732))
	await settle(0.5)
	await replicate(server)
	check(client.session.combat.preview_tools_available and not other.session.combat.preview_tools_available, "Only the allowlisted authenticated pilot receives the tool")
	await request(other, 1, "test_credits", "")
	store = server.session.store
	check(store.pilots["pilot1"]["credits"] == 0 and store.pilots["pilot1"]["equipment"]["revision"] == 0, "Another authenticated pilot cannot forge a grant")
	var contract := HuntingContracts.accept("scout")
	contract["progress"] = 2
	var contracts := {"scout": contract, "sentinel": HuntingContracts.accept("sentinel"), "heavy": HuntingContracts.accept("heavy")}
	check(store.commit({}, {"pilot0": contracts}), "Seed concurrent contracts with Scout progress")
	var inventory_before: Dictionary = store.pilots["pilot0"]["equipment"].duplicate(true)
	var verifier: String = store.pilots["pilot0"]["verifier"]
	var id := client.multiplayer.get_unique_id()
	var ship := server.session.ships[id]
	ship.hull = 87
	ship.shield = 23
	ship.energy = 42
	ship.shot_cooldown = 0.3
	client.shop.open()
	await settle()
	check(client.shop.test_credits_button.visible and not client.shop.test_credits_button.disabled, "Authorized pilot can use the shop button")
	client.shop.test_credits_button.pressed.emit()
	await settle()
	await replicate(server)
	check(client.credits == 100000000 and store.pilots["pilot0"]["credits"] == 100000000, "Button immediately grants and replicates 100,000,000 saved credits")
	check(store.pilots["pilot0"]["equipment"]["revision"] == 1, "Grant commits its duplicate-protection sequence")
	check(store.pilots["pilot0"]["equipment"]["items"] == inventory_before["items"] and store.pilots["pilot0"]["contracts"] == contracts and store.pilots["pilot0"]["verifier"] == verifier, "Grant preserves owned items, fittings, contract progress and credentials")
	check(ship.hull == 87 and ship.shield == 23 and ship.energy == 42 and ship.shot_cooldown == 0.3, "Grant changes no health, energy or weapon cooldown")
	check(client.session.combat.station_message == "Preview: added 100000000 test credits.", "Server confirms the actual committed grant")
	check(store.pilots["pilot1"]["credits"] == 0, "Grant never touches another pilot's wallet")
	await request(client, 1, "test_credits", "")
	check(store.pilots["pilot0"]["credits"] == 100000000, "Duplicate grant cannot add credits twice")
	await request(client, 2, "test_credits", "pilot1")
	check(store.pilots["pilot0"]["equipment"]["revision"] == 1, "Payload cannot select another pilot or an arbitrary amount")
	for reason in ["distance", "speed", "damage", "life"]:
		ship.position = Vector3(0, 0, 400) if reason == "distance" else server.session.combat.records[id]["spawn"]
		ship.velocity = Vector3(10, 0, 0) if reason == "speed" else Vector3.ZERO
		ship.time_since_hit = 0 if reason == "damage" else 5
		await request(client, 2, "test_credits", "", "", "", 99 if reason == "life" else 0)
		check(store.pilots["pilot0"]["credits"] == 100000000, "Station rejects grant for " + reason)
	ship.time_since_hit = 5
	client.shop.buys["laser"].pressed.emit()
	await settle()
	await replicate(server)
	check(client.credits == 99990000 and client.session.combat.inventory["items"].has("purchase-2"), "Granted credits buy real equipment with the next sequence")
	client.shop.test_credits_button.pressed.emit()
	await settle()
	await replicate(server)
	check(client.credits == 199990000 and store.pilots["pilot0"]["equipment"]["revision"] == 3, "Pilot can deliberately grant another budget without restarting")
	client.get_viewport().size = Vector2i(960, 600)
	client.get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if DisplayServer.get_name() != "headless":
		var screen := TextureRect.new()
		screen.texture = client.get_viewport().get_texture()
		root.add_child(screen)
		root.size = Vector2i(960, 600)
	await settle()
	await screenshot(client, "preview-test-credits")
	check(client.shop.get_global_rect().position.y >= 0 and client.shop.get_global_rect().end.y <= 600, "Shop with test credits fits the minimum window height")
	check(server.session.save_balances({id: PilotStore.MAX_CREDITS - 10}), "Seed near the credit cap through the server save path")
	server.session.combat.records[id]["credits"] = PilotStore.MAX_CREDITS - 10
	await request(client, 4, "test_credits", "")
	await replicate(server)
	check(client.credits == PilotStore.MAX_CREDITS and client.session.combat.station_message == "Preview: added 10 test credits.", "Grant respects the credit cap and reports its actual amount")
	check(client.shop.test_credits_button.disabled, "Shop disables grants at the credit cap")
	await request(client, 5, "test_credits", "")
	check(store.pilots["pilot0"]["equipment"]["revision"] == 4, "Grant at the cap does not consume a sequence")
	client.session.disconnect_session("Restart proof")
	other.session.disconnect_session("Restart proof")
	await settle()
	check(not client.session.combat.preview_tools_available, "Disconnect clears the client capability")
	server.session.disconnect_session("Restart proof")
	OS.set_environment("DORBIT_PREVIEW_TOOLS", "1")
	OS.set_environment("DORBIT_PREVIEW_PILOTS", "pilot0")
	check(server.session.host(test_port(24732)) == OK, "Server reloads granted credits")
	OS.unset_environment("DORBIT_PREVIEW_TOOLS")
	OS.unset_environment("DORBIT_PREVIEW_PILOTS")
	client.session.join("127.0.0.1", test_port(24732))
	await settle(0.5)
	await replicate(server)
	store = server.session.store
	check(client.credits == PilotStore.MAX_CREDITS and client.session.combat.inventory["items"].has("purchase-2"), "Credits and purchased equipment survive restart and reconnect")
	await request(client, 1, "test_credits", "")
	check(store.pilots["pilot0"]["equipment"]["revision"] == 4, "Old grant remains rejected after restart")
	check(store.commit({"pilot0": 0}), "Seed the failed-write test")
	var disk_before := FileAccess.get_file_as_string(store.path)
	DirAccess.make_dir_absolute(store.path + ".tmp")
	check(store.transact("pilot0", 5, "test_credits", "", "", "", true) == "Persistence unavailable.", "Failed save returns no success confirmation")
	check(store.failed and store.pilots["pilot0"]["credits"] == 0 and store.pilots["pilot0"]["equipment"]["revision"] == 4 and FileAccess.get_file_as_string(store.path) == disk_before, "Failed grant commits neither credits nor sequence and latches save failure")
	finish()
