extends "res://tests/network_test.gd"
## Deterministically interleave accepted owner snapshots and reliable replies.


func run() -> void:
	var server := make_sector("WalletServer", true, 24881)
	var client := make_sector("WalletClient")
	client.client_only = true
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", test_port(24881))
	await settle(0.6)
	check(client.session.active and not client.session.combat.inventory.is_empty(), "Authenticated owner receives inventory")
	if not client.session.active or client.session.combat.inventory.is_empty():
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	var session := client.session
	var combat := session.combat
	var data := server.session.player_state(id, true)
	var inventory := combat.inventory.duplicate(true)
	data["credits"] = 900
	session.snapshot({id: data}, {}, 50)
	check(client.credits == 900 and combat.wallet_sequence == 50, "World wallet at 50 is displayed")
	combat.station_pending = true
	combat.station_action = "buy"
	inventory["revision"] += 1
	inventory["research"] = {"points": 4, "skills": {}, "resets": 0}
	combat.station_result(inventory, "Purchase complete", false, {}, 100, {}, 40)
	check(client.credits == 900, "Delayed reply at 40 cannot overwrite wallet at 50")
	check(not combat.station_pending and combat.station_action.is_empty() and combat.station_message == "Purchase complete", "Stale wallet reply still acknowledges action and result")
	check(combat.inventory == inventory, "Stale wallet does not discard equipment/research inventory")
	check(Research.state(combat.inventory)["points"] == 4, "Research points still arrive with a stale wallet")
	combat.station_result(inventory, "Purchase complete", false, {}, 800, {}, 50)
	check(client.credits == 800, "Same-tick purchase after snapshot updates wallet")
	combat.station_result(inventory, "Purchase complete", false, {}, 700, {}, 50)
	check(client.credits == 700, "Multiple ordered purchases in one tick remain visible")
	combat.station_result(inventory, "Sale complete", false, {}, 1000, {}, 52)
	data["credits"] = 950
	session.snapshot({id: data}, {}, 51)
	check(client.credits == 1000, "Newer reply prevents an older accepted world wallet overwrite")
	session.snapshot({id: data}, {}, 52)
	check(client.credits == 1000, "Equal-tick snapshot cannot undo a transaction reply")
	data["credits"] = 1200
	session.snapshot({id: data}, {}, 53)
	check(client.credits == 1200, "Newer world rewards update wallet")
	data["life"] += 1
	data["credits"] = 1100
	session.snapshot({id: data}, {}, 54)
	combat.station_result(inventory, "Old purchase", false, {}, 700, {}, 50)
	check(client.credits == 1100, "New-life recovery wallet retains ordering barrier")
	data["docked"] = true
	data["credits"] = 1050
	session.flight_docked(id, data, 55)
	combat.station_result(inventory, "Old purchase", false, {}, 700, {}, 54)
	check(client.preflight and client.credits == 1050, "Dock acknowledgement advances wallet barrier")
	data["map"] = 1
	data["visit"] += 1
	data["credits"] = 1040
	session.map_changed(id, data, 56)
	combat.station_result(inventory, "Old purchase", false, {}, 700, {}, 55)
	check(client.credits == 1040 and combat.wallet_sequence == 56, "Map acknowledgement preserves wallet ordering")
	check(not server.session.player_state(id, false).has("credits"), "Observer state remains wallet-free")
	session.disconnect_session("Wallet reconnect test")
	check(combat.wallet_sequence == -1, "Disconnect clears wallet ordering for a new authority")
	await settle()
	client.session.join("127.0.0.1", test_port(24881))
	await settle(0.6)
	check(client.session.active, "Owner reconnects")
	id = client.multiplayer.get_unique_id()
	data = server.session.player_state(id, true)
	data["credits"] = 25
	client.session.snapshot({id: data}, {}, 1)
	check(client.credits == 25 and combat.wallet_sequence == 1, "Fresh connection accepts a lower world sequence")
	finish()
