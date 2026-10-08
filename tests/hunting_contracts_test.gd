extends "res://tests/dedicated_server_test.gd"
## Authenticated concurrent hunts, automatic payment and durable transactions.

const CONTRACT_PORT := 24689

func connect_pilot(client: Sector, index: int) -> void:
	client.session.credential_id = "pilot%d" % index
	client.session.credential_token = test_token(index)
	client.session.join("127.0.0.1", test_port(CONTRACT_PORT))
	var deadline := Time.get_ticks_msec() + 8000
	while not client.session.active and Time.get_ticks_msec() < deadline:
		await process_frame
	check(client.session.active, "Pilot authenticates within the timeout")
	if client.session.active:
		# These fixtures disable simulation ticks, so request the initial snapshot.
		for viewport in worlds:
			var server: Sector = viewport.get_child(0)
			if server.dedicated_server and server.session.active and server.server_port == test_port(CONTRACT_PORT):
				await replicate(server)
				break
		check(client.session.received_snapshot, "Pilot receives initial state within the convergence timeout")

func station(server: Sector, client: Sector) -> void:
	var ship := server.session.ships[client.multiplayer.get_unique_id()]
	ship.position = Sector.SPAWN_POSITION
	ship.velocity = Vector3.ZERO
	ship.time_since_hit = 6

func action(server: Sector, client: Sector, verb: String, offer: String = "") -> void:
	client.session.combat.request_contract(verb, offer)
	await settle(0.08)
	await replicate(server)

