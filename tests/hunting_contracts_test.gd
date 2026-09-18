extends "res://tests/dedicated_server_test.gd"
## Contracts use authenticated RPCs, actual alien deaths and the production ledger.

const CONTRACT_PORT := 24689


func connect_pilot(client: Sector, index: int) -> void:
	client.session.credential_id = "pilot%d" % index
	client.session.credential_token = test_token(index)
	client.session.join("127.0.0.1", CONTRACT_PORT)
	await settle(0.4)


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
	alien.take_damage(9999, server.session.ships[clients.back().multiplayer.get_unique_id()])
	# A second lethal hit must not emit another rewarded kill.
	alien.take_damage(9999, server.session.ships[clients.back().multiplayer.get_unique_id()])
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
	check(pilot.active_contract.is_empty(), "Legacy wallets start without a contract")
	await kill(server, "Scout", [pilot])
	station(server, pilot)
	remote.position = Vector3(0, 0, 400)
	await action(server, pilot, "accept", "scout")
	check(pilot.active_contract.is_empty(), "Acceptance outside station radius is rejected")
	station(server, pilot)
	remote.velocity = Vector3(9, 0, 0)
	await action(server, pilot, "accept", "scout")
	check(pilot.active_contract.is_empty(), "Acceptance while moving too fast is rejected")
	station(server, pilot)
	remote.time_since_hit = 0
	await action(server, pilot, "accept", "scout")
	check(pilot.active_contract.is_empty(), "Acceptance during damage cooldown is rejected")
	station(server, pilot)
	await action(server, pilot, "accept", "invented")
	check(pilot.active_contract.is_empty(), "Unknown offers cannot create a contract")
	await action(server, pilot, "accept", "scout")
	check(pilot.active_contract.get("progress") == 0, "Kills before acceptance are not counted")
	var first := pilot.active_contract.duplicate()
	await action(server, pilot, "accept", "heavy")
	await action(server, pilot, "claim")
	check(pilot.active_contract == first, "Only one active contract; incomplete claims do nothing")
	for client in [partner, spectator]:
		station(server, client)
		await action(server, client, "accept", "scout")
	for peer in [id, partner.multiplayer.get_unique_id()]:
		var packet := {peer: combat.pack_player(peer)}
		packet[peer].merge({"position": Vector3.ZERO, "rotation": Vector3.ZERO, "velocity": Vector3.ZERO, "energy": 100.0})
		check(var_to_bytes([packet, {}, 1]).size() < 1200, "Active-contract player record leaves room for RPC and ENet headers")
	await kill(server, "Sentinel", [pilot, partner])
	check(pilot.active_contract["progress"] == 0 and partner.active_contract["progress"] == 0, "Nonmatching kills still award credits but no contract progress")
	var credits_before := pilot.credits + partner.credits
	await kill(server, "Scout", [pilot, partner])
	check(pilot.active_contract["progress"] == 1 and partner.active_contract["progress"] == 1, "Each eligible contributor gets a full kill regardless of final hit")
	check(pilot.credits + partner.credits == credits_before + 30, "Credit splitting stays separate from full progress")
	check(spectator.active_contract["progress"] == 0, "A matching contract alone does not grant contribution eligibility")
	var path := server.session.store.path
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for field in ["progress", "required", "reward"]:
		disk["pilots"]["pilot0"]["contract"][field] = int(disk["pilots"]["pilot0"]["contract"][field])
	check(disk["pilots"]["pilot0"]["contract"] == pilot.active_contract and disk["pilots"]["pilot0"]["credits"] == pilot.credits, "Progress and its kill credits share one saved ledger")
	var saved := pilot.active_contract.duplicate()
	pilot.session.disconnect_session("Contract reconnect")
	await settle(0.2)
	await connect_pilot(pilot, 0)
	await replicate(server)
	check(pilot.active_contract == saved, "Reconnect restores partial progress and run identity")
	id = pilot.multiplayer.get_unique_id()
	remote = server.session.ships[id]
	var scout: Alien
	for alien: Alien in server.aliens.values():
		if alien.kind == "Scout":
			scout = alien
			break
	scout.reset_encounter()
	remote.position = scout.home_position + Vector3(0, 0, 80)
	scout.take_damage(1, remote)
	remote.take_damage(9999, server.aliens.values()[0])
	await replicate(server)
	check(not pilot.player.alive and pilot.active_contract == saved, "Death preserves the accepted contract and earned progress")
	await action(server, pilot, "abandon")
	check(pilot.active_contract == saved, "Dead pilots cannot perform station actions")
	# Connected contributors awaiting rescue remain eligible under the encounter rules.
	scout.take_damage(9999, server.session.ships[partner.multiplayer.get_unique_id()])
	await replicate(server)
	check(pilot.active_contract["progress"] == 2, "Eligible pilot awaiting rescue receives matching kill progress")
	combat.tick(3.1)
	await replicate(server)
	await kill(server, "Scout", [pilot, partner])
	check(HuntingContracts.ready(pilot.active_contract), "Required count marks contract ready without claiming")
	await kill(server, "Scout", [pilot])
	check(pilot.active_contract["progress"] == 3, "Completed progress is capped until claim or abandonment")
	scout.reset_encounter()
	var departing := server.session.ships[spectator.multiplayer.get_unique_id()]
	departing.position = scout.home_position + Vector3(0, 0, 80)
	scout.take_damage(1, departing)
	spectator.session.disconnect_session("Leave before kill")
	await settle(0.2)
	scout.take_damage(9999, remote)
	await connect_pilot(spectator, 2)
	await replicate(server)
	check(spectator.active_contract["progress"] == 0, "Disconnecting before death loses encounter eligibility and earns no progress")
	var completed := pilot.active_contract.duplicate()
	server.session.disconnect_session("Contract restart")
	await settle(0.3)
	check(server.session.host(CONTRACT_PORT) == OK, "Server reopens the saved ledger")
	await connect_pilot(pilot, 0)
	await replicate(server)
	check(pilot.active_contract == completed, "Completed but unclaimed contract survives server restart")
	station(server, pilot)
	id = pilot.multiplayer.get_unique_id()
	remote = server.session.ships[id]
	remote.position = Vector3(0, 0, 400)
	await action(server, pilot, "claim")
	check(pilot.active_contract == completed, "Completed reward cannot be claimed remotely")
	station(server, pilot)
	var before_claim := pilot.credits
	# Both requests carry the same accepted run, before a snapshot can clear the client UI.
	pilot.session.combat.request_contract("claim")
	pilot.session.combat.request_contract("claim")
	await settle(0.1)
	await replicate(server)
	check(pilot.credits == before_claim + 90 and pilot.active_contract.is_empty(), "Repeated claims pay exactly once and clear the contract")
	await action(server, pilot, "accept", "scout")
	check(pilot.active_contract["progress"] == 0 and pilot.active_contract["run"] != completed["run"], "Same offer can be repeated with a fresh run")
	pilot.session.combat.contract_request.rpc_id(1, 0, "abandon", "", completed["run"])
	pilot.session.combat.contract_request.rpc_id(1, 0, "claim", "", completed["run"])
	await settle(0.1)
	await replicate(server)
	check(not pilot.active_contract.is_empty() and pilot.credits == before_claim + 90, "Stale requests cannot abandon a new run or pay an old reward")
	await kill(server, "Scout", [pilot])
	station(server, pilot)
	var before_abandon := pilot.credits
	await action(server, pilot, "abandon")
	check(pilot.active_contract.is_empty() and pilot.credits == before_abandon, "Abandonment clears earned progress without a charge")
	await action(server, pilot, "accept", "heavy")
	await kill(server, "Heavy", [pilot])
	station(server, pilot)
	var before_heavy := pilot.credits
	await action(server, pilot, "claim")
	check(pilot.active_contract.is_empty() and pilot.credits == before_heavy + 200, "Heavy contract uses its fixed objective and reward")
	server.session.disconnect_session("Verify claimed restart")
	await settle(0.3)
	server.session.host(CONTRACT_PORT)
	await connect_pilot(pilot, 0)
	await replicate(server)
	check(pilot.active_contract.is_empty() and pilot.credits == before_heavy + 200, "Claim payout and cleared run survive restart together")
	station(server, pilot)
	await action(server, pilot, "accept", "sentinel")
	await kill(server, "Sentinel", [pilot])
	await kill(server, "Sentinel", [pilot])
	station(server, pilot)
	check(HuntingContracts.ready(pilot.active_contract), "Sentinel contract completes after two matching kills")
	var capped_id := pilot.multiplayer.get_unique_id()
	server.session.save_balances({capped_id: PilotStore.MAX_CREDITS})
	combat.records[capped_id]["credits"] = PilotStore.MAX_CREDITS
	await replicate(server)
	await action(server, pilot, "claim")
	check(HuntingContracts.ready(pilot.active_contract) and pilot.credits == PilotStore.MAX_CREDITS, "Wallet cap retains the whole pending reward instead of silently losing it")
	await action(server, pilot, "abandon")
	check(pilot.active_contract.is_empty(), "Completed contracts can also be abandoned")
	var output: Array = []
	for operation in ["kill", "claim"]:
		output.clear()
		var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/hunting_contracts_test.gd", "--", "--contract-save-failure=" + operation], output, true)
		check(code == 1 and str(output).contains("CONTRACT_FAILURE_VERIFIED"), "Failed %s save exits without publishing credits or contract changes" % operation)
	server.session.disconnect_session("Schema validation")
	await settle(0.2)
	var ledger: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var contract := HuntingContracts.accept("scout")
	for invalid in [{"type": "scout"}, null, {"run": contract["run"], "type": "scout", "required": 3, "reward": 90, "progress": 4}]:
		ledger["pilots"]["pilot0"]["contract"] = invalid
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(ledger))
		file.close()
		var original := FileAccess.get_file_as_string(path)
		var store := PilotStore.new()
		check(not store.open(path.get_base_dir()) and FileAccess.get_file_as_string(path) == original, "Malformed contract fails closed without modifying the ledger")
		store.close()
	finish()


