extends "res://tests/network_test.gd"
## Pilot progress reaches only its owner over real authenticated ENet peers.


class RecordingCombat extends SessionCombat:
	## Every player state dictionary this peer applied, keyed by the ship's peer ID.
	var received: Dictionary = {}

	func apply_player(id: int, data: Dictionary, sequence: int = -1) -> bool:
		if not received.has(id):
			received[id] = []
		received[id].append(data.duplicate(true))
		return super(id, data, sequence)


func record(sector: Sector) -> RecordingCombat:
	var spy := RecordingCombat.new()
	spy.name = "Combat"
	spy.session = sector.session
	var original := sector.session.combat
	sector.session.remove_child(original)
	original.free()
	sector.session.add_child(spy)
	sector.session.combat = spy
	return spy


func replicate(host: Sector) -> void:
	# Unreliable snapshots may drop; resend until every peer applied the latest
	# state of each ship it is allowed to see.
	var expected := host.session.snapshot_sequence + 1
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		host.session.send_snapshot()
		await settle(0.05)
		var complete := true
		for viewport in worlds:
			var peer := viewport.get_child(0) as Sector
			if peer == host or not peer.session.active:
				continue
			for id: int in host.session.ships:
				var ship := host.session.ships[id]
				if id == peer.multiplayer.get_unique_id() or not ship.get_meta("docked", false) and ship.map_id == peer.map_id:
					complete = complete and peer.session.player_sequences.get(id, -1) >= expected
		if complete:
			return
	check(false, "Snapshots converge")


func private_free(states: Array) -> bool:
	return states.all(func(state: Dictionary) -> bool:
		return SessionCombat.PRIVATE_FIELDS.all(func(field: String) -> bool: return not state.has(field)))


func run() -> void:
	var server := make_sector("PrivateServer", true, 24851)
	var owner := make_sector("PrivateOwner")
	var viewer := make_sector("PrivateViewer")
	var owner_log := record(owner)
	var viewer_log := record(viewer)
	for index in range(2):
		var client: Sector = [owner, viewer][index]
		client.client_only = true
		client.session.credential_id = "pilot%d" % index
		client.session.credential_token = test_token(index)
		client.session.join("127.0.0.1", test_port(24851))
	await settle(0.6)
	check(server.session.ships.size() == 2, "Two authenticated pilots connect")
	if server.session.ships.size() != 2:
		finish()
		return
	await replicate(server)
	for client in [owner, viewer]:
		client.session.launch()
	await settle()
	await replicate(server)
	check(not owner.preflight and not viewer.preflight, "Both pilots launch into flight")
	var id := owner.multiplayer.get_unique_id()
	var other := viewer.multiplayer.get_unique_id()
	var records := server.session.combat.records
	records[id].merge({"credits": 7777, "kills": 4, "stage": 3, "contracts": {"scout": HuntingContracts.accept("scout"), "heavy": HuntingContracts.accept("heavy")}}, true)
	records[other].merge({"credits": 55, "kills": 1, "contracts": {}}, true)
	var ship := server.session.ships[id]
	ship.position = Vector3(10, 250, 0)
	server.session.ships[other].position = Vector3(-10, 250, 0)
	ship.hull = ship.max_hull * 0.5
	ship.shield = ship.max_shield * 0.25
	ship.repair_seconds = 165.0
	ship.robot_repairing = true
	await replicate(server)

	check(viewer.session.ships.has(id) and viewer_log.received.get(id, []).size() > 0, "Viewer receives the other pilot's snapshots")
	check(private_free(viewer_log.received.get(id, [])), "Viewer never receives another pilot's credits, kills or contracts")
	var remote := viewer.session.ships[id]
	check(is_equal_approx(remote.hull, ship.hull) and is_equal_approx(remote.shield, ship.shield), "Remote hull and shield bars follow the server")
	check(remote.laser_damage == ship.laser_damage and remote.max_hull == ship.max_hull and remote.ship_model == ship.ship_model, "Remote fitting stats and hull model still replicate")
	check(remote.robot_repairing and remote.repair_seconds == 165.0, "Remote repair-bot state still replicates")
	check(viewer.session.goals[id]["position"].is_equal_approx(ship.position), "Remote ship position still replicates")
	check(remote.visible, "Remote ship stays visible")
	check(viewer.credits == 55 and viewer.kills == 1 and viewer.active_contracts.is_empty(), "Viewer keeps its own progress, untouched by others' packets")
	check(owner_log.received.get(id, []).all(func(state: Dictionary) -> bool: return state.has("credits") and state.has("contracts")), "Owner snapshots carry the owner's private progress")
	check(owner.credits == 7777 and owner.kills == 4 and owner.active_contracts.has("scout") and owner.active_contracts.has("heavy"), "Owner receives its own credits, kills and contracts")
	check(private_free(owner_log.received.get(other, [])), "The owner equally receives no private data of the viewer")

	# Reliable map transfer acknowledgements follow the same split.
	var before: int = viewer_log.received[id].size()
	ship.position = SectorMaps.gate_position(0, 1)
	await replicate(server)
	owner.set_paused(false)
	owner.session.request_jump()
	await settle(0.3)
	check(ship.map_id == 1 and owner.map_id == 1, "Owner jumps to the next map")
	check(viewer_log.received[id].size() > before and viewer.session.ships[id].map_id == 1, "Viewer learns of the map change")
	check(private_free(viewer_log.received[id].slice(before)), "Map change acknowledgements omit private progress for viewers")
	check(owner.credits == 7777 and owner.active_contracts.size() == 2, "Owner retains its progress after the jump")

	# Docking sends the owner its full state and other peers only public state.
	owner.session.quit_to_menu()
	await settle(0.3)
	check(ship.get_meta("docked", false) and owner.preflight, "Owner docks from flight")
	check(not viewer.session.ships.has(id), "Viewer removes the docked pilot")
	check(owner.credits == 7777 and owner.kills == 4 and owner.active_contracts.size() == 2, "Docking preserves the owner's progress")
	await replicate(server)
	check(private_free(viewer_log.received.get(id, [])), "Viewer still has no private data of the docked pilot")
	finish()
