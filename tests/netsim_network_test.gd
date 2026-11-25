extends "res://tests/network_test.gd"
## An authenticated client joins a dedicated server through the network
## simulator at moderate latency and loss, flies, and disconnects cleanly.


func run() -> void:
	var server := make_sector("SimServer", true, 24901)
	var client := make_sector("SimClient")
	client.session.credential_id = "pilot0"
	client.session.credential_token = test_token(0)
	server.set_physics_process(true)
	client.set_physics_process(true)
	await settle()
	client.session.use_net_simulator = true
	client.session.net_simulator.set_seed(7)
	client.session.net_simulator.set_round_trip(80.0, 10.0, 5.0, 5.0)
	check(client.session.join("127.0.0.1", test_port(24901)) == OK, "Client joins through the simulator")
	check(client.session.net_simulator.is_running(), "Joining starts the relay")
	check(client.session.attempted_address == "127.0.0.1" and client.session.attempted_port == test_port(24901), "The session keeps the real server address")
	var deadline := Time.get_ticks_msec() + 10000
	while not client.session.received_snapshot and Time.get_ticks_msec() < deadline:
		await process_frame
	check(client.session.active and client.session.received_snapshot, "Authentication and snapshots succeed through the relay")
	var id := client.multiplayer.get_unique_id()
	check(server.session.ships.has(id), "The server spawns the relayed pilot")
	Input.action_press("forward")
	await settle(3.0)
	Input.action_release("forward")
	var stats: Dictionary = client.session.net_simulator.stats()
	var net := client.session.net_stats
	print("Relay stats: ", stats)
	print("Client stats: rtt %.1f ms, up %.0f B/s, down %.0f B/s, snapshots %d, jitter %s, max error %.2f m, commands %d sent / %d accepted" % [
		net.rtt_ms, net.up_bytes_per_second, net.down_bytes_per_second, net.snapshots_received,
		net.snapshot_jitter(), net.max_error_m, net.commands_sent, server.session.net_stats.commands_received.get(id, 0)])
	check(stats["up"]["forwarded_packets"] > 30 and stats["down"]["forwarded_packets"] > 30, "Traffic flows both ways through the relay")
	check(stats["up"]["dropped_packets"] + stats["down"]["dropped_packets"] > 0, "The relay drops datagrams")
	check(stats["up"]["duplicated_packets"] + stats["down"]["duplicated_packets"] > 0, "The relay duplicates datagrams")
	check(net.snapshots_received > 30, "Snapshots keep arriving despite loss")
	check(net.rtt_ms >= 60.0 and net.rtt_ms < 400.0, "ENet measures the added round trip")
	check(net.up_bytes_per_second > 0.0 and net.down_bytes_per_second > net.up_bytes_per_second, "Client traffic rates are sampled")
	check(net.corrections > 0 and net.has_server_state, "Reconciliation against server state is measured")
	check(server.session.ships[id].position.z < Sector.SPAWN_POSITION.z, "Relayed flight commands move the pilot on the server")
	var accepted: int = server.session.net_stats.commands_received.get(id, 0)
	check(accepted > 0 and accepted <= net.commands_sent, "The server counts accepted flight commands")
	# The F8 overlay edits the running relay and shows the server ghost.
	var toggle := InputEventAction.new()
	toggle.action = "netcode"
	toggle.pressed = true
	client._unhandled_input(toggle)
	check(client.show_netcode, "F8 toggles the netcode overlay")
	await process_frame
	await process_frame
	var overlay := client.hud.netcode
	check(overlay.visible and overlay.size == NetcodeOverlay.SIZE, "The overlay opens while connected")
	check(is_equal_approx(overlay.sliders["latency_ms"].value, 80.0) and is_equal_approx(overlay.sliders["loss_percent"].value, 5.0), "Sliders show the relay's round-trip conditions")
	overlay.sliders["latency_ms"].value = 200.0
	check(is_equal_approx(client.session.net_simulator.conditions(NetSimulator.UP)["latency_ms"], 100.0) and client.session.net_simulator.symmetric(), "Round-trip sliders change both directions live")
	overlay.direction.select(2)
	overlay.sync_sliders()
	overlay.sliders["loss_percent"].value = 10.0
	check(client.session.net_simulator.conditions(NetSimulator.DOWN)["loss_percent"] == 10.0 and client.session.net_simulator.conditions(NetSimulator.UP)["loss_percent"] == 5.0, "Per-direction sliders change one direction")
	check(not overlay.note.visible, "No reconnect note while the relay is in the path")
	await process_frame
	check(is_instance_valid(overlay.ghost) and overlay.ghost.visible and overlay.ghost.position.is_equal_approx(net.server_position), "The server ghost marks the authoritative position")
	overlay.ghost_toggle.button_pressed = false
	await process_frame
	check(not overlay.ghost.visible, "The ghost can be hidden")
	client.session.net_simulator.set_round_trip(80.0, 10.0, 5.0, 5.0)
	# The relay flushes ENet's disconnect notice before it stops.
	client.session.disconnect_session("Test leave")
	check(not client.session.net_simulator.is_running(), "Disconnecting stops the relay")
	deadline = Time.get_ticks_msec() + 3000
	while server.session.ships.has(id) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not server.session.ships.has(id), "The server sees the relayed pilot leave promptly")
	client.session.use_net_simulator = false
	check(client.session.join("127.0.0.1", test_port(24901)) == OK and not client.session.net_simulator.is_running(), "Normal joins bypass the relay")
	deadline = Time.get_ticks_msec() + 5000
	while not client.session.active and Time.get_ticks_msec() < deadline:
		await process_frame
	check(client.session.active, "The client reconnects directly")
	await process_frame
	check(overlay.note.visible, "The overlay asks to reconnect when the relay is not in the path")
	finish()
