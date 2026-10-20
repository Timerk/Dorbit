extends "res://tests/dedicated_server_test.gd"
## Real checkpoint and journal I/O, with observation at the commit boundary.

class ObservedStore extends "res://tests/benchmark_store.gd":
	var observe: Callable

	func persist(next: Dictionary) -> bool:
		if observe.is_valid(): observe.call(false)
		var result := super.persist(next)
		if observe.is_valid(): observe.call(result)
		return result


func live_state(server: Sector) -> Dictionary:
	var result := {}
	for id: int in server.session.ships:
		var ship := server.session.ships[id]
		result[id] = [ship.ammo.duplicate(), ship.resource_boosts.duplicate(true),
			server.session.combat.records[id]["credits"],
			server.session.combat.cargo_holds[id].duplicate(true), ship.max_shield, ship.cruise_speed]
	return result


func progression(pilots: Dictionary) -> Dictionary:
	var result := pilots.duplicate(true)
	for pilot: Dictionary in result.values():
		pilot.erase("skylab") # Reopen independently advances real UTC industry time.
	return JSON.parse_string(JSON.stringify(result))


func run() -> void:
	var failing := "--fail-checkpoint" in OS.get_cmdline_user_args()
	var server := make_sector("BatchServer", true)
	var directory := server.session.store.path.get_base_dir()
	server.session.store.close()
	var store := ObservedStore.new()
	check(store.open(directory), "Open observed real store")
	server.session.store = store
	var clients: Array[Sector] = []
	for index in range(3):
		var client := make_sector("BatchPilot%d" % index)
		client.session.credential_id = "pilot%d" % index
		client.session.credential_token = test_token(index)
		client.session.join("127.0.0.1", test_port(24683))
		clients.append(client)
	var deadline := Time.get_ticks_msec() + 10000
	while (server.session.ships.size() != 3 or clients.any(func(client: Sector): return not client.session.active)) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(server.session.ships.size() == 3, "Three pilots authenticate")
	if server.session.ships.size() != 3:
		finish()
		return
	await replicate(server)
	var next := store.pilots.duplicate(true)
	for index in range(3):
		var pilot: Dictionary = next["pilot%d" % index]
		pilot["credits"] = 100000
		pilot["ammo"]["x1"] = 0
		pilot["equipment"]["items"]["buyer"] = {"model": "ammo-cpu", "ship": "starter", "slot": "extra1", "enabled": true, "ammo_type": "x1"}
		pilot["equipment"]["items"]["generator"] = {"model": "generator-cpu", "ship": "starter", "slot": "extra2", "enabled": true}
		pilot["cargo"]["starter"] = {"seprom": 2, "promerium": 2}
		pilot["boosts"]["starter"] = {"lasers": {"resource": "seprom", "remaining": 7}}
	check(store.persist(next), "Seed simultaneous ammo and generator supplies")
	var combat := server.session.combat
	for id: int in server.session.ships:
		var ship := server.session.ships[id]
		ship.set_meta("docked", false)
		ship.ammo = store.pilots[server.session.pilot_ids[id]]["ammo"].duplicate()
		combat.records[id]["credits"] = 100000
		combat.cargo_holds[id] = {"starter": {"seprom": 2, "promerium": 2}}
		combat.apply_equipment(id)
		ship.extras_clock = 1.0
		ship.position = Vector3(0, 200, 0)
		ship.rotation = Vector3.ZERO
	server.alien.position = Vector3(0, 200, -100)
	server.alien.home_position = server.alien.position
	await physics_frame
	var before := live_state(server)
	var ledger := store.pilots.duplicate(true)
	var health := server.alien.hull + server.alien.shield
	var boundary := [0, false]
	store.observe = func(durable: bool):
		check(live_state(server) == before, "All ammo, credits, cargo, boosts and stats stay unchanged inside commit")
		boundary[0] += 1
		if durable:
			var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
			boundary[1] = saved["pilots"]["pilot2"]["ammo"]["x1"] == 10000
	store.measuring = true
	for id: int in server.session.ships:
		server.session.commands[id] = {"target": server.alien.alien_id, "fire": true, "encounter": server.alien.life, "time": Time.get_ticks_msec()}
	var damage_after_commit := [false]
	server.alien.damaged.connect(func(_target: SpaceShip, _attacker: SpaceShip):
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
		var sequence := CombatJournal.replay(FileAccess.get_file_as_string(store.path + ".combat"), saved["combat_journal"], saved["pilots"])
		var pilot_id: String = server.session.pilot_ids[server.session.ships.find_key(_attacker)]
		damage_after_commit[0] = boundary[1] and sequence > saved["combat_journal"]["sequence"] and saved["pilots"][pilot_id]["credits"] == 99000 and saved["pilots"][pilot_id]["boosts"]["starter"]["lasers"]["remaining"] == 7 - (_attacker as Pilot).laser_count
	)
	if failing:
		DirAccess.make_dir_absolute(store.path + ".bak.tmp")
		server.set_physics_process(true)
	combat.tick(0.0)
	store.observe = Callable()
	if failing:
		if store.failed and not server.is_physics_processing() and live_state(server) == before and store.pilots == ledger and boundary[0] == 2 and server.alien.hull + server.alien.shield == health:
			print("EXTRAS_BATCH_FAILURE_VERIFIED")
		else:
			quit(2)
		return
	check(store.counts.get("checkpoint_extras", 0) == 1 and store.extras_pilots == 3, "Three simultaneous resupplies produce exactly one checkpoint")
	check(boundary[0] == 2 and boundary[1], "Verified on-disk batch exists before any live effect")
	check(damage_after_commit[0], "Same-tick firing follows the supply checkpoint and a verified journal debit")
	for id: int in server.session.ships:
		var ship := server.session.ships[id]
		check(ship.ammo["x1"] == 10000 - ship.laser_count and combat.records[id]["credits"] == 99000 and ship.resource_boosts.has("shields") and ship.max_shield > before[id][4] and combat.cargo_holds[id]["starter"] == {"seprom": 1, "promerium": 1}, "Apply each pilot's committed supplies before its shot")
	await replicate(server)
	for client in clients:
		check(client.toast == "Extras: automatic supplies applied." and client.cargo == {"seprom": 1, "promerium": 1} and client.credits == 99000, "Owner receives supply message, cargo and wallet after commit: %s / %s / %s / %d" % [client.name, client.toast, client.cargo, client.credits])
	combat.tick(0.0)
	check(store.counts.get("checkpoint_extras", 0) == 1, "No checkpoint without due supply changes")
	var drop_id := 100
	for id: int in server.session.ships:
		var ship := server.session.ships[id]
		ship.position = Vector3(drop_id * 50, 200, 0)
		server.loot.change(drop_id, {"position": ship.position, "map": ship.map_id, "resources": {"prometium": 3}, "ttl": 180.0})
		drop_id += 1
	var loot_before: int = store.counts["checkpoint"]
	combat.collect_loot()
	check(store.counts["checkpoint"] == loot_before + 1 and server.loot.drops.is_empty(), "Loot still batches all pickups after supplies")
	for id: int in server.session.ships:
		check(combat.cargo_holds[id]["starter"] == {"seprom": 1, "promerium": 1, "prometium": 3} and store.pilots[server.session.pilot_ids[id]]["cargo"] == combat.cargo_holds[id], "Loot preserves the committed automatic resource costs")
	# Completed pending contracts can also settle together, before any new supply cost.
	var contracts := {}
	for id: int in server.session.ships:
		var contract := HuntingContracts.accept("scout")
		contract["progress"] = contract["required"]
		contracts[server.session.pilot_ids[id]] = {"scout": contract}
		combat.records[id]["contracts"] = {"scout": contract.duplicate(true)}
	check(store.commit({}, contracts), "Seed completed pending contracts")
	var checkpoints: int = store.counts["checkpoint"]
	combat.tick(0.0)
	check(store.counts["checkpoint"] == checkpoints + 1, "Several pending contract payouts share one checkpoint")
	for id: int in server.session.ships:
		check(combat.records[id]["credits"] == 99900 and combat.records[id]["contracts"].is_empty() and Research.state(store.pilots[server.session.pilot_ids[id]]["equipment"])["points"] == 1, "Batched payout preserves each pilot's credits, cleared run and research")
	store.begin_combat_tick()
	for id: int in server.session.ships:
		check(combat.debit_ammo(id), "Post-checkpoint ammo journal debit succeeds")
		server.session.ships[id].ammo["x1"] -= server.session.ships[id].laser_count
	store.end_combat_tick()
	var expected := store.pilots.duplicate(true)
	store.close_journal()
	DirAccess.remove_absolute(store.path + ".lock")
	store.locked = false # Reopen without a clean-shutdown checkpoint masking journal replay.
	var reopened := PilotStore.new()
	check(reopened.open(directory) and progression(reopened.pilots) == progression(expected), "Restart replays post-resupply debits without restoring spent ammo or boosts")
	reopened.close()
	var output: Array = []
	var offset := OS.get_environment("DORBIT_TEST_PORT_OFFSET")
	OS.set_environment("DORBIT_TEST_PORT_OFFSET", str(int(offset) + 100))
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/extras_batch_test.gd", "--", "--fail-checkpoint"], output, true)
	OS.set_environment("DORBIT_TEST_PORT_OFFSET", offset)
	check(code == 1 and str(output).contains("EXTRAS_BATCH_FAILURE_VERIFIED"), "Real failed batch stops server and exits before any supply effects")
	finish()