func kill(server: Sector, kind: String, clients: Array[Sector]) -> void:
	var alien: Alien
	for candidate: Alien in server.aliens.values():
		if candidate.kind == kind:
			alien = candidate
			break
	assert(alien != null)
	alien.reset_encounter()
	for client in clients:
		var ship := server.session.ships[client.multiplayer.get_unique_id()]
		ship.position = alien.home_position + Vector3(0, 0, 80)
		alien.take_damage(1, ship)
	alien.take_damage(alien.max_hull + alien.max_shield + 1.0, server.session.ships[clients.back().multiplayer.get_unique_id()])
	alien.take_damage(alien.max_hull + alien.max_shield + 1.0, server.session.ships[clients.back().multiplayer.get_unique_id()])
	await replicate(server)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--contract-save-failure="):
			await failed_transaction(argument.get_slice("=", 1))
			return
	var server := make_sector("ContractServer", true, CONTRACT_PORT)
	var pilot := make_sector("ContractPilot")
	var partner := make_sector("ContractPartner")
	var spectator := make_sector("ContractSpectator")
	await connect_pilot(pilot, 0)
	await connect_pilot(partner, 1)
	await connect_pilot(spectator, 2)
	check(server.session.ships.size() == 3, "Three provisioned pilots authenticate")
	if server.session.ships.size() != 3:
		finish()
		return
	await replicate(server)
	var combat := server.session.combat
	var id := pilot.multiplayer.get_unique_id()
	var remote := server.session.ships[id]
	check(pilot.active_contracts.is_empty(), "Legacy wallets start without hunts")
	await kill(server, "Scout", [pilot])
	station(server, pilot)
	remote.position = Vector3(0, 0, 400)
	await action(server, pilot, "accept", "scout")
	check(pilot.active_contracts.is_empty(), "Acceptance outside station radius is rejected")
	station(server, pilot)
	remote.velocity = Vector3(9, 0, 0)
	await action(server, pilot, "accept", "scout")
	check(pilot.active_contracts.is_empty(), "Acceptance while moving too fast is rejected")
	station(server, pilot)
	remote.time_since_hit = 0
	await action(server, pilot, "accept", "scout")
	check(pilot.active_contracts.is_empty(), "Acceptance during damage cooldown is rejected")
	station(server, pilot)
	await action(server, pilot, "accept", "invented")
	check(pilot.active_contracts.is_empty(), "Unknown offers are rejected")
	for kind: String in HuntingContracts.OFFERS:
		await action(server, pilot, "accept", kind)
	check(pilot.active_contracts.size() == 3, "All three hunts can run concurrently")
	check(pilot.active_contracts["scout"]["progress"] == 0, "Kills before acceptance do not count")
	var first := pilot.active_contracts.duplicate(true)
	await action(server, pilot, "accept", "scout")
	await action(server, pilot, "claim", "scout")
	check(pilot.active_contracts == first, "Duplicate acceptance and manual claims do nothing")
	var packet: Dictionary = {id: combat.pack_player(id)}
	packet[id].merge({"position": Vector3.ZERO, "rotation": Vector3.ZERO, "velocity": Vector3.ZERO, "energy": 100.0})
	packet[id]["systems"][3] = 165.0
	packet[id]["systems"][4] = 1.0
	check(var_to_bytes([packet, {}, 1]).size() < 1300, "One player with all hunts fits the snapshot datagram budget")
	packet[id]["docked"] = true
	check(var_to_bytes([packet, {}, 1]).size() < 1300 and not packet[id].has("spawn"), "Docked quests fit the packet budget without a server-only spawn origin")
	for client in [partner, spectator]:
		station(server, client)
		await action(server, client, "accept", "scout")
	await kill(server, "Sentinel", [pilot, partner])
	check(pilot.active_contracts["sentinel"]["progress"] == 1 and pilot.active_contracts["scout"]["progress"] == 0, "Only the matching hunt progresses")
	var before := pilot.credits + partner.credits
	await kill(server, "Scout", [pilot, partner])
	check(pilot.active_contracts["scout"]["progress"] == 1 and partner.active_contracts["scout"]["progress"] == 1, "Every contributor receives full matching progress")
	check(pilot.credits + partner.credits == before + 300, "Kill credit splitting remains independent")
	check(spectator.active_contracts["scout"]["progress"] == 0, "Noncontributors receive no progress")
	var path := server.session.store.path
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for contract: Dictionary in disk["pilots"]["pilot0"]["contracts"].values():
		for field in ["progress", "required", "reward"]:
			contract[field] = int(contract[field])
	check(disk["pilots"]["pilot0"]["contracts"] == pilot.active_contracts and disk["pilots"]["pilot0"]["credits"] == pilot.credits, "All progress and kill credits commit together")
	var saved := pilot.active_contracts.duplicate(true)
	pilot.session.disconnect_session("Reconnect")
	await settle(0.2)
	await connect_pilot(pilot, 0)
	await replicate(server)
	check(pilot.active_contracts == saved, "Reconnect restores all runs and progress")
	id = pilot.multiplayer.get_unique_id()
	remote = server.session.ships[id]
	var scout: Alien = server.aliens[1]
	scout.reset_encounter()
	remote.position = scout.home_position + Vector3(0, 0, 80)
	scout.take_damage(1, remote)
	remote.take_damage(remote.max_hull + remote.max_shield + 1.0, server.aliens[0])
	await replicate(server)
	check(not pilot.player.alive and pilot.active_contracts == saved, "Death preserves all hunts")
	await action(server, pilot, "abandon", "scout")
	check(pilot.active_contracts == saved, "Dead pilots cannot abandon")
	scout.take_damage(scout.max_hull + scout.max_shield + 1.0, server.session.ships[partner.multiplayer.get_unique_id()])
	await replicate(server)
	check(pilot.active_contracts["scout"]["progress"] == 2, "Contributors awaiting rescue receive progress")
	combat.tick(3.1)
	await replicate(server)
	before = pilot.credits
	await kill(server, "Scout", [pilot, partner])
	check(not pilot.active_contracts.has("scout") and pilot.credits == before + 150 + 900, "Final kill pays full hunt reward automatically outside the station")
	check(pilot.active_contracts.size() == 2 and pilot.active_contracts["sentinel"]["progress"] == 1, "Payment leaves other hunts intact")
	before = pilot.credits
	await kill(server, "Scout", [pilot])
	check(pilot.credits == before + 300, "Subsequent kills cannot pay the completed run again")
	scout.reset_encounter()
	var departing := server.session.ships[spectator.multiplayer.get_unique_id()]
	departing.position = scout.home_position + Vector3(0, 0, 80)
	scout.take_damage(1, departing)
	spectator.session.disconnect_session("Leave before kill")
	await settle(0.2)
	scout.take_damage(scout.max_hull + scout.max_shield + 1.0, remote)
	await connect_pilot(spectator, 2)
	await replicate(server)
	check(spectator.active_contracts["scout"]["progress"] == 0, "Disconnecting before the kill removes contribution eligibility")
	var paid_balance := pilot.credits
	var remaining := pilot.active_contracts.duplicate(true)
	server.session.disconnect_session("Restart")
	await settle(0.3)
	check(server.session.host(test_port(CONTRACT_PORT)) == OK, "Server reopens ledger")
	await connect_pilot(pilot, 0)
	await replicate(server)
	check(pilot.credits == paid_balance and pilot.active_contracts == remaining, "Restart retains payout, cleared run and other hunts atomically")
	id = pilot.multiplayer.get_unique_id()
	station(server, pilot)
	await action(server, pilot, "accept", "scout")
	check(pilot.active_contracts["scout"]["run"] != first["scout"]["run"], "Repeated hunt gets a fresh run identity")
	pilot.session.combat.contract_request.rpc_id(1, 0, "abandon", "scout", first["scout"]["run"])
	pilot.session.combat.contract_request.rpc_id(1, 0, "claim", "scout", first["scout"]["run"])
	await settle(0.1)
	await replicate(server)
	check(pilot.active_contracts.size() == 3 and pilot.credits == paid_balance, "Stale requests cannot alter repeated hunts or pay rewards")
	await action(server, pilot, "abandon", "scout")
	check(pilot.active_contracts == remaining and pilot.credits == paid_balance, "Abandonment removes only the chosen hunt without a charge")
	await kill(server, "Heavy", [pilot])
	check(not pilot.active_contracts.has("heavy") and pilot.credits == paid_balance + 10000 + 30000, "Heavy completion pays instantly without manual claim")
	server.session.save_balances({id: PilotStore.MAX_CREDITS})
	combat.records[id]["credits"] = PilotStore.MAX_CREDITS
	await kill(server, "Sentinel", [pilot])
	check(HuntingContracts.ready(pilot.active_contracts["sentinel"]) and pilot.credits == PilotStore.MAX_CREDITS, "Full wallet retains the whole completed reward")
	server.session.disconnect_session("Pending restart")
	await settle(0.3)
	server.session.host(test_port(CONTRACT_PORT))
	await connect_pilot(pilot, 0)
	await replicate(server)
	id = pilot.multiplayer.get_unique_id()
	check(HuntingContracts.ready(pilot.active_contracts["sentinel"]) and pilot.credits == PilotStore.MAX_CREDITS, "Pending rewards survive restart without premature payment")
	server.session.save_balances({id: PilotStore.MAX_CREDITS - 4500})
	combat.records[id]["credits"] = PilotStore.MAX_CREDITS - 4500
	combat.tick(0.01)
	await replicate(server)
	check(pilot.active_contracts.is_empty() and pilot.credits == PilotStore.MAX_CREDITS, "Pending reward pays automatically when there is room")
	combat.tick(0.01)
	check(combat.records[id]["credits"] == PilotStore.MAX_CREDITS, "Repeated settlement cannot pay twice")
	var output: Array = []
	for operation in ["progress", "completion", "pending"]:
		output.clear()
		var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/hunting_contracts_test.gd", "--", "--contract-save-failure=" + operation], output, true)
		check(code == 1 and str(output).contains("CONTRACT_FAILURE_VERIFIED"), "Failed %s save publishes neither progress nor reward" % operation)
	server.session.disconnect_session("Schema validation")
	await settle(0.2)
	var ledger: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var legacy := HuntingContracts.accept("scout")
	legacy["reward"] = 90
	legacy["progress"] = 2
	ledger["pilots"]["pilot0"].erase("contracts")
	ledger["pilots"]["pilot0"]["contract"] = legacy
	write_ledger(path, ledger)
	var store := PilotStore.new()
	check(store.open(path.get_base_dir()) and store.pilots["pilot0"]["contracts"] == {"scout": legacy}, "Legacy single hunt migrates without losing run or progress")
	store.close()
	legacy["progress"] = 3
	ledger["pilots"]["pilot0"]["credits"] = 100
	write_ledger(path, ledger)
	server.session.host(test_port(CONTRACT_PORT))
	await connect_pilot(pilot, 0)
	combat.tick(0.01)
	await replicate(server)
	check(pilot.active_contracts.is_empty() and pilot.credits == 190, "Legacy completed hunts pay automatically on connection")
	server.session.disconnect_session("Legacy paid")
	await settle(0.2)
	ledger["pilots"]["pilot0"].erase("contract")
	var malformed := legacy.duplicate()
	malformed["progress"] = 4
	for invalid in [null, {"scout": {}}, {"heavy": legacy}, {"invented": legacy}, {"scout": malformed}]:
		ledger["pilots"]["pilot0"]["contracts"] = invalid
		write_ledger(path, ledger)
		var original := FileAccess.get_file_as_string(path)
		store = PilotStore.new()
		check(not store.open(path.get_base_dir()) and FileAccess.get_file_as_string(path) == original, "Malformed collections fail closed without changing saves")
		store.close()
	finish()

