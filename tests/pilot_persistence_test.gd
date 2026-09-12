extends "res://tests/dedicated_server_test.gd"
## Real ENet admission plus disk recovery and failure cases.


func run() -> void:
	if "--save-failure" in OS.get_cmdline_user_args():
		await save_failure_process()
		return
	var server := make_sector("Persistent", true)
	var client := make_sector("Pilot")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.client_only = true
	client.session.join("127.0.0.1", 24683)
	await settle(0.5)
	check(server.session.ships.size() == 1, "Provisioned pilot authenticates before spawning")
	if server.session.ships.size() != 1:
		finish()
		return
	var id := client.multiplayer.get_unique_id()
	check(server.session.pilot_ids[id] == "pilot0", "Server binds peer to verified stable pilot")
	var attacker := make_sector("Attacker")
	attacker.session.credential_id = "pilot1"
	attacker.session.credential_token = test_token(0)
	attacker.session.join("127.0.0.1", 24683)
	await settle(0.5)
	check(not attacker.session.active and not attacker.session.received_snapshot and server.session.ships.size() == 1, "Wrong token cannot choose another wallet or receive world state")
	attacker.session.credential_id = "unknown"
	attacker.session.join("127.0.0.1", 24683)
	await settle(0.5)
	check(not attacker.session.active, "Unknown pilot cannot join")
	attacker.multiplayer.auth_callback = func(peer: int, _data: PackedByteArray): attacker.multiplayer.send_auth(peer, "{bad-json".to_utf8_buffer())
	attacker.session.join("127.0.0.1", 24683)
	await settle(0.5)
	check(not attacker.session.active and server.session.challenges.is_empty(), "Malformed authentication is rejected and its challenge removed")
	attacker.multiplayer.auth_callback = attacker.session.authenticate
	attacker.session.credential_id = "pilot0"
	attacker.session.join("127.0.0.1", 24683)
	await settle(0.5)
	check(not attacker.session.active and client.session.active and server.session.ships.size() == 1, "Duplicate login rejects newcomer and preserves existing session")
	attacker.multiplayer.auth_callback = func(peer: int, challenge: PackedByteArray):
		if challenge == PackedByteArray([1]):
			attacker.multiplayer.complete_auth(peer)
		else:
			var forged := {"id": "pilot1", "proof": Crypto.new().hmac_digest(HashingContext.HASH_SHA256, test_token(1).sha256_buffer(), challenge).hex_encode(), "credits": 999999, "wallet": "pilot0"}
			attacker.multiplayer.send_auth(peer, JSON.stringify(forged).to_utf8_buffer())
	attacker.session.join("127.0.0.1", 24683)
	await settle(0.5)
	await replicate(server)
	check(attacker.session.active and attacker.credits == 0 and server.session.pilot_ids[attacker.multiplayer.get_unique_id()] == "pilot1", "Client-supplied balance and wallet fields cannot override authenticated ownership")
	attacker.session.disconnect_session("Adversarial test complete")
	await settle(0.3)
	var combat := server.session.combat
	combat.contributors.append(id)
	server.alien.take_damage(999, server.session.ships[id])
	await replicate(server)
	check(client.credits == 75, "Earned reward is replicated after persistence")
	var directory := OS.get_environment("DORBIT_DATA_DIR")
	var path := directory.path_join("pilots.json")
	check(JSON.parse_string(FileAccess.get_file_as_string(path))["pilots"]["pilot0"]["credits"] == 75, "Reward is saved before disconnect")
	var locked := PilotStore.new()
	check(not locked.open(directory), "Second server cannot open a live ledger")
	locked.close()
	var nonce := Crypto.new().generate_random_bytes(32)
	var proof := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, test_token(0).sha256_buffer(), nonce)
	check(server.session.store.verifies("pilot0", nonce, proof), "Valid challenge proof verifies")
	check(not server.session.store.verifies("pilot0", Crypto.new().generate_random_bytes(32), proof), "Captured proof fails a fresh challenge")
	check(not server.session.store.verifies("pilot0", nonce, PackedByteArray()), "Malformed proof fails")
	client.session.disconnect_session("Reconnect")
	await settle(0.3)
	client.session.join("127.0.0.1", 24683)
	await settle(0.5)
	await replicate(server)
	check(client.credits == 75 and server.session.pilot_ids.size() == 1, "Reconnect restores wallet and releases old login reservation")
	server.session.disconnect_session("Restart")
	await settle(0.3)
	check(server.session.host(24683) == OK, "Restart opens saved ledger with a new store instance")
	client.session.join("127.0.0.1", 24683)
	await settle(0.5)
	await replicate(server)
	check(client.credits == 75, "Restart restores earned credits")
	server.session.disconnect_session("Disk tests")
	await settle(0.3)
	var store := PilotStore.new()
	check(store.open(directory), "Saved ledger reloads")
	var before := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	check(not store.commit({"pilot0": 80}), "Unwritable temporary save fails")
	check(store.pilots["pilot0"]["credits"] == 75 and FileAccess.get_file_as_string(path) == before, "Failed save changes neither wallet nor primary file")
	check(not store.commit({"pilot0": 90}), "Save failure remains latched until operator recovery")
	store.close()
	var interrupted := PilotStore.new()
	check(not interrupted.open(directory), "Leftover temporary path prevents startup until recovery")
	interrupted.close()
	DirAccess.remove_absolute(path + ".tmp")
	store = PilotStore.new()
	check(store.open(directory), "Operator can reopen preserved primary after fixing write path")
	check(store.commit({"pilot0": 81, "pilot1": 19}), "Multiple reward shares commit together")
	check(FileAccess.get_file_as_string(path + ".bak") == before, "Backup retains previous complete ledger")
	store.close()
	var good := FileAccess.get_file_as_string(path)
	for invalid in ["{broken", '{"version":2,"pilots":{}}', '{"version":1,"pilots":{"pilot0":{"verifier":"%s","credits":-1}}}' % test_token(0).sha256_text(), '{"version":1,"pilots":{"pilot0":{"verifier":"%s","credits":1.5}}}' % test_token(0).sha256_text()]:
		write_text(path, invalid)
		store = PilotStore.new()
		check(not store.open(directory), "Invalid save refuses startup")
		check(not store.commit({"pilot0": 0}) and FileAccess.get_file_as_string(path) == invalid, "Invalid save is never overwritten")
		store.close()
	write_text(path, good)
	store = PilotStore.new()
	check(store.open(directory), "Restored valid ledger opens")
	write_text(path, "external edit")
	check(not store.commit({"pilot0": 99}) and FileAccess.get_file_as_string(path) == "external edit", "Runtime disk corruption is preserved and stops saving")
	store.close()
	write_text(path, good)
	check(not PilotStore.valid_id("../pilot") and not PilotStore.valid_id("") and PilotStore.valid_id("pilot-1"), "Pilot IDs have a bounded canonical format")
	var empty_directory := directory.path_join("missing-save")
	DirAccess.make_dir_absolute(empty_directory)
	store = PilotStore.new()
	check(not store.open(empty_directory) and not FileAccess.file_exists(empty_directory.path_join("pilots.json")), "Missing save never creates a replacement wallet")
	store.close()
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/pilot_persistence_test.gd", "--", "--save-failure"], output, true)
	check(exit_code == 1 and str(output).contains("SAVE_FAILURE_VERIFIED"), "A real server process exits unsuccessfully without granting an unsaved reward")
	finish()


func write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func save_failure_process() -> void:
	var server := make_sector("FailingServer", true)
	var client := make_sector("Pilot")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	client.session.join("127.0.0.1", 24683)
	await settle(0.5)
	if server.session.ships.size() != 1:
		quit(2)
		return
	var id := client.multiplayer.get_unique_id()
	var path := server.session.store.path
	var original := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".bak.tmp")
	server.session.combat.contributors.append(id)
	server.alien.take_damage(999, server.session.ships[id])
	if server.session.store.failed and not server.is_physics_processing() and server.session.combat.records[id]["credits"] == 0 and FileAccess.get_file_as_string(path) == original:
		print("SAVE_FAILURE_VERIFIED")
	else:
		quit(2)