func failed_transaction(operation: String) -> void:
	var server := make_sector("FailingContractServer", true, CONTRACT_PORT + 2)
	var pilot := make_sector("FailingContractPilot")
	pilot.session.credential_id = "pilot0"
	pilot.session.credential_token = test_token(0)
	pilot.session.join("127.0.0.1", CONTRACT_PORT + 2)
	await settle(0.5)
	if server.session.ships.size() != 1:
		quit(2)
		return
	var id := pilot.multiplayer.get_unique_id()
	var combat := server.session.combat
	station(server, pilot)
	combat.contract_action(id, 0, "accept", "heavy", "")
	var heavy: Alien
	for alien: Alien in server.aliens.values():
		if alien.kind == "Heavy":
			heavy = alien
			break
	server.session.ships[id].position = heavy.home_position + Vector3(0, 0, 80)
	if operation == "claim":
		heavy.take_damage(9999, server.session.ships[id])
		station(server, pilot)
	var original := FileAccess.get_file_as_string(server.session.store.path)
	var record: Dictionary = combat.records[id].duplicate(true)
	DirAccess.make_dir_absolute(server.session.store.path + ".bak.tmp")
	if operation == "claim":
		combat.contract_action(id, 0, "claim", "", record["contract"]["run"])
	else:
		heavy.take_damage(9999, server.session.ships[id])
	if server.session.store.failed and combat.records[id] == record and FileAccess.get_file_as_string(server.session.store.path) == original:
		print("CONTRACT_FAILURE_VERIFIED")
	else:
		quit(2)