func write_ledger(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func failed_transaction(operation: String) -> void:
	var server := make_sector("FailingContractServer", true, CONTRACT_PORT + 2)
	var pilot := make_sector("FailingContractPilot")
	pilot.session.credential_id = "pilot0"
	pilot.session.credential_token = test_token(0)
	pilot.session.join("127.0.0.1", test_port(CONTRACT_PORT + 2))
	await settle(0.5)
	if server.session.ships.size() != 1:
		quit(2)
		return
	var id := pilot.multiplayer.get_unique_id()
	var combat := server.session.combat
	station(server, pilot)
	combat.contract_action(id, 0, "accept", "scout" if operation == "progress" else "heavy", "")
	var alien: Alien = server.aliens[1 if operation == "progress" else 4]
	server.session.ships[id].position = alien.home_position + Vector3(0, 0, 80)
	if operation == "pending":
		server.session.save_balances({id: PilotStore.MAX_CREDITS})
		combat.records[id]["credits"] = PilotStore.MAX_CREDITS
		alien.take_damage(alien.max_hull + alien.max_shield + 1.0, server.session.ships[id])
		server.session.save_balances({id: PilotStore.MAX_CREDITS - 45000})
		combat.records[id]["credits"] = PilotStore.MAX_CREDITS - 45000
	var original := FileAccess.get_file_as_string(server.session.store.path)
	var record: Dictionary = combat.records[id].duplicate(true)
	DirAccess.make_dir_absolute(server.session.store.path + ".bak.tmp")
	if operation == "pending":
		combat.pay_pending_contracts(id)
	else:
		alien.take_damage(alien.max_hull + alien.max_shield + 1.0, server.session.ships[id])
	if server.session.store.failed and combat.records[id] == record and FileAccess.get_file_as_string(server.session.store.path) == original:
		print("CONTRACT_FAILURE_VERIFIED")
	else:
		quit(2)
